;;; my-os-windows.el --- Windows-specific settings -*- lexical-binding: t; -*-

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

(provide 'my-os-windows)
;;; my-os-windows.el ends here
