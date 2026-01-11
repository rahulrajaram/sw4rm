;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; SW4RM Orchestrator - Envelope Reader Macros for DSL
;;;;
;;;; This module defines reader macros for convenient envelope syntax:
;;;;   #E{...} - Standard envelopes
;;;;   #X{...} - Cross-swarm envelopes
;;;;
;;;; Reader macros allow the Lisp reader to parse custom syntax directly into
;;;; typed structures at read time, enabling concise DSL notation.
;;;;
;;;; Features:
;;;;   - #E{...} expands to (make-cross-swarm-envelope ...)
;;;;   - #X{...} expands to full cross-swarm envelope with routing
;;;;   - Automatic symbol-to-string conversion (agent-a -> "agent-a")
;;;;   - Nested data structure support in payloads
;;;;   - Readtable management with enable/disable functions
;;;;
;;;; Examples:
;;;;   #E{:from agent-a :to agent-b :payload {:data 42}}
;;;;   #X{:source-swarm frontend :target-swarm backend
;;;;      :from ui-agent :to api-agent
;;;;      :payload {:event :user-login :user-id 42}}
;;;;
;;;; See also:
;;;;   - ../types.lisp for CROSS-SWARM-ENVELOPE definition
;;;;   - ../../../COMMON_LISP_PLAN.md §2.2.1 for DSL design
;;;;
;;;; Version: 0.6.0
;;;; License: Apache 2.0

(in-package :sw4rm-orchestrator.envelope)

;;;; ============================================================================
;;;; Helper Functions for Argument Parsing and Conversion
;;;; ============================================================================

(defun symbolize-to-string (obj)
  "Convert a symbol to a string, leave other types unchanged.

  This is a core utility for the reader macros: we want to parse unquoted
  symbols (like `agent-a`) as strings so they work naturally in DSL notation.

  Args:
    obj - Any Lisp object (typically a symbol)

  Returns:
    If OBJ is a symbol, returns its name as a lowercase string.
    Otherwise returns OBJ unchanged.

  Examples:
    (symbolize-to-string 'agent-a)
    => \"AGENT-A\"

    (symbolize-to-string \"agent-a\")
    => \"agent-a\"

    (symbolize-to-string 42)
    => 42

    (symbolize-to-string :keyword)
    => :KEYWORD"
  (if (symbolp obj)
      (symbol-name obj)
      obj))

(defun parse-keyword-args (args)
  "Parse a flat list of keyword arguments into a plist.

  Takes a list like (:from agent-a :to agent-b :payload {...})
  and returns it as-is, since it's already a plist.

  This function exists for clarity and potential future extension
  (e.g., validation, key normalization).

  Args:
    args - List with keyword car positions

  Returns:
    The args list as-is (already a valid plist).

  Notes:
    Assumes alternating keywords and values. No validation is performed
    at parse time; validation happens during envelope construction.

  Example:
    (parse-keyword-args '(:from agent-a :to agent-b))
    => (:from agent-a :to agent-b)"
  args)

(defun convert-envelope-args (args)
  "Convert argument list for envelope construction.

  Takes keyword arguments from the DSL and converts them to the form
  expected by MAKE-CROSS-SWARM-ENVELOPE.

  Conversion rules:
    :from SYMBOL -> :sender (symbolize-to-string SYMBOL)
    :to SYMBOL -> :recipient (symbolize-to-string SYMBOL)
    (other args pass through unchanged)

  Args:
    args - Plist of keyword arguments

  Returns:
    New plist with :from/:to converted to :sender/:recipient

  Example:
    (convert-envelope-args '(:from agent-a :to agent-b :payload data))
    => (:sender \"AGENT-A\" :recipient \"AGENT-B\" :payload data)"
  (let ((result nil))
    (loop for (key value) on args by #'cddr
          do (cond
               ((eq key :from)
                (setf result (list* :sender (symbolize-to-string value) result)))
               ((eq key :to)
                (setf result (list* :recipient (symbolize-to-string value) result)))
               (t
                (setf result (list* value key result)))))
    (nreverse result)))

(defun convert-cross-swarm-envelope-args (args)
  "Convert argument list for cross-swarm envelope construction.

  Takes keyword arguments from the #X{...} DSL and converts them to the
  form expected by MAKE-CROSS-SWARM-ENVELOPE.

  Conversion rules:
    :source-swarm SYMBOL -> :source-swarm (symbolize-to-string SYMBOL)
    :target-swarm SYMBOL -> :target-swarm (symbolize-to-string SYMBOL)
    :from SYMBOL -> :sender (symbolize-to-string SYMBOL)
    :to SYMBOL -> :recipient (symbolize-to-string SYMBOL)
    (other args pass through unchanged)

  Args:
    args - Plist of keyword arguments

  Returns:
    New plist with symbols converted to strings where appropriate

  Example:
    (convert-cross-swarm-envelope-args
      '(:source-swarm frontend :from ui-agent :to api-agent :target-swarm backend))
    => (:source-swarm \"FRONTEND\" :sender \"UI-AGENT\" :recipient \"API-AGENT\"
         :target-swarm \"BACKEND\")"
  (let ((result nil))
    (loop for (key value) on args by #'cddr
          do (cond
               ((eq key :source-swarm)
                (setf result (list* :source-swarm (symbolize-to-string value) result)))
               ((eq key :target-swarm)
                (setf result (list* :target-swarm (symbolize-to-string value) result)))
               ((eq key :from)
                (setf result (list* :sender (symbolize-to-string value) result)))
               ((eq key :to)
                (setf result (list* :recipient (symbolize-to-string value) result)))
               (t
                (setf result (list* value key result)))))
    (nreverse result)))

;;;; ============================================================================
;;;; Reader Macro Functions
;;;; ============================================================================

(defun envelope-reader (stream char arg)
  "Reader function for #E{...} envelope shorthand.

  Reads a bracketed list of keyword arguments and expands to a
  MAKE-CROSS-SWARM-ENVELOPE call.

  Syntax:
    #E{:from AGENT :to AGENT :payload EXPR}

  where AGENT is a symbol that gets converted to a string.

  Implementation:
    1. Read delimited list until }
    2. Convert :from/:to to :sender/:recipient
    3. Return (make-cross-swarm-envelope ...) form

  Args:
    stream - Input stream being read
    char - The dispatch character (# - ignored here)
    arg - Optional numeric argument to # (ignored)

  Returns:
    A quoted form: (MAKE-CROSS-SWARM-ENVELOPE ...)

  Examples:
    #E{:from agent-a :to agent-b :payload {:data 42}}
    => (make-cross-swarm-envelope :sender \"AGENT-A\" :recipient \"AGENT-B\"
                                  :payload {:data 42})

    #E{:sender \"direct-string\" :recipient \"other\" :payload nil}
    => (make-cross-swarm-envelope :sender \"direct-string\" :recipient \"other\"
                                  :payload nil)

  Notes:
    - Symbols are automatically converted to strings (uppercase)
    - String literals are preserved as-is
    - The form is returned quoted for later evaluation
    - Nested payloads can use full Lisp syntax"
  (declare (ignore char arg))
  (let ((form (read-delimited-list #\} stream t)))
    ;; Validate we got an even number of arguments (plist)
    (unless (evenp (length form))
      (error "Invalid envelope syntax: odd number of arguments in #E{...}"))
    ;; Convert and construct envelope form
    (let ((converted-args (convert-envelope-args form)))
      `(make-cross-swarm-envelope ,@converted-args))))

(defun cross-swarm-envelope-reader (stream char arg)
  "Reader function for #X{...} cross-swarm envelope shorthand.

  Reads a bracketed list of keyword arguments and expands to a
  MAKE-CROSS-SWARM-ENVELOPE call with full routing information.

  Syntax:
    #X{:source-swarm SWARM :target-swarm SWARM
       :from AGENT :to AGENT
       :payload EXPR}

  where SWARM and AGENT are symbols that get converted to strings.

  Implementation:
    1. Read delimited list until }
    2. Convert symbols to strings (:source-swarm, :target-swarm, :from, :to)
    3. Return (make-cross-swarm-envelope ...) form

  Args:
    stream - Input stream being read
    char - The dispatch character (# - ignored here)
    arg - Optional numeric argument to # (ignored)

  Returns:
    A quoted form: (MAKE-CROSS-SWARM-ENVELOPE ...)

  Examples:
    #X{:source-swarm frontend :target-swarm backend
       :from ui-agent :to api-agent
       :payload {:event :user-login :user-id 42}}

    #X{:source-swarm cluster-a :target-swarm cluster-b
       :sender \"agent-x\" :recipient \"agent-y\"
       :payload (list 'data 'here)}

  Notes:
    - All positional swarm/agent names are converted to strings
    - Direct string literals are preserved as-is
    - Keywords like :payload can use arbitrary Lisp expressions
    - Nested data structures in payload work naturally"
  (declare (ignore char arg))
  (let ((form (read-delimited-list #\} stream t)))
    ;; Validate we got an even number of arguments (plist)
    (unless (evenp (length form))
      (error "Invalid cross-swarm envelope syntax: odd number of arguments in #X{...}"))
    ;; Convert and construct envelope form
    (let ((converted-args (convert-cross-swarm-envelope-args form)))
      `(make-cross-swarm-envelope ,@converted-args))))

;;;; ============================================================================
;;;; Readtable Management
;;;; ============================================================================

(defvar *envelope-readtable* nil
  "Cached readtable with envelope macros enabled.

  This is computed lazily on first call to ENABLE-ENVELOPE-SYNTAX.
  We don't modify *READTABLE* directly to ensure thread-safety and
  allow multiple readtables in the same image.")

(defun enable-envelope-syntax (&optional (readtable *readtable*))
  "Enable envelope reader macros in the given readtable.

  Enables the #E{...} and #X{...} dispatch macros so envelope syntax
  can be used in Lisp code.

  Safety:
    - Does NOT modify the default *READTABLE*
    - Creates a copy of the provided readtable (or *READTABLE* if not given)
    - Returns the new readtable for assignment to *READTABLE*

  Args:
    readtable - Readtable to enable macros on (default: *READTABLE*)

  Returns:
    A readtable with envelope macros enabled.

  Side Effects:
    - Caches the result in *ENVELOPE-READTABLE* for efficiency
    - Does not modify the input readtable

  Example:
    ;; In a file, or at REPL:
    (setf *readtable* (enable-envelope-syntax))

    ;; Now envelope syntax works:
    #E{:from agent-a :to agent-b :payload {:data 42}}

  Thread Safety:
    The initial creation is not thread-safe if multiple threads call
    ENABLE-ENVELOPE-SYNTAX simultaneously. If needed, use WITH-LOCK
    or call this once at startup.

  See Also:
    DISABLE-ENVELOPE-SYNTAX, WITH-ENVELOPE-SYNTAX"
  (unless *envelope-readtable*
    ;; Create a copy of the readtable
    (let ((rt (copy-readtable readtable)))
      ;; Register the #E dispatch macro
      (set-dispatch-macro-character #\# #\E #'envelope-reader rt)
      ;; Register the #X dispatch macro
      (set-dispatch-macro-character #\# #\X #'cross-swarm-envelope-reader rt)
      ;; Cache it
      (setf *envelope-readtable* rt)))
  *envelope-readtable*)

(defun disable-envelope-syntax ()
  "Disable envelope reader macros (restore default readtable).

  Returns the standard Common Lisp readtable without envelope macros.

  Returns:
    The standard *READTABLE* (with envelope macros disabled).

  Side Effects:
    Clears the cached envelope readtable.

  Example:
    (setf *readtable* (disable-envelope-syntax))
    ;; Now #E{...} will cause a read error

  Notes:
    This doesn't actually \"undo\" the envelope macros; it just switches
    back to a fresh readtable without them.

  See Also:
    ENABLE-ENVELOPE-SYNTAX, WITH-ENVELOPE-SYNTAX"
  (setf *envelope-readtable* nil)
  (copy-readtable nil))  ; Returns fresh copy of standard readtable

(defmacro with-envelope-syntax (&body body)
  "Execute BODY with envelope reader macros enabled.

  This is a convenience macro that temporarily enables envelope syntax
  for the duration of the body, then restores the original readtable.

  Useful for reading envelope literals from strings or files without
  permanently modifying the default readtable.

  Args:
    &body - Lisp forms to execute with envelope syntax enabled

  Returns:
    Result of evaluating body

  Side Effects:
    Temporarily changes *READTABLE* to enable envelope macros.
    Restores original readtable on exit (even if body signals error).

  Example:
    (with-envelope-syntax
      (read-from-string \"#E{:from a :to b :payload nil}\"))

    => #<CROSS-SWARM-ENVELOPE id: 550e8400... src: a -> b>

  Notes:
    Uses UNWIND-PROTECT to ensure readtable restoration.
    The body forms are not read with envelope syntax; only EVAL is.
    To read envelope literals, use read-from-string within the body.

  See Also:
    ENABLE-ENVELOPE-SYNTAX, DISABLE-ENVELOPE-SYNTAX"
  (let ((old-readtable (gensym)))
    `(let ((,old-readtable *readtable*))
       (unwind-protect
           (progn
             (setf *readtable* (enable-envelope-syntax))
             ,@body)
         (setf *readtable* ,old-readtable)))))

;;;; ============================================================================
;;;; Advanced: named-readtables Integration (Optional)
;;;; ============================================================================

(defun enable-envelope-syntax-with-named-readtables (name)
  "Create and register a named readtable with envelope syntax.

  If the named-readtables library is available, this creates a named
  readtable that can be activated with (in-readtable NAME).

  This is more elegant than managing *READTABLE* manually for packages
  that want envelope syntax consistently.

  Args:
    name - Symbol naming the new readtable

  Returns:
    The readtable (or NIL if named-readtables not available)

  Side Effects:
    Registers the new readtable if named-readtables is loaded.

  Example:
    ;; In a .lisp file header:
    (eval-when (:compile-toplevel :load-toplevel :execute)
      (enable-envelope-syntax-with-named-readtables 'sw4rm-envelope-syntax))

    ;; Then in the file:
    (in-readtable sw4rm-envelope-syntax)

    ;; Now envelope syntax works throughout the file
    #E{:from a :to b :payload nil}

  Notes:
    This is optional. If named-readtables is not loaded, you can still
    use ENABLE-ENVELOPE-SYNTAX and manage *READTABLE* manually.

    Requires the named-readtables library (available via Quicklisp)."
  (let ((rt (enable-envelope-syntax)))
    (handler-case
        (progn
          (require :named-readtables)
          ;; If we get here, named-readtables is available
          (funcall (find-symbol "DEFREADTABLE" :named-readtables)
                   name
                   (:merge :standard)
                   (:dispatch-macro-char #\# #\E #'envelope-reader)
                   (:dispatch-macro-char #\# #\X #'cross-swarm-envelope-reader))
          rt)
      (error ()
        ;; named-readtables not available, just return the readtable
        rt))))

;;;; ============================================================================
;;;; Examples and Documentation
;;;; ============================================================================

(defun example-simple-envelope ()
  "Example: Create a simple envelope with #E{...} syntax.

  This example shows the most basic usage of the #E reader macro.

  Code:
    (setf *readtable* (enable-envelope-syntax))
    (read-from-string \"#E{:from agent-a :to agent-b :payload nil}\")

  Result:
    A CROSS-SWARM-ENVELOPE with:
      - sender: \"AGENT-A\"
      - recipient: \"AGENT-B\"
      - payload: nil
      - All other fields at defaults

  See Also:
    ENVELOPE-READER"
  ;; Note: Can't use #E{} in source - reader macro not yet defined at compile time
  ;; To use: (setf *readtable* (enable-envelope-syntax))
  ;;         (read-from-string \"#E{:from agent-a :to agent-b :payload nil}\")
  '(:example-would-use-reader-macro-e))

(defun example-cross-swarm-envelope ()
  "Example: Create a cross-swarm envelope with #X{...} syntax.

  This example shows the full cross-swarm envelope syntax with
  routing information and nested payload.

  Code:
    (setf *readtable* (enable-envelope-syntax))
    (read-from-string
      \"#X{:source-swarm frontend :target-swarm backend
           :from ui-agent :to api-agent
           :payload {:event :user-login :user-id 42}}\")

  Result:
    A CROSS-SWARM-ENVELOPE with:
      - source-swarm: \"FRONTEND\"
      - target-swarm: \"BACKEND\"
      - sender: \"UI-AGENT\"
      - recipient: \"API-AGENT\"
      - payload: {:event :user-login :user-id 42}

  See Also:
    CROSS-SWARM-ENVELOPE-READER"
  ;; Note: Can't use #X{} in source - reader macro not yet defined at compile time
  ;; To use: (setf *readtable* (enable-envelope-syntax))
  ;;         (read-from-string \"#X{:source-swarm frontend ...}\")
  '(:example-would-use-reader-macro-x))

(defun example-envelope-in-file ()
  "Example: Using envelope syntax in a .lisp source file.

  To use envelope syntax in a source file:

  1. At the top of the file, after your LOAD or REQUIRE statements,
     add:

       (setf *readtable* (enable-envelope-syntax))

  2. Now you can use envelope syntax in source literals:

       (defparameter *test-envelope*
         #E{:from agent-a :to agent-b :payload {:test true}})

       (defun send-cross-swarm-message (target)
         (route-envelope *root*
           #X{:source-swarm frontend :target-swarm backend
              :from ui :to api
              :payload {:action target}}))

  3. The envelope forms are read at compile time and expanded to
     MAKE-CROSS-SWARM-ENVELOPE calls.

  Thread Safety:
    If multiple threads are loading this file, they may interfere.
    Consider using WITH-ENVELOPE-SYNTAX in library code instead of
    globally modifying *READTABLE*."
  nil)

;;;; ============================================================================
;;;; Initialization and Testing
;;;; ============================================================================

(defun test-envelope-syntax ()
  "Test envelope reader macro functionality.

  This function tests both #E and #X syntax to ensure they work correctly.

  Returns:
    T if all tests pass.
    Signals ERROR if any test fails.

  Side Effects:
    Prints test results to *standard-output*
    Temporarily modifies *READTABLE*

  Example:
    (test-envelope-syntax)
    => T"
  (with-envelope-syntax
    ;; Test 1: Simple envelope with #E
    (let ((e1 (read-from-string "#E{:from a :to b :payload nil}")))
      (unless (and (string= (envelope-sender e1) "A")
                   (string= (envelope-recipient e1) "B")
                   (null (envelope-payload e1)))
        (error "Test 1 failed: Simple envelope")))

    ;; Test 2: Cross-swarm envelope with #X
    (let ((e2 (read-from-string
                "#X{:source-swarm src :target-swarm dst
                    :from f :to t :payload {:k :v}}")))
      (unless (and (string= (envelope-source-swarm e2) "SRC")
                   (string= (envelope-target-swarm e2) "DST")
                   (string= (envelope-sender e2) "F")
                   (string= (envelope-recipient e2) "T"))
        (error "Test 2 failed: Cross-swarm envelope")))

    ;; Test 3: Envelope with explicit string arguments
    (let ((e3 (read-from-string
                "#E{:sender \"agent-x\" :recipient \"agent-y\" :payload 42}")))
      (unless (and (string= (envelope-sender e3) "agent-x")
                   (string= (envelope-recipient e3) "agent-y")
                   (= (envelope-payload e3) 42))
        (error "Test 3 failed: String arguments")))

    t))

;;;; ============================================================================
;;;; Entry Point: Auto-enable reader macros on load
;;;; ============================================================================

;;;; NOTE: This is commented out by default to avoid side effects.
;;;; Packages that want envelope syntax should explicitly call
;;;; (setf *readtable* (enable-envelope-syntax)) or use WITH-ENVELOPE-SYNTAX.
;;;;
;;;; Uncomment this if you want envelopes enabled by default:
;; (setf *readtable* (enable-envelope-syntax))

;;;; End of file
