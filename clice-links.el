;;; clice-links.el --- Document links rendered with overlays  -*- lexical-binding: t; -*-

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

;; Eglot does not implement `textDocument/documentLink'.  clice uses it for
;; `#include'/`#include_next'/`__has_include' and `#embed' targets, so header
;; names become clickable here: RET or mouse-2 opens the target.
;;
;; Links are overlays; they move with edits and are refreshed after saving
;; and shortly after the buffer changes.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'clice-protocol)

(defcustom clice-links-auto-refresh t
  "Whether to refresh document links automatically after edits."
  :type 'boolean
  :group 'clice)

(defface clice-link-face
  '((t :inherit link :underline t))
  "Face for clice document links."
  :group 'clice)

(defvar clice-links-mode)

(defvar-local clice--link-overlays nil
  "Overlays rendering the current document links.")

(defvar-local clice--links-refresh-timer nil
  "Pending refresh timer for the current buffer.")

(defvar-keymap clice-link-map
  :doc "Keymap for clice document links."
  "RET" #'clice-open-link-at-point
  "<mouse-2>" #'clice-open-link-at-mouse
  "<mouse-1>" #'clice-open-link-at-mouse)

(defun clice--link-at (position)
  "Return the document-link overlay at POSITION."
  (seq-find (lambda (overlay)
              (overlay-get overlay 'clice--link-target))
            (overlays-at position)))

(defun clice--open-link (overlay)
  "Open the target of document-link OVERLAY."
  (when-let* ((target (overlay-get overlay 'clice--link-target)))
    (find-file (eglot-uri-to-path target))))

(defun clice-open-link-at-point ()
  "Open the clice document link at point."
  (interactive)
  (if-let* ((overlay (clice--link-at (point))))
      (clice--open-link overlay)
    (user-error "No clice document link here")))

(defun clice-open-link-at-mouse (event)
  "Open the clice document link clicked in EVENT."
  (interactive "e")
  (let ((position (posn-point (event-start event))))
    (if-let* ((overlay (clice--link-at position)))
        (clice--open-link overlay)
      (user-error "No clice document link here"))))

(defun clice--links-clear ()
  "Delete all document-link overlays in the current buffer."
  (mapc #'delete-overlay clice--link-overlays)
  (setq clice--link-overlays nil))

(defun clice--link-pos (lsp-position)
  "Convert LSP-POSITION to a buffer position."
  (eglot--lsp-position-to-point lsp-position))

(defun clice-links-refresh (&optional buffer)
  "Refresh the document links of BUFFER.
BUFFER defaults to the current buffer."
  (interactive)
  (let ((buffer (or buffer (current-buffer))))
    (when (and (buffer-live-p buffer)
               (buffer-local-value 'clice-links-mode buffer)
               (with-current-buffer buffer
                 (and (clice-current-server)
                      (buffer-file-name))))
      (with-current-buffer buffer
        (when (eglot-server-capable :documentLinkProvider)
          (condition-case nil
              (let ((links (append
                            (clice--request
                             "textDocument/documentLink"
                             (list :textDocument (list :uri (clice--uri)))
                             10)
                            nil)))
                (clice--links-clear)
                (dolist (link links)
                  (let* ((range (plist-get link :range))
                         (start (clice--link-pos (plist-get range :start)))
                         (end (clice--link-pos (plist-get range :end)))
                         (target (plist-get link :target)))
                    (when (and target (< start end))
                      (let ((overlay (make-overlay start end nil t)))
                        (overlay-put overlay 'clice--link-target target)
                        (overlay-put overlay 'face 'clice-link-face)
                        (overlay-put overlay 'mouse-face 'highlight)
                        (overlay-put overlay 'keymap clice-link-map)
                        (overlay-put overlay 'help-echo target)
                        (overlay-put overlay 'evaporate t)
                        (push overlay clice--link-overlays))))))
            (error nil)))))))

(defun clice--links-schedule-refresh (&rest _)
  "Schedule a debounced document-link refresh."
  (when (and clice-links-mode clice-links-auto-refresh)
    (when (timerp clice--links-refresh-timer)
      (cancel-timer clice--links-refresh-timer))
    (setq clice--links-refresh-timer
          (run-at-time 0.8 nil #'clice-links-refresh (current-buffer)))))

(defun clice--links-cleanup ()
  "Stop timers and delete overlays when the mode is disabled."
  (when (timerp clice--links-refresh-timer)
    (cancel-timer clice--links-refresh-timer))
  (setq clice--links-refresh-timer nil)
  (clice--links-clear))

;;;###autoload
(define-minor-mode clice-links-mode
  "Show clice document links as clickable overlays."
  :lighter " clice-links"
  :group 'clice
  (if clice-links-mode
      (progn
        (add-hook 'after-save-hook #'clice-links-refresh nil t)
        (add-hook 'after-change-functions #'clice--links-schedule-refresh nil t)
        ;; The server may still be initializing when the mode is enabled.
        (run-at-time 0.5 nil #'clice-links-refresh (current-buffer)))
    (remove-hook 'after-save-hook #'clice-links-refresh t)
    (remove-hook 'after-change-functions #'clice--links-schedule-refresh t)
    (clice--links-cleanup)))

(provide 'clice-links)

;;; clice-links.el ends here
