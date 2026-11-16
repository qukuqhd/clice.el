;;; clice-fold-test.el --- Tests for clice-fold  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Code:

(require 'ert)
(require 'clice-fold)

(defun clice-fold-test--buffer ()
  "Return a buffer with ten numbered lines."
  (let ((buffer (generate-new-buffer "*clice-fold-test*")))
    (with-current-buffer buffer
      (dotimes (i 10) (insert (format "line %d\n" i)))
      (goto-char (point-min)))
    buffer))

(ert-deftest clice-fold-key-uses-camel-case ()
  "Fold keys read the LSP camelCase fields."
  (should (equal (clice--fold-key '(:startLine 1 :endLine 3
                                    :startCharacter 4 :endCharacter 5))
                 '(1 3 4 5))))

(ert-deftest clice-fold-render-and-toggle ()
  "Ranges become overlays that can be folded and stay folded."
  (let ((buffer (clice-fold-test--buffer)))
    (unwind-protect
        (with-current-buffer buffer
          (setq clice--fold-ranges
                '((:startLine 2 :endLine 5 :startCharacter 0 :endCharacter 1)))
          (clice--fold-render)
          (should (= 1 (length clice--fold-overlays)))
          (let ((overlay (cdr (car clice--fold-overlays))))
            (should (= (overlay-start overlay)
                       (save-excursion (goto-char (point-min))
                                       (forward-line 3) (point))))
            (goto-char (overlay-start overlay))
            (clice-toggle-fold)
            (should (overlay-get overlay 'invisible)))
          ;; Re-rendering keeps the fold closed.
          (let ((key (caar clice--fold-overlays)))
            (should (gethash key clice--fold-closed))
            (clice--fold-render)
            (should (overlay-get (cdr (assoc key clice--fold-overlays))
                                 'invisible)))
          (clice-unfold-all)
          (should-not (overlay-get (cdr (car clice--fold-overlays)) 'invisible)))
      (kill-buffer buffer))))

(ert-deftest clice-fold-skips-single-line-ranges ()
  "A range that does not span a line is ignored."
  (let ((buffer (clice-fold-test--buffer)))
    (unwind-protect
        (with-current-buffer buffer
          (setq clice--fold-ranges
                '((:startLine 2 :endLine 2 :startCharacter 0 :endCharacter 3)))
          (clice--fold-render)
          (should-not clice--fold-overlays))
      (kill-buffer buffer))))

(provide 'clice-fold-test)

;;; clice-fold-test.el ends here
