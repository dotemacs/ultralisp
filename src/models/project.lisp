(uiop:define-package #:ultralisp/models/project
  (:use #:cl)
  (:import-from #:mito
                #:object-id
                #:includes
                #:save-dao
                #:delete-dao
                #:select-dao
                #:create-dao)
  (:import-from #:jonathan
                #:to-json)
  (:import-from #:dexador)
  (:import-from #:log)
  (:import-from #:ultralisp/metadata
                #:read-metadata)
  (:import-from #:function-cache
                #:defcached)
  (:import-from #:arrows
                #:->)
  (:import-from #:str)
  (:import-from #:alexandria
                #:make-keyword)
  (:import-from #:ultralisp/models/versioned
                #:versioned-table-class
                #:object-version
                #:versioned)
  (:import-from #:ultralisp/protocols/moderation)
  (:import-from #:ultralisp/utils/github
                #:get-topics
                #:extract-github-name)
  (:import-from #:sxql
                #:order-by
                #:limit
                #:where)
  #-ultralisp-worker-mode
  (:import-from #:reblocks-auth/models
                #:get-current-user)
  #+ultralisp-worker-mode
  (:import-from #:ultralisp/worker-mocks
                #:get-current-user)
  (:import-from #:ultralisp/db
                #:with-transaction)
  (:import-from #:ultralisp/utils
                #:time-in-past
                #:update-plist
                #:make-update-diff)
  (:import-from #:ultralisp/models/version
                #:get-number
                #:version)
  (:import-from #:quickdist
                #:get-path
                #:get-filename
                #:get-dependencies
                #:get-system-files
                #:get-project-prefix
                #:get-content-sha1
                #:get-md5sum
                #:get-file-size
                #:get-archive-path
                #:get-project-url
                #:get-project-name)
  (:import-from #:ultralisp/rpc/command
                #:defcommand)
  (:import-from #:ultralisp/models/utils
                #:systems-info-to-json
                #:release-info-to-json
                #:systems-info-from-json
                #:release-info-from-json)
  (:import-from #:log4cl-extras/error
                #:with-log-unhandled)
  (:import-from #:ultralisp/protocols/external-url
                #:external-url)
  (:import-from #:ultralisp/protocols/url
                #:url)
  (:import-from #:ultralisp/models/source
                #:source-systems-info)
  (:import-from #:log4cl-extras/context
                #:with-fields)
  (:import-from #:ultralisp/models/dist
                #:common-dist)
  (:import-from #:ultralisp/models/dist-source
                #:update-source-dists
                #:add-source-to-dist)
  (:import-from #:rutils
                #:fmt)
  (:import-from #:ultralisp/utils/db
                #:deflate-json
                #:inflate-json
                #:deflate-keyword
                #:inflate-keyword)
  (:import-from #:mito.dao
                #:select-by-sql)
  (:import-from #:ultralisp/sources/guesser
                #:make-source)
  (:import-from #:ultralisp/sources/base
                #:create-project
                #:base-source
                #:project-name)
  (:export
   #:update-and-enable-project
   #:is-enabled-p
   #:get-all-projects
   #:get-description
   #:get-url
   #:get-name
   #:project
   #:project2
   #:get-project2
   #:get-source
   #:get-params
   #:get-github-project
   #:add-or-turn-on-project
   #:turn-off-github-project
   #:get-last-seen-commit
   #:disable-project
   #:enable-project
   #:project-version
   #:get-version
   #:create-projects-snapshots-for
   #:get-projects
   #:get-project
   #:get-recent-projects
   #:get-versions
   #:unable-to-create-project
   #:get-reason
   #:make-project-from-url
   #:get-systems-info
   #:get-release-info
   #:get-disable-reason
   #:find-projects-with-conflicting-systems
   #:get-external-url
   #:get-recently-updated-projects
   #:enabled
   #:project-description
   #:project-name
   #:project-sources
   #:source->project
   #:project-url
   #:turn-off-project2
   #:get-projects2-by-username
   #:get-projects-with-sources
   #:ensure-project
   #:get-all-dist-projects
   #:get-project-systems
   #:get-project2-by-id))
(in-package #:ultralisp/models/project)


(defclass project ()
  ((source :col-type (:text)
           :initarg :source
           :reader get-source
           :inflate #'inflate-keyword
           :deflate #'deflate-keyword)
   (name :col-type (:text)
         :initarg :name
         :accessor get-name)
   (description :col-type :text
                :initarg :description
                :accessor get-description)
   (params :col-type (:jsonb)
           :initarg :params
           :accessor get-params
           :deflate #'deflate-json
           :inflate #'inflate-json)
   (enabled :col-type :boolean
            :documentation "If True, then this project will be included into the next distribution version.

                            This attribute should be turned on only after some check was passed."
            :initform nil
            :accessor is-enabled-p)
   (systems-info :col-type (or :jsonb :null)
                 :documentation "Contains a list of lists describing systems same way as quickdist returns."
                 :accessor get-systems-info
                 :deflate #'systems-info-to-json
                 :inflate #'systems-info-from-json)
   (release-info :col-type (or :jsonb :null)
                 :documentation ""
                 :accessor get-release-info
                 :deflate #'release-info-to-json
                 :inflate #'release-info-from-json))
  (:unique-keys name)
  (:metaclass mito:dao-table-class))


(defclass project-version ()
  ((version :col-type version
            :initarg :version
            :reader get-version)
   (source :col-type (:text)
           :initarg :source
           :reader get-source
           :inflate #'inflate-keyword
           :deflate #'deflate-keyword)
   (name :col-type (:text)
         :initarg :name
         :accessor get-name)
   (description :col-type :text
                :initarg :description
                :accessor get-description)
   (params :col-type (:jsonb)
           :initarg :params
           :accessor get-params
           :deflate #'deflate-json
           :inflate #'inflate-json)
   (systems-info :col-type (or :jsonb :null)
                 :documentation "Contains a list of lists describing systems same way as quickdist returns."
                 :initform nil
                 :accessor get-systems-info
                 :deflate #'systems-info-to-json
                 :inflate #'systems-info-from-json)
   (release-info :col-type (or :jsonb :null)
                 :documentation ""
                 :initform nil
                 :accessor get-release-info
                 :deflate #'release-info-to-json
                 :inflate #'release-info-from-json))
  (:documentation "Items of this class store a snapshot of the project's state
                   at the moment when a particular version was built.")
  (:metaclass mito:dao-table-class))


(defclass project2 (versioned)
  ((name :col-type (:text)
         :initarg :name
         :accessor project-name)
   (description :col-type :text
                :initarg :description
                :accessor project-description))
  (:unique-keys name)
  (:primary-key id version)
  ;; (:metaclass versioned-table-class)
  (:metaclass mito:dao-table-class))


(defmethod print-object ((project project) stream)
  (print-unreadable-object (project stream :type t)
    (format stream
            "~A name=~A enabled=~A"
            (get-source project)
            (get-name project)
            (is-enabled-p project))))


(defmethod print-object ((project project2) stream)
  (print-unreadable-object (project stream :type t)
    (format stream
            "~A (v~A)"
            (project-name project)
            (object-version project ))))


(defmethod print-object ((project project-version) stream)
  (print-unreadable-object (project stream :type t)
    (format stream
            "~A~@[ version=~A~] name=~A"
            (get-source project)
            (get-number
             (get-version project))
            (get-name project))))


(defun get-external-url (project)
  ;; TODO: after support of different sources,
  ;;       we need to abstract this function and make
  ;;       it work with any type of project.
  (let* ((params (get-params project))
         (user-name (getf params :user-or-org))
         (project-name (getf params :project)))
    (format nil "https://github.com/~A/~A"
            user-name
            project-name)))


(defun get-last-seen-commit (project)
  (check-type project project)
  (getf (get-params project)
        :last-seen-commit))


(defun (setf get-last-seen-commit) (value project)
  (check-type project project)
  (setf (getf (get-params project)
              :last-seen-commit)
        value))


;; To reveive token in dev:
;; curl -i -u svetlyak40wt -d '{"scopes":["public_repo"], "note": "for-ultralisp-import"}' https://api.github.com/authorizations
(defvar *github-oauth-token* nil
  "Set this to token to raise GitHub's rate limit from 60 to 5000 requests per hour.")


;; TODO: remove after migration to guessers
(defcached %github-get-description (user-or-org project)
  (let ((headers (when *github-oauth-token*
                   (list (cons "Authorization"
                               (format nil "token ~A"
                                       *github-oauth-token*))))))
    (-> (format nil "https://api.github.com/repos/~A/~A"
                user-or-org
                project)
        (dex:get :headers headers)
        (jonathan:parse)
        (getf :|description|))))


(define-condition unable-to-create-project (error)
  ((reason :initform nil
           :initarg :reason
           :reader get-reason)))


(defun add-source (project &key type params)
  (check-type project project2)
  (check-type type keyword)
  (check-type params list)
  (mito:create-dao 'ultralisp/models/source:source
                   :project-id (object-id project)
                   :project-version (object-version project)
                   :type type
                   :params params))


;; TODO: remove after the full move to guessers
;; Tests should be rewritten to guessers too
(defun make-github-project (user-or-org project-name)
  (ultralisp/db:with-transaction
    (let* ((full-project-name (concatenate 'string
                                           user-or-org
                                           "/"
                                           project-name))
           (description (or (ignore-errors
                             ;; We ignore errors here, because
                             ;; description is not very important
                             ;; and can be updated later,
                             ;; but we definitely want to log these
                             ;; errors, to not miss some system problems.
                             (with-log-unhandled ()
                               (%github-get-description user-or-org
                                                        project-name)))
                            ""))
           (project (create-dao 'project2
                                :name full-project-name
                                :description description)))
      (add-source project
                  :type :github
                  :params (list :user-or-org user-or-org
                                :project project-name))

      (uiop:symbol-call "ULTRALISP/MODELS/TAG" "ADD-TAGS"
                        project
                        (get-topics full-project-name))
      project)))


(defun make-project-from-url (url &key (moderator nil moderator-given-p))
  (let* ((source (make-source url))
         (project
           (when source
             (apply #'add-or-turn-on-project
                    (list* source
                           (when moderator-given-p
                             (list :moderator moderator)))))))

    (unless project
      (error 'unable-to-create-project
             :reason (fmt "Unable to create a project from URL: ~A"
                          url)))
    
    (values project)))


(defun get-all-projects (&key only-enabled)
  (if only-enabled
      (select-dao 'project
        (where :enabled))
      (select-dao 'project)))

(defun get-projects-with-sources ()
  "Returns projects with not deleted sources."
  (select-by-sql (find-class 'project2)
                          "
    WITH projects_with_sources AS (
      SELECT distinct source.project_id
        FROM source
       WHERE latest = true
         AND deleted = false
    )
    SELECT *
      FROM project2
     WHERE id IN (SELECT * FROM projects_with_sources)
       AND latest = true"))


(defun get-recent-projects (&key (limit 10))
  "Returns a list of recently added projects to show them on a landing page."
  (select-dao 'project2
    (order-by (:desc :created-at))
    (limit limit)))


(defun get-projects-count ()
  "Returns a total number of projects in the database (including projects with disabled sources."
  (getf (first (mito:retrieve-by-sql "SELECT COUNT(*) as cnt FROM project2"))
        :CNT))


(defun get-recently-updated-projects (&key (since (time-in-past :day 1)))
  "Returns a list of recently added projects to show them on a landing page."
  (select-dao 'project
    (where (:and :enabled
                 (:> :updated-at
                     since)))
    (order-by (:desc :updated-at))))

(defun get-github-project (user-or-org project)
  (first
   (select-dao 'project
     (where (:and
             (:= :source
                 "GITHUB")
             (:a> :params
                  (to-json
                   (list :user-or-org user-or-org
                         :project project)))))
     (limit 1))))

(defun get-project2 (project-name)
  (check-type project-name string)
  (multiple-value-bind (response query)
      (select-dao 'project2
        ;; We need this use of lower,
        ;; to make sure the search of the project
        ;; is case insensitive.
        ;; Database should have an special lowercased
        ;; index,
        (where (:and
                (:= (:raw "lower(name)")
                    (string-downcase project-name))
                (:= :latest
                    1))))
    (values (first response)
            query)))


(defun get-project2-by-id (project-id)
  (check-type project-id integer)
  (multiple-value-bind (response query)
      (select-dao 'project2
        (where (:and
                (:= :id
                    project-id)
                (:= :latest
                    1))))
    (values (first response)
            query)))


(defun get-projects2-by-username (user-name)
  "Returns all projects with names like <user-name>/any-project-name."
  (check-type user-name string)
  (select-dao 'project2
    (where (:like :name
                  (fmt "~A/%" user-name)))
    (order-by :name)))


(defun add-or-turn-on-project (source &key (moderator (get-current-user)))
  "Creates or updates a record in database adding current user to moderators list."
  (check-type source base-source)
  
  (ultralisp/db:with-transaction
    (let ((project (or (get-project2 (project-name source))
                       (progn
                         (log:info "Adding new project to the database" source)
                         (create-project source)
                         ;; (make-github-project user-or-org project-name)
                         ))))
      
      ;; Now we need to bind the source to the common distribution
      ;; if it is not already bound:
      (loop with dist = (common-dist)
            for source in (project-sources project)
            ;; TODO: think if we really need to check source-type here
            ;; for source-type = (ultralisp/models/source:source-type source)
            ;; when (eql source-type :github)
            do (add-source-to-dist dist source)
               ;; We only add to the common dist the first
               ;; source of type :github, because there
               ;; can be more than one such sources in projects
               ;; which already existed in the database,
               ;; but Ultralisp prohibits adding a project twice
               ;; into the same distribution.
               (return))
      

      ;; Here we only making user a moderator if
      ;; nobody else owns a project. Otherwise, he
      ;; need to prove his ownership.
      (when (and moderator
                 (null (ultralisp/protocols/moderation:moderators project)))
        (ultralisp/protocols/moderation:make-moderator
         moderator
         project))
      
      ;; Also, we need to trigger a check of this project
      ;; and to enabled it and to include into the next build
      ;; of a new Ultralisp version.
      (uiop:symbol-call :ultralisp/models/check
                        :make-checks
                        project
                        :added-project)
      
      project)))


(defun turn-off-github-project (name)
  "Creates or updates a record in database adding current user to moderators list."
  (destructuring-bind (user-or-org project . rest)
      (str:split "/" name)
    (declare (ignorable rest))
    
    (let ((project (get-github-project user-or-org project)))
      (when project
        (disable-project project))
      project)))


(defun turn-off-project2 (name)
  "Creates or updates a record in database adding current user to moderators list."
  (let ((project (get-project2 name)))
    (when project
      (remove-project-from-dists project))
    project))


(defun delete-project (project)
  (delete-dao project))


;; Seems this is a one shot function used at some moment
;; for data-migration.
(defun convert-metadata (&optional (filename "projects/projects.txt"))
  "Loads old metadata from file into a database."
  (let ((metadata (read-metadata filename)))
    (with-transaction
      (loop for item in metadata
            for urn = (ultralisp/metadata:get-urn item)
            for splitted = (str:split "/" urn)
            for user = (first splitted)
            for project = (second splitted)
            do (make-github-project user project)))))


(defun enable-project (project)
  "Enables project right now."
  (check-type project project)

  (log:info "Enabling project" project)

  (uiop:symbol-call :ultralisp/models/action
                    :make-project-added-action
                    project
                    :diff nil)
  
  (setf (is-enabled-p project)
        t)
  (save-dao project)
  
  (values project))


(defcommand update-and-enable-project (project data &key force)
  (let* ((params (get-params project))
         (diff (make-update-diff params
                                 data)))
    (when (or diff
              force)
      (log:info "Updating the project and creating actions" project data force)

      (cond
        ((is-enabled-p project)
         (uiop:symbol-call :ultralisp/models/action
                           :make-project-updated-action project
                           :diff diff))
        (t
         (uiop:symbol-call :ultralisp/models/action
                           :make-project-added-action project
                           :diff diff)
         (setf (is-enabled-p project)
               t)))
      
      (setf (get-params project)
            (update-plist params
                          data))
      (save-dao project))))


(defun disable-project (project &key reason traceback) 
  "Disables project."
  (check-type project project)
  
  (when (is-enabled-p project)
    (log:info "Disabling project" project)

    ;; Also, we need to create a new action, related to this project
    (uiop:symbol-call :ultralisp/models/action
                      :make-project-removed-action
                      project
                      :reason reason
                      :traceback traceback)
    (setf (is-enabled-p project)
          nil)

    (save-dao project))
  
  (values project))


(defun remove-project-from-dists (project) 
  "Disables project."
  (check-type project project2)
  
  ;; This will delete links of this project
  ;; with all distributions
  (loop for source in (project-sources project)
        do (update-source-dists source :dists nil))
  
  ;; (when (is-enabled-p project)
  ;;   (log:info "Disabling project" project)

  ;;   ;; Also, we need to create a new action, related to this project
  ;;   (uiop:symbol-call :ultralisp/models/action
  ;;                     :make-project-removed-action
  ;;                     project
  ;;                     :reason reason
  ;;                     :traceback traceback)
  ;;   (setf (is-enabled-p project)
  ;;         nil)

  ;;   (save-dao project))
  
  (values project))


(defun get-disable-reason (project)
  (check-type project project)
  (unless (is-enabled-p project)
    (let* ((last-action (first (uiop:symbol-call :ultralisp/models/action
                                                 :get-project-actions
                                                 project)))
           (params (when last-action
                     (uiop:symbol-call :ultralisp/models/action
                                       :get-params
                                       last-action)))
           (reason (getf params :reason)))
      (when reason
        (values (make-keyword (string-upcase reason)))))))


(defun create-project-snapshort (project version)
  (create-dao 'project-version
              :version version
              :source (get-source project)
              :name (get-name project)
              :description (get-description project)
              :params (get-params project)
              :systems-info (get-systems-info project)
              :release-info (get-release-info project)
              :created-at (mito:object-created-at project)
              :updated-at (mito:object-updated-at project)))


(defun create-projects-snapshots-for (version)
  (check-type version version)
  (loop for project in (get-all-projects :only-enabled t)
        do (create-project-snapshort project version)))


(defun get-projects (version)
  (check-type version version)
  (select-dao 'project-version
    (where (:= :version version))
    (order-by :name)))


(defun get-versions (project)
  (check-type project project)
  (mapcar #'get-version
          (select-dao 'project-version
            (includes 'version)
            (where (:= :name (get-name project)))
            (order-by (:desc :version-id)))))


(defun get-project (project-version)
  "Returns original project."
  (check-type project-version project-version)
  (mito:find-dao 'project
                 :name (get-name project-version)))


(defun project-sources (project)
  (check-type project project2)
  (ultralisp/models/source::%project-sources
   (object-id project)
   (object-version project)))


(defun source->project (source)
  (check-type source (or ultralisp/models/source:source
                         ultralisp/models/source:bound-source))
  (first
   (mito:retrieve-dao 'project2
                      :id (ultralisp/models/source:source-project-id source)
                      :version (ultralisp/models/source:project-version source))))


;; TODO: remove
(defun get-url (project)
  (let* ((name (get-name project)))
    (format nil "/projects/~A"
            name)))


(defun project-url (project)
  (check-type project project2)
  (let* ((name (project-name project)))
    (format nil "/projects/~A"
            name)))


(defmethod external-url ((obj project2))
  (loop for source in (project-sources obj)
        for url = (external-url source)
        when url
        do (return-from external-url url)))


(defmethod url ((obj project2))
  (check-type obj project2)
  (let* ((name (project-name obj)))
    (format nil "/projects/~A"
            name)))


(defun ensure-project (project)
  (etypecase project
    (project2 project)
    (string
     (let* ((project-name project)
            (project (get-project2 project-name)))
       (unless project
         (error "Unable to find ~A"
                project-name))
       project))))


(defun get-all-dist-projects (dist &key (enabled nil enabled-given-p))
  "Returns sorted list of project names, included into the dist."
  (let* ((sources
           (apply #'ultralisp/models/dist-source:dist->sources
                  dist
                  (when enabled-given-p
                    (list :enabled enabled)))))
    (mapcar #'source->project sources)))


(defun get-project-systems (project)
  (check-type project project2)
  (loop for source in (project-sources project)
        for systems = (source-systems-info source)
        appending systems))
