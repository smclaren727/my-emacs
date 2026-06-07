# Feeds Help

RSS and Atom subscriptions are stored in:

```text
~/All-The-Things/50-Resources/feeds.org
```

`elfeed-org` reads this file. Feeds live under the top-level
`* Feeds :elfeed:` heading, and browser captures land in `** Inbox :inbox:` so
they can be refiled or tagged later.

## Emacs Commands

```text
SPC SPC n f   open feeds.org
M-x my-feeds-add-url
```

`M-x my-feeds-add-url` is the lower-level programmatic add command used by the
browser protocol handler. It writes under the feed Inbox and skips duplicate
feed URLs.

## Safari Bookmarklet

The feeds module registers this org-protocol endpoint:

```text
org-protocol://feed
```

Safari stores custom-URL-scheme permissions per website. To avoid an
Allow/Deny prompt on every domain, these bookmarklets open the org-protocol URL
from a temporary `about:blank` tab.

Use this setup bookmarklet once if Safari still prompts. Choose **Always
Allow**, then close the blank tab manually:

```javascript
javascript:(function(){function pick(){var links=[].slice.call(document.querySelectorAll('link[rel~="alternate"]'));function score(l){var t=(l.type||'').toLowerCase(),h=(l.href||'').toLowerCase(),x=(l.title||'').toLowerCase();if(t==='application/rss+xml')return 1;if(t==='application/atom+xml')return 2;if(/rss|atom|xml/.test(t+' '+x+' '+h))return 3;return 99;}links=links.filter(function(l){return l.href&&score(l)<99;}).sort(function(a,b){return score(a)-score(b);});return links[0];}var f=pick();var p=new URLSearchParams({url:f?f.href:location.href,title:f&&(f.title||document.title)||document.title,page_url:location.href,type:f?(f.type||''):''});var w=window.open();var a=w.document.createElement('a');a.href='org-protocol://feed?'+p.toString();w.document.body.appendChild(a);a.click();})();
```

After that, use this daily bookmarklet. It captures the feed and closes the
temporary blank tab:

```javascript
javascript:(function(){function pick(){var links=[].slice.call(document.querySelectorAll('link[rel~="alternate"]'));function score(l){var t=(l.type||'').toLowerCase(),h=(l.href||'').toLowerCase(),x=(l.title||'').toLowerCase();if(t==='application/rss+xml')return 1;if(t==='application/atom+xml')return 2;if(/rss|atom|xml/.test(t+' '+x+' '+h))return 3;return 99;}links=links.filter(function(l){return l.href&&score(l)<99;}).sort(function(a,b){return score(a)-score(b);});return links[0];}var f=pick();var p=new URLSearchParams({url:f?f.href:location.href,title:f&&(f.title||document.title)||document.title,page_url:location.href,type:f?(f.type||''):''});var w=window.open();var a=w.document.createElement('a');a.href='org-protocol://feed?'+p.toString();w.document.body.appendChild(a);a.click();w.close();})();
```

The bookmarklet prefers RSS links, then Atom links, then other alternate links
that look feed-like. If no feed link is advertised, it saves the current Safari
URL as the subscription URL. Capturing only writes `feeds.org`; it does not
fetch the feed immediately.

Focus behavior is handled by `/Applications/Emacs Client.app`, which owns the
`org-protocol` URL scheme. Its `open location` handler should call
`emacsclient -n` only. If it also runs `open -a Emacs`, Safari will save
correctly but Emacs will come to the front after every capture.
