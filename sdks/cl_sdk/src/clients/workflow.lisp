;;;; workflow.lisp - Workflow Service client for SW4RM
;;;;
;;;; Provides DAG-based workflow orchestration for multi-agent systems.

(in-package :sw4rm)

;;;; Client Class

(defclass workflow-client (base-client)
  ()
  (:documentation "Client for the SW4RM Workflow Service.

The workflow service provides:
- DAG (Directed Acyclic Graph) workflow submission
- Workflow status tracking and monitoring
- Workflow cancellation
- Node-level execution status

Workflows coordinate multi-step, multi-agent execution graphs with
dependencies, parallel execution, and conditional branching.

Note: The Python SDK implements this as a local WorkflowEngine rather
than a gRPC service. This Common Lisp client defines the interface that
would be used for a remote gRPC workflow service. For local orchestration,
see the workflow engine implementation."))

;;;; RPC Methods

(defgeneric submit-dag (client workflow-definition)
  (:documentation "Submit a workflow DAG for execution.

Creates a workflow from a DAG definition and begins execution. The
workflow engine will coordinate task distribution across agents based
on the DAG structure.

Args:
  client: The workflow-client instance.
  workflow-definition: Workflow definition plist with:
    :workflow-id (string) - Unique workflow identifier
    :name (string) - Human-readable workflow name
    :nodes (list) - List of node definitions
    :edges (list) - List of edge/dependency definitions
    :metadata (alist, optional) - Additional metadata

  Node definition format:
    :node-id (string) - Unique node identifier
    :agent-id (string) - Agent to execute this node
    :task-type (string) - Type of task
    :params (string or bytes) - Task parameters
    :trigger (keyword) - Trigger type (:automatic, :manual, :conditional)

  Edge definition format:
    :from-node (string) - Source node ID
    :to-node (string) - Target node ID
    :condition (string, optional) - Conditional expression

Returns:
  Workflow submission response plist with:
    :workflow-id (string) - Workflow identifier
    :status (keyword) - Initial status (:submitted, :running)

Signals:
  RPC-ERROR: If submission fails (e.g., invalid DAG, cycles detected).

Example:
  (submit-dag client
              (list :workflow-id \"wf-123\"
                    :name \"Code Review Workflow\"
                    :nodes (list (list :node-id \"analyze\"
                                       :agent-id \"analyzer\"
                                       :task-type \"code-analysis\"
                                       :params \"{}\")
                                 (list :node-id \"review\"
                                       :agent-id \"reviewer\"
                                       :task-type \"code-review\"
                                       :params \"{}\"))
                    :edges (list (list :from-node \"analyze\"
                                       :to-node \"review\"))))"))

(defmethod submit-dag ((client workflow-client) workflow-definition)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC WorkflowService.SubmitDAG
      (error 'rpc-error
             :message "SubmitDAG not implemented - requires gRPC integration"
             :code "UNIMPLEMENTED"))))

(defgeneric get-workflow-status (client workflow-id)
  (:documentation "Get the current status of a workflow.

Retrieves workflow execution state, completed nodes, pending nodes,
and overall progress.

Args:
  client: The workflow-client instance.
  workflow-id: Unique identifier of the workflow.

Returns:
  Workflow status plist with:
    :workflow-id (string) - Workflow identifier
    :status (keyword) - Overall status (:running, :completed, :failed, :cancelled)
    :started-at (timestamp) - Workflow start time
    :completed-at (timestamp, optional) - Workflow completion time
    :nodes (list) - List of node status plists
    :progress (float) - Completion percentage (0.0-1.0)

  Node status format:
    :node-id (string) - Node identifier
    :status (keyword) - Node status (:pending, :running, :completed, :failed, :skipped)
    :started-at (timestamp, optional) - Node start time
    :completed-at (timestamp, optional) - Node completion time
    :error (string, optional) - Error message if failed

Signals:
  RPC-ERROR: If workflow not found or status query fails.

Example:
  (get-workflow-status client \"wf-123\")
  => (:workflow-id \"wf-123\"
      :status :running
      :progress 0.5
      :nodes ((:node-id \"analyze\" :status :completed)
              (:node-id \"review\" :status :running)))"))

(defmethod get-workflow-status ((client workflow-client) workflow-id)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC WorkflowService.GetStatus
      (error 'rpc-error
             :message "GetWorkflowStatus not implemented - requires gRPC integration"
             :code "UNIMPLEMENTED"))))

(defgeneric cancel-workflow (client workflow-id &optional reason)
  (:documentation "Cancel a running workflow.

Requests cancellation of the workflow. Running nodes will be signaled
to abort, and pending nodes will be skipped.

Args:
  client: The workflow-client instance.
  workflow-id: Unique identifier of the workflow to cancel.
  reason: Optional reason for cancellation.

Returns:
  Cancellation response plist with:
    :cancelled (boolean) - Whether cancellation was successful
    :message (string) - Cancellation status message

Signals:
  RPC-ERROR: If cancellation fails.

Example:
  (cancel-workflow client \"wf-123\" \"User requested abort\")"))

(defmethod cancel-workflow ((client workflow-client) workflow-id &optional (reason ""))
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC WorkflowService.Cancel
      (error 'rpc-error
             :message "CancelWorkflow not implemented - requires gRPC integration"
             :code "UNIMPLEMENTED"))))

(defgeneric resume-workflow (client workflow-id node-id &key workflow-data metadata)
  (:documentation "Resume a workflow by marking a node as completed (spec §17.7 MUST).

Marks the specified node as COMPLETED, updates workflow data if provided,
and advances dependent nodes from PENDING to READY when all their
dependencies are met.

Args:
  client: The workflow-client instance.
  workflow-id: Unique identifier of the workflow.
  node-id: Node to mark as completed.
  workflow-data: Optional updated workflow data (JSON string).
  metadata: Optional metadata alist for the resume operation.

Returns:
  Updated workflow status plist.

Signals:
  RPC-ERROR: If workflow or node not found.

Example:
  (resume-workflow client \"wf-123\" \"analyze\"
                   :workflow-data \"{\\\"result\\\": \\\"ok\\\"}\"
                   :metadata '((:resumed-by . \"operator\")))"))

(defmethod resume-workflow ((client workflow-client) workflow-id node-id
                            &key workflow-data metadata)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC WorkflowService.ResumeWorkflow
      (error 'rpc-error
             :message "ResumeWorkflow not implemented - requires gRPC integration"
             :code "UNIMPLEMENTED"))))

;;;; Additional Workflow Management

(defgeneric wait-for-completion (client workflow-id &key timeout-s poll-interval-s)
  (:documentation "Wait for a workflow to complete.

Polls for workflow completion until it reaches a terminal state
(:completed, :failed, :cancelled) or the timeout is reached.

Args:
  client: The workflow-client instance.
  workflow-id: Unique identifier of the workflow.
  timeout-s: Maximum time to wait in seconds (default: 300.0).
  poll-interval-s: Time between polling attempts in seconds (default: 1.0).

Returns:
  Final workflow status plist.

Signals:
  RPC-TIMEOUT: If workflow doesn't complete within timeout period.
  RPC-ERROR: If status polling fails.

Example:
  (wait-for-completion client \"wf-123\" :timeout-s 600.0)"))

(defmethod wait-for-completion ((client workflow-client) workflow-id
                                &key (timeout-s 300.0) (poll-interval-s 1.0))
  (let ((start-time (get-internal-real-time))
        (timeout-ms (* timeout-s 1000)))
    (loop
      (let ((status (get-workflow-status client workflow-id)))
        (when (member (getf status :status) '(:completed :failed :cancelled))
          (return status)))

      (let ((elapsed-ms (floor (* 1000 (- (get-internal-real-time) start-time))
                               internal-time-units-per-second)))
        (when (>= elapsed-ms timeout-ms)
          (error 'rpc-timeout
                 :message (format nil "Workflow ~S did not complete within ~As"
                                  workflow-id timeout-s)
                 :code "DEADLINE_EXCEEDED")))

      (sleep poll-interval-s))))

(defgeneric list-workflows (client &key status limit)
  (:documentation "List workflows, optionally filtered by status.

Retrieves a list of workflow summaries, optionally filtered by status.

Args:
  client: The workflow-client instance.
  status: Optional status filter (keyword).
  limit: Optional maximum number of results.

Returns:
  List of workflow summary plists.

Signals:
  RPC-ERROR: If listing fails.

Example:
  ;; List all running workflows
  (list-workflows client :status :running :limit 10)"))

(defmethod list-workflows ((client workflow-client) &key status limit)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC WorkflowService.List
      (error 'rpc-error
             :message "ListWorkflows not implemented - requires gRPC integration"
             :code "UNIMPLEMENTED"))))
