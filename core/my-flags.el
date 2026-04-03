;;; my-flags.el --- Feature flags for module loading -*- lexical-binding: t; -*-

;; Feature flags that control optional module loading at startup.
;; Platform modules are selected automatically via `system-type' in init.el.
;; Set a flag to nil to disable a subsystem without removing any code.
;; Flags are checked in init.el before each `my-load-module' call.

(defvar my-flag-ui t
  "Load UI module (theme, modeline, fonts).")

(defvar my-flag-editing t
  "Load editing module (completion, minibuffer, undo, pairs).")

(defvar my-flag-dev t
  "Load development module (git, projects, LSP, tree-sitter).")

(defvar my-flag-org t
  "Load notes/org module (capture, agenda, IDs).")

(defvar my-flag-ai t
  "Load AI module.")

(defvar my-flag-ops nil
  "Load ops module (async processes, job runners, orchestration).")

(defvar my-flag-shells t
  "Load shell management module (quick commands and shell buffers).")

(defvar my-flag-tramp t
  "Load remote access module (TRAMP helpers and Nix host shortcuts).")

(defvar my-flag-feeds t
  "Load feeds module (elfeed RSS reader).")

(defvar my-flag-nodes t
  "Load org-node module (networked notes, backlinks, node search).")

(defvar my-flag-bookmarks t
  "Load bookmarks module (org-based bookmark manager).")

(provide 'my-flags)
;;; my-flags.el ends here
