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
import re

_GROUP_RE = re.compile(r"^(item\d+)\.(.+)$", re.IGNORECASE)


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


def _extract_param(key_part, name):
    """Return the value of a single vCard parameter (case-insensitive)."""
    target = name.upper() + "="
    for piece in key_part.upper().split(";")[1:]:
        if piece.startswith(target):
            return piece[len(target):]
    return ""


def _extract_type(key_part):
    """Extract a human-readable type label from vCard parameters.

    e.g., 'TEL;type=CELL;type=VOICE;type=pref' -> 'cell'
          'EMAIL;type=INTERNET;type=WORK'       -> 'work'
    Prefers meaningful labels (home, work, cell, mobile) over
    generic ones (voice, internet, pref).
    """
    params = key_part.upper().split(";")[1:]
    types = []
    for param in params:
        if param.startswith("TYPE="):
            types.append(param[5:].lower())
        elif "=" not in param:
            types.append(param.lower())

    meaningful = {"home", "work", "cell", "mobile", "main", "fax",
                  "iphone", "other", "school"}
    for t in types:
        if t in meaningful:
            return t
    return ""


def parse_vcards(vcf_path):
    """Parse a .vcf file into a list of dicts, one per contact."""
    contacts = []
    current = {}
    current_key = None

    with open(vcf_path, "r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.rstrip("\r\n")

            if not line:
                continue

            # Folded continuation lines start with space/tab
            if line[0] in (" ", "\t") and current_key:
                current[current_key] += line[1:]
                continue

            if line == "BEGIN:VCARD":
                current = {}
                current_key = None
                continue

            if line == "END:VCARD":
                # Apple occasionally ships company-only contacts with
                # FN unset. Fall back to NICKNAME, then to the org
                # name, before deciding whether to keep the contact.
                if not current.get("FN"):
                    fallback = (
                        current.get("NICKNAME", "").strip()
                        or (current.get("ORG", "").split(";")[0].strip()
                            if current.get("ORG") else "")
                    )
                    if fallback:
                        current["FN"] = fallback
                if current.get("FN"):
                    if not current.get("UID"):
                        current["UID"] = synthesize_uid(current)
                    contacts.append(current)
                current = {}
                current_key = None
                continue

            if ":" not in line:
                continue

            key_part, value = line.split(":", 1)

            # Strip itemN. group prefix (Apple grouping mechanism).
            group = ""
            m = _GROUP_RE.match(key_part)
            if m:
                group = m.group(1).lower()
                key_part = m.group(2)

            base_key = key_part.split(";")[0].upper()

            # Skip binary blobs (photos)
            if "ENCODING=b" in key_part or "ENCODING=B" in key_part:
                current_key = None
                continue

            if base_key in ("TEL", "EMAIL", "ADR", "URL"):
                type_label = _extract_type(key_part)
                existing = current.get(base_key, [])
                existing.append((type_label, value, group))
                current[base_key] = existing
            elif base_key == "IMPP":
                # X-SERVICE-TYPE names the messaging service (Skype,
                # iMessage, etc.); xmpp:/x-apple: schemes are stripped.
                service = _extract_param(key_part, "X-SERVICE-TYPE")
                impp_list = current.setdefault("_impp", [])
                impp_list.append((service, _strip_uri_scheme(value)))
            elif base_key == "X-SOCIALPROFILE":
                # type= names the social network (twitter, linkedin, ...).
                network = _extract_param(key_part, "type")
                social_list = current.setdefault("_social", [])
                social_list.append((network, _strip_uri_scheme(value)))
            elif base_key == "X-ADDRESSBOOKSERVER-MEMBER":
                # Group cards list members on multiple lines; collect
                # them all under _members so split_contacts_and_groups
                # can build the membership index.
                members = current.setdefault("_members", [])
                members.append(value)
            elif group:
                # Grouped non-multi-value key (X-ABLABEL, X-ABADR, etc.)
                # — store under _groups so it can be looked up later.
                groups = current.setdefault("_groups", {})
                groups.setdefault(group, {})[base_key] = value
                current_key = None
                continue
            else:
                current[base_key] = value

            current_key = base_key

    return contacts


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
