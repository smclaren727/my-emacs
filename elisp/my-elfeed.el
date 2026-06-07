;;; my-elfeed.el --- Shared Elfeed helpers -*- lexical-binding: t; -*-

;; Small helpers shared between `my-feeds' and `my-save-link'.  Keeping
;; them here lets both modules call into a single source instead of
;; carrying byte-identical copies that can drift.

(declare-function elfeed-search-selected "elfeed-search" (&optional ignore-region-p))

(defvar elfeed-show-entry)

(defun my-elfeed-entry-at-point ()
  "Return the Elfeed entry at point, or nil.
In `elfeed-show-mode' returns the shown entry.  In `elfeed-search-mode'
returns the single selected entry, or nil if no row is selected.
Returns nil outside an Elfeed buffer."
  (cond
   ((derived-mode-p 'elfeed-show-mode)
    elfeed-show-entry)
   ((derived-mode-p 'elfeed-search-mode)
    (elfeed-search-selected :single))))

(provide 'my-elfeed)
;;; my-elfeed.el ends here
