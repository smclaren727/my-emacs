"""vCard parsing and field formatting.

Pure functions over vCard text. No I/O of Org-mode files, no manifest
awareness. Output is a list of dicts whose shape matches the on-disk
vCard fields with light normalisation.

Apple Contacts uses an `itemN.` prefix to group a property with its
companion fields (e.g. `item1.TEL` paired with `item1.X-ABLABEL` for
custom labels, or `item1.ADR` paired with `item1.X-ABADR` for the
country code). The parser strips the prefix from base_key but keeps
the group name so downstream code can look up the companion fields.
"""

import hashlib

import vobject


def split_contacts_and_groups(records):
    """Partition parsed records into regular contacts and a UID->groups index.

    Apple's address book exports group definitions as their own vCards
    with X-ADDRESSBOOKSERVER-KIND:group. Each group lists its members
    via X-ADDRESSBOOKSERVER-MEMBER lines pointing at contact UIDs.

    Returns (contacts, membership) where:
      contacts   — list of dicts, group cards excluded
      membership — {contact_uid: [group_name, ...]} (insertion order)

    `membership` is empty if the input has no group cards at all,
    which the CLI uses as a signal that this run shouldn't touch
    filetags on existing contact files.
    """
    contacts = []
    membership = {}
    for record in records:
        if record.get("X-ADDRESSBOOKSERVER-KIND") == "group":
            group_name = record.get("FN", "").strip()
            if not group_name:
                continue
            for member_uri in record.get("_members", []):
                uid = member_uri.replace("urn:uuid:", "").strip()
                if uid:
                    membership.setdefault(uid, []).append(group_name)
        else:
            contacts.append(record)
    return contacts, membership


def synthesize_uid(contact):
    """Produce a stable identity for a contact whose vCard lacks UID.

    Apple's macOS export drops UID for many contacts, so we hash a
    combination of FN, structured name (N), phones, and emails. The
    result is stable as long as none of those fields change between
    imports — if any of them change, the contact will be detected as
    a new entry and the previous file archived. This is a known
    limitation that Tier 6 (CardDAV) eliminates by using server-side
    resource URLs as identity.
    """
    fn = contact.get("FN", "")
    n = contact.get("N", "")
    phones = sorted(v for _, v, _ in contact.get("TEL", []))
    emails = sorted(v for _, v, _ in contact.get("EMAIL", []))
    payload = "\n".join([fn, n] + phones + emails)
    return "synth-" + hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]


def _strip_uri_scheme(value):
    """Drop Apple's `x-apple:` or `xmpp:` URI scheme from an IMPP/social value."""
    for prefix in ("x-apple:", "xmpp:"):
        if value.lower().startswith(prefix):
            return value[len(prefix):]
    return value


def _extract_param(params, name):
    """Return the first value of a vCard parameter (case-insensitive)."""
    target = name.upper()
    for key, values in params.items():
        if key.upper() != target:
            continue
        if isinstance(values, list):
            return str(values[0]) if values else ""
        return str(values)
    return ""


def _extract_type(params):
    """Extract a human-readable type label from vCard parameters.

    e.g., TYPE=CELL,VOICE -> 'cell'
          TYPE=INTERNET,WORK -> 'work'
    Prefers meaningful labels (home, work, cell, mobile) over
    generic ones (voice, internet, pref).
    """
    types = []
    for key, values in params.items():
        if key.upper() != "TYPE":
            continue
        if not isinstance(values, list):
            values = [values]
        for value in values:
            types.extend(
                piece.strip().lower()
                for piece in str(value).split(",")
                if piece.strip()
            )

    meaningful = {"home", "work", "cell", "mobile", "main", "fax",
                  "iphone", "other", "school"}
    for t in types:
        if t in meaningful:
            return t
    return ""


def _value_to_string(value):
    """Return a stable vCard-ish string for simple and structured values."""
    if hasattr(value, "family") and hasattr(value, "given"):
        return ";".join([
            value.family or "",
            value.given or "",
            value.additional or "",
            value.prefix or "",
            value.suffix or "",
        ])
    if isinstance(value, list):
        return ";".join(str(v) for v in value)
    return str(value)


def _address_to_string(value):
    """Return ADR as the seven semicolon-separated vCard fields."""
    if hasattr(value, "street") and hasattr(value, "city"):
        return ";".join([
            value.box or "",
            value.extended or "",
            value.street or "",
            value.city or "",
            value.region or "",
            value.code or "",
            value.country or "",
        ])
    return str(value)


def _name_to_full_name(value):
    """Build FN fallback text from a structured N value."""
    if not (hasattr(value, "family") and hasattr(value, "given")):
        return ""
    pieces = [
        value.prefix,
        value.given,
        value.additional,
        value.family,
        value.suffix,
    ]
    return " ".join(str(p).strip() for p in pieces if str(p).strip())


def parse_vcard_text(vcf_text):
    """Parse vCard text into a list of dicts, one per contact."""
    contacts = []
    for component in vobject.readComponents(vcf_text):
        contact = {}

        for children in component.contents.values():
            for child in children:
                base_key = child.name.upper()
                group = (getattr(child, "group", "") or "").lower()
                params = getattr(child, "params", {}) or {}

                if base_key == "PHOTO":
                    continue

                if base_key in ("TEL", "EMAIL", "URL"):
                    existing = contact.get(base_key, [])
                    existing.append(
                        (_extract_type(params), _value_to_string(child.value), group)
                    )
                    contact[base_key] = existing
                elif base_key == "ADR":
                    existing = contact.get(base_key, [])
                    existing.append(
                        (_extract_type(params), _address_to_string(child.value), group)
                    )
                    contact[base_key] = existing
                elif base_key == "IMPP":
                    service = _extract_param(params, "X-SERVICE-TYPE")
                    impp_list = contact.setdefault("_impp", [])
                    impp_list.append((service, _strip_uri_scheme(str(child.value))))
                elif base_key == "X-SOCIALPROFILE":
                    network = _extract_param(params, "type")
                    social_list = contact.setdefault("_social", [])
                    social_list.append((network, _strip_uri_scheme(str(child.value))))
                elif base_key == "X-ABRELATEDNAMES":
                    related_list = contact.setdefault("_related", [])
                    related_list.append((group, _value_to_string(child.value)))
                elif base_key == "X-ADDRESSBOOKSERVER-MEMBER":
                    members = contact.setdefault("_members", [])
                    members.append(_value_to_string(child.value))
                elif base_key == "X-ABDATE":
                    groups = contact.setdefault("_groups", {})
                    date_group = group or f"date{len(groups) + 1}"
                    groups.setdefault(date_group, {})[base_key] = _value_to_string(
                        child.value
                    )
                elif group:
                    groups = contact.setdefault("_groups", {})
                    groups.setdefault(group, {})[base_key] = _value_to_string(
                        child.value
                    )
                else:
                    contact[base_key] = _value_to_string(child.value)
                    if base_key == "N" and not contact.get("_N_FULL_NAME"):
                        contact["_N_FULL_NAME"] = _name_to_full_name(child.value)

        # Apple occasionally ships company-only contacts with FN unset.
        # Fall back to NICKNAME, N, then the organization name.
        if not contact.get("FN"):
            fallback = (
                contact.get("NICKNAME", "").strip()
                or contact.get("_N_FULL_NAME", "").strip()
                or (contact.get("ORG", "").split(";")[0].strip()
                    if contact.get("ORG") else "")
            )
            if fallback:
                contact["FN"] = fallback
        contact.pop("_N_FULL_NAME", None)

        if contact.get("FN"):
            if not contact.get("UID"):
                contact["UID"] = synthesize_uid(contact)
            contacts.append(contact)

    return contacts


def parse_vcards(vcf_path):
    """Parse a .vcf file into a list of dicts, one per contact."""
    with open(vcf_path, "r", encoding="utf-8") as f:
        return parse_vcard_text(f.read())


def format_phone(phone):
    return phone.strip()


def format_address(adr):
    """Convert vCard ADR (semicolon-separated) to a readable string."""
    parts = adr.split(";")
    while len(parts) < 7:
        parts.append("")
    _, _, street, city, state, zipcode, country = parts
    pieces = [p.strip() for p in [street, city, state, zipcode, country] if p.strip()]
    return ", ".join(pieces)


def format_birthday(bday):
    """Clean birthday, handling Apple's omit-year sentinel (1604)."""
    if not bday:
        return None
    if bday.startswith("1604-"):
        return bday.replace("1604-", "--")
    return bday
