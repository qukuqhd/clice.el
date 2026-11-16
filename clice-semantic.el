;;; clice-semantic.el --- Eglot semantic tokens for clice's legend  -*- lexical-binding: t; -*-

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

;; Eglot paints only the semantic-token types and modifiers in
;; `eglot-semantic-token-types' / `eglot-semantic-token-modifiers'.  clice's
;; legend is richer: it adds types such as `field', `union', `module',
;; `header', `directive', `templateParameter', `typeAlias' and `concept',
;; and modifiers such as `local', `member', `virtual' and `constexpr'.
;;
;; The `inactive' modifier is how clice marks code that belongs to another
;; compilation context; painting it with `shadow' gives the dimming that its
;; VS Code extension implements.

;;; Code:

(require 'eieio)
(require 'clice-protocol)

(defcustom clice-enable-semantic-tokens t
  "Whether to enable `eglot-semantic-tokens-mode' in clice buffers."
  :type 'boolean
  :group 'clice)

(defcustom clice-enable-inlay-hints t
  "Whether to enable `eglot-inlay-hints-mode' in clice buffers."
  :type 'boolean
  :group 'clice)

(defconst clice-semantic-extra-types
  '(("character" . font-lock-string-face)
    ("escape" . font-lock-string-face)
    ("formatSpecifier" . font-lock-builtin-face)
    ("primitive" . font-lock-type-face)
    ("bracket" . font-lock-bracket-face)
    ("directive" . font-lock-preprocessor-face)
    ("header" . font-lock-string-face)
    ("module" . font-lock-type-face)
    ("union" . font-lock-type-face)
    ("typeAlias" . font-lock-type-face)
    ("templateParameter" . font-lock-type-face)
    ("concept" . font-lock-type-face)
    ("field" . font-lock-property-use-face)
    ("label" . font-lock-constant-face)
    ("macroParameter" . font-lock-variable-name-face)
    ("attribute" . font-lock-builtin-face)
    ("conflict" . font-lock-warning-face))
  "Semantic-token types clice knows beyond Eglot's standard set.")

(defconst clice-semantic-extra-modifiers
  '(("local" . font-lock-variable-name-face)
    ("member" . font-lock-property-use-face)
    ("internal" . font-lock-keyword-face)
    ("global" . font-lock-keyword-face)
    ("template" . font-lock-type-face)
    ("dependent" . font-lock-type-face)
    ("virtual" . font-lock-keyword-face)
    ("constexpr" . font-lock-keyword-face)
    ("constructor" . font-lock-function-name-face)
    ("destructor" . font-lock-function-name-face)
    ("callable" . font-lock-function-name-face)
    ("controlFlow" . font-lock-keyword-face)
    ("userDefined" . font-lock-constant-face)
    ("declarator" . font-lock-variable-name-face)
    ("literal" . font-lock-constant-face)
    ("affix" . font-lock-builtin-face)
    ("empty" . shadow)
    ("inactive" . shadow)
    ("operator" . font-lock-function-name-face))
  "Semantic-token modifiers clice knows beyond Eglot's standard set.")

(defun clice--face-parent (face fallback)
  "Return FACE when it exists, else FALLBACK."
  (if (facep face) face fallback))

(defun clice-semantic--define-faces ()
  "Define the faces clice's extra token types and modifiers need."
  (dolist (cell (append clice-semantic-extra-types
                        clice-semantic-extra-modifiers))
    (let* ((name (car cell))
           (face (intern (format "eglot-semantic-%s" name)))
           (parent (clice--face-parent (cdr cell)
                                       'font-lock-variable-name-face)))
      (unless (facep face)
        (custom-declare-face
         face `((t :inherit ,parent))
         (format "Semantic token face for clice's `%s'." name)
         :group 'eglot-semantic-faces)))))

(defun clice-semantic--extend-lists ()
  "Add clice's extra types and modifiers to Eglot's lists."
  (when (boundp 'eglot-semantic-token-types)
    (dolist (cell clice-semantic-extra-types)
      (add-to-list 'eglot-semantic-token-types (car cell))))
  (when (boundp 'eglot-semantic-token-modifiers)
    (dolist (cell clice-semantic-extra-modifiers)
      (add-to-list 'eglot-semantic-token-modifiers (car cell)))))

(clice-semantic--define-faces)
(clice-semantic--extend-lists)

(defun clice-semantic--clear-cache ()
  "Forget Eglot's decoded-token cache for the current clice server."
  (when-let* ((server (clice-current-server)))
    (ignore-errors
      (let ((cache (eieio-oref server 'semtok-cache)))
        (when (hash-table-p cache)
          (clrhash cache))))))

;;;###autoload
(defun clice-semantic-refresh ()
  "Re-fontify the buffer after the semantic-token lists changed."
  (interactive)
  (clice-semantic--clear-cache)
  (when (bound-and-true-p eglot-semantic-tokens-mode)
    (eglot-semantic-tokens-mode -1)
    (eglot-semantic-tokens-mode 1))
  (font-lock-flush))

(defun clice-semantic--enable ()
  "Enable semantic tokens and inlay hints in the current clice buffer."
  (when (and (clice-current-server)
             (eglot-server-capable :semanticTokensProvider))
    (when (and clice-enable-semantic-tokens
               (fboundp 'eglot-semantic-tokens-mode)
               (not eglot-semantic-tokens-mode))
      (eglot-semantic-tokens-mode 1))
    (when (and clice-enable-inlay-hints
               (fboundp 'eglot-inlay-hints-mode)
               (not eglot-inlay-hints-mode))
      (eglot-inlay-hints-mode 1))))

(defun clice-semantic--setup ()
  "Set up semantic tokens in the current buffer, waiting for the server."
  (when (and (clice-current-server)
             (buffer-file-name)
             (derived-mode-p 'c-mode 'c-ts-mode 'c++-mode 'c++-ts-mode))
    (if (eglot-server-capable :semanticTokensProvider)
        (clice-semantic--enable)
      (run-at-time 0.5 nil
                   (lambda (buffer)
                     (when (buffer-live-p buffer)
                       (with-current-buffer buffer
                         (clice-semantic--enable))))
                   (current-buffer)))))

(add-hook 'eglot-managed-mode-hook #'clice-semantic--setup)

(provide 'clice-semantic)

;;; clice-semantic.el ends here
