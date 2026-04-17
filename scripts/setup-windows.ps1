# ==============================================================
# WordPress Multitenancy Platform  Windows Setup (PowerShell)
# ==============================================================
# Run this script as Administrator:
#   powershell -ExecutionPolicy Bypass -File scripts\setup-windows.ps1
#
# This script will:
#   1. Check/install prerequisites (Docker Desktop, Git, Make)
#   2. Generate .env with random passwords
#   3. Create required directories
#   4. Configure the Windows hosts file
#   5. Start the entire platform
# ==============================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# ---- Colors / Helpers ----
function Write-Step($step, $total, $msg) {
    Write-Host "`n[$step/$total] " -ForegroundColor Yellow -NoNewline
    Write-Host $msg
}
function Write-Ok($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "  [FAIL] $msg" -ForegroundColor Red }

# ---- Resolve project root ----
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectDir = Split-Path -Parent $ScriptDir

Write-Host ""
Write-Host "-" -ForegroundColor Cyan
Write-Host "  WordPress Multitenancy Platform  Windows Setup        " -ForegroundColor Cyan
Write-Host "" -ForegroundColor Cyan

# ==============================================================
# Step 1  Check Prerequisites
# ==============================================================
Write-Step 1 6 "Checking prerequisites..."

$MissingTools = @()

# Check Git
if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Ok "Git found: $(git --version)"
} else {
    Write-Warn "Git not found  will attempt to install"
    $MissingTools += "Git.Git"
}

# Check Docker
if (Get-Command docker -ErrorAction SilentlyContinue) {
    Write-Ok "Docker found: $(docker --version)"
} else {
    Write-Warn "Docker not found  will attempt to install"
    $MissingTools += "Docker.DockerDesktop"
}

# Check Make (optional)
if (Get-Command make -ErrorAction SilentlyContinue) {
    Write-Ok "Make found: $(make --version 2>&1 | Select-Object -First 1)"
} else {
    Write-Warn "Make not found  will attempt to install (optional, for 'make up' shortcut)"
    $MissingTools += "GnuWin32.Make"
}

# ==============================================================
# Step 2  Install Missing Tools via winget
# ==============================================================
if ($MissingTools.Count -gt 0) {
    Write-Step 2 6 "Installing missing tools via winget..."

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Err "winget is not available. Please install the missing tools manually:"
        foreach ($tool in $MissingTools) { Write-Host "    - $tool" -ForegroundColor Red }
        Write-Host "  Get winget: https://aka.ms/getwinget" -ForegroundColor Yellow
        exit 1
    }

    foreach ($tool in $MissingTools) {
        Write-Host "  Installing $tool ..." -ForegroundColor Cyan
        winget install --id $tool -e --accept-package-agreements --accept-source-agreements --silent
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "winget returned exit code $LASTEXITCODE for $tool  it may already be installed or require a reboot."
        } else {
            Write-Ok "$tool installed"
        }
    }

    # Refresh PATH so newly installed tools are visible
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    # After installing Docker Desktop, check if reboot is needed
    if ($MissingTools -contains "Docker.DockerDesktop") {
        Write-Host ""
        Write-Warn "Docker Desktop was just installed."
        Write-Warn "You MUST reboot your machine, then re-run this script."
        Write-Host ""
        $reboot = Read-Host "  Reboot now? (y/n)"
        if ($reboot -eq 'y') { Restart-Computer -Force }
        exit 0
    }
} else {
    Write-Step 2 6 "All prerequisites already installed  skipping."
}

# ==============================================================
# Step 3  Validate Docker is running
# ==============================================================
Write-Step 3 6 "Validating Docker Engine..."

$oldEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$null = docker info 2>$null
$cmdExit = $LASTEXITCODE
$ErrorActionPreference = $oldEap

if ($cmdExit -ne 0) {
    Write-Err "Docker Engine is not running."
    Write-Host "  Please open Docker Desktop and wait for it to fully start (whale icon stops animating)." -ForegroundColor Yellow
    Write-Host "  Then re-run this script." -ForegroundColor Yellow
    exit 1
} else {
    Write-Ok "Docker Engine is running"
}

# Verify Docker Compose V2
$oldEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$composeVer = docker compose version --short 2>$null
$cmdExit = $LASTEXITCODE
$ErrorActionPreference = $oldEap

if ($cmdExit -ne 0) {
    Write-Err "Docker Compose V2 not found. Please update Docker Desktop."
    exit 1
} else {
    Write-Ok "Docker Compose V2 found: v$composeVer"
}

# ==============================================================
# Step 4  Generate .env
# ==============================================================
Write-Step 4 6 "Generating .env file..."

$EnvFile = Join-Path $ProjectDir ".env"
$EnvExample = Join-Path $ProjectDir ".env.example"

function New-RandomPassword {
    -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
}

if (Test-Path $EnvFile) {
    Write-Warn ".env already exists  skipping generation."
    Write-Host "    Delete .env and re-run setup to regenerate." -ForegroundColor Yellow
} else {
    if (-not (Test-Path $EnvExample)) {
        Write-Err ".env.example not found at: $EnvExample"
        exit 1
    }

    $content = Get-Content $EnvExample -Raw
    $content = $content -replace 'alpha_root_change_me', (New-RandomPassword)
    $content = $content -replace 'alpha_db_change_me',   (New-RandomPassword)
    $content = $content -replace 'beta_root_change_me',  (New-RandomPassword)
    $content = $content -replace 'beta_db_change_me',    (New-RandomPassword)
    $content = $content -replace 'grafana_change_me',    (New-RandomPassword)
    # Write with UTF-8 no BOM to avoid Docker issues
    [System.IO.File]::WriteAllText($EnvFile, $content, [System.Text.UTF8Encoding]::new($false))

    Write-Ok ".env generated with random passwords"
    Write-Warn "IMPORTANT: Never commit .env to git!"
}

# ==============================================================
# Step 5  Create directories & configure hosts
# ==============================================================
Write-Step 5 6 "Creating directories & configuring hosts file..."

# Directories
New-Item -ItemType Directory -Force -Path (Join-Path $ProjectDir "backups") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $ProjectDir "nginx\ssl") | Out-Null
Write-Ok "Directories created (backups/, nginx/ssl/)"

# Hosts file
$HostsPath = "C:\Windows\System32\drivers\etc\hosts"
$HostEntries = @(
    "127.0.0.1  tenant-alpha.localhost",
    "127.0.0.1  tenant-beta.localhost"
)

$hostsContent = Get-Content $HostsPath -Raw -ErrorAction SilentlyContinue
$hostsChanged = $false

foreach ($entry in $HostEntries) {
    if ($hostsContent -and $hostsContent.Contains($entry)) {
        Write-Ok "Hosts entry already exists: $entry"
    } else {
        Add-Content -Path $HostsPath -Value $entry -Encoding ASCII
        Write-Ok "Added to hosts: $entry"
        $hostsChanged = $true
    }
}

if ($hostsChanged) {
    # Flush DNS so entries take effect immediately
    ipconfig /flushdns | Out-Null
    Write-Ok "DNS cache flushed"
}

# ==============================================================
# Step 6  Start the platform
# ==============================================================
Write-Step 6 6 "Starting the platform..."

Push-Location $ProjectDir
try {
    Write-Host "  Running: docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d" -ForegroundColor Cyan
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d
    $cmdExit = $LASTEXITCODE
    $ErrorActionPreference = $oldEap

    if ($cmdExit -ne 0) {
        Write-Err "docker compose up failed with exit code $cmdExit"
        Write-Host "  Run 'docker compose -f docker-compose.yml -f docker-compose.monitoring.yml logs' to see errors." -ForegroundColor Yellow
        exit 1
    }
} finally {
    Pop-Location
}

# ==============================================================
# Done!
# ==============================================================
Write-Host ""
Write-Host "-" -ForegroundColor Green
Write-Host "  [OK] Setup complete! Platform is starting...            " -ForegroundColor Green
Write-Host "                                                        " -ForegroundColor Green
Write-Host "  Services:                                             " -ForegroundColor Green
Write-Host "    Tenant Alpha:   http://tenant-alpha.localhost       " -ForegroundColor Green
Write-Host "    Tenant Beta:    http://tenant-beta.localhost        " -ForegroundColor Green
Write-Host "    Grafana:        http://localhost:3000               " -ForegroundColor Green
Write-Host "    Prometheus:     http://localhost:9090               " -ForegroundColor Green
Write-Host "                                                        " -ForegroundColor Green
Write-Host "  Commands:                                             " -ForegroundColor Green
Write-Host "    Status:  docker compose -f docker-compose.yml `     " -ForegroundColor Green
Write-Host "             -f docker-compose.monitoring.yml ps        " -ForegroundColor Green
Write-Host "    Logs:    docker compose -f docker-compose.yml `     " -ForegroundColor Green
Write-Host "             -f docker-compose.monitoring.yml logs -f   " -ForegroundColor Green
Write-Host "    Stop:    docker compose -f docker-compose.yml `     " -ForegroundColor Green
Write-Host "             -f docker-compose.monitoring.yml down      " -ForegroundColor Green
Write-Host "" -ForegroundColor Green
Write-Host ""

# Show port conflict tip
$port80InUse = Get-NetTCPConnection -LocalPort 80 -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.OwningProcess -ne (Get-Process -Name "com.docker*" -ErrorAction SilentlyContinue).Id }
if ($port80InUse) {
    Write-Warn "Port 80 may be in use by another process."
    Write-Host "  If sites don't load, edit .env and set NGINX_HTTP_PORT=8080" -ForegroundColor Yellow
    Write-Host "  Then visit: http://tenant-alpha.localhost:8080" -ForegroundColor Yellow
}
