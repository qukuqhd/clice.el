;;; clice-select-test.el --- Tests for clice-select  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Code:

(require 'ert)
(require 'clice-select)

(defconst clice-select-test--chain
  '((:range (:start (:line 0 :character 1) :end (:line 0 :character 5))
     :parent (:range (:start (:line 0 :character 0) :end (:line 0 :character 8))
                     :parent (:range (:start (:line 0 :character 0)
                                             :end (:line 0 :character 10)))))))

(ert-deftest clice-select-chain ()
  "The parent chain is returned innermost first."
  (let ((chain (clice--selection-chain (car clice-select-test--chain))))
    (should (= 3 (length chain)))
    (should (= 1 (plist-get (plist-get (car chain) :start) :character)))
    (should (= 0 (plist-get (plist-get (car (last chain)) :start) :character)))))

(ert-deftest clice-select-step ()
  "Expanding and contracting follows the server's chain."
  (with-temp-buffer
    (insert "abcdefghij\n")
    (setq buffer-file-name "/tmp/clice-select-test.cpp")
    (goto-char 3)
    (cl-letf (((symbol-function 'clice-current-server) (lambda (&optional _) t))
              ((symbol-function 'clice--request)
               (lambda (_method _params &optional _timeout)
                 (vector (car clice-select-test--chain)))))
      (clice-expand-region)
      (should (= 0 clice--selection-index))
      (should (equal (cons (region-beginning) (region-end)) '(2 . 6)))
      (clice-expand-region)
      (should (= 1 clice--selection-index))
      (should (equal (cons (region-beginning) (region-end)) '(1 . 9)))
      (clice-contract-region)
      (should (= 0 clice--selection-index))
      (should (equal (cons (region-beginning) (region-end)) '(2 . 6))))))

(provide 'clice-select-test)

;;; clice-select-test.el ends here
