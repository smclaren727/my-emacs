#!/usr/bin/env python3
"""Import Apple Contacts vCard export into org-roam contact notes.

Usage:
    python3 vcf-to-org-roam.py <input.vcf> [output-dir]

Output directory defaults to ~/Notes/Contacts/.

On re-import, matches contacts by vCard UID.  Updates properties and
title but preserves any body text (backlinks, notes) you've added
below the header.
"""

import sys
import os
import re
import uuid
from pathlib import Path


def _extract_type(key_part):
    """Extract a human-readable type label from vCard parameters.

    e.g., 'TEL;type=CELL;type=VOICE;type=pref' -> 'cell'
          'EMAIL;type=INTERNET;type=WORK'       -> 'work'
    Prefers meaningful labels (home, work, cell, mobile) over
    generic ones (voice, internet, pref).
    """
    params = key_part.upper().split(";")[1:]
    # Collect all type= values
    types = []
    for param in params:
        if param.startswith("TYPE="):
            types.append(param[5:].lower())
        elif "=" not in param:
            # Bare parameter like TEL;CELL:value (older vCard style)
            types.append(param.lower())

    # Prefer meaningful labels over generic ones
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

            # Skip blank lines
            if not line:
                continue

            # vCard folded lines (continuation) start with space/tab
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

            # Parse "KEY;params:value"
            if ":" not in line:
                continue

            key_part, value = line.split(":", 1)
            # Strip parameters (e.g., TEL;type=CELL -> TEL)
            base_key = key_part.split(";")[0].upper()

            # Skip binary data (photos, etc.)
            if "ENCODING=b" in key_part or "ENCODING=B" in key_part:
                current_key = None
                continue

            # Handle multi-value fields — store as list of (type_label, value)
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
    """Clean phone number for display."""
    return phone.strip()


def format_address(adr):
    """Convert vCard ADR (semicolon-separated) to readable string."""
    # ADR format: PO;Extended;Street;City;State;ZIP;Country
    parts = adr.split(";")
    # Pad to 7 fields
    while len(parts) < 7:
        parts.append("")
    _, _, street, city, state, zipcode, country = parts
    pieces = [p.strip() for p in [street, city, state, zipcode, country] if p.strip()]
    return ", ".join(pieces)


def format_birthday(bday):
    """Clean birthday, handling Apple's omit-year sentinel (1604)."""
    if not bday:
        return None
    # Strip the year if it's Apple's placeholder
    if bday.startswith("1604-"):
        return bday.replace("1604-", "--")
    return bday


def sanitize_filename(name):
    """Create a filesystem-safe filename from a contact name."""
    safe = re.sub(r"[^\w\s-]", "", name)
    safe = re.sub(r"\s+", "-", safe.strip())
    return safe.lower()


def find_existing_note(output_dir, vcard_uid):
    """Find an existing org-roam note matching a vCard UID."""
    if not vcard_uid or not output_dir.exists():
        return None
    for org_file in output_dir.glob("*.org"):
        with open(org_file, "r", encoding="utf-8") as f:
            content = f.read(2000)  # Only need the property drawer
            if f":VCARD_UID: {vcard_uid}" in content:
                return org_file
    return None


def extract_body(filepath):
    """Extract user-written body text (everything after the header block).

    Header = properties drawer + title + filetags.  Body starts at the
    first blank line after filetags (or title if no filetags).
    """
    with open(filepath, "r", encoding="utf-8") as f:
        lines = f.readlines()

    # Find end of header: after :END:, #+title:, #+filetags:
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
    """Build the org-roam note content for a contact."""
    fn = contact.get("FN", "Unknown")

    # Build properties
    props = [
        f":ID:       {org_id}",
    ]
    if vcard_uid:
        props.append(f":VCARD_UID: {vcard_uid}")

    # Email(s) — stored as (type_label, value) tuples
    emails = contact.get("EMAIL", [])
    for i, (label, value) in enumerate(emails):
        suffix = f"_{label.upper()}" if label else (f"_{i+1}" if i > 0 else "")
        props.append(f":EMAIL{suffix}: {value}")

    # Phone(s) — stored as (type_label, value) tuples
    phones = contact.get("TEL", [])
    for i, (label, value) in enumerate(phones):
        suffix = f"_{label.upper()}" if label else (f"_{i+1}" if i > 0 else "")
        props.append(f":PHONE{suffix}: {format_phone(value)}")

    # Organization
    org = contact.get("ORG", "")
    if org:
        # ORG can have sub-fields separated by ;
        org_name = org.split(";")[0].strip()
        if org_name:
            props.append(f":COMPANY:  {org_name}")

    # Title/role
    title = contact.get("TITLE", "")
    if title:
        props.append(f":ROLE:     {title}")

    # Address(es) — stored as (type_label, value) tuples
    addrs = contact.get("ADR", [])
    for i, (label, value) in enumerate(addrs):
        formatted = format_address(value)
        if formatted:
            suffix = f"_{label.upper()}" if label else (f"_{i+1}" if i > 0 else "")
            props.append(f":ADDRESS{suffix}: {formatted}")

    # Birthday
    bday = format_birthday(contact.get("BDAY", ""))
    if bday:
        props.append(f":BIRTHDAY: {bday}")

    # Build the note
    lines = [":PROPERTIES:"]
    lines.extend(props)
    lines.append(":END:")
    lines.append(f"#+title: {fn}")
    lines.append("#+filetags: :contact:")
    lines.append("")

    # Notes from the vCard
    note = contact.get("NOTE", "")
    if note and not existing_body:
        # vCard notes use \n for newlines
        note_text = note.replace("\\n", "\n").strip()
        lines.append(note_text)
        lines.append("")

    # Preserve existing body if updating
    if existing_body:
        lines.append(existing_body.rstrip())
        lines.append("")

    return "\n".join(lines)


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <input.vcf> [output-dir]")
        sys.exit(1)

    vcf_path = Path(sys.argv[1])
    output_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path.home() / "Notes" / "Contacts"

    if not vcf_path.exists():
        print(f"Error: {vcf_path} not found")
        sys.exit(1)

    output_dir.mkdir(parents=True, exist_ok=True)

    contacts = parse_vcards(str(vcf_path))
    print(f"Parsed {len(contacts)} contacts from {vcf_path.name}")

    created = 0
    updated = 0
    skipped = 0

    for contact in contacts:
        fn = contact.get("FN", "").strip()
        if not fn:
            skipped += 1
            continue

        vcard_uid = contact.get("UID", "")

        # Check for existing note
        existing_file = find_existing_note(output_dir, vcard_uid)

        if existing_file:
            # Update: preserve body, regenerate header
            existing_body = extract_body(existing_file)
            # Read existing org-id from the file
            with open(existing_file, "r", encoding="utf-8") as f:
                content = f.read(2000)
            id_match = re.search(r":ID:\s+(.+)", content)
            org_id = id_match.group(1).strip() if id_match else str(uuid.uuid4())
            note_content = build_org_note(contact, org_id, vcard_uid, existing_body)
            with open(existing_file, "w", encoding="utf-8") as f:
                f.write(note_content)
            updated += 1
        else:
            # Create new note
            org_id = str(uuid.uuid4())
            note_content = build_org_note(contact, org_id, vcard_uid)
            filename = sanitize_filename(fn) + ".org"
            filepath = output_dir / filename

            # Handle name collisions
            counter = 2
            while filepath.exists():
                filepath = output_dir / f"{sanitize_filename(fn)}-{counter}.org"
                counter += 1

            with open(filepath, "w", encoding="utf-8") as f:
                f.write(note_content)
            created += 1

    print(f"Done: {created} created, {updated} updated, {skipped} skipped")
    print(f"Output: {output_dir}")
    print("Run M-x org-roam-db-sync in Emacs to index the new notes.")


if __name__ == "__main__":
    main()
