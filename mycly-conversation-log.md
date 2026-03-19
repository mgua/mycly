# mycly — Brainstorming & Design Conversation Log

**Date:** 2026-03-19
**Participants:** Marco Guardigli (mgua), Claude (Anthropic)
**Session type:** Brainstorming → Architecture → Specification → Prototyping
**Artifacts produced:** `mycly-spec.md`, `boot.sh`, `boot.ps1`

---

## Conversation Timeline

### 1. Initial Problem Statement

**Prompt (mgua):** Wants to create a tool that automates repeating setup actions when preparing a user account on a new system. Cross-platform, non-administrative. Console tool, possibly from distro repos, invoked simply, guiding the user through customization. Typical Linux tasks: tmux, bash profile, git, chezmoi, fzf, ripgrep, fd, htop, mc, neovim, and related configurations. Font/console prep, shell setup, aliases, prompt, hosts, .gitconfig.

**Discussion:** Claude framed this as a "day-zero bootstrap" problem and identified three key design questions: relationship to chezmoi (bootstrap only vs. wrapper vs. replacement), language/runtime choice (shell script vs. Python vs. Go/Rust vs. Ansible), and non-admin installation strategies (Homebrew, Nix, cargo, pip, or pre-built binaries to `~/.local/bin`). Proposed three architectural options: smart shell script, Python CLI app, Ansible-local. Asked for user input on preferences.

**Decision:** User chose not to answer the structured questions, preferring open discussion.

---

### 2. Expanding Scope — Remote Access

**Prompt (mgua):** Add preparation of file transfer and remote access tools, SSH keys, etc.

**Discussion:** SSH setup identified as a "day zero" priority with multiple sub-steps (keygen, key distribution, `~/.ssh/config`, permissions hardening, agent setup). Chicken-and-egg quality noted: SSH may be needed *before* dotfiles can be pulled. Module structure emerged: shell environment, terminal tools, editor, git, remote access & transfer, fonts & terminal, dotfile sync, system diagnostics.

**Decision:** Remote access is an early-priority module. Trust decision on SSH keys (fresh per machine vs. carry existing) flagged as important.

---

### 3. Pivotal Insight — AI-Assisted Agent

**Prompt (mgua):** Thinking of something like Claude Code which runs on the system and takes care of the process, maybe in several runs.

**Discussion:** This fundamentally changed the architecture from a deterministic script to an AI-assisted bootstrap agent. Key advantages: the LLM handles platform variation and edge cases (e.g., "install ripgrep on Debian without sudo" vs. "on Fedora with sudo" vs. "via cargo") without encoding branching logic. Three-stage architecture proposed: thin launcher (Stage 0), system profile spec (YAML/TOML), incremental runs. Bootstrap paradox identified: the agent needs *something* to run on — what's the minimum?

**Decision:** AI-assisted agent model adopted. Multi-stage "rocket" architecture.

---

### 4. Bootstrap Entry Point

**Prompt (mgua):** The simplest starting point is wget+bash. Simple and short. This would fetch all the heavier tools and then rely on those. The nondeterministic idea is important — might run on a small microcontroller or a powerful server.

**Discussion:** Multi-stage rocket architecture formalized. Stage 0 (wget+bash, 50-100 lines, probe system, fetch Stage 1), Stage 1 (agent — Python or raw bash API calls), Stage 2 (actual work). Constraint-awareness highlighted as where AI shines: a Pi Zero gets a different plan than a 64-core server.

**Decision:** `wget` chosen over `curl` as the absolute minimum (present in BusyBox). Stage 0 probes capabilities and selects the right Stage 1 payload.

---

### 5. Authentication Design

**Prompt (mgua):** What if we just ask for the email, and then produce a text mode QR code that the user would scan from the mobile?

**Discussion:** Recognized as a device authorization flow (like Netflix TV login or `gh auth login`). Flow: email prompt → generate session token → render text-mode QR code pointing to auth URL → user scans with phone → phone confirms → script polls for approval → receives short-lived API token. Works on headless servers, SSH sessions, any terminal with text output. Fallback for constrained terminals: short URL + 6-character code.

**Decision:** QR code device authorization as primary auth, with code fallback. Minimal backend needed (session management + API proxy).

---

### 6. Naming

**Prompt (mgua):** What about "my127001"? Or mycly?

**Discussion:** Evaluated both options. `my127001` — clever localhost reference, hacker-ish, but long and hard to read. `mycly` — short, typeable, memorable, sounds like "my CLI," works as package name and domain. Alternative `mycl.it` rejected due to unfortunate reading.

**Decision:** `mycly` selected. Domain `mycly.dev` suggested for the project URL.

---

### 7. Enterprise Considerations — Inference Backends

**Prompt (mgua):** Can Claude Code rely on non-Anthropic inference engines?

**Discussion:** Research confirmed that Claude Code can be pointed at any Anthropic Messages API-compatible backend via `ANTHROPIC_BASE_URL` environment variable. Works with Ollama (direct since v0.14.0), LiteLLM proxy, OpenRouter, Bifrost gateway, and self-hosted models. Important caveat: model quality matters for agentic file editing — tool calling support is essential.

**Decision:** mycly must be backend-agnostic. The same protocol works with cloud, corporate, and local inference.

---

### 8. Enterprise Dimension

**Prompt (mgua):** In enterprise environments, external models would not be allowed. Need to rely on internal inference servers. Could evolve to perform system maintenance with admin access. Comprehensive activity logging required. The model could be supported by RAG with internal procedures.

**Discussion:** Two product trajectories identified: mycly-personal (user-level, any API) and mycly-enterprise (admin-capable, internal inference only, auditable, RAG-enhanced with company procedures). Architecture designed to support both via configuration, not code changes: transport layer (just a URL), policy layer (allowed actions), knowledge layer (personal TOML vs. corporate RAG), logging layer (local JSON vs. SIEM export).

**Decision:** Design for personal first, but with clean interfaces at every boundary so enterprise path stays open. Never hardcode assumptions about inference backend, auth method, or privilege level.

---

### 9. Expanded Vision — Personal Systems Agent

**Prompt (mgua):** mycly would run in user account but automate tasks beyond setup. Restructure folders, index contents, download/build tools. Manage Windows shortcuts and taskbar, customize browser and desktop, set application preferences, setup printers, screen resolution, keyboard, Bluetooth devices. On phone, keep preferences consistent. Receive commands and instruction sets. Become the agent managing all digital workplaces. Must be extremely trusted and secure — managing keys, SSH agent, mobile sync, payment systems. Extremely limited autonomy at first, ready to scale.

**Discussion:** Reframed mycly as a personal systems administrator. Introduced progressive trust model with four tiers: Tier 0 (observe only), Tier 1 (reversible changes, ask before acting), Tier 2 (autonomous within scope), Tier 3 (trusted agent — credentials, payments, device pairing). Cross-device consistency as a platform feature. Core design principles established: reversibility, declarative preference model, absolute transparency, credential isolation from LLM, offline capability.

**Decision:** Four-tier trust model adopted. Phased roadmap from bootstrap through to trusted agent. Mobile companion as future phase.

---

### 10. Multi-Backend Inference Routing

**Prompt (mgua):** mycly could have more than a single inference backend. Local on GPU/CPU/NPU. Corporate backend for work competences. Mobile backend for healthcare/fitness/photos. General purpose cloud LLM for advanced search and troubleshooting.

**Discussion:** Identified this as domain-routed inference — backend choice is a function of task type AND data sensitivity. Each backend has a different trust boundary. Routing logic becomes first-class: task classification, data sensitivity assessment, backend availability, capability matching, minimum-privilege selection. Composition pattern: a single user request may hit multiple backends in sequence without mixing data streams.

**Decision:** Multi-backend routing adopted as core architecture. The inference router is a first-class component.

---

### 11. Semantic Firewall

**Prompt (mgua):** Consider adding a semantic firewall for appropriate routing, adequate auditing, with potential rules addressing unaware and unwanted disclosure.

**Discussion:** Identified the primary threat as inadvertent leakage — the user doesn't realize the agent is assembling context that includes internal network topology, hostnames, project codenames, and sending it to a cloud LLM. Semantic firewall sits between agent core and inference router, inspecting every outbound request. Content classification runs on local model only (never remote). Categories: PII, credentials, network topology, organizational, financial, health, location, IP, file content. Actions: pass, redact (semantic-aware with placeholder mapping), reroute to safer backend, or block. User transparency: firewall announces its actions. Enterprise extension: centrally managed policies, DLP integration.

**Decision:** Semantic firewall adopted as mandatory component. Classification must run locally. Redaction preserves problem shape with placeholder mapping.

---

### 12. Digital Identity Manifest

**Prompt (mgua):** Add LinkedIn account, Gmail accounts, Apple account, Android account, Microsoft account, password manager, storage accounts, identity providers, phone number, social media accounts, local encrypted storage (TrueCrypt/VeraCrypt).

**Discussion:** Expanded desired-state TOML into a comprehensive digital identity manifest covering: identity (name, phone, emails), accounts (Google, Microsoft, Apple, Android, GitHub, LinkedIn, social media), identity providers (OIDC/OAuth with preferred order), security (password manager with CLI integration, encrypted volumes with mount points, MFA preferences and hardware keys), cloud storage (Google Drive, OneDrive, Backblaze). Noted the desired-state file is itself a high-value target — maps the user's entire digital footprint. Added tiered password manager integration (Tier 1: reminders, Tier 2: existence checks, Tier 3: automated retrieval). Added encrypted volume awareness with mount assistance.

**Decision:** Full digital identity manifest in desired-state TOML. File must be encrypted at rest. Password manager is single source of truth for credentials. Encrypted volume as potential trust anchor.

---

### 13. Cross-Platform Installation

**Prompt (mgua):** Wants a completely cross-platform setup with a single command, loading as a cross-platform shell archive. Is there a consolidated approach?

**Discussion:** Researched the landscape. Found no truly single-file cross-platform solution. Three patterns identified: (1) two commands/one URL per platform (industry standard — Claude Code, rustup, Deno), (2) polyglot file (bash+PowerShell trick using backtick/multiline comment differences — fragile), (3) server-side User-Agent detection (unreliable). Claude Code uses separate install.sh and install.ps1 with a third install.cmd for CMD.

**Decision:** Two platform-native scripts: `boot.sh` (bash, works with wget or curl) and `boot.ps1` (PowerShell 5.1+). Website auto-detects visitor OS and shows only the relevant command.

---

### 14. Stage 0 Implementation

**Prompt (mgua):** Prepare Stage 0 loaders. On Windows, handle execution policy blocks. Produce friendly messages. Claude Code setup as a valid reference model.

**Discussion:** Analyzed Claude Code's install.sh (fetched the actual script). Built both Stage 0 scripts. bash script: ~540 lines, wget/curl abstraction, full distro family detection, resource assessment, tool inventory, QR auth flow, /dev/tty input handling for piped execution. PowerShell script: ~725 lines, execution policy check with clear remediation guidance, PS 5.1 compatible (no PS7-only features), CIM-based system detection, WSL and Git Bash detection, TLS 1.2 enforcement. Both produce `~/.mycly/system-report.json`.

**Decision:** Both scripts implemented and syntax-verified. Auth flow and Stage 1 download endpoints stubbed (TODO) for future backend development.

---

## Key Architectural Decisions Log

| # | Decision | Rationale | Alternatives Considered |
|---|----------|-----------|------------------------|
| 1 | AI-assisted agent, not deterministic script | Platform variation is too complex to encode in branching logic; LLM handles it naturally | Ansible, shell script with case statements, Python with distro detection |
| 2 | `wget + bash` as minimum bootstrap | Present in BusyBox, works on embedded systems, recovery environments, minimal containers | curl (less universal), Python (not always present), Go binary (portability) |
| 3 | Multi-stage rocket architecture | Separates bootstrap concerns; each stage only assumes what the previous stage established | Monolithic installer, package manager dependency |
| 4 | QR code device authorization | Works on headless/SSH/serial; phone as trusted second factor; no typing long keys | API key paste, browser OAuth, magic link email |
| 5 | Backend-agnostic inference (Anthropic Messages API) | Enterprise requirement; local/corporate/cloud flexibility; proven compatible with Ollama, LiteLLM, OpenRouter | Hardcoded Anthropic, OpenAI-compatible, custom protocol |
| 6 | Four-tier progressive trust model | Matches real-world trust delegation; prevents premature autonomy; each tier earnable | Binary on/off permissions, role-based access, capability-based |
| 7 | Multi-backend inference routing | Different data types have different sensitivity; one backend can't serve all trust domains | Single backend with sanitization, user manual routing |
| 8 | Semantic firewall (local classification) | Inadvertent disclosure is the primary threat; classification must not itself leak data | Regex-only DLP, user manual review, no protection |
| 9 | Declarative desired-state model (TOML) | User says *what* not *how*; agent adapts per platform; idempotent | Imperative scripts, Ansible playbooks, shell profiles |
| 10 | Two platform-native bootstrap scripts | Clean, idiomatic, maintainable; polyglot tricks are fragile | Single polyglot file, server-side detection, manual download |
| 11 | Password manager as credential source of truth | mycly never stores secrets; PM CLI integration enables automation at Tier 3 | Built-in keyring, encrypted config, environment variables |
| 12 | Name: mycly | Short, typeable, pronounceable, "my CLI" meaning, clean as package/domain | my127001 (long), mysh, nido, homectl |

---

## Prompts Reference

Below is a condensed reference of each user prompt that drove the conversation forward:

1. "I want to create a tool that automates a series of actions I have to repeat every time I prepare my account on a system."
2. "Preparation of file transfer and remote access tools, SSH keys etc. would be a task."
3. "I am thinking of something like Claude Code which is run there and takes care of the process, maybe in several runs."
4. "The simplest starting point is wget+bash. Simple and short. The nondeterministic idea is important."
5. "What if we just ask for the email, and then produce a text mode QR code that the user would scan from the mobile?"
6. "What about 'my127001'? Or mycly?"
7. "Can Claude Code rely on non-Anthropic inference engines?"
8. "In enterprise environment, it would not be allowed to use an external model... A natural evolution could be system maintenance with admin access... comprehensive activity log... model supported by RAG with internal procedures."
9. "mycly would run in the user account but automate tasks going way beyond setup... restructure folders, index, manage Windows shortcuts, desktop, printers, screen, keyboard, Bluetooth... on the phone too... extremely trusted and secure... extremely limited autonomy in the beginning."
10. "mycly could have more than a single inference backend. Local on GPU/CPU/NPU... corporate backend... mobile backend... general purpose cloud LLM."
11. "I would consider adding a semantic firewall... support appropriate routing... adequate auditing... rules addressing unaware and unwanted disclosure."
12. "Add to personal info: LinkedIn, Gmail, Apple, Android, Microsoft accounts, password manager, storage accounts, identity providers, phone, social media, encrypted storage."
13. "I would like a completely cross-platform setup, with a single command... is there a consolidated approach?"
14. "Prepare Stage 0 loaders. On Windows, execution authorization blocks. Friendly messages. Claude Code setup as a valid model."

---

## Artifacts Produced

| File | Type | Size | Description |
|------|------|------|-------------|
| `mycly-spec.md` | Specification | ~780 lines | Complete vision, architecture, trust model, security model, desired-state format, roadmap |
| `boot.sh` | Bash script | ~540 lines | Stage 0 Unix bootstrap — system detection, auth, Stage 1 handoff |
| `boot.ps1` | PowerShell script | ~725 lines | Stage 0 Windows bootstrap — execution policy, system detection, auth, Stage 1 handoff |
| `mycly-conversation-log.md` | Documentation | This file | Full conversation timeline, decisions, prompts reference |
| `mycly-operations.md` | Documentation | ~600 lines | Operational documentation for development, testing, deployment |
