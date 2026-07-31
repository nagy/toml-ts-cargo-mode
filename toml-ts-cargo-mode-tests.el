;;; toml-ts-cargo-mode-tests.el --- Tests for toml-ts-cargo-mode -*- lexical-binding: t -*-

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

;; To run these tests:
;;
;;   (require 'toml-ts-cargo-mode)
;;   (require 'ert)
;;
;; Then: M-x ert RET t

(require 'toml-ts-cargo-mode)
(require 'ert)
(require 'cl-lib)

;;; Helpers

(defmacro toml-ts-cargo-test--with-cargo-buffer (content &rest body)
  "Create a temporary `toml-ts-mode' buffer with CONTENT and run BODY.
Enables `toml-ts-cargo-mode' and cleans up afterwards."
  (declare (indent 1))
  `(let ((buf (generate-new-buffer " *toml-ts-cargo-test*")))
     (with-current-buffer buf
       (toml-ts-mode)
       (insert ,content)
       (goto-char (point-min))
       (toml-ts-cargo-mode 1)
       (setq buffer-file-name "/tmp/Cargo.toml"))
     (unwind-protect
         (with-current-buffer buf ,@body)
       (kill-buffer buf))))

(defun toml-ts-cargo-test--url-at (text)
  "Return `thing-at-point' for 'url at the first occurrence of TEXT."
  (goto-char (point-min))
  (search-forward text)
  (goto-char (match-beginning 0))
  (thing-at-point 'url))

;;; URL detection — basic

(ert-deftest toml-ts-cargo-url-at-dependency-key ()
  "URL detection works on bare dependency keys."
  (skip-unless (treesit-ready-p 'toml))
  (toml-ts-cargo-test--with-cargo-buffer
      "[dependencies]\nbase64 = \"0.22\"\nevents = \"1\"\n"
    (should (equal (toml-ts-cargo-test--url-at "base64")
                   "https://crates.io/crates/base64"))
    (should (equal (toml-ts-cargo-test--url-at "events")
                   "https://crates.io/crates/events"))))

(ert-deftest toml-ts-cargo-url-on-value ()
  "URL detection works when point is on the version string."
  (skip-unless (treesit-ready-p 'toml))
  (toml-ts-cargo-test--with-cargo-buffer
      "[dependencies]\nbase64 = \"0.22\"\n"
    (should (equal (toml-ts-cargo-test--url-at "0.22")
                   "https://crates.io/crates/base64"))))

(ert-deftest toml-ts-cargo-url-not-in-dependencies ()
  "Point on a key in a non-dependencies table should NOT return a URL."
  (skip-unless (treesit-ready-p 'toml))
  (toml-ts-cargo-test--with-cargo-buffer
      "[package]\nname = \"my-crate\"\nversion = \"0.1.0\"\n"
    (should-not (toml-ts-cargo-test--url-at "name"))))

(ert-deftest toml-ts-cargo-url-in-dependencies-subtable ()
  "Keys inside [dependencies.serde] should NOT return URLs.
Features are not crate-level dependencies."
  (skip-unless (treesit-ready-p 'toml))
  (toml-ts-cargo-test--with-cargo-buffer
      "[dependencies]\nserde = { version = \"1\", features = [\"derive\"] }\n[dependencies.serde]\nfeatures = [\"derive\"]\n"
    (goto-char (point-min))
    (search-forward "[dependencies.serde]")
    (search-forward "features")
    (goto-char (match-beginning 0))
    (should-not (thing-at-point 'url))))

(ert-deftest toml-ts-cargo-url-with-dotted-key ()
  "Dotted crate keys resolve to the first component."
  (skip-unless (treesit-ready-p 'toml))
  (toml-ts-cargo-test--with-cargo-buffer
      "[dependencies]\ncrate-name.feature = true\n"
    (should (equal (toml-ts-cargo-test--url-at "crate-name")
                   "https://crates.io/crates/crate-name"))))

(ert-deftest toml-ts-cargo-url-quoted-key ()
  "Quoted dependency keys work."
  (skip-unless (treesit-ready-p 'toml))
  (toml-ts-cargo-test--with-cargo-buffer
      "[dependencies]\n\"some-crate\" = \"1.0\"\n"
    (should (equal (toml-ts-cargo-test--url-at "some-crate")
                   "https://crates.io/crates/some-crate"))))

(ert-deftest toml-ts-cargo-url-dev-dependencies ()
  "URL detection works in dev-dependencies tables."
  (skip-unless (treesit-ready-p 'toml))
  (toml-ts-cargo-test--with-cargo-buffer
      "[dev-dependencies]\ntest-crate = \"0.5\"\n"
    (should (equal (toml-ts-cargo-test--url-at "test-crate")
                   "https://crates.io/crates/test-crate"))))

(ert-deftest toml-ts-cargo-url-build-dependencies ()
  "URL detection works in build-dependencies."
  (skip-unless (treesit-ready-p 'toml))
  (toml-ts-cargo-test--with-cargo-buffer
      "[build-dependencies]\ncc = \"1\"\n"
    (should (equal (toml-ts-cargo-test--url-at "cc")
                   "https://crates.io/crates/cc"))))

;;; URL detection — workspace / target / sub-table header

(ert-deftest toml-ts-cargo-url-workspace-dependencies ()
  "URL detection works in [workspace.dependencies]."
  (skip-unless (treesit-ready-p 'toml))
  (toml-ts-cargo-test--with-cargo-buffer
      "[workspace.dependencies]\nserde = \"1\"\n"
    (should (equal (toml-ts-cargo-test--url-at "serde")
                   "https://crates.io/crates/serde"))))

(ert-deftest toml-ts-cargo-url-target-dependencies ()
  "URL detection works in [target.'cfg(unix)'.dependencies]."
  (skip-unless (treesit-ready-p 'toml))
  (toml-ts-cargo-test--with-cargo-buffer
      "[target.'cfg(unix)'.dependencies]\nlibc = \"0.2\"\n"
    (should (equal (toml-ts-cargo-test--url-at "libc")
                   "https://crates.io/crates/libc"))))

;;; URL detection — custom template

(ert-deftest toml-ts-cargo-url-custom-template ()
  "Custom URL template is respected."
  (skip-unless (treesit-ready-p 'toml))
  (let ((toml-ts-cargo-crate-url-template "https://lib.rs/%s"))
    (toml-ts-cargo-test--with-cargo-buffer
        "[dependencies]\nbase64 = \"0.22\"\n"
      (setq-local toml-ts-cargo-crate-url-template "https://lib.rs/%s")
      (should (equal (toml-ts-cargo-test--url-at "base64")
                     "https://lib.rs/base64")))))

;;; Disable

(ert-deftest toml-ts-cargo-mode-disable ()
  "Disabling the mode restores default URL detection."
  (skip-unless (treesit-ready-p 'toml))
  (toml-ts-cargo-test--with-cargo-buffer
      "[dependencies]\nbase64 = \"0.22\"\n"
    (should (toml-ts-cargo-test--url-at "base64"))
    (toml-ts-cargo-mode -1)
    (should-not (toml-ts-cargo-test--url-at "base64"))))

;;; Font-lock highlighting

(ert-deftest toml-ts-cargo-font-lock-dependency-key ()
  "The crate-key predicate correctly identifies only toplevel dep keys."
  (skip-unless (treesit-ready-p 'toml))
  (with-temp-buffer
    (toml-ts-mode)
    (insert "[dependencies]\nserde = \"1\"\n[package]\nname = \"x\"\n")
    (treesit-parser-create 'toml)
    (goto-char (point-min))
    (search-forward "serde")
    (goto-char (match-beginning 0))
    (should (toml-ts-cargo--crate-key-p
             (treesit-node-child
              (treesit-parent-until
               (treesit-node-at (point))
               (lambda (n) (equal (treesit-node-type n) "pair")))
              0 t)))
    (goto-char (point-min))
    (search-forward "name")
    (goto-char (match-beginning 0))
    (should-not (toml-ts-cargo--crate-key-p
                 (treesit-node-child
                  (treesit-parent-until
                   (treesit-node-at (point))
                   (lambda (n) (equal (treesit-node-type n) "pair")))
                  0 t)))))

(ert-deftest toml-ts-cargo-fontify-only-captured-node ()
  "Fontify the captured node only, never the whole fontify region.

Regression test: the fontify function used to pass the fontify
region START/END to `treesit-fontify-with-override', painting
the whole buffer whenever one dep key matched."
  (skip-unless (treesit-ready-p 'toml))
  (with-temp-buffer
    (toml-ts-mode)
    (insert "[dependencies]\nserde = \"1\"\n[package]\nname = \"x\"\n")
    (treesit-parser-create 'toml)
    (goto-char (point-min))
    (search-forward "serde")
    (goto-char (match-beginning 0))
    (let* ((node (treesit-node-at (point)))
           (pair (treesit-parent-until
                  node (lambda (n) (equal (treesit-node-type n) "pair"))))
           (key (treesit-node-child pair 0 t)))
      ;; Simulate the font-lock engine: whole buffer as region bounds.
      (toml-ts-cargo--fontify-crate-key key t (point-min) (point-max))
      ;; Only the key itself should carry the cargo face.
      (should (eq (get-text-property (treesit-node-start key) 'face)
                   'toml-ts-cargo-dependency-key-face))
      ;; ...and nothing outside the key's own bounds.
      (should-not (get-text-property (1- (treesit-node-start key)) 'face))
      (should-not (get-text-property (treesit-node-end key) 'face)))))

(ert-deftest toml-ts-cargo-font-lock-region-bounds ()
  "Full font-lock pass paints the cargo face exactly on crate keys.

Integration test: catches both the whole-region clobber bug and
keys in sub-tables (e.g. [dependencies.serde]) being underlined."
  (skip-unless (treesit-ready-p 'toml))
  (with-temp-buffer
    (toml-ts-mode)
    (insert (concat "[dependencies]\nserde = \"1\"\n"
                    "base64 = { version = \"0.22\" }\n"
                    "[package]\nname = \"x\"\nversion = \"0.1\"\n"
                    "[dependencies.serde]\nfeatures = [\"derive\"]\n"))
    (treesit-parser-create 'toml)
    (toml-ts-cargo-mode 1)
    (font-lock-ensure)
    (let ((regions nil)
          (last-face nil)
          (last-start (point-min)))
      ;; Collect contiguous runs of the cargo face as (start . end).
      (goto-char (point-min))
      (while (< (point) (point-max))
        (let ((face (get-text-property (point) 'face)))
          (cond
           ((and (eq face 'toml-ts-cargo-dependency-key-face)
                 (not (eq last-face 'toml-ts-cargo-dependency-key-face)))
            (setq last-start (point))
            (setq last-face face))
           ((and (not (eq face 'toml-ts-cargo-dependency-key-face))
                 (eq last-face 'toml-ts-cargo-dependency-key-face))
            (push (cons last-start (point)) regions)
            (setq last-face nil))
           (t nil)))
        (forward-char 1))
      (when (eq last-face 'toml-ts-cargo-dependency-key-face)
        (push (cons last-start (point-max)) regions))
      (setq regions (nreverse regions))
      ;; Exactly two cargo-face runs: "serde" and "base64".
      (should (equal (mapcar
                      (lambda (r) (buffer-substring (car r) (cdr r)))
                      regions)
                     '("serde" "base64"))))))

;;; Mode hygiene

(ert-deftest toml-ts-cargo-mode-idempotent ()
  "Enabling the mode twice does not duplicate URL providers."
  (skip-unless (treesit-ready-p 'toml))
  (toml-ts-cargo-test--with-cargo-buffer
      "[dependencies]\nbase64 = \"0.22\"\n"
    (toml-ts-cargo-mode 1)
    (let ((count (cl-count '(url . toml-ts-cargo--url-provider)
                           thing-at-point-provider-alist
                           :test #'equal)))
      (should (= count 1)))))

(ert-deftest toml-ts-cargo-mode-preserves-other-providers ()
  "Disabling the mode does not remove other thing-at-point providers."
  (skip-unless (treesit-ready-p 'toml))
  (toml-ts-cargo-test--with-cargo-buffer
      "[dependencies]\nbase64 = \"0.22\"\n"
    (setq-local thing-at-point-provider-alist
                (cons '(url . my-other-provider)
                      thing-at-point-provider-alist))
    (toml-ts-cargo-mode -1)
    (should (assq 'url thing-at-point-provider-alist))
    (should (eq (cdr (assq 'url thing-at-point-provider-alist))
                #'my-other-provider))))

;;; toml-ts-cargo-maybe-enable

(ert-deftest toml-ts-cargo-maybe-enable-matches ()
  "`toml-ts-cargo-maybe-enable' activates for Cargo.toml paths."
  (skip-unless (treesit-ready-p 'toml))
  (toml-ts-cargo-test--with-cargo-buffer
      "[dependencies]\nbase64 = \"0.22\"\n"
    (setq buffer-file-name "/home/user/Cargo.toml")
    (toml-ts-cargo-mode -1)
    (toml-ts-cargo-maybe-enable)
    (should toml-ts-cargo-mode)))

(ert-deftest toml-ts-cargo-maybe-enable-no-match ()
  "`toml-ts-cargo-maybe-enable' ignores non-Cargo files."
  (skip-unless (treesit-ready-p 'toml))
  (toml-ts-cargo-test--with-cargo-buffer
      "[dependencies]\nbase64 = \"0.22\"\n"
    (setq buffer-file-name "/home/user/package.toml")
    (toml-ts-cargo-mode -1)
    (toml-ts-cargo-maybe-enable)
    (should-not toml-ts-cargo-mode)))

(ert-deftest toml-ts-cargo-maybe-enable-nil-safe ()
  "`toml-ts-cargo-maybe-enable' is safe with nil buffer-file-name."
  (skip-unless (treesit-ready-p 'toml))
  (toml-ts-cargo-test--with-cargo-buffer
      "[dependencies]\nbase64 = \"0.22\"\n"
    (setq buffer-file-name nil)
    (should-not (toml-ts-cargo-maybe-enable))))

(provide 'toml-ts-cargo-mode-tests)
;;; toml-ts-cargo-mode-tests.el ends here
