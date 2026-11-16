;;; clice-toml.el --- clice.toml helpers  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 gangx

;; Author: gangx
;; URL: https://github.com/qukuqhd/clice.el
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; clice is configured by `clice.toml' (or `.clice/config.toml') at the
;; project root.  The file has a JSON Schema at
;; https://docs.clice.io/clice-config.schema.json; editors that understand
;; `#:schema' comments (taplo, and Emacs' `toml-ts-mode' when its schema
;; support is enabled) use it.

;;; Code:

(require 'clice-protocol)

(defconst clice-schema-url "https://docs.clice.io/clice-config.schema.json"
  "URL of the clice configuration JSON Schema.")

(defun clice--config-file (&optional root)
  "Return the configuration file of the project at ROOT, or nil."
  (let ((root (file-name-as-directory (or root (clice-project-root)))))
    (or (let ((file (expand-file-name "clice.toml" root)))
          (and (file-exists-p file) file))
        (let ((file (expand-file-name ".clice/config.toml" root)))
          (and (file-exists-p file) file)))))

;;;###autoload
(defun clice-open-project-config ()
  "Open the clice configuration of the current project.
Create `clice.toml' when the project has none."
  (interactive)
  (let* ((root (clice-project-root))
         (file (or (clice--config-file root)
                   (expand-file-name "clice.toml" root))))
    (find-file file)))

;;;###autoload
(defun clice-insert-schema-comment ()
  "Insert the clice configuration schema comment at the top of the file."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (if (re-search-forward (regexp-quote clice-schema-url) nil t)
        (message "The schema comment is already present")
      (insert (format "#:schema %s\n" clice-schema-url))
      (message "Inserted the clice schema comment"))))

(provide 'clice-toml)

;;; clice-toml.el ends here
