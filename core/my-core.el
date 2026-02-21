;;; my-core.el --- Production-safe defaults -*- lexical-binding: t; -*-

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

;;; Keybinding discovery ----------------------------------------------
;; Shows available keybindings after a prefix key is pressed.
;; Built-in from Emacs 30; package for Emacs 29.
(use-package which-key
  :hook (after-init . which-key-mode)
  :custom
  (which-key-idle-delay 0.5))

(provide 'my-core)
;;; my-core.el ends here
