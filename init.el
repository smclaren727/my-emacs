;;; init.el --- Bootstrap and orchestration -*- lexical-binding: t; -*-

;; This file does four things:
;; 1. Sets load-path
;; 2. Loads feature flags
;; 3. Bootstraps package.el and use-package
;; 4. Loads modules conditionally
;;
;; No configuration logic belongs here.

;;; Load path ---------------------------------------------------------
(add-to-list 'load-path (expand-file-name "core" user-emacs-directory))
(add-to-list 'load-path (expand-file-name "modules" user-emacs-directory))

;;; Feature flags -----------------------------------------------------
;; Loaded first so all module decisions can reference these variables.
(require 'my-flags)

;;; Package bootstrap -------------------------------------------------
;; Initialize package.el and sources before any use-package forms.
(require 'package)
(setq package-archives
      '(("gnu"   . "https://elpa.gnu.org/packages/")
        ("melpa" . "https://melpa.org/packages/")))
(package-initialize)

;; use-package is built-in from Emacs 29+.
(require 'use-package)
(setq use-package-always-ensure t)

;;; Loader — must succeed ---------------------------------------------
;; Provides the `my-load-module' macro used below.
(require 'my-loader)

;;; Core — must succeed -----------------------------------------------
;; If core fails, we want a hard error.  Do not wrap this.
;; Core sets up: no-littering, sane defaults, and startup restoration.
(require 'my-core)

;;; Optional modules --------------------------------------------------
;; Each is guarded by its feature flag and wrapped in error handling.
;; A broken module logs to *startup-errors* but does not take down Emacs.

(when (eq system-type 'darwin)
  (my-load-module os-macos "my-os-macos"))

(when my-flag-ui
  (my-load-module ui "my-ui"))

(when my-flag-editing
  (my-load-module editing "my-editing"))

(when my-flag-dev
  (my-load-module dev "my-dev"))

(when my-flag-org
  (my-load-module org-mode "my-org-mode"))

(when my-flag-ai
  (my-load-module ai "my-ai"))

(when my-flag-ops
  (my-load-module ops "my-ops"))

(when my-flag-shells
  (my-load-module shells "my-shells"))

;;; init.el ends here
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(custom-safe-themes
   '("1b7e575c6681e66d8d83634c2c160b40af12f3756360a4dd81b8032f4495cb5e"
     "0325a6b5eea7e5febae709dab35ec8648908af12cf2d2b569bedc8da0a3a81c1"
     "6a95b0faf6cee6adfda34cdfadb2fed6f4157a1d49aabef8cc9b94c187d69a1d"
     default))
 '(package-selected-packages nil))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
