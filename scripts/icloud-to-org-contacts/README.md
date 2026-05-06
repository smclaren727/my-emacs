# icloud-to-org-contacts

Import Apple/iCloud or generic CardDAV contacts into Org-mode notes.

The tool can import local `.vcf` exports or sync read-only from a
CardDAV server. Each contact becomes one `.org` file with an Org
property drawer, a stable `:ID:`, and contact filetags.

## Features

- Import one `.vcf` file, many `.vcf` files, or a directory of `.vcf`
  files.
- Sync contacts from iCloud, Nextcloud, or another CardDAV server.
- Write one Org note per contact using properties instead of embedded
  raw vCard data.
- Preserve user-added drawer properties, body text, and filetags across
  re-imports.
- Archive contacts that disappear from a full sync and restore them if
  they return.

## Install

From this directory:

```sh
python3 -m venv .venv
. .venv/bin/activate
python3 -m pip install -e .
```

For development and tests:

```sh
python3 -m pip install -e ".[test]"
python3 -m pytest
```

The install provides the `icloud-to-org-contacts` command.

## Configure CardDAV Credentials

Credentials are read from `~/.authinfo.gpg` or `~/.authinfo`. For
iCloud, use your Apple ID and an app-specific password:

```text
machine contacts.icloud.com login you@example.com password app-specific-password
```

Plain `~/.authinfo` works, but encrypted `~/.authinfo.gpg` is strongly
preferred.

## Quick Start

Import a local vCard export:

```sh
icloud-to-org-contacts import-vcf ~/Downloads/contacts.vcf -o ~/notes/Contacts
```

Sync from iCloud/CardDAV:

```sh
icloud-to-org-contacts sync-carddav -o ~/notes/Contacts
```

List available CardDAV groups:

```sh
icloud-to-org-contacts list-groups
```

Use `--help` on the main command or any subcommand to see all options:

```sh
icloud-to-org-contacts --help
icloud-to-org-contacts sync-carddav --help
```

## Common Options

```sh
# Sync from a non-iCloud CardDAV endpoint
icloud-to-org-contacts sync-carddav \
  --server-url https://cloud.example.com/remote.php/dav

# Use a specific authinfo machine name
icloud-to-org-contacts sync-carddav --auth-machine contacts.icloud.com

# Rewrite every managed contact
icloud-to-org-contacts sync-carddav --full-refresh

# Import a one-off VCF without archiving missing contacts
icloud-to-org-contacts import-vcf one-contact.vcf --no-archive

# Sync only selected CardDAV groups by exact name or UID
icloud-to-org-contacts sync-carddav --group Family --group group-uid
```

`--username` and `--password` are available for diagnostics and tests,
but authinfo is preferred for real use so secrets do not appear in shell
history.

## Output

A generated contact note looks like this:

```org
:PROPERTIES:
:ID: 4c6f4ea6-df6c-4d27-bdcf-7f3126c4a7c5
:VCARD_UID: contact-upstream-id
:VCARD_URL: https://contacts.icloud.com/...
:EMAIL_WORK: alice@example.com
:PHONE_CELL: +15550001
:COMPANY: Acme Corp
:END:
#+title: Alice Smith
#+filetags: :contact:
```

The importer stores sync state in `.import-state.json` in the output
directory. Do not edit that file unless you intend to reset or repair
import state.

See [docs/reference.md](docs/reference.md) for the full output contract,
manifest details, archive behavior, Apple Contacts quirks, and project
architecture.

## Emacs

The parent Emacs configuration includes `modules/my-contacts.el`, which
exposes these commands:

```text
M-x my-contacts-import-vcf
M-x my-contacts-sync-carddav
M-x my-contacts-list-carddav-groups
```

That wrapper prefers an installed `icloud-to-org-contacts` executable
and falls back to the checkout wrapper. Output appears in the
`*contacts-import*` buffer.

Some Emacs configurations hide Org property drawers by default. If a
generated note looks empty, reveal drawers with your normal Org folding
commands or with the helper from this Emacs config:

```text
M-x my-org-show-property-drawers
```

## Limits

- Sync is one-way into Org; it never writes contact changes back to
  CardDAV.
- Photos are intentionally dropped.
- Related names are plain `RELATED_*` properties, not automatic Org
  links.
- The full vCard note body is written only on first import. Later
  upstream note changes update the one-line `:NOTE:` property summary.
