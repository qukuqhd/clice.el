;;; clice-context.el --- Compilation contexts and build configurations  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 gangx

;; Author: gangx
;; URL: https://github.com/qukuqhd/clice.el
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;;; Commentary:

;; clice-specific UI built on its custom protocol (see `clice-protocol'):
;;
;;   clice-switch-context          choose the compilation context of a header
;;                                 or a multiply-compiled source file
;;   clice-reset-context           drop the manual choice
;;   clice-toggle-other-contexts   dim/show the code of the other contexts
;;   clice-switch-configuration    choose a build configuration (restarts)
;;   clice-switch-counterparts     header <-> source, interface <-> impl
;;   clice-show-compile-command    show the command the file compiles with
;;
;; Responses are epoch-tagged: a `switchContext' whose epoch no longer
;; matches is rejected with `stale' and must be re-queried.

;;; Code:

(require 'clice-protocol)

;; TODO:
;; - `clice-contexts' struct + `clice--query-contexts' with pagination
;;   (`offset' / `total').
;; - `clice-switch-context' completing-read with the active context marked,
;;   epoch handling and retry on stale.
;; - `clice-current-context' cached per buffer, refreshed on
;;   `eglot-managed-mode-hook', after save and after switching; show it in
;;   the mode line.
;; - `clice-show-compile-command' rendering `command' (source/from/
;;   directory/arguments/query_failure) in a read-only buffer.
;; - `clice-switch-counterparts' using `preferred', else a completing-read
;;   over candidates with their `reasons'.
;; - `clice-list-configurations' / `clice-switch-configuration'.

(provide 'clice-context)

;;; clice-context.el ends here
