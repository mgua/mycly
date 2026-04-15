# mycly — Make Any Machine Yours

An AI-assisted agent that transforms any machine into your personal working environment.

## Quick Start

```bash
# 1. Clone the repo
git clone <your-gitolite-url>/mycly.git
cd mycly

# 2. Configure your inference backend
cp .env.template .env
# Edit .env — set MYCLY_INFERENCE_URL and MYCLY_MODEL

# 3. Create your desired-state file
cp templates/desired-state.template.toml config/desired-state.toml
# Edit config/desired-state.toml with your preferences

# 4. Run mycly
python3 stage1/mycly.py status    # See what mycly detects
python3 stage1/mycly.py apply     # Apply your desired state
python3 stage1/mycly.py           # Interactive session
```

## Requirements

- Python 3.10+
- An inference backend compatible with the Anthropic Messages API (Ollama, vLLM, LiteLLM, etc.)
- No pip dependencies for core functionality

## Commands

| Command | Description |
|---------|-------------|
| `mycly` | Interactive session — chat with the agent about your system |
| `mycly status` | Show system state and drift from desired configuration |
| `mycly apply` | Apply desired state: install tools, write configs, set up shell |
| `mycly undo` | Undo the last recorded action |
| `mycly log` | Show recent action history |

## Project Structure

```
mycly/
├── .env.template                # Inference backend config (copy to .env)
├── .gitignore                   # Protects private files
├── stage0/
│   ├── boot.sh                  # Unix bootstrap (wget|bash)
│   └── boot.ps1                # Windows bootstrap (irm|iex)
├── stage1/
│   └── mycly.py                 # The agent (Python 3.10+)
├── templates/
│   └── desired-state.template.toml  # Example desired-state config
├── config/                      # Your private configs (gitignored)
│   └── desired-state.toml       # Your actual desired state
├── mycly-spec.md                # Architecture & vision document
├── mycly-conversation-log.md    # Design decision log
└── mycly-operations.md          # Operational documentation
```

## File Naming Convention

- `templates/*.template.*` — Non-private templates, committed to repo
- `config/*` — Private production files, gitignored, synced via chezmoi
- `.env` — Private environment config, gitignored

## Documentation

- **[mycly-spec.md](mycly-spec.md)** — Strategic vision, architecture, security model, roadmap
- **[mycly-operations.md](mycly-operations.md)** — Technical reference, testing, deployment
- **[mycly-conversation-log.md](mycly-conversation-log.md)** — Design session decisions and rationale

## License

Private / TBD
