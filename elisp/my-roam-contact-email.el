;;; my-roam-contact-email.el --- Org-roam contact email completion -*- lexical-binding: t; -*-

;;; Provides vertico-powered contact name completion that inserts the
;;; email address.  Queries the org-roam DB for nodes tagged "contact"
;;; and reads the :EMAIL: property from the drawer.

(require 'org-roam)

(defun my-roam-contact-email ()
  "Complete a contact name and insert their email address.
Queries org-roam for nodes tagged `contact' and reads the EMAIL
property from matching nodes."
  (interactive)
  (let* ((contacts (org-roam-db-query
                    [:select [title properties]
                     :from nodes
                     :inner-join tags :on (= tags:node-id nodes:id)
                     :where (= tags:tag "contact")]))
         (names (mapcar #'car contacts))
         (chosen (completing-read "Contact: " names nil t))
         (props (cadr (assoc chosen contacts)))
         (email (cdr (assoc "EMAIL" props))))
    (if email
        (insert email)
      (message "No EMAIL property found for %s" chosen))))

(provide 'my-roam-contact-email)
;;; my-roam-contact-email.el ends here
