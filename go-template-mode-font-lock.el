;;; go-template-mode-font-lock.el --- Font lock for Go templates -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Robert Charusta

;; Author: Robert Charusta <rch-public@posteo.net>
;; Maintainer: Robert Charusta <rch-public@posteo.net>
;; URL: https://codeberg.org/rch/go-template-mode
;; Version: 2.0.0
;; Keywords: languages, tools
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

;; Action-aware fontification shared by `go-template-mode' and host-mode
;; integrations.  Loading this library has no mode-selection or buffer-editing
;; side effects.  Call `go-template-mode-font-lock-install' in a buffer to add
;; highlighting and `go-template-mode-font-lock-uninstall' to remove it.

;;; Code:

(require 'font-lock)

(defvar font-lock-beg)
(defvar font-lock-end)

;; Language vocabulary is based on Go 1.26.7 package text/template.
(defconst go-template-mode-font-lock--action-words
  '("block" "break" "continue" "define" "else" "end" "if" "range"
    "template" "with")
  "Go template action words.")

(defconst go-template-mode-font-lock--constants
  '("false" "nil" "true")
  "Go template constants.")

(defconst go-template-mode-font-lock--predefined-functions
  '("and" "call" "eq" "ge" "gt" "html" "index" "js" "le" "len"
    "lt" "ne" "not" "or" "print" "printf" "println" "slice"
    "urlquery")
  "Predefined Go template functions.")

(defconst go-template-mode-font-lock--double-quoted-special-regexp
  "[\"\\\\\n]"
  "Characters requiring attention inside double-quoted tokens.")

(defconst go-template-mode-font-lock--single-quoted-special-regexp
  "['\\\\\n]"
  "Characters requiring attention inside character constants.")

(defconst go-template-mode-font-lock--ordinary-special-regexp
  (regexp-opt '("{{" "-}}" "}}" "\"" "'" "`" "(" ")"))
  "Tokens that can change action scanning state.")

(defvar-local go-template-mode-font-lock--installed nil
  "Non-nil when shared Go template fontification is installed.")

(defun go-template-mode-font-lock--space-p (char)
  "Return non-nil when CHAR is Go trim-marker whitespace."
  (memq char '(9 10 13 32)))

(defun go-template-mode-font-lock--identifier-char-p (char)
  "Return non-nil when CHAR can occur in a Go template identifier."
  (and char
       (or (= char ?_)
           (memq (get-char-code-property char 'general-category)
                 '(Lu Ll Lt Lm Lo Nd)))))

(defun go-template-mode-font-lock--left-delimiter-end (start)
  "Return the end of the opening delimiter at START.
Include a valid left trim marker, but not its required whitespace."
  (if (and (eq (char-after (+ start 2)) ?-)
           (go-template-mode-font-lock--space-p
            (char-after (+ start 3))))
      (+ start 3)
    (+ start 2)))

(defun go-template-mode-font-lock--scan-quoted (quote)
  "Scan a quoted token beginning at point and delimited by QUOTE.
Return its end, or nil when it is unterminated or crosses a newline."
  (forward-char 1)
  (let ((regexp (if (eq quote ?\")
                    go-template-mode-font-lock--double-quoted-special-regexp
                  go-template-mode-font-lock--single-quoted-special-regexp)))
    (catch 'end
      (while (re-search-forward regexp nil t)
        (let ((char (char-before)))
          (cond
           ((eq char quote)
            (throw 'end (point)))
           ((eq char ?\n)
            (throw 'end nil))
           ((eq char ?\\)
            (if (or (eobp) (eq (char-after) ?\n))
                (throw 'end nil)
              (forward-char 1))))))
      nil)))

(defun go-template-mode-font-lock--scan-raw-string ()
  "Scan a raw string beginning at point and return its end, or nil."
  (forward-char 1)
  (when (search-forward "`" nil t)
    (point)))

(defun go-template-mode-font-lock--comment-start (start open-end)
  "Return the comment marker after the delimiter at START ending OPEN-END.
Return nil when the action does not begin with a valid comment marker."
  (save-excursion
    (goto-char open-end)
    (if (> open-end (+ start 2))
        (progn
          (forward-char 1)
          (and (looking-at "/\\*") (point)))
      (and (looking-at "/\\*") (point)))))

(defun go-template-mode-font-lock--scan-comment (marker-start)
  "Scan a comment action whose comment marker begins at MARKER-START.
Return its complete action end, or nil when malformed or unterminated."
  (save-excursion
    (goto-char (+ marker-start 2))
    (when (search-forward "*/" nil t)
      (let ((comment-end (point)))
        (cond
         ((looking-at "}}")
          (+ comment-end 2))
         ((and (<= (+ (point) 4) (point-max))
               (go-template-mode-font-lock--space-p (char-after))
               (eq (char-after (1+ (point))) ?-)
               (string= (buffer-substring-no-properties
                         (+ (point) 2) (+ (point) 4))
                        "}}"))
          (+ comment-end 4)))))))

(defun go-template-mode-font-lock--scan-ordinary (open-end)
  "Scan an ordinary action after OPEN-END and return its end, or nil."
  (save-excursion
    (goto-char open-end)
    (let ((paren-depth 0))
      (catch 'end
        (while (re-search-forward
                go-template-mode-font-lock--ordinary-special-regexp nil t)
          (goto-char (match-beginning 0))
          (cond
           ((looking-at "{{")
            (throw 'end nil))
           ((and (looking-at "-}}")
                 (> (point) open-end)
                 (go-template-mode-font-lock--space-p (char-before)))
            (throw 'end (and (zerop paren-depth) (+ (point) 3))))
           ((looking-at "}}")
            (throw 'end (and (zerop paren-depth) (+ (point) 2))))
           ((eq (char-after) ?\")
            (unless (go-template-mode-font-lock--scan-quoted ?\")
              (throw 'end nil)))
           ((eq (char-after) ?')
            (unless (go-template-mode-font-lock--scan-quoted ?')
              (throw 'end nil)))
           ((eq (char-after) ?`)
            (unless (go-template-mode-font-lock--scan-raw-string)
              (throw 'end nil)))
           ((eq (char-after) ?\()
            (setq paren-depth (1+ paren-depth))
            (forward-char 1))
           ((eq (char-after) ?\))
            (setq paren-depth (1- paren-depth))
            (when (< paren-depth 0)
              (throw 'end nil))
            (forward-char 1))
           (t
            (forward-char 1))))
        nil))))

(defun go-template-mode-font-lock--scan-action (start)
  "Scan a candidate action beginning at START.
Return its end, or nil when the candidate is incomplete or malformed."
  (save-excursion
    (goto-char start)
    (when (looking-at "{{")
      (let* ((open-end (go-template-mode-font-lock--left-delimiter-end start))
             (comment-start
              (go-template-mode-font-lock--comment-start start open-end))
             (end (if comment-start
                      (go-template-mode-font-lock--scan-comment comment-start)
                    (go-template-mode-font-lock--scan-ordinary open-end))))
        end))))

(defun go-template-mode-font-lock--set-token-match (start end)
  "Set match data for a token from START to END."
  (goto-char end)
  (set-match-data (list start end))
  t)

(defun go-template-mode-font-lock--scan-identifier ()
  "Move point over identifier characters and return the resulting point."
  (while (go-template-mode-font-lock--identifier-char-p (char-after))
    (forward-char 1))
  (point))

(defun go-template-mode-font-lock--terminator-p (pos limit)
  "Return non-nil when POS is a valid identifier boundary before LIMIT."
  (or (>= pos limit)
      (go-template-mode-font-lock--space-p (char-after pos))
      (memq (char-after pos) '(?. ?, ?| ?: ?\) ?\())
      (and (<= (+ pos 2) limit)
           (string= (buffer-substring-no-properties pos (+ pos 2)) "}}"))))

(defun go-template-mode-font-lock--match-token (limit)
  "Match the next template token before LIMIT in the current action."
  (catch 'found
    (while (< (point) limit)
      (let ((start (point)))
        (cond
         ((and (looking-at "{{")
               (go-template-mode-font-lock--comment-start
                start (go-template-mode-font-lock--left-delimiter-end start)))
          (goto-char limit))
         ((looking-at "{{")
          (let ((end (go-template-mode-font-lock--left-delimiter-end start)))
            (go-template-mode-font-lock--set-token-match start end)
            (throw 'found t)))
         ((and (looking-at "-}}")
               (= (+ start 3) limit)
               (go-template-mode-font-lock--space-p (char-before)))
          (go-template-mode-font-lock--set-token-match start limit)
          (throw 'found t))
         ((and (looking-at "}}") (= (+ start 2) limit))
          (go-template-mode-font-lock--set-token-match start limit)
          (throw 'found t))
         ((memq (char-after) '(?\" ?'))
          (let ((end (go-template-mode-font-lock--scan-quoted (char-after))))
            (if end
                (progn
                  (go-template-mode-font-lock--set-token-match start end)
                  (throw 'found t))
              (goto-char limit))))
         ((eq (char-after) ?`)
          (let ((end (go-template-mode-font-lock--scan-raw-string)))
            (if end
                (progn
                  (go-template-mode-font-lock--set-token-match start end)
                  (throw 'found t))
              (goto-char limit))))
         ((eq (char-after) ?$)
          (forward-char 1)
          (go-template-mode-font-lock--scan-identifier)
          (when (go-template-mode-font-lock--terminator-p (point) limit)
            (go-template-mode-font-lock--set-token-match start (point))
            (throw 'found t)))
         ((eq (char-after) ?.)
          (forward-char 1)
          (unless (and (>= (or (char-after) 0) ?0)
                       (<= (or (char-after) 0) ?9))
             (go-template-mode-font-lock--scan-identifier)
             (when (go-template-mode-font-lock--terminator-p (point) limit)
               (go-template-mode-font-lock--set-token-match start (point))
               (throw 'found t))))
         ((go-template-mode-font-lock--identifier-char-p (char-after))
          (go-template-mode-font-lock--scan-identifier)
          (when (go-template-mode-font-lock--terminator-p (point) limit)
            (let ((word (buffer-substring-no-properties start (point))))
               (cond
                ((member word go-template-mode-font-lock--action-words)
                 (go-template-mode-font-lock--set-token-match start (point))
                 (throw 'found t))
                ((member word go-template-mode-font-lock--constants)
                 (go-template-mode-font-lock--set-token-match start (point))
                 (throw 'found t))
                ((member word go-template-mode-font-lock--predefined-functions)
                 (go-template-mode-font-lock--set-token-match start (point))
                 (throw 'found t))))))
         (t
          (forward-char 1)))))
    nil))

(defun go-template-mode-font-lock--token-face ()
  "Return the face for the current token match."
  (let ((start (match-beginning 0))
        (end (match-end 0)))
    (cond
     ((memq (char-after start) '(?\" ?' ?`))
      'font-lock-string-face)
     ((or (eq (char-after start) ?{)
          (eq (char-before end) ?}))
      'font-lock-preprocessor-face)
     ((memq (char-after start) '(?$ ?.))
      'font-lock-variable-name-face)
     ((member (buffer-substring-no-properties start end)
              go-template-mode-font-lock--action-words)
      'font-lock-keyword-face)
     ((member (buffer-substring-no-properties start end)
              go-template-mode-font-lock--constants)
      'font-lock-constant-face)
     (t
      'font-lock-builtin-face))))

(defun go-template-mode-font-lock--action-properties ()
  "Return managed Font Lock properties for the current action match.
The action marker provides a stable boundary for incremental rescanning."
  (let* ((start (match-beginning 0))
         (open-end (go-template-mode-font-lock--left-delimiter-end start))
         (comment (go-template-mode-font-lock--comment-start start open-end)))
    `(face ,(if comment 'font-lock-comment-face 'default)
           font-lock-multiline t
           go-template-mode-font-lock-action t)))

(defun go-template-mode-font-lock--match-action (limit)
  "Match the next complete Go template action before LIMIT."
  (catch 'found
    (while (search-forward "{{" limit t)
      (let* ((start (- (point) 2))
             (end (go-template-mode-font-lock--scan-action start)))
        (if (not end)
            (goto-char limit)
          (if (> end limit)
              (goto-char limit)
            (goto-char end)
            (set-match-data (list start end))
            (throw 'found t)))))
    nil))

(defconst go-template-mode-font-lock--keywords
  '((go-template-mode-font-lock--match-action
     (0 (go-template-mode-font-lock--action-properties) t)
     (go-template-mode-font-lock--match-token
      (let ((start (match-beginning 0))
            (end (match-end 0)))
        (goto-char start)
        end)
      nil
      (0 (go-template-mode-font-lock--token-face) t))))
  "Font Lock rules for complete Go template actions.")

(defun go-template-mode-font-lock--region-scan-start (beg)
  "Return a safe lexical scan start at or before BEG."
  (cond
   ((and (< beg (point-max))
         (get-text-property beg 'go-template-mode-font-lock-action))
    (or (previous-single-property-change
         (1+ beg) 'go-template-mode-font-lock-action nil (point-min))
        (point-min)))
   (t
    (let ((change (previous-single-property-change
                   beg 'go-template-mode-font-lock-action nil (point-min))))
      (if (and change
               (> change (point-min))
               (get-text-property
                (1- change) 'go-template-mode-font-lock-action))
          change
        (save-excursion
          (goto-char beg)
          (if (search-backward "{{" nil t)
              (point-min)
            beg)))))))

(defun go-template-mode-font-lock--extend-region ()
  "Extend fontification to complete or stale Go template actions."
  (let ((original-beg font-lock-beg)
        (original-end font-lock-end))
    (font-lock-extend-region-multiline)
    (let ((bounds (cons font-lock-beg font-lock-end)))
      (save-excursion
        (save-restriction
          (widen)
          (goto-char (go-template-mode-font-lock--region-scan-start
                      (car bounds)))
          (catch 'done
            (while (search-forward "{{" nil t)
              (let* ((start (- (point) 2))
                     (action-end
                      (go-template-mode-font-lock--scan-action start))
                     (span-end (or action-end (point-max))))
                (when (>= start (cdr bounds))
                  (throw 'done nil))
                (when (and (< start (cdr bounds)) (> span-end (car bounds)))
                  (setcar bounds (min (car bounds) start))
                  (setcdr bounds (max (cdr bounds) span-end)))
                (if (not action-end)
                    (throw 'done nil)
                  (goto-char span-end)))))))
      (setq font-lock-beg (car bounds)
            font-lock-end (cdr bounds)))
    (or (/= original-beg font-lock-beg)
        (/= original-end font-lock-end))))

(defun go-template-mode-font-lock--clear-action-properties ()
  "Remove shared Font Lock properties from complete actions."
  (save-restriction
    (widen)
    (save-excursion
      (let ((pos (point-min))
            start
            end)
        (while (setq start
                     (text-property-any
                      pos (point-max) 'go-template-mode-font-lock-action t))
          (setq end
                (next-single-property-change
                 start 'go-template-mode-font-lock-action nil (point-max)))
          (remove-list-of-text-properties
           start end
           '(face font-lock-multiline go-template-mode-font-lock-action))
          (setq pos end))))))

;;;###autoload
(defun go-template-mode-font-lock-install ()
  "Install Go template action fontification in the current buffer."
  (unless go-template-mode-font-lock--installed
    (add-to-list (make-local-variable 'font-lock-extra-managed-props)
                 'go-template-mode-font-lock-action)
    (font-lock-add-keywords nil go-template-mode-font-lock--keywords 'append)
    (add-hook 'font-lock-extend-region-functions
              #'go-template-mode-font-lock--extend-region nil t)
    (add-hook 'change-major-mode-hook
              #'go-template-mode-font-lock-uninstall nil t)
    (setq go-template-mode-font-lock--installed t)
    (font-lock-flush)))

;;;###autoload
(defun go-template-mode-font-lock-uninstall ()
  "Remove Go template action fontification from the current buffer."
  (when go-template-mode-font-lock--installed
    (font-lock-remove-keywords nil go-template-mode-font-lock--keywords)
    (remove-hook 'font-lock-extend-region-functions
                 #'go-template-mode-font-lock--extend-region t)
    (remove-hook 'change-major-mode-hook
                 #'go-template-mode-font-lock-uninstall t)
    (setq go-template-mode-font-lock--installed nil)
    (go-template-mode-font-lock--clear-action-properties)
    (when font-lock-mode
      (font-lock-flush)
      (font-lock-ensure))
    (setq font-lock-extra-managed-props
          (delq 'go-template-mode-font-lock-action
                font-lock-extra-managed-props))))

(provide 'go-template-mode-font-lock)
;;; go-template-mode-font-lock.el ends here
