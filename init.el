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
(add-to-list 'load-path (expand-file-name "elisp" user-emacs-directory))
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

;;; Leader — must succeed ---------------------------------------------
;; Provides the leader keymap that modules bind into.
(require 'my-leader)

;;; Optional modules --------------------------------------------------
;; Each is guarded by its feature flag and wrapped in error handling.
;; A broken module logs to *startup-errors* but does not take down Emacs.
;; Exactly one OS module is loaded, based on `system-type`.

(cond
 ((eq system-type 'darwin)
  (my-load-module os-macos "my-os-macos"))
 ((eq system-type 'gnu/linux)
  (my-load-module os-linux "my-os-linux"))
 ((eq system-type 'windows-nt)
  (my-load-module os-windows "my-os-windows")))

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

(when my-flag-tramp
  (my-load-module tramp "my-tramp"))

(when my-flag-shells
  (my-load-module shells "my-shells"))

;;; init.el ends here
