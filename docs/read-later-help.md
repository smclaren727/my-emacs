# Local-First Read-Later Help

This setup moves saved reading away from Readwise/Reader and into a shared
local-first folder. Emacs, Safari, Elfeed, iPhone shortcuts, and loxley all
write into the same read-later contract.

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
```

Local captures create an Org item in `items/`, dedupe by normalized URL, and
usually add a queue job for snapshotting. Duplicate saves append to the existing
item's capture log.

## Emacs Commands

Available with `M-x`:

```text
my-reading-capture-dwim
my-reading-capture-url
my-reading-capture-current-page
my-reading-capture-elfeed-entry
my-reading-import-readwise-export
my-reading-open-root
my-reading-open-queue
```

Leader bindings, using `C-c u` or the double-space leader:

```text
n d   capture DWIM
n w   capture current Emacs browser/page
n i   import Readwise/Reader export
n q   open read-later queue
n r   open read-later root
```

In Elfeed:

```text
d     save current Elfeed item to read-later
```

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

Capture the front Safari tab:

```sh
~/.emacs.d/scripts/read-later-safari
```

Process all queued local snapshots:

```sh
~/.emacs.d/scripts/read-later-snapshot --all
```

Process one item:

```sh
~/.emacs.d/scripts/read-later-snapshot \
  --item ~/All-The-Things/50-Resources/Read-Later/items/some-item.org
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

Default mode is `readable`.

## Loxley Ingress

Loxley runs:

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

The token is stored on loxley via `sops-nix` as:

```text
/run/secrets/read_later_ingress_token
```

## Current Boundary

Loxley ingress writes raw capture JSON into `queue/`. Local Mac/Emacs captures
already create `items/` plus snapshot queue jobs.

A future worker should materialize loxley ingress queue entries into canonical
`items/` files automatically.
