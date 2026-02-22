;;;; activity.lisp - Activity Service client for SW4RM
;;;;
;;;; Manages activity artifact logging and retrieval for negotiation sessions.

(in-package :sw4rm-sdk)

;;;; Client Class

(defclass activity-client (base-client)
  ()
  (:documentation "Client for the SW4RM Activity Service.

The activity service provides:
- Artifact logging for negotiation sessions
- Artifact retrieval and listing
- Activity timeline tracking

Artifacts represent versioned outputs from negotiation rounds, including
code, documents, designs, and other deliverables. The activity service
maintains the historical record of these artifacts for audit and replay."))

;;;; RPC Methods

(defgeneric register-activity (client artifact)
  (:documentation "Append an artifact to the activity log.

Records a new artifact version associated with a negotiation session.
Artifacts are immutable once logged.

Args:
  client: The activity-client instance.
  artifact: Artifact plist with:
    :negotiation-id (string) - Associated negotiation session
    :kind (string) - Artifact kind (e.g., \"code\", \"document\", \"design\")
    :version (string) - Artifact version (e.g., \"v1\", \"round-3\")
    :content-type (string) - MIME type of content
    :content (bytes) - Artifact content
    :created-at (timestamp) - Creation timestamp

Returns:
  Registration response plist with:
    :artifact-id (string) - Assigned artifact identifier
    :success (boolean) - Whether registration succeeded

Signals:
  RPC-ERROR: If artifact registration fails.

Example:
  (register-activity client
                     (list :negotiation-id \"neg-123\"
                           :kind \"code\"
                           :version \"round-2\"
                           :content-type \"text/x-common-lisp\"
                           :content (babel:string-to-octets \"(defun foo () 42)\")
                           :created-at \"2026-02-11T10:30:00Z\"))"))

(defmethod register-activity ((client activity-client) artifact)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((request-bytes (encode-append-artifact-request artifact))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.activity.ActivityService/AppendArtifact"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-append-artifact-response response-bytes)))))

(defgeneric deregister-activity (client artifact-id)
  (:documentation "Remove an artifact from the activity log.

Deletes an artifact record. This is typically used for cleanup or
administrative purposes, as artifacts are generally immutable.

Args:
  client: The activity-client instance.
  artifact-id: Unique identifier of the artifact to remove.

Returns:
  Deregistration response plist with :success boolean.

Signals:
  RPC-ERROR: If artifact not found or deregistration fails.

Example:
  (deregister-activity client \"artifact-456\")"))

(defmethod deregister-activity ((client activity-client) artifact-id)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((request-bytes (encode-deregister-activity-request artifact-id))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.activity.ActivityService/RemoveArtifact"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-deregister-activity-response response-bytes)))))

(defgeneric list-activities (client negotiation-id &optional kind)
  (:documentation "List artifacts for a negotiation session.

Retrieves all artifacts associated with a negotiation, optionally
filtered by artifact kind.

Args:
  client: The activity-client instance.
  negotiation-id: Negotiation session identifier.
  kind: Optional artifact kind filter (e.g., \"code\", \"document\").

Returns:
  List of artifact plists, each with:
    :artifact-id (string) - Artifact identifier
    :negotiation-id (string) - Associated negotiation
    :kind (string) - Artifact kind
    :version (string) - Artifact version
    :content-type (string) - MIME type
    :created-at (timestamp) - Creation time
    :content (bytes) - Artifact content

Signals:
  RPC-ERROR: If listing fails.

Example:
  ;; List all artifacts for a negotiation
  (list-activities client \"neg-123\")

  ;; List only code artifacts
  (list-activities client \"neg-123\" \"code\")"))

(defmethod list-activities ((client activity-client) negotiation-id &optional kind)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((request-bytes (encode-list-artifacts-request negotiation-id kind))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.activity.ActivityService/ListArtifacts"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-list-artifacts-response response-bytes)))))

(defgeneric get-artifact (client artifact-id)
  (:documentation "Retrieve a specific artifact by ID.

Fetches the full artifact content and metadata.

Args:
  client: The activity-client instance.
  artifact-id: Unique identifier of the artifact.

Returns:
  Artifact plist with full content and metadata, or NIL if not found.

Signals:
  RPC-ERROR: If retrieval fails.

Example:
  (get-artifact client \"artifact-456\")
  => (:artifact-id \"artifact-456\"
      :negotiation-id \"neg-123\"
      :kind \"code\"
      :version \"round-2\"
      :content-type \"text/x-common-lisp\"
      :content #(...))"))

(defmethod get-artifact ((client activity-client) artifact-id)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((request-bytes (encode-get-artifact-request artifact-id))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.activity.ActivityService/GetArtifact"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-get-artifact-response response-bytes)))))
