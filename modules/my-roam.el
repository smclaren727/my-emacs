;;; my-roam.el --- Org-roam networked notes -*- lexical-binding: t; -*-

;; Org-roam: plain-text knowledge management with backlinking.
;; Notes live in `my-notes-directory'.  The SQLite database enables
;; fast backlink queries and can be accessed externally by tools
;; like Loxley for graph-based information retrieval.

;;; Org-roam setup -----------------------------------------------------

(use-package org-roam
  :custom
  (org-roam-directory my-notes-directory)
  (org-roam-db-location (no-littering-expand-var-file-name "org-roam.db"))
  (org-roam-completion-everywhere t)
  (org-roam-node-display-template
   (concat "${title:*} " (propertize "${tags:20}" 'face 'org-tag)))

  :config
  (org-roam-db-autosync-mode)

  ;; Leader bindings under o r (org → roam).
  (my-leader-define "o r b" #'org-roam-buffer-toggle)
  (my-leader-define "o r c" #'org-roam-capture)
  (my-leader-define "o r f" #'org-roam-node-find)
  (my-leader-define "o r g" #'org-roam-graph)
  (my-leader-define "o r i" #'org-roam-node-insert)

  ;; Which-key description for the roam sub-prefix.
  (with-eval-after-load 'which-key
    (which-key-add-keymap-based-replacements my-leader-map
      "o r" "roam")))

;;; Org-roam dailies ---------------------------------------------------

(use-package org-roam-dailies
  :ensure nil
  :after org-roam
  :custom
  (org-roam-dailies-directory "daily/")
  :config
  (my-leader-define "o r d" #'org-roam-dailies-capture-today))

(provide 'my-roam)
;;; my-roam.el ends here
