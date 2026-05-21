;;; my-reading.el --- Local-first read-later captures -*- lexical-binding: t; -*-

;; The CLI scripts own the durable file format.  Emacs is the fast local
;; control surface for EWW, Elfeed, minibuffer captures, and Reader migration.

(require 'json)
(require 'seq)
(require 'subr-x)
(require 'thingatpt)

(declare-function elfeed-entry-link "elfeed-db" (entry))
(declare-function elfeed-entry-tags "elfeed-db" (entry))
(declare-function elfeed-entry-title "elfeed-db" (entry))
(declare-function elfeed-search-selected "elfeed-search" (&optional ignore-region-p))
(declare-function elfeed-search-update-entry "elfeed-search" (entry))
(declare-function elfeed-tag "elfeed-db" (entry &rest tags))

(defvar elfeed-show-entry)
(defvar eww-data)

;;; Variables -----------------------------------------------------------

(defvar my-reading-root-directory
  (expand-file-name
   (or (getenv "MY_READING_ROOT")
       (expand-file-name "50-Resources/Read-Later/" my-notes-directory)))
  "Root directory for local-first read-later captures.")

(defvar my-reading-default-archive-mode "readable"
  "Default archive mode passed to `read-later-capture'.")

;;; Script helpers ------------------------------------------------------

(defun my-reading--script (name)
  "Return read-later script NAME from this config checkout."
  (my-emacs-source-file (expand-file-name name "scripts/")))

(defun my-reading--arg (name value)
  "Return CLI argument pair NAME VALUE when VALUE is a non-empty string."
  (when (and (stringp value) (not (string-empty-p (string-trim value))))
    (list name value)))

(defun my-reading--call-json (script &rest args)
  "Run SCRIPT with ARGS and parse one JSON object from stdout."
  (unless (file-executable-p script)
    (user-error "Read-later script is not executable: %s" script))
  (with-temp-buffer
    (let ((status (apply #'process-file script nil t nil args)))
      (unless (zerop status)
        (user-error "%s failed: %s" script (string-trim (buffer-string)))))
    (json-parse-string (buffer-string) :object-type 'alist :array-type 'list)))

(defun my-reading--capture-script (&rest args)
  "Run `read-later-capture' with ARGS."
  (apply #'my-reading--call-json
         (my-reading--script "read-later-capture")
         (append (list "--root" my-reading-root-directory "--json") args)))

(defun my-reading--region-text ()
  "Return active region text, or an empty string."
  (if (use-region-p)
      (buffer-substring-no-properties (region-beginning) (region-end))
    ""))

(defun my-reading--message-result (result)
  "Display capture RESULT and return the item path."
  (let ((path (alist-get 'path result))
        (duplicate (alist-get 'duplicate result)))
    (message "%s read-later item: %s"
             (if duplicate "Updated" "Captured")
             path)
    path))

;;; Browser helpers -----------------------------------------------------

(defun my-reading--eww-data-value (property)
  "Return PROPERTY from EWW's current page data, or nil."
  (when (and (boundp 'eww-data) (listp eww-data))
    (plist-get eww-data property)))

(defun my-reading--current-page-url ()
  "Return the current browser page URL or URL at point."
  (cond
   ((derived-mode-p 'eww-mode)
    (my-reading--eww-data-value :url))
   ((thing-at-point-url-at-point))))

(defun my-reading--current-page-title (url)
  "Return the current browser page title, falling back to URL."
  (cond
   ((derived-mode-p 'eww-mode)
    (or (my-reading--eww-data-value :title) url))
   (t
    (read-string "Title: " nil nil url))))

;;; Capture commands ----------------------------------------------------

(defun my-reading-capture-url (url title &optional source tags note selection archive-mode)
  "Capture URL with TITLE into the local read-later store.
SOURCE, TAGS, NOTE, SELECTION, and ARCHIVE-MODE are passed through
to the CLI capture contract."
  (interactive
   (list
    (read-string "URL: " (or (thing-at-point-url-at-point) ""))
    (read-string "Title: ")
    "manual"
    (read-string "Tags: ")
    (read-string "Note: ")
    (my-reading--region-text)
    (completing-read "Archive mode: "
                     '("readable" "metadata" "full" "defer")
                     nil t nil nil my-reading-default-archive-mode)))
  (let ((args (append
               (list "--url" url
                     "--title" title
                     "--source" (or source "manual")
                     "--archive-mode" (or archive-mode my-reading-default-archive-mode))
               (my-reading--arg "--tags" tags)
               (my-reading--arg "--note" note)
               (my-reading--arg "--selection" selection))))
    (my-reading--message-result (apply #'my-reading--capture-script args))))

(defun my-reading-capture-current-page ()
  "Capture the current Emacs browser page or URL at point."
  (interactive)
  (let* ((url (or (my-reading--current-page-url)
                  (read-string "URL: ")))
         (title (my-reading--current-page-title url))
         (source (if (derived-mode-p 'eww-mode) "eww" "emacs"))
         (selection (my-reading--region-text)))
    (when (string-empty-p (string-trim url))
      (user-error "No page URL found"))
    (my-reading-capture-url url title source "" "" selection my-reading-default-archive-mode)))

(defun my-reading--elfeed-entry-at-point ()
  "Return the current Elfeed entry."
  (cond
   ((derived-mode-p 'elfeed-show-mode)
    elfeed-show-entry)
   ((derived-mode-p 'elfeed-search-mode)
    (elfeed-search-selected :single))))

(defun my-reading-capture-elfeed-entry ()
  "Capture the current Elfeed entry into the read-later store."
  (interactive)
  (let ((entry (my-reading--elfeed-entry-at-point)))
    (unless entry
      (user-error "No Elfeed entry at point"))
    (let* ((url (elfeed-entry-link entry))
           (title (elfeed-entry-title entry))
           (tags (mapconcat
                  #'symbol-name
                  (seq-remove (lambda (tag) (memq tag '(unread star saved)))
                              (elfeed-entry-tags entry))
                  ",")))
      (my-reading-capture-url url title "elfeed" tags "" "" my-reading-default-archive-mode)
      (elfeed-tag entry 'saved)
      (when (derived-mode-p 'elfeed-search-mode)
        (elfeed-search-update-entry entry)))))

(defun my-reading-capture-dwim ()
  "Capture the current thing: Elfeed entry, Emacs browser page, or URL."
  (interactive)
  (cond
   ((or (derived-mode-p 'elfeed-show-mode)
        (derived-mode-p 'elfeed-search-mode))
    (my-reading-capture-elfeed-entry))
   ((or (derived-mode-p 'eww-mode)
        (thing-at-point-url-at-point))
    (my-reading-capture-current-page))
   (t
    (call-interactively #'my-reading-capture-url))))

(defun my-reading-import-readwise-export (path)
  "Import a one-time Readwise/Reader export file at PATH."
  (interactive "fReadwise export file: ")
  (let ((result
         (my-reading--call-json
          (my-reading--script "readwise-export-import")
          "--root" my-reading-root-directory
          "--json"
          (expand-file-name path))))
    (message "Readwise import processed %d records" (length result))
    result))

(defun my-reading-open-root ()
  "Open the read-later root directory."
  (interactive)
  (dired my-reading-root-directory))

(defun my-reading-open-queue ()
  "Open the read-later ingest queue."
  (interactive)
  (dired (expand-file-name "queue/" my-reading-root-directory)))

;;; Keybindings ---------------------------------------------------------

(my-leader-define "n d" #'my-reading-capture-dwim)
(my-leader-define "n i" #'my-reading-import-readwise-export)
(my-leader-define "n q" #'my-reading-open-queue)
(my-leader-define "n r" #'my-reading-open-root)
(my-leader-define "n w" #'my-reading-capture-current-page)

(with-eval-after-load 'elfeed
  (define-key elfeed-search-mode-map (kbd "d") #'my-reading-capture-elfeed-entry)
  (define-key elfeed-show-mode-map (kbd "d") #'my-reading-capture-elfeed-entry))

(with-eval-after-load 'which-key
  (which-key-add-keymap-based-replacements my-leader-map
    "n d" "capture"
    "n i" "import Readwise"
    "n q" "read-later queue"
    "n r" "read-later root"
    "n w" "capture web page"))

(provide 'my-reading)
;;; my-reading.el ends here
