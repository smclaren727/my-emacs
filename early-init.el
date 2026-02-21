;;; early-init.el --- Pre-initialization -*- lexical-binding: t; -*-

;; This file runs before init.el and before the package system or UI
;; initializes.  Keep it minimal: performance and visual suppression only.

;;; Startup performance -----------------------------------------------
;; Temporarily disable GC and file-name-handler processing during init.
;; Both are restored in my-core.el via emacs-startup-hook.
(setq gc-cons-threshold most-positive-fixnum)

(defvar my-early--file-name-handler-alist file-name-handler-alist
  "Saved value of `file-name-handler-alist' to restore after init.")
(setq file-name-handler-alist nil)

;;; UI suppression ----------------------------------------------------
;; Prevent visual elements from flashing before our config hides them.
;; These are reset or configured properly in the ui module.
(setq inhibit-startup-screen t
      inhibit-startup-echo-area-message user-login-name)

(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)
(push '(fullscreen . maximized) default-frame-alist)

;; Prevent package.el from inserting (package-initialize) into init.el.
;; We call it ourselves in init.el after setting up sources.
(setq package-enable-at-startup nil)

;;; Native compilation ------------------------------------------------
;; Silence compiler warnings during async native compilation.
;; We assume native-comp is available (emacs-plus build).
(when (featurep 'native-compile)
  (setq native-comp-async-report-warnings-errors 'silent))

;; Suppress byte-compile warnings from third-party packages.
(setq byte-compile-warnings '(not docstrings free-vars))

;;; Frame resize ------------------------------------------------------
;; Pixel-wise resizing prevents gaps when using tiling window managers.
(setq frame-resize-pixelwise t)

;;; early-init.el ends here
