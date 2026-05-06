from icloud_to_org_contacts.carddav import CardDAVClient, parse_multistatus


class FakeResponse:
    def __init__(self, status_code, text="", headers=None):
        self.status_code = status_code
        self.text = text
        self.headers = headers or {}


class FakeSession:
    def __init__(self, routes):
        self.routes = routes
        self.calls = []

    def request(self, method, url, **kwargs):
        self.calls.append((method, url, kwargs))
        key = (method, url)
        if key not in self.routes:
            raise AssertionError(f"Unexpected request: {method} {url}")
        return self.routes[key]


def multistatus(*responses):
    return f"""<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav" xmlns:CS="http://calendarserver.org/ns/">
  {''.join(responses)}
</D:multistatus>"""


def response(href, *props):
    return f"""
<D:response>
  <D:href>{href}</D:href>
  <D:propstat>
    <D:prop>{''.join(props)}</D:prop>
    <D:status>HTTP/1.1 200 OK</D:status>
  </D:propstat>
</D:response>"""


def response_status(href, status_text, *props):
    return f"""
<D:response>
  <D:href>{href}</D:href>
  <D:propstat>
    <D:prop>{''.join(props)}</D:prop>
    <D:status>{status_text}</D:status>
  </D:propstat>
</D:response>"""


def test_parse_multistatus_extracts_href_status_and_props():
    xml = multistatus(
        response(
            "/carddav/card.vcf",
            "<D:getetag>etag-1</D:getetag>",
            "<C:address-data><![CDATA[BEGIN:VCARD\nFN:Alice\nEND:VCARD]]></C:address-data>",
        )
    )

    [entry] = parse_multistatus(xml)

    assert entry.href == "/carddav/card.vcf"
    assert entry.status == 200
    assert entry.ok is True
    assert entry.props["getetag"] == "etag-1"
    assert "FN:Alice" in entry.props["address-data"]


def test_carddav_client_discovers_addressbook_and_fetches_vcards():
    session = FakeSession(
        {
            ("PROPFIND", "https://contacts.example/.well-known/carddav"): FakeResponse(
                302,
                headers={"Location": "/dav/"},
            ),
            ("PROPFIND", "https://contacts.example/dav/"): FakeResponse(
                207,
                multistatus(
                    response(
                        "/dav/",
                        "<D:current-user-principal><D:href>/dav/principals/user/</D:href></D:current-user-principal>",
                    )
                ),
            ),
            ("PROPFIND", "https://contacts.example/dav/principals/user/"): FakeResponse(
                207,
                multistatus(
                    response(
                        "/dav/principals/user/",
                        "<C:addressbook-home-set><D:href>/dav/addressbooks/user/</D:href></C:addressbook-home-set>",
                    )
                ),
            ),
            ("PROPFIND", "https://contacts.example/dav/addressbooks/user/"): FakeResponse(
                207,
                multistatus(
                    response(
                        "/dav/addressbooks/user/",
                        "<D:displayname>Home</D:displayname>",
                        "<D:resourcetype><D:collection /></D:resourcetype>",
                    ),
                    response(
                        "/dav/addressbooks/user/card/",
                        "<D:displayname>Contacts</D:displayname>",
                        "<CS:getctag>ctag-1</CS:getctag>",
                        "<D:resourcetype><D:collection /><C:addressbook /></D:resourcetype>",
                    ),
                ),
            ),
            ("REPORT", "https://contacts.example/dav/addressbooks/user/card/"): FakeResponse(
                207,
                multistatus(
                    response(
                        "/dav/addressbooks/user/card/alice.vcf",
                        "<D:getetag>etag-a</D:getetag>",
                        "<C:address-data><![CDATA[BEGIN:VCARD\nVERSION:3.0\nUID:alice\nFN:Alice\nEND:VCARD]]></C:address-data>",
                    )
                ),
            ),
        }
    )
    client = CardDAVClient(
        "https://contacts.example",
        "user@example.com",
        "app-password",
        session=session,
    )

    [book] = client.addressbooks()
    [card] = client.fetch_vcards(book.url)

    assert book.url == "https://contacts.example/dav/addressbooks/user/card/"
    assert book.display_name == "Contacts"
    assert book.ctag == "ctag-1"
    assert card.url == "https://contacts.example/dav/addressbooks/user/card/alice.vcf"
    assert card.etag == "etag-a"
    assert "UID:alice" in card.data
    auth_header = session.calls[0][2]["headers"]["Authorization"]
    assert auth_header.startswith("Basic ")
    assert session.calls[-1][2]["headers"]["Depth"] == "1"


def test_carddav_client_falls_back_when_well_known_has_no_principal():
    session = FakeSession(
        {
            ("PROPFIND", "https://contacts.example/.well-known/carddav"): FakeResponse(
                207,
                multistatus(
                    response_status(
                        "/.well-known/carddav/",
                        "HTTP/1.1 404 Not Found",
                        "<D:current-user-principal />",
                    )
                ),
            ),
            ("PROPFIND", "https://contacts.example/"): FakeResponse(
                207,
                multistatus(
                    response(
                        "/",
                        "<D:current-user-principal><D:href>/principal/</D:href></D:current-user-principal>",
                    )
                ),
            ),
            ("PROPFIND", "https://contacts.example/principal/"): FakeResponse(
                207,
                multistatus(
                    response(
                        "/principal/",
                        "<C:addressbook-home-set><D:href>/addressbooks/</D:href></C:addressbook-home-set>",
                    )
                ),
            ),
            ("PROPFIND", "https://contacts.example/addressbooks/"): FakeResponse(
                207,
                multistatus(
                    response(
                        "/addressbooks/card/",
                        "<D:displayname>Contacts</D:displayname>",
                        "<D:resourcetype><D:collection /><C:addressbook /></D:resourcetype>",
                    )
                ),
            ),
        }
    )
    client = CardDAVClient(
        "https://contacts.example",
        "user@example.com",
        "app-password",
        session=session,
    )

    [book] = client.addressbooks()

    assert book.url == "https://contacts.example/addressbooks/card/"
    assert session.calls[1][1] == "https://contacts.example/"
