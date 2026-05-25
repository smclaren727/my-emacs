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

(defalias 'my-leader-command my-leader-map)

;;; Entry points ------------------------------------------------------

;; Conventional prefix — always works, no dependencies.
(global-set-key (kbd "C-c u") #'my-leader-command)

;; Ergonomic chord via key-chord.
(if (or use-package-always-ensure
        (locate-library "key-chord"))
    (condition-case err
        (use-package key-chord
          :demand t
          :config
          (setq key-chord-two-keys-delay 0.05)
          (key-chord-define-global "  " #'my-leader-command)
          (key-chord-mode 1))
      (error
       (display-warning
        'my-leader
        (format "key-chord unavailable; using C-c u only: %s"
                (error-message-string err))
        :warning)))
  (unless (eq my-host-type 'node)
    (display-warning
     'my-leader
     "key-chord unavailable; using C-c u only."
     :warning)))

;;; Binding helper ----------------------------------------------------
(defun my-leader-define (key command)
  "Bind KEY to COMMAND in the leader map.
KEY is a string accepted by `kbd'."
  (define-key my-leader-map (kbd key) command))

(defvar my-leader--default-bindings nil
  "Alist of leader bindings last installed as core defaults.")

(defun my-leader--lookup (key)
  "Return the exact leader binding for KEY, or nil when KEY is unbound."
  (let ((binding (lookup-key my-leader-map (kbd key))))
    (unless (numberp binding)
      binding)))

(defun my-leader-define-default (key command)
  "Bind KEY to COMMAND unless a module has replaced the core default."
  (let ((current (my-leader--lookup key))
        (previous (alist-get key my-leader--default-bindings nil nil #'equal)))
    (when (or (null current)
              (eq current previous)
              (and (null previous)
                   (eq current command)))
      (my-leader-define key command)
      (setf (alist-get key my-leader--default-bindings nil nil #'equal)
            command))))

;;; Bindings ----------------------------------------------------------
;; Organized alphabetically by prefix.  Commands from optional modules
;; are bound here as symbols; they resolve at call time so loading order
;; doesn't matter.

;; b = buffer
(my-leader-define-default "b b" #'bury-buffer)
(my-leader-define-default "b k" #'kill-current-buffer)
(my-leader-define-default "b l" #'ibuffer)
(my-leader-define-default "b r" #'rename-buffer)
(my-leader-define-default "b s" #'switch-to-buffer)
(my-leader-define-default "b v" #'revert-buffer)

;; c = compile / build
(my-leader-define-default "c c" #'compile)
(my-leader-define-default "c d" #'flymake-show-buffer-diagnostics)
(my-leader-define-default "c n" #'flymake-goto-next-error)
(my-leader-define-default "c p" #'flymake-goto-prev-error)
(my-leader-define-default "c r" #'recompile)

;; d = dired
(my-leader-define-default "d c" #'dired-create-directory)
(my-leader-define-default "d d" #'dired)
(my-leader-define-default "d g" #'revert-buffer)
(my-leader-define-default "d j" #'dired-jump)
(my-leader-define-default "d m" #'dired-mark)
(my-leader-define-default "d n" #'dired-create-empty-file)
(my-leader-define-default "d p" #'dired-jump-other-window)
(my-leader-define-default "d r" #'wdired-change-to-wdired-mode)
(my-leader-define-default "d t" #'dired-toggle-marks)
(my-leader-define-default "d u" #'dired-unmark)

;; e = emacs / evaluate
(my-leader-define-default "e b" #'eval-buffer)
(my-leader-define-default "e r" #'eval-region)
(my-leader-define-default "e e" #'eval-expression)

;; f = files / search
(my-leader-define-default "f f" #'project-find-file)
(my-leader-define-default "f g" #'consult-ripgrep)
(my-leader-define-default "f r" #'my-reveal-in-file-manager)

;; g = git
(my-leader-define-default "g b" #'magit-blame-addition)
(my-leader-define-default "g c" #'magit-commit-create)
(my-leader-define-default "g g" #'magit-status)
(my-leader-define-default "g l" #'magit-log-current)

;; h = help
(my-leader-define-default "h f" #'describe-function)
(my-leader-define-default "h k" #'describe-key)
(my-leader-define-default "h m" #'describe-mode)
(my-leader-define-default "h v" #'describe-variable)

;; n = news / feeds
(my-leader-define-default "n b" #'my-feeds-browse-article)
(my-leader-define-default "n d" #'my-feeds-save-article)
(my-leader-define-default "n f" #'my-feeds-open-feed-file)
(my-leader-define-default "n n" #'elfeed)
(my-leader-define-default "n s" #'my-feeds-show-starred)
(my-leader-define-default "n u" #'elfeed-update)

;; o = org
(my-leader-define-default "o a" #'org-agenda)
(my-leader-define-default "o c" #'org-capture)
(my-leader-define-default "o g" #'org-goto)
(my-leader-define-default "o i" #'org-id-get-create)
(my-leader-define-default "o l" #'org-store-link)
(my-leader-define-default "o o" #'org-occur)
(my-leader-define-default "o m" #'org-refile)
(my-leader-define-default "o s" #'org-set-tags-command)
(my-leader-define-default "o t" #'org-todo)

;; p = project
(my-leader-define-default "p f" #'project-find-file)
(my-leader-define-default "p s" #'project-switch-project)

;; r = remote / TRAMP
(my-leader-define-default "r a" #'my-tramp-cleanup-all-connections)
(my-leader-define-default "r b" #'my-tramp-cleanup-all-buffers)
(my-leader-define-default "r c" #'my-tramp-cleanup-current-connection)
(my-leader-define-default "r d" #'my-tramp-open-nixos-directory)
(my-leader-define-default "r f" #'my-tramp-open-nixos-config)
(my-leader-define-default "r l" #'my-tramp-open-local-shell)
(my-leader-define-default "r n" #'my-tramp-open-nixos-modules)
(my-leader-define-default "r s" #'my-tramp-sudo-edit-current-file)
(my-leader-define-default "r t" #'my-tramp-open-shell)
(my-leader-define-default "r T" #'my-tramp-open-tailscale-shell)

;; s = shell
(my-leader-define-default "s n" #'my-shell-named)
(my-leader-define-default "s s" #'my-shell-here)
(my-leader-define-default "s w" #'my-shell-switch)

;; w = window
(my-leader-define-default "w b" #'balance-windows)
(my-leader-define-default "w d" #'delete-window)
(my-leader-define-default "w o" #'delete-other-windows)
(my-leader-define-default "w r" #'winner-redo)
(my-leader-define-default "w s" #'split-window-below)
(my-leader-define-default "w u" #'winner-undo)
(my-leader-define-default "w v" #'split-window-right)

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
    "n" "news/feeds"
    "o" "org"
    "p" "project"
    "r" "remote"
    "s" "shell"
    "w" "window"))

(provide 'my-leader)
;;; my-leader.el ends here
