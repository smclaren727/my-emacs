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

;; Give GUI frames the soft NANO-style shell as early as possible.
;; Unsupported frame parameters are harmless on builds without the patches.
(if (eq system-type 'darwin)
    (progn
      (push '(width . 92) default-frame-alist)
      (push '(height . 42) default-frame-alist)
      (push '(alpha-background . 88) default-frame-alist)
      (push '(ns-background-blur . 30) default-frame-alist)
      (push '(ns-alpha-elements . (ns-alpha-all)) default-frame-alist))
  (push '(fullscreen . maximized) default-frame-alist))

;; Prevent package.el from inserting (package-initialize) into init.el.
;; We call it ourselves in init.el after setting up sources.
(setq package-enable-at-startup nil)

;;; Native compilation ------------------------------------------------
(defun my-early--homebrew-gcc-runtime-dir ()
  "Return the Homebrew GCC runtime directory containing `libemutls_w.a'."
  (let ((match
         (car (file-expand-wildcards
               "/opt/homebrew/lib/gcc/current/gcc/*/*/libemutls_w.a"))))
    (when match
      (directory-file-name (file-name-directory match)))))

;; Silence compiler warnings during async native compilation.
;; We assume native-comp is available (emacs-plus build).
(when (featurep 'native-compile)
  (require 'comp)
  (setq native-comp-async-report-warnings-errors 'silent)
  (let ((gcc-runtime-dir (my-early--homebrew-gcc-runtime-dir)))
    (when gcc-runtime-dir
      (let ((existing-library-path (getenv "LIBRARY_PATH")))
        (setenv "LIBRARY_PATH"
                (if (and existing-library-path
                         (> (length existing-library-path) 0))
                    (concat gcc-runtime-dir ":" existing-library-path)
                  gcc-runtime-dir)))
      ;; Async native-comp workers need an explicit search path on macOS
      ;; so the linker can find Homebrew's GCC runtime libraries.
      (setq native-comp-driver-options
            (delete-dups
             (append native-comp-driver-options
                     (list (concat "-L" gcc-runtime-dir))))))))

;; Suppress byte-compile warnings from third-party packages.
(setq byte-compile-warnings '(not docstrings free-vars))

;;; Frame resize ------------------------------------------------------
;; Pixel-wise resizing prevents gaps when using tiling window managers.
(setq frame-resize-pixelwise t)

;;; early-init.el ends here
