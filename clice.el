;;; clice.el --- Eglot support for the clice C/C++ language server  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 gangx

;; Author: gangx
;; URL: https://github.com/qukuqhd/clice.el
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1"))
;; Keywords: languages, tools, c
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; `clice' (https://github.com/clice-io/clice) is a C/C++ language server
;; built on LLVM/Clang.  Eglot already speaks the standard parts of its LSP
;; surface; this package fills the rest:
;;
;;   - registers `clice serve' with Eglot, with the language ids clice knows
;;     (c, cpp, objective-c, objective-c++, cuda-cpp, hip, opencl);
;;   - advertises the client capabilities clice looks for: document links,
;;     folding ranges, selection ranges, and the experimental
;;     `restartServer' flag;
;;   - handles `clice/restartServer', so saving `clice.toml' or switching a
;;     build configuration reconnects the server instead of leaving a
;;     "restart to apply" diagnostic behind;
;;   - provides the clice-specific UI (compilation contexts, build
;;     configurations, header/source counterparts, compile command) in the
;;     `clice-context' library;
;;   - fills Eglot's gaps (document links, folding, selection ranges) in
;;     `clice-links', `clice-fold' and `clice-select';
;;   - extends Eglot's semantic-token faces with clice's richer legend in
;;     `clice-semantic';
;;   - wraps the `clice' CLI in `clice-cli'.
;;
;; Usage:
;;
;;   (require 'clice)
;;   (clice-mode 1)
;;
;; See README.md for details and docs/DESIGN.md for the architecture.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'eglot)
(require 'jsonrpc)

(defgroup clice nil
  "Eglot support for the clice C/C++ language server."
  :group 'tools
  :group 'languages
  :link '(url-link "https://github.com/clice-io/clice")
  :prefix "clice-")

(defcustom clice-executable "clice"
  "Name or path of the clice executable."
  :type 'string
  :group 'clice)

(defcustom clice-server-args '("serve")
  "Arguments passed to `clice-executable' when starting the server."
  :type '(repeat string)
  :group 'clice)

(defcustom clice-auto-restart t
  "Whether to reconnect when clice asks for a restart.
When nil, only report the reason; the user can call
`clice-restart-server' afterwards."
  :type 'boolean
  :group 'clice)

(defcustom clice-auto-enable-links t
  "Whether to enable `clice-links-mode' in clice buffers."
  :type 'boolean
  :group 'clice)

(defcustom clice-auto-enable-fold t
  "Whether to enable `clice-fold-mode' in clice buffers.
This turns `hs-minor-mode' off in those buffers."
  :type 'boolean
  :group 'clice)

(defcustom clice-language-ids
  '((c-mode . "c")
    (c-ts-mode . "c")
    (c++-mode . "cpp")
    (c++-ts-mode . "cpp")
    (objc-mode . "objective-c")
    (objc++-mode . "objective-cpp")
    (cuda-mode . "cuda-cpp")
    (cuda-ts-mode . "cuda-cpp")
    (hip-mode . "hip")
    (opencl-mode . "opencl"))
  "Major modes clice serves, mapped to their LSP language ids."
  :type '(alist :key-type symbol :value-type string)
  :group 'clice)

(declare-function clice-current-server "clice-protocol" (&optional buffer))

(declare-function clice-switch-context "clice-context" ())
(declare-function clice-reset-context "clice-context" ())
(declare-function clice-toggle-other-contexts "clice-context" ())
(declare-function clice-switch-configuration "clice-context" ())
(declare-function clice-switch-counterparts "clice-context" ())
(declare-function clice-show-compile-command "clice-context" ())
(declare-function clice-lint "clice-cli" ())
(declare-function clice-format-check "clice-cli" ())
(declare-function clice-index "clice-cli" ())
(declare-function clice-scan "clice-cli" ())
(declare-function clice-query "clice-cli" (&optional subcommand argument))
(declare-function clice-open-project-config "clice-toml" ())

(defvar-keymap clice-command-map
  :doc "Prefix map for clice commands."
  "c" #'clice-switch-context
  "C" #'clice-switch-configuration
  "r" #'clice-reset-context
  "o" #'clice-toggle-other-contexts
  "h" #'clice-switch-counterparts
  "k" #'clice-show-compile-command
  "R" #'clice-restart-server
  "l" #'clice-lint
  "f" #'clice-format-check
  "i" #'clice-index
  "s" #'clice-scan
  "q" #'clice-query
  "t" #'clice-open-project-config
  "d" #'clice-status)

(defvar clice--setup-p nil
  "Non-nil when `clice-setup' has installed its hooks and advice.")

;;; Server registration

(defun clice--command-p (command)
  "Return non-nil when COMMAND starts the clice server.
COMMAND is a process command line as returned by `process-command'."
  (and (consp command)
       (stringp (car command))
       (let ((exe (file-name-nondirectory (car command))))
         (or (member exe '("clice" "clice.exe"))
             (and (stringp clice-executable)
                  (not (string-empty-p clice-executable))
                  (string= exe (file-name-nondirectory clice-executable)))))))

(defun clice--server-program-entry ()
  "Return the `eglot-server-programs' entry for clice."
  (cons (mapcar (lambda (cell)
                  (list (car cell) :language-id (cdr cell)))
                clice-language-ids)
        (cons clice-executable clice-server-args)))

(defun clice--unregister-server-program ()
  "Remove any clice entry from `eglot-server-programs'."
  (setq eglot-server-programs
        (seq-remove (lambda (entry)
                      (clice--command-p (cdr-safe entry)))
                    eglot-server-programs)))

(defun clice--register-server-program ()
  "Add the clice entry to `eglot-server-programs', replacing old ones."
  (clice--unregister-server-program)
  (add-to-list 'eglot-server-programs (clice--server-program-entry)))

;;; Client capabilities

(defun clice--augment-capabilities (capabilities)
  "Return CAPABILITIES plus what clice needs from its client.
CAPABILITIES is the plist returned by `eglot-client-capabilities'."
  (let* ((capabilities (copy-tree capabilities))
         (text-document (copy-tree (plist-get capabilities :textDocument)))
         (empty '(:dynamicRegistration :json-false)))
    (setq text-document (plist-put text-document :documentLink empty))
    (setq text-document (plist-put text-document :foldingRange empty))
    (setq text-document (plist-put text-document :selectionRange empty))
    (setq capabilities (plist-put capabilities :textDocument text-document))
    ;; clice only sends `clice/restartServer' when the client says it can
    ;; restart the server itself.
    (plist-put capabilities :experimental (list :restartServer t))))

(defun clice--inject-capabilities (orig server)
  "Around `eglot-client-capabilities': augment SERVER's capabilities for clice."
  (let ((capabilities (funcall orig server)))
    (if (clice--server-p server)
        (clice--augment-capabilities capabilities)
      capabilities)))

(defun clice--server-p (server)
  "Return non-nil when SERVER runs the clice server."
  (let ((process (ignore-errors (jsonrpc--process server))))
    (and (processp process)
         (clice--command-p (ignore-errors (process-command process))))))

;;; Restart

(defun clice--reconnect (server)
  "Reconnect SERVER, reporting failures instead of signalling."
  (when (jsonrpc-running-p server)
    (condition-case err
        (eglot-reconnect server)
      (error (message "clice: server restart failed: %s"
                      (error-message-string err))))))

(defun clice--handle-restart-request (server reason)
  "Reconnect SERVER after clice asked for a restart because of REASON."
  (message "clice: %s; restarting the server" (or reason "settings changed"))
  (if clice-auto-restart
      ;; Answer the request first: a reconnect during the process filter
      ;; would kill the connection the reply still needs.
      (run-at-time 0.2 nil #'clice--reconnect server)
    (message "clice: call `clice-restart-server' to apply the change")))

(cl-defmethod eglot-handle-request
  (server (_method (eql clice/restartServer)) &key reason)
  "Handle clice's `clice/restartServer' request."
  (clice--handle-restart-request server reason))

;;;###autoload
(defun clice-restart-server ()
  "Restart the clice server of the current buffer."
  (interactive)
  (let ((server (eglot-current-server)))
    (unless server
      (user-error "No LSP server in this buffer"))
    (if (clice--server-p server)
        (eglot-reconnect server)
      (user-error "The current LSP server is not clice"))))

;;; Version probing

(defun clice--parse-version (string)
  "Parse the first X.Y.Z in STRING into a list of integers."
  (when (and (stringp string)
             (string-match "\\([0-9]+\\)\\.\\([0-9]+\\)\\.\\([0-9]+\\)" string))
    (list (string-to-number (match-string 1 string))
          (string-to-number (match-string 2 string))
          (string-to-number (match-string 3 string)))))

(defun clice-version ()
  "Return the output of \"clice --version\", or nil when unavailable."
  (when (executable-find clice-executable)
    (with-temp-buffer
      (when (zerop (call-process clice-executable nil t nil "--version"))
        (string-trim (buffer-string))))))

;;; Status

;;;###autoload
(defun clice-status ()
  "Describe this buffer's LSP server and clice features."
  (interactive)
  (let* ((buffer (current-buffer))
         (server (ignore-errors (eglot-current-server)))
         (clice-server (and server (clice--server-p server) server))
         (modes (with-current-buffer buffer
                  (delq nil
                        (list (and (bound-and-true-p clice-links-mode) "links")
                              (and (bound-and-true-p clice-fold-mode) "folding")
                              (and (bound-and-true-p eglot-semantic-tokens-mode)
                                   "semantic-tokens")
                              (and (bound-and-true-p eglot-inlay-hints-mode)
                                   "inlay-hints")))))
         (context (with-current-buffer buffer
                    (and (fboundp 'clice--current-context)
                         (ignore-errors (clice--current-context)))))
         (capabilities
          (with-current-buffer buffer
            (delq nil
                  (mapcar
                   (lambda (capability)
                     (and (ignore-errors
                            (eglot-server-capable capability))
                          capability))
                   '(:documentLinkProvider :foldingRangeProvider
                     :selectionRangeProvider :inlayHintProvider
                     :semanticTokensProvider))))))
    (with-current-buffer (get-buffer-create "*clice status*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "Buffer:      %s\n" (buffer-name buffer)))
        (cond
         ((null server)
          (insert "LSP server:  none\n"))
         ((null clice-server)
          (insert (format "LSP server:  %s (not clice)\n"
                          (or (ignore-errors (eglot--server-name server))
                              "unknown"))))
         (t
          (let ((info (eglot--server-info clice-server))
                (command (ignore-errors
                           (process-command (jsonrpc--process clice-server))))
                (project (ignore-errors
                           (project-root (eglot--project clice-server))))
                (languages (ignore-errors (eglot--language-ids clice-server))))
            (insert (format "LSP server:  clice %s\n"
                            (or (plist-get info :version) "?")))
            (insert (format "Command:     %s\n"
                            (if command (string-join command " ") "?")))
            (insert (format "Project:     %s\n" (or project "?")))
            (insert (format "Languages:   %s\n"
                            (string-join
                             (or (delete-dups (copy-sequence languages))
                                 (list "?"))
                             " ")))
            (insert (format "Buffer modes: %s\n"
                            (if modes (string-join modes " ") "none")))
            (if context
                (let ((source (plist-get (plist-get context :command) :source)))
                  (insert (format "Context:     %s (%s%s%s)\n"
                                  (or (plist-get (plist-get context :context)
                                                 :label)
                                      "none")
                                  (if (eq (plist-get context :automatic)
                                          :json-false)
                                      "chosen" "automatic")
                                  (if (eq (plist-get context :otherContexts)
                                          :json-false)
                                      ", other contexts hidden" "")
                                  (if source
                                      (format "; command: %s" source)
                                    ""))))
              (insert "Context:     unavailable\n"))
            (insert (format "Capabilities: %s\n"
                            (string-join
                             (mapcar
                              (lambda (capability)
                                (replace-regexp-in-string
                                 "Provider\\'" ""
                                 (replace-regexp-in-string
                                  "\\`:" "" (symbol-name capability))))
                              capabilities)
                             " ")))))))
      (special-mode)
      (goto-char (point-min))
      (display-buffer (current-buffer)))))

;;; Setup

;;;###autoload
(defun clice--enable-buffer-features ()
  "Enable clice's buffer-local extras in the current buffer."
  (when (and (clice-current-server) (buffer-file-name))
    (when (and clice-auto-enable-links (fboundp 'clice-links-mode))
      (clice-links-mode 1))
    (when (and clice-auto-enable-fold (fboundp 'clice-fold-mode))
      (clice-fold-mode 1))))

(add-hook 'eglot-managed-mode-hook #'clice--enable-buffer-features)

(defun clice-setup ()
  "Install clice's Eglot integration.
Idempotent: safe to call from init files or a mode hook."
  (interactive)
  (require 'clice-protocol)
  (require 'clice-context)
  (require 'clice-links)
  (require 'clice-fold)
  (require 'clice-select)
  (require 'clice-semantic)
  (require 'clice-cli)
  (require 'clice-toml)
  (clice--register-server-program)
  (advice-add 'eglot-client-capabilities :around #'clice--inject-capabilities)
  (setq clice--setup-p t))

(defun clice-unsetup ()
  "Remove clice's Eglot integration."
  (interactive)
  (advice-remove 'eglot-client-capabilities #'clice--inject-capabilities)
  (clice--unregister-server-program)
  (setq clice--setup-p nil))

;;;###autoload
(define-minor-mode clice-mode
  "Global minor mode enabling clice's Eglot integration."
  :global t
  :group 'clice
  (if clice-mode
      (clice-setup)
    (clice-unsetup)))

(provide 'clice)

;;; clice.el ends here
