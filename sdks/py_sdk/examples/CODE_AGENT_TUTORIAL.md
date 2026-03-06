# Code-Agent Tutorial: 3-Agent Code Review Swarm

A complete walkthrough of building a multi-agent code review pipeline using SW4RM's negotiation and handoff protocols.

## Architecture

```
                    +-----------+
                    |  Writer   |  1. Generate code
                    |  Agent    |─────────────────────┐
                    +-----------+                     │
                                                      ▼
                                              ┌──────────────┐
                                              │  Negotiation  │
                                              │    Room       │  2. Submit proposal
                                              └──────┬───────┘
                                                     │
                                    ┌────────────────┼────────────────┐
                                    ▼                                 ▼
                            +-----------+                     +-----------+
                            | Reviewer  |  3a. Vote           | Reviewer  |  3b. Vote
                            | (correct) |  (score+pass)       | (style)   |  (score+pass)
                            +-----------+                     +-----------+
                                    │                                 │
                                    └────────────────┬────────────────┘
                                                     ▼
                                              ┌──────────────┐
                                              │  Coordinator  │  4. Aggregate votes
                                              │  (threshold)  │     → APPROVED / REVISION
                                              └──────┬───────┘
                                                     │
                                          ┌──────────┴──────────┐
                                          ▼                     ▼
                                  +-----------+          +-----------+
                                  | Deployer  |          | Writer    |
                                  | Agent     |  5a.     | Agent     |  5b.
                                  | (handoff) |  Deploy  | (revise)  |  Feedback
                                  +-----------+          +-----------+
```

## SW4RM Concepts Used

| Concept | SDK Module | Purpose |
|---------|-----------|---------|
| Negotiation Room | `sw4rm.clients.negotiation_room` | Multi-reviewer voting with aggregation |
| Proposals | `sw4rm.negotiation_types.NegotiationProposal` | Submit code artifact for review |
| Votes | `sw4rm.negotiation_types.NegotiationVote` | Score, pass/fail, strengths/weaknesses |
| Aggregation | `sw4rm.negotiation_types.aggregate_votes()` | Weighted mean, std dev, consensus |
| Decisions | `sw4rm.negotiation_types.NegotiationDecision` | APPROVED / REVISION_REQUESTED |
| Handoff | `sw4rm.clients.handoff.HandoffClient` | Transfer work between agents |
| Context | `sw4rm.handoff.context.HandoffContext` | Serialize conversation history for handoff |

## Step-by-Step Walkthrough

### Step 1: Code Generation

The `WriterAgent` generates a fibonacci function. In production, this would call an LLM via your preferred provider.

### Step 2: Submit Proposal

The code is wrapped in a `NegotiationProposal` with `ArtifactType.CODE` and submitted to a negotiation room. The proposal names the requested critics (reviewers).

### Step 3: Code Review

Each `ReviewerAgent` inspects the code and submits a `NegotiationVote` with:
- **score** (0-10): overall quality rating
- **confidence** (0-1): reviewer's self-assessed confidence
- **passed**: binary pass/fail
- **strengths/weaknesses/recommendations**: structured feedback

### Step 4: Vote Aggregation

`aggregate_votes()` computes:
- Mean, min, max scores
- Confidence-weighted mean
- Standard deviation

The coordinator applies a policy: weighted mean >= 7.0 AND all reviewers passed.

### Step 5a: Handoff to Deployer (Approved)

If approved, a `HandoffRequest` transfers work to the deployer:
1. Build `HandoffContext` with full review history
2. `serialize_context()` encodes it as bytes
3. `request_handoff()` initiates the transfer
4. Deployer calls `accept_handoff()`, deserializes context, deploys
5. `complete_handoff()` closes the workflow

### Step 5b: Feedback Loop (Revision)

If revision is requested, the coordinator logs structured feedback for the writer to address in a future iteration.

## Running

```bash
cd sdks/py_sdk
python examples/code_agent_tutorial.py
```

No gRPC services required — runs entirely in-process with mock mode.

## Extending with a Real LLM

Replace the stubbed methods in each agent class:

```python
class WriterAgent:
    def generate(self, prompt: str) -> str:
        # Replace with your LLM call
        response = llm_client.complete(prompt)
        return response.text

class ReviewerAgent:
    def review(self, code: str) -> NegotiationVote:
        # Have the LLM produce structured feedback
        feedback = llm_client.complete(
            f"Review this code for {self.focus}:\n{code}"
        )
        return NegotiationVote(
            artifact_id=self.current_artifact_id,
            critic_id=self.agent_id,
            score=feedback.score,
            confidence=feedback.confidence,
            passed=feedback.score >= 6.0,
            strengths=feedback.strengths,
            weaknesses=feedback.weaknesses,
            recommendations=feedback.recommendations,
            negotiation_room_id=self.room_id,
        )
```

To connect to live SW4RM services, pass a gRPC channel to each client:

```python
import grpc
channel = grpc.insecure_channel("localhost:50051")
handoff_client = HandoffClient(channel=channel)
```
