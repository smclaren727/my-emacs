;;; my-os-linux.el --- Linux-specific settings -*- lexical-binding: t; -*-

;;; Clipboard ---------------------------------------------------------
;; Use both clipboard and primary selection on Linux desktops.
(setq select-enable-clipboard t
      select-enable-primary t)

;;; Trash integration -------------------------------------------------
;; Delete files to Trash instead of permanent delete when supported.
(setq delete-by-moving-to-trash t)

(provide 'my-os-linux)
;;; my-os-linux.el ends here
