;;; my-feeds.el --- RSS feed reader with elfeed -*- lexical-binding: t; -*-

;; Elfeed provides the feed engine; elfeed-org lets us manage
;; subscriptions in an org file with hierarchical tagging.
;; org-web-tools handles full-article download via pandoc.

(require 'subr-x)
(require 'cl-lib)

;;; Variables -----------------------------------------------------------

(defvar my-feeds-directory
  (expand-file-name "saved-articles/" my-notes-directory)
  "Directory for downloaded article markdown files.")

(defvar my-feeds-org-file
  (expand-file-name "feeds.org" my-notes-directory)
  "Org file containing elfeed feed subscriptions.
Managed by elfeed-org — feeds are org headings tagged :elfeed:.")

;;; Elfeed — feed reader engine -----------------------------------------

(use-package elfeed
  :commands (elfeed elfeed-update)
  :custom
  ;; Store DB under no-littering var directory.
  (elfeed-db-directory (expand-file-name "elfeed/db/" (locate-user-emacs-file "var/")))
  ;; Use curl for faster, more reliable fetching.
  (elfeed-use-curl t)
  ;; Default search shows unread entries from the last 2 weeks.
  (elfeed-search-filter "@2-weeks-ago +unread")
  ;; Wider title column so long titles aren't truncated.
  (elfeed-search-title-max-width 100)
  :config
  ;; Ensure saved-articles directory exists.
  (make-directory my-feeds-directory t)
  :hook
  ;; Wrap long lines in article view.
  (elfeed-show-mode . visual-line-mode))

;;; elfeed-org — manage feeds in an org file ----------------------------

;; Feeds live in ~/Notes/feeds.org as org headings with :elfeed: tag.
;; Tags on parent headings inherit downward — no need to tag every feed.
(use-package elfeed-org
  :after elfeed
  :custom
  (rmh-elfeed-org-files (list my-feeds-org-file))
  :config
  (elfeed-org))

;;; org-web-tools — article download pipeline ---------------------------

;; Provides functions to fetch a URL through eww-readable and convert
;; to org via pandoc.  We use this as the first stage of article saving.
(use-package org-web-tools
  :commands (org-web-tools-read-url-as-org))

;;; Internal helpers ----------------------------------------------------

(defun my-feeds--slugify (title)
  "Convert TITLE to a filesystem-safe slug.
Downcase, replace non-alphanumeric runs with hyphens, trim edges."
  (let* ((slug (downcase title))
         (slug (replace-regexp-in-string "[^a-z0-9]+" "-" slug))
         (slug (replace-regexp-in-string "^-\\|-$" "" slug)))
    (if (string-empty-p slug) "untitled" slug)))

(defun my-feeds--entry-url ()
  "Return the URL of the current elfeed entry, or nil."
  (cond
   ;; In the article show buffer.
   ((derived-mode-p 'elfeed-show-mode)
    (elfeed-entry-link elfeed-show-entry))
   ;; In the search buffer — use entry at point.
   ((derived-mode-p 'elfeed-search-mode)
    (when-let ((entry (elfeed-search-selected :single)))
      (elfeed-entry-link entry)))))

(defun my-feeds--entry-at-point ()
  "Return the elfeed entry object at point, or nil."
  (cond
   ((derived-mode-p 'elfeed-show-mode)
    elfeed-show-entry)
   ((derived-mode-p 'elfeed-search-mode)
    (elfeed-search-selected :single))))

(defun my-feeds--article-to-markdown (url title &optional author date tags)
  "Fetch URL content, convert to markdown, and save to `my-feeds-directory'.
TITLE is used for the filename and front-matter.  Optional AUTHOR,
DATE, and TAGS are included in YAML front-matter."
  (let* ((slug (my-feeds--slugify title))
         (filename (concat slug ".md"))
         (filepath (expand-file-name filename my-feeds-directory))
         ;; Fetch readable HTML and convert to org via pandoc.
         (org-content (org-web-tools--url-as-readable-org url))
         ;; Convert org to markdown via pandoc.
         (md-content (when org-content
                       (with-temp-buffer
                         (insert org-content)
                         (call-process-region
                          (point-min) (point-max)
                          "pandoc" t t nil
                          "-f" "org" "-t" "markdown" "--wrap=none")
                         (buffer-string)))))
    (unless md-content
      (user-error "Failed to fetch article content from %s" url))
    ;; Build the file with YAML front-matter.
    (with-temp-file filepath
      (insert "---\n")
      (insert (format "title: \"%s\"\n" (string-replace "\"" "\\\"" title)))
      (when author
        (insert (format "author: \"%s\"\n" author)))
      (insert (format "date: %s\n" (or date (format-time-string "%Y-%m-%d"))))
      (insert (format "source: %s\n" url))
      (when tags
        (insert (format "tags: [%s]\n"
                        (mapconcat (lambda (tag) (format "\"%s\"" tag)) tags ", "))))
      (insert "---\n\n")
      (insert md-content))
    (message "Saved article to %s" filepath)
    filepath))

;;; Interactive commands ------------------------------------------------

(defun my-feeds-star ()
  "Toggle the `star' tag on the elfeed entry at point."
  (interactive)
  (let ((entries (if (derived-mode-p 'elfeed-search-mode)
                     (elfeed-search-selected)
                   (list (my-feeds--entry-at-point)))))
    (dolist (entry entries)
      (when entry
        (if (elfeed-tagged-p 'star entry)
            (elfeed-untag entry 'star)
          (elfeed-tag entry 'star))))
    ;; Refresh the display to show updated tags.
    (when (derived-mode-p 'elfeed-search-mode)
      (elfeed-search-update--force))))

(defun my-feeds-show-starred ()
  "Open elfeed filtered to starred entries."
  (interactive)
  (elfeed)
  (elfeed-search-set-filter "+star"))

(defun my-feeds-save-article ()
  "Download the current elfeed article and save as markdown.
The file is saved to `my-feeds-directory' with YAML front-matter
containing title, author, date, source URL, and tags."
  (interactive)
  (let ((entry (my-feeds--entry-at-point)))
    (unless entry
      (user-error "No elfeed entry at point"))
    (let* ((url (elfeed-entry-link entry))
           (title (elfeed-entry-title entry))
           ;; elfeed-entry-date returns seconds since epoch.
           (date (format-time-string "%Y-%m-%d"
                                     (seconds-to-time
                                      (elfeed-entry-date entry))))
           ;; Extract author if available via elfeed-meta.
           (authors (elfeed-meta entry :authors))
           (author-str (when authors
                         (mapconcat
                          (lambda (a) (or (plist-get a :name) ""))
                          authors ", ")))
           ;; Convert elfeed tags to strings, skip internal ones.
           (tags (cl-remove-if
                  (lambda (tag) (memq tag '(unread star)))
                  (elfeed-entry-tags entry)))
           (tag-strs (mapcar #'symbol-name tags)))
      (message "Downloading article: %s..." title)
      (condition-case err
          (my-feeds--article-to-markdown url title author-str date tag-strs)
        (error
         (user-error "Article download failed: %s" (error-message-string err)))))))

(defun my-feeds-open-feed-file ()
  "Open the feeds.org file for editing subscriptions."
  (interactive)
  (find-file my-feeds-org-file))

(defun my-feeds-browse-article ()
  "Open the current elfeed article in an external browser."
  (interactive)
  (let ((url (my-feeds--entry-url)))
    (unless url
      (user-error "No elfeed entry at point"))
    (browse-url url)))

;;; Mode-local keybindings ----------------------------------------------

;; Bind inside elfeed buffers for quick access.
(with-eval-after-load 'elfeed
  ;; Search mode — starring from the list.
  (define-key elfeed-search-mode-map (kbd "m") #'my-feeds-star)
  (define-key elfeed-search-mode-map (kbd "b") #'my-feeds-browse-article)
  ;; Show mode — article-level actions.
  (define-key elfeed-show-mode-map (kbd "m") #'my-feeds-star)
  (define-key elfeed-show-mode-map (kbd "d") #'my-feeds-save-article)
  (define-key elfeed-show-mode-map (kbd "b") #'my-feeds-browse-article))

(provide 'my-feeds)
;;; my-feeds.el ends here
