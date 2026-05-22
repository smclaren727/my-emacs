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
| Saved articles | Read-later items promoted or processed into durable article artifacts. | Same Org item, plus readable/html snapshots |

Read-later Org files remain canonical. Elfeed is a review surface, not the source
of truth. The generated RSS feed at
`~/All-The-Things/50-Resources/Read-Later/feed.xml` is disposable and can be
rebuilt from the Org files.

## Current Usage

### Save A Link Or Article Candidate

| Source | Command | Current Behavior |
|---|---|---|
| Any Emacs context | `SPC SPC n d` | DWIM save: Elfeed entry, EWW page, URL at point, or minibuffer URL. |
| EWW / Emacs browser | `SPC SPC n w` | Save the current page URL/title/selection. |
| Elfeed | `d` | Save the current Elfeed entry, preserve feed tags in `:TAGS:`, and tag the Elfeed entry `saved`. |
| Safari | `org-protocol://read-later` bookmarklet | Save current tab URL/title plus selected text when present. |
| Manual | `M-x my-reading-capture-url` | Prompt for URL, title, tags, note, selection, and archive mode. |

Current default archive mode is `readable`, so most captures create an Org item
and queue snapshot processing. This is useful while testing, but it may be too
eager for the final workflow.

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

`SPC SPC n l` regenerates the local RSS feed and asks Elfeed to refresh that
source. Emacs captures also try to refresh the feed when Elfeed is already
loaded.

### Snapshot Processing

`SPC SPC n x` runs `read-later-snapshot --all` in a compilation buffer. The
snapshot script processes queued items, stores HTML/readable output under
`snapshots/`, appends a readable section to the item file, updates
`:SNAPSHOT_STATUS:`, and refreshes the generated Elfeed feed.

Snapshot extraction defaults to `--extractor auto`: try EWW readable extraction
first, then fall back to Pandoc.

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

## Roadmap

### Next Workflow Decision

Decide whether capture should default to link-only:

```text
ARCHIVE_MODE: metadata
SNAPSHOT_STATUS: not-requested
```

The current default is `readable`, which queues snapshot work immediately. The
likely long-term behavior is cheaper capture first, explicit article promotion
later.

### Likely Next Implementation Slice

Add promotion commands:

| Proposed Command | Purpose |
|---|---|
| `my-reading-promote-item-at-point` | Promote the current read-later/Elfeed item to saved article. |
| `my-reading-promote-marked-items` | Promote marked read-later items from Elfeed or Dired. |
| `my-reading-snapshot-item` | Snapshot exactly one selected item. |

Promotion should set or update a clear state property and queue/process only the
chosen item.

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
- Whether discarded items should stay in `items/` with a state property or move
  to an archive folder.

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
Snapshotting should become an intentional promote-to-article action.
