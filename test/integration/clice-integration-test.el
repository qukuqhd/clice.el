;;; clice-integration-test.el --- Tests against a real clice server  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 gangx

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; These tests start a real `clice serve' through Eglot.  They are skipped
;; when clice is not installed, so `make test' stays dependency-free.

;;; Code:

(require 'ert)
(require 'json)
(require 'clice)
(require 'clice-protocol)
(require 'clice-context)

(clice-setup)

;;; Helpers

(defun clice-integration--wait (predicate &optional seconds)
  "Wait until PREDICATE returns non-nil, at most SECONDS (default 30)."
  (let ((deadline (+ (float-time) (or seconds 30)))
        (done nil))
    (while (and (< (float-time) deadline)
                (not (setq done (ignore-errors (funcall predicate)))))
      (accept-process-output nil 0.2))
    done))

(defun clice-integration--write (dir relative content)
  "Write CONTENT to RELATIVE under DIR, creating directories."
  (let ((path (expand-file-name relative dir)))
    (make-directory (file-name-directory path) t)
    (with-temp-file path (insert content))))

(defun clice-integration--make-project (files &optional compile-files)
  "Create a git project under a temp directory.
FILES is an alist of relative path to content.  COMPILE-FILES lists the
sources to put in `compile_commands.json'."
  (let ((dir (make-temp-file "clice-it-" t)))
    (dolist (cell files)
      (clice-integration--write dir (car cell) (cdr cell)))
    (when compile-files
      (with-temp-file (expand-file-name "compile_commands.json" dir)
        (insert
         (json-encode
          (vconcat
           (mapcar (lambda (file)
                    (let ((path (expand-file-name file dir)))
                      (list :directory dir :file path
                              :command (format "g++ -std=c++20 -I%s -c %s"
                                               dir path))))
                    compile-files))))))
    (call-process "git" nil nil nil "-C" dir "init" "-q")
    dir))

(defun clice-integration--index (dir)
  "Build clice's persisted index for DIR."
  (let ((default-directory dir))
    (call-process clice-executable nil nil nil "index")))

(defun clice-integration--connect (file)
  "Start clice for FILE and return the Eglot server."
  (clice-setup)
  (with-current-buffer (find-file-noselect file)
    (let ((server (apply #'eglot--connect (eglot--guess-contact))))
      (clice-integration--wait
       (lambda () (eglot-server-capable :hoverProvider)) 60)
      server)))

(defun clice-integration--manage (file)
  "Make FILE a managed clice buffer."
  (with-current-buffer (find-file-noselect file)
    (eglot-ensure)
    (run-hooks 'post-command-hook)
    (clice-integration--wait (lambda () (eglot-managed-p)) 30)))

(defun clice-integration--compile (file)
  "Force clice to compile FILE by pulling its diagnostics."
  (with-current-buffer (find-file-noselect file)
    (ignore-errors
      (clice--request "textDocument/diagnostic"
                      (list :textDocument (list :uri (clice--uri))) 30))))

(defvar clice-integration--restart-reason nil
  "Reason of the last `clice/restartServer' request seen by a test.")

(defun clice-integration--record-restart (_server reason)
  "Record REASON for a test."
  (setq clice-integration--restart-reason reason))

(defun clice-integration--cleanup (server dir)
  "Shut SERVER down and delete DIR."
  (when (and server (jsonrpc-running-p server))
    (ignore-errors (eglot-shutdown server nil nil 'preserve-buffers)))
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (and buffer-file-name
                 (string-prefix-p (file-truename dir)
                                  (file-truename buffer-file-name)))
        (kill-buffer buffer))))
  (delete-directory dir t))

;;; Tests

(ert-deftest clice-integration-connect-and-capabilities ()
  "Clice is detected, and its capabilities reach Eglot."
  (skip-unless (executable-find clice-executable))
  (let* ((dir (clice-integration--make-project
               '(("main.cpp"
                  . "struct Foo { int value; };\nint main() { Foo f{1}; return f.value; }\n"))
               '("main.cpp")))
         (file (expand-file-name "main.cpp" dir))
         (server nil))
    (unwind-protect
        (progn
          (setq server (clice-integration--connect file))
          (with-current-buffer (find-file-noselect file)
            (should (clice-current-server))
            (should (eglot-server-capable :documentLinkProvider))
            (should (eglot-server-capable :foldingRangeProvider))
            (should (eglot-server-capable :selectionRangeProvider))))
      (clice-integration--cleanup server dir))))

(ert-deftest clice-integration-contexts ()
  "Header contexts are listed, switched, reset and toggled."
  (skip-unless (executable-find clice-executable))
  (let* ((dir (clice-integration--make-project
               '(("int_host.cpp"
                  . "#define VALUE_TYPE int\n#include \"shared.h\"\nVALUE_TYPE get_value() { return 0; }\nint main() { return 0; }\n")
                 ("real_host.cpp"
                  . "#define VALUE_TYPE float\n#include \"shared.h\"\nVALUE_TYPE get_value() { return 0.0f; }\nfloat real() { return 0; }\n")
                 ("shared.h" . "#pragma once\n\nVALUE_TYPE get_value();\n"))
               '("int_host.cpp" "real_host.cpp")))
         (file (expand-file-name "shared.h" dir))
         (server nil))
    (unwind-protect
        (progn
          (clice-integration--index dir)
          (setq server (clice-integration--connect
                        (expand-file-name "int_host.cpp" dir)))
          (clice-integration--manage (expand-file-name "real_host.cpp" dir))
          (clice-integration--compile (expand-file-name "int_host.cpp" dir))
          (clice-integration--compile (expand-file-name "real_host.cpp" dir))
          (with-current-buffer (find-file-noselect file)
            (eglot-ensure)
            (run-hooks 'post-command-hook)
            (should (clice-integration--wait
                     (lambda ()
                       (= 2 (length (append (plist-get (clice--all-contexts)
                                                       :contexts)
                                            nil))))
                     30))
            (let* ((listing (clice--all-contexts))
                   (contexts (append (plist-get listing :contexts) nil))
                   (labels (mapcar (lambda (item) (plist-get item :label))
                                   contexts))
                   (target (seq-find (lambda (item)
                                       (string-match-p "real_host" (plist-get item :label)))
                                     contexts)))
              (should (equal (sort labels #'string<)
                             '("int_host.cpp" "real_host.cpp")))
              (should target)
              ;; Switch.
              (should (eq (clice--switch-context target
                                                 (plist-get listing :epoch))
                          'success))
              (clice-context-refresh)
              (let ((current (clice--current-context)))
                (should (string-match-p "real_host"
                                        (plist-get (plist-get current :context)
                                                   :label)))
                (should-not (clice--json-true-p
                             (plist-get current :automatic))))
              ;; Reset.
              (clice-reset-context)
              (should (clice--json-true-p
                       (plist-get (clice--current-context) :automatic)))
              ;; Toggle other contexts.
              (let ((before (clice--json-true-p
                             (plist-get (clice--current-context) :otherContexts))))
                (clice-toggle-other-contexts)
                (should (not (eq before
                                 (clice--json-true-p
                                  (plist-get (clice--current-context)
                                             :otherContexts))))))
              ;; Compile command.
              (clice-show-compile-command)
              (with-current-buffer (get-buffer "*clice compile command: shared.h*")
                (should (string-match-p "# source: "
                                        (buffer-substring-no-properties
                                         (point-min) (point-max))))
                (should (string-match-p "# from: "
                                        (buffer-substring-no-properties
                                         (point-min) (point-max)))))
              ;; Counterparts (the persisted index may still be warming up).
              (should
               (clice-integration--wait
                (lambda ()
                  (let ((result (clice--request "clice/counterparts"
                                                (list :uri (clice--uri)) 10)))
                    (= 2 (length (append (plist-get result :candidates)
                                         nil)))))
                20)))
      (clice-integration--cleanup server dir))))))

(ert-deftest clice-integration-links-fold-selection ()
  "Document links, folding and selection ranges work end to end."
  (skip-unless (executable-find clice-executable))
  (let* ((dir (clice-integration--make-project
               '(("shared.h" . "#pragma once\n\nint add(int a, int b);\n")
                 ("main.cpp"
                  . "#include \"shared.h\"\n\nint main() {\n    int total = 0;\n    for (int i = 0; i < 3; ++i) {\n        total += add(i, 1);\n    }\n    return total;\n}\n"))
               '("main.cpp")))
         (file (expand-file-name "main.cpp" dir))
         (server nil))
    (unwind-protect
        (progn
          (setq server (clice-integration--connect file))
          (with-current-buffer (find-file-noselect file)
            ;; Links
            (should (clice-integration--wait
                     (lambda () (and clice-links-mode
                                     (> (length clice--link-overlays) 0)))
                     30))
            (should (seq-some
                     (lambda (overlay)
                       (string-match-p "shared.h"
                                       (overlay-get overlay 'clice--link-target)))
                     clice--link-overlays))
            ;; Folding
            (should (clice-integration--wait
                     (lambda () (> (length clice--fold-overlays) 0)) 30))
            (let* ((cell (car (sort (copy-sequence clice--fold-overlays)
                                    (lambda (a b)
                                      (< (overlay-start (cdr a))
                                         (overlay-start (cdr b)))))))
                   (overlay (cdr cell)))
              (goto-char (overlay-start overlay))
              (clice-toggle-fold)
              (should (overlay-get overlay 'invisible)))
            ;; Selection ranges
            (clice-selection-range-reset)
            (goto-char (point-min))
            (search-forward "add(i, 1)")
            (goto-char (match-beginning 0))
            (clice-expand-region)
            (let ((first (cons (region-beginning) (region-end))))
              (clice-expand-region)
              (let ((second (cons (region-beginning) (region-end))))
                (should (<= (- (car second) (cdr second))
                            (- (car first) (cdr first))))))
            (should (> (length clice--selection-stack) 1))))
      (clice-integration--cleanup server dir))))

(ert-deftest clice-integration-build-configurations ()
  "Build configurations are listed, selectable, and ask for a restart."
  (skip-unless (executable-find clice-executable))
  (let* ((dir (clice-integration--make-project
               '(("main.cpp" . "int main() { return 0; }\n")
                 ("clice.toml"
                  . "default_configuration = \"debug\"\n\n[[rules]]\nconfiguration = \"debug\"\ncompile_commands = [\"out/debug\"]\n\n[[rules]]\nconfiguration = \"release\"\ncompile_commands = [\"out/release\"]\n"))))
         (file (expand-file-name "main.cpp" dir))
         (server nil)
         (clice-auto-restart nil)
         (clice-integration--restart-reason nil))
    (dolist (configuration '("debug" "release"))
      (make-directory (expand-file-name (format "out/%s" configuration) dir) t)
      (clice-integration--write
       dir (format "out/%s/compile_commands.json" configuration)
       (json-encode
        (vector (list :directory dir :file file
                      :command (format "g++ -std=c++20 -I%s -c %s"
                                       dir file))))))
    (advice-add 'clice--handle-restart-request :before
                #'clice-integration--record-restart)
    (unwind-protect
        (progn
          (setq server (clice-integration--connect file))
          (with-current-buffer (find-file-noselect file)
            (let ((listing (clice--request "clice/listConfigurations"
                                           (list :uri (clice--uri)) 10)))
              (should (equal (sort (append (plist-get listing :configurations)
                                           nil)
                                   #'string<)
                             '("debug" "release")))
              (should (equal (plist-get listing :active) "debug")))
            (cl-letf (((symbol-function 'completing-read)
                       (lambda (&rest _) "release")))
              (clice-switch-configuration))
            (should (clice-integration--wait
                     (lambda () clice-integration--restart-reason) 15))
            (should (string-match-p "release"
                                    clice-integration--restart-reason))))
      (advice-remove 'clice--handle-restart-request
                     #'clice-integration--record-restart)
      (clice-integration--cleanup server dir))))

(provide 'clice-integration-test)

;;; clice-integration-test.el ends here
