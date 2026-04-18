;;; my-mail.el --- Mail workflow via mu4e, mbsync, and msmtp -*- lexical-binding: t; -*-

;; Mail setup for a server-synced workflow:
;; - mbsync handles transport
;; - mu/mu4e handle indexing and the UI
;; - msmtp handles sending
;; - Org captures and org contact files hold durable task/context data
;; - ~/.emacs.d/scripts/bootstrap-mail-config.sh installs tracked local
;;   templates for ~/.mbsyncrc, ~/.msmtprc, and ~/.authinfo.example

(require 'cl-lib)
(require 'subr-x)

(declare-function mu4e-dashboard "mu4e-dashboard")
(declare-function mu4e-dashboard-expand-bookmarks-in-query "mu4e-dashboard")
(declare-function mu4e-dashboard-update-link "mu4e-dashboard")
(declare-function mu4e-search "mu4e-search")
(declare-function org-element-context "org-element")
(declare-function org-link-set-parameters "ol")
(defvar mu4e-dashboard-file)
(defvar mu4e-dashboard-link-name)
(defvar mu4e-dashboard-mu-program)
(defvar mu4e-dashboard-propagate-keymap)
(defvar mu4e-search-results-limit)

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

(defvar my-mail-contacts-directory
  (expand-file-name "50-Resources/Contacts/" my-notes-directory)
  "Directory containing curated org contact entries.")

(defvar my-mail-dashboard-file
  (expand-file-name "etc/mu4e-dashboard.org" user-emacs-directory)
  "Org dashboard file used by mu4e-dashboard.")

(defvar my-mail-dashboard-sidebar-width 40
  "Width of the left mail dashboard window.")

(defvar my-mail-sync-channels '("gmail")
  "mbsync channels to sync when refreshing mail.
Set to nil to run all configured channels.")

(defvaralias 'my-mail-org-contacts-directory 'my-mail-contacts-directory)

(defvar my-mail-contact-candidates-cache nil
  "Cached contact completion candidates built from org contact files.")

(defvar my-mail-contact-candidates-cache-key nil
  "Cache key for `my-mail-contact-candidates-cache`.")

(defvar my-mail-address-headers '("bcc" "cc" "from" "reply-to" "to")
  "Headers where contact completion should be offered.")

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
    (format "%s && %s index"
            (if my-mail-sync-channels
                (mapconcat
                 (lambda (channel)
                   (format "%s %s"
                           (shell-quote-argument mbsync)
                           (shell-quote-argument channel)))
                 my-mail-sync-channels
                 " && ")
              (format "%s -a" (shell-quote-argument mbsync)))
            (shell-quote-argument mu))))

(defun my-mail-sync-now ()
  "Run mbsync and mu index manually."
  (interactive)
  (if-let ((command (my-mail--sync-command)))
      (async-shell-command command "*mail-sync*")
    (user-error "mbsync or mu is not installed yet")))

(defun my-mail-dashboard-visual-setup ()
  "Use fixed-width, edge-to-edge layout in the mail dashboard."
  (setq-local truncate-lines t
              line-spacing 0.08
              left-margin-width 0
              right-margin-width 0)
  (variable-pitch-mode -1)
  (when (fboundp 'my-ui--apply-prose-margins)
    (remove-hook 'window-configuration-change-hook
                 #'my-ui--apply-prose-margins t))
  (dolist (window (get-buffer-window-list (current-buffer) nil t))
    (set-window-margins window 0 0)))

(defun my-mail-dashboard ()
  "Open the mu4e dashboard with mail configuration loaded."
  (interactive)
  (require 'mu4e)
  (require 'mu4e-dashboard)
  (mu4e-dashboard))

(defun my-mail-dashboard--mail-window ()
  "Return the preferred mu4e window for dashboard link searches."
  (or (cl-find-if (lambda (window)
                    (window-parameter window 'my-mail-dashboard-mail-window))
                  (window-list nil 'no-minibuf))
      (get-buffer-window "*mu4e-headers*" t)))

(defun my-mail-dashboard--search (query &optional limit)
  "Run mu4e QUERY in the dashboard's mail window.
When LIMIT is non-nil, temporarily limit the number of results."
  (require 'mu4e)
  (with-selected-window (or (my-mail-dashboard--mail-window)
                            (selected-window))
    (when-let ((command-window (selected-window)))
      (set-window-parameter command-window
                            'my-mail-dashboard-mail-window t))
    (if limit
        (let ((mu4e-search-results-limit limit))
          (mu4e-search query))
      (mu4e-search query))))

(defun my-mail-dashboard-follow-link (path)
  "Follow a mu4e-dashboard link without replacing the dashboard window."
  (let* ((link (org-element-context))
         (parts (split-string path "|"))
         (query-name (string-trim (nth 0 parts)))
         (query (mu4e-dashboard-expand-bookmarks-in-query query-name))
         (fmt (nth 1 parts))
         (count (nth 2 parts)))
    (cond
     ((and count (> (length count) 0))
      (my-mail-dashboard--search query (string-to-number count)))
     ((and fmt (> (length fmt) 0))
      (mu4e-dashboard-update-link link))
     (t
      (message "%s" query)
      (my-mail-dashboard--search query)))))

(defun my-mail-dashboard-sidebar ()
  "Open the mu4e dashboard beside a live mu4e search window."
  (interactive)
  (require 'mu4e)
  (require 'mu4e-dashboard)
  (delete-other-windows)
  (let* ((dashboard-window (selected-window))
         (mail-window (split-window-right my-mail-dashboard-sidebar-width)))
    (with-selected-window dashboard-window
      (mu4e-dashboard)
      (setq-local window-size-fixed 'width)
      (set-window-parameter dashboard-window
                            'my-mail-dashboard-sidebar-window t))
    (with-selected-window mail-window
      (set-window-parameter mail-window 'my-mail-dashboard-mail-window t)
      (mu4e t)
      (my-mail-dashboard--search (my-mail--all-inboxes-query)))
    (select-window mail-window)))

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

(defun my-mail--contact-files ()
  "Return the org contact files under `my-mail-contacts-directory'."
  (if (file-directory-p my-mail-contacts-directory)
      (directory-files-recursively my-mail-contacts-directory "\\.org\\'")
    nil))

(defun my-mail--contact-file-cache-key ()
  "Return a stable cache key for the current org contact files."
  (mapcar (lambda (file)
            (let ((attributes (file-attributes file 'string)))
              (list file
                    (file-attribute-size attributes)
                    (file-attribute-modification-time attributes))))
          (sort (my-mail--contact-files) #'string<)))

(defun my-mail--parse-contact-file (file)
  "Return completion entries parsed from contact FILE."
  (let ((case-fold-search t)
        title
        emails)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (when (re-search-forward "^#\\+title:[ \t]*\\(.+\\)$" nil t)
        (setq title (string-trim (match-string-no-properties 1))))
      (goto-char (point-min))
      (while (re-search-forward
              "^[ \t]*:EMAIL\\(?:_[[:alnum:]_]+\\)?:[ \t]*\\(.+\\)$"
              nil t)
        (let ((email (string-trim (match-string-no-properties 1))))
          (unless (string-empty-p email)
            (push email emails)))))
    (cl-loop for email in (delete-dups (nreverse emails))
             collect (list :candidate (if (and title (not (string-empty-p title)))
                                          (format "%s <%s>" title email)
                                        email)
                           :name title
                           :email email
                           :file file))))

(defun my-mail--contact-candidates ()
  "Return cached completion entries parsed from org contact files."
  (let ((cache-key (my-mail--contact-file-cache-key)))
    (unless (equal cache-key my-mail-contact-candidates-cache-key)
      (setq my-mail-contact-candidates-cache-key cache-key
            my-mail-contact-candidates-cache
            (cl-delete-duplicates
             (cl-mapcan #'my-mail--parse-contact-file (my-mail--contact-files))
             :test (lambda (left right)
                     (string-equal (plist-get left :candidate)
                                   (plist-get right :candidate))))))
    my-mail-contact-candidates-cache))

(defun my-mail--contact-match-p (input entry)
  "Return non-nil when INPUT matches contact ENTRY."
  (let* ((tokens (split-string (downcase (string-trim input)) "[[:space:]]+" t))
         (fields (delq nil
                       (mapcar (lambda (field)
                                 (when field
                                   (downcase field)))
                               (list (plist-get entry :candidate)
                                     (plist-get entry :name)
                                     (plist-get entry :email))))))
    (or (null tokens)
        (cl-every (lambda (token)
                    (cl-some (lambda (field)
                               (string-match-p (regexp-quote token) field))
                             fields))
                  tokens))))

(defun my-mail--contact-completion-table (string pred action)
  "Completion table for contact candidates matching STRING, PRED, and ACTION."
  (if (eq action 'metadata)
      '(metadata (category . email-address))
    (complete-with-action
     action
     (cl-loop for entry in (my-mail--contact-candidates)
              when (my-mail--contact-match-p string entry)
              collect (plist-get entry :candidate))
     string
     pred)))

(defun my-mail--current-message-header-name ()
  "Return the current message header name, lower-cased."
  (when (and (derived-mode-p 'message-mode)
             (fboundp 'message-point-in-header-p)
             (message-point-in-header-p))
    (save-excursion
      (beginning-of-line)
      (while (and (not (bobp))
                  (looking-at-p "^[ \t]"))
        (forward-line -1)
        (beginning-of-line))
      (when (looking-at "^\\([^: \t\n]+\\):")
        (downcase (match-string-no-properties 1))))))

(defun my-mail--current-message-header-value-start ()
  "Return the start position of the current message header value."
  (when (my-mail--current-message-header-name)
    (save-excursion
      (beginning-of-line)
      (while (and (not (bobp))
                  (looking-at-p "^[ \t]"))
        (forward-line -1)
        (beginning-of-line))
      (when (re-search-forward "^[^: \t\n]+:[ \t]*" (line-end-position) t)
        (point)))))

(defun my-mail--contact-capf-bounds ()
  "Return completion bounds for the current address at point."
  (when-let ((header-name (my-mail--current-message-header-name)))
    (when (member header-name my-mail-address-headers)
      (let ((end (point))
            (value-start (my-mail--current-message-header-value-start)))
        (when value-start
          (save-excursion
            (if (re-search-backward "," value-start t)
                (progn
                  (forward-char 1)
                  (skip-chars-forward " \t\n"))
              (goto-char value-start))
            (cons (point) end)))))))

(defun my-mail-contact-capf ()
  "Complete org contact addresses while composing email."
  (when-let ((bounds (my-mail--contact-capf-bounds)))
    (list (car bounds)
          (cdr bounds)
          #'my-mail--contact-completion-table
          :exclusive 'no)))

(defun my-mail--enable-contact-capf ()
  "Add org contact completion to the current mail composition buffer."
  (add-hook 'completion-at-point-functions #'my-mail-contact-capf nil t))

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
(add-hook 'message-mode-hook #'my-mail--enable-contact-capf)

(let ((msmtp (my-mail--find-executable "msmtp" "/opt/homebrew/bin/msmtp")))
  (when msmtp
    (setq sendmail-program msmtp
          message-send-mail-function #'message-send-mail-with-sendmail
          send-mail-function #'message-send-mail-with-sendmail
          message-sendmail-envelope-from 'header
          message-sendmail-extra-arguments '("--read-envelope-from"))))

(with-eval-after-load 'org
  (my-mail--install-capture-templates))

(when (locate-library "mu4e")
  (use-package mu4e
    :ensure nil
    :commands (mu4e mu4e-update-mail-and-index)
    :defer 20
    :init
    (setq mail-user-agent 'mu4e-user-agent)
    (my-leader-define "o e" nil)
    (my-leader-define "o r" nil)
    (my-leader-define "m e" #'mu4e)
    (my-leader-define "m r" #'my-mail-sync-now)
    (with-eval-after-load 'which-key
      (which-key-add-keymap-based-replacements my-leader-map
        "m" "mail/bookmarks"
        "m e" "mu4e"
        "m r" "sync mail"))
    :config
    (setq mu4e-maildir my-mail-root
          mu4e-change-filenames-when-moving t
          mu4e-compose-format-flowed t
          mu4e-view-show-images t
          mu4e-view-prefer-html nil
          mu4e-completing-read-function #'completing-read
          mu4e-index-update-in-background t
          mu4e-update-interval nil
          mu4e-get-mail-command (my-mail--sync-command)
          mu4e-search-threads t
          mu4e-sent-messages-behavior 'delete
          mu4e-contexts (mapcar #'my-mail--make-context my-mail-accounts)
          mu4e-context-policy 'pick-first
          mu4e-compose-context-policy 'ask-if-none
          mu4e-bookmarks (my-mail--bookmarks)))

  (use-package mu4e-org
    :ensure nil
    :after (mu4e org)
    :config
    (require 'mu4e-org))

  (use-package org-msg
    :after (mu4e org)
    :custom
    (org-msg-options "html-postamble:nil H:5 num:nil ^:{} toc:nil author:nil email:nil \\n:t")
    (org-msg-startup "hidestars indent inlineimages")
    (org-msg-default-alternatives
     '((new . (text html))
       (reply-to-html . (text html))
       (reply-to-text . (text))))
    (org-msg-convert-citation t)
    :config
    (org-msg-mode 1))

  (use-package mu4e-dashboard
    :vc (:url "https://github.com/rougier/mu4e-dashboard")
    :commands (mu4e-dashboard mu4e-dashboard-mode)
    :init
    (setq mu4e-dashboard-file my-mail-dashboard-file
          mu4e-dashboard-mu-program
          (or (my-mail--find-executable "mu" "/opt/homebrew/bin/mu") "mu")
          ;; Keep dashboard-local shortcuts from leaking into mu4e headers.
          mu4e-dashboard-propagate-keymap nil)
    (my-leader-define "o d" nil)
    (my-leader-define "m d" #'my-mail-dashboard-sidebar)
    (my-leader-define "m D" #'my-mail-dashboard)
    (with-eval-after-load 'which-key
      (which-key-add-keymap-based-replacements my-leader-map
        "m" "mail/bookmarks"
        "m d" "mail dashboard"
        "m D" "dashboard only"))
    :config
    (org-link-set-parameters mu4e-dashboard-link-name
                             :follow #'my-mail-dashboard-follow-link)
    :hook
    (mu4e-dashboard-mode . my-mail-dashboard-visual-setup)))

(provide 'my-mail)
;;; my-mail.el ends here
