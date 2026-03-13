;;; my-editing.el --- Completion and editing enhancements -*- lexical-binding: t; -*-

;; Completion and text editing enhancements.  Minibuffer narrowing
;; (vertico + orderless + marginalia + consult + embark), in-buffer
;; completion (corfu + cape), visual undo (vundo), and markdown
;; support.  No development-specific or org-specific config here.

;;; Minibuffer completion ---------------------------------------------

(use-package vertico
  :hook (after-init . vertico-mode)
  :custom
  (vertico-count 12)
  (vertico-cycle t))

(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles partial-completion)))))

(use-package marginalia
  :hook (after-init . marginalia-mode))

(use-package consult
  :bind
  (("C-s"     . consult-line)
   ("C-x b"   . consult-buffer)
   ("M-g g"   . consult-goto-line)
   ("M-g M-g" . consult-goto-line)
   ("M-s f"   . consult-find)
   ("C-x r b" . consult-bookmark)
   ("M-y"     . consult-yank-pop)))

(use-package embark
  :bind
  (("C-."   . embark-act)
   ("C-;"   . embark-dwim)
   ("C-h B" . embark-bindings))
  :custom
  (prefix-help-command #'embark-prefix-help-command))

(use-package embark-consult
  :after (embark consult)
  :hook (embark-collect-mode . consult-preview-at-point-mode))

;;; In-buffer completion ----------------------------------------------

(use-package corfu
  :hook (after-init . global-corfu-mode)
  :custom
  (corfu-auto t)
  (corfu-auto-delay 0.2)
  (corfu-auto-prefix 2)
  (corfu-cycle t)
  (corfu-preselect 'prompt)
  :bind
  (:map corfu-map
        ("RET" . corfu-insert)
        ("TAB" . corfu-next)
        ([tab] . corfu-next)))

(use-package cape
  :init
  (add-hook 'completion-at-point-functions #'cape-dabbrev)
  (add-hook 'completion-at-point-functions #'cape-file)
  (add-hook 'completion-at-point-functions #'cape-keyword))

;;; Undo --------------------------------------------------------------

(use-package vundo
  :bind ("C-x u" . vundo)
  :custom
  (vundo-glyph-alist vundo-unicode-symbols))

;;; Markdown ----------------------------------------------------------

(use-package markdown-mode
  :mode ("\\.md\\'" . markdown-mode)
  :custom
  (markdown-command "pandoc")
  (markdown-fontify-code-blocks-natively t)
  (markdown-header-scaling t)
  (markdown-enable-math t))

(use-package markdown-indent-mode
  :hook (markdown-mode . markdown-indent-mode))

(provide 'my-editing)
;;; my-editing.el ends here
