;;; clice-semantic-test.el --- Tests for clice-semantic  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Code:

(require 'ert)
(require 'clice-semantic)

(ert-deftest clice-semantic-types-extended ()
  "clice's extra token types are in Eglot's list and have faces."
  (dolist (name '("field" "union" "module" "header" "directive"
                  "templateParameter" "typeAlias" "concept"))
    (should (member name eglot-semantic-token-types))
    (should (facep (intern (format "eglot-semantic-%s" name))))))

(ert-deftest clice-semantic-modifiers-extended ()
  "clice's extra modifiers are in Eglot's list and have faces."
  (dolist (name '("local" "member" "virtual" "constexpr" "inactive"))
    (should (member name eglot-semantic-token-modifiers))
    (should (facep (intern (format "eglot-semantic-%s" name))))))

(ert-deftest clice-semantic-extend-is-idempotent ()
  "Extending twice does not duplicate entries."
  (clice-semantic--extend-lists)
  (clice-semantic--extend-lists)
  (should (= 1 (seq-count (lambda (x) (equal x "field"))
                          eglot-semantic-token-types)))
  (should (= 1 (seq-count (lambda (x) (equal x "inactive"))
                          eglot-semantic-token-modifiers))))

(provide 'clice-semantic-test)

;;; clice-semantic-test.el ends here
