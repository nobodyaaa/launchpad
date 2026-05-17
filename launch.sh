#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

PID_FILE=".launchpad.pid"
LOG_FILE="launchpad.log"

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

case "${1:-start}" in
    start) start ;;
    stop) stop ;;
    status) status ;;
    restart) stop; sleep 1; start ;;
    *) echo "Usage: $0 {start|stop|status|restart}"; exit 1 ;;
esac
