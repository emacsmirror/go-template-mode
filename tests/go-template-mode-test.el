;;; go-template-mode-test.el --- Tests for go-template-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Robert Charusta

;; Author: Robert Charusta <rch-public@posteo.net>
;; URL: https://codeberg.org/rch/go-template-mode
;; Package-Requires: ((emacs "28.1"))

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
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
;; along with this program.  If not, see
;; <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Behavioral and regression tests for `go-template-mode'.

;;; Code:

(require 'ert)
(require 'go-template-mode)

(defconst go-template-mode-test--template-faces
  '(font-lock-builtin-face
    font-lock-comment-face
    font-lock-constant-face
    font-lock-function-name-face
    font-lock-keyword-face
    font-lock-preprocessor-face
    font-lock-string-face
    font-lock-variable-name-face)
  "Faces whose accidental use outside template actions is tested.")

(defun go-template-mode-test--face-p (pos face)
  "Return non-nil when FACE is applied at POS."
  (let ((value (get-char-property pos 'face)))
    (if (listp value)
        (memq face value)
      (eq value face))))

(defun go-template-mode-test--position (text &optional occurrence)
  "Return the start of OCCURRENCE of TEXT in the current buffer."
  (let ((remaining (or occurrence 1)))
    (save-excursion
      (goto-char (point-min))
      (while (and (> remaining 0) (search-forward text nil t))
        (setq remaining (1- remaining)))
      (if (zerop remaining)
          (- (point) (length text))
        (ert-fail (format "Could not find occurrence %d of %S"
                          (or occurrence 1) text))))))

(defun go-template-mode-test--should-have-face (text face &optional occurrence offset)
  "Require TEXT at OCCURRENCE plus OFFSET to have FACE."
  (let ((pos (+ (go-template-mode-test--position text occurrence)
                (or offset 0))))
    (unless (go-template-mode-test--face-p pos face)
      (ert-fail (format "%S at %d has face %S, expected %S"
                        text pos (get-char-property pos 'face) face)))))

(defun go-template-mode-test--should-not-have-face
    (text face &optional occurrence offset)
  "Require TEXT at OCCURRENCE plus OFFSET not to have FACE."
  (let ((pos (+ (go-template-mode-test--position text occurrence)
                (or offset 0))))
    (when (go-template-mode-test--face-p pos face)
      (ert-fail (format "%S at %d unexpectedly has face %S"
                        text pos face)))))

(defun go-template-mode-test--should-have-no-template-face
    (text &optional occurrence offset)
  "Require TEXT at OCCURRENCE plus OFFSET to have no template face."
  (let ((pos (+ (go-template-mode-test--position text occurrence)
                (or offset 0))))
    (dolist (face go-template-mode-test--template-faces)
      (when (go-template-mode-test--face-p pos face)
        (ert-fail (format "%S at %d unexpectedly has template face %S"
                          text pos face))))))

(defmacro go-template-mode-test--with-fontified (text &rest body)
  "Insert TEXT, activate `go-template-mode', fontify, then evaluate BODY."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (rename-buffer (generate-new-buffer-name "go-template-mode-test"))
     (insert ,text)
     (go-template-mode)
     (let ((noninteractive nil))
       (font-lock-mode 1))
     (font-lock-ensure)
     ,@body))

(ert-deftest go-template-mode-fontifies-basic-action-tokens ()
  "Fontify representative tokens inside ordinary actions."
  (go-template-mode-test--with-fontified
      "{{if $x.Name}}{{printf \"%s\" $x}}{{else}}{{end}}"
    (go-template-mode-test--should-have-face
     "{{" 'font-lock-preprocessor-face)
    (go-template-mode-test--should-have-face
     "if" 'font-lock-keyword-face)
    (go-template-mode-test--should-have-face
     "$x" 'font-lock-variable-name-face)
    (go-template-mode-test--should-have-face
     ".Name" 'font-lock-variable-name-face)
    (go-template-mode-test--should-have-face
     "printf" 'font-lock-builtin-face)
    (go-template-mode-test--should-have-face
     "\"%s\"" 'font-lock-string-face)
    (go-template-mode-test--should-have-face
     "else" 'font-lock-keyword-face)
    (go-template-mode-test--should-have-face
     "end" 'font-lock-keyword-face)
    (go-template-mode-test--should-have-face
     "}}" 'font-lock-preprocessor-face)))

(ert-deftest go-template-mode-limits-template-faces-to-actions ()
  "Do not fontify template-looking output text or HTML tags."
  (go-template-mode-test--with-fontified
      (concat "if printf $x \"quoted output\" "
              "<div> <user-card> <SECTION> <divine>\n"
              "{{if $x}}{{printf \"%s\" $x}}{{end}}")
    (go-template-mode-test--should-have-no-template-face "if" 1)
    (go-template-mode-test--should-have-no-template-face "printf" 1)
    (go-template-mode-test--should-have-no-template-face "$x" 1)
    (go-template-mode-test--should-have-no-template-face "\"quoted output\"")
    (dolist (tag '("<div>" "<user-card>" "<SECTION>" "<divine>"))
      (go-template-mode-test--should-have-no-template-face tag))
    (go-template-mode-test--should-have-face
     "if" 'font-lock-keyword-face 2)
    (go-template-mode-test--should-have-face
     "printf" 'font-lock-builtin-face 2)
    (go-template-mode-test--should-have-face
     "$x" 'font-lock-variable-name-face 2)))

(ert-deftest go-template-mode-fontifies-actions-in-double-quoted-output ()
  "Do not let surrounding double quotes swallow template actions."
  (go-template-mode-test--with-fontified
      "<div class=\"{{if $x}}active{{else}}inactive{{end}}\">text</div>"
    (go-template-mode-test--should-have-face
     "{{" 'font-lock-preprocessor-face)
    (go-template-mode-test--should-not-have-face
     "{{" 'font-lock-string-face)
    (go-template-mode-test--should-have-face
     "if" 'font-lock-keyword-face)
    (go-template-mode-test--should-have-face
     "$x" 'font-lock-variable-name-face)
    (go-template-mode-test--should-have-face
     "else" 'font-lock-keyword-face)
    (go-template-mode-test--should-have-face
     "end" 'font-lock-keyword-face)
    (go-template-mode-test--should-have-no-template-face "<div")))

(ert-deftest go-template-mode-fontifies-current-action-vocabulary ()
  "Fontify action words and constants from the Go 1.26.7 baseline."
  (go-template-mode-test--with-fontified
      (concat "{{block}}{{break}}{{continue}}{{define}}{{else}}{{end}}"
              "{{if}}{{range}}{{template}}{{with}}"
              "{{nil}}{{true}}{{false}}")
    (dolist (word '("block" "break" "continue" "define" "else" "end"
                    "if" "range" "template" "with"))
      (go-template-mode-test--should-have-face
       word 'font-lock-keyword-face))
    (dolist (constant '("nil" "true" "false"))
      (go-template-mode-test--should-have-face
       constant 'font-lock-constant-face))))

(ert-deftest go-template-mode-fontifies-current-predefined-functions ()
  "Fontify predefined functions from the Go 1.26.7 baseline."
  (let ((functions '("and" "call" "html" "index" "slice" "js" "len"
                     "not" "or" "print" "printf" "println" "urlquery"
                     "eq" "ne" "lt" "le" "gt" "ge")))
    (go-template-mode-test--with-fontified
        (mapconcat (lambda (name) (format "{{%s}}" name)) functions "")
      (dolist (name functions)
        (go-template-mode-test--should-have-face
         name 'font-lock-builtin-face)))))

(ert-deftest go-template-mode-fontifies-variables-and-fields ()
  "Fontify root, named, Unicode, numeric, and chained references."
  (go-template-mode-test--with-fontified
      "{{$}} {{$1}} {{$_}} {{$name_2}} {{$π2}} {{$x.Field}} {{.Root.Child}}"
    (dolist (variable '("$" "$1" "$_" "$name_2" "$π2" "$x"))
      (go-template-mode-test--should-have-face
       variable 'font-lock-variable-name-face))
    (dolist (field '(".Field" ".Root" ".Child"))
      (go-template-mode-test--should-have-face
       field 'font-lock-variable-name-face))))

(ert-deftest go-template-mode-respects-identifiers-and-case ()
  "Do not partially or case-insensitively fontify identifiers."
  (go-template-mode-test--with-fontified
      "{{myrange}}{{printfx}}{{length}}{{IF}}{{Printf}}"
    (dolist (name '("myrange" "printfx" "length" "IF" "Printf"))
      (go-template-mode-test--should-have-no-template-face name))))

(ert-deftest go-template-mode-does-not-close-actions-inside-strings ()
  "Treat delimiter-looking text inside action strings as string data."
  (go-template-mode-test--with-fontified
      (concat "{{printf \"%s\" \"double }} data\"}}\n"
              "{{printf `%s` `raw\n}} data`}}\n"
              "{{printf \"%c\" '}'}}\n"
              "{{printf \"%s\" (index .Values 0)}}")
    (go-template-mode-test--should-have-face
     "}}" 'font-lock-string-face 1)
    (go-template-mode-test--should-not-have-face
     "}}" 'font-lock-preprocessor-face 1)
    (go-template-mode-test--should-have-face
     "}}" 'font-lock-preprocessor-face 2)
    (go-template-mode-test--should-have-face
     "}}" 'font-lock-string-face 3)
    (go-template-mode-test--should-not-have-face
     "}}" 'font-lock-preprocessor-face 3)
    (go-template-mode-test--should-have-face
     "}}" 'font-lock-preprocessor-face 4)
    (go-template-mode-test--should-have-face
     "'}'" 'font-lock-string-face)))

(ert-deftest go-template-mode-skips-escaped-quotes ()
  "Do not terminate interpreted strings or character constants at escapes."
  (go-template-mode-test--with-fontified
      (concat "{{printf \"%s\" \"escaped \\\" }} data\"}}\n"
              "{{printf \"%c\" '\\''}}")
    (go-template-mode-test--should-have-face
     "}}" 'font-lock-string-face 1)
    (go-template-mode-test--should-have-face
     "}}" 'font-lock-preprocessor-face 2)
    (go-template-mode-test--should-have-face
     "'\\''" 'font-lock-string-face)))

(ert-deftest go-template-mode-fontifies-template-comments ()
  "Fontify complete ordinary and trim-marked comment actions only."
  (go-template-mode-test--with-fontified
      (concat "{{/* ordinary\ncomment */}}\n"
              "{{- /* trimmed\ncomment */ -}}\n"
              "{{-  /* too much left space */}}\n"
              "{{/* too much right space */  -}}\n"
              "{{ /* not a comment */ }}\n"
              "plain /* not a comment */")
    (go-template-mode-test--should-have-face
     "ordinary" 'font-lock-comment-face)
    (go-template-mode-test--should-have-face
     "trimmed" 'font-lock-comment-face)
    (go-template-mode-test--should-not-have-face
     "too much left space" 'font-lock-comment-face)
    (go-template-mode-test--should-not-have-face
     "too much right space" 'font-lock-comment-face)
    (go-template-mode-test--should-not-have-face
     "not a comment" 'font-lock-comment-face 1)
    (go-template-mode-test--should-not-have-face
     "not a comment" 'font-lock-comment-face 2)))

(ert-deftest go-template-mode-distinguishes-trimming-from-negative-values ()
  "Fontify valid trim markers but not a negative number's minus sign."
  (go-template-mode-test--with-fontified
      "{{- print \"x\" -}} {{-3}}"
    (go-template-mode-test--should-have-face
     "{{-" 'font-lock-preprocessor-face 1 2)
    (go-template-mode-test--should-have-face
     "-}}" 'font-lock-preprocessor-face)
    (go-template-mode-test--should-have-face
     "{{-3}}" 'font-lock-preprocessor-face 1 0)
    (go-template-mode-test--should-not-have-face
     "{{-3}}" 'font-lock-preprocessor-face 1 2)))

(ert-deftest go-template-mode-leaves-incomplete-actions-unfontified ()
  "Leave incomplete ordinary and comment actions unfontified."
  (dolist (text '("prefix {{if .Missing"
                  "prefix {{/* unfinished {{if}}"
                  "prefix {{/* c */ "
                  "prefix {{/* c */ -"
                  "prefix {{/* c */ -}"
                  "prefix {{printf \"unfinished {{if}}"
                  "prefix {{printf \"escaped\\
newline\"}}{{if}}"
                  "prefix {{printf 'escaped\\
newline'}}{{if}}"))
    (go-template-mode-test--with-fontified text
      (let ((occurrence 1))
        (while (save-excursion
                 (goto-char (point-min))
                 (search-forward "{{" nil t occurrence))
          (go-template-mode-test--should-have-no-template-face
           "{{" occurrence)
          (setq occurrence (1+ occurrence)))))))

(ert-deftest go-template-mode-handles-long-incomplete-actions ()
  "Leave long unterminated ordinary and quoted actions unfontified."
  (dolist (prefix '("{{" "{{printf \""))
    (go-template-mode-test--with-fontified
        (concat prefix (make-string 100000 ?a))
      (go-template-mode-test--should-have-no-template-face "{{"))))

(ert-deftest go-template-mode-rejects-invalid-token-boundaries ()
  "Do not face template tokens followed by invalid punctuation."
  (go-template-mode-test--with-fontified
      "{{if+2}} {{printf+2}} {{.Foo-bar}} {{$x+2}} {{.-}}"
    (dolist (token '("if" "printf" ".Foo" "$x" ".-"))
      (go-template-mode-test--should-have-no-template-face token))))

(ert-deftest go-template-mode-rejects-unclosed-parentheses ()
  "Leave a malformed parenthesized action and following text unfontified."
  (go-template-mode-test--with-fontified
      "{{printf (index .Values 0}}{{if}}"
    (go-template-mode-test--should-have-no-template-face "{{" 1)
    (go-template-mode-test--should-have-no-template-face "printf")
    (go-template-mode-test--should-have-no-template-face "{{" 2)
    (go-template-mode-test--should-have-no-template-face "if")))

(ert-deftest go-template-mode-preserves-editing-interface ()
  "Preserve mode ancestry, comment commands, and indentation behavior."
  (with-temp-buffer
    (insert "hello")
    (go-template-mode)
    (should (derived-mode-p 'text-mode))
    (should (equal comment-start "{{/* "))
    (should (equal comment-end " */}}"))
    (should indent-tabs-mode)
    (comment-region (point-min) (point-max))
    (should (equal (buffer-string) "{{/* hello */}}"))
    (uncomment-region (point-min) (point-max))
    (should (equal (buffer-string) "hello"))))

(ert-deftest go-template-mode-registers-supported-file-extensions ()
  "Select the mode for every documented extension."
  (dolist (filename '("example.gotmpl" "example.tpl" "example.tmpl"))
    (with-temp-buffer
      (setq buffer-file-name filename)
      (set-auto-mode)
      (should (eq major-mode 'go-template-mode)))))

(ert-deftest go-template-mode-font-lock-lifecycle-is-idempotent ()
  "Install once per buffer and restore host fontification on uninstall."
  (with-temp-buffer
    (rename-buffer (generate-new-buffer-name "go-template-mode-test"))
    (insert "<div class=\"prefix {{if .Enabled}} suffix\">\nmanual")
    (html-mode)
    (let ((noninteractive nil))
      (font-lock-mode 1))
    (let ((before-mode major-mode)
          (before-syntax (syntax-table))
          (before-indent indent-line-function)
          (before-comment-start comment-start)
          (before-comment-end comment-end)
          (before-defaults font-lock-defaults))
      (go-template-mode-font-lock-install)
      (go-template-mode-font-lock-install)
      (font-lock-ensure)
      (should (eq major-mode before-mode))
      (should (eq (syntax-table) before-syntax))
      (should (eq indent-line-function before-indent))
      (should (equal comment-start before-comment-start))
      (should (equal comment-end before-comment-end))
      (should (equal font-lock-defaults before-defaults))
      (go-template-mode-test--should-have-face
       "prefix" 'font-lock-string-face)
      (go-template-mode-test--should-have-face
       "if" 'font-lock-keyword-face)
      (go-template-mode-test--should-not-have-face
       "{{if .Enabled}}" 'font-lock-string-face 1 4)
      (let ((manual (go-template-mode-test--position "manual"))
            (action (go-template-mode-test--position "if")))
        (let ((overlay (make-overlay manual (+ manual 6))))
          (overlay-put overlay 'face 'bold))
        (put-text-property action (+ action 2)
                           'go-template-mode-test-marker t))
      (go-template-mode-font-lock-uninstall)
      (go-template-mode-font-lock-uninstall)
      (go-template-mode-test--should-not-have-face
       "if" 'font-lock-keyword-face)
      (go-template-mode-test--should-have-face
       "if" 'font-lock-string-face)
      (go-template-mode-test--should-have-face "manual" 'bold)
      (should (get-text-property
               (go-template-mode-test--position "if")
               'go-template-mode-test-marker)))))

(ert-deftest go-template-mode-uninstalls-after-programmatic-fontification ()
  "Clear every managed span even when Font Lock mode is disabled."
  (with-temp-buffer
    (insert "{{if .Enabled}} plain {{printf \"%s\" .Name}}")
    (go-template-mode)
    (font-lock-ensure)
    (should-not font-lock-mode)
    (go-template-mode-test--should-have-face
      "if" 'font-lock-keyword-face)
    (go-template-mode-test--should-have-face
     "printf" 'font-lock-builtin-face)
    (go-template-mode-font-lock-uninstall)
    (go-template-mode-test--should-have-no-template-face "if")
    (go-template-mode-test--should-have-no-template-face "printf")
    (should-not (text-property-any
                  (point-min) (point-max)
                  'font-lock-multiline t))
    (should-not (text-property-any
                 (point-min) (point-max)
                 'go-template-mode-font-lock-action t))))

(ert-deftest go-template-mode-refontifies-after-closing-delimiter-edits ()
  "Clear and restore action faces after narrow closing-delimiter edits."
  (go-template-mode-test--with-fontified "before {{if .Enabled}} after"
    (go-template-mode-test--should-have-face
     "if" 'font-lock-keyword-face)
    (let ((close (go-template-mode-test--position "}}")))
      (delete-region close (+ close 2))
      (font-lock-flush (1- close) (1+ close))
      (font-lock-ensure (1- close) (1+ close))
      (go-template-mode-test--should-have-no-template-face "{{")
      (go-template-mode-test--should-have-no-template-face "if")
      (goto-char close)
      (insert "}}")
      (font-lock-flush (1- close) (+ close 3))
      (font-lock-ensure (1- close) (+ close 3))
      (go-template-mode-test--should-have-face
       "{{" 'font-lock-preprocessor-face)
      (go-template-mode-test--should-have-face
       "if" 'font-lock-keyword-face))))

(ert-deftest go-template-mode-removes-fontification-before-major-mode-change ()
  "Do not leave shared highlighting behind after changing major mode."
  (go-template-mode-test--with-fontified "{{if .Enabled}}"
    (go-template-mode-test--should-have-face
     "if" 'font-lock-keyword-face)
    (fundamental-mode)
    (go-template-mode-test--should-have-no-template-face "if")))

(ert-deftest go-template-mode-refontifies-after-opening-delimiter-edits ()
  "Clear and restore action faces after narrow opening-delimiter edits."
  (go-template-mode-test--with-fontified "before {{if .Enabled}} after"
    (let ((open (go-template-mode-test--position "{{")))
      (delete-region open (+ open 2))
      (font-lock-flush (1- open) (1+ open))
      (font-lock-ensure (1- open) (1+ open))
      (go-template-mode-test--should-have-no-template-face "if")
      (goto-char open)
      (insert "{{")
      (font-lock-flush (1- open) (+ open 3))
      (font-lock-ensure (1- open) (+ open 3))
      (go-template-mode-test--should-have-face
       "{{" 'font-lock-preprocessor-face)
      (go-template-mode-test--should-have-face
       "if" 'font-lock-keyword-face))))

(ert-deftest go-template-mode-recovers-after-middle-action-is-broken ()
  "Do not merge a broken middle action with the following action."
  (go-template-mode-test--with-fontified
      "{{if .First}} {{if .Second}} {{if .Third}}"
    (let ((close (go-template-mode-test--position "}}" 2)))
      (delete-region close (+ close 2))
      (font-lock-flush (1- close) (1+ close))
      (font-lock-ensure (1- close) (1+ close))
      (go-template-mode-test--should-have-face
       "if" 'font-lock-keyword-face 1)
      (go-template-mode-test--should-have-no-template-face "if" 2)
      (go-template-mode-test--should-have-no-template-face "if" 3)
      (goto-char close)
      (insert "}}")
      (font-lock-flush (1- close) (+ close 3))
      (font-lock-ensure (1- close) (+ close 3))
      (go-template-mode-test--should-have-face
       "if" 'font-lock-keyword-face 2)
      (go-template-mode-test--should-have-face
       "if" 'font-lock-keyword-face 3))))

(ert-deftest go-template-mode-refontifies-multiline-comments-incrementally ()
  "Clear and restore multiline comments after narrow delimiter edits."
  (go-template-mode-test--with-fontified "before {{/* one\ntwo */}} after"
    (go-template-mode-test--should-have-face
     "two" 'font-lock-comment-face)
    (let ((close (go-template-mode-test--position "*/}}")))
      (delete-region (+ close 2) (+ close 4))
      (font-lock-flush (+ close 1) (+ close 3))
      (font-lock-ensure (+ close 1) (+ close 3))
      (go-template-mode-test--should-have-no-template-face "{{")
      (go-template-mode-test--should-have-no-template-face "two")
      (goto-char (+ close 2))
      (insert "}}")
      (font-lock-flush (+ close 1) (+ close 5))
      (font-lock-ensure (+ close 1) (+ close 5))
      (go-template-mode-test--should-have-face
       "two" 'font-lock-comment-face))))

(provide 'go-template-mode-test)
;;; go-template-mode-test.el ends here
