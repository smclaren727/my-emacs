;;; my-vulpea.el --- Vulpea SQLite-backed notes engine -*- lexical-binding: t; -*-

;; Vulpea: networked notes backed by its own SQLite database, with a
;; typed query API and structured `vulpea-meta' metadata.  This is the
;; notes engine — it replaced org-node; see docs/vulpea-migration-plan.md.
;; Notes live in `my-notes-directory'.

;;; Forward declarations ------------------------------------------------

(declare-function my-emacs-state-file "my-core" (path))
(declare-function vulpea-db-autosync-mode "vulpea-db-sync" (&optional arg))
(declare-function vulpea-db-sync-full-scan "vulpea-db-sync")
(declare-function vulpea-find "vulpea")
(declare-function vulpea-insert "vulpea")
(declare-function vulpea-find-backlink "vulpea")
(declare-function vulpea-db-query "vulpea-db-query")
(declare-function vulpea-db-query-by-tags-some "vulpea-db-query")
(declare-function vulpea-note-id "vulpea-note")
(declare-function vulpea-note-title "vulpea-note")
(declare-function vulpea-note-aliases "vulpea-note")
(declare-function vulpea-note-properties "vulpea-note")
(declare-function org-in-src-block-p "org")
(declare-function org-link-make-string "ol")
(declare-function consult-ripgrep "consult")
(defvar my-notes-directory)
(defvar my-leader-map)
(defvar vulpea-db-location)
(defvar vulpea-db-sync-directories)
(defvar vulpea-db-sync-scan-on-enable)
(defvar vulpea-default-notes-directory)
(defvar vulpea-buffer-alias-property)

;;; Database location ---------------------------------------------------
;; Kept in a variable so a host-context shim (e.g. the nix-node) can
;; point the database elsewhere without editing this module.

(defvar my-vulpea-db-location
  (my-emacs-state-file "var/vulpea/vulpea.db")
  "Filesystem path of the vulpea SQLite database.")

;;; Deferred index warm-up ----------------------------------------------
;; Mirror the org-node approach: don't scan during init.  Enable vulpea
;; autosync (file-watch + async indexing) on an idle timer so startup
;; stays under the 1 s target.  With `vulpea-db-sync-scan-on-enable' set
;; to `async', enabling the mode also kicks off a catch-up scan.

(defvar my-vulpea-startup-idle-delay 5
  "Seconds of idle time before enabling vulpea autosync.")

(defvar my-vulpea--startup-timer nil
  "Idle timer used to enable `vulpea-db-autosync-mode'.")

(defun my-vulpea--enable-autosync-now ()
  "Enable vulpea database autosync."
  (setq my-vulpea--startup-timer nil)
  (vulpea-db-autosync-mode 1))

(defun my-vulpea--enable-autosync ()
  "Schedule vulpea autosync to start after startup settles."
  (when (timerp my-vulpea--startup-timer)
    (cancel-timer my-vulpea--startup-timer))
  (setq my-vulpea--startup-timer
        (run-with-idle-timer my-vulpea-startup-idle-delay
                             nil
                             #'my-vulpea--enable-autosync-now)))

;;; Notes search --------------------------------------------------------

(defun my-vulpea-grep ()
  "Search notes with `consult-ripgrep' rooted at `my-notes-directory'.
Replaces the org-node `o n g' grep binding."
  (interactive)
  (consult-ripgrep my-notes-directory))

;;; Vulpea setup --------------------------------------------------------

(use-package vulpea
  :defer t
  :init
  ;; Set engine options before the package loads; defcustom keeps these
  ;; values because the variables are already bound when it runs.
  (setq vulpea-db-location my-vulpea-db-location
        vulpea-db-sync-directories (list my-notes-directory)
        vulpea-default-notes-directory my-notes-directory
        ;; Existing vault convention — and vulpea's own default.
        vulpea-buffer-alias-property "ALIASES"
        ;; Catch edits made while Emacs was closed without blocking.
        vulpea-db-sync-scan-on-enable 'async)
  (make-directory (file-name-directory my-vulpea-db-location) t)

  ;; Notes bindings under `o n' (org -> notes).
  (my-leader-define "o n f" #'vulpea-find)
  (my-leader-define "o n i" #'vulpea-insert)
  (my-leader-define "o n b" #'vulpea-find-backlink)
  (my-leader-define "o n g" #'my-vulpea-grep)
  (my-leader-define "o n s" #'vulpea-db-sync-full-scan)

  (my-vulpea--enable-autosync)

  (with-eval-after-load 'which-key
    (which-key-add-keymap-based-replacements my-leader-map
      "o n" "notes")))

;;; Link completion via [[ ----------------------------------------------
;; Typing `[[' in an Org buffer offers vulpea note titles and aliases via
;; corfu; selecting one replaces the bracket pair with a full
;; [[id:..][title]] link (electric-pair aware).

(defvar my-vulpea-link-capf-enabled t
  "When non-nil, offer vulpea note completion after `[[' in Org buffers.")

(defun my-vulpea-link-capf ()
  "Complete vulpea note titles after `[[' in Org buffers.
Designed for `completion-at-point-functions'.  Inserts an
[[id:..][title]] link on selection."
  (when (and my-vulpea-link-capf-enabled
             (derived-mode-p 'org-mode)
             (not (org-in-src-block-p)))
    (let ((pt (point)))
      (save-excursion
        (when (search-backward "[[" (line-beginning-position) t)
          (let ((start (+ 2 (point))))
            (when (<= start pt)
              (let ((title<>id (make-hash-table :test 'equal))
                    (titles nil))
                (dolist (note (vulpea-db-query))
                  (let ((id (vulpea-note-id note)))
                    (when id
                      (dolist (name (cons (vulpea-note-title note)
                                          (vulpea-note-aliases note)))
                        (when (and name (not (gethash name title<>id)))
                          (puthash name id title<>id)
                          (push name titles))))))
                (list start pt
                      (nreverse titles)
                      :exclusive 'no
                      :exit-function
                      (lambda (text _status)
                        (when-let* ((id (gethash text title<>id)))
                          (atomic-change-group
                            (let ((end (point))
                                  (beg (save-excursion
                                         (search-backward "[[" nil t))))
                              (when beg
                                (when (looking-at-p "\\]\\]")
                                  (setq end (+ end 2)))
                                (delete-region beg end)
                                (goto-char beg)
                                (insert (org-link-make-string
                                         (concat "id:" id) text))))))))))))))))

(defun my-vulpea--enable-link-capf ()
  "Register the vulpea link completion-at-point function buffer-locally."
  (add-hook 'completion-at-point-functions #'my-vulpea-link-capf nil t))

(add-hook 'org-mode-hook #'my-vulpea--enable-link-capf)

;;; Contact email completion -------------------------------------------
;; Port of `my-node-contact-email'.  The original read only the EMAIL
;; property, so it surfaced just the handful of contacts that use it.
;; This version also searches EMAIL_WORK / EMAIL_HOME / EMAIL_OTHER and
;; shows the address in the candidate, so every address is selectable.

(defvar my-vulpea-contact-email-properties
  '("EMAIL" "EMAIL_WORK" "EMAIL_HOME" "EMAIL_OTHER")
  "Contact-note properties searched for an email address, in order.")

(defun my-vulpea--contact-email-candidates ()
  "Return an alist of (DISPLAY . EMAIL) from notes tagged `contact'."
  (let (candidates)
    (dolist (note (vulpea-db-query-by-tags-some '("contact")))
      (let ((name (vulpea-note-title note))
            (props (vulpea-note-properties note)))
        (dolist (key my-vulpea-contact-email-properties)
          (when-let* ((email (cdr (assoc key props))))
            (push (cons (format "%s  <%s>" name email) email) candidates)))))
    (nreverse candidates)))

(defun my-vulpea-contact-email ()
  "Complete a contact and insert their email address.
Searches vulpea notes tagged `contact' for the properties in
`my-vulpea-contact-email-properties'."
  (interactive)
  (let* ((candidates (my-vulpea--contact-email-candidates))
         (choice (and candidates
                      (completing-read "Contact email: " candidates nil t)))
         (email (cdr (assoc choice candidates))))
    (cond ((not candidates) (message "No contact emails found"))
          (email (insert email))
          (t (message "No email for %s" choice)))))

(provide 'my-vulpea)
;;; my-vulpea.el ends here
