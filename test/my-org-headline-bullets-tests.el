;;; my-org-headline-bullets-tests.el --- Tests for my-org-headline-bullets -*- lexical-binding: t; -*-

(require 'ert)
(require 'my-org-headline-bullets)


;;; Glyph selection --------------------------------------------------

(ert-deftest my-org-headline-bullets-test/glyph-returns-first-for-level-1 ()
  (let ((my-org-headline-bullets '("●" "○" "◉")))
    (should (equal (my-org-headline-bullets--glyph 1) "●"))))

(ert-deftest my-org-headline-bullets-test/glyph-returns-nth-for-in-range-level ()
  (let ((my-org-headline-bullets '("●" "○" "◉")))
    (should (equal (my-org-headline-bullets--glyph 2) "○"))
    (should (equal (my-org-headline-bullets--glyph 3) "◉"))))

(ert-deftest my-org-headline-bullets-test/glyph-clamps-deep-levels-to-last ()
  (let ((my-org-headline-bullets '("●" "○" "◉")))
    (should (equal (my-org-headline-bullets--glyph 4) "◉"))
    (should (equal (my-org-headline-bullets--glyph 99) "◉"))))

(ert-deftest my-org-headline-bullets-test/glyph-returns-nil-when-list-is-empty ()
  (let ((my-org-headline-bullets nil))
    (should-not (my-org-headline-bullets--glyph 1))
    (should-not (my-org-headline-bullets--glyph 5))))

(ert-deftest my-org-headline-bullets-test/glyph-works-with-single-element-list ()
  (let ((my-org-headline-bullets '("●")))
    (should (equal (my-org-headline-bullets--glyph 1) "●"))
    (should (equal (my-org-headline-bullets--glyph 7) "●"))))


;;; Matcher regex ----------------------------------------------------

(defmacro my-org-headline-bullets-tests--match-in (contents &rest body)
  "Insert CONTENTS, return point to start, evaluate BODY."
  (declare (indent 1) (debug (form body)))
  `(with-temp-buffer
     (insert ,contents)
     (goto-char (point-min))
     ,@body))

(ert-deftest my-org-headline-bullets-test/matcher-finds-level-1-heading ()
  (my-org-headline-bullets-tests--match-in "* Heading\n"
    (should (my-org-headline-bullets--matcher nil))
    (should (equal (match-string 1) "*"))))

(ert-deftest my-org-headline-bullets-test/matcher-finds-deeper-heading ()
  (my-org-headline-bullets-tests--match-in "*** Deeper\n"
    (should (my-org-headline-bullets--matcher nil))
    (should (equal (match-string 1) "***"))))

(ert-deftest my-org-headline-bullets-test/matcher-matches-empty-heading-at-eol ()
  (my-org-headline-bullets-tests--match-in "*\n"
    (should (my-org-headline-bullets--matcher nil))
    (should (equal (match-string 1) "*"))))

(ert-deftest my-org-headline-bullets-test/matcher-rejects-star-without-trailing-space ()
  (my-org-headline-bullets-tests--match-in "*bold-ish text\n"
    (should-not (my-org-headline-bullets--matcher nil))))

(ert-deftest my-org-headline-bullets-test/matcher-rejects-mid-line-stars ()
  (my-org-headline-bullets-tests--match-in "text ** with stars\n"
    (should-not (my-org-headline-bullets--matcher nil))))

(ert-deftest my-org-headline-bullets-test/matcher-returns-nil-when-no-heading ()
  (my-org-headline-bullets-tests--match-in "just plain text\nmore text\n"
    (should-not (my-org-headline-bullets--matcher nil))))

(ert-deftest my-org-headline-bullets-test/matcher-advances-through-multiple-headings ()
  (my-org-headline-bullets-tests--match-in "* One\n** Two\n*** Three\n"
    (should (my-org-headline-bullets--matcher nil))
    (should (equal (match-string 1) "*"))
    (should (my-org-headline-bullets--matcher nil))
    (should (equal (match-string 1) "**"))
    (should (my-org-headline-bullets--matcher nil))
    (should (equal (match-string 1) "***"))
    (should-not (my-org-headline-bullets--matcher nil))))

(provide 'my-org-headline-bullets-tests)
;;; my-org-headline-bullets-tests.el ends here
