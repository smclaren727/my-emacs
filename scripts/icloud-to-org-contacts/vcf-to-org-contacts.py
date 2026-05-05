#!/usr/bin/env python3
"""Import Apple Contacts vCard export into plain Org contact notes.

Usage:
    python3 vcf-to-org-contacts.py <input.vcf> [output-dir]

Output directory defaults to ~/All-The-Things/50-Resources/Contacts/.

On re-import, matches contacts by vCard UID.  Updates properties and
title but preserves any body text (backlinks, notes) you've added
below the header.

A manifest file (.import-state.json) in the output directory tracks
per-contact content hashes so unchanged contacts are skipped on
subsequent runs.
"""

import re
import sys
import uuid
from datetime import date
from pathlib import Path

from vcard import parse_vcards
from orgnote import (
    build_org_note,
    extract_body,
    find_existing_note,
    sanitize_filename,
    unique_filepath,
)
from manifest import (
    content_hash,
    load_manifest,
    make_entry,
    output_settings_hash,
    save_manifest,
)
from lifecycle import archive_contact, resurrect_contact


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <input.vcf> [output-dir]")
        sys.exit(1)

    vcf_path = Path(sys.argv[1])
    output_dir = (
        Path(sys.argv[2])
        if len(sys.argv) > 2
        else Path.home() / "All-The-Things" / "50-Resources" / "Contacts"
    )

    if not vcf_path.exists():
        print(f"Error: {vcf_path} not found")
        sys.exit(1)

    output_dir.mkdir(parents=True, exist_ok=True)

    manifest = load_manifest(output_dir)
    settings_hash = output_settings_hash()
    settings_changed = (
        manifest.get("output_settings_hash") is not None
        and manifest["output_settings_hash"] != settings_hash
    )
    if settings_changed:
        print("Output settings changed — rewriting all contacts.")

    contacts = parse_vcards(str(vcf_path))
    print(f"Parsed {len(contacts)} contacts from {vcf_path.name}")

    created = 0
    updated = 0
    unchanged = 0
    skipped = 0
    renamed = 0
    archived = 0
    resurrected = 0
    today = date.today().isoformat()

    for contact in contacts:
        fn = contact.get("FN", "").strip()
        if not fn:
            skipped += 1
            continue

        vcard_uid = contact.get("UID", "")
        chash = content_hash(contact)
        prev = manifest["contacts"].get(vcard_uid) if vcard_uid else None

        # Resurrect first: a previously-archived contact reappearing
        # in the source is moved back out of Archive/ and gets archive
        # markers stripped before the normal create/update flow runs.
        was_archived = bool(prev and prev.get("archived"))
        if was_archived:
            archived_path = output_dir / prev["path"]
            if archived_path.exists():
                new_path = resurrect_contact(archived_path, output_dir)
                prev["path"] = str(new_path.relative_to(output_dir))
                resurrected += 1
            prev["archived"] = False

        if (not was_archived
                and vcard_uid
                and prev
                and not settings_changed
                and prev.get("content_hash") == chash
                and (output_dir / prev["path"]).exists()):
            unchanged += 1
            continue

        existing_file = find_existing_note(output_dir, vcard_uid)

        if existing_file:
            desired_basename = sanitize_filename(fn)
            if existing_file.stem != desired_basename:
                new_path = unique_filepath(output_dir, desired_basename)
                existing_file.rename(new_path)
                print(f"  renamed: {existing_file.name} -> {new_path.name}")
                existing_file = new_path
                renamed += 1

            existing_body = extract_body(existing_file)
            with open(existing_file, "r", encoding="utf-8") as f:
                content = f.read(2000)
            id_match = re.search(r":ID:\s+(.+)", content)
            org_id = id_match.group(1).strip() if id_match else str(uuid.uuid4())
            note_content = build_org_note(contact, org_id, vcard_uid, existing_body)
            with open(existing_file, "w", encoding="utf-8") as f:
                f.write(note_content)
            updated += 1
            filepath = existing_file
        else:
            org_id = str(uuid.uuid4())
            note_content = build_org_note(contact, org_id, vcard_uid)
            filepath = unique_filepath(output_dir, sanitize_filename(fn))

            with open(filepath, "w", encoding="utf-8") as f:
                f.write(note_content)
            created += 1

        if vcard_uid:
            manifest["contacts"][vcard_uid] = make_entry(
                str(filepath.relative_to(output_dir)),
                chash,
            )

    # Deletion sweep: any UID we tracked previously but didn't see in
    # this run is archived (unless already archived, or its file is
    # already gone — in which case we just drop the manifest entry).
    seen_uids = {
        c.get("UID", "") for c in contacts
        if c.get("UID") and c.get("FN", "").strip()
    }
    for uid, entry in list(manifest["contacts"].items()):
        if uid in seen_uids:
            continue
        file_path = output_dir / entry["path"]
        if entry.get("archived"):
            # Already archived: just confirm the file still exists,
            # otherwise drop the stale manifest entry.
            if not file_path.exists():
                del manifest["contacts"][uid]
            continue
        if not file_path.exists():
            # User deleted the file manually before it was archived.
            del manifest["contacts"][uid]
            continue
        new_path = archive_contact(file_path, output_dir, today)
        entry["path"] = str(new_path.relative_to(output_dir))
        entry["archived"] = True
        archived += 1

    manifest["output_settings_hash"] = settings_hash
    save_manifest(output_dir, manifest)

    print(f"Done: {created} created, {updated} updated, "
          f"{unchanged} unchanged, {skipped} skipped, {renamed} renamed, "
          f"{archived} archived, {resurrected} resurrected")
    print(f"Output: {output_dir}")
    print("Notes use plain Org IDs and should appear once org-node refreshes its cache.")


if __name__ == "__main__":
    main()
