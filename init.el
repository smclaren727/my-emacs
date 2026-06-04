;;; init.el --- Bootstrap and orchestration -*- lexical-binding: t; -*-

;; This file does four things:
;; 1. Sets load-path
;; 2. Loads feature flags
;; 3. Bootstraps package.el and use-package
;; 4. Loads modules conditionally
;;
;; No configuration logic belongs here.

;;; Source and host context --------------------------------------------
(defvar my-emacs-source-root
  (let ((source-root (getenv "MY_EMACS_SOURCE_ROOT")))
    (if (and source-root
             (file-directory-p source-root))
        (expand-file-name source-root)
      (expand-file-name user-emacs-directory)))
  "Root directory containing the tracked Emacs configuration source.")

(defvar my-host-type
  (pcase system-type
    ('darwin 'mac)
    ('gnu/linux 'linux)
    ('windows-nt 'windows)
    (_ 'unknown))
  "Current host profile.  `node' enables headless node-only behavior.")

(defvar my-package-vc-enabled t
  "Whether `use-package :vc' declarations may install packages on this host.")

;;; Load path ---------------------------------------------------------
(add-to-list 'load-path (expand-file-name "core" my-emacs-source-root))
(add-to-list 'load-path (expand-file-name "elisp" my-emacs-source-root))
(add-to-list 'load-path (expand-file-name "modules" my-emacs-source-root))

;;; Host context -------------------------------------------------------
(let ((host-context (getenv "MY_EMACS_HOST_CONTEXT")))
  (when (and host-context (file-readable-p host-context))
    (load host-context nil 'nomessage)))

;;; Feature flags -----------------------------------------------------
;; Loaded first so all module decisions can reference these variables.
(require 'my-flags)

;;; Package bootstrap -------------------------------------------------
;; Initialize package.el and sources before any use-package forms.
(require 'package)
(setq package-archives
      '(("gnu"   . "https://elpa.gnu.org/packages/")
        ("melpa" . "https://melpa.org/packages/")))
;; mu4e is provided by the system package manager, not ELPA.  Mark it as
;; built in so package-vc packages can declare a mu4e dependency cleanly.
(add-to-list 'package--builtin-versions (cons 'mu4e (version-to-list "0")))
(package-initialize)

;; use-package is built-in from Emacs 29+.
(require 'use-package)
(setq use-package-always-ensure (not (eq my-host-type 'node))
      my-package-vc-enabled (not (eq my-host-type 'node)))

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

;;; Platform module ---------------------------------------------------
;; OS integration is selected automatically from `my-host-type', which is
;; derived from `system-type' at the top of this file (and may be
;; overridden by a host-context shim, e.g. `node').

(pcase my-host-type
  ('mac     (my-load-module os-macos   "my-os-macos"))
  ('linux   (my-load-module os-linux   "my-os-linux"))
  ('windows (my-load-module os-windows "my-os-windows")))

;;; Optional modules --------------------------------------------------
;; Each is guarded by its feature flag and wrapped in error handling.
;; A broken module logs to *startup-errors* but does not take down Emacs.
;; Feature flags are for optional subsystems, not OS detection.

(when my-flag-ui
  (my-load-module ui "my-ui"))

(when my-flag-files
  (my-load-module files "my-files"))

(when my-flag-editing
  (my-load-module editing "my-editing"))

(when my-flag-dev
  (my-load-module dev "my-dev"))

(when my-flag-org
  (my-load-module org-mode "my-org-mode"))

(when my-flag-mail
  (my-load-module mail "my-mail"))

(when my-flag-ai
  (my-load-module ai "my-ai"))

(when my-flag-ops
  (my-load-module ops "my-ops"))

(when my-flag-tramp
  (my-load-module tramp "my-tramp"))

(when my-flag-shells
  (my-load-module shells "my-shells"))

(when my-flag-feeds
  (my-load-module feeds "my-feeds"))

(when my-flag-reading
  (my-load-module reading "my-reading"))

(when my-flag-vulpea
  (my-load-module vulpea "my-vulpea"))

(when my-flag-bookmarks
  (my-load-module bookmarks "my-bookmarks"))

(when my-flag-contacts
  (my-load-module contacts "my-contacts"))

(when my-flag-node
  (my-load-module node "my-node"))

;;; init.el ends here
