;;; my-leader.el --- Personal leader key -*- lexical-binding: t; -*-

;; Provides a unified leader keymap accessible via:
;;   - double-space chord (ergonomic, requires key-chord)
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
(condition-case err
    (use-package key-chord
      :demand t
      :config
      (setq key-chord-two-keys-delay 0.05)
      (key-chord-define-global "  " 'my-leader-command)
      (key-chord-mode 1))
  (error
   (display-warning
    'my-leader
    (format "key-chord unavailable; using C-c u only: %s"
            (error-message-string err))
    :warning)))

;;; Binding helper ----------------------------------------------------
(defun my-leader-define (key command)
  "Bind KEY to COMMAND in the leader map.
KEY is a string accepted by `kbd'."
  (define-key my-leader-map (kbd key) command))

;;; Bindings ----------------------------------------------------------
;; Organized alphabetically by prefix.  Commands from optional modules
;; are bound here as symbols; they resolve at call time so loading order
;; doesn't matter.

;; b = buffer
(my-leader-define "b b" #'bury-buffer)
(my-leader-define "b k" #'kill-current-buffer)
(my-leader-define "b l" #'ibuffer)
(my-leader-define "b r" #'rename-buffer)
(my-leader-define "b s" #'switch-to-buffer)
(my-leader-define "b v" #'revert-buffer)

;; c = compile / build
(my-leader-define "c c" #'compile)
(my-leader-define "c d" #'flymake-show-buffer-diagnostics)
(my-leader-define "c n" #'flymake-goto-next-error)
(my-leader-define "c p" #'flymake-goto-prev-error)
(my-leader-define "c r" #'recompile)

;; d = dired
(my-leader-define "d c" #'dired-create-directory)
(my-leader-define "d d" #'dired)
(my-leader-define "d g" #'revert-buffer)
(my-leader-define "d j" #'dired-jump)
(my-leader-define "d m" #'dired-mark)
(my-leader-define "d n" #'dired-create-empty-file)
(my-leader-define "d p" #'dired-jump-other-window)
(my-leader-define "d r" #'wdired-change-to-wdired-mode)
(my-leader-define "d t" #'dired-toggle-marks)
(my-leader-define "d u" #'dired-unmark)

;; e = emacs / evaluate
(my-leader-define "e b" #'eval-buffer)
(my-leader-define "e r" #'eval-region)
(my-leader-define "e e" #'eval-expression)

;; f = files / search
(my-leader-define "f f" #'project-find-file)
(my-leader-define "f g" #'consult-ripgrep)
(my-leader-define "f r" #'my-reveal-in-file-manager)

;; g = git
(my-leader-define "g b" #'magit-blame-addition)
(my-leader-define "g c" #'magit-commit-create)
(my-leader-define "g g" #'magit-status)
(my-leader-define "g l" #'magit-log-current)

;; h = help
(my-leader-define "h f" #'describe-function)
(my-leader-define "h k" #'describe-key)
(my-leader-define "h m" #'describe-mode)
(my-leader-define "h v" #'describe-variable)

;; o = org
(my-leader-define "o a" #'org-agenda)
(my-leader-define "o c" #'org-capture)
(my-leader-define "o g" #'org-goto)
(my-leader-define "o i" #'org-id-get-create)
(my-leader-define "o l" #'org-store-link)
(my-leader-define "o o" #'org-occur)
(my-leader-define "o r" #'org-refile)
(my-leader-define "o t" #'org-todo)

;; p = project
(my-leader-define "p f" #'project-find-file)
(my-leader-define "p s" #'project-switch-project)

;; s = shell
(my-leader-define "s n" #'my-shell-named)
(my-leader-define "s s" #'my-shell-here)
(my-leader-define "s w" #'my-shell-switch)

;; w = window
(my-leader-define "w b" #'balance-windows)
(my-leader-define "w d" #'delete-window)
(my-leader-define "w o" #'delete-other-windows)
(my-leader-define "w r" #'winner-redo)
(my-leader-define "w s" #'split-window-below)
(my-leader-define "w u" #'winner-undo)
(my-leader-define "w v" #'split-window-right)

;;; Which-key descriptions --------------------------------------------
(with-eval-after-load 'which-key
  (which-key-add-keymap-based-replacements my-leader-map
    "b" "buffer"
    "c" "compile"
    "d" "dired"
    "e" "emacs/eval"
    "f" "files"
    "g" "git"
    "h" "help"
    "o" "org"
    "p" "project"
    "s" "shell"
    "w" "window"))

(provide 'my-leader)
;;; my-leader.el ends here
