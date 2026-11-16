;;; clice-integration-test.el --- Tests against a real clice server  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 gangx

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; End-to-end tests: each test copies a fixture project from
;; `test/fixtures', writes a compilation database, starts `clice serve'
;; through Eglot and exercises one group of clice features.  Tests are
;; skipped when clice is not installed.

;;; Code:

(require 'ert)
(require 'clice-test-helpers)

;; Keep tests deterministic: enable the buffer-local extras explicitly where
;; they are under test instead of relying on background timers.
(setq clice-auto-enable-links nil
      clice-auto-enable-fold nil
      clice-context-auto-refresh nil
      clice-context-refresh-on-save nil)

(defconst clice-integration--basics-db
  '("src/main.cpp" "src/shapes.cpp" "src/diagnostics.cpp"
    "src/code_action.cpp" "src/format.cpp")
  "Compilation database of the basics fixture.")

(defconst clice-integration--contexts-db
  '("fast_host.cpp" "slow_host.cpp")
  "Compilation database of the contexts fixture.")

(defvar clice-integration--restart-reason nil
  "Reason of the last `clice/restartServer' request seen by a test.")

(defun clice-integration--record-restart (_server reason)
  "Record REASON for a test."
  (setq clice-integration--restart-reason reason))

(defun clice-integration--labels (result key)
  "Return KEY from every plist in RESULT (a vector or list)."
  (mapcar (lambda (item) (plist-get item key)) (append result nil)))

(defun clice-integration--symbol-names (symbols)
  "Flatten the :name of SYMBOLS and their :children."
  (mapcan (lambda (symbol)
            (cons (plist-get symbol :name)
                  (clice-integration--symbol-names
                   (plist-get symbol :children))))
          (append symbols nil)))

(defun clice-integration--inlay-text (hints)
  "Flatten the labels of HINTS into a string."
  (mapconcat
   (lambda (hint)
     (let ((label (plist-get hint :label)))
       (if (stringp label)
           label
         (mapconcat (lambda (part) (or (plist-get part :value) ""))
                    (append label nil) ""))))
   (append hints nil) " "))

;;; Tests

(ert-deftest clice-integration-connect-and-capabilities ()
  "Clice is detected, and its capabilities reach Eglot."
  (skip-unless (executable-find clice-executable))
  (let* ((dir (clice-test--project "basics" clice-integration--basics-db))
         (file (expand-file-name "src/main.cpp" dir))
         (server nil))
    (unwind-protect
        (progn
          (setq server (clice-test--connect file))
          (with-current-buffer (find-file-noselect file)
            (should (clice-current-server))
            (dolist (capability '(:documentLinkProvider :foldingRangeProvider
                                  :selectionRangeProvider :inlayHintProvider
                                  :semanticTokensProvider :callHierarchyProvider
                                  :typeHierarchyProvider))
              (should (eglot-server-capable capability)))))
      (clice-test--cleanup server dir))))

(ert-deftest clice-integration-completion-hover-signature-navigation ()
  "Completion, hover, signature help and navigation work."
  (skip-unless (executable-find clice-executable))
  (let* ((dir (clice-test--project "basics" clice-integration--basics-db))
         (file (expand-file-name "src/main.cpp" dir))
         (header (expand-file-name "include/shapes.h" dir))
         (server nil))
    (unwind-protect
        (progn
          (clice-test--index dir)
          (setq server (clice-test--connect file))
          ;; Completion after shapes::
          (let* ((result (clice-test--request
                          file "textDocument/completion"
                          (list :textDocument (list :uri (clice-test--uri file))
                                :position (clice-test--position file "shapes::" 1 t))))
                 (labels (clice-integration--labels (plist-get result :items) :label)))
            (dolist (expected '("Circle" "Point" "distance" "Shape"))
              (should (member expected labels))))
          ;; Hover
          (let* ((result (clice-test--request
                          file "textDocument/hover"
                          (list :textDocument (list :uri (clice-test--uri file))
                                :position (clice-test--position file "distance(a"))))
                 (value (plist-get (plist-get result :contents) :value)))
            (should (stringp value))
            (should (string-match-p "distance" value)))
          ;; Signature help
          (let* ((result (clice-test--request
                          file "textDocument/signatureHelp"
                          (list :textDocument (list :uri (clice-test--uri file))
                                :position (clice-test--position file "distance(" 1 t))))
                 (signatures (plist-get result :signatures)))
            (should (> (length signatures) 0))
            (should (string-match-p "distance"
                                    (plist-get (aref signatures 0) :label))))
          ;; Definition, references, implementation, type definition
          (let ((definitions (clice-test--request
                              file "textDocument/definition"
                              (list :textDocument (list :uri (clice-test--uri file))
                                    :position (clice-test--position file "distance(a")))))
            (should (= 1 (length (append definitions nil))))
            (should (string-match-p "shapes\\.\\(h\\|cpp\\)"
                                    (plist-get (aref definitions 0) :uri))))
          (let ((references (clice-test--request
                             file "textDocument/references"
                             (list :textDocument (list :uri (clice-test--uri file))
                                   :position (clice-test--position file "distance(a")
                                   :context (list :includeDeclaration t)))))
            (should (>= (length references) 3))
            (let ((uris (clice-integration--labels references :uri)))
              (should (seq-some (lambda (uri) (string-match-p "main\\.cpp" uri)) uris))
              (should (seq-some (lambda (uri) (string-match-p "shapes\\.cpp" uri)) uris))))
          ;; Document highlights, workspace symbols, call and type hierarchy.
          (let ((highlights (clice-test--request
                             file "textDocument/documentHighlight"
                             (list :textDocument (list :uri (clice-test--uri file))
                                   :position (clice-test--position file "total = sum")))))
            (should (> (length (append highlights nil)) 0)))
          (let* ((symbols (clice-test--request
                           file "workspace/symbol" (list :query "distance")))
                 (names (clice-integration--labels symbols :name)))
            (should (member "distance" names)))
          (let* ((prepared (clice-test--request
                            file "textDocument/prepareCallHierarchy"
                            (list :textDocument (list :uri (clice-test--uri file))
                                  :position (clice-test--position file "sum(v)"))))
                 (item (and (> (length (append prepared nil)) 0)
                            (aref prepared 0))))
            (should item)
            (should (equal (plist-get item :name) "sum"))
            (let ((incoming (clice-test--request
                             file "callHierarchy/incomingCalls"
                             (list :item item))))
              (should (> (length (append incoming nil)) 0))))
          (let* ((prepared (clice-test--request
                            header "textDocument/prepareTypeHierarchy"
                            (list :textDocument (list :uri (clice-test--uri header))
                                  :position (clice-test--position header "Circle :"))))
                 (item (and (> (length (append prepared nil)) 0)
                            (aref prepared 0))))
            (should item)
            (should (equal (plist-get item :name) "Circle"))
            (let ((supertypes (clice-test--request
                               header "typeHierarchy/supertypes"
                               (list :item item))))
              (should (seq-some (lambda (entry)
                                  (string-match-p "Shape"
                                                  (plist-get entry :name)))
                                (append supertypes nil)))))
          (let ((implementation
                 (clice-test--request
                  header "textDocument/implementation"
                  (list :textDocument (list :uri (clice-test--uri header))
                        :position (clice-test--position
                                   header "area() const = 0")))))
            (should (= 1 (length (append implementation nil))))
            (should (string-match-p "shapes\\.cpp"
                                    (plist-get (aref implementation 0) :uri)))))
      (clice-test--cleanup server dir))))

(ert-deftest clice-integration-rename-symbols-diagnostics-actions ()
  "Rename, document symbols, diagnostics and code actions work."
  (skip-unless (executable-find clice-executable))
  (let* ((dir (clice-test--project "basics" clice-integration--basics-db))
         (file (expand-file-name "src/main.cpp" dir))
         (broken (expand-file-name "src/diagnostics.cpp" dir))
         (action-file (expand-file-name "src/code_action.cpp" dir))
         (server nil))
    (unwind-protect
        (progn
          (clice-test--index dir)
          (setq server (clice-test--connect file))
          ;; Rename across files.
          (let* ((result (clice-test--request
                          file "textDocument/rename"
                          (list :textDocument (list :uri (clice-test--uri file))
                                :position (clice-test--position file "distance(a")
                                :newName "distance2")))
                 (changes (append (plist-get result :documentChanges) nil)))
            (should (= 3 (length changes)))
            (dolist (change changes)
              (let ((edits (append (plist-get change :edits) nil)))
                (should edits)
                (dolist (edit edits)
                  (should (equal (plist-get edit :newText) "distance2"))))))
          ;; Document symbols.
          (let* ((symbols (clice-test--request
                           file "textDocument/documentSymbol"
                           (list :textDocument (list :uri (clice-test--uri file)))))
                 (names (clice-integration--labels symbols :name)))
            (should (member "sum" names))
            (should (member "main" names)))
          (let* ((symbols (clice-test--request
                           (expand-file-name "include/shapes.h" dir)
                           "textDocument/documentSymbol"
                           (list :textDocument
                                 (list :uri (clice-test--uri
                                             (expand-file-name "include/shapes.h" dir))))))
                 (names (clice-integration--symbol-names symbols)))
            (dolist (expected '("Point" "Shape" "Circle" "distance"))
              (should (member expected names))))
          ;; Diagnostics (pull).
          (let* ((result (clice-test--pull-diagnostics broken))
                 (items (append (plist-get result :items) nil)))
            (should items)
            (should (seq-some (lambda (item)
                                (string-match-p "undeclared_symbol"
                                                (plist-get item :message)))
                              items)))
          ;; Code action: add the missing <vector> include.
          (let* ((result (clice-test--request
                          action-file "textDocument/codeAction"
                          (list :textDocument (list :uri (clice-test--uri action-file))
                                :range (clice-test--range action-file "std::vector")
                                :context (list :diagnostics []))))
                 (actions (append result nil)))
            (should actions)
            (let ((action (seq-find
                           (lambda (candidate)
                             (string-match-p "include <vector>"
                                             (plist-get candidate :title)))
                           actions)))
              (should action)
              (should (equal (plist-get action :kind) "quickfix"))
              (let* ((change (aref (plist-get (plist-get action :edit)
                                              :documentChanges)
                                   0))
                     (edit (aref (plist-get change :edits) 0)))
                (should (string-match-p "#include <vector>"
                                        (plist-get edit :newText)))))))
      (clice-test--cleanup server dir))))

(ert-deftest clice-integration-semantic-inlay-formatting ()
  "Semantic tokens, inlay hints and formatting work."
  (skip-unless (executable-find clice-executable))
  (let* ((dir (clice-test--project "basics" clice-integration--basics-db))
         (file (expand-file-name "src/main.cpp" dir))
         (format-file (expand-file-name "src/format.cpp" dir))
         (server nil))
    (unwind-protect
        (progn
          (setq server (clice-test--connect file))
          ;; Semantic tokens.
          (let* ((result (clice-test--request
                          file "textDocument/semanticTokens/full"
                          (list :textDocument (list :uri (clice-test--uri file)))))
                 (data (plist-get result :data)))
            (should (> (length data) 50)))
          ;; Inlay hints.
          (let* ((result (clice-test--request
                          file "textDocument/inlayHint"
                          (list :textDocument (list :uri (clice-test--uri file))
                                :range (list :start (list :line 0 :character 0)
                                             :end (list :line 40 :character 0)))))
                 (text (clice-integration--inlay-text result)))
            (should (> (length (append result nil)) 0))
            (should (string-match-p "values" text)))
          ;; Range formatting.
          (let ((edits (clice-test--request
                        format-file "textDocument/rangeFormatting"
                        (list :textDocument (list :uri (clice-test--uri format-file))
                              :range (list :start (list :line 0 :character 0)
                                           :end (list :line 2 :character 1))
                              :options (list :tabSize 4 :insertSpaces t)))))
            (should (> (length (append edits nil)) 0)))
          ;; Formatting through Eglot.
          (clice-test--manage format-file)
          (should (clice-test--wait
                   (lambda ()
                     (with-current-buffer (find-file-noselect format-file)
                       (eglot-server-capable :documentFormattingProvider)))
                   30))
          (with-current-buffer (find-file-noselect format-file)
            (eglot-format-buffer)
            (should (string-match-p "int messy(int a, int b)"
                                    (buffer-string)))
            (should-not (string-match-p "int  messy" (buffer-string)))))
      (clice-test--cleanup server dir))))

(ert-deftest clice-integration-links-fold-selection ()
  "Document links, folding and selection ranges work end to end."
  (skip-unless (executable-find clice-executable))
  (let* ((dir (clice-test--project "basics" clice-integration--basics-db))
         (file (expand-file-name "src/main.cpp" dir))
         (server nil))
    (unwind-protect
        (progn
          (setq server (clice-test--connect file))
          (with-current-buffer (find-file-noselect file)
            (clice-links-mode 1)
            (clice-fold-mode 1)
            ;; Links: the project header and the __has_include probe.
            (should (clice-test--wait
                     (lambda () (and clice-links-mode
                                     (>= (length clice--link-overlays) 2)))
                     30))
            (let ((targets (mapcar (lambda (overlay)
                                     (overlay-get overlay 'clice--link-target))
                                   clice--link-overlays)))
              (should (seq-some (lambda (target)
                                  (string-match-p "shapes\\.h" target))
                                targets))
              (should (seq-some (lambda (target)
                                  (string-match-p "vector" target))
                                targets)))
            ;; Folding.
            (should (clice-test--wait
                     (lambda () (> (length clice--fold-overlays) 0)) 30))
            (let* ((cell (car (sort (copy-sequence clice--fold-overlays)
                                    (lambda (a b)
                                      (< (overlay-start (cdr a))
                                         (overlay-start (cdr b)))))))
                   (overlay (cdr cell)))
              (goto-char (overlay-start overlay))
              (clice-toggle-fold)
              (should (overlay-get overlay 'invisible))
              (clice-unfold-all)
              (should-not (overlay-get overlay 'invisible)))
            ;; Selection ranges.
            (clice-selection-range-reset)
            (goto-char (point-min))
            (search-forward "sum(v)")
            (goto-char (match-beginning 0))
            (clice-expand-region)
            (let ((first (cons (region-beginning) (region-end))))
              (clice-expand-region)
              (let ((second (cons (region-beginning) (region-end))))
                (should (>= (- (cdr second) (car second))
                            (- (cdr first) (car first))))
                (should (> clice--selection-index 0)))
              (clice-contract-region)
              (should (= clice--selection-index 0)))))
      (clice-test--cleanup server dir))))

(ert-deftest clice-integration-contexts-and-inactive ()
  "Contexts, inactive dimming, counterparts and compile commands work."
  (skip-unless (executable-find clice-executable))
  (let* ((dir (clice-test--project "contexts" clice-integration--contexts-db))
         (fast (expand-file-name "fast_host.cpp" dir))
         (slow (expand-file-name "slow_host.cpp" dir))
         (header (expand-file-name "shared.h" dir))
         (server nil))
    (unwind-protect
        (progn
          (clice-test--index dir)
          (setq server (clice-test--connect fast))
          (clice-test--manage slow)
          (clice-test--pull-diagnostics fast)
          (clice-test--pull-diagnostics slow)
          (with-current-buffer (find-file-noselect header)
            (eglot-ensure)
            (run-hooks 'post-command-hook)
            (should (clice-test--wait
                     (lambda ()
                       (= 2 (length (append (plist-get (clice--all-contexts)
                                                       :contexts)
                                            nil))))
                     30))
            (let* ((listing (clice--all-contexts))
                   (contexts (append (plist-get listing :contexts) nil))
                   (labels (mapcar (lambda (item) (plist-get item :label))
                                   contexts))
                   (target (seq-find (lambda (item)
                                       (string-match-p "slow_host"
                                                       (plist-get item :label)))
                                     contexts)))
              (should (equal (sort labels #'string<)
                             '("fast_host.cpp" "slow_host.cpp")))
              (should target)
              ;; The inactive branch is flagged by the semantic tokens;
              ;; the tokens settle once both hosts contributed.
              (should
               (clice-test--wait
                (lambda ()
                  (let* ((result (clice--request
                                  "textDocument/semanticTokens/full"
                                  (list :textDocument (list :uri (clice--uri))) 20))
                         (data (plist-get result :data))
                         (index (clice-test--token-modifier-index
                                 (current-buffer) "inactive")))
                    (and index (clice-test--token-has-modifier-p data index))))
                20))
              ;; Switch, toggle other contexts, reset.
              (should (eq (clice--switch-context-retrying
                           target (plist-get listing :epoch))
                          'success))
              (clice-context-refresh)
              (let ((current (clice--current-context)))
                (should (string-match-p "slow_host"
                                        (plist-get (plist-get current :context)
                                                   :label)))
                (should-not (clice--json-true-p
                             (plist-get current :automatic))))
              (let ((before (clice--json-true-p
                             (plist-get (clice--current-context) :otherContexts))))
                (clice-toggle-other-contexts)
                (should (not (eq before
                                 (clice--json-true-p
                                  (plist-get (clice--current-context)
                                             :otherContexts))))))
              ;; Compile command.
              (clice-show-compile-command)
              (with-current-buffer (get-buffer "*clice compile command: shared.h*")
                (let ((text (buffer-substring-no-properties (point-min)
                                                            (point-max))))
                  (should (string-match-p "# source: " text))
                  (should (string-match-p "# from: " text))))
              ;; Counterparts.
              (should (clice-test--wait
                       (lambda ()
                         (let ((result (clice--request
                                        "clice/counterparts"
                                        (list :uri (clice--uri)) 10)))
                           (= 2 (length (append (plist-get result :candidates)
                                                nil)))))
                       20))
              (clice-reset-context)
              (should (clice--json-true-p
                       (plist-get (clice--current-context) :automatic)))))
      (clice-test--cleanup server dir)))))

(ert-deftest clice-integration-build-configurations ()
  "Build configurations are listed, selectable, and ask for a restart."
  (skip-unless (executable-find clice-executable))
  (let* ((dir (clice-test--fixture "configs"))
         (file (expand-file-name "main.cpp" dir))
         (server nil)
         (clice-auto-restart nil)
         (clice-integration--restart-reason nil))
    ;; One database per configuration; both list the same source.
    (clice-test--database dir '("main.cpp"))
    (dolist (configuration '("debug" "release"))
      (make-directory (expand-file-name (format "out/%s" configuration) dir) t)
      (copy-file (expand-file-name "compile_commands.json" dir)
                 (expand-file-name (format "out/%s/compile_commands.json"
                                           configuration)
                                   dir)
                 t))
    (delete-file (expand-file-name "compile_commands.json" dir))
    (advice-add 'clice--handle-restart-request :before
                #'clice-integration--record-restart)
    (unwind-protect
        (progn
          (setq server (clice-test--connect file))
          (with-current-buffer (find-file-noselect file)
            (let ((listing (clice--request "clice/listConfigurations"
                                           (list :uri (clice--uri)) 10)))
              (should (equal (sort (append (plist-get listing :configurations)
                                           nil)
                                   #'string<)
                             '("debug" "release")))
              (should (equal (plist-get listing :active) "debug"))
              (should (equal (plist-get listing :defaultConfiguration)
                             "debug")))
            (cl-letf (((symbol-function 'completing-read)
                       (lambda (&rest _) "release")))
              (clice-switch-configuration))
            (should (clice-test--wait
                     (lambda () clice-integration--restart-reason) 15))
            (should (string-match-p "release"
                                    clice-integration--restart-reason))
            (let ((listing (clice--request "clice/listConfigurations"
                                           (list :uri (clice--uri)) 10)))
              (should (equal (plist-get listing :selected) "release")))))
      (advice-remove 'clice--handle-restart-request
                     #'clice-integration--record-restart)
      (clice-test--cleanup server dir))))

(ert-deftest clice-integration-modules ()
  "C++20 modules resolve across translation units."
  (skip-unless (executable-find clice-executable))
  (skip-unless (executable-find "clang++"))
  (let* ((dir (clice-test--project
               "modules"
               (list (cons "math.ixx"
                           '(:arguments ("clang++" "-std=c++20"
                                         "-x" "c++-module" "-fsyntax-only")))
                     (cons "main.cpp"
                           '(:arguments ("clang++" "-std=c++20"
                                         "-fsyntax-only"))))))
         (file (expand-file-name "main.cpp" dir))
         (server nil))
    (unwind-protect
        (progn
          (setq server (clice-test--connect file))
          (let* ((result (clice-test--request
                          file "textDocument/hover"
                          (list :textDocument (list :uri (clice-test--uri file))
                                :position (clice-test--position file "add(1"))))
                 (value (plist-get (plist-get result :contents) :value)))
            (should (string-match-p "add" value)))
          (let ((definitions (clice-test--request
                              file "textDocument/definition"
                              (list :textDocument (list :uri (clice-test--uri file))
                                    :position (clice-test--position file "add(1")))))
            (should (= 1 (length (append definitions nil))))
            (should (string-match-p "math\\.ixx"
                                    (plist-get (aref definitions 0) :uri))))
          (let* ((result (clice-test--request
                          file "textDocument/completion"
                          (list :textDocument (list :uri (clice-test--uri file))
                                :position (clice-test--position file "add(1"))))
                 (labels (clice-integration--labels (plist-get result :items)
                                                    :label)))
            (should (member "add" labels))))
      (clice-test--cleanup server dir))))

(ert-deftest clice-integration-forced-include ()
  "A command's -include is honoured."
  (skip-unless (executable-find clice-executable))
  (let* ((dir (clice-test--project
               "forced_include"
               (list (cons "main.cpp"
                           '(:command
                             "g++ -std=c++20 -include ${ROOT}/config.h -fsyntax-only ${FILE}")))))
         (file (expand-file-name "main.cpp" dir))
         (server nil))
    (unwind-protect
        (progn
          (setq server (clice-test--connect file))
          (let* ((result (clice-test--request
                          file "textDocument/hover"
                          (list :textDocument (list :uri (clice-test--uri file))
                                :position (clice-test--position file "CONFIG_VALUE"))))
                 (value (plist-get (plist-get result :contents) :value)))
            (should (string-match-p "CONFIG_VALUE" value)))
          (let* ((result (clice-test--pull-diagnostics file))
                 (items (append (plist-get result :items) nil)))
            (should-not items)))
      (clice-test--cleanup server dir))))

(ert-deftest clice-integration-cli-tools ()
  "The CLI wrappers and JSON helpers work on a real project."
  (skip-unless (executable-find clice-executable))
  (let* ((dir (clice-test--project "basics" clice-integration--basics-db))
         (file (expand-file-name "src/main.cpp" dir))
         (default-directory dir))
    (unwind-protect
        (progn
          (clice-test--index dir)
          ;; scan --json
          (let* ((result (clice--json-command '("scan" "--json")))
                 (paths (clice-integration--labels (plist-get result :files)
                                                   :path)))
            (should (seq-some (lambda (path)
                                (string-match-p "src/main\\.cpp" path))
                              paths)))
          ;; lint --json
          (let* ((result (clice--json-command '("lint" "--json")))
                 (findings (append (plist-get result :findings) nil)))
            (should findings)
            (should (seq-some (lambda (finding)
                                (and (string-match-p "diagnostics\\.cpp"
                                                     (plist-get finding :file))
                                     (string-match-p "undeclared_symbol"
                                                     (plist-get finding :message))))
                              findings)))
          ;; query wrapper
          (clice-query "project-files")
          (with-current-buffer (get-buffer "*clice query project-files*")
            (should (string-match-p "src/main\\.cpp" (buffer-string)))
            (kill-buffer)))
      (ignore-errors (delete-directory dir t)))))

(provide 'clice-integration-test)

;;; clice-integration-test.el ends here
