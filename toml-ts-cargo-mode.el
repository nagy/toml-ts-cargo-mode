;;; toml-ts-cargo-mode.el --- Cargo.toml features for toml-ts-mode -*- lexical-binding: t -*-

;; Copyright (C) 2026  Daniel Nagy

;; This file is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU Affero General Public License for more details.

;; You should have received a copy of the GNU Affero General Public
;; License along with this file.  If not, see
;; <https://www.gnu.org/licenses/>.

;; Author: Daniel Nagy
;; Version: 0.2.0
;; Keywords: languages, tools
;; Package-Requires: ((emacs "30.1"))
;; URL: https://github.com/nagy/toml-ts-cargo-mode

;;; Commentary:

;; `toml-ts-cargo-mode' is a minor mode for `toml-ts-mode' buffers that
;; adds Cargo.toml-specific enhancements:
;;
;;   - URL detection: `thing-at-point' for 'url returns the crates.io
;;     URL for whichever crate dependency key is under point.
;;
;;   - Underline highlighting: dependency keys inside known dependency
;;     tables are underlined.
;;
;; Usage:
;;     (add-hook 'toml-ts-mode-hook #'toml-ts-cargo-maybe-enable)

;;; Code:

(require 'toml-ts-mode)
(require 'thingatpt)
(require 'cl-lib)

(defgroup toml-ts-cargo nil
  "Cargo.toml support for `toml-ts-mode'."
  :group 'toml-ts-mode
  :prefix "toml-ts-cargo-")

(defcustom toml-ts-cargo-crate-url-template
  "https://crates.io/crates/%s"
  "URL template for crate dependencies."
  :type 'string
  :group 'toml-ts-cargo)

(defcustom toml-ts-cargo-highlight-dependencies t
  "When non-nil, underline dependency keys."
  :type 'boolean
  :group 'toml-ts-cargo)

(defface toml-ts-cargo-dependency-key-face
  '((t :underline t :inherit (font-lock-property-use-face)))
  "Face for crate dependency keys."
  :group 'toml-ts-cargo)

;;; Predicates

(defun toml-ts-cargo--strip-quotes (string)
  "Strip surrounding single or double quotes from STRING."
  (if (and (> (length string) 1)
           (memq (aref string 0) '(?\" ?\'))
           (eq (aref string 0) (aref string (1- (length string)))))
      (substring string 1 -1)
    string))

(defun toml-ts-cargo--key-text (key-node)
  "Return the full key text for tree-sitter KEY-NODE as a string.
For dotted keys, concatenates named children with dots."
  (let ((ktype (treesit-node-type key-node)))
    (cond
     ((equal ktype "bare_key")
      (treesit-node-text key-node))
     ((equal ktype "quoted_key")
      (toml-ts-cargo--strip-quotes (treesit-node-text key-node)))
     ((equal ktype "dotted_key")
      (let ((children (treesit-node-children key-node)))
        (mapconcat (lambda (c) (toml-ts-cargo--key-text c))
                   (cl-remove-if-not (lambda (c) (treesit-node-check c 'named))
                                     children)
                   ".")))
     (t nil))))

(defun toml-ts-cargo--dep-table-header-p (header-text)
  "Return `top' if HEADER-TEXT names a toplevel Cargo dep table.
Return `sub' for sub-tables like [dependencies.serde].
Return nil otherwise.

A header names a dep table if any suffix component is one of
the known dep table names.  If the last component matches, it's
toplevel; if the second-to-last matches (and last does not), it's
a sub-table."
  (when (stringp header-text)
    (let* ((dep-names '("dependencies" "dev-dependencies" "build-dependencies"))
           (parts (split-string header-text "\\."))
           (last (car (last parts)))
           (n (length parts)))
      (cond
       ((member last dep-names) 'top)
       ((and (>= n 2) (member (nth (- n 2) parts) dep-names)) 'sub)
       (t nil)))))

(defun toml-ts-cargo--crate-key-p (key-node)
  "Return non-nil if KEY-NODE names a crate in a toplevel Cargo dep table."
  (let* ((pair (treesit-node-parent key-node))
         (table (and pair
                     (equal (treesit-node-type pair) "pair")
                     (let ((parent (treesit-node-parent pair)))
                       (and parent
                            (member (treesit-node-type parent)
                                    '("table" "table_array_element"))
                            parent)))))
    (when table
      (let* ((header (treesit-node-child table 0 t))
             (header-text (and header (toml-ts-cargo--key-text header))))
        (eq (toml-ts-cargo--dep-table-header-p header-text) 'top)))))

;;; Font-lock

(defun toml-ts-cargo--fontify-crate-key (node override start end &rest _)
  "Font-lock function: highlight NODE if it's a crate dependency key."
  (when (toml-ts-cargo--crate-key-p node)
    (treesit-fontify-with-override
     start end 'toml-ts-cargo-dependency-key-face override)))

(defvar toml-ts-cargo--font-lock-rules
  (treesit-font-lock-rules
   :language 'toml
   :override t
   :feature 'cargo-dependency
   '((table (pair [(bare_key) (quoted_key) (dotted_key)]
                  @toml-ts-cargo--fontify-crate-key))
     (table_array_element
      (pair [(bare_key) (quoted_key) (dotted_key)]
            @toml-ts-cargo--fontify-crate-key))))
  "Treesit font-lock rules for Cargo.toml dependency-key highlighting.")

;;; URL provider

(defvar toml-ts-cargo-mode)

(defun toml-ts-cargo--url-provider ()
  "Return a crates.io URL if point is on a Cargo dependency key."
  (when (and toml-ts-cargo-mode
             (derived-mode-p 'toml-ts-mode)
             (treesit-ready-p 'toml t))
    (let ((node (treesit-node-at (point))))
      (when node
        (let* ((pair (treesit-parent-until
                      node
                      (lambda (n) (equal (treesit-node-type n) "pair"))))
               (key-node (and pair (treesit-node-child pair 0 t))))
          (when (and key-node (toml-ts-cargo--crate-key-p key-node))
            ;; For dotted keys, use only the first component (the crate).
            (let* ((name (toml-ts-cargo--key-text key-node))
                   (crate (car (split-string name "\\."))))
              (format toml-ts-cargo-crate-url-template crate))))))))

;;; Minor mode

;;;###autoload
(defun toml-ts-cargo-maybe-enable ()
  "Enable `toml-ts-cargo-mode' when visiting a Cargo.toml file.
Safe to add to `toml-ts-mode-hook'."
  (when (and buffer-file-name
             (string-match-p "/Cargo\\.toml\\'" buffer-file-name))
    (toml-ts-cargo-mode 1)))

;;;###autoload
(define-minor-mode toml-ts-cargo-mode
  "Minor mode for Cargo.toml enhancements in `toml-ts-mode' buffers.

When enabled, this mode:
  - Underlines dependency keys in toplevel dep tables.
  - Makes `thing-at-point' return crates.io URLs for those keys."
  :lighter " Cargo"
  (if toml-ts-cargo-mode
      (toml-ts-cargo--enable)
    (toml-ts-cargo--disable)))

(defun toml-ts-cargo--enable ()
  "Register URL provider and font-lock rules."
  (unless (member '(url . toml-ts-cargo--url-provider)
                  thing-at-point-provider-alist)
    (setq-local thing-at-point-provider-alist
                (cons '(url . toml-ts-cargo--url-provider)
                      thing-at-point-provider-alist)))
  (when toml-ts-cargo-highlight-dependencies
    (treesit-add-font-lock-rules toml-ts-cargo--font-lock-rules)
    (font-lock-flush)))

(defun toml-ts-cargo--disable ()
  "Unregister URL provider and font-lock rules."
  (setq-local thing-at-point-provider-alist
              (delete '(url . toml-ts-cargo--url-provider)
                      thing-at-point-provider-alist))
  (let ((new-settings nil))
    (dolist (setting treesit-font-lock-settings)
      (unless (eq (treesit-font-lock-setting-feature setting)
                  'cargo-dependency)
        (push setting new-settings)))
    (setq-local treesit-font-lock-settings (nreverse new-settings)))
  (font-lock-flush))

(provide 'toml-ts-cargo-mode)
;;; toml-ts-cargo-mode.el ends here
