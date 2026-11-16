;;; clice-context.el --- Compilation contexts and build configurations  -*- lexical-binding: t; -*-

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

;; clice-specific UI built on its custom protocol (see `clice-protocol'):
;;
;;   clice-switch-context          choose the compilation context of a
;;                                 header or a multiply-compiled source file
;;   clice-reset-context           drop the manual choice
;;   clice-toggle-other-contexts   dim/show the code of the other contexts
;;   clice-switch-configuration    choose a build configuration (restarts)
;;   clice-switch-counterparts     header <-> source, interface <-> impl
;;   clice-show-compile-command    show the command the file compiles with
;;
;; The active context is shown in the mode line once a clice buffer is
;; managed by Eglot.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'clice-protocol)

(defcustom clice-context-mode-line t
  "Whether to show the active compilation context in the mode line."
  :type 'boolean
  :group 'clice)

(defcustom clice-context-refresh-on-save t
  "Whether to refresh the context display after saving a buffer."
  :type 'boolean
  :group 'clice)

(defvar-local clice--context-data nil
  "Cached `clice/currentContext' result for this buffer.")

(defvar-local clice--context-mode-line nil
  "Mode-line string for this buffer's compilation context.")

;;; Helpers

(defun clice--json-true-p (value)
  "Return non-nil when VALUE is JSON true."
  (and value (not (eq value :json-false))))

(defun clice--json-bool (value)
  "Return VALUE encoded as a JSON boolean."
  (if value t :json-false))

(defun clice--same-context-p (a b)
  "Return non-nil when context items A and B are the same context."
  (and a b
       (equal (plist-get a :uri) (plist-get b :uri))
       (equal (or (plist-get a :occurrence) 0)
              (or (plist-get b :occurrence) 0))
       (equal (or (plist-get a :commandHash) "")
              (or (plist-get b :commandHash) ""))))

(defun clice--context-display (item &optional active)
  "Return a menu label for context ITEM, marked when ACTIVE."
  (let ((description (plist-get item :description)))
    (concat (if active "✓ " "  ")
            (or (plist-get item :label) "context")
            (if (and description
                     (not (equal description (plist-get item :label))))
                (format "  (%s)" description)
              ""))))

(defun clice--context-candidates (contexts current)
  "Return an alist of (DISPLAY . CONTEXT) for CONTEXTS.
CURRENT is marked with a check mark; duplicate labels get a suffix."
  (let ((seen (make-hash-table :test #'equal))
        (result nil))
    (seq-doseq (item contexts)
      (let* ((base (clice--context-display
                    item (clice--same-context-p item current)))
             (count (puthash base (1+ (gethash base seen 0)) seen))
             (display (if (= count 1) base (format "%s #%d" base count))))
        (push (cons display item) result)))
    (nreverse result)))

;;; Requests

(defun clice--query-contexts (&optional uri offset)
  "Return one page of compilation contexts for URI.
OFFSET is the index of the first context to return."
  (let ((params (append (list :uri (or uri (clice--uri)))
                        (when offset (list :offset offset)))))
    (clice--request "clice/queryContext" params 10)))

(defun clice--all-contexts (&optional uri)
  "Return all compilation contexts for URI, following pagination.
The result is a plist with `:contexts' (a vector), `:total' and `:epoch'."
  (let* ((uri (or uri (clice--uri)))
         (first (clice--query-contexts uri))
         (total (or (plist-get first :total) 0))
         (epoch (plist-get first :epoch))
         (contexts (append (plist-get first :contexts) nil))
         (offset (length contexts))
         (pages 0))
    (while (and (< (length contexts) total)
                (< (setq pages (1+ pages)) 50))
      (let* ((page (clice--query-contexts uri offset))
             (items (append (plist-get page :contexts) nil)))
        (if (null items)
            (setq total (length contexts))
          (setq contexts (append contexts items)
                offset (+ offset (length items))))))
    (list :contexts (vconcat contexts) :total (length contexts) :epoch epoch)))

(defun clice--current-context (&optional uri)
  "Return the `clice/currentContext' result for URI."
  (clice--request "clice/currentContext"
                  (list :uri (or uri (clice--uri))) 10))

(defun clice--switch-context (item epoch &optional uri)
  "Ask clice to switch to context ITEM.
EPOCH is the generation the listing came from.  Return `success',
`stale' or nil."
  (let ((params (append (list :uri (or uri (clice--uri))
                              :contextUri (plist-get item :uri))
                        (when (integerp (plist-get item :occurrence))
                          (list :occurrence (plist-get item :occurrence)))
                        (when-let* ((hash (plist-get item :commandHash)))
                          (list :commandHash hash))
                        (list :epoch epoch))))
    (let ((result (clice--request "clice/switchContext" params 10)))
      (cond ((clice--json-true-p (plist-get result :stale)) 'stale)
            ((clice--json-true-p (plist-get result :success)) 'success)
            (t nil)))))

(defun clice--switch-context-retrying (item epoch)
  "Switch to ITEM, re-querying when the listing went stale."
  (let ((outcome nil)
        (attempts 0))
    (while (and (null outcome) (< attempts 3))
      (setq attempts (1+ attempts))
      (setq outcome (clice--switch-context item epoch))
      (when (eq outcome 'stale)
        (let* ((listing (clice--all-contexts))
               (fresh (seq-find (lambda (candidate)
                                  (clice--same-context-p candidate item))
                                (append (plist-get listing :contexts) nil))))
          (setq epoch (plist-get listing :epoch))
          (if fresh
              (setq item fresh
                    outcome nil)
            (setq outcome 'gone)))))
    outcome))

(defun clice--refresh-context-data (&optional uri)
  "Fetch and cache the current context for URI."
  (setq clice--context-data (clice--current-context uri))
  (clice--update-mode-line)
  clice--context-data)

;;; Mode line

(defun clice--mode-line-string ()
  "Return the mode-line string for the cached context."
  (let* ((context (plist-get clice--context-data :context))
         (label (plist-get context :label))
         (automatic (clice--json-true-p
                     (plist-get clice--context-data :automatic)))
         (other (clice--json-true-p
                 (plist-get clice--context-data :otherContexts)))
         (inactive (plist-get clice--context-data :inactiveChoice)))
    (when (and clice-context-mode-line label)
      (concat " [clice: "
              (truncate-string-to-width label 24 nil nil "…")
              (if automatic "" " *")
              (if other "" " solo")
              (if inactive " pending" "")
              "]"))))

(defun clice--update-mode-line ()
  "Update the buffer-local mode-line string."
  (setq clice--context-mode-line (clice--mode-line-string))
  (force-mode-line-update))

;;; Setup

(defun clice-context-refresh (&optional buffer)
  "Refresh the compilation context shown for BUFFER.
BUFFER defaults to the current buffer.  Errors are ignored: the buffer
may not be initialized yet, or clice may not answer for it."
  (interactive)
  (let ((buffer (or buffer (current-buffer))))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (and (clice-current-server)
                   (buffer-file-name)
                   (eglot-server-capable :hoverProvider))
          (condition-case nil
              (clice--refresh-context-data)
            (error nil)))))))

(defun clice--context-setup ()
  "Set up the context display in the current clice buffer."
  (when (clice-current-server)
    (setq-local mode-line-misc-info
                (cons 'clice--context-mode-line
                      (remove 'clice--context-mode-line mode-line-misc-info)))
    (when clice-context-refresh-on-save
      (add-hook 'after-save-hook #'clice-context-refresh nil t))
    ;; The server may still be initializing when the mode starts.
    (run-at-time 0.5 nil #'clice-context-refresh (current-buffer))))

(add-hook 'eglot-managed-mode-hook #'clice--context-setup)

;;; Commands

(defun clice-switch-context ()
  "Choose the compilation context of the current file."
  (interactive)
  (let* ((uri (clice--uri))
         (listing (clice--all-contexts uri))
         (contexts (append (plist-get listing :contexts) nil))
         (epoch (plist-get listing :epoch))
         (current (ignore-errors
                    (plist-get (clice--current-context uri) :context))))
    (unless (> (length contexts) 1)
      (user-error "clice reports a single compilation context here"))
    (let* ((candidates (clice--context-candidates contexts current))
           (choice (completing-read "Compilation context: "
                                    candidates nil t nil 'clice-context-history))
           (item (cdr (assoc choice candidates)))
           (outcome (clice--switch-context-retrying item epoch)))
      (pcase outcome
        ('success (clice-context-refresh)
                  (message "clice: switched to %s" (plist-get item :label)))
        ('stale (user-error "clice: the contexts changed; please try again"))
        ('gone (user-error "clice: that context no longer exists"))
        (_ (user-error "clice: cannot switch the compilation context"))))))

(defvar clice-context-history nil
  "History of `clice-switch-context' choices.")

(defun clice-reset-context ()
  "Drop the manual compilation-context choice of the current file."
  (interactive)
  (let ((result (clice--request "clice/resetContext"
                                (list :uri (clice--uri)) 10)))
    (if (clice--json-true-p (plist-get result :success))
        (progn (clice-context-refresh)
               (message "clice: back to the automatic context"))
      (user-error "clice: cannot reset the compilation context"))))

(defun clice-toggle-other-contexts ()
  "Show or hide the code of the other compilation contexts."
  (interactive)
  (let* ((uri (clice--uri))
         (data (or clice--context-data (clice--current-context uri)))
         (show (not (clice--json-true-p (plist-get data :otherContexts)))))
    (clice--request "clice/showOtherContexts"
                    (list :uri uri :show (clice--json-bool show))
                    10)
    (clice-context-refresh)
    (message "clice: other contexts %s" (if show "shown" "hidden"))))

(defun clice-switch-configuration ()
  "Choose the build configuration clice runs with."
  (interactive)
  (let* ((uri (clice--uri))
         (listing (clice--request "clice/listConfigurations"
                                  (list :uri uri) 10))
         (configurations (append (plist-get listing :configurations) nil))
         (active (plist-get listing :active))
         (selected (plist-get listing :selected))
         (default (plist-get listing :defaultConfiguration)))
    (unless configurations
      (user-error "clice declares no build configurations"))
    (let* ((prompt (format "Build configuration (active %s%s): "
                           (or active "?")
                           (if selected (format ", selected %s" selected) "")))
           (choice (completing-read prompt configurations nil t nil nil
                                    (or active (car configurations))))
           (result (clice--request "clice/switchConfiguration"
                                   (list :name choice :uri uri)
                                   10)))
      (if (clice--json-true-p (plist-get result :success))
          (message "clice: configuration %s selected%s"
                   choice
                   (if (equal choice (or active default ""))
                       ""
                     "; restarting to apply it"))
        (user-error "clice: %s"
                    (or (plist-get result :reason)
                        "cannot switch the build configuration"))))))

(defun clice-switch-counterparts ()
  "Jump between a header and its source (or module interface and impl)."
  (interactive)
  (let* ((result (clice--request "clice/counterparts"
                                 (list :uri (clice--uri)) 10))
         (candidates (append (plist-get result :candidates) nil))
         (preferred (plist-get result :preferred)))
    (unless candidates
      (user-error "clice knows no counterpart of this file"))
    (if preferred
        (find-file (eglot-uri-to-path preferred))
      (let* ((choices
              (mapcar (lambda (candidate)
                        (cons (format "%s  (%s)"
                                      (file-name-nondirectory
                                       (eglot-uri-to-path
                                        (plist-get candidate :uri)))
                                      (string-join
                                       (append (plist-get candidate :reasons) nil)
                                       ", "))
                              candidate))
                      candidates))
             (choice (completing-read "Counterpart: " choices nil t))
             (target (plist-get (cdr (assoc choice choices)) :uri)))
        (find-file (eglot-uri-to-path target))))))

(defun clice--compile-command-string (file command)
  "Return a shell script for COMMAND, the compile command of FILE."
  (concat
   (format "# %s\n" file)
   (format "# source: %s\n" (or (plist-get command :source) "unknown"))
   (when-let* ((from (plist-get command :from)))
     (format "# from: %s\n" from))
   (when-let* ((failure (plist-get command :queryFailure)))
     (format "# compiler query failed: %s\n" failure))
   "\n"
   (format "cd %s\n" (shell-quote-argument
                      (or (plist-get command :directory) default-directory)))
   (mapconcat #'shell-quote-argument
              (append (plist-get command :arguments) nil)
              " ")
   "\n"))

(defun clice-show-compile-command ()
  "Show the command clice compiles the current file with."
  (interactive)
  (let* ((file (buffer-file-name))
         (data (or clice--context-data (clice--current-context)))
         (command (plist-get data :command)))
    (unless file
      (user-error "This buffer is not visiting a file"))
    (unless command
      (user-error "clice has no compile command for this file"))
    (with-current-buffer (get-buffer-create
                          (format "*clice compile command: %s*"
                                  (file-name-nondirectory file)))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (clice--compile-command-string file command)))
      (special-mode)
      (setq default-directory (or (plist-get command :directory)
                                  default-directory))
      (goto-char (point-min))
      (display-buffer (current-buffer)))))

(provide 'clice-context)

;;; clice-context.el ends here
