#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PID_FILE="$SCRIPT_DIR/.launchpad.pid"
LOG_FILE="$SCRIPT_DIR/launchpad.log"
CONFIG_FILE="$SCRIPT_DIR/services.json"
SERVER_SCRIPT="$SCRIPT_DIR/server.py"

API="http://127.0.0.1:9999/api/services"

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

    nohup python3 "$SERVER_SCRIPT" >> "$LOG_FILE" 2>&1 &
    pid=$!
    echo $pid > "$PID_FILE"
    disown "$pid" 2>/dev/null || true

    echo "Launchpad started (PID $pid)"
    echo "Logs: $LOG_FILE"
    echo "Visit http://localhost:9999"
}

server_stop() {
    if [ ! -f "$PID_FILE" ]; then
        echo "Launchpad is not running (no PID file)"
        exit 1
    fi
    pid=$(cat "$PID_FILE")
    if kill "$pid" 2>/dev/null; then
        echo "Launchpad stopped (PID $pid)"
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
    python3 -c "
import json, sys
try:
    svc = json.load(open('$CONFIG_FILE')).get('$1', {})
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

    python3 -c "
import json
with open('$CONFIG_FILE') as f:
    services = json.load(f)
services['$id'] = {
    'label': '$name',
    'icon': '📦',
    'path': '$path',
    'description': ''
}
with open('$CONFIG_FILE', 'w') as f:
    json.dump(services, f, ensure_ascii=False, indent=2)
print('Registered: $name ($id)')
"

    [ -d "$path/.launchpad" ] || echo "Note: $path/.launchpad/ doesn't exist — create start.sh and stop.sh"
}

svc_list() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "No services configured"
        return
    fi

    printf "%-20s %-8s  %s\n" "ID" "STATE" "LABEL"
    printf -- "------------------------------\n"

    python3 -c "
import json
cfg = json.load(open('$CONFIG_FILE'))
for k, v in cfg.items():
    state = '?'
    print(f'{k:<20} {state:<8} {v.get(\"label\", \"\")}')
" | column -t -s $'\t'
}

svc_list_with_status() {
    # Fetch from API for live status
    local data
    data=$(curl -sf "$API" 2>/dev/null) || {
        svc_list
        return
    }
    python3 -c "
import json
services = json.loads('''$data''')
for s in services:
    state = s.get('state', '?')
    url = s.get('url', '')
    print(f'{s[\"id\"]:<20} {state:<8} {s[\"label\"]}  {url}')
" 2>/dev/null || svc_list
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
    stop) shift; svc_kill "$@" ;;
    kill) shift; svc_kill "$@" ;;
    register) shift; svc_add "$@" ;;
    add) shift; svc_add "$@" ;;
    list)
        if server_status >/dev/null 2>&1; then
            svc_list_with_status
        else
            svc_list
        fi
        ;;

    # Install
    install)
        local target="${2:-$HOME/.local/bin/lp}"
        mkdir -p "$(dirname "$target")"
        ln -sf "$SCRIPT_DIR/launch.sh" "$target"
        chmod +x "$SCRIPT_DIR/launch.sh"
        echo "Installed to $target"
        echo "Make sure $(dirname "$target") is in your PATH"
        ;;
    uninstall)
        rm -f "$HOME/.local/bin/lp" "$HOME/.local/bin/launchpad" 2>/dev/null
        echo "Uninstalled"
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
        echo "    stop <id>   Stop a service"
        echo "    register <name> <path>  Register a new service"
        echo ""
        echo "  Setup:"
        echo "    install [path]  Install 'lp' command (default ~/.local/bin)"
        echo "    uninstall       Remove the installed command"
        ;;
esac
