;;; my-core.el --- Production-safe defaults -*- lexical-binding: t; -*-

;; Production-safe Emacs defaults that apply regardless of which
;; optional modules are loaded.  Handles startup restoration,
;; no-littering paths, backup/autosave, history, and shared
;; variables that multiple modules depend on.

(defvar my-early--file-name-handler-alist)

;;; Startup timer -----------------------------------------------------
(add-hook 'emacs-startup-hook
          (lambda ()
            (message "Emacs ready in %.2f seconds with %d garbage collections."
                     (float-time (time-subtract after-init-time
                                                before-init-time))
                     gcs-done)))

;;; Restore early-init overrides --------------------------------------
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 16 1024 1024)
                  file-name-handler-alist my-early--file-name-handler-alist)))

;;; No-littering (keep .emacs.d clean) --------------------------------
;; Redirects package data into:
;;   ~/.emacs.d/etc/  — configuration data
;;   ~/.emacs.d/var/  — persistent runtime data
(use-package no-littering
  :demand t
  :config
  (setq auto-save-file-name-transforms
        `((".*" ,(no-littering-expand-var-file-name "auto-save/") t)))
  ;; Ensure the auto-save directory exists — no-littering sets the
  ;; path but doesn't create it.  Backups fail silently without this.
  (make-directory (no-littering-expand-var-file-name "auto-save/") t)
  (when (fboundp 'startup-redirect-eln-cache)
    (startup-redirect-eln-cache
     (convert-standard-filename
      (expand-file-name "var/eln-cache/" user-emacs-directory)))))

;;; Backups -----------------------------------------------------------
(let ((backup-dir (no-littering-expand-var-file-name "backup/")))
  (make-directory backup-dir t)
  (setq backup-directory-alist `(("." . ,backup-dir))
        backup-by-copying t
        version-control t
        delete-old-versions t
        kept-new-versions 5
        kept-old-versions 2))

;;; Shared paths -------------------------------------------------------
;; Used by multiple modules (org-mode, feeds).  Defined here so no
;; module needs to defensively re-declare it.
(defvar my-emacs-source-root (expand-file-name user-emacs-directory)
  "Root directory containing the tracked Emacs configuration source.")

(defun my-emacs-source-file (path)
  "Return PATH resolved relative to `my-emacs-source-root'."
  (expand-file-name path my-emacs-source-root))

(defun my-emacs-state-file (path)
  "Return PATH resolved relative to `user-emacs-directory'."
  (expand-file-name path user-emacs-directory))

(defvar my-notes-directory "~/All-The-Things/"
  "Root directory for all notes and org files.")

;;; History and state -------------------------------------------------

(use-package savehist
  :ensure nil
  :hook (after-init . savehist-mode)
  :custom
  (savehist-additional-variables '(search-ring regexp-search-ring)))

(use-package recentf
  :ensure nil
  :hook (after-init . recentf-mode)
  :custom
  (recentf-max-saved-items 200))

;;; Buffer and file behavior ------------------------------------------

(global-auto-revert-mode 1)
(setq global-auto-revert-non-file-buffers t)

(setq uniquify-buffer-name-style 'forward)

(electric-pair-mode 1)

(setq use-short-answers t)

;; Suppress all native GUI dialogs — keep everything in the minibuffer.
(setq use-dialog-box nil)

;; Prevent accidentally suspending/minimizing Emacs.
(global-unset-key (kbd "C-z"))
(global-unset-key (kbd "C-x C-z"))

;; Silence the audible bell and visual flash.
(setq ring-bell-function 'ignore)

(blink-cursor-mode -1)

(column-number-mode 1)

(delete-selection-mode 1)

(setq scroll-conservatively 101
      scroll-margin 2)

(setq create-lockfiles nil)

(set-default-coding-systems 'utf-8)
(prefer-coding-system 'utf-8)

;; Redirect customize writes to a separate file so they don't pollute init.el.
(setq custom-file (my-emacs-state-file "etc/custom.el"))
(when (file-exists-p custom-file)
  (load custom-file 'noerror))

;;; Credential store ---------------------------------------------------
;; Prefer encrypted .authinfo.gpg for future credential needs
;; (elfeed-protocol, mail clients).  Falls back to plaintext.
(setq auth-sources '("~/.authinfo.gpg" "~/.authinfo"))

;;; External tool check ------------------------------------------------
;; Warn at startup if expected external tools are missing.
(defvar my-core--expected-tools '("curl" "pandoc" "rg")
  "External tools that modules expect to be available.")

(defun my-core--check-external-tools ()
  "Warn about missing external tools from `my-core--expected-tools'."
  (require 'seq)
  (let ((missing (seq-remove #'executable-find my-core--expected-tools)))
    (when missing
      (display-warning
       'init
       (format "Missing external tools: %s"
               (string-join missing ", "))
       :warning))))

(add-hook 'emacs-startup-hook #'my-core--check-external-tools)

;;; Server mode --------------------------------------------------------
;; Allow emacsclient connections (e.g. scripts/bookmark-open).
;; Platform-specific socket compatibility belongs in OS modules.
(require 'server)

(defconst my-core-server-dir
  (no-littering-expand-var-file-name "server/")
  "Stable directory for the primary Emacs server socket.")

(defvar my-core-after-server-ready-hook nil
  "Hook run after `my-core--ensure-server' verifies server access.")

(defun my-core--local-server-sockets-supported-p ()
  "Return non-nil when this Emacs build supports local server sockets."
  (featurep 'make-network-process '(:family local)))

(defun my-core--ensure-server ()
  "Start the Emacs server if needed and run post-start hooks."
  (make-directory my-core-server-dir t)
  ;; Emacs refuses to place server sockets in directories that are
  ;; accessible by other users.
  (set-file-modes my-core-server-dir #o700)
  (setq server-auth-dir my-core-server-dir)
  (if (my-core--local-server-sockets-supported-p)
      (setq server-use-tcp nil
            server-socket-dir my-core-server-dir)
    (setq server-use-tcp t))
  (let ((server-state (server-running-p server-name)))
    (when (null server-state)
      (server-start)
      (setq server-state t))
    (when server-state
      (run-hooks 'my-core-after-server-ready-hook))))

(add-hook 'after-init-hook #'my-core--ensure-server)

;;; Keybinding discovery ----------------------------------------------
;; Shows available keybindings after a prefix key is pressed.
;; Built-in from Emacs 30; package for Emacs 29.
(use-package which-key
  :hook (after-init . which-key-mode)
  :custom
  (which-key-idle-delay 0.5))

(provide 'my-core)
;;; my-core.el ends here
