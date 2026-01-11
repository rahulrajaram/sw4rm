# SW4RM Common Lisp Reference Services

Production-ready reference implementations of SW4RM coordination services in Common Lisp.

## Overview

This directory contains the Common Lisp implementations of the SW4RM reference services, equivalent to the Python reference-services. These services provide the infrastructure for multi-agent coordination:

| Service | Port | Description |
|---------|------|-------------|
| **Registry** | 50052 | Agent registration, heartbeat tracking, discovery |
| **Router** | 50051 | Message routing with queue-based delivery |
| **Scheduler** | 50053 | LLM-driven task orchestration |
| **Coordination** | 50060 | Handoff, Workflow, NegotiationRoom services |

## Protocol

All services use **JSON-over-TCP** with a 4-byte big-endian length prefix:

```
+----------+------------------+
| Length   | JSON Payload     |
| (4 bytes)| (variable)       |
+----------+------------------+
```

This differs from the Python/Rust/JS SDKs which use gRPC. The JSON-over-TCP protocol provides:
- No external protobuf dependencies
- Easy debugging with standard tools
- Native Common Lisp data serialization

## Quick Start

### Prerequisites

- SBCL (Steel Bank Common Lisp)
- Quicklisp installed at `~/quicklisp`

### Local Mode

```bash
# Start all services
./start_services.sh --local

# Stop all services
./stop_services.sh --local
```

### Docker Mode

```bash
# Build and start with docker-compose
./start_services.sh --docker

# Stop
./stop_services.sh --docker
```

## Directory Structure

```
reference-services/
├── hive/                           # Core coordination services
│   ├── registry-service.lisp       # Agent registration (~350 lines)
│   ├── router-service.lisp         # Message routing (~450 lines)
│   └── scheduler-service.lisp      # LLM orchestration (~700 lines)
│
├── coordination/                   # Advanced coordination services
│   ├── server.lisp                 # Unified coordination server
│   ├── handoff-service.lisp        # Agent-to-agent handoff (~350 lines)
│   ├── workflow-service.lisp       # DAG-based workflows (~450 lines)
│   └── negotiation-room-service.lisp # Multi-party voting (~500 lines)
│
├── docker/                         # Docker deployment
│   ├── docker-compose.yml          # Service orchestration
│   ├── Dockerfile.registry
│   ├── Dockerfile.router
│   ├── Dockerfile.scheduler
│   └── Dockerfile.coordination
│
├── start_services.sh               # Multi-mode launcher
├── stop_services.sh                # Service shutdown
└── README.md                       # This file
```

## Service APIs

### Registry Service (Port 50052)

```lisp
;; Request format: {:method "..." :params {...}}

;; Register an agent
{:method "register" :params {:agent-id "my-agent" :metadata {:type "worker"}}}

;; Heartbeat
{:method "heartbeat" :params {:agent-id "my-agent" :status "active"}}

;; Deregister
{:method "deregister" :params {:agent-id "my-agent"}}

;; List agents
{:method "list" :params {:status "active"}}  ; optional filter

;; Get specific agent
{:method "get" :params {:agent-id "my-agent"}}

;; Health check
{:method "health"}
```

### Router Service (Port 50051)

```lisp
;; Send a message
{:method "send" :params {:producer-id "agent-a" :consumer-id "agent-b"
                         :message-type "data" :payload {...}
                         :correlation-id "req-123"}}

;; Receive a message (blocking with timeout)
{:method "receive" :params {:agent-id "my-agent" :timeout 30}}

;; Stream incoming messages (continuous)
{:method "stream" :params {:agent-id "my-agent"}}

;; Get queue depth
{:method "depth" :params {:agent-id "my-agent"}}

;; List all queues
{:method "list"}
```

### Scheduler Service (Port 50053)

```lisp
;; Submit a task for orchestration
{:method "submit" :params {:session-id "session-1" :prompt "Build a web app"}}

;; Get session status
{:method "get" :params {:session-id "session-1"}}

;; List sessions
{:method "list" :params {:status "running"}}  ; optional filter

;; Cancel a session
{:method "cancel" :params {:session-id "session-1"}}

;; Report agent status (internal)
{:method "report" :params {:session-id "session-1" :agent-id "frontend"
                           :status "completed" :artifacts ["app.tsx"]}}
```

### Coordination Server (Port 50060)

All requests include a `:service` key to route to the appropriate sub-service:

#### Handoff Service

```lisp
;; Initiate handoff
{:service "handoff" :method "initiate"
 :params {:source-agent "agent-a" :target-agent "agent-b"
          :context {:conversation-id "conv-1"} :timeout 300}}

;; Complete handoff
{:service "handoff" :method "complete"
 :params {:handoff-id "handoff-123" :result {...}}}

;; Cancel handoff
{:service "handoff" :method "cancel"
 :params {:handoff-id "handoff-123" :reason "timeout"}}
```

#### Workflow Service

```lisp
;; Create workflow
{:service "workflow" :method "create"
 :params {:workflow-id "wf-1" :name "Data Pipeline"}}

;; Add step
{:service "workflow" :method "add-step"
 :params {:workflow-id "wf-1" :step-id "extract" :agent-id "extractor"
          :task "Extract data from source" :dependencies []}}

;; Start workflow
{:service "workflow" :method "start"
 :params {:workflow-id "wf-1"}}

;; Complete step
{:service "workflow" :method "complete-step"
 :params {:workflow-id "wf-1" :step-id "extract" :output {...}}}

;; Get ready steps (steps with all dependencies satisfied)
{:service "workflow" :method "ready-steps"
 :params {:workflow-id "wf-1"}}
```

#### Negotiation Room Service

```lisp
;; Create room
{:service "negotiation" :method "create"
 :params {:room-id "room-1" :name "API Design" :quorum 0.5}}

;; Join room
{:service "negotiation" :method "join"
 :params {:room-id "room-1" :participant-id "agent-a"}}

;; Submit proposal
{:service "negotiation" :method "propose"
 :params {:room-id "room-1" :proposer-id "agent-a"
          :title "Use REST API" :description "..."}}

;; Vote
{:service "negotiation" :method "vote"
 :params {:room-id "room-1" :voter-id "agent-b"
          :value "approve" :reason "Good approach"}}

;; Get consensus
{:service "negotiation" :method "consensus"
 :params {:room-id "room-1"}}
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REGISTRY_PORT` | 50052 | Registry service port |
| `ROUTER_PORT` | 50051 | Router service port |
| `SCHEDULER_PORT` | 50053 | Scheduler service port |
| `COORDINATION_PORT` | 50060 | Coordination server port |
| `REGISTRY_HOST` | localhost | Registry host (for scheduler) |
| `ROUTER_HOST` | localhost | Router host (for scheduler) |

## Client Example

```lisp
(defun send-request (host port request)
  "Send a request to a service and return the response."
  (let* ((socket (usocket:socket-connect host port
                   :element-type '(unsigned-byte 8)))
         (stream (usocket:socket-stream socket)))
    (unwind-protect
         (progn
           ;; Encode and send
           (let* ((json (cl-json:encode-json-to-string request))
                  (bytes (babel:string-to-octets json :encoding :utf-8))
                  (len (length bytes))
                  (header (make-array 4 :element-type '(unsigned-byte 8))))
             (setf (aref header 0) (ldb (byte 8 24) len))
             (setf (aref header 1) (ldb (byte 8 16) len))
             (setf (aref header 2) (ldb (byte 8 8) len))
             (setf (aref header 3) (ldb (byte 8 0) len))
             (write-sequence header stream)
             (write-sequence bytes stream)
             (force-output stream))
           ;; Read response
           (let ((header (make-array 4 :element-type '(unsigned-byte 8))))
             (read-sequence header stream)
             (let* ((len (+ (ash (aref header 0) 24)
                           (ash (aref header 1) 16)
                           (ash (aref header 2) 8)
                           (aref header 3)))
                    (payload (make-array len :element-type '(unsigned-byte 8))))
               (read-sequence payload stream)
               (cl-json:decode-json-from-string
                (babel:octets-to-string payload :encoding :utf-8)))))
      (usocket:socket-close socket))))

;; Example: Register an agent
(send-request "localhost" 50052
  '((:method . "register")
    (:params . ((:agent-id . "my-agent")
                (:metadata . ((:type . "worker")))))))
```

## Comparison with Python SDK

| Feature | Python SDK | Common Lisp SDK |
|---------|------------|-----------------|
| Protocol | gRPC | JSON-over-TCP |
| Threading | asyncio | bordeaux-threads |
| Serialization | Protobuf | JSON (cl-json) |
| Signal handling | signal module | SBCL sb-sys |
| State management | Dict + asyncio.Lock | Hash-table + bt:lock |
| Background tasks | asyncio tasks | bt:make-thread |

### Why JSON-over-TCP?

1. **No gRPC dependency**: The Common Lisp gRPC ecosystem is less mature
2. **Easier debugging**: JSON messages are human-readable
3. **Native integration**: Works naturally with CL's data structures
4. **Simpler deployment**: No protobuf compilation step

## Testing

```bash
# Run individual service tests
sbcl --load ~/quicklisp/setup.lisp \
     --load hive/registry-service.lisp \
     --eval '(registry-service:start-server :port 50052)'

# In another terminal, test with netcat
echo '{"method":"health"}' | nc localhost 50052
```

## License

Apache-2.0 License

---

*Part of the SW4RM Common Lisp Orchestrator SDK v0.6.0*
