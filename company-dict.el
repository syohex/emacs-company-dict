;;; company-dict.el --- A backend that emulates ac-source-dictionary
;;
;; Copyright (C) 2015-16 Henrik Lissner

;; Author: Henrik Lissner <http://github/hlissner>
;; Maintainer: Henrik Lissner <henrik@lissner.net>
;; Created: June 21, 2015
;; Modified: May 25, 2016
;; Version: 1.2.7
;; Keywords: company dictionary ac-source-dictionary
;; Homepage: https://github.com/hlissner/emacs-company-dict
;; Package-Requires: ((company "0.8.12") (cl-lib "0.5") (parent-mode "2.3"))
;;
;; This file is not part of GNU Emacs.
;;
;;; Code:

(require 'company)
(eval-when-compile
  (require 'cl-lib)
  (require 'subr-x))

(autoload 'parent-mode-list "parent-mode")

;; For compiler
(defvar yas-minor-mode)
(declare-function yas-expand-snippet "yasnippet")

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

(defcustom company-dict-enable-fuzzy nil
  "Whether to allow fuzzy searching for company-dict."
  :group 'company-dict
  :type 'boolean)
(define-obsolete-variable-alias 'company-dict-fuzzy 'company-dict-enable-fuzzy "v1.2.4")

(defcustom company-dict-enable-yasnippet t
  "If non-nil, company-dict autocompletions will be expanded like a `yasnippet'
snippet, but only if yasnippet is loaded and `yas-minor-mode' is enabled in the
current buffer. Otherwise, company-dict will pretend this is set to nil.

Note: yasnippet is optional and not a dependency of company-dict. You'll have to
install and enable it yourself."
  :group 'company-dict
  :type 'boolean)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar company-dict-table (make-hash-table :test 'equal)
  "A lookup hash table that maps major (or minor) modes to lists of completion candidates.")

(defun company-dict--read-file (file-path)
  (when (file-exists-p file-path)
    (unless (file-readable-p file-path)
      (user-error "Dictionary file isn't readable! (%s)" file-path))
    (decode-coding-string
     (with-temp-buffer
       (set-buffer-multibyte nil)
       (setq buffer-file-coding-system 'utf-8)
       (insert-file-contents-literally file-path)
       (buffer-substring-no-properties (point-min) (point-max))) 'utf-8)))

(defun company-dict--relevant-modes ()
  (append '(all) (parent-mode-list major-mode) company-dict-minor-mode-list))

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
  (let (file contents result)
    (unless (symbolp mode)
      (error "Expected symbol, got %s" mode))
    (unless (gethash mode company-dict-table)
      (setq file (expand-file-name (symbol-name mode) company-dict-dir)
            contents (company-dict--read-file file))
      (when (stringp contents)
        (mapc (lambda (line)
                (let ((l (split-string (string-trim-right line) "\t" t)))
                  (push (propertize (nth 0 l) :note (nth 1 l) :meta (nth 2 l))
                        result)))
              (split-string contents "\n" t))
        (puthash mode result company-dict-table)))
    result))

(defun company-dict--annotation (data)
  (get-text-property 0 :note data))

(defun company-dict--meta (data)
  (get-text-property 0 :meta data))

(defun company-dict--post-completion (data)
  (when (and company-dict-enable-yasnippet
             (featurep 'yasnippet)
             (bound-and-true-p yas-minor-mode))
    (yas-expand-snippet data (- (point) (length data)) (point))))

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
      (interactive     (company-begin-backend 'company-dict))
      (prefix          (and dicts (company-grab-symbol)))
      (candidates      (cl-remove-if-not
                        (if company-dict-enable-fuzzy
                            (lambda (c) (cl-subsetp (string-to-list arg)
                                               (string-to-list c)))
                          (lambda (c) (string-prefix-p arg c)))
                        dicts))
      (annotation      (company-dict--annotation arg))
      (meta            (company-dict--meta arg))
      (post-completion (company-dict--post-completion arg))
      (sorted          't)
      (no-cache        't))))

(provide 'company-dict)
;;; company-dict.el ends here
