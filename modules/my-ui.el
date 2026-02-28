;;; my-ui.el --- Visual configuration -*- lexical-binding: t; -*-

;;; Theme -------------------------------------------------------------
;; ef-themes by Prot — high-quality, accessible, matched dark/light pairs.
(use-package ef-themes
  :demand t
  :config
  (setq ef-themes-to-toggle '(ef-night ef-day)))


;;; Auto theme switching ----------------------------------------------
;; Use the built-in NS hook to follow macOS dark/light mode.
;; ns-system-appearance-change-functions fires on every OS toggle.
(defun my-ui--apply-system-theme (appearance)
  "Load ef-night for dark, ef-day for light based on APPEARANCE."
  (pcase appearance
    ('dark  (load-theme 'ef-night t))
    ('light (load-theme 'ef-day t))))

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
;; doom-modeline — polished, informative, icon support.
;; Requires nerd-icons for file/mode icons in the modeline.
(use-package nerd-icons
  :demand t)

(use-package doom-modeline
  :demand t
  :custom
  (doom-modeline-height 30)
  (doom-modeline-bar-width 4)
  (doom-modeline-buffer-encoding nil)  ; hide UTF-8 — it's always UTF-8
  :config
  (doom-modeline-mode 1))

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
