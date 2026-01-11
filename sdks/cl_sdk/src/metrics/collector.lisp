;;;; collector.lisp
;;;;
;;;; Production metrics collection for SW4RM orchestrator
;;;;
;;;; This module provides:
;;;;   - Counter, Gauge, and Histogram metric types
;;;;   - Thread-safe metric collection with fine-grained locks
;;;;   - Prometheus text exposition format export
;;;;   - Label support for multi-dimensional metrics
;;;;   - Standard SW4RM metrics pre-configured
;;;;
;;;; Version: 0.6.0
;;;; License: Apache 2.0

(in-package :sw4rm-orchestrator.metrics)

;;;; ============================================================================
;;;; Metric Types
;;;; ============================================================================

(defclass metric ()
  ((name :accessor metric-name
         :initarg :name
         :type string
         :documentation "Metric name (follows Prometheus naming convention)")
   (help :accessor metric-help
         :initarg :help
         :initform ""
         :type string
         :documentation "Help text describing the metric")
   (labels :accessor metric-labels
           :initarg :labels
           :initform nil
           :type list
           :documentation "List of label names (keywords)"))
  (:documentation "Base class for all metric types."))

(defclass counter (metric)
  ((values :accessor counter-values
           :initform (make-hash-table :test 'equal)
           :documentation "Hash table mapping label values to counter values"))
  (:documentation "Counter is a cumulative metric that only increases.

   Use counters for:
     - Total requests processed
     - Total errors encountered
     - Total messages routed

   Examples:
     (inc-counter \"sw4rm_messages_total\" :label-values '(:swarm-id \"leaf-a\"))"))

(defclass gauge (metric)
  ((values :accessor gauge-values
           :initform (make-hash-table :test 'equal)
           :documentation "Hash table mapping label values to gauge values"))
  (:documentation "Gauge is a metric that can go up or down.

   Use gauges for:
     - Current queue depth
     - Active connections
     - Memory usage

   Examples:
     (set-gauge \"sw4rm_connections\" 5 :label-values '(:swarm-id \"leaf-a\"))
     (inc-gauge \"sw4rm_queue_depth\")
     (dec-gauge \"sw4rm_queue_depth\")"))

(defconstant +default-histogram-buckets+
  '(0.001 0.005 0.01 0.025 0.05 0.1 0.25 0.5 1.0 2.5 5.0 10.0)
  "Default histogram bucket boundaries in seconds.

   Suitable for measuring latencies from 1ms to 10s.")

(defclass histogram (metric)
  ((buckets :accessor histogram-buckets
            :initarg :buckets
            :initform +default-histogram-buckets+
            :type list
            :documentation "Sorted list of bucket boundaries")
   (counts :accessor histogram-counts
           :initform (make-hash-table :test 'equal)
           :documentation "Hash table mapping labels to bucket count vectors")
   (sums :accessor histogram-sums
         :initform (make-hash-table :test 'equal)
         :documentation "Hash table mapping labels to sum of observed values")
   (totals :accessor histogram-totals
           :initform (make-hash-table :test 'equal)
           :documentation "Hash table mapping labels to total observation count"))
  (:documentation "Histogram tracks observations in configurable buckets.

   Use histograms for:
     - Request latencies
     - Response sizes
     - Operation durations

   Each observation increments all buckets where value <= bucket boundary.

   Examples:
     (observe-histogram \"sw4rm_latency_seconds\" 0.025
                        :label-values '(:operation \"route\"))"))

;;;; ============================================================================
;;;; Metrics Registry
;;;; ============================================================================

(defclass metrics-registry ()
  ((metrics :accessor registry-metrics
            :initform (make-hash-table :test 'equal)
            :documentation "Hash table mapping metric names to metric objects")
   (lock :accessor registry-lock
         :initform (bt:make-lock "metrics-registry")
         :documentation "Lock protecting registry modifications"))
  (:documentation "Registry holds all metrics for an application.

   Typically use *DEFAULT-REGISTRY* unless you need isolated metrics."))

(defvar *default-registry* (make-instance 'metrics-registry)
  "Default metrics registry for the application.")

;;;; ============================================================================
;;;; Registry Operations
;;;; ============================================================================

(defun register-metric (metric &optional (registry *default-registry*))
  "Register a metric in the registry.

   Args:
     metric - METRIC instance to register
     registry - Registry to use (default: *default-registry*)

   Returns:
     The registered metric.

   Raises:
     ERROR if metric with same name already exists."
  (bt:with-lock-held ((registry-lock registry))
    (let ((name (metric-name metric)))
      (when (gethash name (registry-metrics registry))
        (error "Metric already registered: ~A" name))
      (setf (gethash name (registry-metrics registry)) metric)
      metric)))

(defun get-metric (name &optional (registry *default-registry*))
  "Get a metric by name from the registry.

   Args:
     name - Metric name string
     registry - Registry to use (default: *default-registry*)

   Returns:
     METRIC instance or NIL if not found."
  (bt:with-lock-held ((registry-lock registry))
    (gethash name (registry-metrics registry))))

(defun unregister-metric (name &optional (registry *default-registry*))
  "Remove a metric from the registry.

   Args:
     name - Metric name string
     registry - Registry to use

   Returns:
     T if metric was removed, NIL if not found."
  (bt:with-lock-held ((registry-lock registry))
    (remhash name (registry-metrics registry))))

;;;; ============================================================================
;;;; Metric Creation Helpers
;;;; ============================================================================

(defun make-counter (name &key help labels (registry *default-registry*))
  "Create and register a counter metric.

   Args:
     name - Metric name (string)
     help - Help text describing the metric
     labels - List of label names (keywords)
     registry - Registry to use

   Returns:
     New COUNTER instance.

   Examples:
     (make-counter \"sw4rm_messages_total\"
                   :help \"Total messages routed\"
                   :labels '(:source-swarm :target-swarm))"
  (let ((counter (make-instance 'counter
                                :name name
                                :help (or help "")
                                :labels labels)))
    (register-metric counter registry)
    counter))

(defun make-gauge (name &key help labels (registry *default-registry*))
  "Create and register a gauge metric.

   Args:
     name - Metric name (string)
     help - Help text describing the metric
     labels - List of label names (keywords)
     registry - Registry to use

   Returns:
     New GAUGE instance.

   Examples:
     (make-gauge \"sw4rm_connections\"
                 :help \"Active gRPC connections\"
                 :labels '(:swarm-id :state))"
  (let ((gauge (make-instance 'gauge
                              :name name
                              :help (or help "")
                              :labels labels)))
    (register-metric gauge registry)
    gauge))

(defun make-histogram (name &key help labels buckets (registry *default-registry*))
  "Create and register a histogram metric.

   Args:
     name - Metric name (string)
     help - Help text describing the metric
     labels - List of label names (keywords)
     buckets - List of bucket boundaries (default: +DEFAULT-HISTOGRAM-BUCKETS+)
     registry - Registry to use

   Returns:
     New HISTOGRAM instance.

   Examples:
     (make-histogram \"sw4rm_latency_seconds\"
                     :help \"Operation latency in seconds\"
                     :labels '(:operation)
                     :buckets '(0.001 0.01 0.1 1.0))"
  (let ((histogram (make-instance 'histogram
                                  :name name
                                  :help (or help "")
                                  :labels labels
                                  :buckets (or buckets +default-histogram-buckets+))))
    (register-metric histogram registry)
    histogram))

;;;; ============================================================================
;;;; Counter Operations
;;;; ============================================================================

(defun inc-counter (counter &key (amount 1) (label-values nil))
  "Increment a counter metric.

   Args:
     counter - COUNTER instance or metric name string
     amount - Amount to increment (default: 1)
     label-values - Plist of label values

   Returns:
     New counter value.

   Examples:
     (inc-counter \"sw4rm_messages_total\"
                  :label-values '(:source-swarm \"leaf-a\" :target-swarm \"leaf-b\"))"
  (let ((c (if (stringp counter)
               (get-metric counter)
               counter)))
    (unless c
      (error "Counter not found: ~A" counter))

    (let ((key (serialize-label-values (metric-labels c) label-values)))
      (bt:with-lock-held ((make-lock-for-metric c))
        (incf (gethash key (counter-values c) 0) amount)))))

;;;; ============================================================================
;;;; Gauge Operations
;;;; ============================================================================

(defun set-gauge (gauge value &key (label-values nil))
  "Set a gauge metric to a specific value.

   Args:
     gauge - GAUGE instance or metric name string
     value - Value to set
     label-values - Plist of label values

   Returns:
     The set value.

   Examples:
     (set-gauge \"sw4rm_connections\" 5
                :label-values '(:swarm-id \"leaf-a\" :state \"connected\"))"
  (let ((g (if (stringp gauge)
               (get-metric gauge)
               gauge)))
    (unless g
      (error "Gauge not found: ~A" gauge))

    (let ((key (serialize-label-values (metric-labels g) label-values)))
      (bt:with-lock-held ((make-lock-for-metric g))
        (setf (gethash key (gauge-values g)) value)))))

(defun inc-gauge (gauge &key (amount 1) (label-values nil))
  "Increment a gauge metric.

   Args:
     gauge - GAUGE instance or metric name string
     amount - Amount to increment (default: 1)
     label-values - Plist of label values

   Returns:
     New gauge value."
  (let ((g (if (stringp gauge)
               (get-metric gauge)
               gauge)))
    (unless g
      (error "Gauge not found: ~A" gauge))

    (let ((key (serialize-label-values (metric-labels g) label-values)))
      (bt:with-lock-held ((make-lock-for-metric g))
        (incf (gethash key (gauge-values g) 0) amount)))))

(defun dec-gauge (gauge &key (amount 1) (label-values nil))
  "Decrement a gauge metric.

   Args:
     gauge - GAUGE instance or metric name string
     amount - Amount to decrement (default: 1)
     label-values - Plist of label values

   Returns:
     New gauge value."
  (inc-gauge gauge :amount (- amount) :label-values label-values))

;;;; ============================================================================
;;;; Histogram Operations
;;;; ============================================================================

(defun observe-histogram (histogram value &key (label-values nil))
  "Observe a value in a histogram metric.

   Args:
     histogram - HISTOGRAM instance or metric name string
     value - Observed value (typically latency in seconds)
     label-values - Plist of label values

   Examples:
     (observe-histogram \"sw4rm_latency_seconds\" 0.025
                        :label-values '(:operation \"route\"))"
  (let ((h (if (stringp histogram)
               (get-metric histogram)
               histogram)))
    (unless h
      (error "Histogram not found: ~A" histogram))

    (let ((key (serialize-label-values (metric-labels h) label-values)))
      (bt:with-lock-held ((make-lock-for-metric h))
        ;; Increment bucket counts
        (let ((counts (gethash key (histogram-counts h))))
          (unless counts
            ;; Initialize bucket vector (one extra for +Inf)
            (setf counts (make-array (1+ (length (histogram-buckets h)))
                                     :initial-element 0)
                  (gethash key (histogram-counts h)) counts))

          ;; Find appropriate bucket and increment all buckets >= value
          (loop for bucket in (histogram-buckets h)
                for i from 0
                when (<= value bucket)
                  do (incf (aref counts i)))
          ;; Always increment +Inf bucket
          (incf (aref counts (length (histogram-buckets h)))))

        ;; Update sum and total
        (incf (gethash key (histogram-sums h) 0) value)
        (incf (gethash key (histogram-totals h) 0))))))

;;;; ============================================================================
;;;; Label Serialization
;;;; ============================================================================

(defun serialize-label-values (label-names label-values)
  "Serialize label values to a string key for hash table lookup.

   Args:
     label-names - List of label names (keywords)
     label-values - Plist of label values

   Returns:
     String key for hash table.

   Examples:
     (serialize-label-values '(:swarm-id :status)
                             '(:swarm-id \"leaf-a\" :status \"ok\"))
     => \"swarm-id=leaf-a,status=ok\""
  (if (null label-names)
      ""
      (with-output-to-string (s)
        (loop for label-name in label-names
              for first = t then nil
              do (progn
                   (unless first
                     (write-string "," s))
                   (let ((value (getf label-values label-name "")))
                     (format s "~(~A~)=~A"
                             (string-downcase (symbol-name label-name))
                             (escape-label-value value))))))))

(defun escape-label-value (value)
  "Escape label value for Prometheus format.

   Args:
     value - Label value (string, keyword, or number)

   Returns:
     Escaped string."
  (let ((str (cond
               ((stringp value) value)
               ((keywordp value) (string-downcase (symbol-name value)))
               ((numberp value) (princ-to-string value))
               (t (format nil "~A" value)))))
    ;; Escape backslash, newline, and quote
    (with-output-to-string (s)
      (loop for char across str
            do (case char
                 (#\\ (write-string "\\\\" s))
                 (#\Newline (write-string "\\n" s))
                 (#\" (write-string "\\\"" s))
                 (t (write-char char s)))))))

;;;; ============================================================================
;;;; Metric Locks (one per metric for fine-grained concurrency)
;;;; ============================================================================

(defvar *metric-locks* (make-hash-table :test 'eq)
  "Hash table mapping metric objects to their locks.")

(defvar *metric-locks-lock* (bt:make-lock "metric-locks-lock")
  "Lock protecting the metric-locks hash table itself.")

(defun make-lock-for-metric (metric)
  "Get or create a lock for a specific metric.

   Args:
     metric - METRIC instance

   Returns:
     BT:LOCK for this metric."
  (bt:with-lock-held (*metric-locks-lock*)
    (or (gethash metric *metric-locks*)
        (setf (gethash metric *metric-locks*)
              (bt:make-lock (format nil "metric-~A" (metric-name metric)))))))

;;;; ============================================================================
;;;; Prometheus Export
;;;; ============================================================================

(defun export-prometheus-format (&optional (registry *default-registry*) (stream *standard-output*))
  "Export all metrics in Prometheus text exposition format.

   Args:
     registry - Metrics registry to export
     stream - Output stream (default: *standard-output*)

   Returns:
     NIL (writes to stream).

   Examples:
     ;; Export to string
     (with-output-to-string (s)
       (export-prometheus-format *default-registry* s))

     ;; Export to file
     (with-open-file (f \"/tmp/metrics.txt\" :direction :output
                        :if-exists :supersede)
       (export-prometheus-format *default-registry* f))"
  (bt:with-lock-held ((registry-lock registry))
    (maphash (lambda (name metric)
               (declare (ignore name))
               (export-metric-prometheus metric stream))
             (registry-metrics registry))))

(defgeneric export-metric-prometheus (metric stream)
  (:documentation "Export a single metric in Prometheus format."))

(defmethod export-metric-prometheus ((metric counter) stream)
  "Export counter metric in Prometheus format."
  (format stream "# HELP ~A ~A~%" (metric-name metric) (metric-help metric))
  (format stream "# TYPE ~A counter~%" (metric-name metric))

  (bt:with-lock-held ((make-lock-for-metric metric))
    (maphash (lambda (labels value)
               (if (zerop (length labels))
                   (format stream "~A ~A~%" (metric-name metric) value)
                   (format stream "~A{~A} ~A~%"
                           (metric-name metric)
                           labels
                           value)))
             (counter-values metric))))

(defmethod export-metric-prometheus ((metric gauge) stream)
  "Export gauge metric in Prometheus format."
  (format stream "# HELP ~A ~A~%" (metric-name metric) (metric-help metric))
  (format stream "# TYPE ~A gauge~%" (metric-name metric))

  (bt:with-lock-held ((make-lock-for-metric metric))
    (maphash (lambda (labels value)
               (if (zerop (length labels))
                   (format stream "~A ~A~%" (metric-name metric) value)
                   (format stream "~A{~A} ~A~%"
                           (metric-name metric)
                           labels
                           value)))
             (gauge-values metric))))

(defmethod export-metric-prometheus ((metric histogram) stream)
  "Export histogram metric in Prometheus format."
  (format stream "# HELP ~A ~A~%" (metric-name metric) (metric-help metric))
  (format stream "# TYPE ~A histogram~%" (metric-name metric))

  (bt:with-lock-held ((make-lock-for-metric metric))
    (maphash (lambda (labels counts)
               (let ((base-labels (if (zerop (length labels))
                                      ""
                                      (concatenate 'string labels ",")))
                     (sum (gethash labels (histogram-sums metric) 0))
                     (count (gethash labels (histogram-totals metric) 0)))

                 ;; Export bucket counts
                 (loop for bucket in (histogram-buckets metric)
                       for i from 0
                       for bucket-count = (aref counts i)
                       do (format stream "~A_bucket{~Ale=\"~A\"} ~A~%"
                                  (metric-name metric)
                                  base-labels
                                  bucket
                                  bucket-count))

                 ;; Export +Inf bucket
                 (format stream "~A_bucket{~Ale=\"+Inf\"} ~A~%"
                         (metric-name metric)
                         base-labels
                         (aref counts (length (histogram-buckets metric))))

                 ;; Export sum and count
                 (if (zerop (length labels))
                     (progn
                       (format stream "~A_sum ~A~%" (metric-name metric) sum)
                       (format stream "~A_count ~A~%" (metric-name metric) count))
                     (progn
                       (format stream "~A_sum{~A} ~A~%" (metric-name metric) labels sum)
                       (format stream "~A_count{~A} ~A~%" (metric-name metric) labels count)))))
             (histogram-counts metric))))

;;;; ============================================================================
;;;; Convenience Macros
;;;; ============================================================================

(defmacro with-timing ((histogram &key label-values) &body body)
  "Execute BODY and record execution time in histogram.

   Args:
     histogram - HISTOGRAM instance or metric name
     label-values - Plist of label values
     body - Code to time

   Returns:
     Result of BODY.

   Examples:
     (with-timing (\"sw4rm_wal_write_latency_seconds\"
                   :label-values '(:operation \"append\"))
       (wal-append wal :route envelope-data))"
  (let ((start-var (gensym "START-"))
        (result-var (gensym "RESULT-"))
        (histogram-var (gensym "HISTOGRAM-")))
    `(let ((,start-var (get-internal-real-time))
           (,histogram-var ,histogram)
           ,result-var)
       (unwind-protect
            (setf ,result-var (progn ,@body))
         (let ((elapsed (/ (- (get-internal-real-time) ,start-var)
                           internal-time-units-per-second)))
           (observe-histogram ,histogram-var elapsed :label-values ,label-values)))
       ,result-var)))

;;;; ============================================================================
;;;; Standard SW4RM Metrics
;;;; ============================================================================

(defun initialize-standard-metrics (&optional (registry *default-registry*))
  "Initialize standard SW4RM metrics.

   Creates all metrics required for monitoring:
     - WAL metrics
     - Checkpoint metrics
     - gRPC metrics
     - Routing metrics

   Args:
     registry - Registry to initialize in

   Returns:
     NIL."

  ;; WAL metrics
  (make-histogram "sw4rm_wal_write_latency_seconds"
                  :help "WAL write operation latency in seconds"
                  :labels '(:operation)
                  :buckets '(0.0001 0.0005 0.001 0.005 0.01 0.05 0.1 0.5 1.0)
                  :registry registry)

  (make-histogram "sw4rm_wal_replay_latency_seconds"
                  :help "WAL replay operation latency in seconds"
                  :labels '(:operation)
                  :buckets '(0.001 0.01 0.1 1.0 10.0 60.0)
                  :registry registry)

  (make-counter "sw4rm_wal_entries_total"
                :help "Total number of WAL entries written"
                :labels '(:operation)
                :registry registry)

  (make-gauge "sw4rm_wal_size_bytes"
              :help "Current WAL file size in bytes"
              :registry registry)

  ;; Checkpoint metrics
  (make-histogram "sw4rm_checkpoint_duration_seconds"
                  :help "Checkpoint operation duration in seconds"
                  :labels '(:type)
                  :buckets '(0.1 0.5 1.0 5.0 10.0 30.0 60.0)
                  :registry registry)

  (make-gauge "sw4rm_checkpoint_lag_seconds"
              :help "Time since last successful checkpoint"
              :registry registry)

  (make-counter "sw4rm_checkpoint_total"
                :help "Total number of checkpoints taken"
                :labels '(:status)
                :registry registry)

  ;; gRPC metrics
  (make-counter "sw4rm_grpc_requests_total"
                :help "Total gRPC requests"
                :labels '(:swarm-id :method :status)
                :registry registry)

  (make-histogram "sw4rm_grpc_request_latency_seconds"
                  :help "gRPC request latency in seconds"
                  :labels '(:swarm-id :method)
                  :buckets '(0.001 0.005 0.01 0.05 0.1 0.5 1.0 5.0)
                  :registry registry)

  (make-gauge "sw4rm_grpc_connections"
              :help "Current number of active gRPC connections"
              :labels '(:swarm-id :state)
              :registry registry)

  (make-counter "sw4rm_grpc_errors_total"
                :help "Total gRPC errors"
                :labels '(:swarm-id :error-type)
                :registry registry)

  ;; Routing metrics
  (make-counter "sw4rm_messages_routed_total"
                :help "Total messages routed"
                :labels '(:source-swarm :target-swarm :decision)
                :registry registry)

  (make-histogram "sw4rm_routing_latency_seconds"
                  :help "Message routing decision latency"
                  :labels '(:decision)
                  :buckets '(0.00001 0.0001 0.001 0.01 0.1)
                  :registry registry)

  (make-gauge "sw4rm_routing_table_size"
              :help "Number of routes in routing table"
              :labels '(:node-id)
              :registry registry)

  ;; Tree metrics
  (make-gauge "sw4rm_tree_nodes"
              :help "Number of nodes in orchestrator tree"
              :labels '(:type)
              :registry registry)

  (make-gauge "sw4rm_tree_depth"
              :help "Maximum depth of orchestrator tree"
              :registry registry)

  nil)

;;;; End of file
