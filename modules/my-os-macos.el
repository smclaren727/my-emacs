;;; my-os-macos.el --- macOS-specific settings -*- lexical-binding: t; -*-

;; macOS-specific configuration: modifier key mapping (Cmd → Meta,
;; Opt → Super, Fn → Hyper), shell PATH inheritance for GUI and daemon Emacs,
;; clipboard, trash, titlebar appearance, and file manager integration.

;;; Modifier keys -----------------------------------------------------
(setq mac-command-modifier 'meta
      mac-option-modifier 'super
      mac-function-modifier 'hyper
      mac-right-option-modifier 'none)

;;; Shell PATH --------------------------------------------------------
;; launchd-started Emacs on macOS doesn't inherit the shell's environment.
(use-package exec-path-from-shell
  :config
  (exec-path-from-shell-initialize))

;;; Emacs server compatibility ----------------------------------------
;; Keep plain `emacsclient` working by mirroring the stable socket into
;; the default macOS temp directory path that emacsclient probes.
(defun my-os-macos--default-server-socket ()
  "Return the default macOS emacsclient socket path for `server-name'."
  (expand-file-name
   server-name
   (expand-file-name (format "emacs%d/" (user-uid))
                     temporary-file-directory)))

(defun my-os-macos--link-default-server-socket (&rest _)
  "Expose the stable server socket at the default macOS client path."
  (when-let* (((not server-use-tcp))
              (server-dir server-socket-dir)
              (stable-socket (expand-file-name server-name server-dir))
              (default-socket (my-os-macos--default-server-socket)))
    (make-directory (file-name-directory default-socket) t)
    (let ((existing-link (file-symlink-p default-socket)))
      (cond
       ((and existing-link
             (string= existing-link stable-socket)))
       ((file-symlink-p default-socket)
        (delete-file default-socket)
        (make-symbolic-link stable-socket default-socket))
       ((file-exists-p default-socket)
        (display-warning
         'server
         (format "Leaving existing default emacsclient socket in place: %s"
                 default-socket)
         :warning))
       (t
        (make-symbolic-link stable-socket default-socket))))))

(add-hook 'my-core-after-server-ready-hook #'my-os-macos--link-default-server-socket)
(unless (advice-member-p #'my-os-macos--link-default-server-socket 'server-start)
  (advice-add 'server-start :after #'my-os-macos--link-default-server-socket))

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

;;; Dired — use GNU ls -------------------------------------------------
;; BSD ls lacks --dired; use Homebrew coreutils gls when available.
(when-let* ((gls (executable-find "gls")))
  (setq insert-directory-program gls))

;;; File manager integration -------------------------------------------
(defun my-reveal-in-file-manager ()
  "Reveal current file or directory in Finder."
  (interactive)
  (let ((path (expand-file-name (or (buffer-file-name) default-directory))))
    (start-process "my-reveal" nil "open" "-R" path)))

(provide 'my-os-macos)
;;; my-os-macos.el ends here
