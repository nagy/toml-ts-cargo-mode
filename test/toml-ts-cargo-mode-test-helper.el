;;; toml-ts-cargo-mode-test-helper.el --- Shared ERT fixtures  -*- lexical-binding: t -*-

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

;;; Commentary:

;; Helpers shared by the ERT files under test/.  The file name must not
;; match `*-test.el', so the glob loader never treats it as a test file.

;;; Code:

(require 'toml-ts-mode)
(require 'toml-ts-cargo-mode)

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

(provide 'toml-ts-cargo-mode-test-helper)
;;; toml-ts-cargo-mode-test-helper.el ends here
