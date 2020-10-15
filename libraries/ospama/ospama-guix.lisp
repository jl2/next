;;;; SPDX-FileCopyrightText: Atlas Engineer LLC
;;;; SPDX-License-Identifier: BSD-3-Clause

(in-package :ospama)

(defun guix-eval (form &rest more-forms)
  ;; TODO: "guix repl" is a reliable way to execute Guix code, sadly it does not
  ;; seem to support standard input.  Report upstream?  Alternatively, use Guile
  ;; the way emacs-guix.el does it, but it does not seem reliable.
  (let ((*package* (find-package :ospama)) ; Need to be in this package to avoid prefixing symbols with current package.
        (*print-case* :downcase))
    (uiop:with-temporary-file (:pathname p)
      (with-open-file (s p :direction :output :if-exists :append)
        (dolist (f (cons form more-forms))
          (write-string
           ;; Escaped symbols (e.g. '\#t) are printed as '|NAME| but should be
           ;; printed as NAME.
           (ppcre:regex-replace-all "'\\|([^|]*)\\|" (format nil "~s" f) "\\1")
           s)))
      (uiop:run-program `("guix" "repl" ,(namestring p))
                        :output '(:string :stripped t)
                        :error-output :output))))

(defun generate-database ()
  (guix-eval
   '(use-modules
     (guix packages)
     (guix licenses)
     (guix utils)
     (gnu packages))

   '(define (ensure-list l)
     (if (list? l)
         l
         (list l)))

   '(display
     (with-output-to-string
         (lambda ()
           (format '\#t "(~&")
           (fold-packages
            (lambda (package count)
              (let ((location (package-location package)))
                (format '\#t "(~s (:version ~s :outputs ~s :supported-systems ~s :inputs ~s :propagated-inputs ~s :native-inputs ~s :location ~s :home-page ~s :licenses ~s :synopsis ~s :description ~s))~&"
                        (package-name package)
                        (package-version package)
                        (package-outputs package)
                        (package-supported-systems package)
                        (map car (package-inputs package))
                        (map car (package-propagated-inputs package))
                        (map car (package-native-inputs package))
                        (string-join (list (location-file location)
                                           (number->string (location-line location))
                                           (number->string (location-column location)))
                                     ":")
                        (or (package-home-page package) 'nil) ; #f must be turned to NIL for Common Lisp.
                        (map license-name (ensure-list (package-license package)))
                        (package-synopsis package)
                        (package-description package)))
              (+ 1 count))
            1)
           (format '\#t "~&)~&"))))))

(define-class guix-package (os-package)
  ((outputs '())
   (supported-systems '())
   (inputs '())
   (propagated-inputs '())
   (native-inputs '())
   (location "")
   (description "")))

(defvar *guix-database* nil)

(defun guix-database ()
  (unless *guix-database*
    (setf *guix-database* (read-from-string (generate-database))))
  *guix-database*)

(defun make-guix-package (name &optional (pkg (second (assoc name (guix-database) :test #'string=))))
  (apply #'make-instance 'guix-package
         :name name
         (alexandria:mappend
          (lambda (kw)
            (list kw (getf pkg kw)))
          '(:version :outputs :supported-systems :inputs :propagated-inputs
            :native-inputs :location :home-page :licenses :synopsis
            :description))))

(defun database-entry->guix-package (entry)
  (make-guix-package (first entry) (second entry)))

(defmethod find-os-package ((manager (eql :guix)) name)
  (make-guix-package name))

(defmethod list-packages ((manager (eql :guix)))
  (mapcar #'database-entry->guix-package (guix-database)))

(defmethod refresh ((manager (eql :guix)))
  (declare (ignore manager))
  (setf *guix-database* nil))

(defmethod install-command ((manager (eql :guix)))
  (declare (ignore manager))
  '("guix" "install"))

(defmethod uninstall-command ((manager (eql :guix)))
  (declare (ignore manager))
  '("guix" "remove"))

(defmethod show-command ((manager (eql :guix)))
  (declare (ignore manager))
  '("guix" "show"))

(defmethod profile-install ((manager (eql :guix)) profile)
  (declare (ignore manager))
  (list "guix" "install" (str:concat "--profile=" profile)))

(defmethod size-command ((manager (eql :guix)))
  '("guix" "size"))

(defmethod size ((manager (eql :guix)) package)
  (run-over-packages #'size-command (list package)))

;; TODO: Find a way to list the files.  If we get the store path we are good.
;; TODO: Find a way to list the reverse dependencies.

;; TODO: Guix special commands:
;; - build
;; - edit