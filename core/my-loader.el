;;; my-loader.el --- Error-resilient module loader -*- lexical-binding: t; -*-

;; Provides loading-time macros consumed by init.el and the
;; module files:
;;   `my-load-module'             — fail-soft wrapper around `load'
;;   `my-use-package-vc-or-not'   — :vc when permitted, else local-only

;; `my-load-module' catches errors from optional modules and logs them
;; to the *startup-errors* buffer so one broken module can't take down
;; the rest of the configuration.

(defmacro my-load-module (name file)
  "Load FILE as module NAME, catching errors gracefully.
NAME is an unquoted symbol used for logging.  FILE is a string passed to
`load'."
  (declare (debug (symbolp form))
           (indent 1))
  `(condition-case err
       (load ,file nil 'nomessage)
     (error
      (let ((buf (get-buffer-create "*startup-errors*")))
        (with-current-buffer buf
          (goto-char (point-max))
          (insert (format "[%s] Module `%s' failed:\n  %s\n\n"
                          (format-time-string "%T")
                          ',name
                          (error-message-string err))))
        (display-warning 'init
                         (format "Module `%s' failed to load: %s"
                                 ',name (error-message-string err))
                         :error)))))

(defmacro my-use-package-vc-or-not (name vc-spec &rest body)
  "Configure NAME via `use-package', preferring :vc when permitted.

NAME is the unquoted package symbol.  VC-SPEC is the form passed to
`use-package' as the :vc declaration when `my-package-vc-enabled' is
non-nil.  BODY is the rest of the `use-package' declaration (`:custom',
`:config', `:hook', `:bind', etc.) and is shared between the two
branches.

When :vc is disabled, the fallback `use-package' call is gated on
`locate-library' so node-style hosts that disable both `:vc' and
package-ensure don't fail loudly on packages they don't have installed.
On editable hosts the gate is irrelevant because the :vc branch is
taken; on node hosts a package must already be on the load-path for
this form to do anything.

This contract assumes `my-package-vc-enabled' and
`use-package-always-ensure' co-vary, which is how `init.el' configures
them."
  (declare (debug (symbolp form &rest sexp))
           (indent 2))
  `(if my-package-vc-enabled
       (use-package ,name :vc ,vc-spec ,@body)
     (when (locate-library ,(symbol-name name))
       (use-package ,name ,@body))))

(provide 'my-loader)
;;; my-loader.el ends here
