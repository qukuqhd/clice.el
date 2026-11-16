;;; clice-fold.el --- Folding driven by LSP folding ranges  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 gangx

;; Author: gangx
;; URL: https://github.com/qukuqhd/clice.el
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Eglot does not implement `textDocument/foldingRange'.  clice produces
;; clang-accurate ranges (namespaces, types, functions, lambdas, blocks,
;; templates, includes, comments), so folding should come from the server
;; rather than from `hs-minor-mode' syntax heuristics.
;;
;; `hs-minor-mode' is enabled on `prog-mode' by many distributions
;; (including Centaur); in clice buffers this mode should win and the
;; two must not both manipulate invisibility.

;;; Code:

(require 'clice-protocol)

;; TODO:
;; - `clice-fold-mode' with a range tree, `clice-toggle-fold',
;;   `clice-fold-all', `clice-unfold-all'.
;; - Render with `invisible' overlays, `isearch-open-invisible', and a
;;   fringe/ellipsis indicator.
;; - Refresh on save and after server-side recompiles; prevent refresh
;;   from collapsing user-opened folds.
;; - Turn `hs-minor-mode' off in buffers where `clice-fold-mode' is on.

(provide 'clice-fold)

;;; clice-fold.el ends here
