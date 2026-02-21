;;; my-org-mode.el --- Org-mode knowledge layer -*- lexical-binding: t; -*-

;;; Notes root --------------------------------------------------------
;; Single variable for all note paths.  Nothing else should hardcode
;; paths to notes — always derive from this.
(defvar my-notes-directory "~/Notes/"
  "Root directory for all notes and org files.")

;;; Org setup ---------------------------------------------------------
(use-package org
  :ensure nil
  :hook (org-mode . visual-line-mode)
  :bind
  (("C-c u c" . org-capture)
   ("C-c u a" . org-agenda)
   ("C-c u l" . org-store-link))
  :custom
  ;; Core paths — all derived from my-notes-directory.
  (org-directory my-notes-directory)
  (org-default-notes-file (expand-file-name "inbox.org" my-notes-directory))
  ;; RET on a link opens it instead of inserting a newline.
  (org-return-follows-link t)

  ;; Agenda pulls from these files.
  (org-agenda-files (list my-notes-directory))

  ;; TODO workflow.
  ;; PROJECT = non-actionable container heading (never "do" a project, do its tasks).
  ;; NEXT    = the one task in a project you'll do next.
  ;; TODO    = on the list but not yet the next action.
  ;; WAITING = blocked on something external; w@ prompts for a reason on entry.
  ;; The | separates active states from terminal states.
  (org-todo-keywords
   '((sequence "TODO(t)" "NEXT(n)" "WAITING(w@/!)" "|" "DONE(d@/!)" "CANCELLED(c@)")
     (sequence "PROJECT(p)" "|" "DONE(d@/!)" "CANCELLED(c@)")))

  ;; Log timestamps when tasks are completed.
  (org-log-done 'time)

  ;; Store state-change notes (e.g. WAITING reason) in a :LOGBOOK: drawer,
  ;; not inline in the heading body.  Keeps the outline readable.
  (org-log-into-drawer t)

  ;; Can't mark a parent DONE while it has incomplete TODO children.
  (org-enforce-todo-dependencies t)

  ;; Can't mark a TODO DONE while it has unchecked checkboxes.
  (org-enforce-todo-checkbox-dependencies t)

  ;; Properties set on a parent (e.g. CATEGORY) inherit down to children
  ;; in the agenda.  Useful once you start tagging projects.
  (org-use-property-inheritance t)

  ;; Tags sit flush against heading text rather than right-justified.
  ;; Easier to read, especially with org-modern.
  (org-tags-column 0)

  ;; M-RET on a heading creates a new heading; never splits the current line.
  ;; The default split behavior is surprising and rarely what you want.
  (org-M-RET-may-split-line nil)

  ;; Open links in the same window.
  (org-link-frame-setup '((file . find-file)))

  ;; Indent content under headings visually (no hard tabs).
  (org-startup-indented t)

  ;; Hide markup characters (*bold*, /italic/) and show formatted text.
  (org-hide-emphasis-markers t)

  :config
  ;; Ensure the notes directory exists.
  (make-directory my-notes-directory t)

  ;; Refile targets: projects file up to 3 levels deep, inbox up to 2.
  ;; org-refile-use-outline-path shows the full path (file/heading/subheading)
  ;; so you can distinguish headings with the same name in different files.
  ;; Completing in one step (not nil) is faster with Vertico/Consult.
  (setq org-refile-targets
        `((,(expand-file-name "projects.org" my-notes-directory) :maxlevel . 3)
          (,(expand-file-name "inbox.org" my-notes-directory)    :maxlevel . 2))
        org-refile-use-outline-path 'file
        org-outline-path-complete-in-steps nil)

  ;; --- Capture templates ---
  ;; C-c u c then press the key in parentheses to select a template.
  ;;
  ;; %?  = cursor position after capture
  ;; %U  = inactive timestamp (doesn't show in agenda)
  ;; %a  = link to where you were when you captured
  ;; %i  = active region (selected text), if any
  (setq org-capture-templates
        `(("t" "Todo" entry
           (file ,(expand-file-name "inbox.org" my-notes-directory))
           "* TODO %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n"
           :empty-lines 1)
          ("n" "Note" entry
           (file ,(expand-file-name "inbox.org" my-notes-directory))
           "* %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n%a\n%i"
           :empty-lines 1)
          ("j" "Journal" entry
           (file+olp+datetree ,(expand-file-name "journal.org" my-notes-directory))
           "* %?\n%U\n"
           :tree-type day
           :empty-lines 1)
          ("p" "Project" entry
           (file ,(expand-file-name "projects.org" my-notes-directory))
           "* PROJECT %^{Project name}\n:PROPERTIES:\n:CREATED: %U\n:GOAL:    %?\n:END:\n\n** NEXT Define first action\n"
           :empty-lines 1))))

;;; Org IDs -----------------------------------------------------------
(use-package org-id
  :ensure nil
  :after org
  :custom
  (org-id-link-to-org-use-id 'create-if-interactive-and-no-custom-id)
  (org-id-locations-file
   (expand-file-name "var/org-id-locations" user-emacs-directory))
  :config
  (add-hook 'org-capture-prepare-finalize-hook #'org-id-get-create))

;;; Org appearance ----------------------------------------------------
(use-package org-modern
  :hook ((org-mode . org-modern-mode)
         (org-agenda-finalize . org-modern-agenda))
  :custom
  (org-modern-star '("◉" "○" "◈" "◇" "▸")))

(provide 'my-org-mode)
;;; my-org-mode.el ends here
