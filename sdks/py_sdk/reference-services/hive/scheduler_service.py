#!/usr/bin/env python3

"""
Minimal, stateless Scheduler Service for the Python reference stack.

- Binds a gRPC server on 0.0.0.0:50053 for liveness/health (no API used here).
- Registers as agent_id "scheduler" with Registry and opens a Router stream.
- On receiving a seed message (MessageType.DATA, content_type
  "application/vnd.sw4rm.scheduler.seed+json;v=1"), invokes `claude -p "<prompt>"
  --output-format stream-json --verbose`, parses the result into a minimal plan
  shape {"frontend": str|obj, "backend": str|obj}, normalizes to prompts and
  dispatches CONTROL generate commands to agents.
- On receiving a CONTROL run trigger addressed to the scheduler
  (content_type "application/vnd.sw4rm.scheduler.command+json;v=1", stage="run"),
  it does not read or persist any plan. Instead, it accepts inline
  {params: {plan: {...}}} or {params: {commands: {...}}} to compute run commands
  and fans them out to agents. If absent, it falls back to safe defaults.
"""

import json
import os
import subprocess
from concurrent import futures
from typing import Optional
import traceback
import time
import threading

import grpc
import shutil
import logging

try:
    from sw4rm.protos import common_pb2, scheduler_pb2, scheduler_pb2_grpc
except Exception:
    # Fallback numeric constants if stubs not available
    class _C:
        CONTROL = 1
        DATA = 2
        NOTIFICATION = 4

    class common_pb2:
        MessageType = type("MessageType", (), {"CONTROL": _C.CONTROL, "DATA": _C.DATA, "NOTIFICATION": _C.NOTIFICATION})

    scheduler_pb2 = None
    scheduler_pb2_grpc = None
from pathlib import Path
from collections import Counter

from state_store import SchedulerStateStore
from reference_auth_middleware import build_auth_interceptors
from reference_logging import configure_reference_service_logging, request_logging_context
from health_service import add_reference_health_service
from reference_config import (
    ReferenceServiceConfig,
    ReferenceServiceConfigWatcher,
    load_reference_service_config,
    start_reference_service_config_watcher,
)
from graceful_shutdown import (
    ReferenceServiceShutdownCoordinator,
)

_DEFAULT_DB_DIR = os.getenv(
    "REFERENCE_SERVICE_DB_DIR",
    str(Path.cwd() / ".reference_services_state"),
)
_CONFIG_WATCHER: Optional[ReferenceServiceConfigWatcher] = None

from sw4rm.clients.registry import RegistryClient
from sw4rm.clients.router import RouterClient
from sw4rm.envelope import build_envelope

# Track whether we've established a session in this process
_SESSION_READY: bool = False


def _default_db_path(env_var: str, filename: str) -> str:
    explicit = os.getenv(env_var)
    if explicit:
        return explicit
    return str(Path(_DEFAULT_DB_DIR) / filename)


def _active_config() -> "ReferenceServiceConfig":
    if _CONFIG_WATCHER is not None:
        return _CONFIG_WATCHER.config
    return load_reference_service_config("scheduler")


def _log(msg: str) -> None:
    logging.info(msg)

def _log_success(msg: str) -> None:
    logging.info(msg)

def _log_error(msg: str) -> None:
    logging.error(msg)


def _router_channel() -> grpc.Channel:
    cfg = _active_config()
    host = cfg.router_host or os.getenv("ROUTER_HOST", "localhost")
    port = int(cfg.router_port or int(os.getenv("ROUTER_PORT", "50051")))
    return grpc.insecure_channel(f"{host}:{port}")


def _registry_channel() -> grpc.Channel:
    cfg = _active_config()
    host = cfg.registry_host or os.getenv("REGISTRY_HOST", "localhost")
    port = int(cfg.registry_port or int(os.getenv("REGISTRY_PORT", "50052")))
    return grpc.insecure_channel(f"{host}:{port}")


def _transcript_path() -> Path:
    # Write transcript alongside the demo assets
    base = Path(__file__).parent / "client_server_llm"
    base.mkdir(parents=True, exist_ok=True)
    return base / "transcript.json"


# removed per-cleanup: avoid writing raw stream jsonl logs


def _normalize_agent_plan(role: str, plan: object) -> Optional[dict]:
    """Coerce planner output into normalized dict with prompt/run_cmd/expected_artifacts.

    Accepts legacy shape where `plan` is a string prompt.
    Fills defaults for run_cmd and expected_artifacts when missing.
    Returns None if no usable prompt is present.
    """
    defaults = {
        "backend": {
            "expected_artifacts": ["backend/server.py"],
            "run_cmd": "cd backend && python3 server.py",
        },
        "frontend": {
            "expected_artifacts": ["frontend/index.html", "frontend/index.js"],
            "run_cmd": "cd frontend && python3 -m http.server 5173",
        },
    }
    d = defaults.get(role, {})
    if isinstance(plan, str):
        prompt = plan.strip()
        if not prompt:
            return None
        return {
            "prompt": prompt,
            "expected_artifacts": d.get("expected_artifacts", []),
            "run_cmd": d.get("run_cmd", ""),
        }
    if isinstance(plan, dict):
        prompt = plan.get("prompt") or plan.get("instructions") or plan.get("text")
        if not isinstance(prompt, str) or not prompt.strip():
            return None
        out = dict(plan)
        out.setdefault("expected_artifacts", d.get("expected_artifacts", []))
        out.setdefault("run_cmd", d.get("run_cmd", ""))
        return out
    return None


def _transcript_append(event: dict) -> None:
    try:
        p = _transcript_path()
        with p.open("a", encoding="utf-8") as f:
            f.write(json.dumps(event) + "\n")
    except Exception:
        pass


def _start_heartbeats(registry: RegistryClient, agent_id: str) -> None:
    def _hb():
        while True:
            try:
                registry.heartbeat(agent_id=agent_id, state=0, health={"service": "scheduler"})
            except Exception:
                pass
            time.sleep(30)
    t = threading.Thread(target=_hb, daemon=True)
    t.start()


def _session_file() -> Path:
    return Path(__file__).parent / "client_server_llm" / ".scheduler_session_id"


def _read_session_id() -> Optional[str]:
    try:
        p = _session_file()
        if p.exists():
            return p.read_text(encoding="utf-8").strip() or None
    except Exception:
        pass
    return None


def _write_session_id(session_id: str) -> None:
    try:
        p = _session_file()
        p.write_text(session_id, encoding="utf-8")
    except Exception:
        pass


def _extract_first_json_object(text: str) -> Optional[dict]:
    """Best-effort extraction of the first balanced JSON object from text."""
    start = text.find("{")
    if start == -1:
        return None
    depth = 0
    for i in range(start, len(text)):
        c = text[i]
        if c == "{" :
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                try:
                    return json.loads(text[start:i+1])
                except Exception:
                    return None
    return None


def run_claude_stream_json(prompt: str) -> tuple[Optional[dict], str]:
    """Run `claude` CLI and reconstruct text from stream-json events.

    We expect the CLI to emit JSONL events. We concatenate text from
    `content_block_delta` events, then attempt to parse the final text as JSON.
    """
    _log(f"{time.strftime('%Y-%m-%dT%H:%M:%S')} claude prompt (first 400):\n{prompt[:400]}")
    # Resolve CLI path and prepare command
    cli_path = shutil.which("claude") or "claude"
    cmd = [
        cli_path,
        "-p",
        prompt,
        "--output-format",
        "stream-json",
        "--verbose",
    ]
    # Only pass a session id after the first successful call in this process
    global _SESSION_READY
    sid = _read_session_id()
    passing_sid = bool(sid and _SESSION_READY)
    if passing_sid:
        cmd += ["--session-id", sid]
    _log(f"LLM invoke: cli={cli_path} pass_sid={passing_sid} sid={sid or '-'}")
    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
    except FileNotFoundError:
        _log_error("claude CLI not found on PATH. Please install and authenticate it.")
        return None, ""

    # Accumulate textual content from stream events
    text_buf: list[str] = []
    raw_lines_sample: list[str] = []
    assert proc.stdout is not None
    seen_session: Optional[str] = None
    last_result_text: str = ""
    type_counts: Counter[str] = Counter()
    saw_result = False
    # Do not persist raw frames to disk (keep console/transcript only)
    stream_fp = None
    for line in proc.stdout:
        line = line.strip()
        if not line:
            continue
        # Persist raw line for troubleshooting
        # raw frame persistence disabled
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(obj, dict):
            continue
        typ = str(obj.get("type"))
        type_counts[typ] += 1
        if len(raw_lines_sample) < 20:
            raw_lines_sample.append(line)
        # Accumulate text deltas
        if typ == "content_block_delta":
            delta = obj.get("delta") or {}
            if isinstance(delta, dict) and delta.get("type") == "text_delta":
                frag = delta.get("text", "")
                if isinstance(frag, str):
                    text_buf.append(frag)
        # Some CLIs emit initial full text chunk
        elif typ == "content_block_start":
            cb = obj.get("content_block") or {}
            if isinstance(cb, dict) and cb.get("type") == "text":
                initial = cb.get("text", "")
                if isinstance(initial, str) and initial:
                    text_buf.append(initial)
        # Prefer structured result event
        if typ == "result":
            saw_result = True
            res = obj.get("result")
            if isinstance(obj.get("session_id"), str):
                seen_session = obj["session_id"]
            if isinstance(res, str):
                # Preprocess: strip markdown code fences and extract JSON object
                s = res.strip()
                if s.startswith("```"):
                    # Remove leading fence line
                    s = "\n".join(s.splitlines()[1:])
                    # Remove trailing fence if present
                    if s.rstrip().endswith("```"):
                        s = "\n".join(s.splitlines()[:-1])
                last_result_text = s
                # Try direct JSON
                try:
                    parsed = json.loads(s)
                    if isinstance(parsed, dict):
                        return parsed, s
                except Exception:
                    # Try to extract first JSON object from text
                    obj2 = _extract_first_json_object(s)
                    if isinstance(obj2, dict):
                        return obj2, s
                    # As a last resort, return text wrapper
                    return {"text": res}, res
            elif isinstance(res, dict):
                try:
                    last_result_text = json.dumps(res)
                except Exception:
                    last_result_text = ""
                return res, json.dumps(res)
        # Some variants stream JSON chunks
        elif typ == "message_delta":
            delta = obj.get("delta") or {}
            if isinstance(delta, dict):
                pj = delta.get("partial_json")
                if isinstance(pj, str):
                    text_buf.append(pj)
        # Fallbacks: look for common fields carrying text arrays
        else:
            # e.g., {"message": {"content": [{"type":"text","text":"..."}]}}
            msg = obj.get("message") or obj.get("response")
            if isinstance(msg, dict):
                content = msg.get("content")
                if isinstance(content, list):
                    for item in content:
                        if isinstance(item, dict) and item.get("type") in ("text", "output_text"):
                            t = item.get("text") or item.get("output_text")
                            if isinstance(t, str):
                                text_buf.append(t)

        proc.wait()
        # no stream log to close
        full_text = "".join(text_buf).strip()
        if not full_text:
            if raw_lines_sample:
                _log("No reconstructed text; raw stream sample:")
                for ln in raw_lines_sample:
                    _log(ln)
        # Write summary to transcript
        _transcript_append({
            "event": "llm_stream_summary",
            "agent": "scheduler",
            "ts": time.strftime('%Y-%m-%dT%H:%M:%S'),
            "saw_result": saw_result,
            "type_counts": dict(type_counts),
            "full_text_len": 0,
        })
        return None, ""
    # Helpful diagnostic for common auth errors
    if "Invalid API key" in full_text:
        _log("Claude CLI reports Invalid API key. Run `claude login` or fix auth.")
    # Try direct JSON parse first
    try:
        parsed = json.loads(full_text)
        if isinstance(parsed, dict):
            return parsed, full_text
    except Exception:
        _log("JSON parse failed on reconstructed text; trying fallback extraction…")
        traceback.print_exc()
    # Fallback: extract first JSON object from the text
    obj = _extract_first_json_object(full_text)
    if obj is None:
                            _log("Fallback JSON object extraction failed. Text excerpt (first 400 chars):")
                            _log(full_text[:400])
    # Record summary for troubleshooting
    _transcript_append({
        "event": "llm_stream_summary",
        "agent": "scheduler",
        "ts": time.strftime('%Y-%m-%dT%H:%M:%S'),
        "saw_result": saw_result,
        "type_counts": dict(type_counts),
        "full_text_len": len(full_text),
        "full_text_excerpt": full_text[:400],
    })
    # Persist session id if seen
    if seen_session:
        _write_session_id(seen_session)
        _SESSION_READY = True
    # Log session and result excerpt
    try:
        excerpt = (last_result_text or full_text or "")[:400]
        _log(f"{time.strftime('%Y-%m-%dT%H:%M:%S')} claude session={seen_session or (_read_session_id() or '-')}, result_excerpt (first 400):\n{excerpt}")
        _transcript_append({
            "event": "llm_call",
            "agent": "scheduler",
            "ts": time.strftime('%Y-%m-%dT%H:%M:%S'),
            "session_id": seen_session or (_read_session_id() or ""),
            "prompt_excerpt": prompt[:800],
            "result_excerpt": excerpt,
        })
    except Exception:
        pass
    return obj, full_text

def _send(router: RouterClient, producer_id: str, message_type: int, content_type: str, payload: bytes, corr: Optional[str] = None):
    env = build_envelope(
        producer_id=producer_id,
        message_type=message_type,
        content_type=content_type,
        payload=payload,
        correlation_id=corr,
    )
    return router.send_message(env)


def _looks_like_port_in_use(logs: str) -> bool:
    if not isinstance(logs, str):
        return False
    s = logs.lower()
    patterns = [
        "address already in use",
        "eaddrinuse",
        "errno 98",
        "[errno 98]",
        "oserror",
    ]
    return any(pat in s for pat in patterns)


# Scheduler does not choose ports; backend self-selects and reports.


# =============================================================================
# gRPC SCHEDULER SERVICE IMPLEMENTATION
# =============================================================================

class SchedulerServiceImpl:
    """Implementation of SchedulerService gRPC RPCs.

    Provides task scheduling, preemption, and activity buffer management.
    """

    def __init__(
        self,
        db_path: Optional[str] = None,
        shutdown_manager: Optional[ReferenceServiceShutdownCoordinator] = None,
        config_watcher: Optional[ReferenceServiceConfigWatcher] = None,
    ):
        self._config_watcher = config_watcher
        base_config = (
            config_watcher.config
            if config_watcher is not None
            else load_reference_service_config("scheduler")
        )
        self.db_path = db_path or base_config.scheduler_db_path
        self.state = SchedulerStateStore(self.db_path)
        self.tasks: dict[str, dict] = {}
        self.activity: dict[str, list] = {}
        self._shutdown_manager = (
            shutdown_manager
            or ReferenceServiceShutdownCoordinator(
                "scheduler-service",
                grace_period_seconds=base_config.shutdown_grace_seconds,
            )
        )
        self._restore_state()
        self.lock = threading.RLock()
        logging.info("Scheduler service initialized")

    def _restore_state(self) -> None:
        tasks, activity = self.state.load_state()
        self.tasks = tasks

        self.activity = {}
        for agent_id, entries in activity.items():
            self.activity[agent_id] = [
                self._activity_from_record(record) for record in entries
            ]

    @staticmethod
    def _activity_from_record(record: dict) -> "scheduler_pb2.ActivityEntry":
        return scheduler_pb2.ActivityEntry(
            task_id=record.get("task_id", ""),
            repo_id=record.get("repo_id", ""),
            worktree_id=record.get("worktree_id", ""),
            branch=record.get("branch", ""),
            description=record.get("description", ""),
            timestamp=record.get("timestamp", ""),
        )

    def SubmitTask(self, request, context):
        """Submit a task for scheduling."""
        if self._shutdown_manager.is_draining:
            return scheduler_pb2.SubmitTaskResponse(
                accepted=False,
                reason="Scheduler service is shutting down",
            )

        with self._shutdown_manager.track_request("SubmitTask"):
            with self.lock:
                task_id = request.task_id or f"task-{len(self.tasks)}"
                task_record = {
                    "agent_id": request.agent_id,
                    "task_id": task_id,
                    "priority": request.priority,
                    "scope": request.scope,
                    "content_type": request.content_type,
                    "params": request.params,
                    "status": "pending",
                    "submitted_at": time.time(),
                }
                self.tasks[task_id] = task_record
                self.state.save_task(task_id, task_record)

                # Record activity
                if request.agent_id not in self.activity:
                    self.activity[request.agent_id] = []
                activity_entry = scheduler_pb2.ActivityEntry(
                    task_id=task_id,
                    description=f"Task submitted: {request.scope or 'default'}",
                    timestamp=time.strftime('%Y-%m-%dT%H:%M:%SZ'),
                )
                self.activity[request.agent_id].append(activity_entry)
                self.state.append_activity(request.agent_id, {
                    "task_id": task_id,
                    "repo_id": "",
                    "worktree_id": "",
                    "branch": "",
                    "description": activity_entry.description,
                    "timestamp": activity_entry.timestamp,
                })

                logging.info(f"Task {task_id} submitted for agent {request.agent_id}")
                return scheduler_pb2.SubmitTaskResponse(
                    accepted=True,
                    reason=f"Task {task_id} accepted",
                )

    def RequestPreemption(self, request, context):
        """Request preemption of a running task."""
        if self._shutdown_manager.is_draining:
            return scheduler_pb2.PreemptResponse(enqueued=False)

        with self._shutdown_manager.track_request("RequestPreemption"):
            with self.lock:
                task_id = request.task_id
                if task_id in self.tasks:
                    self.tasks[task_id]["status"] = "preempted"
                    self.tasks[task_id]["preempt_reason"] = request.reason
                    self.state.update_task_status(task_id, "preempted", request.reason)
                    logging.info(f"Task {task_id} marked for preemption: {request.reason}")
                    return scheduler_pb2.PreemptResponse(enqueued=True)
                else:
                    logging.warning(f"Preemption requested for unknown task: {task_id}")
                    return scheduler_pb2.PreemptResponse(enqueued=False)

    def ShutdownAgent(self, request, context):
        """Request graceful shutdown of an agent."""
        if self._shutdown_manager.is_draining:
            return scheduler_pb2.ShutdownAgentResponse(ok=False)

        with self._shutdown_manager.track_request("ShutdownAgent"):
            agent_id = request.agent_id
            grace_seconds = request.grace_period.seconds if request.grace_period else 30
            logging.info(f"Shutdown requested for agent {agent_id} (grace: {grace_seconds}s)")

            # In a real implementation, this would signal the agent
            # For now, just acknowledge the request
            return scheduler_pb2.ShutdownAgentResponse(ok=True)


    def PollActivityBuffer(self, request, context):
        """Poll activity buffer for an agent."""
        if self._shutdown_manager.is_draining:
            return scheduler_pb2.PollActivityBufferResponse(entries=[])
        with self._shutdown_manager.track_request("PollActivityBuffer"):
            with self.lock:
                entries = self.activity.get(request.agent_id, [])
                logging.debug(f"Polled {len(entries)} entries for agent {request.agent_id}")
                return scheduler_pb2.PollActivityBufferResponse(entries=entries)

    def PurgeActivity(self, request, context):
        """Purge activity entries for an agent."""
        if self._shutdown_manager.is_draining:
            return scheduler_pb2.PurgeActivityResponse(purged=0)

        with self._shutdown_manager.track_request("PurgeActivity"):
            with self.lock:
                agent_id = request.agent_id
                task_ids = set(request.task_ids)

                if agent_id not in self.activity:
                    return scheduler_pb2.PurgeActivityResponse(purged=0)

                purged = self.state.clear_activity(agent_id, task_ids)
                if task_ids:
                    self.activity[agent_id] = [
                        e for e in self.activity[agent_id]
                        if e.task_id not in task_ids
                    ]
                else:
                    self.activity[agent_id] = []
                logging.info(f"Purged {purged} entries for agent {agent_id}")
                return scheduler_pb2.PurgeActivityResponse(purged=purged)


def main() -> int:
    # Bind gRPC server with scheduler service
    config_watcher = start_reference_service_config_watcher("scheduler")
    config = config_watcher.config
    global _CONFIG_WATCHER
    _CONFIG_WATCHER = config_watcher
    configure_reference_service_logging(
        service_name="scheduler-service",
        level=os.getenv("REFERENCE_LOG_LEVEL", "INFO"),
    )
    port = int(config.scheduler_port)
    scheduler_shutdown_manager = ReferenceServiceShutdownCoordinator(
        "scheduler-service",
        grace_period_seconds=config.shutdown_grace_seconds,
    )
    grpc_server = grpc.server(
        futures.ThreadPoolExecutor(max_workers=4),
        interceptors=list(build_auth_interceptors(service_name="scheduler")),
    )

    # Register SchedulerService if protos available
    if scheduler_pb2_grpc is not None:
        scheduler_impl = SchedulerServiceImpl(
            db_path=config.scheduler_db_path,
            shutdown_manager=scheduler_shutdown_manager,
            config_watcher=config_watcher,
        )
        scheduler_pb2_grpc.add_SchedulerServiceServicer_to_server(
            scheduler_impl, grpc_server
        )
        logging.info(f"Scheduler gRPC service registered on port {port}")
    try:
        scheduler_service_name = scheduler_pb2.DESCRIPTOR.services_by_name[
            "SchedulerService"
        ].full_name
    except Exception:
        scheduler_service_name = "sw4rm.scheduler.SchedulerService"
    add_reference_health_service(grpc_server, service_names=(scheduler_service_name,))

    grpc_server.add_insecure_port(f"0.0.0.0:{port}")
    grpc_server.start()

    # Register and open Router stream
    router = RouterClient(_router_channel())
    registry = RegistryClient(_registry_channel())
    agent_id = "scheduler"

    try:
        registry.register({
            "agent_id": agent_id,
            "name": "Scheduler",
            "description": "LLM-driven scheduler demo",
            "capabilities": ["planning", "fanout"],
            "communication_class": 0,
        })
    except Exception:
        pass
    _start_heartbeats(registry, agent_id)

    # Simple in-memory session tracker
    # sessions[corr] = {
    #   generate_ok: {frontend: bool, backend: bool},
    #   probe_ok: {frontend: bool, backend: bool},
    #   iter: int,
    #   backend_port: int,
    # }
    sessions: dict[str, dict] = {}

    def handle_stream():
        for item in router.stream_incoming(agent_id):
            try:
                msg = item.msg
                ct = getattr(msg, "content_type", "")
                payload = getattr(msg, "payload", b"") or b""
                corr = getattr(msg, "correlation_id", None)
                if corr and corr not in sessions:
                    sessions[corr] = {
                        "generate_ok": {"frontend": False, "backend": False},
                        "run_ok": {"frontend": False, "backend": False},
                        "done": False,
                    }

                with request_logging_context(
                    request=msg,
                    method_name="StreamIncoming",
                    fallback_correlation_id=corr,
                ):
                    # Endpoint mediation/relay removed in simplified flow
                    # Handle agent reports first (NOTIFICATION)
                    if ct == "application/vnd.sw4rm.agent.report+json;v=1":
                        try:
                            rep = json.loads(payload.decode("utf-8", errors="replace"))
                        except Exception:
                            rep = {"stage": "?", "status": "error", "logs": "<invalid json>"}
                        from_id = getattr(msg, "producer_id", "")
                        corr = getattr(msg, "correlation_id", "")
                        stage = rep.get("stage")
                        status = rep.get("status")
                        files = rep.get("files")
                        files_n = len(files) if isinstance(files, list) else None
                        extra = ''
                        try:
                            if from_id == 'backend' and stage == 'run_probe' and isinstance(rep.get('port'), (int, float, str)):
                                extra = f" port={rep.get('port')}"
                        except Exception:
                            pass
                        # Highlight failures
                        if status == "ok":
                            _log(f"report from {from_id} corr={corr} stage={stage} status={status} files={files_n}{extra}")
                        else:
                            _log_error(f"report from {from_id} corr={corr} stage={stage} status={status} files={files_n}{extra}")
                        _transcript_append({
                            "event": "report",
                            "from": from_id,
                            "corr": corr,
                            "stage": stage,
                            "status": status,
                            "files": files_n,
                        })
                        # Update session state and drive next commands
                        sess = sessions.get(corr)
                        if isinstance(sess, dict) and not sess.get("done"):
                            role = from_id if from_id in ("frontend", "backend") else None
                            if stage == "generate" and role:
                                sess["generate_ok"][role] = (status == "ok")
                                if all(sess["generate_ok"].values()):
                                    # Auto-run if commands present from unified plan
                                    cmds = sess.get("run_cmds") if isinstance(sess, dict) else None
                                    if isinstance(cmds, dict):
                                        back_cmd_s = (cmds.get("backend") or "")
                                        front_cmd_s = (cmds.get("frontend") or "")
                                        if back_cmd_s and front_cmd_s:
                                            cmd_ct = "application/vnd.sw4rm.scheduler.command+json;v=1"
                                            back_cmd = json.dumps({"schema_version": 1, "to": "backend", "stage": "run", "params": {"cmd": back_cmd_s}}).encode("utf-8")
                                            front_cmd = json.dumps({"schema_version": 1, "to": "frontend", "stage": "run", "params": {"cmd": front_cmd_s}}).encode("utf-8")
                                            _send(router, agent_id, common_pb2.MessageType.CONTROL, cmd_ct, back_cmd, corr)
                                            _send(router, agent_id, common_pb2.MessageType.CONTROL, cmd_ct, front_cmd, corr)
                                            _log(f"dispatched run to frontend/backend corr={corr} (from LLM plan)")
                            elif stage == "run" and role:
                                sess["run_ok"][role] = (status == "ok")
                                if all(sess["run_ok"].values()):
                                    sess["done"] = True
                                    _transcript_append({"event": "success_run", "corr": corr})
                                    _log_success(f"completed session: both agents running (corr={corr})")
                        continue

                # Operator control: allow external run trigger (stage=run), and unified prompt (stage=plan/prompt)
                if ct == "application/vnd.sw4rm.scheduler.command+json;v=1":
                    try:
                        obj = json.loads(payload.decode("utf-8", errors="replace"))
                    except Exception:
                        obj = {}
                    if isinstance(obj, dict) and (obj.get("to") in (None, "scheduler")) and obj.get("stage") == "run":
                        # ALWAYS route run through LLM: treat input as guidance to produce canonical commands
                        params = obj.get("params") or {}
                        suggested = params.get("commands") if isinstance(params, dict) else None
                        # Build a concise run prompt
                        run_prompt = [
                            "You are the Scheduler. Output run commands for two agents.",
                            "Respond JSON ONLY, no prose/fences, as {\"commands\":{",
                            "  \"backend\":{\"run_cmd\":string},",
                            "  \"frontend\":{\"run_cmd\":string}}}",
                            "Constraints: backend must run on port 8000; frontend serves static files on 5173.",
                            "Execution cwd is ./generated_app. Use 'cd backend' and 'cd frontend' (do NOT include generated_app in paths).",
                        ]
                        if isinstance(suggested, dict):
                            try:
                                b = (suggested.get("backend") or {}).get("run_cmd")
                                f = (suggested.get("frontend") or {}).get("run_cmd")
                                if b or f:
                                    run_prompt.append("Suggested commands (may confirm or adjust):")
                                    run_prompt.append(json.dumps({"backend": {"run_cmd": b}, "frontend": {"run_cmd": f}}))
                            except Exception:
                                pass
                        # If caller provided a freeform message, include it
                        freeform = params.get("prompt") if isinstance(params, dict) else None
                        if isinstance(freeform, str) and freeform.strip():
                            run_prompt.append("User guidance:")
                            run_prompt.append(freeform.strip())
                        prompt_text = "\n".join(run_prompt)

                        # Call LLM to obtain commands
                        result, full_text = run_claude_stream_json(prompt_text)
                        if not isinstance(result, dict):
                            _log_error("run LLM did not return a JSON object; aborting run dispatch")
                            continue
                        commands_obj = result.get("commands") or result.get("run_commands") or result.get("run_cmds")
                        if not isinstance(commands_obj, dict):
                            _log_error("run LLM response missing 'commands' object; aborting run dispatch")
                            continue
                        back_cmd_s = str(((commands_obj.get("backend") or {}).get("run_cmd")) or "")
                        front_cmd_s = str(((commands_obj.get("frontend") or {}).get("run_cmd")) or "")
                        if not back_cmd_s or not front_cmd_s:
                            _log_error("run LLM response missing backend/frontend run_cmd; aborting run dispatch")
                            continue
                        # Dispatch run commands from LLM output
                        cmd_ct = "application/vnd.sw4rm.scheduler.command+json;v=1"
                        back_cmd = json.dumps({"schema_version": 1, "to": "backend", "stage": "run", "params": {"cmd": back_cmd_s}}).encode("utf-8")
                        front_cmd = json.dumps({"schema_version": 1, "to": "frontend", "stage": "run", "params": {"cmd": front_cmd_s}}).encode("utf-8")
                        _send(router, agent_id, common_pb2.MessageType.CONTROL, cmd_ct, back_cmd, corr)
                        _send(router, agent_id, common_pb2.MessageType.CONTROL, cmd_ct, front_cmd, corr)
                        _log_success("dispatched run (via LLM) to frontend/backend")
                        _log(f"run cmds: backend='{back_cmd_s}', frontend='{front_cmd_s}'")
                        continue
                    if isinstance(obj, dict) and (obj.get("to") in (None, "scheduler")) and obj.get("stage") in ("plan", "prompt"):
                        params = obj.get("params") or {}
                        seed = (params.get("seed") or params.get("prompt") or "") if isinstance(params, dict) else ""
                        if not isinstance(seed, str) or not seed.strip():
                            _log("scheduler CONTROL prompt missing seed/prompt text; ignoring")
                            continue
                        _log(f"[scheduler] received prompt ({len(seed)} bytes)")
                        _transcript_append({"event": "seed", "len": len(seed)})
                        # Use same flow as legacy seed
                        result, full_text = run_claude_stream_json(seed)
                        if not isinstance(result, dict):
                            _log_error("[scheduler] invalid result from claude: not a dict. Excerpt of text:")
                            if full_text:
                                _log(full_text[:400])
                            continue
                        raw_front = result.get("frontend")
                        raw_back = result.get("backend")
                        plan_front = _normalize_agent_plan("frontend", raw_front)
                        plan_back = _normalize_agent_plan("backend", raw_back)
                        # Save session
                        sess = sessions.setdefault(corr, {"generate_ok": {"frontend": False, "backend": False}, "run_ok": {"frontend": False, "backend": False}, "done": False})
                        sess["plan"] = {"frontend": plan_front, "backend": plan_back}
                        # Optional run commands
                        commands_obj = result.get("commands") or result.get("run_commands") or result.get("run_cmds")
                        if isinstance(commands_obj, dict):
                            b = str(((commands_obj.get("backend") or {}).get("run_cmd")) or "")
                            f = str(((commands_obj.get("frontend") or {}).get("run_cmd")) or "")
                            if b and f:
                                sess["run_cmds"] = {"backend": b, "frontend": f}
                        # Dispatch generate if present
                        cmd_ct = "application/vnd.sw4rm.scheduler.command+json;v=1"
                        if isinstance(plan_front, dict):
                            front_prompt = plan_front.get("prompt", "") + (
                                "\n\nRespond with JSON ONLY, no prose or fences. Schema: "
                                "{\"schema_version\":1,\"files\":[{\"path\":string,\"encoding\":\"base64\",\"content_b64\":string,\"executable\":boolean}]}. "
                                "Paths are relative to your generated app root. Encode all file contents in base64. "
                                "If you are the backend, implement CORS for browser access: add Access-Control-Allow-Origin: * and related headers on responses and handle OPTIONS preflight with 204."
                            )
                            cmd_front = json.dumps({"schema_version": 1, "to": "frontend", "stage": "generate", "params": {"prompt": front_prompt, "expected_artifacts": plan_front.get("expected_artifacts")}}).encode("utf-8")
                            _send(router, agent_id, common_pb2.MessageType.CONTROL, cmd_ct, cmd_front, corr)
                            _transcript_append({"event": "command", "corr": corr, "to": "frontend", "stage": "generate"})
                        if isinstance(plan_back, dict):
                            back_prompt = plan_back.get("prompt", "") + (
                                "\n\nRespond with JSON ONLY, no prose or fences. Schema: "
                                "{\"schema_version\":1,\"files\":[{\"path\":string,\"encoding\":\"base64\",\"content_b64\":string,\"executable\":boolean}]}. "
                                "Paths are relative to your generated app root. Encode all file contents in base64. "
                                "If you are the backend, implement CORS for browser access: add Access-Control-Allow-Origin: * and related headers on responses and handle OPTIONS preflight with 204."
                            )
                            cmd_back = json.dumps({"schema_version": 1, "to": "backend", "stage": "generate", "params": {"prompt": back_prompt, "expected_artifacts": plan_back.get("expected_artifacts")}}).encode("utf-8")
                            _send(router, agent_id, common_pb2.MessageType.CONTROL, cmd_ct, cmd_back, corr)
                            _transcript_append({"event": "command", "corr": corr, "to": "backend", "stage": "generate"})
                        continue
                    # Not a scheduler-directed control; ignore and continue
                    continue

                if ct != "application/vnd.sw4rm.scheduler.seed+json;v=1":
                    continue

                # Expect JSON payload {"seed": string}
                try:
                    seed_obj = json.loads(payload.decode("utf-8", errors="replace"))
                    seed = seed_obj.get("seed", "")
                except Exception:
                    seed = payload.decode("utf-8", errors="replace")
                _log(f"[scheduler] received seed ({len(seed)} bytes)")
                _transcript_append({"event": "seed", "len": len(seed)})

                # Always use Claude CLI stream-json
                result, full_text = run_claude_stream_json(seed)
                if not isinstance(result, dict):
                    _log_error("[scheduler] invalid result from claude: not a dict. Excerpt of text:")
                    if full_text:
                        _log(full_text[:400])
                    continue
                # Normalize planner schema: accept string prompts and fill defaults
                raw_front = result.get("frontend")
                raw_back = result.get("backend")
                plan_front = _normalize_agent_plan("frontend", raw_front)
                plan_back = _normalize_agent_plan("backend", raw_back)
                if not isinstance(plan_front, dict) or not isinstance(plan_back, dict):
                    _log_error(f"[scheduler] planner result missing required prompt(s) for frontend/backend. Got keys: {list(result.keys())}")
                    try:
                        _log(json.dumps(result)[:400])
                    except Exception:
                        pass
                    continue

                # Persist per-correlation plan in-memory only (stateless process)
                corr = getattr(msg, "correlation_id", None)
                sess = sessions.setdefault(corr, {
                    "generate_ok": {"frontend": False, "backend": False},
                    "run_ok": {"frontend": False, "backend": False},
                    "done": False,
                })
                sess["plan"] = {"frontend": plan_front, "backend": plan_back}
                # Optional run commands from planner result
                try:
                    commands_obj = result.get("commands") or result.get("run_commands") or result.get("run_cmds")
                    if isinstance(commands_obj, dict):
                        b = str(((commands_obj.get("backend") or {}).get("run_cmd")) or "")
                        f = str(((commands_obj.get("frontend") or {}).get("run_cmd")) or "")
                        if b and f:
                            sess["run_cmds"] = {"backend": b, "frontend": f}
                except Exception:
                    pass

                # Build prompts with strict base64 schema footer
                FOOTER = (
                    "\n\nRespond with JSON ONLY, no prose or fences. Schema: "
                    "{\"schema_version\":1,\"files\":[{\"path\":string,\"encoding\":\"base64\",\"content_b64\":string,\"executable\":boolean}]}. "
                    "Paths are relative to your generated app root. Encode all file contents in base64. "
                    "If you are the backend, implement CORS for browser access: add Access-Control-Allow-Origin: * and related headers on responses and handle OPTIONS preflight with 204."
                )
                front_prompt = plan_front.get("prompt", "") + FOOTER
                back_prompt = plan_back.get("prompt", "") + FOOTER

                # Fan out generate commands
                cmd_ct = "application/vnd.sw4rm.scheduler.command+json;v=1"
                cmd_front = json.dumps({
                    "schema_version": 1,
                    "to": "frontend",
                    "stage": "generate",
                    "params": {"prompt": front_prompt, "expected_artifacts": plan_front.get("expected_artifacts")},
                }).encode("utf-8")
                cmd_back = json.dumps({
                    "schema_version": 1,
                    "to": "backend",
                    "stage": "generate",
                    "params": {"prompt": back_prompt, "expected_artifacts": plan_back.get("expected_artifacts")},
                }).encode("utf-8")
                _send(router, agent_id, common_pb2.MessageType.CONTROL, cmd_ct, cmd_front, corr)
                _send(router, agent_id, common_pb2.MessageType.CONTROL, cmd_ct, cmd_back, corr)
                _transcript_append({"event": "command", "corr": corr, "to": "frontend", "stage": "generate"})
                _transcript_append({"event": "command", "corr": corr, "to": "backend", "stage": "generate"})
                _log("[scheduler] dispatched generate commands to frontend/backend agents")
            except Exception as e:
                _log_error(f"[scheduler] stream error: {e}")

    t = threading.Thread(target=handle_stream, daemon=True)
    t.start()

    def signal_handler(signum, frame):
        logging.info(f"Received signal {signum}, shutting down...")
        scheduler_shutdown_manager.stop_server(
            grpc_server,
            logger=logging.getLogger("scheduler.service"),
            pre_stop_hook=lambda: logging.info("Scheduler service entering graceful drain mode"),
        )

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    try:
        grpc_server.wait_for_termination()
    except KeyboardInterrupt:
        logging.info("Shutting down...")
        scheduler_shutdown_manager.stop_server(
            grpc_server,
            logger=logging.getLogger("scheduler.service"),
            pre_stop_hook=lambda: logging.info("Scheduler service entering graceful drain mode"),
        )
    finally:
        config_watcher.close()
        if _CONFIG_WATCHER is config_watcher:
            _CONFIG_WATCHER = None
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
