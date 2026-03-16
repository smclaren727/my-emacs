;;; my-bookmarks.el --- Org-based bookmark manager -*- lexical-binding: t; -*-

;; Plaintext bookmark management using org-mode.  Bookmarks are stored
;; as org headlines with links in ~/Notes/bookmarks.org, searchable via
;; completing-read (vertico/orderless).  An emacsclient-friendly frame
;; launcher enables system-wide access from Raycast/Alfred/hotkeys.

;;; Variables -----------------------------------------------------------

(defvar my-bookmarks-file
  (expand-file-name "bookmarks.org" my-notes-directory)
  "Org file containing bookmarks.")

;;; Internal helpers ----------------------------------------------------

(defun my-bookmarks--collect ()
  "Return alist of (\"Title — URL\" . URL) from `my-bookmarks-file'."
  (with-temp-buffer
    (insert-file-contents my-bookmarks-file)
    (org-mode)
    (let (bookmarks)
      (org-element-map (org-element-parse-buffer) 'link
        (lambda (link)
          (when (member (org-element-property :type link) '("http" "https"))
            (let* ((url (org-element-property :raw-link link))
                   (contents-begin (org-element-property :contents-begin link))
                   (contents-end (org-element-property :contents-end link))
                   (title (if (and contents-begin contents-end)
                              (buffer-substring-no-properties contents-begin contents-end)
                            url))
                   (display (concat title
                                    (propertize (concat "  " url)
                                                'face 'completions-annotations))))
              (push (cons display url) bookmarks)))))
      (nreverse bookmarks))))

(defun my-bookmarks--read (prompt)
  "Prompt user to select a bookmark and return its URL.
PROMPT is the minibuffer prompt string."
  (let* ((bookmarks (my-bookmarks--collect))
         (selection (completing-read prompt (mapcar #'car bookmarks) nil t))
         (url (cdr (assoc selection bookmarks))))
    (unless url
      (user-error "No bookmark selected"))
    url))

;;; Interactive commands ------------------------------------------------

(defun my-bookmarks-open ()
  "Select a bookmark and open it in the default browser."
  (interactive)
  (browse-url (my-bookmarks--read "Open bookmark: ")))

(defun my-bookmarks-copy-url ()
  "Select a bookmark and copy its URL to the kill ring."
  (interactive)
  (let ((url (my-bookmarks--read "Copy bookmark URL: ")))
    (kill-new url)
    (message "Copied: %s" url)))

(defun my-bookmarks-open-file ()
  "Open the bookmarks org file for editing."
  (interactive)
  (find-file my-bookmarks-file))

(defun my-bookmarks-add ()
  "Capture a new bookmark via org-capture."
  (interactive)
  (org-capture nil "b"))

;;; Frame launcher for emacsclient --------------------------------------

(defun my-bookmarks-open-frame ()
  "Open a bookmark from a dedicated frame.
Intended for use via emacsclient from outside Emacs:
  emacsclient --eval \\='(my-bookmarks-open-frame)\\='
Creates a small frame, runs the bookmark picker, then cleans up."
  (interactive)
  (let ((frame (make-frame '((name . "Bookmarks")
                              (width . 80)
                              (height . 20)
                              (minibuffer . only)))))
    (unwind-protect
        (with-selected-frame frame
          (my-bookmarks-open))
      (delete-frame frame))))

;;; Capture template ----------------------------------------------------

;; Append bookmark capture template to org-capture-templates.
(with-eval-after-load 'org
  (add-to-list 'org-capture-templates
               `("b" "Bookmark" entry
                 (file+headline ,my-bookmarks-file "Inbox")
                 ,(concat "** [[%^{URL}][%^{Title}]]\n"
                          ":PROPERTIES:\n"
                          ":CREATED: %(format-time-string \"[%%Y-%%m-%%d]\")\n"
                          ":TAGS: %^{Tags}\n"
                          ":END:\n")
                 :empty-lines 0)
               t))

;;; Leader bindings -----------------------------------------------------

(my-leader-define "m m" #'my-bookmarks-open)
(my-leader-define "m a" #'my-bookmarks-add)
(my-leader-define "m c" #'my-bookmarks-copy-url)
(my-leader-define "m f" #'my-bookmarks-open-file)

(with-eval-after-load 'which-key
  (which-key-add-keymap-based-replacements my-leader-map
    "m" "bookmarks"))

(provide 'my-bookmarks)
;;; my-bookmarks.el ends here
