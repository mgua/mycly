# mycly — Make Any Machine Yours

## Vision

mycly is an AI-assisted agent that transforms any machine into your personal working environment. Starting from a single `wget | bash` command, it bootstraps itself onto the target system, assesses what's available, and interactively guides the user through setup, customization, and ongoing maintenance of their digital workspace.

mycly is not a configuration management tool. It is a personal systems agent — one that understands your preferences, adapts to the constraints of each machine it runs on, earns trust incrementally, and eventually manages the full lifecycle of your digital workplaces across devices.

---

## Principles

1. **Minimal bootstrap, maximal reach.** The entry point is `wget` and `bash` — nothing else is assumed. From there, mycly pulls in what it needs based on what the system can support, from a Raspberry Pi Zero to a 64-core server.

2. **Backend-agnostic inference.** mycly never hardcodes a dependency on any specific LLM provider. The inference backend is a URL and a token. It works with Anthropic cloud, a corporate vLLM instance, a local Ollama server, or any endpoint that speaks the Anthropic Messages API format.

3. **Progressive trust.** mycly starts with zero authority and earns more over time. Early runs are observe-and-suggest. Later, with explicit user consent and appropriate safeguards, it can act autonomously. Trust tiers are enforced, not advisory.

4. **Everything is reversible.** Before making any change, mycly snapshots the prior state. Every session can be rolled back. This is non-negotiable at every trust tier.

5. **Transparency is absolute.** mycly maintains a human-readable, structured log of every action it takes, every action it plans, and why. The user is never surprised.

6. **Credentials never touch the LLM.** SSH keys, API tokens, payment configurations, and other secrets flow through a dedicated secure channel. The inference backend sees intent ("install this SSH key"), never key material.

7. **Data stays in its trust domain.** Different types of data route to different inference backends based on sensitivity. Personal health data never hits the corporate server. Company procedures never hit the public cloud. The routing policy is explicit and auditable.

8. **Offline-capable.** mycly degrades gracefully without network access. A local model handles what it can. Without any model, mycly falls back to a deterministic mode that applies known-good configurations from cached state.

---

## Architecture

### Layered Model

```
┌──────────────────────────────────────────────┐
│                  User Interface               │
│         (interactive console / --auto)         │
├──────────────────────────────────────────────┤
│                  Agent Core                    │
│    reasoning loop · tool execution · state     │
│    tracking · resumability · rollback          │
├──────────────────────────────────────────────┤
│               Policy Layer                     │
│    trust tier enforcement · action allow/deny  │
│    approval workflows · scope limits           │
├──────────────────────────────────────────────┤
│             Inference Router                   │
│    task classification · data sensitivity      │
│    backend selection · query sanitization      │
├────────┬────────┬─────────┬──────────────────┤
│ Local  │ Corp   │ Mobile  │ Cloud            │
│ Model  │ Server │ Backend │ LLM              │
├────────┴────────┴─────────┴──────────────────┤
│              Knowledge Layer                   │
│    desired-state spec · RAG corpus ·           │
│    platform knowledge · user preferences       │
├──────────────────────────────────────────────┤
│              Logging Layer                     │
│    action log · rollback manifests ·           │
│    audit trail · SIEM export (enterprise)      │
└──────────────────────────────────────────────┘
```

### Inference Router — Multi-Backend Model

mycly supports multiple simultaneous inference backends, each serving a distinct trust domain and competency area. The router selects the appropriate backend based on task type and data sensitivity.

**Local on-device model.** The most trusted backend. File contents, personal patterns, and local context can be reasoned about here because nothing leaves the machine. Runs on GPU, CPU, or NPU depending on hardware. Handles routine tasks: file organization, config application, indexing, preference management. Serves as the offline fallback — mycly never becomes useless because the network is down.

**Corporate inference server.** Trusted for work data, not personal data. Enhanced with RAG containing company-specific procedures, runbooks, and configuration standards. mycly routes work-related tasks here: environment setup per company policy, VPN configuration, compliance checks. Personal data (photos, health, financial) never touches this backend.

**Mobile/personal backend.** Trusted for personal non-sensitive data. Interacts with health and fitness APIs, photo organization, calendar sync, note management. Filtered through mobile OS permission models that enforce their own boundaries.

**General-purpose cloud LLM.** The most capable but least trusted with private data. Receives abstract, sanitized queries: "how to configure printer model X on Ubuntu 24," procedural troubleshooting, general knowledge. mycly strips identifying context before sending — the problem shape, not the user's actual file paths, hostnames, or data.

**Routing logic.** The router evaluates each task against a policy matrix: what kind of task is it, what data must be in the prompt, which backends are currently available, which has the right domain knowledge, and what is the minimum-privilege backend that can handle it. The local model can perform initial triage to classify tasks before routing.

**Composition.** A single user request may hit multiple backends in sequence. "Set up my new work laptop" might query the corporate server for standard configuration, the cloud LLM for driver troubleshooting, and the local model for applying personal preferences — without mixing data streams across trust boundaries.

### Semantic Firewall

The semantic firewall is a mandatory inspection layer between the agent core and the inference router. Every outbound request to any remote inference backend passes through it. Its purpose is to prevent unaware and unwanted disclosure of sensitive information — including disclosures the user did not intend and may not even realize are occurring.

#### Threat Model

The primary threat is not malicious exfiltration but inadvertent leakage. When mycly assembles context for an inference call, it naturally gathers system details, file paths, hostnames, network topology, project names, credential references, personal data, and organizational structure. Without intervention, this context flows to whichever backend handles the request. The user never explicitly chose to share their internal network layout with a cloud LLM — it just happened because the agent needed context to reason about a VPN problem.

#### Architecture

```
Agent Core
    │
    ▼
┌──────────────────────────────────┐
│        Semantic Firewall          │
│                                   │
│  1. Content Classification        │
│     (runs on LOCAL model only)    │
│                                   │
│  2. Policy Evaluation             │
│     (destination × data category) │
│                                   │
│  3. Action: pass / redact / block │
│     / reroute to safer backend    │
│                                   │
│  4. Audit Record                  │
│     (what was sent, where, why)   │
└──────────────────────────────────┘
    │
    ▼
Inference Router → backends
```

#### Content Classification

Before any request leaves the machine, the firewall classifies the content. Classification itself runs exclusively on the local model — it never involves a remote call. Categories include:

- **PII** — names, email addresses, phone numbers, physical addresses, government IDs
- **Credentials** — SSH keys, API tokens, passwords, certificate material, session tokens
- **Network topology** — internal hostnames, IP addresses, subnet layouts, VPN endpoints, firewall rules
- **Organizational** — project codenames, client names, contract references, internal team names, org chart details
- **Financial** — account numbers, transaction details, salary information, budget figures
- **Health** — medical records, fitness data, prescriptions, health conditions
- **Location** — GPS coordinates, home/office addresses, travel patterns
- **Intellectual property** — patent references, proprietary algorithms, trade secrets, unreleased product names
- **File content** — actual document text, source code, database contents (vs. structural metadata about files)

Classification is probabilistic, not binary. The firewall assigns confidence scores and applies the precautionary principle: when uncertain, treat content as sensitive.

#### Policy Rules

Each inference backend has a policy defining permitted and prohibited data categories:

```toml
[firewall.backends.local]
# Local model — no restrictions, nothing leaves the machine
allow = "all"

[firewall.backends.corporate]
# Work server — work data permitted, personal data prohibited
allow = ["organizational", "network_topology", "file_metadata"]
redact = ["pii_personal", "health", "financial_personal", "location_home"]
block = ["credentials"]

[firewall.backends.cloud]
# Cloud LLM — only abstract problem descriptions
allow = ["generic_technical"]
redact = ["pii", "organizational", "network_topology", "file_content", "location"]
block = ["credentials", "health", "financial"]

[firewall.backends.mobile]
# Mobile backend — personal non-sensitive
allow = ["health", "location", "pii_personal"]
redact = ["organizational", "network_topology"]
block = ["credentials", "financial"]
```

#### Actions

When the firewall detects policy-violating content in an outbound request:

- **Pass** — content is clean for this destination, send unchanged
- **Redact** — replace sensitive tokens with generic placeholders (`dev.internal.corp` → `[INTERNAL_HOST]`, `/home/mgua/clients/acme/` → `[PROJECT_PATH]`). The agent still gets a useful response because the problem shape is preserved
- **Reroute** — the query contains data that cannot be meaningfully redacted without losing the ability to answer. The firewall downgrades the request to a more trusted backend (typically local model), even if it's less capable
- **Block** — the query fundamentally cannot be answered without exposing prohibited data to this backend, and no safer backend is available. The firewall blocks the request and explains why to the user

#### Redaction Strategy

Redaction is not simple string replacement. It is semantic-aware:

- Hostnames are replaced with role-based placeholders (`[WEB_SERVER]`, `[DB_HOST]`) so the LLM can still reason about architecture
- File paths are replaced with structural descriptions (`[PROJECT_ROOT]/[CONFIG_FILE]`)
- Code snippets are abstracted to pseudocode when sending to untrusted backends
- Person names are replaced with role references (`[TEAM_LEAD]`, `[CLIENT_CONTACT]`)
- The mapping between real values and placeholders is kept locally so the agent can reconstruct the full context when applying the response

#### User Transparency

The firewall is never silent about its actions:

- On first run, mycly explains the semantic firewall concept to the user
- When content is redacted: "I removed 3 internal hostnames before sending this to the cloud backend"
- When a request is rerouted: "This query involves client project details — answering locally instead of via cloud"
- When blocked: "I can't answer this without sending credential-adjacent information externally. Would you like me to try with the local model?"
- `mycly firewall log` — shows recent firewall decisions in human-readable form
- `mycly firewall policy` — shows current rules per backend

#### Learning and Adaptation

Over time, the firewall learns what the user considers sensitive in their specific context:

- User can flag false positives ("that's not actually sensitive, it's a public project name")
- User can flag missed detections ("you should have caught that client reference")
- These corrections feed into a local-only refinement of the classification model
- Corrections never leave the machine

#### Enterprise Extension

In the enterprise variant, the semantic firewall becomes a compliance enforcement point:

- Policies are centrally managed and pushed to endpoints
- Users cannot override corporate firewall rules (can only make them stricter)
- All firewall decisions are logged to the corporate SIEM
- DLP (Data Loss Prevention) integration for regulatory compliance (GDPR, HIPAA, SOX)
- The corporate security team can audit what data categories have been sent to which backends across all managed mycly instances

---

## Trust Tiers

### Tier 0 — Observe Only

mycly scans the system, reports findings, and suggests changes. It touches nothing.

- Detect OS, distro, architecture, available package managers
- Inventory installed tools and their versions
- Check shell configuration, existing dotfiles
- Assess available resources (memory, disk, GPU/NPU)
- Report sudo access status
- Suggest an action plan

**Unlocks Tier 1:** User explicitly requests changes.

### Tier 1 — Reversible Changes (Ask Before Acting)

mycly can modify the user environment, but asks for confirmation before every action and snapshots everything it touches.

- Install user-local packages (~/.local/bin, Homebrew, cargo, pip --user)
- Create and modify dotfiles (.bashrc, .gitconfig, .ssh/config)
- Set up shell prompt, aliases, completion, keybindings
- Configure terminal, fonts, color schemes
- Clone repos, initialize chezmoi
- Generate SSH keypairs, configure SSH agent
- Set application preferences, desktop shortcuts

Every action produces a rollback manifest. `mycly undo` reverses the last action or session.

**Unlocks Tier 2:** Sustained use without rollbacks. User explicitly enables autonomous mode for specific scopes.

### Tier 2 — Autonomous Within Scope

mycly performs routine maintenance without asking, within user-defined boundaries.

- Keep user-local packages updated
- Sync configurations across machines
- Reorganize files according to user-defined rules
- Maintain indexes, caches, and local search databases
- Apply preference changes pushed from other devices
- Monitor and report on system state

Cannot touch: credentials, payment systems, system-level settings, anything outside defined scope.

**Unlocks Tier 3:** Explicit trust escalation ceremony, possibly requiring hardware key or biometric confirmation.

### Tier 3 — Trusted Agent

mycly manages sensitive aspects of the digital workspace.

- SSH key lifecycle (generation, rotation, distribution)
- Credential store management
- Payment system configuration
- Device pairing (Bluetooth, printers, displays)
- Cross-device sync of sensitive preferences
- Mobile phone note sync, health data integration

Every action at this tier is cryptographically logged. Requires strong authentication (hardware key, biometric) for initial enablement and periodic reconfirmation.

---

## Platform Targets

### Linux (Primary, ships first)

Full capability. User-local package installation via multiple strategies (distro package manager with sudo if available, Homebrew/Linuxbrew, Nix single-user, cargo, pip, pre-built binaries to ~/.local/bin). Shell customization, dotfile management, SSH, editor setup. Works on everything from Raspberry Pi to server.

### Windows

PowerShell-native agent variant. Winget, scoop, chocolatey for package management. Registry and Settings integration for preferences. Taskbar, shortcuts, keyboard layout, display configuration. WSL detection and bridge — mycly on Windows can bootstrap WSL and then hand off to the Linux variant inside it.

### macOS

Homebrew-centric. System Preferences via `defaults write`. Dock customization. Tight integration with Keychain for credential management.

### Android / iOS (Future)

Constrained by mobile OS sandboxing. Works through accessibility APIs, Shortcuts/Tasker, and mycly's own app. Manages what the OS permits: app preferences, notification settings, display configuration, Bluetooth pairing. The preference model is shared with desktop — mycly carries your identity across platforms and applies it wherever the platform allows.

---

## Bootstrap Sequence

### Stage 0 — Cross-Platform Entry Points

mycly provides two platform-native bootstrap scripts, following the established pattern used by Claude Code, rustup, Deno, and similar tools. A single polyglot script was considered but rejected: the tricks required to make one file valid in both bash and PowerShell are fragile, unmaintainable, and violate the principle of least surprise. Two clean, idiomatic scripts are more trustworthy than one clever hack.

**Unix (Linux, macOS, WSL, FreeBSD):**
```
wget -qO- https://mycly.dev/boot | bash
curl -fsSL https://mycly.dev/boot | bash
```

**Windows (PowerShell 5.1+):**
```
irm https://mycly.dev/boot.ps1 | iex
```

If execution policy blocks the PowerShell script, the user gets clear guidance:
```
Set-ExecutionPolicy Bypass -Scope Process -Force; irm https://mycly.dev/boot.ps1 | iex
```

The website at mycly.dev detects the visitor's OS via browser User-Agent and shows only the relevant command — one command per visitor, not a confusing table of options.

### Stage 0 — What It Does

Both scripts follow the same logic, implemented idiomatically for each platform:

1. **System detection.** OS, distro (and family: debian/rhel/arch/alpine/suse), architecture (x64/arm64/armv7/riscv64), libc (glibc/musl), kernel version, hostname
2. **Resource assessment.** Total memory, available disk in $HOME, CPU count, GPU/NPU presence, terminal dimensions. Drives decisions about which tools and configurations are feasible
3. **Privilege detection.** Root/admin status, sudo availability (passwordless or not), available package managers (system-level and user-level)
4. **Tool inventory.** Runtimes (Python, Node, Deno), shells (bash, zsh, PowerShell 7), core tools (git, ssh, gpg), editors (neovim, vim, VS Code), modern CLI (fzf, rg, fd, bat, jq), config management (chezmoi), containers (docker, podman). On Windows: also WSL status, Git Bash presence
5. **Network check.** Connectivity to mycly.dev, proxy detection, TLS version verification (Windows)
6. **Authentication.** Email prompt, device authorization flow via QR code (if terminal supports it and qrencode is available) or short code entry. Polls for approval. Existing sessions within 24h are reused. Environment variable MYCLY_API_KEY provides a direct bypass
7. **Stage 1 selection.** Based on available runtimes: Python agent (full), Node agent, PowerShell agent (Windows), or bash agent (lightweight). Downloads the appropriate payload
8. **System report.** Writes `~/.mycly/system-report.json` with all findings for Stage 1 consumption

The Unix script (~540 lines of bash) works with wget or curl and handles the `wget | bash` stdin redirection challenge by reading user input from `/dev/tty`. The Windows script (~725 lines of PowerShell) targets PowerShell 5.1 Desktop edition compatibility: no PowerShell 7 operators (`??`, ternary, `&&`), uses `Get-CimInstance` for WMI, and checks execution policy before doing anything else.

Both scripts are implemented and available as `boot.sh` and `boot.ps1`.

### Stage 1 — The Agent

On capable systems (Python 3.8+ available): a Python script that establishes the agent loop, connects to the inference backend, and begins interactive session.

On minimal systems (no Python, limited resources): a bash-driven agent that makes raw HTTPS POST requests to the inference API using wget/curl. Less capable but functional. On Windows without Python: a PowerShell-based agent.

On offline systems: a deterministic fallback that applies cached desired-state configurations without AI assistance.

Stage 1 persists itself to `~/.mycly/` so subsequent runs don't need Stage 0 again.

### Stage 2 — The Work

The agent, now running, begins executing against the user's desired state. Interactive by default — shows what it plans to do, asks for confirmation. Supports `--auto` for unattended runs with a pre-approved action set.

---

## Desired-State Model

User preferences are declared in a TOML file that travels with the user (stored in the mycly cloud, in a git repo, on a USB stick, or entered interactively on first run).

**IMPORTANT: The desired-state file itself is sensitive.** It contains account identifiers, service references, and digital identity information. The file must be stored encrypted — either within an encrypted volume, in the password manager, or encrypted at rest by mycly itself using a key derived from the user's authentication. It is never sent to any remote inference backend in full. The agent reads it locally and extracts only the non-sensitive fragments needed for a specific task.

```toml
# ============================================================
# mycly desired-state specification
# This file defines the user's complete digital identity and
# workspace preferences. It is declarative: it says what should
# be true, not how to achieve it.
#
# SENSITIVITY: HIGH — this file contains account identifiers
# and digital identity references. Store encrypted.
# ============================================================

# ------------------------------------------------------------
# IDENTITY — who the user is
# ------------------------------------------------------------

[identity]
name = "Marco Guardigli"
phone = "+39 xxx xxxxxxx"

[identity.email]
primary = "marco@example.com"
work = "m.guardigli@tomware.it"

# ------------------------------------------------------------
# ACCOUNTS — the user's digital presence
# ------------------------------------------------------------

[accounts.google]
# Multiple Google/Gmail accounts with designated roles
personal = "marco.guardigli@gmail.com"
work = "m.guardigli@tomware.it"            # Google Workspace
default = "personal"

[accounts.microsoft]
# Microsoft 365 / Outlook / Azure AD
personal = "marco@outlook.com"
work = "m.guardigli@tomware.onmicrosoft.com"
default = "work"

[accounts.apple]
id = "marco@icloud.com"
# Used for: iCloud sync, App Store, Keychain, Find My

[accounts.android]
# Primary Google account for Android device management
id = "marco.guardigli@gmail.com"

[accounts.github]
username = "mgua"
# Signing key, GPG, commit verification preferences
sign_commits = true

[accounts.linkedin]
profile = "https://linkedin.com/in/marcoguardigli"

[accounts.social]
# Additional social media — mycly can configure apps and
# notification preferences on desktop and mobile
mastodon = "@mgua@mastodon.social"
# twitter = ""
# bluesky = ""

# ------------------------------------------------------------
# IDENTITY PROVIDERS — SSO and federation
# ------------------------------------------------------------

[identity_providers]
# Ordered by preference for SSO flows
preferred_order = ["microsoft_work", "google_personal", "github"]

[identity_providers.microsoft_work]
type = "oidc"
tenant = "tomware.onmicrosoft.com"
use_for = ["corporate_apps", "vpn", "intranet"]

[identity_providers.google_personal]
type = "oauth2"
account = "marco.guardigli@gmail.com"
use_for = ["personal_services", "android_sync"]

[identity_providers.github]
type = "oauth2"
username = "mgua"
use_for = ["dev_tools", "ci_cd", "package_registries"]

# ------------------------------------------------------------
# SECURITY — credential and secret management
# ------------------------------------------------------------

[security.password_manager]
provider = "bitwarden"                     # or keepass, 1password, lastpass
# mycly uses the password manager as the source of truth for
# credentials. It never stores passwords itself.
# At Tier 3, mycly can interact with the password manager CLI
# to retrieve credentials for automated setup.
cli_integration = true
vault_timeout_minutes = 15

[security.encrypted_storage]
# Local encrypted volumes — mycly can detect, mount (with user
# passphrase), and configure applications to use these paths
[[security.encrypted_storage.volumes]]
label = "personal-vault"
type = "veracrypt"
container = "~/vault/personal.hc"
mount_point = "~/secure"
automount = false                          # require explicit user action

[[security.encrypted_storage.volumes]]
label = "work-keys"
type = "veracrypt"
container = "~/vault/work-keys.hc"
mount_point = "~/work-secure"
automount = false

[security.mfa]
# Multi-factor authentication preferences
preferred_method = "hardware_key"          # hardware_key, totp, push
hardware_keys = ["yubikey_5_nfc"]
totp_app = "aegis"                         # or google_authenticator, authy
backup_codes_location = "password_manager" # stored in Bitwarden

# ------------------------------------------------------------
# CLOUD STORAGE — sync and file services
# ------------------------------------------------------------

[storage.personal]
provider = "google_drive"
account = "marco.guardigli@gmail.com"
sync_folders = ["documents", "photos"]

[storage.work]
provider = "onedrive"
account = "m.guardigli@tomware.onmicrosoft.com"
sync_folders = ["projects", "shared"]

[storage.backup]
# Additional storage accounts for backup or archive
provider = "backblaze_b2"
bucket = "mgua-archive"

# ------------------------------------------------------------
# SHELL & TERMINAL
# ------------------------------------------------------------

[shell]
preferred = "bash"
prompt = "oh-my-posh"
theme = "custom-mg"
aliases = true
completion = true
vi_mode = false

# ------------------------------------------------------------
# TOOLS
# ------------------------------------------------------------

[tools]
core = ["git", "tmux", "fzf", "ripgrep", "fd", "htop", "mc", "jq", "bat", "tree"]
editor = "neovim"
editor_config = "https://github.com/mgua/mg-nvim-2025"
dotfiles = "chezmoi"
dotfiles_repo = "https://github.com/mgua/dotfiles"

# ------------------------------------------------------------
# REMOTE ACCESS
# ------------------------------------------------------------

[remote]
ssh_keygen = true
ssh_key_type = "ed25519"
ssh_agent = true
ssh_hosts = [
    { alias = "dev", host = "dev.example.com", user = "mgua" },
    { alias = "prod", host = "prod.example.com", user = "deploy" },
]

# ------------------------------------------------------------
# FONTS
# ------------------------------------------------------------

[fonts]
nerd_font = "JetBrainsMono"
install_method = "user-local"

# ------------------------------------------------------------
# GIT
# ------------------------------------------------------------

[git]
default_branch = "main"
pull_rebase = true
credential_helper = "store"
signing_key = "from_password_manager"      # mycly retrieves via PM CLI

# ------------------------------------------------------------
# LOCALE
# ------------------------------------------------------------

[locale]
lang = "it_IT.UTF-8"
keyboard = "it"
timezone = "Europe/Rome"

# ------------------------------------------------------------
# FILE ORGANIZATION
# ------------------------------------------------------------

[files]
organize_downloads = true
project_root = "~/projects"
document_structure = ["documents", "projects", "tmp", "archive"]
encrypted_documents = "~/secure/documents" # inside veracrypt volume

# ------------------------------------------------------------
# INFERENCE BACKENDS
# ------------------------------------------------------------

[inference]
local_url = "http://localhost:11434"
local_model = "qwen3.5:35b-a3b"
cloud_url = "https://api.anthropic.com"
corporate_url = ""
mobile_url = ""

# ------------------------------------------------------------
# FIREWALL ROUTING POLICY
# (which data categories each backend may see)
# ------------------------------------------------------------

[firewall.local]
allow = "all"

[firewall.corporate]
allow = ["organizational", "network_topology", "file_metadata"]
redact = ["pii_personal", "health", "financial_personal", "location_home"]
block = ["credentials"]

[firewall.cloud]
allow = ["generic_technical"]
redact = ["pii", "organizational", "network_topology", "file_content", "location"]
block = ["credentials", "health", "financial"]

[firewall.mobile]
allow = ["health", "location", "pii_personal"]
redact = ["organizational", "network_topology"]
block = ["credentials", "financial"]
```

The spec is declarative — it says what should be true, not how to achieve it. The agent figures out the how based on the platform, available resources, and current state.

Note that the desired-state file is itself a high-value target. It maps the user's entire digital footprint: which services they use, which accounts they hold, where their encrypted volumes live, which identity providers they trust. The file does not contain any passwords or secret keys — those live in the password manager — but the metadata alone is sensitive. mycly must protect this file with at least the same rigor it applies to the data it guards: encrypted at rest, never transmitted to remote backends in full, and accessible only after user authentication.

---

## Security Model

### Authentication

- Stage 0 uses device authorization flow (QR code / short code) with email-based identity
- Session tokens are short-lived, scoped to the machine, and stored in `~/.mycly/session`
- Tier 3 operations require hardware key or biometric reconfirmation

### Credential Isolation

- SSH private keys, API tokens, and other secrets never appear in inference API calls
- The agent decides what credentials are needed; a separate secure channel handles the material
- Credential operations are logged as intent ("installed SSH key for dev.example.com") not content

### Password Manager Integration

The password manager is mycly's single source of truth for credentials. mycly never stores passwords, tokens, or secrets itself — it delegates to the user's chosen password manager.

- At Tier 1: mycly reminds the user which credentials are needed and tells them where to find them in the vault. The user copies credentials manually.
- At Tier 2: mycly can query the password manager CLI (e.g., `bw`, `op`, `keepassxc-cli`) to check whether a credential exists, without retrieving the secret itself.
- At Tier 3: mycly can invoke the password manager CLI to retrieve credentials and apply them directly — for example, injecting an API token into a config file or populating a `.netrc`. The secret passes from the PM to the target file; it never enters the inference loop.

Supported password managers (initial targets): Bitwarden (CLI: `bw`), KeePassXC (CLI: `keepassxc-cli`), 1Password (CLI: `op`). The interface is pluggable — additional providers can be added.

### Encrypted Storage

mycly is aware of the user's encrypted volumes (VeraCrypt, LUKS, etc.) and their role in the workspace:

- At Tier 0-1: mycly detects the presence of encrypted containers listed in the desired-state spec and reports their mount status. It reminds the user if a volume that should be mounted is not.
- At Tier 2: mycly can prompt the user for the volume passphrase and invoke the mount command. The passphrase is passed directly to the mount utility via stdin — it never enters the agent's context, logs, or inference calls.
- At Tier 3: mycly can retrieve volume passphrases from the password manager and mount volumes without user interaction, when the policy permits.

Encrypted volumes may serve as the backing store for sensitive application data. The desired-state spec can reference paths inside encrypted volumes (e.g., `encrypted_documents = "~/secure/documents"`), and mycly will ensure the volume is mounted before configuring applications that depend on those paths.

### Desired-State File Protection

The desired-state TOML file is itself a high-value asset — it maps the user's digital identity across all platforms and services. Protection requirements:

- The file is encrypted at rest using a key derived from the user's mycly authentication
- It is never transmitted to any remote inference backend in full
- The agent reads it locally and extracts only the non-sensitive fragments needed for a specific task
- Recommended storage locations: inside an encrypted volume, in the password manager as a secure note, or encrypted by mycly's own key management
- When the file is updated (new account added, preference changed), the previous version is retained in encrypted history for rollback

### Inference Sanitization

- Before sending context to any remote inference backend, mycly strips:
  - Absolute paths (replaced with relative/generic paths)
  - Hostnames and IP addresses (replaced with placeholders)
  - File contents (replaced with structural descriptions)
  - Usernames and identifying information
- Sanitization depth varies by backend trust level:
  - Local model: no sanitization needed
  - Corporate server: personal data stripped, work context preserved
  - Cloud LLM: maximum sanitization, only problem shape transmitted

### Rollback

- Every change produces a snapshot stored in `~/.mycly/snapshots/`
- Snapshots are timestamped and tagged with the session ID
- `mycly undo` reverses the most recent action
- `mycly rollback <session-id>` restores to the state before a specific session
- Rollback data is never sent to inference backends

### Audit Log

- All actions logged to `~/.mycly/log/` in structured JSON format
- Each entry: timestamp, trust tier, action type, target, backend used, outcome, rollback reference
- In enterprise mode: logs shipped to centralized SIEM via configurable transport
- Logs are append-only from mycly's perspective

---

## Roadmap

### Phase 1 — Bootstrap (ship first)

- Stage 0 shell script (wget + sh)
- QR code / device code authentication
- System detection and inventory (Tier 0)
- Linux only: Debian/Ubuntu + RHEL/Fedora
- Single inference backend (configurable URL)
- Interactive Tier 1: tool installation, shell setup, git config, SSH keypair, dotfiles via chezmoi
- Basic rollback (file-level snapshots)
- Action logging to local JSON

### Phase 2 — Comfort

- Desired-state TOML spec: define once, apply everywhere
- Multi-backend inference routing
- Semantic firewall: content classification, basic redaction, policy enforcement
- Offline fallback with local model support
- Password manager detection and read-only integration (check credential existence)
- Encrypted volume awareness (detect, report mount status)
- Account inventory: detect which accounts are already signed in, report gaps
- Neovim config deployment
- Font installation (user-local nerd fonts)
- Prompt setup (oh-my-posh)
- Windows support via PowerShell variant
- `mycly status` — show drift from desired state
- `mycly undo` / `mycly rollback` — full rollback support

### Phase 3 — Autonomy

- Tier 2: autonomous maintenance within defined scope
- File organization and indexing
- Cross-machine preference sync
- Package update management
- Desktop and application preference management (Linux + Windows)
- Browser configuration, keyboard layout, display settings
- Printer setup, Bluetooth device pairing
- Semantic firewall learning: user corrections, false positive/negative feedback loop
- Encrypted volume mount assistance (passphrase via user prompt)
- Identity provider SSO flow guidance (walk user through OAuth/MFA ceremonies)
- Cloud storage client setup (Google Drive, OneDrive, Backblaze)

### Phase 4 — Trusted Agent

- Tier 3: credential and key lifecycle management
- Password manager CLI integration: automated credential retrieval and application
- Encrypted volume automount via password manager passphrase retrieval
- Mobile companion app (Android first)
- Cross-device consistency (desktop + phone)
- Cross-device MFA relay (phone approves auth challenges for desktop setup)
- Account lifecycle: detect stale sessions, refresh tokens, report compromised credentials
- Enterprise variant: admin mode, RAG-enhanced procedures, SIEM integration
- Enterprise semantic firewall: centrally managed policies, DLP integration, compliance reporting
- Policy-driven action approval workflows
- Hardware key / biometric trust escalation

---

## Open Questions

1. **Package name / distribution.** Should mycly be available in distro repos (AUR, PPA, Homebrew tap) or is the wget bootstrap sufficient? Distro packages add discoverability but create a chicken-and-egg with the bootstrap philosophy.

2. **Desired-state storage.** Where does the TOML spec live canonically? Options: mycly cloud service, git repo, local file only. Each has different sync and backup implications.

3. **Multi-user / multi-profile.** Should mycly support switching between profiles (personal vs. work) on the same machine? This interacts with the multi-backend routing.

4. **Update mechanism.** How does mycly update itself? Auto-update is convenient but conflicts with the trust model — you don't want the tool modifying itself without consent.

5. **Community profiles.** Could users share desired-state profiles? "Here's my Python developer setup" as a starting point that others can fork and customize.

6. **Licensing.** Open source (which license?) or proprietary? Open source builds trust and community but complicates the hosted auth service.

7. **Semantic firewall bootstrapping.** The firewall's content classification runs on the local model, but on first run there may be no local model yet. How does mycly protect outbound requests during Stage 0 and early Stage 1 before the local model is available? Options: conservative regex-based redaction as a fallback, or simply refusing to send rich context to remote backends until the local classifier is operational.

8. **Firewall policy portability.** Should firewall policies be part of the desired-state TOML, or a separate security configuration? In enterprise, they must be centrally managed. In personal use, they should be user-editable. These may need to be different mechanisms.

9. **Account enumeration risk.** The desired-state file lists all of the user's accounts across services — effectively a map of their digital footprint. Even without passwords, this is valuable to an attacker for social engineering, credential stuffing, or targeted phishing. Should mycly split the identity section into a separate, more heavily protected file? Or is encryption at rest sufficient?

10. **Password manager as a dependency.** At Tier 3, mycly leans heavily on the password manager CLI. What happens if the PM is locked, unavailable, or the CLI isn't installed? mycly needs a graceful degradation path — probably falling back to Tier 1 behavior (ask the user to provide credentials manually) rather than failing entirely.

11. **Multi-device account consistency.** When mycly configures a new machine with the user's accounts (Google, Microsoft, Apple), it can set up the client-side configuration but cannot complete OAuth flows or MFA challenges on behalf of the user. The auth ceremony still requires human interaction. How should mycly handle this — queue the setup, walk the user through each login, or integrate with the phone companion app to relay MFA approvals?

12. **Encrypted volume as trust anchor.** If the desired-state file and the local mycly state live inside an encrypted VeraCrypt volume, then mounting that volume becomes the implicit trust ceremony — you prove you're you by knowing the passphrase. This could simplify the trust model but creates a hard dependency on the encrypted volume being available.
