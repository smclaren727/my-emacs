;;; my-tramp.el --- TRAMP helpers for remote workflows -*- lexical-binding: t; -*-

(require 'subr-x)

;;; Core TRAMP behavior -----------------------------------------------
(use-package tramp
  :ensure nil
  :custom
  (tramp-default-method "ssh")
  :config
  ;; Nix often installs tools outside standard remote PATH defaults.
  (dolist (path '("/run/current-system/sw/bin"
                  "/nix/var/nix/profiles/default/bin"))
    (add-to-list 'tramp-remote-path path 'append)))

;;; Nix host shortcuts ------------------------------------------------
(defvar my-tramp-default-host "nixnode"
  "Default SSH alias used by TRAMP helper commands.")

(defvar my-tramp-nixos-config-file "/etc/nixos/configuration.nix"
  "Path to the main NixOS configuration file on remote hosts.")

(defvar my-tramp-nixos-directory "/etc/nixos/"
  "Directory containing NixOS configuration files on remote hosts.")

(defun my-tramp--read-host (&optional prompt-host)
  "Return remote host alias, prompting when PROMPT-HOST is non-nil."
  (if prompt-host
      (read-string
       (format "TRAMP host (default %s): " my-tramp-default-host)
       nil nil my-tramp-default-host)
    my-tramp-default-host))

(defun my-tramp--remote-file (host path &optional sudo-p)
  "Return TRAMP file path on HOST for PATH.
When SUDO-P is non-nil, use a sudo hop as root."
  (let ((absolute-path (if (string-prefix-p "/" path) path (concat "/" path))))
    (if sudo-p
        (format "/ssh:%s|sudo:root@%s:%s" host host absolute-path)
      (format "/ssh:%s:%s" host absolute-path))))

(defun my-tramp-open-nixos-config (&optional prompt-host)
  "Open NixOS config on a remote host.  With prefix, prompt for host."
  (interactive "P")
  (let ((host (my-tramp--read-host prompt-host)))
    (find-file (my-tramp--remote-file host my-tramp-nixos-config-file))))

(defun my-tramp-open-nixos-directory (&optional prompt-host)
  "Open remote `/etc/nixos/` in Dired.  With prefix, prompt for host."
  (interactive "P")
  (let ((host (my-tramp--read-host prompt-host)))
    (dired (my-tramp--remote-file host my-tramp-nixos-directory))))

(defun my-tramp-open-shell (&optional prompt-host)
  "Open a shell at remote home directory.  With prefix, prompt for host."
  (interactive "P")
  (let* ((host (my-tramp--read-host prompt-host))
         (default-directory (my-tramp--remote-file host "~/"))
         (buffer-name (format "*shell:%s*" host)))
    (if (get-buffer buffer-name)
        (pop-to-buffer buffer-name)
      (shell buffer-name))))

(defun my-tramp-sudo-edit-current-file ()
  "Reopen current remote file as root using a sudo TRAMP hop."
  (interactive)
  (unless buffer-file-name
    (user-error "Current buffer is not visiting a file"))
  (let ((host (file-remote-p buffer-file-name 'host))
        (localname (file-remote-p buffer-file-name 'localname)))
    (unless (and host localname)
      (user-error "Current file is not remote"))
    (find-alternate-file (my-tramp--remote-file host localname t))))

(defun my-tramp-cleanup-current-connection ()
  "Cleanup current TRAMP connection."
  (interactive)
  (if (file-remote-p default-directory)
      (progn
        (tramp-cleanup-this-connection)
        (message "Cleaned up current TRAMP connection"))
    (message "Current buffer is local; no TRAMP connection to cleanup")))

(defun my-tramp-cleanup-all-connections ()
  "Cleanup all TRAMP connections."
  (interactive)
  (tramp-cleanup-all-connections)
  (message "Cleaned up all TRAMP connections"))

(defun my-tramp-cleanup-all-buffers ()
  "Cleanup all TRAMP buffers."
  (interactive)
  (tramp-cleanup-all-buffers)
  (message "Cleaned up TRAMP buffers"))

(provide 'my-tramp)
;;; my-tramp.el ends here
