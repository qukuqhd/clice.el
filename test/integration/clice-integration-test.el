;;; clice-integration-test.el --- Tests against a real clice server  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 gangx

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; These tests start a real `clice serve' through Eglot.  They are skipped
;; when clice is not installed, so `make test' stays dependency-free.

;;; Code:

(require 'ert)
(require 'clice)
(require 'clice-protocol)

(defun clice-integration--make-project ()
  "Create a throwaway C++ project and return its directory.
The project has a git repository so Eglot finds a project root."
  (let ((dir (make-temp-file "clice-integration-" t)))
    (with-temp-file (expand-file-name "main.cpp" dir)
      (insert "struct Foo { int value; };\n"
              "int add(int a, int b) { return a + b; }\n"
              "int main() { Foo f{1}; return add(f.value, 2); }\n"))
    (with-temp-file (expand-file-name "compile_commands.json" dir)
      (insert (format "[{\"directory\":%S,\"file\":%S,\"command\":%S}]\n"
                      dir (expand-file-name "main.cpp" dir)
                      "g++ -std=c++20 -c main.cpp")))
    (call-process "git" nil nil nil "-C" dir "init" "-q")
    dir))

(defun clice-integration--connect (file)
  "Start clice for FILE and return the Eglot server."
  (clice-setup)
  (with-current-buffer (find-file-noselect file)
    (let ((server (apply #'eglot--connect (eglot--guess-contact))))
      (with-timeout (60)
        (while (not (ignore-errors (eglot-server-capable :hoverProvider)))
          (accept-process-output nil 0.3)))
      server)))

(ert-deftest clice-integration-connect-and-capabilities ()
  "Clice is detected, and its capabilities reach Eglot."
  (skip-unless (executable-find clice-executable))
  (let* ((dir (clice-integration--make-project))
         (file (expand-file-name "main.cpp" dir))
         (buffer (find-file-noselect file))
         (server nil))
    (unwind-protect
        (progn
          (setq server (clice-integration--connect file))
          (with-current-buffer buffer
            (should (clice-current-server))
            (should (eglot-server-capable :documentLinkProvider))
            (should (eglot-server-capable :foldingRangeProvider))
            (should (eglot-server-capable :selectionRangeProvider))
            (message "clice version: %s" (clice-version))))
      (when (and server (jsonrpc-running-p server))
        (ignore-errors (eglot-shutdown server nil nil 'preserve-buffers)))
      (clice-unsetup)
      (delete-directory dir t))))

(provide 'clice-integration-test)

;;; clice-integration-test.el ends here
