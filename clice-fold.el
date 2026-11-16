;;; clice-fold.el --- Folding driven by LSP folding ranges  -*- lexical-binding: t; -*-

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

;; Eglot does not implement `textDocument/foldingRange'.  clice produces
;; clang-accurate ranges (namespaces, types, functions, lambdas, blocks,
;; templates, include groups, comments), so folding comes from the server
;; instead of `hs-minor-mode' syntax heuristics.
;;
;; Enabling `clice-fold-mode' turns `hs-minor-mode' off in the buffer: the
;; two must not both manipulate invisibility.
;;
;; Suggested bindings:
;;
;;   (keymap-set clice-fold-mode-map "TAB" #'clice-toggle-fold)
;;   (keymap-set clice-fold-mode-map "C-c C-f" #'clice-fold-all)

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'clice-protocol)

(defcustom clice-fold-auto-refresh t
  "Whether to refresh folding ranges automatically after edits."
  :type 'boolean
  :group 'clice)

(defvar clice-fold-mode)

(defvar-local clice--fold-ranges nil
  "Folding ranges from the server: a list of plists.
Each plist has `:startLine', `:endLine', `:startCharacter',
`:endCharacter' and `:kind'.")

(defvar-local clice--fold-overlays nil
  "Alist of (KEY . OVERLAY) for the current folding ranges.")

(defvar-local clice--fold-closed (make-hash-table :test #'equal)
  "Keys of the folding ranges currently collapsed.")

(defvar-local clice--fold-refresh-timer nil
  "Pending refresh timer for the current buffer.")

(defun clice--fold-line-beginning (line)
  "Return the buffer position at the beginning of 0-based LINE."
  (save-excursion
    (goto-char (point-min))
    (forward-line line)
    (point)))

(defun clice--fold-line-end (line)
  "Return the buffer position at the end of 0-based LINE."
  (save-excursion
    (goto-char (point-min))
    (forward-line line)
    (line-end-position)))

(defun clice--fold-key (range)
  "Return a stable key for folding RANGE."
  (list (plist-get range :startLine)
        (plist-get range :endLine)
        (plist-get range :startCharacter)
        (plist-get range :endCharacter)))

(defun clice--fold-clear-overlays ()
  "Delete all folding overlays in the current buffer."
  (mapc (lambda (cell) (delete-overlay (cdr cell))) clice--fold-overlays)
  (setq clice--fold-overlays nil))

(defun clice--fold-isearch-open (overlay)
  "Make OVERLAY visible for isearch."
  (overlay-put overlay 'invisible nil))

(defun clice--fold-isearch-temporary (overlay open)
  "Show or hide OVERLAY while isearch runs."
  (overlay-put overlay 'invisible (not open)))

(defun clice--fold-render ()
  "Create overlays for `clice--fold-ranges', preserving closed state."
  (clice--fold-clear-overlays)
  (let ((closed (make-hash-table :test #'equal)))
    (dolist (range clice--fold-ranges)
      (let* ((key (clice--fold-key range))
             (start (plist-get range :startLine))
             (end (plist-get range :endLine))
             (beg (clice--fold-line-beginning (1+ start)))
             (finish (clice--fold-line-end end))
             (was-closed (gethash key clice--fold-closed)))
        (when (and (integerp start) (integerp end)
                   (> end start)
                   (< beg finish))
          (when was-closed (puthash key t closed))
          (let ((overlay (make-overlay beg finish nil t)))
            (overlay-put overlay 'clice--fold-key key)
            (overlay-put overlay 'invisible (and was-closed t))
            (overlay-put overlay 'evaporate t)
            (overlay-put overlay 'isearch-open-invisible
                         #'clice--fold-isearch-open)
            (overlay-put overlay 'isearch-open-invisible-temporary
                         #'clice--fold-isearch-temporary)
            (overlay-put overlay 'help-echo "clice fold")
            (push (cons key overlay) clice--fold-overlays)))))
    (setq clice--fold-closed closed)))

(defun clice-fold-refresh (&optional buffer)
  "Refresh the folding ranges of BUFFER.
BUFFER defaults to the current buffer."
  (interactive)
  (let ((buffer (or buffer (current-buffer))))
    (when (and (buffer-live-p buffer)
               (buffer-local-value 'clice-fold-mode buffer)
               (with-current-buffer buffer
                 (and (clice-current-server)
                      (buffer-file-name))))
      (with-current-buffer buffer
        (when (eglot-server-capable :foldingRangeProvider)
          (condition-case nil
              (let ((ranges (append
                             (clice--request
                              "textDocument/foldingRange"
                              (list :textDocument (list :uri (clice--uri)))
                              10)
                             nil)))
                (setq clice--fold-ranges ranges)
                (clice--fold-render))
            (error nil)))))))

(defun clice--fold-schedule-refresh ()
  "Schedule a debounced folding refresh."
  (when (and clice-fold-mode clice-fold-auto-refresh)
    (when (timerp clice--fold-refresh-timer)
      (cancel-timer clice--fold-refresh-timer))
    (setq clice--fold-refresh-timer
          (run-at-time 0.8 nil #'clice-fold-refresh (current-buffer)))))

(defun clice--fold-at (position)
  "Return the innermost folding overlay around POSITION, or at its line."
  (let* ((line-start (save-excursion
                       (goto-char position)
                       (line-beginning-position)))
         (candidates
          (seq-filter
           (lambda (cell)
             (let ((overlay (cdr cell)))
               (or (and (>= position (overlay-start overlay))
                        (<= position (overlay-end overlay)))
                   (and (>= (overlay-start overlay) line-start)
                        (< (overlay-start overlay)
                           (save-excursion
                             (goto-char line-start)
                             (line-beginning-position 2)))))))
           clice--fold-overlays)))
    (car (sort candidates
               (lambda (a b)
                 (> (overlay-start (cdr a)) (overlay-start (cdr b))))))))

(defun clice-toggle-fold ()
  "Toggle the folding range at point."
  (interactive)
  (if-let* ((cell (clice--fold-at (point))))
      (let* ((key (car cell))
             (overlay (cdr cell))
             (closed (not (overlay-get overlay 'invisible))))
        (overlay-put overlay 'invisible closed)
        (if closed
            (puthash key t clice--fold-closed)
          (remhash key clice--fold-closed)))
    (user-error "No folding range here")))

(defun clice-fold-all ()
  "Fold all ranges reported by clice."
  (interactive)
  (dolist (cell clice--fold-overlays)
    (overlay-put (cdr cell) 'invisible t)
    (puthash (car cell) t clice--fold-closed)))

(defun clice-unfold-all ()
  "Unfold all ranges reported by clice."
  (interactive)
  (dolist (cell clice--fold-overlays)
    (overlay-put (cdr cell) 'invisible nil))
  (clrhash clice--fold-closed))

;;;###autoload
(define-minor-mode clice-fold-mode
  "Fold C/C++ code using clice's folding ranges."
  :lighter " clice-fold"
  :group 'clice
  (if clice-fold-mode
      (progn
        ;; hs-minor-mode uses syntax heuristics and its own invisibility;
        ;; keep a single mechanism in charge.
        (when (bound-and-true-p hs-minor-mode)
          (hs-minor-mode -1))
        (setq-local buffer-invisibility-spec '((t . t)))
        (add-hook 'after-save-hook #'clice-fold-refresh nil t)
        (add-hook 'after-change-functions #'clice--fold-schedule-refresh nil t)
        (run-at-time 0.5 nil #'clice-fold-refresh (current-buffer)))
    (remove-hook 'after-save-hook #'clice-fold-refresh t)
    (remove-hook 'after-change-functions #'clice--fold-schedule-refresh t)
    (when (timerp clice--fold-refresh-timer)
      (cancel-timer clice--fold-refresh-timer))
    (setq clice--fold-refresh-timer nil)
    (clice--fold-clear-overlays)))

(provide 'clice-fold)

;;; clice-fold.el ends here
