;;; my-reading.el --- Local-first read-later captures -*- lexical-binding: t; -*-

;; The CLI scripts own the durable file format.  Emacs is the fast local
;; control surface for EWW, Elfeed, minibuffer captures, and Reader migration.

(require 'json)
(require 'seq)
(require 'subr-x)
(require 'thingatpt)

(declare-function elfeed-entry-link "elfeed-db" (entry))
(declare-function elfeed-entry-id "elfeed-db" (entry))
(declare-function elfeed-entry-feed-id "elfeed-db" (entry))
(declare-function elfeed-entry-tags "elfeed-db" (entry))
(declare-function elfeed-entry-title "elfeed-db" (entry))
(declare-function elfeed-db-gc "elfeed-db" (&optional stats-p))
(declare-function elfeed-meta "elfeed-db" (entry prop &optional default))
(declare-function elfeed-db-save "elfeed-db" ())
(declare-function elfeed-db-set-update-time "elfeed-db" ())
(declare-function elfeed-search-buffer "elfeed-search")
(declare-function elfeed-search-selected "elfeed-search" (&optional ignore-region-p))
(declare-function elfeed-search-update--force "elfeed-search")
(declare-function elfeed-search-update-entry "elfeed-search" (entry))
(declare-function elfeed-tag "elfeed-db" (entry &rest tags))
(declare-function elfeed-update-feed "elfeed" (url))
(declare-function rmh-elfeed-org-process "elfeed-org" (files tree-id))
(declare-function avl-tree-delete "avl-tree" (tree data))
(declare-function dired-get-filename "dired" (&optional localp no-error-if-not-filep))
(declare-function dired-get-marked-files "dired" (&optional localp arg filter distinguish-one-marked error))
(declare-function dired-marker-regexp "dired" ())
(declare-function dired-do-delete "dired" (&optional arg))
(declare-function dired-do-flagged-delete "dired" (&optional nomessage))
(declare-function dired-map-over-marks "dired" (body arg &optional show-progress distinguish-one-marked))

(defvar elfeed-show-entry)
(defvar elfeed-db-entries)
(defvar elfeed-db-index)
(defvar elfeed-new-entry-parse-hook)
(defvar elfeed-update-hooks)
(defvar dired-del-marker)
(defvar dired-marker-char)
(defvar dired-mode-map)
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

(defun my-reading--delete-script (&rest args)
  "Run `read-later-delete' with ARGS."
  (apply #'my-reading--call-json
         (my-reading--script "read-later-delete")
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

(defun my-reading--result-deleted-records (result)
  "Return deleted record list from read-later delete RESULT."
  (or (alist-get 'deleted result) '()))

(defun my-reading--result-org-ids (result)
  "Return deleted Org IDs from read-later delete RESULT."
  (delq nil
        (delete-dups
         (mapcar (lambda (record)
                   (let ((org-id (alist-get 'org_id record)))
                     (when (and (stringp org-id)
                                (not (string-empty-p org-id)))
                       org-id)))
                 (my-reading--result-deleted-records result)))))

(defun my-reading--result-snapshot-count (result)
  "Return number of snapshots deleted in read-later delete RESULT."
  (apply #'+
         (mapcar (lambda (record)
                   (length (or (alist-get 'snapshots_deleted record) '())))
                 (my-reading--result-deleted-records result))))

(defun my-reading--read-later-item-path-p (path)
  "Return non-nil when PATH is an Org item in the read-later items directory."
  (let ((items-directory (expand-file-name "items/" my-reading-root-directory))
        (path (expand-file-name path)))
    (and (equal (file-name-extension path) "org")
         (file-in-directory-p path items-directory))))

(defun my-reading--all-read-later-items-p (files)
  "Return non-nil when every file in FILES is a read-later item."
  (and files (seq-every-p #'my-reading--read-later-item-path-p files)))

(defun my-reading--elfeed-delete-org-ids (org-ids)
  "Remove read-later feed entries matching ORG-IDS from the live Elfeed DB."
  (when (and org-ids
             (boundp 'elfeed-db-entries)
             (hash-table-p elfeed-db-entries))
    (let ((deleted 0))
      (dolist (org-id org-ids)
        (let ((entry-id (cons (my-reading-feed-url) org-id)))
          (when (gethash entry-id elfeed-db-entries)
            (when (and (boundp 'elfeed-db-index) elfeed-db-index)
              (ignore-errors
                (avl-tree-delete elfeed-db-index entry-id)))
            (remhash entry-id elfeed-db-entries)
            (setq deleted (1+ deleted)))))
      (when (> deleted 0)
        (when (fboundp 'elfeed-db-set-update-time)
          (elfeed-db-set-update-time))
        (when (fboundp 'elfeed-db-gc)
          (ignore-errors
            (elfeed-db-gc)))
        (when (fboundp 'elfeed-db-save)
          (elfeed-db-save))
        (when (and (fboundp 'elfeed-search-buffer)
                   (fboundp 'elfeed-search-update--force))
          (when-let* ((buffer (get-buffer (elfeed-search-buffer))))
            (with-current-buffer buffer
              (elfeed-search-update--force)))))
      deleted)))

(defun my-reading--delete-message (result elfeed-count)
  "Display deletion summary for RESULT and ELFEED-COUNT."
  (let ((item-count (length (my-reading--result-deleted-records result)))
        (queue-count (length (or (alist-get 'queue_deleted result) '())))
        (snapshot-count (my-reading--result-snapshot-count result)))
    (message "Deleted %d read-later item%s, %d queue entr%s, %d snapshot%s, %d Elfeed entr%s"
             item-count
             (if (= item-count 1) "" "s")
             queue-count
             (if (= queue-count 1) "y" "ies")
             snapshot-count
             (if (= snapshot-count 1) "" "s")
             elfeed-count
             (if (= elfeed-count 1) "y" "ies"))))

(defun my-reading-delete-files (files)
  "Delete read-later item FILES and their generated state."
  (interactive
   (list
    (list (read-file-name "Read-later item: "
                          (expand-file-name "items/" my-reading-root-directory)
                          nil t nil
                          (lambda (path)
                            (or (file-directory-p path)
                                (my-reading--read-later-item-path-p path)))))))
  (let ((files (delete-dups (mapcar #'expand-file-name files))))
    (unless (my-reading--all-read-later-items-p files)
      (user-error "Can only delete Org files under %s"
                  (expand-file-name "items/" my-reading-root-directory)))
    (when (yes-or-no-p
           (format "Delete %d read-later item%s and clean queue/snapshots/Elfeed? "
                   (length files)
                   (if (= (length files) 1) "" "s")))
      (let* ((args (apply #'append
                          (mapcar (lambda (file) (list "--item" file)) files)))
             (result (apply #'my-reading--delete-script args))
             (elfeed-count (my-reading--elfeed-delete-org-ids
                            (my-reading--result-org-ids result))))
        (my-reading--delete-message result (or elfeed-count 0))
        result))))

(defun my-reading--elfeed-read-later-entry-org-id (entry)
  "Return the read-later Org ID represented by generated feed ENTRY."
  (when (my-reading--elfeed-local-feed-entry-p entry)
    (let ((entry-id (elfeed-entry-id entry)))
      (when (consp entry-id)
        (cdr entry-id)))))

(defun my-reading-delete-elfeed-entries ()
  "Delete selected generated read-later entries from Elfeed and disk."
  (interactive)
  (let* ((entries (cond
                   ((derived-mode-p 'elfeed-show-mode)
                    (when elfeed-show-entry
                      (list elfeed-show-entry)))
                   ((derived-mode-p 'elfeed-search-mode)
                    (elfeed-search-selected))))
         (org-ids (delq nil
                        (delete-dups
                         (mapcar #'my-reading--elfeed-read-later-entry-org-id
                                 entries)))))
    (unless org-ids
      (user-error "No generated read-later Elfeed entries selected"))
    (when (yes-or-no-p
           (format "Delete %d read-later item%s and clean queue/snapshots/Elfeed? "
                   (length org-ids)
                   (if (= (length org-ids) 1) "" "s")))
      (let* ((args (apply #'append
                          (mapcar (lambda (org-id) (list "--org-id" org-id))
                                  org-ids)))
             (result (apply #'my-reading--delete-script args))
             (elfeed-count (my-reading--elfeed-delete-org-ids org-ids)))
        (my-reading--delete-message result (or elfeed-count 0))
        (when (derived-mode-p 'elfeed-show-mode)
          (kill-buffer))
        result))))

(defun my-reading-delete-dwim ()
  "Delete read-later items from Dired, Elfeed, or the current item buffer."
  (interactive)
  (cond
   ((derived-mode-p 'dired-mode)
    (require 'dired)
    (my-reading-delete-files (dired-get-marked-files)))
   ((or (derived-mode-p 'elfeed-show-mode)
        (derived-mode-p 'elfeed-search-mode))
    (my-reading-delete-elfeed-entries))
   ((and buffer-file-name
         (my-reading--read-later-item-path-p buffer-file-name))
    (my-reading-delete-files (list buffer-file-name)))
   (t
    (call-interactively #'my-reading-delete-files))))

(defun my-reading-dired-do-delete (&optional arg)
  "Delete Dired read-later item files through the read-later cleanup path.
For non-read-later files, delegate to `dired-do-delete'."
  (interactive "P")
  (require 'dired)
  (let ((files (dired-get-marked-files nil arg)))
    (cond
     ((my-reading--all-read-later-items-p files)
      (my-reading-delete-files files)
      (revert-buffer))
     ((seq-some #'my-reading--read-later-item-path-p files)
      (user-error "Delete read-later items separately so cleanup can run"))
     (t
      (dired-do-delete arg)))))

(defun my-reading--dired-flagged-files ()
  "Return Dired files flagged for deletion."
  (require 'dired)
  (let* ((dired-marker-char dired-del-marker)
         (regexp (dired-marker-regexp))
         case-fold-search)
    (when (save-excursion
            (goto-char (point-min))
            (re-search-forward regexp nil t))
      (nreverse
       (dired-map-over-marks (dired-get-filename) nil)))))

(defun my-reading-dired-do-flagged-delete (&optional nomessage)
  "Delete flagged read-later item files through the read-later cleanup path.
For non-read-later files, delegate to `dired-do-flagged-delete'."
  (interactive)
  (let ((files (my-reading--dired-flagged-files)))
    (cond
     ((my-reading--all-read-later-items-p files)
      (my-reading-delete-files files)
      (revert-buffer))
     ((seq-some #'my-reading--read-later-item-path-p files)
      (user-error "Delete read-later items separately so cleanup can run"))
     (files
      (dired-do-flagged-delete nomessage))
     (t
      (unless nomessage
        (message "(No deletions requested)"))))))

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
(my-leader-define "n D" #'my-reading-delete-dwim)
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
  (define-key elfeed-search-mode-map (kbd "D") #'my-reading-delete-elfeed-entries)
  (define-key elfeed-show-mode-map (kbd "D") #'my-reading-delete-elfeed-entries)
  (define-key elfeed-search-mode-map (kbd "d") #'my-reading-capture-elfeed-entry)
  (define-key elfeed-show-mode-map (kbd "d") #'my-reading-capture-elfeed-entry))

(with-eval-after-load 'dired
  (define-key dired-mode-map [remap dired-do-delete] #'my-reading-dired-do-delete)
  (define-key dired-mode-map [remap dired-do-flagged-delete]
              #'my-reading-dired-do-flagged-delete))

(with-eval-after-load 'which-key
  (which-key-add-keymap-based-replacements my-leader-map
    "n d" '("save to read-later" . my-reading-capture-dwim)
    "n D" '("delete read-later item" . my-reading-delete-dwim)
    "n l" '("update read-later feed" . my-reading-update-feed)
    "n q" "read-later queue"
    "n r" "read-later root"
    "n w" '("capture web page" . my-reading-capture-current-page)
    "n x" '("snapshot queue" . my-reading-snapshot-queue)))

(provide 'my-reading)
;;; my-reading.el ends here
