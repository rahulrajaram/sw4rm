;;;; scheduler.lisp - Scheduler Service client for SW4RM
;;;;
;;;; Manages task submission, cancellation, status queries, and preemption
;;;; for distributed agent scheduling.

(in-package :sw4rm-sdk)

;;;; Client Class

(defclass scheduler-client (base-client)
  ()
  (:documentation "Client for the SW4RM Scheduler Service.

The scheduler service provides:
- Task submission with priority and scope
- Preemption requests for running tasks
- Agent shutdown with a grace period
- Activity buffer polling and purging for agent task queues

The scheduler coordinates task execution across agents, handling conflicts,
priorities, and resource constraints."))

;;;; RPC Methods

(defgeneric shutdown-agent (client agent-id &key grace-period-seconds grace-period-nanos)
  (:documentation "Request canonical SchedulerService.ShutdownAgent with an optional Duration."))

(defmethod shutdown-agent ((client scheduler-client) agent-id
                           &key grace-period-seconds grace-period-nanos)
  (ensure-connected client)
  (decode-shutdown-agent-response
   (grpc-unary-call
    (client-channel client)
    "/sw4rm.scheduler.SchedulerService/ShutdownAgent"
    (encode-shutdown-agent-request agent-id grace-period-seconds grace-period-nanos)
    :deadline-ms (client-timeout-ms client))))

(defgeneric submit-task (client agent-id task-id &key priority scope params content-type)
  (:documentation "Submit a task to the scheduler for execution.

Schedules a task for execution by the specified agent. The scheduler
will handle queueing, conflict detection (via scope), and priority-based
ordering.

Args:
  client: The scheduler-client instance.
  agent-id: Target agent identifier.
  task-id: Unique task identifier.
  priority: Task priority from -19 (highest) to 20 (lowest), default 0.
  scope: Resource scope descriptor for conflict detection (default: \"\").
  params: Task parameters as byte array (default: empty).
  content-type: MIME type of params (default: \"application/json\").

Returns:
  Task submission response plist with:
    :accepted (boolean) - Whether the task was accepted by the scheduler.
    :reason (string) - Scheduler reason/details for the acceptance decision.

Signals:
  RPC-ERROR: If submission fails.
  ERROR: If priority is out of range [-19, 20].

Example:
  (submit-task client \"agent-1\" \"task-123\"
               :priority -5
               :scope \"file:/path/to/resource\"
               :params (babel:string-to-octets \"{\\\"action\\\": \\\"compile\\\"}\")
               :content-type \"application/json\")"))

(defmethod submit-task ((client scheduler-client) agent-id task-id
                        &key (priority 0) (scope "") (params #()) (content-type "application/json"))
  (unless (<= -19 priority 20)
    (error "Priority must be between -19 and 20, got ~A" priority))
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((request-bytes (encode-submit-task-request
                             agent-id task-id
                             :priority priority :scope scope
                             :params params :content-type content-type))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.scheduler.SchedulerService/SubmitTask"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-submit-task-response response-bytes)))))

(defgeneric preempt-agent (client agent-id task-id &optional reason)
  (:documentation "Request preemption of a running task.

Signals the agent to pause or abort the currently executing task,
typically to allow a higher-priority task to run.

Args:
  client: The scheduler-client instance.
  agent-id: Agent running the task to preempt.
  task-id: Task identifier to preempt.
  reason: Optional reason for preemption (default: \"\").

Returns:
  Preemption response plist with :enqueued boolean.

Signals:
  RPC-ERROR: If preemption request fails.

Example:
  (preempt-agent client \"agent-1\" \"task-123\" \"Higher priority task queued\")"))

(defmethod preempt-agent ((client scheduler-client) agent-id task-id &optional (reason ""))
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((request-bytes (encode-preempt-request agent-id task-id reason))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.scheduler.SchedulerService/RequestPreemption"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-preempt-response response-bytes)))))

(defgeneric poll-activity-buffer (client agent-id)
  (:documentation "Poll the activity buffer for an agent's task queue.

Retrieves the current list of tasks in the agent's activity buffer,
including pending, running, and recently completed tasks.

Args:
  client: The scheduler-client instance.
  agent-id: Agent whose activity to poll.

Returns:
  List of activity entry plists, each with:
    :task-id (string) - Task identifier
    :status (keyword) - Task status
    :priority (integer) - Task priority
    :submitted-at (timestamp) - Submission time

Signals:
  RPC-ERROR: If poll fails.

Example:
  (poll-activity-buffer client \"agent-1\")
  => ((:task-id \"task-123\" :status :running :priority 0)
      (:task-id \"task-124\" :status :pending :priority 5))"))

(defmethod poll-activity-buffer ((client scheduler-client) agent-id)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((request-bytes (encode-poll-activity-buffer-request agent-id))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.scheduler.SchedulerService/PollActivityBuffer"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-poll-activity-buffer-response response-bytes)))))

(defgeneric purge-activity (client agent-id task-ids)
  (:documentation "Purge completed/failed tasks from the activity buffer.

Removes specified tasks from the agent's activity buffer to free up
space and avoid clutter.

Args:
  client: The scheduler-client instance.
  agent-id: Agent whose activity to purge.
  task-ids: List of task IDs to remove.

Returns:
  Purge response plist with :purged (number of tasks purged).

Signals:
  RPC-ERROR: If purge fails.

Example:
  (purge-activity client \"agent-1\" '(\"task-123\" \"task-124\"))
  => (:purged 2)"))

(defmethod purge-activity ((client scheduler-client) agent-id task-ids)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((request-bytes (encode-purge-activity-request agent-id task-ids))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.scheduler.SchedulerService/PurgeActivity"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-purge-activity-response response-bytes)))))
