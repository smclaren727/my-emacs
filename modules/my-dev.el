;;; my-dev.el --- Development tools -*- lexical-binding: t; -*-

;; Development tools: project management, compilation, git (magit +
;; diff-hl), tree-sitter grammars, LSP via eglot, syntax checking
;; (flymake), and code hygiene (hl-todo, trailing whitespace).
;; Language servers must be installed separately.

;;; Project management ------------------------------------------------
(use-package project
  :ensure nil)

;;; Compilation -------------------------------------------------------
;; Run build commands from Emacs.  Scroll stops at first error.
(use-package compile
  :ensure nil
  :custom
  (compilation-scroll-output 'first-error))

;;; Git ---------------------------------------------------------------
(use-package magit
  :bind
  (("C-x g" . magit-status))
  :custom
  (magit-save-repository-buffers 'dontask))

(use-package diff-hl
  :hook ((after-init  . global-diff-hl-mode)
         (magit-post-refresh . diff-hl-magit-post-refresh))
  :custom
  (diff-hl-draw-borders nil))

;;; Tree-sitter -------------------------------------------------------
(use-package treesit-auto
  :demand t
  :custom
  ;; Keep grammar installation explicit.  Prompting from file previews is
  ;; disruptive, especially in Dirvish buffers that briefly visit many files.
  (treesit-auto-install nil)
  :config
  (let (ready-langs unready-ts-modes)
    (dolist (recipe treesit-auto-recipe-list)
      (if (treesit-ready-p (treesit-auto-recipe-lang recipe) t)
          (push (treesit-auto-recipe-lang recipe) ready-langs)
        (push (treesit-auto-recipe-ts-mode recipe) unready-ts-modes)))
    (setq treesit-auto-langs (nreverse ready-langs))
    (setq auto-mode-alist
          (delq nil
                (mapcar (lambda (entry)
                          (unless (memq (cdr entry) unready-ts-modes)
                            entry))
                        auto-mode-alist))))
  ;; Only register tree-sitter modes whose grammars are actually installed.
  ;; Missing grammars fall back to regular modes instead of warning during
  ;; file previews, for example when Dirvish previews JSON files.
  ;; Avoid `global-treesit-auto-mode' here: it advises `set-auto-mode-0',
  ;; so unrelated file scans such as `org-refile' target collection can end
  ;; up recomputing tree-sitter remaps for every visited file.
  (treesit-auto-add-to-auto-mode-alist treesit-auto-langs))

;;; LSP via Eglot -----------------------------------------------------
;; Language servers must be installed separately:
;;   Python:     pip3 install python-lsp-server
;;   TypeScript: npm install -g typescript-language-server typescript
(use-package eglot
  :ensure nil
  :hook ((python-ts-mode     . eglot-ensure)
         (js-ts-mode         . eglot-ensure)
         (typescript-ts-mode . eglot-ensure)
         (tsx-ts-mode        . eglot-ensure))
  :custom
  (eglot-autoshutdown t)
  (eglot-send-changes-idle-time 0.5))

;;; Syntax checking ---------------------------------------------------
(use-package flymake
  :ensure nil
  :hook (prog-mode . flymake-mode)
  :bind
  (:map flymake-mode-map
        ("M-n" . flymake-goto-next-error)
        ("M-p" . flymake-goto-prev-error)
        ("C-c u e" . flymake-show-buffer-diagnostics)))

(defun my-dev--scratch-buffer-p ()
  "Return non-nil when the current buffer is the scratch buffer."
  (and (derived-mode-p 'lisp-interaction-mode)
       (string= (buffer-name) "*scratch*")))

(defun my-dev--flymake-enable-request-p (arg)
  "Return non-nil when ARG requests enabling Flymake."
  (or (null arg)
      (and (numberp arg)
           (> arg 0))))

(defun my-dev--inhibit-flymake-in-scratch (orig-fn &optional arg)
  "Keep Flymake disabled in `*scratch*' while delegating to ORIG-FN."
  (unless (and (my-dev--scratch-buffer-p)
               (my-dev--flymake-enable-request-p arg))
    (funcall orig-fn arg)))

(advice-add 'flymake-mode :around #'my-dev--inhibit-flymake-in-scratch)

;;; Misc dev quality of life ------------------------------------------

(use-package paren
  :ensure nil
  :custom
  (show-paren-delay 0)
  :config
  (show-paren-mode 1))

(use-package hl-todo
  :hook (prog-mode . hl-todo-mode))

(defun my-dev--delete-trailing-whitespace ()
  "Delete trailing whitespace in programming buffers."
  (when (derived-mode-p 'prog-mode)
    (delete-trailing-whitespace)))

(add-hook 'before-save-hook #'my-dev--delete-trailing-whitespace)

(provide 'my-dev)
;;; my-dev.el ends here
