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
;; Version: 0.1.0
;; Keywords: languages, tools
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:

;; This package provides `toml-ts-cargo-mode', a minor mode that adds
;; Cargo.toml-specific enhancements to `toml-ts-mode' buffers:
;;
;;   - URL detection: `thing-at-point' for 'url returns the crates.io
;;     page for the crate whose dependency key is under point.
;;
;;   - Underline highlighting: dependency keys inside known dependency
;;     tables are underlined via treesit queries with `:match?'
;;     predicates.
;;
;; Usage:
;;     (add-hook 'toml-ts-mode-hook
;;               (lambda ()
;;                 (when (string-match-p "/Cargo\\.toml\\'" buffer-file-name)
;;                   (toml-ts-cargo-mode 1))))

;;; Code:

(require 'toml-ts-mode)
(require 'thingatpt)
(eval-when-compile (require 'rx))

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

(defconst toml-ts-cargo--dependency-table-names
  '("dependencies" "dev-dependencies" "build-dependencies")
  "Cargo.toml table names that contain crate-level dependencies.")

(defconst toml-ts-cargo--dependency-table-re
  (rx-to-string `(seq bos (or ,@toml-ts-cargo--dependency-table-names) eos))
  "Regexp matching `toml-ts-cargo--dependency-table-names'.")


;;; Tree-sitter helpers

(defun toml-ts-cargo--strip-quotes (string)
  "Strip surrounding double or single quotes from STRING."
  (if (and (> (length string) 1)
           (memq (aref string 0) '(?\" ?\'))
           (eq (aref string 0) (aref string (1- (length string)))))
      (substring string 1 -1)
    string))

(defun toml-ts-cargo--key-text (key-node)
  "Return the key text for a tree-sitter KEY-NODE."
  (let ((ktype (treesit-node-type key-node)))
    (cond
     ((equal ktype "bare_key")
      (treesit-node-text key-node))
     ((equal ktype "quoted_key")
      (toml-ts-cargo--strip-quotes (treesit-node-text key-node)))
     ((equal ktype "dotted_key")
      (let ((first (treesit-node-child key-node 0 t)))
        (when first
          (if (equal (treesit-node-type first) "quoted_key")
              (toml-ts-cargo--strip-quotes (treesit-node-text first))
            (treesit-node-text first)))))
     (t nil))))

(defun toml-ts-cargo--find-table-pair (node)
  "Walk up from NODE to find a pair whose parent is a table.
Returns nil for pairs inside inline_tables."
  (treesit-parent-until
   node
   (lambda (n)
     (and (equal (treesit-node-type n) "pair")
          (let ((p (treesit-node-parent n)))
            (and p
                 (member (treesit-node-type p)
                         '("table" "table_array_element"))))))
   t))


;;; Treesit font-lock rules

(defvar toml-ts-cargo--font-lock-rules
  (treesit-font-lock-rules
   :language 'toml
   :override t
   :feature 'cargo-dependency
   `((table
      [(bare_key) (quoted_key)] @_table-key
      (pair (bare_key) @toml-ts-cargo-dependency-key-face)
      (:match? @_table-key ,toml-ts-cargo--dependency-table-re))
     (table
      [(bare_key) (quoted_key)] @_table-key
      (pair (quoted_key) @toml-ts-cargo-dependency-key-face)
      (:match? @_table-key ,toml-ts-cargo--dependency-table-re))
     (table
      [(bare_key) (quoted_key)] @_table-key
      (pair (dotted_key) @toml-ts-cargo-dependency-key-face)
      (:match? @_table-key ,toml-ts-cargo--dependency-table-re))
     (table_array_element
      [(bare_key) (quoted_key)] @_table-key
      (pair (bare_key) @toml-ts-cargo-dependency-key-face)
      (:match? @_table-key ,toml-ts-cargo--dependency-table-re))
     (table_array_element
      [(bare_key) (quoted_key)] @_table-key
      (pair (quoted_key) @toml-ts-cargo-dependency-key-face)
      (:match? @_table-key ,toml-ts-cargo--dependency-table-re))
     (table_array_element
      [(bare_key) (quoted_key)] @_table-key
      (pair (dotted_key) @toml-ts-cargo-dependency-key-face)
      (:match? @_table-key ,toml-ts-cargo--dependency-table-re))))
  "Treesit font-lock rules for Cargo.toml dependency-key highlighting.")


;;; URL provider

(defvar toml-ts-cargo-mode)

(defun toml-ts-cargo--url-provider ()
  "Return a crates.io URL if point is on a dependency key."
  (when (and toml-ts-cargo-mode
             (derived-mode-p 'toml-ts-mode)
             (treesit-ready-p 'toml t))
    (when-let* ((node (treesit-node-at (point)))
                (pair (toml-ts-cargo--find-table-pair node))
                (table (treesit-node-parent pair))
                (header (treesit-node-child table 0 t))
                ((member (treesit-node-type header)
                         '("bare_key" "quoted_key")))
                (header-text (toml-ts-cargo--key-text header))
                ((member header-text toml-ts-cargo--dependency-table-names))
                (key-node (treesit-node-child pair 0 t))
                (crate-name (and key-node (toml-ts-cargo--key-text key-node))))
      (format toml-ts-cargo-crate-url-template crate-name))))


;;; Minor mode

(defvar-keymap toml-ts-cargo-mode-map
  :doc "Keymap for `toml-ts-cargo-mode'."
  "RET" #'toml-ts-cargo-browse-at-point)

(defun toml-ts-cargo-browse-at-point ()
  "Open the crates.io URL for the crate dependency at point in a browser."
  (interactive)
  (if-let* ((url (thing-at-point 'url)))
      (browse-url url)
    (user-error "No crate URL at point")))

;;;###autoload
(define-minor-mode toml-ts-cargo-mode
  "Minor mode for Cargo.toml enhancements in `toml-ts-mode' buffers.

When enabled, this mode:
  - Underlines dependency keys in dependencies, dev-dependencies and
    build-dependencies tables.
  - Makes `thing-at-point' return crates.io URLs for those keys.
  - Pressing RET on a dependency key opens it on crates.io."
  :lighter " Cargo"
  :keymap toml-ts-cargo-mode-map
  (if toml-ts-cargo-mode
      (toml-ts-cargo--enable)
    (toml-ts-cargo--disable)))

(defun toml-ts-cargo--enable ()
  "Register URL provider and treesit font-lock rules."
  ;; URL provider
  (setq-local thing-at-point-provider-alist
              (cons '(url . toml-ts-cargo--url-provider)
                    thing-at-point-provider-alist))
  ;; Treesit font-lock rules
  (when toml-ts-cargo-highlight-dependencies
    (setq-local treesit-font-lock-settings
                (append treesit-font-lock-settings
                        toml-ts-cargo--font-lock-rules))
    (add-to-list 'treesit-font-lock-feature-list '(cargo-dependency))
    (treesit-font-lock-recompute-features)
    (font-lock-flush)
    (font-lock-ensure)))

(defun toml-ts-cargo--disable ()
  "Unregister URL provider and treesit font-lock rules."
  ;; URL provider
  (setq-local thing-at-point-provider-alist
              (assq-delete-all 'url thing-at-point-provider-alist))
  ;; Treesit font-lock rules
  (when toml-ts-cargo-highlight-dependencies
    (let ((new-settings nil))
      (dolist (setting treesit-font-lock-settings)
        (unless (eq (plist-get (cdr setting) :feature) 'cargo-dependency)
          (push setting new-settings)))
      (setq-local treesit-font-lock-settings (nreverse new-settings)))
    (setq-local treesit-font-lock-feature-list
                (remove '(cargo-dependency) treesit-font-lock-feature-list))
    (treesit-font-lock-recompute-features)
    (font-lock-flush)
    (font-lock-ensure)))

(provide 'toml-ts-cargo-mode)
;;; toml-ts-cargo-mode.el ends here
