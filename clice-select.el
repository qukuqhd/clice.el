;;; clice-select.el --- Selection ranges from the language server  -*- lexical-binding: t; -*-

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

;; Eglot does not implement `textDocument/selectionRange'.  clice expands a
;; selection along C++ syntax (expressions, statements, declarations,
;; blocks) and into text-only positions inside comments, strings and
;; brackets.
;;
;; `clice-expand-region' walks outwards, `clice-contract-region' walks back
;; in.  Suggested binding (it overrides `expand-region'):
;;
;;   (keymap-set c++-ts-mode-map "C-=" #'clice-expand-region)

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'clice-protocol)

(defvar-local clice--selection-stack nil
  "Ranges returned for the current selection, innermost first.")

(defvar-local clice--selection-index nil
  "Index into `clice--selection-stack' for the active selection.")

(defun clice--selection-chain (node)
  "Return the parent chain of selection-range NODE, innermost first."
  (let (ranges)
    (while node
      (push (plist-get node :range) ranges)
      (setq node (plist-get node :parent)))
    (nreverse ranges)))

(defun clice--selection-range-bounds (range)
  "Return (BEG . END) for LSP RANGE."
  (cons (eglot--lsp-position-to-point (plist-get range :start))
        (eglot--lsp-position-to-point (plist-get range :end))))

(defun clice--selection-request ()
  "Ask clice for the selection-range chain at point."
  (let* ((result (clice--request
                  "textDocument/selectionRange"
                  (list :textDocument (list :uri (clice--uri))
                        :positions (vector (eglot--pos-to-lsp-position (point))))
                  10))
         (node (and (vectorp result) (> (length result) 0)
                    (aref result 0))))
    (and node (clice--selection-chain node))))

(defun clice--selection-active-p ()
  "Return non-nil when the cached selection still applies at point."
  (and clice--selection-stack
       clice--selection-index
       (region-active-p)
       (let* ((range (nth clice--selection-index clice--selection-stack))
              (bounds (clice--selection-range-bounds range)))
         (and (>= (point) (car bounds))
              (<= (point) (cdr bounds))))))

(defun clice--selection-apply (index)
  "Select the range at INDEX of the current stack."
  (let* ((range (nth index clice--selection-stack))
         (bounds (clice--selection-range-bounds range)))
    (setq clice--selection-index index)
    (goto-char (cdr bounds))
    (push-mark (car bounds) nil t)
    (activate-mark)))

(defun clice--selection-step (direction)
  "Move the selection one step in DIRECTION (+1 out, -1 in)."
  (if (clice--selection-active-p)
      (setq clice--selection-index
            (max 0 (min (+ clice--selection-index direction)
                        (1- (length clice--selection-stack)))))
    (setq clice--selection-stack
          (or (clice--selection-request)
              (user-error "clice returned no selection range"))
          clice--selection-index 0))
  (clice--selection-apply clice--selection-index))

;;;###autoload
(defun clice-expand-region ()
  "Expand the active region outwards using clice's selection ranges."
  (interactive)
  (unless (clice-current-server)
    (user-error "No clice server in this buffer"))
  (clice--selection-step 1))

;;;###autoload
(defun clice-contract-region ()
  "Shrink the active region inwards using clice's selection ranges."
  (interactive)
  (unless (clice-current-server)
    (user-error "No clice server in this buffer"))
  (clice--selection-step -1))

;;;###autoload
(defun clice-selection-range-reset ()
  "Forget the cached clice selection stack."
  (interactive)
  (setq clice--selection-stack nil
        clice--selection-index nil))

(provide 'clice-select)

;;; clice-select.el ends here
