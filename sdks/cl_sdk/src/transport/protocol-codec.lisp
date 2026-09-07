;;;; Descriptor-backed codecs for every message in the canonical SW4RM schema.
;;;; Plist keys use kebab-case, enums are integers, bytes are octet vectors,
;;;; maps are alists, and nested messages are plists (including NIL for Empty).
(in-package :sw4rm-sdk)

(defun protocol-message-fields (name)
  "Return the generated field schema for a fully qualified message NAME."
  (let ((schema (assoc name *protocol-message-schemas* :test #'string=)))
    (unless schema (error "Unknown protobuf message: ~A" name))
    (second schema)))

(defun %protocol-bytes (&rest parts)
  (apply #'concatenate '(simple-array (unsigned-byte 8) (*)) parts))

(defun %protocol-length-field (number bytes)
  (%protocol-bytes (encode-tag number 2) (encode-varint (length bytes)) bytes))

(defun %protocol-integer (value kind)
  (let ((range (ecase kind
                 ((:int32 :enum) '(signed-byte 32))
                 (:int64 '(signed-byte 64))
                 (:uint32 '(unsigned-byte 32))
                 (:uint64 '(unsigned-byte 64)))))
    (unless (typep value range)
      (error "Value ~S is outside protobuf ~S" value kind))
    (ldb (byte 64 0) value)))

(defun %protocol-encode-field (field value &optional preserve-default)
  (destructuring-bind (key number kind repeated target map-entry) field
    (declare (ignore key repeated map-entry))
    (ecase kind
      (:message (%protocol-length-field number (encode-protocol-message target value)))
      (:string (if (or preserve-default (plusp (length value)))
                   (%protocol-length-field number (babel:string-to-octets value :encoding :utf-8))
                   (%protocol-bytes)))
      (:bytes (if (or preserve-default (plusp (length value)))
                  (%protocol-length-field number value) (%protocol-bytes)))
      (:bool (if (or value preserve-default)
                 (%protocol-bytes (encode-tag number 0) (encode-varint (if value 1 0)))
                 (%protocol-bytes)))
      ((:int32 :int64 :uint32 :uint64 :enum)
       (let ((integer (%protocol-integer value kind)))
         (if (or preserve-default (not (zerop integer)))
             (%protocol-bytes (encode-tag number 0) (encode-varint integer))
             (%protocol-bytes))))
      (:double (or (encode-field-double number value) (%protocol-bytes)))
      (:float (or (encode-field-float number value) (%protocol-bytes))))))

(defun encode-protocol-message (name message)
  "Encode a canonical message plist without discarding unknown input keys."
  (let ((fields (protocol-message-fields name)))
    (unless (and (listp message) (evenp (length message)))
      (error "~A requires a property list" name))
    (loop for (key value) on message by #'cddr
          do (unless (assoc key fields) (error "Unknown ~A field: ~S" name key)))
    (apply #'%protocol-bytes
           (loop for field in fields
                 for key = (first field)
                 for found = (loop for tail on message by #'cddr
                                   when (eq (first tail) key) return tail)
                 when found append
                 (let ((value (second found)))
                   (cond
                     ((sixth field)
                      (mapcar (lambda (entry)
                                (%protocol-length-field
                                 (second field)
                                 (let ((entry-fields (protocol-message-fields (fifth field))))
                                   (%protocol-bytes
                                    (%protocol-encode-field (assoc :key entry-fields) (car entry) t)
                                    (%protocol-encode-field (assoc :value entry-fields) (cdr entry) t)))))
                              (sort (copy-list value) #'string< :key #'car)))
                     ((fourth field)
                      (mapcar (lambda (entry) (%protocol-encode-field field entry t)) value))
                     (t (list (%protocol-encode-field field value)))))))))

(defun %protocol-signed (value bits)
  (let ((low (ldb (byte bits 0) value)))
    (if (logbitp (1- bits) low) (- low (ash 1 bits)) low)))

(defun %protocol-decode-value (field raw)
  (let ((kind (third field)))
    (ecase kind
      (:message (decode-protocol-message (fifth field) raw))
      (:string (babel:octets-to-string raw :encoding :utf-8))
      (:bytes raw)
      (:bool (not (zerop raw)))
      ((:int32 :enum) (%protocol-signed raw 32))
      (:int64 (%protocol-signed raw 64))
      (:uint32 (ldb (byte 32 0) raw))
      (:uint64 raw)
      (:double (field-double (list (cons 1 raw)) 1))
      (:float (field-float (list (cons 1 raw)) 1)))))

(defun %protocol-last-map-values (entries)
  (loop for (entry . rest) on entries
        unless (assoc (car entry) rest :test #'equal) collect entry))

(defun %protocol-default-value (field)
  "Map entries may omit their key or value; protobuf supplies scalar defaults."
  (case (third field)
    (:string "")
    (:bytes (%protocol-bytes))
    ((:bool :message) nil)
    ((:float :double) 0.0)
    (otherwise 0)))

(defun %protocol-wire-type (kind)
  "Expected protobuf wire type for a schema KIND (third value of a field row).
Wire types: 0 varint, 1 fixed64, 2 length-delimited, 5 fixed32 (R37)."
  (case kind
    ((:int32 :int64 :uint32 :uint64 :bool :enum) 0)
    ((:string :bytes :message) 2)
    (:float 5)
    (:double 1)
    (otherwise (error "Unhandled schema kind ~A" kind))))

(defun decode-protocol-message (name bytes)
  "Decode fields known to NAME, retaining repeated order and nested presence.
Unknown wire fields are skipped — including fields whose NUMBER matches a
schema field but whose WIRE TYPE contradicts the schema kind (R37).  Singular
scalars use the last occurrence; singular submessages merge as required by
protobuf. Maps keep the last value."
  (let ((raw-fields (%decode-fields-typed bytes)))
    (loop for field in (protocol-message-fields name)
          for expected-wire-type = (%protocol-wire-type (third field))
          for occurrences = (remove (second field) raw-fields :key #'car :test-not #'=)
          for matching = (remove-if-not (lambda (entry)
                                          (= expected-wire-type (second entry)))
                                        occurrences)
          when matching append
          (list (first field)
                (cond
                  ((sixth field)
                   (%protocol-last-map-values
                    (mapcar (lambda (entry)
                              (let* ((decoded (%protocol-decode-value field (cddr entry)))
                                     (value-field (assoc :value (protocol-message-fields (fifth field)))))
                                (cons (getf decoded :key "")
                                      (getf decoded :value (%protocol-default-value value-field)))))
                            matching)))
                  ((fourth field)
                   (mapcar (lambda (entry) (%protocol-decode-value field (cddr entry))) matching))
                  ((eq (third field) :message)
                   (%protocol-decode-value field (apply #'%protocol-bytes (mapcar #'cddr matching))))
                  (t (%protocol-decode-value field (cddr (car (last matching))))))))))
