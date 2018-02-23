(defpackage #:overlord/module
  (:use #:cl #:alexandria #:serapeum #:overlord/util)
  (:import-from #:overlord/types
    #:overlord-error)
  (:import-from #:trivial-garbage
    #:make-weak-pointer
    #:weak-pointer-value)
  (:export
   #:validate-module
   #:make-module
   #:module-ref
   #:module-ref*
   #:module-ref/inline-cache
   #:module-fn-ref
   #:module-fn-ref/inline-cache
   #:reset-inline-caches
   #:module-exports #:module-exports*
   #:module-static-exports
   #:current-module
   #:current-module-cell
   #:current-module-source
   #:current-module-lang
   #:current-module-meta
   #:default-export-module
   #:module-error
   #:module-error-module
   #:no-such-export
   #:not-a-module
   #:import-from))

(in-package #:overlord/module)

;;; Generic functions.

(defcondition module-error (overlord-error)
  ((module :initarg :module
           :reader module-error-module)))

(defcondition not-a-module (module-error)
  ()
  (:report (lambda (c s)
             (with-slots ((x module)) c
               (format s "Not a module: ~a" x)))))

(defcondition invalid-module (not-a-module)
  ()
  (:report (lambda (c s)
             (with-slots ((x module)) c
               (format s "~a cannot be a module." x)))))

(defcondition no-such-export (module-error)
  ((key :initarg :key :type symbol))
  (:report (lambda (c s)
             (with-slots (module key) c
               (format s "Module ~a does not export ~a."
                       module key)))))

(defgeneric module-ref (module name)
  (:documentation "Get the value of NAME in MODULE.")
  (:method (module name)
    (declare (ignore name))
    (error 'not-a-module
           :module module)))

(defgeneric module-exports (module)
  (:documentation "A list of names exported by MODULE.")
  (:method (module)
    (error 'not-a-module
           :module module)))

(defgeneric module-static-exports (lang source)
  (:documentation "Get static exports from LANG and SOURCE.
Returns two values: a list of static exports, and a second value that is T if the exports could be statically determined."))

(defun validate-module (module)
  "Validate that MODULE can be used as a module."
  (when (null module)
    (error 'invalid-module :module module))
  ;; `module-exports' signals `not-a-module' if there is no defined
  ;; method.
  (module-exports module)
  module)



;;; Distinguished module objects.

(defun empty-exports-table (module key)
  "An export table that always signals an error."
  (error 'no-such-export
         :module module
         :key key))

(defstruct-read-only (module (:conc-name __module-)
                             (:constructor __make-module))
  (exports nil :type list)
  (exports-table #'empty-exports-table :type function))

(defmethod module-exports ((module module))
  (__module-exports module))

(defmethod module-ref ((module module) key)
  (funcall (__module-exports-table module) module key))

(defun make-module (&key exports exports-table)
  "Make a module with EXPORTS, a list of symbols, and EXPORTS-TABLE, a
table that maps from symbols to values."
  (assert (every #'symbolp exports))
  (__make-module :exports exports
                 :exports-table exports-table))

(defun default-export-module (default)
  "Wrap DEFAULT in a module with a single binding, named `:default',
with DEFAULT as its value."
  (make-module
   :exports '(:default)
   :exports-table (default-export-table default)))

(defun default-export-table (default)
  "Return an export table with a single binding, `:default', mapped to
DEFAULT."
  (lambda (module key)
    (if (eql key :default) default
        (error "Module ~a has no export named ~a" module key))))


;;; Actual entry points.

(defconst flank-speed
  '((speed 3)
    (safety 1)
    (debug 0)
    (compilation-speed 0)
    (space 0))
  "Go as fast as you safely can.")

(defconst battleshort
  '((speed 3)
    (safety 0)
    (debug 0)
    (compilation-speed 0)
    (space 0))
  "You'd better know what you're doing.")

(defsubst module-ref* (module name)
  "Entry point for calling `module-ref' from internal code.
Inlinable, and skips generic dispatch for some common types."
  (declare (optimize . #.flank-speed))
  (typecase module
    (function (funcall module name))
    (hash-table (gethash name module))
    (module (funcall (__module-exports-table module) module name))
    (t (module-ref module name))))

(defsubst module-exports* (module)
  "Entry point for calling `module-exports' from internal code.
Inlinable, and skips generic dispatch for some common types."
  (declare (optimize . #.flank-speed))
  (typecase module
    (module (__module-exports module))
    (hash-table (hash-table-keys module))
    (t (module-exports module))))

(defunit unbound
  "Distinguished value for something unbound.")

(defvar *module-inline-cache-pointers*
  (make-hash-table :test 'eq
                   :size 1024)
  "Table of modules and inline caches.
Maps a module object to a list of weak pointers to inline cache
objects (boxes).

Why use weak pointers? To avoid accumulating pointers into old
versions of code that has been recompiled.")

(defun register-inline-cache (module box)
  "Add BOX to the table of inline caches for MODULE.
This is important so the inline caches can be reset if MODULE is
reloaded."
  (declare (type box box))
  (synchronized ('*module-inline-cache-pointers*)
    (setf (gethash module *module-inline-cache-pointers*)
          (adjoin (tg:make-weak-pointer box)
                  ;; Purge dead pointers.
                  (remove-if-not #'tg:weak-pointer-value
                                 (gethash module *module-inline-cache-pointers*))
                  :test #'eq
                  :key #'tg:weak-pointer-value))))

(defun reset-inline-caches (module)
  "Look up the inline caches pointing into MODULE and make them all
unbound again.

This should be used before a module is reloaded, to make sure the
inline caches will point into the new module."
  (declare (optimize speed (safety 0)))
  (let ((pointers
          (synchronized ('*module-inline-cache-pointers*)
            (pophash module *module-inline-cache-pointers*))))
    (dolist (p pointers)
      (when-let (cache (tg:weak-pointer-value p))
        (setf (unbox cache) unbound)))))

(defun fill-inline-cache (inline-cache module key)
  "Register INLINE-CACHE as an inline cache for MODULE and store
  MODULE's value for KEY in the cache."
  (register-inline-cache module inline-cache)
  (setf (unbox inline-cache)
        (module-ref* module key)))

(-> fill-inline-cache/fn (box t t) function)
(defun fill-inline-cache/fn (inline-cache module key)
  "Like `fill-inline-cache', but with a signature that says it returns
a function."
  (assure function
    (fill-inline-cache inline-cache module key)))

(defmacro module-ref/inline-cache (module key &environment env)
  "Embed an inline cache (using `load-time-value') and use it to cache
lookups of KEY in MODULE."
  (assert (constantp key env))
  (with-unique-names (inline-cache val)
    `(locally (declare (optimize . #.battleshort))
       (let* ((,inline-cache (load-time-value (box unbound)))
              (,val (unbox ,inline-cache)))
         (if (eq unbound ,val)
             (fill-inline-cache ,inline-cache ,module ,key)
             ,val)))))

(-> module-fn-ref (t symbol) function)
(defsubst module-fn-ref (module name)
  "Exactly like `module-ref*', but has a signature that says it
returns a function."
  (assure function (module-ref* module name)))

(defmacro module-fn-ref/inline-cache (module key &environment env)
  "Like `module-ref/inline-cache', but set up so the compiler knows it
returns a function."
  (assert (constantp key env))
  (with-unique-names (inline-cache val)
    `(locally (declare (optimize . #.battleshort))
       (let* ((,inline-cache (load-time-value (box unbound)))
              (,val (unbox ,inline-cache)))
         (the function
              (if (functionp ,val)
                  ,val
                  (fill-inline-cache/fn ,inline-cache ,module ,key)))))))
