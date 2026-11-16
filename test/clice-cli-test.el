;;; clice-cli-test.el --- Tests for clice-cli  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Code:

(require 'ert)
(require 'clice-cli)

(ert-deftest clice-cli-args ()
  "The optional --jobs flag is appended."
  (let ((clice-cli-jobs nil))
    (should (equal (clice--cli-args '("lint")) '("lint"))))
  (let ((clice-cli-jobs 4))
    (should (equal (clice--cli-args '("lint"))
                   '("lint" "--jobs" "4")))))

(ert-deftest clice-cli-command-quotes ()
  "The command line quotes the executable and arguments."
  (let ((clice-executable "clice"))
    (should (string-prefix-p "clice lint" (clice--cli-command '("lint"))))))

(ert-deftest clice-cli-query-subcommands ()
  "Every query subcommand has a prompt, optionally nil."
  (should (assoc "project-files" clice-query-subcommands))
  (should (cdr (assoc "definition" clice-query-subcommands))))

(provide 'clice-cli-test)

;;; clice-cli-test.el ends here
