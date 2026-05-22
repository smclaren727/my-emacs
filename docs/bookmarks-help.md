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

Safari stores custom-URL-scheme permissions per website. To avoid an
Allow/Deny prompt on every domain, these bookmarklets open the org-protocol URL
from a temporary `about:blank` tab.

Use this setup bookmarklet once if Safari still prompts. Choose **Always
Allow**, then close the blank tab manually:

```javascript
javascript:(function(){var p=new URLSearchParams({url:location.href,title:document.title});var w=window.open();var a=w.document.createElement('a');a.href='org-protocol://bookmark?'+p.toString();w.document.body.appendChild(a);a.click();})();
```

After that, use this daily bookmarklet. It captures the page and closes the
temporary blank tab:

```javascript
javascript:(function(){var p=new URLSearchParams({url:location.href,title:document.title});var w=window.open();var a=w.document.createElement('a');a.href='org-protocol://bookmark?'+p.toString();w.document.body.appendChild(a);a.click();w.close();})();
```

Using the daily bookmarklet saves the current Safari page as a bookmark,
separate from the read-later capture flow.

Focus behavior is handled by `/Applications/Emacs Client.app`, which owns the
`org-protocol` URL scheme. Its `open location` handler should call
`emacsclient -n` only. If it also runs `open -a Emacs`, Safari will save
correctly but Emacs will come to the front after every capture.
