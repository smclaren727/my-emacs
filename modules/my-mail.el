;;; my-mail.el --- Mail workflow via mu4e, mbsync, and msmtp -*- lexical-binding: t; -*-

;; Mail setup for a server-synced workflow:
;; - mbsync handles transport
;; - mu/mu4e handle indexing and the UI
;; - msmtp handles sending
;; - Org captures and org-contacts hold durable task/context data
;; - ~/.emacs.d/scripts/bootstrap-mail-config.sh installs tracked local
;;   templates for ~/.mbsyncrc, ~/.msmtprc, and ~/.authinfo.example

(require 'cl-lib)
(require 'subr-x)

(defvar my-mail-root (expand-file-name "~/Mail/")
  "Root Maildir path shared by mu and mbsync.")

(defvar my-mail-accounts-file
  (expand-file-name "etc/mail-accounts.el" user-emacs-directory)
  "Optional untracked account overrides loaded after defaults.")

(defvar my-mail-org-tasks-file
  (expand-file-name "10-Projects/email-tasks.org" my-notes-directory)
  "Org file that stores mail-related tasks.")

(defvar my-mail-org-notes-file
  (expand-file-name "50-Resources/email-notes.org" my-notes-directory)
  "Org file that stores reference notes captured from mail.")

(defvar my-mail-org-contacts-directory
  (expand-file-name "50-Resources/Contacts/" my-notes-directory)
  "Directory containing curated org-contacts entries.")

(defvar my-mail-accounts
  '((:name "gmail"
     :email "smclaren727@gmail.com"
     :full-name "Sean McLaren"
     :maildir "/gmail"
     :inbox "/gmail/INBOX"
     :drafts "/gmail/[Gmail]/Drafts"
     :sent "/gmail/[Gmail]/Sent Mail"
     :trash "/gmail/[Gmail]/Trash"
     :sent-behavior delete)
    (:name "icloud"
     :email "smclaren727@icloud.com"
     :full-name "Sean McLaren"
     :maildir "/icloud"
     :inbox "/icloud/INBOX"
     :drafts "/icloud/Drafts"
     :sent "/icloud/Sent Messages"
     :trash "/icloud/Deleted Messages"
     :sent-behavior sent))
  "Account plist list used to build mu4e contexts.

Each plist should provide at least:
- :name
- :email
- :maildir
- :inbox
- :drafts
- :sent
- :trash

See etc/mail-accounts.example.el for an override example.")

(when (file-readable-p my-mail-accounts-file)
  (load my-mail-accounts-file nil 'nomessage))

(defun my-mail--find-executable (program &rest fallbacks)
  "Return PROGRAM or the first executable fallback path."
  (cl-find-if #'file-executable-p
              (delq nil (cons (executable-find program) fallbacks))))

(defun my-mail--mu4e-directory-from-mu (mu-binary)
  "Return the mu4e site-lisp directory derived from MU-BINARY."
  (when mu-binary
    (let* ((mu-truename (file-truename mu-binary))
           (bin-dir (file-name-directory mu-truename))
           (prefix (file-name-directory (directory-file-name bin-dir))))
      (cl-find-if
       #'file-directory-p
       (list (expand-file-name "share/emacs/site-lisp/mu/mu4e" prefix)
             (expand-file-name "share/emacs/site-lisp/mu4e" prefix))))))

(defun my-mail--candidate-mu4e-directories ()
  "Return likely mu4e load-path candidates."
  (delete-dups
   (delq nil
         (list (my-mail--mu4e-directory-from-mu
                (my-mail--find-executable "mu" "/opt/homebrew/bin/mu"))
               "/opt/homebrew/share/emacs/site-lisp/mu/mu4e"
               "/opt/homebrew/share/emacs/site-lisp/mu4e"
               "/usr/local/share/emacs/site-lisp/mu/mu4e"
               "/usr/local/share/emacs/site-lisp/mu4e"))))

(dolist (dir (my-mail--candidate-mu4e-directories))
  (when (file-directory-p dir)
    (add-to-list 'load-path dir)))

(defun my-mail--sync-command ()
  "Return the shell command used for manual sync/index refreshes."
  (when-let ((mbsync (my-mail--find-executable "mbsync" "/opt/homebrew/bin/mbsync"))
             (mu (my-mail--find-executable "mu" "/opt/homebrew/bin/mu")))
    (format "%s -a && %s index"
            (shell-quote-argument mbsync)
            (shell-quote-argument mu))))

(defun my-mail-sync-now ()
  "Run mbsync and mu index manually."
  (interactive)
  (if-let ((command (my-mail--sync-command)))
      (async-shell-command command "*mail-sync*")
    (user-error "mbsync or mu is not installed yet")))

(defun my-mail--signature-for-account (account)
  "Return a default signature string for ACCOUNT."
  (format "-- \n%s" (or (plist-get account :full-name) user-full-name)))

(defun my-mail--make-context (account)
  "Build one mu4e context from ACCOUNT."
  (let* ((name (plist-get account :name))
         (maildir (plist-get account :maildir))
         (email (plist-get account :email))
         (full-name (or (plist-get account :full-name) user-full-name))
         (drafts (plist-get account :drafts))
         (sent (plist-get account :sent))
         (trash (plist-get account :trash))
         (signature (or (plist-get account :signature)
                        (my-mail--signature-for-account account)))
         (sent-behavior (or (plist-get account :sent-behavior) 'sent)))
    (make-mu4e-context
     :name name
     :match-func
     (lambda (msg)
       (when msg
         (when-let ((message-maildir (mu4e-message-field msg :maildir)))
           (string-prefix-p maildir message-maildir))))
     :vars `((user-mail-address . ,email)
             (user-full-name . ,full-name)
             (mu4e-drafts-folder . ,drafts)
             (mu4e-sent-folder . ,sent)
             (mu4e-trash-folder . ,trash)
             (mu4e-compose-signature . ,signature)
             (mu4e-sent-messages-behavior . ,sent-behavior)))))

(defun my-mail--all-inboxes-query ()
  "Return a bookmark query that spans every configured inbox."
  (mapconcat (lambda (account)
               (format "maildir:%s" (plist-get account :inbox)))
             my-mail-accounts
             " OR "))

(defun my-mail--bookmarks ()
  "Return the bookmark list for mu4e."
  (let ((all-inboxes (my-mail--all-inboxes-query)))
    `((:name "All Inboxes"
       :query ,all-inboxes
       :key ?i)
      (:name "Unread"
       :query "flag:unread AND NOT flag:trashed"
       :key ?u)
      (:name "Today"
       :query "date:today..now"
       :key ?t)
      (:name "Week"
       :query "date:7d..now"
       :key ?w)
      (:name "Flagged"
       :query "flag:flagged"
       :key ?f))))

(defun my-mail--contacts-files ()
  "Return the org-contact files under `my-mail-org-contacts-directory'."
  (if (file-directory-p my-mail-org-contacts-directory)
      (directory-files-recursively my-mail-org-contacts-directory "\\.org\\'")
    nil))

(defun my-mail--ensure-org-file (path contents)
  "Create PATH with CONTENTS when it does not already exist."
  (unless (file-exists-p path)
    (make-directory (file-name-directory path) t)
    (with-temp-file path
      (insert contents))))

(defun my-mail--ensure-org-files ()
  "Create mail capture files the first time this module is loaded."
  (my-mail--ensure-org-file
   my-mail-org-tasks-file
   "#+TITLE: Email Tasks\n\n* Email Tasks\n\n* Reply Needed\n")
  (my-mail--ensure-org-file
   my-mail-org-notes-file
   "#+TITLE: Email Notes\n\n* Notes\n"))

(defun my-mail--mail-capture-entry-p (entry)
  "Return non-nil when ENTRY belongs to the mail capture group."
  (and (consp entry)
       (stringp (car entry))
       (member (car entry) '("m" "me" "mn" "mr"))))

(defun my-mail--install-capture-templates ()
  "Append mail-specific Org capture templates once."
  (my-mail--ensure-org-files)
  (setq org-capture-templates
        (append
         (cl-remove-if #'my-mail--mail-capture-entry-p org-capture-templates)
         `(("m" "Mail")
           ("me" "Email TODO" entry
            (file+headline ,my-mail-org-tasks-file "Email Tasks")
            "* TODO %? :email:\n:PROPERTIES:\n:CREATED: %U\n:END:\nFrom: %:from\nSubject: %:subject\n[[mu4e:msgid:%:message-id][Email Link]]\n%i"
            :empty-lines 1)
           ("mn" "Email Note" entry
            (file+headline ,my-mail-org-notes-file "Notes")
            "* %:subject :email:note:\n:PROPERTIES:\n:CREATED: %U\n:END:\nFrom: %:from\n[[mu4e:msgid:%:message-id][Email Link]]\n\n%i%?"
            :empty-lines 1)
           ("mr" "Email Reply TODO" entry
            (file+headline ,my-mail-org-tasks-file "Reply Needed")
            "* TODO Reply to %:from re: %:subject :email:reply:\nDEADLINE: %^{Deadline}t\n[[mu4e:msgid:%:message-id][Email Link]]\n%?"
            :empty-lines 1)))))

(defun my-mail--warn-about-missing-tools ()
  "Warn once at startup when expected mail tools are unavailable."
  (let ((missing (delq nil
                       (mapcar (lambda (tool)
                                 (when (not (my-mail--find-executable tool
                                                                     (when (string= tool "mbsync")
                                                                       "/opt/homebrew/bin/mbsync")
                                                                     (when (string= tool "mu")
                                                                       "/opt/homebrew/bin/mu")
                                                                     (when (string= tool "msmtp")
                                                                       "/opt/homebrew/bin/msmtp")
                                                                     (when (string= tool "gpg")
                                                                       "/opt/homebrew/bin/gpg")))
                                   tool))
                               '("mbsync" "mu" "msmtp" "gpg")))))
    (when missing
      (display-warning
       'my-mail
       (format "Mail tools not found yet: %s" (string-join missing ", "))
       :warning))))

(add-hook 'emacs-startup-hook #'my-mail--warn-about-missing-tools)

(let ((msmtp (my-mail--find-executable "msmtp" "/opt/homebrew/bin/msmtp")))
  (when msmtp
    (setq sendmail-program msmtp
          message-send-mail-function #'message-send-mail-with-sendmail
          send-mail-function #'message-send-mail-with-sendmail
          message-sendmail-envelope-from 'header
          message-sendmail-extra-arguments '("--read-envelope-from"))))

(with-eval-after-load 'org
  (my-mail--install-capture-templates))

(use-package org-contacts
  :after org
  :custom
  (org-contacts-files (my-mail--contacts-files)))

(when (locate-library "mu4e")
  (use-package mu4e
    :ensure nil
    :commands (mu4e mu4e-update-mail-and-index)
    :defer 20
    :config
    (setq mail-user-agent 'mu4e-user-agent
          mu4e-maildir my-mail-root
          mu4e-change-filenames-when-moving t
          mu4e-compose-format-flowed t
          mu4e-view-show-images t
          mu4e-view-prefer-html nil
          mu4e-completing-read-function #'completing-read
          mu4e-index-update-in-background t
          mu4e-update-interval nil
          mu4e-get-mail-command (my-mail--sync-command)
          mu4e-sent-messages-behavior 'delete
          mu4e-contexts (mapcar #'my-mail--make-context my-mail-accounts)
          mu4e-context-policy 'pick-first
          mu4e-compose-context-policy 'ask-if-none
          mu4e-bookmarks (my-mail--bookmarks))

    (my-leader-define "o e" #'mu4e)
    (my-leader-define "o r" #'my-mail-sync-now))

  (use-package mu4e-org
    :ensure nil
    :after (mu4e org)
    :config
    (require 'mu4e-org)))

(provide 'my-mail)
;;; my-mail.el ends here
