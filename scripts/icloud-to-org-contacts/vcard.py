"""vCard parsing and field formatting.

Pure functions over vCard text. No I/O of Org-mode files, no manifest
awareness. Output is a list of dicts whose shape matches the on-disk
vCard fields with light normalisation.
"""


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
                if current.get("FN"):
                    contacts.append(current)
                current = {}
                current_key = None
                continue

            if ":" not in line:
                continue

            key_part, value = line.split(":", 1)
            base_key = key_part.split(";")[0].upper()

            # Skip binary blobs (photos)
            if "ENCODING=b" in key_part or "ENCODING=B" in key_part:
                current_key = None
                continue

            if base_key in ("TEL", "EMAIL", "ADR"):
                type_label = _extract_type(key_part)
                existing = current.get(base_key, [])
                existing.append((type_label, value))
                current[base_key] = existing
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
