# Read-Later Workflow Plan

Status: active working doc. Updated 2026-05-22.

This note tracks the operating model we are testing. The command reference lives
in `docs/read-later-help.md`; this file explains how the workflow should feel
and what remains intentionally undecided.

## Current Model

The local read-later system has three related but separate surfaces:

| Surface | Purpose | Canonical Storage |
|---|---|---|
| Bookmarks | Reusable references, tools, sites, and links that should stay easy to reopen. | `~/All-The-Things/50-Resources/bookmarks.org` |
| Saved links | Low-commitment items that caught my attention and may be worth returning to. | `~/All-The-Things/50-Resources/Read-Later/items/*.org` |
| Promoted saved items | Read-later items promoted into durable article snapshots. | Same Org item, plus readable/html snapshots |

Read-later Org files remain canonical. Elfeed is a review surface, not the source
of truth. The generated RSS feed at
`~/All-The-Things/50-Resources/Read-Later/feed.xml` is disposable and can be
rebuilt from the Org files.

## MVP Capability Checkpoint

This is the current MVP loop:

| Capability | Status |
|---|---|
| Save from Safari | Done via `org-protocol://read-later` bookmarklet. |
| Save from Emacs/EWW | Done via `SPC SPC n w` and DWIM save. |
| Save from Elfeed | Done via `d`. |
| Save manually | Done via `M-x my-reading-capture-url`. |
| Store canonical item in Org | Done in `Read-Later/items/*.org`. |
| Dedupe saved items | Done by `CANONICAL_URL`. |
| Review alongside RSS | Done through generated `feed.xml` in Elfeed. |
| Delete end-to-end | Done from Dired, Elfeed, or `SPC SPC n D`. |
| Promote selected items | Done with `P` or `SPC SPC n p` from Elfeed. |
| Save readable article artifact | Done via Playwright Readability to Org snapshots. |
| Keep bookmarks separate | Done via the separate bookmark org-protocol helper. |

The important current boundary: promoted articles are durable Org artifacts
inside `Read-Later/items/`, with optional snapshot files under `snapshots/`.
They are not yet moved into `40-Knowledge/` or integrated into `org-node` as
first-class knowledge notes.

## Current Usage

### Save A Link Or Article Candidate

| Source | Command | Current Behavior |
|---|---|---|
| Any Emacs context | `SPC SPC n d` | DWIM save: Elfeed entry, EWW page, URL at point, or minibuffer URL. |
| EWW / Emacs browser | `SPC SPC n w` | Save the current page URL/title/selection. |
| Elfeed | `d` | Save the current Elfeed entry, preserve feed tags in `:TAGS:`, and tag the Elfeed entry `saved`. |
| Safari | `org-protocol://read-later` bookmarklet | Save current tab URL/title plus selected text when present. |
| Manual | `M-x my-reading-capture-url` | Prompt for URL, title, tags, note, selection, and archive mode. |

Current default archive mode is `metadata`, so captures create an Org item
without queueing snapshot work. Promotion is explicit from Elfeed.

### Delete Saved Items

Use the read-later delete path instead of raw file deletion when possible:

| Source | Command | Cleanup |
|---|---|---|
| Dired in `Read-Later/items/` | `D` or `d x` | Deletes selected item files, queue entries, snapshots, regenerated feed, and live Elfeed entries. |
| Any Emacs context | `SPC SPC n D` | DWIM delete from Dired, generated Elfeed entries, current item buffer, or prompted file. |
| Generated Elfeed read-later feed | `D` | Deletes selected generated read-later entries and their canonical item files. |
| Shell | `read-later-delete --item path/to/item.org` | Performs filesystem cleanup and regenerates `feed.xml`. |

Plain filesystem deletion is still possible, but it only removes the item file.
It does not clean pending queue JSON, snapshot files, or already-imported Elfeed
DB entries.

### Review Saved Links In Elfeed

Read-later items are exposed to Elfeed through `feeds.org`:

```org
** Read Later :readlater:
*** [[file:///Users/seanmclaren/All-The-Things/50-Resources/Read-Later/feed.xml][Read Later]]
```

Use this filter in Elfeed:

```text
+readlater
```

Useful tags include:

```text
readlater
saved-link
saved-article
source-safari
source-eww
source-elfeed
source-manual
```

Feed descriptions stay lightweight. They include capture metadata, original
URL, item link, notes, and selections, but they do not embed readable snapshot
bodies. Snapshot content remains in the Org item and `snapshots/`.

`SPC SPC n l` regenerates the local RSS feed and asks Elfeed to refresh that
source. Emacs captures also try to refresh the feed when Elfeed is already
loaded.

### Snapshot Processing

`SPC SPC n x` runs `read-later-snapshot --all` in a compilation buffer. The
snapshot script processes queued items, stores HTML/readable output under
`snapshots/`, appends a readable section to the item file, updates
`:SNAPSHOT_STATUS:`, and refreshes the generated Elfeed feed.

Snapshot extraction defaults to `--extractor auto`: try a Playwright-rendered
page with Mozilla Readability first, then fall back to EWW readable extraction,
then Pandoc. Use `--extractor readability` when testing the browser reader path
directly. The helper uses pinned transient `npm exec` packages and does not
create a persistent `node_modules/` directory.

### Promote Selected Entries

Use `P` in Elfeed, or `SPC SPC n p`, after selecting the entries you want to
keep long term. In an Elfeed search buffer, an active region selects multiple
entries; with no region, the command uses the entry at point.

| Entry type | Promotion behavior |
|---|---|
| Generated `+readlater` entry | Reuses the existing read-later Org item and snapshots that item only. |
| Regular RSS entry | Captures the entry as a lightweight read-later item, tags the original Elfeed entry `saved`, then snapshots that new item only. |

Promotion calls `read-later-snapshot --item ...` with the selected item paths,
not `--all`, so unselected files in `Read-Later/items/` stay lightweight.
If a selected item still has an older pending queue JSON, the direct snapshot
consumes that matching queue entry.

### Bookmarks Stay Separate

Safari has a separate `org-protocol://bookmark` helper backed by
`my-bookmarks-add-url`. Use it for durable bookmarks, not speculative reading
items. Bookmark dedupe is working and writes to `bookmarks.org`.

## Tested Decisions

| Decision | Status | Notes |
|---|---|---|
| One Org file per read-later item | Adopted | Easier dedupe, snapshots, and future sync than one giant Org file. |
| `CANONICAL_URL` as dedupe key | Adopted | Normalized URL dedupe works across capture surfaces. |
| Org `:ID:` instead of custom `READ_LATER_ID` | Adopted | The old property is normalized away. |
| No file-level `#+source` | Adopted | Source lives in `:SOURCE_APP:` and capture log. |
| Tags in `:TAGS:` property | Adopted | Replaces `#+filetags`, `CAPTURE_TAGS`, and `FEED_TAGS`. |
| Safari read-later through org-protocol | Adopted | Replaces the old `read-later-safari` script idea. |
| Bookmarks through separate org-protocol helper | Adopted | Keeps bookmarks distinct from read-later items. |
| Elfeed review via generated local RSS feed | Adopted | Option A. `feed.xml` is generated, listed in `feeds.org`, and tagged in Elfeed. |
| Direct Elfeed DB insertion | Parked | Technically possible, but too coupled to Elfeed internals for canonical storage. |
| Intentional delete path | Adopted | Dired/Elfeed delete commands call `read-later-delete` and then remove live generated Elfeed entries. |
| Default link-only capture | Adopted | New captures use `ARCHIVE_MODE: metadata` and `SNAPSHOT_STATUS: not-requested`. |
| Selected Elfeed promotion | Adopted | `P` / `SPC SPC n p` snapshots only selected generated read-later or regular RSS entries. |

## Roadmap

### Possible Next Implementation Slices

| Possible Slice | Purpose |
|---|---|
| iPhone / loxley ingress | Mobile capture into the same item contract. |
| Failed snapshot retry UI | Show failed snapshot jobs and retry selected failures from Emacs. |
| Dired promotion command | Promote marked read-later items from Dired. |
| Explicit state command | Set or clear a future saved-state property without re-snapshotting. |
| Knowledge promotion command | Move or copy a promoted read-later item into `40-Knowledge/` / `org-node` when it becomes a permanent note. |
| Readwise migration run | One-time import of Reader documents, highlights, OPML, and uploaded files. |

### State Model To Settle

Open question: should article state be inferred from `:SNAPSHOT_STATUS: ok`, or
should we add an explicit property?

Possible explicit property:

```org
:READING_STATE: link
```

Possible values:

```text
link
article
archived
discarded
```

This would make Elfeed filters and future automation easier, but it adds one
more field to maintain.

### Review UI

The generated Elfeed feed is the current review UI. It is better than a raw
Dired queue because it supports the familiar Elfeed triage pattern:

1. Browse a list of saved links.
2. Open a show buffer for preview/context.
3. Visit the original URL when needed.
4. Promote only the items worth preserving.

Still undecided:

- Whether `d` on a `+readlater` entry should mean promote, discard, or something else.
- Whether to add a dedicated read-later hydra/transient-style menu.
- Whether discard should mean physical deletion, a `discarded` state, or moving
  items to an archive folder.

### Mobile And Loxley

The desired mobile shape remains:

- iPhone Share Sheet posts to loxley over Tailscale.
- Loxley materializes incoming captures into the same read-later item contract.
- Syncthing keeps the folder present on Mac and loxley.

Current Mac/Emacs captures already create canonical items. The remaining loxley
work is making remote/mobile ingress produce the same item format instead of
stopping at raw queue JSON.

## Bias

Capture should be cheap and low-commitment. Elfeed should be the review surface.
Snapshotting should stay an intentional promote-to-saved-snapshot action.
