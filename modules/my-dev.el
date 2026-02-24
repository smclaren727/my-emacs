;;; my-dev.el --- Development tools -*- lexical-binding: t; -*-

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
  (treesit-auto-install 'prompt)
  :config
  (treesit-auto-add-to-auto-mode-alist 'all)
  (global-treesit-auto-mode 1))

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

;;; Misc dev quality of life ------------------------------------------

(use-package paren
  :ensure nil
  :custom
  (show-paren-delay 0)
  :config
  (show-paren-mode 1))

(use-package hl-todo
  :hook (prog-mode . hl-todo-mode))

(add-hook 'before-save-hook
          (lambda ()
            (when (derived-mode-p 'prog-mode)
              (delete-trailing-whitespace))))

(provide 'my-dev)
;;; my-dev.el ends here
