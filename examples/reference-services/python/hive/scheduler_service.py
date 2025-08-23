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
import shlex
import subprocess
import threading
from concurrent import futures
from typing import Optional
import traceback

import grpc
import shutil

try:
    from sw4rm.protos import common_pb2
except Exception:
    # Fallback numeric constants if stubs not available
    class _C:
        CONTROL = 1
        DATA = 2
        NOTIFICATION = 4

    class common_pb2:
        MessageType = type("MessageType", (), {"CONTROL": _C.CONTROL, "DATA": _C.DATA, "NOTIFICATION": _C.NOTIFICATION})

from sw4rm.clients.registry import RegistryClient
from sw4rm.clients.router import RouterClient
from sw4rm.envelope import build_envelope
from pathlib import Path
import threading
import time
import socket
from collections import Counter

# Track whether we've established a session in this process
_SESSION_READY: bool = False

# --- simple colored logging helpers ---
def _supports_color() -> bool:
    try:
        import sys as _sys
        return _sys.stdout.isatty() and os.getenv("NO_COLOR") is None
    except Exception:
        return False

_COLOR_RESET = "\033[0m"
_COLOR = "\033[33m"  # yellow for scheduler
_GREEN = "\033[32m"
_RED = "\033[31m"

def _tag() -> str:
    return f"{_COLOR}[scheduler]{_COLOR_RESET}" if _supports_color() else "[scheduler]"

def _log(msg: str) -> None:
    print(f"{_tag()} {msg}")

def _log_success(msg: str) -> None:
    if _supports_color():
        print(f"{_tag()} {_GREEN}{msg}{_COLOR_RESET}")
    else:
        print(f"{_tag()} {msg}")

def _log_error(msg: str) -> None:
    if _supports_color():
        print(f"{_tag()} {_RED}{msg}{_COLOR_RESET}")
    else:
        print(f"{_tag()} {msg}")


def _router_channel() -> grpc.Channel:
    host = os.getenv("ROUTER_HOST", "localhost")
    port = int(os.getenv("ROUTER_PORT", "50051"))
    return grpc.insecure_channel(f"{host}:{port}")


def _registry_channel() -> grpc.Channel:
    host = os.getenv("REGISTRY_HOST", "localhost")
    port = int(os.getenv("REGISTRY_PORT", "50052"))
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
        print("claude CLI not found on PATH. Please install and authenticate it.")
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
                print(ln)
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
        print(full_text[:400])
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


def main() -> int:
    # Bind a no-op gRPC server for health/liveness
    port = int(os.getenv("SCHEDULER_PORT", "50053"))
    grpc_server = grpc.server(futures.ThreadPoolExecutor(max_workers=2))
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
                        print(f"[scheduler] received prompt ({len(seed)} bytes)")
                        _transcript_append({"event": "seed", "len": len(seed)})
                        # Use same flow as legacy seed
                        result, full_text = run_claude_stream_json(seed)
                        if not isinstance(result, dict):
                            print("[scheduler] invalid result from claude: not a dict. Excerpt of text:")
                            if full_text:
                                print(full_text[:400])
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
                print(f"[scheduler] received seed ({len(seed)} bytes)")
                _transcript_append({"event": "seed", "len": len(seed)})

                # Always use Claude CLI stream-json
                result, full_text = run_claude_stream_json(seed)
                if not isinstance(result, dict):
                    print("[scheduler] invalid result from claude: not a dict. Excerpt of text:")
                    if full_text:
                        print(full_text[:400])
                    continue
                # Normalize planner schema: accept string prompts and fill defaults
                raw_front = result.get("frontend")
                raw_back = result.get("backend")
                plan_front = _normalize_agent_plan("frontend", raw_front)
                plan_back = _normalize_agent_plan("backend", raw_back)
                if not isinstance(plan_front, dict) or not isinstance(plan_back, dict):
                    print("[scheduler] planner result missing required prompt(s) for frontend/backend. Got keys:", list(result.keys()))
                    try:
                        print(json.dumps(result)[:400])
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
                print("[scheduler] dispatched generate commands to frontend/backend agents")
            except Exception as e:
                print(f"[scheduler] stream error: {e}")

    t = threading.Thread(target=handle_stream, daemon=True)
    t.start()

    try:
        grpc_server.wait_for_termination()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
