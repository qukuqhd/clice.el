;;; clice-context-test.el --- Tests for clice-context  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Code:

(require 'ert)
(require 'clice-context)

(defconst clice-test--host-a
  '(:label "int_host.cpp" :description "/p/int_host.cpp"
    :uri "file:///p/int_host.cpp" :occurrence nil :commandHash nil))

(defconst clice-test--host-b
  '(:label "real_host.cpp" :description "/p/real_host.cpp"
    :uri "file:///p/real_host.cpp" :occurrence nil :commandHash "abc"))

(ert-deftest clice-context-candidates-list-and-vector ()
  "Candidates work for both lists and vectors, marking the current one."
  (let* ((current clice-test--host-a)
         (list-cands (clice--context-candidates
                      (list clice-test--host-a clice-test--host-b) current))
         (vector-cands (clice--context-candidates
                        (vector clice-test--host-a clice-test--host-b) current)))
    (should (= 2 (length list-cands)))
    (should (string-prefix-p "✓" (car (car list-cands))))
    (should (string-prefix-p "  " (car (cadr list-cands))))
    (should (equal (mapcar #'car list-cands) (mapcar #'car vector-cands)))))

(ert-deftest clice-context-candidates-deduplicate ()
  "Identical labels get a numeric suffix."
  (let* ((a (copy-sequence clice-test--host-a))
         (b (copy-sequence clice-test--host-a)))
    (setq b (plist-put b :uri "file:///p/other.cpp"))
    (let ((cands (clice--context-candidates (list a b) nil)))
      (should (= 2 (length cands)))
      (should (string-match-p "#2" (car (cadr cands)))))))

(ert-deftest clice-context-same-p ()
  "Context identity uses uri, occurrence and command hash."
  (should (clice--same-context-p clice-test--host-a
                                 (copy-sequence clice-test--host-a)))
  (should-not (clice--same-context-p clice-test--host-a clice-test--host-b))
  (let ((a (plist-put (copy-sequence clice-test--host-a) :occurrence 0))
        (b (plist-put (copy-sequence clice-test--host-a) :occurrence 1)))
    (should-not (clice--same-context-p a b))))

(ert-deftest clice-context-switch-params ()
  "switchContext sends camelCase params and the epoch."
  (let (calls)
    (cl-letf (((symbol-function 'clice--request)
               (lambda (method params &optional _timeout)
                 (push (list method params) calls)
                 '(:success t :stale :json-false))))
      (should (eq (clice--switch-context clice-test--host-b 9 "file:///p/x.h")
                  'success))
      (let ((params (nth 1 (car calls))))
        (should (equal (caar calls) "clice/switchContext"))
        (should (equal (plist-get params :uri) "file:///p/x.h"))
        (should (equal (plist-get params :contextUri) "file:///p/real_host.cpp"))
        (should (equal (plist-get params :commandHash) "abc"))
        (should (= (plist-get params :epoch) 9))
        (should-not (plist-member params :occurrence))))))

(ert-deftest clice-context-switch-stale-retry ()
  "A stale switch re-queries and retries with the new epoch."
  (with-temp-buffer
    (setq buffer-file-name "/tmp/clice-stale.h")
    (let ((switches 0))
      (cl-letf (((symbol-function 'clice--request)
               (lambda (method params &optional _timeout)
                 (pcase method
                   ("clice/switchContext"
                    (setq switches (1+ switches))
                    (if (= switches 1)
                        '(:success :json-false :stale t)
                      '(:success t :stale :json-false)))
                   ("clice/queryContext"
                    (list :contexts (vector clice-test--host-b)
                          :total 1 :epoch 12))
                   (_ nil)))))
        (should (eq (clice--switch-context-retrying clice-test--host-b 3)
                    'success))
        (should (= switches 2))))))

(ert-deftest clice-context-compile-command ()
  "The compile command script quotes arguments and shows provenance."
  (let ((script (clice--compile-command-string
                 "/p/a.cpp"
                 '(:source "host" :from "file:///p/a.cpp"
                   :directory "/p" :arguments ("g++" "-std=c++20" "-c" "/p/a.cpp")
                   :queryFailure nil))))
    (should (string-match-p "source: host" script))
    (should (string-match-p "from: file:///p/a.cpp" script))
    (should (string-match-p "cd /p" script))
    (should (string-match-p "-c /p/a.cpp" script)))
  (let ((script (clice--compile-command-string
                 "/p/a.cpp"
                 '(:source "database" :directory "/p" :arguments ("g++")
                   :queryFailure "no compiler"))))
    (should (string-match-p "compiler query failed: no compiler" script))))

(ert-deftest clice-context-mode-line ()
  "The mode line shows the label and the automatic/manual state."
  (let ((clice-context-mode-line t))
    (let ((clice--context-data
           '(:context (:label "real_host.cpp") :automatic t
             :otherContexts t)))
      (should (string-match-p "real_host" (clice--mode-line-string)))
      (should (string-match-p "clice:" (clice--mode-line-string))))
    (let ((clice--context-data
           '(:context (:label "real_host.cpp") :automatic :json-false
             :otherContexts :json-false)))
      (should (string-match-p "\\*" (clice--mode-line-string)))
      (should (string-match-p "solo" (clice--mode-line-string))))
    (let ((clice--context-data nil))
      (should-not (clice--mode-line-string)))))

(ert-deftest clice-context-project-root ()
  "The project root follows clice.toml/compile_commands.json upwards."
  (let* ((dir (make-temp-file "clice-root-" t))
         (sub (expand-file-name "src" dir)))
    (unwind-protect
        (progn
          (make-directory sub)
          (with-temp-file (expand-file-name "clice.toml" dir) (insert ""))
          (should (equal (file-name-as-directory (file-truename dir))
                         (file-name-as-directory (file-truename
                                                  (clice-project-root sub))))))
      (delete-directory dir t))))

(provide 'clice-context-test)

;;; clice-context-test.el ends here
