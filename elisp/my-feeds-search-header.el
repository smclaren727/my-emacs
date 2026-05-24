;;; my-feeds-search-header.el --- Powerline header rendering for Elfeed -*- lexical-binding: t; -*-

;; Custom Date / Tags / Subject / Feed Source header for the Elfeed
;; search and show buffers, drawn with Powerline separators and synced
;; to the active theme.  Lives here rather than in `my-feeds' to keep
;; that module focused on the Elfeed engine, capture pipeline, and
;; interactive commands.
;;
;; Consumed by `my-feeds' via `(require 'my-feeds-search-header)' and
;; wired into elfeed-goodies through `elfeed-search-header-function'
;; and `elfeed-search-print-entry-function'.

(require 'cl-lib)
(require 'subr-x)

(declare-function elfeed-entry-date "elfeed-db" (entry))
(declare-function elfeed-entry-feed "elfeed-db" (entry))
(declare-function elfeed-entry-tags "elfeed-db" (entry))
(declare-function elfeed-entry-title "elfeed-db" (entry))
(declare-function elfeed-feed-title "elfeed-db" (feed))
(declare-function elfeed-format-column "elfeed-lib" (string width &optional align))
(declare-function elfeed-meta "elfeed-db" (entry prop &optional default))
(declare-function elfeed-search--faces "elfeed-search" (tags))
(declare-function elfeed-search-format-date "elfeed-search" (date))
(declare-function elfeed-search-update--force "elfeed-search")
(declare-function face-remap-add-relative "face-remap" (face &rest specs))
(declare-function face-remap-remove-relative "face-remap" (cookie))
(declare-function powerline-raw "powerline" (str &optional face pad))
(declare-function powerline-render "powerline" (values))

(defvar elfeed-goodies/feed-source-column-width)
(defvar elfeed-goodies/powerline-default-separator)
(defvar elfeed-goodies/tag-column-width)
(defvar elfeed-search-date-format)
(defvar elfeed-search-title-min-width)
(defvar elfeed-show-entry)
(defvar powerline-default-separator-dir)
(defvar powerline-utf-8-separator-left)
(defvar powerline-utf-8-separator-right)

;;; Faces -------------------------------------------------------------

(defface my-feeds-search-header-active1
  '((t (:inherit powerline-active1)))
  "Light Powerline face for the Elfeed search header."
  :group 'faces)

(defface my-feeds-search-header-active2
  '((t (:inherit powerline-active2)))
  "Dark Powerline face for the Elfeed search header."
  :group 'faces)

;;; User-facing tuning -------------------------------------------------

(defvar my-feeds-search-font-scale 1.08
  "Relative font scale used in the Elfeed search buffer.")

(defvar my-feeds-search-line-spacing 0.36
  "Buffer-local line spacing used in the Elfeed search buffer.")

(defvar my-feeds-search-date-extra-width 2
  "Extra padding after dates in the Elfeed search buffer.")

;;; Buffer-local state ------------------------------------------------

(defvar-local my-feeds-search--font-remap-cookie nil
  "Face-remap cookie for Elfeed search font scaling.")

(defvar-local my-feeds-search--header-remap-cookies nil
  "Face-remap cookies for the Elfeed search header tail.")

(defvar-local my-feeds-search--last-window-width nil
  "Last rendered window width for the current Elfeed search buffer.")

(defvar-local my-feeds-search--resize-timer nil
  "Debounce timer for Elfeed search redraws after window resizing.")

(defvar-local my-feeds-show--font-remap-cookie nil
  "Face-remap cookie for Elfeed show font scaling.")

(defvar-local my-feeds-show--header-remap-cookies nil
  "Face-remap cookies for the Elfeed show header tail.")

;;; Layout helpers ----------------------------------------------------

(defun my-feeds--search-date-column-width ()
  "Return the configured Elfeed search date column width."
  (+ (or (cadr elfeed-search-date-format) 10)
     my-feeds-search-date-extra-width))

(defun my-feeds--center-header-label (label width)
  "Return LABEL centered in a header column WIDTH characters wide."
  (let* ((label (truncate-string-to-width label width))
         (padding (max 0 (- width (string-width label))))
         (left-padding (/ padding 2))
         (right-padding (- padding left-padding)))
    (concat (make-string left-padding ?\s)
            label
            (make-string right-padding ?\s))))

(defun my-feeds--search-window-width ()
  "Return the visible width of the Elfeed search window."
  (if-let* ((window (get-buffer-window (current-buffer) t)))
      (window-body-width window)
    (window-body-width)))

(defun my-feeds--header-window-width ()
  "Return the width available to Powerline headers.

Leaving one cell for the right fringe keeps Emacs from drawing a
truncation marker over the end of the header."
  (max 1 (1- (my-feeds--search-window-width))))

(defun my-feeds--search-layout (&optional window-width)
  "Return Elfeed search column widths as (DATE TAG SUBJECT FEED).

When WINDOW-WIDTH is non-nil, size the layout to that width instead of
the current window body width."
  (let* ((date-width (my-feeds--search-date-column-width))
         (tag-width elfeed-goodies/tag-column-width)
         (feed-width elfeed-goodies/feed-source-column-width)
         (window-width (or window-width (my-feeds--search-window-width)))
         (gap-width 3)
         (subject-min-width (max (string-width "Subject")
                                 elfeed-search-title-min-width))
         (subject-width
          (- window-width date-width tag-width feed-width gap-width)))
    (when (< subject-width subject-min-width)
      (let ((shortage (- subject-min-width subject-width)))
        (let ((feed-reduction (min shortage (max 0 (- feed-width 18)))))
          (setq feed-width (- feed-width feed-reduction)
                shortage (- shortage feed-reduction)))
        (let ((tag-reduction (min shortage (max 0 (- tag-width 12)))))
          (setq tag-width (- tag-width tag-reduction)))))
    (list date-width
          tag-width
          (max 1 (- window-width date-width tag-width feed-width gap-width))
          feed-width)))

;;; Face / box helpers ------------------------------------------------

(defun my-feeds--header-box-width (&optional face)
  "Return the box width used by FACE (default `header-line')."
  (let ((box (face-attribute (or face 'header-line) :box nil 'default)))
    (or (and (listp box) (plist-get box :line-width))
        0)))

(defun my-feeds--default-face-color (attribute fallback)
  "Return the default face ATTRIBUTE, or FALLBACK when unspecified."
  (let ((value (face-attribute 'default attribute nil t)))
    (if (eq value 'unspecified)
        fallback
      value)))

(defun my-feeds--remap-header-line-tail (cookies)
  "Replace COOKIES with remaps that hide unused header-line cells.
Remaps both `header-line' and `header-line-inactive' so the trailing
fringe region stays invisible regardless of window selection.  Both
faces share `header-line's box width so the row keeps the same height
when focus switches between Elfeed panes.  COOKIES is the previous
list (or nil); returns the replacement list."
  (dolist (cookie (if (listp cookies) cookies (list cookies)))
    (when cookie
      (face-remap-remove-relative cookie)))
  (let* ((background (my-feeds--default-face-color
                      :background (or (frame-parameter nil 'background-color)
                                      "white")))
         (foreground (my-feeds--default-face-color
                      :foreground (or (frame-parameter nil 'foreground-color)
                                      "black")))
         (box-width (my-feeds--header-box-width 'header-line))
         (spec (list :background background
                     :foreground foreground
                     :box `(:line-width ,box-width
                            :color ,background :style nil))))
    (list
     (apply #'face-remap-add-relative 'header-line spec)
     (apply #'face-remap-add-relative 'header-line-inactive spec))))

(defun my-feeds--header-trailing-pad (&optional face)
  "Return a stretch space that fills the header to the right-fringe edge.
When FACE is non-nil, use its background; otherwise fall back to the
buffer background.  The Elfeed buffers zero out the right fringe so
the pad reaches the actual window edge, letting the last Powerline
segment's color extend to where the mode line ends."
  (let* ((bg (or (and face (face-background face nil t))
                 (my-feeds--default-face-color
                  :background (or (frame-parameter nil 'background-color)
                                  "white"))))
         (box-width (my-feeds--header-box-width 'header-line)))
    (propertize " "
                'display '(space :align-to right-fringe)
                'face `(:background ,bg
                        :box (:line-width ,box-width
                              :color ,bg
                              :style nil)))))

(defun my-feeds--sync-powerline-header-face (target source)
  "Make TARGET match SOURCE colors with full `header-line' height."
  (let* ((background (face-background source nil t))
         (foreground (face-foreground source nil t))
         (box-width (my-feeds--header-box-width)))
    (set-face-attribute
     target nil
     :inherit source
     :background background
     :foreground foreground
     :box `(:line-width ,box-width :color ,background :style nil))))

(defun my-feeds--sync-powerline-header-faces ()
  "Synchronize Elfeed header faces with the active theme."
  (my-feeds--sync-powerline-header-face
   'my-feeds-search-header-active1 'powerline-active1)
  (my-feeds--sync-powerline-header-face
   'my-feeds-search-header-active2 'powerline-active2))

;;; Powerline header assembly ----------------------------------------

(defun my-feeds--powerline-separator (face1 face2)
  "Return an Elfeed header Powerline separator from FACE1 to FACE2."
  (if (eq elfeed-goodies/powerline-default-separator 'utf-8)
      (let* ((direction (car powerline-default-separator-dir))
             (separator (if (eq direction 'left)
                            powerline-utf-8-separator-left
                          powerline-utf-8-separator-right))
             (foreground (face-background face1 nil t))
             (background (face-background face2 nil t))
             (box-width (my-feeds--header-box-width)))
        (powerline-raw
         (char-to-string separator)
         `(:foreground ,foreground
           :background ,background
           :box (:line-width ,box-width :color ,background :style nil)
           :inverse-video nil)))
    (let ((separator (intern (format "powerline-%s-%s"
                                     elfeed-goodies/powerline-default-separator
                                     (car powerline-default-separator-dir)))))
      (when (fboundp separator)
        (funcall separator face1 face2)))))

(defun my-feeds--powerline-header-column (text width face align)
  "Return a Powerline header column for TEXT, WIDTH, FACE, and ALIGN."
  (powerline-raw
   (pcase align
     ('center (my-feeds--center-header-label text width))
     (_ (elfeed-format-column (concat " " (or text "") " ") width :left)))
   face))

(defun my-feeds--powerline-header (columns)
  "Draw a Date / Tags / Subject / Feed Source header from COLUMNS.

COLUMNS is a four-item list where each item is (TEXT ALIGN).  ALIGN may
be `center' for headings or `left' for entry values."
  (cl-destructuring-bind (date-width tag-width subject-width feed-width)
      (my-feeds--search-layout (my-feeds--header-window-width))
    (my-feeds--sync-powerline-header-faces)
    (let* ((date-face 'my-feeds-search-header-active1)
           (tag-face 'my-feeds-search-header-active2)
           (subject-face 'my-feeds-search-header-active1)
           (feed-face 'my-feeds-search-header-active2)
           (widths (list date-width tag-width subject-width feed-width))
           (faces (list date-face tag-face subject-face feed-face))
           (next-faces (list tag-face subject-face feed-face nil))
           segments)
      (cl-loop for (text align) in columns
               for width in widths
               for face in faces
               for next-face in next-faces
               do (push (my-feeds--powerline-header-column
                         text width face align)
                        segments)
                  (when next-face
                    (push (my-feeds--powerline-separator face next-face)
                          segments)))
      (concat (powerline-render (nreverse segments))
              (my-feeds--header-trailing-pad feed-face)))))

;;; Visual setup + redraw hooks --------------------------------------

(defun my-feeds-search-refresh-on-resize (window)
  "Refresh the Elfeed search listing after WINDOW changes width."
  (let ((width (window-body-width window)))
    (when (and (derived-mode-p 'elfeed-search-mode)
               (not (equal width my-feeds-search--last-window-width)))
      (setq my-feeds-search--last-window-width width)
      (when (timerp my-feeds-search--resize-timer)
        (cancel-timer my-feeds-search--resize-timer))
      (setq my-feeds-search--resize-timer
            (run-at-time
             0.2 nil
             (lambda (buffer)
               (when (buffer-live-p buffer)
                 (with-current-buffer buffer
                   (setq my-feeds-search--resize-timer nil)
                   (when (derived-mode-p 'elfeed-search-mode)
                     (elfeed-search-update--force)
                     (force-mode-line-update)))))
             (current-buffer))))))

(defun my-feeds-search-visual-setup ()
  "Apply buffer-local readability tweaks for the Elfeed search buffer."
  (setq-local line-spacing my-feeds-search-line-spacing)
  (setq-local right-fringe-width 0)
  (setq-local my-feeds-search--last-window-width
              (my-feeds--search-window-width))
  (add-hook 'window-size-change-functions
            #'my-feeds-search-refresh-on-resize nil t)
  (when my-feeds-search--font-remap-cookie
    (face-remap-remove-relative my-feeds-search--font-remap-cookie))
  (setq-local my-feeds-search--font-remap-cookie
              (face-remap-add-relative 'default :height my-feeds-search-font-scale))
  (setq-local my-feeds-search--header-remap-cookies
              (my-feeds--remap-header-line-tail
               my-feeds-search--header-remap-cookies)))

(defun my-feeds-show-visual-setup ()
  "Apply visual tweaks for the Elfeed show buffer."
  (setq-local header-line-format '(:eval (my-feeds-show-header-draw))
              line-spacing my-feeds-search-line-spacing
              right-fringe-width 0)
  (when my-feeds-show--font-remap-cookie
    (face-remap-remove-relative my-feeds-show--font-remap-cookie))
  (setq-local my-feeds-show--font-remap-cookie
              (face-remap-add-relative 'default :height my-feeds-search-font-scale))
  (setq-local my-feeds-show--header-remap-cookies
              (my-feeds--remap-header-line-tail
               my-feeds-show--header-remap-cookies))
  (dolist (window (get-buffer-window-list (current-buffer) nil t))
    (set-window-margins window nil nil)))

;;; Header / entry drawers -------------------------------------------

(defun my-feeds-search-header-draw ()
  "Draw the Elfeed search header with the preferred column order."
  (my-feeds--powerline-header
   '(("Date" center)
     ("Tags" center)
     ("Subject" center)
     ("Feed Source" center))))

(defun my-feeds-show-header-draw ()
  "Draw the Elfeed show header with the same order as search rows."
  (when elfeed-show-entry
    (let* ((date (format-time-string
                  "%Y-%m-%d"
                  (seconds-to-time (elfeed-entry-date elfeed-show-entry))))
           (tags (mapcar #'symbol-name
                         (elfeed-entry-tags elfeed-show-entry)))
           (tags-str (concat "[" (mapconcat #'identity tags ",") "]"))
           (title (or (elfeed-meta elfeed-show-entry :title)
                      (elfeed-entry-title elfeed-show-entry)
                      ""))
           (feed (elfeed-entry-feed elfeed-show-entry))
           (feed-title (if feed
                           (or (elfeed-meta feed :title)
                               (elfeed-feed-title feed))
                         "")))
      (my-feeds--powerline-header
       (list (list date 'left)
             (list tags-str 'left)
             (list title 'left)
             (list feed-title 'left))))))

(defun my-feeds-search-entry-line-draw (entry)
  "Print ENTRY using Date, Tags, Subject, Feed Source columns."
  (cl-destructuring-bind (date-width tag-width subject-width feed-width)
      (my-feeds--search-layout (my-feeds--header-window-width))
    (let* ((date (elfeed-search-format-date (elfeed-entry-date entry)))
           (title (or (elfeed-meta entry :title) (elfeed-entry-title entry) ""))
           (title-faces (elfeed-search--faces (elfeed-entry-tags entry)))
           (feed (elfeed-entry-feed entry))
           (feed-title (if feed
                           (or (elfeed-meta feed :title) (elfeed-feed-title feed))
                         ""))
           (tags (mapcar #'symbol-name (elfeed-entry-tags entry)))
           (tags-str (concat "[" (mapconcat #'identity tags ",") "]"))
           (date-column (elfeed-format-column date date-width :left))
           (tag-column (elfeed-format-column tags-str tag-width :left))
           (feed-column (elfeed-format-column feed-title feed-width :left))
           (title-column (elfeed-format-column title subject-width :left)))
      (insert (propertize date-column 'face 'elfeed-search-date-face) " ")
      (insert (propertize tag-column 'face 'elfeed-search-tag-face) " ")
      (insert (propertize title-column 'face title-faces 'kbd-help title) " ")
      (insert (propertize feed-column 'face 'elfeed-search-feed-face)))))

(provide 'my-feeds-search-header)
;;; my-feeds-search-header.el ends here
