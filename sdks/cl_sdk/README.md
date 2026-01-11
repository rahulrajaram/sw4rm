# SW4RM Common Lisp Orchestrator SDK

**Version:** 0.6.0
**Status:** Initial Implementation
**License:** Apache 2.0

---

## Overview

The SW4RM Common Lisp Orchestrator SDK provides a recursive tree orchestration layer for hierarchical SW4RM deployments. It enables composition of independent sw4rm instances into trees where inner nodes (orchestrators) coordinate child sw4rms via gRPC.

**Why Common Lisp?**

- **Powerful macro system**: Reader macros for custom envelope syntax
- **Sophisticated error handling**: Conditions/restarts for distributed failure recovery
- **CLOS + MOP**: Extensible agent type system and meta-programming
- **Image-based development**: Native support for stateful checkpointing
- **Hot code reload**: Update orchestration logic without downtime

---

## Architecture

### SwarmTree Algebra

```
SwarmTree = Leaf(SwarmInstance) | Node(Orchestrator, children: [SwarmTree])
```

This algebraic data type enables:
- Arbitrary nesting depth (practical systems use 2-4 levels)
- Independent sw4rm instances as composable units
- Hierarchical routing with path-based message delivery
- Failure isolation at sw4rm boundaries

### System Structure

```
┌─────────────────────────────────────────────────────────┐
│           Common Lisp Orchestrator (Root)               │
│  ┌────────────┐  ┌────────────┐  ┌──────────────────┐  │
│  │Tree Manager│  │Cross-Swarm │  │Checkpoint/Recovery│  │
│  │            │  │Router      │  │                  │  │
│  └──────┬─────┘  └─────┬──────┘  └──────────────────┘  │
│         │              │                                │
│  ┌──────┴──────────────┴────────────────────────────┐  │
│  │         gRPC Service Layer (cl-grpc)             │  │
│  └──────────────────┬───────────────────────────────┘  │
└─────────────────────┼──────────────────────────────────┘
                      │ gRPC
     ┌────────────────┼────────────────┐
     │                │                │
     ▼                ▼                ▼
┌─────────┐      ┌─────────┐      ┌─────────┐
│ Python  │      │ Python  │      │ Python  │
│ SW4RM   │      │ SW4RM   │      │ SW4RM   │
│ Leaf A  │      │ Leaf B  │      │ Leaf C  │
└─────────┘      └─────────┘      └─────────┘
```

---

## Installation

### Prerequisites

- **Common Lisp Implementation**: SBCL 2.0+ (recommended) or CCL
- **Quicklisp**: Common Lisp package manager
- **gRPC Libraries**: (to be integrated - see roadmap)

### Setup

```bash
# Clone repository
cd sigagent/sdks/cl_sdk

# Load in SBCL REPL
sbcl
```

```lisp
;; Load Quicklisp
(load "~/quicklisp/setup.lisp")

;; Load system
(ql:quickload :sw4rm-orchestrator)
```

---

## Quick Start

### Basic Usage

```lisp
(in-package :sw4rm-orchestrator)

;; Create root orchestrator
(defparameter *root* (make-instance 'swarm-node :id "root"))

;; Register Python leaves (assumes they're running on localhost)
(register-child *root*
  (make-instance 'swarm-leaf
    :id "frontend"
    :host "localhost"
    :port 50051))

(register-child *root*
  (make-instance 'swarm-leaf
    :id "backend"
    :host "localhost"
    :port 50052))

;; Route a message from frontend to backend
(route-envelope *root*
  (make-cross-swarm-envelope
    :source-swarm "frontend"
    :target-swarm "backend"
    :sender "ui-agent"
    :recipient "api-agent"
    :payload '(:event "user-login" :user-id 42)))

;; Check routing table
(print-routing-table (routing-table *root*))
```

### Running from Command Line

```bash
# Build standalone executable (SBCL only)
sbcl --eval '(ql:quickload :sw4rm-orchestrator)' \
     --eval '(sw4rm-orchestrator:build-image)' \
     --quit

# Run with configuration file
./sw4rm-orchestrator --config /etc/sw4rm/config.lisp

# Run with command-line arguments
./sw4rm-orchestrator --id root --port 50050 --log-level DEBUG

# Restore from checkpoint
./sw4rm-orchestrator --restore /var/sw4rm/checkpoints/latest.bin
```

---

## Directory Structure

```
cl_sdk/
├── sw4rm-orchestrator.asd     # ASDF system definition
├── README.md                   # This file
├── src/
│   ├── package.lisp            # Package definitions
│   ├── config.lisp             # Configuration management
│   ├── main.lisp               # Entry point
│   │
│   ├── tree/                   # SwarmTree ADT
│   │   ├── types.lisp          # Base types and protocols
│   │   ├── leaf.lisp           # Leaf node (Python wrapper)
│   │   ├── node.lisp           # Inner node (orchestrator)
│   │   └── traversal.lisp      # Tree operations
│   │
│   ├── envelope/               # Envelope handling
│   │   ├── types.lisp          # Envelope data types
│   │   ├── reader.lisp         # Reader macros (#E{}, #X{})
│   │   └── serialization.lisp  # Proto conversion
│   │
│   ├── routing/                # Cross-swarm routing
│   │   ├── table.lisp          # Routing table management
│   │   ├── strategies.lisp     # Routing strategies
│   │   └── router.lisp         # Core routing logic
│   │
│   ├── coordination/           # Cross-swarm coordination
│   │   ├── sync.lisp           # Barrier synchronization
│   │   ├── artifacts.lisp      # Shared artifact registry
│   │   └── negotiation.lisp    # Cross-swarm negotiation
│   │
│   ├── errors/                 # Error handling
│   │   ├── conditions.lisp     # Condition definitions
│   │   └── restarts.lisp       # Standard restarts
│   │
│   ├── grpc/                   # gRPC bridge to Python
│   │   ├── proto-compat.lisp   # Proto compatibility layer
│   │   ├── client.lisp         # gRPC client
│   │   └── server.lisp         # gRPC server
│   │
│   └── persistence/            # State management
│       ├── checkpoint.lisp     # Image checkpointing
│       └── wal.lisp            # Write-ahead logging
│
├── test/                       # Test suite
│   ├── package.lisp            # Test package definition
│   ├── tree-tests.lisp         # Tree tests
│   ├── routing-tests.lisp      # Routing tests
│   └── integration-tests.lisp  # Integration tests
│
└── examples/                   # Example usage
    ├── two-swarm.lisp          # Simple two-leaf example
    ├── microservices.lisp      # Microservices orchestration
    └── hierarchical.lisp       # Multi-level hierarchy
```

---

## Configuration

### Configuration File Format

Configuration files can be in Lisp or JSON format:

**Lisp format** (`config.lisp`):
```lisp
(("orchestrator.id" "my-orchestrator")
 ("grpc.host" "0.0.0.0")
 ("grpc.port" 50050)
 ("checkpoint.enabled" t)
 ("checkpoint.path" "/var/sw4rm/checkpoints")
 ("logging.level" "INFO"))
```

**JSON format** (`config.json`) - TODO:
```json
{
  "orchestrator.id": "my-orchestrator",
  "grpc.host": "0.0.0.0",
  "grpc.port": 50050,
  "checkpoint.enabled": true,
  "checkpoint.path": "/var/sw4rm/checkpoints",
  "logging.level": "INFO"
}
```

### Environment Variables

Configuration can also be loaded from environment variables with `SW4RM_` prefix:

```bash
export SW4RM_ORCHESTRATOR_ID=my-orchestrator
export SW4RM_GRPC_PORT=50050
export SW4RM_LOGGING_LEVEL=DEBUG
```

### Programmatic Configuration

```lisp
(set-config "grpc.port" 50051)
(set-config "logging.level" "DEBUG")
(get-config "orchestrator.id")
```

---

## Testing

### Running Tests

```lisp
;; Load test system
(ql:quickload :sw4rm-orchestrator/test)

;; Run all tests
(sw4rm-orchestrator.test:run-all-tests)

;; Run specific test suites
(sw4rm-orchestrator.test:run-tree-tests)
(sw4rm-orchestrator.test:run-routing-tests)
```

### Integration Tests

Integration tests require Python sw4rm instances running:

```bash
# Terminal 1: Start Python leaf A
cd ../py_sdk
python -m sw4rm.server --id leaf-a --port 50051

# Terminal 2: Start Python leaf B
python -m sw4rm.server --id leaf-b --port 50052

# Terminal 3: Run integration tests
sbcl --eval '(ql:quickload :sw4rm-orchestrator/test)' \
     --eval '(sw4rm-orchestrator.test:run-integration-tests)'
```

---

## Development

### REPL-Driven Development

Common Lisp's REPL provides powerful interactive development:

```lisp
;; Start orchestrator in REPL
(start-orchestrator :id "dev-orchestrator" :port 50050)

;; Register a leaf interactively
(register-child *orchestrator*
  (make-instance 'swarm-leaf :id "test-leaf" :host "localhost" :port 50051))

;; Test routing
(route-envelope *orchestrator*
  (make-cross-swarm-envelope
    :target-swarm "test-leaf"
    :payload '(:test t)))

;; Inspect state
(list-children *orchestrator*)
(print-routing-table (routing-table *orchestrator*))

;; Stop orchestrator
(stop-orchestrator)
```

### Hot Code Reload

```lisp
;; Recompile and reload a module without restarting
(ql:quickload :sw4rm-orchestrator :force t)
```

### Checkpointing and Recovery

```lisp
;; Save checkpoint manually
(save-orchestrator-checkpoint "/tmp/checkpoint.bin")

;; Restore from checkpoint
(restore-from-checkpoint "/tmp/checkpoint.bin")
```

---

## Implementation Status

### Phase 1: Foundation (Current)

- [x] Project structure and ASDF system definition
- [x] Package definitions
- [x] Configuration management
- [x] Main entry point and CLI argument parsing
- [ ] Core data types (tree, envelope, routing)
- [ ] Basic routing logic

### Phase 2: gRPC Bridge (Planned)

- [ ] Proto compilation for Common Lisp
- [ ] gRPC client for Python communication
- [ ] gRPC server for Python callbacks
- [ ] Envelope serialization/deserialization

### Phase 3: Integration Testing (Planned)

- [ ] Two-leaf integration test
- [ ] Failure scenario tests
- [ ] Performance benchmarks

### Phase 4: Advanced Features (Future)

- [ ] Checkpointing and recovery
- [ ] Nested orchestrators
- [ ] Cross-swarm coordination primitives

---

## Dependencies

### Required (ASDF system)

- `alexandria` - General utilities
- `bordeaux-threads` - Portable threading
- `lparallel` - Parallel execution
- `cl-json` - JSON serialization
- `cl-store` - Object persistence
- `log4cl` - Logging framework
- `fiveam` - Testing framework

### To Be Integrated

- `grpc` - gRPC client/server (needs integration or custom implementation)
- `cl-protobuf` - Protocol buffers (needs integration)

---

## Contributing

See main project [CONTRIBUTING.md](../../CONTRIBUTING.md) for guidelines.

For Common Lisp SDK specific contributions:

1. Follow existing code style (2-space indentation, docstrings for all public functions)
2. Write tests for new functionality
3. Update this README for new features
4. Run all tests before submitting PR

---

## License

Apache 2.0 - See [LICENSE](../../LICENSE) for details.

---

## Resources

- **Architecture Overview**: [COMMON_LISP_PLAN.md](../COMMON_LISP_PLAN.md)
- **Protocol Specification**: [spec.md](../../documentation/protocol/spec.md)
- **Common Lisp Resources**:
  - [SBCL Manual](http://www.sbcl.org/manual/)
  - [Quicklisp](https://www.quicklisp.org/)
  - [Practical Common Lisp](http://www.gigamonkeys.com/book/)
  - [Common Lisp Recipes](http://weitz.de/cl-recipes/)

---

## Contact

For questions about the Common Lisp SDK:
- File issues on GitHub
- See main project README for contact information
