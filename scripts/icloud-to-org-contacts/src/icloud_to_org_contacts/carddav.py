"""Small CardDAV client for reading address book vCards."""

import base64
from dataclasses import dataclass
from urllib.parse import urljoin

import requests
from defusedxml import ElementTree as ET


DAV_NS = "DAV:"
CARDDAV_NS = "urn:ietf:params:xml:ns:carddav"
CALENDAR_SERVER_NS = "http://calendarserver.org/ns/"


class CardDAVError(RuntimeError):
    """Raised when CardDAV discovery or fetch fails."""


@dataclass(frozen=True)
class DAVAddressBook:
    """A CardDAV address book collection."""

    url: str
    display_name: str = ""
    ctag: str = ""


@dataclass(frozen=True)
class DAVCard:
    """A vCard object fetched from CardDAV."""

    url: str
    etag: str
    data: str


@dataclass(frozen=True)
class DAVResponse:
    """Parsed WebDAV multistatus response entry."""

    href: str
    status: int
    ok: bool
    props: dict


def _local_name(tag):
    if "}" in tag:
        return tag.rsplit("}", 1)[1]
    return tag


def _children(element, name):
    return [child for child in list(element) if _local_name(child.tag) == name]


def _first_child(element, name):
    matches = _children(element, name)
    return matches[0] if matches else None


def _first_text(element, name, default=""):
    child = _first_child(element, name)
    if child is None:
        return default
    return "".join(child.itertext()).strip()


def _status_code(status_text, default=0):
    parts = status_text.split()
    for part in parts:
        if part.isdigit():
            return int(part)
    return default


def _prop_value(prop):
    href = _first_text(prop, "href")
    if href:
        return href
    if _children(prop, "addressbook"):
        return [_local_name(child.tag) for child in list(prop)]
    if _children(prop, "collection"):
        return [_local_name(child.tag) for child in list(prop)]
    return "".join(prop.itertext()).strip()


def parse_multistatus(xml_text):
    """Parse a WebDAV multistatus XML document."""
    root = ET.fromstring(xml_text)
    responses = []
    for response_el in root.iter():
        if _local_name(response_el.tag) != "response":
            continue
        href = _first_text(response_el, "href")
        props = {}
        status = 0
        ok = False
        for propstat in _children(response_el, "propstat"):
            propstat_status = _status_code(_first_text(propstat, "status"))
            if propstat_status:
                status = propstat_status
            if not (200 <= propstat_status < 300):
                continue
            ok = True
            prop_el = _first_child(propstat, "prop")
            if prop_el is None:
                continue
            for prop in list(prop_el):
                props[_local_name(prop.tag)] = _prop_value(prop)
        response_status = _status_code(_first_text(response_el, "status"))
        if response_status:
            status = response_status
            ok = 200 <= response_status < 300
        responses.append(DAVResponse(href=href, status=status, ok=ok, props=props))
    return responses


class CardDAVClient:
    """Read-only CardDAV client for contacts."""

    def __init__(self, server_url, username, password, *, session=None):
        self.server_url = server_url.rstrip("/") + "/"
        self.username = username
        self.password = password
        self.session = session or requests.Session()

    def _headers(self, *, depth=None):
        token = base64.b64encode(
            f"{self.username}:{self.password}".encode("utf-8")
        ).decode("ascii")
        headers = {
            "Authorization": f"Basic {token}",
            "Content-Type": "text/xml;charset=UTF-8",
        }
        if depth is not None:
            headers["Depth"] = depth
        return headers

    def _request(self, method, url, *, body="", depth=None, allow_redirects=False):
        response = self.session.request(
            method,
            url,
            headers=self._headers(depth=depth),
            data=body,
            allow_redirects=allow_redirects,
        )
        if response.status_code == 401:
            raise CardDAVError("Invalid CardDAV credentials")
        if response.status_code >= 400:
            raise CardDAVError(
                f"CardDAV {method} {url} failed with HTTP {response.status_code}"
            )
        return response

    def _propfind(self, url, prop_xml, *, depth="0"):
        body = f"""<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="{DAV_NS}" xmlns:C="{CARDDAV_NS}" xmlns:CS="{CALENDAR_SERVER_NS}">
  <D:prop>
    {prop_xml}
  </D:prop>
</D:propfind>"""
        response = self._request("PROPFIND", url, body=body, depth=depth)
        return parse_multistatus(response.text)

    def _report(self, url, report_xml, *, depth="1"):
        response = self._request("REPORT", url, body=report_xml, depth=depth)
        return parse_multistatus(response.text)

    def discover_root_url(self):
        """Return the CardDAV root URL after .well-known discovery."""
        well_known = urljoin(self.server_url, "/.well-known/carddav")
        body = f"""<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="{DAV_NS}">
  <D:prop><D:current-user-principal /></D:prop>
</D:propfind>"""
        response = self._request("PROPFIND", well_known, body=body, depth="0")
        if 300 <= response.status_code < 400 and response.headers.get("Location"):
            return urljoin(self.server_url, response.headers["Location"])
        return well_known if response.status_code == 207 else self.server_url

    def principal_url(self, root_url):
        responses = self._propfind(
            root_url,
            "<D:current-user-principal />",
            depth="0",
        )
        for response in responses:
            href = response.props.get("current-user-principal")
            if response.ok and href:
                return urljoin(root_url, href)
        raise CardDAVError("Unable to discover CardDAV principal URL")

    def addressbook_home_url(self, root_url, principal_url):
        responses = self._propfind(
            principal_url,
            "<C:addressbook-home-set />",
            depth="0",
        )
        for response in responses:
            href = response.props.get("addressbook-home-set")
            if response.ok and href:
                return urljoin(root_url, href)
        raise CardDAVError("Unable to discover CardDAV addressbook home")

    def addressbooks(self):
        root_url = self.discover_root_url()
        principal_url = self.principal_url(root_url)
        home_url = self.addressbook_home_url(root_url, principal_url)
        responses = self._propfind(
            home_url,
            """
    <D:displayname />
    <CS:getctag />
    <D:resourcetype />
            """,
            depth="1",
        )
        books = []
        for response in responses:
            resource_types = response.props.get("resourcetype") or []
            if response.ok and "addressbook" in resource_types:
                books.append(
                    DAVAddressBook(
                        url=urljoin(root_url, response.href),
                        display_name=response.props.get("displayname", ""),
                        ctag=response.props.get("getctag", ""),
                    )
                )
        if not books:
            raise CardDAVError("No CardDAV address books found")
        return books

    def fetch_vcards(self, addressbook_url=None):
        """Fetch all vCard objects from ADDRESSBOOK_URL or the first book."""
        if addressbook_url is None:
            addressbook_url = self.addressbooks()[0].url
        body = f"""<?xml version="1.0" encoding="utf-8"?>
<C:addressbook-query xmlns:D="{DAV_NS}" xmlns:C="{CARDDAV_NS}">
  <D:prop>
    <D:getetag />
    <C:address-data />
  </D:prop>
  <C:filter>
    <C:prop-filter name="FN" />
  </C:filter>
</C:addressbook-query>"""
        responses = self._report(addressbook_url, body, depth="1")
        cards = []
        for response in responses:
            data = response.props.get("address-data", "")
            if response.ok and data:
                cards.append(
                    DAVCard(
                        url=urljoin(addressbook_url, response.href),
                        etag=response.props.get("getetag", ""),
                        data=data,
                    )
                )
        return cards
