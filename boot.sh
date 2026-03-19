#!/bin/bash
# ============================================================
# mycly — Stage 0 Bootstrap
# Make Any Machine Yours
#
# Usage:
#   wget -qO- https://mycly.dev/boot | bash
#   curl -fsSL https://mycly.dev/boot | bash
#
# This script:
#   1. Detects the system (OS, distro, arch, resources)
#   2. Inventories available tools and runtimes
#   3. Authenticates the user (QR code / device code)
#   4. Downloads and launches Stage 1
#
# Requirements: bash, wget or curl
# Runs as: unprivileged user (no sudo required)
# ============================================================

set -euo pipefail

# ---- Constants ----

MYCLY_VERSION="0.1.0"
MYCLY_URL="https://mycly.dev"
MYCLY_API="${MYCLY_URL}/api/v1"
MYCLY_HOME="${HOME}/.mycly"
MYCLY_BIN="${HOME}/.local/bin"
MYCLY_LOG="${MYCLY_HOME}/log"

# ---- Terminal Colors & Symbols ----

setup_colors() {
    if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
        BOLD=$(tput bold)
        DIM=$(tput dim)
        RESET=$(tput sgr0)
        RED=$(tput setaf 1)
        GREEN=$(tput setaf 2)
        YELLOW=$(tput setaf 3)
        BLUE=$(tput setaf 4)
        CYAN=$(tput setaf 6)
    else
        BOLD="" DIM="" RESET=""
        RED="" GREEN="" YELLOW="" BLUE="" CYAN=""
    fi

    # Use unicode symbols if the terminal supports it, ASCII fallback otherwise
    if printf '\xe2\x9c\x93' 2>/dev/null | grep -q '✓' 2>/dev/null; then
        SYM_OK="✓"
        SYM_WARN="⚠"
        SYM_FAIL="✗"
        SYM_ARROW="→"
        SYM_DOT="·"
    else
        SYM_OK="+"
        SYM_WARN="!"
        SYM_FAIL="x"
        SYM_ARROW="->"
        SYM_DOT="*"
    fi
}

# ---- Output Helpers ----

info()    { echo "${BLUE}${SYM_DOT}${RESET} $*"; }
ok()      { echo "${GREEN}${SYM_OK}${RESET} $*"; }
warn()    { echo "${YELLOW}${SYM_WARN}${RESET} $*"; }
fail()    { echo "${RED}${SYM_FAIL}${RESET} $*" >&2; }
step()    { echo ""; echo "${BOLD}${SYM_ARROW} $*${RESET}"; }
detail()  { echo "  ${DIM}$*${RESET}"; }

die() {
    echo ""
    fail "$1"
    echo ""
    fail "mycly bootstrap failed. If this seems like a bug, please report it:"
    fail "  https://github.com/mgua/mycly/issues"
    echo ""
    exit "${2:-1}"
}

# ---- Banner ----

show_banner() {
    echo ""
    echo "${BOLD}${CYAN}  mycly${RESET} ${DIM}v${MYCLY_VERSION}${RESET}"
    echo "${DIM}  Make Any Machine Yours${RESET}"
    echo ""
}

# ---- Downloader Abstraction ----

DOWNLOADER=""

detect_downloader() {
    if command -v curl >/dev/null 2>&1; then
        DOWNLOADER="curl"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOADER="wget"
    else
        die "Neither curl nor wget found. Please install one of them and try again."
    fi
}

# Download URL to stdout
fetch() {
    local url="$1"
    if [ "$DOWNLOADER" = "curl" ]; then
        curl -fsSL "$url"
    else
        wget -qO- "$url"
    fi
}

# Download URL to file
fetch_to() {
    local url="$1"
    local dest="$2"
    if [ "$DOWNLOADER" = "curl" ]; then
        curl -fsSL -o "$dest" "$url"
    else
        wget -q -O "$dest" "$url"
    fi
}

# ---- System Detection ----

declare -A SYSTEM

detect_system() {
    step "Detecting system"

    # OS
    SYSTEM[os]="$(uname -s)"
    case "${SYSTEM[os]}" in
        Linux)  SYSTEM[os_type]="linux" ;;
        Darwin) SYSTEM[os_type]="macos" ;;
        CYGWIN*|MINGW*|MSYS*)
            SYSTEM[os_type]="windows_shell"
            warn "Detected Windows shell environment (${SYSTEM[os]})"
            warn "For native Windows, use the PowerShell installer instead:"
            warn "  irm ${MYCLY_URL}/boot.ps1 | iex"
            echo ""
            ;;
        FreeBSD)  SYSTEM[os_type]="freebsd" ;;
        *)
            SYSTEM[os_type]="unknown"
            warn "Unknown OS: ${SYSTEM[os]}. Will try to proceed anyway."
            ;;
    esac

    # Architecture
    SYSTEM[arch]="$(uname -m)"
    case "${SYSTEM[arch]}" in
        x86_64|amd64)   SYSTEM[arch_norm]="x64" ;;
        aarch64|arm64)  SYSTEM[arch_norm]="arm64" ;;
        armv7l|armhf)   SYSTEM[arch_norm]="armv7" ;;
        armv6l)         SYSTEM[arch_norm]="armv6" ;;
        i686|i386)      SYSTEM[arch_norm]="x86" ;;
        riscv64)        SYSTEM[arch_norm]="riscv64" ;;
        *)              SYSTEM[arch_norm]="unknown" ;;
    esac

    # Kernel
    SYSTEM[kernel]="$(uname -r)"

    # Hostname (for display only, never sent to remote backends)
    SYSTEM[hostname]="$(hostname 2>/dev/null || echo 'unknown')"

    ok "OS: ${SYSTEM[os]} (${SYSTEM[os_type]})"
    ok "Arch: ${SYSTEM[arch]} (${SYSTEM[arch_norm]})"
    detail "Kernel: ${SYSTEM[kernel]}"
    detail "Host: ${SYSTEM[hostname]}"
}

# ---- Linux Distribution Detection ----

declare -A DISTRO

detect_distro() {
    if [ "${SYSTEM[os_type]}" != "linux" ]; then
        return
    fi

    step "Detecting distribution"

    DISTRO[id]="unknown"
    DISTRO[name]="Unknown Linux"
    DISTRO[version]=""
    DISTRO[family]="unknown"

    # Try os-release first (modern standard)
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO[id]="${ID:-unknown}"
        DISTRO[name]="${PRETTY_NAME:-${NAME:-Unknown}}"
        DISTRO[version]="${VERSION_ID:-}"
        DISTRO[id_like]="${ID_LIKE:-}"
    elif [ -f /etc/redhat-release ]; then
        DISTRO[id]="rhel"
        DISTRO[name]="$(cat /etc/redhat-release)"
        DISTRO[family]="rhel"
    elif [ -f /etc/debian_version ]; then
        DISTRO[id]="debian"
        DISTRO[name]="Debian $(cat /etc/debian_version)"
        DISTRO[family]="debian"
    fi

    # Determine family from ID or ID_LIKE
    case "${DISTRO[id]}" in
        ubuntu|debian|mint|pop|raspbian|kali)
            DISTRO[family]="debian" ;;
        fedora|rhel|centos|rocky|alma|ol)
            DISTRO[family]="rhel" ;;
        arch|manjaro|endeavouros)
            DISTRO[family]="arch" ;;
        opensuse*|sles)
            DISTRO[family]="suse" ;;
        alpine)
            DISTRO[family]="alpine" ;;
        void)
            DISTRO[family]="void" ;;
        *)
            # Fall back to ID_LIKE
            case "${DISTRO[id_like]:-}" in
                *debian*|*ubuntu*) DISTRO[family]="debian" ;;
                *rhel*|*fedora*)   DISTRO[family]="rhel" ;;
                *arch*)            DISTRO[family]="arch" ;;
                *suse*)            DISTRO[family]="suse" ;;
            esac
            ;;
    esac

    # Check for musl vs glibc
    DISTRO[libc]="glibc"
    if [ -f /lib/libc.musl-*.so.1 ] 2>/dev/null || (ldd --version 2>&1 || true) | grep -qi musl; then
        DISTRO[libc]="musl"
    fi

    ok "${DISTRO[name]}"
    detail "Family: ${DISTRO[family]}, Libc: ${DISTRO[libc]}"
}

# ---- Resource Detection ----

declare -A RESOURCES

detect_resources() {
    step "Checking resources"

    # Memory (in MB)
    RESOURCES[mem_total_mb]=0
    if [ -f /proc/meminfo ]; then
        local mem_kb
        mem_kb=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')
        RESOURCES[mem_total_mb]=$((mem_kb / 1024))
    elif command -v sysctl >/dev/null 2>&1; then
        # macOS / BSD
        local mem_bytes
        mem_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
        RESOURCES[mem_total_mb]=$((mem_bytes / 1048576))
    fi

    # Disk space available in $HOME (in MB)
    RESOURCES[disk_avail_mb]=0
    if command -v df >/dev/null 2>&1; then
        # df -m is POSIX-ish but not universal; try it and fall back
        local disk_mb
        disk_mb=$(df -m "$HOME" 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)
        RESOURCES[disk_avail_mb]="${disk_mb:-0}"
    fi

    # CPU count
    RESOURCES[cpus]=1
    if [ -f /proc/cpuinfo ]; then
        RESOURCES[cpus]=$(grep -c '^processor' /proc/cpuinfo)
    elif command -v nproc >/dev/null 2>&1; then
        RESOURCES[cpus]=$(nproc)
    elif command -v sysctl >/dev/null 2>&1; then
        RESOURCES[cpus]=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
    fi

    # GPU / NPU detection (basic)
    RESOURCES[gpu]="none"
    if command -v nvidia-smi >/dev/null 2>&1; then
        RESOURCES[gpu]="nvidia"
    elif [ -d /sys/class/drm ] && ls /sys/class/drm/card*/device/vendor 2>/dev/null | head -1 | xargs cat 2>/dev/null | grep -q '0x1002'; then
        RESOURCES[gpu]="amd"
    elif [ -d /dev/dri ]; then
        RESOURCES[gpu]="drm_present"
    fi

    # Terminal size
    RESOURCES[cols]=$(tput cols 2>/dev/null || echo 80)
    RESOURCES[rows]=$(tput lines 2>/dev/null || echo 24)

    ok "Memory: ${RESOURCES[mem_total_mb]} MB"
    ok "Disk available: ${RESOURCES[disk_avail_mb]} MB in \$HOME"
    detail "CPUs: ${RESOURCES[cpus]}, GPU: ${RESOURCES[gpu]}"
    detail "Terminal: ${RESOURCES[cols]}x${RESOURCES[rows]}"

    # Warnings for constrained environments
    if [ "${RESOURCES[mem_total_mb]}" -lt 256 ]; then
        warn "Very low memory. mycly will use minimal mode."
    fi
    if [ "${RESOURCES[disk_avail_mb]}" -lt 100 ]; then
        warn "Very low disk space. Some features may be unavailable."
    fi
}

# ---- Privilege Detection ----

detect_privileges() {
    step "Checking privileges"

    SYSTEM[is_root]="no"
    SYSTEM[has_sudo]="no"
    SYSTEM[has_pkg_manager]="no"
    SYSTEM[pkg_managers]=""

    # Check if running as root
    if [ "$(id -u)" -eq 0 ]; then
        SYSTEM[is_root]="yes"
        warn "Running as root. mycly works best as a regular user."
    fi

    # Check sudo availability (non-interactively)
    if command -v sudo >/dev/null 2>&1; then
        if sudo -n true 2>/dev/null; then
            SYSTEM[has_sudo]="yes_passwordless"
            ok "sudo: available (passwordless)"
        else
            SYSTEM[has_sudo]="yes"
            ok "sudo: available (password required)"
        fi
    else
        SYSTEM[has_sudo]="no"
        info "sudo: not available. Will install tools to user directories."
    fi

    # Detect package managers
    local pkg_list=""
    for pm in apt dnf yum pacman zypper apk brew nix-env snap flatpak; do
        if command -v "$pm" >/dev/null 2>&1; then
            pkg_list="${pkg_list:+$pkg_list, }$pm"
        fi
    done
    # User-level package managers (always available if installed)
    for pm in pip pip3 cargo npm; do
        if command -v "$pm" >/dev/null 2>&1; then
            pkg_list="${pkg_list:+$pkg_list, }$pm"
        fi
    done

    if [ -n "$pkg_list" ]; then
        SYSTEM[has_pkg_manager]="yes"
        SYSTEM[pkg_managers]="$pkg_list"
        ok "Package managers: $pkg_list"
    else
        warn "No package managers detected."
    fi
}

# ---- Runtime & Tool Inventory ----

declare -A TOOLS

detect_tools() {
    step "Inventorying installed tools"

    local found=0
    local missing=0

    check_tool() {
        local name="$1"
        local cmd="${2:-$1}"
        if command -v "$cmd" >/dev/null 2>&1; then
            local ver
            ver=$("$cmd" --version 2>/dev/null | head -1 || echo "installed")
            TOOLS[$name]="$ver"
            detail "${GREEN}${SYM_OK}${RESET} ${name}: ${DIM}${ver}${RESET}"
            found=$((found + 1))
        else
            TOOLS[$name]=""
            missing=$((missing + 1))
        fi
    }

    # Runtimes (important for Stage 1 decision)
    info "Runtimes:"
    check_tool "python3" "python3"
    [ -z "${TOOLS[python3]}" ] && check_tool "python" "python"
    check_tool "node" "node"
    check_tool "deno" "deno"

    # Shell tools
    info "Shell & terminal:"
    check_tool "bash" "bash"
    check_tool "zsh" "zsh"
    check_tool "tmux" "tmux"
    check_tool "screen" "screen"

    # Core utilities
    info "Core tools:"
    check_tool "git" "git"
    check_tool "ssh" "ssh"
    check_tool "gpg" "gpg"
    check_tool "rsync" "rsync"

    # Editor
    info "Editors:"
    check_tool "nvim" "nvim"
    check_tool "vim" "vim"
    check_tool "vi" "vi"
    check_tool "nano" "nano"

    # Modern CLI tools
    info "Modern CLI:"
    check_tool "fzf" "fzf"
    check_tool "rg" "rg"
    check_tool "fd" "fd"
    [ -z "${TOOLS[fd]}" ] && check_tool "fdfind" "fdfind"
    check_tool "bat" "bat"
    [ -z "${TOOLS[bat]}" ] && check_tool "batcat" "batcat"
    check_tool "jq" "jq"
    check_tool "htop" "htop"
    check_tool "mc" "mc"
    check_tool "tree" "tree"

    # Configuration management
    info "Config management:"
    check_tool "chezmoi" "chezmoi"

    # Container / virtualization
    info "Containers:"
    check_tool "docker" "docker"
    check_tool "podman" "podman"

    echo ""
    ok "Found ${found} tools installed"
    if [ "$missing" -gt 0 ]; then
        info "${missing} common tools not yet installed"
    fi
}

# ---- Network Check ----

check_network() {
    step "Checking network"

    # Try to reach the mycly API
    local net_ok=false
    if fetch "${MYCLY_URL}/health" >/dev/null 2>&1; then
        net_ok=true
        ok "mycly.dev reachable"
    else
        # Fall back to a general connectivity check
        if fetch "https://api.anthropic.com" >/dev/null 2>&1 || \
           fetch "https://github.com" >/dev/null 2>&1; then
            net_ok=true
            ok "Internet reachable (mycly.dev not yet available)"
        fi
    fi

    if [ "$net_ok" = false ]; then
        warn "No network connectivity detected."
        warn "mycly will start in offline mode if a local cache exists."
    fi

    # Check for proxy settings
    if [ -n "${http_proxy:-}" ] || [ -n "${https_proxy:-}" ] || [ -n "${HTTP_PROXY:-}" ]; then
        info "Proxy detected: ${http_proxy:-${https_proxy:-${HTTP_PROXY:-}}}"
    fi
}

# ---- Authentication ----

authenticate() {
    step "Authentication"

    # Check for existing session
    if [ -f "${MYCLY_HOME}/session" ]; then
        local session_age
        session_age=$(( $(date +%s) - $(stat -c %Y "${MYCLY_HOME}/session" 2>/dev/null || stat -f %m "${MYCLY_HOME}/session" 2>/dev/null || echo 0) ))
        if [ "$session_age" -lt 86400 ]; then
            ok "Existing session found (less than 24h old)"
            return 0
        else
            info "Session expired. Re-authenticating."
        fi
    fi

    # Check for API key in environment (direct mode)
    if [ -n "${MYCLY_API_KEY:-}" ]; then
        ok "Using API key from environment"
        mkdir -p "${MYCLY_HOME}"
        echo "env_key" > "${MYCLY_HOME}/session"
        return 0
    fi

    echo ""
    info "mycly needs to verify your identity."
    info "This is a one-time setup per machine."
    echo ""

    # Prompt for email
    local email=""
    if [ -t 0 ]; then
        # Interactive terminal — prompt the user
        printf "  ${BOLD}Email address:${RESET} "
        read -r email
    else
        # Piped input (wget | bash) — we need to read from /dev/tty
        printf "  ${BOLD}Email address:${RESET} "
        read -r email < /dev/tty
    fi

    if [ -z "$email" ]; then
        die "Email address is required for authentication."
    fi

    # Request a device authorization session
    # TODO: Replace with actual API call when backend is ready
    info "Requesting authorization..."

    local session_id
    session_id="mycly-$(date +%s)-$$"
    local auth_url="${MYCLY_URL}/auth?session=${session_id}&email=${email}"
    local short_code
    short_code=$(echo "$session_id" | md5sum 2>/dev/null | head -c 8 | tr '[:lower:]' '[:upper:]' || echo "ABCD1234")
    short_code="${short_code:0:4}-${short_code:4:4}"

    echo ""

    # Display QR code if terminal is large enough and qrencode is available
    local showed_qr=false
    if [ "${RESOURCES[cols]:-80}" -ge 60 ] && [ "${RESOURCES[rows]:-24}" -ge 20 ]; then
        if command -v qrencode >/dev/null 2>&1; then
            info "Scan this QR code with your phone:"
            echo ""
            qrencode -t ANSIUTF8 -m 1 "$auth_url" 2>/dev/null && showed_qr=true
            echo ""
        fi
    fi

    # Always show the manual fallback
    if [ "$showed_qr" = false ]; then
        info "To authorize this machine:"
        echo ""
        echo "  ${BOLD}1.${RESET} Open ${CYAN}${MYCLY_URL}/auth${RESET} on your phone or browser"
        echo "  ${BOLD}2.${RESET} Enter code: ${BOLD}${YELLOW}${short_code}${RESET}"
        echo ""
    else
        info "Or enter code ${BOLD}${YELLOW}${short_code}${RESET} at ${CYAN}${MYCLY_URL}/auth${RESET}"
    fi

    # Poll for authorization
    info "Waiting for authorization..."
    local attempts=0
    local max_attempts=120  # 2 minutes at 1s intervals
    local authorized=false

    while [ "$attempts" -lt "$max_attempts" ]; do
        # TODO: Replace with actual polling when backend is ready
        # For now, simulate authorization after a brief wait for development
        sleep 1
        attempts=$((attempts + 1))

        # Visual feedback: a subtle spinner
        local spinner_chars='|/-\'
        local spinner_char="${spinner_chars:$((attempts % 4)):1}"
        printf "\r  ${DIM}${spinner_char} Waiting... (%ds)${RESET}  " "$attempts"

        # TODO: Actual check:
        # if fetch "${MYCLY_API}/auth/check?session=${session_id}" 2>/dev/null | grep -q '"authorized":true'; then
        #     authorized=true
        #     break
        # fi

        # Development shortcut: auto-authorize after 3 seconds
        if [ "$attempts" -ge 3 ]; then
            authorized=true
            break
        fi
    done

    printf "\r                                     \r"  # Clear spinner line

    if [ "$authorized" = true ]; then
        ok "Authorization successful!"
        mkdir -p "${MYCLY_HOME}"
        echo "${session_id}" > "${MYCLY_HOME}/session"
        chmod 600 "${MYCLY_HOME}/session"
    else
        die "Authorization timed out. Please try again."
    fi
}

# ---- Stage 1 Download & Launch ----

prepare_stage1() {
    step "Preparing mycly agent"

    mkdir -p "${MYCLY_HOME}" "${MYCLY_BIN}" "${MYCLY_LOG}"

    # Decide which Stage 1 variant to fetch based on available runtimes
    local stage1_type=""

    if [ -n "${TOOLS[python3]:-}" ] || [ -n "${TOOLS[python]:-}" ]; then
        stage1_type="python"
        ok "Using Python-based agent (full capabilities)"
    elif [ -n "${TOOLS[node]:-}" ]; then
        stage1_type="node"
        ok "Using Node.js-based agent"
    else
        stage1_type="bash"
        ok "Using bash-based agent (lightweight mode)"
        info "Install Python 3.8+ for full mycly capabilities"
    fi

    # Check if Stage 1 is already cached and up to date
    if [ -f "${MYCLY_HOME}/agent/version" ]; then
        local cached_ver
        cached_ver=$(cat "${MYCLY_HOME}/agent/version")
        info "Cached agent found: v${cached_ver}"
        # TODO: Check for updates
    fi

    # Download Stage 1
    info "Downloading mycly agent (${stage1_type})..."

    # TODO: Replace with actual download when packages are built
    # fetch_to "${MYCLY_API}/stage1/${stage1_type}/${SYSTEM[os_type]}/${SYSTEM[arch_norm]}" \
    #          "${MYCLY_HOME}/agent/mycly-agent"

    # For now, create a placeholder that shows the system report
    mkdir -p "${MYCLY_HOME}/agent"
    echo "${MYCLY_VERSION}" > "${MYCLY_HOME}/agent/version"
    echo "${stage1_type}" > "${MYCLY_HOME}/agent/type"

    ok "Agent ready"
}

# ---- System Report ----

write_system_report() {
    # Write a structured JSON report of everything we found
    # This is what Stage 1 uses to understand the system

    local report_file="${MYCLY_HOME}/system-report.json"

    cat > "$report_file" << REPORT_EOF
{
  "mycly_version": "${MYCLY_VERSION}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)",
  "system": {
    "os": "${SYSTEM[os]}",
    "os_type": "${SYSTEM[os_type]}",
    "arch": "${SYSTEM[arch]}",
    "arch_norm": "${SYSTEM[arch_norm]}",
    "kernel": "${SYSTEM[kernel]}",
    "hostname": "${SYSTEM[hostname]}",
    "is_root": "${SYSTEM[is_root]}",
    "has_sudo": "${SYSTEM[has_sudo]}"
  },
  "distro": {
    "id": "${DISTRO[id]:-n/a}",
    "name": "${DISTRO[name]:-n/a}",
    "version": "${DISTRO[version]:-}",
    "family": "${DISTRO[family]:-n/a}",
    "libc": "${DISTRO[libc]:-n/a}"
  },
  "resources": {
    "mem_total_mb": ${RESOURCES[mem_total_mb]},
    "disk_avail_mb": ${RESOURCES[disk_avail_mb]},
    "cpus": ${RESOURCES[cpus]},
    "gpu": "${RESOURCES[gpu]}",
    "terminal_cols": ${RESOURCES[cols]:-80},
    "terminal_rows": ${RESOURCES[rows]:-24}
  },
  "package_managers": "${SYSTEM[pkg_managers]}",
  "stage1_type": "$(cat "${MYCLY_HOME}/agent/type" 2>/dev/null || echo 'unknown')"
}
REPORT_EOF

    chmod 600 "$report_file"
    detail "System report written to ${report_file}"
}

# ---- Summary ----

show_summary() {
    echo ""
    echo "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    echo "  ${BOLD}mycly is ready.${RESET}"
    echo ""
    echo "  ${DIM}System:${RESET}    ${SYSTEM[os_type]} / ${SYSTEM[arch_norm]}"
    [ -n "${DISTRO[name]:-}" ] && echo "  ${DIM}Distro:${RESET}    ${DISTRO[name]}"
    echo "  ${DIM}Memory:${RESET}    ${RESOURCES[mem_total_mb]} MB"
    echo "  ${DIM}Sudo:${RESET}      ${SYSTEM[has_sudo]}"
    echo "  ${DIM}Agent:${RESET}     $(cat "${MYCLY_HOME}/agent/type" 2>/dev/null || echo 'pending')"
    echo ""
    echo "  To start mycly:"
    echo "    ${BOLD}mycly${RESET}"
    echo ""
    echo "  To see what mycly knows about this system:"
    echo "    ${BOLD}mycly status${RESET}"
    echo ""
    echo "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
}

# ---- Main ----

main() {
    setup_colors
    show_banner

    # Core detection
    detect_downloader
    detect_system
    detect_distro
    detect_resources
    detect_privileges
    detect_tools

    # Network & auth
    check_network
    authenticate

    # Stage 1
    prepare_stage1
    write_system_report

    # Done
    show_summary

    # TODO: Launch Stage 1 agent
    # exec "${MYCLY_HOME}/agent/mycly-agent" --first-run
}

main "$@"
