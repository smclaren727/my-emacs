#!/usr/bin/env python3
"""CLI for importing vCard/CardDAV contacts into Org notes."""

import argparse
import sys
import uuid
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from urllib.parse import urlparse

from .authinfo import CredentialError, load_authinfo_credential
from .carddav import CardDAVClient, CardDAVError
from .lifecycle import archive_contact, resurrect_contact
from .manifest import (
    content_hash,
    load_manifest,
    make_entry,
    output_settings_hash,
    save_manifest,
)
from .orgnote import (
    build_drawer_pairs,
    build_org_note,
    extract_body,
    find_existing_note,
    format_org_note,
    merge_drawer_pairs,
    merge_filetags,
    normalize_filetags,
    parse_existing_drawer,
    parse_existing_filetags,
    sanitize_filename,
    unique_filepath,
)
from .vcard import parse_vcard_text, parse_vcards, split_contacts_and_groups


DEFAULT_OUTPUT_DIR = Path.home() / "All-The-Things" / "50-Resources" / "Contacts"
DEFAULT_CARDDAV_URL = "https://contacts.icloud.com"
ERRORS_FILENAME = "errors.org"
COMMANDS = {"import-vcf", "sync-carddav", "list-groups"}


@dataclass(frozen=True)
class SourceMeta:
    """Metadata for one upstream vCard resource."""

    etag: str = ""
    url: str = ""


def _append_error(output_dir, heading, exception, data=None):
    """Append a heading describing a per-contact failure to errors.org."""
    errors_path = output_dir / ERRORS_FILENAME
    is_new = not errors_path.exists()
    today = date.today().isoformat()

    chunk = []
    if is_new:
        chunk.append("#+title: Contact import errors")
        chunk.append("#+filetags: :contacts-errors:")
        chunk.append("")
    chunk.append(f"* {today} - {heading}")
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
    """Expand each positional argument into a list of .vcf file paths."""
    paths = []
    for raw in raw_inputs:
        p = Path(raw)
        if not p.exists():
            raise SystemExit(f"Error: {p} not found")
        if p.is_dir():
            found = sorted(p.glob("*.vcf"))
            if not found:
                print(f"Warning: no .vcf files in {p}")
            paths.extend(found)
        else:
            paths.append(p)
    if not paths:
        raise SystemExit("Error: no input VCF files")
    return paths


def _records_from_vcf_paths(vcf_paths):
    """Parse VCF files, de-duping records by UID with last-seen wins."""
    by_uid = {}
    extras = []
    for vcf_path in vcf_paths:
        these = parse_vcards(str(vcf_path))
        print(f"Parsed {len(these)} records from {vcf_path.name}")
        for record in these:
            uid = record.get("UID", "")
            if uid:
                by_uid[uid] = record
            else:
                extras.append(record)
    return list(by_uid.values()) + extras


def _records_from_dav_cards(cards):
    """Parse fetched CardDAV cards into records and UID metadata."""
    by_uid = {}
    extras = []
    metadata_by_uid = {}
    for card in cards:
        for record in parse_vcard_text(card.data):
            uid = record.get("UID", "")
            if uid:
                by_uid[uid] = record
                metadata_by_uid[uid] = SourceMeta(etag=card.etag, url=card.url)
            else:
                extras.append(record)
    return list(by_uid.values()) + extras, metadata_by_uid


def _member_uid(member_uri):
    return member_uri.replace("urn:uuid:", "").strip()


def _group_records(records):
    return [
        record for record in records
        if record.get("X-ADDRESSBOOKSERVER-KIND") == "group"
    ]


def _filter_records_by_groups(records, selectors):
    """Return only contacts and group cards selected by UID or name."""
    wanted = {selector.strip() for selector in selectors if selector.strip()}
    if not wanted:
        return records

    selected_groups = [
        group for group in _group_records(records)
        if group.get("UID") in wanted or group.get("FN") in wanted
    ]
    selected_contact_uids = {
        _member_uid(member)
        for group in selected_groups
        for member in group.get("_members", [])
        if _member_uid(member)
    }
    return [
        record for record in records
        if (
            record in selected_groups
            or (
                record.get("X-ADDRESSBOOKSERVER-KIND") != "group"
                and record.get("UID") in selected_contact_uids
            )
        )
    ]


def _source_unchanged(prev, chash, metadata):
    if not prev:
        return False
    if metadata.etag:
        return (
            prev.get("etag") == metadata.etag
            and prev.get("url") == metadata.url
        )
    return prev.get("content_hash") == chash


def import_records(
    records,
    output_dir,
    *,
    no_archive=False,
    force=False,
    metadata_by_uid=None,
    source_summary="",
):
    """Import parsed contact records into OUTPUT_DIR."""
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    metadata_by_uid = metadata_by_uid or {}

    manifest = load_manifest(output_dir)
    settings_hash = output_settings_hash()
    settings_changed = (
        manifest.get("output_settings_hash") is not None
        and manifest["output_settings_hash"] != settings_hash
    )
    if settings_changed:
        print("Output settings changed - rewriting all contacts.")

    contacts, membership = split_contacts_and_groups(records)
    group_count = sum(
        1 for record in records
        if record.get("X-ADDRESSBOOKSERVER-KIND") == "group"
    )
    have_group_data = group_count > 0
    suffix = f" {source_summary}" if source_summary else ""
    print(f"Total: {len(contacts)} unique contacts, {group_count} group cards{suffix}")

    created = updated = unchanged = skipped = 0
    renamed = archived = resurrected = errors = 0
    today = date.today().isoformat()

    for contact in contacts:
        fn = contact.get("FN", "").strip()
        if not fn:
            skipped += 1
            continue

        try:
            vcard_uid = contact.get("UID", "")
            chash = content_hash(contact)
            metadata = metadata_by_uid.get(vcard_uid, SourceMeta())
            prev = manifest["contacts"].get(vcard_uid) if vcard_uid else None
            desired_emitted_tags = (
                normalize_filetags(membership.get(vcard_uid, []))
                if have_group_data else None
            )
            tags_changed = (
                have_group_data
                and prev
                and (prev.get("emitted_tags") or []) != desired_emitted_tags
            )

            was_archived = bool(prev and prev.get("archived"))
            if was_archived:
                archived_path = output_dir / prev["path"]
                if archived_path.exists():
                    new_path = resurrect_contact(archived_path, output_dir)
                    prev["path"] = str(new_path.relative_to(output_dir))
                    resurrected += 1
                prev["archived"] = False

            if (not force
                    and not was_archived
                    and vcard_uid
                    and prev
                    and not settings_changed
                    and not tags_changed
                    and _source_unchanged(prev, chash, metadata)
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

                new_pairs = build_drawer_pairs(
                    contact,
                    org_id,
                    vcard_uid,
                    metadata.url,
                )

                old_emitted = (prev or {}).get("emitted_keys") or []
                if not old_emitted and existing_pairs:
                    today_keys = {k for k, _ in new_pairs}
                    drawer_keys = {k for k, _ in existing_pairs}
                    old_emitted = list(today_keys & drawer_keys)

                merged_pairs = merge_drawer_pairs(
                    existing_pairs,
                    old_emitted,
                    new_pairs,
                )

                if have_group_data:
                    new_filetags = desired_emitted_tags or []
                    existing_filetags = parse_existing_filetags(existing_file)
                    old_emitted_tags = (prev or {}).get("emitted_tags") or []
                    if not old_emitted_tags and existing_filetags:
                        new_filetag_set = set(new_filetags)
                        old_emitted_tags = [
                            tag for tag in existing_filetags
                            if tag in new_filetag_set
                        ]
                    filetags = merge_filetags(
                        existing_filetags,
                        old_emitted_tags,
                        new_filetags,
                    )
                    emitted_tags = new_filetags
                else:
                    filetags = parse_existing_filetags(existing_file)
                    emitted_tags = (prev or {}).get("emitted_tags") or []

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
                filetags = desired_emitted_tags if have_group_data else []
                emitted_tags = list(filetags)
                note_content, emitted_keys = build_org_note(
                    contact,
                    org_id,
                    vcard_uid,
                    filetags=filetags,
                    vcard_url=metadata.url,
                )
                filepath = unique_filepath(output_dir, sanitize_filename(fn))

                with open(filepath, "w", encoding="utf-8") as f:
                    f.write(note_content)
                created += 1

            if vcard_uid:
                manifest["contacts"][vcard_uid] = make_entry(
                    str(filepath.relative_to(output_dir)),
                    chash,
                    etag=metadata.etag or None,
                    url=metadata.url or None,
                    emitted_keys=emitted_keys,
                    emitted_tags=emitted_tags,
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

    if no_archive:
        seen = {c.get("UID", "") for c in contacts}
        if any(uid for uid in manifest["contacts"] if uid not in seen):
            print("--no-archive: deletion sweep skipped; manifest may have stale entries.")
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
                if not file_path.exists():
                    del manifest["contacts"][uid]
                continue
            if not file_path.exists():
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


def _credential_from_args(args):
    if args.username and args.password:
        return args.username, args.password
    if args.password and not args.username:
        raise SystemExit("--password requires --username")

    parsed = urlparse(args.server_url)
    machine = args.auth_machine or parsed.hostname or "contacts.icloud.com"
    try:
        credential = load_authinfo_credential(machine, args.username)
    except CredentialError as exc:
        raise SystemExit(str(exc)) from exc
    return credential.login, credential.password


def _carddav_client_from_args(args):
    username, password = _credential_from_args(args)
    return CardDAVClient(args.server_url, username, password)


def run_import_vcf(args):
    vcf_paths = _resolve_inputs(args.inputs)
    records = _records_from_vcf_paths(vcf_paths)
    import_records(
        records,
        args.output_dir,
        no_archive=args.no_archive,
        force=args.full_refresh,
        source_summary=f"across {len(vcf_paths)} file(s)",
    )


def run_sync_carddav(args):
    try:
        client = _carddav_client_from_args(args)
        cards = client.fetch_vcards(args.addressbook_url)
    except (CardDAVError, CredentialError) as exc:
        raise SystemExit(str(exc)) from exc

    records, metadata_by_uid = _records_from_dav_cards(cards)
    records = _filter_records_by_groups(records, args.group)
    import_records(
        records,
        args.output_dir,
        no_archive=args.no_archive,
        force=args.full_refresh,
        metadata_by_uid=metadata_by_uid,
        source_summary=f"from {len(cards)} CardDAV card(s)",
    )


def run_list_groups(args):
    try:
        client = _carddav_client_from_args(args)
        cards = client.fetch_vcards(args.addressbook_url)
    except (CardDAVError, CredentialError) as exc:
        raise SystemExit(str(exc)) from exc

    records, _ = _records_from_dav_cards(cards)
    for group in _group_records(records):
        members = len(group.get("_members", []))
        print(f"{group.get('UID', '')}\t{group.get('FN', '')}\t{members}")


def _add_common_output_options(parser):
    parser.add_argument(
        "-o", "--output-dir",
        default=str(DEFAULT_OUTPUT_DIR),
        help="Output directory for Org notes (default: %(default)s).",
    )
    parser.add_argument(
        "--no-archive",
        action="store_true",
        help="Do not archive contacts absent from this run.",
    )
    parser.add_argument(
        "--full-refresh",
        action="store_true",
        help="Rewrite all contacts even when upstream state is unchanged.",
    )


def _add_carddav_options(parser):
    parser.add_argument(
        "--server-url",
        default=DEFAULT_CARDDAV_URL,
        help="CardDAV server URL (default: %(default)s).",
    )
    parser.add_argument(
        "--auth-machine",
        default=None,
        help="authinfo machine name (default: hostname from --server-url).",
    )
    parser.add_argument("--username", default=None, help="CardDAV username.")
    parser.add_argument(
        "--password",
        default=None,
        help="CardDAV password. Prefer authinfo for real use.",
    )
    parser.add_argument(
        "--addressbook-url",
        default=None,
        help="Specific address book collection URL.",
    )


def build_parser():
    parser = argparse.ArgumentParser(
        description="Import CardDAV or vCard contacts into Org notes.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    import_vcf = subparsers.add_parser(
        "import-vcf",
        help="Import one or more .vcf files or directories.",
    )
    import_vcf.add_argument(
        "inputs",
        nargs="+",
        help="One or more .vcf files or directories containing them.",
    )
    _add_common_output_options(import_vcf)
    import_vcf.set_defaults(func=run_import_vcf)

    sync = subparsers.add_parser(
        "sync-carddav",
        help="Fetch contacts from CardDAV and write Org notes.",
    )
    _add_common_output_options(sync)
    _add_carddav_options(sync)
    sync.add_argument(
        "--group",
        action="append",
        default=[],
        help="Only sync contacts in a group UID or exact group name. Repeatable.",
    )
    sync.set_defaults(func=run_sync_carddav)

    list_groups = subparsers.add_parser(
        "list-groups",
        help="List CardDAV groups as UID, name, member count.",
    )
    _add_carddav_options(list_groups)
    list_groups.set_defaults(func=run_list_groups)

    return parser


def build_legacy_parser():
    parser = argparse.ArgumentParser(
        description="Import Apple Contacts vCard exports into Org notes.",
    )
    parser.add_argument(
        "inputs",
        nargs="+",
        help="One or more .vcf files or directories containing them.",
    )
    _add_common_output_options(parser)
    parser.set_defaults(func=run_import_vcf)
    return parser


def main(argv=None):
    raw_args = list(sys.argv[1:] if argv is None else argv)
    if raw_args and raw_args[0] in COMMANDS:
        parser = build_parser()
    elif raw_args and raw_args[0] in ("-h", "--help"):
        parser = build_parser()
    else:
        parser = build_legacy_parser()
    args = parser.parse_args(raw_args)
    args.func(args)


if __name__ == "__main__":
    main()
