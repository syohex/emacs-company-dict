;;; company-dict.el --- A backend that emulates ac-source-dictionary
;;
;; Copyright (C) 2015-16 Henrik Lissner

;; Author: Henrik Lissner <http://github/hlissner>
;; Maintainer: Henrik Lissner <henrik@lissner.net>
;; Created: June 21, 2015
;; Modified: May 21, 2016
;; Version: 1.2.2
;; Keywords: company dictionary ac-source-dictionary
;; Homepage: https://github.com/hlissner/emacs-company-dict
;; Package-Requires: ((company "0.8.12") (cl-lib "0.5"))
;;
;; This file is not part of GNU Emacs.
;;
;;; Code:

(require 'company)
(eval-when-compile (require 'cl-lib))
(eval-when-compile (require 'subr-x))

(defgroup company-dict nil
  "A backend that mimics ac-source-dictionary, with support for annotations and
documentation."
  :prefix "company-dict-"
  :group 'company)

(defcustom company-dict-dir (concat user-emacs-directory "dict/")
  "Directory to look for dictionary files."
  :group 'company-dict
  :type 'directory)

(defcustom company-dict-minor-mode-list '()
  "A list of minor modes to be aware of when looking up dictionaries (if they're active)."
  :group 'company-dict
  :type '(repeat symbol))

(defcustom company-dict-fuzzy nil
  "Whether to allow fuzzy searching for company-dict."
  :group 'company-dict)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar company-dict-table (make-hash-table :test 'equal)
  "A lookup hash table that maps major (or minor) modes to lists of completion candidates.")

(defun company-dict--read-file (file-path)
  (when (file-exists-p file-path)
    (decode-coding-string
     (with-temp-buffer
       (set-buffer-multibyte nil)
       (setq buffer-file-coding-system 'binary)
       (insert-file-contents-literally file-path)
       (buffer-substring-no-properties (point-min) (point-max))) 'utf-8)))

(defun company-dict--relevant-modes ()
  (append `(all ,major-mode) company-dict-minor-mode-list))

(defun company-dict--relevant-dicts ()
  "Merge all dicts together into one large list."
  (let ((dicts (append (gethash 'all company-dict-table)
                       (gethash major-mode company-dict-table))))
    (mapc (lambda (mode)
            (when (and (boundp mode) (symbol-value mode))
              (setq dicts (append dicts (gethash mode company-dict-table)))))
          company-dict-minor-mode-list)
    dicts))

(defun company-dict--init (mode)
  "Read dict files and populate dictionary."
  (let ((file (expand-file-name (symbol-name mode) company-dict-dir))
        result)
    (unless (gethash mode company-dict-table)
      (when (company-dict--read-file file)
        (mapc (lambda (line)
                (unless (string-empty-p line)
                  (let ((l (split-string (string-trim-right line) "\t" t)))
                    (push (propertize (nth 0 l) :note (nth 1 l) :meta (nth 2 l))
                          result))))
              (split-string (company-dict--read-file file) "\n" nil))
        (puthash mode result company-dict-table)))
    result))

(defun company-dict--annotation (data)
  (get-text-property 0 :note data))

(defun company-dict--meta (data)
  (get-text-property 0 :meta data))

;;;###autoload
(defun company-dict-refresh ()
  "Refresh all loaded dictionaries."
  (interactive)
  (let ((modes (hash-table-keys company-dict-table)))
    (setq company-dict-table (make-hash-table :test 'equal))
    (mapc 'company-dict--init modes)))

;;;###autoload
(defun company-dict (command &optional arg &rest ignored)
  "`company-mode' backend for user-provided dictionaries. Dictionary files are lazy
loaded."
  (interactive (list 'interactive))
  (mapc 'company-dict--init (company-dict--relevant-modes))
  (let ((dicts (company-dict--relevant-dicts)))
    (cl-case command
      (interactive (company-begin-backend 'company-dict))
      (prefix (and dicts
                   (company-grab-symbol)))
      (candidates
       (remove-if-not
        (if company-dict-fuzzy
            (lambda (c) (cl-subsetp (string-to-list arg)
                               (string-to-list c)))
          (lambda (c) (string-prefix-p arg c)))
        dicts))
      (annotation (company-dict--annotation arg))
      (meta (company-dict--meta arg))
      (sorted nil)
      (no-cache 't))))

(provide 'company-dict)
;;; company-dict.el ends here