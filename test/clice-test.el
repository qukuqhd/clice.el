;;; clice-test.el --- Tests for clice.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 gangx

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Unit tests that do not need a running clice server.  Integration tests
;; against a real server live in test/integration/ and are skipped when the
;; executable is missing.

;;; Code:

(require 'ert)
(require 'seq)
(require 'clice)

(defmacro clice-test--with-clean-state (&rest body)
  "Run BODY with a private `eglot-server-programs' and no clice advice."
  (declare (indent 0) (debug t))
  `(let ((eglot-server-programs (copy-sequence eglot-server-programs))
         (clice--setup-p nil))
     (clice-unsetup)
     (unwind-protect
         (progn ,@body)
       (clice-unsetup))))

(defun clice-test--clice-entries ()
  "Return the `eglot-server-programs' entries that start clice."
  (seq-filter (lambda (entry)
                (clice--command-p (cdr-safe entry)))
              eglot-server-programs))

(ert-deftest clice-test-augment-capabilities ()
  "Clice's capabilities are added without touching the input."
  (let* ((input (list :textDocument
                      (list :hover '(:dynamicRegistration :json-false))
                      :experimental eglot--{}))
         (output (clice--augment-capabilities input))
         (text-document (plist-get output :textDocument)))
    (dolist (capability '(:documentLink :foldingRange :selectionRange))
      (should (equal (plist-get text-document capability)
                     '(:dynamicRegistration :json-false))))
    (should (equal (plist-get output :experimental)
                   '(:restartServer t)))
    ;; Eglot's other entries survive.
    (should (equal (plist-get text-document :hover)
                   '(:dynamicRegistration :json-false)))
    ;; The argument itself is not mutated.
    (should-not (plist-get (plist-get input :textDocument) :documentLink))))

(ert-deftest clice-test-command-p ()
  "Only clice command lines are recognised."
  (should (clice--command-p '("clice" "serve")))
  (should (clice--command-p '("/usr/bin/clice" "serve")))
  (should (clice--command-p '("C:/tools/clice.exe" "serve")))
  (should-not (clice--command-p '("/usr/bin/clangd")))
  (should-not (clice--command-p '("gopls")))
  (should-not (clice--command-p nil))
  (should-not (clice--command-p "clice")))

(ert-deftest clice-test-register-server-program ()
  "Setup registers exactly one clice entry, with language ids."
  (clice-test--with-clean-state
    (clice-setup)
    (let ((entries (clice-test--clice-entries)))
      (should (= 1 (length entries)))
      (should (equal (cdr (car entries))
                     (cons clice-executable clice-server-args)))
      (let ((modes (car (car entries))))
        (should (equal (plist-get (cdr (assq 'c-mode modes)) :language-id) "c"))
        (should (equal (plist-get (cdr (assq 'c++-mode modes)) :language-id) "cpp"))
        (should (equal (plist-get (cdr (assq 'objc++-mode modes))
                                  :language-id)
                       "objective-cpp"))))
    ;; Idempotent.
    (clice-setup)
    (should (= 1 (length (clice-test--clice-entries))))
    (clice-unsetup)
    (should (= 0 (length (clice-test--clice-entries))))))

(ert-deftest clice-test-mode-toggles-setup ()
  "`clice-mode' installs and removes the integration."
  (clice-test--with-clean-state
    (clice-mode 1)
    (should clice--setup-p)
    (should (= 1 (length (clice-test--clice-entries))))
    (clice-mode -1)
    (should-not clice--setup-p)
    (should (= 0 (length (clice-test--clice-entries))))))

(ert-deftest clice-test-parse-version ()
  "Clice's version string is parsed into numbers."
  (should (equal (clice--parse-version "clice version 0.1.0+g5803486")
                 '(0 1 0)))
  (should (equal (clice--parse-version "0.2.10") '(0 2 10)))
  (should-not (clice--parse-version "clice version unknown"))
  (should-not (clice--parse-version nil)))

(provide 'clice-test)

;;; clice-test.el ends here
