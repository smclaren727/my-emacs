# AGENTS.md - icloud-to-org-contacts

This file gives local instructions for agents working in this
subproject. The parent Emacs configuration guide still applies, but
this directory is a standalone Python package with its own boundaries.

## Project Purpose

`icloud-to-org-contacts` imports Apple/iCloud or generic CardDAV
contacts into one Org file per contact. It is inspired by
`obsidian-icloud-contacts`, but writes Org property drawers, filetags,
and `org-id` compatible `:ID:` values instead of Obsidian frontmatter.

The sync is read-only with respect to CardDAV. It never writes changes
back to iCloud.

## Read First

- `README.md` for user-facing behavior, install commands, output shape,
  and known limits.
- `pyproject.toml` for package metadata, dependencies, console scripts,
  and pytest configuration.
- `tests/` before changing import behavior; tests use synthetic data and
  should remain free of personal contacts.

## Repository Boundary

This project lives under the larger Emacs config repo at:

```text
~/.emacs.d/scripts/icloud-to-org-contacts/
```

Keep most changes inside this directory. Only edit the parent Emacs
config when the task explicitly involves the wrapper module
`modules/my-contacts.el` or integration behavior.

`CLAUDE.md` in this directory is intentionally only:

```text
@AGENTS.md
```

Do not add more content to `CLAUDE.md`; update this file instead.

## Architecture

```text
pyproject.toml
vcf-to-org-contacts.py          compatibility wrapper
src/icloud_to_org_contacts/
  authinfo.py                   authinfo/.authinfo.gpg credential loading
  carddav.py                    read-only CardDAV client
  cli.py                        argparse commands and import orchestration
  lifecycle.py                  archive/resurrect contact files
  manifest.py                   .import-state.json and dirty checks
  orgnote.py                    Org file format and drawer merging
  vcard.py                      vCard parsing and value normalization
tests/
```

Key ownership rules:

- `vcard.py` parses vCard data into normalized dictionaries.
- `orgnote.py` owns the on-disk Org note format.
- `manifest.py` owns `.import-state.json` schema and output schema
  versioning.
- `carddav.py` should stay read-only and avoid mutating remote data.
- `cli.py` coordinates parsing, filtering, writes, archives, and
  manifest updates.

## Output Contract

Generated contact files must remain valid Org files with a top-level
property drawer:

```org
:PROPERTIES:
:ID: <org-id-uuid>
:VCARD_UID: <upstream uid>
:VCARD_URL: <carddav resource url>
:EMAIL_WORK: person@example.com
:PHONE_CELL: +15550001
:END:
#+title: Contact Name
#+filetags: :contact:
```

Important invariants:

- Always emit `:ID:` for new contacts.
- Preserve an existing `:ID:` when updating a managed contact.
- Emit `:VCARD_UID:` for identity matching.
- Emit `:VCARD_URL:` for CardDAV resources when available.
- Property drawer values must be one physical line.
- Do not embed raw vCard data in Org source/example blocks.
- Preserve user-owned drawer keys, body text, and hand-added filetags.
- Use `OUTPUT_SCHEMA_VERSION` in `manifest.py` to force rewrites when
  the Org output format changes.

## Credentials And Privacy

- Real `.vcf` exports are personal data. Do not commit them.
- Do not commit `.authinfo`, `.authinfo.gpg`, app-specific passwords,
  generated contact notes, `.import-state.json`, or `errors.org`.
- Use synthetic fixtures in tests.
- Keep CardDAV tests mocked; do not add network-dependent tests.
- Prefer authinfo for real credentials. `--username` and `--password`
  exist for diagnostics and tests only.

## Commands

Install for development:

```sh
python3 -m pip install -e ".[test]"
```

Run tests:

```sh
python3 -m pytest
```

Common CLI commands:

```sh
icloud-to-org-contacts import-vcf /path/to/contacts.vcf
icloud-to-org-contacts sync-carddav
icloud-to-org-contacts sync-carddav --full-refresh
icloud-to-org-contacts list-groups
```

The parent Emacs wrapper exposes interactive commands by `M-x`:

```text
my-contacts-import-vcf
my-contacts-sync-carddav
my-contacts-list-carddav-groups
```

These commands intentionally do not have leader bindings unless a
future task explicitly asks for them.

## Coding Guidelines

- Use Python 3.11+ compatible code.
- Prefer small pure functions for parsing and formatting.
- Keep filesystem writes concentrated in CLI/lifecycle/manifest code.
- Avoid broad refactors when fixing one parser or output issue.
- Add or update focused tests for any behavior change.
- Use standard parsers (`vobject`, XML parsing helpers) instead of ad
  hoc string parsing when practical.
- Keep generated fixtures synthetic and minimal.

## Validation Before Handoff

For code changes, run:

```sh
python3 -m pytest
git diff --check
```

For docs-only changes, `git diff --check` is usually enough.

When changing Org output shape, also inspect a generated note or add a
test that proves the property drawer remains valid.
