# SW4RM product direction: a narrower case for continuing

!!! note "Internal planning document"

    This is a dated internal owner-assessment memo, not a ratified product
    pivot and not a customer-facing page. It is excluded from the site
    navigation; the only in-site pointer is the product-assessment link in
    [Protocol RFC](protocol/index.md).

Assessment date: 2026-09-04. Status: recommendation for owner review, not a
ratified product pivot or a claim of demonstrated market demand.

## Recommendation

Continue SW4RM only as a bounded attempt to make review decisions and handoffs
portable across independently implemented agents. Finish the 0.7.0 compatibility
repair, then test that proposition in one real workflow. Do not keep expanding
it as a general agent platform on the strength of reliable messaging, five SDKs,
or a large specification alone.

The customer promise to test is: **a team can pause, restart, and inspect a
multi-agent review without losing which artifact was reviewed, whose input was
required, or which decision permits the next step.** This is a proposed promise;
the current implementation does not yet prove all of it, especially permission
to perform external effects.

The problem is real. The evidence so far does not show that it needs a separate
SW4RM platform. That distinction should govern further investment.

## What the related local projects already provide

This is a source inspection of the named checkouts, not a fresh deployment
qualification or an inventory of every project on the machine.

| Project | Observed responsibility | Consequence for SW4RM |
|---|---|---|
| gptqueue | Agent directory, Redis inboxes, durable task claims and acknowledgements, lease renewal, recovery/dead-letter handling, custody, offline wake coordination | Avoid building a competing local task broker or actor launcher |
| Nudge | Operator notifications, durable human requests/responses, managed session continuation, approval-grant claim/consumption state | Reuse human interaction and approval boundaries rather than inventing another notification/approval store |
| gptengage | Model/CLI invocation, parallel debate rounds, synthesis, persistent conversation sessions | Treat it as an execution/deliberation engine; avoid duplicating model adapters and debate orchestration |
| Grilling skill | A question-first reasoning method with bounded speculative/parallel modes, evidence gathering, and handoff instructions | Treat it as a review method; its instructions alone do not supply a transport, durable workflow engine, or effect-authority boundary |
| SW4RM | Typed envelopes, proposal/vote/decision records, quorum and score rules, handoff/delegation contracts, SDKs, reference stores | The strongest candidate contribution is a reusable coordination contract above execution and delivery |

Local evidence (paths are relative to `~/Documents`):

- `gptqueue/src/core/task-claim-store.ts` and
  `gptqueue/src/mcp-server/lua/claims-{batch-claim,ack,renew,recover}.lua` implement
  claim ownership, renewal, and recovery; `actor-directory.ts` and `wake-lease.ts`
  cover actors and activation. Its product thesis also targets autonomous agent
  coordination, so the overlap is strategic as well as technical.
- `nudge/nudge/human.py` contains SQLite-backed requests, responses, resume
  attempts, and approval-grant claim/finalization models. Nudge's current scope
  is substantially broader than its README's opening “directory watchdog” label.
- `gptengage/src/orchestrator/debate.rs` implements participant rounds and
  synthesis; `gptengage/src/session/mod.rs` persists conversation sessions.
- `~/.codex/skills/grilling/SKILL.md` defines interview, evidence-wave,
  debate, and bounded lattice modes.
- In this repository, `protos/negotiation_room.proto`,
  `sdks/py_sdk/sw4rm_policies/`, and
  `sdks/py_sdk/reference-services/coordination/` implement the candidate policy
  and durable review-record layer.

These are possible composition boundaries. No integrations were installed,
activated, or implemented as part of this assessment.

## What the industry already solves

| Alternative | Existing capability | Implication |
|---|---|---|
| A2A | Agent discovery, messages/tasks, artifacts, streaming, cancellation, authentication requirements, and extension mechanisms | A new general inter-agent wire protocol needs a compelling reason; investigate an A2A extension/profile for review semantics |
| Temporal | Durable workflow/activity execution, including documented agent integrations | Process recovery and long-running orchestration are occupied territory |
| Restate | Durable execution for agents, workflows, and distributed calls | Simpler durable-agent positioning also has direct alternatives |
| LangGraph | Graph state checkpoints, persistent stores, human-interruption and recovery support | A workflow owned by one application may already have adequate coordination infrastructure |
| NATS JetStream and established brokers | Persistent messaging, consumer acknowledgement, redelivery, delivery limits | ACKs and retry queues are necessary infrastructure, not a distinctive product claim |

Sources checked on 2026-09-04: [A2A specification](https://a2a-protocol.org/latest/specification/),
[Temporal agent example](https://docs.temporal.io/ai/cookbook/openai-agents-sdk-python),
[Restate AI agents](https://docs.restate.dev/use-cases/ai-agents),
[LangGraph persistence](https://docs.langchain.com/oss/python/langgraph/persistence),
and [NATS consumer semantics](https://github.com/nats-io/nats.docs/blob/master/nats-concepts/jetstream/consumers.md).
These documents establish available mechanisms, not comparative performance in
our workload. The optional local Temporal benchmark has not executed against
Temporal; it supplies no evidence that SW4RM wins.

A2A makes send idempotency optional and provides typed extension mechanisms.
That leaves room for a stricter review/decision profile, but it also means the
profile may fit inside an existing protocol. It is not evidence that the industry
has no solution. The hypothesis is reduced integration work, not invention of
quorum, durable messaging, or multi-agent debate.

## The useful distinction: delivery, decision, and authority

A task broker answers whether work reached a worker. A workflow engine records
which step runs next. A review policy answers whether the required evidence and
critics support a particular outcome. The component performing an external
effect must still check whether that outcome grants valid authority now.

SW4RM could help make the review-policy part reusable across different runtimes.
For example: attach two independent review results to one immutable code
revision, preserve a dissent, wait for a human decision, restart a failed
coordinator, and explain why the chosen revision may proceed.

Today's proposal/vote/decision records are a starting point. They do not by
themselves provide authenticated reviewer identity, critic independence,
content-bound approval invalidation, or a transaction with deployment. The wire
contract carries an artifact ID and policy version; an application must still
bind those to the exact artifact and enforce effects. A quorum of correlated
models can confidently repeat the same error.

This identifies both a candidate product and the work needed to earn its claims.
Making the transport more elaborate would not resolve these concerns.

## First user and first independently useful workflow

The first user is a developer or small team already coordinating separate coding
and review agents. Their painful job is recovering a review after an agent,
terminal, or coordinator disappears and determining whether approval still
applies after the artifact changes. Their workaround is a mixture of messages,
files, session history, and manual checks.

Use one existing code-change review as the experiment:

1. gptengage or an existing agent runtime produces the bounded work and review input.
2. gptqueue delivers tasks to the chosen agents and handles offline participants.
3. SW4RM policy/records track artifact identity, required reviewers, votes,
   dissent, policy, and decision.
4. Nudge obtains human input when required and resumes the correct conversation.
5. The existing effect executor checks the artifact and authority before acting.

The experiment must not require replacing all existing runtimes or deploying
all 15 protocol services. A policy library plus a small record store may be enough.
If an A2A extension or ordinary application data can express the contract with
less integration work, prefer that form.

## Compare three operating models

| Model | What it protects | Adversarial test | Assessment |
|---|---|---|---|
| Continue the broad platform | A uniform end-to-end architecture | A team already uses Temporal/A2A and asks why it must replace working infrastructure | Too much duplication and maintenance before demand evidence |
| Narrow to portable review/decision rules plus adapters | Existing investments and explicit coordination semantics | Change an artifact after review; restart the coordinator; deliver a vote twice | Recommended hypothesis to test |
| Put small policy helpers into the existing tools and maintain/archive the rest | Simplicity and lower maintenance | Two genuinely independent runtimes need the same contract | Prefer this if no recurring cross-runtime contract emerges |

No SDK retirement, deprecation, dependency adoption, or public API removal is
made by this recommendation. Those are later owner decisions.

## Evidence ledger

| Kind | Statement |
|---|---|
| Observed fact | Local gptqueue/Nudge/gptengage already implement substantial overlapping infrastructure |
| Observed fact | Published SW4RM remains 0.6.0; current work repairs an unreleased cross-SDK contract |
| Observed fact | Existing public alternatives provide durable execution, messaging, and agent interoperability |
| Supported inference | SW4RM's broad infrastructure pitch is weak against both local and external alternatives |
| Strategic bet | Portable review semantics will eliminate repeated bespoke integration work |
| Preference | Preserve user choice of agent runtime, task broker, and human interface |
| Known unknown | Whether independent users encounter this problem often enough to adopt another contract |
| Known unknown | Whether a library or A2A profile is more useful than a separate service |
| Protection | Keep the first experiment small, reversible, and explicit about effect authority |

## Success, stop, and revision rules

Proposed experiment budget: two engineer-weeks after the compatibility release
is reviewable. This is a recommended budget, not an automatically started task.
Use real existing review work; do not manufacture agent traffic or favorable
benchmark cases.

Measure manual interventions, integration-specific code, recovery correctness,
repeated model work, and time to explain a decision. Compare the same workflow
using the existing tools alone. Include interruption during review, duplicate
votes, a missing critic, artifact replacement after approval, and human input
arriving after restart.

Continue if at least two independently maintained workflows reuse the same
contract, interruptions require less manual reconstruction, and the adapters are
simpler than the duplicated glue they replace. Seek external users before
claiming a broader market. Download counts, package count, test count, and a
month of idle uptime do not substitute for that evidence.

Narrow further or stop if the useful logic remains a few project-specific
functions, all users already share one workflow runtime, adapters cost more than
the removed glue, or nobody accepts the integration cost. Preserve reusable
schemas/tests/policies even if the platform identity is retired.

Revisit the decision if an external team brings a concrete multi-runtime review
problem, A2A adds a suitable standardized review contract, or the first workflow
requires stronger authentication/commit-time authority than the current stack.

## Language ladder and direction

**Customer:** recover an interrupted agent review and know which decision applies
to which artifact.

**Product:** reusable review and handoff rules across the tools a team already uses.

**Practitioner:** keep proposals, critics, policy outcomes, and human decisions
attached to a stable work item; inspect and resume it after failure.

**Technical:** explicit identity and policy data, pure evaluators, durable records,
transport adapters, conformance cases, and an external effect-authority boundary.

Now: repair 0.7.0 parity, package contents, and documentation claims. Next: test
one real workflow against the existing-tools baseline. Horizon: a reusable review
profile across runtimes, if the evidence supports it. A larger agent platform is
not the default continuation.
