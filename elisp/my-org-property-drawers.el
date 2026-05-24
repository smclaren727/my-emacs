;;; my-org-property-drawers.el --- Keep Org property drawers folded -*- lexical-binding: t; -*-

;; Org's built-in drawer folding keeps the :PROPERTIES: line visible.
;; This layer hides the whole drawer during normal cycling, while adding
;; one extra local/global cycle state that reveals property drawers on demand.

(require 'org)
(require 'org-cycle)
(require 'org-fold)
(require 'subr-x)

(defvar my-org-property-drawers--cycle-advice-installed nil
  "Non-nil when the property-drawer cycle advices are installed.")

(defun my-org-property-drawers--bounds-at-match ()
  "Return fold bounds for the property drawer matched at point."
  (let ((start (match-beginning 0))
        (end (match-end 0)))
    ;; Include the newline before the drawer so no empty display row remains.
    (cons (if (> start (point-min)) (1- start) start)
          end)))

(defun my-org-property-drawers--map (function &optional beg end)
  "Call FUNCTION with bounds for each property drawer between BEG and END."
  (let ((case-fold-search nil)
        (limit (copy-marker (or end (point-max)))))
    (save-excursion
      (goto-char (or beg (point-min)))
      (while (re-search-forward org-property-drawer-re limit t)
        (let ((bounds (my-org-property-drawers--bounds-at-match)))
          (funcall function (car bounds) (cdr bounds))
          (goto-char (cdr bounds)))))))

;;;###autoload
(defun my-org-hide-property-drawers (&optional beg end)
  "Hide all property drawers between BEG and END.
When BEG and END are nil, hide property drawers in the current buffer."
  (interactive)
  (when (derived-mode-p 'org-mode)
    (my-org-property-drawers--map
     (lambda (start finish)
       (org-fold-region start finish t 'drawer))
     beg end)))

;;;###autoload
(defun my-org-show-property-drawers (&optional beg end)
  "Show all property drawers between BEG and END.
When BEG and END are nil, show property drawers in the current buffer."
  (interactive)
  (when (derived-mode-p 'org-mode)
    (my-org-property-drawers--map
     (lambda (start finish)
       (org-fold-region start finish nil 'drawer))
     beg end)))

(defun my-org-property-drawers--subtree-bounds ()
  "Return bounds for the current subtree, or nil outside a heading."
  (save-excursion
    (when (ignore-errors (org-back-to-heading t) t)
      (cons (point)
            (save-excursion (org-end-of-subtree t t))))))

(defun my-org-property-drawers--after-cycle (state)
  "Re-hide property drawers after Org changes visibility to STATE."
  (when (bound-and-true-p my-org-property-drawers-mode)
    (pcase state
      ('all-with-property-drawers nil)
      ((or 'children 'subtree 'folded)
       (if-let* ((bounds (my-org-property-drawers--subtree-bounds)))
           (my-org-hide-property-drawers (car bounds) (cdr bounds))
         (my-org-hide-property-drawers)))
      (_ (my-org-hide-property-drawers)))))

(defun my-org-property-drawers--show-local-all-state ()
  "Reveal the current subtree, including property drawers."
  (let ((bounds (my-org-property-drawers--subtree-bounds)))
    (when bounds
      (save-excursion
        (goto-char (car bounds))
        (org-fold-show-subtree)
        (my-org-show-property-drawers (car bounds) (cdr bounds)))
      (org-unlogged-message "ALL")
      (setq org-cycle-subtree-status 'all)
      t)))

(defun my-org-property-drawers--cycle-internal-local (original &rest args)
  "Add a local Org cycle state that reveals property drawers.
ORIGINAL and ARGS are the wrapped `org-cycle-internal-local' call."
  (if (and (bound-and-true-p my-org-property-drawers-mode)
           (eq last-command this-command)
           (eq org-cycle-subtree-status 'subtree)
           (save-excursion
             (beginning-of-line)
             (looking-at-p org-outline-regexp)))
      (or (my-org-property-drawers--show-local-all-state)
          (apply original args))
    (apply original args)))

(defun my-org-property-drawers--show-global-all-state ()
  "Reveal the whole buffer, including property drawers."
  (org-fold-show-all '(headings blocks))
  (my-org-show-property-drawers)
  (org-unlogged-message "SHOW ALL + PROPERTIES")
  (setq org-cycle-global-status 'all-with-property-drawers)
  t)

(defun my-org-property-drawers--cycle-internal-global (original &rest args)
  "Add a global Org cycle state that reveals property drawers.
ORIGINAL and ARGS are the wrapped `org-cycle-internal-global' call."
  (if (and (bound-and-true-p my-org-property-drawers-mode)
           (eq last-command this-command)
           (eq org-cycle-global-status 'all))
      (my-org-property-drawers--show-global-all-state)
    (apply original args)))

(defun my-org-property-drawers--ensure-cycle-advice ()
  "Install the Org cycle advices once."
  (unless my-org-property-drawers--cycle-advice-installed
    (advice-add #'org-cycle-internal-local
                :around #'my-org-property-drawers--cycle-internal-local)
    (advice-add #'org-cycle-internal-global
                :around #'my-org-property-drawers--cycle-internal-global)
    (setq my-org-property-drawers--cycle-advice-installed t)))

;;;###autoload
(define-minor-mode my-org-property-drawers-mode
  "Keep Org property drawers hidden during normal visibility cycling."
  :lighter nil
  (if my-org-property-drawers-mode
      (progn
        (my-org-property-drawers--ensure-cycle-advice)
        (add-hook 'org-cycle-hook #'my-org-property-drawers--after-cycle nil t)
        (my-org-hide-property-drawers))
    (remove-hook 'org-cycle-hook #'my-org-property-drawers--after-cycle t)))

(provide 'my-org-property-drawers)
;;; my-org-property-drawers.el ends here
