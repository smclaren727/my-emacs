;;; my-flags.el --- Feature flags for module loading -*- lexical-binding: t; -*-

;; Feature flags that control which modules load at startup.
;; Set a flag to nil to disable a module without removing any code.
;; Flags are checked in init.el before each my-load-module call.

(defvar my-flag-ui t
  "Load UI module (theme, modeline, fonts).")

(defvar my-flag-editing t
  "Load editing module (completion, minibuffer, undo, pairs).")

(defvar my-flag-dev t
  "Load development module (git, projects, LSP, tree-sitter).")

(defvar my-flag-org t
  "Load notes/org module (capture, agenda, IDs).")

(defvar my-flag-ai nil
  "Load AI module. Disabled until Phase 2 design is done.")

(defvar my-flag-ops nil
  "Load ops module (async processes, job runners, orchestration).")

(defvar my-flag-shells t
  "Load shell management module (quick commands and shell buffers).")

(defvar my-flag-tramp t
  "Load remote access module (TRAMP helpers and Nix host shortcuts).")

(defvar my-flag-feeds t
  "Load feeds module (elfeed RSS reader).")

(defvar my-flag-roam t
  "Load org-roam module (networked notes, backlinks, knowledge graph).")

(provide 'my-flags)
;;; my-flags.el ends here
