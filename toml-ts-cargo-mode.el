;;; toml-ts-cargo-mode.el --- Cargo.toml features for toml-ts-mode -*- lexical-binding: t -*-

;; Copyright (C) 2026

;; Author: TOML TS Cargo Mode Maintainers
;; Version: 0.1.0
;; Keywords: languages, tools
;; Package-Requires: ((emacs "29.1"))

;;; Commentary:

;; This package provides `toml-ts-cargo-mode', a minor mode that adds
;; Cargo.toml-specific enhancements to `toml-ts-mode' buffers:
;;
;;   - URL detection: `thing-at-point' for 'url returns the crates.io
;;     page for the crate whose dependency key is under point.
;;
;;   - Underline highlighting: dependency keys are underlined during
;;     font-lock by applying `font-lock-face' via
;;     `font-lock-append-text-property' inside a wrapper around
;;     `font-lock-fontify-region-function'.
;;
;; Usage:
;;     (add-hook 'toml-ts-mode-hook
;;               (lambda ()
;;                 (when (string-match-p "/Cargo\\.toml\\'" buffer-file-name)
;;                   (toml-ts-cargo-mode 1))))

;;; Code:

(require 'toml-ts-mode)
(require 'thingatpt)
(require 'subr-x)

(defgroup toml-ts-cargo nil
  "Cargo.toml support for `toml-ts-mode'."
  :group 'toml-ts-mode
  :prefix "toml-ts-cargo-")

(defcustom toml-ts-cargo-crate-url-template
  "https://crates.io/crates/%s"
  "URL template for crate dependencies."
  :type 'string
  :group 'toml-ts-cargo)

(defcustom toml-ts-cargo-dependency-tables
  '("dependencies")
  "List of TOML table names that contain crate-level dependencies.
Only exact (non-dotted) table names match."
  :type '(repeat string)
  :group 'toml-ts-cargo)

(defcustom toml-ts-cargo-highlight-dependencies t
  "When non-nil, underline dependency keys."
  :type 'boolean
  :group 'toml-ts-cargo)

(defface toml-ts-cargo-dependency-key-face
  '((t :underline t :inherit (font-lock-property-use-face)))
  "Face for crate dependency keys."
  :group 'toml-ts-cargo)

(defvar-local toml-ts-cargo--saved-fontify-function nil
  "Saved original `font-lock-fontify-region-function'.")


;;;###autoload
(define-minor-mode toml-ts-cargo-mode
  "Minor mode for Cargo.toml enhancements in `toml-ts-mode' buffers."
  :lighter " Cargo"
  (if toml-ts-cargo-mode
      (toml-ts-cargo--enable)
    (toml-ts-cargo--disable)))

(defun toml-ts-cargo--enable ()
  "Register URL provider and font-lock wrapper."
  (setq-local thing-at-point-provider-alist
              (cons '(url . toml-ts-cargo--url-provider)
                    thing-at-point-provider-alist))
  (when toml-ts-cargo-highlight-dependencies
    (setq-local toml-ts-cargo--saved-fontify-function
                font-lock-fontify-region-function)
    (setq-local font-lock-fontify-region-function
                #'toml-ts-cargo--fontify-region-wrapper)))

(defun toml-ts-cargo--disable ()
  "Unregister URL provider and restore original font-lock function."
  (setq-local thing-at-point-provider-alist
              (assq-delete-all 'url thing-at-point-provider-alist))
  (when toml-ts-cargo--saved-fontify-function
    (setq-local font-lock-fontify-region-function
                toml-ts-cargo--saved-fontify-function)
    (kill-local-variable 'toml-ts-cargo--saved-fontify-function)
    ;; Re-fontify with the restored (original) function to clear
    ;; our underline faces.
    (font-lock-flush)
    (font-lock-ensure)))

(defun toml-ts-cargo--fontify-region-wrapper (beg end loudly)
  "Fontify BEG..END: treesit pass first, then our underline pass."
  (funcall toml-ts-cargo--saved-fontify-function beg end loudly)
  (toml-ts-cargo--fontify-dependency-keys beg end))


;;; Tree-sitter helpers (shared between URL provider and fontify pass)

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

(defun toml-ts-cargo--table-header-text (table-node)
  "Return (NAME . TYPE) for TABLE-NODE's header."
  (when table-node
    (let ((header (treesit-node-child table-node 0 t)))
      (when header
        (cons (toml-ts-cargo--key-text header)
              (treesit-node-type header))))))

(defun toml-ts-cargo--in-dependency-table-p (node)
  "Return non-nil if NODE is inside a configured dependency table."
  (let ((table (treesit-parent-until
                node
                (lambda (n)
                  (member (treesit-node-type n)
                          '("table" "table_array_element"))))))
    (when table
      (pcase-let ((`(,name . ,header-type)
                   (toml-ts-cargo--table-header-text table)))
        (and name
             (member header-type '("bare_key" "quoted_key"))
             (member name toml-ts-cargo-dependency-tables))))))

(defun toml-ts-cargo--pair-key-node (pair-node)
  "Return the key node from PAIR-NODE."
  (treesit-node-child pair-node 0 t))

(defun toml-ts-cargo--pair-key-name (pair-node)
  "Return the crate name string from PAIR-NODE's key."
  (let ((key-node (toml-ts-cargo--pair-key-node pair-node)))
    (when key-node
      (toml-ts-cargo--key-text key-node))))

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


;;; URL provider

(defun toml-ts-cargo--url-provider ()
  "Return a crates.io URL if point is on a dependency key."
  (when (and toml-ts-cargo-mode
             (derived-mode-p 'toml-ts-mode)
             (treesit-ready-p 'toml t))
    (let ((node (treesit-node-at (point))))
      (when node
        (when-let* ((pair (toml-ts-cargo--find-table-pair node))
                    (crate-name (toml-ts-cargo--pair-key-name pair)))
          (when (toml-ts-cargo--in-dependency-table-p pair)
            (format toml-ts-cargo-crate-url-template crate-name)))))))


;;; Font-lock underline pass

(defun toml-ts-cargo--fontify-dependency-keys (beg end)
  "Add underline face to dependency keys between BEG and END.
Called from the font-lock wrapper after treesit fontification.
Uses `font-lock-append-text-property' to add our face after
existing `font-lock-face' properties so our :underline wins.
because `inhibit-modification-hooks' is t at that point."
  (save-excursion
    (goto-char beg)
    (while (< (point) end)
      (if-let* ((node (treesit-node-at (point)))
                (pair (toml-ts-cargo--find-table-pair node))
                ((toml-ts-cargo--in-dependency-table-p pair))
                (key-node (toml-ts-cargo--pair-key-node pair)))
          (let ((kstart (treesit-node-start key-node))
                (kend   (treesit-node-end key-node))
                (pair-end (treesit-node-end pair)))
            (if (and kstart kend (> kend (point)))
                ;; Fresh key: apply underline and skip past it.
                (progn
                  (font-lock-append-text-property
                   kstart kend
                   'font-lock-face
                   'toml-ts-cargo-dependency-key-face)
                  (if pair-end
                      (goto-char pair-end)
                    (goto-char kend)))
              ;; Already past this key: skip the whole pair.
              (if pair-end
                  (goto-char pair-end)
                (forward-char 1))))
        ;; Not on a dependency pair: advance one char.
        (forward-char 1)))))

(provide 'toml-ts-cargo-mode)
;;; toml-ts-cargo-mode.el ends here
