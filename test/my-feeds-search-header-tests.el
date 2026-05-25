;;; my-feeds-search-header-tests.el --- Tests for layout helpers -*- lexical-binding: t; -*-

;; Narrow scope: only the pure layout helpers
;; (date-column width, label centering, search-layout shrink logic).
;; The Powerline rendering, face syncing, and window-hook plumbing
;; are excluded by design — they are visual and would require live
;; faces/windows to test meaningfully.

(require 'ert)

;; The source file declares these as special via `(defvar SYM)` with no
;; value, but that declaration is scoped to its own file's compilation
;; unit.  Re-declare them here so `let' under `lexical-binding: t' uses
;; dynamic binding, which is what the function under test reads.
(defvar elfeed-search-date-format)
(defvar elfeed-goodies/tag-column-width)
(defvar elfeed-goodies/feed-source-column-width)
(defvar elfeed-search-title-min-width)

(require 'my-feeds-search-header)


;;; Date column width -----------------------------------------------

(ert-deftest my-feeds-search-header-test/date-column-width-uses-format-and-extra ()
  (let ((elfeed-search-date-format '("%Y-%m-%d" 10))
        (my-feeds-search-date-extra-width 2))
    (should (= 12 (my-feeds--search-date-column-width)))))

(ert-deftest my-feeds-search-header-test/date-column-width-falls-back-when-format-width-nil ()
  (let ((elfeed-search-date-format '(nil nil))
        (my-feeds-search-date-extra-width 0))
    (should (= 10 (my-feeds--search-date-column-width)))))

(ert-deftest my-feeds-search-header-test/date-column-width-respects-extra-padding ()
  (let ((elfeed-search-date-format '("%Y" 4))
        (my-feeds-search-date-extra-width 5))
    (should (= 9 (my-feeds--search-date-column-width)))))


;;; Header label centering -----------------------------------------

(ert-deftest my-feeds-search-header-test/center-label-even-padding ()
  (should (equal (my-feeds--center-header-label "foo" 9) "   foo   ")))

(ert-deftest my-feeds-search-header-test/center-label-odd-padding-extra-goes-right ()
  (should (equal (my-feeds--center-header-label "foo" 10) "   foo    ")))

(ert-deftest my-feeds-search-header-test/center-label-fits-exactly ()
  (should (equal (my-feeds--center-header-label "foo" 3) "foo")))

(ert-deftest my-feeds-search-header-test/center-label-truncates-when-too-long ()
  (should (equal (my-feeds--center-header-label "foobar" 3) "foo")))

(ert-deftest my-feeds-search-header-test/center-label-empty-string ()
  (should (equal (my-feeds--center-header-label "" 4) "    ")))


;;; Search layout ----------------------------------------------------

(defmacro my-feeds-search-header-tests--with-layout-defaults (&rest body)
  "Bind the defvars `my-feeds--search-layout' reads and run BODY."
  (declare (indent 0) (debug (body)))
  `(let ((elfeed-search-date-format '("%Y-%m-%d" 10))
         (my-feeds-search-date-extra-width 2)
         (elfeed-goodies/tag-column-width 18)
         (elfeed-goodies/feed-source-column-width 20)
         (elfeed-search-title-min-width 16))
     ,@body))

(ert-deftest my-feeds-search-header-test/layout-no-shrink-when-window-wide ()
  ;; window 100: subject = 100 - 12 - 18 - 20 - 3 = 47 (>= min 16), no shrink.
  (my-feeds-search-header-tests--with-layout-defaults
    (should (equal (my-feeds--search-layout 100) '(12 18 47 20)))))

(ert-deftest my-feeds-search-header-test/layout-shrinks-feed-then-tag-when-tight ()
  ;; window 50: subject = -3, shortage = 19; feed shrinks 20→18 (floor),
  ;; tag shrinks 18→12 (floor); remaining subject = 50-12-12-18-3 = 5.
  (my-feeds-search-header-tests--with-layout-defaults
    (should (equal (my-feeds--search-layout 50) '(12 12 5 18)))))

(ert-deftest my-feeds-search-header-test/layout-clamps-subject-to-one-when-very-narrow ()
  ;; window 30: even after both reductions to floors, subject would be
  ;; negative; the final (max 1 ...) clamps it to 1 column.
  (my-feeds-search-header-tests--with-layout-defaults
    (should (equal (my-feeds--search-layout 30) '(12 12 1 18)))))

(ert-deftest my-feeds-search-header-test/layout-only-tag-shrinks-when-feed-already-at-floor ()
  ;; feed already at its floor of 18; only tag has room to give.
  (my-feeds-search-header-tests--with-layout-defaults
    (let ((elfeed-goodies/feed-source-column-width 18))
      (should (equal (my-feeds--search-layout 50) '(12 12 5 18))))))

(ert-deftest my-feeds-search-header-test/layout-feed-reduction-can-meet-shortage-alone ()
  ;; Large feed column means feed reduction alone satisfies shortage;
  ;; tag still gets a small trim because shortage is not yet zero.
  ;; window 65, feed 40: subject = -8, shortage 24; feed 40→18 (Δ22),
  ;; remaining shortage 2 → tag 18→16; subject = 65-12-16-18-3 = 16.
  (my-feeds-search-header-tests--with-layout-defaults
    (let ((elfeed-goodies/feed-source-column-width 40))
      (should (equal (my-feeds--search-layout 65) '(12 16 16 18))))))

(provide 'my-feeds-search-header-tests)
;;; my-feeds-search-header-tests.el ends here
