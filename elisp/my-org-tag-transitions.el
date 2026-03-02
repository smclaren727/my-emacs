;;; my-org-tag-transitions.el --- Org tag transition engine -*- lexical-binding: t; -*-

(require 'org)
(require 'seq)
(require 'subr-x)

;;; Transition rules --------------------------------------------------
;; Each rule is:
;;   ((SOURCE-TAG-1 SOURCE-TAG-2 ...) . TARGET-TAG)
;;
;; On apply, when all SOURCE tags are present on a heading:
;; - add TARGET-TAG
;; - remove SOURCE tags
;;
;; Note: Org tags do not parse `-` reliably. This module keeps the rule
;; definitions readable but normalizes tags to Org-safe forms by replacing
;; `-` with `_` before matching or writing.
(defvar my-org-tag-transition-rules
  '((("required-yes" "impact-high") . "core")
    (("required-yes" "impact-low") . "maintenance")
    (("required-no" "impact-high") . "growth")
    (("required-no" "impact-low") . "explore")
    (("priority-yes" "effort-high") . "schedule")
    (("priority-yes" "effort-low") . "batch")
    (("priority-no" "effort-high") . "plan")
    (("priority-no" "effort-low") . "fill"))
  "Rules that convert source tag pairs into target tags.")

(defun my-org-transition-source-tags ()
  "Return unique, Org-safe source tags from `my-org-tag-transition-rules`."
  (delete-dups
   (apply #'append (mapcar #'car (my-org--normalized-transition-rules)))))

(defun my-org--normalize-tag (tag)
  "Convert TAG to an Org-safe tag string."
  (replace-regexp-in-string "-" "_" tag))

(defun my-org--normalize-transition-rule (rule)
  "Return normalized form of RULE."
  (cons (mapcar #'my-org--normalize-tag (car rule))
        (my-org--normalize-tag (cdr rule))))

(defun my-org--normalized-transition-rules ()
  "Return transition rules normalized to Org-safe tags."
  (mapcar #'my-org--normalize-transition-rule my-org-tag-transition-rules))

(defun my-org--matching-transition-rules (tags)
  "Return transition rules that match TAGS."
  (seq-filter
   (lambda (rule)
     (seq-every-p (lambda (source-tag) (member source-tag tags))
                  (car rule)))
   (my-org--normalized-transition-rules)))

(defun my-org-apply-tag-transitions-at-heading (&optional quiet)
  "Apply all matching transition rules to current heading.
Return non-nil when tags changed.  QUIET suppresses status messages."
  (unless (derived-mode-p 'org-mode)
    (user-error "This command only works in org-mode buffers"))
  (org-back-to-heading t)
  (let* ((current-tags (org-get-tags nil t))
         (matching-rules (my-org--matching-transition-rules current-tags)))
    (if (null matching-rules)
        nil
      (let* ((remove-tags
              (delete-dups (apply #'append (mapcar #'car matching-rules))))
             (add-tags (delete-dups (mapcar #'cdr matching-rules)))
             (updated-tags
              (delete-dups
               (append
                add-tags
                (seq-remove (lambda (tag) (member tag remove-tags)) current-tags)))))
        (unless (equal updated-tags current-tags)
          (org-set-tags updated-tags)
          (unless quiet
            (message "Updated tags: +%s -%s"
                     (string-join add-tags ",")
                     (string-join remove-tags ",")))
          t)))))

(defun my-org-apply-tag-transitions-buffer (&optional quiet)
  "Apply tag transition rules across current Org buffer.
QUIET suppresses status messages."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "This command only works in org-mode buffers"))
  (let ((updated-count 0))
    (org-map-entries
     (lambda ()
       (when (my-org-apply-tag-transitions-at-heading t)
         (setq updated-count (1+ updated-count))))
     nil)
    (unless quiet
      (message "Applied tag transitions to %d heading(s)" updated-count))
    updated-count))

(defun my-org-apply-tag-transitions-before-save ()
  "Apply tag transitions before saving the current Org buffer."
  (when (derived-mode-p 'org-mode)
    (my-org-apply-tag-transitions-buffer t)))

(defun my-org-enable-tag-transition-autosave ()
  "Enable automatic tag transitions on save for the current Org buffer."
  (add-hook 'before-save-hook #'my-org-apply-tag-transitions-before-save nil t))

(provide 'my-org-tag-transitions)
;;; my-org-tag-transitions.el ends here
