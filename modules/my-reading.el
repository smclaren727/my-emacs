;;; my-reading.el --- Local-first read-later captures -*- lexical-binding: t; -*-

;; The CLI scripts own the durable file format.  Emacs is the fast local
;; control surface for EWW, Elfeed, minibuffer captures, and Reader migration.

(require 'json)
(require 'seq)
(require 'subr-x)
(require 'thingatpt)

(declare-function elfeed-entry-link "elfeed-db" (entry))
(declare-function elfeed-entry-feed-id "elfeed-db" (entry))
(declare-function elfeed-entry-tags "elfeed-db" (entry))
(declare-function elfeed-entry-title "elfeed-db" (entry))
(declare-function elfeed-meta "elfeed-db" (entry prop &optional default))
(declare-function elfeed-db-save "elfeed-db" ())
(declare-function elfeed-search-selected "elfeed-search" (&optional ignore-region-p))
(declare-function elfeed-search-update-entry "elfeed-search" (entry))
(declare-function elfeed-tag "elfeed-db" (entry &rest tags))
(declare-function elfeed-update-feed "elfeed" (url))
(declare-function rmh-elfeed-org-process "elfeed-org" (files tree-id))

(defvar elfeed-show-entry)
(defvar elfeed-db-entries)
(defvar elfeed-new-entry-parse-hook)
(defvar elfeed-update-hooks)
(defvar eww-data)
(defvar org-protocol-protocol-alist)
(defvar rmh-elfeed-org-files)
(defvar rmh-elfeed-org-tree-id)

;;; Variables -----------------------------------------------------------

(defvar my-reading-root-directory
  (expand-file-name
   (or (getenv "MY_READING_ROOT")
       (expand-file-name "50-Resources/Read-Later/" my-notes-directory)))
  "Root directory for local-first read-later captures.")

(defvar my-reading-default-archive-mode "readable"
  "Default archive mode passed to `read-later-capture'.")

(defvar my-reading-feed-file "feed.xml"
  "Generated RSS feed filename under `my-reading-root-directory'.")

;;; Script helpers ------------------------------------------------------

(defvar my-reading-script-directory
  (when-let* ((directory (getenv "MY_READING_SCRIPT_DIR")))
    (unless (string-empty-p (string-trim directory))
      (file-name-as-directory (expand-file-name directory))))
  "Optional directory containing read-later helper scripts.")

(defconst my-reading--module-directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory containing this module when it was loaded.")

(defun my-reading--script-candidates (name)
  "Return candidate paths for read-later script NAME."
  (delete-dups
   (delq nil
         (list
          (when my-reading-script-directory
            (expand-file-name name my-reading-script-directory))
          (my-emacs-source-file (expand-file-name name "scripts/"))
          (expand-file-name (concat "scripts/" name) user-emacs-directory)
          (when my-reading--module-directory
            (expand-file-name (concat "../scripts/" name)
                              my-reading--module-directory))))))

(defun my-reading--script (name)
  "Return executable read-later script NAME."
  (let ((candidates (my-reading--script-candidates name)))
    (or (seq-find #'file-executable-p candidates)
        (user-error "No executable read-later script %s found. Checked: %s"
                    name
                    (string-join candidates ", ")))))

(defun my-reading--arg (name value)
  "Return CLI argument pair NAME VALUE when VALUE is a non-empty string."
  (when (and (stringp value) (not (string-empty-p (string-trim value))))
    (list name value)))

(defun my-reading--call-json (script &rest args)
  "Run SCRIPT with ARGS and parse one JSON object from stdout."
  (unless (and script (file-executable-p script))
    (let ((name (and script (file-name-nondirectory script))))
      (user-error "Read-later script is not executable: %s%s"
                  (or script "<none>")
                  (if name
                      (format " (checked: %s)"
                              (string-join
                               (my-reading--script-candidates name)
                               ", "))
                    ""))))
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

(defun my-reading-feed-path ()
  "Return the generated read-later RSS feed path."
  (expand-file-name my-reading-feed-file my-reading-root-directory))

(defun my-reading-feed-url ()
  "Return the generated read-later RSS feed as a file URL."
  (concat "file://" (expand-file-name (my-reading-feed-path))))

(defun my-reading-generate-feed ()
  "Generate the local read-later RSS feed from canonical Org items."
  (interactive)
  (let ((result
         (my-reading--call-json
          (my-reading--script "read-later-feed")
          "--root" my-reading-root-directory
          "--output" (my-reading-feed-path)
          "--json")))
    (when (called-interactively-p 'interactive)
      (message "Generated read-later feed with %s items: %s"
               (alist-get 'items result)
               (alist-get 'path result)))
    result))

(defun my-reading-update-feed ()
  "Generate the read-later RSS feed and update it in Elfeed when available."
  (interactive)
  (let ((result (my-reading-generate-feed)))
    (my-reading--refresh-elfeed-org-feeds)
    (if (fboundp 'elfeed-update-feed)
        (progn
          (elfeed-update-feed (my-reading-feed-url))
          (message "Updating read-later feed in Elfeed: %s"
                   (alist-get 'path result)))
      (message "Generated read-later feed; run Elfeed update after Elfeed loads: %s"
               (alist-get 'path result)))
    result))

(defun my-reading--update-elfeed-feed-quietly ()
  "Refresh the generated read-later feed in Elfeed when Elfeed is loaded."
  (when (fboundp 'elfeed-update-feed)
    (my-reading--refresh-elfeed-org-feeds)
    (elfeed-update-feed (my-reading-feed-url))))

(defun my-reading--refresh-elfeed-org-feeds ()
  "Refresh `elfeed-feeds' from elfeed-org when it is available."
  (when (and (boundp 'rmh-elfeed-org-files)
             (boundp 'rmh-elfeed-org-tree-id)
             (fboundp 'rmh-elfeed-org-process))
    (rmh-elfeed-org-process rmh-elfeed-org-files rmh-elfeed-org-tree-id)))

(defun my-reading--category-tag (category)
  "Return a safe Elfeed tag symbol for CATEGORY."
  (let ((tag (replace-regexp-in-string
              "[^A-Za-z0-9_@#.-]+" "-"
              (downcase (string-trim category)))))
    (unless (string-empty-p tag)
      (intern tag))))

(defun my-reading--elfeed-local-feed-entry-p (entry)
  "Return non-nil when ENTRY came from the generated read-later feed."
  (and (fboundp 'elfeed-entry-feed-id)
       (string= (elfeed-entry-feed-id entry) (my-reading-feed-url))))

(defun my-reading--elfeed-tag-local-feed-entry (entry)
  "Apply read-later search tags to generated Elfeed ENTRY."
  (when (my-reading--elfeed-local-feed-entry-p entry)
    (let* ((categories (and (fboundp 'elfeed-meta)
                            (elfeed-meta entry :categories)))
           (category-tags (delq nil (mapcar #'my-reading--category-tag categories))))
      (apply #'elfeed-tag entry (cons 'readlater category-tags)))))

(defun my-reading--elfeed-tag-local-feed-entry-from-parse (_type _item entry)
  "Apply read-later tags while Elfeed parses generated feed ENTRY."
  (my-reading--elfeed-tag-local-feed-entry entry))

(defun my-reading--elfeed-tag-local-feed-entries (&optional url)
  "Retag existing generated feed entries after Elfeed updates URL."
  (when (or (null url) (string= url (my-reading-feed-url)))
    (when (and (boundp 'elfeed-db-entries) (hash-table-p elfeed-db-entries))
      (maphash
       (lambda (_id entry)
         (my-reading--elfeed-tag-local-feed-entry entry))
       elfeed-db-entries)
      (when (fboundp 'elfeed-db-save)
        (elfeed-db-save)))))

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

;;; Org protocol helpers -----------------------------------------------

(defun my-reading--plist-string (plist property)
  "Return non-empty string value for PROPERTY in PLIST, or nil."
  (let ((value (plist-get plist property)))
    (when (and (stringp value) (not (string-empty-p (string-trim value))))
      value)))

(defun my-reading--archive-mode (value)
  "Return VALUE when it is a valid archive mode, otherwise the default."
  (if (member value '("readable" "metadata" "full" "defer"))
      value
    my-reading-default-archive-mode))

(defun my-reading-capture-org-protocol (info)
  "Capture a browser link from org-protocol INFO.
Expected INFO is a plist containing `:url', `:title', optional
`:body', `:source', `:tags', `:note', and `:archive-mode'."
  (let* ((url (my-reading--plist-string info :url))
         (title (or (my-reading--plist-string info :title) url))
         (selection (my-reading--plist-string info :body))
         (source (or (my-reading--plist-string info :source) "browser"))
         (tags (my-reading--plist-string info :tags))
         (note (my-reading--plist-string info :note))
         (archive-mode
          (my-reading--archive-mode
           (or (my-reading--plist-string info :archive-mode)
               (my-reading--plist-string info :archive_mode)))))
    (unless url
      (user-error "org-protocol read-later capture requires a URL"))
    (my-reading-capture-url url title source tags note selection archive-mode)
    nil))

(defun my-reading--register-org-protocol ()
  "Register the read-later org-protocol handler."
  (setq org-protocol-protocol-alist
        (cons
         '("read-later"
           :protocol "read-later"
           :function my-reading-capture-org-protocol
           :kill-client t)
         (seq-remove
          (lambda (entry)
            (string= "read-later" (plist-get (cdr entry) :protocol)))
          org-protocol-protocol-alist))))

(with-eval-after-load 'org-protocol
  (my-reading--register-org-protocol))

(require 'org-protocol nil t)

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

(defun my-reading-capture-url (url title &optional source tags note selection archive-mode feed-tags)
  "Capture URL with TITLE into the local read-later store.
SOURCE, TAGS, NOTE, SELECTION, ARCHIVE-MODE, and FEED-TAGS are
passed through to the CLI capture contract."
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
               (my-reading--arg "--feed-tags" feed-tags)
               (my-reading--arg "--note" note)
               (my-reading--arg "--selection" selection))))
    (prog1 (my-reading--message-result (apply #'my-reading--capture-script args))
      (my-reading--update-elfeed-feed-quietly))))

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
      (my-reading-capture-url url title "elfeed" "" "" "" my-reading-default-archive-mode tags)
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

(defun my-reading-snapshot-queue ()
  "Process all queued read-later snapshots."
  (interactive)
  (require 'compile)
  (let* ((default-directory (file-name-as-directory my-reading-root-directory))
         (script (my-reading--script "read-later-snapshot"))
         (command (mapconcat #'shell-quote-argument
                             (list script "--root" my-reading-root-directory "--all")
                             " ")))
    (compilation-start command 'compilation-mode
                       (lambda (_mode) "*read-later-snapshot*"))))

;;; Keybindings ---------------------------------------------------------

(my-leader-define "n d" #'my-reading-capture-dwim)
(my-leader-define "n l" #'my-reading-update-feed)
(my-leader-define "n q" #'my-reading-open-queue)
(my-leader-define "n r" #'my-reading-open-root)
(my-leader-define "n w" #'my-reading-capture-current-page)
(my-leader-define "n x" #'my-reading-snapshot-queue)

(with-eval-after-load 'elfeed
  (add-hook 'elfeed-new-entry-parse-hook
            #'my-reading--elfeed-tag-local-feed-entry-from-parse)
  (add-hook 'elfeed-update-hooks
            #'my-reading--elfeed-tag-local-feed-entries)
  (define-key elfeed-search-mode-map (kbd "d") #'my-reading-capture-elfeed-entry)
  (define-key elfeed-show-mode-map (kbd "d") #'my-reading-capture-elfeed-entry))

(with-eval-after-load 'which-key
  (which-key-add-keymap-based-replacements my-leader-map
    "n d" '("save to read-later" . my-reading-capture-dwim)
    "n l" '("update read-later feed" . my-reading-update-feed)
    "n q" "read-later queue"
    "n r" "read-later root"
    "n w" '("capture web page" . my-reading-capture-current-page)
    "n x" '("snapshot queue" . my-reading-snapshot-queue)))

(provide 'my-reading)
;;; my-reading.el ends here
