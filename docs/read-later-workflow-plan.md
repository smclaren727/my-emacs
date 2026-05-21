# Read-Later Workflow Plan

Status: proposed, not yet implemented.

## Working Model

The read-later system should probably separate lightweight capture from durable article archiving.

Elfeed is the model:

- The feed list is an inbox of possible reads.
- The show buffer is a preview or triage view.
- Visiting the article is a stronger intent signal.
- Saving or tagging is separate from archiving the full content.

The same distinction should apply to Safari, EWW, and manual captures.

## Proposed Item Types

| Type | Meaning | Content Stored |
|---|---|---|
| Saved link | Something that caught my eye and may be worth returning to. | URL, title, source, tags, note/selection, capture log. |
| Saved article | A link promoted into a durable knowledge artifact. | Saved-link metadata plus local readable snapshot. |
| Bookmark | A reusable reference, tool, or site. | Stays in the bookmark system, not read-later by default. |

## Likely Workflow

1. Capture defaults to saved-link only.
2. Saved links do not automatically queue full snapshot processing.
3. Capture may still preserve useful context, such as selected text from Safari or feed tags from Elfeed.
4. Review saved links later from the read-later folder.
5. Promote only selected links to saved articles.
6. Promotion runs snapshot processing for that item or marked items.
7. Promoted articles get readable content appended and `:SNAPSHOT_STATUS:` updated.

Example day:

- Save 20 links from Elfeed, Safari, EWW, and manual capture.
- Keep them as lightweight read-later items.
- Later decide 4 are worth preserving.
- Snapshot only those 4.

## Command Implications

Likely changes to consider:

| Command | Future Role |
|---|---|
| `SPC SPC n d` | Save current thing as a lightweight saved link. |
| `SPC SPC n w` | Save current page/link as a lightweight saved link. |
| Elfeed `d` | Save the feed entry as a lightweight saved link. |
| Safari bookmarklet | Save the page as a lightweight saved link. |
| `SPC SPC n x` | Process explicitly queued/promoted article snapshots. |
| New command | Promote current saved link to saved article. |
| New command | Promote marked read-later items to saved articles. |

## Open Questions

- Should capture default to `ARCHIVE_MODE: metadata` and `SNAPSHOT_STATUS: not-requested`?
- Should promotion add a separate property such as `:READING_STATE: article` or rely on `:SNAPSHOT_STATUS: ok`?
- Should saved links and saved articles live in the same `items/` folder or separate folders/views?
- Should Elfeed `d` save only metadata, while another key means save and snapshot immediately?
- Should Safari have one bookmarklet for saved links and another for save-and-snapshot?
- How should bookmarks remain distinct from read-later links when a URL could plausibly be either?

## Current Bias

Capture should be cheap and low-commitment. Snapshotting should become an explicit promote-to-article action.
