"""Build Org-mode contact notes from parsed vCard data.

Pure functions over the dicts produced by vcard.parse_vcards plus
small filesystem helpers (find/extract). Owns the on-disk note shape:
property drawer, title, filetags, body preservation.

The drawer is built as a list of (key, value) pairs so the CLI can
do a 3-way merge against an existing file's drawer: keys we never
emitted (= user-added) are preserved across imports.
"""

import re

from vcard import format_address, format_birthday, format_phone

_DRAWER_LINE_RE = re.compile(r"^:([A-Z_][A-Z_0-9]*):\s*(.*)$")


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

    Header = property drawer + any number of `#+keyword:` lines. Body
    is everything after that, minus a single optional separator blank
    line. Returns "" if the file has no body content.
    """
    with open(filepath, "r", encoding="utf-8") as f:
        lines = f.readlines()

    end_idx = -1
    for i, line in enumerate(lines):
        if line.strip() == ":END:":
            end_idx = i
            break
    if end_idx < 0:
        body = "".join(lines)
        return body if body.strip() else ""

    i = end_idx + 1
    while i < len(lines) and lines[i].lstrip().startswith("#+"):
        i += 1
    if i < len(lines) and lines[i].strip() == "":
        i += 1

    body = "".join(lines[i:])
    return body if body.strip() else ""


def parse_existing_drawer(filepath):
    """Parse :PROPERTIES: drawer into a list of (key, value) pairs.

    Preserves order. Keys are upper-case without surrounding colons;
    values have leading/trailing whitespace stripped. Returns [] if
    no drawer is present.
    """
    with open(filepath, "r", encoding="utf-8") as f:
        lines = f.readlines()

    pairs = []
    in_drawer = False
    for line in lines:
        stripped = line.strip()
        if stripped == ":PROPERTIES:":
            in_drawer = True
            continue
        if stripped == ":END:":
            break
        if not in_drawer:
            continue
        m = _DRAWER_LINE_RE.match(stripped)
        if m:
            pairs.append((m.group(1), m.group(2).strip()))
    return pairs


def build_drawer_pairs(contact, org_id, vcard_uid):
    """Compute the property drawer key-value pairs we want to emit.

    Returns list of (key, value) tuples. Keys are upper-case without
    surrounding colons. Values are pre-formatted strings.
    """
    pairs = [("ID", org_id)]
    if vcard_uid:
        pairs.append(("VCARD_UID", vcard_uid))

    for i, (label, value) in enumerate(contact.get("EMAIL", [])):
        suffix = f"_{label.upper()}" if label else (f"_{i+1}" if i > 0 else "")
        pairs.append((f"EMAIL{suffix}", value))

    for i, (label, value) in enumerate(contact.get("TEL", [])):
        suffix = f"_{label.upper()}" if label else (f"_{i+1}" if i > 0 else "")
        pairs.append((f"PHONE{suffix}", format_phone(value)))

    org = contact.get("ORG", "")
    if org:
        org_name = org.split(";")[0].strip()
        if org_name:
            pairs.append(("COMPANY", org_name))

    title = contact.get("TITLE", "")
    if title:
        pairs.append(("ROLE", title))

    for i, (label, value) in enumerate(contact.get("ADR", [])):
        formatted = format_address(value)
        if formatted:
            suffix = f"_{label.upper()}" if label else (f"_{i+1}" if i > 0 else "")
            pairs.append((f"ADDRESS{suffix}", formatted))

    bday = format_birthday(contact.get("BDAY", ""))
    if bday:
        pairs.append(("BIRTHDAY", bday))

    return pairs


def merge_drawer_pairs(existing_pairs, old_emitted_keys, new_pairs):
    """3-way merge of property drawer state.

    Inputs:
      existing_pairs    — what's currently in the file's drawer.
      old_emitted_keys  — keys we wrote on the previous run.
      new_pairs         — keys+values we want to write this run.

    Output: ordered list of (key, value) pairs comprising:
      1. new_pairs in their canonical order (our values win for any
         key we currently emit).
      2. user-added keys preserved from existing_pairs in their
         original order — i.e. any key in the drawer that wasn't in
         old_emitted_keys and isn't in new_pairs.
    """
    old_emitted = set(old_emitted_keys)
    new_keys = {k for k, _ in new_pairs}

    user_keys = [
        (k, v) for k, v in existing_pairs
        if k not in old_emitted and k not in new_keys
    ]
    return list(new_pairs) + user_keys


def format_org_note(drawer_pairs, fn, *, body="", vcard_note=""):
    """Format a complete org file from drawer pairs + title/filetags + body."""
    lines = [":PROPERTIES:"]
    for key, value in drawer_pairs:
        lines.append(f":{key}: {value}".rstrip())
    lines.append(":END:")
    lines.append(f"#+title: {fn}")
    lines.append("#+filetags: :contact:")
    lines.append("")

    if vcard_note and not body:
        note_text = vcard_note.replace("\\n", "\n").strip()
        lines.append(note_text)
        lines.append("")

    if body:
        lines.append(body.rstrip())
        lines.append("")

    return "\n".join(lines)


def build_org_note(contact, org_id, vcard_uid, existing_body=None):
    """Build a fresh org note (no drawer merge — for new contacts).

    Returns (note_text, emitted_keys).
    """
    pairs = build_drawer_pairs(contact, org_id, vcard_uid)
    fn = contact.get("FN", "Unknown")
    text = format_org_note(
        pairs,
        fn,
        body=existing_body or "",
        vcard_note=contact.get("NOTE", ""),
    )
    return text, [k for k, _ in pairs]
