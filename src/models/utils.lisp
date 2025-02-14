(defpackage #:ultralisp/models/utils
  (:use #:cl)
  (:import-from #:yason)
  (:import-from #:serapeum
                #:dict
                #:@)
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
  (:import-from #:ultralisp/models/system-info
                #:system-info)
  (:export #:systems-info-to-json
           #:release-info-to-json
           #:systems-info-from-json
           #:release-info-from-json))
(in-package #:ultralisp/models/utils)


(defun %normalize-names (name-or-names)
  ;; This is a workaround for cases when quoting is used inside defsystem
  ;; https://github.com/thephoeron/fmcs/pull/1
  (typecase name-or-names
    (list (cond
            ((eql (first name-or-names)
                  'quote)
             (second name-or-names))
            (t
             name-or-names)))
    (string name-or-names)
    (t nil)))


(defun %normalize-license (license)
  (typecase license
    (string license)
    (t
     (log:warn "Project's license is not string: ~S. Coercing to string."
               license)
     (princ-to-string license))))


(defun %system-info-to-json (system-info)
  (check-type system-info system-info)

  ;; Using uppercase to preserve backward compatibility
  ;; with old data in the database.
  (dict "PATH" (uiop:native-namestring (get-path system-info))
        "PROJECT-NAME" (get-project-name system-info)
        "FILENAME" (get-filename system-info)
        "NAME" (quickdist:get-name system-info)
        "DEPENDENCIES" (get-dependencies system-info)
        ;; Some authors may use symbol as license name like in:
        ;; https://github.com/ajberkley/cl-binary-store/blob/3b0587eaaa74c79734477cb38132237411068ef8/cl-binary-store.asd#L66
        ;; But we need to serialize it to JSON:
        "LICENSE" (%normalize-license
                   (ultralisp/models/system-info::system-info-license system-info))
        "AUTHOR" (%normalize-names
                  (ultralisp/models/system-info::system-info-author system-info))
        "MAINTAINER" (%normalize-names
                      (ultralisp/models/system-info::system-info-maintainer system-info))
        "DESCRIPTION" (ultralisp/models/system-info::system-info-description system-info)
        "LONG-DESCRIPTION" (ultralisp/models/system-info::system-info-long-description system-info)))

(defun systems-info-to-json (systems-info)
  "Prepares a list of systems info objects to be serialized to json."
  (yason:with-output-to-string* ()
    (yason:encode
     ;; If we won't transform systems-info list into the vector,
     ;; then yason will output "null" instead of "[]" for empty lists
     (map 'simple-vector
          #'%system-info-to-json
          systems-info))))


(defun release-info-to-json (release-info)
  (check-type release-info (or null quickdist:release-info))
  
  (yason:with-output-to-string* ()
    (yason:encode
     (if release-info
         (dict "PROJECT-NAME" (get-project-name release-info)
               "PROJECT-URL" (get-project-url release-info)
               "ARCHIVE-PATH" (uiop:native-namestring (get-archive-path release-info))
               "FILE-SIZE" (get-file-size release-info)
               "MD5SUM" (get-md5sum release-info)
               "CONTENT-SHA1" (get-content-sha1 release-info)
               "PROJECT-PREFIX" (get-project-prefix release-info)
               "SYSTEM-FILES" (get-system-files release-info))
         :null))))


(defun %system-info-from-json (data)
  "Prepares a list of systems info objects to be deserialized from json."
  (when data
    (make-instance 'system-info
                   :path (@ data "PATH")
                   :project-name (@ data "PROJECT-NAME")
                   :filename (@ data "FILENAME")
                   :name (@ data "NAME")
                   :dependencies (@ data "DEPENDENCIES")
                   :license (@ data "LICENSE")
                   :author (@ data "AUTHOR")
                   :maintainer (@ data "MAINTAINER")
                   :description (@ data "DESCRIPTION")
                   :long-description (@ data "LONG-DESCRIPTION"))))


(defun release-info-from-json (json)
  (when json
    (let ((data (yason:parse json)))
      (when data
        (make-instance 'quickdist:release-info
                       :project-name (@ data "PROJECT-NAME")
                       :project-url (@ data "PROJECT-URL")
                       :archive-path (@ data "ARCHIVE-PATH")
                       :file-size (@ data "FILE-SIZE")
                       :md5sum (@ data "MD5SUM")
                       :content-sha1 (@ data "CONTENT-SHA1")
                       :project-prefix (@ data "PROJECT-PREFIX")
                       :system-files (@ data "SYSTEM-FILES"))))))


(defun systems-info-from-json (json)
  "Prepares a list of systems info objects to be serialized to json."
  (when json
    (let ((data (yason:parse json)))
      (mapcar #'%system-info-from-json
              data))))
