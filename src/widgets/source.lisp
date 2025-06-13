(defpackage #:ultralisp/widgets/source
  (:use #:cl)
  (:import-from #:parenscript
                #:@)
  (:import-from #:log)
  (:import-from #:quickdist)
  (:import-from #:ultralisp/protocols/render-changes)
  (:import-from #:reblocks/widget
                #:defwidget
                #:render)
  (:import-from #:reblocks-lass)
  (:import-from #:reblocks/dependencies)
  (:import-from #:ultralisp/models/dist-source
                #:dist-version
                #:dist-id
                #:delete-source
                #:update-source-dists
                #:source-distributions)
  (:import-from #:ultralisp/models/dist-moderator)
  (:import-from #:ultralisp/protocols/external-url
                #:external-url)
  (:import-from #:ultralisp/protocols/url)
  (:import-from #:rutils
                #:awhen
                #:it
                #:fmt)
  (:import-from #:reblocks/html
                #:with-html)
  (:import-from #:ultralisp/models/dist
                #:dist-name
                #:find-dist)
  (:import-from #:ultralisp/models/dist-source
                #:source->dists
                #:dist-source->dist)
  (:import-from #:ultralisp/models/check
                #:make-check
                #:get-last-source-check
                #:source-checks)
  (:import-from #:ultralisp/utils
                #:make-keyword)
  (:import-from #:ultralisp/models/source
                #:project-version
                #:source-project-id
                #:source-type
                #:params-from-github)
  (:import-from #:ultralisp/utils/git
                #:get-git-branches)
  (:import-from #:ultralisp/utils/github
                #:get-github-branches)
  (:import-from #:ultralisp/protocols/enabled
                #:enabled-p)
  (:import-from #:mito
                #:object-id)
  (:import-from #:ultralisp/models/versioned
                #:get-latest-version-of
                #:object-version)
  (:import-from #:ultralisp/models/project
                #:source->project)
  (:import-from #:reblocks-auth/models
                #:get-current-user)
  (:import-from #:ultralisp/protocols/moderation
                #:is-moderator)
  (:import-from #:log4cl-extras/context
                #:with-fields)
  (:import-from #:ultralisp/utils/time
                #:humanize-timestamp
                #:humanize-duration)
  (:import-from #:ultralisp/utils/source
                #:format-ignore-list
                #:parse-ignore-list)
  (:import-from #:group-by
                #:group-by)
  (:import-from #:ultralisp/models/asdf-system
                #:asdf-systems-conflict)
  (:import-from #:reblocks-ui/form
                #:form-error-placeholder
                #:field-error
                #:error-placeholder)
  (:import-from #:local-time
                #:now)
  (:import-from #:local-time-duration
                #:timestamp-difference)
  (:import-from #:reblocks/actions
                #:make-js-action)
  (:import-from #:reblocks/utils/misc
                #:safe-funcall)
  (:import-from #:str
                #:join)
  (:import-from #:ultralisp/cron
                #:get-time-of-the-next-check)
  (:import-from #:reblocks-parenscript
                #:make-js-handler)
  (:export
   #:make-source-widget
   #:make-add-source-widget))
(in-package #:ultralisp/widgets/source)


(defwidget source-widget ()
  ((source :initarg :source
           :accessor source)
   (on-delete :initform nil
              :initarg :on-delete
              :documentation "An optional callback.

                              It will be called if the source is deleted.

                              The SOURCE-WIDGET's instance is passed as a single argument to a callback.")
   (subwidget :initform nil
              :accessor subwidget)))


(defwidget readonly-source-widget ()
  ((parent :initarg :parent
           :type source-widget
           :reader parent)
   (last-check :initarg :check
               :initform nil
               :type (or ultralisp/models/check:check2
                         null)
               :reader last-check)))


(defwidget branch-select-widget ()
  ((branches :initarg :branches
             :reader branches)
   (retrieve-branches-func :initarg :retrieve-branches-func
                           :reader retrieve-branches-func)
   (current :initarg :current
            :reader current-branch)))


(defun make-branch-select-widget (url source-type &key (current "main"))
  (let ((callable (case source-type
                    (:github 'get-github-branches)
                    (:git 'get-git-branches))))
    (multiple-value-bind (branches default-branch)
        (funcall callable url)
      (make-instance 'branch-select-widget
                     :retrieve-branches-func callable
                     :branches branches
                     :current (or current
                                  default-branch)))))


(defun update-url (widget url)
  (check-type widget branch-select-widget)
  (check-type url string)
  
  (multiple-value-bind (branches default-branch)
      (funcall (retrieve-branches-func widget) url)
    (setf (slot-value widget 'branches)
          branches
          (slot-value widget 'current)
          default-branch)
    (reblocks/widget:update widget)))


(defwidget edit-source-widget ()
  ((parent :initarg :parent
           :type source-widget
           :reader parent)
   (branches :initarg :branches
             :reader branches)
   (dist-conflicts :initform nil
                   :accessor dist-conflicts)))


(defwidget add-source-widget ()
  ((project :initarg :project
            :reader project)
   (on-new-source :initform nil
                  :initarg :on-new-source
                  :reader on-new-source
                  :documentation "
                      A function of one argument.
                      Will be called with a new source.
                  ")))


(defun edit (widget)
  (check-type widget readonly-source-widget)
  (log:debug "Switching to the edit widget")
  (let* ((main (parent widget))
         (source (source main))
         ;; Где-то здесь надо воткнуть получение списка полей
         (subwidget (make-instance 'edit-source-widget
                                   :parent main
                                   :branches (make-branch-select-widget
                                              (external-url source)
                                              (source-type source)
                                              :current (ultralisp/models/source:get-current-branch source)))))
    (setf (slot-value main 'subwidget)
          subwidget)
    (reblocks/widget:update main)))


(defun switch-to-readonly (widget)
  (check-type widget edit-source-widget)

  (log:debug "Switching to the view widget")
  
  (let* ((parent (parent widget))
         (source (source parent))
         (subwidget (make-instance 'readonly-source-widget
                                   :parent parent
                                   :check (get-last-source-check source))))

    (setf (slot-value parent 'subwidget)
          subwidget)
    (reblocks/widget:update parent)))


;; Here is the flow of working with a source.
;; Each source type has to define it's own form for read-only
;; rendering, editing and a method for saving results.
;; When results are saved, there is a common part of
;; distribution update and a custom part of fields update.


(defun ensure-all-dists-have-same-lisp-implementation (dist-names)
  (loop with implementations = nil
        for name in dist-names
        for dist = (find-dist name :raise-error nil)
        when dist
        do (pushnew (ultralisp/models/dist:lisp-implementation dist)
                    implementations
                    :test #'equal)
        finally (when (> (length implementations) 1)
                  (field-error "distributions"
                               "Unable to add source to distributions with different lisp implementations"))))


(defun get-updated-params (source url branch ignore-dirs)
  (let ((type (source-type source)))
    (case type
      (:github
       (multiple-value-bind (user-name project-name)
           (params-from-github url)
         (list :user-or-org user-name
               :project project-name
               :branch branch
               :ignore-dirs ignore-dirs))
       )
      (:git
       (list :url url
             :branch branch
             :ignore-dirs ignore-dirs)))))


(defun save (widget args)
  (check-type widget edit-source-widget)

  (let* ((parent (parent widget)))
    (loop with url = (getf args :url)
          with branch = (getf args :branch)
          with ignore-dirs = (awhen (getf args :ignore-dirs)
                               (parse-ignore-list it))
          for (name value) on args by #'cddr
          when (member name '(:distributions :distributions[]))
          collect value into new-dist-names
          finally
             (log:info "Saving" new-dist-names url branch)
             (ensure-all-dists-have-same-lisp-implementation new-dist-names)
          
             (let ((params-update
                     (get-updated-params (source parent)
                                         url
                                         branch
                                         ignore-dirs)))
               (with-fields (:params params-update)
                 (multiple-value-bind (new-source was-cloned-p)
                     (update-source-dists (source parent)
                                          :dists new-dist-names
                                          :params params-update)
                   (when was-cloned-p
                     (log:info "A new source version was created: " new-source)
                     (setf (source parent)
                           new-source))))))
    (switch-to-readonly widget)))


(defun make-add-source-widget (project &key on-new-source)
  (make-instance 'add-source-widget
                 :project project
                 :on-new-source on-new-source))


(defun make-source-widget (source &key on-delete)
  (let* ((main (make-instance 'source-widget
                              :source source
                              :on-delete on-delete))
         (subwidget (make-instance 'readonly-source-widget
                                   :parent main)))
    (setf (slot-value main 'subwidget)
          subwidget)
    main))


(defun render-distribution (dist-source)
  (check-type dist-source ultralisp/models/dist-source:dist-source)
  (let* ((dist (dist-source->dist dist-source))
         (name (dist-name dist))
         (url (ultralisp/protocols/url:url dist))
         (enabled (enabled-p dist-source))
         (class (if enabled
                    "dist enabled"
                    "dist disabled"))
         (reason (unless enabled
                   ;; TODO: create a special pretty-printer for disable reason.
                   ;; and probably make a popup with the traceback.
                   (fmt "Disabled: ~A"
                        (ultralisp/models/dist-source:disable-reason dist-source)))))
    (with-html ()
      (:a :class class
          :title reason
          :href url
          name))))


(defgeneric render-source (widget type source))


(defun github-url (source-params)
  (let ((user-or-org (getf source-params :user-or-org))
        (project-name (getf source-params :project)))
    (if (and user-or-org project-name)
        (format nil "https://github.com/~A/~A"
                user-or-org
                project-name)
        "")))


(defun on-delete (widget)
  (check-type widget source-widget)
  
  (let ((source (source widget)))
    (with-fields (:source-id (object-id source)
                  :source-version (object-version source))
      (log:error "Deleting source")
     
      (delete-source source)
     
      (reblocks/utils/misc:safe-funcall (slot-value widget 'on-delete)
                                        widget))))


(defmethod render-source ((widget readonly-source-widget)
                          (type (eql :github))
                          source)
  (let* ((params (ultralisp/models/source:source-params source))
         (deleted (ultralisp/models/source:deleted-p source))
         (url (github-url params))
         (last-seen-commit (getf params :last-seen-commit))
         (ignore-dirs (getf params :ignore-dirs))
         (release-info (ultralisp/models/source:source-release-info source))
         (distributions (source-distributions source))
         (systems (ultralisp/models/source:source-systems-info source))
         (user-is-moderator (is-moderator
                             (get-current-user)
                             (source->project source))))
    ;; Deleted sources should not be in the list
    ;; for rendering.
    (assert (not deleted))

    (flet ((deletion-handler (&rest args)
             (declare (ignorable args))
             (on-delete (parent widget))))
      (let ((last-check (get-last-source-check source)))
        (with-html ()
          (:table :class "unstriped"
                  (:thead
                   (:tr (:th :class "label-column"
                             "Type")
                        (:th :class "field-column"
                             type
                             ;; Controls for editing and deleting source
                             (when user-is-moderator
                               (:div :class "source-controls float-right"
                                     (reblocks-ui/form:with-html-form
                                         (:post #'deletion-handler
                                          :requires-confirmation-p t
                                          :confirm-question (:div (:h1 "Warning!")
                                                                  (:p "If you'll remove this source, it will be excluded from the future versions of these distributions:")
                                                                  (:ul
                                                                   (loop for name in (mapcar #'dist-name
                                                                                             (remove-if-not
                                                                                              #'enabled-p
                                                                                              (source->dists source)))
                                                                         do (:li name)))))
                                       (:input :type "submit"
                                               :class "alert button tiny"
                                               :name "button"
                                               :value "Remove"))
                                    
                                     (reblocks-ui/form:with-html-form
                                         (:post (lambda (&rest args)
                                                  (declare (ignorable args))
                                                  (edit widget)))
                                       (:input :type "submit"
                                               :class "button tiny"
                                               :name "button"
                                               :value "Edit")))))))
                  (:tbody
                   (:tr (:td :class "label-column"
                             "Created at")
                        (:td :class "field-column"
                             (humanize-timestamp
                              (mito:object-created-at source))))
                   (:tr (:td :class "label-column"
                             "Source")
                        (:td :class "field-column"
                             (:a :href url
                                 url)))
                   (:tr (:td :class "label-column"
                             "Branch or tag")
                        (:td :class "field-column"
                             (ultralisp/models/source:get-current-branch source)))
                   (when ignore-dirs
                     (:tr (:td :class "label-column"
                               "Ignore systems in these dirs and ASD files")
                          (:td :class "field-column"
                               (:pre
                                (:code
                                 (format-ignore-list
                                  ignore-dirs))))))
                   (when last-seen-commit
                     (:tr (:td :class "label-column"
                               "Last seen commit")
                          (:td :class "field-column"
                               (:a :href (fmt "~A/commit/~A" url last-seen-commit)
                                   last-seen-commit))))
                   (when release-info
                     (:tr (:td :class "label-column"
                               "Release")
                          (:td :class "field-column"
                               (:a :href (quickdist:get-project-url release-info)
                                   (quickdist:get-project-url release-info)))))
                   (when systems
                     (:tr (:td :class "label-column"
                               "Systems")
                          (:td :class "field-column"
                               (:dl
                                (loop with grouped = (sort
                                                      (group-by systems
                                                                :key #'quickdist:get-filename
                                                                :value #'quickdist:get-name
                                                                :test #'string=)
                                                      #'string<
                                                      :key #'car)
                                      for (filename . systems) in grouped
                                      do (:dt filename)
                                         (:dd :style "padding-left: 2em"
                                              (join ", " (sort systems
                                                               #'string<))))))))
                   (:tr (:td :class "label-column"
                             "Distributions")
                        (:td :class "field-column"
                             (mapc #'render-distribution
                                   distributions)))
                   (:tr (:td :class "label-column"
                             "Last check")
                        (:td :class "field-column"
                             (cond
                               (last-check
                                (let* ((processed-at (ultralisp/models/check:get-processed-at
                                                      last-check)))
                                  (cond (processed-at
                                         (let* ((now (now))
                                                (duration
                                                  (humanize-duration
                                                   (timestamp-difference
                                                    now
                                                    processed-at)))
                                                (error (ultralisp/models/check:get-error last-check))
                                                (time-to-next-check
                                                  (local-time-duration:timestamp-difference
                                                                 (get-time-of-the-next-check source)
                                                                 now))
                                                (next-check-at (if (> (local-time-duration:duration-as time-to-next-check :sec)
                                                                      0)
                                                                   (fmt " Next check will be made in ~A."
                                                                        (humanize-duration
                                                                         time-to-next-check))
                                                                   " Next check will be made very soon.")))
                                           (:span (fmt "Finished ~A ago. " duration))
                                           
                                           (when error
                                             (:span "There was an")
                                             (let* ((popup-id (symbol-name (gensym "ERROR-POPUP"))))
                                               (:div :id popup-id
                                                     :class "reveal large"
                                                     :data-reveal "true"
                                                     (:h1 "Check Error")
                                                     (:pre error))
                                               (:a :data-open popup-id
                                                   "error"))
                                             (:span "."))
                                           (:span next-check-at)))
                                        (t
                                         ("Waiting in the queue. Position: ~A."
                                          (ultralisp/models/check:position-in-the-queue last-check))))))
                               (t
                                ("No checks yet.")))

                             (when user-is-moderator
                               (reblocks-ui/form:with-html-form
                                   (:post (lambda (&rest args)
                                            (declare (ignore args))
                                            ;; This call will create a new check
                                            ;; only if it is not exist yet:
                                            (make-check source
                                                        :manual)
                                            (reblocks/widget:update widget))
                                    :class "float-right")
                                 (:input :type "submit"
                                         :class "button tiny secondary"
                                         :name "button"
                                         :value "Check"
                                         :title "Put the check into the queue."))))))))))))


;; Probably I need to replace eql git with real class and reuse some code between
;; git and github source types?
(defmethod render-source ((widget readonly-source-widget)
                          (type (eql :git))
                          source)
  (let* ((params (ultralisp/models/source:source-params source))
         (deleted (ultralisp/models/source:deleted-p source))
         ;; The only difference between github and git sources
         ;; (url (github-url params))
         (url (getf params :url))
         (last-seen-commit (getf params :last-seen-commit))
         (ignore-dirs (getf params :ignore-dirs))
         (release-info (ultralisp/models/source:source-release-info source))
         (distributions (source-distributions source))
         (systems (ultralisp/models/source:source-systems-info source))
         (user-is-moderator (is-moderator
                             (get-current-user)
                             (source->project source))))
    ;; Deleted sources should not be in the list
    ;; for rendering.
    (assert (not deleted))

    (flet ((deletion-handler (&rest args)
             (declare (ignorable args))
             (on-delete (parent widget))))
      (let ((last-check (get-last-source-check source)))
        (with-html ()
          (:table :class "unstriped"
                  (:thead
                   (:tr (:th :class "label-column"
                             "Type")
                        (:th :class "field-column"
                             type
                             ;; Controls for editing and deleting source
                             (when user-is-moderator
                               (:div :class "source-controls float-right"
                                     (reblocks-ui/form:with-html-form
                                         (:post #'deletion-handler
                                          :requires-confirmation-p t
                                          :confirm-question (:div (:h1 "Warning!")
                                                                  (:p "If you'll remove this source, it will be excluded from the future versions of these distributions:")
                                                                  (:ul
                                                                   (loop for name in (mapcar #'dist-name
                                                                                             (remove-if-not
                                                                                              #'enabled-p
                                                                                              (source->dists source)))
                                                                         do (:li name)))))
                                       (:input :type "submit"
                                               :class "alert button tiny"
                                               :name "button"
                                               :value "Remove"))
                                    
                                     (reblocks-ui/form:with-html-form
                                         (:post (lambda (&rest args)
                                                  (declare (ignorable args))
                                                  (edit widget)))
                                       (:input :type "submit"
                                               :class "button tiny"
                                               :name "button"
                                               :value "Edit")))))))
                  (:tbody
                   (:tr (:td :class "label-column"
                             "Created at")
                        (:td :class "field-column"
                             (humanize-timestamp
                              (mito:object-created-at source))))
                   (:tr (:td :class "label-column"
                             "Source")
                        (:td :class "field-column"
                             (:a :href url
                                 url)))
                   (:tr (:td :class "label-column"
                             "Branch or tag")
                        (:td :class "field-column"
                             (ultralisp/models/source:get-current-branch source)))
                   (when ignore-dirs
                     (:tr (:td :class "label-column"
                               "Ignore systems in these dirs and ASD files")
                          (:td :class "field-column"
                               (:pre
                                (:code
                                 (format-ignore-list
                                  ignore-dirs))))))
                   (when last-seen-commit
                     (:tr (:td :class "label-column"
                               "Last seen commit")
                          (:td :class "field-column"
                               (:a :href (fmt "~A/commit/~A" url last-seen-commit)
                                   last-seen-commit))))
                   (when release-info
                     (:tr (:td :class "label-column"
                               "Release")
                          (:td :class "field-column"
                               (:a :href (quickdist:get-project-url release-info)
                                   (quickdist:get-project-url release-info)))))
                   (when systems
                     (:tr (:td :class "label-column"
                               "Systems")
                          (:td :class "field-column"
                               (:dl
                                (loop with grouped = (sort
                                                      (group-by systems
                                                                :key #'quickdist:get-filename
                                                                :value #'quickdist:get-name
                                                                :test #'string=)
                                                      #'string<
                                                      :key #'car)
                                      for (filename . systems) in grouped
                                      do (:dt filename)
                                         (:dd :style "padding-left: 2em"
                                              (join ", " (sort systems
                                                               #'string<))))))))
                   (:tr (:td :class "label-column"
                             "Distributions")
                        (:td :class "field-column"
                             (mapc #'render-distribution
                                   distributions)))
                   (:tr (:td :class "label-column"
                             "Last check")
                        (:td :class "field-column"
                             (cond
                               (last-check
                                (let* ((processed-at (ultralisp/models/check:get-processed-at
                                                      last-check)))
                                  (cond (processed-at
                                         (let* ((now (now))
                                                (duration
                                                  (humanize-duration
                                                   (timestamp-difference
                                                    now
                                                    processed-at)))
                                                (error (ultralisp/models/check:get-error last-check))
                                                (time-to-next-check
                                                  (local-time-duration:timestamp-difference
                                                   (get-time-of-the-next-check source)
                                                   now))
                                                (next-check-at (if (> (local-time-duration:duration-as time-to-next-check :sec)
                                                                      0)
                                                                   (fmt " Next check will be made in ~A."
                                                                        (humanize-duration
                                                                         time-to-next-check))
                                                                   " Next check will be made very soon.")))
                                           (:span (fmt "Finished ~A ago. " duration))
                                           
                                           (when error
                                             (:span "There was an")
                                             (let* ((popup-id (symbol-name (gensym "ERROR-POPUP"))))
                                               (:div :id popup-id
                                                     :class "reveal large"
                                                     :data-reveal "true"
                                                     (:h1 "Check Error")
                                                     (:pre error))
                                               (:a :data-open popup-id
                                                   "error"))
                                             (:span "."))
                                           (:span next-check-at)))
                                        (t
                                         ("Waiting in the queue. Position: ~A."
                                          (ultralisp/models/check:position-in-the-queue last-check))))))
                               (t
                                ("No checks yet.")))

                             (when user-is-moderator
                               (reblocks-ui/form:with-html-form
                                   (:post (lambda (&rest args)
                                            (declare (ignore args))
                                            ;; This call will create a new check
                                            ;; only if it is not exist yet:
                                            (make-check source
                                                        :manual)
                                            (reblocks/widget:update widget))
                                    :class "float-right")
                                 (:input :type "submit"
                                         :class "button tiny secondary"
                                         :name "button"
                                         :value "Check"
                                         :title "Put the check into the queue."))))))))))))


(defmethod render-source ((widget readonly-source-widget)
                          (type (eql :archive))
                          source)
  (with-html ()
    (:p "Archive sources aren't supported yet")))


(defmethod render-source ((widget edit-source-widget)
                          (type (eql :github))
                          source)
  (let* ((params (ultralisp/models/source:source-params source))
         (deleted (ultralisp/models/source:deleted-p source))
         (url (github-url params))
         (last-seen-commit (getf params :last-seen-commit))
         (ignore-dirs (getf params :ignore-dirs))
         ;; (distributions (source-distributions source))
         (user (reblocks-auth/models:get-current-user))
         (user-dists (ultralisp/models/dist-moderator:moderated-dists user))
         (all-dists (append (ultralisp/models/dist:public-dists)
                          user-dists))
         ;; Previously we gathered only enabled dists, but this lead
         ;; to a bug when you can't remove a source from the dist where
         ;; it was disabled or where it is not checked yet.
         (current-dists (source->dists source))
         (release-info (ultralisp/models/source:source-release-info source)))
    ;; Deleted sources should not be in the list
    ;; for rendering.
    (assert (not deleted))

    (flet ((is-enabled (dist)
             (member (ultralisp/models/dist:dist-name dist)
                     current-dists
                     :key #'ultralisp/models/dist:dist-name
                     :test #'string-equal)))
      (with-html ()
        (reblocks-ui/form:with-html-form
            (:post (lambda (&rest args)
                     (handler-case (save widget args)
                       (asdf-systems-conflict (c)
                         (let ((message (fmt "~A" c)))
                           (setf (dist-conflicts widget)
                                 message)
                           (reblocks/widget:update widget))))))
          (form-error-placeholder)
          (:table :class "unstriped"
           (:thead
            (:tr (:th :class "label-column"
                      "Type")
                 (:th :class "field-column"
                      type
                      (:div :class "source-controls float-right"
                            (let ((js-code-to-cancel
                                    (make-js-action
                                     (lambda (&rest args)
                                           (declare (ignore args))
                                       (switch-to-readonly widget)))))
                              (:input :type "button"
                                      :class "secondary button tiny"
                                      :name "button"
                                      :onclick js-code-to-cancel
                                      :value "Cancel"))
                            (:input :type "submit"
                                    :class "success button tiny"
                                    :name "button"
                                    :value "Save")))))
           (:tbody
            (:tr (:td :class "label-column"
                      "Source")
                 (:td :class "field-column"
                      (:input :value url
                              :name "url"
                              :type "text"
                              :onchange
                              (make-js-handler
                               :lisp-code ((&key url &allow-other-keys)
                                           (update-url (branches widget)
                                                       url))
                               :js-code ((event)
                                         ;; This will pass new URL value
                                         ;; to the backend:
                                         (parenscript:create
                                          :url (@ event target value)))))))
            (:tr (:td :class "label-column"
                      "Branch or tag")
                 (:td :class "field-column"
                      (render (branches widget))))
            (:tr (:td :class "label-column"
                      "Ignore systems in these dirs and ASD files")
                 (:td :class "field-column"
                      (:textarea :name "ignore-dirs"
                                 :placeholder "vendor/, my-system-test.asd"
                                 (format-ignore-list
                                  ignore-dirs))))
            (when last-seen-commit
              (:tr (:td :class "label-column"
                        "Last seen commit")
                   (:td :class "field-column"
                        (:a :href (fmt "~A/commit/~A" url last-seen-commit)
                            last-seen-commit))))
            (when release-info
              (:tr (:td :class "label-column"
                        "Release")
                   (:td (:a :href (quickdist:get-project-url release-info)
                            (quickdist:get-project-url release-info)))))
            (:tr (:td :class "label-column"
                      "Distributions")
                 (:td :class "field-column"
                      (loop for dist in all-dists
                            for name = (ultralisp/models/dist:dist-name dist)
                            do  (:input :type "checkbox"
                                        :name "distributions"
                                        :value name
                                        :checked (is-enabled dist)
                                        (:label name)))
                      (when (dist-conflicts widget)
                        (:pre :class "error"
                              (dist-conflicts widget)))
                      (error-placeholder "distributions"))))))))))


;; TODO: deduplicate code between :git and :github
(defmethod render-source ((widget edit-source-widget)
                          (type (eql :git))
                          source)
  (let* ((params (ultralisp/models/source:source-params source))
         (deleted (ultralisp/models/source:deleted-p source))
         ;; TODO: difference
         (url (getf params :url))
         (last-seen-commit (getf params :last-seen-commit))
         (ignore-dirs (getf params :ignore-dirs))
         ;; (distributions (source-distributions source))
         (user (reblocks-auth/models:get-current-user))
         (user-dists (ultralisp/models/dist-moderator:moderated-dists user))
         (all-dists (append (ultralisp/models/dist:public-dists)
                            user-dists))
         ;; Previously we gathered only enabled dists, but this lead
         ;; to a bug when you can't remove a source from the dist where
         ;; it was disabled or where it is not checked yet.
         (current-dists (source->dists source))
         (release-info (ultralisp/models/source:source-release-info source)))
    ;; Deleted sources should not be in the list
    ;; for rendering.
    (assert (not deleted))

    (flet ((is-enabled (dist)
             (member (ultralisp/models/dist:dist-name dist)
                     current-dists
                     :key #'ultralisp/models/dist:dist-name
                     :test #'string-equal)))
      (with-html ()
        (reblocks-ui/form:with-html-form
            (:post (lambda (&rest args)
                     (handler-case (save widget args)
                       (asdf-systems-conflict (c)
                         (let ((message (fmt "~A" c)))
                           (setf (dist-conflicts widget)
                                 message)
                           (reblocks/widget:update widget))))))
          (form-error-placeholder)
          (:table :class "unstriped"
                  (:thead
                   (:tr (:th :class "label-column"
                             "Type")
                        (:th :class "field-column"
                             type
                             (:div :class "source-controls float-right"
                                   (let ((js-code-to-cancel
                                           (make-js-action
                                            (lambda (&rest args)
                                              (declare (ignore args))
                                              (switch-to-readonly widget)))))
                                     (:input :type "button"
                                             :class "secondary button tiny"
                                             :name "button"
                                             :onclick js-code-to-cancel
                                             :value "Cancel"))
                                   (:input :type "submit"
                                           :class "success button tiny"
                                           :name "button"
                                           :value "Save")))))
                  (:tbody
                   (:tr (:td :class "label-column"
                             "Source")
                        (:td :class "field-column"
                             (:input :value url
                                     :name "url"
                                     :type "text"
                                     :onchange
                                     (make-js-handler
                                      :lisp-code ((&key url &allow-other-keys)
                                                  (update-url (branches widget)
                                                              url))
                                      :js-code ((event)
                                                ;; This will pass new URL value
                                                ;; to the backend:
                                                (parenscript:create
                                                 :url (@ event target value)))))))
                   (:tr (:td :class "label-column"
                             "Branch or tag")
                        (:td :class "field-column"
                             (render (branches widget))))
                   (:tr (:td :class "label-column"
                             "Ignore systems in these dirs and ASD files")
                        (:td :class "field-column"
                             (:textarea :name "ignore-dirs"
                                        :placeholder "vendor/, my-system-test.asd"
                                        (format-ignore-list
                                         ignore-dirs))))
                   (when last-seen-commit
                     (:tr (:td :class "label-column"
                               "Last seen commit")
                          (:td :class "field-column"
                               (:a :href (fmt "~A/commit/~A" url last-seen-commit)
                                   last-seen-commit))))
                   (when release-info
                     (:tr (:td :class "label-column"
                               "Release")
                          (:td (:a :href (quickdist:get-project-url release-info)
                                   (quickdist:get-project-url release-info)))))
                   (:tr (:td :class "label-column"
                             "Distributions")
                        (:td :class "field-column"
                             (loop for dist in all-dists
                                   for name = (ultralisp/models/dist:dist-name dist)
                                   do  (:input :type "checkbox"
                                               :name "distributions"
                                               :value name
                                               :checked (is-enabled dist)
                                               (:label name)))
                             (when (dist-conflicts widget)
                               (:pre :class "error"
                                     (dist-conflicts widget)))
                             (error-placeholder "distributions"))))))))))



(defmethod reblocks/widget:render ((widget branch-select-widget))
  (with-html ()
    (:select :name "branch"
      (:option :disabled "disabled"
               "Select a branch")
      (loop with current = (current-branch widget)
            for branch in (branches widget)
            do (:option :selected (when (string-equal branch
                                                      current)
                                    "selected")
                        branch)))))


(defmethod reblocks/widget:render ((widget source-widget))
  ;; When user hits the refresh button we need to update
  ;; source information because it might be changed
  ;; while page was opened in the browser.
  (when (reblocks/request:refresh-request-p)
    (setf (source widget)
          (get-latest-version-of (source widget))))
  
  (reblocks/widget:render (subwidget widget)))


(defmethod reblocks/widget:render ((widget readonly-source-widget))
  (let* ((source (source (parent widget)))
         (type (ultralisp/models/source:source-type source)))
    (with-html ()
      ;; This piece here to make debugging easier:
      (:p :style "display: none"
          (fmt "source-id=~S version=~S project-id=~S project-version=~S"
               (object-id source)
               (object-version source)
               (source-project-id source)
               (project-version source))))
    (render-source widget type source)))


(defmethod reblocks/widget:render ((widget edit-source-widget))
  (let* ((source (source (parent widget)))
         (type (ultralisp/models/source:source-type source)))
    (render-source widget type source)))


(defmethod reblocks/dependencies:get-dependencies ((widget source-widget))
  (append
   (list
    (reblocks-lass:make-dependency
      `(.source-widget
        :border-top "2px solid #cc4b37"
        (input :margin 0)
        (.dist :margin-right 1em)
        (.label-column :white-space "nowrap"
                       :vertical-align "top")
        (.field-column :width "100%")
        ((:and .dist .disabled) :color "gray")

        ((.source-controls > (:or form input))
         :display "inline-block"
         :margin-left 1em)
        (.error :color "red"))))
   (call-next-method)))


;; Methods to render changes between source versions

(defmethod ultralisp/protocols/render-changes:render ((type (eql :git)) prev-source new-source)
  (reblocks/html:with-html ()
    (:ul
     (loop with old-params = (ultralisp/models/source:source-params prev-source)
           with new-params = (ultralisp/models/source:source-params new-source)
           with key-to-name = '(:last-seen-commit "commit")
           with key-to-length = '(:last-seen-commit 8)
           for (key new-value) on new-params by #'cddr
           for old-value = (let ((result (getf old-params key)))
                             (cond
                               ;; For new sources
                               ;; branch might be not given.
                               ;; In this case we show it as "main"
                               ;; TODO: We need to fill branch parameter
                               ;; when source gets added to the database.
                               ;; When it will be done, this hack can be removed.
                               ((and (eql key :branch)
                                     (null result))
                                "main")
                               (t result)))
           for name = (getf key-to-name key
                            (string-downcase
                             (symbol-name key)))
           for length = (getf key-to-length key 20)
           unless (equal old-value new-value)
           do (:li ("**~A** ~A ➞ ~A"
                    name
                    (str:shorten length old-value :ellipsis "…")
                    (str:shorten length new-value :ellipsis "…")))))))


(defmethod ultralisp/protocols/render-changes:render ((type (eql :github)) prev-source new-source)
  ;; Renders for :git and :github are the same. Probably we don't need a generic function here?
  (ultralisp/protocols/render-changes:render :git prev-source new-source))


(defmethod reblocks/widget:render ((widget add-source-widget))
  (let ((project (project widget))
        (user (reblocks-auth/models:get-current-user)))
    (reblocks/html:with-html ()
      ;; Controls for editing and deleting source
      (when (ultralisp/protocols/moderation:is-moderator user project)
        (reblocks-ui/form:with-html-form
            (:post (lambda (&rest args)
                     (declare (ignorable args))
                     (let* ((on-new-source (on-new-source widget))
                            (source-type (make-keyword (getf args :type)))
                            (source (ultralisp/models/source:create-source project
                                                                           source-type)))
                       (safe-funcall on-new-source source))))
          (:table
           (:tr
            (:td
             (:label :style "min-width: 20%; white-space: nowrap"
                     "New source of type:"))
            (:td
             (:select :name "type"
               :style "min-width: 7em; margin: 0"
               (:option :selected t
                        :value "github"
                        "GitHub")
               (:option :value "git"
                        "Git")
               (:option :value "archive"
                        :disabled t "Tar Archive (not supported yet)")
               (:option :value "mercurial"
                        :disabled t "Mercurial (not supported yet)")))
            (:td :style "width: 100%"
                 (:input :type "submit"
                         :class "button small"
                         :style "margin: 0"
                         :name "button"
                         :value "Add")))))))))
