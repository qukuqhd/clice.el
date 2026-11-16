;;; clice-toml.el --- clice.toml helpers  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 gangx

;; Author: gangx
;; URL: https://github.com/qukuqhd/clice.el
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;;; Commentary:

;; clice is configured by `clice.toml' (or `.clice/config.toml') at the
;; project root.  The file has a JSON Schema at
;; https://docs.clice.io/clice-config.schema.json; editors that understand
;; `#:schema' comments (taplo, `toml-ts-mode' + schema support) use it.

;;; Code:

;; TODO:
;; - `clice-open-project-config' (find clice.toml / .clice/config.toml
;;   from `project-current', creating a buffer when absent).
;; - `clice-insert-schema-comment' inserting
;;   `#:schema https://docs.clice.io/clice-config.schema.json'.
;; - Associate the file with `toml-ts-mode'.

(provide 'clice-toml)

;;; clice-toml.el ends here
