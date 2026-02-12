;;;; workflow-orchestration.lisp -- DAG-based workflow orchestration example
;;;;
;;;; Demonstrates the SW4RM workflow orchestration subsystem:
;;;;   1. DAG-based workflow definition with node dependencies
;;;;   2. Topological sort and parallel execution planning
;;;;   3. Node execution with context passing
;;;;   4. Cycle detection in workflow graphs
;;;;   5. Workflow checkpoint and resumption
;;;;
;;;; Prerequisites:
;;;;   - Quicklisp installed (https://www.quicklisp.org/)
;;;;   - SW4RM SDK on ASDF load path
;;;;
;;;; Run:
;;;;   sbcl --load examples/workflow-orchestration.lisp

;;; ---------------------------------------------------------------------------
;;; Step 0: Ensure Quicklisp is available, then load the SDK
;;; ---------------------------------------------------------------------------

#-quicklisp
(let ((quicklisp-init (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file quicklisp-init)
    (load quicklisp-init)))

(ql:quickload :sw4rm-sdk)

(defpackage #:workflow-orchestration-example
  (:use #:cl #:sw4rm-sdk))

(in-package #:workflow-orchestration-example)

;;; ---------------------------------------------------------------------------
;;; Local Workflow Engine
;;; ---------------------------------------------------------------------------
;;; The CL SDK's workflow-client defines the gRPC interface. This local engine
;;; provides a functional DAG executor for demonstration, mirroring the Python
;;; SDK's WorkflowEngine.

(defstruct workflow-node
  "A node in a workflow DAG."
  (node-id "" :type string)
  (agent-id "" :type string)
  (trigger :automatic :type keyword)
  (input-mapping nil :type list)
  (output-mapping nil :type list))

(defstruct workflow-definition
  "A complete workflow DAG definition."
  (workflow-id "" :type string)
  (nodes nil :type list)            ; list of workflow-node
  (edges nil :type list)            ; list of (from . to) pairs
  (metadata nil :type list))

(defstruct node-state
  "Execution state of a single node."
  (node-id "" :type string)
  (status :pending :type keyword)   ; :pending :running :completed :failed
  (result nil)
  (error-msg nil :type (or null string))
  (started-at 0 :type integer)
  (completed-at 0 :type integer))

(defstruct workflow-state
  "Execution state of a complete workflow."
  (workflow-id "" :type string)
  (node-states (make-hash-table :test 'equal) :type hash-table)
  (shared-data (make-hash-table :test 'equal) :type hash-table))

;;; ---------------------------------------------------------------------------
;;; Workflow Builder
;;; ---------------------------------------------------------------------------

(defclass workflow-builder ()
  ((workflow-id :initarg :workflow-id :accessor builder-workflow-id)
   (nodes :initform nil :accessor builder-nodes)
   (edges :initform nil :accessor builder-edges)
   (input-mappings :initform (make-hash-table :test 'equal)
                   :accessor builder-input-mappings)
   (output-mappings :initform (make-hash-table :test 'equal)
                    :accessor builder-output-mappings)
   (metadata :initform nil :accessor builder-metadata))
  (:documentation "Fluent builder for workflow DAG construction."))

(defmethod add-node ((builder workflow-builder) node-id agent-id
                     &optional (trigger :automatic))
  "Add a node to the workflow."
  (push (make-workflow-node :node-id node-id :agent-id agent-id :trigger trigger)
        (builder-nodes builder))
  builder)

(defmethod add-edge ((builder workflow-builder) from-node to-node)
  "Add a dependency edge: TO-NODE depends on FROM-NODE."
  (push (cons from-node to-node) (builder-edges builder))
  builder)

(defmethod add-fan-in ((builder workflow-builder) from-nodes to-node)
  "Add multiple dependency edges: TO-NODE depends on all FROM-NODES."
  (dolist (from from-nodes)
    (add-edge builder from to-node))
  builder)

(defmethod set-input-mapping ((builder workflow-builder) node-id mapping)
  "Set input mapping for a node."
  (setf (gethash node-id (builder-input-mappings builder)) mapping)
  builder)

(defmethod set-output-mapping ((builder workflow-builder) node-id mapping)
  "Set output mapping for a node."
  (setf (gethash node-id (builder-output-mappings builder)) mapping)
  builder)

(defmethod set-metadata ((builder workflow-builder) metadata)
  "Set workflow metadata."
  (setf (builder-metadata builder) metadata)
  builder)

;;; ---------------------------------------------------------------------------
;;; Graph Utilities
;;; ---------------------------------------------------------------------------

(defun get-dependencies (node-id edges)
  "Get the list of nodes that NODE-ID depends on."
  (mapcar #'car
          (remove-if-not (lambda (edge) (string= (cdr edge) node-id)) edges)))

(defun get-dependents (node-id edges)
  "Get the list of nodes that depend on NODE-ID."
  (mapcar #'cdr
          (remove-if-not (lambda (edge) (string= (car edge) node-id)) edges)))

(defun detect-cycle (nodes edges)
  "Detect cycles in the DAG using Kahn's algorithm.
Returns NIL if no cycle, or a descriptive error string if cycle found."
  (let ((in-degree (make-hash-table :test 'equal))
        (adj (make-hash-table :test 'equal))
        (queue nil)
        (visited-count 0))

    ;; Initialize
    (dolist (node nodes)
      (let ((nid (workflow-node-node-id node)))
        (setf (gethash nid in-degree) 0)
        (setf (gethash nid adj) nil)))

    ;; Build adjacency and in-degree
    (dolist (edge edges)
      (push (cdr edge) (gethash (car edge) adj))
      (incf (gethash (cdr edge) in-degree)))

    ;; Start with zero in-degree nodes
    (maphash (lambda (nid degree)
               (when (zerop degree)
                 (push nid queue)))
             in-degree)

    ;; Process
    (loop while queue do
      (let ((current (pop queue)))
        (incf visited-count)
        (dolist (neighbor (gethash current adj))
          (decf (gethash neighbor in-degree))
          (when (zerop (gethash neighbor in-degree))
            (push neighbor queue)))))

    ;; If we didn't visit all nodes, there's a cycle
    (if (< visited-count (length nodes))
        (format nil "Cycle detected: visited ~D of ~D nodes"
                visited-count (length nodes))
        nil)))

(defun topological-stages (nodes edges)
  "Compute execution stages (levels) via topological sort.
Returns a list of lists, where each inner list contains node-ids
that can execute in parallel."
  (let ((in-degree (make-hash-table :test 'equal))
        (adj (make-hash-table :test 'equal))
        (stages nil)
        (current-stage nil))

    ;; Initialize
    (dolist (node nodes)
      (let ((nid (workflow-node-node-id node)))
        (setf (gethash nid in-degree) 0)
        (setf (gethash nid adj) nil)))

    ;; Build adjacency and in-degree
    (dolist (edge edges)
      (push (cdr edge) (gethash (car edge) adj))
      (incf (gethash (cdr edge) in-degree)))

    ;; Iteratively extract zero-degree nodes as stages
    (loop
      (setf current-stage nil)
      (maphash (lambda (nid degree)
                 (when (zerop degree)
                   (push nid current-stage)))
               in-degree)

      (when (null current-stage)
        (return))

      ;; Remove processed nodes and update degrees
      (dolist (nid current-stage)
        (remhash nid in-degree)
        (dolist (neighbor (gethash nid adj))
          (when (gethash neighbor in-degree)
            (decf (gethash neighbor in-degree)))))

      (push (sort current-stage #'string<) stages))

    (nreverse stages)))

(defun get-root-nodes (nodes edges)
  "Get nodes with no dependencies (entry points)."
  (let ((node-ids (mapcar #'workflow-node-node-id nodes)))
    (remove-if (lambda (nid) (get-dependencies nid edges)) node-ids)))

(defun get-leaf-nodes (nodes edges)
  "Get nodes with no dependents (exit points)."
  (let ((node-ids (mapcar #'workflow-node-node-id nodes)))
    (remove-if (lambda (nid) (get-dependents nid edges)) node-ids)))

;;; ---------------------------------------------------------------------------
;;; Workflow Builder: Build and Validate
;;; ---------------------------------------------------------------------------

(defmethod build-workflow ((builder workflow-builder) &key (validate t))
  "Build the workflow definition, optionally validating the DAG."
  (let ((nodes (reverse (builder-nodes builder)))
        (edges (reverse (builder-edges builder))))

    ;; Apply mappings
    (dolist (node nodes)
      (let ((nid (workflow-node-node-id node)))
        (setf (workflow-node-input-mapping node)
              (gethash nid (builder-input-mappings builder)))
        (setf (workflow-node-output-mapping node)
              (gethash nid (builder-output-mappings builder)))))

    ;; Validate
    (when validate
      (let ((cycle-error (detect-cycle nodes edges)))
        (when cycle-error
          (error "WorkflowBuilderError: ~A" cycle-error))))

    (make-workflow-definition
     :workflow-id (builder-workflow-id builder)
     :nodes nodes
     :edges edges
     :metadata (builder-metadata builder))))

;;; ---------------------------------------------------------------------------
;;; Workflow Execution Engine
;;; ---------------------------------------------------------------------------

(defun execute-workflow (workflow executor &key initial-data)
  "Execute a workflow DAG using EXECUTOR function for each node.
EXECUTOR is called as (funcall executor node input-data) -> output-data.
Returns the final workflow-state."
  (let* ((nodes (workflow-definition-nodes workflow))
         (edges (workflow-definition-edges workflow))
         (stages (topological-stages nodes edges))
         (state (make-workflow-state
                 :workflow-id (workflow-definition-workflow-id workflow)))
         (shared (workflow-state-shared-data state))
         (node-map (make-hash-table :test 'equal)))

    ;; Index nodes by ID
    (dolist (node nodes)
      (setf (gethash (workflow-node-node-id node) node-map) node))

    ;; Initialize shared data
    (when initial-data
      (loop for (k v) on initial-data by #'cddr
            do (setf (gethash k shared) v)))

    ;; Execute stage by stage
    (dolist (stage stages)
      ;; In a real engine, nodes within a stage run in parallel.
      ;; Here we run them sequentially but note the parallelism opportunity.
      (when (> (length stage) 1)
        (format t "~&;;   [Engine] Parallel stage: ~A~%" stage))

      (dolist (node-id stage)
        (let* ((node (gethash node-id node-map))
               (ns (make-node-state :node-id node-id
                                    :status :running
                                    :started-at (get-universal-time)))
               ;; Build input from shared data via input mapping
               (input-mapping (workflow-node-input-mapping node))
               (input-data (make-hash-table :test 'equal)))

          ;; Resolve input mapping
          (loop for (local-key shared-key) on input-mapping by #'cddr
                do (setf (gethash local-key input-data)
                         (gethash shared-key shared)))

          ;; Execute
          (format t "~&;; Executing node: ~A (agent: ~A)~%"
                  node-id (workflow-node-agent-id node))
          (handler-case
              (let ((output (funcall executor node input-data)))
                ;; Apply output mapping to shared data
                (let ((output-mapping (workflow-node-output-mapping node)))
                  (loop for (local-key shared-key) on output-mapping by #'cddr
                        do (setf (gethash shared-key shared)
                                 (gethash local-key output))))

                (setf (node-state-status ns) :completed
                      (node-state-result ns) output
                      (node-state-completed-at ns) (get-universal-time)))
            (error (e)
              (setf (node-state-status ns) :failed
                    (node-state-error-msg ns) (princ-to-string e)
                    (node-state-completed-at ns) (get-universal-time))))

          (setf (gethash node-id (workflow-state-node-states state)) ns))))

    state))

;;; ---------------------------------------------------------------------------
;;; Node Executor Functions
;;; ---------------------------------------------------------------------------

(defun fetch-data-executor (node input-data)
  "Executor for data fetching node."
  (let ((source (or (gethash :source input-data) "default_source")))
    (format t ";;   [Fetch] Fetching data from '~A'...~%" source)
    (sleep 0.05)
    (let ((data (list :records '((:id 1 :value 100 :category "A")
                                 (:id 2 :value 200 :category "B")
                                 (:id 3 :value 150 :category "A")
                                 (:id 4 :value 300 :category "C"))
                      :fetch-timestamp (get-universal-time)
                      :source source))
          (output (make-hash-table :test 'equal)))
      (format t ";;   [Fetch] Retrieved ~D records~%"
              (length (getf data :records)))
      (setf (gethash :fetched-data output) data)
      output)))

(defun validate-data-executor (node input-data)
  "Executor for data validation node."
  (let* ((data (gethash :data input-data))
         (records (getf data :records))
         (output (make-hash-table :test 'equal)))
    (format t ";;   [Validate] Validating ~D records...~%" (length records))
    (sleep 0.02)
    (let* ((valid (remove-if-not
                   (lambda (r)
                     (and (plusp (getf r :value))
                          (getf r :category)))
                   records))
           (invalid (set-difference records valid))
           (result (list :valid-count (length valid)
                         :invalid-count (length invalid)
                         :valid-records valid
                         :validation-passed (zerop (length invalid)))))
      (format t ";;   [Validate] Valid: ~D, Invalid: ~D~%"
              (getf result :valid-count) (getf result :invalid-count))
      (setf (gethash :validation-result output) result)
      output)))

(defun transform-data-executor (node input-data)
  "Executor for data transformation node."
  (let* ((validation (gethash :validation input-data))
         (records (getf validation :valid-records))
         (aggregates (make-hash-table :test 'equal))
         (output (make-hash-table :test 'equal)))
    (format t ";;   [Transform] Transforming ~D records...~%" (length records))
    (sleep 0.03)
    ;; Aggregate by category
    (dolist (record records)
      (let* ((cat (getf record :category))
             (val (getf record :value))
             (existing (gethash cat aggregates)))
        (if existing
            (setf (gethash cat aggregates)
                  (list :count (1+ (getf existing :count))
                        :total (+ (getf existing :total) val)))
            (setf (gethash cat aggregates)
                  (list :count 1 :total val)))))
    ;; Calculate averages
    (maphash (lambda (cat stats)
               (setf (gethash cat aggregates)
                     (append stats
                             (list :average (/ (float (getf stats :total))
                                               (getf stats :count))))))
             aggregates)
    (format t ";;   [Transform] Created ~D category aggregates~%"
            (hash-table-count aggregates))
    (setf (gethash :transformed-data output) aggregates)
    output))

(defun enrich-data-executor (node input-data)
  "Executor for data enrichment node (runs in parallel with transform)."
  (let* ((validation (gethash :validation input-data))
         (records (getf validation :valid-records))
         (output (make-hash-table :test 'equal)))
    (format t ";;   [Enrich] Enriching ~D records with metadata...~%" (length records))
    (sleep 0.04)
    (let ((enrichment (list :category-labels '(("A" . "High Priority")
                                               ("B" . "Medium Priority")
                                               ("C" . "Low Priority"))
                            :data-quality-score 0.95
                            :enrichment-source "metadata-service")))
      (format t ";;   [Enrich] Added labels for ~D categories~%"
              (length (getf enrichment :category-labels)))
      (setf (gethash :enrichment-data output) enrichment)
      output)))

(defun merge-results-executor (node input-data)
  "Executor for merging results from parallel nodes."
  (let* ((transformed (gethash :transformed input-data))
         (enrichment (gethash :enrichment input-data))
         (labels (getf enrichment :category-labels))
         (final (make-hash-table :test 'equal))
         (output (make-hash-table :test 'equal)))
    (format t ";;   [Merge] Merging transformed data with enrichment...~%")
    (sleep 0.02)
    (when transformed
      (maphash (lambda (cat stats)
                 (let ((label (or (cdr (assoc cat labels :test #'string=))
                                  "Unknown")))
                   (setf (gethash cat final)
                         (append stats (list :label label)))))
               transformed))
    (format t ";;   [Merge] Final result has ~D categories~%"
            (hash-table-count final))
    (setf (gethash :merged-result output)
          (list :final-data final
                :data-quality (getf enrichment :data-quality-score)
                :processed-at (get-universal-time)))
    output))

(defun store-results-executor (node input-data)
  "Executor for storing final results."
  (let ((merged (gethash :merged input-data))
        (output (make-hash-table :test 'equal)))
    (format t ";;   [Store] Storing results to database...~%")
    (sleep 0.02)
    (let ((result (list :storage-id (format nil "result-~D" (get-universal-time))
                        :records-stored (if (and merged (getf merged :final-data))
                                            (hash-table-count (getf merged :final-data))
                                            0)
                        :storage-timestamp (get-universal-time)
                        :status "success")))
      (format t ";;   [Store] Stored with ID: ~A~%" (getf result :storage-id))
      (setf (gethash :storage-confirmation output) result)
      output)))

;;; ---------------------------------------------------------------------------
;;; Dispatcher
;;; ---------------------------------------------------------------------------

(defvar *executors*
  (let ((table (make-hash-table :test 'equal)))
    (setf (gethash "fetch-agent" table) #'fetch-data-executor)
    (setf (gethash "validator-agent" table) #'validate-data-executor)
    (setf (gethash "transformer-agent" table) #'transform-data-executor)
    (setf (gethash "enricher-agent" table) #'enrich-data-executor)
    (setf (gethash "merger-agent" table) #'merge-results-executor)
    (setf (gethash "storage-agent" table) #'store-results-executor)
    table))

(defun dispatch-executor (node input-data)
  "Dispatch to the appropriate executor based on agent-id."
  (let ((exec-fn (gethash (workflow-node-agent-id node) *executors*)))
    (if exec-fn
        (funcall exec-fn node input-data)
        (progn
          (format t ";;   No executor for agent: ~A~%"
                  (workflow-node-agent-id node))
          (make-hash-table :test 'equal)))))

;;; ---------------------------------------------------------------------------
;;; Build and Run: Data Processing Pipeline
;;; ---------------------------------------------------------------------------
;;; Pipeline structure:
;;;   [fetch] --> [validate] --> [transform] ---|
;;;                                              |--> [merge] --> [store]
;;;                          --> [enrich]   -----|

(defun build-data-pipeline ()
  "Build a data processing pipeline workflow using the WorkflowBuilder."
  (format t "~&~%~A~%" (make-string 60 :initial-element #\=))
  (format t ";; BUILDING WORKFLOW: Data Processing Pipeline~%")
  (format t "~A~%" (make-string 60 :initial-element #\=))

  (let ((builder (make-instance 'workflow-builder
                                :workflow-id "data_pipeline_v1")))
    ;; Add nodes
    (add-node builder "fetch" "fetch-agent" :manual)
    (add-node builder "validate" "validator-agent")
    (add-node builder "transform" "transformer-agent")
    (add-node builder "enrich" "enricher-agent")
    (add-node builder "merge" "merger-agent")
    (add-node builder "store" "storage-agent")

    ;; Define dependencies
    (add-edge builder "fetch" "validate")
    (add-edge builder "validate" "transform")
    (add-edge builder "validate" "enrich")
    (add-fan-in builder '("transform" "enrich") "merge")
    (add-edge builder "merge" "store")

    ;; Set input/output mappings
    (set-input-mapping builder "fetch" (list :source :data-source))
    (set-output-mapping builder "fetch" (list :fetched-data :raw-data))
    (set-input-mapping builder "validate" (list :data :raw-data))
    (set-output-mapping builder "validate" (list :validation-result :validated-data))
    (set-input-mapping builder "transform" (list :validation :validated-data))
    (set-output-mapping builder "transform" (list :transformed-data :aggregates))
    (set-input-mapping builder "enrich" (list :validation :validated-data))
    (set-output-mapping builder "enrich" (list :enrichment-data :metadata))
    (set-input-mapping builder "merge" (list :transformed :aggregates
                                              :enrichment :metadata))
    (set-output-mapping builder "merge" (list :merged-result :final-output))
    (set-input-mapping builder "store" (list :merged :final-output))
    (set-output-mapping builder "store" (list :storage-confirmation :storage-status))

    ;; Set metadata
    (set-metadata builder
                  (list :description "Data pipeline with validation and enrichment"
                        :version "1.0.0"
                        :owner "data-team"))

    ;; Build and validate
    (let ((workflow (build-workflow builder :validate t)))
      (let ((nodes (workflow-definition-nodes workflow))
            (edges (workflow-definition-edges workflow)))
        (format t "~&~%;; Workflow created: ~A~%"
                (workflow-definition-workflow-id workflow))
        (format t ";;   Nodes: ~D~%" (length nodes))
        (format t ";;   Root nodes: ~A~%" (get-root-nodes nodes edges))
        (format t ";;   Leaf nodes: ~A~%" (get-leaf-nodes nodes edges)))
      workflow)))

(defun show-execution-plan (workflow)
  "Display the execution plan showing parallel stages."
  (let* ((nodes (workflow-definition-nodes workflow))
         (edges (workflow-definition-edges workflow))
         (stages (topological-stages nodes edges)))
    (format t "~&~%~A~%" (make-string 40 :initial-element #\-))
    (format t ";; EXECUTION PLAN (Parallel Stages)~%")
    (format t "~A~%" (make-string 40 :initial-element #\-))
    (loop for stage in stages
          for i from 1
          do (format t ";;   Stage ~D: [~{~A~^, ~}]~A~%"
                     i stage
                     (if (> (length stage) 1) " (parallel)" "")))))

(defun run-pipeline-workflow ()
  "Execute the data pipeline workflow."
  (let ((workflow (build-data-pipeline)))
    (show-execution-plan workflow)

    (format t "~&~%~A~%" (make-string 60 :initial-element #\=))
    (format t ";; EXECUTING WORKFLOW~%")
    (format t "~A~%" (make-string 60 :initial-element #\=))

    (let* ((start-time (get-internal-real-time))
           (state (execute-workflow workflow #'dispatch-executor
                                    :initial-data (list :data-source "production_database")))
           (elapsed (/ (float (- (get-internal-real-time) start-time))
                       internal-time-units-per-second)))

      ;; Display results
      (format t "~&~%~A~%" (make-string 60 :initial-element #\=))
      (format t ";; EXECUTION RESULTS~%")
      (format t "~A~%" (make-string 60 :initial-element #\=))
      (format t "~&~%;; Workflow: ~A~%" (workflow-state-workflow-id state))
      (format t ";; Execution time: ~,3Fs~%" elapsed)

      (let ((all-completed t))
        (format t "~&~%;; Node Results:~%")
        (maphash (lambda (node-id ns)
                   (format t ";;   ~A:~%" node-id)
                   (format t ";;     Status: ~A~%" (node-state-status ns))
                   (when (node-state-error-msg ns)
                     (format t ";;     Error: ~A~%" (node-state-error-msg ns)))
                   (unless (eq (node-state-status ns) :completed)
                     (setf all-completed nil)))
                 (workflow-state-node-states state))
        (format t "~&~%;; All completed: ~A~%" (if all-completed "yes" "no")))

      ;; Show final output
      (let ((storage (gethash :storage-status (workflow-state-shared-data state))))
        (when storage
          (format t "~&~%;; Final Output:~%")
          (format t ";;   Storage ID: ~A~%" (getf storage :storage-id))
          (format t ";;   Records stored: ~A~%" (getf storage :records-stored))
          (format t ";;   Status: ~A~%" (getf storage :status))))

      state)))

;;; ---------------------------------------------------------------------------
;;; Demo: Cycle Detection
;;; ---------------------------------------------------------------------------

(defun demo-cycle-detection ()
  "Demonstrate cycle detection in workflow DAGs."
  (format t "~&~%~A~%" (make-string 60 :initial-element #\=))
  (format t ";; DEMO: Cycle Detection~%")
  (format t "~A~%" (make-string 60 :initial-element #\=))

  (format t "~&~%;; Attempting to create a workflow with a cycle...~%")

  (let ((builder (make-instance 'workflow-builder
                                :workflow-id "cyclic_workflow")))
    (add-node builder "A" "agent-a")
    (add-node builder "B" "agent-b")
    (add-node builder "C" "agent-c")

    ;; Create cycle: A -> B -> C -> A
    (add-edge builder "A" "B")
    (add-edge builder "B" "C")
    (add-edge builder "C" "A")

    (handler-case
        (progn
          (build-workflow builder :validate t)
          (format t ";;   ERROR: Cycle was not detected!~%"))
      (error (e)
        (format t ";;   Caught expected error: ~A~%" e)))))

;;; ---------------------------------------------------------------------------
;;; Demo: Workflow Resumption
;;; ---------------------------------------------------------------------------

(defun demo-workflow-resumption ()
  "Demonstrate checkpoint and resumption of workflows."
  (format t "~&~%~A~%" (make-string 60 :initial-element #\=))
  (format t ";; DEMO: Workflow Resumption~%")
  (format t "~A~%" (make-string 60 :initial-element #\=))

  ;; Build a simple 3-step workflow
  (let ((builder (make-instance 'workflow-builder
                                :workflow-id "resumable_workflow")))
    (add-node builder "step1" "agent-1")
    (add-node builder "step2" "agent-2")
    (add-node builder "step3" "agent-3")
    (add-edge builder "step1" "step2")
    (add-edge builder "step2" "step3")

    (let* ((workflow (build-workflow builder))
           (call-count 0))

      ;; Create executor that counts calls
      (flet ((counting-executor (node input-data)
               (incf call-count)
               (format t ";;   Executing: ~A (call #~D)~%"
                       (workflow-node-node-id node) call-count)
               (let ((output (make-hash-table :test 'equal)))
                 (setf (gethash :output output)
                       (format nil "result_from_~A" (workflow-node-node-id node)))
                 output)))

        ;; Simulate partial execution (first 2 nodes completed)
        (format t "~&~%;; Simulating partial execution (step1, step2 completed)...~%")
        (let ((state (make-workflow-state :workflow-id "resumable_workflow")))
          (setf (gethash "step1" (workflow-state-node-states state))
                (make-node-state :node-id "step1" :status :completed))
          (setf (gethash "step2" (workflow-state-node-states state))
                (make-node-state :node-id "step2" :status :completed))

          (let ((completed nil))
            (maphash (lambda (k v)
                       (when (eq (node-state-status v) :completed)
                         (push k completed)))
                     (workflow-state-node-states state))
            (format t ";;   Completed nodes: ~A~%" completed))

          ;; Resume: only execute nodes not yet completed
          (format t "~&~%;; Resuming from checkpoint...~%")
          (setf call-count 0)

          ;; Find nodes that need execution
          (let ((nodes (workflow-definition-nodes workflow))
                (edges (workflow-definition-edges workflow))
                (stages (topological-stages
                         (workflow-definition-nodes workflow)
                         (workflow-definition-edges workflow))))
            (dolist (stage stages)
              (dolist (node-id stage)
                (let ((ns (gethash node-id (workflow-state-node-states state))))
                  (unless (and ns (eq (node-state-status ns) :completed))
                    ;; Execute this node
                    (let ((node (find node-id nodes
                                      :key #'workflow-node-node-id
                                      :test #'string=)))
                      (when node
                        (let ((output (counting-executor
                                       node (make-hash-table :test 'equal))))
                          (setf (gethash node-id (workflow-state-node-states state))
                                (make-node-state :node-id node-id
                                                 :status :completed))))))))))

          (format t "~&~%;; Resumption complete:~%")
          (format t ";;   Executor calls: ~D (only step3 should have been executed)~%"
                  call-count)
          (let ((all-done t))
            (maphash (lambda (k v)
                       (unless (eq (node-state-status v) :completed)
                         (setf all-done nil)))
                     (workflow-state-node-states state))
            (format t ";;   All completed: ~A~%" (if all-done "yes" "no"))))))))

;;; ---------------------------------------------------------------------------
;;; Main Entry Point
;;; ---------------------------------------------------------------------------

(format t "~&~%;; SW4RM Workflow Orchestration Example~%")
(format t "~A~%" (make-string 60 :initial-element #\=))
(format t ";; This demonstrates DAG-based workflow execution~%")

(run-pipeline-workflow)
(demo-cycle-detection)
(demo-workflow-resumption)

(format t "~&~%~A~%" (make-string 60 :initial-element #\=))
(format t ";; ALL WORKFLOW SCENARIOS COMPLETED~%")
(format t "~A~%" (make-string 60 :initial-element #\=))
(format t "~&~%;; Key takeaways:~%")
(format t ";;   1. Use workflow-builder for fluent DAG construction~%")
(format t ";;   2. Define dependencies with add-edge to control execution order~%")
(format t ";;   3. Nodes without dependencies can execute in parallel~%")
(format t ";;   4. Use input/output mapping for data flow between nodes~%")
(format t ";;   5. detect-cycle validates DAG structure (no cycles)~%")
(format t ";;   6. Resume from checkpoints by skipping completed nodes~%")
