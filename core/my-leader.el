;;; my-leader.el --- Personal leader key -*- lexical-binding: t; -*-

;; Provides a unified leader keymap accessible via:
;;   - "fj" chord (ergonomic, requires key-chord)
;;   - C-c u     (fallback, works everywhere including terminal/SSH)
;;
;; All personal bindings go in `my-leader-map'.  Both entry points
;; share the same map, so a binding added once works via either.

;;; Leader map --------------------------------------------------------
(defvar my-leader-map (make-sparse-keymap)
  "Keymap for all personal leader bindings.")

(define-prefix-command 'my-leader-command 'my-leader-map)

;;; Entry points ------------------------------------------------------

;; Conventional prefix — always works, no dependencies.
(global-set-key (kbd "C-c u") 'my-leader-command)

;; Ergonomic chord via key-chord.
(use-package key-chord
  :config
  (setq key-chord-two-keys-delay 0.05)
  (key-chord-define-global "fj" 'my-leader-command)
  (key-chord-mode 1))

;;; Binding helper ----------------------------------------------------
(defun my-leader-define (key command)
  "Bind KEY to COMMAND in the leader map.
KEY is a string accepted by `kbd'."
  (define-key my-leader-map (kbd key) command))

(provide 'my-leader)
;;; my-leader.el ends here
