;;; my-os-macos.el --- macOS-specific settings -*- lexical-binding: t; -*-

;;; Modifier keys -----------------------------------------------------
(setq mac-command-modifier 'meta
      mac-option-modifier 'super
      mac-function-modifier 'hyper
      mac-right-option-modifier 'none)

;;; Shell PATH --------------------------------------------------------
;; GUI Emacs on macOS doesn't inherit the terminal's $PATH.
(use-package exec-path-from-shell
  :if (display-graphic-p)
  :config
  (exec-path-from-shell-initialize))

;;; Clipboard ---------------------------------------------------------
(setq select-enable-clipboard t
      select-enable-primary nil)

;;; Trash integration -------------------------------------------------
;; Delete files to Trash instead of permanent delete.
(setq delete-by-moving-to-trash t)

;;; Frame appearance --------------------------------------------------
;; Remove thin border introduced in macOS Monterey.
(set-frame-parameter nil 'internal-border-width 0)

;;; Titlebar ----------------------------------------------------------
(use-package ns-auto-titlebar
  :config
  (ns-auto-titlebar-mode 1))

;;; Input protection --------------------------------------------------
;; Prevent trackpad pinch and ctrl-wheel from resizing font accidentally.
(global-set-key (kbd "<pinch>") 'ignore)
(global-set-key (kbd "<C-wheel-up>") 'ignore)
(global-set-key (kbd "<C-wheel-down>") 'ignore)

;;; Fonts — Unicode and emoji -----------------------------------------
;; Render Apple Color Emoji and SF symbols correctly in GUI frames.
(when (display-graphic-p)
  (set-fontset-font t 'symbol
                    (font-spec :family "Apple Color Emoji") nil 'prepend)
  (set-fontset-font t nil "SF Pro Display" nil 'append))

;;; Reveal in Finder --------------------------------------------------
(defun my-os-macos-reveal-in-finder ()
  "Reveal the current file or directory in Finder."
  (interactive)
  (let ((path (or (buffer-file-name) default-directory)))
    (call-process "open" nil 0 nil "-R" (expand-file-name path))))

(provide 'my-os-macos)
;;; my-os-macos.el ends here
