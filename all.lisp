(uiop:define-package :overlord/all
    (:nicknames :overlord)
  (:import-from :overlord/types
    :overlord-error :overlord-warning
    :overlord-error-target)
  (:export :overlord-error :overlord-warning)
  (:import-from :overlord/message
    :message
    :*message-stream*)
  (:import-from :overlord/util
    :write-file-if-changed
    :copy-file-if-changed
    :strip-directory)
  (:import-from :overlord/specials
    :use-threads-p)
  (:import-from :overlord/redo
    :recursive-dependency
    :missing-script
    :building?
    :redo-always)

  (:import-from :overlord/build-env :*use-build-cache*)
  (:export :*use-build-cache*)

  (:export
   :recursive-dependency :missing-script
   :module-ref :module-ref* :module-exports :module-static-exports
   :simple-module :hash-table-module
   :ensure-file-package :reset-file-package
   :message :*message-stream*
   :write-file-if-changed :copy-file-if-changed
   :strip-directory
   :use-threads-p
   :building? :redo-always
   :overlord-error-target :overlord-error)
  (:use-reexport
   :overlord/base
   :overlord/target
   :overlord/freeze
   :overlord/message
   :overlord/target-protocol
   :overlord/oracle
   :overlord/cmd))

(defpackage :overlord-user
  (:use :cl :alexandria :serapeum :overlord))
