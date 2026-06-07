;;; my-save-link.el --- Local-first save-link captures -*- lexical-binding: t; -*-

;; The CLI scripts own the durable file format.  Emacs is the fast local
;; control surface for EWW, Elfeed, minibuffer captures, and Reader migration.

(require 'cl-lib)
(require 'json)
(require 'my-elfeed)
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

(defvar my-save-link-root-directory
  (expand-file-name
   (or (getenv "MY_SAVE_LINK_ROOT")
       (expand-file-name "50-Resources/Save-Link/" my-notes-directory)))
  "Root directory for local-first save-link captures.")

(defvar my-save-link-default-archive-mode "metadata"
  "Default archive mode passed to `save-link-capture'.")

(defvar my-save-link-feed-file "feed.xml"
  "Generated RSS feed filename under `my-save-link-root-directory'.")

(defvar-local my-save-link--snapshot-promote-count nil
  "Number of selected entries being promoted by this compilation buffer.")

;;; Script helpers ------------------------------------------------------

(defvar my-save-link-script-directory
  (when-let* ((directory (getenv "MY_SAVE_LINK_SCRIPT_DIR")))
    (unless (string-empty-p (string-trim directory))
      (file-name-as-directory (expand-file-name directory))))
  "Optional directory containing save-link helper scripts.")

(defconst my-save-link--module-directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory containing this module when it was loaded.")

(defun my-save-link--script-candidates (name)
  "Return candidate paths for save-link script NAME."
  (delete-dups
   (delq nil
         (list
          (when my-save-link-script-directory
            (expand-file-name name my-save-link-script-directory))
          (when my-save-link-script-directory
            (expand-file-name (concat "save-link/" name)
                              my-save-link-script-directory))
          (my-emacs-source-file (expand-file-name name "scripts/save-link/"))
          (my-emacs-source-file (expand-file-name name "scripts/"))
          (expand-file-name (concat "scripts/save-link/" name)
                            user-emacs-directory)
          (expand-file-name (concat "scripts/" name) user-emacs-directory)
          (when my-save-link--module-directory
            (expand-file-name (concat "../scripts/save-link/" name)
                              my-save-link--module-directory))
          (when my-save-link--module-directory
            (expand-file-name (concat "../scripts/" name)
                              my-save-link--module-directory))))))

(defun my-save-link--script (name)
  "Return executable save-link script NAME."
  (let ((candidates (my-save-link--script-candidates name)))
    (or (seq-find #'file-executable-p candidates)
        (user-error "No executable save-link script %s found. Checked: %s"
                    name
                    (string-join candidates ", ")))))

(defun my-save-link--arg (name value)
  "Return CLI argument pair NAME VALUE when VALUE is a non-empty string."
  (when (and (stringp value) (not (string-empty-p (string-trim value))))
    (list name value)))

(defun my-save-link--call-json (script &rest args)
  "Run SCRIPT with ARGS and parse one JSON object from stdout."
  (unless (and script (file-executable-p script))
    (let ((name (and script (file-name-nondirectory script))))
      (user-error "Save-link script is not executable: %s%s"
                  (or script "<none>")
                  (if name
                      (format " (checked: %s)"
                              (string-join
                               (my-save-link--script-candidates name)
                               ", "))
                    ""))))
  (with-temp-buffer
    (let ((status (apply #'process-file script nil t nil args)))
      (unless (zerop status)
        (user-error "%s failed: %s" script (string-trim (buffer-string)))))
    (json-parse-string (buffer-string) :object-type 'alist :array-type 'list)))

(defun my-save-link--capture-script (&rest args)
  "Run `save-link-capture' with ARGS."
  (apply #'my-save-link--call-json
         (my-save-link--script "save-link-capture")
         (append (list "--root" my-save-link-root-directory "--json") args)))

(defun my-save-link--delete-script (&rest args)
  "Run `save-link-delete' with ARGS."
  (apply #'my-save-link--call-json
         (my-save-link--script "save-link-delete")
         (append (list "--root" my-save-link-root-directory "--json") args)))

(defun my-save-link--read-org-property (path key)
  "Read Org property KEY from PATH."
  (with-temp-buffer
    (insert-file-contents path nil nil nil t)
    (when (re-search-forward
           (format "^:%s:[ \t]*\\(.*?\\)[ \t]*$" (regexp-quote key))
           nil t)
      (string-trim (match-string 1)))))

(defun my-save-link-feed-path ()
  "Return the generated save-link RSS feed path."
  (expand-file-name my-save-link-feed-file my-save-link-root-directory))

(defun my-save-link-feed-url ()
  "Return the generated save-link RSS feed as a file URL."
  (concat "file://" (expand-file-name (my-save-link-feed-path))))

(defun my-save-link-generate-feed ()
  "Generate the local save-link RSS feed from canonical Org items."
  (interactive)
  (let ((result
         (my-save-link--call-json
          (my-save-link--script "save-link-feed")
          "--root" my-save-link-root-directory
          "--output" (my-save-link-feed-path)
          "--json")))
    (when (called-interactively-p 'interactive)
      (message "Generated save-link feed with %s items: %s"
               (alist-get 'items result)
               (alist-get 'path result)))
    result))

(defun my-save-link-update-feed ()
  "Generate the save-link RSS feed and update it in Elfeed when available."
  (interactive)
  (let ((result (my-save-link-generate-feed)))
    (my-save-link--refresh-elfeed-org-feeds)
    (if (fboundp 'elfeed-update-feed)
        (progn
          (elfeed-update-feed (my-save-link-feed-url))
          (message "Updating save-link feed in Elfeed: %s"
                   (alist-get 'path result)))
      (message "Generated save-link feed; run Elfeed update after Elfeed loads: %s"
               (alist-get 'path result)))
    result))

(defun my-save-link--update-elfeed-feed-quietly ()
  "Refresh the generated save-link feed in Elfeed when Elfeed is loaded."
  (when (fboundp 'elfeed-update-feed)
    (my-save-link--refresh-elfeed-org-feeds)
    (elfeed-update-feed (my-save-link-feed-url))))

(defun my-save-link--refresh-elfeed-org-feeds ()
  "Refresh `elfeed-feeds' from elfeed-org when it is available."
  (when (and (boundp 'rmh-elfeed-org-files)
             (boundp 'rmh-elfeed-org-tree-id)
             (fboundp 'rmh-elfeed-org-process))
    (rmh-elfeed-org-process rmh-elfeed-org-files rmh-elfeed-org-tree-id)))

(defun my-save-link--category-tag (category)
  "Return a safe Elfeed tag symbol for CATEGORY."
  (let ((tag (replace-regexp-in-string
              "[^A-Za-z0-9_@#.-]+" "-"
              (downcase (string-trim category)))))
    (unless (string-empty-p tag)
      (intern tag))))

(defun my-save-link--elfeed-local-feed-entry-p (entry)
  "Return non-nil when ENTRY came from the generated save-link feed."
  (and (fboundp 'elfeed-entry-feed-id)
       (string= (elfeed-entry-feed-id entry) (my-save-link-feed-url))))

(defun my-save-link--elfeed-tag-local-feed-entry (entry)
  "Apply save-link search tags to generated Elfeed ENTRY."
  (when (my-save-link--elfeed-local-feed-entry-p entry)
    (let* ((categories (and (fboundp 'elfeed-meta)
                            (elfeed-meta entry :categories)))
           (category-tags (delq nil (mapcar #'my-save-link--category-tag categories))))
      (apply #'elfeed-tag entry (cons 'savelink category-tags)))))

(defun my-save-link--elfeed-tag-local-feed-entry-from-parse (_type _item entry)
  "Apply save-link tags while Elfeed parses generated feed ENTRY."
  (my-save-link--elfeed-tag-local-feed-entry entry))

(defun my-save-link--elfeed-tag-local-feed-entries (&optional url)
  "Retag existing generated feed entries after Elfeed updates URL."
  (when (or (null url) (string= url (my-save-link-feed-url)))
    (when (and (boundp 'elfeed-db-entries) (hash-table-p elfeed-db-entries))
      (maphash
       (lambda (_id entry)
         (my-save-link--elfeed-tag-local-feed-entry entry))
       elfeed-db-entries)
      (when (fboundp 'elfeed-db-save)
        (elfeed-db-save)))))

(defun my-save-link--result-deleted-records (result)
  "Return deleted record list from save-link delete RESULT."
  (or (alist-get 'deleted result) '()))

(defun my-save-link--result-org-ids (result)
  "Return deleted Org IDs from save-link delete RESULT."
  (delq nil
        (delete-dups
         (mapcar (lambda (record)
                   (let ((org-id (alist-get 'org_id record)))
                     (when (and (stringp org-id)
                                (not (string-empty-p org-id)))
                       org-id)))
                 (my-save-link--result-deleted-records result)))))

(defun my-save-link--result-snapshot-count (result)
  "Return number of snapshots deleted in save-link delete RESULT."
  (apply #'+
         (mapcar (lambda (record)
                   (length (or (alist-get 'snapshots_deleted record) '())))
                 (my-save-link--result-deleted-records result))))

(defun my-save-link--save-link-item-path-p (path)
  "Return non-nil when PATH is an Org item in the save-link items directory."
  (let ((items-directory (expand-file-name "items/" my-save-link-root-directory))
        (path (expand-file-name path)))
    (and (equal (file-name-extension path) "org")
         (file-in-directory-p path items-directory))))

(defun my-save-link--all-save-link-items-p (files)
  "Return non-nil when every file in FILES is a save-link item."
  (and files (seq-every-p #'my-save-link--save-link-item-path-p files)))

(defun my-save-link--elfeed-delete-org-ids (org-ids)
  "Remove save-link feed entries matching ORG-IDS from the live Elfeed DB."
  (when (and org-ids
             (boundp 'elfeed-db-entries)
             (hash-table-p elfeed-db-entries))
    (let ((deleted 0))
      (dolist (org-id org-ids)
        (let ((entry-id (cons (my-save-link-feed-url) org-id)))
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

(defun my-save-link--delete-message (result elfeed-count)
  "Display deletion summary for RESULT and ELFEED-COUNT."
  (let ((item-count (length (my-save-link--result-deleted-records result)))
        (queue-count (length (or (alist-get 'queue_deleted result) '())))
        (snapshot-count (my-save-link--result-snapshot-count result)))
    (message "Deleted %d save-link item%s, %d queue entr%s, %d snapshot%s, %d Elfeed entr%s"
             item-count
             (if (= item-count 1) "" "s")
             queue-count
             (if (= queue-count 1) "y" "ies")
             snapshot-count
             (if (= snapshot-count 1) "" "s")
             elfeed-count
             (if (= elfeed-count 1) "y" "ies"))))

(defun my-save-link-delete-files (files)
  "Delete save-link item FILES and their generated state."
  (interactive
   (list
    (list (read-file-name "Save-link item: "
                          (expand-file-name "items/" my-save-link-root-directory)
                          nil t nil
                          (lambda (path)
                            (or (file-directory-p path)
                                (my-save-link--save-link-item-path-p path)))))))
  (let ((files (delete-dups (mapcar #'expand-file-name files))))
    (unless (my-save-link--all-save-link-items-p files)
      (user-error "Can only delete Org files under %s"
                  (expand-file-name "items/" my-save-link-root-directory)))
    (when (yes-or-no-p
           (format "Delete %d save-link item%s and clean queue/snapshots/Elfeed? "
                   (length files)
                   (if (= (length files) 1) "" "s")))
      (let* ((args (apply #'append
                          (mapcar (lambda (file) (list "--item" file)) files)))
             (result (apply #'my-save-link--delete-script args))
             (elfeed-count (my-save-link--elfeed-delete-org-ids
                            (my-save-link--result-org-ids result))))
        (my-save-link--delete-message result (or elfeed-count 0))
        result))))

(defun my-save-link--elfeed-save-link-entry-org-id (entry)
  "Return the save-link Org ID represented by generated feed ENTRY."
  (when (my-save-link--elfeed-local-feed-entry-p entry)
    (let ((entry-id (elfeed-entry-id entry)))
      (when (consp entry-id)
        (cdr entry-id)))))

(defun my-save-link--item-path-for-org-id (org-id)
  "Return save-link item path for ORG-ID, or nil."
  (when (and (stringp org-id) (not (string-empty-p org-id)))
    (let ((items-directory (expand-file-name "items/" my-save-link-root-directory)))
      (when (file-directory-p items-directory)
        (seq-find
         (lambda (path)
           (string= org-id (my-save-link--read-org-property path "ID")))
         (directory-files items-directory t "\\.org\\'"))))))

(defun my-save-link--selected-elfeed-entries ()
  "Return selected Elfeed entries from search or show mode."
  (cond
   ((derived-mode-p 'elfeed-show-mode)
    (when elfeed-show-entry
      (list elfeed-show-entry)))
   ((derived-mode-p 'elfeed-search-mode)
    (elfeed-search-selected))
   (t
    (user-error "Promote from an Elfeed search or show buffer"))))

(defun my-save-link--elfeed-entry-feed-tags (entry)
  "Return comma-separated feed tags from ENTRY for save-link storage."
  (mapconcat
   #'symbol-name
   (seq-remove (lambda (tag)
                 (memq tag '(unread star saved savelink saved-link saved-article)))
               (elfeed-entry-tags entry))
   ","))

(defun my-save-link--capture-elfeed-entry-result (entry)
  "Capture regular Elfeed ENTRY as a lightweight save-link item."
  (let* ((url (elfeed-entry-link entry))
         (title (elfeed-entry-title entry))
         (feed-tags (my-save-link--elfeed-entry-feed-tags entry))
         (args (append
                (list "--url" url
                      "--title" title
                      "--source" "elfeed"
                      "--archive-mode" "metadata")
                (my-save-link--arg "--feed-tags" feed-tags)))
         (result (apply #'my-save-link--capture-script args)))
    (elfeed-tag entry 'saved)
    (when (derived-mode-p 'elfeed-search-mode)
      (elfeed-search-update-entry entry))
    result))

(defun my-save-link--item-path-for-elfeed-entry (entry)
  "Return save-link item path for ENTRY, capturing it first when needed."
  (if-let* ((org-id (my-save-link--elfeed-save-link-entry-org-id entry)))
      (or (my-save-link--item-path-for-org-id org-id)
          (user-error "No save-link item file found for Org ID %s" org-id))
    (alist-get 'path (my-save-link--capture-elfeed-entry-result entry))))

(defun my-save-link-delete-elfeed-entries ()
  "Delete selected generated save-link entries from Elfeed and disk."
  (interactive)
  (let* ((entries (cond
                   ((derived-mode-p 'elfeed-show-mode)
                    (when elfeed-show-entry
                      (list elfeed-show-entry)))
                   ((derived-mode-p 'elfeed-search-mode)
                    (elfeed-search-selected))))
         (org-ids (delq nil
                        (delete-dups
                         (mapcar #'my-save-link--elfeed-save-link-entry-org-id
                                 entries)))))
    (unless org-ids
      (user-error "No generated save-link Elfeed entries selected"))
    (when (yes-or-no-p
           (format "Delete %d save-link item%s and clean queue/snapshots/Elfeed? "
                   (length org-ids)
                   (if (= (length org-ids) 1) "" "s")))
      (let* ((args (apply #'append
                          (mapcar (lambda (org-id) (list "--org-id" org-id))
                                  org-ids)))
             (result (apply #'my-save-link--delete-script args))
             (elfeed-count (my-save-link--elfeed-delete-org-ids org-ids)))
        (my-save-link--delete-message result (or elfeed-count 0))
        (when (derived-mode-p 'elfeed-show-mode)
          (kill-buffer))
        result))))

(defun my-save-link-delete-dwim ()
  "Delete save-link items from Dired, Elfeed, or the current item buffer."
  (interactive)
  (cond
   ((derived-mode-p 'dired-mode)
    (require 'dired)
    (my-save-link-delete-files (dired-get-marked-files)))
   ((or (derived-mode-p 'elfeed-show-mode)
        (derived-mode-p 'elfeed-search-mode))
    (my-save-link-delete-elfeed-entries))
   ((and buffer-file-name
         (my-save-link--save-link-item-path-p buffer-file-name))
    (my-save-link-delete-files (list buffer-file-name)))
   (t
    (call-interactively #'my-save-link-delete-files))))

(defun my-save-link-dired-do-delete (&optional arg)
  "Delete Dired save-link item files through the save-link cleanup path.
For non-save-link files, delegate to `dired-do-delete'."
  (interactive "P")
  (require 'dired)
  (let ((files (dired-get-marked-files nil arg)))
    (cond
     ((my-save-link--all-save-link-items-p files)
      (my-save-link-delete-files files)
      (revert-buffer))
     ((seq-some #'my-save-link--save-link-item-path-p files)
      (user-error "Delete save-link items separately so cleanup can run"))
     (t
      (dired-do-delete arg)))))

(defun my-save-link--dired-flagged-files ()
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

(defun my-save-link-dired-do-flagged-delete (&optional nomessage)
  "Delete flagged save-link item files through the save-link cleanup path.
For non-save-link files, delegate to `dired-do-flagged-delete'."
  (interactive)
  (let ((files (my-save-link--dired-flagged-files)))
    (cond
     ((my-save-link--all-save-link-items-p files)
      (my-save-link-delete-files files)
      (revert-buffer))
     ((seq-some #'my-save-link--save-link-item-path-p files)
      (user-error "Delete save-link items separately so cleanup can run"))
     (files
      (dired-do-flagged-delete nomessage))
     (t
      (unless nomessage
        (message "(No deletions requested)"))))))

(defun my-save-link--region-text ()
  "Return active region text, or an empty string."
  (if (use-region-p)
      (buffer-substring-no-properties (region-beginning) (region-end))
    ""))

(defun my-save-link--message-result (result)
  "Display capture RESULT and return the item path."
  (let ((path (alist-get 'path result))
        (duplicate (alist-get 'duplicate result)))
    (message "%s save-link item: %s"
             (if duplicate "Updated" "Captured")
             path)
    path))

;;; Org protocol helpers -----------------------------------------------

(defun my-save-link--archive-mode (value)
  "Return VALUE when it is a valid archive mode, otherwise the default."
  (if (member value '("readable" "metadata" "full" "defer"))
      value
    my-save-link-default-archive-mode))

(defun my-save-link-capture-org-protocol (info)
  "Capture a browser link from org-protocol INFO.
Expected INFO is a plist containing `:url', `:title', optional
`:body', `:source', `:tags', `:note', and `:archive-mode'."
  (let* ((url (my-plist-non-empty-string info :url))
         (title (or (my-plist-non-empty-string info :title) url))
         (selection (my-plist-non-empty-string info :body))
         (source (or (my-plist-non-empty-string info :source) "browser"))
         (tags (my-plist-non-empty-string info :tags))
         (note (my-plist-non-empty-string info :note))
         (archive-mode
          (my-save-link--archive-mode
           (or (my-plist-non-empty-string info :archive-mode)
               (my-plist-non-empty-string info :archive_mode)))))
    (unless url
      (user-error "org-protocol save-link capture requires a URL"))
    (my-save-link-capture-url url title
                            :source source
                            :tags tags
                            :note note
                            :selection selection
                            :archive-mode archive-mode)
    nil))

(with-eval-after-load 'org-protocol
  (my-org-protocol-register "save-link"
                            #'my-save-link-capture-org-protocol
                            :kill-client t))

(require 'org-protocol nil t)

;;; Browser helpers -----------------------------------------------------

(defun my-save-link--eww-data-value (property)
  "Return PROPERTY from EWW's current page data, or nil."
  (when (and (boundp 'eww-data) (listp eww-data))
    (plist-get eww-data property)))

(defun my-save-link--current-page-url ()
  "Return the current browser page URL or URL at point."
  (cond
   ((derived-mode-p 'eww-mode)
    (my-save-link--eww-data-value :url))
   ((thing-at-point-url-at-point))))

(defun my-save-link--current-page-title (url)
  "Return the current browser page title, falling back to URL."
  (cond
   ((derived-mode-p 'eww-mode)
    (or (my-save-link--eww-data-value :title) url))
   (t
    (read-string "Title: " nil nil url))))

;;; Capture commands ----------------------------------------------------

(cl-defun my-save-link-capture-url (url title &key source tags note selection
                                      archive-mode feed-tags)
  "Capture URL with TITLE into the local save-link store.
Keyword arguments SOURCE, TAGS, NOTE, SELECTION, ARCHIVE-MODE, and
FEED-TAGS are passed through to the CLI capture contract."
  (interactive
   (list
    (read-string "URL: " (or (thing-at-point-url-at-point) ""))
    (read-string "Title: ")
    :source "manual"
    :tags (read-string "Tags: ")
    :note (read-string "Note: ")
    :selection (my-save-link--region-text)
    :archive-mode (completing-read
                   "Archive mode: "
                   '("readable" "metadata" "full" "defer")
                   nil t nil nil my-save-link-default-archive-mode)))
  (let ((args (append
               (list "--url" url
                     "--title" title
                     "--source" (or source "manual")
                     "--archive-mode" (or archive-mode
                                          my-save-link-default-archive-mode))
               (my-save-link--arg "--tags" tags)
               (my-save-link--arg "--feed-tags" feed-tags)
               (my-save-link--arg "--note" note)
               (my-save-link--arg "--selection" selection))))
    (prog1 (my-save-link--message-result (apply #'my-save-link--capture-script args))
      (my-save-link--update-elfeed-feed-quietly))))

(defun my-save-link-capture-current-page ()
  "Capture the current Emacs browser page or URL at point."
  (interactive)
  (let* ((url (or (my-save-link--current-page-url)
                  (read-string "URL: ")))
         (title (my-save-link--current-page-title url))
         (source (if (derived-mode-p 'eww-mode) "eww" "emacs"))
         (selection (my-save-link--region-text)))
    (when (string-empty-p (string-trim url))
      (user-error "No page URL found"))
    (my-save-link-capture-url url title
                            :source source
                            :selection selection
                            :archive-mode my-save-link-default-archive-mode)))

(defun my-save-link-capture-elfeed-entry ()
  "Capture the current Elfeed entry into the save-link store."
  (interactive)
  (let ((entry (my-elfeed-entry-at-point)))
    (unless entry
      (user-error "No Elfeed entry at point"))
    (let* ((url (elfeed-entry-link entry))
           (title (elfeed-entry-title entry))
           (tags (mapconcat
                  #'symbol-name
                  (seq-remove (lambda (tag) (memq tag '(unread star saved)))
                              (elfeed-entry-tags entry))
                  ",")))
      (my-save-link-capture-url url title
                              :source "elfeed"
                              :archive-mode my-save-link-default-archive-mode
                              :feed-tags tags)
      (elfeed-tag entry 'saved)
      (when (derived-mode-p 'elfeed-search-mode)
        (elfeed-search-update-entry entry)))))

(defun my-save-link-capture-dwim ()
  "Capture the current thing: Elfeed entry, Emacs browser page, or URL."
  (interactive)
  (cond
   ((or (derived-mode-p 'elfeed-show-mode)
        (derived-mode-p 'elfeed-search-mode))
    (my-save-link-capture-elfeed-entry))
   ((or (derived-mode-p 'eww-mode)
        (thing-at-point-url-at-point))
    (my-save-link-capture-current-page))
   (t
    (call-interactively #'my-save-link-capture-url))))

(defun my-save-link-import-readwise-export (path)
  "Import a one-time Readwise/Reader export file at PATH."
  (interactive "fReadwise export file: ")
  (let ((result
         (my-save-link--call-json
          (my-save-link--script "readwise-export-import")
          "--root" my-save-link-root-directory
          "--json"
          (expand-file-name path))))
    (message "Readwise import processed %d records" (length result))
    result))

(defun my-save-link-open-root ()
  "Open the save-link root directory."
  (interactive)
  (dired my-save-link-root-directory))

(defun my-save-link-open-queue ()
  "Open the save-link ingest queue."
  (interactive)
  (dired (expand-file-name "queue/" my-save-link-root-directory)))

(defun my-save-link-snapshot-queue ()
  "Process all queued save-link snapshots."
  (interactive)
  (require 'compile)
  (let* ((default-directory (file-name-as-directory my-save-link-root-directory))
         (script (my-save-link--script "save-link-snapshot"))
         (command (mapconcat #'shell-quote-argument
                             (list script "--root" my-save-link-root-directory "--all")
                             " ")))
    (compilation-start command 'compilation-mode
                       (lambda (_mode) "*save-link-snapshot*"))))

(defun my-save-link--snapshot-compilation-finished (buffer status)
  "Refresh Elfeed after snapshot compilation BUFFER finishes with STATUS."
  (when (string-match-p "\\`finished" status)
    (with-current-buffer buffer
      (message "Promoted %d selected save-link item%s"
               (or my-save-link--snapshot-promote-count 0)
               (if (= (or my-save-link--snapshot-promote-count 0) 1) "" "s")))
    (my-save-link--update-elfeed-feed-quietly)))

(defun my-save-link-snapshot-items (items)
  "Snapshot exactly ITEMS and consume their matching queue entries."
  (interactive
   (list
    (list (read-file-name "Save-link item: "
                          (expand-file-name "items/" my-save-link-root-directory)
                          nil t nil
                          (lambda (path)
                            (or (file-directory-p path)
                                (my-save-link--save-link-item-path-p path)))))))
  (let* ((items (delete-dups (mapcar #'expand-file-name items)))
         (count (length items)))
    (unless (my-save-link--all-save-link-items-p items)
      (user-error "Can only snapshot Org files under %s"
                  (expand-file-name "items/" my-save-link-root-directory)))
    (require 'compile)
    (let* ((default-directory (file-name-as-directory my-save-link-root-directory))
           (script (my-save-link--script "save-link-snapshot"))
           (args (append (list script "--root" my-save-link-root-directory
                               "--mode" "readable")
                         (apply #'append
                                (mapcar (lambda (item) (list "--item" item))
                                        items))))
           (command (mapconcat #'shell-quote-argument args " "))
           (buffer (compilation-start command 'compilation-mode
                                      (lambda (_mode) "*save-link-promote*"))))
      (with-current-buffer buffer
        (setq-local my-save-link--snapshot-promote-count count)
        (add-hook 'compilation-finish-functions
                  #'my-save-link--snapshot-compilation-finished nil t))
      buffer)))

(defun my-save-link-promote-elfeed-entries ()
  "Promote selected Elfeed entries into saved snapshots.
Generated save-link entries reuse their existing item files. Regular RSS
entries are first captured as lightweight save-link items, then only the
selected items are snapshotted."
  (interactive)
  (let* ((entries (my-save-link--selected-elfeed-entries))
         (count (length entries)))
    (unless entries
      (user-error "No Elfeed entries selected"))
    (when (yes-or-no-p
           (format "Promote %d selected Elfeed entr%s to saved snapshot%s? "
                   count
                   (if (= count 1) "y" "ies")
                   (if (= count 1) "" "s")))
      (let ((items (delete-dups
                    (mapcar #'my-save-link--item-path-for-elfeed-entry entries))))
        (my-save-link--update-elfeed-feed-quietly)
        (my-save-link-snapshot-items items)))))

;;; Keybindings ---------------------------------------------------------

(my-leader-define "n d" #'my-save-link-capture-dwim)
(my-leader-define "n D" #'my-save-link-delete-dwim)
(my-leader-define "n l" #'my-save-link-update-feed)
(my-leader-define "n p" #'my-save-link-promote-elfeed-entries)
(my-leader-define "n q" #'my-save-link-open-queue)
(my-leader-define "n r" #'my-save-link-open-root)
(my-leader-define "n w" #'my-save-link-capture-current-page)
(my-leader-define "n x" #'my-save-link-snapshot-queue)

(with-eval-after-load 'elfeed
  (add-hook 'elfeed-new-entry-parse-hook
            #'my-save-link--elfeed-tag-local-feed-entry-from-parse)
  (add-hook 'elfeed-update-hooks
            #'my-save-link--elfeed-tag-local-feed-entries)
  (dolist (map (list elfeed-search-mode-map elfeed-show-mode-map))
    (define-key map (kbd "D") #'my-save-link-delete-elfeed-entries)
    (define-key map (kbd "P") #'my-save-link-promote-elfeed-entries)
    (define-key map (kbd "d") #'my-save-link-capture-elfeed-entry)))

(with-eval-after-load 'dired
  (define-key dired-mode-map [remap dired-do-delete] #'my-save-link-dired-do-delete)
  (define-key dired-mode-map [remap dired-do-flagged-delete]
              #'my-save-link-dired-do-flagged-delete))

(with-eval-after-load 'which-key
  (which-key-add-keymap-based-replacements my-leader-map
    "n d" '("save to save-link" . my-save-link-capture-dwim)
    "n D" '("delete save-link item" . my-save-link-delete-dwim)
    "n l" '("update save-link feed" . my-save-link-update-feed)
    "n p" '("promote selected" . my-save-link-promote-elfeed-entries)
    "n q" "save-link queue"
    "n r" "save-link root"
    "n w" '("capture web page" . my-save-link-capture-current-page)
    "n x" '("snapshot queue" . my-save-link-snapshot-queue)))

(provide 'my-save-link)
;;; my-save-link.el ends here
