(in-package #:groceries)


(defvar *db-name* nil)
(defvar *db-user* nil)
(defvar *db-pass* nil)
(defvar *db-host* nil)
(defvar *db-port* nil)

(defmacro with-db (&body body)
  "postmodern:with-connection with db credentials."
  `(pm:with-connection (list *db-name* *db-user* *db-pass*
                             *db-host* :port *db-port* :pooled-p t)
     ,@body))

(pm:defprepared db-schema-exists "
SELECT EXISTS(
        SELECT *
        FROM information_schema.tables
        WHERE table_name = $1
        AND table_catalog = $2
)" :single)

(defun db-version ()
  (with-db
    (unless (db-schema-exists "db_version" *db-name*)
      (return-from db-version 0))
    (pm:query "SELECT schema_version()" :single)))

(defun db-upgrade (source dest)
  (loop
     :for i from (1+ source) upto dest
     :do (progn
           (format t "Running upgrade ~D...~%" i)
           (with-db
             (db-run (merge-pathnames
                      (concatenate 'string (write-to-string i) ".sql")
                      (or
                       (uiop:getenv "SQL_UPGRADES_FOLDER")
                       (merge-pathnames "sql/upgrades/"
                                        (asdf:system-source-directory :groceries))))
                     :multiqueries t)))))

(defun db-initialize ()
  ;; schema is the only multi-queries file
  (let ((sql-folder
         (or (uiop:getenv "SQL_FOLDER")
             (merge-pathnames "sql/" (asdf:system-source-directory :groceries)))))
    (db-run (merge-pathnames "schema.sql" sql-folder)
            :multiqueries t)
    (dolist (file (mapcar
                   #'(lambda (name)
                       (merge-pathnames
                        (concatenate 'string name ".sql")
                        sql-folder))
                   '("schema_version"
                     "items"
                     "add_item"
                     "list_items")))
      (db-run file))))

(defun db-run (file &key (multiqueries nil))
  (with-db
    (if multiqueries
        (loop
           :for query in (cl-ppcre:split "-----" (a:read-file-into-string file))
           :do (pm:query query))
        (pm:query (a:read-file-into-string file)))))

(defun str-alists-to-jsown-json (str-alists)
  (mapcar #'(lambda (item)
              `(:obj ,@item))
          str-alists))
