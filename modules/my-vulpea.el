;;; my-vulpea.el --- Vulpea SQLite-backed notes engine -*- lexical-binding: t; -*-

;; Vulpea: networked notes backed by its own SQLite database, with a
;; typed query API and structured `vulpea-meta' metadata.  Installed
;; alongside org-node during the migration so both engines can index the
;; same vault non-destructively; see docs/vulpea-migration-plan.md.
;; Notes live in `my-notes-directory'.  Set `my-flag-vulpea' to nil to
;; roll back to org-node alone.

;;; Forward declarations ------------------------------------------------

(declare-function my-emacs-state-file "my-core" (path))
(declare-function vulpea-db-autosync-mode "vulpea-db-sync" (&optional arg))
(declare-function vulpea-db-sync-full-scan "vulpea-db-sync")
(declare-function vulpea-find "vulpea")
(declare-function vulpea-insert "vulpea")
(declare-function vulpea-find-backlink "vulpea")
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

  ;; Coexistence bindings under `o v' (org -> vulpea).  Kept separate
  ;; from org-node's `o n' until cutover so both engines stay usable.
  (my-leader-define "o v f" #'vulpea-find)
  (my-leader-define "o v i" #'vulpea-insert)
  (my-leader-define "o v b" #'vulpea-find-backlink)
  (my-leader-define "o v s" #'vulpea-db-sync-full-scan)

  (my-vulpea--enable-autosync)

  (with-eval-after-load 'which-key
    (which-key-add-keymap-based-replacements my-leader-map
      "o v" "vulpea")))

(provide 'my-vulpea)
;;; my-vulpea.el ends here
