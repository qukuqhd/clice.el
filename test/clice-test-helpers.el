;;; clice-test-helpers.el --- Shared helpers for clice integration tests  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 gangx

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Fixture projects live in test/fixtures/<name>.  A test copies one to a
;; temporary directory, writes a compilation database, starts clice through
;; Eglot and asserts against both the server and the package UI.

;;; Code:

(require 'ert)
(require 'json)
(require 'seq)
(require 'clice)
(require 'clice-protocol)
(require 'clice-context)
(require 'clice-cli)

(defconst clice-test--fixtures-dir
  (expand-file-name "fixtures"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Directory holding the integration fixture projects.")

(defun clice-test--wait (predicate &optional seconds)
  "Wait until PREDICATE returns non-nil, at most SECONDS (default 30)."
  (let ((deadline (+ (float-time) (or seconds 30)))
        (done nil))
    (while (and (< (float-time) deadline)
                (not (setq done (ignore-errors (funcall predicate)))))
      (accept-process-output nil 0.2))
    done))

(defun clice-test--substitute (string dir file)
  "Replace ${ROOT} and ${FILE} in STRING."
  (thread-last string
    (string-replace "${ROOT}" dir)
    (string-replace "${FILE}" file)))

(defun clice-test--database (dir entries)
  "Write `compile_commands.json' in DIR for ENTRIES.
Each entry is a relative file name, or (RELATIVE . PLIST) where PLIST
provides `:arguments' (without the file itself) or `:command'.  The
default command is `g++ -std=c++20 -I DIR/include -c FILE'."
  (let ((default-include (expand-file-name "include" dir))
        (result nil))
    (dolist (entry entries)
      (let* ((relative (if (consp entry) (car entry) entry))
             (spec (and (consp entry) (cdr entry)))
             (file (expand-file-name relative dir))
             (arguments (plist-get spec :arguments))
             (command (plist-get spec :command)))
        (push (cond
               (command
                (list :directory dir :file file
                      :command (clice-test--substitute command dir file)))
               (arguments
                (list :directory dir :file file
                      :arguments
                      (vconcat
                       (mapcar (lambda (argument)
                                 (clice-test--substitute argument dir file))
                               arguments)
                       (list file))))
               (t
                (list :directory dir :file file
                      :command
                      (format "g++ -std=c++20%s -c %s"
                              (if (file-directory-p default-include)
                                  (format " -I%s" default-include)
                                "")
                              file))))
              result)))
    (with-temp-file (expand-file-name "compile_commands.json" dir)
      (insert (json-encode (vconcat (nreverse result)))))))

(defun clice-test--fixture (name)
  "Copy fixture NAME to a temporary git project and return its directory."
  (let ((source (expand-file-name name clice-test--fixtures-dir))
        (destination (make-temp-file "clice-fixture-" t)))
    (copy-directory source destination nil t t)
    (call-process "git" nil nil nil "-C" destination "init" "-q")
    destination))

(defun clice-test--project (name &optional database)
  "Create a project from fixture NAME and write DATABASE."
  (let ((dir (clice-test--fixture name)))
    (when database (clice-test--database dir database))
    dir))

(defun clice-test--connect (file)
  "Start clice for FILE through Eglot and return the server."
  (clice-setup)
  (with-current-buffer (find-file-noselect file)
    (let ((server (apply #'eglot--connect (eglot--guess-contact))))
      (clice-test--wait
       (lambda () (eglot-server-capable :hoverProvider)) 60)
      server)))

(defun clice-test--manage (file)
  "Make FILE a managed clice buffer."
  (with-current-buffer (find-file-noselect file)
    (eglot-ensure)
    (run-hooks 'post-command-hook)
    (clice-test--wait (lambda () (eglot-managed-p)) 30)))

(defun clice-test--pull-diagnostics (file)
  "Force clice to compile FILE by pulling its diagnostics."
  (with-current-buffer (find-file-noselect file)
    (ignore-errors
      (clice--request "textDocument/diagnostic"
                      (list :textDocument (list :uri (clice--uri))) 30))))

(defun clice-test--index (dir)
  "Build clice's persisted index for DIR."
  (let ((default-directory dir))
    (call-process clice-executable nil nil nil "index")))

(defun clice-test--uri (file)
  "Return the file URI of FILE."
  (eglot-path-to-uri (expand-file-name file)))

(defun clice-test--request (file method params &optional timeout)
  "Send METHOD with PARAMS for FILE."
  (with-current-buffer (find-file-noselect file)
    (clice--request method params (or timeout 20))))

(defun clice-test--position (file needle &optional occurrence after)
  "Return the LSP position at NEEDLE in FILE.
OCCURRENCE defaults to 1.  With AFTER, use the end of the match."
  (with-current-buffer (find-file-noselect file)
    (goto-char (point-min))
    (let ((n (or occurrence 1)))
      (dotimes (_ (1- n)) (search-forward needle))
      (search-forward needle)
      (eglot--pos-to-lsp-position (if after (point) (match-beginning 0))))))

(defun clice-test--range (file needle &optional after)
  "Return a zero-width LSP range at NEEDLE in FILE."
  (let ((position (clice-test--position file needle 1 after)))
    (list :start position :end position)))

(defun clice-test--token-modifier-index (buffer modifier)
  "Return MODIFIER's index in BUFFER's semantic-token legend."
  (with-current-buffer buffer
    (let* ((server (eglot-current-server))
           (capabilities (eglot--capabilities server))
           (modifiers (append
                       (plist-get (plist-get (plist-get capabilities
                                                        :semanticTokensProvider)
                                             :legend)
                                  :tokenModifiers)
                       nil)))
      (seq-position modifiers modifier))))

(defun clice-test--token-has-modifier-p (data index)
  "Return non-nil when DATA contains the modifier at INDEX."
  (and index
       (cl-loop for i from 0 below (length data) by 5
                for bits = (aref data (+ i 4))
                thereis (cl-plusp (logand bits (ash 1 index))))))

(defun clice-test--cleanup (server dir)
  "Shut SERVER down and delete DIR."
  (when (and server (jsonrpc-running-p server))
    (ignore-errors (eglot-shutdown server nil 5 'preserve-buffers))
    (when (jsonrpc-running-p server)
      (ignore-errors (delete-process (jsonrpc--process server)))))
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (and buffer-file-name
                 (string-prefix-p (file-truename dir)
                                  (file-truename buffer-file-name)))
        (kill-buffer buffer))))
  (delete-directory dir t)
  (message "clice-test: cleanup done"))

(provide 'clice-test-helpers)

;;; clice-test-helpers.el ends here
