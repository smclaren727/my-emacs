;;; my-tramp.el --- TRAMP helpers for remote workflows -*- lexical-binding: t; -*-

;; TRAMP configuration and remote host helpers.  Optimizes
;; remote performance (disables VC probes, adds Nix paths),
;; and provides interactive commands for SSH/sudo workflows
;; targeted at NixOS hosts.

(require 'seq)
(require 'subr-x)

;;; Core TRAMP behavior -----------------------------------------------
(use-package tramp
  :ensure nil
  :demand t
  :init
  (setq tramp-default-method "ssh"
        tramp-verbose 1
        auto-revert-remote-files nil)
  :config
  ;; Avoid expensive VC probes on remote paths.
  (setq vc-ignore-dir-regexp
        (concat vc-ignore-dir-regexp "\\|" tramp-file-name-regexp))
  ;; Nix often installs tools outside standard remote PATH defaults.
  (dolist (path '("/run/current-system/sw/bin"
                  "/nix/var/nix/profiles/default/bin"))
    (add-to-list 'tramp-remote-path path 'append)))

;;; Nix host shortcuts ------------------------------------------------
(defvar my-tramp-local-host "loxley"
  "SSH alias for the Nix node on the local network.")

(defvar my-tramp-tailscale-host "loxley-ts"
  "SSH alias for the Nix node over Tailscale.")

(defvar my-tramp-default-host my-tramp-local-host
  "Default SSH alias used by TRAMP helper commands.")

(defvar my-tramp-known-hosts
  '("loxley" "loxley-ts" "nixnode" "nixnode-ts")
  "SSH aliases offered by TRAMP helper commands.")

(defvar my-tramp-nixos-config-candidates
  '("/srv/loxley/nixos/flake.nix"
    "/etc/nixos/flake.nix"
    "/etc/nixos/configuration.nix"
    "/etc/nixos/loxley.nix")
  "Candidate paths for the main NixOS configuration file.")

(defvar my-tramp-nixos-directory "/srv/loxley/nixos/"
  "Directory containing NixOS configuration files on remote hosts.")

(defvar my-tramp-nixos-modules-directory "/srv/loxley/nixos/modules/"
  "Directory containing NixOS module files on remote hosts.")

(defun my-tramp--read-host (&optional prompt-host)
  "Return remote host alias, prompting when PROMPT-HOST is non-nil."
  (if prompt-host
      (let ((hosts (cons my-tramp-default-host
                         (seq-remove
                          (lambda (host)
                            (string= host my-tramp-default-host))
                          my-tramp-known-hosts))))
        (completing-read
         (format "TRAMP host (default %s): " my-tramp-default-host)
         hosts nil nil nil nil my-tramp-default-host))
    my-tramp-default-host))

(defun my-tramp--remote-file (host path &optional sudo-p)
  "Return TRAMP file path on HOST for PATH.
When SUDO-P is non-nil, use a sudo hop as root."
  (let ((remote-path (cond
                      ((string-prefix-p "~" path) path)
                      ((string-prefix-p "/" path) path)
                      (t (concat "/" path)))))
    (if sudo-p
        (format "/ssh:%s|sudo:root@%s:%s" host host remote-path)
      (format "/ssh:%s:%s" host remote-path))))

(defun my-tramp--resolve-nixos-config-file (host)
  "Return best-available NixOS config path for HOST.
Falls back to prompting for a path when none of the candidates exist."
  (or (seq-find
       (lambda (path)
         (file-exists-p (my-tramp--remote-file host path)))
       my-tramp-nixos-config-candidates)
      (read-string
       (format "NixOS config path on %s: " host)
       "/etc/nixos/")))

(defun my-tramp-open-nixos-config (&optional prompt-host)
  "Open NixOS config on a remote host.  With prefix, prompt for host."
  (interactive "P")
  (let* ((host (my-tramp--read-host prompt-host))
         (config-path (my-tramp--resolve-nixos-config-file host)))
    (find-file (my-tramp--remote-file host config-path))))

(defun my-tramp-open-nixos-modules (&optional prompt-host)
  "Open remote NixOS modules directory.  With prefix, prompt for host.
Falls back to `my-tramp-nixos-directory' when modules dir is missing."
  (interactive "P")
  (let* ((host (my-tramp--read-host prompt-host))
         (modules-dir (my-tramp--remote-file host my-tramp-nixos-modules-directory))
         (fallback-dir (my-tramp--remote-file host my-tramp-nixos-directory)))
    (if (file-directory-p modules-dir)
        (dired modules-dir)
      (message "Modules dir missing on %s; opening %s" host my-tramp-nixos-directory)
      (dired fallback-dir))))

(defun my-tramp-open-nixos-directory (&optional prompt-host)
  "Open remote `/etc/nixos/` in Dired.  With prefix, prompt for host."
  (interactive "P")
  (let ((host (my-tramp--read-host prompt-host)))
    (dired (my-tramp--remote-file host my-tramp-nixos-directory))))

(defun my-tramp--open-shell-for-host (host)
  "Open an Eshell at HOST's remote home directory."
  (let* ((default-directory (my-tramp--remote-file host "~/"))
         (buffer-name (format "*eshell:%s*" host)))
    (if (get-buffer buffer-name)
        (pop-to-buffer buffer-name)
      (progn
        (eshell t)
        (rename-buffer buffer-name t)))))

(defun my-tramp-open-shell (&optional prompt-host)
  "Open an Eshell on the default remote host.
With prefix, prompt for the host alias."
  (interactive "P")
  (my-tramp--open-shell-for-host (my-tramp--read-host prompt-host)))

(defun my-tramp-open-local-shell ()
  "Open an Eshell on the local-network Nix node alias."
  (interactive)
  (my-tramp--open-shell-for-host my-tramp-local-host))

(defun my-tramp-open-tailscale-shell ()
  "Open an Eshell on the Tailscale Nix node alias."
  (interactive)
  (my-tramp--open-shell-for-host my-tramp-tailscale-host))

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
