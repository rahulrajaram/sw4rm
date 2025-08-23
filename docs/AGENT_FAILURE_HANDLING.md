1. Scope and Motivation

This document specifies failure handling, recovery, and adjudication semantics for a multi‑agent system composed of a Scheduler, application Agents (Frontend and Backend), a Verifier, a Router, and a Registry. It defines common failure classifications, protocol extensions, orchestration rules, and security procedures required to converge reliably when components encounter transient faults, terminal faults, or adversarial behavior.

1.1. Problem Statement

Multi‑agent workflows fail in non‑trivial ways. A Frontend may retry while a Backend cannot bind its port. A Backend may claim progress while remaining unavailable. Agents may return conflicting reports or act maliciously. Naïve “single‑probe then fix” loops misclassify conditions, waste attempts, and prematurely exhaust iteration budgets. The system must separate concerns: allow Agents to manage local retries, require precise classification and evidence, and require the Scheduler to adjudicate based on corroborated signals.

1.2. Goals

Define a protocol that: (a) standardizes failure classification; (b) delegates bounded retry to Agents; (c) requires explicit evidence; (d) introduces a Verifier for trust‑but‑verify; (e) prevents premature iteration exhaustion; and (f) enables quarantine of suspected compromises without blocking the entire workflow.

2. System Model

The system comprises the following principals connected through a Router. A Registry tracks liveness and heartbeats.

2.1. Entities

The Scheduler orchestrates phases (generate → run_probe → fix) and issues CONTROL commands. The Frontend Agent generates the client and probes the server via HTTP. The Backend Agent generates the service and probes its readiness via a local HTTP call. The Verifier independently measures externally observable behavior (e.g., curl) without relying on agent self‑reports. The Router enqueues and streams messages; the Registry maintains registration and TTL with protected roles (e.g., the Scheduler).

2.2. Protocol Baseline

Messages carry a MessageType (DATA, CONTROL, NOTIFICATION), a content_type with vendor versioning, a correlation_id for session scoping, and an idempotency token when commands must not be applied twice. All principals send NOTIFICATION reports with structured payloads after each budgeted action.

3. Failure Taxonomy

Classify outcomes along two axes: status and classification.

3.1. Status

Status is an observable outcome of a budgeted action: ok or error. An ok status signals successful completion of the requested action under the stated budget. An error status signals failure to meet the budget or detect the required condition.

3.2. Classification

Classification is a semantic judgment of the error cause:

• retryable: The agent expects success with additional attempts within a bounded backoff plan (e.g., transient 5xx, delayed startup).  
• terminal: The agent expects further attempts to fail without remediation (e.g., EADDRINUSE, missing dependency).  
• suspected_compromise: The agent’s behavior appears inconsistent or adversarial (e.g., mismatched self‑reports vs. Verifier, refusal to honor commands).

3.3. Examples

EADDRINUSE is terminal unless the agent detects a racily dying prior process and explicitly requests a brief delay. DNS resolution failures with intermittent connectivity are retryable. Persistent mismatches between claimed and observed ports are suspected_compromise.

4. Protocol Extensions

Extend report and command payloads to communicate budgets, classifications, and evidence.

4.1. Report v2

Define content_type application/vnd.sw4rm.agent.report+json;v=2 with the following fields:

• status: "ok" | "error".  
• classification: "retryable" | "terminal" | "suspected_compromise" (required when status="error").  
• advise: "retry" | "fix" | "give_up" (agent’s recommendation).  
• retry_plan: { attempts_used: int, max_attempts: int, backoff_ms: int } (present if classification="retryable").  
• next_not_before: RFC3339 timestamp indicating earliest safe retry time.  
• observed: { port?: int, url?: string } capturing externally relevant facts.  
• artifacts: { log_digest: string, transcript_ref?: string } for evidence linkage.  
• files?: [string] when generation or fix produced artifacts (optional).  
• schema_version: 2.

4.2. Command Extensions

Define command fields applicable to all CONTROL stages:

• deadline_ms: Absolute budget for the command’s end‑to‑end handling.  
• budget_ms: Time available for agent‑internal retries under backoff.  
• idempotency_token: Opaque string used to deduplicate command application.  
• params: Stage‑specific arguments (e.g., probe URL).  
• schema_version: Integer for payload evolution.

4.3. Correlation and Idempotency

The correlation_id scopes an orchestration session. The idempotency_token scopes command application at the agent and must be included in any resulting report for auditing. Agents must not execute the same idempotent command more than once.

5. Scheduler Orchestration Semantics

The Scheduler enforces phase‑gated decision making and prevents premature iteration exhaustion.

5.1. Phase Gating

Wait for both Frontend and Backend to submit a run_probe report or until a per‑phase deadline elapses. Do not issue fix commands based on a single report. Do not increment the Scheduler’s iteration counter until both reports arrive and the decision logic produces a new action (fix or success).

5.2. Probe Budgets

Issue run_probe with a budget_ms. Permit agents to perform bounded internal retries with backoff within the budget. Require agents to aggregate outcomes into a single report that includes retry_plan and next_not_before. Do not stream intermediate retry attempts as separate reports.

5.3. Decision Rules

Apply the following rules when both reports are available or the phase deadline expires:

• Both ok: Declare success for the phase.  
• Backend terminal, Frontend any: Prioritize a backend fix that brings the service to a known good state (e.g., honor PORT) and re‑probe afterward.  
• Frontend retryable while Backend terminal: Hold Frontend; do not spend its budget until Backend becomes available.  
• Conflicting or suspicious reports: Request a Verifier measurement. If disagreement persists, classify suspected_compromise and quarantine the offending agent.  
• No reports by deadline: Classify the missing agent’s outcome as error with classification retryable or suspected_compromise based on prior reliability.

5.4. Port Negotiation

Require the Backend to self‑select a free port and report it under observed.port. When the Backend reports a new port, re‑issue the Frontend run_probe with the updated URL regardless of its prior status. Do not prescribe a specific port in the command. Request a fix only to honor the PORT environment variable and to report the chosen port.

5.5. Iteration Accounting

Increment the Scheduler’s iteration counter only when it emits at least one fix command in response to a fully observed phase. Reset per‑phase probe receipt flags on each new fix cycle. Stop after a global maximum number of fix cycles or a global deadline.

6. Agent Responsibilities

Agents must implement budgets, classification, and evidence capture consistently.

6.1. Backend Agent

On run_probe, attempt to start the server once within the budget. Prefer port 8000 if free; otherwise self‑select the next free port. Bind to 0.0.0.0. Report observed.port and a log_digest. If bind fails with address‑in‑use, classify terminal and advise fix. On fix, apply changes to honor the PORT environment variable and to maintain the reporting contract.

6.2. Frontend Agent

On run_probe, issue an HTTP request to the Backend with bounded internal retries and exponential backoff within the budget. Classify network errors and HTTP status classes appropriately. Report advise and retry_plan. Do not run unbounded loops.

6.3. Logging and Artifacts

Include a log_digest that is a stable hash (e.g., SHA‑256) of normalized logs. Attach first and last N lines to aid diagnosis. Reference a transcript_ref when a longer artifact exists.

7. Verifier Agent

Introduce a Verifier that independently measures the externally observable behavior. On request, the Verifier performs a probe (e.g., curl) to a URL and returns a structured report with timings and status. The Scheduler uses the Verifier when agent self‑reports conflict or when trust scores drop below a threshold. The Verifier never consumes the session budget for generation or fix and avoids becoming a choke point.

8. Security and Quarantine

Define objective triggers for suspected_compromise and formalize quarantine procedures.

8.1. Triggers

Trigger suspected_compromise when: (a) the Verifier repeatedly contradicts an agent’s ok claims; (b) the agent refuses idempotent commands or ignores budgets; or (c) the agent reports inconsistent observed data (e.g., oscillating ports without corresponding fixes).

8.2. Quarantine Procedures

Emit a quarantine command to the offending agent and remove it from routing and scheduling decisions for the correlation_id. Record the event in the transcript with evidence references. Require manual review or regeneration before re‑admission.

9. Observability and Telemetry

Record every decision and its evidence.

9.1. Transcript

Persist a transcript per correlation_id that includes seeds, commands (with budgets and idempotency tokens), reports (with classification), Verifier outcomes, and decisions. Use correlation_id and idempotency_token to join events. Upload logs and transcripts as artifacts when phases fail or when suspected_compromise occurs.

10. Stopping Conditions

Terminate orchestration under the following conditions: (a) success is achieved; (b) both agents return terminal classification after at least one fix cycle; (c) the global time budget or fix‑cycle limit is exceeded; or (d) the system quarantines a critical agent and cannot progress.

11. Backwards Compatibility and Migration

Version content types to introduce v2 reports and extended commands. Accept v1 payloads during a migration window by mapping missing fields to defaults (e.g., classification=retryable when status=error and retry_plan present). Emit v2 from reference implementations by default.

12. Risks and Mitigations

Unbounded retries waste resources. Mitigate with explicit budgets and backoff parameters. Premature iteration exhaustion hides signal. Mitigate with phase gating and iteration accounting tied to fixes. Adversarial agents degrade trust. Mitigate with the Verifier and quarantine procedures. Port churn destabilizes probes. Mitigate by requiring backend self‑selection and explicit observed.port reporting.

13. Appendix: Illustrative Schemas

The following JSON snippets illustrate payloads; they are not exhaustive.

Report v2:
{
  "schema_version": 2,
  "stage": "run_probe",
  "status": "error",
  "classification": "retryable",
  "advise": "retry",
  "retry_plan": {"attempts_used": 2, "max_attempts": 4, "backoff_ms": 800},
  "next_not_before": "2025-08-20T23:31:45Z",
  "observed": {"port": 8002, "url": "http://localhost:8002/hello"},
  "artifacts": {"log_digest": "sha256:…"}
}

Command (run_probe with budget):
{
  "schema_version": 2,
  "to": "frontend",
  "stage": "run_probe",
  "deadline_ms": 10000,
  "budget_ms": 8000,
  "idempotency_token": "c734…",
  "params": {"url": "http://localhost:8002/hello"}
}

