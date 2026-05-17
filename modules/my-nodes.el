;;; my-nodes.el --- Org-node networked notes -*- lexical-binding: t; -*-

;; Org-node: fast, SQLite-free knowledge management with backlinking.
;; Notes live in `my-notes-directory'.  Backlinks are written as
;; :BACKLINKS: drawers directly into target files on save.

;;; Org-node setup -------------------------------------------------------

(defvar el-job-ng-max-cores)
(defvar org-mem-do-look-everywhere)
(defvar org-mem-watch-dirs)

(defvar my-org-node-startup-idle-delay 5
  "Seconds of idle time before warming the org-node cache.")

(defvar my-org-node--startup-timer nil
  "Idle timer used to start org-node cache modes.")

(defun my-org-node--ensure-org-id-locations ()
  "Load Org ID locations before initializing org-node."
  (require 'org-id)
  (org-id-locations-load))

(defun my-org-node--ignore-empty-tip (&rest _)
  "Suppress org-mem's transient empty-cache startup tip."
  nil)

(defun my-org-node--enable-modes-now ()
  "Start org-node and org-mem in the intended order."
  (setq my-org-node--startup-timer nil)
  (require 'org-mem-updater)
  (advice-add 'org-mem-tip-if-empty :override #'my-org-node--ignore-empty-tip)
  (unwind-protect
      (org-node-cache-mode 1)
    (advice-remove 'org-mem-tip-if-empty #'my-org-node--ignore-empty-tip))
  (org-mem-updater-mode 1)
  (org-node-backlink-mode 1))

(defun my-org-node--enable-modes ()
  "Warm org-node after startup instead of during init."
  (when (timerp my-org-node--startup-timer)
    (cancel-timer my-org-node--startup-timer))
  (setq my-org-node--startup-timer
        (run-with-idle-timer my-org-node-startup-idle-delay
                             nil
                             #'my-org-node--enable-modes-now)))

(use-package org-node
  :after org-id
  :custom
  (org-node-filter-fn #'org-node-filter-no-roam-exclude-p)
  :init
  ;; Keep org-mem focused and gentle: only scan the notes tree, not every
  ;; directory inferred from recentf/agenda/org-id, and avoid saturating CPUs.
  (setq org-mem-watch-dirs (list my-notes-directory)
        org-mem-do-look-everywhere nil
        el-job-ng-max-cores 2)
  (my-org-node--ensure-org-id-locations)
  :config
  (my-org-node--enable-modes)

  ;; Leader bindings under o n (org → nodes).
  (my-leader-define "o n f" #'org-node-find)
  (my-leader-define "o n i" #'org-node-insert-link)
  (my-leader-define "o n g" #'org-node-grep)

  ;; Which-key description for the nodes sub-prefix.
  (with-eval-after-load 'which-key
    (which-key-add-keymap-based-replacements my-leader-map
      "o n" "nodes")))

;;; Link completion via [[ -----------------------------------------------

;; Typing [[ in an org buffer triggers corfu with org-node candidates.
;; Selecting one inserts a full [[id:...][title]] link.  Regular typing
;; is unaffected — dictionary/dabbrev completion works as before.

(defun my-org-node-link-capf ()
  "Complete node titles after `[[' in org buffers.
Designed for `completion-at-point-functions'.  Works with
electric-pair-mode which inserts ]] immediately after [[."
  (when (and (derived-mode-p 'org-mode)
             (not (org-in-src-block-p)))
    (let ((pt (point)))
      (save-excursion
        (when (search-backward "[[" (line-beginning-position) t)
          (let ((start (+ 2 (point))))
            (when (<= start pt)
              (list start pt
                    org-node--title<>affixations
                    :exclusive 'no
                    :exit-function
                    (lambda (text _)
                      (when-let* ((id (gethash text org-mem--title<>id)))
                        (atomic-change-group
                          ;; Find [[ before and ]] after the completed
                          ;; text relative to current point, since the
                          ;; buffer has changed since completion started.
                          (let ((end (point))
                                (beg (save-excursion
                                       (search-backward "[[" nil t))))
                            (when beg
                              ;; Remove trailing ]] if present.
                              (when (looking-at-p "\\]\\]")
                                (setq end (+ end 2)))
                              (delete-region beg end)
                              (goto-char beg)
                              (insert (org-link-make-string
                                       (concat "id:" id) text)))))
                        (run-hooks 'org-node-insert-link-hook)))))))))))

(add-hook 'org-mode-hook
          (lambda ()
            (add-to-list 'completion-at-point-functions
                         #'my-org-node-link-capf nil #'eq)))

;;; Use ALIASES property through compatibility hooks --------------------

;; Keep the vault on the cleaner ALIASES property while preserving the
;; compatibility entry points that org-node/org-mem still name with "roam".

(with-eval-after-load 'org-mem
  (defun org-mem-entry-roam-aliases (entry)
    "Alternative titles for ENTRY, taken from property ALIASES."
    (when-let* ((aliases (org-mem-entry-property "ALIASES" entry)))
      (split-string-and-unquote aliases))))

(with-eval-after-load 'org-node
  (defun org-node-add-alias (alias &optional interactive)
    "Add ALIAS to ALIASES in entry at `org-node-nearest-relevant'."
    (interactive
     (list (read-string "Alias: ") t)
     org-mode)
    (when interactive
      (org-node--add-to-property-keep-space "ALIASES" alias))))

(provide 'my-nodes)
;;; my-nodes.el ends here
