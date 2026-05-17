#!/usr/bin/env python3
"""Local Services Manager - Backend Server"""

import os
import json
import subprocess
import time
import signal
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse
from pathlib import Path

HOST = "127.0.0.1"
PORT = 9999
STATIC_DIR = Path(__file__).parent
CONFIG_DIR = Path(os.environ.get("LAUNCHPAD_DIR", str(STATIC_DIR)))
CONFIG_FILE = CONFIG_DIR / "services.json"

DEFAULT_SERVICES: dict[str, dict] = {
    "n8n": {
        "label": "n8n",
        "icon": "⚡",
        "path": str(Path.home() / "workflow" / "n8n"),
        "url": "http://localhost:5678",
        "description": "Workflow automation platform",
    },
    "dify": {
        "label": "Dify",
        "icon": "🧩",
        "path": str(Path.home() / "workflow" / "dify" / "docker"),
        "url": "http://localhost:3000",
        "description": "LLM application development platform",
    },
    "workflows-docs": {
        "label": "Workflows Docs",
        "icon": "📄",
        "path": str(Path.home() / "workflow" / "collections" / "n8n-workflows"),
        "description": "n8n workflow documentation service",
    },
}


def load_services() -> dict[str, dict]:
    if CONFIG_FILE.exists():
        try:
            data = json.loads(CONFIG_FILE.read_text())
            if isinstance(data, dict) and len(data) > 0:
                return data
        except (json.JSONDecodeError, OSError):
            pass
    save_services(DEFAULT_SERVICES)
    return dict(DEFAULT_SERVICES)


def save_services(services: dict[str, dict]) -> None:
    CONFIG_FILE.write_text(json.dumps(services, ensure_ascii=False, indent=2))


def run_cmd(cmd: list[str], cwd: str | None = None, timeout: int = 30) -> dict:
    try:
        r = subprocess.run(
            cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout
        )
        return {"ok": r.returncode == 0, "stdout": r.stdout, "stderr": r.stderr, "code": r.returncode}
    except subprocess.TimeoutExpired:
        return {"ok": False, "stdout": "", "stderr": "Command timed out", "code": -1}
    except FileNotFoundError:
        return {"ok": False, "stdout": "", "stderr": "Command not found", "code": -1}
    except Exception as e:
        return {"ok": False, "stdout": "", "stderr": str(e), "code": -1}


def check_script(svc_dir: str, name: str) -> bool:
    return os.path.isfile(os.path.join(svc_dir, ".launchpad", name))


def has_compose_file(svc_dir: str) -> bool:
    for name in ("docker-compose.yml", "docker-compose.yaml", "compose.yaml"):
        if os.path.isfile(os.path.join(svc_dir, name)):
            return True
    return False


def get_service_status(service_dir: str, is_docker: bool) -> dict:
    if not is_docker:
        return {"state": "unknown", "containers": [], "ports": []}

    r = run_cmd(["docker", "compose", "ps", "--format", "json"], cwd=service_dir)
    if r["ok"] and r["stdout"].strip():
        try:
            containers = []
            for line in r["stdout"].strip().split("\n"):
                if line.strip():
                    containers.append(json.loads(line))
            all_ports: list[str] = []
            for c in containers:
                ports_str = c.get("Ports", "")
                if ports_str:
                    for part in ports_str.split(","):
                        part = part.strip()
                        if "->" in part:
                            host_part = part.split("->")[0].strip()
                            if ":" in host_part:
                                host_port = host_part.split(":")[-1].strip()
                            else:
                                host_port = host_part
                            all_ports.append(host_port)
            running = any(c.get("State", "").lower() == "running" for c in containers)
            return {
                "state": "running" if running else "partial",
                "containers": [
                    {"name": c.get("Name", ""), "state": c.get("State", ""), "status": c.get("Status", "")}
                    for c in containers
                ],
                "ports": all_ports,
            }
        except (json.JSONDecodeError, ValueError):
            pass
    return {"state": "stopped", "containers": [], "ports": []}


def get_logs(service_dir: str, is_docker: bool, lines: int = 50) -> dict:
    if not is_docker:
        return {"ok": False, "stdout": "", "stderr": "Logs are only available for docker-compose services"}
    return run_cmd(
        ["docker", "compose", "logs", "--tail", str(lines), "--no-log-prefix"],
        cwd=service_dir, timeout=10,
    )


def get_all_services() -> list[dict]:
    services = load_services()
    result: list[dict] = []
    for key, svc in services.items():
        svc_dir = svc["path"]
        exists = os.path.isdir(svc_dir)
        if not exists:
            result.append({
                "id": key, "label": svc["label"], "icon": svc["icon"],
                "description": svc["description"], "available": False,
                "state": "unknown", "containers": [], "ports": [],
                "has_start_script": False, "has_stop_script": False,
                "is_docker": False,
            })
            continue
        is_docker = has_compose_file(svc_dir)
        status = get_service_status(svc_dir, is_docker)
        ports = status["ports"]
        explicit_url = svc.get("url", "")
        auto_url = f"http://localhost:{ports[0]}" if ports and not explicit_url else ""
        result.append({
            "id": key, "label": svc["label"], "icon": svc["icon"],
            "description": svc["description"], "url": explicit_url or auto_url, "available": True,
            "state": status["state"],
            "containers": status["containers"],
            "ports": ports,
            "has_start_script": check_script(svc_dir, "start.sh"),
            "has_stop_script": check_script(svc_dir, "stop.sh"),
            "is_docker": is_docker,
        })
    return result


def read_body(handler: BaseHTTPRequestHandler) -> dict:
    length = int(handler.headers.get("Content-Length", 0))
    if length == 0:
        return {}
    raw = handler.rfile.read(length)
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format: str, *args) -> None:
        pass

    def _send_json(self, data, status: int = 200) -> None:
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_file(self, path: str) -> None:
        try:
            with open(path, "rb") as f:
                content = f.read()
        except FileNotFoundError:
            self._send_json({"error": "Not found"}, 404)
            return
        ext = os.path.splitext(path)[1].lower()
        mime_map = {
            ".html": "text/html; charset=utf-8",
            ".css": "text/css; charset=utf-8",
            ".js": "application/javascript; charset=utf-8",
            ".json": "application/json; charset=utf-8",
            ".png": "image/png", ".jpg": "image/jpeg",
            ".svg": "image/svg+xml", ".ico": "image/x-icon",
        }
        self.send_response(200)
        self.send_header("Content-Type", mime_map.get(ext, "application/octet-stream"))
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"

        if path == "/":
            self._send_file(str(STATIC_DIR / "index.html"))
        elif path == "/api/services":
            self._send_json(get_all_services())
        elif path.startswith("/api/services/") and path.endswith("/logs"):
            parts = path.split("/")
            if len(parts) == 5:
                svc_id = parts[3]
                services = load_services()
                svc = services.get(svc_id)
                if svc and os.path.isdir(svc["path"]):
                    lines = 50
                    for q in urlparse(self.path).query.split("&"):
                        if q.startswith("lines="):
                            try:
                                lines = int(q.split("=")[1])
                            except ValueError:
                                pass
                    is_docker = has_compose_file(svc["path"])
                    r = get_logs(svc["path"], is_docker, lines)
                    self._send_json({"stdout": r["stdout"], "stderr": r["stderr"], "ok": r["ok"]})
                else:
                    self._send_json({"error": "Service not found"}, 404)
        else:
            self._send_json({"error": "Not found"}, 404)

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")
        parts = path.split("/")

        if path == "/api/services/add":
            body = read_body(self)
            svc_id = body.get("id", "").strip()
            if not svc_id:
                self._send_json({"error": "Missing service id"}, 400)
                return
            services = load_services()
            if svc_id in services:
                self._send_json({"error": f"Service '{svc_id}' already exists"}, 409)
                return
            services[svc_id] = {
                "label": body.get("label", svc_id),
                "icon": body.get("icon", "📦"),
                "path": body.get("path", ""),
                "description": body.get("description", ""),
            }
            save_services(services)
            self._send_json({"ok": True, "id": svc_id})
            return

        # POST /api/services/<id>/start|stop
        if len(parts) >= 5 and parts[1] == "api" and parts[2] == "services":
            svc_id = parts[3]
            action = parts[4]
            services = load_services()
            svc = services.get(svc_id)
            if not svc or not os.path.isdir(svc["path"]):
                self._send_json({"error": "Service not found"}, 404)
                return

            svc_dir = svc["path"]

            if action == "start":
                script = os.path.join(svc_dir, ".launchpad", "start.sh")
                if not os.path.isfile(script):
                    self._send_json({"ok": False, "message": "start.sh not found in .launchpad/"}, 400)
                    return
                r_obj = run_cmd(["bash", script], cwd=svc_dir, timeout=120)
                time.sleep(1)
                is_docker = has_compose_file(svc_dir)
                status = get_service_status(svc_dir, is_docker)
                self._send_json({"ok": r_obj["ok"], "message": r_obj["stdout"] or r_obj["stderr"], "service": status})
            elif action == "stop":
                script = os.path.join(svc_dir, ".launchpad", "stop.sh")
                if not os.path.isfile(script):
                    self._send_json({"ok": False, "message": "stop.sh not found in .launchpad/"}, 400)
                    return
                r_obj = run_cmd(["bash", script], cwd=svc_dir, timeout=120)
                time.sleep(1)
                is_docker = has_compose_file(svc_dir)
                status = get_service_status(svc_dir, is_docker)
                self._send_json({"ok": r_obj["ok"], "message": r_obj["stdout"] or r_obj["stderr"], "service": status})
            else:
                self._send_json({"error": "Unknown action"}, 400)
            return

        self._send_json({"error": "Not found"}, 404)

    def do_DELETE(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")
        parts = path.split("/")

        if len(parts) == 4 and parts[1] == "api" and parts[2] == "services":
            svc_id = parts[3]
            services = load_services()
            if svc_id not in services:
                self._send_json({"error": "Service not found"}, 404)
                return
            del services[svc_id]
            save_services(services)
            self._send_json({"ok": True})
            return

        self._send_json({"error": "Not found"}, 404)


def main() -> None:
    server = HTTPServer((HOST, PORT), Handler)
    print(f"\n  🚀 Launchpad running at http://localhost:{PORT}")
    print(f"  Press Ctrl+C to stop\n")

    def shutdown(sig, frame) -> None:
        print("\n  Shutting down...")
        server.shutdown()

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)
    server.serve_forever()


if __name__ == "__main__":
    main()
