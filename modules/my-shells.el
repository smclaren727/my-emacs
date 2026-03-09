;;; my-shells.el --- Shell configuration -*- lexical-binding: t; -*-

;; Project-aware shell management.  Opens named shell buffers
;; rooted in the current project directory, reuses existing
;; buffers, and preserves shell history across sessions.

;;; Core settings -----------------------------------------------------
;; Configure comint (the engine behind M-x shell) for comfortable use.
(use-package shell
  :ensure nil
  :hook (shell-mode . my-shell--setup)
  :custom
  (shell-file-name (or (executable-find "zsh")
                       (executable-find "bash")
                       "/bin/sh"))
  :config
  (defun my-shell--setup ()
    "Common setup for every shell buffer."
    (setq-local comint-buffer-maximum-size 10000
                comint-process-echoes t
                comint-input-ring-size 2000
                comint-input-ring-file-name (or (getenv "HISTFILE")
                                                (expand-file-name "~/.zsh_history")))
    (comint-read-input-ring 'silent)
    (add-hook 'comint-output-filter-functions
              #'comint-truncate-buffer nil t)
    (ansi-color-for-comint-mode-on)))

;;; Shell commands ----------------------------------------------------

(defun my-shell-here ()
  "Open a shell for the current project or directory.
Uses the project name as the buffer name when inside a project."
  (interactive)
  (let* ((proj (project-current))
         (dir (if proj (project-root proj) default-directory))
         (name (if proj
                   (file-name-nondirectory (directory-file-name dir))
                 (abbreviate-file-name dir)))
         (buf-name (format "*shell:%s*" name)))
    (if (get-buffer buf-name)
        (pop-to-buffer buf-name)
      (let ((default-directory dir))
        (shell buf-name)))))

(defun my-shell-named (name)
  "Open or switch to a named shell buffer.
Useful for maintaining multiple shells (build, logs, remote)."
  (interactive "sShell name: ")
  (let ((buf-name (format "*shell:%s*" name)))
    (if (get-buffer buf-name)
        (pop-to-buffer buf-name)
      (shell buf-name))))

(defun my-shell-switch ()
  "Switch between open shell buffers."
  (interactive)
  (let ((shells (seq-filter (lambda (buf)
                              (with-current-buffer buf
                                (derived-mode-p 'shell-mode)))
                            (buffer-list))))
    (if (null shells)
        (message "No shell buffers open.  Use C-c u s s to create one.")
      (pop-to-buffer
       (completing-read "Shell: " (mapcar #'buffer-name shells) nil t)))))

(defun my-shell-clear ()
  "Clear the shell buffer, leaving the prompt intact."
  (interactive)
  (let ((inhibit-read-only t))
    (erase-buffer)
    (comint-send-input)))

(defun my-shell-kill ()
  "Kill the current shell buffer and its process."
  (interactive)
  (when-let ((proc (get-buffer-process (current-buffer))))
    (delete-process proc))
  (kill-buffer (current-buffer)))

(provide 'my-shells)
;;; my-shells.el ends here
