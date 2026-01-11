# Common Lisp Orchestrator: Technical Gotchas & Hard Lessons

**Companion to:** IMPLEMENTATION_REALITY_CHECK.md
**Purpose:** Concrete technical problems you'll hit, not just time estimates

---

## 1. gRPC Integration: The Real Showstopper

### 1.1 Why `grpc-common-lisp` Won't Work (If It Doesn't)

The proposal lists grpc-common-lisp as "available" but it's effectively abandoned. When you try:

```bash
$ sbcl
* (ql:quickload :grpc-common-lisp)
;; Error: unknown system "grpc-common-lisp"
;; Check the tutorial and documentation

$ (ql:system-apropos "grpc")
;; No matching system
```

**What you find:**
- Fork on GitHub last updated: 2021
- Depends on old gRPC library (1.30.x)
- No support for proto3 or recent protobuf
- Doesn't handle streaming (crucial for heartbeats)
- Tries to use asynchronous I/O with bordeaux-threads (mismatch)

### 1.2 The Custom gRPC Build: Hidden Costs

If you decide to build it yourself, you must:

**Part 1: HTTP/2 Transport (2-3 weeks)**
```lisp
;; You need to send HTTP/2 SETTINGS frames
;; Lisp has: usocket, cl-async (async), (salza2 for gzip)
;; Missing: HTTP/2 implementation library

;; Option A: Wrap grpc-go CLI tool (hacky, slow)
;; Option B: Use CL-HTTP2 (unmaintained)
;; Option C: Build HTTP/2 parser yourself (madness)

;; Example nightmare:
(defun send-grpc-request (service method payload)
  ;; Must manually construct:
  ;; - HTTP/2 SETTINGS frame
  ;; - Pseudo-headers (:method, :path, etc)
  ;; - Compressed payload (gzip)
  ;; - Length-prefixed protobuf message
  ;; Each wrong detail = silent failure or wrong error
)
```

**Part 2: Protocol Buffers (1-2 weeks)**
```lisp
;; Must parse .proto files and generate Lisp stubs
;; Options:
;; - cl-protobufs: Semi-working, limited to proto2
;; - protoc plugin: Write Protoc plugin in Lisp (existential nightmare)
;; - Manual stubs: Generate once, maintain by hand (error-prone)

;; If sw4rm.proto changes, you must regenerate
(defun compile-proto ()
  ;; Expects protoc binary + Lisp plugin
  ;; Protoc plugins are C++ (hard to write in Lisp)
  ;; Most Lisp projects skip this and hand-maintain stubs
)
```

**Part 3: Async Message Handling (2-3 weeks)**
```lisp
;; gRPC uses streaming (server pushes)
;; Lisp's bordeaux-threads is thread-based, not async
;; Mismatch: Python async def → Lisp threads

;; Example: Heartbeat stream from Python
(defun heartbeat-stream-handler (channel)
  ;; Must read variable-length messages from stream
  ;; Each message: 1-byte flag + 4-byte length + payload
  ;; Handle partial reads, keepalives, errors
  ;; bordeaux-threads will spawn thread per stream (heavyweight)
)

;; Reality:
;; - 100 concurrent swarms = 100+ threads
;; - Lisp thread startup cost: 1-10ms each
;; - Memory per thread: 50-100KB
;; - Total: 5-10MB just for threads
;; - Thread pool management adds complexity
```

**Total custom gRPC cost: 6-8 weeks, not "Medium"**

### 1.3 Protobuf Serialization Gotchas

The proposal shows envelope serialization, but it glosses over edge cases:

```lisp
;; Case 1: Null fields in proto
(defstruct cross-swarm-envelope
  (correlation-id nil :type (or null string)))

;; When serializing to proto3:
;; - Null string becomes empty string ""
;; - When deserializing: "" stays ""
;; - Is `(eq nil "")` in your hash table lookup? NO.
;; - Silent bug: Can't match response to request

;; Case 2: Integer overflow in hop-count
(defstruct cross-swarm-envelope
  (hop-count 0 :type fixnum))
;; Lisp fixnum ≠ proto int32
;; Lisp: Arbitrary precision (automatic bignum)
;; Proto: Wraps at 2^31-1
;; Envelope passes 100 hops → wraps negative → rejected

;; Case 3: Timestamp precision
(defstruct cross-swarm-envelope
  (created-at (get-universal-time) :type integer))
;; get-universal-time returns seconds since 1900
;; Proto uses milliseconds since 1970
;; Off by factor of 1000 + 70 years
;; Deadline checks fail mysteriously
```

**Testing needed:** Protobuf round-trip tests with 100+ edge cases. Cost: 1-2 weeks.

---

## 2. CLOS & MOP Footguns

### 2.1 Method Combination Surprise

The proposal shows `:around` methods for tracing:

```lisp
(defmethod route-envelope :around ((node swarm-tree) envelope)
  (let ((start-time (get-internal-real-time)))
    (log:debug "Routing ~A" (envelope-id envelope))
    (unwind-protect
        (call-next-method)
      (let ((duration ...))
        (record-metric ...)))))
```

**Gotcha 1: Order of method combination**

```lisp
(defmethod route-envelope ((node swarm-leaf) envelope)
  ;; Leaf implementation
)

(defmethod route-envelope ((node swarm-node) envelope)
  ;; Node implementation
)

(defmethod route-envelope :around ((node swarm-tree) envelope)
  ;; Tracing wrapper
  ;; This is a :around method on the base class
)

;; What happens when you call (route-envelope leaf-instance envelope)?
;; Correct answer: :around fires first, then route-envelope dispatches to leaf
;; Common wrong answer: Developers expect it to NOT fire (it's "just tracing")
;; Result: Metric recorded for EVERY call, even if method fails
;; Side effects happen even when handler catches error
;; Debugging nightmare: "Why are my metrics wrong?"
```

**Gotcha 2: CLOS slot access in multithreaded context**

```lisp
(defclass swarm-node (swarm-tree)
  ((children :accessor node-children
             :initform (make-hash-table :test 'equal))))

(defmethod register-child ((node swarm-node) child)
  ;; NOT thread-safe!
  (setf (gethash (swarm-id child) (node-children node)) child))

;; Race condition:
;; Thread A: reads hash-table size → 100
;; Thread B: adds 200 new children
;; Thread A: writes expecting size 100 → corruption
;; No error. Silent. Data loss.

;; Fix: Add BORDEAUX-THREADS:MAKE-LOCK, use WITH-LOCK
;; Cost: Forgot to add to proposal. Budget 2-3 days debugging.
```

**Gotcha 3: Method cache invalidation**

```lisp
;; You redefine a method:
(defmethod route-envelope ((node swarm-node) envelope)
  ;; ... old code ...
)

;; Hours later, you change it:
(defmethod route-envelope ((node swarm-node) envelope)
  ;; ... new code ...
)

;; SBCL might cache old method. You restart REPL and suddenly works.
;; In production (no REPL restarts), old behavior persists until:
;; - Process crashes
;; - Cache is invalidated manually
;; - Memory runs out and GC clears it

;; Fix: Use (clear-method-cache) or restart
;; Cost: 4-6 hours of "why doesn't my change work?" debugging
```

### 2.2 Slot Initialization Gotchas

```lisp
(defclass swarm-node (swarm-tree)
  ((routing-table :accessor routing-table
                  :initform (make-routing-table))))

;; PROBLEM: :initform is evaluated ONCE at class definition time
;; NOT at instance creation time

(setf node1 (make-instance 'swarm-node :id "n1"))
(setf node2 (make-instance 'swarm-node :id "n2"))

;; Both node1 and node2 share the SAME routing-table object!
(setf (gethash "child-a" (routing-table node1)) node-a)
;; Now routing-table of node2 ALSO has "child-a"
;; Silent data corruption: "Why did child-a appear in both nodes?"

;; Fix: Use :initform with a lambda
(defclass swarm-node (swarm-tree)
  ((routing-table :accessor routing-table
                  :initform (lambda () (make-routing-table)))))

;; WRONG. Initform doesn't accept lambdas. Must use :initfunction
;; But most Lisp books don't mention this clearly.
;; Cost: 2-3 hours debugging.
```

---

## 3. Conditions & Restarts: Not What You Think

### 3.1 Conditions Don't Stop Execution

The proposal shows sophisticated error handling with restarts:

```lisp
(handler-bind
    ((swarm-unreachable
       (lambda (c)
         (when (critical-swarm-p (unreachable-swarm-id c))
           (alert-ops-team c))
         (invoke-restart 'retry-with-backoff 10))))
  (route-to-swarm envelope target))
```

**Gotcha 1: handler-bind doesn't CATCH**

```lisp
;; Python equivalent
try:
    route_to_swarm(envelope, target)
except SwarmUnreachable as e:
    if is_critical(e.swarm_id):
        alert_ops(e)
    retry_with_backoff(10)

;; Lisp equivalent (what you think it does)
(handler-bind ((swarm-unreachable handler))
  (route-to-swarm envelope target))

;; What it ACTUALLY does:
;; 1. Set up handler in dynamic scope
;; 2. Call route-to-swarm
;; 3. If swarm-unreachable is signaled:
;;    a. Call handler WHILE unwinding
;;    b. Handler can invoke-restart
;;    c. If no restart, unwinding continues
;; 4. If route-to-swarm completes normally:
;;    a. Handler is ignored
;;    b. No error was signaled

;; DIFFERENCE:
;; - Python: catches all exceptions
;; - Lisp: handler only fires if condition is SIGNALED
;; - If route-to-swarm returns nil silently: handler never runs
;; - Code after handler-bind might receive nil (no error!)

;; Debugging nightmare:
(handler-bind ((swarm-unreachable ...))
  (let ((result (route-to-swarm envelope)))
    (unless result
      ;; Did swarm-unreachable fire? You don't know!
      ;; Was result nil because unreachable? Or because message was empty?
      ;; The error handler may or may not have run.
)))
```

**Gotcha 2: Restarts must be established by error site**

```lisp
(defun route-to-swarm (envelope target)
  (restart-case
      (let ((connection (get-swarm-connection target)))
        (unless connection
          (error 'swarm-unreachable :swarm-id target))
        ...)
    ;; Restarts defined here
    (retry-with-backoff (&optional (attempts 5))
      :report "Retry"
      (route-to-swarm envelope target))))

;; Caller expects to invoke restart:
(handler-bind ((swarm-unreachable
                 (lambda (c)
                   (invoke-restart 'retry-with-backoff 10))))
  (route-to-swarm envelope target))

;; GOTCHA: If caller calls a different function that calls route-to-swarm:
(defun deliver-to-all-swarms (envelopes targets)
  (dolist (target targets)
    (route-to-swarm envelope target)))  ;; NO restarts here!

;; Caller:
(handler-bind ((swarm-unreachable handler))
  (deliver-to-all-swarms envelopes targets))

;; What happens: Error fires, handler invokes restart
;; But restart was defined in route-to-swarm, not deliver-to-all-swarms
;; Restart searches up call stack for establishment point
;; What if dolist is in between? Restart might not be visible!
;; Or different restart is found (wrong one)

;; Debugging: "Why did my restart not fire?"
;; Answer: Restart wasn't in the right scope
;; Cost: 4-8 hours debugging conditions/restarts confusion
```

**Gotcha 3: Multiple handlers can interact badly**

```lisp
(handler-bind ((swarm-unreachable
                 (lambda (c)
                   (log:warn "Unreachable: ~A" c))))
  (handler-bind ((swarm-unreachable
                   (lambda (c)
                     (invoke-restart 'retry-with-backoff))))
    (route-to-swarm envelope target)))

;; Inner handler fires first
;; If it invokes restart, outer handler NEVER sees the error
;; If it doesn't, outer handler sees it
;; Nesting handlers = complex semantics
;; Easy to accidentally catch+hide errors
```

### 3.2 When to Use handler-bind vs. ignore-errors

```lisp
;; The proposal shows handler-bind for flow control
;; But you'll be tempted to use IGNORE-ERRORS instead:

(ignore-errors
  (route-to-swarm envelope target))
;; Returns nil if error, true if success
;; WRONG: Silently catches all errors, including bugs
;; Example:
;;   (ignore-errors (/ x 0))  ;; Returns nil, not error
;;   (ignore-errors (undefined-function))  ;; Hides bug!

;; Cost: 1-2 weeks of "my code silently fails" bugs
```

---

## 4. Reader Macros: Debugging Nightmare

The proposal touts reader macros:

```lisp
#E{:from agent-a :to agent-b :payload {:data 42}}
#X{:source-swarm frontend :target-swarm backend ...}
```

### 4.1 Reader Macro Scope

```lisp
;; In file A.lisp, you define reader macro:
(set-dispatch-macro-character #\# #\E #'envelope-reader)

;; In file B.lisp, you try to use it:
#E{:from a :to b}
;; Error: Reader macro not recognized

;; Why? Reader macros are READER state, not package state
;; They only exist in the current read session
;; Each file load is separate read session

;; Fix: Put reader macro definition in early-loaded file
;; But what file? How do you order loads?
;; Cost: 2-4 hours getting reader macros to work consistently
```

### 4.2 Reader Macro Conflicts

```lisp
;; You use #E for envelopes
;; Quicklisp library also uses #E for something else
;; When you load that library, #E changes meaning

;; Debugging: "Why does my code break after loading library X?"
;; Answer: Reader macro was shadowed
;; Cost: 4-6 hours detective work

;; Prevention: Namespace reader macros
;; But CL has no standard namespacing for reader syntax
;; You must resort to exotic syntax like #E{ or #E[
;; Or use ENABLE-READ-MACRO-SYNTAX (uncommon)
```

### 4.3 Can't Debug Reader Macros Easily

```lisp
#E{:from a :to b :payload {:nested {:deep {:data 42}}}}

;; Reader macro runs and builds object
;; If it fails, you see: "Reader error at line 42"
;; You don't see intermediate expansions

;; In Python/Rust:
(make-envelope :from "a" :to "b" :payload (dict "nested" (dict "data" 42)))

;; Easier to debug: Stack trace shows the nested call
```

---

## 5. Memory & GC: Production Surprises

### 5.1 Consing in Hot Paths

The proposal doesn't mention memory allocation. In orchestration, this matters:

```lisp
(defmethod route-envelope ((node swarm-node) envelope)
  ;; Every call creates new list
  (dolist (child (list-children node))
    (push (swarm-id node) (envelope-path envelope))))

;; If you handle 1000 envelopes/second:
;; Each creates list of 10-100 children
;; = 10,000-100,000 list cons cells per second
;; = ~100KB-1MB garbage per second
;; = GC pause every 1-2 seconds
;; = 50-200ms latency spikes
;; = Envelope timeouts

;; Fix: Pre-allocate vectors, minimize consing
;; Cost: 1-2 weeks performance debugging
```

### 5.2 GC Pause Variability

```lisp
;; SBCL's default GC is aggressive
;; Tuning requires deep knowledge:

(setf (sb-ext:bytes-consed-between-gcs) (* 50 1024 1024))
;; Too high: GC pauses > 500ms
;; Too low: GC runs constantly, CPU 100%

;; There's no magic number. Depends on:
;; - Heap size
;; - Workload patterns
;; - System RAM available
;; - CPU cores

;; You must benchmark and tune
;; Cost: 1-2 weeks GC tuning
```

### 5.3 Checkpoint Serialization Gotcha

The proposal shows:

```lisp
(defun save-orchestrator-checkpoint (path)
  (let ((state (capture-orchestrator-state *orchestrator*)))
    (cl-store:store state out)))
```

**Gotchas:**
```lisp
;; 1. Can't serialize function closures
(defvar *handler-fn* (lambda (x) (+ x 1)))
(cl-store:store *handler-fn* out)
;; Error: Can't serialize closure

;; 2. Can't serialize open file handles
;; 3. Can't serialize gRPC channel objects
;; 4. Can't serialize thread objects

;; Result: You can't checkpoint live system
;; Must pause all activity, serialize, resume
;; = Downtime during checkpoint

;; Fix: Serialize only data, not closures
;; = Manual serialization code
;; Cost: 2-3 weeks
```

---

## 6. Debugging: No Equivalent of Python's pdb

### 6.1 SLIME Debugging is Different

Python debugging:
```python
import pdb; pdb.set_trace()
```

Lisp debugging (with SLIME):
```lisp
(break "Debugging here")
;; Or set breakpoint in Emacs
;; Or (step (some-function))
```

**Gotchas:**
- Can't easily attach to running process
- Stack traces are less readable (MOP overhead)
- Macroexpansion errors are cryptic
- Reader errors are hard to trace

**Cost:** Your Python team will struggle. Budget 2-3 weeks for "why can't I find the bug?"

### 6.2 Cross-Language Debugging is Impossible

Lisp orchestrator crashes while handling Python envelope. Where's the bug?

- Lisp side: Can debug in SLIME
- Python side: Can debug in pdb
- Boundary: Black box
  - Is it serialization? Deserialization?
  - Is it network timeout?
  - Is the envelope corrupted?

**Cost:** Expect 20-30% of test time spent debugging boundary issues.

---

## 7. Docker & Deployment Gotchas

### 7.1 Quicklisp Caching Nightmare

```dockerfile
FROM debian:bookworm-slim
RUN sbcl --eval '(ql:quickload :sw4rm-orchestrator)' ...
```

**What happens:**
- First build: Downloads all deps from Quicklisp server (~10 min)
- Second build: Uses Quicklisp cache (~5 min)
- Third build with new dependency: Downloads again (~10 min)
- Quicklisp server times out: Build hangs for 20 minutes
- You add NEW dependency to local system.lisp: Cache invalidates, rebuilds

**Fix:**
```dockerfile
# Copy local quicklisp cache
COPY quicklisp /root/quicklisp
# Or use custom Quicklisp mirror
```

**Cost:** 1-2 weeks getting Docker caching right

### 7.2 SBCL Startup Variability

```bash
$ time sbcl --eval '(ql:quickload :sw4rm-orchestrator)' --quit
real	0m5.234s
user	0m4.891s
sys	0m0.343s

$ time sbcl --eval '(ql:quickload :sw4rm-orchestrator)' --quit
real	0m12.456s  # 2.4x slower!
```

Why? Disk cache, memory pressure, depends on system state.

**In Kubernetes:**
- Pod startup takes 5-15 seconds (unpredictable)
- Readiness probe times out waiting for orchestrator
- Liveness probe kills container
- Pod restart loop

**Fix:** Implement HTTP health endpoint that returns quickly

**Cost:** 1 week

---

## 8. Protobuf Compatibility: Version Mismatch Risk

The proposal assumes proto3 stays stable. It doesn't:

```protobuf
// v1: SW4RM protocol (current)
message CrossSwarmEnvelope {
  string id = 1;
  string correlation_id = 2;
  // ... fields ...
}

// v2: Someone adds field (common)
message CrossSwarmEnvelope {
  string id = 1;
  string correlation_id = 2;
  string trace_id = 3;  // NEW!
  // ...
}
```

**What happens:**
- Old Lisp orchestrator (v1) receives envelope from Python (v2)
- Lisp reads proto, ignores unknown field (correct proto behavior)
- Missing trace_id causes bug in observability
- Silent failure: spans don't link to envelope

**Lisp side:**
```lisp
(defstruct cross-swarm-envelope
  (id ... )
  (correlation-id ...)
  ;; No trace-id field
  ;; Lisp doesn't know it exists
)

;; When you deserialize:
(proto-to-envelope proto-obj)
;; Silently drops trace_id
;; No error, no warning
```

**Fix:** Add versioning, compatibility tests
**Cost:** 1-2 weeks

---

## Summary: Real "Gotcha Tax"

| Gotcha | Estimated Loss | When Discovered |
|--------|----------------|-----------------|
| gRPC custom build | +6-8 weeks | Week 4-6 |
| CLOS threading bugs | 2-3 days | Week 7-8 |
| Reader macro conflicts | 4-6 hours | Week 5 |
| GC pause tuning | 1-2 weeks | Week 10+ |
| Checkpoint serialization | 2-3 weeks | Week 11 |
| Docker Quicklisp caching | 1-2 weeks | Week 8 |
| Kubernetes startup | 1 week | Week 12+ |
| Protobuf versioning | 1-2 weeks | Post-launch |
| **TOTAL** | **+14-26 weeks** | **Distributed** |

These aren't sequential. They overlap. But collectively they explain why the 12-week proposal is unrealistic.

