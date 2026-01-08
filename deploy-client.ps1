#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Alta Relay Client Deployment Script for Windows

.DESCRIPTION
    Downloads and installs alta-client as a Windows service using NSSM.

.PARAMETER Server
    Relay server address (required). Example: 146.190.68.219:5000

.PARAMETER Session
    Session ID (required). Example: 12345678

.PARAMETER Version
    Version to install (default: latest)

.PARAMETER InstallDir
    Installation directory (default: C:\alta-proxy)

.PARAMETER Uninstall
    Remove alta-client service and files

.EXAMPLE
    .\deploy-client.ps1 -Server 146.190.68.219:5000 -Session 12345678

.EXAMPLE
    .\deploy-client.ps1 -Uninstall
#>

param(
    [string]$Server,
    [string]$Session,
    [string]$Version = "latest",
    [string]$InstallDir = "C:\alta-proxy",
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

$ServiceName = "alta-client"
$BinaryName = "alta-client.exe"
$GitHubRepo = "nmelo/drone-control"
$NssmUrl = "https://nssm.cc/release/nssm-2.24.zip"

function Write-Log {
    param([string]$Message, [string]$Color = "Green")
    Write-Host "[+] $Message" -ForegroundColor $Color
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "[x] $Message" -ForegroundColor Red
    exit 1
}

function Get-LatestVersion {
    if ($Version -eq "latest") {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$GitHubRepo/releases/latest"
        return $release.tag_name
    }
    return $Version
}

function Install-NSSM {
    $nssmPath = "$InstallDir\nssm.exe"

    if (Test-Path $nssmPath) {
        Write-Log "NSSM already installed"
        return $nssmPath
    }

    Write-Log "Installing NSSM..."
    $zipPath = "$env:TEMP\nssm.zip"
    $extractPath = "$env:TEMP\nssm"

    Invoke-WebRequest -Uri $NssmUrl -OutFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

    $nssmExe = Get-ChildItem -Path $extractPath -Recurse -Filter "nssm.exe" |
               Where-Object { $_.Directory.Name -eq "win64" } |
               Select-Object -First 1

    Copy-Item -Path $nssmExe.FullName -Destination $nssmPath
    Remove-Item -Path $zipPath -Force
    Remove-Item -Path $extractPath -Recurse -Force

    Write-Log "NSSM installed to $nssmPath"
    return $nssmPath
}

function Add-DefenderExclusion {
    Write-Log "Adding Windows Defender exclusion..."
    try {
        Add-MpPreference -ExclusionPath $InstallDir -ErrorAction SilentlyContinue
        Write-Log "Defender exclusion added for $InstallDir"
    }
    catch {
        Write-Warn "Could not add Defender exclusion (may require additional permissions)"
    }
}

function Stop-ExistingService {
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        Write-Log "Stopping existing service..."
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

function Download-Binary {
    param([string]$Ver)

    $url = "https://github.com/$GitHubRepo/releases/download/$Ver/alta-client-windows-amd64.exe"
    $destPath = "$InstallDir\$BinaryName"

    Write-Log "Downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $destPath
    Write-Log "Downloaded to $destPath"
}

function Install-Service {
    param([string]$NssmPath)

    $binaryPath = "$InstallDir\$BinaryName"
    $arguments = "-server $Server -session $Session"

    # Check if service exists
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

    if ($service) {
        Write-Log "Updating existing service..."
        & $NssmPath set $ServiceName Application $binaryPath
        & $NssmPath set $ServiceName AppParameters $arguments
    }
    else {
        Write-Log "Creating service..."
        & $NssmPath install $ServiceName $binaryPath $arguments
    }

    # Configure service
    & $NssmPath set $ServiceName AppDirectory $InstallDir
    & $NssmPath set $ServiceName DisplayName "Alta Relay Client"
    & $NssmPath set $ServiceName Description "Connects operator GCS to Alta Relay server"
    & $NssmPath set $ServiceName Start SERVICE_AUTO_START
    & $NssmPath set $ServiceName AppStdout "$InstallDir\alta-client.log"
    & $NssmPath set $ServiceName AppStderr "$InstallDir\alta-client.log"
    & $NssmPath set $ServiceName AppRotateFiles 1
    & $NssmPath set $ServiceName AppRotateBytes 10485760

    Write-Log "Service configured"
}

function Start-ClientService {
    Write-Log "Starting service..."
    Start-Service -Name $ServiceName
    Start-Sleep -Seconds 2

    $service = Get-Service -Name $ServiceName
    if ($service.Status -eq "Running") {
        Write-Log "Service started successfully"
    }
    else {
        Write-Err "Service failed to start. Check logs at $InstallDir\alta-client.log"
    }
}

function Show-Status {
    param([string]$Ver)

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Alta Relay Client Deployed" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Version:    $Ver"
    Write-Host "  Server:     $Server"
    Write-Host "  Session:    $Session"
    Write-Host "  Install:    $InstallDir"
    Write-Host "  Logs:       $InstallDir\alta-client.log"
    Write-Host ""
    Write-Host "  Commands:"
    Write-Host "    Status:   Get-Service $ServiceName"
    Write-Host "    Logs:     Get-Content $InstallDir\alta-client.log -Tail 50"
    Write-Host "    Restart:  Restart-Service $ServiceName"
    Write-Host "    Stop:     Stop-Service $ServiceName"
    Write-Host ""
}

function Uninstall-Client {
    Write-Log "Uninstalling Alta Client..."

    # Stop and remove service
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        $nssmPath = "$InstallDir\nssm.exe"
        if (Test-Path $nssmPath) {
            & $nssmPath remove $ServiceName confirm
        }
        else {
            sc.exe delete $ServiceName
        }
        Write-Log "Service removed"
    }

    # Remove files
    if (Test-Path $InstallDir) {
        Remove-Item -Path $InstallDir -Recurse -Force
        Write-Log "Files removed from $InstallDir"
    }

    # Remove Defender exclusion
    try {
        Remove-MpPreference -ExclusionPath $InstallDir -ErrorAction SilentlyContinue
    }
    catch { }

    Write-Log "Uninstall complete"
    exit 0
}

# Main
Write-Host ""
Write-Host "Alta Relay Client Deployment" -ForegroundColor Cyan
Write-Host "============================" -ForegroundColor Cyan
Write-Host ""

if ($Uninstall) {
    Uninstall-Client
}

# Validate required parameters
if (-not $Server) {
    Write-Err "Missing required parameter: -Server"
}
if (-not $Session) {
    Write-Err "Missing required parameter: -Session"
}

# Create install directory
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Write-Log "Created $InstallDir"
}

$ver = Get-LatestVersion
Write-Log "Version: $ver"

Stop-ExistingService
Add-DefenderExclusion
Download-Binary -Ver $ver
$nssmPath = Install-NSSM
Install-Service -NssmPath $nssmPath
Start-ClientService
Show-Status -Ver $ver
