---
name: launchpad
description: Add, remove, or manage services in Launchpad — the local service management dashboard. Use when the user wants to register a new service, delete a service, or check service status. Run `chmod +x /path/to/launchpad/launch.sh` if not already executable.
---

# Launchpad Skill

Launchpad is a web dashboard for managing local services. Each service stores its scripts in a `.launchpad/` subdirectory (so they don't conflict with any existing scripts in the project). The start/stop scripts plus a registration entry in `services.json` are all that's needed.

## Quick Reference

| Command | What it does |
|---------|-------------|
| `lp start` | Start web panel |
| `lp list` | List all services |
| `lp run <id>` | Start a service |
| `lp stop <id>` | Stop a service |
| `lp register <name> <path>` | Register a new service |

## Reference

- **Project dir**: `/path/to/launchpad/`
- **CLI command**: `lp` (installed via `bash launch.sh install`)
- **Config file**: `services.json`
- **Server script**: `server.py`
- **Launch script**: `launch.sh` (CLI entry point)
- **Frontend**: `index.html`

## Workflow

### 1. Read the Project First

The user might say "add ~/workflow/xxx as a service". Before doing anything:

- Read key files: `README.md`, `package.json`, `Dockerfile`, `docker-compose.yml`, `main.py`, `index.js`, etc.
- Understand what the project actually is: a web service? a CLI tool? a library? a config?

If it's NOT a service (library, CLI tool, config files, etc.), tell the user:

> "This project looks like a [library/CLI/config], not a long-running service. It doesn't need start/stop scripts. Are you sure you want to add it?"

Only proceed if the user confirms or if it's clearly a long-running service (web server, API, worker, bot, etc.).

### 2. Detect Script Status

Check whether scripts exist in the `.launchpad/` subdirectory:

```
path/
├── .launchpad/
│   ├── start.sh     ✓ or ✗
│   └── stop.sh      ✓ or ✗
├── docker-compose.yml  (present or not)
└── ...other files
```

Report to the user what's in place and what's missing. If no scripts exist, ask what commands should go in them.

### 3. Gather Service Info

Ask the user (or use provided info) for:

| Field | Required | Description |
|-------|----------|-------------|
| `id` | ✅ | URL-safe slug, e.g. `my-service` |
| `label` | ✅ | Display name, e.g. `My Service` |
| `icon` | ✅ | Single emoji, e.g. `🚀` |
| `path` | ✅ | Absolute path to the project directory |
| `url` | ❌ | Direct link to open the service, e.g. `http://localhost:5678` |
| `description` | ❌ | Short description of what it does |

### 4. Create Scripts (if missing)

If `.launchpad/start.sh` or `.launchpad/stop.sh` don't exist, create them in the `.launchpad/` subdirectory and `chmod +x`.

Base the script template on what you detected:
- Has `docker-compose.yml` → use docker compose template
- Has no compose file → ask what command to run

**Important:** Scripts use `cd "$(dirname "$0")/.."` to reach the project root since they live in `.launchpad/`.

**Common patterns:**

- **Docker service** (`docker compose up -d` / `docker compose down`):
  ```bash
  # .launchpad/start.sh
  #!/usr/bin/env bash
  set -euo pipefail
  cd "$(dirname "$0")/.."
  docker compose up -d "$@"
  ```
  ```bash
  # .launchpad/stop.sh
  #!/usr/bin/env bash
  set -euo pipefail
  cd "$(dirname "$0")/.."
  docker compose down "$@"
  ```

- **Generic service** (direct process):
  ```bash
  # .launchpad/start.sh
  #!/usr/bin/env bash
  set -euo pipefail
  cd "$(dirname "$0")/.."
  nohup <command> >> service.log 2>&1 &
  disown $! 2>/dev/null || true
  ```
  ```bash
  # .launchpad/stop.sh
  #!/usr/bin/env bash
  set -euo pipefail
  cd "$(dirname "$0")/.."
  pkill -f "<process-marker>" 2>/dev/null || true
  ```

### 5. Register in services.json

Read and update `/path/to/launchpad/services.json`. Each entry:

```json
{
  "<service-id>": {
    "label": "Display Name",
    "icon": "🚀",
    "path": "/absolute/path/to/service",
    "url": "http://localhost:5678",
    "description": "What this service does"
  }
}
```

Use the Edit tool to modify services.json, or read and rewrite it.

### 6. Start Launchpad Server

If the Launchpad server isn't running, start it:

```bash
bash /path/to/launchpad/launch.sh start
# or if installed: lp start
```

### 7. Verify

- Confirm `.launchpad/start.sh` and `.launchpad/stop.sh` exist and are executable
- Confirm services.json registration is correct
- Open http://localhost:9999 to verify the service appears

## Removing a Service

When asked to remove/delete a service:
1. Remove the entry from `services.json`
2. Ask if they want to keep the `.launchpad/` scripts or delete them too
