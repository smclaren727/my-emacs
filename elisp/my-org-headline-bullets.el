;;; my-org-headline-bullets.el --- Minimal Org headline bullets -*- lexical-binding: t; -*-

;; Display-only replacement for the final visible Org headline star.
;; File contents stay as plain Org stars.

(defgroup my-org-headline-bullets nil
  "Minimal headline bullet display for Org."
  :group 'org)

(defcustom my-org-headline-bullets '("●" "○" "◉" "⌾" "⚬")
  "Display glyphs for Org headline levels.
Levels deeper than the list length use the final glyph."
  :type '(repeat string)
  :group 'my-org-headline-bullets)

(defun my-org-headline-bullets--glyph (level)
  "Return the configured bullet glyph for Org headline LEVEL."
  (when my-org-headline-bullets
    (nth (min (1- level) (1- (length my-org-headline-bullets)))
         my-org-headline-bullets)))

(defun my-org-headline-bullets--matcher (limit)
  "Find the next Org headline star run before LIMIT."
  (re-search-forward "^\\(\\*+\\)\\(?:[ \t]\\|$\\)" limit t))

(defun my-org-headline-bullets--compose ()
  "Compose the final visible Org headline star for the current match."
  (let* ((beg (match-beginning 1))
         (end (match-end 1))
         (level (- end beg))
         (glyph (my-org-headline-bullets--glyph level)))
    (when glyph
      (compose-region (1- end) end glyph)))
  nil)

(defvar my-org-headline-bullets--keywords
  '((my-org-headline-bullets--matcher
     (1 (my-org-headline-bullets--compose) append)))
  "Font-lock keywords for `my-org-headline-bullets-mode'.")

(defun my-org-headline-bullets--decompose ()
  "Remove headline bullet composition from the current buffer."
  (save-excursion
    (goto-char (point-min))
    (while (my-org-headline-bullets--matcher nil)
      (decompose-region (1- (match-end 1)) (match-end 1)))))

;;;###autoload
(define-minor-mode my-org-headline-bullets-mode
  "Display minimal level-specific bullets for Org headlines."
  :global nil
  :lighter nil
  (cond
   (my-org-headline-bullets-mode
    (font-lock-add-keywords nil my-org-headline-bullets--keywords 'append)
    (font-lock-flush))
   (t
    (font-lock-remove-keywords nil my-org-headline-bullets--keywords)
    (my-org-headline-bullets--decompose)
    (font-lock-flush))))

(provide 'my-org-headline-bullets)
;;; my-org-headline-bullets.el ends here
