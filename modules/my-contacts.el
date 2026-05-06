;;; my-contacts.el --- Apple Contacts to Org import -*- lexical-binding: t; -*-

;; Wraps the icloud-to-org-contacts Python script so vCard exports
;; from Apple Contacts (or any CardDAV source, once tier 6 lands)
;; can be imported into the org notes tree without leaving Emacs.
;;
;; The script handles its own state (manifest, archive folder,
;; errors.org) under `my-contacts-output-dir'.  This module is just
;; a thin wrapper that prompts for input, runs the script async via
;; `make-process', and surfaces output in a buffer.

(require 'subr-x)

;;; Variables -----------------------------------------------------------

(defvar my-contacts-command nil
  "Optional executable for icloud-to-org-contacts.
When nil, prefer `icloud-to-org-contacts' from PATH and fall back to
`my-contacts-python' plus `my-contacts-script'.")

(defvar my-contacts-python "python3"
  "Python executable used when the contacts console script is unavailable.")

(defvar my-contacts-script
  (my-emacs-source-file "scripts/icloud-to-org-contacts/vcf-to-org-contacts.py")
  "Path to the icloud-to-org-contacts compatibility wrapper.")

(defvar my-contacts-output-dir
  (expand-file-name "50-Resources/Contacts" my-notes-directory)
  "Directory where contact org files are written.")

(defvar my-contacts-carddav-server-url "https://contacts.icloud.com"
  "CardDAV server URL for contact sync.")

(defvar my-contacts-carddav-auth-machine nil
  "Optional authinfo machine name for CardDAV credentials.")

(defvar my-contacts-carddav-groups nil
  "Optional list of CardDAV group UIDs or exact names to sync.")

(defvar my-contacts-buffer-name "*contacts-import*"
  "Name of the buffer that surfaces import script output.")

;;; Helpers -------------------------------------------------------------

(defun my-contacts--base-command ()
  "Return the base command list for icloud-to-org-contacts."
  (cond
   (my-contacts-command
    (list my-contacts-command))
   ((executable-find "icloud-to-org-contacts")
    (list (executable-find "icloud-to-org-contacts")))
   ((file-exists-p my-contacts-script)
    (list my-contacts-python my-contacts-script))
   (t
    (user-error "Contacts importer not found; install scripts/icloud-to-org-contacts"))))

(defun my-contacts--run (label args)
  "Run contacts importer with LABEL and ARGS."
  (let ((buffer (get-buffer-create my-contacts-buffer-name))
        (command (append (my-contacts--base-command) args)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "%s\n\n$ %s\n\n"
                        label
                        (string-join command " "))))
      (special-mode))
    (display-buffer buffer)
    (make-process
     :name "contacts-import"
     :buffer buffer
     :command command
     :sentinel #'my-contacts--sentinel)))

;;; Commands ------------------------------------------------------------

(defun my-contacts-import-vcf (input)
  "Import vCard data from INPUT into `my-contacts-output-dir'.

INPUT is a path to a .vcf file or a directory of them.  When called
interactively, prompts for the path."
  (interactive
   (list (read-file-name "Import VCF (file or directory): " "~/Downloads/")))
  (unless (file-exists-p input)
    (user-error "Input not found: %s" input))
  (let ((resolved-input (expand-file-name input)))
    (my-contacts--run
     (format "Importing %s\n  -> %s"
             resolved-input my-contacts-output-dir)
     (list "import-vcf"
           resolved-input
           "-o" my-contacts-output-dir))))

(defun my-contacts-sync-carddav (&optional full-refresh)
  "Sync CardDAV contacts into `my-contacts-output-dir'.
With prefix argument FULL-REFRESH, rewrite all contacts."
  (interactive "P")
  (let ((args (list "sync-carddav"
                    "-o" my-contacts-output-dir
                    "--server-url" my-contacts-carddav-server-url)))
    (when full-refresh
      (setq args (append args (list "--full-refresh"))))
    (when my-contacts-carddav-auth-machine
      (setq args (append args (list "--auth-machine"
                                    my-contacts-carddav-auth-machine))))
    (dolist (group my-contacts-carddav-groups)
      (setq args (append args (list "--group" group))))
    (my-contacts--run
     (format "Syncing CardDAV contacts\n  -> %s" my-contacts-output-dir)
     args)))

(defun my-contacts-list-carddav-groups ()
  "List CardDAV contact groups in `my-contacts-buffer-name'."
  (interactive)
  (let ((args (list "list-groups"
                    "--server-url" my-contacts-carddav-server-url)))
    (when my-contacts-carddav-auth-machine
      (setq args (append args (list "--auth-machine"
                                    my-contacts-carddav-auth-machine))))
    (my-contacts--run "Listing CardDAV contact groups" args)))

(defun my-contacts--sentinel (proc event)
  "Process sentinel for contacts importer process.
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
(my-leader-define "m I" #'my-contacts-sync-carddav)
(my-leader-define "m G" #'my-contacts-list-carddav-groups)

(provide 'my-contacts)
;;; my-contacts.el ends here
