;;; my-feeds.el --- RSS feed reader with elfeed -*- lexical-binding: t; -*-

;; Elfeed provides the feed engine; elfeed-org lets us manage
;; subscriptions in an org file with hierarchical tagging.
;; org-web-tools handles full-article download via pandoc.

(require 'subr-x)
(require 'cl-lib)

(declare-function elfeed "elfeed")
(declare-function elfeed-entry-date "elfeed-db" (entry))
(declare-function elfeed-entry-feed "elfeed-db" (entry))
(declare-function elfeed-entry-link "elfeed-db" (entry))
(declare-function elfeed-entry-tags "elfeed-db" (entry))
(declare-function elfeed-entry-title "elfeed-db" (entry))
(declare-function elfeed-feed-title "elfeed-db" (feed))
(declare-function elfeed-format-column "elfeed-lib" (string width &optional align))
(declare-function elfeed-meta "elfeed-db" (entry prop &optional default))
(declare-function elfeed-search-buffer "elfeed-search")
(declare-function elfeed-search--faces "elfeed-search" (tags))
(declare-function elfeed-search-format-date "elfeed-search" (date))
(declare-function elfeed-search-selected "elfeed-search" (&optional ignore-region-p))
(declare-function elfeed-search-set-filter "elfeed-search" (filter))
(declare-function elfeed-search-show-entry "elfeed-search" (entry))
(declare-function elfeed-search-update--force "elfeed-search")
(declare-function elfeed-search-update-entry "elfeed-search" (entry))
(declare-function elfeed-tag "elfeed-db" (entry &rest tags))
(declare-function elfeed-tagged-p "elfeed-db" (tag entry))
(declare-function elfeed-untag "elfeed-db" (entry &rest tags))
(declare-function elfeed-update "elfeed")
(declare-function face-remap-add-relative "face-remap" (face &rest specs))
(declare-function face-remap-remove-relative "face-remap" (cookie))
(declare-function elfeed-goodies/setup "elfeed-goodies")
(declare-function powerline-raw "powerline" (str &optional face pad))
(declare-function powerline-render "powerline" (values))
(declare-function elfeed-tube-fetch "elfeed-tube" (&optional video-id update-p))
(declare-function elfeed-tube-mpv-follow-mode "elfeed-tube-mpv")
(declare-function elfeed-tube-mpv-where "elfeed-tube-mpv")
(declare-function elfeed-tube-save "elfeed-tube")
(declare-function elfeed-tube-setup "elfeed-tube")
(declare-function org-web-tools--url-as-readable-org "org-web-tools" (url))

(defvar elfeed-goodies/feed-source-column-width)
(defvar elfeed-goodies/entry-pane-position)
(defvar elfeed-goodies/entry-pane-size)
(defvar elfeed-goodies/powerline-default-separator)
(defvar elfeed-goodies/show-mode-padding)
(defvar elfeed-goodies/switch-to-entry)
(defvar elfeed-goodies/tag-column-width)
(defvar elfeed-search-date-format)
(defvar elfeed-search-header-function)
(defvar elfeed-search-mode-map)
(defvar elfeed-search-print-entry-function)
(defvar elfeed-search-remain-on-entry)
(defvar elfeed-search-title-min-width)
(defvar elfeed-show-entry)
(defvar elfeed-show-mode-map)
(defvar powerline-default-separator-dir)
(defvar powerline-utf-8-separator-left)
(defvar powerline-utf-8-separator-right)

;;; Variables -----------------------------------------------------------

(defface my-feeds-search-header-active1
  '((t (:inherit powerline-active1)))
  "Light Powerline face for the Elfeed search header."
  :group 'faces)

(defface my-feeds-search-header-active2
  '((t (:inherit powerline-active2)))
  "Dark Powerline face for the Elfeed search header."
  :group 'faces)

(defvar my-feeds-directory nil
  "Directory for downloaded article Org files.")
(setq my-feeds-directory
      (expand-file-name "50-Resources/Saved-Articles/" my-notes-directory))

(defvar my-feeds-org-file nil
  "Org file containing elfeed feed subscriptions.
Managed by elfeed-org — feeds are org headings tagged :elfeed:.")
(setq my-feeds-org-file
      (expand-file-name "50-Resources/feeds.org" my-notes-directory))

(defvar my-feeds-update-interval (* 6 60 60)
  "Seconds between automatic Elfeed updates.")

(defvar my-feeds-update-timer nil
  "Timer used for automatic Elfeed updates.")

(defvar my-feeds-search-font-scale 1.08
  "Relative font scale used in the Elfeed search buffer.")

(defvar my-feeds-search-line-spacing 0.36
  "Buffer-local line spacing used in the Elfeed search buffer.")

(defvar my-feeds-search-date-extra-width 2
  "Extra padding after dates in the Elfeed search buffer.")

(defvar-local my-feeds-search--font-remap-cookie nil
  "Face-remap cookie for Elfeed search font scaling.")

(defvar-local my-feeds-search--last-window-width nil
  "Last rendered window width for the current Elfeed search buffer.")

(defvar-local my-feeds-search--resize-timer nil
  "Debounce timer for Elfeed search redraws after window resizing.")

(defvar-local my-feeds-show--font-remap-cookie nil
  "Face-remap cookie for Elfeed show font scaling.")

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
  ;; Keep the stock Elfeed fallback renderer roomy.
  (elfeed-search-title-max-width 100)
  :config
  ;; Ensure Saved-Articles directory exists.
  (make-directory my-feeds-directory t)
  :hook
  ;; Wrap long lines in article view.
  (elfeed-show-mode . visual-line-mode))

(defun my-feeds-start-auto-update ()
  "Start automatic Elfeed updates, replacing any existing timer."
  (interactive)
  (when (timerp my-feeds-update-timer)
    (cancel-timer my-feeds-update-timer))
  (setq my-feeds-update-timer
        (run-at-time nil my-feeds-update-interval #'elfeed-update)))

(defun my-feeds-search-visual-setup ()
  "Apply buffer-local readability tweaks for the Elfeed search buffer."
  (setq-local line-spacing my-feeds-search-line-spacing)
  (setq-local my-feeds-search--last-window-width
              (my-feeds--search-window-width))
  (add-hook 'window-size-change-functions
            #'my-feeds-search-refresh-on-resize nil t)
  (when my-feeds-search--font-remap-cookie
    (face-remap-remove-relative my-feeds-search--font-remap-cookie))
  (setq-local my-feeds-search--font-remap-cookie
              (face-remap-add-relative 'default :height my-feeds-search-font-scale)))

(defun my-feeds--search-date-column-width ()
  "Return the configured Elfeed search date column width."
  (+ (or (cadr elfeed-search-date-format) 10)
     my-feeds-search-date-extra-width))

(defun my-feeds--center-header-label (label width)
  "Return LABEL centered in a header column WIDTH characters wide."
  (let* ((label (truncate-string-to-width label width))
         (padding (max 0 (- width (string-width label))))
         (left-padding (/ padding 2))
         (right-padding (- padding left-padding)))
    (concat (make-string left-padding ?\s)
            label
            (make-string right-padding ?\s))))

(defun my-feeds--search-window-width ()
  "Return the visible width of the Elfeed search window."
  (if-let* ((window (get-buffer-window (current-buffer) t)))
      (window-body-width window)
    (window-body-width)))

(defun my-feeds--header-window-width ()
  "Return the width available to Powerline headers.

Leaving one cell for the right fringe keeps Emacs from drawing a
truncation marker over the end of the header."
  (max 1 (1- (my-feeds--search-window-width))))

(defun my-feeds--search-layout (&optional window-width)
  "Return Elfeed search column widths as (DATE TAG SUBJECT FEED).

When WINDOW-WIDTH is non-nil, size the layout to that width instead of
the current window body width."
  (let* ((date-width (my-feeds--search-date-column-width))
         (tag-width elfeed-goodies/tag-column-width)
         (feed-width elfeed-goodies/feed-source-column-width)
         (window-width (or window-width (my-feeds--search-window-width)))
         (gap-width 3)
         (subject-min-width (max (string-width "Subject")
                                 elfeed-search-title-min-width))
         (subject-width
          (- window-width date-width tag-width feed-width gap-width)))
    (when (< subject-width subject-min-width)
      (let ((shortage (- subject-min-width subject-width)))
        (let ((feed-reduction (min shortage (max 0 (- feed-width 18)))))
          (setq feed-width (- feed-width feed-reduction)
                shortage (- shortage feed-reduction)))
        (let ((tag-reduction (min shortage (max 0 (- tag-width 12)))))
          (setq tag-width (- tag-width tag-reduction)))))
    (list date-width
          tag-width
          (max 1 (- window-width date-width tag-width feed-width gap-width))
          feed-width)))

(defun my-feeds--header-box-width ()
  "Return the box width used by `header-line'."
  (let ((box (face-attribute 'header-line :box nil)))
    (or (and (listp box) (plist-get box :line-width))
        0)))

(defun my-feeds--sync-powerline-header-face (target source)
  "Make TARGET match SOURCE colors with full `header-line' height."
  (let* ((background (face-background source nil t))
         (foreground (face-foreground source nil t))
         (box-width (my-feeds--header-box-width)))
    (set-face-attribute
     target nil
     :inherit source
     :background background
     :foreground foreground
     :box `(:line-width ,box-width :color ,background :style nil))))

(defun my-feeds--sync-powerline-header-faces ()
  "Synchronize Elfeed header faces with the active theme."
  (my-feeds--sync-powerline-header-face
   'my-feeds-search-header-active1 'powerline-active1)
  (my-feeds--sync-powerline-header-face
   'my-feeds-search-header-active2 'powerline-active2))

(defun my-feeds--powerline-separator (face1 face2)
  "Return an Elfeed header Powerline separator from FACE1 to FACE2."
  (if (eq elfeed-goodies/powerline-default-separator 'utf-8)
      (let* ((direction (car powerline-default-separator-dir))
             (separator (if (eq direction 'left)
                            powerline-utf-8-separator-left
                          powerline-utf-8-separator-right))
             (foreground (face-background face1 nil t))
             (background (face-background face2 nil t))
             (box-width (my-feeds--header-box-width)))
        (powerline-raw
         (char-to-string separator)
         `(:foreground ,foreground
           :background ,background
           :box (:line-width ,box-width :color ,background :style nil)
           :inverse-video nil)))
    (let ((separator (intern (format "powerline-%s-%s"
                                     elfeed-goodies/powerline-default-separator
                                     (car powerline-default-separator-dir)))))
      (when (fboundp separator)
        (funcall separator face1 face2)))))

(defun my-feeds--powerline-header-column (text width face align)
  "Return a Powerline header column for TEXT, WIDTH, FACE, and ALIGN."
  (powerline-raw
   (pcase align
     ('center (my-feeds--center-header-label text width))
     (_ (elfeed-format-column (concat " " (or text "") " ") width :left)))
   face))

(defun my-feeds--powerline-header (columns)
  "Draw a Date / Tags / Subject / Feed Source header from COLUMNS.

COLUMNS is a four-item list where each item is (TEXT ALIGN).  ALIGN may
be `center' for headings or `left' for entry values."
  (cl-destructuring-bind (date-width tag-width subject-width feed-width)
      (my-feeds--search-layout (my-feeds--header-window-width))
    (my-feeds--sync-powerline-header-faces)
    (let* ((date-face 'my-feeds-search-header-active1)
           (tag-face 'my-feeds-search-header-active2)
           (subject-face 'my-feeds-search-header-active1)
           (feed-face 'my-feeds-search-header-active2)
           (widths (list date-width tag-width subject-width feed-width))
           (faces (list date-face tag-face subject-face feed-face))
           (next-faces (list tag-face subject-face feed-face nil))
           segments)
      (cl-loop for (text align) in columns
               for width in widths
               for face in faces
               for next-face in next-faces
               do (push (my-feeds--powerline-header-column
                         text width face align)
                        segments)
                  (when next-face
                    (push (my-feeds--powerline-separator face next-face)
                          segments)))
      (powerline-render (nreverse segments)))))

(defun my-feeds-search-refresh-on-resize (window)
  "Refresh the Elfeed search listing after WINDOW changes width."
  (let ((width (window-body-width window)))
    (when (and (derived-mode-p 'elfeed-search-mode)
               (not (equal width my-feeds-search--last-window-width)))
      (setq my-feeds-search--last-window-width width)
      (when (timerp my-feeds-search--resize-timer)
        (cancel-timer my-feeds-search--resize-timer))
      (setq my-feeds-search--resize-timer
            (run-at-time
             0.2 nil
             (lambda (buffer)
               (when (buffer-live-p buffer)
                 (with-current-buffer buffer
                   (setq my-feeds-search--resize-timer nil)
                   (when (derived-mode-p 'elfeed-search-mode)
                     (elfeed-search-update--force)
                     (force-mode-line-update)))))
             (current-buffer))))))

(defun my-feeds-search-header-draw ()
  "Draw the Elfeed search header with the preferred column order."
  (my-feeds--powerline-header
   '(("Date" center)
     ("Tags" center)
     ("Subject" center)
     ("Feed Source" center))))

(defun my-feeds-show-header-draw ()
  "Draw the Elfeed show header with the same order as search rows."
  (when elfeed-show-entry
    (let* ((date (format-time-string
                  "%Y-%m-%d"
                  (seconds-to-time (elfeed-entry-date elfeed-show-entry))))
           (tags (mapcar #'symbol-name
                         (elfeed-entry-tags elfeed-show-entry)))
           (tags-str (concat "[" (mapconcat #'identity tags ",") "]"))
           (title (or (elfeed-meta elfeed-show-entry :title)
                      (elfeed-entry-title elfeed-show-entry)
                      ""))
           (feed (elfeed-entry-feed elfeed-show-entry))
           (feed-title (if feed
                           (or (elfeed-meta feed :title)
                               (elfeed-feed-title feed))
                         "")))
      (my-feeds--powerline-header
       (list (list date 'left)
             (list tags-str 'left)
             (list title 'left)
             (list feed-title 'left))))))

(defun my-feeds-show-visual-setup ()
  "Apply visual tweaks for the Elfeed show buffer."
  (setq-local header-line-format '(:eval (my-feeds-show-header-draw))
              line-spacing my-feeds-search-line-spacing)
  (when my-feeds-show--font-remap-cookie
    (face-remap-remove-relative my-feeds-show--font-remap-cookie))
  (setq-local my-feeds-show--font-remap-cookie
              (face-remap-add-relative 'default :height my-feeds-search-font-scale))
  (dolist (window (get-buffer-window-list (current-buffer) nil t))
    (set-window-margins window nil nil)))

(defun my-feeds-search-entry-line-draw (entry)
  "Print ENTRY using Date, Tags, Subject, Feed Source columns."
  (cl-destructuring-bind (date-width tag-width subject-width feed-width)
      (my-feeds--search-layout (my-feeds--header-window-width))
    (let* ((date (elfeed-search-format-date (elfeed-entry-date entry)))
           (title (or (elfeed-meta entry :title) (elfeed-entry-title entry) ""))
           (title-faces (elfeed-search--faces (elfeed-entry-tags entry)))
           (feed (elfeed-entry-feed entry))
           (feed-title (if feed
                           (or (elfeed-meta feed :title) (elfeed-feed-title feed))
                         ""))
           (tags (mapcar #'symbol-name (elfeed-entry-tags entry)))
           (tags-str (concat "[" (mapconcat #'identity tags ",") "]"))
           (date-column (elfeed-format-column date date-width :left))
           (tag-column (elfeed-format-column tags-str tag-width :left))
           (feed-column (elfeed-format-column feed-title feed-width :left))
           (title-column (elfeed-format-column title subject-width :left)))
      (insert (propertize date-column 'face 'elfeed-search-date-face) " ")
      (insert (propertize tag-column 'face 'elfeed-search-tag-face) " ")
      (insert (propertize title-column 'face title-faces 'kbd-help title) " ")
      (insert (propertize feed-column 'face 'elfeed-search-feed-face)))))

(unless noninteractive
  (my-feeds-start-auto-update))

;;; elfeed-goodies — visual enhancements -------------------------------

(use-package elfeed-goodies
  :after elfeed
  :demand t
  :custom
  ;; Keep search selected while showing entry previews below it.
  (elfeed-goodies/entry-pane-position 'bottom)
  (elfeed-goodies/entry-pane-size 0.5)
  ;; Keep search and preview headers on the same width budget.
  (elfeed-goodies/show-mode-padding 0)
  (elfeed-goodies/switch-to-entry nil)
  ;; Give long source names like "Hacker News - Front Page" room to breathe.
  (elfeed-goodies/feed-source-column-width 48)
  ;; UTF-8 separators avoid the chunky image wedges from `arrow-fade'.
  (elfeed-goodies/powerline-default-separator 'utf-8)
  :config
  (elfeed-goodies/setup)
  (setq elfeed-search-header-function #'my-feeds-search-header-draw
        elfeed-search-print-entry-function #'my-feeds-search-entry-line-draw)
  (add-hook 'elfeed-show-mode-hook #'my-feeds-show-visual-setup t)
  :hook
  (elfeed-search-mode . my-feeds-search-visual-setup))

;;; elfeed-tube — richer YouTube entries --------------------------------

(use-package elfeed-tube
  :after elfeed
  :demand t
  :custom
  ;; Prefer yt-dlp for richer metadata now that Invidious API access is spotty.
  (elfeed-tube-backend 'yt-dlp)
  :config
  (elfeed-tube-setup)
  :bind (:map elfeed-show-mode-map
              ("F" . elfeed-tube-fetch)
              ([remap save-buffer] . elfeed-tube-save)
              :map elfeed-search-mode-map
              ("F" . elfeed-tube-fetch)
              ([remap save-buffer] . elfeed-tube-save)))

;;; elfeed-tube-mpv — live transcript playback -------------------------

(use-package elfeed-tube-mpv
  :after elfeed-tube
  :bind (:map elfeed-show-mode-map
              ("C-c C-f" . elfeed-tube-mpv-follow-mode)
              ("C-c C-w" . elfeed-tube-mpv-where)))

;;; elfeed-org — manage feeds in an org file ----------------------------

;; Feeds live in ~/All-The-Things/50-Resources/feeds.org as org headings with :elfeed: tag.
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
    (when-let* ((entry (elfeed-search-selected :single)))
      (elfeed-entry-link entry)))))

(defun my-feeds--entry-at-point ()
  "Return the elfeed entry object at point, or nil."
  (cond
   ((derived-mode-p 'elfeed-show-mode)
    elfeed-show-entry)
   ((derived-mode-p 'elfeed-search-mode)
    (elfeed-search-selected :single))))

(defun my-feeds--selected-entries ()
  "Return selected elfeed entries for the current buffer."
  (cond
   ((derived-mode-p 'elfeed-search-mode)
    (elfeed-search-selected))
   ((derived-mode-p 'elfeed-show-mode)
    (when elfeed-show-entry
      (list elfeed-show-entry)))))

(defun my-feeds--browse-url-background (url)
  "Open URL in the system browser without focusing it."
  (pcase system-type
    ('darwin
     (unless (executable-find "open")
       (user-error "macOS open command not found"))
     (start-process (format "open background %s" url)
                    nil "open" "--background" url))
    (_
     (user-error "Background browser opening is only configured for macOS"))))

(defun my-feeds--mark-entry-read (entry)
  "Mark ENTRY read and refresh visible elfeed buffers."
  (elfeed-untag entry 'unread)
  (when (derived-mode-p 'elfeed-search-mode)
    (elfeed-search-update-entry entry))
  (when-let* ((search-buffer (and (fboundp 'elfeed-search-buffer)
                                  (get-buffer (elfeed-search-buffer)))))
    (with-current-buffer search-buffer
      (elfeed-search-update-entry entry))))

(defun my-feeds--article-to-org (url title &optional author date tags)
  "Fetch URL content and save as org to `my-feeds-directory'.
TITLE is used for the filename and header.  Optional AUTHOR,
DATE, and TAGS are included as org metadata."
  (let* ((slug (my-feeds--slugify title))
         (filename (concat slug ".org"))
         (filepath (expand-file-name filename my-feeds-directory))
         (org-content (progn
                        (require 'org-web-tools)
                        (org-web-tools--url-as-readable-org url))))
    (unless org-content
      (user-error "Failed to fetch article content from %s" url))
    (with-temp-file filepath
      (insert (format "#+title: %s\n" title))
      (when author
        (insert (format "#+author: %s\n" author)))
      (insert (format "#+date: %s\n" (or date (format-time-string "%Y-%m-%d"))))
      (insert "\n:PROPERTIES:\n")
      (insert (format ":URL: %s\n" url))
      (when tags
        (insert (format ":TAGS: %s\n" (mapconcat #'identity tags ","))))
      (insert ":END:\n\n")
      (insert org-content))
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
  "Download the current elfeed article and save it as an Org file.
The file is saved to `my-feeds-directory' with title, author, date,
URL property, and tags."
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
          (my-feeds--article-to-org url title author-str date tag-strs)
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

(defun my-feeds-browse-background-article ()
  "Open current or selected elfeed articles without focusing the browser.
In `elfeed-search-mode', open all selected entries.  In
`elfeed-show-mode', open the displayed entry."
  (interactive)
  (let ((buffer (current-buffer))
        (entries (my-feeds--selected-entries)))
    (unless entries
      (user-error "No elfeed entry at point"))
    (dolist (entry entries)
      (when-let* ((url (elfeed-entry-link entry)))
        (my-feeds--browse-url-background url)
        (my-feeds--mark-entry-read entry)))
    (when (derived-mode-p 'elfeed-search-mode)
      (with-current-buffer buffer
        (unless (or elfeed-search-remain-on-entry (use-region-p))
          (forward-line))))))

(defun my-feeds-search-preview-entry (&optional lines)
  "Preview the Elfeed entry LINES away while keeping search selected."
  (interactive)
  (let ((origin (point))
        (search-window (selected-window))
        (lines (or lines 0)))
    (forward-line lines)
    (if-let* ((entry (elfeed-search-selected :ignore-region)))
        (progn
          (recenter)
          (elfeed-search-show-entry entry)
          (when (window-live-p search-window)
            (select-window search-window))
          (unless elfeed-search-remain-on-entry
            (forward-line -1)))
      (goto-char origin)
      (user-error "No Elfeed entry at point"))))

(defun my-feeds-search-preview-next (&optional count)
  "Preview the next COUNT Elfeed entry without leaving search."
  (interactive "p")
  (my-feeds-search-preview-entry (or count 1)))

(defun my-feeds-search-preview-previous (&optional count)
  "Preview the previous COUNT Elfeed entry without leaving search."
  (interactive "p")
  (my-feeds-search-preview-entry (- (or count 1))))

(defun my-feeds-search-preview-current ()
  "Preview the current Elfeed entry without leaving search."
  (interactive)
  (my-feeds-search-preview-entry 0))

;;; Mode-local keybindings ----------------------------------------------

;; Bind inside elfeed buffers for quick access.
(with-eval-after-load 'elfeed
  ;; Search mode — starring from the list.
  (define-key elfeed-search-mode-map (kbd "m") #'my-feeds-star)
  (define-key elfeed-search-mode-map (kbd "n") #'my-feeds-search-preview-next)
  (define-key elfeed-search-mode-map (kbd "p") #'my-feeds-search-preview-previous)
  (define-key elfeed-search-mode-map (kbd "M-RET") #'my-feeds-search-preview-current)
  (define-key elfeed-search-mode-map (kbd "b") #'my-feeds-browse-article)
  (define-key elfeed-search-mode-map (kbd "B") #'my-feeds-browse-background-article)
  ;; Show mode — article-level actions.
  (define-key elfeed-show-mode-map (kbd "m") #'my-feeds-star)
  (define-key elfeed-show-mode-map (kbd "d") #'my-feeds-save-article)
  (define-key elfeed-show-mode-map (kbd "b") #'my-feeds-browse-article)
  (define-key elfeed-show-mode-map (kbd "B") #'my-feeds-browse-background-article))

(provide 'my-feeds)
;;; my-feeds.el ends here
