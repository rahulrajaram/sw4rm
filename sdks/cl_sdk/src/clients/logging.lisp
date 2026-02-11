;;;; logging.lisp - Logging Service client for SW4RM
;;;;
;;;; Provides centralized log ingestion and querying for agent activities.

(in-package :sw4rm)

;;;; Client Class

(defclass logging-client (base-client)
  ()
  (:documentation "Client for the SW4RM Logging Service.

The logging service provides:
- Centralized log ingestion for agent activities
- Structured logging with correlation IDs
- Log querying and filtering
- Distributed tracing support

All agents should send their log events to the centralized logging
service for consistent monitoring, debugging, and audit trails.

Log events are structured with correlation IDs to trace execution
across distributed agent interactions."))

;;;; RPC Methods

(defgeneric log-event (client event)
  (:documentation "Ingest a log event into the logging service.

Sends a structured log event to the centralized logging service for
storage and indexing.

Args:
  client: The logging-client instance.
  event: Log event plist with:
    :timestamp (string) - ISO 8601 timestamp
    :level (keyword) - Log level (:debug, :info, :warning, :error, :critical)
    :message (string) - Log message
    :correlation-id (string, optional) - Correlation/trace ID
    :agent-id (string, optional) - Agent identifier
    :metadata (alist, optional) - Additional key-value metadata
    :tags (list of strings, optional) - Searchable tags

Returns:
  Ingestion response plist with:
    :ingested (boolean) - Whether event was accepted
    :event-id (string) - Assigned event identifier

Signals:
  RPC-ERROR: If ingestion fails.

Example:
  (log-event client
             (list :timestamp \"2026-02-11T10:30:00Z\"
                   :level :info
                   :message \"Task completed successfully\"
                   :correlation-id \"wf-123\"
                   :agent-id \"agent-1\"
                   :metadata '((:task-id . \"task-456\")
                               (:duration-ms . 1234))
                   :tags '(\"task\" \"completion\")))"))

(defmethod log-event ((client logging-client) event)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC LoggingService.Ingest
      (error 'rpc-error
             :message "LogEvent not implemented - requires gRPC integration"
             :code "UNIMPLEMENTED"))))

(defgeneric query-logs (client &key correlation-id agent-id level start-time end-time
                                    tags limit)
  (:documentation "Query logs from the logging service.

Retrieves log events matching the specified filter criteria. Supports
filtering by correlation ID, agent, level, time range, and tags.

Args:
  client: The logging-client instance.
  correlation-id: Filter by correlation/trace ID (optional).
  agent-id: Filter by agent identifier (optional).
  level: Filter by minimum log level (optional, keyword).
  start-time: Filter by start timestamp (optional, ISO 8601 string).
  end-time: Filter by end timestamp (optional, ISO 8601 string).
  tags: Filter by tags (optional, list of strings).
  limit: Maximum number of results (optional, default: 100).

Returns:
  List of log event plists matching the criteria.

Signals:
  RPC-ERROR: If query fails.

Example:
  ;; Get all logs for a workflow
  (query-logs client :correlation-id \"wf-123\" :limit 1000)

  ;; Get error logs from a specific agent
  (query-logs client :agent-id \"agent-1\" :level :error)

  ;; Get logs in a time range with specific tags
  (query-logs client
              :start-time \"2026-02-11T10:00:00Z\"
              :end-time \"2026-02-11T11:00:00Z\"
              :tags '(\"task\" \"completion\")
              :limit 50)"))

(defmethod query-logs ((client logging-client) &key correlation-id agent-id level
                                                    start-time end-time tags
                                                    (limit 100))
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC LoggingService.Query
      (error 'rpc-error
             :message "QueryLogs not implemented - requires gRPC integration"
             :code "UNIMPLEMENTED"))))

;;;; Convenience Logging Methods

(defgeneric log-debug (client message &key correlation-id agent-id metadata)
  (:documentation "Log a debug-level event.

Args:
  client: The logging-client instance.
  message: Log message string.
  correlation-id: Optional correlation/trace ID.
  agent-id: Optional agent identifier.
  metadata: Optional metadata alist.

Returns:
  Ingestion response plist."))

(defmethod log-debug ((client logging-client) message
                      &key correlation-id agent-id metadata)
  (log-event client
             (list :timestamp (format-iso8601-timestamp)
                   :level :debug
                   :message message
                   :correlation-id correlation-id
                   :agent-id agent-id
                   :metadata metadata)))

(defgeneric log-info (client message &key correlation-id agent-id metadata)
  (:documentation "Log an info-level event."))

(defmethod log-info ((client logging-client) message
                     &key correlation-id agent-id metadata)
  (log-event client
             (list :timestamp (format-iso8601-timestamp)
                   :level :info
                   :message message
                   :correlation-id correlation-id
                   :agent-id agent-id
                   :metadata metadata)))

(defgeneric log-warning (client message &key correlation-id agent-id metadata)
  (:documentation "Log a warning-level event."))

(defmethod log-warning ((client logging-client) message
                        &key correlation-id agent-id metadata)
  (log-event client
             (list :timestamp (format-iso8601-timestamp)
                   :level :warning
                   :message message
                   :correlation-id correlation-id
                   :agent-id agent-id
                   :metadata metadata)))

(defgeneric log-error (client message &key correlation-id agent-id metadata)
  (:documentation "Log an error-level event."))

(defmethod log-error ((client logging-client) message
                      &key correlation-id agent-id metadata)
  (log-event client
             (list :timestamp (format-iso8601-timestamp)
                   :level :error
                   :message message
                   :correlation-id correlation-id
                   :agent-id agent-id
                   :metadata metadata)))

(defgeneric log-critical (client message &key correlation-id agent-id metadata)
  (:documentation "Log a critical-level event."))

(defmethod log-critical ((client logging-client) message
                         &key correlation-id agent-id metadata)
  (log-event client
             (list :timestamp (format-iso8601-timestamp)
                   :level :critical
                   :message message
                   :correlation-id correlation-id
                   :agent-id agent-id
                   :metadata metadata)))

;;;; Utility Functions

(defun format-iso8601-timestamp ()
  "Format current time as ISO 8601 timestamp string.

Returns:
  ISO 8601 formatted timestamp string (e.g., \"2026-02-11T10:30:00Z\")."
  (multiple-value-bind (sec min hour day month year)
      (get-decoded-time)
    (format nil "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0DZ"
            year month day hour min sec)))
