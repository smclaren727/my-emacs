;;; my-contacts.el --- Contact management with EBDB -*- lexical-binding: t; -*-

;; Contact management via EBDB (Emacs Big Brother Database).
;; Stores contacts in var/ebdb, provides vCard export, org
;; linking, and message-mode email completion.  MUA integration
;; (mu4e/notmuch) is stubbed for future mail client adoption.

;;; EBDB core ----------------------------------------------------------
(use-package ebdb
  :custom
  (ebdb-sources (expand-file-name "var/ebdb" user-emacs-directory))
  (ebdb-default-record-class 'ebdb-record-person)
  (ebdb-complete-mail 'capf)
  (ebdb-save-on-exit t)
  (ebdb-auto-revert t))

;;; Interactive commands -----------------------------------------------
(use-package ebdb-com
  :ensure nil
  :after ebdb)

;;; vCard export -------------------------------------------------------
(use-package ebdb-vcard
  :ensure nil
  :after ebdb)

;;; MUA integration base -----------------------------------------------
;; Auto-search existing records when reading mail; auto-create when sending.
(use-package ebdb-mua
  :ensure nil
  :after ebdb
  :custom
  (ebdb-mua-sender-update-p 'create)
  (ebdb-mua-reader-update-p 'existing)
  (ebdb-mua-pop-up t))

;;; message-mode completion --------------------------------------------
;; Hooks register at load time — email completion works in To/Cc/Bcc.
(use-package ebdb-message
  :ensure nil
  :after ebdb)

;;; Org integration ----------------------------------------------------
;; Provides ebdb: link type for linking contacts from Org files.
(use-package ebdb-org
  :ensure nil
  :after (ebdb org))

;; Future: uncomment when adopting a mail client
;; (use-package ebdb-mu4e
;;   :ensure nil
;;   :after (ebdb mu4e))
;; (use-package ebdb-notmuch
;;   :ensure nil
;;   :after (ebdb notmuch))

(provide 'my-contacts)
;;; my-contacts.el ends here
