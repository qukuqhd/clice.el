;;; clice-toml-test.el --- Tests for clice-toml  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Code:

(require 'ert)
(require 'clice-toml)

(ert-deftest clice-toml-config-file ()
  "clice.toml wins over .clice/config.toml."
  (let ((dir (make-temp-file "clice-toml-" t)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name ".clice" dir) t)
          (with-temp-file (expand-file-name ".clice/config.toml" dir)
            (insert ""))
          (should (equal (clice--config-file dir)
                         (expand-file-name ".clice/config.toml" dir)))
          (with-temp-file (expand-file-name "clice.toml" dir) (insert ""))
          (should (equal (clice--config-file dir)
                         (expand-file-name "clice.toml" dir))))
      (delete-directory dir t))))

(ert-deftest clice-toml-schema-comment ()
  "The schema comment is inserted once."
  (with-temp-buffer
    (insert "default_configuration = \"debug\"\n")
    (cl-letf (((symbol-function 'message) #'ignore))
      (clice-insert-schema-comment)
      (clice-insert-schema-comment))
    (goto-char (point-min))
    (should (= 1 (count-matches (regexp-quote clice-schema-url)
                                (point-min) (point-max))))
    (should (string-prefix-p "#:schema" (buffer-string)))))

(provide 'clice-toml-test)

;;; clice-toml-test.el ends here
