;;; my-ui.el --- Visual configuration -*- lexical-binding: t; -*-

;; Visual layer: theme (sanityinc-tomorrow with auto dark/light
;; switching), font selection, spacious frame padding, mood-line,
;; prose layout, line numbers, smooth scrolling,
;; navigation pulses, and window layout history.
;; No editing or keybinding logic belongs here.

(require 'subr-x)

;;; Theme -------------------------------------------------------------
(use-package color-theme-sanityinc-tomorrow
  :demand t)

(defvar my-ui-theme-dark 'sanityinc-tomorrow-night
  "Theme used when system appearance is dark.")

(defvar my-ui-theme-light 'sanityinc-tomorrow-day
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
                               :inherit 'default)
    (when (fboundp 'my-ui--apply-org-heading-faces)
      (my-ui--apply-org-heading-faces))))

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

;;; Frame shell -------------------------------------------------------

(defvar my-ui-background-alpha 88
  "Background opacity percentage for GUI frames.")

(defvar my-ui-background-blur 30
  "macOS background blur radius for Emacs Plus builds that support it.")

(defun my-ui--apply-soft-frame-shell (frame)
  "Apply rounded, translucent frame parameters to FRAME when supported."
  (when (and (eq system-type 'darwin)
             (display-graphic-p frame))
    (set-frame-parameter frame 'alpha-background my-ui-background-alpha)
    (set-frame-parameter frame 'ns-background-blur my-ui-background-blur)
    (set-frame-parameter frame 'ns-alpha-elements '(ns-alpha-all))))

(my-ui--apply-soft-frame-shell (selected-frame))
(add-hook 'after-make-frame-functions #'my-ui--apply-soft-frame-shell)

;;; Font and spacing --------------------------------------------------
;; Try preferred fonts in order — first one found wins.
;; Works cross-platform: JetBrains Mono and Fira Code are installable
;; anywhere, Menlo is macOS, DejaVu Sans Mono is Linux.
(defvar my-ui-monospace-fonts
  '("JetBrains Mono" "Fira Code" "SF Mono" "Menlo" "DejaVu Sans Mono")
  "Preferred monospace fonts, in fallback order.")

(defvar my-ui-monospace-height 130
  "Default height for monospace faces.")

(defvar my-ui-variable-pitch-fonts
  '("Avenir Next" "SF Pro Text" "Helvetica Neue" "Cantarell" "DejaVu Sans")
  "Preferred variable-pitch fonts, in fallback order.")

(defvar my-ui-variable-pitch-height 140
  "Default height for variable-pitch faces.")

(defun my-ui--first-available-font (fonts &optional frame)
  "Return the first installed font from FONTS for FRAME."
  (catch 'font
    (dolist (font fonts)
      (when (find-font (font-spec :name font) frame)
        (throw 'font font)))))

(defun my-ui--set-font-defaults ()
  "Set face defaults used by future graphical frames."
  (when-let* ((mono (my-ui--first-available-font my-ui-monospace-fonts)))
    (set-face-attribute 'default nil
                        :family mono
                        :height my-ui-monospace-height)
    (set-face-attribute 'fixed-pitch nil
                        :family mono
                        :height my-ui-monospace-height))
  (when-let* ((variable (my-ui--first-available-font my-ui-variable-pitch-fonts)))
    (set-face-attribute 'variable-pitch nil
                        :family variable
                        :height my-ui-variable-pitch-height)))

(defun my-ui--set-font-for-frame (frame)
  "Set mono and variable-pitch fonts on FRAME."
  (when (display-graphic-p frame)
    (when-let* ((mono (my-ui--first-available-font my-ui-monospace-fonts frame)))
      (set-face-attribute 'default frame
                          :family mono
                          :height my-ui-monospace-height)
      (set-face-attribute 'fixed-pitch frame
                          :family mono
                          :height my-ui-monospace-height))
    (when-let* ((variable (my-ui--first-available-font my-ui-variable-pitch-fonts frame)))
      (set-face-attribute 'variable-pitch frame
                          :family variable
                          :height my-ui-variable-pitch-height))))

(defun my-ui--set-fonts-for-existing-frames ()
  "Set fonts on all existing graphical frames."
  (dolist (frame (frame-list))
    (my-ui--set-font-for-frame frame)))

(my-ui--set-font-defaults)
(my-ui--set-fonts-for-existing-frames)
(add-hook 'after-make-frame-functions #'my-ui--set-font-for-frame)

;;; Icons -------------------------------------------------------------

(use-package nerd-icons
  :defer t)

;; Give text a little more air without making code feel too loose.
(setq-default line-spacing 0.08)

;; Reapply face customizations whenever a package that owns themed faces
;; finishes loading.  The set of packages here is the union of those that
;; either inherit `fixed-pitch' (org, markdown-mode) or own minibuffer/UI
;; surfaces that `my-ui--apply-face-customizations' touches.
(dolist (feature '(org markdown-mode vertico marginalia orderless corfu which-key))
  (with-eval-after-load feature
    (my-ui--apply-face-customizations)))

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
(defun my-ui-mood-line-segment-kbd-macro ()
  "Return keyboard macro recording status for `mood-line'."
  (when defining-kbd-macro
    (propertize (string-trim (format-mode-line mode-line-defining-kbd-macro))
                'face 'mood-line-major-mode)))

(use-package mood-line
  :after color-theme-sanityinc-tomorrow
  :demand t
  :custom
  ;; Use mood-line's pretty Unicode glyphs instead of the ASCII fallback.
  (mood-line-glyph-alist mood-line-glyphs-fira-code)
  :config
  ;; Emacs 31/native-comp can trip over mood-line's lazy hook segment stubs
  ;; during major-mode changes; load the hook-backed segments before enabling.
  (require 'mood-line-segment-checker)
  (require 'mood-line-segment-vc)

  (setq mood-line-format
        (mood-line-defformat
         :left
         (((mood-line-segment-modal)                  . " ")
          ((or (mood-line-segment-buffer-status) " ") . " ")
          ((mood-line-segment-buffer-name)            . "  ")
          ((mood-line-segment-anzu)                   . "  ")
          ((mood-line-segment-multiple-cursors)       . "  ")
          ((mood-line-segment-cursor-position)        . " ")
          ((mood-line-segment-region)                 . " ")
          (mood-line-segment-scroll))
         :right
         (((mood-line-segment-vc)              . "  ")
          ((mood-line-segment-major-mode)      . "  ")
          ((mood-line-segment-misc-info)       . "  ")
          ((my-ui-mood-line-segment-kbd-macro) . "  ")
          ((mood-line-segment-checker)         . "  ")
          ((mood-line-segment-process)         . "  "))))
  (mood-line-mode 1)
  (my-ui--apply-face-customizations))

;; Frame title shows buffer name.
(setq frame-title-format '("%b — Emacs"))

;;; Prose layout ------------------------------------------------------

(defvar my-ui-prose-margin-width 3
  "Number of columns to use as side margins in prose buffers.")

(defvar my-ui-org-margin-width 6
  "Number of columns to use as side margins in Org buffers.")

(defvar-local my-ui--buffer-margin-width nil
  "Side margin width for the current buffer.")

(defun my-ui--apply-prose-margins (&rest _)
  "Apply configured side margins to visible windows showing the current buffer."
  (let ((margin-width (or my-ui--buffer-margin-width
                          my-ui-prose-margin-width)))
    (setq-local left-margin-width margin-width
                right-margin-width margin-width)
    (dolist (window (get-buffer-window-list (current-buffer) nil t))
      (set-window-margins window margin-width margin-width))))

(defun my-ui-enable-org-layout ()
  "Use fixed-pitch text and wider margins for Org buffers."
  ;; org-bars draws continuous image rails in Org's virtual indentation.
  ;; Non-nil line spacing creates visible gaps between those per-line images.
  (setq-local line-spacing nil
              my-ui--buffer-margin-width my-ui-org-margin-width)
  (variable-pitch-mode -1)
  (hl-line-mode -1)
  (my-ui--apply-org-heading-faces)
  (my-ui--apply-prose-margins)
  (add-hook 'window-configuration-change-hook
            #'my-ui--apply-prose-margins nil t))

(defun my-ui-enable-prose-layout ()
  "Use comfortable typography and light side margins for prose buffers."
  (setq-local line-spacing 0.18
              my-ui--buffer-margin-width my-ui-prose-margin-width)
  (variable-pitch-mode 1)
  (my-ui--apply-prose-margins)
  (add-hook 'window-configuration-change-hook
            #'my-ui--apply-prose-margins nil t))

(defun my-ui--apply-org-heading-faces ()
  "Keep Org headings bold, fixed-pitch, and calm across theme changes."
  (my-ui--set-face-if-exists 'org-document-title
                             :inherit 'fixed-pitch
                             :weight 'bold
                             :height 1.25)
  (dolist (spec '((org-level-1 . 1.10)
                  (org-level-2 . 1.08)
                  (org-level-3 . 1.06)
                  (org-level-4 . 1.04)
                  (org-level-5 . 1.02)))
    (my-ui--set-face-if-exists (car spec)
                               :inherit 'fixed-pitch
                               :weight 'bold
                               :height (cdr spec)))
  (dolist (face '(org-level-6 org-level-7 org-level-8))
    (my-ui--set-face-if-exists face
                               :inherit 'fixed-pitch
                               :weight 'semibold
                               :height 1.0)))

(add-hook 'org-mode-hook #'my-ui-enable-org-layout)
(add-hook 'markdown-mode-hook #'my-ui-enable-prose-layout)
(add-hook 'gfm-mode-hook #'my-ui-enable-prose-layout)

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

;;; Responsiveness ----------------------------------------------------
;; Keep scrolling and repeated cursor movement responsive by letting redisplay
;; defer nonessential fontification work while input is pending.
(setq redisplay-skip-fontification-on-input t
      jit-lock-defer-time 0.1)

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
