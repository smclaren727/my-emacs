;;; my-ui.el --- Visual configuration -*- lexical-binding: t; -*-

;; Visual layer: theme (ef-themes with auto dark/light
;; switching), font selection, spacious frame padding, modeline
;; (moody + minions), prose layout, line numbers, smooth scrolling,
;; navigation pulses, and window layout history.
;; No editing or keybinding logic belongs here.

(require 'subr-x)

;;; Theme -------------------------------------------------------------
(use-package ef-themes
  :demand t)

(defvar my-ui-theme-dark 'ef-dark
  "Theme used when system appearance is dark.")

(defvar my-ui-theme-light 'ef-light
  "Theme used when system appearance is light.")

(defun my-ui--face-color (face attribute)
  "Return FACE ATTRIBUTE when it is a concrete color, or nil."
  (when (facep face)
    (let ((color (face-attribute face attribute nil 'default)))
      (unless (or (memq color '(nil unspecified))
                  (and (stringp color)
                       (string-prefix-p "unspecified" color)))
        color))))

(defun my-ui--set-face-if-exists (face &rest attributes)
  "Apply ATTRIBUTES to FACE when FACE is defined."
  (when (facep face)
    (apply #'set-face-attribute face nil attributes)))

(defun my-ui--apply-face-customizations ()
  "Apply face tweaks that should survive theme changes."
  (let ((accent (or (my-ui--face-color 'font-lock-keyword-face :foreground)
                    (my-ui--face-color 'link :foreground)))
        (muted (my-ui--face-color 'shadow :foreground)))
    (dolist (face '(org-block org-code org-date org-drawer org-formula
                    org-meta-line org-property-value org-special-keyword
                    org-table org-tag org-verbatim org-checkbox))
      (my-ui--set-face-if-exists face :inherit 'fixed-pitch))
    (dolist (face '(markdown-code-face markdown-inline-code-face
                    markdown-pre-face markdown-table-face))
      (my-ui--set-face-if-exists face :inherit 'fixed-pitch))

    ;; Keep minibuffer and completion surfaces visually quiet, but intentional.
    (when accent
      (my-ui--set-face-if-exists 'minibuffer-prompt
                                 :foreground accent
                                 :weight 'semibold)
      (my-ui--set-face-if-exists 'orderless-match-face-0
                                 :foreground accent
                                 :weight 'semibold)
      (my-ui--set-face-if-exists 'which-key-key-face
                                 :foreground accent
                                 :weight 'semibold)
      (my-ui--set-face-if-exists 'which-key-special-key-face
                                 :foreground accent
                                 :weight 'semibold)
      (my-ui--set-face-if-exists 'which-key-group-description-face
                                 :foreground accent
                                 :weight 'semibold))
    (when muted
      (dolist (face '(completions-annotations marginalia-documentation
                      marginalia-date marginalia-size marginalia-type
                      which-key-note-face which-key-separator-face
                      corfu-annotations))
        (my-ui--set-face-if-exists face :foreground muted))
      (my-ui--set-face-if-exists 'marginalia-documentation
                                 :foreground muted
                                 :slant 'italic))
    (my-ui--set-face-if-exists 'vertico-current :inherit 'highlight :extend t)
    (my-ui--set-face-if-exists 'corfu-current :inherit 'highlight)
    (my-ui--set-face-if-exists 'which-key-command-description-face
                               :inherit 'default)
    (my-ui--set-face-if-exists 'which-key-local-map-description-face
                               :inherit 'default)))

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
      (load-theme theme t))
    (my-ui--apply-face-customizations)))

;; Apply once at startup.
(my-ui--apply-system-theme (my-ui--current-appearance))

;; Use NS appearance hooks on macOS when available.
(when (and (eq system-type 'darwin)
           (boundp 'ns-system-appearance-change-functions))
  (add-hook 'ns-system-appearance-change-functions #'my-ui--apply-system-theme))


;;; Font and spacing --------------------------------------------------
;; Try preferred fonts in order — first one found wins.
;; Works cross-platform: JetBrains Mono and Fira Code are installable
;; anywhere, Menlo is macOS, DejaVu Sans Mono is Linux.
(defvar my-ui-monospace-fonts
  '("JetBrains Mono" "Fira Code" "SF Mono" "Menlo" "DejaVu Sans Mono")
  "Preferred monospace fonts, in fallback order.")

(defvar my-ui-variable-pitch-fonts
  '("Avenir Next" "SF Pro Text" "Helvetica Neue" "Cantarell" "DejaVu Sans")
  "Preferred variable-pitch fonts, in fallback order.")

(defun my-ui--first-available-font (fonts)
  "Return the first installed font from FONTS."
  (catch 'font
    (dolist (font fonts)
      (when (find-font (font-spec :name font))
        (throw 'font font)))))

(defun my-ui--set-font-for-frame (frame)
  "Set mono and variable-pitch fonts on FRAME."
  (when (display-graphic-p frame)
    (when-let ((mono (my-ui--first-available-font my-ui-monospace-fonts)))
      (set-face-attribute 'default frame :family mono :height 140)
      (set-face-attribute 'fixed-pitch frame :family mono :height 140))
    (when-let ((variable (my-ui--first-available-font my-ui-variable-pitch-fonts)))
      (set-face-attribute 'variable-pitch frame :family variable :height 150))))

(my-ui--set-font-for-frame (selected-frame))
(add-hook 'after-make-frame-functions #'my-ui--set-font-for-frame)

;; Give text a little more air without making code feel too loose.
(setq-default line-spacing 0.08)
(with-eval-after-load 'org
  (my-ui--apply-face-customizations))
(with-eval-after-load 'markdown-mode
  (my-ui--apply-face-customizations))
(with-eval-after-load 'vertico
  (my-ui--apply-face-customizations))
(with-eval-after-load 'marginalia
  (my-ui--apply-face-customizations))
(with-eval-after-load 'orderless
  (my-ui--apply-face-customizations))
(with-eval-after-load 'corfu
  (my-ui--apply-face-customizations))
(with-eval-after-load 'which-key
  (my-ui--apply-face-customizations))

;;; Frame spacing -----------------------------------------------------

(use-package spacious-padding
  :demand t
  :custom
  (spacious-padding-widths
   '(:internal-border-width 12
     :header-line-width 4
     :mode-line-width 2
     :custom-button-width 3
     :tab-width 4
     :right-divider-width 18
     :scroll-bar-width 8
     :fringe-width 10))
  :config
  (spacious-padding-mode 1)
  (my-ui--apply-face-customizations))

;;; Modeline ----------------------------------------------------------
;; minions collapses minor modes into a single menu.
(use-package minions
  :custom
  (minions-mode-line-lighter "…")
  (minions-mode-line-delimiters '("" . ""))
  :config
  (minions-mode 1))

;; Moody's documented replacements provide the tab/ribbon modeline style.
(use-package moody
  :demand t
  :config
  (setq x-underline-at-descent-line t)
  (moody-replace-mode-line-front-space)
  (moody-replace-mode-line-buffer-identification)
  (moody-replace-vc-mode)
  (my-ui--apply-face-customizations))

;; Show clock in modeline (no load average).
(setq display-time-default-load-average nil)
(setq display-time-24hr-format t)
(display-time-mode 1)

;; Frame title shows buffer name.
(setq frame-title-format '("%b — Emacs"))

;;; Prose layout ------------------------------------------------------

(defun my-ui-enable-prose-layout ()
  "Use comfortable typography and width for prose buffers."
  (setq-local line-spacing 0.18)
  (variable-pitch-mode 1)
  (when (fboundp 'olivetti-mode)
    (olivetti-mode 1)))

(use-package olivetti
  :commands olivetti-mode
  :hook ((org-mode markdown-mode gfm-mode) . my-ui-enable-prose-layout)
  :custom
  (olivetti-body-width 0.72)
  (olivetti-minimum-body-width 82)
  (olivetti-recall-visual-line-mode-entry-state t)
  (olivetti-lighter nil))

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

;;; Navigation feedback -----------------------------------------------

(use-package pulsar
  :custom
  (pulsar-delay 0.045)
  (pulsar-iterations 8)
  (pulsar-face 'pulsar-cyan)
  :config
  (pulsar-global-mode 1)
  (with-eval-after-load 'consult
    (add-hook 'consult-after-jump-hook #'pulsar-recenter-top)
    (add-hook 'consult-after-jump-hook #'pulsar-reveal-entry)))

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
