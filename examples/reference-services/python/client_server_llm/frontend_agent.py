#!/usr/bin/env python3
import json
import os
import pathlib
import subprocess
import shutil
import sys
import threading
import time
import grpc

# Ensure Python SDK on path for local dev
sys.path.append(os.path.join(os.path.dirname(__file__), "..", "..", "..", "sdks", "py_sdk"))
from sw4rm.clients.registry import RegistryClient
from sw4rm.clients.router import RouterClient


ROOT = pathlib.Path(__file__).resolve().parent
GEN_ROOT = ROOT / "generated_app" / "frontend"

# --- logging helpers ---
def _supports_color() -> bool:
    try:
        return sys.stdout.isatty() and os.getenv("NO_COLOR") is None
    except Exception:
        return False

_COLOR_RESET = "\033[0m"
_COLOR = "\033[35m"  # magenta for frontend
_GREEN = "\033[32m"
_RED = "\033[31m"

def _tag() -> str:
    return f"{_COLOR}[frontend]{_COLOR_RESET}" if _supports_color() else "[frontend]"

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

_SESSION_FILE = ROOT / ".frontend_session_id"
_SESSION_READY = False


def _ts() -> str:
    import datetime
    return datetime.datetime.now().isoformat(timespec="seconds")


def _transcript_append(event: dict) -> None:
    try:
        p = ROOT / "transcript.json"
        with p.open("a", encoding="utf-8") as f:
            f.write(json.dumps(event) + "\n")
    except Exception:
        pass


def _read_session_id() -> str | None:
    try:
        if _SESSION_FILE.exists():
            return _SESSION_FILE.read_text(encoding="utf-8").strip() or None
    except Exception:
        pass
    return None


def _write_session_id(sid: str) -> None:
    try:
        _SESSION_FILE.write_text(sid, encoding="utf-8")
    except Exception:
        pass


def ensure_workspace() -> None:
    (ROOT / "generated_app").mkdir(parents=True, exist_ok=True)


def _extract_json_from_text(text: str) -> dict | None:
    import re
    s = (text or "").strip()
    if not s:
        return None
    try:
        obj = json.loads(s)
        if isinstance(obj, dict):
            return obj
    except Exception:
        pass
    if s.startswith("```"):
        lines = s.splitlines()
        s = "\n".join(lines[1:-1] if lines[-1].strip().startswith("```") else lines[1:])
        try:
            obj = json.loads(s)
            if isinstance(obj, dict):
                return obj
        except Exception:
            pass
    start = s.find("{")
    if start != -1:
        depth = 0
        for i, ch in enumerate(s[start:], start=start):
            if ch == '{': depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    try:
                        obj = json.loads(s[start:i+1])
                        if isinstance(obj, dict):
                            return obj
                    except Exception:
                        break
    for m in re.finditer(r"\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}", s):
        try:
            obj = json.loads(m.group(0))
            if isinstance(obj, dict):
                return obj
        except Exception:
            continue
    return None


def write_frontend_files(result_obj: dict, fallback_prompt: str) -> list[str]:
    GEN_ROOT.mkdir(parents=True, exist_ok=True)
    files = result_obj.get("files") if isinstance(result_obj, dict) else None
    written: list[str] = []
    if isinstance(files, list):
        import base64
        def _normalize_rel_path(rel: str) -> pathlib.Path:
            s = str(rel or "").replace("\\", "/").lstrip("/")
            parts = [p for p in s.split("/") if p not in ("", ".", "..")]
            # Strip leading generated_app and frontend if present
            if parts[:1] == ["generated_app"]:
                parts = parts[1:]
            if parts[:1] == ["frontend"]:
                parts = parts[1:]
            if not parts:
                parts = ["unknown.txt"]
            return pathlib.Path(*parts)
        for f in files:
            try:
                rel = f.get("path", "unknown.txt")
                path = GEN_ROOT / _normalize_rel_path(rel)
                path.parent.mkdir(parents=True, exist_ok=True)
                encoding = (f.get("encoding") or "").lower()
                if "content_b64" in f or encoding == "base64":
                    b64 = f.get("content_b64") or f.get("content") or ""
                    data = base64.b64decode(b64 + "==") if isinstance(b64, str) else b""
                    with open(path, "wb") as fp:
                        fp.write(data)
                else:
                    text = f.get("content", "")
                    path.write_text(text if isinstance(text, str) else "", encoding="utf-8")
                if f.get("executable") is True:
                    try:
                        os.chmod(path, 0o755)
                    except Exception:
                        pass
                written.append(str(path.relative_to(GEN_ROOT)))
            except Exception:
                continue
        return written
    # Minimal fallback
    (GEN_ROOT / "index.html").write_text("""<!doctype html>
<html><head><meta charset=\"utf-8\"><title>Frontend</title></head>
<body>
  <h1>Frontend</h1>
  <button id=\"btn\">Call Backend</button>
  <pre id=\"out\"></pre>
  <script src=\"index.js\"></script>
</body></html>
""", encoding="utf-8")
    (GEN_ROOT / "index.js").write_text("""
document.getElementById('btn').addEventListener('click', async () => {
  const url = 'http://localhost:8000/hello';
  try {
    const res = await fetch(url);
    document.getElementById('out').textContent = await res.text();
  } catch (e) {
    document.getElementById('out').textContent = String(e);
  }
});
""", encoding="utf-8")
    (GEN_ROOT / "PROMPT.txt").write_text(fallback_prompt, encoding="utf-8")
    return [str(p.relative_to(GEN_ROOT)) for p in GEN_ROOT.rglob('*') if p.is_file()]


def run_claude(prompt: str) -> dict:
    _log(f"{_ts()} claude prompt (first 400):\n{prompt[:400]}")
    cli_path = shutil.which("claude") or "claude"
    cmd = [cli_path, "-p", prompt, "--output-format", "stream-json", "--verbose"]
    global _SESSION_READY
    sid = _read_session_id()
    if sid and _SESSION_READY:
        cmd += ["--session-id", sid]
    _log(f"LLM invoke: cli={cli_path} pass_sid={bool(_SESSION_READY and sid)} sid={sid or '-'}")
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1, env=os.environ.copy())
    except FileNotFoundError:
        _log("claude CLI not found on PATH. Please install and authenticate it.")
        sys.exit(1)
    assert proc.stdout is not None
    text_buf: list[str] = []
    result_obj = None
    seen_session = None
    last_result_text = ""
    for line in proc.stdout:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(obj, dict):
            continue
        typ = obj.get("type")
        if typ == "content_block_delta":
            delta = obj.get("delta") or {}
            if isinstance(delta, dict) and delta.get("type") == "text_delta":
                frag = delta.get("text", "")
                if isinstance(frag, str):
                    text_buf.append(frag)
        elif typ == "content_block_start":
            cb = obj.get("content_block") or {}
            if isinstance(cb, dict) and cb.get("type") == "text":
                initial = cb.get("text", "")
                if isinstance(initial, str) and initial:
                    text_buf.append(initial)
        elif typ == "message_delta":
            delta = obj.get("delta") or {}
            if isinstance(delta, dict):
                pj = delta.get("partial_json")
                if isinstance(pj, str):
                    text_buf.append(pj)
        if typ == "result":
            if isinstance(obj.get("session_id"), str):
                seen_session = obj["session_id"]
                _write_session_id(seen_session)
            res = obj.get("result")
            if isinstance(res, str):
                s = res.strip()
                if s.startswith("```"):
                    s = "\n".join(s.splitlines()[1:])
                    if s.rstrip().endswith("```"):
                        s = "\n".join(s.splitlines()[:-1])
                last_result_text = s
                parsed = _extract_json_from_text(s)
                if isinstance(parsed, dict):
                    result_obj = parsed
            elif isinstance(res, dict):
                result_obj = res
                try:
                    last_result_text = json.dumps(res)
                except Exception:
                    last_result_text = ""
    proc.wait()
    full_text = "".join(text_buf).strip()
    if result_obj is None and full_text:
        result_obj = _extract_json_from_text(full_text) or {}
    if "Invalid API key" in (last_result_text or full_text):
        _log("Claude CLI reports Invalid API key. Run `claude login` and retry.")
    excerpt = (last_result_text or full_text or "")[:400]
    _log(f"{_ts()} claude session={seen_session or '-'}, result_excerpt (first 400):\n{excerpt}")
    _transcript_append({
        "event": "llm_call",
        "agent": "frontend",
        "ts": _ts(),
        "session_id": seen_session or "",
        "prompt_excerpt": prompt[:800],
        "result_excerpt": excerpt,
    })
    if seen_session:
        _SESSION_READY = True
    return result_obj or {}


def main() -> int:
    ensure_workspace()

    host = os.getenv("ROUTER_HOST", "localhost")
    port = int(os.getenv("ROUTER_PORT", "50051"))
    router = RouterClient(grpc.insecure_channel(f"{host}:{port}"))
    reg = RegistryClient(grpc.insecure_channel(f"{os.getenv('REGISTRY_HOST','localhost')}:{int(os.getenv('REGISTRY_PORT','50052'))}"))

    agent_id = "frontend"
    try:
        reg.register({
            "agent_id": agent_id,
            "name": "Frontend Agent",
            "description": "Generates frontend client",
            "capabilities": ["frontend"],
            "communication_class": 0,
        })
    except Exception:
        pass
    # Heartbeats
    def _hb():
        while True:
            try:
                reg.heartbeat(agent_id=agent_id, state=0, health={"role": "frontend"})
            except Exception:
                pass
            time.sleep(30)
    threading.Thread(target=_hb, daemon=True).start()

    _log("waiting for commands…")
    processed: set[tuple[str, str]] = set()
    for item in router.stream_incoming(agent_id):
        msg = item.msg
        ct = getattr(msg, "content_type", "")
        if ct != "application/vnd.sw4rm.scheduler.command+json;v=1":
            continue
        try:
            cmd = json.loads((getattr(msg, "payload", b"") or b"").decode("utf-8", errors="replace"))
        except Exception:
            continue
        target = cmd.get("to")
        if target and target != agent_id:
            continue
        stage = cmd.get("stage")
        params = cmd.get("params") or {}
        corr = getattr(msg, "correlation_id", "")
        key = (str(corr), str(stage), json.dumps(params, sort_keys=True))
        if key in processed:
            _log(f"duplicate command ignored {key}")
            continue
        if stage == "generate":
            prompt = params.get("prompt", "")
            _log("generate: invoking claude…")
            result_obj = run_claude(prompt)
            files_written = write_frontend_files(result_obj, prompt)
            report = {"schema_version": 1, "stage": "generate", "status": "ok", "files": files_written}
            from sw4rm.protos import common_pb2 as pb
            env = {"producer_id": agent_id, "message_type": pb.MessageType.NOTIFICATION, "content_type": "application/vnd.sw4rm.agent.report+json;v=1", "payload": json.dumps(report).encode("utf-8"), "correlation_id": corr}
            router.send_message(env)
            # Uniform completion log
            try:
                preview = ", ".join(files_written[:5]) + ("…" if len(files_written) > 5 else "")
                _log_success(f"completed generate: status=ok files={len(files_written)} [{preview}]")
            except Exception:
                _log_success("completed generate: status=ok")
            processed.add(key)
        elif stage == "run":
            suggested_cmd = params.get("cmd") or ""
            # Consult LLM to confirm/adjust run command
            llm_prompt = (
                "You are the frontend run orchestrator. A suggested command was provided. "
                "Return JSON ONLY as {\"run_cmd\": string}. Execution cwd is ./generated_app. "
                "Use 'cd frontend && python3 -m http.server 5173'. Do NOT include 'generated_app' in paths.\n\n"
                f"Suggested: {json.dumps(suggested_cmd)}"
            )
            _log("run: invoking claude to confirm command…")
            result_obj = run_claude(llm_prompt)
            cmdline = (result_obj.get("run_cmd") if isinstance(result_obj, dict) else None) or suggested_cmd
            base_dir = ROOT / "generated_app"
            log_path = GEN_ROOT / "service.log"
            try:
                log_fp = open(log_path, "ab", buffering=0)
            except Exception:
                log_fp = None
            try:
                proc = subprocess.Popen(cmdline, cwd=str(base_dir), shell=True, stdout=log_fp or subprocess.DEVNULL, stderr=log_fp or subprocess.DEVNULL)
                (GEN_ROOT / ".service.pid").write_text(str(proc.pid), encoding="utf-8")
                status = "ok"; info = {"pid": proc.pid, "cmd": cmdline}
            except Exception as e:
                status = "error"; info = {"error": str(e), "cmd": cmdline}
            report = {"schema_version": 1, "stage": "run", "status": status, "info": info}
            from sw4rm.protos import common_pb2 as pb
            env = {"producer_id": agent_id, "message_type": pb.MessageType.NOTIFICATION, "content_type": "application/vnd.sw4rm.agent.report+json;v=1", "payload": json.dumps(report).encode("utf-8"), "correlation_id": corr}
            router.send_message(env)
            if log_fp:
                try: log_fp.flush()
                except Exception: pass
            # Uniform completion log
            if status == "ok":
                _log_success(f"completed run: started pid={info.get('pid')} cmd='{cmdline}'")
            else:
                _log_error(f"completed run: failed error='{info.get('error','')}' cmd='{cmdline}'")
            processed.add(key)
        # no 'fix' stage handling; simplified flow

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
