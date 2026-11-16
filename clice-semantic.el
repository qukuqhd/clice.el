;;; clice-semantic.el --- Eglot semantic tokens for clice's legend  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 gangx

;; Author: gangx
;; URL: https://github.com/qukuqhd/clice.el
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Eglot only paints semantic-token types and modifiers listed in
;; `eglot-semantic-token-types' / `eglot-semantic-token-modifiers', and
;; only has faces for its own (standard) subset.  clice's legend is much
;; richer (field, union, module, header, directive, typeAlias,
;; templateParameter, concept, escape, formatSpecifier, primitive, bracket,
;; declarator, affix, inactive, ...) and its `inactive' modifier is what
;; dims code belonging to other compilation contexts.
;;
;; This library defines the extra faces and extends those two variables.
;; `eglot-semantic-tokens-mode' then paints them; no Eglot patch needed.

;;; Code:

(require 'clice-protocol)

;; TODO:
;; - `defface clice-semantic-<type>' for every extra type/modifier, all
;;   inheriting the closest standard face (e.g. field -> property-use,
;;   templateParameter -> type, inactive -> shadow).
;; - Append the names to `eglot-semantic-token-types' /
;;   `eglot-semantic-token-modifiers' (respecting the user's choice).
;; - Enable `eglot-semantic-tokens-mode' and `eglot-inlay-hints-mode' on
;;   clice-managed C/C++ buffers.
;; - Invalidate Eglot's per-token face cache after changing the lists.

(provide 'clice-semantic)

;;; clice-semantic.el ends here
