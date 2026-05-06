# icloud-to-org-contacts

Import Apple/iCloud or generic CardDAV contacts into Org-mode contact
notes. The project is inspired by
[obsidian-icloud-contacts](https://github.com/Trulsaa/obsidian-icloud-contacts),
but uses Org property drawers, filetags, and `org-id` instead of
Obsidian frontmatter and wikilinks.

The importer supports both local `.vcf` exports and live read-only
CardDAV sync. It never embeds raw vCard payloads in Org files; parsed
contact fields become drawer properties, and server metadata stays in
the manifest except for the visible `:VCARD_URL:` property.

## Features

- Import single `.vcf` files, multi-contact `.vcf` files, or directories
  of `.vcf` files.
- Sync read-only contacts from iCloud, Nextcloud, or another CardDAV
  server.
- Emit one `<sanitized-name>.org` per contact with stable Org property
  drawers and `#+filetags:`.
- Preserve user-owned drawer keys, body content, and hand-added
  filetags across re-imports.
- Track per-contact content hashes, CardDAV ETags, URLs, emitted
  drawer keys, and emitted tags in `.import-state.json`.
- Archive contacts absent from a full run into `<output_dir>/Archive/`
  with `:STATUS: archived`; resurrect them if they return.
- Log per-contact failures to `<output_dir>/errors.org`.

## Install

From this directory:

```sh
python3 -m pip install -e ".[test]"
```

That installs the `icloud-to-org-contacts` console command and the test
dependencies. For runtime-only use, `python3 -m pip install -e .` is
enough.

## Usage

### VCF Import

```sh
# Single file
icloud-to-org-contacts import-vcf /path/to/contacts.vcf

# Multiple files
icloud-to-org-contacts import-vcf file1.vcf file2.vcf

# Directory of .vcf files, non-recursive
icloud-to-org-contacts import-vcf ~/Downloads/icloud-export/

# Custom output dir
icloud-to-org-contacts import-vcf contacts.vcf -o ~/notes/contacts/

# Partial import: do not archive contacts missing from this run
icloud-to-org-contacts import-vcf one-new-contact.vcf --no-archive
```

The legacy checkout wrapper still works after installing dependencies:

```sh
python3 vcf-to-org-contacts.py /path/to/contacts.vcf
```

### CardDAV Sync

Credentials are read from `~/.authinfo.gpg` or `~/.authinfo`. For iCloud,
use an Apple ID plus an app-specific password:

```text
machine contacts.icloud.com login you@example.com password app-specific-password
```

Then sync:

```sh
icloud-to-org-contacts sync-carddav
```

Useful options:

```sh
# Custom server, for example Nextcloud
icloud-to-org-contacts sync-carddav --server-url https://cloud.example.com/remote.php/dav

# Use a specific authinfo machine name
icloud-to-org-contacts sync-carddav --auth-machine contacts.icloud.com

# Rewrite all contacts even if ETags match
icloud-to-org-contacts sync-carddav --full-refresh

# Restrict to selected group names or UIDs; repeatable
icloud-to-org-contacts sync-carddav --group Family --group group-uuid

# List available groups as UID, name, member count
icloud-to-org-contacts list-groups
```

`--username` and `--password` exist for testing or one-off use, but
authinfo is preferred so secrets do not appear in shell history.

### Emacs

`modules/my-contacts.el` adds:

```text
SPC SPC m i   import VCF file/directory
SPC SPC m I   sync CardDAV contacts
SPC SPC m G   list CardDAV groups
```

The module prefers an installed `icloud-to-org-contacts` executable and
falls back to the checkout wrapper. Output appears in `*contacts-import*`.

Key variables:

- `my-contacts-output-dir`
- `my-contacts-carddav-server-url`
- `my-contacts-carddav-auth-machine`
- `my-contacts-carddav-groups`

## Output Format

Each contact becomes one `.org` file:

```org
:PROPERTIES:
:ID: <org-id-uuid>
:VCARD_UID: <real-or-synth-uid>
:VCARD_URL: https://contacts.icloud.com/...
:NICKNAME: Alex
:EMAIL_HOME: alice@example.com
:EMAIL_WORK: alice@work.com
:PHONE_CELL: +15550001
:IM_SKYPE: alice-skype
:SOCIAL_TWITTER: https://twitter.com/alice
:RELATED_SPOUSE: Bob Smith
:COMPANY: Acme Corp
:DEPARTMENT: Platform
:ROLE: Engineer
:ADDRESS_HOME: 100 Main St, Springfield, IL, 62701, USA
:URL_HOME: https://alice.example.com
:BIRTHDAY: 1985-04-12
:DATE_ANNIVERSARY: 2010-06-15
:NOTE: One-line flattened summary of the vCard NOTE
:END:
#+title: Alice Smith
#+filetags: :contact:family:work:

body text is user-owned after first import
```

Drawer order is stable: identity, contact methods, IM/social/related,
employment, location, date fields, and NOTE summary.

## Architecture

```text
scripts/icloud-to-org-contacts/
  pyproject.toml
  vcf-to-org-contacts.py
  src/icloud_to_org_contacts/
    authinfo.py
    carddav.py
    cli.py
    lifecycle.py
    manifest.py
    orgnote.py
    vcard.py
  tests/
```

The CardDAV client is read-only. The importer writes only Org notes,
`errors.org`, `Archive/`, and `.import-state.json` under the configured
output directory.

## Manifest

State lives at `<output_dir>/.import-state.json`:

```json
{
  "version": 1,
  "last_run": "2026-05-05T19:24:04+00:00",
  "output_settings_hash": "sha256...",
  "contacts": {
    "<vcard_uid>": {
      "path": "alice-smith.org",
      "content_hash": "sha256...",
      "etag": "\"abc123\"",
      "url": "https://contacts.icloud.com/...",
      "emitted_keys": ["ID", "VCARD_UID", "EMAIL_HOME"],
      "emitted_tags": ["family"],
      "archived": false
    }
  }
}
```

`emitted_keys` and `emitted_tags` power the 3-way merges that preserve
user-owned Org metadata while allowing the importer to remove stale
fields or group tags it previously emitted.

## Apple Quirks Handled

- Missing UIDs in macOS `.vcf` exports get a synthetic `synth-<hash>`
  UID from stable contact fields.
- Folded vCard lines and comma-style `TYPE=INTERNET,WORK` parameters
  are parsed via `vobject`.
- Apple `itemN.` grouped fields preserve custom labels such as Spouse
  or Bestie.
- Apple's `1604-` omit-year sentinel becomes Org's `--MM-DD` shape.
- Address Book group cards become contact filetags.
- `xmpp:` and `x-apple:` prefixes are stripped from IMPP/social values.
- Volatile fields such as `REV`, `PRODID`, `PHOTO`, and `VERSION` are
  ignored for content-hash dirty checks.

## Known Limits

- The sync is one-way into Org; it does not write changes back to
  CardDAV.
- Synthetic UIDs from VCF exports can change if the name, structured
  name, phone list, or email list changes. CardDAV URLs/ETags avoid
  this for live sync.
- Photos are intentionally dropped.
- Related names are plain `RELATED_*` properties, not automatic
  `org-id` links.
- The full vCard NOTE is written into the body on first import only;
  later upstream NOTE changes update the `:NOTE:` drawer summary.

## Testing

```sh
python3 -m pip install -e ".[test]"
python3 -m pytest
```

Tests use synthetic vCards and mocked CardDAV responses so personal
contact data never needs to be committed.
