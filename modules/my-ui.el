;;; my-ui.el --- Visual configuration -*- lexical-binding: t; -*-

;;; Theme -------------------------------------------------------------
(use-package color-theme-sanityinc-tomorrow
  :demand t)

(defvar my-ui-theme-dark 'sanityinc-tomorrow-night
  "Theme used when system appearance is dark.")

(defvar my-ui-theme-light 'sanityinc-tomorrow-day
  "Theme used when system appearance is light.")

;;; Auto theme switching ----------------------------------------------
(defun my-ui--current-appearance ()
  "Return `dark' or `light' based on system/frame appearance."
  (cond
   ((and (eq system-type 'darwin)
         (boundp 'ns-system-appearance)
         (memq ns-system-appearance '(dark light)))
    ns-system-appearance)
   ((eq (frame-parameter nil 'background-mode) 'dark)
    'dark)
   (t
    'light)))

(defun my-ui--apply-system-theme (appearance)
  "Load the light or dark theme for APPEARANCE."
  (let ((theme (if (eq appearance 'dark) my-ui-theme-dark my-ui-theme-light)))
    (unless (and (= (length custom-enabled-themes) 1)
                 (eq (car custom-enabled-themes) theme))
      (mapc #'disable-theme custom-enabled-themes)
      (load-theme theme t))))

;; Apply once at startup.
(my-ui--apply-system-theme (my-ui--current-appearance))

;; Use NS appearance hooks on macOS when available.
(when (and (eq system-type 'darwin)
           (boundp 'ns-system-appearance-change-functions))
  (add-hook 'ns-system-appearance-change-functions #'my-ui--apply-system-theme))


;;; Font --------------------------------------------------------------
;; Try preferred fonts in order — first one found wins.
;; Works cross-platform: JetBrains Mono and Fira Code are installable
;; anywhere, Menlo is macOS, DejaVu Sans Mono is Linux.
(defun my-ui--set-font-for-frame (frame)
  "Set monospace font on FRAME, trying preferred options in order."
  (when (display-graphic-p frame)
    (let ((fonts '("JetBrains Mono" "Fira Code" "SF Mono" "Menlo" "DejaVu Sans Mono"))
          (chosen nil))
      (while (and fonts (not chosen))
        (when (find-font (font-spec :name (car fonts)))
          (setq chosen (car fonts)))
        (setq fonts (cdr fonts)))
      (when chosen
        (set-face-attribute 'default frame :family chosen :height 140)))))

(my-ui--set-font-for-frame (selected-frame))
(add-hook 'after-make-frame-functions #'my-ui--set-font-for-frame)


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
