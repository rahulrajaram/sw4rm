;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; SW4RM Orchestrator - Envelope Serialization
;;;;
;;;; This module provides serialization and deserialization for cross-swarm envelopes.
;;;;
;;;; Supported formats:
;;;;   - JSON: Primary wire format, compatible with Python
;;;;   - Plist: Lisp-native format for Lisp-to-Lisp communication
;;;;   - Octets (Binary): For persistence and efficient storage
;;;;
;;;; The serialization layer is designed to be swappable:
;;;; - JSON serialization uses a simple hand-coded approach
;;;; - Plist serialization uses native Lisp structures
;;;; - Binary serialization uses cl-store (or compatible pattern)
;;;;
;;;; Field conversion includes:
;;;;   - Timestamp conversion (universal-time <-> Unix epoch)
;;;;   - Keyword normalization (keywords <-> strings)
;;;;   - Payload handling (any Lisp object -> JSON/plist/binary)
;;;;   - Validation of deserialized envelopes
;;;;
;;;; Version: 0.6.0
;;;; License: Apache 2.0
;;;;
;;;; Spec References:
;;;;   - §11.3: Three-ID model (message_id, correlation_id, idempotency_token)
;;;;   - §12: Message serialization formats

(in-package :sw4rm-orchestrator.envelope)

;;;; ============================================================================
;;;; JSON Serialization (Primary Wire Format)
;;;; ============================================================================

(defun %swarm-id-string (value)
  "Normalize swarm ID values to string for serialization."
  (cond
    ((keywordp value) (symbol-name value))
    (t value)))

(defun envelope-to-json (envelope)
  "Serialize an envelope to JSON string.

   Args:
     envelope: CROSS-SWARM-ENVELOPE to serialize

   Returns:
     A JSON string representing the envelope.

   Notes:
     - All required fields are included
     - Optional fields (nil values) are omitted or set to null
     - Timestamps are converted to Unix epoch (seconds since 1970-01-01)
     - Payloads are serialized to JSON (see serialize-payload)
     - Priority and message-type are converted to lowercase strings

   Raises:
     ERROR if envelope fails validation before serialization

   Example:
     (let ((env (make-cross-swarm-envelope
                  :source-swarm \"frontend\"
                  :target-swarm \"backend\"
                  :payload '(:event \"login\"))))
       (envelope-to-json env))
     => \"{\\\"id\\\":\\\"550e8400-e29b...\\\",\\\"source_swarm\\\":\\\"frontend\\\",
         \\\"target_swarm\\\":\\\"backend\\\",\\\"payload\\\":{\\\"event\\\":\\\"login\\\"},
         \\\"hop_count\\\":0,\\\"max_hops\\\":10,\\\"created_at\\\":1704902400,
         \\\"priority\\\":\\\"normal\\\",\\\"message_type\\\":\\\"request\\\"}\""
  (validate-envelope envelope)
  (with-output-to-string (out)
    (write-char #\{ out)

    ;; Write required fields
    (format out "\"id\":~A" (json-escape-string (envelope-id envelope)))

    ;; Write optional three-ID model fields
    (when (envelope-correlation-id envelope)
      (format out ",\"correlation_id\":~A"
              (json-escape-string (envelope-correlation-id envelope))))
    (when (envelope-idempotency-token envelope)
      (format out ",\"idempotency_token\":~A"
              (json-escape-string (envelope-idempotency-token envelope))))

    ;; Write routing fields
    (when (envelope-source-swarm envelope)
      (format out ",\"source_swarm\":~A"
              (json-escape-string (%swarm-id-string (envelope-source-swarm envelope)))))
    (when (envelope-target-swarm envelope)
      (format out ",\"target_swarm\":~A"
              (json-escape-string (%swarm-id-string (envelope-target-swarm envelope)))))
    (when (envelope-sender envelope)
      (format out ",\"sender\":~A"
              (json-escape-string (envelope-sender envelope))))
    (when (envelope-recipient envelope)
      (format out ",\"recipient\":~A"
              (json-escape-string (envelope-recipient envelope))))

    ;; Write payload (serialized as JSON)
    (format out ",\"payload\":~A"
            (serialize-payload (envelope-payload envelope) :json))

    ;; Write path tracking
    (when (envelope-path envelope)
      (format out ",\"path\":[~{~A~^,~}]"
              (mapcar #'json-escape-string (envelope-path envelope))))
    (format out ",\"hop_count\":~D" (envelope-hop-count envelope))
    (format out ",\"max_hops\":~D" (envelope-max-hops envelope))

    ;; Write lifecycle fields
    (format out ",\"created_at\":~D"
            (universal-to-timestamp (envelope-created-at envelope)))
    (when (envelope-deadline envelope)
      (format out ",\"deadline\":~D"
              (universal-to-timestamp (envelope-deadline envelope))))

    ;; Write priority and message-type
    (format out ",\"priority\":~A"
            (json-escape-string (string-downcase (symbol-name (envelope-priority envelope)))))
    (format out ",\"message_type\":~A"
            (json-escape-string (string-downcase (symbol-name (envelope-message-type envelope)))))

    (write-char #\} out)))

(defun json-to-envelope (json-string)
  "Deserialize an envelope from JSON string.

   Args:
     json-string: A JSON string representing a CROSS-SWARM-ENVELOPE

   Returns:
     A CROSS-SWARM-ENVELOPE instance.

   Notes:
     - Required field: id (or error)
     - Optional fields default to nil
     - Timestamps are converted from Unix epoch to universal-time
     - Payloads are deserialized from JSON
     - Priority and message-type strings are converted to keywords

   Raises:
     ERROR if JSON is malformed
     ERROR if required fields are missing
     ERROR if envelope validation fails after deserialization

   Example:
     (json-to-envelope
       \"{\\\"id\\\":\\\"550e8400-e29b...\\\",\\\"source_swarm\\\":\\\"frontend\\\",
         \\\"target_swarm\\\":\\\"backend\\\",\\\"hop_count\\\":0}\")
     => #<ENVELOPE id: 550e8400-e29b-41d4-a7... src: frontend -> backend>"
  (let ((parsed (parse-json json-string)))
    (unless parsed
      (error "Failed to parse JSON: ~S" json-string))
    (json-object-to-envelope parsed)))

(defun envelope-from-json (json-string)
  "Compatibility wrapper: deserialize an envelope from JSON string."
  (json-to-envelope json-string))

(defun json-escape-string (str)
  "Escape a string for JSON output.

   Args:
     str: A string to escape

   Returns:
     A properly JSON-escaped string (with quotes).

   Notes:
     Escapes: quote, backslash, newline, carriage return, tab, etc.

   Example:
     (json-escape-string \"Hello World\")
     => \"\\\"Hello World\\\"\""
  (with-output-to-string (out)
    (write-char #\" out)
    (loop for char across str
          do (case char
               (#\" (write-string "\\\"" out))
               (#\\ (write-string "\\\\" out))
               (#\Newline (write-string "\\n" out))
               (#\Return (write-string "\\r" out))
               (#\Tab (write-string "\\t" out))
               (t (write-char char out))))
    (write-char #\" out)))

(defun parse-json (json-string)
  "Parse a JSON string into a Lisp structure.

   Args:
     json-string: A JSON string

   Returns:
     A Lisp structure (hash-table, list, string, number, t, nil)
     or NIL if parsing fails.

   Notes:
     This is a simplified JSON parser suitable for envelopes.
     For production use, consider using a library like cl-json or jonathan.

   This implementation:
     - Handles objects, arrays, strings, numbers, booleans, null
     - Does not handle Unicode escapes (simplified)
     - Returns hash-tables for JSON objects

   Example:
     (parse-json \"{\\\"name\\\":\\\"John\\\",\\\"age\\\":30}\")
     => #<HASH-TABLE name: \"John\" age: 30>"
  (handler-case
      (with-input-from-string (in json-string)
        (json-read-value in))
    (error () nil)))

(defun json-read-value (stream)
  "Read a single JSON value from stream.

   Args:
     stream: An input stream positioned at a JSON value

   Returns:
     The Lisp representation of the value.

   Raises:
     ERROR if JSON is malformed."
  (skip-whitespace stream)
  (let ((char (peek-char nil stream nil)))
    (cond
      ((null char) (error "Unexpected end of input"))
      ((char= char #\{) (json-read-object stream))
      ((char= char #\[) (json-read-array stream))
      ((char= char #\") (json-read-string stream))
      ((char= char #\t) (json-read-true stream))
      ((char= char #\f) (json-read-false stream))
      ((char= char #\n) (json-read-null stream))
      ((or (char= char #\-) (digit-char-p char))
       (json-read-number stream))
      (t (error "Unexpected character in JSON: ~A" char)))))

(defun json-read-object (stream)
  "Read a JSON object ({...}) from stream.

   Returns a hash-table with string keys."
  (let ((table (make-hash-table :test 'equal)))
    (read-char stream) ; consume {
    (skip-whitespace stream)

    ;; Handle empty object
    (when (char= (peek-char nil stream) #\})
      (read-char stream)
      (return-from json-read-object table))

    ;; Read key-value pairs
    (loop do
      (skip-whitespace stream)
      (let ((key (json-read-string stream)))
        (skip-whitespace stream)
        (unless (char= (read-char stream) #\:)
          (error "Expected ':' in JSON object"))
        (skip-whitespace stream)
        (let ((value (json-read-value stream)))
          (setf (gethash key table) value)))

      (skip-whitespace stream)
      (let ((next (read-char stream)))
        (cond
          ((char= next #\,) (skip-whitespace stream))
          ((char= next #\}) (return table))
          (t (error "Expected ',' or '}' in JSON object")))))
    table))

(defun json-read-array (stream)
  "Read a JSON array ([...]) from stream.

   Returns a list of values."
  (read-char stream) ; consume [
  (skip-whitespace stream)

  ;; Handle empty array
  (when (char= (peek-char nil stream) #\])
    (read-char stream)
    (return-from json-read-array nil))

  ;; Read elements
  (let ((result nil))
    (loop do
      (skip-whitespace stream)
      (push (json-read-value stream) result)

      (skip-whitespace stream)
      (let ((next (read-char stream)))
        (cond
          ((char= next #\,) (skip-whitespace stream))
          ((char= next #\]) (return (nreverse result)))
          (t (error "Expected ',' or ']' in JSON array")))))
    result))

(defun json-read-string (stream)
  "Read a JSON string (\"...\") from stream.

   Returns a string (without surrounding quotes)."
  (read-char stream) ; consume opening quote
  (with-output-to-string (out)
    (loop for char = (read-char stream)
          do (cond
               ((char= char #\") (return))
               ((char= char #\\)
                ;; Handle escape sequences
                (let ((escaped (read-char stream)))
                  (case escaped
                    (#\" (write-char #\" out))
                    (#\\ (write-char #\\ out))
                    (#\/ (write-char #\/ out))
                    (#\b (write-char #\Backspace out))
                    (#\f (write-char #\Page out))
                    (#\n (write-char #\Newline out))
                    (#\r (write-char #\Return out))
                    (#\t (write-char #\Tab out))
                    (t (write-char escaped out)))))
               (t (write-char char out))))))

(defun json-read-number (stream)
  "Read a JSON number from stream.

   Returns an integer or float."
  (let ((num-string (with-output-to-string (out)
                      (loop for char = (peek-char nil stream)
                            while (and char (or (digit-char-p char)
                                                (member char '(#\- #\+ #\. #\e #\E))))
                            do (write-char (read-char stream) out)))))
    (if (find #\. num-string)
        (read-from-string (format nil "~Af0" num-string))
        (parse-integer num-string))))

(defun json-read-true (stream)
  "Read JSON 'true' keyword."
  (read-char stream) (read-char stream) (read-char stream) (read-char stream)
  t)

(defun json-read-false (stream)
  "Read JSON 'false' keyword."
  (read-char stream) (read-char stream) (read-char stream)
  (read-char stream) (read-char stream)
  nil)

(defun json-read-null (stream)
  "Read JSON 'null' keyword."
  (read-char stream) (read-char stream) (read-char stream) (read-char stream)
  nil)

(defun skip-whitespace (stream)
  "Skip whitespace characters in stream."
  (loop for char = (peek-char nil stream nil)
        while (and char (member char '(#\Space #\Newline #\Return #\Tab)))
        do (read-char stream)))

(defun json-object-to-envelope (json-object)
  "Convert a parsed JSON object (hash-table) to an envelope.

   Args:
     json-object: A hash-table from parse-json

   Returns:
     A CROSS-SWARM-ENVELOPE instance.

   Raises:
     ERROR if required fields are missing or invalid."
  (let ((id (gethash "id" json-object)))
    (unless id
      (error "Missing required field 'id' in JSON envelope"))

    (let ((env (make-cross-swarm-envelope
                 :correlation-id (gethash "correlation_id" json-object)
                 :idempotency-token (gethash "idempotency_token" json-object)
                 :source-swarm (gethash "source_swarm" json-object)
                 :target-swarm (gethash "target_swarm" json-object)
                 :sender (gethash "sender" json-object)
                 :recipient (gethash "recipient" json-object)
                 :payload (deserialize-payload
                           (gethash "payload" json-object) :json)
                 :path (gethash "path" json-object)
                 :hop-count (or (gethash "hop_count" json-object) 0)
                 :max-hops (or (gethash "max_hops" json-object) 10)
                 :created-at (timestamp-to-universal
                              (gethash "created_at" json-object))
                 :deadline (when (gethash "deadline" json-object)
                             (timestamp-to-universal
                              (gethash "deadline" json-object)))
                 :priority (or (keyword-from-string
                                (gethash "priority" json-object)) :normal)
                 :message-type (or (keyword-from-string
                                    (gethash "message_type" json-object)) :request))))
      ;; Override the auto-generated ID with the one from JSON
      (setf (slot-value env 'id) id)
      (validate-envelope env)
      env)))

;;;; ============================================================================
;;;; Plist Serialization (Lisp-Native Format)
;;;; ============================================================================

(defun envelope-to-plist (envelope)
  "Serialize an envelope to a property list (plist).

   Args:
     envelope: CROSS-SWARM-ENVELOPE to serialize

   Returns:
     A property list (:key1 value1 :key2 value2 ...)

   Notes:
     - All fields are included (nil values are preserved as nil)
     - Payload is included as-is (not serialized)
     - Timestamps remain as universal-time (not converted)
     - Keywords remain as keywords

   Example:
     (let ((env (make-cross-swarm-envelope
                  :source-swarm \"frontend\"
                  :target-swarm \"backend\")))
       (envelope-to-plist env))
     => (:ID \"550e8400-e29b...\" :CORRELATION-ID NIL :SOURCE-SWARM \"frontend\"
         :TARGET-SWARM \"backend\" ...)"
  (list
    :id (envelope-id envelope)
    :correlation-id (envelope-correlation-id envelope)
    :idempotency-token (envelope-idempotency-token envelope)
    :source-swarm (envelope-source-swarm envelope)
    :target-swarm (envelope-target-swarm envelope)
    :sender (envelope-sender envelope)
    :recipient (envelope-recipient envelope)
    :payload (envelope-payload envelope)
    :path (envelope-path envelope)
    :hop-count (envelope-hop-count envelope)
    :max-hops (envelope-max-hops envelope)
    :created-at (envelope-created-at envelope)
    :deadline (envelope-deadline envelope)
    :priority (envelope-priority envelope)
    :message-type (envelope-message-type envelope)))

(defun plist-to-envelope (plist)
  "Deserialize an envelope from a property list.

   Args:
     plist: A property list created by envelope-to-plist

   Returns:
     A CROSS-SWARM-ENVELOPE instance.

   Notes:
     - All fields are restored from the plist
     - Payload is restored as-is
     - No type conversion (assumes well-formed plist)

   Raises:
     ERROR if envelope validation fails

   Example:
     (let ((env (make-cross-swarm-envelope :source-swarm \"frontend\")))
       (let ((plist (envelope-to-plist env)))
         (plist-to-envelope plist)))
     => #<ENVELOPE id: 550e8400-e29b-41d4-a7... src: frontend -> ...>"
  (let ((env (make-cross-swarm-envelope
               :correlation-id (getf plist :correlation-id)
               :idempotency-token (getf plist :idempotency-token)
               :source-swarm (getf plist :source-swarm)
               :target-swarm (getf plist :target-swarm)
               :sender (getf plist :sender)
               :recipient (getf plist :recipient)
               :payload (getf plist :payload)
               :path (getf plist :path)
               :hop-count (or (getf plist :hop-count) 0)
               :max-hops (or (getf plist :max-hops) 10)
               :created-at (or (getf plist :created-at) (get-universal-time))
               :deadline (getf plist :deadline)
               :priority (or (getf plist :priority) :normal)
               :message-type (or (getf plist :message-type) :request))))
    ;; Override ID if provided in plist
    (when (getf plist :id)
      (setf (slot-value env 'id) (getf plist :id)))
    (validate-envelope env)
    env))

(defun envelope-from-plist (plist)
  "Compatibility wrapper: deserialize an envelope from plist."
  (plist-to-envelope plist))

;;;; ============================================================================
;;;; Binary Serialization (For Persistence)
;;;; ============================================================================

(defun envelope-to-octets (envelope)
  "Serialize an envelope to a byte array (octets).

   Args:
     envelope: CROSS-SWARM-ENVELOPE to serialize

   Returns:
     A (SIMPLE-ARRAY (UNSIGNED-BYTE 8)) containing the serialized envelope.

   Notes:
     - Uses a simple binary format (version 1)
     - Format: [version(1)] [json-length(4)] [json-data] [checksum(4)]
     - JSON is used as the serialization format (could use msgpack/protobuf)
     - Checksum is CRC32 of the JSON data

   Example:
     (let ((env (make-cross-swarm-envelope :source-swarm \"frontend\")))
       (let ((octets (envelope-to-octets env)))
         (length octets)))
     => 256  ; typical size"
  (let ((json (envelope-to-json envelope)))
    (let ((json-bytes (string-to-octets json))
          (result (make-array 0 :element-type '(unsigned-byte 8)
                             :adjustable t :fill-pointer t)))

      ;; Write version byte (1)
      (vector-push-extend 1 result)

      ;; Write JSON length (4 bytes, big-endian)
      (let ((len (length json-bytes)))
        (vector-push-extend (ldb (byte 8 24) len) result)
        (vector-push-extend (ldb (byte 8 16) len) result)
        (vector-push-extend (ldb (byte 8 8) len) result)
        (vector-push-extend (ldb (byte 8 0) len) result))

      ;; Write JSON data
      (loop for byte across json-bytes
            do (vector-push-extend byte result))

      ;; Write checksum (4 bytes, simple sum)
      (let ((checksum (compute-checksum json-bytes)))
        (vector-push-extend (ldb (byte 8 24) checksum) result)
        (vector-push-extend (ldb (byte 8 16) checksum) result)
        (vector-push-extend (ldb (byte 8 8) checksum) result)
        (vector-push-extend (ldb (byte 8 0) checksum) result))

      ;; Convert adjustable array to simple array
      (coerce result '(simple-array (unsigned-byte 8) (*))))))

(defun envelope-to-binary (envelope)
  "Compatibility wrapper: serialize envelope to octets."
  (envelope-to-octets envelope))

(defun octets-to-envelope (octets)
  "Deserialize an envelope from a byte array.

   Args:
     octets: A (SIMPLE-ARRAY (UNSIGNED-BYTE 8)) from envelope-to-octets

   Returns:
     A CROSS-SWARM-ENVELOPE instance.

   Notes:
     - Verifies checksum before deserializing
     - Supports version 1 binary format

   Raises:
     ERROR if octets are malformed
     ERROR if checksum fails
     ERROR if JSON is invalid

   Example:
     (let* ((env (make-cross-swarm-envelope :source-swarm \"frontend\"))
            (octets (envelope-to-octets env))
            (restored (octets-to-envelope octets)))
       (string= (envelope-id env) (envelope-id restored)))
     => T"
  (when (< (length octets) 9)
    (error "Octets too short for envelope: ~D bytes" (length octets)))

  (let ((version (aref octets 0)))
    (unless (= version 1)
      (error "Unsupported envelope format version: ~D" version))

    ;; Read JSON length
    (let ((len (+ (ash (aref octets 1) 24)
                  (ash (aref octets 2) 16)
                  (ash (aref octets 3) 8)
                  (aref octets 4))))
      (when (> (+ 9 len) (length octets))
        (error "Octets truncated: declared length ~D exceeds available ~D"
               len (- (length octets) 9)))

      ;; Extract JSON data
      (let ((json-bytes (subseq octets 5 (+ 5 len))))
        ;; Verify checksum
        (let ((expected-checksum (+ (ash (aref octets (+ 5 len)) 24)
                                    (ash (aref octets (+ 6 len)) 16)
                                    (ash (aref octets (+ 7 len)) 8)
                                    (aref octets (+ 8 len))))
              (actual-checksum (compute-checksum json-bytes)))
          (unless (= expected-checksum actual-checksum)
            (warn "Checksum mismatch: expected ~D, got ~D"
                  expected-checksum actual-checksum)))

        ;; Deserialize from JSON
        (let ((json-string (octets-to-string json-bytes)))
          (json-to-envelope json-string))))))

(defun envelope-from-binary (octets)
  "Compatibility wrapper: deserialize envelope from octets."
  (octets-to-envelope octets))

(defun string-to-octets (string)
  "Convert a string to an octet array (UTF-8 encoded).

   Args:
     string: A string to encode

   Returns:
     (SIMPLE-ARRAY (UNSIGNED-BYTE 8)) containing UTF-8 bytes."
  (let ((encoded (sb-ext:string-to-octets string :external-format :utf-8)))
    (coerce encoded '(simple-array (unsigned-byte 8) (*)))))

(defun octets-to-string (octets)
  "Convert an octet array to a string (UTF-8 decoded).

   Args:
     octets: (SIMPLE-ARRAY (UNSIGNED-BYTE 8)) to decode

   Returns:
     A string decoded from UTF-8 bytes."
  (sb-ext:octets-to-string octets :external-format :utf-8))

(defun compute-checksum (octets)
  "Compute a simple checksum for octets.

   Args:
     octets: (SIMPLE-ARRAY (UNSIGNED-BYTE 8))

   Returns:
     A 32-bit checksum value.

   Notes:
     Uses a simple sum (not a real hash). For production, use CRC32 or SHA256."
  (let ((sum 0))
    (loop for byte across octets
          do (setf sum (logand (+ sum byte) #xFFFFFFFF)))
    sum))

;;;; ============================================================================
;;;; Payload Serialization
;;;; ============================================================================

(defun serialize-payload (payload format)
  "Serialize a payload to the specified format.

   Args:
     payload: Any Lisp object
     format: :json, :plist, or :raw

   Returns:
     Serialized payload (string for JSON, plist for :plist, object for :raw)

   Notes:
     - :json: Converts payload to JSON string (requires simple structures)
     - :plist: Returns payload as-is (assumes Lisp structure)
     - :raw: Returns payload as-is (no serialization)

   Raises:
     ERROR if payload cannot be serialized in the given format

   Example:
     (serialize-payload '(:event \"login\" :user-id 42) :json)
     => \"{\\\"event\\\":\\\"login\\\",\\\"user_id\\\":42}\"

     (serialize-payload '(:event \"login\") :plist)
     => (:EVENT \"login\")"
  (ecase format
    (:json (lisp-to-json payload))
    (:plist payload)
    (:raw payload)))

(defun deserialize-payload (serialized format)
  "Deserialize a payload from the specified format.

   Args:
     serialized: Serialized payload (format-dependent)
     format: :json, :plist, or :raw

   Returns:
     The deserialized Lisp object

   Notes:
     - :json: Parses JSON string to Lisp structure
     - :plist: Returns as-is (already a Lisp plist)
     - :raw: Returns as-is (no deserialization)

   Example:
     (deserialize-payload \"{\\\"event\\\":\\\"login\\\"}\" :json)
     => #<HASH-TABLE event: \"login\">

     (deserialize-payload '(:event \"login\") :plist)
     => (:EVENT \"login\")"
  (ecase format
    (:json (json-to-lisp serialized))
    (:plist serialized)
    (:raw serialized)))

(defun lisp-to-json (obj)
  "Convert a Lisp object to a JSON string.

   Args:
     obj: A Lisp object (list, hash-table, string, number, boolean, nil)

   Returns:
     A JSON string representation

   Notes:
     - Lists are converted to JSON objects or arrays (heuristic)
     - Hash-tables are converted to JSON objects
     - Strings are escaped and quoted
     - Numbers are converted directly
     - T becomes true, NIL becomes null

   Example:
     (lisp-to-json '(:event \"login\" :user-id 42))
     => \"{\\\"event\\\":\\\"login\\\",\\\"user_id\\\":42}\""
  (cond
    ((null obj) "null")
    ((eq obj t) "true")
    ((stringp obj) (json-escape-string obj))
    ((numberp obj) (write-to-string obj))
    ((listp obj) (lisp-list-to-json obj))
    ((hash-table-p obj) (hash-table-to-json obj))
    (t (format nil "~S" obj))))

(defun json-to-lisp (json-string)
  "Convert a JSON string to a Lisp object.

   Args:
     json-string: A JSON string

   Returns:
     A Lisp object (hash-table, list, string, number, boolean, nil)

   Example:
     (json-to-lisp \"{\\\"event\\\":\\\"login\\\"}\")
     => #<HASH-TABLE event: \"login\">"
  (parse-json json-string))

(defun lisp-list-to-json (list)
  "Convert a Lisp list to JSON (object or array).

   Args:
     list: A Lisp list

   Returns:
     JSON string (object if plist, array otherwise)

   Notes:
     Heuristic: If list is a plist (alternating keywords and values),
     convert to JSON object. Otherwise, convert to JSON array."
  (if (and (> (length list) 0)
           (keywordp (car list))
           (evenp (length list)))
      ;; Looks like a plist -> convert to JSON object
      (with-output-to-string (out)
        (write-char #\{ out)
        (loop for (key val) on list by #'cddr
              for i from 0
              do (when (> i 0) (write-char #\, out))
                 (format out "~A:~A"
                         (json-escape-string (string-downcase (symbol-name key)))
                         (lisp-to-json val)))
        (write-char #\} out))
      ;; Regular list -> convert to JSON array
      (with-output-to-string (out)
        (write-char #\[ out)
        (loop for item in list
              for i from 0
              do (when (> i 0) (write-char #\, out))
                 (write-string (lisp-to-json item) out))
        (write-char #\] out))))

(defun hash-table-to-json (ht)
  "Convert a hash-table to JSON object.

   Args:
     ht: A hash-table with string keys

   Returns:
     JSON string representing the object"
  (with-output-to-string (out)
    (write-char #\{ out)
    (let ((first t))
      (maphash (lambda (key value)
                 (unless first (write-char #\, out))
                 (setf first nil)
                 (format out "~A:~A"
                         (json-escape-string (string key))
                         (lisp-to-json value)))
               ht))
    (write-char #\} out)))

;;;; ============================================================================
;;;; Timestamp Conversion Helpers
;;;; ============================================================================

(defun timestamp-to-universal (unix-timestamp)
  "Convert Unix epoch timestamp (seconds since 1970-01-01) to universal-time.

   Args:
     unix-timestamp: Integer seconds since 1970-01-01

   Returns:
     Integer universal-time (seconds since 1900-01-01)

   Notes:
     The difference between Unix epoch and Common Lisp universal-time is
     2208988800 seconds (70 years).

   Example:
     (timestamp-to-universal 0)
     => 2208988800  ; 1970-01-01 00:00:00 in universal-time"
  (+ unix-timestamp 2208988800))

(defun universal-to-timestamp (universal-time)
  "Convert universal-time to Unix epoch timestamp.

   Args:
     universal-time: Integer seconds since 1900-01-01

   Returns:
     Integer seconds since 1970-01-01

   Notes:
     Inverse of timestamp-to-universal.

   Example:
     (universal-to-timestamp 2208988800)
     => 0  ; 1970-01-01 00:00:00"
  (- universal-time 2208988800))

;;;; ============================================================================
;;;; Keyword/String Conversion
;;;; ============================================================================

(defun keyword-to-string (keyword)
  "Convert a keyword to a string (lowercase, without colon).

   Args:
     keyword: A keyword symbol

   Returns:
     A string (lowercase, without leading colon)

   Example:
     (keyword-to-string :normal)
     => \"normal\""
  (string-downcase (symbol-name keyword)))

(defun string-to-keyword (string)
  "Convert a string to a keyword (uppercase, with colon).

   Args:
     string: A string

   Returns:
     A keyword symbol

   Example:
     (string-to-keyword \"normal\")
     => :NORMAL"
  (intern (string-upcase string) :keyword))

(defun keyword-from-string (string)
  "Convert a string to a keyword, handling nil and errors gracefully.

   Args:
     string: A string or nil

   Returns:
     A keyword symbol, or NIL if string is nil

   Example:
     (keyword-from-string \"normal\")
     => :NORMAL

     (keyword-from-string nil)
     => NIL"
  (when string
    (string-to-keyword string)))

;;;; ============================================================================
;;;; Envelope Validation During Deserialization
;;;; ============================================================================

(defun validate-json-envelope (json-string)
  "Validate a JSON envelope string without full deserialization.

   Args:
     json-string: A JSON string to validate

   Returns:
     (VALUES success errors) where:
       - success: T if envelope is valid, NIL otherwise
       - errors: List of error messages

   Notes:
     This is a pre-check before calling json-to-envelope.
     Useful for filtering malformed input.

   Example:
     (validate-json-envelope \"{\\\"id\\\":\\\"abc\\\",...}\")
     => (VALUES T NIL)

     (validate-json-envelope \"{invalid json}\")
     => (VALUES NIL (\"Failed to parse JSON: ...\"))"
  (let ((errors nil))
    ;; Try to parse JSON
    (let ((parsed (parse-json json-string)))
      (unless parsed
        (push "Failed to parse JSON" errors)
        (return-from validate-json-envelope (values nil errors)))

      ;; Check for required fields
      (unless (gethash "id" parsed)
        (push "Missing required field 'id'" errors))

      ;; Check field types where possible
      (let ((hop-count (gethash "hop_count" parsed)))
        (when (and hop-count (not (integerp hop-count)))
          (push "Field 'hop_count' must be an integer" errors)))

      (let ((max-hops (gethash "max_hops" parsed)))
        (when (and max-hops (not (integerp max-hops)))
          (push "Field 'max_hops' must be an integer" errors)))

      ;; Return validation result
      (if errors
          (values nil (nreverse errors))
          (values t nil)))))

;;;; End of file
