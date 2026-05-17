;;; my-org-mode.el --- Org-mode knowledge layer -*- lexical-binding: t; -*-

;; Org-mode knowledge layer: capture templates, agenda, refile
;; targets, org-id for stable linking, and minimal headline bullets.
;; All note files live under `my-notes-directory'.
;; Small Org helpers loaded from elisp/.

(require 'cl-lib)
(require 'my-org-headline-bullets)
(require 'my-org-property-drawers)
(require 'my-org-tag-transitions)
(declare-function my-emacs-state-file "my-core" (path))
(defvar my-package-vc-enabled nil
  "Non-nil when `use-package :vc' may install packages on this host.")
(defvar so-long-action)
(defvar so-long-minor-modes)
(defvar so-long-variable-overrides)

;;; Org setup ---------------------------------------------------------
(use-package org
  :ensure nil
  :demand t
  :hook ((org-mode . visual-line-mode)
         (org-mode . my-org-property-drawers-mode)
         (org-mode . my-org-enable-tag-transition-autosave)
         (org-mode . my-org-enable-updated-property-autosave))
  :custom
  ;; Core paths — all derived from my-notes-directory.
  (org-directory my-notes-directory)
  (org-default-notes-file (expand-file-name "00-Capture/inbox.org" my-notes-directory))
  ;; RET on a link opens it instead of inserting a newline.
  (org-return-follows-link t)

  ;; Agenda pulls from all PARA subdirectories.
  (org-agenda-files (list (expand-file-name "00-Capture/" my-notes-directory)
                          (expand-file-name "10-Projects/" my-notes-directory)
                          (expand-file-name "20-Areas/" my-notes-directory)
                          (expand-file-name "30-Interests/" my-notes-directory)))

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
  (org-tags-column 0)

  ;; M-RET on a heading creates a new heading; never splits the current line.
  ;; The default split behavior is surprising and rarely what you want.
  (org-M-RET-may-split-line nil)

  ;; Open links in the same window.
  (org-link-frame-setup '((file . find-file)))

  ;; Indent content under headings visually (no hard tabs).
  (org-startup-indented t)

  ;; Open Org files in overview mode: top-level headings only.
  (org-startup-folded 'overview)

  ;; Add a blank line before new headings, but not before list items.
  (org-blank-before-new-entry '((heading . always)
                                (plain-list-item . nil)))

  ;; Show blank lines between headings when the outline is folded.
  (org-cycle-separator-lines 2)

  ;; Use a visible folded-subtree indicator.
  (org-ellipsis " ▼")

  ;; Hide markup characters (*bold*, /italic/) and show formatted text.
  (org-hide-emphasis-markers t)

  ;; Archive to a single file in 60-Archive/, filed under a heading
  ;; matching the source file name.
  (org-archive-location
   (concat (expand-file-name "60-Archive/archive.org" my-notes-directory)
           "::* From %s"))

  :config
  ;; Ensure the notes directory exists.
  (make-directory my-notes-directory t)

  (defun my-org-refresh-ellipsis ()
    "Apply `org-ellipsis' to Org fold specs in the current buffer."
    (when (and (stringp org-ellipsis)
               (not (string-empty-p org-ellipsis))
               (boundp 'org-fold-core--specs)
               (fboundp 'org-fold-core-set-folding-spec-property))
      (unless buffer-display-table
        (setq buffer-display-table (make-display-table)))
      (set-display-table-slot
       buffer-display-table 4
       (vconcat (mapcar (lambda (c) (make-glyph-code c 'org-ellipsis))
                         org-ellipsis)))
      (dolist (spec '(outline org-fold-outline
                      org-hide-block org-fold-block
                      org-hide-drawer org-fold-drawer))
        (when (assq spec org-fold-core--specs)
          (setq buffer-invisibility-spec
                (cl-remove-if
                 (lambda (entry)
                   (or (eq entry spec)
                       (and (consp entry) (eq (car entry) spec))))
                 buffer-invisibility-spec))
          (org-fold-core-set-folding-spec-property
           spec :ellipsis org-ellipsis t)))))
  (add-hook 'org-mode-hook #'my-org-refresh-ellipsis)

  ;; Offer source tags in Org tag completion without clobbering
  ;; any existing persistent tags.
  (setq org-tag-persistent-alist
        (delete-dups
         (append
          (mapcar (lambda (tag) (list tag))
                  (my-org-transition-source-tags))
          org-tag-persistent-alist)))

  ;; Refile targets: project files up to 2 levels deep, inbox up to 2.
  ;; org-refile-use-outline-path shows the full path (file/heading/subheading)
  ;; so you can distinguish headings with the same name in different files.
  ;; Completing in one step (not nil) is faster with Vertico/Consult.
  (setq org-refile-targets
        `((,(file-expand-wildcards
             (expand-file-name "10-Projects/*.org" my-notes-directory))
           :maxlevel . 2)
          (,(file-expand-wildcards
             (expand-file-name "20-Areas/*.org" my-notes-directory))
           :maxlevel . 3)
          (,(file-expand-wildcards
             (expand-file-name "30-Interests/*.org" my-notes-directory))
           :maxlevel . 2))
        org-refile-use-outline-path 'file
        org-outline-path-complete-in-steps nil
        org-refile-allow-creating-parent-nodes 'confirm)

  ;; Auto-save all org files after refile so the move is persisted immediately.
  (unless (advice-member-p #'org-save-all-org-buffers 'org-refile)
    (advice-add 'org-refile :after #'org-save-all-org-buffers))

  ;; Update a top-level UPDATED property automatically when present.
  ;; This keeps document-level metadata honest without forcing every Org file
  ;; into the same property convention.
  (defun my-org--document-updated-property-heading-position ()
    "Return the first top-level heading with an UPDATED property, or nil."
    (save-excursion
      (goto-char (point-min))
      (catch 'match
        (while (re-search-forward org-heading-regexp nil t)
          (when (and (= (org-outline-level) 1)
                     (org-entry-get (point) "UPDATED"))
            (throw 'match (point))))
        nil)))

  (defun my-org-touch-updated-property-before-save ()
    "Refresh a document-level UPDATED property before saving the current buffer."
    (when (derived-mode-p 'org-mode)
      (when-let ((position (my-org--document-updated-property-heading-position)))
        (save-excursion
          (goto-char position)
          (org-entry-put (point)
                         "UPDATED"
                         (format-time-string "[%Y-%m-%d %a %H:%M]"))))))

  (defun my-org-enable-updated-property-autosave ()
    "Enable automatic UPDATED-property refreshes for the current Org buffer."
    (add-hook 'before-save-hook #'my-org-touch-updated-property-before-save nil t))

  ;; --- Project capture helper ---
  ;; Prompts for a project name, creates a new file in 10-Projects/
  ;; with title and properties, returns the file path for capture.
  (defun my-org-capture-project-file ()
    "Prompt for a project name and return its file in 10-Projects/.
Creates the file with #+TITLE and a :PROPERTIES: drawer if it
doesn't already exist."
    (let* ((name (read-string "Project name: "))
           (slug (downcase (replace-regexp-in-string "[^a-z0-9]+" "-"
                            (downcase name))))
           (slug (replace-regexp-in-string "^-\\|-$" "" slug))
           (file (expand-file-name (concat "10-Projects/" slug ".org")
                                   my-notes-directory)))
      (unless (file-exists-p file)
        (with-temp-file file
          (insert (format "#+TITLE: %s\n" name))
          (insert ":PROPERTIES:\n")
          (insert (format ":CREATED: %s\n"
                          (format-time-string "[%Y-%m-%d %a %H:%M]")))
          (insert (format ":GOAL:    \n"))
          (insert (format ":ID:       %s\n" (org-id-new)))
          (insert ":END:\n\n")))
      file))

  ;; --- Capture templates ---
  ;; C-c u c then press the key in parentheses to select a template.
  ;;
  ;; %?  = cursor position after capture
  ;; %U  = inactive timestamp (doesn't show in agenda)
  ;; %a  = link to where you were when you captured
  ;; %i  = active region (selected text), if any
  (setq org-capture-templates
        `(("t" "Todo" entry
           (file ,(expand-file-name "00-Capture/inbox.org" my-notes-directory))
           "* TODO %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n"
           :empty-lines 1)
          ("n" "Note" entry
           (file ,(expand-file-name "00-Capture/inbox.org" my-notes-directory))
           "* %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n%a\n%i"
           :empty-lines 1)
          ("j" "Journal" entry
           (file+olp+datetree ,(expand-file-name "00-Capture/journal.org" my-notes-directory))
           "* %?\n%U\n"
           :tree-type day
           :empty-lines 1)
          ("p" "Project" entry
           (file my-org-capture-project-file)
           "* NEXT Define first action\n"
           :empty-lines 1))))

;;; Org IDs -----------------------------------------------------------
(use-package org-id
  :ensure nil
  :after org
  :demand t
  :custom
  (org-id-link-to-org-use-id 'create-if-interactive-and-no-custom-id)
  (org-id-locations-file
   (my-emacs-state-file "var/org-id-locations"))
  :config
  (org-id-locations-load)
  (add-hook 'org-capture-prepare-finalize-hook #'org-id-get-create))

;;; Long-line protection ----------------------------------------------
(defun my-org-configure-so-long ()
  "Use gentle long-line mitigation in Org buffers."
  (setq-local so-long-action 'so-long-minor-mode)
  (setq-local so-long-minor-modes
              (cl-remove-duplicates
               (cons 'org-bars-mode so-long-minor-modes)
               :test #'eq))
  (setq-local so-long-variable-overrides
              (assq-delete-all 'buffer-read-only
                                (copy-tree so-long-variable-overrides))))

(use-package so-long
  :ensure nil
  :after org
  :demand t
  :hook (org-mode . my-org-configure-so-long)
  :config
  (add-to-list 'so-long-target-modes 'org-mode)
  (global-so-long-mode 1))

;;; Org export --------------------------------------------------------
;; Keep Org's standard LaTeX -> PDF path for native PDF export, while
;; adding Pandoc-backed exporters for broader format conversion.
(use-package ox-pandoc
  :if (executable-find "pandoc")
  :after ox
  :demand t
  :custom
  (org-pandoc-options '((standalone . t)))
  ;; Keep the common PDF routes deterministic instead of relying on
  ;; Pandoc's per-writer defaults.
  (org-pandoc-options-for-beamer-pdf '((pdf-engine . "pdflatex")))
  (org-pandoc-options-for-latex-pdf '((pdf-engine . "pdflatex")))
  (org-pandoc-options-for-html5-pdf '((pdf-engine . "weasyprint")))
  :config
  (add-to-list 'org-export-backends 'pandoc))

;;; Org appearance ----------------------------------------------------
(add-hook 'org-mode-hook #'my-org-headline-bullets-mode)

;;; Org outline guide bars -------------------------------------------
(if my-package-vc-enabled
    (use-package org-bars
      :vc (:url "https://github.com/tonyaldon/org-bars" :rev :newest)
      :after org
      :demand t
      :init
      ;; Custom headline bullets own stars; org-bars only draws rails.
      (setq org-bars-with-dynamic-stars-p nil
            org-bars-extra-pixels-height 1)
      :hook
      (org-mode . org-bars-mode))
  (when (locate-library "org-bars")
    (use-package org-bars
      :after org
      :demand t
      :init
      (setq org-bars-with-dynamic-stars-p nil
            org-bars-extra-pixels-height 1)
      :hook
      (org-mode . org-bars-mode))))

(provide 'my-org-mode)
;;; my-org-mode.el ends here
