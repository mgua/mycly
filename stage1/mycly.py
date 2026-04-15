#!/usr/bin/env python3
"""
mycly — Make Any Machine Yours
Stage 1 Agent

A personal systems agent that bootstraps and maintains your working environment.
Talks to any Anthropic Messages API-compatible inference backend (Ollama, vLLM, etc.)

Usage:
    python3 mycly.py                  # Interactive mode
    python3 mycly.py status           # Show system status
    python3 mycly.py apply            # Apply desired state
    python3 mycly.py undo             # Undo last action
    python3 mycly.py log              # Show action log

Requires: Python 3.10+, no external dependencies for core functionality.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import textwrap
import urllib.error
import urllib.request
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any

# ============================================================
# Constants
# ============================================================

VERSION = "0.1.0"
MYCLY_HOME = Path(os.environ.get("MYCLY_HOME", Path.home() / ".mycly"))
SNAPSHOTS_DIR = MYCLY_HOME / "snapshots"
LOG_DIR = MYCLY_HOME / "log"
CONFIG_DIR = MYCLY_HOME / "config"

# ============================================================
# Terminal Output
# ============================================================

class Term:
    """Minimal terminal formatting — no dependencies."""

    _colors_enabled: bool = sys.stdout.isatty()

    @staticmethod
    def _esc(code: str) -> str:
        return f"\033[{code}m" if Term._colors_enabled else ""

    BOLD  = property(lambda _: Term._esc("1"))
    DIM   = property(lambda _: Term._esc("2"))
    RESET = property(lambda _: Term._esc("0"))
    RED   = property(lambda _: Term._esc("31"))
    GREEN = property(lambda _: Term._esc("32"))
    YELLOW = property(lambda _: Term._esc("33"))
    BLUE  = property(lambda _: Term._esc("34"))
    CYAN  = property(lambda _: Term._esc("36"))

T = Term()


def info(msg: str) -> None:
    print(f"  {T.BLUE}·{T.RESET} {msg}")

def ok(msg: str) -> None:
    print(f"  {T.GREEN}✓{T.RESET} {msg}")

def warn(msg: str) -> None:
    print(f"  {T.YELLOW}⚠{T.RESET} {msg}")

def fail(msg: str) -> None:
    print(f"  {T.RED}✗{T.RESET} {msg}", file=sys.stderr)

def step(msg: str) -> None:
    print(f"\n  {T.BOLD}→ {msg}{T.RESET}")

def banner() -> None:
    print(f"\n  {T.BOLD}{T.CYAN}mycly{T.RESET} {T.DIM}v{VERSION}{T.RESET}")
    print(f"  {T.DIM}Make Any Machine Yours{T.RESET}\n")


# ============================================================
# Configuration (.env loader — no dependencies)
# ============================================================

@dataclass
class Config:
    inference_url: str = "http://localhost:11434"
    model: str = "qwen3.5:35b-a3b"
    api_key: str = "dummy"
    corporate_url: str = ""
    corporate_key: str = ""
    cloud_url: str = ""
    cloud_key: str = ""
    debug: bool = False

    @classmethod
    def load(cls) -> Config:
        """Load configuration from .env file and environment variables.
        Environment variables take precedence over .env file."""

        config = cls()

        # Try loading .env file from multiple locations
        env_paths = [
            Path.cwd() / ".env",
            MYCLY_HOME / ".env",
            Path(__file__).parent / ".env",
        ]

        env_vars: dict[str, str] = {}
        for env_path in env_paths:
            if env_path.is_file():
                env_vars = _parse_env_file(env_path)
                break

        def get(key: str, default: str = "") -> str:
            """Env var > .env file > default."""
            return os.environ.get(key, env_vars.get(key, default))

        config.inference_url = get("MYCLY_INFERENCE_URL", config.inference_url)
        config.model = get("MYCLY_MODEL", config.model)
        config.api_key = get("MYCLY_API_KEY", config.api_key)
        config.corporate_url = get("MYCLY_CORPORATE_URL", "")
        config.corporate_key = get("MYCLY_CORPORATE_KEY", "")
        config.cloud_url = get("MYCLY_CLOUD_URL", "")
        config.cloud_key = get("MYCLY_CLOUD_KEY", "")
        config.debug = get("MYCLY_DEBUG", "") == "1"

        return config


def _parse_env_file(path: Path) -> dict[str, str]:
    """Parse a .env file. Handles comments, quotes, empty lines."""
    result: dict[str, str] = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()
        # Strip surrounding quotes
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
            value = value[1:-1]
        result[key] = value
    return result


# ============================================================
# Desired State (TOML parser — minimal, no dependencies)
# ============================================================

def load_desired_state(path: Path | None = None) -> dict[str, Any]:
    """Load desired-state TOML. Uses tomllib (3.11+) or a basic fallback."""
    if path is None:
        candidates = [
            CONFIG_DIR / "desired-state.toml",
            MYCLY_HOME / "desired-state.toml",
            Path.cwd() / "config" / "desired-state.toml",
            Path.cwd() / "desired-state.toml",
        ]
        for c in candidates:
            if c.is_file():
                path = c
                break

    if path is None or not path.is_file():
        return {}

    try:
        import tomllib  # Python 3.11+
        with open(path, "rb") as f:
            return tomllib.load(f)
    except ImportError:
        pass

    # Fallback: try tomli (pip installable, pure Python)
    try:
        import tomli
        with open(path, "rb") as f:
            return tomli.load(f)
    except ImportError:
        pass

    # Last resort: very basic parser for flat key=value sections
    warn("No TOML parser available (Python 3.11+ or tomli). Using basic parser.")
    return _basic_toml_parse(path)


def _basic_toml_parse(path: Path) -> dict[str, Any]:
    """Extremely basic TOML parser. Handles [section] and key = value only."""
    result: dict[str, Any] = {}
    current_section: dict[str, Any] = result

    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section_name = line[1:-1].strip()
            parts = section_name.split(".")
            current_section = result
            for part in parts:
                if part not in current_section:
                    current_section[part] = {}
                current_section = current_section[part]
        elif "=" in line:
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if value.lower() == "true":
                value = True
            elif value.lower() == "false":
                value = False
            current_section[key] = value

    return result


# ============================================================
# Inference Client (Anthropic Messages API — stdlib only)
# ============================================================

class InferenceClient:
    """Talks to any Anthropic Messages API-compatible endpoint."""

    def __init__(self, config: Config):
        self.base_url = config.inference_url.rstrip("/")
        self.model = config.model
        self.api_key = config.api_key
        self.debug = config.debug

        # Determine the messages endpoint
        # Ollama: http://host:11434/v1/messages  (with /v1 prefix)
        # Anthropic: https://api.anthropic.com/v1/messages
        # vLLM/LiteLLM: varies
        if "/v1" in self.base_url:
            self.messages_url = f"{self.base_url}/messages"
        else:
            self.messages_url = f"{self.base_url}/v1/messages"

    def ask(
        self,
        prompt: str,
        system: str = "",
        max_tokens: int = 4096,
        temperature: float = 0.3,
    ) -> str:
        """Send a message and return the text response."""

        messages = [{"role": "user", "content": prompt}]

        body: dict[str, Any] = {
            "model": self.model,
            "max_tokens": max_tokens,
            "messages": messages,
        }
        if system:
            body["system"] = system
        if temperature is not None:
            body["temperature"] = temperature

        headers = {
            "Content-Type": "application/json",
            "x-api-key": self.api_key,
            "anthropic-version": "2023-06-01",
        }

        data = json.dumps(body).encode("utf-8")

        if self.debug:
            info(f"[debug] POST {self.messages_url}")
            info(f"[debug] model={self.model}, prompt_len={len(prompt)}")

        try:
            req = urllib.request.Request(
                self.messages_url,
                data=data,
                headers=headers,
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=120) as resp:
                result = json.loads(resp.read().decode("utf-8"))

            # Extract text from content blocks
            text_parts = []
            for block in result.get("content", []):
                if block.get("type") == "text":
                    text_parts.append(block["text"])
            return "\n".join(text_parts)

        except urllib.error.HTTPError as e:
            error_body = e.read().decode("utf-8", errors="replace")
            fail(f"Inference API error: {e.code}")
            if self.debug:
                fail(f"[debug] Response: {error_body}")
            return f"[error: HTTP {e.code}]"

        except urllib.error.URLError as e:
            fail(f"Cannot reach inference backend at {self.base_url}")
            fail(f"  {e.reason}")
            info("Check MYCLY_INFERENCE_URL in your .env file.")
            return "[error: connection failed]"

        except Exception as e:
            fail(f"Inference error: {e}")
            return f"[error: {e}]"


# ============================================================
# Action Log & Rollback
# ============================================================

@dataclass
class ActionRecord:
    timestamp: str
    action: str
    target: str
    detail: str = ""
    rollback_path: str = ""
    success: bool = True

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


class ActionLog:
    """Append-only JSON log + file-level rollback snapshots."""

    def __init__(self):
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        SNAPSHOTS_DIR.mkdir(parents=True, exist_ok=True)
        self._log_file = LOG_DIR / "actions.jsonl"

    def snapshot(self, path: Path) -> str | None:
        """Copy a file before modifying it. Returns snapshot path."""
        if not path.exists():
            return None

        ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        safe_name = str(path).replace("/", "__").replace("\\", "__")
        snap_path = SNAPSHOTS_DIR / f"{ts}_{safe_name}"
        shutil.copy2(path, snap_path)
        return str(snap_path)

    def record(self, action: str, target: str, detail: str = "",
               rollback_path: str = "", success: bool = True) -> None:
        """Append an action to the log."""
        rec = ActionRecord(
            timestamp=datetime.datetime.now().isoformat(),
            action=action,
            target=target,
            detail=detail,
            rollback_path=rollback_path,
            success=success,
        )
        with open(self._log_file, "a") as f:
            f.write(json.dumps(rec.to_dict()) + "\n")

    def get_last(self, n: int = 10) -> list[ActionRecord]:
        """Read the last N actions from the log."""
        if not self._log_file.exists():
            return []
        lines = self._log_file.read_text().strip().splitlines()
        records = []
        for line in lines[-n:]:
            try:
                d = json.loads(line)
                records.append(ActionRecord(**d))
            except (json.JSONDecodeError, TypeError):
                continue
        return records

    def undo_last(self) -> bool:
        """Undo the most recent action that has a rollback snapshot."""
        records = self.get_last(50)
        for rec in reversed(records):
            if rec.rollback_path and Path(rec.rollback_path).exists():
                target = Path(rec.target)
                info(f"Restoring {target} from snapshot")
                shutil.copy2(rec.rollback_path, target)
                self.record(
                    action="undo",
                    target=str(target),
                    detail=f"Restored from {rec.rollback_path}",
                )
                ok(f"Undone: {rec.action} on {rec.target}")
                return True
        warn("No undoable actions found in recent log.")
        return False


# ============================================================
# System Detection (reuses Stage 0 report or detects fresh)
# ============================================================

def detect_system() -> dict[str, Any]:
    """Gather system information. Uses Stage 0 report if available."""
    report_path = MYCLY_HOME / "system-report.json"
    if report_path.exists():
        try:
            report = json.loads(report_path.read_text())
            # Check freshness (less than 1 hour old)
            ts = report.get("timestamp", "")
            if ts:
                try:
                    report_time = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
                    age = datetime.datetime.now(datetime.timezone.utc) - report_time
                    if age.total_seconds() < 3600:
                        return report
                except ValueError:
                    pass
        except json.JSONDecodeError:
            pass

    # Fresh detection
    info("Detecting system (no recent Stage 0 report found)...")
    system: dict[str, Any] = {
        "mycly_version": VERSION,
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "system": {
            "os": platform.system(),
            "os_type": platform.system().lower(),
            "arch": platform.machine(),
            "hostname": platform.node(),
            "python": platform.python_version(),
        },
    }

    # Tool inventory
    tools_to_check = [
        "git", "tmux", "fzf", "rg", "fd", "fdfind", "htop", "mc",
        "jq", "bat", "batcat", "tree", "nvim", "vim", "ssh",
        "chezmoi", "docker", "podman", "curl", "wget",
    ]
    found: dict[str, str] = {}
    for tool in tools_to_check:
        path = shutil.which(tool)
        if path:
            found[tool] = path

    system["tools"] = found
    return system


# ============================================================
# Tier 1 Actions — the things mycly can actually do
# ============================================================

def tool_is_installed(name: str) -> bool:
    """Check if a tool is on PATH."""
    return shutil.which(name) is not None


def install_tool_from_github(
    name: str,
    repo: str,
    asset_pattern: str,
    binary_name: str | None = None,
    log: ActionLog | None = None,
) -> bool:
    """
    Download a tool from GitHub releases to ~/.local/bin.
    asset_pattern: substring to match in the release asset filename
    binary_name: name of the binary inside the archive (if different from name)
    """
    if binary_name is None:
        binary_name = name

    bin_dir = Path.home() / ".local" / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)
    dest = bin_dir / binary_name

    step(f"Installing {name} from github.com/{repo}")

    # Check if already installed at destination
    if dest.exists():
        ok(f"{name} already at {dest}")
        return True

    # Get latest release info
    api_url = f"https://api.github.com/repos/{repo}/releases/latest"
    try:
        req = urllib.request.Request(api_url, headers={"User-Agent": "mycly"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            release = json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        fail(f"Cannot fetch release info: {e}")
        if log:
            log.record("install_tool", str(dest), f"Failed: {e}", success=False)
        return False

    # Find matching asset
    asset_url = None
    asset_name_found = None
    for asset in release.get("assets", []):
        if asset_pattern in asset["name"]:
            asset_url = asset["browser_download_url"]
            asset_name_found = asset["name"]
            break

    if not asset_url:
        fail(f"No matching asset for pattern '{asset_pattern}' in {repo}")
        available = [a["name"] for a in release.get("assets", [])]
        info(f"Available assets: {', '.join(available[:10])}")
        if log:
            log.record("install_tool", str(dest), "No matching asset", success=False)
        return False

    info(f"Downloading {asset_name_found}...")

    # Download to temp location
    tmp_dir = MYCLY_HOME / "tmp"
    tmp_dir.mkdir(parents=True, exist_ok=True)
    tmp_file = tmp_dir / asset_name_found

    try:
        req = urllib.request.Request(asset_url, headers={"User-Agent": "mycly"})
        with urllib.request.urlopen(req, timeout=120) as resp:
            tmp_file.write_bytes(resp.read())
    except Exception as e:
        fail(f"Download failed: {e}")
        if log:
            log.record("install_tool", str(dest), f"Download failed: {e}", success=False)
        return False

    # Extract based on file type
    try:
        if asset_name_found.endswith(".tar.gz") or asset_name_found.endswith(".tgz"):
            import tarfile
            with tarfile.open(tmp_file, "r:gz") as tar:
                # Find the binary in the archive
                for member in tar.getmembers():
                    if member.name.endswith(f"/{binary_name}") or member.name == binary_name:
                        member.name = binary_name
                        tar.extract(member, path=str(bin_dir))
                        break
                else:
                    # Try extracting everything and looking for it
                    tar.extractall(path=str(tmp_dir))
                    # Search for the binary
                    for p in tmp_dir.rglob(binary_name):
                        if p.is_file():
                            shutil.copy2(p, dest)
                            break

        elif asset_name_found.endswith(".zip"):
            import zipfile
            with zipfile.ZipFile(tmp_file) as zf:
                for zi in zf.infolist():
                    if zi.filename.endswith(f"/{binary_name}") or zi.filename == binary_name:
                        zi.filename = binary_name
                        zf.extract(zi, path=str(bin_dir))
                        break
                else:
                    zf.extractall(path=str(tmp_dir))
                    for p in tmp_dir.rglob(binary_name):
                        if p.is_file():
                            shutil.copy2(p, dest)
                            break

        elif asset_name_found.endswith(".gz") and not asset_name_found.endswith(".tar.gz"):
            import gzip
            with gzip.open(tmp_file, "rb") as gz:
                dest.write_bytes(gz.read())

        else:
            # Plain binary
            shutil.copy2(tmp_file, dest)

    except Exception as e:
        fail(f"Extraction failed: {e}")
        if log:
            log.record("install_tool", str(dest), f"Extract failed: {e}", success=False)
        return False
    finally:
        # Clean up temp files
        shutil.rmtree(tmp_dir, ignore_errors=True)

    # Make executable
    dest.chmod(0o755)

    # Verify
    if dest.exists() and dest.stat().st_size > 0:
        ok(f"{name} installed to {dest}")
        if log:
            log.record("install_tool", str(dest), f"From {repo} ({asset_name_found})")
        return True
    else:
        fail(f"Installation failed — {dest} is missing or empty")
        if log:
            log.record("install_tool", str(dest), "Binary missing after extract", success=False)
        return False


def write_gitconfig(desired: dict[str, Any], log: ActionLog) -> bool:
    """Write ~/.gitconfig from desired state."""
    identity = desired.get("identity", {})
    git_conf = desired.get("git", {})
    github = desired.get("accounts", {}).get("github", {})

    name = identity.get("name", "")
    email_section = identity.get("email", {})
    email = email_section.get("primary", identity.get("email", "")) if isinstance(email_section, dict) else identity.get("email", "")

    if not name or not email:
        warn("Cannot write .gitconfig — identity.name or identity.email missing from desired state")
        return False

    step("Configuring git")

    gitconfig_path = Path.home() / ".gitconfig"

    # Snapshot existing
    snap = log.snapshot(gitconfig_path)

    lines = [
        "[user]",
        f"\tname = {name}",
        f"\temail = {email}",
    ]

    if github.get("sign_commits"):
        lines.append("\tsigningkey = ")  # placeholder — real key from PM

    default_branch = git_conf.get("default_branch", "main")
    lines += [
        "",
        "[init]",
        f"\tdefaultBranch = {default_branch}",
    ]

    if git_conf.get("pull_rebase"):
        lines += [
            "",
            "[pull]",
            "\trebase = true",
        ]

    credential_helper = git_conf.get("credential_helper", "")
    if credential_helper:
        lines += [
            "",
            "[credential]",
            f"\thelper = {credential_helper}",
        ]

    # Common quality-of-life settings
    lines += [
        "",
        "[color]",
        "\tui = auto",
        "",
        "[core]",
        "\tautocrlf = input",
        "\teditor = nvim",
        "",
        "[alias]",
        "\tst = status",
        "\tco = checkout",
        "\tbr = branch",
        "\tlg = log --oneline --graph --decorate",
        "",
    ]

    content = "\n".join(lines) + "\n"

    # Write
    gitconfig_path.write_text(content)
    ok(f"Written {gitconfig_path}")
    log.record("write_gitconfig", str(gitconfig_path), f"name={name}, email={email}",
               rollback_path=snap or "")
    return True


def write_shell_aliases(desired: dict[str, Any], log: ActionLog) -> bool:
    """Write mycly shell aliases to a sourceable file and hook into .bashrc."""
    shell_conf = desired.get("shell", {})
    if not shell_conf.get("aliases", True):
        info("Shell aliases disabled in desired state")
        return True

    step("Setting up shell aliases")

    # Write aliases to a dedicated file
    aliases_file = MYCLY_HOME / "shell_aliases.sh"
    snap = log.snapshot(aliases_file)

    aliases = textwrap.dedent("""\
        # mycly shell aliases — managed by mycly, do not edit manually
        # Source: ~/.mycly/shell_aliases.sh

        # Navigation
        alias ..='cd ..'
        alias ...='cd ../..'
        alias ....='cd ../../..'

        # ls improvements
        if command -v eza >/dev/null 2>&1; then
            alias ls='eza'
            alias ll='eza -la'
            alias lt='eza -laT --level=2'
        else
            alias ll='ls -la'
            alias lt='ls -la'
        fi

        # Safety
        alias rm='rm -i'
        alias cp='cp -i'
        alias mv='mv -i'

        # Modern tool aliases (use modern tools if available, fall back gracefully)
        command -v bat    >/dev/null 2>&1 && alias cat='bat --paging=never'
        command -v batcat >/dev/null 2>&1 && alias cat='batcat --paging=never'
        command -v rg     >/dev/null 2>&1 && alias grep='rg'
        command -v fd     >/dev/null 2>&1 && alias find='fd'
        command -v fdfind >/dev/null 2>&1 && alias find='fdfind'

        # Git shortcuts
        alias gs='git status'
        alias gd='git diff'
        alias gl='git log --oneline --graph --decorate -20'
        alias gp='git pull --rebase'

        # Misc
        alias h='history | tail -30'
        alias myip='curl -s ifconfig.me'
        alias ports='ss -tuln'
        alias df='df -h'
        alias du='du -h --max-depth=1'
        alias tree='tree -C'

        # mycly
        alias m='python3 ~/.mycly/mycly.py'
    """)

    aliases_file.write_text(aliases)
    ok(f"Written {aliases_file}")

    # Hook into .bashrc if not already there
    bashrc = Path.home() / ".bashrc"
    source_line = f'\n# mycly shell integration\n[ -f "{aliases_file}" ] && source "{aliases_file}"\n'

    if bashrc.exists():
        existing = bashrc.read_text()
        if str(aliases_file) in existing:
            ok(".bashrc already sources mycly aliases")
        else:
            bashrc_snap = log.snapshot(bashrc)
            with open(bashrc, "a") as f:
                f.write(source_line)
            ok(f"Added mycly source line to {bashrc}")
            log.record("modify_bashrc", str(bashrc), "Added mycly alias source",
                       rollback_path=bashrc_snap or "")
    else:
        bashrc.write_text(source_line)
        ok(f"Created {bashrc} with mycly source line")

    log.record("write_aliases", str(aliases_file), rollback_path=snap or "")
    return True


# ============================================================
# GitHub Release Tool Database
# ============================================================

# Maps tool names to their GitHub repos and asset patterns per arch
TOOL_REGISTRY: dict[str, dict[str, Any]] = {
    "ripgrep": {
        "repo": "BurntSushi/ripgrep",
        "binary": "rg",
        "assets": {
            "x86_64": "x86_64-unknown-linux-musl.tar.gz",
            "aarch64": "aarch64-unknown-linux-gnu.tar.gz",
        },
    },
    "fd": {
        "repo": "sharkdp/fd",
        "binary": "fd",
        "assets": {
            "x86_64": "x86_64-unknown-linux-musl.tar.gz",
            "aarch64": "aarch64-unknown-linux-gnu.tar.gz",
        },
    },
    "bat": {
        "repo": "sharkdp/bat",
        "binary": "bat",
        "assets": {
            "x86_64": "x86_64-unknown-linux-musl.tar.gz",
            "aarch64": "aarch64-unknown-linux-gnu.tar.gz",
        },
    },
    "fzf": {
        "repo": "junegunn/fzf",
        "binary": "fzf",
        "assets": {
            "x86_64": "linux_amd64.tar.gz",
            "aarch64": "linux_arm64.tar.gz",
        },
    },
    "jq": {
        "repo": "jqlang/jq",
        "binary": "jq",
        "assets": {
            "x86_64": "jq-linux-amd64",
            "aarch64": "jq-linux-arm64",
        },
    },
    "eza": {
        "repo": "eza-community/eza",
        "binary": "eza",
        "assets": {
            "x86_64": "x86_64-unknown-linux-musl.tar.gz",
            "aarch64": "aarch64-unknown-linux-gnu.tar.gz",
        },
    },
}


def install_tools_from_desired_state(desired: dict[str, Any], log: ActionLog) -> None:
    """Install missing tools listed in desired state."""
    tools_config = desired.get("tools", {})
    tool_list = tools_config.get("core", [])

    if not tool_list:
        info("No tools listed in desired state")
        return

    step("Checking tools")
    arch = platform.machine()
    missing = []

    for tool_name in tool_list:
        # Check common binary name variations
        names_to_check = [tool_name]
        if tool_name == "ripgrep":
            names_to_check = ["rg", "ripgrep"]
        elif tool_name == "fd":
            names_to_check = ["fd", "fdfind"]
        elif tool_name == "bat":
            names_to_check = ["bat", "batcat"]

        found = any(tool_is_installed(n) for n in names_to_check)
        if found:
            ok(f"{tool_name}: installed")
        else:
            warn(f"{tool_name}: not found")
            missing.append(tool_name)

    if not missing:
        ok("All desired tools are installed")
        return

    info(f"\n  {len(missing)} tools to install: {', '.join(missing)}")

    for tool_name in missing:
        if tool_name not in TOOL_REGISTRY:
            info(f"  {tool_name}: not in tool registry, skipping (install manually or via package manager)")
            continue

        entry = TOOL_REGISTRY[tool_name]
        pattern = entry["assets"].get(arch, "")
        if not pattern:
            warn(f"  {tool_name}: no binary available for {arch}")
            continue

        install_tool_from_github(
            name=tool_name,
            repo=entry["repo"],
            asset_pattern=pattern,
            binary_name=entry.get("binary", tool_name),
            log=log,
        )


# ============================================================
# Commands
# ============================================================

def cmd_status(config: Config) -> None:
    """Show current system status and drift from desired state."""
    banner()
    step("System")
    system = detect_system()

    sys_info = system.get("system", {})
    info(f"OS: {sys_info.get('os', '?')} / {sys_info.get('arch', '?')}")
    info(f"Host: {sys_info.get('hostname', '?')}")
    info(f"Python: {sys_info.get('python', sys.version.split()[0])}")

    step("Inference backend")
    info(f"URL: {config.inference_url}")
    info(f"Model: {config.model}")

    # Quick connectivity check
    try:
        req = urllib.request.Request(
            config.inference_url.rstrip("/"),
            method="GET",
            headers={"User-Agent": "mycly"},
        )
        urllib.request.urlopen(req, timeout=5)
        ok("Backend reachable")
    except Exception:
        warn("Backend not reachable")

    step("Desired state")
    desired = load_desired_state()
    if desired:
        identity = desired.get("identity", {})
        ok(f"Loaded — identity: {identity.get('name', '?')}")
        tool_list = desired.get("tools", {}).get("core", [])
        if tool_list:
            installed = sum(1 for t in tool_list if tool_is_installed(t) or
                          tool_is_installed({"ripgrep": "rg", "fd": "fdfind", "bat": "batcat"}.get(t, t)))
            info(f"Tools: {installed}/{len(tool_list)} installed")
    else:
        warn("No desired-state file found")
        info("Create config/desired-state.toml (see templates/desired-state.template.toml)")

    step("Recent actions")
    log = ActionLog()
    records = log.get_last(5)
    if records:
        for rec in records:
            status = f"{T.GREEN}✓{T.RESET}" if rec.success else f"{T.RED}✗{T.RESET}"
            print(f"    {status} {rec.timestamp[:16]} {rec.action} → {rec.target}")
    else:
        info("No actions recorded yet")

    print()


def cmd_apply(config: Config) -> None:
    """Apply desired state — install tools, write configs."""
    banner()
    log = ActionLog()

    desired = load_desired_state()
    if not desired:
        fail("No desired-state file found.")
        info("Create config/desired-state.toml from the template.")
        return

    identity = desired.get("identity", {})
    step(f"Applying desired state for {identity.get('name', 'unknown user')}")

    # Ensure ~/.local/bin is on PATH
    local_bin = Path.home() / ".local" / "bin"
    local_bin.mkdir(parents=True, exist_ok=True)
    if str(local_bin) not in os.environ.get("PATH", ""):
        warn(f"{local_bin} is not on PATH")
        info("Add to your .bashrc:  export PATH=\"$HOME/.local/bin:$PATH\"")

    # 1. Install tools
    install_tools_from_desired_state(desired, log)

    # 2. Git configuration
    write_gitconfig(desired, log)

    # 3. Shell aliases
    write_shell_aliases(desired, log)

    # 4. Create directory structure
    files_conf = desired.get("files", {})
    dirs = files_conf.get("document_structure", [])
    if dirs:
        step("Creating directory structure")
        for d in dirs:
            dir_path = Path.home() / d
            dir_path.mkdir(parents=True, exist_ok=True)
            ok(f"{dir_path}")
        log.record("create_dirs", str(Path.home()),
                    f"Created: {', '.join(dirs)}")

    # Summary
    print()
    ok(f"{T.BOLD}Apply complete.{T.RESET}")
    info("Run 'source ~/.bashrc' to activate shell changes.")
    info("Run 'mycly status' to verify.")
    print()


def cmd_undo() -> None:
    """Undo the last recorded action."""
    banner()
    log = ActionLog()
    log.undo_last()


def cmd_log() -> None:
    """Show recent action log."""
    banner()
    step("Action log")
    log = ActionLog()
    records = log.get_last(20)
    if not records:
        info("No actions recorded.")
        return

    for rec in records:
        status = f"{T.GREEN}✓{T.RESET}" if rec.success else f"{T.RED}✗{T.RESET}"
        rollback = f" [snapshot: {Path(rec.rollback_path).name}]" if rec.rollback_path else ""
        print(f"  {status} {rec.timestamp[:19]}  {rec.action:<20} {rec.target}{rollback}")
        if rec.detail:
            print(f"    {T.DIM}{rec.detail}{T.RESET}")


def cmd_interactive(config: Config) -> None:
    """Interactive session — talk to the inference backend about your system."""
    banner()

    client = InferenceClient(config)
    system = detect_system()
    desired = load_desired_state()

    system_context = json.dumps(system, indent=2, default=str)
    desired_context = json.dumps(desired, indent=2, default=str) if desired else "No desired-state file loaded."

    system_prompt = textwrap.dedent(f"""\
        You are mycly, a personal systems agent. You help the user set up and maintain
        their working environment on this machine.

        Current system:
        {system_context}

        User's desired state:
        {desired_context}

        You can suggest commands to run, configurations to write, and tools to install.
        Be practical and specific to this system. When suggesting commands, use the
        actual paths and package managers available on this machine.

        Keep responses concise. Use bullet points for action items.
        When you suggest a file to write, show the full content.
    """)

    step("Interactive session")
    info(f"Backend: {config.inference_url} ({config.model})")
    info("Type 'quit' or Ctrl+C to exit.\n")

    while True:
        try:
            user_input = input(f"  {T.BOLD}you:{T.RESET} ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break

        if not user_input:
            continue
        if user_input.lower() in ("quit", "exit", "q"):
            break

        print()
        info("Thinking...")
        response = client.ask(user_input, system=system_prompt)

        if response.startswith("[error"):
            fail(response)
        else:
            # Print response with a left margin
            for line in response.splitlines():
                print(f"  {T.CYAN}mycly:{T.RESET} {line}")

        print()

    ok("Session ended.")


# ============================================================
# Entry Point
# ============================================================

def ensure_mycly_home() -> None:
    """Create mycly home directory structure."""
    for d in [MYCLY_HOME, SNAPSHOTS_DIR, LOG_DIR, CONFIG_DIR]:
        d.mkdir(parents=True, exist_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="mycly",
        description="mycly — Make Any Machine Yours",
    )
    parser.add_argument(
        "command",
        nargs="?",
        default="interactive",
        choices=["status", "apply", "undo", "log", "interactive"],
        help="Command to run (default: interactive)",
    )
    parser.add_argument("--version", action="version", version=f"mycly {VERSION}")

    args = parser.parse_args()

    ensure_mycly_home()
    config = Config.load()

    match args.command:
        case "status":
            cmd_status(config)
        case "apply":
            cmd_apply(config)
        case "undo":
            cmd_undo()
        case "log":
            cmd_log()
        case "interactive" | _:
            cmd_interactive(config)


if __name__ == "__main__":
    main()
