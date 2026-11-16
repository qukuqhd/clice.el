;;; clice-cli.el --- Run the clice command line tools  -*- lexical-binding: t; -*-

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

;; clice also ships project-wide tools that LSP does not expose: `analyze',
;; `format --check', `index', `lint', `modularize', `query', `refactor' and
;; `scan'.  This library runs them from Emacs; diagnostics go through
;; `compilation-mode', JSON output is shown in a JSON buffer.
;;
;; These commands write clice's cache.  The running language server also
;; reads it, so avoid starting a long `clice index' while the server is
;; compiling heavily.

;;; Code:

(require 'json)
(require 'clice-protocol)

(defcustom clice-cli-jobs nil
  "Value for `--jobs' passed to clice CLI commands.
Nil means clice's default."
  :type '(choice (const :tag "Default" nil)
                 (integer :tag "Workers"))
  :group 'clice)

(defun clice--cli-args (arguments &optional no-jobs)
  "Return ARGUMENTS with the optional `--jobs' flag.
NO-JOBS disables the flag for commands that do not accept it."
  (append arguments
          (when (and clice-cli-jobs (not no-jobs))
            (list "--jobs" (number-to-string clice-cli-jobs)))))

(defun clice--cli-command (arguments)
  "Return a shell command string for clice and ARGUMENTS."
  (mapconcat #'shell-quote-argument
             (cons clice-executable arguments)
             " "))

(defun clice--run-compilation (arguments name)
  "Run clice with ARGUMENTS in `compilation-mode', named NAME."
  (let ((default-directory (clice-project-root))
        (compilation-read-command nil)
        (compilation-buffer-name-function (lambda (_mode) name)))
    (compile (clice--cli-command (clice--cli-args arguments)))))

(defun clice-lint ()
  "Lint the project with clice."
  (interactive)
  (clice--run-compilation '("lint") "clice-lint"))

(defun clice-format-check ()
  "Report the files clice would reformat."
  (interactive)
  (clice--run-compilation '("format" "--check") "clice-format-check"))

(defun clice-index ()
  "Index the project with clice."
  (interactive)
  (clice--run-compilation '("index") "clice-index"))

(defun clice-scan ()
  "Scan the project's dependencies with clice."
  (interactive)
  (clice--run-compilation '("scan") "clice-scan"))

(defun clice--json-command (arguments)
  "Run clice with ARGUMENTS and return the parsed JSON."
  (let ((default-directory (clice-project-root))
        (buffer (get-buffer-create " *clice-json*")))
    (unwind-protect
        (with-current-buffer buffer
          (erase-buffer)
          (let ((status (apply #'call-process clice-executable nil t nil
                               (clice--cli-args arguments))))
            (goto-char (point-min))
            (condition-case nil
                (json-parse-buffer :object-type 'plist :array-type 'list)
              (error
               (user-error "clice %s failed (exit %d): %s"
                           (string-join arguments " ")
                           status
                           (string-trim (buffer-string)))))))
      (kill-buffer buffer))))

(defun clice--json-buffer (title data)
  "Show DATA as JSON in a read-only buffer named TITLE."
  (with-current-buffer (get-buffer-create title)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (json-encode data))
      (goto-char (point-min))
      (when (fboundp 'json-pretty-print)
        (json-pretty-print (point-min) (point-max))))
    (special-mode)
    (display-buffer (current-buffer))))

(defun clice-scan-json ()
  "Show clice's dependency scan as JSON."
  (interactive)
  (clice--json-buffer "*clice scan*" (clice--json-command '("scan" "--json"))))

(defun clice-lint-json ()
  "Show clice's lint report as JSON."
  (interactive)
  (clice--json-buffer "*clice lint*" (clice--json-command '("lint" "--json"))))

(defconst clice-query-subcommands
  '(("project-files" . nil)
    ("file-deps" . "File: ")
    ("impact-analysis" . "File: ")
    ("counterparts" . "File: ")
    ("symbol-search" . "Locator: ")
    ("read-symbol" . "Symbol: ")
    ("document-symbols" . "File: ")
    ("definition" . "Symbol: ")
    ("references" . "Symbol: ")
    ("call-graph" . "Function: ")
    ("implementation" . "Class: ")
    ("type-hierarchy" . "Type: "))
  "clice query subcommands and their argument prompts.")

(defun clice-query (subcommand &optional argument)
  "Run a clice query SUBCOMMAND with ARGUMENT and show the result.
Interactively, choose the subcommand and type its argument."
  (interactive
   (let* ((subcommand (completing-read "clice query: "
                                       clice-query-subcommands nil t))
          (prompt (cdr (assoc subcommand clice-query-subcommands))))
     (list subcommand (when prompt (read-string prompt)))))
  (let* ((arguments (append (list "query" subcommand)
                            (when (and argument (not (string-empty-p argument)))
                              (list argument))
                            ))
         (default-directory (clice-project-root))
         (buffer (get-buffer-create (format "*clice query %s*" subcommand))))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (unless (zerop (apply #'call-process clice-executable nil t nil
                              (clice--cli-args arguments t)))
          (message "clice query %s failed" subcommand)))
      (special-mode)
      (goto-char (point-min))
      (display-buffer (current-buffer)))))

(defun clice-run-cli (arguments)
  "Run clice with ARGUMENTS, read from the minibuffer."
  (interactive (list (read-string "clice arguments: ")))
  (clice--run-compilation (split-string-and-unquote arguments) "clice"))

(defun clice-cli-menu ()
  "Dispatch to the clice command line tools."
  (interactive)
  (pcase (completing-read
          "clice: "
          '("lint" "format --check" "index" "scan" "scan --json"
            "lint --json" "query" "run arbitrary arguments...")
          nil t)
    ("lint" (clice-lint))
    ("format --check" (clice-format-check))
    ("index" (clice-index))
    ("scan" (clice-scan))
    ("scan --json" (clice-scan-json))
    ("lint --json" (clice-lint-json))
    ("query" (call-interactively #'clice-query))
    (_ (call-interactively #'clice-run-cli))))

(provide 'clice-cli)

;;; clice-cli.el ends here
