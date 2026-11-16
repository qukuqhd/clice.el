;;; clice-links.el --- Document links rendered with buttons  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 gangx

;; Author: gangx
;; URL: https://github.com/qukuqhd/clice.el
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Eglot does not implement `textDocument/documentLink'.  clice uses it for
;; `#include'/`#include_next'/`__has_include' and `#embed' targets, so the
;; header names become clickable here.
;;
;; Plan: `clice-links-mode' requests the links, renders them as text
;; buttons (RET / mouse-1), refreshes after save and on idle, and survives
;; edits by relying on overlay/marker tracking.

;;; Code:

(require 'clice-protocol)

;; TODO:
;; - `clice-links-mode' minor mode, refresh function, `clice-open-link'.
;; - Refresh triggers: `eglot-managed-mode-hook', `after-save-hook',
;;   debounced idle after changes.
;; - Handle ranges and `target' (uri + optional range); open with
;;   `xref--find-file' semantics so the target is reused.
;; - Face: `clice-link-face' inheriting `link'.

(provide 'clice-links)

;;; clice-links.el ends here
