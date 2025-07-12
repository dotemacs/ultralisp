(defpackage #:ultralisp/models/dist-source
  (:use #:cl)
  (:import-from #:jonathan)
  (:import-from #:log)
  (:import-from #:alexandria
                #:make-keyword)
  (:import-from #:ultralisp/models/dist
                #:dist-state
                #:get-or-create-pending-version
                #:dist-name
                #:dist-equal
                #:ensure-dist)
  (:import-from #:ultralisp/models/source
                #:source-systems-info
                #:copy-source)
  (:import-from #:mito
                #:object-id)
  (:import-from #:ultralisp/models/versioned
                #:prev-version
                #:object-version)
  (:import-from #:ultralisp/db
                #:with-transaction)
  (:import-from #:ultralisp/utils
                #:update-plist)
  (:import-from #:ultralisp/utils/text
                #:remove-ansi-sequences)
  (:import-from #:ultralisp/protocols/enabled
                #:enabled-p)
  (:import-from #:rutils
                #:fmt
                #:ensure-keyword)
  (:import-from #:ultralisp/utils/db
                #:inflate-keyword
                #:deflate-keyword
                #:inflate-json
                #:deflate-json)
  (:import-from #:mito.dao
                #:select-by-sql)
  (:export
   #:dist-source
   #:dist-id
   #:dist-version
   #:source-id
   #:source-version
   #:include-reason
   #:disable-reason
   #:deleted-p
   #:dist-source->dist
   #:source->dists
   #:source-distributions
   #:update-source-dists
   #:create-pending-dists-for-new-source-version
   #:make-disable-reason
   #:disable-reason-type
   #:dist-source->source
   #:dist->sources
   #:add-source-to-dist
   #:get-link
   #:lisp-implementation))
(in-package #:ultralisp/models/dist-source)

(defparameter *deb* nil)

(defclass dist-source ()
  ((dist-id :col-type :bigint
            :initarg :dist-id
            :reader dist-id)
   (dist-version :col-type :bigint
                 :initarg :dist-version
                 :reader dist-version)
   (source-id :col-type :bigint
              :initarg :source-id
              :reader source-id)
   (source-version :col-type :bigint
                   :initarg :source-version
                   :documentation "This field can be changed only on dist-source linked to the :pending dist."
                   :accessor source-version)
   (include-reason :col-type :text
                   ;; Can be:
                   ;; - :direct
                   :initarg :include-reason
                   :reader include-reason
                   :deflate #'deflate-keyword
                   :inflate #'inflate-keyword)
   (enabled :col-type :boolean
            :initarg :enabled
            :initform t
            :documentation "This field can be changed only on dist-source linked to the :pending dist."
            :accessor enabled-p)
   (disable-reason :col-type :jsonb
                   :initarg :disable-reason
                   :initform nil
                   :accessor disable-reason
                   :deflate #'deflate-json
                   :inflate #'inflate-json
                   :documentation "A plist with like this: '(:type :manual :comment \"Renamed the project.\")
                                   This field can be changed only on dist-source linked to the :pending dist.")
   (deleted :col-type :boolean
            :initarg :deleted
            :initform nil
            :documentation "This field can be changed only on dist-source linked to the :pending dist."
            :accessor deleted-p))
  (:primary-key
   dist-id dist-version
   source-id)
  (:metaclass mito:dao-table-class))


(defmethod print-object ((obj dist-source) stream)
  (print-unreadable-object (obj stream :type t)
    (with-slots (dist-id dist-version
                 source-id source-version
                 enabled)
        obj
      (format stream "dist-id=~A dist-version=~A source-id=~A source-version=~A enabled=~A"
              dist-id dist-version
              source-id source-version
              enabled))))


(defmethod include-reason ((obj ultralisp/models/dist:bound-dist))
  (ultralisp/models/dist::include-reason obj))


(defun dist-source->dist (dist-source)
  (check-type dist-source dist-source)
  (mito:find-dao
   'ultralisp/models/dist:dist
   :id (dist-id dist-source)
   :version (dist-version dist-source)))


(defun dist-source->source (dist-source)
  (check-type dist-source
              ultralisp/models/dist-source:dist-source)
  (mito:find-dao
   'ultralisp/models/source:source
   :id (source-id dist-source)
   :version (source-version dist-source)))


(defgeneric source-distributions (source &key)
  (:method ((source ultralisp/models/source:source) &key (enabled nil enabled-given-p))
    "Returns all source distributions given source belongs to
     except those where it was deleted.

     Note, that only the latest version of each distribution is returned.

     Also note, the source can be bound to a one of the previous versions of the dist.
     For such case the latest dist-source will be returned.

     If latest dist-source record has `deleted` flag, it is not returned et all."
    (let ((sql "
WITH ids_to_select AS (
    SELECT dist_id, max(dist_version), source_id
      FROM dist_source
     WHERE source_id = ?
       AND source_version <= ?
     GROUP by dist_id, source_id
)
SELECT *
  FROM dist_source
 WHERE (dist_id, dist_version, source_id) IN (SELECT * FROM ids_to_select)
   AND deleted = false
")
          (params (list (object-id source)
                        (object-version source))))
      (when enabled-given-p
        (setf sql
              (concatenate 'string
                           sql
                           (if enabled
                               "   AND enabled = true"
                               "   AND enabled = false"))))
      (select-by-sql (find-class 'dist-source)
                     sql
                     :binds params)))
  
  (:method ((dist ultralisp/models/dist:dist) &key (enabled nil enabled-given-p)
                                                   (limit nil limit-given-p))
    "Returns all source distributions which are enabled and not
     deleted in the given dist.

     Note: Results contain all sources linked to the previous
     dist versions."

    (let ((sql "
WITH ids_to_select AS (
    SELECT dist_id, max(dist_version), source_id
      FROM dist_source
     WHERE dist_id = ?
       AND dist_version <= ?
     GROUP by dist_id, source_id
)
SELECT *
  FROM dist_source
 WHERE (dist_id, dist_version, source_id) IN (SELECT * FROM ids_to_select)
   AND deleted = false")
          (params (list (object-id dist)
                        (object-version dist))))
      (when enabled-given-p
        (setf sql
              (fmt "~A~%~A"
                   sql
                   (if enabled
                       "   AND enabled = true"
                       "   AND enabled = false"))))
      (when limit-given-p
        (setf sql
              (fmt "~A~%~A"
                   sql
                   " LIMIT ?"))
        (setf params (append params
                             (list limit))))
      (mito.dao:select-by-sql (find-class 'dist-source)
                              sql
                              :binds params))))


(defun %this-version-source-distributions (dist &key (enabled nil enabled-given-p)
                                                     (limit most-positive-fixnum))
  "Returns only source distributions which are enabled 
   deleted in the given dist."
  (check-type dist ultralisp/models/dist:dist)
  
  (let ((clauses
          `(:and
            (:= dist_source.dist_id
                ,(object-id dist))
            (:= dist_source.dist_version
                ,(object-version dist))
            ,@(when enabled-given-p
                `((:= dist-source.enabled
                      ,(if enabled
                           "true"
                           "false")))))))
    (mito:select-dao 'dist-source
      (sxql:where clauses)
      (sxql:limit limit))))


(defun source->dists (source &key (enabled nil enabled-given-p))
  "Returns dist objects along with their enabled flag"
  (check-type source
              ultralisp/models/source:source)
  (loop for dist-source in (apply #'source-distributions
                                  source
                                  (when enabled-given-p
                                    (list :enabled enabled)))
        for dist = (dist-source->dist dist-source)
        collect (make-instance 'ultralisp/models/dist:bound-dist
                               :dist dist
                               :enabled (enabled-p dist-source)
                               :disable-reason (disable-reason dist-source)
                               :include-reason (include-reason dist-source))))


(defun dist->sources (dist &key this-version
                                (enabled nil enabled-given-p)
                                (limit most-positive-fixnum))
  "Returns all sources bound to the dist dist objects along with their enabled flag"
  (check-type dist
              ultralisp/models/dist:dist)
  (loop for dist-source in (cond
                             (this-version
                              (apply #'%this-version-source-distributions
                                     dist
                                     :limit limit
                                     (when enabled-given-p
                                       (list :enabled enabled))))
                             (t
                              (apply #'source-distributions
                                     dist
                                     :limit limit
                                     (when enabled-given-p
                                       (list :enabled enabled)))))
        for source = (dist-source->source dist-source)
        collect (make-instance 'ultralisp/models/source:bound-source
                               :source source
                               :dist dist
                               :enabled (enabled-p dist-source)
                               :disable-reason (disable-reason dist-source)
                               :include-reason (include-reason dist-source))))


(defmethod prev-version ((obj ultralisp/models/source:bound-source))
  "
   To get the previous version of bound source, we have to find
   a source which was bound to a previos version of the dist.

   Otherwise we can choose wrong source version which was unbound
   during the distributions list change.
  "
  (let* ((source (ultralisp/models/source:source obj))
         (dist (ultralisp/models/source:dist obj))
         (current-dist-version (object-version dist)))
    (let ((prev-dist-source
            (first
             (mito:select-dao 'dist-source
               (sxql:where (:and (:= :dist-id (object-id dist))
                                 (:= :source-id (object-id source))
                                 ;; The same source version can be bound
                                 ;; to different dist versions,
                                 ;; but one dist version can't include
                                 ;; different versions of the same
                                 ;; source.
                                 ;; 
                                 ;; That is why we are searching the dist-source
                                 ;; with a maximum version which is less than current.
                                 ;;
                                 ;; Note, this version can be lesser than (1- current-dist-version)
                                 ;; because links between source and dist are created
                                 ;; only when source was changed or enabled/disabled.
                                 (:< :dist-version current-dist-version)))
               (sxql:order-by (:desc :dist-version))
               (sxql:limit 1)))))
      (when prev-dist-source
        (let ((prev-source (ultralisp/models/source:find-source-version
                            (source-id prev-dist-source)
                            (source-version prev-dist-source)))
              (prev-dist (ultralisp/models/dist:find-dist-version
                            (dist-id prev-dist-source)
                            (dist-version prev-dist-source))))
          (unless prev-source
            (error "Unable to find source with id = ~A and version = ~A"
                   (source-id prev-dist-source)
                   (source-version prev-dist-source)))
          (make-instance 'ultralisp/models/source:bound-source
                         :source prev-source
                         :dist prev-dist
                         :enabled (enabled-p prev-dist-source)
                         :disable-reason (disable-reason prev-dist-source)
                         :include-reason (include-reason prev-dist-source)))))))


(defun update-source-dists (source &key (params nil)
                                        (dists nil dists-p)
                                        (include-reason :direct)
                                        (disable-reason :manual)
                                        ;; If new-source version is not given,
                                        ;; it will be created automatically:
                                        (new-source nil))
  "Creates a new version of the source by changing the dists and optionally updating source params.

   New version is created only if there were changes in params or dists.

   Returns:
     Two values - a source object and boolean.
     If boolean is `t` then source was cloned and updated.
"
  (check-type source ultralisp/models/source:source)
  
  (with-transaction
    (multiple-value-bind (new-params params-changed-p)
        (update-plist (ultralisp/models/source:source-params source)
                      params)
      (flet ((ensure-there-is-a-clone ()
               (unless new-source
                 (setf new-source
                       (ultralisp/models/source:copy-source source
                                                            :params new-params)))))
        (when params-changed-p
          (ensure-there-is-a-clone))

        (let* ((current-dists
                 ;; Previously we've collected only enabled dists into this
                 ;; variable. But this lead to the situation when
                 ;; it was impossible to remove disabled source from the dist.
                 (source->dists source))
               (new-dists (if dists-p
                              (mapcar #'ensure-dist dists)
                              ;; If dists list was not given, then
                              ;; we'll just keep all dists as is by
                              ;; reataching them to a new source version.
                              current-dists))
               (dists-to-remove
                 (set-difference current-dists
                                 new-dists
                                 :key #'dist-name
                                 :test #'string=))
               (dists-to-add
                 (set-difference new-dists
                                 current-dists
                                 :key #'dist-name
                                 :test #'string=))
               ;; These dists nor added nor removed,
               ;; we have to keep links to them
               (keep-dists
                 (intersection current-dists
                               new-dists
                               :key #'dist-name
                               :test #'string=)))
          
          (when dists-to-add
            (ensure-there-is-a-clone)
            ;; If source should be added to the dist,
            ;; we have to get/create a pending dist
            ;; and to link this source to it:
            (let* ((has-release-info (ultralisp/models/source:source-release-info source))
                   (enabled (when has-release-info
                              t))
                   (disable-reason (unless has-release-info
                                     ;; When source gets added to the distribution,
                                     ;; it has this disable reason.
                                     ;; However, if it has some release-info,
                                     ;; it is added as "enabled", because we don't
                                     ;; need to check it to build the distribution.
                                     (make-disable-reason :just-added
                                                          :comment "This source waits for the check."))))
              (loop for dist in dists-to-add
                    for new-version = (get-or-create-pending-version dist)
                    for old-dist-source = (mito:find-dao 'dist-source
                                                         :dist-id (object-id dist)
                                                         :dist-version (object-version dist)
                                                         :source-id (object-id source))
                    do (cond
                         ;; We only need to create a new link if a new pending
                         ;; version was created and the source previously
                         ;; was linked to it (and probably removed).
                         ((and (dist-equal dist new-version)
                               old-dist-source)
                          ;; When dist version is the same and it is still pending,
                          ;; we can just mark existing dist-source as enabled.
                          (unless (eql (dist-state new-version)
                                       :pending)
                            (error "We can add a new source version only to a pending dist version."))
                          ;; First, we need to change source version in the link
                          (setf (source-version old-dist-source)
                                (object-version new-source))
                          ;; Second, to set flags, showing that the source is enabled and not deleted
                          ;; from the dist:
                          (setf (deleted-p old-dist-source) nil
                                (enabled-p old-dist-source) enabled
                                (disable-reason old-dist-source) disable-reason)
                          (mito:update-dao old-dist-source))
                         (t
                          (mito:create-dao 'dist-source
                                           :dist-id (object-id new-version)
                                           :dist-version (object-version new-version)
                                           :source-id (object-id new-source)
                                           :source-version (object-version new-source)
                                           :include-reason include-reason
                                           :enabled enabled
                                           :disable-reason disable-reason)))

                       ;; Now we need to update asdf systems in the database:
                       (uiop:symbol-call "ULTRALISP/MODELS/ASDF-SYSTEM"
                                         "ADD-SOURCE-SYSTEMS"
                                         new-version
                                         new-source))))

          (when dists-to-remove
            (ensure-there-is-a-clone)
            ;; if source should be removed from some dist,
            ;; then we have to get/create a pending dist
            ;; and to link this source with "deleted" mark:
            (loop with disable-reason = (make-disable-reason
                                         disable-reason)
                  for dist in dists-to-remove
                  for new-version = (get-or-create-pending-version dist)
                  for old-dist-source = (mito:find-dao 'dist-source
                                                       :dist-id (object-id dist)
                                                       :dist-version (object-version dist)
                                                       :source-id (object-id source))
                  do (cond
                       ;; We only need to create a new link if a new pending
                       ;; version was created.
                       ((dist-equal dist new-version)
                        ;; When dist version is the same and it is still pending,
                        ;; we can just mark existing dist-source as disabled.
                        (unless (eql (dist-state new-version)
                                     :pending)
                          (error "We can remove a new source version only to a pending dist version."))
                        ;; First, we need to change source version in the link
                        (setf (source-version old-dist-source)
                              (object-version new-source))
                        ;; Second, to set flags, showing that the source was disabled and removed
                        ;; from the dist:
                        (setf (deleted-p old-dist-source) t
                              (enabled-p old-dist-source) nil
                              (disable-reason old-dist-source) disable-reason)
                        (mito:update-dao old-dist-source))
                       (t
                        (mito:create-dao 'dist-source
                                         :dist-id (object-id new-version)
                                         :dist-version (object-version new-version)
                                         :source-id (object-id new-source)
                                         :source-version (object-version new-source)
                                         ;; Here we reuse reason from the removed
                                         ;; dist.
                                         :include-reason (include-reason dist)
                                         ;; Important to set this flag:
                                         :deleted t
                                         :enabled nil
                                         :disable-reason disable-reason)))

                     ;; Now we need to remove asdf systems from the database:
                     (uiop:symbol-call "ULTRALISP/MODELS/ASDF-SYSTEM"
                                       "REMOVE-SOURCE-SYSTEMS"
                                       new-version
                                       new-source)))
          
          (when new-source
            ;; We need to execute this section in any case if params were updated
            ;; or if some dists were changed. In both cases, source will be
            ;; cloned and new-version will not be nil.
            (loop for dist in keep-dists
                  for new-version = (get-or-create-pending-version dist)
                  ;; Here we need to attach to the pending dist a new source version
                  for old-dist-source = (mito:find-dao 'dist-source
                                                       :dist-id (object-id dist)
                                                       :dist-version (object-version dist)
                                                       :source-id (object-id source))
                  do (cond
                       ;; We only need to create a new link if a new pending
                       ;; version was created.
                       ((dist-equal dist new-version)
                        ;; When dist version is the same, but we need to bind
                        ;; a new source version to it, then we'll modify
                        ;; existing dist-source.
                        ;;
                        ;; However, we can do this only on pending dist
                        (unless (eql (dist-state new-version)
                                     :pending)
                          (error "We can rebind a new source version only to a pending dist version."))
                        (setf (source-version old-dist-source)
                              (object-version new-source))
                        (mito:update-dao old-dist-source))
                       (t
                        (mito:create-dao 'dist-source
                                         :dist-id (object-id new-version)
                                         :dist-version (object-version new-version)
                                         :source-id (object-id new-source)
                                         :source-version (object-version new-source)
                                         ;; Keep previous inclusion reason
                                         :include-reason (include-reason dist))))))))

      ;; Also, we'll need to recheck this source
      ;; before it will be included into the new dist versions.
      ;; 
      ;; We don't do this when only dists list changed, because
      ;; dists don't affect the source's code.
      (when params-changed-p
        ;; We have a circular dependency:
        ;; project -> dist-source -> check -> project :(
        (uiop:symbol-call "ULTRALISP/MODELS/CHECK"
                          "MAKE-CHECK"
                          new-source :changed-project)))
    
    ;; Now we'll return old or a new source and a True as a second
    ;; value, if something was changed and source was cloned.
    (values (or new-source
                source)
            (when new-source
              t))))


(defun disable-reason-type (reason)
  (ensure-keyword
   (getf reason :type)))


(defun make-disable-reason (type &key comment traceback)
  (check-type type (member :check-error
                           ;; When source gets added to the distribution,
                           ;; it has this disable reason.
                           ;; However, if it has some release-info,
                           ;; it is added as "enabled".
                           :just-added
                           :manual
                           :system-conflict))
  (append (list :type type)
          (when comment
            (list :comment
                  (remove-ansi-sequences comment)))
          (when traceback
            (list :traceback
                  ;; Sometimes condition description might
                  ;; include an output of some console program
                  ;; and this output might contain ANSI sequences
                  ;; which broke JSON serialization to the database.
                  ;; This is why we remove them here:
                  (remove-ansi-sequences traceback)))))


(defun create-pending-dists-for-new-source-version (old-source new-source &key
                                                                          (enable nil enable-p)
                                                                          disable-reason)
  "Creates pending dist copies and links new source using dist-source copies.

   If enable == t then new-source is linked as enabled unless previous link has been disabled manually.

   Links marked as \"deleted\" aren't copied.

   If source is already linked to the pending-dist,
   then it's dist-source's enabled, disable-reason are updated.
   "
  (log:info "Checking if we need to create a pending dist for a" new-source "copied from" old-source)
  (log:debug "Other params are" enable enable-p disable-reason)

  (unless (= (object-id old-source)
             (object-id new-source))
    (error "Old source and new source are versions of different sources."))

  (with-transaction
    (let ((old-dist-sources (source-distributions old-source)))
      (loop with conflicts = (uiop:symbol-call "ULTRALISP/MODELS/ASDF-SYSTEM"
                                               "GET-CONFLICTING-SYSTEMS"
                                               new-source)
            for old-dist-source in old-dist-sources
            for old-dist = (dist-source->dist old-dist-source)
            for pending-dist = (get-or-create-pending-version old-dist)
            for old-disable-reason = (disable-reason old-dist-source)
            for old-disable-reason-type = (disable-reason-type old-disable-reason)
            for old-enabled = (enabled-p old-dist-source)
            for has-conflict-with-other-system-in-this-dist = (remove-if-not
                                                               (lambda (asdf-system)
                                                                 (= (object-id pending-dist)
                                                                    (uiop:symbol-call "ULTRALISP/MODELS/ASDF-SYSTEM"
                                                                                      "DIST-ID"
                                                                                      asdf-system)))
                                                               conflicts)
            for new-enabled = (cond
                                (has-conflict-with-other-system-in-this-dist
                                 ;; Disable source for this dist!
                                 nil)
                                ((eql :manual old-disable-reason-type) old-enabled)
                                (enable-p enable)
                                (t old-enabled))
            for new-disable-reason = (unless new-enabled
                                       (if has-conflict-with-other-system-in-this-dist
                                           (let* ((projects (loop for s in has-conflict-with-other-system-in-this-dist
                                                                  collect (uiop:symbol-call "ULTRALISP/MODELS/ASDF-SYSTEM"
                                                                                            "ASDF-SYSTEM-PROJECT"
                                                                                            s)))
                                                  (project-names (loop for p in projects
                                                                       collect (uiop:symbol-call "ULTRALISP/MODELS/PROJECT"
                                                                                                 "PROJECT-NAME"
                                                                                                 p)))
                                                  (comment (fmt "ASDF system conflicts with ~{~S~^, ~}"
                                                                project-names)))
                                             (make-disable-reason :system-conflict
                                                                  :comment comment))
                                           (or disable-reason
                                               old-disable-reason)))
            ;; We only need to create a new dist version
            ;; if source was enabled/disabled,
            ;; or if a new source version was created
            do (unless (and (eql old-enabled new-enabled)
                            (= (object-version old-source)
                               (object-version new-source)))
                 (let ((old-dist-source-linked-to-the-pending-dist
                         (mito:find-dao 'dist-source
                                        :dist-id (object-id pending-dist)
                                        :dist-version (object-version pending-dist)
                                        :source-id (object-id old-source)
                                        :source-version (object-version old-source))))
                   (log:debug "Found or created pending dist"
                              pending-dist
                              old-enabled
                              old-disable-reason)
                   (cond
                     ;; This case can be when we are setting enable == t and disable reason
                     ;; for the checked source which is bound to the pending dist.
                     ;; In this case we just update existing dist-source, detaching the old
                     ;; source version and attaching the new version.
                     (old-dist-source-linked-to-the-pending-dist
                      (log:debug "Found existing dist-source bound to a pending dist." 
                                 old-dist-source-linked-to-the-pending-dist
                                 new-enabled
                                 new-disable-reason)
                      (setf (enabled-p old-dist-source-linked-to-the-pending-dist)
                            new-enabled)
                      (setf (disable-reason old-dist-source-linked-to-the-pending-dist)
                            new-disable-reason)
                      (setf (source-version old-dist-source-linked-to-the-pending-dist)
                            (object-version new-source))

                      (mito:save-dao old-dist-source-linked-to-the-pending-dist))
                     
                     ((deleted-p old-dist-source)
                      (log:debug "Source was deleted from the dist, we'll ignore it and don't create a link to a pending dist."))
                     (t
                      (let ((include-reason (include-reason old-dist-source))
                            (existing-dist-source (mito:find-dao 'dist-source
                                                                 :dist-id (object-id pending-dist)
                                                                 :dist-version (object-version pending-dist)
                                                                 :source-id (object-id new-source))))
                        (log:info "Creating a link from source to the dist"
                                  new-source
                                  pending-dist
                                  new-enabled
                                  include-reason
                                  new-disable-reason
                                  old-dist-source
                                  existing-dist-source)
                        (mito:create-dao 'dist-source
                                         :dist-id (object-id pending-dist)
                                         :dist-version (object-version pending-dist)
                                         :source-id (object-id new-source)
                                         :source-version (object-version new-source)
                                         :include-reason include-reason
                                         :enabled new-enabled
                                         :disable-reason new-disable-reason
                                         :deleted nil))))

                   (if new-enabled
                       (uiop:symbol-call "ULTRALISP/MODELS/ASDF-SYSTEM"
                                         "ADD-SOURCE-SYSTEMS"
                                         pending-dist
                                         new-source)
                       (uiop:symbol-call "ULTRALISP/MODELS/ASDF-SYSTEM"
                                         "REMOVE-SOURCE-SYSTEMS"
                                         pending-dist
                                         new-source))))))))


(defun add-source-to-dist (dist source &key (include-reason :direct))
  "Creates pending dist and links the source using dist-source.

   Source is linked in \"disabled\" state.
   "
  (let* ((pending-dist (get-or-create-pending-version dist))
         (already-linked-dist-source
           (mito:find-dao 'dist-source
                          :dist-id (object-id pending-dist)
                          :dist-version (object-version pending-dist)
                          :source-id (object-id source)
                          :source-version (object-version source))))
    (unless already-linked-dist-source
      (let* ((has-release-info (ultralisp/models/source:source-release-info source))
             (enabled (when has-release-info
                        t))
             (disable-reason (unless has-release-info
                               ;; When source gets added to the distribution,
                               ;; it has this disable reason.
                               ;; However, if it has some release-info,
                               ;; it is added as "enabled", because we don't
                               ;; need to check it to build the distribution.
                               (make-disable-reason :just-added
                                                    :comment "This source waits for the check."))))
        (when enabled
          (uiop:symbol-call "ULTRALISP/MODELS/ASDF-SYSTEM"
                            "ADD-SOURCE-SYSTEMS"
                            pending-dist
                            source))
        (mito:create-dao 'dist-source
                         :dist-id (object-id pending-dist)
                         :dist-version (object-version pending-dist)
                         :source-id (object-id source)
                         :source-version (object-version source)
                         :include-reason include-reason
                         :enabled enabled
                         :disable-reason disable-reason
                         :deleted nil)))))


(defun delete-source (source)
  "Removes source from all dists and marks it as deleted.

   Actually, this all happens with a new source version."
  (with-transaction
    (let ((new-source (copy-source source :deleted t)))
      (update-source-dists source
                           :new-source new-source
                           :dists nil))))


(defun lisp-implementation (source)
  "Returns a lisp implementation to use for checking the source.

   If source is bound to a few dists, then tries to choose implementation
   different from SBCL.

   Probably we should prohibit inclusion of the sources into the dists
   with different lisp implementation."
  
  (check-type source ultralisp/models/source:source)
  (loop with implementations = nil
        for dist in (source->dists source)
        for impl = (ultralisp/models/dist:lisp-implementation dist)
        do (pushnew impl implementations)
        finally (return (cond
                          ((= (length implementations) 1)
                           (first implementations))
                          (t (let ((implementations
                                     (remove :sbcl implementations)))
                               (when (> (length implementations) 1)
                                 (log:error "Source ~S included into a few dists with different Lisp implementations: ~S"
                                            source implementations))
                               (first implementations)))))))



(defun get-link (dist source)
  "Returns a DIST-SOURCE object representing a link between given version of SOURCE and a DIST.

   DIST's version is not take into account, because this function is used when we are having
   a concrete source version and want to understand wether it was enable in the given dist or not
   and dist object can be the latest version not the on SOURCE is bound to."
  (check-type dist ultralisp/models/dist:dist)
  (check-type source ultralisp/models/source:source)

  (mito:find-dao 'dist-source
                 :dist-id (object-id dist)
                 :source-id (object-id source)
                 :source-version (object-version source)))
