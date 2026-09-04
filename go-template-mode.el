;;; go-template-mode.el --- Major mode for Go templates -*- lexical-binding: t; -*-

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

;; Lightweight major mode for Go text/template files.  It uses an
;; action-aware lexical scanner with incremental fontification and no caches.

;;; Code:

(require 'go-template-mode-font-lock)

(defgroup go-template nil
  "Editing Go text/template files."
  :group 'languages
  :prefix "go-template-")

;;;###autoload
(define-derived-mode go-template-mode text-mode "Go-Template"
  "Major mode for editing Go text/template files."
  ;; Comments for M-; convenience (not syntactically enforced).
  (setq-local comment-start "{{/* ")
  (setq-local comment-end " */}}")
  ;; Strings are template syntax only inside actions.
  (setq-local font-lock-defaults '(nil t))
  ;; Preserve the mode's established tab preference.
  (setq-local indent-tabs-mode t)
  (go-template-mode-font-lock-install))

;;;###autoload
(add-to-list 'auto-mode-alist
             '("\\.\\(gotmpl\\|tpl\\|tmpl\\)\\'" . go-template-mode))

(provide 'go-template-mode)
;;; go-template-mode.el ends here
