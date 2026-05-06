# icloud-to-org-contacts Reference

This document keeps the details that are useful for maintainers and
advanced users without making the README too heavy.

## Output Contract

Each contact is written to one `.org` file named from the sanitized full
name. The first block is a top-level Org property drawer:

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

Important invariants:

- `:ID:` is always emitted for new contacts and preserved on update.
- `:VCARD_UID:` is used to match an existing note to an upstream
  contact.
- `:VCARD_URL:` is emitted for CardDAV resources when available.
- Property values are always written as one physical line.
- Raw vCard payloads are never embedded in Org source or example blocks.
- Drawer order is stable: identity, contact methods, IM/social/related,
  employment, location, date fields, then note summary.

## Merge Behavior

The importer tracks the drawer keys and filetags it emitted on the
previous run. On update, it performs a simple 3-way merge:

- importer-owned values are replaced with the latest upstream values;
- user-added drawer keys are preserved;
- user-added body text is preserved;
- user-added filetags are preserved;
- stale importer-owned group tags are removed when group data is
  available.

The full vCard `NOTE` is written into the body only when a note has no
body yet. After that, upstream note changes update the `:NOTE:` property
summary, leaving user-owned body text alone.

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

The manifest powers dirty checks, deletion detection, CardDAV ETag
checks, archive/resurrection behavior, and 3-way metadata merges.

When the Org output shape changes, bump `OUTPUT_SCHEMA_VERSION` in
`src/icloud_to_org_contacts/manifest.py`. That forces managed contacts
through a rewrite on the next run.

## Archive Behavior

For full imports and CardDAV syncs, a managed contact that no longer
appears upstream is moved to `<output_dir>/Archive/` and marked archived
in the manifest.

If the contact appears again later, it is moved back into the main
output directory and updated in place.

Use `--no-archive` for one-off or partial imports where missing contacts
should not be treated as deletions.

## Apple And CardDAV Notes

The importer handles several Apple Contacts behaviors:

- macOS `.vcf` exports that omit `UID` get a synthetic `synth-<hash>`
  identity based on stable contact fields;
- CardDAV sync uses upstream UIDs, resource URLs, and ETags when
  available;
- folded vCard lines and comma-style `TYPE=INTERNET,WORK` parameters
  are parsed with `vobject`;
- Apple `itemN.` grouped fields preserve custom labels such as Spouse
  or Bestie;
- Apple's `1604-` omit-year birthday sentinel becomes Org's `--MM-DD`
  shape;
- address book group cards become Org filetags;
- `xmpp:` and `x-apple:` prefixes are stripped from IMPP/social values;
- volatile fields such as `REV`, `PRODID`, `PHOTO`, and `VERSION` are
  ignored for content-hash dirty checks.

Synthetic UIDs from `.vcf` exports can change if the name, structured
name, phone list, or email list changes. CardDAV sync avoids that
limitation by using server-side identity.

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

Module responsibilities:

- `authinfo.py` reads credentials from `.authinfo.gpg` or `.authinfo`.
- `carddav.py` is a read-only CardDAV client.
- `cli.py` owns command parsing and import orchestration.
- `lifecycle.py` moves contacts into and out of `Archive/`.
- `manifest.py` owns `.import-state.json` and output schema hashing.
- `orgnote.py` owns the Org note format and drawer/filetag merges.
- `vcard.py` parses and normalizes vCard data.

The importer writes only under the configured output directory:

- contact `.org` notes;
- `.import-state.json`;
- `errors.org`;
- `Archive/`.

## Privacy And Testing

Real contact exports are personal data. Do not commit `.vcf` files,
generated contact notes, manifests, error logs, authinfo files, or
passwords.

Tests use synthetic vCards and mocked CardDAV responses:

```sh
python3 -m pip install -e ".[test]"
python3 -m pytest
```

Before handing off changes:

```sh
python3 -m pytest
git diff --check
```
