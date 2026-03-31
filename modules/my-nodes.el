;;; my-nodes.el --- Org-node networked notes -*- lexical-binding: t; -*-

;; Org-node: fast, SQLite-free knowledge management with backlinking.
;; Notes live in `my-notes-directory'.  Backlinks are written as
;; :BACKLINKS: drawers directly into target files on save.

;;; Org-node setup -------------------------------------------------------

(use-package org-node
  :custom
  (org-node-filter-fn #'org-node-filter-no-roam-exclude-p)
  :config
  (org-node-cache-mode)
  (org-node-backlink-mode)
  (org-node-complete-at-point-mode)

  ;; Leader bindings under o n (org → nodes).
  (my-leader-define "o n f" #'org-node-find)
  (my-leader-define "o n i" #'org-node-insert-link)
  (my-leader-define "o n g" #'org-node-grep)

  ;; Which-key description for the nodes sub-prefix.
  (with-eval-after-load 'which-key
    (which-key-add-keymap-based-replacements my-leader-map
      "o n" "nodes")))

(provide 'my-nodes)
;;; my-nodes.el ends here
