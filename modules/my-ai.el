;;; my-ai.el --- AI chat and agent shells -*- lexical-binding: t; -*-

;; Local AI user experience only.  This module configures gptel for API-backed
;; conversations and agent-shell for interactive coding-agent sessions inside
;; Emacs.  Harness routing, policy, workflows, and ledgers stay in
;; Emacs-Harness.

(require 'subr-x)
(require 'auth-source nil t)

;;; Auth helpers ------------------------------------------------------

(defun my-ai--auth-source-secret (host user &optional port)
  "Return the first auth-source secret for HOST, USER, and optional PORT."
  (when (featurep 'auth-source)
    (let* ((search-args (append (list :max 1
                                      :host host
                                      :user user
                                      :require '(:secret))
                               (when (and port (not (string-empty-p port)))
                                 (list :port port))))
           (match (car (apply #'auth-source-search search-args)))
           (secret (plist-get match :secret)))
      (cond
       ((stringp secret) secret)
       ((functionp secret) (funcall secret))
       (t nil)))))

(defun my-ai--env-or-auth-source-secret (env-var host &optional user port)
  "Return a secret from ENV-VAR or auth-source for HOST, USER, and PORT."
  (let ((env-value (getenv env-var)))
    (if (and (stringp env-value) (not (string-empty-p (string-trim env-value))))
        env-value
      (my-ai--auth-source-secret host (or user "apikey") port))))

(defun my-ai--openai-api-key ()
  "Return the OpenAI API key from env or auth-source."
  (my-ai--env-or-auth-source-secret "OPENAI_API_KEY" "api.openai.com"))

(defun my-ai--anthropic-api-key ()
  "Return the Anthropic API key from env or auth-source."
  (my-ai--env-or-auth-source-secret "ANTHROPIC_API_KEY" "api.anthropic.com"))

(defun my-ai--openrouter-api-key ()
  "Return the OpenRouter API key from env or auth-source."
  (my-ai--env-or-auth-source-secret "OPENROUTER_API_KEY" "openrouter.ai"))

;;; gptel -------------------------------------------------------------

(defvar my-ai--gptel-default-backend nil
  "First registered gptel backend to use as the local default.")

(defun my-ai--set-gptel-default-backend (backend)
  "Set BACKEND as the default gptel backend once."
  (unless my-ai--gptel-default-backend
    (setq my-ai--gptel-default-backend backend
          gptel-backend backend)))

(use-package gptel
  :vc (:url "https://github.com/karthink/gptel")
  :commands (gptel gptel-send gptel-menu)
  :init
  (setq gptel-use-curl t)
  :config
  (when-let ((openai-key (my-ai--openai-api-key)))
    (my-ai--set-gptel-default-backend
     (gptel-make-openai "OpenAI"
       :key (lambda () openai-key)
       :stream t)))
  (when-let ((anthropic-key (my-ai--anthropic-api-key)))
    (my-ai--set-gptel-default-backend
     (gptel-make-anthropic "Claude"
       :key (lambda () anthropic-key)
       :stream t)))
  (when-let ((openrouter-key (my-ai--openrouter-api-key)))
    (my-ai--set-gptel-default-backend
     (gptel-make-openai "OpenRouter"
       :host "openrouter.ai"
       :endpoint "/api/v1/chat/completions"
       :key (lambda () openrouter-key)
       :stream t)))
  (when (and (fboundp 'gptel-make-ollama)
             (or (executable-find "ollama")
                 (file-directory-p (expand-file-name "~/.ollama"))))
    (my-ai--set-gptel-default-backend
     (gptel-make-ollama "Ollama"))))

;;; agent-shell -------------------------------------------------------

(use-package agent-shell
  :commands (agent-shell
             agent-shell-anthropic-start-claude-code
             agent-shell-openai-start-codex)
  :config
  (when (fboundp 'agent-shell-openai-make-authentication)
    (setq agent-shell-openai-authentication
          (agent-shell-openai-make-authentication :login t)))
  (when (fboundp 'agent-shell-anthropic-make-authentication)
    (setq agent-shell-anthropic-authentication
          (agent-shell-anthropic-make-authentication :login t))))

;;; Interactive commands ---------------------------------------------

(defun my-ai--agent-command (variable fallback)
  "Return the executable name from VARIABLE or FALLBACK."
  (let ((value (and (boundp variable) (symbol-value variable))))
    (if (and (listp value) (stringp (car value)))
        (car value)
      fallback)))

(defun my-ai-chat ()
  "Open or switch to a gptel chat buffer."
  (interactive)
  (require 'gptel)
  (call-interactively #'gptel))

(defun my-ai-codex ()
  "Start a Codex session in agent-shell."
  (interactive)
  (require 'agent-shell)
  (let ((command (my-ai--agent-command 'agent-shell-openai-codex-acp-command
                                       "codex-acp")))
    (unless (executable-find command)
      (user-error "%s is not installed or not on PATH" command)))
  (call-interactively #'agent-shell-openai-start-codex))

(defun my-ai-claude ()
  "Start a Claude Code session in agent-shell."
  (interactive)
  (require 'agent-shell)
  (let ((command (my-ai--agent-command 'agent-shell-anthropic-claude-acp-command
                                       "claude-agent-acp")))
    (unless (executable-find command)
      (user-error "%s is not installed or not on PATH" command)))
  (call-interactively #'agent-shell-anthropic-start-claude-code))

(provide 'my-ai)
;;; my-ai.el ends here
