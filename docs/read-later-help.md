# Local-First Read-Later Help

This setup moves saved reading away from Readwise/Reader and into a shared
local-first folder. Emacs, Safari, and Elfeed currently write into the same
read-later contract; iPhone and loxley ingress remain roadmap work.

## Storage Layout

Mac default root:

```text
~/All-The-Things/50-Resources/Read-Later/
```

Loxley root:

```text
/srv/loxley/All-The-Things/50-Resources/Read-Later/
```

Folder roles:

```text
AGENTS.md
items/              canonical Org capture files
queue/              pending snapshot/ingress work
snapshots/html/     fetched HTML snapshots
snapshots/readable/ readable Org conversions
imports/readwise/   one-time Reader export material
failures/           failed snapshot jobs
logs/               capture/index/processed logs
feed.xml            generated RSS feed for Elfeed review
```

Local captures create an Org item in `items/`, dedupe by normalized URL, and
default to lightweight metadata-only saves. Duplicate saves append to the
existing item's capture log. The generated `feed.xml` is derived from `items/`;
it can be deleted and rebuilt at any time.

## Item Contract

Each saved item is one Org file. New captures use standard Org document
metadata plus a property drawer:

```org
#+title: Article Title
#+date: [2026-05-20 Wed 20:27]

:PROPERTIES:
:ID: 550e8400-e29b-41d4-a716-446655440000
:URL: https://example.com/article?utm_source=newsletter
:CANONICAL_URL: https://example.com/article
:SOURCE_APP: eww
:CAPTURED: [2026-05-20 Wed 20:27]
:ARCHIVE_MODE: metadata
:TAGS: emacs,reading,news
:CONTENT_SHA256:
:SNAPSHOT_STATUS: not-requested
:END:
```

`CANONICAL_URL` is the dedupe key. `ID` is the normal Org identity used for
local object references, snapshot filenames, and queue records. `SOURCE_APP`
records the most recent capture surface; the capture log preserves earlier
captures. `TAGS` stores tags from manual/browser capture and Elfeed category
tags. Older items that still have `READ_LATER_ID`, `CAPTURE_TAGS`, or
`FEED_TAGS` are tolerated by the normalizer, but new captures should not
create those properties.

## Emacs Commands

Available with `M-x`:

```text
my-reading-capture-dwim
my-reading-capture-url
my-reading-capture-current-page
my-reading-capture-elfeed-entry
my-reading-open-root
my-reading-open-queue
my-reading-generate-feed
my-reading-update-feed
my-reading-delete-dwim
my-reading-delete-files
my-reading-promote-elfeed-entries
my-reading-snapshot-items
my-reading-snapshot-queue
```

Leader bindings, using `C-c u` or the double-space leader:

```text
n d   save to read-later
n D   delete read-later item
n p   promote selected Elfeed entries
n w   capture current Emacs browser/page
n l   update generated read-later feed
n q   open read-later queue
n r   open read-later root
n x   process snapshot queue
```

In Elfeed:

```text
d     save current Elfeed item to read-later
D     delete generated read-later item and clean related state
P     promote selected entries to saved snapshots
```

In Dired, normal delete commands are intercepted only for Org files under the
read-later `items/` directory:

```text
D     delete marked/current read-later item with cleanup
d x   flag then execute read-later item deletion with cleanup
```

For non-read-later files, Dired delete behavior stays unchanged.

## Elfeed Review Feed

Saved links are exposed back to Elfeed through a generated local RSS feed:

```text
~/All-The-Things/50-Resources/Read-Later/feed.xml
```

That feed is listed in `~/All-The-Things/50-Resources/feeds.org` under the
normal `:elfeed:` tree:

```org
** Read Later :readlater:
*** [[file:///Users/seanmclaren/All-The-Things/50-Resources/Read-Later/feed.xml][Read Later]]
```

Captures and snapshot processing refresh `feed.xml`; Emacs captures also ask
Elfeed to refresh the local feed when Elfeed is already loaded. To rebuild it
manually and ask Elfeed to update that source:

```text
SPC SPC n l
```

To see saved links and promoted items inside Elfeed, use a filter such as:

```text
+readlater
```

The feed carries item categories, and the Emacs read-later layer turns those
into Elfeed search tags like `saved-link`, `saved-article`, `source-safari`,
`source-eww`, `source-elfeed`, and any tags stored on the read-later item.
The feed description stays intentionally lightweight: source, capture time,
snapshot status, original URL, Org item link, notes, and selections. Snapshot
bodies are kept in the Org item and `snapshots/`, not embedded in `feed.xml`.

## Promote Selected Elfeed Entries

Use `P` in Elfeed, or `SPC SPC n p`, after selecting entries you want to keep
long term. In an Elfeed search buffer, an active region selects multiple
entries; with no region, the command uses the entry at point. This command
snapshots only the selected entries:

```text
P
SPC SPC n p
```

For regular RSS entries, promotion first captures the entry as a lightweight
read-later item, tags the original Elfeed entry as `saved`, and then snapshots
that item. For generated `+readlater` entries, promotion reuses the existing Org
item and snapshots that item directly. Unselected files in `Read-Later/items/`
are not processed.

## Browser Bookmarklet

The read-later module registers this org-protocol endpoint:

```text
org-protocol://read-later
```

Create a Safari bookmark and replace its address with this bookmarklet:

```javascript
javascript:location.href='org-protocol://read-later?'+new URLSearchParams({url:location.href,title:document.title,body:window.getSelection().toString(),source:'safari'});void(0)
```

Using the bookmarklet captures the current Safari page through the same local
read-later path as Emacs. Selected text is stored as the capture selection, and
the saved item gets `:SOURCE_APP: safari`.

## Shell Commands

Capture a URL:

```sh
~/.emacs.d/scripts/read-later-capture \
  --url "https://example.com/article" \
  --title "Article Title" \
  --source manual \
  --tags "emacs,reading" \
  --note "Why I saved it"
```

Normalize existing read-later items after a format change:

```sh
~/.emacs.d/scripts/read-later-capture --normalize-existing
```

Process all queued local snapshots:

```sh
~/.emacs.d/scripts/read-later-snapshot --all
```

Regenerate the Elfeed review feed:

```sh
~/.emacs.d/scripts/read-later-feed
```

Delete a read-later item and clean generated state:

```sh
~/.emacs.d/scripts/read-later-delete \
  --item ~/All-The-Things/50-Resources/Read-Later/items/some-item.org
```

The delete command removes the canonical item file, matching queue entries, and
matching `snapshots/html/` and `snapshots/readable/` files. It then regenerates
`feed.xml` and appends a historical deletion record to `logs/deletions.jsonl`.
When invoked from Emacs, the live generated Elfeed entries are also removed from
the Elfeed DB.

Snapshot processing defaults to `--extractor auto`, which tries a
Playwright-rendered page with Mozilla Readability first, then falls back to
EWW's `eww-readable`, then Pandoc. Use `--extractor readability` to require
the Playwright/Readability path, `--extractor pandoc` to force the older
HTML-to-Org conversion, or `--extractor eww` to fail instead of falling back.
The Readability path uses `npm exec` with pinned transient packages, so it does
not create a persistent `node_modules/` directory in this repo. On macOS it
uses Playwright's cached browser when available and falls back to local Chrome,
Chromium, or Edge. Set `READ_LATER_CHROMIUM` to override the browser path.

From Emacs, use:

```text
SPC SPC n x
```

Process one item:

```sh
~/.emacs.d/scripts/read-later-snapshot \
  --item ~/All-The-Things/50-Resources/Read-Later/items/some-item.org
```

Force the Playwright/Readability extractor for one item:

```sh
~/.emacs.d/scripts/read-later-snapshot \
  --item ~/All-The-Things/50-Resources/Read-Later/items/some-item.org \
  --extractor readability
```

Dry-run a Readwise/Reader export import:

```sh
~/.emacs.d/scripts/readwise-export-import --dry-run /path/to/reader-export.zip
```

Import OPML into the Elfeed feeds file:

```sh
~/.emacs.d/scripts/readwise-export-import \
  --feeds-org ~/All-The-Things/50-Resources/feeds.org \
  /path/to/subscriptions.opml
```

## Archive Modes

`read-later-capture` supports:

```text
metadata   create item only, no snapshot queue
readable   create item and queue readable snapshot
full       create item and queue fuller snapshot intent
defer      create item and queue later processing
```

Default mode is `metadata`.

## Future Loxley Ingress

The intended loxley service shape is:

```text
loxley-read-later-ingress.service
```

Endpoint:

```text
POST http://loxley:45741/capture
```

Required header:

```text
Authorization: Bearer <read_later_ingress_token>
```

Example:

```sh
curl -X POST http://loxley:45741/capture \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $READ_LATER_TOKEN" \
  -d '{"url":"https://example.com","title":"Example","source":"iphone","tags":["mobile"]}'
```

Health check:

```sh
curl http://loxley:45741/health
```

The token should be stored on loxley via `sops-nix` as:

```text
/run/secrets/read_later_ingress_token
```

## Current Boundary

Local Mac/Emacs captures create canonical `items/` entries and default to
metadata-only saves. Snapshot work happens only when you explicitly promote
selected Elfeed entries or run the snapshot queue processor.

Loxley/mobile ingress is not the active capture path yet. A future worker
should accept remote/mobile captures and materialize them into the same
canonical `items/` format automatically.
