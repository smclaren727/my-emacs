# Local-First Save-Link Help

This setup stores saved links and article candidates in a shared local-first
folder. Emacs, Safari, and Elfeed currently write into the same save-link
contract; one-time Readwise/Reader imports are supported by the importer, and
iPhone/loxley ingress remains roadmap work.

## Storage Layout

Mac default root:

```text
~/All-The-Things/00-Capture/Ingest/Saved-Links/
```

Planned loxley root:

```text
/srv/loxley/All-The-Things/00-Capture/Ingest/Saved-Links/
```

Folder roles:

```text
AGENTS.md
items/              canonical Org capture files
queue/              pending snapshot work
snapshots/html/     fetched HTML snapshots
snapshots/readable/ readable Org conversions
imports/readwise/   one-time Reader export material
failures/           failed snapshot jobs
logs/               capture/index/processed logs
```

Local captures create an Org item in `items/`, dedupe by normalized URL, and
default to lightweight metadata-only saves. Duplicate saves append to the
existing item's capture log.

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
:TAGS: emacs,article,news
:CONTENT_SHA256:
:SNAPSHOT_STATUS: not-requested
:END:
```

`CANONICAL_URL` is the dedupe key. `ID` is the normal Org identity used for
local object references, snapshot filenames, and queue records. `SOURCE_APP`
records the most recent capture surface; the capture log preserves earlier
captures. `TAGS` stores tags from manual/browser capture and Elfeed category
tags.

## Emacs Commands

Available with `M-x`:

```text
my-save-link-capture-dwim
my-save-link-capture-url
my-save-link-capture-current-page
my-save-link-capture-elfeed-entry
my-save-link-open-root
my-save-link-open-queue
my-save-link-delete-dwim
my-save-link-delete-files
my-save-link-snapshot-items
my-save-link-snapshot-queue
my-save-link-import-readwise-export
```

Leader bindings, using `C-c u` or the double-space leader:

```text
n d   save to save-link
n D   delete save-link item
n w   capture current Emacs browser/page
n q   open save-link queue
n r   open save-link root
n x   process snapshot queue
```

In Elfeed:

```text
d     save current Elfeed item to save-link
```

`d` captures the current RSS entry into your save-links and tags the Elfeed
entry `saved`.

In Dired, normal delete commands are intercepted only for Org files under the
save-link `items/` directory:

```text
D     delete marked/current save-link item with cleanup
d x   flag then execute save-link item deletion with cleanup
```

For non-save-link files, Dired delete behavior stays unchanged.

## Browser Bookmarklet

The save-link module registers this org-protocol endpoint:

```text
org-protocol://save-link
```

Safari stores custom-URL-scheme permissions per website. To avoid an
Allow/Deny prompt on every domain, these bookmarklets open the org-protocol URL
from a temporary `about:blank` tab.

Use this setup bookmarklet once if Safari still prompts. Choose **Always
Allow**, then close the blank tab manually. The code is URL-encoded for pasting
into Safari's bookmark URL field:

```javascript
javascript:(function(){var%20p=new%20URLSearchParams({url:location.href,title:document.title,body:window.getSelection().toString(),source:'safari'});var%20w=window.open();var%20a=w.document.createElement('a');a.href='org-protocol://save-link?'+p.toString();w.document.body.appendChild(a);a.click();})();
```

After that, use this daily bookmarklet. It captures the page and closes the
temporary blank tab:

```javascript
javascript:(function(){var%20p=new%20URLSearchParams({url:location.href,title:document.title,body:window.getSelection().toString(),source:'safari'});var%20w=window.open();var%20a=w.document.createElement('a');a.href='org-protocol://save-link?'+p.toString();w.document.body.appendChild(a);a.click();w.close();})();
```

Using the daily bookmarklet captures the current Safari page through the same
local save-link path as Emacs. Selected text is stored as the capture
selection, and the saved item gets `:SOURCE_APP: safari`.

If updating an older bookmarklet, the protocol portion must be
`org-protocol://save-link`; the old `read-later` protocol is not registered.

Focus behavior is handled by `/Applications/Emacs Client.app`, which owns the
`org-protocol` URL scheme. Its `open location` handler should call
`emacsclient -n` only. If it also runs `open -a Emacs`, Safari will save
correctly but Emacs will come to the front after every capture.

## Shell Commands

The five feature scripts live together in `~/.emacs.d/scripts/save-link/`.
They all accept `--root` to target a non-default store. Without `--root`,
they use `MY_SAVE_LINK_ROOT` when set, otherwise
`~/All-The-Things/00-Capture/Ingest/Saved-Links`. The core scripts also support
`--json` for automation-friendly output.

Capture a URL:

```sh
~/.emacs.d/scripts/save-link/save-link-capture \
  --url "https://example.com/article" \
  --title "Article Title" \
  --source manual \
  --tags "emacs,article" \
  --note "Why I saved it"
```

Normalize existing save-link items after a format change:

```sh
~/.emacs.d/scripts/save-link/save-link-capture --normalize-existing
```

Process all queued local snapshots:

```sh
~/.emacs.d/scripts/save-link/save-link-snapshot --all
```

Delete a save-link item and clean generated state:

```sh
~/.emacs.d/scripts/save-link/save-link-delete \
  --item ~/All-The-Things/00-Capture/Ingest/Saved-Links/items/some-item.org
```

The delete script can also select items with `--org-id` or `--url`.

The delete command removes the canonical item file, matching queue entries, and
matching `snapshots/html/` and `snapshots/readable/` files, and appends a
historical deletion record to `logs/deletions.jsonl`.

Snapshot processing defaults to `--extractor auto`, which tries a
Playwright-rendered page with Mozilla Readability first, then falls back to
EWW's `eww-readable`, then Pandoc. Use `--extractor readability` to require
the Playwright/Readability path, `--extractor pandoc` to force the older
HTML-to-Org conversion, or `--extractor eww` to fail instead of falling back.
The Readability path uses `npm exec` with pinned transient packages, so it does
not create a persistent `node_modules/` directory in this repo. On macOS it
uses Playwright's cached browser when available and falls back to local Chrome,
Chromium, or Edge. Set `SAVE_LINK_CHROMIUM` to override the browser path.

From Emacs, use:

```text
SPC SPC n x
```

Process one item:

```sh
~/.emacs.d/scripts/save-link/save-link-snapshot \
  --item ~/All-The-Things/00-Capture/Ingest/Saved-Links/items/some-item.org
```

Force the Playwright/Readability extractor for one item:

```sh
~/.emacs.d/scripts/save-link/save-link-snapshot \
  --item ~/All-The-Things/00-Capture/Ingest/Saved-Links/items/some-item.org \
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

`save-link-capture` supports:

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
loxley-save-link-ingress.service
```

Endpoint:

```text
POST http://loxley:45741/capture
```

Required header:

```text
Authorization: Bearer <save_link_ingress_token>
```

Example:

```sh
curl -X POST http://loxley:45741/capture \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $SAVE_LINK_TOKEN" \
  -d '{"url":"https://example.com","title":"Example","source":"iphone","tags":["mobile"]}'
```

Health check:

```sh
curl http://loxley:45741/health
```

The token should be stored on loxley via `sops-nix` as:

```text
/run/secrets/save_link_ingress_token
```

## Current Boundary

Local Mac/Emacs captures create canonical `items/` entries and default to
metadata-only saves. Snapshot work happens only when you snapshot selected
items or run the snapshot queue processor.

There is no separate kind or state field in the current item contract.
`SNAPSHOT_STATUS` is the only lifecycle-like property: feed categories derive
`saved-link` versus `saved-article` from whether a readable snapshot exists.
Use tags, notes, and the capture log for lightweight context.

Loxley/mobile ingress is not the active capture path yet. A future worker
should accept remote/mobile captures and materialize them into the same
canonical `items/` format automatically.
