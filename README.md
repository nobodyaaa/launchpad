# 🚀 Launchpad

A web dashboard for managing local services. Any service that can be started with `start.sh` and stopped with `stop.sh` — Docker or not — works with Launchpad.

[![GitHub](https://img.shields.io/badge/GitHub-nobodyaaa/launchpad-181717?logo=github)](https://github.com/nobodyaaa/launchpad)

## Quick Start

```bash
# Install the global `lp` command
bash launch.sh install

# Start the web panel
lp start

# Open http://localhost:9999
```

Or run directly:

```bash
python3 server.py
```

## Features

- **One-click start/stop** for any local service
- **Docker integration** — auto-detects container status, port mappings, and logs
- **Generic services** — works without Docker for any process
- **Live status** — auto-refreshes every 15 seconds
- **AI-assisted setup** — use `/launchpad` in Claude Code to add services interactively

## How It Works

Every service needs two scripts inside a `.launchpad/` subdirectory:

| Script | Purpose | Required |
|--------|---------|----------|
| `.launchpad/start.sh` | Start the service | ✅ |
| `.launchpad/stop.sh` | Stop the service | ✅ |

If either script is missing, the web UI shows a warning and disables the action buttons.

### Service Types

**Docker services** — project has a `docker-compose.yml` or `.yaml`
- Auto-detects container state and port mappings
- Container logs available in the UI

**Generic services** — no docker-compose file
- Start/stop only
- State shows `—`

## CLI Commands (`lp`)

Once installed, `lp` works from any directory:

```bash
# Service management
lp list                    # List all services with status
lp run n8n                 # Start a service
lp stop n8n                # Stop a service
lp register MyApp ~/app    # Register a new service

# Panel control
lp start                   # Start the web panel
lp stop                    # Stop the web panel
lp status                  # Check if the panel is running
lp restart                 # Restart the panel
```

## Adding a New Service

1. Create `.launchpad/start.sh` and `.launchpad/stop.sh` in the project directory (`chmod +x`)
2. Run `lp register MyService /path/to/project`
3. Or click **+ Add Service** in the web UI
4. Or use the `/launchpad` command in Claude Code

## Claude Code Skill Setup

```bash
# 1. Clone the repo
git clone https://github.com/nobodyaaa/launchpad.git
cd launchpad

# 2. Install the global `lp` command
bash launch.sh install

# 3. Install the launchpad skill
mkdir -p ~/.claude/skills/launchpad
cp SKILL.md ~/.claude/skills/launchpad/SKILL.md

# 4. Edit SKILL.md — replace <launchpad-dir> with your actual path
#    vim ~/.claude/skills/launchpad/SKILL.md

# 5. Start the panel
lp start
```

Then use `/launchpad` in Claude Code to add or manage services.

## File Structure

```
launchpad/
├── server.py          # Python backend (stdlib only, zero dependencies)
├── index.html         # Management UI
├── launch.sh          # CLI entry point (installed as `lp`)
├── SKILL.md           # Claude Code skill definition
├── CLAUDE.md          # Development conventions
└── README.md          # This file

~/.launchpad/          # Runtime data (separate from source)
  ├── services.json    # Registered services
  ├── launchpad.log    # Server logs
  └── .launchpad.pid   # Process PID
```
