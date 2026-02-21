;;; my-loader.el --- Error-resilient module loader -*- lexical-binding: t; -*-

(defmacro my-load-module (name file)
  "Load FILE as module NAME, catching errors gracefully.
NAME is an unquoted symbol for logging.  FILE is a string passed to `load'."
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

(provide 'my-loader)
;;; my-loader.el ends here
