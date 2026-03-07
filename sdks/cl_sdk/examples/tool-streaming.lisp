;;;; tool-streaming.lisp -- Tool client and connector client example
;;;;
;;;; Demonstrates the SW4RM tool execution and provider registration subsystem:
;;;;   1. Registering a tool provider with the Connector Service
;;;;   2. Listing available tools and providers
;;;;   3. Executing a unary tool call
;;;;   4. Executing a streaming tool call with a frame handler
;;;;   5. Cancelling an in-flight tool call
;;;;
;;;; Prerequisites:
;;;;   - Quicklisp installed (https://www.quicklisp.org/)
;;;;   - SW4RM SDK on ASDF load path (e.g., symlink sdks/cl_sdk/ into ~/quicklisp/local-projects/)
;;;;
;;;; Run:
;;;;   sbcl --load examples/tool-streaming.lisp

;;; ---------------------------------------------------------------------------
;;; Step 0: Ensure Quicklisp is available, then load the SDK
;;; ---------------------------------------------------------------------------

;;; Ensure Quicklisp is available
#-quicklisp
(let ((quicklisp-init (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file quicklisp-init)
    (load quicklisp-init)))

(ql:quickload :sw4rm-sdk)

(defpackage #:tool-streaming-example
  (:use #:cl #:sw4rm-sdk))

(in-package #:tool-streaming-example)

;;; ---------------------------------------------------------------------------
;;; Part A: Connector Client -- Provider Registration
;;; ---------------------------------------------------------------------------

(format t "~&;; === Part A: Connector Client -- Provider Registration ===~%")

(defvar *config*
  (make-agent-config
   :agent-id "tool-agent-1"
   :name "ToolDemoAgent"
   :description "Demonstrates tool client and connector client usage."
   :version "0.6.0"
   :capabilities '("tool-execution" "streaming")
   :endpoints (make-default-endpoints)
   :timeout-ms 30000
   :retry-max-attempts 3
   :heartbeat-interval-ms 30000))

;; Create a connector client for tool provider registration.
(defvar *connector*
  (make-instance 'connector-client
                 :address (endpoints-connector (agent-config-endpoints *config*))))

(format t ";;   Connector service: ~A~%" (endpoints-connector (agent-config-endpoints *config*)))

;; Define a tool catalog for our provider.
;; Each tool descriptor specifies its schema and execution properties.
(defvar *tool-catalog*
  (list
   (list :tool-name "shell_exec"
         :input-schema '(:type "object"
                         :properties ((:command (:type "string"))
                                      (:timeout-s (:type "integer" :default 30))))
         :output-schema '(:type "object"
                          :properties ((:stdout (:type "string"))
                                       (:stderr (:type "string"))
                                       (:exit-code (:type "integer"))))
         :idempotent nil
         :needs-worktree t
         :default-timeout-s 60
         :max-concurrency 4
         :side-effects t)
   (list :tool-name "file_read"
         :input-schema '(:type "object"
                         :properties ((:path (:type "string"))
                                      (:encoding (:type "string" :default "utf-8"))))
         :output-schema '(:type "object"
                          :properties ((:content (:type "string"))
                                       (:size-bytes (:type "integer"))))
         :idempotent t
         :needs-worktree t
         :default-timeout-s 10
         :max-concurrency 8
         :side-effects nil)))

(format t ";;   Tool catalog: ~{~A~^, ~}~%"
        (mapcar (lambda (t-desc) (getf t-desc :tool-name)) *tool-catalog*))

;; Register the provider (stub transport -- shows the call pattern).
(with-sw4rm-error-handling ()
  (handler-case
      (register-provider *connector* "shell-provider-1" *tool-catalog*)
    (error (e)
      (format t ";;   [expected] register-provider stub: ~A~%" e))))

;; List providers (stub transport).
(with-sw4rm-error-handling ()
  (handler-case
      (let ((providers (list-providers *connector*)))
        (format t ";;   Providers: ~A~%" providers))
    (error (e)
      (format t ";;   [expected] list-providers stub: ~A~%" e))))

;;; ---------------------------------------------------------------------------
;;; Part B: Tool Client -- Unary Tool Call
;;; ---------------------------------------------------------------------------

(format t "~&~%;; === Part B: Tool Client -- Unary Tool Call ===~%")

;; Create a tool client.
(defvar *tool-client*
  (make-instance 'tool-client
                 :address (endpoints-connector (agent-config-endpoints *config*))))

;; Build a tool call request.
(defvar *call-id* (generate-uuid))

(defvar *tool-call*
  (list :call-id *call-id*
        :tool-name "file_read"
        :provider-id "shell-provider-1"
        :args '(:path "/tmp/example.txt" :encoding "utf-8")
        :worktree-id "wt-tool-agent-1"
        :timeout-ms 10000))

(format t ";;   Tool call:~%")
(format t ";;     call-id    : ~A~%" (getf *tool-call* :call-id))
(format t ";;     tool-name  : ~A~%" (getf *tool-call* :tool-name))
(format t ";;     provider-id: ~A~%" (getf *tool-call* :provider-id))

;; Execute unary tool call (stub transport).
(with-sw4rm-error-handling ()
  (handler-case
      (let ((result (call-tool *tool-client* *tool-call*)))
        (format t ";;   Result: ~A~%" result))
    (error (e)
      (format t ";;   [expected] call-tool stub: ~A~%" e)
      (format t ";;   (In production, this returns {:call-id, :status, :result, :error-message})~%"))))

;;; ---------------------------------------------------------------------------
;;; Part C: Tool Client -- Streaming Tool Call
;;; ---------------------------------------------------------------------------

(format t "~&~%;; === Part C: Tool Client -- Streaming Tool Call ===~%")

(defvar *stream-call-id* (generate-uuid))

(defvar *stream-tool-call*
  (list :call-id *stream-call-id*
        :tool-name "shell_exec"
        :provider-id "shell-provider-1"
        :args '(:command "find . -name '*.lisp' -type f" :timeout-s 30)
        :worktree-id "wt-tool-agent-1"
        :timeout-ms 60000))

(format t ";;   Streaming call-id: ~A~%" *stream-call-id*)

;; Define a frame handler that processes streaming results.
(defvar *frame-count* 0)

(defun handle-stream-frame (frame)
  "Handler called for each frame of a streaming tool call."
  (incf *frame-count*)
  (format t ";;   [frame ~D] ~A~%" *frame-count* frame))

;; Execute streaming tool call (stub transport).
(with-sw4rm-error-handling ()
  (handler-case
      (stream-tool-call *tool-client* *stream-tool-call* #'handle-stream-frame)
    (error (e)
      (format t ";;   [expected] stream-tool-call stub: ~A~%" e)
      (format t ";;   (In production, handler-fn is called for each frame received.)~%"))))

;;; ---------------------------------------------------------------------------
;;; Part D: Tool Client -- Cancel Tool Call
;;; ---------------------------------------------------------------------------

(format t "~&~%;; === Part D: Tool Client -- Cancel Tool Call ===~%")

(format t ";;   Cancelling call-id: ~A~%" *stream-call-id*)

(with-sw4rm-error-handling ()
  (handler-case
      (cancel-tool-call *tool-client* *stream-call-id*)
    (error (e)
      (format t ";;   [expected] cancel-tool-call stub: ~A~%" e)
      (format t ";;   (In production, this is a best-effort cancellation.)~%"))))

;;; ---------------------------------------------------------------------------
;;; Part E: List Available Tools
;;; ---------------------------------------------------------------------------

(format t "~&~%;; === Part E: List Available Tools ===~%")

(with-sw4rm-error-handling ()
  (handler-case
      (let ((tools (list-tools *tool-client*)))
        (format t ";;   Available tools: ~A~%" tools))
    (error (e)
      (format t ";;   [expected] list-tools stub: ~A~%" e)
      (format t ";;   (In production, returns tool descriptors with schemas.)~%"))))

;;; ---------------------------------------------------------------------------
;;; Summary
;;; ---------------------------------------------------------------------------

(format t "~&~%;; Tool streaming example complete.~%")
(format t ";; Key takeaways:~%")
(format t ";;   - connector-client / register-provider for tool provider registration~%")
(format t ";;   - Tool descriptors with input/output schemas and execution properties~%")
(format t ";;   - tool-client / call-tool for unary (request-response) tool execution~%")
(format t ";;   - stream-tool-call with handler-fn for streaming results~%")
(format t ";;   - cancel-tool-call for best-effort cancellation~%")
(format t ";;   - list-tools / list-providers for discovery~%")
