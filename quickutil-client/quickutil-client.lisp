;;;; quickutil-client.lisp
;;;; Copyright (c) 2012-2013 Robert Smith

(in-package #:quickutil-client)

;;;; Client functions, including the public API, which handles the
;;;; loading of utilities.
;;;;
;;;; Convention in this file: If a function name ends in an asterisk,
;;;; then it takes a list as an argument. The same function without
;;;; the asterisk takes &REST arguments.

;;; XXX FIXME: This could use improved error handling.
(defun who-provides (symbol)
  "Which utility provides the symbol SYMBOL?"
  (assert (or (symbolp symbol)
              (stringp symbol)))
  (flet ((autoload-lookup (symbol)
           (let* ((autoload-url (reverse-lookup-url symbol))
                  (str (download-url-string autoload-url)))
             (if (string-equal "NIL" str)
                 (error "Could not find originating utility for symbol: ~A"
                        (symbol-name symbol))
                 str))))
    (let ((who (ignore-errors (autoload-lookup (if (symbolp symbol)
                                                   symbol
                                                   (make-symbol symbol))))))
      (nth-value 0 (and who (intern who '#:keyword))))))

(defun category-utilities (category-names)
  "Query for the symbols in the categories CATEGORY-NAMES."
  (flet ((category-syms (category-name)
           (let ((str (ignore-errors (download-url-string (category-url category-name)))))
             (if (null str)
                 nil
                 (nth-value 0 (read-from-string str))))))
    (loop :for category :in category-names
          :append (category-syms category) :into symbols
          :finally (return (remove-duplicates symbols)))))

(defun symbol-utilities (symbols)
  (remove nil (remove-duplicates (mapcar #'who-provides symbols))))

(defun query-needed-utilities (&key utilities categories symbols)
  (remove-duplicates
   (append utilities
           (category-utilities categories)
           (symbol-utilities symbols))))

(defun utilize (&key utilities categories symbols)
  (compile-and-load-from-url
   (quickutil-query-url
    (query-needed-utilities :utilities utilities
                            :categories categories
                            :symbols symbols))))

(defun utilize-utilities (&rest utilities)
  "Load the utilities UTILITIES and their dependencies."
  (utilize :utilities utilities))

(defun utilize-categories (&rest categories)
  "Load the utilities in the categories CATEGORIES."
  (utilize :categories categories))

(defun utilize-symbols (&rest symbols)
  "Load the utilities which provide the symbols SYMBOLS."
  (utilize :symbols symbols))

(defun print-lines (stream &rest strings)
  "Print the lines denoted by the strings STRINGS to the stream
STREAM."
  (dolist (string strings)
    (write-string string stream)
    (terpri stream)))

(defun ensure-keyword-list (list)
  "Ensure that LIST is a list of keywords."
  (if (listp list)
      (mapcar #'(lambda (symb)
                  (intern (symbol-name symb) '#:keyword))
              list)
      (ensure-keyword-list (list list))))

(defun save-utils-as (filename &key utilities categories symbols)
  (with-open-file (file filename :direction :output
                                 :if-exists :supersede
                                 :if-does-not-exist :create)
    (let ((file-contents (download-url-string
                          (quickutil-query-url
                           (query-needed-utilities :utilities utilities
                                                   :categories categories
                                                   :symbols symbols)))))
      ;; Header
      (print-lines file
                   ";;;; This file was automatically generated by Quickutil."
                   ";;;; See http://quickutil.org for details."
                   ""
                   ";;;; To regenerate:")
      (let ((*print-pretty* nil))
        (format file
                ";;;; (qtlc:save-utils-as ~S :utilities '~S :categories '~S :symbols '~S)~%~%"
                filename
                (ensure-keyword-list utilities)
                (ensure-keyword-list categories)
                (ensure-keyword-list symbols)))
      
      ;; Package definition
      (print-lines file
                   ;; Package Definition
                   "(eval-when (:compile-toplevel :load-toplevel :execute)"
                   "  (unless (find-package '#:quickutil)" 
                   "    (defpackage quickutil"
                   "      (:documentation \"Package that contains the actual utility functions.\")"
                   "      (:nicknames #:qtl)"
                   "      (:use #:cl))))"
                   ""
                   
                   ;; Code
                   file-contents
                   ""
                   
                   ;; End of file
                   (format nil ";;;; END OF ~A ;;;;" filename))

      ;; Return the pathname
      (pathname filename))))
