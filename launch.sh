#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

PID_FILE=".launchpad.pid"
LOG_FILE="launchpad.log"
CONFIG_FILE="services.json"

start() {
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Launchpad is already running (PID $pid)"
            echo "Visit http://localhost:9999"
            exit 0
        fi
        rm "$PID_FILE"
    fi

    nohup python3 server.py >> "$LOG_FILE" 2>&1 &
    pid=$!
    echo $pid > "$PID_FILE"
    disown "$pid" 2>/dev/null || true

    echo "Launchpad started (PID $pid)"
    echo "Logs: $LOG_FILE"
    echo "Visit http://localhost:9999"
}

stop() {
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

status() {
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Launchpad is running (PID $pid)"
            echo "Visit http://localhost:9999"
            return 0
        fi
        echo "Launchpad PID file exists but process is dead"
        return 1
    fi
    echo "Launchpad is not running"
    return 1
}

run_service() {
    local id="$1"
    if [ -z "$id" ]; then
        echo "Usage: $0 run <service-id>"
        exit 1
    fi
    local dir
    dir=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    svc = json.load(f).get('$id', {})
print(svc.get('path', ''))
")
    if [ -z "$dir" ]; then
        echo "Service '$id' not found in $CONFIG_FILE"
        exit 1
    fi
    local script="$dir/.launchpad/start.sh"
    if [ ! -f "$script" ]; then
        echo "start.sh not found in $dir/.launchpad/"
        exit 1
    fi
    echo "Starting $id..."
    bash "$script"
    echo "$id started"
}

kill_service() {
    local id="$1"
    if [ -z "$id" ]; then
        echo "Usage: $0 kill <service-id>"
        exit 1
    fi
    local dir
    dir=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    svc = json.load(f).get('$id', {})
print(svc.get('path', ''))
")
    if [ -z "$dir" ]; then
        echo "Service '$id' not found in $CONFIG_FILE"
        exit 1
    fi
    local script="$dir/.launchpad/stop.sh"
    if [ ! -f "$script" ]; then
        echo "stop.sh not found in $dir/.launchpad/"
        exit 1
    fi
    echo "Stopping $id..."
    bash "$script"
    echo "$id stopped"
}

add_service() {
    local path="${1:-}"
    local label="${2:-}"
    local icon="${3:-📦}"

    if [ -z "$path" ]; then
        echo "Usage: $0 add <path> [label] [icon]"
        echo ""
        echo "  path   Absolute path to the service directory"
        echo "  label  Display name (default: directory name)"
        echo "  icon   Emoji icon (default: 📦)"
        exit 1
    fi

    # Resolve to absolute path
    path="$(cd "$path" 2>/dev/null && pwd)" || {
        echo "Directory not found: $path"
        exit 1
    }

    local id
    id=$(basename "$path" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g')
    [ -z "$label" ] && label=$(basename "$path")

    # Register in services.json
    python3 -c "
import json
with open('$CONFIG_FILE') as f:
    services = json.load(f)
services['$id'] = {
    'label': '$label',
    'icon': '$icon',
    'path': '$path',
    'description': ''
}
with open('$CONFIG_FILE', 'w') as f:
    json.dump(services, f, ensure_ascii=False, indent=2)
print('Registered: $label ($id)')
"

    # Notify running server to refresh
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Server is running — refresh http://localhost:9999 to see it"
        fi
    fi
}

case "${1:-}" in
    start) start ;;
    stop) stop ;;
    status) status ;;
    restart) stop; sleep 1; start ;;
    run) shift; run_service "$@" ;;
    kill) shift; kill_service "$@" ;;
    add) shift; add_service "$@" ;;
    *)
        echo "Usage: $0 {start|stop|status|restart|run|kill|add}"
        echo ""
        echo "  Server:"
        echo "    start    Start the Launchpad web server"
        echo "    stop     Stop the Launchpad web server"
        echo "    status   Check if the server is running"
        echo "    restart  Restart the server"
        echo ""
        echo "  Services:"
        echo "    run <id>  Start a service by its ID"
        echo "    kill <id> Stop a service by its ID"
        echo "    add <path> [label] [icon]  Register a new service"
        exit 1
        ;;
esac
