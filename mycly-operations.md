# mycly — Operations Documentation

**Version:** 0.1.0-alpha
**Last updated:** 2026-03-19
**Status:** Stage 0 bootstrap implemented, Stage 1+ in design

---

## 1. Project Structure

```
mycly/
├── README.md                    # Public-facing project description
├── mycly-spec.md                # Strategic vision & architecture specification
├── mycly-conversation-log.md    # Design session log and decision record
├── mycly-operations.md          # This file — operational documentation
├── stage0/
│   ├── boot.sh                  # Unix bootstrap script (bash)
│   └── boot.ps1                # Windows bootstrap script (PowerShell 5.1+)
├── stage1/                      # Agent implementations (future)
│   ├── python/                  # Full-capability Python agent
│   ├── node/                    # Node.js agent variant
│   ├── bash/                    # Lightweight bash agent
│   └── powershell/              # Windows PowerShell agent
├── backend/                     # Auth service & API (future)
│   ├── auth/                    # Session management, device code flow
│   ├── api/                     # Stage 1 distribution, telemetry
│   └── web/                     # mycly.dev landing page
├── specs/                       # Detailed sub-specifications (future)
│   ├── desired-state-schema.md  # TOML schema formal definition
│   ├── firewall-policy.md       # Semantic firewall policy format
│   ├── trust-tiers.md           # Trust tier transition criteria
│   └── inference-routing.md     # Multi-backend routing rules
└── tests/
    ├── stage0/                  # Bootstrap script tests
    ├── integration/             # Cross-platform integration tests
    └── fixtures/                # Test system profiles
```

---

## 2. Development Environment Setup

### Prerequisites

Development of mycly itself requires:

- Git
- Bash 4+ (for associative arrays in boot.sh)
- PowerShell 5.1+ (for boot.ps1 testing; available on Linux/macOS via `pwsh`)
- Python 3.8+ (for Stage 1 development)
- shellcheck (for bash linting)
- A text editor (neovim recommended)

### Getting Started

```bash
git clone https://github.com/mgua/mycly.git
cd mycly

# Verify bash script syntax
bash -n stage0/boot.sh

# Lint bash script
shellcheck stage0/boot.sh

# Test the bash bootstrap in dry-run mode (when implemented)
MYCLY_DRY_RUN=1 bash stage0/boot.sh

# Test the PowerShell bootstrap (requires pwsh or Windows)
pwsh -NoProfile -File stage0/boot.ps1
```

---

## 3. Stage 0 Bootstrap — Technical Reference

### 3.1 Unix Bootstrap (`boot.sh`)

#### Invocation Methods

```bash
# Standard — via wget (most universal, present in BusyBox)
wget -qO- https://mycly.dev/boot | bash

# Alternative — via curl
curl -fsSL https://mycly.dev/boot | bash

# Local testing
bash stage0/boot.sh

# With debug output
MYCLY_DEBUG=1 bash stage0/boot.sh
```

#### Execution Flow

```
main()
├── setup_colors()           # Detect terminal capabilities
├── show_banner()            # Display mycly branding
├── detect_downloader()      # Find wget or curl
├── detect_system()          # OS, arch, kernel, hostname
├── detect_distro()          # Distribution family, version, libc
├── detect_resources()       # Memory, disk, CPU, GPU, terminal size
├── detect_privileges()      # root, sudo, package managers
├── detect_tools()           # Runtime and tool inventory
├── check_network()          # Connectivity, proxy
├── authenticate()           # Email → QR/code → poll → session
├── prepare_stage1()         # Select and download agent variant
├── write_system_report()    # JSON report to ~/.mycly/
└── show_summary()           # Final status display
```

#### Key Design Decisions

**Input handling during piped execution.** When invoked as `wget | bash`, stdin is the script itself. User input (email prompt) is read from `/dev/tty` instead, which is the controlling terminal. This is the standard pattern used by all interactive pipe-to-shell installers.

**Downloader abstraction.** The script detects whether `wget` or `curl` is available and wraps both behind `fetch()` and `fetch_to()` functions. All HTTP operations go through this abstraction.

**Associative arrays.** The script uses bash associative arrays (`declare -A`) for structured data. This requires bash 4+, which is available on all modern Linux distributions. On macOS, the system bash is 3.2 but users typically have bash 4+ via Homebrew. If this becomes a problem, the arrays can be replaced with individual variables.

**Color and symbol detection.** Terminal capabilities are probed via `tput`. If the terminal doesn't support colors or Unicode, ASCII fallbacks are used for all symbols. The script never assumes a specific terminal emulator.

**Distro family detection.** Uses `/etc/os-release` (the modern systemd standard) with fallbacks to legacy files (`/etc/redhat-release`, `/etc/debian_version`). Maps specific distro IDs to families (debian, rhel, arch, alpine, suse, void) via both direct ID matching and `ID_LIKE` fallback.

**Libc detection.** Checks for musl shared objects and `ldd --version` output. Critical for selecting the correct pre-built binary (glibc vs. musl).

#### Output Files

| File | Location | Content |
|------|----------|---------|
| System report | `~/.mycly/system-report.json` | Full system profile in JSON |
| Session token | `~/.mycly/session` | Auth session ID (mode 600) |
| Agent version | `~/.mycly/agent/version` | Installed agent version |
| Agent type | `~/.mycly/agent/type` | python / node / bash |

#### Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `MYCLY_API_KEY` | Skip interactive auth, use direct API key | (none) |
| `MYCLY_DEBUG` | Enable debug output | (none) |
| `MYCLY_DRY_RUN` | Detect and report only, don't install | (none) |
| `http_proxy` / `https_proxy` | Proxy settings (auto-detected) | (none) |

---

### 3.2 Windows Bootstrap (`boot.ps1`)

#### Invocation Methods

```powershell
# Standard — one-liner
irm https://mycly.dev/boot.ps1 | iex

# If execution policy blocks it
Set-ExecutionPolicy Bypass -Scope Process -Force; irm https://mycly.dev/boot.ps1 | iex

# Permanent policy change for user (more permissive)
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
irm https://mycly.dev/boot.ps1 | iex

# Local testing
.\stage0\boot.ps1

# From CMD (if PowerShell is available)
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://mycly.dev/boot.ps1 | iex"
```

#### Execution Flow

```
Invoke-MyclyBootstrap
├── Show-Banner                  # Display mycly branding
├── Test-ExecutionPolicy         # Check and advise on policy
├── Find-SystemInfo              # Windows version, arch, PS version
├── Find-Resources               # Memory, disk, CPU, GPU via CIM
├── Find-Privileges              # Admin status, package managers, WSL, Git Bash
├── Find-Tools                   # Runtime and tool inventory
├── Test-Network                 # Connectivity, proxy, TLS version
├── Invoke-Authentication        # Email → code → poll → session
├── Install-Stage1               # Select and download agent, update PATH
├── Write-SystemReport           # JSON report to ~/.mycly/
└── Show-Summary                 # Final status display
```

#### Key Design Decisions

**PowerShell 5.1 compatibility.** The script avoids all PowerShell 7+ features: no null-coalescing (`??`), no ternary (`? :`), no pipeline chain operators (`&&`, `||`). Uses `if/else` blocks, `-ErrorAction SilentlyContinue`, and `try/catch` throughout. The `$PSVersionTable.PSEdition` property is checked but not relied upon.

**Execution policy handling.** This is the first thing the script checks. If the effective policy is `Restricted` or `AllSigned`, the script cannot continue — but instead of a cryptic error, it displays clear remediation steps with the exact commands to run, explaining the difference between session-scoped bypass (safer, temporary) and user-scoped RemoteSigned (permanent). This follows the Claude Code installation UX pattern.

**TLS enforcement.** Older Windows systems may default to TLS 1.0/1.1 for `System.Net.WebRequest`. The script checks `SecurityProtocol` and explicitly enables TLS 1.2 and 1.3 if they're not active. This prevents mysterious download failures on older Windows 10 builds.

**CIM over WMI.** Uses `Get-CimInstance` (the modern replacement for `Get-WmiObject`) for system information. CIM is available in PowerShell 3+ and is the recommended approach going forward.

**PATH management.** Adds `~/.local/bin` to the user's PATH via `[Environment]::SetEnvironmentVariable()` at the User scope. Also updates `$env:Path` for the current session. Checks for existing presence to avoid duplicates.

**WSL and Git Bash detection.** Both are important for the Windows CLI ecosystem. WSL presence is checked via `Get-Command wsl`, and available distros are listed. Git Bash is located by checking common installation paths (`Program Files`, `Program Files (x86)`, `LOCALAPPDATA`). This information helps Stage 1 decide whether to use native PowerShell tooling or bridge to a Unix-like environment.

#### Output Files

Same as Unix, located under `$env:USERPROFILE\.mycly\`:

| File | Location | Content |
|------|----------|---------|
| System report | `~\.mycly\system-report.json` | Full system profile in JSON |
| Session token | `~\.mycly\session` | Auth session ID |
| Agent version | `~\.mycly\agent\version` | Installed agent version |
| Agent type | `~\.mycly\agent\type` | python / node / powershell |

#### Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `MYCLY_API_KEY` | Skip interactive auth, use direct API key | (none) |

---

## 4. Authentication Service — Design Notes

The auth backend is not yet implemented. This section captures the design for future development.

### Device Authorization Flow

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Target Machine  │     │  mycly Backend    │     │  User's Phone   │
│  (Stage 0)       │     │  (mycly.dev)      │     │  (Browser)      │
└────────┬────────┘     └────────┬─────────┘     └────────┬────────┘
         │                       │                         │
         │ POST /api/v1/auth/init│                         │
         │  { email: "..." }     │                         │
         │──────────────────────>│                         │
         │                       │                         │
         │ { session_id,         │                         │
         │   short_code,         │                         │
         │   auth_url,           │                         │
         │   expires_in: 300 }   │                         │
         │<──────────────────────│                         │
         │                       │                         │
         │ Display QR code       │                         │
         │ or short code         │                         │
         │                       │  GET /auth?session=...  │
         │                       │<────────────────────────│
         │                       │                         │
         │                       │  Confirmation page      │
         │                       │────────────────────────>│
         │                       │                         │
         │                       │  POST /auth/confirm     │
         │                       │<────────────────────────│
         │                       │                         │
         │ GET /api/v1/auth/check│                         │
         │  { session_id }       │                         │
         │──────────────────────>│                         │
         │                       │                         │
         │ { authorized: true,   │                         │
         │   token: "..." }      │                         │
         │<──────────────────────│                         │
         │                       │                         │
```

### Backend Implementation Options

For the MVP, the backend can be minimal:

- **Cloudflare Worker + KV**: Stateless, globally distributed, free tier covers early usage. Session state in Workers KV. Auth pages served from Worker.
- **FastAPI on a VPS**: Simple Python service, PostgreSQL or Redis for sessions. Easy to develop and debug.
- **Serverless (AWS Lambda / GCP Cloud Functions)**: Pay-per-invocation, auto-scaling, but more complex deployment.

Recommended for MVP: **FastAPI + Redis**, deployed on a small VPS or Railway/Fly.io. Simple, debuggable, and easy for Marco to maintain.

### Token Scoping

- Session tokens expire after 24 hours
- Tokens are scoped to a machine fingerprint (hash of hostname + OS + arch)
- Tokens grant access to: Stage 1 download, inference API proxy (if using mycly's hosted backend), preference sync
- Tokens do NOT grant access to: other machines' data, account management, billing

---

## 5. Stage 1 Agent — Design Notes

Not yet implemented. Architecture from the spec:

### Python Agent (Full Capability)

```
~/.mycly/agent/
├── mycly-agent.py              # Main entry point
├── core/
│   ├── loop.py                 # Agent reasoning loop
│   ├── tools.py                # System manipulation tools
│   ├── state.py                # State tracking and snapshots
│   └── rollback.py             # Rollback management
├── inference/
│   ├── router.py               # Multi-backend routing
│   ├── firewall.py             # Semantic firewall
│   ├── backends.py             # Backend client implementations
│   └── sanitizer.py            # Context sanitization
├── modules/
│   ├── shell.py                # Shell setup module
│   ├── tools.py                # Tool installation module
│   ├── editor.py               # Editor setup module
│   ├── git.py                  # Git configuration module
│   ├── ssh.py                  # SSH setup module
│   ├── fonts.py                # Font installation module
│   └── dotfiles.py             # Dotfile management module
├── config/
│   └── desired-state.toml      # User's desired state
└── data/
    ├── system-report.json      # From Stage 0
    ├── session                  # Auth token
    ├── snapshots/               # Rollback snapshots
    └── log/                     # Action logs (JSON)
```

### Bash Agent (Lightweight)

For systems without Python — makes raw HTTPS POST calls to the inference API using wget/curl. Limited to Tier 0-1 operations. Cannot run the semantic firewall (no local model). Uses conservative regex-based redaction as a safety net.

### PowerShell Agent (Windows)

Windows-native agent using PowerShell. Can leverage .NET APIs for system configuration (registry, environment variables, shortcuts, taskbar). Integrates with winget/scoop/choco for package management.

---

## 6. Testing Strategy

### Stage 0 Testing

**Automated syntax checks:**
```bash
# Bash
bash -n stage0/boot.sh
shellcheck stage0/boot.sh

# PowerShell (requires pwsh)
pwsh -Command "& { \$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content stage0/boot.ps1 -Raw), [ref]\$null) }"
```

**Platform matrix testing:** Use Docker containers and VMs to test Stage 0 across target platforms:

| Platform | Container/Image | Notes |
|----------|----------------|-------|
| Ubuntu 22.04 | `ubuntu:22.04` | Primary target |
| Ubuntu 24.04 | `ubuntu:24.04` | Latest LTS |
| Debian 12 | `debian:12` | Stable |
| Fedora 40 | `fedora:40` | RHEL family |
| Rocky Linux 9 | `rockylinux:9` | Enterprise RHEL |
| Alpine 3.19 | `alpine:3.19` | musl libc, BusyBox |
| Arch Linux | `archlinux:latest` | Rolling release |
| Raspberry Pi OS | ARM VM or real hardware | ARM target |
| macOS | GitHub Actions runner | Darwin target |
| Windows 10 | GitHub Actions runner | PowerShell 5.1 |
| Windows 11 | GitHub Actions runner | PowerShell 5.1 + optional PS7 |

**Testing scenarios:**

1. **Minimal system.** Alpine container with only wget and busybox. Stage 0 should detect everything correctly and select bash agent.
2. **Full system.** Ubuntu with Python, Node, git, tmux, etc. Stage 0 should detect all tools and select Python agent.
3. **No network.** Container with no external connectivity. Stage 0 should report offline status and suggest offline mode.
4. **No sudo.** Non-root user in container without sudo. Stage 0 should detect and report, never attempt sudo.
5. **Windows restricted policy.** PowerShell with Restricted execution policy. boot.ps1 should display clear remediation.
6. **Piped execution.** `cat boot.sh | bash` — email prompt must work via /dev/tty.
7. **Tiny terminal.** Terminal set to 40x10. QR code should not render; short code shown instead.

### CI/CD Pipeline (Future)

```yaml
# GitHub Actions workflow sketch
name: Stage 0 Tests
on: [push, pull_request]
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: shellcheck stage0/boot.sh
      - run: bash -n stage0/boot.sh

  test-linux:
    strategy:
      matrix:
        container: [ubuntu:22.04, ubuntu:24.04, debian:12, fedora:40, alpine:3.19]
    runs-on: ubuntu-latest
    container: ${{ matrix.container }}
    steps:
      - uses: actions/checkout@v4
      - run: bash stage0/boot.sh  # With MYCLY_DRY_RUN=1

  test-macos:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash stage0/boot.sh

  test-windows:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - run: .\stage0\boot.ps1
        shell: powershell
```

---

## 7. Deployment — Web Infrastructure

### mycly.dev Website

The website serves two purposes:

1. **Landing page.** Explains what mycly is, shows the install command (auto-detected per OS), links to docs.
2. **Bootstrap script host.** Serves `boot.sh` and `boot.ps1` with correct MIME types.
3. **Auth pages.** Device authorization confirmation flow.

URL routing:

| URL | Response |
|-----|----------|
| `GET /` | Landing page (HTML, OS-detected install command) |
| `GET /boot` | `boot.sh` (Content-Type: text/x-shellscript) |
| `GET /boot.ps1` | `boot.ps1` (Content-Type: text/plain) |
| `GET /auth?session=...` | Auth confirmation page |
| `POST /api/v1/auth/init` | Create auth session |
| `GET /api/v1/auth/check?session=...` | Poll auth status |
| `POST /api/v1/auth/confirm` | User confirms auth |
| `GET /api/v1/stage1/:type/:os/:arch` | Stage 1 agent download |
| `GET /health` | Health check endpoint |

### Domain & Hosting

Recommended: **mycly.dev** domain with Cloudflare DNS. Static content (landing page, scripts) via Cloudflare Pages. API via a small backend (FastAPI on Fly.io / Railway / small VPS).

---

## 8. Security Considerations

### Script Distribution

- Scripts served over HTTPS only
- Consider adding a checksum verification step (like Claude Code's manifest.json approach)
- Script content should be reviewable — host the exact same scripts in the public GitHub repo so users can audit before running

### Session Security

- Session tokens are random, unpredictable, and short-lived (24h)
- Stored with mode 600 (Unix) or user-only ACL (Windows)
- Never sent to inference backends
- Revocable server-side

### Privacy During Bootstrap

- Stage 0 collects system information (OS, arch, tools) but does NOT:
  - Read file contents
  - Scan directories beyond checking for tool binaries
  - Collect usernames beyond the current user
  - Send any data anywhere before authentication is complete
- The system report is stored locally and only sent to the selected inference backend during Stage 1, subject to semantic firewall rules

### Supply Chain

- The wget-pipe-to-bash pattern has inherent trust implications: the user trusts that mycly.dev serves safe code
- Mitigations: public source repo, signed releases (future), reproducible builds (future), HTTPS + certificate pinning in Stage 1

---

## 9. Glossary

| Term | Definition |
|------|-----------|
| **Stage 0** | The initial bootstrap script. Fetched via wget/curl (Unix) or irm (Windows). Detects the system and downloads Stage 1. |
| **Stage 1** | The mycly agent. An interactive AI-assisted tool that performs system setup and maintenance. |
| **Stage 2** | The actual work performed by the agent: installing tools, configuring shell, setting up SSH, etc. |
| **Desired state** | A TOML file declaring what the user wants their environment to look like. mycly works toward this state. |
| **Trust tier** | One of four levels (0-3) of autonomy mycly has on a given machine. Starts at 0, escalates with user consent. |
| **Semantic firewall** | An inspection layer that classifies outbound data and prevents inadvertent leakage to remote inference backends. |
| **Inference router** | The component that selects which backend (local, corporate, cloud) handles a given task based on data sensitivity and capability. |
| **System report** | A JSON file (`~/.mycly/system-report.json`) containing everything Stage 0 detected about the machine. |
| **Device authorization** | The QR code / short code authentication flow where the user's phone confirms the new machine's identity. |
| **Rollback manifest** | A record of file states before mycly made changes, enabling `mycly undo` and `mycly rollback`. |

---

## 10. Next Steps — Priority Order

1. **Set up Git repository.** Initialize `github.com/mgua/mycly` with the current artifacts.
2. **Implement auth backend.** Minimal FastAPI service with Redis for session management. Deploy to Fly.io or similar.
3. **Build mycly.dev landing page.** Static page with OS-detected install command, hosted on Cloudflare Pages.
4. **Implement Stage 1 Python agent.** Start with system inventory display (Tier 0) and interactive tool installation (Tier 1). Single inference backend initially.
5. **Test across platforms.** Docker-based test matrix for the Stage 0 scripts. Verify on real hardware (Raspberry Pi, Windows laptop).
6. **Implement desired-state TOML parser.** Define schema, write parser, create Marco's personal profile as the first real config.
7. **Add rollback.** File-level snapshots before any modification. `mycly undo` command.
8. **Multi-backend inference routing.** Local + cloud backends. Routing policy in config.
9. **Semantic firewall MVP.** Regex-based classification first (PII, credentials, hostnames), with local model classification as an upgrade path.
10. **Windows Stage 1.** PowerShell-native agent with winget/scoop integration.
