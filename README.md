# 🚀 Launchpad

Local services dashboard — managed by you, or by your AI agent.

[![GitHub](https://img.shields.io/badge/GitHub-nobodyaaa/launchpad-181717?logo=github)](https://github.com/nobodyaaa/launchpad)
[![Claude Code](https://img.shields.io/badge/Claude_Code-/lp-8A2BE2?logo=claude)](.)

Launchpad is a **zero-dependency** web panel for managing local services. Any service that can be started with `start.sh` and stopped with `stop.sh` works — Docker or not.

Its killer feature: **Claude Code can manage it for you.** Tell Claude "add my blog service" or "start the database," and it handles everything — creating scripts, registering the service, and monitoring status.

## Quick Start

```bash
# Install the global `lp` command
bash launch.sh install

# Start the web panel
lp start

# Open http://localhost:9999
```

Or run directly: `python3 server.py`

## AI Agent Features

Launchpad is built to be managed by Claude Code through `/lp`:

| What you say | What happens |
|---|---|
| `/lp add my-blog ~/projects/blog` | Claude creates `.launchpad/start` & `.launchpad/stop`, registers the service |
| `/lp status` | Claude checks panel status and lists all services |
| `/lp start db` | Claude runs `lp run db` |
| `/lp kill api` | Claude runs `lp kill api` |
| `/lp status` | Claude queries and summarizes service states |

## Features

- **AI-native** — full Claude Code skill (`/lp`) for natural language management
- **One-click start/stop** via web UI for any local service
- **Docker integration** — auto-detects container status, port mappings, and logs
- **Generic services** — works with any process, Docker or not
- **Live status** — auto-refreshes every 15 seconds, no page reload needed
- **Zero dependencies** — Python stdlib only on the backend, vanilla HTML/CSS/JS on the frontend

## How It Works

Every service needs two scripts inside a `.launchpad/` subdirectory. Claude Code's `/lp` skill can generate these for you automatically.

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
- Start/stop with live status detection

## CLI Commands (`lp`)

Once installed, `lp` works from any directory:

```bash
# Service management
lp list                    # List all services with status
lp run n8n                 # Start a service
lp kill n8n                # Stop a service
lp remove n8n              # Delete a service from registry
lp register MyApp ~/app    # Register a new service

# Panel control
lp start                   # Start the web panel (port 9999)
lp stop                    # Stop the panel + all services
lp status                  # Check if the panel is running
lp restart                 # Restart the panel
```

## Adding a New Service

Three ways, pick your favorite:

**🤖 Via Claude Code** — say "add my app" and Claude generates scripts + registers it
**⌨️ Via CLI** — `lp register MyApp /path/to/project`
**🖱️ Via Web UI** — click **+ Add Service** and fill in the form

Whichever you choose, Launchpad requires `.launchpad/start.sh` and `.launchpad/stop.sh` in the project directory.

## Claude Code Skill Setup

To let Claude manage Launchpad for you, install the `/lp` skill:

```bash
# 1. Clone the repo
git clone https://github.com/nobodyaaa/launchpad.git
cd launchpad

# 2. Install the global `lp` command
bash launch.sh install

# 3. Install the skill
cp SKILL.md ~/.claude/skills/launchpad/SKILL.md
#    Then edit SKILL.md — replace <launchpad-dir> with your actual path

# 4. Start the panel
lp start
```

Now when you ask Claude "add my service" or "check what's running," it handles the rest via `/lp`.

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
