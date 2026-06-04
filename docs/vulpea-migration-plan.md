# Vulpea Migration Plan

Status: active working doc. Updated 2026-06-04.

This file tracks the migration of the networked-notes engine from
`org-node` + `org-mem` to `vulpea` (v2), and the larger arc it serves:
exposing the notes vault to mobile via a Go-backed PWA reading directly
from vulpea's SQLite database. Phase 1 (the Emacs-side engine swap) is the
immediate work; Phases 2–3 are sketched so Phase 1 decisions point
somewhere. The notes engine module today is `modules/my-nodes.el`; the
contact helper is `elisp/my-node-contact-email.el`.

## Why migrate

The decisive reason is `vulpea-meta`: structured, typed, **queryable**
key/value metadata stored as an Org description list, indexed into a real
SQLite database with a typed query API (`vulpea-db-query-by-*`).
`org-node`/`org-mem` has no equivalent — metadata there is `PROPERTIES`
drawers only, queried by hand-rolled iteration over in-RAM hash tables.

vulpea v2 (GA 2025-12-30, currently v2.2.0) **dropped its org-roam
dependency** and maintains its own SQLite DB. So this is a swap between two
peer indexing engines, not an adoption of org-roam. The SQLite file is what
makes the mobile/PWA arc possible: any language with a SQLite driver becomes
a first-class read client against the vault.

Full comparison and rationale: `~/vulpea-vs-org-node-comparison.html`.

## The arc

| Phase | Goal | Status |
|---|---|---|
| 1 | Swap the Mac notes engine org-node → vulpea, at feature parity, producing `vulpea.db`. | In progress |
| 2 | Serve layer on the nix-node: vulpea on the node's daemon indexes the vault; Go service reads `vulpea.db`; write-bridge via `emacsclient` to whitelisted commands; Tailscale/SSH access. | Not started |
| 3 | Build the PWAs (Go backend + Add-to-Home-Screen frontends): reading queue first, then bookmarks / contacts / capture / today. | Not started |

## Pre-flight findings (verified, de-risked)

| Check | Result | Implication |
|---|---|---|
| Emacs has built-in SQLite | `sqlite-available-p` → `t` on Emacs 31.0.60 (aarch64-darwin) | vulpea's DB backend works natively on the Mac |
| Notes carry org-ids | `org-id` creates IDs on capture + finalize | vulpea indexes existing notes as-is; no ID backfill |
| vulpea alias property | `vulpea-buffer-alias-property` **defaults to `"ALIASES"`** | Your convention is vulpea's default; the ALIASES shims just disappear; no note rewrite |
| On-disk format | `#+title:`, `#+filetags:`, `:ID:` — identical to today | Non-destructive; both engines read the same vault during coexistence |
| Currently installed | org-node 2026-03-09, org-mem 2026-03-26; **no** vulpea/emacsql/org-roam | Clean install of the vulpea stack on the Mac (MELPA) |

## Locked decisions (2026-06-04)

| Decision | Choice | Consequence for the plan |
|---|---|---|
| Migration strategy | **Coexistence → cutover** | Both engines run over the same vault during Phase 1; rollback is `my-flag-vulpea nil`. vulpea uses parallel bindings until cutover. |
| Canonical home (vault + daemon + DB) | **Decide in Phase 2** | Phase 1 is Mac-only. Make the DB path a relocatable `my-vulpea-db-location` defvar so the node can point at it later. |
| `:BACKLINKS:` drawers | **Delete them** | Discrete, backed-up, committed step run *at cutover* (while org-node is still loaded, so `org-node-backlink-mass-delete-drawers` is available); rely on `vulpea-ui` sidebar afterward. |

## Progress log

- **2026-06-04 — Phase 1 engine scaffold landed (coexistence).** Installed
  vulpea 20260308 + emacsql (MELPA). Added `my-flag-vulpea`, the `init.el`
  load block, and `modules/my-vulpea.el` (autosync idle-warm; DB at
  `my-vulpea-db-location`; `vulpea-db-sync-directories` → `my-notes-directory`;
  alias property `ALIASES`; parallel `o v` leader bindings). org-node left
  untouched (`my-flag-nodes t`).
  - Validated: `check-parens` clean; byte-compiles clean; a synchronous
    `(vulpea-db-sync-full-scan 'force)` of the real vault indexed **280 notes
    from 253 files** (167 tagged `contact`; 213 tag rows, 41 links, 1155
    properties, 0 meta — meta is empty until adopted). DB pre-warmed at
    `~/.emacs.d/var/vulpea/vulpea.db` (736K).
  - Confirmed for Phase 2/3: emacsql renders SQLite identifiers with
    **underscores** (`note_id`, `outline_path`, `schema_registry`), not dashes.
  - **Open (Step 1 safety net):** `~/All-The-Things/` is **not** under git.
    Put it under version control (or a snapshot) before cutover / drawer
    deletion.
- **2026-06-04 — Step 4 helpers ported.** Added `my-vulpea-link-capf`
  (gated by `my-vulpea-link-capf-enabled`, default nil) and
  `my-vulpea-contact-email` to `modules/my-vulpea.el`. Validated: check-parens
  + byte-compile clean; against the live DB the capf builds 280 title/alias
  candidates with valid id mapping, and the contact helper yields 58 addresses
  (vs 18 for the original EMAIL-only helper). The old contact helper was
  orphaned (never `require`d) and mail completion is independent — nothing to
  repoint.
- **2026-06-04 — Step 5 parity validated (user).** `o v f/i/b`,
  `my-vulpea-contact-email`, and the `[[` capf all work as expected in a live
  session. Decision: at cutover, set `my-vulpea-link-capf-enabled` default to
  `t` so the capf is always on (kept off until then to avoid a double capf
  while org-node is still loaded).
- **2026-06-04 — Step 6 cutover complete.** Snapshotted the vault, deleted the
  3 `:BACKLINKS:` drawers (verified by diff against the snapshot), and retired
  org-node: `o n` rebinds to vulpea, `[[` capf always-on, `my-flag-nodes` +
  `my-nodes.el` + `elisp/my-node-contact-email.el` removed, and
  init/flags/AGENTS/decisions-log updated. **vulpea is now the sole notes
  engine.** Rollback = restore the snapshot tarball + `git revert`.
- **2026-06-04 — post-migration housekeeping + vulpea-ui.** Uninstalled the
  unused org-node/org-mem/el-job packages (`custom.el` selected-packages
  updated). Refreshed the assistant memory (`MEMORY.md`). Installed `vulpea-ui`
  (+ `vui`) and bound the live sidebar to `o n u`
  (backlinks/outline/links/stats; replaces the deleted drawers).
- Next: evaluate `vulpea-journal` (a journaling-model change — its own design
  decision), then Phase 2 (re-enable Syncthing to the node; nix-node serve
  layer + Go PWA reading `vulpea.db`).

## Phase 1 — migration steps

### 1. Safety net
- [ ] Confirm `~/All-The-Things/` is under version control (or snapshot it). Every file-touching step below gets its own commit first.

### 2. New module behind a flag (coexistence)
- [x] Add `my-flag-vulpea t` to `core/my-flags.el`.
- [x] Add `(when my-flag-vulpea (my-load-module vulpea "my-vulpea"))` to `init.el` (beside the `my-flag-nodes` block). **Keep `my-flag-nodes t`** for now.
- [x] Create `modules/my-vulpea.el` (`(provide 'my-vulpea)`).
- Naming caution: `my-flag-node` (singular) is the headless-host profile — unrelated to notes. Use `my-flag-vulpea`.

### 3. Configure vulpea
- [x] `use-package vulpea` (auto-installs from MELPA on the Mac; `use-package-always-ensure` is on for non-node hosts — no `:ensure` needed).
- [x] Define `my-vulpea-db-location` (defvar) defaulting to a no-littering `var/` path; set `vulpea-db-location` to it. Overridable from the host-context shim for Phase 2.
- [x] Point `vulpea-db-sync-directories` at `(list my-notes-directory)`.
- [x] Set `vulpea-buffer-alias-property` to `"ALIASES"` (matches existing notes; also the default).
- [x] Enable `vulpea-db-autosync-mode` (file-watch + async indexing); `vulpea-db-sync-scan-on-enable` set to `'async` for catch-up scans on enable.
- [x] Warm the index on an idle timer after startup, mirroring `my-org-node--enable-modes`, to preserve the <1 s startup target.

### 4. Port the three helpers into `my-vulpea.el`
- [x] **`[[` → corfu capf.** `my-vulpea-link-capf` ports the org-node capf: candidates (titles **+ aliases**; 280) from `vulpea-db-query`, selection replaces the bracket pair with `[[id:..][title]]`. Gated by `my-vulpea-link-capf-enabled` (nil during coexistence so it does not double with org-node's capf); the `org-mode-hook` is registered now. Flip to `t` to A/B test or at cutover.
- [x] **Contact email.** `my-vulpea-contact-email` queries `vulpea-db-query-by-tags-some '("contact")`. Also fixes a latent gap: the original read only `EMAIL` (18 contacts); the port covers `EMAIL_WORK`/`EMAIL_HOME`/`EMAIL_OTHER` too (58 addresses) and shows each address in the candidate. No mail-side caller to repoint — `my-mail.el` has its own contact completion and the old helper was orphaned (never `require`d).
- [x] **Aliases.** Not ported — vulpea handles `ALIASES` natively. The `org-mem-entry-roam-aliases` / `org-node-add-alias` shims go away with `my-nodes.el` at cutover.
- [x] **Leader bindings.** Done in Step 3: `o v f/i/b/s`. `o n …` stays on org-node until cutover.
- [ ] **Grep.** No vulpea equivalent for `org-node-grep`; bind `consult-ripgrep` over `my-notes-directory` at cutover.

### 5. Validate parity (acceptance criteria)
- [ ] vulpea indexes the vault; note count is consistent with `(length (org-mem-all-id-nodes))`.
- [ ] `vulpea-find` opens notes; `vulpea-insert` and `my-vulpea-link-capf` produce correct `id:` links.
- [ ] Aliases resolve in find/insert (notes using the `ALIASES` property).
- [ ] Contact completion returns the right email addresses.
- [ ] Inspect the DB: `sqlite3 <my-vulpea-db-location> '.tables'` and `'.schema'` — confirm it is populated and **capture the real column identifiers** (emacsql dash/underscore mangling) for the Go phase.

### 6. Cutover (single commit window)
- [x] Snapshot the vault → `~/All-The-Things-backup-pre-vulpea-20260604-152832.tar.gz`.
- [x] Delete the `:BACKLINKS:` drawers — only **3 files** had them (vault is sparsely linked). Removed via a verified pure-text edit (diffed against the snapshot: only drawer lines removed, nothing else).
- [x] Repoint `o n f/i/b/g/s` to vulpea (`vulpea-find` / `vulpea-insert` / `vulpea-find-backlink` / `my-vulpea-grep` / `vulpea-db-sync-full-scan`); `my-vulpea-link-capf-enabled` default now `t`; org-node's capf removed with `my-nodes.el`.
- [x] Removed the `my-flag-nodes` flag + its init load block; deleted `modules/my-nodes.el` and `elisp/my-node-contact-email.el`.
- [x] Updated `AGENTS.md` and `emacs-decisions-log.md`. (MEMORY.md is the assistant auto-memory and already stale on unrelated points — left for a separate `consolidate-memory` pass.)
- [ ] Final commit: `modules: complete cutover from org-node to vulpea`.

## Deferred (not blocking Phase 1 parity)

| Item | Why deferred |
|---|---|
| `vulpea-ui` sidebar (+ `vui`) | **✅ Added 2026-06-04** (post-parity). Live backlinks/outline/links/stats sidebar, toggle `o n u`. Replaces the deleted `:BACKLINKS:` drawers. Mac-only convenience (irrelevant to the headless node / Go layer). |
| `vulpea-journal` | Changes journal storage from the single datetree file to one-file-per-day ID notes. Its own decision; evaluate in Phase 3. Default: keep the current datetree for now. |
| Node packaging | Phase 2. On the node `use-package-always-ensure` is off, so vulpea/emacsql/vui must be added to the node's Nix Emacs package set, not installed via package.el. |

## Phase 2 — serve layer (sketch)

- vulpea on the node's Nix Emacs daemon indexes the vault → `vulpea.db` on the node.
- Go service (single static binary; pure-Go SQLite via `modernc.org/sqlite`) reads the DB **read-only** for all queries.
- Writes go **through Emacs**: Go shells out to `emacsclient -s <socket> --eval "(my-mobile-... )"` calling **whitelisted** commands (`vulpea-create`, `vulpea-meta-set`, `org-capture`) — never raw eval over the wire. Emacs writes the Org file; vulpea re-indexes; the DB refreshes.
- Access from iPhone over **Tailscale** (or an SSH tunnel, since SSH to the node already exists). Bind the service to localhost/tailnet only.
- Correctness rule: `vulpea.db` is a derived read-replica. The Org files are the source of truth. Never write the DB directly.

**Open question (parking lot):** how does `~/All-The-Things/` reach the node today — git, Syncthing, TRAMP-only, or not yet synced? Determines whether the node indexes its own copy or shares one. This is the last unknown for the serve layer.

## Phase 3 — PWAs (sketch)

- First vertical slice: **reading queue** — exercises the EAV `meta` table end-to-end (list `status :: queued`, tap → flip to `done` via the write-bridge), and it's a genuinely useful mobile view of `my-reading.el`.
- Then: bookmarks (replace `my-bookmarks.el`'s org-element parsing with meta-notes), contacts lookup (read-only from `vulpea.db`), quick capture (iOS Shortcut → endpoint, mirroring the existing `org-protocol` capture pattern), today/agenda.
- Frontends are static HTML/CSS/JS with a `manifest.json` (`display: standalone`) for Add-to-Home-Screen; service worker for offline reads.

## Reference — verified `vulpea.db` schema (schema v3)

Backend `emacsql-sqlite-builtin`, foreign keys on. Default location
`vulpea.db` in `user-emacs-directory` (we override via
`my-vulpea-db-location`). Confirm exact column identifiers from a live DB
before writing Go queries.

| Table | Columns | Shape |
|---|---|---|
| `notes` | `id` (PK), `path`, `level`, `pos`, `title`, `properties` (JSON), `tags` (JSON), `aliases` (JSON), `meta` (JSON), `links` (JSON), `todo`, `priority`, `scheduled`, `deadline`, `closed`, `outline-path`, `attach-dir`, `file-title`, `created-at`, `modified-at`. Unique `(path, level, pos)`. | Denormalized — one row = one full note |
| `meta` | `note-id` (FK→notes, cascade), `key`, `value` | EAV — one row per key/value |
| `tags` | `note-id` (FK), `tag`. PK `(note-id, tag)` | Normalized |
| `links` | `source` (FK), `dest`, `type`, `pos`, `description`. PK `(source, dest, type, pos)` | Normalized — backlinks table |
| `properties` | `note-id` (FK), `key`, `value`. PK `(note-id, key)` | Normalized |
| `files` | `path` (PK), `hash`, `mtime`, `size` | Change-detection ledger |
| `schema-registry` | `name` (PK), `version`, `created-at` | Version management |

Pattern for the Go read layer: filter through the normalized tables
(`meta`, `tags`, `links`), hydrate full notes from the JSON columns in
`notes` — no joins needed for retrieval.

## Reference — key vulpea API for the port

| Need | vulpea | replaces (org-node/org-mem) |
|---|---|---|
| Find/open note | `vulpea-find` | `org-node-find` |
| Insert link | `vulpea-insert` | `org-node-insert-link` |
| Backlink (interactive) | `vulpea-find-backlink` | — |
| Query by tag | `vulpea-db-query-by-tags-some` / `-every` / `-none` | manual `seq-filter` over `org-mem-all-id-nodes` |
| Query by metadata | `vulpea-db-query-by-meta` / `-by-meta-key` | (no equivalent) |
| Query by property | `vulpea-db-query-by-property` / `-by-property-key` | `org-mem-entry-property` + iteration |
| Read note meta | `vulpea-meta-get` / `-get-list` (typed) | (no equivalent) |
| Set note meta | `vulpea-meta-set`, `vulpea-buffer-meta-set` | (no equivalent) |
| Create note programmatically | `vulpea-create` | `org-node-new-file` |
| Select from a note list | `vulpea-select-from` | hand-rolled `completing-read` |
| Aliases | `vulpea-buffer-alias-add/-set/-remove` (property `ALIASES`) | the custom shims (delete) |

## Sources

- vulpea: https://github.com/d12frosted/vulpea (v2.2.0; own SQLite DB)
- vulpea-ui: https://github.com/d12frosted/vulpea-ui · vui: https://github.com/d12frosted/vui.el
- vulpea-journal: https://github.com/d12frosted/vulpea-journal
- "Vulpea v2: breaking up with org-roam": https://www.d12frosted.io/posts/2025-11-28-vulpea-v2-breaking-up-with-org-roam
- org-node: https://github.com/meedstrom/org-node · org-mem: https://github.com/meedstrom/org-mem
- Comparison report: `~/vulpea-vs-org-node-comparison.html`
