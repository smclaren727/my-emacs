;;; my-files.el --- File browsing and Dired enhancements -*- lexical-binding: t; -*-

;; Dirvish keeps Dired as the foundation while adding a more familiar,
;; polished file-manager surface.

;;; Dired -------------------------------------------------------------

(use-package dired
  :ensure nil
  :config
  (put 'dired-find-alternate-file 'disabled nil)
  (when (or (not (memq system-type '(darwin windows-nt)))
            (and (boundp 'insert-directory-program)
                 insert-directory-program
                 (string-match-p "\\(?:g\\)?ls\\'" insert-directory-program)))
    (setq dired-listing-switches
          "-l --almost-all --human-readable --group-directories-first --no-group"))
  (when (boundp 'dired-mouse-drag-files)
    (setq dired-mouse-drag-files t))
  (when (boundp 'mouse-drag-and-drop-region-cross-program)
    (setq mouse-drag-and-drop-region-cross-program t)))

;; Dirvish already draws Nerd Icons via its `nerd-icons' attribute.  Keep this
;; package available for plain Dired without double-decorating Dirvish rows.
(use-package nerd-icons-dired
  :after dired
  :commands nerd-icons-dired-mode)

;;; Dirvish -----------------------------------------------------------

(use-package dirvish
  :after dired
  :commands (dirvish dirvish-dwim dirvish-dispatch)
  :init
  ;; Keep standard Dired as the default while Dirvish is still settling into
  ;; the workflow.  Invoke Dirvish explicitly with `dirvish' or `dirvish-dwim'.
  (my-leader-define "d D" #'dirvish-dwim)
  :custom
  (dirvish-attributes
   '(vc-state subtree-state nerd-icons collapse file-time file-size))
  (dirvish-side-attributes
   '(vc-state nerd-icons collapse file-size))
  (dirvish-large-directory-threshold 20000)
  :config
  (setq dirvish-mode-line-format
        '(:left (sort symlink) :right (omit yank index))))

(use-package treemacs-nerd-icons
  :after treemacs
  :config
  (treemacs-nerd-icons-config))

(provide 'my-files)
;;; my-files.el ends here
