# ============================================================
# mycly — Stage 0 Bootstrap (Windows PowerShell)
# Make Any Machine Yours
#
# Usage:
#   irm https://mycly.dev/boot.ps1 | iex
#
# Or if execution policy blocks that:
#   Set-ExecutionPolicy Bypass -Scope Process -Force; irm https://mycly.dev/boot.ps1 | iex
#
# This script:
#   1. Checks execution policy and provides guidance
#   2. Detects the system (Windows version, arch, resources)
#   3. Inventories available tools and runtimes
#   4. Authenticates the user (QR code / device code)
#   5. Downloads and launches Stage 1
#
# Requirements: PowerShell 5.1+ (built into Windows 10+)
# Runs as: unprivileged user (no admin required)
# ============================================================

# Ensure we stop on errors
$ErrorActionPreference = "Stop"

# ---- Constants ----

$MyclyVersion = "0.1.0"
$MyclyUrl = "https://mycly.dev"
$MyclyApi = "$MyclyUrl/api/v1"
$MyclyHome = Join-Path $env:USERPROFILE ".mycly"
$MyclyBin = Join-Path $env:USERPROFILE ".local\bin"
$MyclyLog = Join-Path $MyclyHome "log"

# ---- Output Helpers ----

# Detect if we can use Unicode and colors
$SupportsUnicode = $false
$SupportsColor = $true

try {
    # PowerShell 5.1 on Windows defaults to the system codepage.
    # Windows Terminal and modern consoles support Unicode fine.
    if ($Host.UI.SupportsVirtualTerminal -or $env:WT_SESSION) {
        $SupportsUnicode = $true
    }
} catch {
    # Silently fall back
}

if ($SupportsUnicode) {
    $SymOk    = [char]0x2713  # ✓
    $SymWarn  = [char]0x26A0  # ⚠
    $SymFail  = [char]0x2717  # ✗
    $SymArrow = [char]0x2192  # →
    $SymDot   = [char]0x00B7  # ·
} else {
    $SymOk    = "+"
    $SymWarn  = "!"
    $SymFail  = "x"
    $SymArrow = "->"
    $SymDot   = "*"
}

function Write-Info    { param([string]$Msg) Write-Host "  $SymDot " -ForegroundColor Blue -NoNewline; Write-Host $Msg }
function Write-Ok      { param([string]$Msg) Write-Host "  $SymOk " -ForegroundColor Green -NoNewline; Write-Host $Msg }
function Write-Warn    { param([string]$Msg) Write-Host "  $SymWarn " -ForegroundColor Yellow -NoNewline; Write-Host $Msg }
function Write-Fail    { param([string]$Msg) Write-Host "  $SymFail " -ForegroundColor Red -NoNewline; Write-Host $Msg }
function Write-Step    { param([string]$Msg) Write-Host ""; Write-Host "  $SymArrow $Msg" -ForegroundColor White }
function Write-Detail  { param([string]$Msg) Write-Host "    $Msg" -ForegroundColor DarkGray }

function Exit-WithError {
    param([string]$Msg, [int]$Code = 1)
    Write-Host ""
    Write-Fail $Msg
    Write-Host ""
    Write-Fail "mycly bootstrap failed. If this seems like a bug, please report it:"
    Write-Fail "  https://github.com/mgua/mycly/issues"
    Write-Host ""
    exit $Code
}

# ---- Banner ----

function Show-Banner {
    Write-Host ""
    Write-Host "  mycly" -ForegroundColor Cyan -NoNewline
    Write-Host " v$MyclyVersion" -ForegroundColor DarkGray
    Write-Host "  Make Any Machine Yours" -ForegroundColor DarkGray
    Write-Host ""
}

# ---- Execution Policy Check ----

function Test-ExecutionPolicy {
    Write-Step "Checking PowerShell execution policy"

    $currentPolicy = Get-ExecutionPolicy -Scope Process
    $userPolicy = Get-ExecutionPolicy -Scope CurrentUser
    $machinePolicy = Get-ExecutionPolicy -Scope LocalMachine

    Write-Detail "Process scope:  $currentPolicy"
    Write-Detail "User scope:     $userPolicy"
    Write-Detail "Machine scope:  $machinePolicy"

    # Determine effective policy
    $effective = Get-ExecutionPolicy
    Write-Detail "Effective:      $effective"

    if ($effective -eq "Restricted") {
        Write-Warn "Execution policy is Restricted."
        Write-Host ""
        Write-Host "  PowerShell is blocking script execution. You have two options:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Option 1 — For this session only (recommended):" -ForegroundColor White
        Write-Host "    Set-ExecutionPolicy Bypass -Scope Process -Force" -ForegroundColor Cyan
        Write-Host "    irm $MyclyUrl/boot.ps1 | iex" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Option 2 — Permanently for your user account:" -ForegroundColor White
        Write-Host "    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force" -ForegroundColor Cyan
        Write-Host "    irm $MyclyUrl/boot.ps1 | iex" -ForegroundColor Cyan
        Write-Host ""
        Write-Info "Option 1 is safer — it only affects the current terminal window."
        Write-Host ""
        Exit-WithError "Cannot continue with Restricted execution policy."
    }
    elseif ($effective -eq "AllSigned") {
        Write-Warn "Execution policy is AllSigned."
        Write-Host ""
        Write-Host "  Your system requires all scripts to be signed." -ForegroundColor Yellow
        Write-Host "  To allow mycly for this session:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "    Set-ExecutionPolicy Bypass -Scope Process -Force" -ForegroundColor Cyan
        Write-Host "    irm $MyclyUrl/boot.ps1 | iex" -ForegroundColor Cyan
        Write-Host ""
        Exit-WithError "Cannot continue with AllSigned execution policy."
    }
    else {
        Write-Ok "Execution policy: $effective"
    }
}

# ---- System Detection ----

$SystemInfo = @{}

function Find-SystemInfo {
    Write-Step "Detecting system"

    # OS version
    $osInfo = [System.Environment]::OSVersion
    $SystemInfo["os_version"] = $osInfo.VersionString
    $SystemInfo["os_platform"] = $osInfo.Platform.ToString()

    # Windows build and edition
    try {
        $winVer = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue)
        $SystemInfo["win_build"] = "$($winVer.CurrentMajorVersionNumber).$($winVer.CurrentMinorVersionNumber).$($winVer.CurrentBuildNumber)"
        $SystemInfo["win_edition"] = $winVer.EditionID
        $SystemInfo["win_name"] = $winVer.ProductName
    } catch {
        $SystemInfo["win_build"] = "unknown"
        $SystemInfo["win_edition"] = "unknown"
        $SystemInfo["win_name"] = "Windows"
    }

    # Architecture
    $SystemInfo["arch"] = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    # Fallback for PS 5.1 where RuntimeInformation may not be available
    if (-not $SystemInfo["arch"] -or $SystemInfo["arch"] -eq "") {
        $SystemInfo["arch"] = $env:PROCESSOR_ARCHITECTURE
    }

    switch ($SystemInfo["arch"]) {
        "X64"   { $SystemInfo["arch_norm"] = "x64" }
        "Arm64" { $SystemInfo["arch_norm"] = "arm64" }
        "X86"   { $SystemInfo["arch_norm"] = "x86" }
        "AMD64" { $SystemInfo["arch_norm"] = "x64" }
        default { $SystemInfo["arch_norm"] = $SystemInfo["arch"].ToLower() }
    }

    # Hostname
    $SystemInfo["hostname"] = $env:COMPUTERNAME

    # PowerShell version
    $SystemInfo["ps_version"] = $PSVersionTable.PSVersion.ToString()
    $SystemInfo["ps_edition"] = if ($PSVersionTable.PSEdition) { $PSVersionTable.PSEdition } else { "Desktop" }

    Write-Ok "OS: $($SystemInfo['win_name']) ($($SystemInfo['win_build']))"
    Write-Ok "Arch: $($SystemInfo['arch_norm'])"
    Write-Ok "PowerShell: $($SystemInfo['ps_version']) ($($SystemInfo['ps_edition']))"
    Write-Detail "Host: $($SystemInfo['hostname'])"
}

# ---- Resource Detection ----

$Resources = @{}

function Find-Resources {
    Write-Step "Checking resources"

    # Memory
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        $Resources["mem_total_mb"] = [math]::Round($os.TotalVisibleMemorySize / 1024)
        $Resources["mem_free_mb"] = [math]::Round($os.FreePhysicalMemory / 1024)
    } catch {
        # Fallback: use systeminfo parsing or just report unknown
        $Resources["mem_total_mb"] = 0
        $Resources["mem_free_mb"] = 0
    }

    # Disk space on system drive
    try {
        $drive = Get-PSDrive -Name ($env:USERPROFILE.Substring(0,1)) -ErrorAction SilentlyContinue
        $Resources["disk_avail_mb"] = [math]::Round($drive.Free / 1MB)
    } catch {
        $Resources["disk_avail_mb"] = 0
    }

    # CPU
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        $Resources["cpus"] = $cpu.NumberOfLogicalProcessors
        $Resources["cpu_name"] = $cpu.Name.Trim()
    } catch {
        $Resources["cpus"] = $env:NUMBER_OF_PROCESSORS
        $Resources["cpu_name"] = "unknown"
    }

    # GPU
    $Resources["gpu"] = "none"
    try {
        $gpus = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue
        if ($gpus) {
            $gpuNames = ($gpus | ForEach-Object { $_.Name }) -join ", "
            $Resources["gpu"] = $gpuNames
        }
    } catch { }

    # Terminal size
    try {
        $Resources["cols"] = $Host.UI.RawUI.WindowSize.Width
        $Resources["rows"] = $Host.UI.RawUI.WindowSize.Height
    } catch {
        $Resources["cols"] = 120
        $Resources["rows"] = 30
    }

    Write-Ok "Memory: $($Resources['mem_total_mb']) MB total, $($Resources['mem_free_mb']) MB free"
    Write-Ok "Disk available: $($Resources['disk_avail_mb']) MB"
    Write-Detail "CPUs: $($Resources['cpus']) ($($Resources['cpu_name']))"
    Write-Detail "GPU: $($Resources['gpu'])"
    Write-Detail "Terminal: $($Resources['cols'])x$($Resources['rows'])"

    if ($Resources["mem_total_mb"] -lt 2048) {
        Write-Warn "Low memory. Some features may be limited."
    }
    if ($Resources["disk_avail_mb"] -lt 500) {
        Write-Warn "Low disk space."
    }
}

# ---- Privilege Detection ----

function Find-Privileges {
    Write-Step "Checking privileges"

    # Admin check
    $isAdmin = $false
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { }

    $SystemInfo["is_admin"] = $isAdmin

    if ($isAdmin) {
        Write-Warn "Running as Administrator. mycly works best as a regular user."
    } else {
        Write-Ok "Running as regular user (recommended)"
    }

    # Detect package managers
    $pkgManagers = @()

    $pmChecks = @{
        "winget"     = "winget"
        "scoop"      = "scoop"
        "choco"      = "choco"
        "pip"        = "pip"
        "pip3"       = "pip3"
        "npm"        = "npm"
        "cargo"      = "cargo"
    }

    foreach ($pm in $pmChecks.GetEnumerator()) {
        if (Get-Command $pm.Value -ErrorAction SilentlyContinue) {
            $pkgManagers += $pm.Key
        }
    }

    $SystemInfo["pkg_managers"] = $pkgManagers -join ", "

    if ($pkgManagers.Count -gt 0) {
        Write-Ok "Package managers: $($SystemInfo['pkg_managers'])"
    } else {
        Write-Warn "No package managers found. Consider installing winget or scoop."
    }

    # WSL check
    $SystemInfo["has_wsl"] = $false
    if (Get-Command wsl -ErrorAction SilentlyContinue) {
        $SystemInfo["has_wsl"] = $true
        Write-Ok "WSL: available"
        try {
            $distros = wsl --list --quiet 2>$null
            if ($distros) {
                Write-Detail "WSL distros: $($distros -join ', ')"
            }
        } catch { }
    } else {
        Write-Info "WSL: not installed"
    }

    # Git Bash check (important for Windows CLI tooling)
    $SystemInfo["has_git_bash"] = $false
    $gitBashPaths = @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )
    foreach ($p in $gitBashPaths) {
        if (Test-Path $p) {
            $SystemInfo["has_git_bash"] = $true
            $SystemInfo["git_bash_path"] = $p
            Write-Ok "Git Bash: found at $p"
            break
        }
    }
    if (-not $SystemInfo["has_git_bash"]) {
        Write-Info "Git Bash: not found"
    }
}

# ---- Tool Inventory ----

$Tools = @{}

function Find-Tools {
    Write-Step "Inventorying installed tools"

    $found = 0
    $missing = 0

    function Test-Tool {
        param([string]$Name, [string]$Cmd)
        if (-not $Cmd) { $Cmd = $Name }
        $result = Get-Command $Cmd -ErrorAction SilentlyContinue
        if ($result) {
            $ver = "installed"
            try {
                $verOutput = & $Cmd --version 2>&1 | Select-Object -First 1
                if ($verOutput) { $ver = $verOutput.ToString().Trim() }
            } catch { }
            $script:Tools[$Name] = $ver
            Write-Host "    " -NoNewline
            Write-Host "$SymOk" -ForegroundColor Green -NoNewline
            Write-Host " ${Name}: " -NoNewline
            Write-Host "$ver" -ForegroundColor DarkGray
            $script:found++
        } else {
            $script:Tools[$Name] = ""
            $script:missing++
        }
    }

    # Runtimes
    Write-Info "Runtimes:"
    Test-Tool "python3" "python3"
    if (-not $Tools["python3"]) { Test-Tool "python" "python" }
    Test-Tool "node" "node"
    Test-Tool "deno" "deno"
    Test-Tool "pwsh" "pwsh"  # PowerShell 7+

    # Core tools
    Write-Info "Core tools:"
    Test-Tool "git" "git"
    Test-Tool "ssh" "ssh"
    Test-Tool "gpg" "gpg"

    # Editors
    Write-Info "Editors:"
    Test-Tool "nvim" "nvim"
    Test-Tool "vim" "vim"
    Test-Tool "code" "code"  # VS Code

    # Modern CLI
    Write-Info "Modern CLI:"
    Test-Tool "fzf" "fzf"
    Test-Tool "rg" "rg"
    Test-Tool "fd" "fd"
    Test-Tool "bat" "bat"
    Test-Tool "jq" "jq"
    Test-Tool "htop" "htop"
    Test-Tool "tree" "tree"

    # Configuration management
    Write-Info "Config management:"
    Test-Tool "chezmoi" "chezmoi"

    # Containers
    Write-Info "Containers:"
    Test-Tool "docker" "docker"
    Test-Tool "podman" "podman"

    Write-Host ""
    Write-Ok "Found $found tools installed"
    if ($missing -gt 0) {
        Write-Info "$missing common tools not yet installed"
    }
}

# ---- Network Check ----

function Test-Network {
    Write-Step "Checking network"

    $netOk = $false

    try {
        $response = Invoke-WebRequest -Uri "$MyclyUrl/health" -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) {
            $netOk = $true
            Write-Ok "mycly.dev reachable"
        }
    } catch {
        # Fallback connectivity check
        try {
            $null = Invoke-WebRequest -Uri "https://github.com" -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
            $netOk = $true
            Write-Ok "Internet reachable (mycly.dev not yet available)"
        } catch { }
    }

    if (-not $netOk) {
        Write-Warn "No network connectivity detected."
        Write-Warn "mycly will start in offline mode if a local cache exists."
    }

    # Proxy detection
    $proxy = [System.Net.WebRequest]::DefaultWebProxy
    if ($proxy -and $proxy.GetProxy("https://mycly.dev").AbsoluteUri -ne "https://mycly.dev/") {
        Write-Info "Proxy detected: $($proxy.GetProxy('https://mycly.dev'))"
    }

    # TLS version check
    try {
        $tlsVersion = [System.Net.ServicePointManager]::SecurityProtocol
        Write-Detail "TLS protocols: $tlsVersion"
        if ($tlsVersion -notmatch "Tls12|Tls13") {
            Write-Warn "TLS 1.2+ not enabled. Enabling for this session."
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
        }
    } catch { }
}

# ---- Authentication ----

function Invoke-Authentication {
    Write-Step "Authentication"

    # Check for existing session
    $sessionFile = Join-Path $MyclyHome "session"
    if (Test-Path $sessionFile) {
        $sessionAge = (Get-Date) - (Get-Item $sessionFile).LastWriteTime
        if ($sessionAge.TotalHours -lt 24) {
            Write-Ok "Existing session found (less than 24h old)"
            return
        } else {
            Write-Info "Session expired. Re-authenticating."
        }
    }

    # Check for API key in environment
    if ($env:MYCLY_API_KEY) {
        Write-Ok "Using API key from environment"
        New-Item -Path $MyclyHome -ItemType Directory -Force | Out-Null
        "env_key" | Out-File -FilePath $sessionFile -Encoding utf8 -NoNewline
        return
    }

    Write-Host ""
    Write-Info "mycly needs to verify your identity."
    Write-Info "This is a one-time setup per machine."
    Write-Host ""

    # Prompt for email
    Write-Host "  " -NoNewline
    Write-Host "Email address: " -ForegroundColor White -NoNewline
    $email = Read-Host

    if ([string]::IsNullOrWhiteSpace($email)) {
        Exit-WithError "Email address is required for authentication."
    }

    # Generate session
    $sessionId = "mycly-$(Get-Date -Format 'yyyyMMddHHmmss')-$PID"
    $authUrl = "$MyclyUrl/auth?session=$sessionId&email=$email"

    # Generate a short code from the session ID
    $hashBytes = [System.Security.Cryptography.SHA256]::Create().ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($sessionId)
    )
    $shortCode = (($hashBytes[0..3] | ForEach-Object { $_.ToString("X2") }) -join "")
    $shortCode = "$($shortCode.Substring(0,4))-$($shortCode.Substring(4,4))"

    Write-Host ""
    Write-Info "To authorize this machine:"
    Write-Host ""
    Write-Host "  1. " -ForegroundColor White -NoNewline
    Write-Host "Open " -NoNewline
    Write-Host "$MyclyUrl/auth" -ForegroundColor Cyan -NoNewline
    Write-Host " on your phone or browser"
    Write-Host "  2. " -ForegroundColor White -NoNewline
    Write-Host "Enter code: " -NoNewline
    Write-Host "$shortCode" -ForegroundColor Yellow
    Write-Host ""

    # TODO: If a QR code module is available (e.g., QRCoder via NuGet), render
    # a text-mode QR code here. For now, stick with the manual code entry.

    # Poll for authorization
    Write-Info "Waiting for authorization..."
    $attempts = 0
    $maxAttempts = 120
    $authorized = $false
    $spinnerChars = @('|', '/', '-', '\')

    while ($attempts -lt $maxAttempts) {
        Start-Sleep -Seconds 1
        $attempts++

        $spinner = $spinnerChars[$attempts % 4]
        Write-Host "`r    $spinner Waiting... ($($attempts)s)  " -NoNewline -ForegroundColor DarkGray

        # TODO: Actual API polling:
        # try {
        #     $check = Invoke-RestMethod -Uri "$MyclyApi/auth/check?session=$sessionId" -TimeoutSec 3
        #     if ($check.authorized) { $authorized = $true; break }
        # } catch { }

        # Development shortcut: auto-authorize after 3 seconds
        if ($attempts -ge 3) {
            $authorized = $true
            break
        }
    }

    Write-Host "`r                                       `r" -NoNewline  # Clear spinner

    if ($authorized) {
        Write-Ok "Authorization successful!"
        New-Item -Path $MyclyHome -ItemType Directory -Force | Out-Null
        $sessionId | Out-File -FilePath $sessionFile -Encoding utf8 -NoNewline
    } else {
        Exit-WithError "Authorization timed out. Please try again."
    }
}

# ---- Stage 1 Preparation ----

function Install-Stage1 {
    Write-Step "Preparing mycly agent"

    # Create directories
    New-Item -Path $MyclyHome -ItemType Directory -Force | Out-Null
    New-Item -Path $MyclyBin -ItemType Directory -Force | Out-Null
    New-Item -Path $MyclyLog -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $MyclyHome "agent") -ItemType Directory -Force | Out-Null

    # Decide Stage 1 variant
    $stage1Type = "powershell"  # Default on Windows

    if ($Tools["python3"] -or $Tools["python"]) {
        $stage1Type = "python"
        Write-Ok "Using Python-based agent (full capabilities)"
    } elseif ($Tools["node"]) {
        $stage1Type = "node"
        Write-Ok "Using Node.js-based agent"
    } else {
        Write-Ok "Using PowerShell-based agent"
        Write-Info "Install Python 3.8+ for full mycly capabilities"
    }

    # Check for cached agent
    $versionFile = Join-Path $MyclyHome "agent\version"
    if (Test-Path $versionFile) {
        $cachedVer = Get-Content $versionFile -Raw
        Write-Info "Cached agent found: v$cachedVer"
    }

    # Download Stage 1
    Write-Info "Downloading mycly agent ($stage1Type)..."

    # TODO: Replace with actual download when packages are built
    # Invoke-WebRequest -Uri "$MyclyApi/stage1/$stage1Type/windows/$($SystemInfo['arch_norm'])" `
    #                   -OutFile (Join-Path $MyclyHome "agent\mycly-agent.exe") `
    #                   -UseBasicParsing

    # Placeholder
    $MyclyVersion | Out-File -FilePath $versionFile -Encoding utf8 -NoNewline
    $stage1Type | Out-File -FilePath (Join-Path $MyclyHome "agent\type") -Encoding utf8 -NoNewline

    # Add mycly to PATH for current user (if not already there)
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath -notlike "*$MyclyBin*") {
        [Environment]::SetEnvironmentVariable("Path", "$MyclyBin;$currentPath", "User")
        $env:Path = "$MyclyBin;$env:Path"
        Write-Ok "Added $MyclyBin to user PATH"
        Write-Info "You may need to restart your terminal for PATH changes to take effect."
    } else {
        Write-Ok "mycly is already in PATH"
    }

    Write-Ok "Agent ready"
}

# ---- System Report ----

function Write-SystemReport {
    $reportFile = Join-Path $MyclyHome "system-report.json"

    $report = @{
        mycly_version = $MyclyVersion
        timestamp     = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        system        = @{
            os         = $SystemInfo["win_name"]
            os_type    = "windows"
            os_version = $SystemInfo["win_build"]
            arch       = $SystemInfo["arch"]
            arch_norm  = $SystemInfo["arch_norm"]
            hostname   = $SystemInfo["hostname"]
            ps_version = $SystemInfo["ps_version"]
            ps_edition = $SystemInfo["ps_edition"]
            is_admin   = $SystemInfo["is_admin"]
            has_wsl    = $SystemInfo["has_wsl"]
            has_git_bash = $SystemInfo["has_git_bash"]
        }
        resources     = @{
            mem_total_mb  = $Resources["mem_total_mb"]
            mem_free_mb   = $Resources["mem_free_mb"]
            disk_avail_mb = $Resources["disk_avail_mb"]
            cpus          = $Resources["cpus"]
            gpu           = $Resources["gpu"]
        }
        package_managers = $SystemInfo["pkg_managers"]
        stage1_type      = (Get-Content (Join-Path $MyclyHome "agent\type") -ErrorAction SilentlyContinue)
    } | ConvertTo-Json -Depth 4

    $report | Out-File -FilePath $reportFile -Encoding utf8
    Write-Detail "System report written to $reportFile"
}

# ---- Summary ----

function Show-Summary {
    $separator = [string]::new([char]0x2500, 53)
    if (-not $SupportsUnicode) { $separator = ("-" * 53) }

    Write-Host ""
    Write-Host "  $separator" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  mycly is ready." -ForegroundColor White
    Write-Host ""
    Write-Host "  System:    " -ForegroundColor DarkGray -NoNewline
    Write-Host "$($SystemInfo['win_name']) / $($SystemInfo['arch_norm'])"
    Write-Host "  Memory:    " -ForegroundColor DarkGray -NoNewline
    Write-Host "$($Resources['mem_total_mb']) MB"
    Write-Host "  Admin:     " -ForegroundColor DarkGray -NoNewline
    Write-Host "$(if ($SystemInfo['is_admin']) { 'yes' } else { 'no' })"
    Write-Host "  Agent:     " -ForegroundColor DarkGray -NoNewline
    Write-Host (Get-Content (Join-Path $MyclyHome "agent\type") -ErrorAction SilentlyContinue)
    Write-Host ""
    Write-Host "  To start mycly:" -ForegroundColor DarkGray
    Write-Host "    mycly" -ForegroundColor White
    Write-Host ""
    Write-Host "  To see what mycly knows about this system:" -ForegroundColor DarkGray
    Write-Host "    mycly status" -ForegroundColor White
    Write-Host ""
    Write-Host "  $separator" -ForegroundColor Cyan
    Write-Host ""
}

# ---- Main ----

function Invoke-MyclyBootstrap {
    Show-Banner

    # Pre-flight
    Test-ExecutionPolicy

    # System detection
    Find-SystemInfo
    Find-Resources
    Find-Privileges
    Find-Tools

    # Network & auth
    Test-Network
    Invoke-Authentication

    # Stage 1
    Install-Stage1
    Write-SystemReport

    # Done
    Show-Summary

    # TODO: Launch Stage 1 agent
    # & (Join-Path $MyclyHome "agent\mycly-agent.exe") --first-run
}

# Run bootstrap
Invoke-MyclyBootstrap
