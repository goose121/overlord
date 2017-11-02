;; Freezing the state of the Lisp image.
(defpackage :overlord/freeze
  (:use :cl :alexandria :serapeum)
  (:export
   :freeze :freeze-policy
   :unfreeze
   :file
   :check-not-frozen
   :frozen?))
(in-package :overlord/freeze)

(deftype freeze-policy ()
  '(member t nil :hard))

(defparameter *freeze-policy* t)
(declaim (type freeze-policy *freeze-policy*))

(defun freeze-policy ()
  "Get or set the current freeze policy.

The freeze policy determines what Overlord does when saving an image.

A freeze policy of `t' (the default) disables module loading, but can
be reversed with `overlord:unfreeze'.

A freeze policy of `nil` does nothing. This should only be used for
local development.

A freeze policy of `:hard' does the same thing as `t', but cannot be
reversed. This should be used when the image is intended to be
distributed."
  *freeze-policy*)

(defun (setf freeze-policy) (value)
  (setf *freeze-policy* (assure freeze-policy value)))

(defvar *frozen* nil
  "Is the build system frozen?")

(defun frozen? ()
  *frozen*)

(defparameter *freeze-fmakunbound-hit-list*
  '(unfreeze
    redo
    redo-ifchange
    redo-ifcreate
    redo-always
    redo-stamp
    dynamic-require-as))

(defun freeze ()
  ;; NB. You should be able to load an image and save it again.
  (unless (frozen?)
    (labels ((freeze ()
               (format t "~&Overlord: freezing image...~%")
               (redo (root-target))
               ;; The DB can still be reloaded, but is not in memory.
               (unload-db)
               (setf *frozen* t))
             (hard-freeze ()
               (freeze)
               (format t "~&Overlord: hard freeze...~%")
               (fmakunbound 'unfreeze)
               ;; Variables aren't defined yet.
               (clear-target-table (symbol-value '*top-level-targets*))
               (clrhash (symbol-value '*symbol-timestamps*))
               (clrhash (symbol-value '*tasks*))
               ;; The table of module cells needs special handling.
               (clear-module-cells)
               (clrhash (symbol-value '*claimed-module-names*))
               ;; The DB will not be reloaded.
               (deactivate-db)
               (dolist (fn *freeze-fmakunbound-hit-list*)
                 (fmakunbound fn))))
      (ecase-of freeze-policy *freeze-policy*
        ((nil))
        ((t) (freeze))
        (:hard (hard-freeze))))))

(uiop:register-image-dump-hook 'freeze)

(defun unfreeze ()
  (setf *frozen* nil))

(defun check-not-frozen ()
  (when *frozen*
    (restart-case
        (error* "The build system is frozen.")
      (unfreeze ()
        :report "Unfreeze the build system."
        (setf *frozen* nil)))))