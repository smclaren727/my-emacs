;;; my-ui.el --- Visual configuration -*- lexical-binding: t; -*-

;;; Theme -------------------------------------------------------------
(use-package color-theme-sanityinc-tomorrow
  :demand t)


;;; Auto theme switching ----------------------------------------------
;; Use the built-in NS hook to follow macOS dark/light mode.
;; ns-system-appearance-change-functions fires on every OS toggle.
(defun my-ui--apply-system-theme (appearance)
  "Load tomorrow-night for dark, tomorrow-day for light based on APPEARANCE."
  (pcase appearance
    ('dark  (load-theme 'sanityinc-tomorrow-night t))
    ('light (load-theme 'sanityinc-tomorrow-day t))))

(add-hook 'ns-system-appearance-change-functions #'my-ui--apply-system-theme)

;; Apply once at startup.
(my-ui--apply-system-theme ns-system-appearance)


;;; Font --------------------------------------------------------------
;; Try preferred fonts in order — first one found wins.
;; Works cross-platform: JetBrains Mono and Fira Code are installable
;; anywhere, Menlo is macOS, DejaVu Sans Mono is Linux.
(defun my-ui--set-font ()
  "Set monospace font, trying preferred options in order."
  (when (display-graphic-p)
    (let ((fonts '("JetBrains Mono" "Fira Code" "SF Mono" "Menlo" "DejaVu Sans Mono"))
          (chosen nil))
      (while (and fonts (not chosen))
        (when (find-font (font-spec :name (car fonts)))
          (setq chosen (car fonts)))
        (setq fonts (cdr fonts)))
      (when chosen
        (set-face-attribute 'default nil :family chosen :height 140)))))

(my-ui--set-font)


;;; Modeline ----------------------------------------------------------
;; minions collapses minor modes into a single menu.
(use-package minions
  :custom
  (minions-mode-line-lighter "…")
  (minions-mode-line-delimiters '("" . ""))
  :config
  (minions-mode 1))

;; moody provides tabs and ribbons for the mode line.
(use-package moody
  :config
  (setq x-underline-at-descent-line t)
  (setq-default mode-line-format
                '(" "
                  mode-line-front-space
                  mode-line-client
                  mode-line-frame-identification
                  mode-line-buffer-identification
                  " "
                  mode-line-position
                  (vc-mode vc-mode)
                  " " mode-line-modes
                  mode-line-misc-info
                  mode-line-end-spaces))
  (moody-replace-mode-line-buffer-identification)
  (moody-replace-vc-mode))

;; Show clock in modeline (no load average).
(setq display-time-default-load-average nil)
(setq display-time-24hr-format t)
(display-time-mode 1)

;; Frame title shows buffer name.
(setq frame-title-format '("%b — Emacs"))

;;; Line numbers ------------------------------------------------------
;; Show line numbers in programming buffers only.
(add-hook 'prog-mode-hook #'display-line-numbers-mode)

;;; Visual cleanup ----------------------------------------------------
;; Highlight the current line — helps track the cursor.
(global-hl-line-mode 1)

;; Hide cursor in inactive windows — reduces visual noise.
(setq cursor-in-non-selected-windows nil)

;; Remove the \ continuation indicator from the fringe.
(setq-default fringe-indicator-alist
              (delq (assq 'continuation fringe-indicator-alist)
                    fringe-indicator-alist))

;;; Window layout history ---------------------------------------------
;; Undo/redo window configurations — M-<escape> or M-` to undo.
(use-package winner
  :ensure nil
  :bind (("M-<escape>" . winner-undo)
         ("M-`"        . winner-undo)
         ("M-~"        . winner-redo))
  :config
  (winner-mode 1))

;;; Smooth scrolling --------------------------------------------------
;; ultra-scroll provides pixel-level smooth scrolling.
;; scroll-conservatively and scroll-margin are set here since
;; ultra-scroll owns these settings.
(use-package ultra-scroll
  :custom
  (scroll-conservatively 3)
  (scroll-margin 0)
  :config
  (ultra-scroll-mode 1))

(provide 'my-ui)
;;; my-ui.el ends here
