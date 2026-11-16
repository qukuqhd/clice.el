;;; clice-select.el --- Selection ranges from the language server  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 gangx

;; Author: gangx
;; URL: https://github.com/qukuqhd/clice.el
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Eglot does not implement `textDocument/selectionRange'.  clice expands a
;; selection along C++ syntax (expressions, statements, declarations,
;; blocks) and into text-only positions inside comments, strings and
;; brackets.
;;
;; Plan: keep a per-buffer stack of ranges returned for the current
;; position; `clice-expand-region' walks to the parent, `clice-contract-region'
;; walks back, activating the region each time.

;;; Code:

(require 'clice-protocol)

;; TODO:
;; - `clice--selection-ranges' request for one position (parents array).
;; - `clice-expand-region' / `clice-contract-region' with an invocation
;;   stack; reset when point leaves the region.
;; - Optional bridge to `expand-region' (`C-='): when the clice stack is
;;   active, use the LSP step instead of the heuristic one.

(provide 'clice-select)

;;; clice-select.el ends here
