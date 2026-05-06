# icloud-to-org-contacts

Imports Apple Contacts vCard exports into Org-mode contact notes
under `~/All-The-Things/50-Resources/Contacts/`. Inspired by the
[obsidian-icloud-contacts](https://github.com/Trulsaa/obsidian-icloud-contacts)
plugin but adapted for org-mode idioms (property drawers + filetags +
`org-id` rather than YAML frontmatter + Obsidian wikilinks).

Currently driven by `.vcf` exports from Apple Contacts; designed so
the eventual CardDAV cutover (Tier 6, deferred) reuses the same
modules and on-disk format.

## Scope

**Does:**

- Parse macOS-exported `.vcf` files (single contact, multi-contact
  combined, or directories of them).
- Emit one `<sanitized-name>.org` per contact with a fully-populated
  property drawer.
- Round-trip safely: re-importing preserves user-added drawer keys,
  body content, and filetags (within stated limits).
- Track per-contact state so unchanged contacts skip work.
- Move deleted-upstream contacts into `<output_dir>/Archive/` with
  `:STATUS: archived` markers; restore on return.
- Surface per-contact failures to `<output_dir>/errors.org` instead
  of crashing the whole run.

**Does not (yet):**

- Talk to iCloud directly (no CardDAV — Tier 6).
- Resolve contact-to-contact relationships into `org-id` links
  (Tier 4a, deliberately skipped).
- Cache the raw vCard payload in the org file (re-evaluated and
  dropped — see *Skipped / deferred* below).

## Architecture

```
scripts/icloud-to-org-contacts/
  pyproject.toml             — package metadata, console script, test config
  vcf-to-org-contacts.py     — compatibility wrapper for checkout usage
  src/icloud_to_org_contacts/
    cli.py                   — thin CLI orchestrating the import
    vcard.py                 — parse vCard text → list of contact dicts
    orgnote.py               — build / merge org file content
    lifecycle.py             — archive + resurrect transitions
    manifest.py              — JSON state file (.import-state.json)
  tests/                     — pytest coverage for import behavior
  .gitignore                 — *.vcf (sample data never committed)
```

Five small modules plus a CLI. Pure-function boundaries between
them; no shared mutable state; no class hierarchies.

## Usage

### From the command line

```sh
# From a checkout
python3 -m pip install -e ".[test]"

# Single file
python3 vcf-to-org-contacts.py /path/to/contacts.vcf

# Or, after install
icloud-to-org-contacts /path/to/contacts.vcf

# Multiple positionals
python3 vcf-to-org-contacts.py file1.vcf file2.vcf

# Directory of .vcf files (non-recursive glob)
python3 vcf-to-org-contacts.py ~/Downloads/icloud-export/

# Custom output dir
python3 vcf-to-org-contacts.py contacts.vcf -o ~/notes/contacts/

# Partial / incremental import — don't archive contacts missing
# from this run
python3 vcf-to-org-contacts.py one-new-contact.vcf --no-archive
```

### From Emacs

```
SPC SPC m i      ; (or C-c u m i)
```

Bound by `modules/my-contacts.el`. Prompts for a path (file or
directory) via `read-file-name`, runs the script async, surfaces
output in `*contacts-import*`. Gated by `my-flag-contacts` (default
`t`).

Defaults:

- script: `<repo>/scripts/icloud-to-org-contacts/vcf-to-org-contacts.py`
- output: `<my-notes-directory>/50-Resources/Contacts/`

## Output format

Each contact becomes one `.org` file:

```
:PROPERTIES:
:ID: <org-id-uuid>
:VCARD_UID: <real-or-synth-uid>
:NICKNAME: Alex
:EMAIL_HOME: alice@example.com
:EMAIL_WORK: alice@work.com
:PHONE_CELL: +15550001
:IM_SKYPE: alice-skype
:SOCIAL_TWITTER: https://twitter.com/alice
:COMPANY: Acme Corp
:ROLE: Engineer
:ADDRESS_HOME: 100 Main St, Springfield, IL, 62701, USA
:URL_HOME: https://alice.example.com
:BIRTHDAY: 1985-04-12
:DATE_ANNIVERSARY: 2010-06-15
:NOTE: One-line flattened summary of the vCard NOTE
:END:
#+title: Alice Smith
#+filetags: :contact:family:work:

(body — vCard NOTE on first import; user-owned thereafter)
```

Drawer order is stable: identity, contact methods, IM/social,
employment, location, date fields, NOTE summary.

## What's complete

18 commits, all on local `main`, none pushed. Each tier is one or
more atomic commits.

| Tier | Commit  | Slice |
|------|---------|-------|
| 0    | c9e02c5 | scaffold (split parser/builder/CLI) |
| 1    | ab534ab | manifest + content-hash skip |
| 2a   | a531ace | filename follows title on rename |
| 2b   | 29e68b6 | archive on deletion / resurrect on return |
| 2c   | bc256df | 3-way drawer merge preserves user-added keys |
| 2d-1 | 4a53031 | strip Apple's `itemN.` group prefix |
| 2d-2 | fbaf57e | synthetic UID fallback when vCard lacks one |
| 2d-3 | e06bba9 | multi-input + `--no-archive` flag |
| 3.3  | 218ae76 | `:NICKNAME:` + FN fallback |
| 3.6  | 7b04605 | mirror vCard NOTE as `:NOTE:` drawer property |
| 3.1  | 3870e3c | X-ABLABEL custom labels (Spouse, Bestie, etc.) |
| 3.2  | ef21b6c | URL field |
| 3.4  | 990bdeb | X-ABDATE anniversaries / custom dates |
| 3.5  | 14aa050 | IMPP and X-SOCIALPROFILE |
| 4b   | e0da217 | group cards → filetags |
| 5a   | ffa8bec | per-contact errors → `errors.org` |
| 5b   | 17a5813 | Emacs leader binding (`m i`) |

## What's left

### Tier 6 — CardDAV cutover (largest remaining piece)

Replace the VCF input path with live iCloud sync via the CardDAV
protocol (or against Nextcloud, which speaks the same protocol).

Revised design (simpler than originally planned):

- Authentication via `~/.authinfo.gpg` using an Apple ID +
  app-specific password (mirrors the existing mail-sync pattern).
- Contacts pulled as `{url, etag, data}` triples from
  `https://contacts.icloud.com/`.
- Real Apple UIDs replace the `synth-XXXX` fallback for any contact
  that already has one. Existing files keep their `synth-` UIDs;
  no automatic migration.
- ETag-based dirty check: if `etag` matches the manifest, skip even
  the parse step.
- `:VCARD_URL:` becomes a real drawer property (was reserved but
  unpopulated in earlier tiers).
- **No raw-vCard caching** in the org file (initially planned as a
  `#+begin_src vcard` block; dropped — see *Skipped*).

Estimated 3-5 commits depending on how cleanly the auth + fetch
+ merge integration goes.

### Smaller polish work (not strictly tiered)

- **Filetags 3-way merge.** Tier 4b clobbers hand-added filetags
  on a *full* import. A `manifest.emitted_tags` field mirroring
  `emitted_keys` would solve this — same pattern as the drawer-key
  preservation in Tier 2c.
- **launchd timer.** Once CardDAV lands, an hourly sync job at
  `etc/com.seanmclaren.contacts-sync.plist` would mirror the
  existing mail-sync setup.

## Skipped / deferred

### Tier 4a — related-names as `org-id` links

The Obsidian plugin emits `[[Wikilinks]]` for `X-ABRELATEDNAMES`
entries to populate its graph. The org-mode equivalent would be
`[[id:<uuid>][Name]]`.

**Skipped at user direction.** Not every org-mode contacts setup
treats contact files as wiki nodes; this would impose graph
behavior that doesn't necessarily fit. Easy to add later as a
small slice if the workflow evolves.

### Raw vCard embedded in the org file

Initially planned for Tier 6 as a `#+begin_src vcard ... #+end_src`
block at file end (mirroring how the Obsidian plugin caches the
full vCard JSON in frontmatter).

**Dropped on review.** The arguments for storing it didn't hold up:

- Properties already extract every field Apple emits.
- Schema-change rewrites can re-fetch from CardDAV (one HTTP
  request per contact, parallelizable, cheap).
- ETag-based dirty checking belongs in the manifest, not the org
  file.
- Org property drawers are for structured key-value metadata,
  not multi-KB serialized blobs.

Tier 6 will instead track `etag`/`url` in the manifest internally
and emit only `:VCARD_URL:` as a user-visible drawer property.

## Known limitations

These are intentional trade-offs, not bugs to fix imminently.

1. **Synthetic UIDs are fragile.** When Apple's export omits a real
   UID (consistent in macOS 15.7.x for non-iCloud-synced contacts),
   we hash `FN + N + sorted phones + sorted emails` into a
   `synth-<hex>` UID. If any of those four change between imports,
   the contact is re-detected as new — old file archived, new file
   created. Only fully solved by Tier 6.

2. **Filetag clobbering on full imports.** When a run includes group
   cards (`have_group_data == True`), filetags are rewritten from
   membership data. Hand-added tags on existing files are lost.
   Partial imports (no group cards) preserve existing filetags;
   that's the current escape hatch. A proper 3-way merge for
   filetags is one of the polish items above.

3. **Apple group cards aren't always exported.** Selected-contact
   exports omit `X-ADDRESSBOOKSERVER-KIND:group` records. To get
   group memberships into filetags, either select the group itself
   in the Apple Contacts sidebar before exporting, or wait for
   Tier 6 (CardDAV pulls groups unconditionally).

4. **`PHOTO` data is dropped.** Base64-encoded photos (`ENCODING=b`)
   are recognized and skipped during parse. Not extracted to a
   sidecar file. No plan to add — adds binary state, complicates
   git, marginal value.

5. **Body text vs. drawer NOTE divergence.** The vCard `NOTE` is
   written into the body on *first import only*; updates leave the
   body alone but refresh the `:NOTE:` drawer property (truncated
   to 200 chars, newlines flattened to ` / `). If the upstream NOTE
   changes meaningfully after first import, the body and drawer
   will disagree and the drawer is canonical for the current
   upstream value.

## Apple-specific quirks handled

Discovered while testing against real macOS 15.7.3 exports.

- **Missing UIDs.** macOS-exported `.vcf` files often omit the
  `UID:` line entirely. Tier 2d-2's synth-UID fills the gap.

- **`itemN.` group prefix.** Apple groups a property with its
  metadata fields (X-ABLABEL, X-ABADR, X-APPLE-SUBADMINISTRATIVE-
  AREA) by sharing an `itemN.` prefix. Pre-Tier 2d-1 we silently
  dropped any property carrying that prefix — which included every
  street address with a country code (the default). Now stripped
  during parse and exposed via `contact["_groups"]`.

- **`_$!<...>!$_` label wrapping.** Apple's standard labels are
  wrapped in this sentinel. Tier 3.1 strips it.

- **`X-APPLE-OMIT-YEAR=1604`.** Apple's year-omitted-birthday
  sentinel uses `1604-` as the year prefix. We normalize to org's
  `--MM-DD` shape; same logic handles X-ABDATE entries (Tier 3.4).

- **`X-ADDRESSBOOKSERVER-*` group cards and members.** Apple
  represents groups as their own vCards with `KIND:group` and
  multiple `MEMBER` lines pointing at member UIDs. Tier 4b reads
  these into a `{uid: [groups]}` index.

- **`xmpp:` / `x-apple:` URI schemes** on IMPP and
  X-SOCIALPROFILE values. Tier 3.5 strips them so the value is
  the bare handle / URL.

- **Volatile fields in re-exports.** `REV:`, `PRODID:`, `PHOTO:`,
  and `VERSION:` change on every Apple re-export even when the
  contact's substance hasn't changed. The content-hash dirty check
  ignores these (Tier 1).

## Manifest

State persisted as `<output_dir>/.import-state.json`. Atomic
write (temp file + rename). Format:

```json
{
  "version": 1,
  "last_run": "2026-05-05T19:24:04+00:00",
  "output_settings_hash": "sha256...",
  "contacts": {
    "<vcard_uid>": {
      "path": "alice-smith.org",
      "content_hash": "sha256...",
      "emitted_keys": ["ID", "VCARD_UID", "EMAIL_HOME", ...],
      "etag": null,
      "url": null,
      "archived": false
    }
  }
}
```

- `path` is relative to the output directory.
- `content_hash` ignores volatile vCard fields (REV, PRODID,
  PHOTO, VERSION).
- `emitted_keys` is the set of drawer keys we wrote on the last
  run. The 3-way merge consults this to distinguish "we removed
  this" from "user added this."
- `etag` / `url` are reserved for Tier 6.
- `archived` flips when the contact is moved into `Archive/`.

`OUTPUT_SCHEMA_VERSION` (currently `"tier-4b"`) is hashed into
`output_settings_hash`. Bumping it forces every contact through a
rewrite on the next run — used whenever a tier changes the on-disk
format (new keys, reordering, etc.).

## Testing approach

Run the fixture suite from this directory:

```sh
python3 -m pip install -e ".[test]"
python3 -m pytest
```

Tests use synthetic, non-personal vCards so sample contact data never
needs to be committed. Coverage currently checks property-drawer
output, user edit preservation, group filetags, and manifest state.

## Layout notes

- `.gitignore` in this directory excludes `*.vcf` so contact data
  never lands in git accidentally.
- `__pycache__/` is gitignored project-wide.
- Module is loaded conditionally via `my-flag-contacts` in
  `core/my-flags.el`; default-on.
- The Emacs wrapper module is `modules/my-contacts.el`. Leader
  binding lives there alongside the import command.
