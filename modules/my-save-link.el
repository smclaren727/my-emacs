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
(declare-function elfeed-entry-tags "elfeed-db" (entry))
(declare-function elfeed-entry-title "elfeed-db" (entry))
(declare-function elfeed-search-update-entry "elfeed-search" (entry))
(declare-function elfeed-tag "elfeed-db" (entry &rest tags))
(declare-function dired-get-filename "dired" (&optional localp no-error-if-not-filep))
(declare-function dired-get-marked-files "dired" (&optional localp arg filter distinguish-one-marked error))
(declare-function dired-marker-regexp "dired" ())
(declare-function dired-do-delete "dired" (&optional arg))
(declare-function dired-do-flagged-delete "dired" (&optional nomessage))
(declare-function dired-map-over-marks "dired" (body arg &optional show-progress distinguish-one-marked))

(defvar dired-del-marker)
(defvar dired-marker-char)
(defvar dired-mode-map)
(defvar eww-data)
(defvar org-protocol-protocol-alist)

;;; Variables -----------------------------------------------------------

(defvar my-save-link-root-directory
  (expand-file-name
   (or (getenv "MY_SAVE_LINK_ROOT")
       (expand-file-name "00-Capture/Ingest/Saved-Links/" my-notes-directory)))
  "Root directory for local-first save-link captures.")

(defvar my-save-link-default-archive-mode "metadata"
  "Default archive mode passed to `save-link-capture'.")

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

(defun my-save-link--result-deleted-records (result)
  "Return deleted record list from save-link delete RESULT."
  (or (alist-get 'deleted result) '()))

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

(defun my-save-link--delete-message (result)
  "Display deletion summary for RESULT."
  (let ((item-count (length (my-save-link--result-deleted-records result)))
        (queue-count (length (or (alist-get 'queue_deleted result) '())))
        (snapshot-count (my-save-link--result-snapshot-count result)))
    (message "Deleted %d save-link item%s, %d queue entr%s, %d snapshot%s"
             item-count
             (if (= item-count 1) "" "s")
             queue-count
             (if (= queue-count 1) "y" "ies")
             snapshot-count
             (if (= snapshot-count 1) "" "s"))))

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
           (format "Delete %d save-link item%s and clean queue/snapshots? "
                   (length files)
                   (if (= (length files) 1) "" "s")))
      (let* ((args (apply #'append
                          (mapcar (lambda (file) (list "--item" file)) files)))
             (result (apply #'my-save-link--delete-script args)))
        (my-save-link--delete-message result)
        result))))

(defun my-save-link-delete-dwim ()
  "Delete save-link items from Dired or the current item buffer."
  (interactive)
  (cond
   ((derived-mode-p 'dired-mode)
    (require 'dired)
    (my-save-link-delete-files (dired-get-marked-files)))
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
    ;; org-protocol is an untrusted boundary: only http(s) links, so a crafted
    ;; capture cannot drive the snapshot fetcher at a file:// path or an internal
    ;; address. (Interactive / eww capture paths stay permissive.)
    (unless (string-match-p "\\`https?://" url)
      (user-error "org-protocol save-link only accepts http(s) URLs: %s" url))
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
    (my-save-link--message-result (apply #'my-save-link--capture-script args))))

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
  "Report snapshot compilation BUFFER completion with STATUS."
  (when (string-match-p "\\`finished" status)
    (with-current-buffer buffer
      (message "Promoted %d selected save-link item%s"
               (or my-save-link--snapshot-promote-count 0)
               (if (= (or my-save-link--snapshot-promote-count 0) 1) "" "s")))))

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

;;; Keybindings ---------------------------------------------------------

(my-leader-define "n d" #'my-save-link-capture-dwim)
(my-leader-define "n D" #'my-save-link-delete-dwim)
(my-leader-define "n q" #'my-save-link-open-queue)
(my-leader-define "n r" #'my-save-link-open-root)
(my-leader-define "n w" #'my-save-link-capture-current-page)
(my-leader-define "n x" #'my-save-link-snapshot-queue)

(with-eval-after-load 'elfeed
  (dolist (map (list elfeed-search-mode-map elfeed-show-mode-map))
    (define-key map (kbd "d") #'my-save-link-capture-elfeed-entry)))

(with-eval-after-load 'dired
  (define-key dired-mode-map [remap dired-do-delete] #'my-save-link-dired-do-delete)
  (define-key dired-mode-map [remap dired-do-flagged-delete]
              #'my-save-link-dired-do-flagged-delete))

(with-eval-after-load 'which-key
  (which-key-add-keymap-based-replacements my-leader-map
    "n d" '("save to save-link" . my-save-link-capture-dwim)
    "n D" '("delete save-link item" . my-save-link-delete-dwim)
    "n q" "save-link queue"
    "n r" "save-link root"
    "n w" '("capture web page" . my-save-link-capture-current-page)
    "n x" '("snapshot queue" . my-save-link-snapshot-queue)))

(provide 'my-save-link)
;;; my-save-link.el ends here
