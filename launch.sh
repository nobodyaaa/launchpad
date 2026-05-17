#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DATA_DIR="${LAUNCHPAD_DIR:-$HOME/.launchpad}"
PID_FILE="$DATA_DIR/.launchpad.pid"
LOG_FILE="$DATA_DIR/launchpad.log"
CONFIG_FILE="$DATA_DIR/services.json"
SERVER_SCRIPT="$SCRIPT_DIR/server.py"

# ── Server ──

server_start() {
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Launchpad is already running (PID $pid)"
            echo "Visit http://localhost:9999"
            exit 0
        fi
        rm "$PID_FILE"
    fi

    # Check what's on port 9999
    local port_pid
    port_pid=$(ss -tlnp 2>/dev/null | grep ':9999' | grep -oP 'pid=\K[0-9]+' || true)
    if [ -n "$port_pid" ]; then
        if [ -f "$PID_FILE" ] && [ "$(cat "$PID_FILE" 2>/dev/null)" = "$port_pid" ]; then
            echo "Launchpad is already running (PID $port_pid)"
            echo "Visit http://localhost:9999"
            exit 0
        fi
        local port_cmd
        port_cmd=$(ps -p "$port_pid" -o comm= 2>/dev/null || echo "unknown")
        echo "Port 9999 is already in use by PID $port_pid ($port_cmd)"
        echo "Use 'kill $port_pid' to free it, then try again"
        exit 1
    fi

    LAUNCHPAD_DIR="$DATA_DIR" nohup python3 "$SERVER_SCRIPT" >> "$LOG_FILE" 2>&1 &
    pid=$!
    echo $pid > "$PID_FILE"
    disown "$pid" 2>/dev/null || true

    echo "Launchpad started (PID $pid)"
    echo "Logs: $LOG_FILE"
    echo "Visit http://localhost:9999"
}

_stop_all_services() {
    if [ ! -f "$CONFIG_FILE" ]; then
        return
    fi
    LP_CONFIG="$CONFIG_FILE" python3 -c "
import json, subprocess, os
with open(os.environ['LP_CONFIG']) as f:
    services = json.load(f)
for svc_id, svc in services.items():
    script = svc.get('path', '') + '/.launchpad/stop.sh'
    result = subprocess.run(['bash', script], capture_output=True, text=True, timeout=30)
    if result.returncode == 0:
        print(f'  ✓ {svc[\"label\"]}')
    else:
        print(f'  ✗ {svc[\"label\"]}: {result.stderr.strip() or result.stdout.strip()}')
" 2>/dev/null || true
}

server_stop() {
    if [ ! -f "$PID_FILE" ]; then
        echo "Launchpad is not running (no PID file)"
        exit 1
    fi

    echo "Stopping all services..."
    _stop_all_services

    pid=$(cat "$PID_FILE")
    if kill "$pid" 2>/dev/null; then
        # Wait for the process to actually exit
        for i in 1 2 3 4 5; do
            kill -0 "$pid" 2>/dev/null || { echo "Launchpad stopped (PID $pid)"; rm -f "$PID_FILE"; return 0; }
            sleep 1
        done
        # Force kill if still alive
        kill -9 "$pid" 2>/dev/null || true
        echo "Launchpad force killed (PID $pid)"
    else
        echo "Process $pid not found, removing stale PID file"
    fi
    rm -f "$PID_FILE"
}

server_status() {
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Launchpad is running (PID $pid) — http://localhost:9999"
            return 0
        fi
        echo "Launchpad PID file exists but process is dead"
        return 1
    fi
    echo "Launchpad is not running"
    return 1
}

server_restart() {
    server_stop
    sleep 1
    server_start
}

# ── Services ──

_svc_path() {
    LP_SVC_ID="$1" LP_CONFIG="$CONFIG_FILE" python3 -c "
import json, os
try:
    svc = json.load(open(os.environ['LP_CONFIG'])).get(os.environ['LP_SVC_ID'], {})
    print(svc.get('path', ''))
except Exception:
    pass
"
}

svc_run() {
    local id="$1"
    local dir
    dir=$(_svc_path "$id")
    [ -n "$dir" ] || { echo "Service '$id' not found"; exit 1; }

    local script="$dir/.launchpad/start.sh"
    [ -f "$script" ] || { echo "start.sh not found in $dir/.launchpad/"; exit 1; }

    echo "Starting $id..."
    bash "$script" && echo "$id started"
}

svc_kill() {
    local id="$1"
    local dir
    dir=$(_svc_path "$id")
    [ -n "$dir" ] || { echo "Service '$id' not found"; exit 1; }

    local script="$dir/.launchpad/stop.sh"
    [ -f "$script" ] || { echo "stop.sh not found in $dir/.launchpad/"; exit 1; }

    echo "Stopping $id..."
    bash "$script" && echo "$id stopped"
}

svc_add() {
    local name="${1:-}"
    local path="${2:-}"

    if [ -z "$name" ] || [ -z "$path" ]; then
        echo "Usage: launchpad add <name> <path>"
        echo ""
        echo "  name  Display name (also used as ID)"
        echo "  path  Absolute or relative path to the service directory"
        exit 1
    fi

    path="$(cd "$path" 2>/dev/null && pwd)" || {
        echo "Directory not found: $path"
        exit 1
    }

    local id
    id=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g' | sed 's/^-\+//;s/-\+$//')
    [ -z "$id" ] && id=$(basename "$path")

    if [ ! -f "$path/.launchpad/start.sh" ] || [ ! -f "$path/.launchpad/stop.sh" ]; then
        echo "Error: $path/.launchpad/ is missing start.sh or stop.sh"
        echo "Create them first, or use /launchpad skill to auto-generate"
        exit 1
    fi

    LP_CONFIG="$CONFIG_FILE" LP_ID="$id" LP_NAME="$name" LP_PATH="$path" python3 -c "
import json, os
cfg_path = os.environ['LP_CONFIG']
with open(cfg_path) as f:
    services = json.load(f)
svc_id = os.environ['LP_ID']
services[svc_id] = {
    'label': os.environ['LP_NAME'],
    'icon': '📦',
    'path': os.environ['LP_PATH'],
    'description': ''
}
with open(cfg_path, 'w') as f:
    json.dump(services, f, ensure_ascii=False, indent=2)
print('Registered: ' + os.environ['LP_NAME'] + ' (' + svc_id + ')')
"
}

svc_list() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "No services configured"
        return
    fi

    LP_CONFIG="$CONFIG_FILE" python3 -c "
import json, os, subprocess, sys, socket
from urllib.parse import urlparse
from concurrent.futures import ThreadPoolExecutor, as_completed

# One-shot: collect all listening ports
listeners: set[str] = set()
try:
    r = subprocess.run(['ss', '-tlnp', '--no-header'], capture_output=True, text=True, timeout=5)
    for line in r.stdout.strip().split('\n'):
        parts = line.strip().split()
        if len(parts) >= 4:
            listeners.add(parts[3].rsplit(':', 1)[-1])
except Exception:
    pass

cfg = json.load(open(os.environ['LP_CONFIG']))

def get_status(svc_id, svc):
    path = svc.get('path', '')
    label = svc.get('label', '')
    url = svc.get('url', '')
    if not os.path.isdir(path):
        return (svc_id, 'missing', label)
    # Check url port first (works for both docker and non-docker)
    if url:
        parsed = urlparse(url)
        port = str(parsed.port) if parsed.port else ''
        if port and port in listeners:
            return (svc_id, 'running', label)
        if port:
            return (svc_id, 'stopped', label)
    # No url: fallback detection
    is_docker = any(
        os.path.isfile(os.path.join(path, name))
        for name in ('docker-compose.yml', 'docker-compose.yaml', 'compose.yaml')
    )
    if is_docker:
        project = os.path.basename(os.path.normpath(path))
        r = subprocess.run(
            ['docker', 'ps', '--filter', f'label=com.docker.compose.project={project}',
             '--format', '{{.Names}}'],
            capture_output=True, text=True, timeout=5
        )
        return (svc_id, 'running' if r.returncode == 0 and r.stdout.strip() else 'stopped', label)
    # Non-docker without url: check /proc/<pid>/cwd
    running = False
    for p in os.listdir('/proc'):
        if not p.isdigit():
            continue
        try:
            cwd = os.readlink(f'/proc/{p}/cwd')
            if os.path.samefile(cwd, path):
                running = True
                break
        except OSError:
            continue
    return (svc_id, 'running' if running else 'stopped', label)

with ThreadPoolExecutor(max_workers=8) as pool:
    futures = {pool.submit(get_status, k, v): k for k, v in cfg.items()}
    results = [f.result() for f in as_completed(futures)]

print(f'{\"ID\":<20} {\"STATE\":<8}  LABEL')
print('------------------------------')
for svc_id, state, label in sorted(results, key=lambda x: x[0]):
    print(f'{svc_id:<20} {state:<8}  {label}')
" 2>/dev/null || {
    # Fallback: just dump ids
    LP_CONFIG="$CONFIG_FILE" python3 -c "
import json, os
cfg = json.load(open(os.environ['LP_CONFIG']))
for k in cfg:
    print(k)
" 2>/dev/null || echo 'error listing services'
}
}

svc_remove() {
    local id="$1"
    [ -n "$id" ] || { echo "Usage: launchpad remove <id>"; exit 1; }

    LP_SVC_ID="$id" LP_CONFIG="$CONFIG_FILE" python3 -c "
import json, os, subprocess, socket
from urllib.parse import urlparse

svc_id = os.environ['LP_SVC_ID']
cfg_path = os.environ['LP_CONFIG']

with open(cfg_path) as f:
    services = json.load(f)

svc = services.get(svc_id)
if not svc:
    print(f'Service \"{svc_id}\" not found')
    exit(1)

label = svc.get('label', svc_id)
path = svc.get('path', '')
url = svc.get('url', '')

# Check if service is still running
running = False
if url:
    parsed = urlparse(url)
    port = str(parsed.port) if parsed.port else ''
    if port:
        try:
            r = subprocess.run(['ss', '-tlnp', '--no-header'], capture_output=True, text=True, timeout=5)
            for line in r.stdout.strip().split('\n'):
                parts = line.strip().split()
                if len(parts) >= 4 and parts[3].rsplit(':', 1)[-1] == port:
                    running = True
                    break
        except Exception:
            pass
elif path and os.path.isdir(path):
    is_docker = any(
        os.path.isfile(os.path.join(path, name))
        for name in ('docker-compose.yml', 'docker-compose.yaml', 'compose.yaml')
    )
    if is_docker:
        project = os.path.basename(os.path.normpath(path))
        r = subprocess.run(
            ['docker', 'ps', '--filter', f'label=com.docker.compose.project={project}', '--format', '{{.Names}}'],
            capture_output=True, text=True, timeout=5
        )
        running = r.returncode == 0 and bool(r.stdout.strip())

if running:
    print(f'{label} ({svc_id}) is still running — stop it first with \"lp kill {svc_id}\"')
    exit(1)

del services[svc_id]
with open(cfg_path, 'w') as f:
    json.dump(services, f, ensure_ascii=False, indent=2)
print(f'Removed: {label} ({svc_id})')
"
}

# ── Dispatch ──

case "${1:-}" in
    # Server commands
    start) server_start ;;
    stop) server_stop ;;
    status) server_status ;;
    restart) server_restart ;;

    # Service commands
    run) shift; svc_run "$@" ;;
    kill) shift; svc_kill "$@" ;;
    register) shift; svc_add "$@" ;;
    add) shift; svc_add "$@" ;;
    remove) shift; svc_remove "$@" ;;
    list) svc_list ;;

    # Install
    install)
        target="${2:-$HOME/.local/bin/lp}"
        mkdir -p "$(dirname "$target")"
        ln -sf "$SCRIPT_DIR/launch.sh" "$target"
        chmod +x "$SCRIPT_DIR/launch.sh"

        mkdir -p "$DATA_DIR"
        if [ ! -f "$CONFIG_FILE" ] && [ -f "$SCRIPT_DIR/services.json" ]; then
            cp "$SCRIPT_DIR/services.json" "$CONFIG_FILE"
            echo "Copied default services.json to $CONFIG_FILE"
        fi

        echo "Installed to $target"
        echo "Data directory: $DATA_DIR"
        echo "Make sure $(dirname "$target") is in your PATH"
        ;;
    uninstall)
        rm -f "$HOME/.local/bin/lp" "$HOME/.local/bin/launchpad" 2>/dev/null
        echo "Uninstalled"
        echo "Note: data in $DATA_DIR was kept"
        ;;

    *)
        echo "Usage: launchpad <command>"
        echo ""
        echo "  Server:"
        echo "    start       Start the web server"
        echo "    stop        Stop the web server"
        echo "    status      Check if server is running"
        echo "    restart     Restart the web server"
        echo ""
        echo "  Services:"
        echo "    list        List all registered services"
        echo "    run <id>    Start a service"
        echo "    kill <id>   Stop a service"
        echo "    remove <id>  Delete a service from registry"
        echo "    register <name> <path>  Register a new service"
        echo ""
        echo "  Setup:"
        echo "    install [path]  Install 'lp' command (default ~/.local/bin)"
        echo "    uninstall       Remove the installed command"
        ;;
esac
