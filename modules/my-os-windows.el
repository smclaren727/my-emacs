;;; my-os-windows.el --- Windows-specific settings -*- lexical-binding: t; -*-

;; Windows-specific configuration: Super modifier mapping for
;; Windows keys, clipboard, trash/Recycle Bin integration, and
;; file manager integration via explorer.exe.

(defvar w32-lwindow-modifier)
(defvar w32-rwindow-modifier)

;;; Modifiers ---------------------------------------------------------
;; Keep both Windows keys available as Super modifiers.
(setq w32-lwindow-modifier 'super
      w32-rwindow-modifier 'super)

;;; Clipboard ---------------------------------------------------------
(setq select-enable-clipboard t
      select-enable-primary nil)

;;; Trash integration -------------------------------------------------
;; Delete files to Recycle Bin when possible.
(setq delete-by-moving-to-trash t)

;;; File manager integration -------------------------------------------
(defun my-reveal-in-file-manager ()
  "Reveal current file or directory in Windows Explorer."
  (interactive)
  (let ((path (expand-file-name (or (buffer-file-name) default-directory))))
    (start-process
     "my-reveal" nil "explorer.exe"
     (if (file-directory-p path)
         (subst-char-in-string ?/ ?\\ path)
       (concat "/select," (subst-char-in-string ?/ ?\\ path))))))

(provide 'my-os-windows)
;;; my-os-windows.el ends here
