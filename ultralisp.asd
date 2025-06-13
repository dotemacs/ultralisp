;; (loop for path in (list
;;                    "~/projects/jsonrpc/"
;;                    "~/projects/reblocks/"
;;                    "~/projects/linter/")
;;       when (probe-file path)
;;         do (pushnew path asdf:*central-registry*
;;                     :test #'equal))


(defun search-version-in-changelog (lines)
  (let* ((line (nth 4 lines))
         (space-pos (position #\Space line)))
    (when space-pos
      (subseq line 0 space-pos))))


(defsystem ultralisp
  :description "A fast-moving Common Lisp software distribution for those who want to publish his/her software today."
  :author "Alexander Artemenko <svetlyak.40wt@gmail.com>"
  :licence "BSD"
  :class :package-inferred-system
  :version (:read-file-line "ChangeLog.rst" :at search-version-in-changelog)
  :pathname "src"
  :serial t
  :depends-on ("cl-interpol"
               "log4sly"
	       ;; To not load it when worker is starting
	       ;; This should fix issue with bordeaux-threads recompilation:
	       ;; https://github.com/ultralisp/ultralisp/issues/84
	       "dbd-postgres"
               ;; We need this while will not support package inferred systems:
               ;; https://github.com/ultralisp/ultralisp/issues/3
               "40ants-doc"
               "reblocks-ui"
               "reblocks-auth"
               ;; To make inplace links work in the HTML
               "ultralisp/main"
               "ultralisp/server"
               "ultralisp/worker")
  :in-order-to ((test-op (test-op ultralisp-test)))
  ;; :perform (compile-op :before (o c)
  ;;                      #+ros.installing
  ;;                      (roswell:roswell '("install" "40ants/defmain")))
  )

#+sbcl
(register-system-packages "prometheus.collectors.sbcl" '(#:prometheus.sbcl))

(register-system-packages "prometheus.collectors.process" '(#:prometheus.process))

(register-system-packages "dbd-postgres" '(#:dbd.postgres))

(register-system-packages "log4cl" '(#:log))

(register-system-packages "cl-dbi" '(#:dbi.cache.thread #:dbi.error))

(register-system-packages "dexador" '(#:dexador.connection-cache #:dex))

(register-system-packages "quicklisp" '(#:quicklisp-client))

(register-system-packages "cl-base64" '(#:base64))

(register-system-packages "mito" '(#:mito.class #:mito.db #:mito.dao #:mito.util))

(register-system-packages "slynk" '(#:slynk-api))

(register-system-packages "lack-middleware-mount" '(#:lack.middleware.mount))

(register-system-packages "bordeaux-threads" '(#:bordeaux-threads-2))
