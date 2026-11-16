;;; clice-cli.el --- Run the clice command line tools  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 gangx

;; Author: gangx
;; URL: https://github.com/qukuqhd/clice.el
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;;; Commentary:

;; clice also ships project-wide tools that the editor protocol does not
;; expose: `analyze', `format --check', `index', `lint', `modularize',
;; `query', `refactor' and `scan'.  Most accept `--json'.
;;
;; This library runs them from Emacs: text output in `compilation-mode',
;; JSON output parsed for clickable results.

;;; Code:

(require 'clice-protocol)

;; TODO:
;; - `clice--run' using `compile' / `make-process' in the project root.
;; - `clice-lint' (JSON -> compilation-mode with file:line:col),
;;   `clice-format-check', `clice-index', `clice-scan'.
;; - `clice-query' sub-commands (symbol-search, definition, references,
;;   call-graph, counterparts, ...) with xref/tabulated-list output.
;; - `clice-dispatch' transient menu.
;; - Warn when a CLI run and the LSP server may touch the same cache.

(provide 'clice-cli)

;;; clice-cli.el ends here
