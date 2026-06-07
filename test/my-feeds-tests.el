;;; my-feeds-tests.el --- Tests for feed subscription capture -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(add-to-list 'load-path (expand-file-name "elisp" default-directory))
(add-to-list 'load-path (expand-file-name "modules" default-directory))

(defvar my-notes-directory temporary-file-directory)
(defvar my-leader-map nil)

(defmacro use-package (&rest _args)
  "Ignore use-package forms while testing pure feed helpers.")

(defun my-leader-define (&rest _args)
  "Ignore leader bindings while testing pure feed helpers.")

(defun my-org-protocol-register (&rest _args)
  "Ignore org-protocol registration while testing pure feed helpers.")

(defun my-plist-non-empty-string (plist property)
  "Return PROPERTY from PLIST as a trimmed string, or nil."
  (let ((value (plist-get plist property)))
    (when (and (stringp value) (not (string-empty-p (string-trim value))))
      (string-trim value))))

(require 'my-feeds)

(defmacro my-feeds-tests--with-feed-file (contents &rest body)
  "Evaluate BODY with `my-feeds-org-file' bound to a temp file.
When CONTENTS is non-nil, write it into the file before BODY runs."
  (declare (indent 1) (debug (form body)))
  `(let* ((directory (make-temp-file "my-feeds-tests-" t))
          (my-feeds-org-file (expand-file-name "feeds.org" directory)))
     (unwind-protect
         (progn
           (when ,contents
             (with-temp-file my-feeds-org-file
               (insert ,contents)))
           ,@body)
       (when-let* ((buffer (find-buffer-visiting my-feeds-org-file)))
         (kill-buffer buffer))
       (delete-directory directory t))))

(defun my-feeds-tests--file-string ()
  "Return the current temp feed file contents."
  (with-temp-buffer
    (insert-file-contents my-feeds-org-file)
    (buffer-string)))

(defun my-feeds-tests--match-position (regexp string)
  "Return the start position of REGEXP in STRING."
  (and (string-match regexp string)
       (match-beginning 0)))


;;; Feed file structure -------------------------------------------------

(ert-deftest my-feeds-test/ensure-file-creates-root-and-inbox ()
  (my-feeds-tests--with-feed-file nil
    (my-feeds--ensure-file)
    (let ((contents (my-feeds-tests--file-string)))
      (should (string-match-p "^\\* Feeds :elfeed:$" contents))
      (should (string-match-p "^\\*\\* Inbox :inbox:$" contents)))))

(ert-deftest my-feeds-test/add-url-appends-feed-under-inbox ()
  (my-feeds-tests--with-feed-file
      "#+TITLE: RSS Feeds\n#+STARTUP: showall\n\n* Feeds :elfeed:\n"
    (let ((result (my-feeds-add-url "https://example.com/feed.xml"
                                    "Example Feed"
                                    "https://example.com/"
                                    "application/rss+xml")))
      (should-not (plist-get result :duplicate))
      (let ((contents (my-feeds-tests--file-string)))
        (should (string-match-p "^\\*\\* Inbox :inbox:$" contents))
        (should (string-match-p
                 "^\\*\\*\\* \\[\\[https://example.com/feed.xml\\]\\[Example Feed\\]\\]$"
                 contents))
        (should (string-match-p "^:PAGE_URL: https://example.com/$" contents))
        (should (string-match-p "^:FEED_TYPE: application/rss\\+xml$"
                                contents))))))

(ert-deftest my-feeds-test/add-url-skips-duplicate-feed-url ()
  (my-feeds-tests--with-feed-file
      (concat "#+TITLE: RSS Feeds\n\n"
              "* Feeds :elfeed:\n"
              "** Inbox :inbox:\n"
              "*** [[https://example.com/feed.xml][Example Feed]]\n")
    (let ((result (my-feeds-add-url "https://example.com/feed.xml"
                                    "Other Title")))
      (should (plist-get result :duplicate))
      (let ((contents (my-feeds-tests--file-string))
            (count 0)
            (start 0))
        (while (string-match "https://example.com/feed\\.xml" contents start)
          (setq count (1+ count)
                start (match-end 0)))
        (should (= 1 count))))))

(ert-deftest my-feeds-test/add-url-preserves-existing-categories ()
  (my-feeds-tests--with-feed-file
      (concat "#+TITLE: RSS Feeds\n\n"
              "* Feeds :elfeed:\n"
              "** Tech :tech:\n"
              "*** [[https://hnrss.org/frontpage][Hacker News - Front Page]]\n")
    (my-feeds-add-url "https://example.com/rss" "Example")
    (let ((contents (my-feeds-tests--file-string)))
      (should (string-match-p "^\\*\\* Tech :tech:$" contents))
      (should (string-match-p
               "^\\*\\*\\* \\[\\[https://hnrss.org/frontpage\\]\\[Hacker News - Front Page\\]\\]$"
               contents))
      (should (string-match-p "^\\*\\* Inbox :inbox:$" contents))
      (should (string-match-p
               "^\\*\\*\\* \\[\\[https://example.com/rss\\]\\[Example\\]\\]$"
               contents)))))

(ert-deftest my-feeds-test/ensure-file-moves-existing-inbox-to-top ()
  (my-feeds-tests--with-feed-file
      (concat "#+TITLE: RSS Feeds\n\n"
              "* Feeds :elfeed:\n"
              "** Tech :tech:\n"
              "*** [[https://hnrss.org/frontpage][Hacker News - Front Page]]\n"
              "** Inbox :inbox:\n"
              "*** [[https://example.com/rss][Example]]\n")
    (my-feeds--ensure-file)
    (let* ((contents (my-feeds-tests--file-string))
           (inbox-position (my-feeds-tests--match-position
                            "^\\*\\* Inbox :inbox:$"
                            contents))
           (tech-position (my-feeds-tests--match-position
                           "^\\*\\* Tech :tech:$"
                           contents)))
      (should inbox-position)
      (should tech-position)
      (should (< inbox-position tech-position))
      (should (string-match-p
               "^\\*\\*\\* \\[\\[https://example.com/rss\\]\\[Example\\]\\]$"
               contents)))))

(ert-deftest my-feeds-test/capture-org-protocol-saves-without-fetching ()
  (my-feeds-tests--with-feed-file nil
    (let ((updated nil))
      (cl-letf (((symbol-function 'elfeed-update)
                 (lambda ()
                   (setq updated t))))
        (my-feeds-capture-org-protocol
         '(:url "https://example.com/feed.atom"
           :title "Example Atom"
           :page_url "https://example.com/"
           :type "application/atom+xml")))
      (should-not updated)
      (should (string-match-p
               "^\\*\\*\\* \\[\\[https://example.com/feed.atom\\]\\[Example Atom\\]\\]$"
               (my-feeds-tests--file-string))))))

(provide 'my-feeds-tests)
;;; my-feeds-tests.el ends here
