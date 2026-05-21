# Bookmarks Help

Bookmarks are stored in:

```text
~/All-The-Things/50-Resources/bookmarks.org
```

They are durable references: reusable sites, tools, dashboards, and links you
expect to come back to. Use read-later for interesting links you may or may not
return to.

## Emacs Commands

```text
SPC SPC m m   open bookmark picker
SPC SPC m a   add bookmark manually with org-capture
SPC SPC m c   copy bookmark URL
SPC SPC m f   open bookmarks.org
```

`M-x my-bookmarks-add-url` is the lower-level programmatic add command used by
the browser protocol handler. It writes under the `Inbox` heading and skips
duplicate URLs.

## Safari Bookmarklet

The bookmark module registers this org-protocol endpoint:

```text
org-protocol://bookmark
```

Create a Safari bookmark and replace its address with this bookmarklet:

```javascript
javascript:location.href='org-protocol://bookmark?'+new URLSearchParams({url:location.href,title:document.title});void(0)
```

Using this bookmarklet saves the current Safari page as a bookmark, separate
from the read-later capture flow.
