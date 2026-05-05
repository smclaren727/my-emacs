;;; my-contacts.el --- Apple Contacts to Org import -*- lexical-binding: t; -*-

;; Wraps the icloud-to-org-contacts Python script so vCard exports
;; from Apple Contacts (or any CardDAV source, once tier 6 lands)
;; can be imported into the org notes tree without leaving Emacs.
;;
;; The script handles its own state (manifest, archive folder,
;; errors.org) under `my-contacts-output-dir'.  This module is just
;; a thin wrapper that prompts for input, runs the script async via
;; `make-process', and surfaces output in a buffer.

;;; Variables -----------------------------------------------------------

(defvar my-contacts-script
  (my-emacs-source-file "scripts/icloud-to-org-contacts/vcf-to-org-contacts.py")
  "Path to the icloud-to-org-contacts CLI script.")

(defvar my-contacts-output-dir
  (expand-file-name "50-Resources/Contacts" my-notes-directory)
  "Directory where contact org files are written.")

(defvar my-contacts-buffer-name "*contacts-import*"
  "Name of the buffer that surfaces import script output.")

;;; Commands ------------------------------------------------------------

(defun my-contacts-import-vcf (input)
  "Import vCard data from INPUT into `my-contacts-output-dir'.

INPUT is a path to a .vcf file or a directory of them.  When called
interactively, prompts for the path."
  (interactive
   (list (read-file-name "Import VCF (file or directory): " "~/Downloads/")))
  (unless (file-exists-p my-contacts-script)
    (user-error "Contacts script not found at %s" my-contacts-script))
  (unless (file-exists-p input)
    (user-error "Input not found: %s" input))
  (let* ((buffer (get-buffer-create my-contacts-buffer-name))
         (resolved-input (expand-file-name input)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "Importing %s\n  -> %s\n\n"
                        resolved-input my-contacts-output-dir)))
      (special-mode))
    (display-buffer buffer)
    (make-process
     :name "contacts-import"
     :buffer buffer
     :command (list "python3"
                    my-contacts-script
                    resolved-input
                    "-o" my-contacts-output-dir)
     :sentinel #'my-contacts--sentinel)))

(defun my-contacts--sentinel (proc event)
  "Process sentinel for `my-contacts-import-vcf'.
PROC is the process object; EVENT is the change description."
  (when (memq (process-status proc) '(exit signal))
    (let ((trimmed (string-trim event)))
      (with-current-buffer (process-buffer proc)
        (let ((inhibit-read-only t))
          (goto-char (point-max))
          (insert (format "\n[process %s]\n" trimmed))))
      (message "contacts import: %s" trimmed))))

;;; Leader bindings -----------------------------------------------------

(my-leader-define "m i" #'my-contacts-import-vcf)

(provide 'my-contacts)
;;; my-contacts.el ends here
