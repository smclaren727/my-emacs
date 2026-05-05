"""Build Org-mode contact notes from parsed vCard data.

Pure functions over the dicts produced by vcard.parse_vcards plus
small filesystem helpers (find/extract). Owns the on-disk note shape:
property drawer, title, filetags, body preservation.
"""

import re

from vcard import format_address, format_birthday, format_phone


def sanitize_filename(name):
    """Create a filesystem-safe filename from a contact name."""
    safe = re.sub(r"[^\w\s-]", "", name)
    safe = re.sub(r"\s+", "-", safe.strip())
    return safe.lower()


def unique_filepath(directory, basename, suffix=".org"):
    """Return a Path inside `directory` that does not collide.

    Tries `<basename><suffix>` first, then `<basename>-2<suffix>`,
    `<basename>-3<suffix>`, ... until an unused name is found.
    """
    path = directory / f"{basename}{suffix}"
    counter = 2
    while path.exists():
        path = directory / f"{basename}-{counter}{suffix}"
        counter += 1
    return path


def find_existing_note(output_dir, vcard_uid):
    """Find an existing contact note matching a vCard UID."""
    if not vcard_uid or not output_dir.exists():
        return None
    for org_file in output_dir.glob("*.org"):
        with open(org_file, "r", encoding="utf-8") as f:
            content = f.read(2000)
            if f":VCARD_UID: {vcard_uid}" in content:
                return org_file
    return None


def extract_body(filepath):
    """Extract user-written body text (everything after the header block).

    Header = properties drawer + title + filetags. Body starts at the
    first blank line after filetags (or title if no filetags).
    """
    with open(filepath, "r", encoding="utf-8") as f:
        lines = f.readlines()

    body_start = 0
    past_drawer = False
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped == ":END:":
            past_drawer = True
            continue
        if past_drawer and stripped.startswith("#+"):
            continue
        if past_drawer and stripped == "":
            body_start = i + 1
            break
        if past_drawer:
            body_start = i
            break

    body = "".join(lines[body_start:])
    return body if body.strip() else ""


def build_org_note(contact, org_id, vcard_uid, existing_body=None):
    """Build the Org note content for a contact."""
    fn = contact.get("FN", "Unknown")

    props = [f":ID:       {org_id}"]
    if vcard_uid:
        props.append(f":VCARD_UID: {vcard_uid}")

    emails = contact.get("EMAIL", [])
    for i, (label, value) in enumerate(emails):
        suffix = f"_{label.upper()}" if label else (f"_{i+1}" if i > 0 else "")
        props.append(f":EMAIL{suffix}: {value}")

    phones = contact.get("TEL", [])
    for i, (label, value) in enumerate(phones):
        suffix = f"_{label.upper()}" if label else (f"_{i+1}" if i > 0 else "")
        props.append(f":PHONE{suffix}: {format_phone(value)}")

    org = contact.get("ORG", "")
    if org:
        org_name = org.split(";")[0].strip()
        if org_name:
            props.append(f":COMPANY:  {org_name}")

    title = contact.get("TITLE", "")
    if title:
        props.append(f":ROLE:     {title}")

    addrs = contact.get("ADR", [])
    for i, (label, value) in enumerate(addrs):
        formatted = format_address(value)
        if formatted:
            suffix = f"_{label.upper()}" if label else (f"_{i+1}" if i > 0 else "")
            props.append(f":ADDRESS{suffix}: {formatted}")

    bday = format_birthday(contact.get("BDAY", ""))
    if bday:
        props.append(f":BIRTHDAY: {bday}")

    lines = [":PROPERTIES:"]
    lines.extend(props)
    lines.append(":END:")
    lines.append(f"#+title: {fn}")
    lines.append("#+filetags: :contact:")
    lines.append("")

    note = contact.get("NOTE", "")
    if note and not existing_body:
        note_text = note.replace("\\n", "\n").strip()
        lines.append(note_text)
        lines.append("")

    if existing_body:
        lines.append(existing_body.rstrip())
        lines.append("")

    return "\n".join(lines)
