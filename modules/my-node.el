;;; my-node.el --- Shared node profile hooks -*- lexical-binding: t; -*-

;; Shared node-only behavior belongs here rather than in Nix-generated inline
;; elisp.  The host-context shim selects this module on the headless node.

(require 'subr-x)
(defvar telega-app)
(declare-function eh-bootstrap-maybe-enable-runtime "eh-bootstrap" (harness-root))

(defconst my-node-harness-root "/srv/emacs-node/Harness"
  "Filesystem root of the Emacs-Harness checkout on the node.")

(defconst my-node-runtime-dir "/run/emacs-node"
  "Runtime directory for node health and bootstrap markers.")

(defconst my-node-bootstrap-failed-marker
  (expand-file-name "bootstrap-failed" my-node-runtime-dir)
  "Marker file written when Harness bootstrap fails.")

(defconst my-node-openrouter-secret-file "/run/secrets/openrouter_api_key"
  "Secret file containing the OpenRouter API key for the node.")

(defconst my-node-telegram-api-id-secret-file "/run/secrets/telegram_api_id"
  "Secret file containing the Telegram API id for the node.")

(defconst my-node-telegram-api-hash-secret-file "/run/secrets/telegram_api_hash"
  "Secret file containing the Telegram API hash for the node.")

(defun my-node--read-secret (path)
  "Return the trimmed contents of PATH, or nil if it is unavailable."
  (when (file-readable-p path)
    (string-trim
     (with-temp-buffer
       (insert-file-contents path)
       (buffer-string)))))

(defun my-node--apply-secrets ()
  "Read secrets from `/run/secrets' and publish them to Emacs state."
  (let ((openrouter-key (my-node--read-secret my-node-openrouter-secret-file)))
    (when openrouter-key
      (setenv "OPENROUTER_API_KEY" openrouter-key)))
  (let ((api-id (my-node--read-secret my-node-telegram-api-id-secret-file))
        (api-hash (my-node--read-secret my-node-telegram-api-hash-secret-file)))
    (when (and api-id api-hash)
      (setq telega-app (cons (string-to-number api-id) api-hash)))))

(defun my-node-health ()
  "Return :ok when the daemon is responsive."
  :ok)

(defun my-node-reload-secrets ()
  "Re-read secrets from `/run/secrets' and return :ok on success."
  (my-node--apply-secrets)
  :ok)

;; Preserve the operator-facing entry points used by emacs-node-ops.
(defalias 'emacs-node-health #'my-node-health)
(defalias 'emacs-node-reload-secrets #'my-node-reload-secrets)

(defun my-node--clear-bootstrap-marker ()
  "Remove any stale Harness bootstrap-failed marker."
  (when (file-exists-p my-node-bootstrap-failed-marker)
    (ignore-errors
      (delete-file my-node-bootstrap-failed-marker))))

(defun my-node--write-bootstrap-marker (reason detail)
  "Record a Harness bootstrap failure REASON and DETAIL for operators."
  (ignore-errors
    (with-temp-file my-node-bootstrap-failed-marker
      (insert (format "timestamp: %s\n"
                      (format-time-string "%Y-%m-%dT%H:%M:%S%z")))
      (insert (format "reason: %s\n" reason))
      (insert "detail:\n")
      (insert (or detail "(none)")))))

(defun my-node--bootstrap-harness-runtime ()
  "Load the Harness runtime hooks if the repo is present."
  (let* ((harness-root my-node-harness-root)
         (listeners (expand-file-name "Config/listeners.json" harness-root)))
    (cond
     ((not (file-exists-p listeners))
      (message "[emacs-node] Harness config not found at %s; bootstrap skipped."
               listeners)
      (my-node--write-bootstrap-marker
       (format "Harness config missing: %s" listeners) nil))
     (t
      (condition-case err
          (progn
            (dolist (path (list harness-root
                                (expand-file-name "Lisp" harness-root)))
              (when (file-directory-p path)
                (add-to-list 'load-path path)))
            (require 'eh-bootstrap)
            (eh-bootstrap-maybe-enable-runtime harness-root)
            (my-node--clear-bootstrap-marker)
            (message "[emacs-node] Harness runtime bootstrap enabled for %s"
                     harness-root))
        (error
         (let ((reason (error-message-string err)))
           (message "[emacs-node] ERROR: harness bootstrap failed: %s"
                    reason)
           (my-node--write-bootstrap-marker reason (format "%S" err)))))))))

(require 'org)
(require 'plz nil t)
(require 'gptel nil t)
(require 'telega nil t)
(my-node--apply-secrets)
(run-at-time 2 nil #'my-node--bootstrap-harness-runtime)

(provide 'my-node)
;;; my-node.el ends here
