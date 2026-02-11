---
template: home.html
title: SW4RM Agentic Protocol
hide: [toc]
---

<!-- Landing page content is provided by the home.html template (hero + Agentic Workflows). -->
SW4RM (pronounced "swarm") establishes the foundational protocol that enables agentic systems to operate with the same level of standardization and reliability as traditional distributed systems. Just as TCP provides reliable packet delivery and Linux provides process scheduling, SW4RM provides:


- **Standardized Message Protocols**: Guaranteed delivery semantics with explicit acknowledgment lifecycle
- **Agent Scheduling Framework**: Priority-based task ordering with cooperative preemption policies
- **Autonomous Decision-Making Support**: Built-in negotiation protocols enabling agents to resolve conflicts and make decisions independently without human intervention
- **Interoperability Standards**: Protocol-level compatibility enabling cross-framework agent communication
- **Production-Ready Infrastructure**: Enterprise-grade features including audit trails, state persistence, and security

SW4RM defines a standardized communication protocol for agentic systems, providing the architectural foundation for agent interoperability. The protocol establishes:


- **Service Discovery**: Registry-based agent discovery and capability advertisement
- **Message Envelope Format**: Structured message format with metadata and payload separation
- **Acknowledgment Protocol**: Reliable message delivery with confirmation semantics
- **Flow Control**: Backpressure mechanisms to prevent receiver overload
- **Error Handling**: Standardized error codes and recovery procedures

This protocol specification enables heterogeneous agent implementations to communicate using a common IPC layer, similar to how TCP/IP enables network interoperability across diverse systems.

SW4RM is an open agentic protocol for building resilient, distributed agentic systems that operate reliably in mission-critical enterprise environments. It defines services, message envelopes, and ACK lifecycle semantics that enable robust, stateful, message-driven architectures.

The protocol addresses the fundamental challenges inherent in distributed agentic systems — message loss, state corruption, coordination failures, autonomous decision-making, and operational complexity — while enabling developers to build truly autonomous agents that can negotiate, coordinate, and resolve conflicts independently without human intervention.

For a narrative deep dive into the platform's concepts, architecture, and positioning, see the [Overview](overview.md).

## Available SDKs

SW4RM provides official SDK implementations in multiple languages:

| SDK | Path | Description |
|-----|------|-------------|
| **Python** | [`sdks/py_sdk`](https://github.com/rahulrajaram/sw4rm/tree/master/sdks/py_sdk) | Full-featured reference implementation |
| **Rust** | [`sdks/rust_sdk`](https://github.com/rahulrajaram/sw4rm/tree/master/sdks/rust_sdk) | High-performance implementation |
| **JavaScript/TypeScript** | [`sdks/js_sdk`](https://github.com/rahulrajaram/sw4rm/tree/master/sdks/js_sdk) | Browser and Node.js support |
| **Common Lisp** | [`sdks/cl_sdk`](https://github.com/rahulrajaram/sw4rm/tree/master/sdks/cl_sdk) | Full peer SDK with idiomatic CL condition/restart patterns |

All SDKs implement SW4RM protocol v0.5.0 and maintain behavioral consistency through shared operational contracts.

For gRPC service client APIs exposed by these SDKs, see the [SDK Clients](clients/index.md) reference.

## Technical Architecture Overview

SW4RM implements a **process-based architecture** where agents are independent processes that communicate through a central scheduler. The architecture consists of three primary layers:

1. **Agent Runtime Layer**: Client-side execution environment containing business logic, SW4RM SDK runtime libraries, and local state management (Activity Buffer, Worktree State Manager, ACK Lifecycle Manager)
2. **Core Services Layer**: Essential distributed infrastructure services providing message routing with delivery guarantees, centralized agent registry and discovery, and distributed task scheduling with preemption support
3. **Extended Services Layer**: Optional specialized services enabling human-in-the-loop workflows, Git repository context management, external tool execution, multi-agent negotiation, reasoning analytics, audit logging, and third-party API integration

<div class="diagram-container">

```kroki-graphviz
digraph G {
  graph [rankdir=TB, nodesep=0.45, ranksep=0.8, splines=spline, compound=true, margin=6];
  node  [shape=box, style="rounded,filled", fillcolor="white", color="#1f2937", fontsize=12, fontname="Inter,Helvetica,Arial,sans-serif"];
  edge  [color="#1f2937", arrowsize=0.7];

  subgraph cluster_runtime {
    label="Agent Runtime Environment"; labelloc=t; labeljust=l; color="#e5e7eb"; style=rounded;
    A   [label="Agent Application Code"];
    SDK [label="SW4RM SDK Runtime", fillcolor="#f9fafb"];
    AB  [label="Activity Buffer"];
    WS  [label="Worktree State Manager"];
    AL  [label="ACK Lifecycle Manager"];
    A -> SDK;
    SDK -> AB; SDK -> WS; SDK -> AL;
  }

  subgraph cluster_core {
    label="Core Infrastructure Services"; labelloc=t; labeljust=l; color="#e5e7eb"; style=rounded;
    CORE [label="Core Services", shape=ellipse, fillcolor="#f3f4f6"];
    R   [label="Registry Service\nPort: 50052"];
    RT  [label="Router Service\nPort: 50051"];
    SCH [label="Scheduler Service\nPort: 50053"];
    CORE -> R; CORE -> RT; CORE -> SCH;
  }

  subgraph cluster_ext {
    label="Extended Capability Services"; labelloc=t; labeljust=l; color="#e5e7eb"; style=rounded;
    EXT [label="Extended Services", shape=ellipse, fillcolor="#f3f4f6"];
    H   [label="Human-in-the-Loop\nPort: 50061"];
    WT  [label="Worktree Management\nPort: 50062"];
    T   [label="Tool Execution\nPort: 50063"];
    N   [label="Negotiation\nPort: 50064"];
    RS  [label="Reasoning\nPort: 50065"];
    L   [label="Logging & Audit\nPort: 50066"];
    C   [label="External Connector\nPort: 50067"];
    EXT -> H; EXT -> WT; EXT -> T; EXT -> N; EXT -> RS; EXT -> L; EXT -> C;
  }

  subgraph cluster_persistence {
    label="Persistence Layer"; labelloc=t; labeljust=l; color="#e5e7eb"; style=rounded;
    DB  [shape=ellipse, label="State Database", fillcolor="#f9fafb"];
    FS  [shape=ellipse, label="File System", fillcolor="#f9fafb"];
    OBJ [shape=ellipse, label="Object Storage", fillcolor="#f9fafb"];
  }

  // primary integration
  SDK -> CORE;
  SDK -> EXT;

  // persistence relations
  R -> DB; RT -> DB; SCH -> DB;
  WS -> FS; AB -> FS; T -> OBJ;
}
```
</div>

For detailed architecture, design principles, deployment topology, and production implementation guidance, see the [Overview](overview.md).

## Quick Example: DevOps Pipeline Agent

```python
import grpc
import json

from sw4rm import constants as C
from sw4rm.ack_integration import ACKLifecycleManager, MessageProcessor
from sw4rm.activity_buffer import PersistentActivityBuffer
from sw4rm.clients.hitl import HitlClient
from sw4rm.clients.router import RouterClient
from sw4rm.clients.tool import ToolClient
from sw4rm.clients.worktree import WorktreeClient

router = RouterClient(grpc.insecure_channel("localhost:50051"))
hitl = HitlClient(grpc.insecure_channel("localhost:50060"))
tool = ToolClient(grpc.insecure_channel("localhost:50063"))
worktree = WorktreeClient(grpc.insecure_channel("localhost:50062"))

ack_manager = ACKLifecycleManager(
    router_client=router,
    activity_buffer=PersistentActivityBuffer(),
    agent_id="devops-pipeline",
)
processor = MessageProcessor(ack_manager)


def handle_deploy(envelope):
    payload = json.loads(envelope.get("payload", b"{}").decode())
    app = payload["application"]
    env = payload["environment"]

    if env == "production":
        decision = hitl.decide({
            "correlation_id": envelope.get("correlation_id", ""),
            "reason_type": "deployment",
            "context": payload,
            "options": ["approve", "reject"],
        })
        if not getattr(decision, "approved", False):
            return {"status": "rejected", "reason": getattr(decision, "reason", "")}

    worktree.bind("devops-pipeline", app["repo"], payload["worktree_id"])
    result = tool.call({
        "call_id": payload.get("call_id", "deploy-1"),
        "tool_name": "kubectl",
        "provider_id": "default",
        "args": ["apply", "-f", f"{app['k8s_path']}/{env}/"],
    })
    return {"status": "deployed", "tool_status": getattr(result, "status", "ok")}


processor.register_handler(C.DATA, handle_deploy)
```

**This 30-line agent provides:**

- Persistent state across restarts
- Human approval workflows
- Repository context management
- External tool execution
- Automatic error handling and retry
- Complete audit trail

<div class="grid cards" markdown>


-   :material-rocket-launch:{ .lg .middle } **Quick Start**

    ---

    Get up and running with your first agent in 5 minutes

    [:octicons-arrow-right-24: Get Started](quickstart/index.md)


-   :material-file-document-outline:{ .lg .middle } **Protocol Spec**

    ---

    Complete protocol specification and service architecture

    [:octicons-arrow-right-24: View Spec](protocol/index.md)


-   :material-code-braces:{ .lg .middle } **Examples**

    ---

    Comprehensive examples from basic to advanced agents

    [:octicons-arrow-right-24: View Examples](examples/index.md)


-   :material-architecture:{ .lg .middle } **Architecture**

    ---

    Deep dive into SDK architecture and design patterns

    [:octicons-arrow-right-24: Learn More](architecture/index.md)

</div>

<div class="grid" markdown>

<div markdown>
**New to SW4RM?**


Start with the quickstart guide to build your first agent in minutes.

[Get Started :material-arrow-right:](quickstart/index.md){ .md-button .md-button--primary }
</div>

<div markdown>
**Ready for Production?**


Explore advanced examples and production deployment guides.

[View Examples :material-arrow-right:](examples/index.md){ .md-button }
</div>

</div>
