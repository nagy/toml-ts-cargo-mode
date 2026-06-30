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

;;; Helper: create a toml-ts-mode buffer with content and return it.
(defun toml-ts-cargo-test--with-cargo-buffer (content)
  "Create a temporary `toml-ts-mode' buffer with CONTENT.
Enables `toml-ts-cargo-mode', moves point to the beginning, and
returns the buffer."
  (let ((buf (generate-new-buffer " *toml-ts-cargo-test*")))
    (with-current-buffer buf
      (toml-ts-mode)
      (insert content)
      (goto-char (point-min))
      (toml-ts-cargo-mode 1)
      (setq buffer-file-name "/tmp/Cargo.toml"))
    buf))

;;; Tests

(ert-deftest toml-ts-cargo-url-at-dependency-key ()
  "Test URL detection when point is on a bare dependency key."
  (skip-unless (treesit-ready-p 'toml))
  (let ((buf (toml-ts-cargo-test--with-cargo-buffer
              "[dependencies]\nbase64 = \"0.22\"\nevents = \"1\"\n")))
    (with-current-buffer buf
      ;; Point on 'base64'
      (goto-char (point-min))
      (search-forward "base64")
      (goto-char (match-beginning 0))
      (should (equal (thing-at-point 'url)
                     "https://crates.io/crates/base64"))
      ;; Point on 'events'
      (goto-char (point-min))
      (search-forward "events")
      (goto-char (match-beginning 0))
      (should (equal (thing-at-point 'url)
                     "https://crates.io/crates/events")))
    (kill-buffer buf)))

(ert-deftest toml-ts-cargo-url-on-value ()
  "Point on the version string should still resolve to the crate URL.
The pair key base64 is found via \=`treesit-parent-until\=' from the
value node up to the enclosing pair."
  (skip-unless (treesit-ready-p 'toml))
  (let ((buf (toml-ts-cargo-test--with-cargo-buffer
              "[dependencies]\nbase64 = \"0.22\"\n")))
    (with-current-buffer buf
      (goto-char (point-min))
      (search-forward "0.22")
      (goto-char (match-beginning 0))
      (should (equal (thing-at-point 'url)
                     "https://crates.io/crates/base64")))
    (kill-buffer buf)))

(ert-deftest toml-ts-cargo-url-not-in-dependencies ()
  "Point on a key in a non-dependencies table should NOT return a URL."
  (skip-unless (treesit-ready-p 'toml))
  (let ((buf (toml-ts-cargo-test--with-cargo-buffer
              "[package]\nname = \"my-crate\"\nversion = \"0.1.0\"\n")))
    (with-current-buffer buf
      (goto-char (point-min))
      (search-forward "name")
      (goto-char (match-beginning 0))
      (should-not (thing-at-point 'url)))
    (kill-buffer buf)))

(ert-deftest toml-ts-cargo-url-in-dependencies-subtable ()
  "Keys inside [dependencies.serde] should NOT return URLs for the sub-keys.
\(Features are not crate-level dependencies.)"
  (skip-unless (treesit-ready-p 'toml))
  (let ((buf (toml-ts-cargo-test--with-cargo-buffer
              "[dependencies]\nserde = { version = \"1\", features = [\"derive\"] }\n[dependencies.serde]\nfeatures = [\"derive\"]\n")))
    (with-current-buffer buf
      ;; The 'features' key inside [dependencies.serde] is not a crate dep
      (goto-char (point-min))
      (search-forward "[dependencies.serde]")
      (search-forward "features")
      (goto-char (match-beginning 0))
      (should-not (thing-at-point 'url)))
    (kill-buffer buf)))

(ert-deftest toml-ts-cargo-url-with-dotted-key ()
  "Dotted crate keys should resolve to the first component."
  (skip-unless (treesit-ready-p 'toml))
  (let ((buf (toml-ts-cargo-test--with-cargo-buffer
              "[dependencies]\ncrate-name.feature = true\n")))
    (with-current-buffer buf
      (goto-char (point-min))
      (search-forward "crate-name")
      (goto-char (match-beginning 0))
      (should (equal (thing-at-point 'url)
                     "https://crates.io/crates/crate-name")))
    (kill-buffer buf)))

(ert-deftest toml-ts-cargo-url-quoted-key ()
  "Quoted dependency keys should work."
  (skip-unless (treesit-ready-p 'toml))
  (let ((buf (toml-ts-cargo-test--with-cargo-buffer
              "[dependencies]\n\"some-crate\" = \"1.0\"\n")))
    (with-current-buffer buf
      (goto-char (point-min))
      (search-forward "some-crate")
      (goto-char (match-beginning 0))
      (should (equal (thing-at-point 'url)
                     "https://crates.io/crates/some-crate")))
    (kill-buffer buf)))

(ert-deftest toml-ts-cargo-url-dev-dependencies ()
  "URL detection works in dev-dependencies tables."
  (skip-unless (treesit-ready-p 'toml))
  (let ((buf (toml-ts-cargo-test--with-cargo-buffer
              "[dev-dependencies]\ntest-crate = \"0.5\"\n")))
    (with-current-buffer buf
      (goto-char (point-min))
      (search-forward "test-crate")
      (goto-char (match-beginning 0))
      (should (equal (thing-at-point 'url)
                     "https://crates.io/crates/test-crate")))
    (kill-buffer buf)))

(ert-deftest toml-ts-cargo-url-custom-template ()
  "Custom URL template should be respected."
  (skip-unless (treesit-ready-p 'toml))
  (let ((toml-ts-cargo-crate-url-template "https://lib.rs/%s"))
    (let ((buf (toml-ts-cargo-test--with-cargo-buffer
                "[dependencies]\nbase64 = \"0.22\"\n")))
      (with-current-buffer buf
        (setq-local toml-ts-cargo-crate-url-template "https://lib.rs/%s")
        (toml-ts-cargo--disable)
        (toml-ts-cargo--enable)
        (goto-char (point-min))
        (search-forward "base64")
        (goto-char (match-beginning 0))
        (should (equal (thing-at-point 'url)
                       "https://lib.rs/base64")))
      (kill-buffer buf))))

(ert-deftest toml-ts-cargo-mode-disable ()
  "Disabling the mode should restore default URL detection."
  (skip-unless (treesit-ready-p 'toml))
  (let ((buf (toml-ts-cargo-test--with-cargo-buffer
              "[dependencies]\nbase64 = \"0.22\"\n")))
    (with-current-buffer buf
      (goto-char (point-min))
      (search-forward "base64")
      (goto-char (match-beginning 0))
      (should (thing-at-point 'url))
      ;; Disable and verify no URL detection
      (toml-ts-cargo-mode -1)
      (should-not (thing-at-point 'url)))
    (kill-buffer buf)))


(ert-deftest toml-ts-cargo-browse-at-point ()
  "Pressing RET on a dependency key should call browse-url with the crates.io URL."
  (skip-unless (treesit-ready-p 'toml))
  (let ((browse-url-called nil)
        (browse-url-arg nil))
    (cl-letf (((symbol-function 'browse-url)
               (lambda (url)
                 (setq browse-url-called t
                       browse-url-arg url))))
      (let ((buf (toml-ts-cargo-test--with-cargo-buffer
                  "[dependencies]\nbase64 = \"0.22\"\n")))
        (with-current-buffer buf
          (goto-char (point-min))
          (search-forward "base64")
          (goto-char (match-beginning 0))
          (toml-ts-cargo-browse-at-point)
          (should browse-url-called)
          (should (equal browse-url-arg
                         "https://crates.io/crates/base64")))
        (kill-buffer buf)))))

(ert-deftest toml-ts-cargo-browse-at-point-no-crate ()
  "Pressing RET on non-crate text should signal an error."
  (skip-unless (treesit-ready-p 'toml))
  (let ((buf (toml-ts-cargo-test--with-cargo-buffer
              "[package]\nname = \"my-crate\"\n")))
    (with-current-buffer buf
      (goto-char (point-min))
      (search-forward "name")
      (goto-char (match-beginning 0))
      (should-error (toml-ts-cargo-browse-at-point)))
    (kill-buffer buf)))

(provide 'toml-ts-cargo-mode-tests)
;;; toml-ts-cargo-mode-tests.el ends here
