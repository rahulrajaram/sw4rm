# SW4RM Common Lisp SDK - Package Quick Reference

Quick lookup guide for developers using the package definitions.

## Package Hierarchy

```
:sw4rm-orchestrator (main - re-exports everything)
  ├── :sw4rm-orchestrator.errors      (condition system)
  ├── :sw4rm-orchestrator.tree        (SwarmTree ADT)
  ├── :sw4rm-orchestrator.envelope    (message structure)
  ├── :sw4rm-orchestrator.routing     (routing algorithms)
  ├── :sw4rm-orchestrator.coordination (sync primitives)
  ├── :sw4rm-orchestrator.grpc        (Python bridge)
  └── :sw4rm-orchestrator.persistence (checkpointing)
```

## Most-Used Symbols by Task

### I want to create a tree

```lisp
(in-package :sw4rm-orchestrator)

;; Create root
(defparameter *root* (make-instance 'swarm-node :id "root"))

;; Add Python leaf
(let ((leaf (make-instance 'swarm-leaf
              :id "leaf-a"
              :host "localhost"
              :port 50051)))
  (register-child *root* leaf))
```

**Symbols needed:**
- `swarm-node` - class
- `swarm-leaf` - class
- `register-child` - function
- `make-instance` - standard (from `:cl`)

---

### I want to route a message

```lisp
(let ((envelope (make-cross-swarm-envelope
                  :source-swarm "frontend"
                  :target-swarm "backend"
                  :sender "ui-agent"
                  :recipient "api-agent"
                  :payload '(:event "click"))))
  (route-envelope *root* envelope))
```

**Symbols needed:**
- `make-cross-swarm-envelope` - constructor
- `route-envelope` - generic function

---

### I want to handle routing failure

```lisp
(handler-bind
    ((swarm-unreachable
       (lambda (c)
         (format t "Swarm ~A unreachable~%"
                 (swarm-unreachable-swarm-id c))
         (invoke-restart 'retry-with-backoff 5))))
  (route-envelope *root* envelope))
```

**Symbols needed:**
- `swarm-unreachable` - condition type
- `swarm-unreachable-swarm-id` - accessor
- `invoke-restart` - standard (from `:cl`)

---

### I want to synchronize across swarms

```lisp
;; Create barrier
(let ((barrier (create-barrier '("leaf-a" "leaf-b" "leaf-c"))))
  ;; Tell each to arrive
  (dolist (id (barrier-participants barrier))
    (route-envelope *root*
      (make-envelope :target-swarm id :payload barrier)))
  ;; Wait for all
  (barrier-wait barrier)
  ;; Process results
  ...)
```

**Symbols needed:**
- `create-barrier` - constructor
- `barrier-participants` - accessor
- `barrier-wait` - function

---

### I want to connect to a Python leaf

```lisp
(let ((client (make-instance 'leaf-grpc-client
                :swarm-id "leaf-a"
                :host "localhost"
                :port 50051)))
  (connect client)
  (deliver-envelope client envelope)
  (disconnect client))
```

**Symbols needed:**
- `leaf-grpc-client` - class
- `connect` - generic function
- `disconnect` - generic function
- `deliver-envelope` - generic function

---

### I want to save state

```lisp
(save-orchestrator-checkpoint "/var/sw4rm/checkpoint.bin")
```

**Symbols needed:**
- `save-orchestrator-checkpoint` - function

---

### I want to restore state

```lisp
(restore-from-checkpoint "/var/sw4rm/checkpoint.bin")
```

**Symbols needed:**
- `restore-from-checkpoint` - function

---

## Import Strategies

### Strategy 1: Use main package (recommended for scripts)

```lisp
(in-package :sw4rm-orchestrator)
;; Everything is available: swarm-node, route-envelope, etc.
```

### Strategy 2: Import specific package

```lisp
(defpackage :my-app
  (:use :cl)
  (:import-from :sw4rm-orchestrator
   #:swarm-node
   #:route-envelope
   #:make-cross-swarm-envelope))
```

### Strategy 3: Qualified imports

```lisp
(defpackage :my-app
  (:use :cl)
  (:import-from :sw4rm-orchestrator.tree
   #:swarm-node
   #:route-envelope)
  (:import-from :sw4rm-orchestrator.envelope
   #:make-cross-swarm-envelope))
```

### Strategy 4: Prefix all (rarely needed)

```lisp
(defpackage :my-app
  (:use :cl)
  (:import-from :sw4rm-orchestrator.tree #:route-envelope))

(sw4rm-orchestrator.tree:route-envelope root envelope)
```

---

## Package Dependencies

```
:sw4rm-orchestrator.errors
  └─ :cl (standard library)

:sw4rm-orchestrator.tree
  └─ :cl

:sw4rm-orchestrator.envelope
  └─ :cl

:sw4rm-orchestrator.routing
  └─ :cl
  └─ :sw4rm-orchestrator.tree
  └─ :sw4rm-orchestrator.envelope

:sw4rm-orchestrator.coordination
  └─ :cl
  └─ :bordeaux-threads (eventually)

:sw4rm-orchestrator.grpc
  └─ :cl
  └─ :sw4rm-orchestrator.envelope
  └─ :cl-grpc (eventually)

:sw4rm-orchestrator.persistence
  └─ :cl
  └─ :sw4rm-orchestrator.tree
  └─ :cl-store (eventually)

:sw4rm-orchestrator (main)
  └─ all of above
```

---

## Symbol Categories

### Classes (OOP types)

| Class | Package | Purpose |
|-------|---------|---------|
| `swarm-tree` | `.tree` | Base class for tree nodes |
| `swarm-leaf` | `.tree` | Leaf wrapping Python sw4rm |
| `swarm-node` | `.tree` | Orchestrator node |
| `leaf-grpc-client` | `.grpc` | gRPC client |
| `barrier` | `.coordination` | Synchronization point |
| `shared-artifact-registry` | `.coordination` | Artifact store |
| `distributed-lease` | `.coordination` | Timeout lock |
| `distributed-semaphore` | `.coordination` | Resource counter |

### Structs (data)

| Struct | Package | Purpose |
|--------|---------|---------|
| `cross-swarm-envelope` | `.envelope` | Message with metadata |
| `routing-result` | `.routing` | Routing decision result |
| `orchestrator-state` | `.persistence` | Checkpoint snapshot |

### Condition Types (errors)

| Condition | Package | When signaled |
|-----------|---------|---------------|
| `sw4rm-error` | `.errors` | Base for all errors |
| `swarm-unreachable` | `.errors` | Target swarm down |
| `swarm-disconnected` | `.errors` | Connection lost |
| `routing-error` | `.errors` | Routing decision failed |
| `envelope-error` | `.errors` | Invalid envelope |
| `max-hops-exceeded` | `.errors` | Hop limit hit |
| `idempotent-delivery-error` | `.errors` | Duplicate delivery |

### Generic Functions (methods)

| Function | Package | Argument types |
|----------|---------|-----------------|
| `route-envelope` | `.tree` | node, envelope |
| `receive-envelope` | `.tree` | node, envelope |
| `register-child` | `.tree` | node, child |
| `connect` | `.grpc` | leaf-grpc-client |
| `disconnect` | `.grpc` | leaf-grpc-client |
| `deliver-envelope` | `.grpc` | leaf-grpc-client, envelope |

### Regular Functions (utilities)

| Function | Package | Returns |
|----------|---------|---------|
| `make-cross-swarm-envelope` | `.envelope` | envelope |
| `make-routing-result` | `.routing` | routing-result |
| `make-routing-table` | `.routing` | routing-table |
| `create-barrier` | `.coordination` | barrier |
| `save-orchestrator-checkpoint` | `.persistence` | nil |
| `restore-from-checkpoint` | `.persistence` | t/nil |

---

## Common Patterns

### Create and route

```lisp
(route-envelope
  *root*
  (make-cross-swarm-envelope
    :source-swarm "a"
    :target-swarm "b"
    :sender "agent-x"
    :recipient "agent-y"
    :payload data))
```

### Error handling with recovery

```lisp
(restart-case
    (route-envelope *root* envelope)
  (retry-with-backoff (&optional max-attempts)
    (loop repeat max-attempts
          when (retry-delivery envelope)
            return t))
  (route-to-alternative (alt-swarm)
    (route-envelope *root*
      (make-cross-swarm-envelope
        :source-swarm "a"
        :target-swarm alt-swarm
        :payload (envelope-payload envelope)))))
```

### Tree traversal

```lisp
;; Find all leaves under node
(subtree-nodes root)

;; Get depth
(node-depth root)

;; Get specific child
(get-child root "leaf-a")

;; List all children
(list-children root)
```

### State management

```lisp
;; Periodic checkpoint
(defun auto-checkpoint ()
  (loop
    (sleep 60)
    (save-orchestrator-checkpoint "/var/sw4rm/ck.bin")))

;; On startup
(defun startup ()
  (when (probe-file "/var/sw4rm/ck.bin")
    (restore-from-checkpoint "/var/sw4rm/ck.bin")))
```

---

## Checklist: Before Importing

Before using any symbol, ask:

- [ ] Is it exported from a package? (look at `:export` list)
- [ ] Do I have all its dependencies loaded? (check `:use` lists)
- [ ] Is it documented? (read the docstring)
- [ ] Are there examples? (check inline comments)
- [ ] What package should I `:use` or `:import-from`?

---

## Common Questions

**Q: Can I use both `:sw4rm-orchestrator` and `:sw4rm-orchestrator.tree`?**

A: No, `:sw4rm-orchestrator` already imports from `.tree`. Choose one. Use main package for apps, subpackages for libraries.

**Q: What's the difference between `swarm-id` and `swarm-unreachable-swarm-id`?**

A: Former is accessor on `swarm-tree` object. Latter is accessor on `swarm-unreachable` condition. Different types, different purposes.

**Q: How do I define my own tree node type?**

A: Subclass `swarm-tree` and specialize methods:

```lisp
(defclass my-node (swarm-tree)
  ((special-data :initarg :data)))

(defmethod route-envelope ((node my-node) envelope)
  ;; Custom logic
  )
```

**Q: What if I need a symbol not exported?**

A: Open an issue. But check the code first—internal symbols in implementation packages are intentionally hidden.

---

## Version Information

- **SDK Version:** 0.6.0
- **Spec Version:** 0.6.0
- **Last Updated:** 2026-01-10

---

## Related Documentation

- `PACKAGE_DEFINITIONS.md` - Detailed specification
- `/COMMON_LISP_PLAN.md` - Architecture and rationale
- `/documentation/protocol/spec.md` - Protocol specification
