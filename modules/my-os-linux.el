;;; my-os-linux.el --- Linux-specific settings -*- lexical-binding: t; -*-

;; Linux-specific configuration: clipboard selection behavior,
;; trash integration, and file manager integration via xdg-open.

;;; Clipboard ---------------------------------------------------------
;; Use both clipboard and primary selection on Linux desktops.
(setq select-enable-clipboard t
      select-enable-primary t)

;;; Trash integration -------------------------------------------------
;; Delete files to Trash instead of permanent delete when supported.
(setq delete-by-moving-to-trash t)

;;; File manager integration -------------------------------------------
(defun my-reveal-in-file-manager ()
  "Reveal current file or directory in the desktop file manager."
  (interactive)
  (let* ((path (expand-file-name (or (buffer-file-name) default-directory)))
         (dir (if (file-directory-p path) path (file-name-directory path))))
    (cond
     ((executable-find "xdg-open")
      (start-process "my-reveal" nil "xdg-open" dir))
     ((executable-find "gio")
      (start-process "my-reveal" nil "gio" "open" dir))
     (t
      (user-error "No file manager opener found (tried xdg-open and gio)")))))

(provide 'my-os-linux)
;;; my-os-linux.el ends here
