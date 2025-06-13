(uiop:define-package #:ultralisp/variables
  (:use #:cl)
  (:import-from #:function-cache
                #:defcached)
  (:import-from #:secret-values
                #:conceal-value)
  (:export
   #:to-prod-db))
(in-package #:ultralisp/variables)


(defmacro def-env-var (getter var-name &optional default)
  `(progn
     (defcached ,getter ()
       "If `value' is not given, then tries to extract it from env variables or fall back to default."
       (or (uiop:getenv ,var-name)
           ,default))
     (export ',getter)))

(defmacro def-secret-env-var (getter var-name &optional default)
  `(progn
     (defcached ,getter ()
       "If `value' is not given, then tries to extract it from env variables or fall back to default."
       (conceal-value
        (or (uiop:getenv ,var-name)
            ,default)))
     (export ',getter)))

(def-env-var get-projects-dir
  "PROJECTS_DIR"
  "./build/sources/")

(def-env-var get-dist-dir
  "DIST_DIR"
  "./build/dist/")

(def-env-var get-clpi-dist-dir
  "CLPI_DIST_DIR"
  "./build/clpi/")

(def-env-var get-base-url
  "BASE_URL"
  "http://dist.ultralisp.org/")

(def-env-var get-clpi-base-url
  "CLPI_BASE_URL"
  "https://clpi.ultralisp.org/")

(def-env-var get-dist-name
  "DIST_NAME"
  "ultralisp")

(def-env-var get-yandex-counter-id
  "YANDEX_COUNTER_ID")

(def-env-var get-google-counter-id
  "GOOGLE_COUNTER_ID")

(def-env-var get-postgres-host
  "POSTGRES_HOST"
  "localhost")

(def-env-var get-postgres-dbname
  "POSTGRES_DBNAME"
  "ultralisp")

(def-env-var get-postgres-user
  "POSTGRES_USER"
  "ultralisp")

(def-env-var get-postgres-ro-user
  "POSTGRES_RO_USER"
  "ultralisp_ro")

(def-secret-env-var get-postgres-pass
  "POSTGRES_PASS"
  "ultralisp")

(def-secret-env-var get-postgres-ro-pass
  "POSTGRES_RO_PASS"
  "ultralisp_ro")

(def-env-var get-gearman-server
  "GEARMAN_SERVER"
  "localhost:4730")

(def-env-var get-github-client-id
  "GITHUB_CLIENT_ID")

(def-secret-env-var get-github-secret
  "GITHUB_SECRET")

(def-secret-env-var get-github-robot-token
  "GITHUB_ROBOT_TOKEN")

(def-env-var get-aws-access-key-id
  "AWS_ACCESS_KEY_ID")

(def-secret-env-var get-aws-secret-access-key
  "AWS_SECRET_ACCESS_KEY")

(def-env-var get-s3-bucket
  "S3_BUCKET"
  "dist.ultralisp.org")

(def-env-var get-s3-clpi-bucket
  "S3_CLPI_BUCKET"
  "clpi.ultralisp.org")

(def-env-var get-uploader-type
  "UPLOADER_TYPE")

(def-secret-env-var get-resend-api-key
  "RESEND_API_KEY")

(def-env-var get-recaptcha-site-key
  "RECAPTCHA_SITE_KEY")

(def-env-var get-recaptcha-secret-key
  "RECAPTCHA_SECRET_KEY")

(def-env-var get-user-agent
  "USER_AGENT"
  "Ultralisp (https://ultralisp.org)")


(def-env-var get-elastic-host
  "ELASTIC_SEARCH_HOST"
  "elastic")


(defvar *github-webhook-path* "/webhook/github")


(defvar *in-unit-test* nil)


(defun to-prod-db ()
  (setf (uiop:getenv "POSTGRES_DBNAME") "ultralisp_prod")
  (function-cache:clear-cache *get-postgres-dbname-cache*))
