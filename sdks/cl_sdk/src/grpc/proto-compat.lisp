;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; SW4RM Orchestrator - Protobuf Compatibility Layer
;;;;
;;;; This module provides a compatibility layer for protobuf message types,
;;;; enabling interaction with Python sw4rm instances via gRPC.
;;;;
;;;; This is designed to be swappable with actual generated protobuf code:
;;;;   - Define proto messages as defstructs (with conversion functions)
;;;;   - Implement serialization to/from JSON (acts as wire format)
;;;;   - Provide conversion functions for envelope/proto round-trips
;;;;
;;;; Proto messages defined (per cross-swarm.proto):
;;;;   - CROSS-SWARM-ENVELOPE: Main message carrier
;;;;   - LEAF-REGISTRATION: Register Python leaf with orchestrator
;;;;   - HEARTBEAT: Health check from Python leaf
;;;;   - ROUTING-RESULT: Result of routing computation
;;;;
;;;; Wire format:
;;;;   - Primary: JSON (compatible with Python json module)
;;;;   - Backup: Binary (using cl-store or similar)
;;;;   - Internal: Lisp structures for efficiency
;;;;
;;;; Version: 0.6.0
;;;; License: Apache 2.0
;;;;
;;;; Spec References:
;;;;   - Part 4.1: Proto definition (lines 488-566 in COMMON_LISP_PLAN.md)
;;;;   - Part 4.2: gRPC client (lines 609-624 in COMMON_LISP_PLAN.md)

(in-package :sw4rm-orchestrator.grpc)

;;;; ============================================================================
;;;; Proto Message Type Definitions (as Lisp Structs)
;;;; ============================================================================
;;;;
;;;; These defstructs mirror the protobuf message definitions from cross-swarm.proto.
;;;; They serve as intermediate representations between Lisp and JSON/gRPC.

(defstruct cross-swarm-envelope-proto
  "Proto representation of CrossSwarmEnvelope message.

   Maps directly to:
     message CrossSwarmEnvelope {
       string id = 1;
       string correlation_id = 2;
       string idempotency_token = 3;
       string source_swarm = 4;
       string target_swarm = 5;
       string sender = 6;
       string recipient = 7;
       bytes payload = 8;
       repeated string path = 9;
       int32 hop_count = 10;
       int32 max_hops = 11;
       int64 created_at = 12;
       int64 deadline = 13;
     }

   Fields:
     id - Unique message identifier (required)
     correlation-id - Workflow identifier (optional)
     idempotency-token - Deduplication token (optional)
     source-swarm - Originating swarm (optional)
     target-swarm - Destination swarm (optional)
     sender - Sending agent (optional)
     recipient - Receiving agent (optional)
     payload - Serialized message data (bytes, typically JSON)
     path - Route taken (list of strings)
     hop-count - Current hop number (int32)
     max-hops - Maximum allowed hops (int32)
     created-at - Creation timestamp in Unix epoch (int64)
     deadline - Absolute deadline in Unix epoch (int64, optional)"
  (id nil :type (or null string))
  (correlation-id nil :type (or null string))
  (idempotency-token nil :type (or null string))
  (source-swarm nil :type (or null string))
  (target-swarm nil :type (or null string))
  (sender nil :type (or null string))
  (recipient nil :type (or null string))
  (payload nil :type (or null (simple-array (unsigned-byte 8))))
  (path nil :type list)
  (hop-count 0 :type (integer 0 2147483647))
  (max-hops 10 :type (integer 0 2147483647))
  (created-at 0 :type (integer 0 9223372036854775807))
  (deadline nil :type (or null (integer 0 9223372036854775807))))

(defstruct leaf-registration-proto
  "Proto representation of LeafRegistration message.

   Maps directly to:
     message LeafRegistration {
       string swarm_id = 1;
       string host = 2;
       int32 port = 3;
       repeated string capabilities = 4;
     }

   Fields:
     swarm-id - Unique identifier for the leaf swarm (required)
     host - Hostname or IP address of the leaf (required)
     port - gRPC port number of the leaf (required)
     capabilities - List of advertised capabilities (optional)"
  (swarm-id nil :type (or null string))
  (host nil :type (or null string))
  (port 50051 :type (integer 1 65535))
  (capabilities nil :type list))

(defstruct heartbeat-proto
  "Proto representation of Heartbeat message.

   Maps directly to:
     message Heartbeat {
       string swarm_id = 1;
       int64 timestamp = 2;
       map<string, string> metrics = 3;
     }

   Fields:
     swarm-id - Identifier of the sending leaf (required)
     timestamp - Heartbeat timestamp in Unix epoch (required)
     metrics - Key-value metrics (hash-table or plist)"
  (swarm-id nil :type (or null string))
  (timestamp 0 :type (integer 0 9223372036854775807))
  (metrics nil :type (or null hash-table)))

(defstruct routing-result-proto
  "Proto representation of RoutingResult message.

   Maps directly to:
     message RoutingResult {
       enum Decision {
         LOCAL = 0;
         CHILD = 1;
         PARENT = 2;
         BROADCAST = 3;
         REJECT = 4;
       }
       Decision decision = 1;
       string target = 2;
       string reason = 3;
     }

   Fields:
     decision - Routing decision (:LOCAL, :CHILD, :PARENT, :BROADCAST, :REJECT)
     target - Target swarm ID (optional)
     reason - Explanation for decision (optional)"
  (decision :reject :type (member :local :child :parent :broadcast :reject))
  (target nil :type (or null string))
  (reason nil :type (or null string)))

(defstruct registration-response-proto
  "Proto response to leaf registration.

   Fields:
     success - Whether registration succeeded
     message - Response message"
  (success nil :type (or null boolean))
  (message nil :type (or null string)))

(defstruct delivery-ack-proto
  "Proto acknowledgement of envelope delivery.

   Fields:
     envelope-id - ID of delivered envelope
     success - Whether delivery succeeded
     reason - Explanation if failed"
  (envelope-id nil :type (or null string))
  (success nil :type (or null boolean))
  (reason nil :type (or null string)))

;;;; ============================================================================
;;;; Conversion: Lisp Envelope <-> Proto Envelope
;;;; ============================================================================

(defun envelope-to-proto (envelope)
  "Convert a Lisp envelope to a protobuf-compatible structure.

   Args:
     envelope: A CROSS-SWARM-ENVELOPE instance

   Returns:
     A CROSS-SWARM-ENVELOPE-PROTO structure ready for gRPC serialization.

   Notes:
     - Payload is serialized to JSON bytes
     - Timestamps are converted to Unix epoch
     - Optional fields that are nil are preserved as nil
     - The proto structure can be serialized to JSON or binary

   Example:
     (let ((env (make-cross-swarm-envelope
                  :source-swarm \"frontend\"
                  :target-swarm \"backend\"
                  :payload '(:event \"login\"))))
       (let ((proto (envelope-to-proto env)))
         (cross-swarm-envelope-proto-id proto)))
     => \"550e8400-e29b-41d4-a716-446655440000\""
  (let ((payload-json (if (envelope-payload envelope)
                          (serialize-payload (envelope-payload envelope) :json)
                          nil)))
    (make-cross-swarm-envelope-proto
      :id (envelope-id envelope)
      :correlation-id (envelope-correlation-id envelope)
      :idempotency-token (envelope-idempotency-token envelope)
      :source-swarm (envelope-source-swarm envelope)
      :target-swarm (envelope-target-swarm envelope)
      :sender (envelope-sender envelope)
      :recipient (envelope-recipient envelope)
      :payload (if payload-json
                   (string-to-octets payload-json)
                   nil)
      :path (envelope-path envelope)
      :hop-count (envelope-hop-count envelope)
      :max-hops (envelope-max-hops envelope)
      :created-at (universal-to-timestamp (envelope-created-at envelope))
      :deadline (when (envelope-deadline envelope)
                  (universal-to-timestamp (envelope-deadline envelope))))))

(defun proto-to-envelope (proto)
  "Convert a protobuf structure to a Lisp envelope.

   Args:
     proto: A CROSS-SWARM-ENVELOPE-PROTO structure

   Returns:
     A CROSS-SWARM-ENVELOPE instance.

   Notes:
     - Payload bytes are deserialized from JSON
     - Timestamps are converted from Unix epoch to universal-time
     - Missing optional fields become nil
     - The returned envelope is validated

   Raises:
     ERROR if envelope validation fails

   Example:
     (let ((proto (make-cross-swarm-envelope-proto
                    :id \"550e8400-e29b-41d4-a716-446655440000\"
                    :source-swarm \"frontend\")))
       (let ((env (proto-to-envelope proto)))
         (envelope-id env)))
     => \"550e8400-e29b-41d4-a716-446655440000\""
  (let ((payload (if (cross-swarm-envelope-proto-payload proto)
                     (deserialize-payload
                      (octets-to-string
                       (cross-swarm-envelope-proto-payload proto))
                      :json)
                     nil)))
    (let ((env (make-cross-swarm-envelope
                 :correlation-id (cross-swarm-envelope-proto-correlation-id proto)
                 :idempotency-token (cross-swarm-envelope-proto-idempotency-token proto)
                 :source-swarm (cross-swarm-envelope-proto-source-swarm proto)
                 :target-swarm (cross-swarm-envelope-proto-target-swarm proto)
                 :sender (cross-swarm-envelope-proto-sender proto)
                 :recipient (cross-swarm-envelope-proto-recipient proto)
                 :payload payload
                 :path (cross-swarm-envelope-proto-path proto)
                 :hop-count (cross-swarm-envelope-proto-hop-count proto)
                 :max-hops (cross-swarm-envelope-proto-max-hops proto)
                 :created-at (timestamp-to-universal
                              (cross-swarm-envelope-proto-created-at proto))
                 :deadline (when (cross-swarm-envelope-proto-deadline proto)
                             (timestamp-to-universal
                              (cross-swarm-envelope-proto-deadline proto))))))
      ;; Set the ID from the proto
      (setf (slot-value env 'id) (cross-swarm-envelope-proto-id proto))
      (validate-envelope env)
      env)))

;;;; ============================================================================
;;;; Proto Message Constructors
;;;; ============================================================================

(defun make-leaf-registration-proto (&key swarm-id host port capabilities)
  "Create a leaf registration protobuf message.

   Args:
     swarm-id: Unique identifier for the leaf swarm (required)
     host: Hostname or IP address of the leaf (required)
     port: gRPC port number (required)
     capabilities: List of capability keywords (optional)

   Returns:
     A LEAF-REGISTRATION-PROTO structure

   Example:
     (make-leaf-registration-proto
       :swarm-id \"frontend\"
       :host \"10.0.1.5\"
       :port 50051
       :capabilities '(:nlp :vision))
     => #<LEAF-REGISTRATION-PROTO swarm_id: \"frontend\" host: \"10.0.1.5\"
         port: 50051 capabilities: (:NLP :VISION)>"
  (make-leaf-registration-proto
    :swarm-id swarm-id
    :host host
    :port port
    :capabilities capabilities))

(defun make-routing-result-proto (decision &key target reason)
  "Create a routing result protobuf message.

   Args:
     decision: Routing decision keyword (:local, :child, :parent, :broadcast, :reject)
     target: Target swarm ID (optional)
     reason: Explanation for decision (optional)

   Returns:
     A ROUTING-RESULT-PROTO structure

   Example:
     (make-routing-result-proto :child
       :target \"leaf-a\"
       :reason \"Direct child route\")
     => #<ROUTING-RESULT-PROTO decision: :CHILD target: \"leaf-a\"
         reason: \"Direct child route\">"
  (make-routing-result-proto
    :decision decision
    :target target
    :reason reason))

(defun make-heartbeat-proto (swarm-id &key metrics timestamp)
  "Create a heartbeat protobuf message.

   Args:
     swarm-id: Identifier of the sending leaf (required)
     metrics: Hash-table or plist of metrics (optional)
     timestamp: Heartbeat timestamp in Unix epoch (optional, defaults to now)

   Returns:
     A HEARTBEAT-PROTO structure

   Notes:
     If timestamp is not provided, uses current Unix timestamp.
     If metrics is a plist, it's converted to a hash-table.

   Example:
     (make-heartbeat-proto \"leaf-a\"
       :metrics '(\"messages-processed\" \"1000\"
                  \"active-agents\" \"5\")
       :timestamp 1704902400)
     => #<HEARTBEAT-PROTO swarm_id: \"leaf-a\" timestamp: 1704902400
         metrics: #<HASH-TABLE ...>>"
  (let ((ts (or timestamp
                (universal-to-timestamp (get-universal-time))))
        (metrics-ht (if (and metrics (not (hash-table-p metrics)))
                        (plist-to-hash-table metrics)
                        metrics)))
    (make-heartbeat-proto
      :swarm-id swarm-id
      :timestamp ts
      :metrics metrics-ht)))

;;;; ============================================================================
;;;; Proto Message Validation
;;;; ============================================================================

(defun validate-proto-envelope (proto)
  "Validate a protobuf envelope structure.

   Args:
     proto: A CROSS-SWARM-ENVELOPE-PROTO structure

   Returns:
     T if valid, NIL otherwise

   Checks:
     - id is present and non-empty
     - hop-count is non-negative
     - max-hops is positive
     - hop-count <= max-hops
     - deadline (if present) >= created-at

   Example:
     (let ((proto (make-cross-swarm-envelope-proto :id \"abc\")))
       (validate-proto-envelope proto))
     => T"
  (and
    ;; id check
    (cross-swarm-envelope-proto-id proto)
    (> (length (cross-swarm-envelope-proto-id proto)) 0)

    ;; hop count checks
    (>= (cross-swarm-envelope-proto-hop-count proto) 0)
    (> (cross-swarm-envelope-proto-max-hops proto) 0)
    (<= (cross-swarm-envelope-proto-hop-count proto)
        (cross-swarm-envelope-proto-max-hops proto))

    ;; deadline check
    (if (cross-swarm-envelope-proto-deadline proto)
        (>= (cross-swarm-envelope-proto-deadline proto)
            (cross-swarm-envelope-proto-created-at proto))
        t)))

(defun validate-proto-leaf-registration (proto)
  "Validate a leaf registration protobuf message.

   Args:
     proto: A LEAF-REGISTRATION-PROTO structure

   Returns:
     (VALUES valid errors)

   Checks:
     - swarm-id is present and non-empty
     - host is present and non-empty
     - port is in valid range (1-65535)

   Example:
     (validate-proto-leaf-registration
       (make-leaf-registration-proto
         :swarm-id \"leaf-a\"
         :host \"localhost\"
         :port 50051))
     => (VALUES T NIL)"
  (let ((errors nil))
    (unless (and (leaf-registration-proto-swarm-id proto)
                 (> (length (leaf-registration-proto-swarm-id proto)) 0))
      (push "Missing or empty swarm_id" errors))

    (unless (and (leaf-registration-proto-host proto)
                 (> (length (leaf-registration-proto-host proto)) 0))
      (push "Missing or empty host" errors))

    (let ((port (leaf-registration-proto-port proto)))
      (unless (and (integerp port) (<= 1 port 65535))
        (push (format nil "Invalid port: ~A (must be 1-65535)" port) errors)))

    (if errors
        (values nil (nreverse errors))
        (values t nil))))

;;;; ============================================================================
;;;; Field Type Coercion
;;;; ============================================================================

(defun coerce-proto-field (value field-type)
  "Coerce a value to the correct type for a proto field.

   Args:
     value: The value to coerce
     field-type: The target field type (keyword)

   Returns:
     The coerced value, or the original if no coercion needed

   Supports:
     - :string: Coerce to string
     - :int32: Coerce to 32-bit integer
     - :int64: Coerce to 64-bit integer
     - :bytes: Coerce to byte array
     - :bool: Coerce to boolean
     - :list: Ensure value is a list
     - :hash-table: Ensure value is a hash-table

   Example:
     (coerce-proto-field \"42\" :int32)
     => 42

     (coerce-proto-field 42 :string)
     => \"42\""
  (case field-type
    (:string
     (if (stringp value) value (format nil "~A" value)))
    (:int32
     (if (integerp value) value (parse-integer (format nil "~A" value))))
    (:int64
     (if (integerp value) value (parse-integer (format nil "~A" value))))
    (:bytes
     (if (typep value '(simple-array (unsigned-byte 8)))
         value
         (string-to-octets (format nil "~A" value))))
    (:bool
     (and value t))
    (:list
     (if (listp value) value (list value)))
    (:hash-table
     (if (hash-table-p value) value (plist-to-hash-table value)))
    (t value)))

;;;; ============================================================================
;;;; Enum Conversion
;;;; ============================================================================

(defun routing-decision-to-proto (decision)
  "Convert a Lisp routing decision to proto enum value.

   Args:
     decision: Lisp keyword (:local, :child, :parent, :broadcast, :reject)

   Returns:
     Proto enum value (keyword or integer)

   Example:
     (routing-decision-to-proto :child)
     => :CHILD"
  decision)  ; Already a keyword, which maps directly

(defun proto-to-routing-decision (proto-value)
  "Convert a proto enum value to a Lisp routing decision.

   Args:
     proto-value: Proto enum value

   Returns:
     Lisp keyword (:local, :child, :parent, :broadcast, :reject)

   Example:
     (proto-to-routing-decision :CHILD)
     => :CHILD"
  (if (keywordp proto-value)
      proto-value
      (intern (format nil "~:@(~A~)" proto-value) :keyword)))

;;;; ============================================================================
;;;; Wire Format: Serialize/Deserialize Proto Messages
;;;; ============================================================================

(defun proto-to-json (proto)
  "Serialize a proto message to JSON.

   Args:
     proto: A proto message struct

   Returns:
     A JSON string representation

   Notes:
     This is a simple hand-coded serializer. For production, use
     actual protobuf-generated code or a library like cl-json.

   Example:
     (let ((proto (make-cross-swarm-envelope-proto
                    :id \"abc\"
                    :hop-count 1)))
       (proto-to-json proto))
     => \"{\\\"id\\\":\\\"abc\\\",\\\"hop_count\\\":1,...}\""
  (typecase proto
    (cross-swarm-envelope-proto
     (proto-envelope-to-json proto))
    (leaf-registration-proto
     (proto-leaf-registration-to-json proto))
    (heartbeat-proto
     (proto-heartbeat-to-json proto))
    (routing-result-proto
     (proto-routing-result-to-json proto))
    (t
     (error "Unknown proto type: ~A" (type-of proto)))))

(defun proto-envelope-to-json (proto)
  "Serialize a CrossSwarmEnvelope proto to JSON."
  (with-output-to-string (out)
    (write-char #\{ out)
    (let ((first t))
      (unless first (write-char #\, out))
      (format out "\"id\":~A"
              (json-escape-string (cross-swarm-envelope-proto-id proto)))
      (setf first nil)

      (when (cross-swarm-envelope-proto-correlation-id proto)
        (write-char #\, out)
        (format out "\"correlation_id\":~A"
                (json-escape-string
                 (cross-swarm-envelope-proto-correlation-id proto))))

      (when (cross-swarm-envelope-proto-idempotency-token proto)
        (write-char #\, out)
        (format out "\"idempotency_token\":~A"
                (json-escape-string
                 (cross-swarm-envelope-proto-idempotency-token proto))))

      (when (cross-swarm-envelope-proto-source-swarm proto)
        (write-char #\, out)
        (format out "\"source_swarm\":~A"
                (json-escape-string
                 (cross-swarm-envelope-proto-source-swarm proto))))

      (when (cross-swarm-envelope-proto-target-swarm proto)
        (write-char #\, out)
        (format out "\"target_swarm\":~A"
                (json-escape-string
                 (cross-swarm-envelope-proto-target-swarm proto))))

      (when (cross-swarm-envelope-proto-sender proto)
        (write-char #\, out)
        (format out "\"sender\":~A"
                (json-escape-string
                 (cross-swarm-envelope-proto-sender proto))))

      (when (cross-swarm-envelope-proto-recipient proto)
        (write-char #\, out)
        (format out "\"recipient\":~A"
                (json-escape-string
                 (cross-swarm-envelope-proto-recipient proto))))

      (when (cross-swarm-envelope-proto-payload proto)
        (write-char #\, out)
        (format out "\"payload\":~A"
                (json-escape-string
                 (octets-to-string
                  (cross-swarm-envelope-proto-payload proto)))))

      (when (cross-swarm-envelope-proto-path proto)
        (write-char #\, out)
        (format out "\"path\":[~{~A~^,~}]"
                (mapcar #'json-escape-string
                        (cross-swarm-envelope-proto-path proto))))

      (write-char #\, out)
      (format out "\"hop_count\":~D"
              (cross-swarm-envelope-proto-hop-count proto))

      (write-char #\, out)
      (format out "\"max_hops\":~D"
              (cross-swarm-envelope-proto-max-hops proto))

      (write-char #\, out)
      (format out "\"created_at\":~D"
              (cross-swarm-envelope-proto-created-at proto))

      (when (cross-swarm-envelope-proto-deadline proto)
        (write-char #\, out)
        (format out "\"deadline\":~D"
                (cross-swarm-envelope-proto-deadline proto))))

    (write-char #\} out)))

(defun proto-leaf-registration-to-json (proto)
  "Serialize a LeafRegistration proto to JSON."
  (with-output-to-string (out)
    (write-char #\{ out)
    (format out "\"swarm_id\":~A"
            (json-escape-string (leaf-registration-proto-swarm-id proto)))
    (write-char #\, out)
    (format out "\"host\":~A"
            (json-escape-string (leaf-registration-proto-host proto)))
    (write-char #\, out)
    (format out "\"port\":~D" (leaf-registration-proto-port proto))
    (when (leaf-registration-proto-capabilities proto)
      (write-char #\, out)
      (format out "\"capabilities\":[~{~A~^,~}]"
              (mapcar #'json-escape-string
                      (leaf-registration-proto-capabilities proto))))
    (write-char #\} out)))

(defun proto-heartbeat-to-json (proto)
  "Serialize a Heartbeat proto to JSON."
  (with-output-to-string (out)
    (write-char #\{ out)
    (format out "\"swarm_id\":~A"
            (json-escape-string (heartbeat-proto-swarm-id proto)))
    (write-char #\, out)
    (format out "\"timestamp\":~D" (heartbeat-proto-timestamp proto))
    (when (heartbeat-proto-metrics proto)
      (write-char #\, out)
      (write-string "\"metrics\":{" out)
      (let ((first t))
        (maphash (lambda (key value)
                   (unless first (write-char #\, out))
                   (setf first nil)
                   (format out "~A:~A"
                           (json-escape-string (format nil "~A" key))
                           (json-escape-string (format nil "~A" value))))
                 (heartbeat-proto-metrics proto)))
      (write-char #\} out))
    (write-char #\} out)))

(defun proto-routing-result-to-json (proto)
  "Serialize a RoutingResult proto to JSON."
  (with-output-to-string (out)
    (write-char #\{ out)
    (format out "\"decision\":~A"
            (json-escape-string
             (string-downcase (symbol-name (routing-result-proto-decision proto)))))
    (when (routing-result-proto-target proto)
      (write-char #\, out)
      (format out "\"target\":~A"
              (json-escape-string (routing-result-proto-target proto))))
    (when (routing-result-proto-reason proto)
      (write-char #\, out)
      (format out "\"reason\":~A"
              (json-escape-string (routing-result-proto-reason proto))))
    (write-char #\} out)))

(defun proto-from-json (json-string proto-type)
  "Deserialize a proto message from JSON.

   Args:
     json-string: JSON string to deserialize
     proto-type: Type of proto message to create (:envelope, :registration, etc)

   Returns:
     The deserialized proto message struct

   Raises:
     ERROR if JSON is malformed or incompatible with proto-type

   Example:
     (proto-from-json
       \"{\\\"id\\\":\\\"abc\\\",\\\"hop_count\\\":0}\"
       :envelope)
     => #<CROSS-SWARM-ENVELOPE-PROTO id: \"abc\" hop_count: 0>"
  (let ((parsed (parse-json json-string)))
    (unless parsed
      (error "Failed to parse JSON: ~S" json-string))
    (ecase proto-type
      (:envelope (json-to-proto-envelope parsed))
      (:registration (json-to-proto-leaf-registration parsed))
      (:heartbeat (json-to-proto-heartbeat parsed))
      (:routing-result (json-to-proto-routing-result parsed)))))

(defun json-to-proto-envelope (json-obj)
  "Convert parsed JSON object to CrossSwarmEnvelope proto."
  (make-cross-swarm-envelope-proto
    :id (gethash "id" json-obj)
    :correlation-id (gethash "correlation_id" json-obj)
    :idempotency-token (gethash "idempotency_token" json-obj)
    :source-swarm (gethash "source_swarm" json-obj)
    :target-swarm (gethash "target_swarm" json-obj)
    :sender (gethash "sender" json-obj)
    :recipient (gethash "recipient" json-obj)
    :payload (when (gethash "payload" json-obj)
               (string-to-octets (gethash "payload" json-obj)))
    :path (gethash "path" json-obj)
    :hop-count (or (gethash "hop_count" json-obj) 0)
    :max-hops (or (gethash "max_hops" json-obj) 10)
    :created-at (or (gethash "created_at" json-obj) 0)
    :deadline (gethash "deadline" json-obj)))

(defun json-to-proto-leaf-registration (json-obj)
  "Convert parsed JSON object to LeafRegistration proto."
  (make-leaf-registration-proto
    :swarm-id (gethash "swarm_id" json-obj)
    :host (gethash "host" json-obj)
    :port (or (gethash "port" json-obj) 50051)
    :capabilities (gethash "capabilities" json-obj)))

(defun json-to-proto-heartbeat (json-obj)
  "Convert parsed JSON object to Heartbeat proto."
  (make-heartbeat-proto
    :swarm-id (gethash "swarm_id" json-obj)
    :timestamp (or (gethash "timestamp" json-obj) 0)
    :metrics (gethash "metrics" json-obj)))

(defun json-to-proto-routing-result (json-obj)
  "Convert parsed JSON object to RoutingResult proto."
  (make-routing-result-proto
    (string-to-keyword (gethash "decision" json-obj))
    :target (gethash "target" json-obj)
    :reason (gethash "reason" json-obj)))

;;;; ============================================================================
;;;; Helper Functions
;;;; ============================================================================

(defun plist-to-hash-table (plist)
  "Convert a plist to a hash-table.

   Args:
     plist: A property list (:key1 value1 :key2 value2 ...)

   Returns:
     A hash-table with keyword keys"
  (let ((ht (make-hash-table :test 'equal)))
    (loop for (key val) on plist by #'cddr
          do (setf (gethash (string-downcase (symbol-name key)) ht) val))
    ht))

(defun hash-table-to-plist (ht)
  "Convert a hash-table to a plist.

   Args:
     ht: A hash-table with string keys

   Returns:
     A property list with keyword keys"
  (let ((plist nil))
    (maphash (lambda (key value)
               (setf plist (list* (string-to-keyword key) value plist)))
             ht)
    plist))

;;;; ============================================================================
;;;; Import required serialization functions from envelope package
;;;; ============================================================================
;;;;
;;;; These need to be available for proto-to-envelope and envelope-to-proto
;;;; conversions. They're defined in the envelope/serialization.lisp module.

;; Forward declarations - these are imported from envelope package
(defun serialize-payload (payload format))
(defun deserialize-payload (serialized format))
(defun timestamp-to-universal (unix-timestamp))
(defun universal-to-timestamp (universal-time))
(defun string-to-octets (string))
(defun octets-to-string (octets))
(defun json-escape-string (string))
(defun parse-json (json-string))

;;;; End of file
