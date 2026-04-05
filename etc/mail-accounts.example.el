;;; mail-accounts.example.el --- Example account overrides -*- lexical-binding: t; -*-

;; Copy this file to etc/mail-accounts.el and adjust it to match the
;; providers and maildir names you actually use.  `my-mail.el' loads
;; that untracked file automatically when it exists.

(setq my-mail-accounts
      '((:name "gmail"
         :email "your-personal@example.com"
         :full-name "Your Name"
         :maildir "/gmail"
         :inbox "/gmail/INBOX"
         :drafts "/gmail/[Gmail]/Drafts"
         :sent "/gmail/[Gmail]/Sent Mail"
         :trash "/gmail/[Gmail]/Trash"
         :sent-behavior delete)
        (:name "work"
         :email "your-work@example.com"
         :full-name "Your Name"
         :maildir "/work"
         :inbox "/work/INBOX"
         :drafts "/work/Drafts"
         :sent "/work/Sent Items"
         :trash "/work/Deleted Items"
         :sent-behavior sent)))
