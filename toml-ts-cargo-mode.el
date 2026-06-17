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
;;     font-lock by registering custom `treesit-font-lock-rules' with
;;     a function capture that checks whether the pair is inside a
;;     configured dependency table.
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


;;; Tree-sitter helpers (shared between URL provider and font-lock rules)

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


;;; Font-lock function capture

(defun toml-ts-cargo--fontify-key (node override start end)
  "Fontify NODE with `toml-ts-cargo-dependency-key-face' if inside a
dependency table.  NODE is the captured key node.  OVERRIDE, START,
and END are passed by the treesit font-lock engine."
  (when (toml-ts-cargo--in-dependency-table-p node)
    (treesit-fontify-with-override
     (treesit-node-start node) (treesit-node-end node)
     'toml-ts-cargo-dependency-key-face
     override start end)))


;;; Treesit font-lock rules

(defvar toml-ts-cargo--font-lock-rules
  (treesit-font-lock-rules
   :language 'toml
   :override t
   :feature 'cargo-dependency
   ;; Pairs directly inside tables or table-array-elements (not inline_tables).
   ;; The capture name matches the function above, not a face – Emacs
   ;; falls back to calling it as (node override start end).
   '((table (pair (bare_key) @toml-ts-cargo--fontify-key))
     (table (pair (quoted_key) @toml-ts-cargo--fontify-key))
     (table (pair (dotted_key) @toml-ts-cargo--fontify-key))
     (table_array_element (pair (bare_key) @toml-ts-cargo--fontify-key))
     (table_array_element (pair (quoted_key) @toml-ts-cargo--fontify-key))
     (table_array_element (pair (dotted_key) @toml-ts-cargo--fontify-key))))
  "Treesit font-lock rules for Cargo.toml dependency-key highlighting.")


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


;;; Minor mode

;;;###autoload
(define-minor-mode toml-ts-cargo-mode
  "Minor mode for Cargo.toml enhancements in `toml-ts-mode' buffers."
  :lighter " Cargo"
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
    (unless (toml-ts-cargo--feature-registered-p)
      ;; Append our rules to the buffer-local font-lock settings.
      (setq-local treesit-font-lock-settings
                  (append treesit-font-lock-settings
                          toml-ts-cargo--font-lock-rules))
      ;; Register our feature so Emacs activates it at level 1+.
      (setq-local treesit-font-lock-feature-list
                  (cons (cons 'cargo-dependency
                              (car treesit-font-lock-feature-list))
                        (cdr treesit-font-lock-feature-list)))
      ;; Recompute and re-fontify.
      (treesit-font-lock-recompute-features)
      (font-lock-flush)
      (font-lock-ensure))))

(defun toml-ts-cargo--disable ()
  "Unregister URL provider and treesit font-lock rules."
  ;; URL provider
  (setq-local thing-at-point-provider-alist
              (assq-delete-all 'url thing-at-point-provider-alist))
  ;; Treesit font-lock rules
  (when toml-ts-cargo-highlight-dependencies
    ;; Remove our rules from settings.
    (let ((new-settings nil))
      (dolist (setting treesit-font-lock-settings)
        (unless (eq (plist-get (cdr setting) :feature) 'cargo-dependency)
          (push setting new-settings)))
      (setq-local treesit-font-lock-settings (nreverse new-settings)))
    ;; Remove our feature from each decoration level.
    (let ((new-features nil))
      (dolist (level treesit-font-lock-feature-list)
        (push (assq-delete-all 'cargo-dependency level) new-features))
      (setq-local treesit-font-lock-feature-list (nreverse new-features)))
    ;; Recompute and re-fontify (clears our faces).
    (treesit-font-lock-recompute-features)
    (font-lock-flush)
    (font-lock-ensure)))

(defun toml-ts-cargo--feature-registered-p ()
  "Return non-nil if the `cargo-dependency' feature is already registered."
  (catch 'found
    (dolist (level treesit-font-lock-feature-list)
      (when (assq 'cargo-dependency level)
        (throw 'found t)))
    nil))

(provide 'toml-ts-cargo-mode)
;;; toml-ts-cargo-mode.el ends here
