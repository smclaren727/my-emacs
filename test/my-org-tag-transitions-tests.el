;;; my-org-tag-transitions-tests.el --- Tests for my-org-tag-transitions -*- lexical-binding: t; -*-

(require 'ert)
(require 'org)
(require 'my-org-tag-transitions)

(defmacro my-org-tag-transitions-tests--with-rules (rules &rest body)
  "Evaluate BODY with `my-org-tag-transition-rules' temporarily bound to RULES."
  (declare (indent 1) (debug (form body)))
  `(let ((my-org-tag-transition-rules ,rules))
     ,@body))

(defmacro my-org-tag-transitions-tests--with-org-buffer (contents &rest body)
  "Insert CONTENTS in a temp Org buffer and evaluate BODY with point at start."
  (declare (indent 1) (debug (form body)))
  `(with-temp-buffer
     (let ((org-mode-hook nil))
       (org-mode))
     (insert ,contents)
     (goto-char (point-min))
     ,@body))


;;; Pure helpers ------------------------------------------------------

(ert-deftest my-org-tag-transitions-test/normalize-tag-replaces-hyphens ()
  (should (equal (my-org--normalize-tag "required-yes") "required_yes"))
  (should (equal (my-org--normalize-tag "impact-high") "impact_high")))

(ert-deftest my-org-tag-transitions-test/normalize-tag-leaves-safe-tags-alone ()
  (should (equal (my-org--normalize-tag "core") "core"))
  (should (equal (my-org--normalize-tag "snake_case") "snake_case")))

(ert-deftest my-org-tag-transitions-test/normalize-transition-rule ()
  (should (equal (my-org--normalize-transition-rule
                  '(("required-yes" "impact-high") . "core"))
                 '(("required_yes" "impact_high") . "core"))))

(ert-deftest my-org-tag-transitions-test/normalized-transition-rules-applies-to-all ()
  (my-org-tag-transitions-tests--with-rules
      '((("priority-yes" "effort-high") . "schedule")
        (("priority-no"  "effort-low")  . "fill"))
    (should (equal (my-org--normalized-transition-rules)
                   '((("priority_yes" "effort_high") . "schedule")
                     (("priority_no"  "effort_low")  . "fill"))))))

(ert-deftest my-org-tag-transitions-test/transition-source-tags-deduplicates ()
  (my-org-tag-transitions-tests--with-rules
      '((("required-yes" "impact-high") . "core")
        (("required-yes" "impact-low")  . "maintenance"))
    (should (equal (sort (copy-sequence (my-org-transition-source-tags))
                         #'string<)
                   '("impact_high" "impact_low" "required_yes")))))


;;; Rule matching -----------------------------------------------------

(ert-deftest my-org-tag-transitions-test/matching-rules-finds-rule-when-all-source-tags-present ()
  (my-org-tag-transitions-tests--with-rules
      '((("required-yes" "impact-high") . "core")
        (("required-no"  "impact-low")  . "explore"))
    (should (equal (my-org--matching-transition-rules
                    '("required_yes" "impact_high"))
                   '((("required_yes" "impact_high") . "core"))))))

(ert-deftest my-org-tag-transitions-test/matching-rules-empty-when-no-rule-matches ()
  (my-org-tag-transitions-tests--with-rules
      '((("required-yes" "impact-high") . "core"))
    (should-not (my-org--matching-transition-rules '("unrelated")))))

(ert-deftest my-org-tag-transitions-test/matching-rules-requires-all-source-tags ()
  (my-org-tag-transitions-tests--with-rules
      '((("required-yes" "impact-high") . "core"))
    (should-not (my-org--matching-transition-rules '("required_yes")))))

(ert-deftest my-org-tag-transitions-test/matching-rules-returns-multiple-when-multiple-match ()
  (my-org-tag-transitions-tests--with-rules
      '((("a") . "x")
        (("b") . "y"))
    (should (equal (sort (mapcar #'cdr
                                 (my-org--matching-transition-rules '("a" "b")))
                         #'string<)
                   '("x" "y")))))


;;; Buffer transformations -------------------------------------------

(ert-deftest my-org-tag-transitions-test/apply-at-heading-rewrites-tags ()
  (my-org-tag-transitions-tests--with-rules
      '((("required-yes" "impact-high") . "core"))
    (my-org-tag-transitions-tests--with-org-buffer
        "* Task :required_yes:impact_high:\n"
      (should (my-org-apply-tag-transitions-at-heading t))
      (should (equal (org-get-tags nil t) '("core"))))))

(ert-deftest my-org-tag-transitions-test/apply-at-heading-preserves-unrelated-tags ()
  (my-org-tag-transitions-tests--with-rules
      '((("required-yes" "impact-high") . "core"))
    (my-org-tag-transitions-tests--with-org-buffer
        "* Task :keep:required_yes:impact_high:\n"
      (my-org-apply-tag-transitions-at-heading t)
      (should (equal (sort (copy-sequence (org-get-tags nil t)) #'string<)
                     '("core" "keep"))))))

(ert-deftest my-org-tag-transitions-test/apply-at-heading-returns-nil-without-match ()
  (my-org-tag-transitions-tests--with-rules
      '((("required-yes" "impact-high") . "core"))
    (my-org-tag-transitions-tests--with-org-buffer
        "* Task :unrelated:\n"
      (should-not (my-org-apply-tag-transitions-at-heading t))
      (should (equal (org-get-tags nil t) '("unrelated"))))))

(ert-deftest my-org-tag-transitions-test/apply-at-heading-errors-outside-org ()
  (with-temp-buffer
    (fundamental-mode)
    (should-error (my-org-apply-tag-transitions-at-heading t)
                  :type 'user-error)))

(ert-deftest my-org-tag-transitions-test/apply-buffer-counts-changed-headings ()
  (my-org-tag-transitions-tests--with-rules
      '((("required-yes" "impact-high") . "core"))
    (my-org-tag-transitions-tests--with-org-buffer
        (concat
         "* One :required_yes:impact_high:\n"
         "* Two :unrelated:\n"
         "* Three :required_yes:impact_high:\n")
      (should (= 2 (my-org-apply-tag-transitions-buffer t))))))

(ert-deftest my-org-tag-transitions-test/apply-buffer-errors-outside-org ()
  (with-temp-buffer
    (fundamental-mode)
    (should-error (my-org-apply-tag-transitions-buffer t)
                  :type 'user-error)))


;;; Autosave hook -----------------------------------------------------

(ert-deftest my-org-tag-transitions-test/enable-autosave-adds-local-hook ()
  (with-temp-buffer
    (let ((org-mode-hook nil))
      (org-mode))
    (my-org-enable-tag-transition-autosave)
    (should (memq 'my-org-apply-tag-transitions-before-save before-save-hook))
    (should-not (memq 'my-org-apply-tag-transitions-before-save
                      (default-value 'before-save-hook)))))

(ert-deftest my-org-tag-transitions-test/before-save-is-noop-in-non-org-buffer ()
  (with-temp-buffer
    (fundamental-mode)
    (my-org-apply-tag-transitions-before-save)))

(provide 'my-org-tag-transitions-tests)
;;; my-org-tag-transitions-tests.el ends here
