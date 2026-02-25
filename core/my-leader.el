;;; my-leader.el --- Personal leader key -*- lexical-binding: t; -*-

;; Provides a unified leader keymap accessible via:
;;   - "fj" chord (ergonomic, requires key-chord)
;;   - C-c u     (fallback, works everywhere including terminal/SSH)
;;
;; All personal bindings go in `my-leader-map'.  Both entry points
;; share the same map, so a binding added once works via either.

;;; Leader map --------------------------------------------------------
(defvar my-leader-map (make-sparse-keymap)
  "Keymap for all personal leader bindings.")

(define-prefix-command 'my-leader-command 'my-leader-map)

;;; Entry points ------------------------------------------------------

;; Conventional prefix — always works, no dependencies.
(global-set-key (kbd "C-c u") 'my-leader-command)

;; Ergonomic chord via key-chord.
(use-package key-chord
  :config
  (setq key-chord-two-keys-delay 0.05)
  (key-chord-define-global "fj" 'my-leader-command)
  (key-chord-mode 1))

;;; Binding helper ----------------------------------------------------
(defun my-leader-define (key command)
  "Bind KEY to COMMAND in the leader map.
KEY is a string accepted by `kbd'."
  (define-key my-leader-map (kbd key) command))

;;; Bindings ----------------------------------------------------------
;; Organized alphabetically by prefix.  Commands from optional modules
;; are bound here as symbols; they resolve at call time so loading order
;; doesn't matter.

;; c = compile / build
(my-leader-define "c c" #'compile)
(my-leader-define "c r" #'recompile)

;; e = emacs / evaluate
(my-leader-define "e b" #'eval-buffer)
(my-leader-define "e r" #'eval-region)
(my-leader-define "e e" #'eval-expression)

;; f = files / search
(my-leader-define "f f" #'project-find-file)
(my-leader-define "f g" #'consult-ripgrep)
(my-leader-define "f r" #'my-os-macos-reveal-in-finder) ; macOS only

;; g = git
(my-leader-define "g b" #'magit-blame-addition)
(my-leader-define "g g" #'magit-status)

;; o = org
(my-leader-define "o a" #'org-agenda)
(my-leader-define "o c" #'org-capture)
(my-leader-define "o l" #'org-store-link)
(my-leader-define "o r" #'org-refile)

;; p = project
(my-leader-define "p p" #'project-switch-project)

;; s = shell
(my-leader-define "s n" #'my-shell-named)
(my-leader-define "s s" #'my-shell-here)
(my-leader-define "s w" #'my-shell-switch)

;;; Which-key descriptions --------------------------------------------
(with-eval-after-load 'which-key
  (which-key-add-keymap-based-replacements my-leader-map
    "b" "buffer"
    "c" "compile"
    "e" "emacs/eval"
    "f" "files"
    "g" "git"
    "o" "org"
    "p" "project"
    "s" "shell"))

(provide 'my-leader)
;;; my-leader.el ends here
