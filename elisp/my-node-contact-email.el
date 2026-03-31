;;; my-node-contact-email.el --- Org-node contact email completion -*- lexical-binding: t; -*-

;;; Provides vertico-powered contact name completion that inserts the
;;; email address.  Iterates the org-node cache for entries tagged
;;; "contact" and reads the :EMAIL: property from the drawer.

(require 'org-node)

(defun my-node-contact-email ()
  "Complete a contact name and insert their email address.
Queries org-node for entries tagged `contact' and reads the EMAIL
property from matching nodes."
  (interactive)
  (let* ((contacts
          (cl-loop for entry in (org-mem-all-id-nodes)
                   when (member "contact" (org-mem-entry-tags entry))
                   collect (cons (org-mem-entry-title-maybe entry)
                                 (cdr (assoc "EMAIL"
                                             (org-mem-entry-properties-local entry))))))
         (names (mapcar #'car contacts))
         (chosen (completing-read "Contact: " names nil t))
         (email (cdr (assoc chosen contacts))))
    (if email
        (insert email)
      (message "No EMAIL property found for %s" chosen))))

(provide 'my-node-contact-email)
;;; my-node-contact-email.el ends here
