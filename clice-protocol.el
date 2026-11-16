;;; clice-protocol.el --- clice protocol helpers for Eglot  -*- lexical-binding: t; -*-

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

;; Thin layer over Eglot for the custom `clice/*' requests.  Keeping the
;; use of Eglot internals (`eglot--request', `eglot-current-server') in one
;; file makes it cheap to adapt when Eglot changes.
;;
;; clice's custom methods (see docs/PROTOCOL.md and clice's
;; src/server/extension.cppm):
;;
;;   clice/queryContext        list a file's compilation contexts
;;   clice/currentContext      active context, compile command, epoch
;;   clice/switchContext       choose a context (epoch-checked)
;;   clice/resetContext        back to the automatic context
;;   clice/showOtherContexts   show/dim other contexts' code
;;   clice/listConfigurations  list build configurations
;;   clice/switchConfiguration choose a build configuration (needs restart)
;;   clice/counterparts        header/source, interface/implementation pairs
;;   clice/restartServer       server -> client restart request

;;; Code:

(require 'clice)
(require 'eglot)

(defun clice-current-server (&optional buffer)
  "Return the clice server managing BUFFER, or nil.
BUFFER defaults to the current buffer."
  (with-current-buffer (or buffer (current-buffer))
    (let ((server (ignore-errors (eglot-current-server))))
      (and server (clice--server-p server) server))))

(defun clice--server-or-lose (&optional buffer)
  "Return the clice server for BUFFER or signal a user error."
  (or (clice-current-server buffer)
      (user-error "No clice server in this buffer")))

(defun clice--request (method params &optional timeout)
  "Send METHOD with PARAMS to the current clice server.
TIMEOUT, when non-nil, aborts the request after that many seconds."
  (eglot--request (clice--server-or-lose) method params :timeout timeout))

(defun clice--notify (method params)
  "Send notification METHOD with PARAMS to the current clice server."
  (jsonrpc-notify (clice--server-or-lose) method params))

(defun clice--capability (name)
  "Return clice's server capability NAME, or nil."
  (clice--server-or-lose)
  (eglot-server-capable name))

(defun clice--supports-p (&rest capabilities)
  "Return non-nil when clice advertises every capability in CAPABILITIES."
  (clice--server-or-lose)
  (apply #'eglot-server-capable capabilities))

(defun clice--uri (&optional buffer)
  "Return the file URI of BUFFER, defaulting to the current buffer."
  (let ((file (buffer-file-name (or buffer (current-buffer)))))
    (unless file
      (user-error "This buffer is not visiting a file"))
    (eglot-path-to-uri file)))

(defun clice-project-root (&optional directory)
  "Return the clice project root for DIRECTORY.
DIRECTORY defaults to `default-directory'.  Looks for `clice.toml',
`.clice/config.toml' or `compile_commands.json' upwards, then falls back
to the Emacs project root and finally to DIRECTORY itself."
  (let* ((directory (file-name-as-directory
                     (expand-file-name (or directory default-directory))))
         (root (or (locate-dominating-file directory "clice.toml")
                   (locate-dominating-file directory ".clice/config.toml")
                   (locate-dominating-file directory "compile_commands.json")
                   (when-let* ((project (ignore-errors (project-current nil directory))))
                     (project-root project))
                   directory)))
    (file-name-as-directory (expand-file-name root))))

(provide 'clice-protocol)

;;; clice-protocol.el ends here
