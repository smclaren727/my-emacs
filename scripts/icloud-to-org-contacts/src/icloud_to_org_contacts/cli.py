#!/usr/bin/env python3
"""Import Apple Contacts vCard exports into plain Org contact notes.

Usage:
    vcf-to-org-contacts.py <input>... [-o OUTPUT_DIR] [--no-archive]

Each <input> is either a .vcf file or a directory containing .vcf
files (globbed non-recursively). Multiple positional arguments are
accepted; their parsed contacts are unioned and treated as the
authoritative dataset for the deletion sweep.

Output defaults to ~/All-The-Things/50-Resources/Contacts/.

On re-import, matches contacts by vCard UID. Updates properties and
title but preserves any body text and any hand-added drawer keys.

A manifest file (.import-state.json) in the output directory tracks
per-contact content hashes so unchanged contacts are skipped.
"""

import argparse
import sys
import uuid
from datetime import date
from pathlib import Path

from .vcard import parse_vcards, split_contacts_and_groups
from .orgnote import (
    build_drawer_pairs,
    build_org_note,
    extract_body,
    find_existing_note,
    format_org_note,
    merge_drawer_pairs,
    parse_existing_drawer,
    parse_existing_filetags,
    sanitize_filename,
    unique_filepath,
)
from .manifest import (
    content_hash,
    load_manifest,
    make_entry,
    output_settings_hash,
    save_manifest,
)
from .lifecycle import archive_contact, resurrect_contact


DEFAULT_OUTPUT_DIR = Path.home() / "All-The-Things" / "50-Resources" / "Contacts"
ERRORS_FILENAME = "errors.org"


def _append_error(output_dir, heading, exception, data=None):
    """Append a heading describing a per-contact failure to errors.org.

    The file is created on first write with a small header. Subsequent
    failures append additional `* date - heading` sections containing
    the exception type, message, and an example block dumping the
    contact data for debugging.
    """
    errors_path = output_dir / ERRORS_FILENAME
    is_new = not errors_path.exists()
    today = date.today().isoformat()

    chunk = []
    if is_new:
        chunk.append("#+title: Contact import errors")
        chunk.append("#+filetags: :contacts-errors:")
        chunk.append("")
    chunk.append(f"* {today} — {heading}")
    chunk.append(f"  {type(exception).__name__}: {exception}")
    if data is not None:
        chunk.append("")
        chunk.append("  #+begin_example")
        for line in str(data).splitlines() or [str(data)]:
            chunk.append(f"  {line}")
        chunk.append("  #+end_example")
    chunk.append("")

    with open(errors_path, "a", encoding="utf-8") as f:
        f.write("\n".join(chunk) + "\n")


def _resolve_inputs(raw_inputs):
    """Expand each positional argument into a list of .vcf file paths.

    A directory contributes its top-level *.vcf files (sorted, not
    recursive); a regular file contributes itself. Missing paths or
    directories with no .vcf files raise SystemExit.
    """
    paths = []
    for raw in raw_inputs:
        p = Path(raw)
        if not p.exists():
            print(f"Error: {p} not found")
            sys.exit(1)
        if p.is_dir():
            found = sorted(p.glob("*.vcf"))
            if not found:
                print(f"Warning: no .vcf files in {p}")
            paths.extend(found)
        else:
            paths.append(p)
    if not paths:
        print("Error: no input VCF files")
        sys.exit(1)
    return paths


def main():
    parser = argparse.ArgumentParser(
        description="Import Apple Contacts vCard exports into Org notes.",
    )
    parser.add_argument(
        "inputs",
        nargs="+",
        help="One or more .vcf files or directories containing them.",
    )
    parser.add_argument(
        "-o", "--output-dir",
        default=str(DEFAULT_OUTPUT_DIR),
        help="Output directory for Org notes (default: %(default)s).",
    )
    parser.add_argument(
        "--no-archive",
        action="store_true",
        help="Do not archive contacts that are absent from this run. "
             "Use for partial / incremental imports against an "
             "existing dataset.",
    )
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    vcf_paths = _resolve_inputs(args.inputs)

    output_dir.mkdir(parents=True, exist_ok=True)

    manifest = load_manifest(output_dir)
    settings_hash = output_settings_hash()
    settings_changed = (
        manifest.get("output_settings_hash") is not None
        and manifest["output_settings_hash"] != settings_hash
    )
    if settings_changed:
        print("Output settings changed — rewriting all contacts.")

    # Parse every input VCF and union the results. A contact appearing
    # in multiple files (same UID) keeps its last-seen entry — newer
    # exports win.
    by_uid = {}
    extras = []
    for vcf_path in vcf_paths:
        these = parse_vcards(str(vcf_path))
        print(f"Parsed {len(these)} records from {vcf_path.name}")
        for c in these:
            uid = c.get("UID", "")
            if uid:
                by_uid[uid] = c
            else:
                # Should not happen post-2d-2 (synth-UID is always
                # injected for FN-bearing contacts) but kept defensive.
                extras.append(c)
    records = list(by_uid.values()) + extras

    # Split out group cards. `membership` maps each contact's UID to
    # the list of groups it belongs to. When the import contains no
    # group cards at all, membership is empty — we use that as a
    # signal not to touch filetags on existing contact files (so a
    # partial export doesn't blow away tags from an earlier full one).
    contacts, membership = split_contacts_and_groups(records)
    have_group_data = any(
        r.get("X-ADDRESSBOOKSERVER-KIND") == "group" for r in records
    )
    print(f"Total: {len(contacts)} unique contacts, "
          f"{sum(1 for r in records if r.get('X-ADDRESSBOOKSERVER-KIND') == 'group')} group cards "
          f"across {len(vcf_paths)} file(s)")

    created = 0
    updated = 0
    unchanged = 0
    skipped = 0
    renamed = 0
    archived = 0
    resurrected = 0
    errors = 0
    today = date.today().isoformat()

    for contact in contacts:
        fn = contact.get("FN", "").strip()
        if not fn:
            skipped += 1
            continue

        try:
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

                existing_pairs = parse_existing_drawer(existing_file)
                existing_id = next(
                    (v for k, v in existing_pairs if k == "ID"), None
                )
                org_id = existing_id or str(uuid.uuid4())
                existing_body = extract_body(existing_file)

                new_pairs = build_drawer_pairs(contact, org_id, vcard_uid)

                # Migration: pre-2c manifests have empty emitted_keys. The
                # safe heuristic is "anything in the drawer that we'd emit
                # today was put there by us" — that way hand-added keys
                # (which the current code wouldn't emit) are preserved.
                old_emitted = (prev or {}).get("emitted_keys") or []
                if not old_emitted and existing_pairs:
                    today_keys = {k for k, _ in new_pairs}
                    drawer_keys = {k for k, _ in existing_pairs}
                    old_emitted = list(today_keys & drawer_keys)

                merged_pairs = merge_drawer_pairs(
                    existing_pairs, old_emitted, new_pairs
                )

                # Filetags policy: when the import contains group cards we
                # trust membership data and emit `:contact:<group-slugs>:`.
                # When no group cards are present (partial export, etc.)
                # we preserve whatever non-contact, non-archived tags are
                # already on the file so a partial run doesn't blow them
                # away.
                if have_group_data:
                    filetags = membership.get(vcard_uid, [])
                else:
                    filetags = parse_existing_filetags(existing_file)

                note_content = format_org_note(
                    merged_pairs,
                    fn,
                    body=existing_body,
                    vcard_note=contact.get("NOTE", ""),
                    filetags=filetags,
                )
                with open(existing_file, "w", encoding="utf-8") as f:
                    f.write(note_content)
                updated += 1
                filepath = existing_file
                emitted_keys = [k for k, _ in new_pairs]
            else:
                org_id = str(uuid.uuid4())
                filetags = membership.get(vcard_uid, []) if have_group_data else []
                note_content, emitted_keys = build_org_note(
                    contact, org_id, vcard_uid, filetags=filetags
                )
                filepath = unique_filepath(output_dir, sanitize_filename(fn))

                with open(filepath, "w", encoding="utf-8") as f:
                    f.write(note_content)
                created += 1

            if vcard_uid:
                manifest["contacts"][vcard_uid] = make_entry(
                    str(filepath.relative_to(output_dir)),
                    chash,
                    emitted_keys=emitted_keys,
                )
        except Exception as exc:
            errors += 1
            _append_error(
                output_dir,
                f"Failed to process {fn}",
                exc,
                data={
                    "UID": contact.get("UID"),
                    "FN": fn,
                    "TEL": contact.get("TEL"),
                    "EMAIL": contact.get("EMAIL"),
                    "ORG": contact.get("ORG"),
                },
            )

    # Deletion sweep: any UID we tracked previously but didn't see in
    # this run is archived (unless already archived, or its file is
    # already gone — in which case we just drop the manifest entry).
    # Skipped entirely when --no-archive is passed for a partial import.
    if args.no_archive:
        if any(uid for uid in manifest["contacts"]
               if uid not in {c.get("UID", "") for c in contacts}):
            print("--no-archive: deletion sweep skipped; "
                  "manifest may have stale entries.")
    else:
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
            try:
                new_path = archive_contact(file_path, output_dir, today)
                entry["path"] = str(new_path.relative_to(output_dir))
                entry["archived"] = True
                archived += 1
            except Exception as exc:
                errors += 1
                _append_error(
                    output_dir,
                    f"Failed to archive {file_path.name}",
                    exc,
                    data={"UID": uid, "path": str(file_path)},
                )

    manifest["output_settings_hash"] = settings_hash
    save_manifest(output_dir, manifest)

    print(f"Done: {created} created, {updated} updated, "
          f"{unchanged} unchanged, {skipped} skipped, {renamed} renamed, "
          f"{archived} archived, {resurrected} resurrected, {errors} errors")
    print(f"Output: {output_dir}")
    if errors:
        print(f"Errors logged to: {output_dir / ERRORS_FILENAME}")
    print("Notes use plain Org IDs and should appear once org-node refreshes its cache.")


if __name__ == "__main__":
    main()
