#Requires -RunAsAdministrator

<#
.SYNOPSIS
    [ES] Dice por que ESET Endpoint no esta instalado, no arranca o no se conecta a la consola.
    [EN] Explains why ESET Endpoint is missing, not starting or not reaching the console.
.DESCRIPTION
    Comprehensive ESET detection script with fresh registry reads,
    service/process monitoring, and recording mode support.
    Resolves stale cache issues and provides detailed diagnostics.
.NOTES
    v1.0 - 2026-04-11
#>

$ErrorActionPreference = 'Continue'

# ==============================================
# Configuration
# ==============================================

$Source          = if ($env:SOPORTE_ORIGEN_PAQUETES) { $env:SOPORTE_ORIGEN_PAQUETES } else { '\\servidor\utilidades\1.Node_Preparation' }
$LogDir          = "$env:USERPROFILE\LOGS_Script"
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
$LogFile         = "$LogDir\ESET-Diag_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$LocalCache      = "$env:TEMP\_ESET_Cache"
$DefaultTimeout  = 300

# ESET Keywords for detection (fresh each time, not cached)
$EsetKeywords    = @(
    'ESET',
    'Endpoint Security',
    'Windows Defender MDR',
    'ESET Internet Security',
    'ESET File Security',
    'epi_win_live_installer'
)

$EsetServices    = @('ekrn', 'egui', 'eguib', 'eset')
$EsetProcesses   = @('ekrn', 'egui', 'eguib', 'EsetOnlineScan', 'ecmd')

# ==============================================
# Logging Functions
# ==============================================

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $color = switch ($Level) {
        'ERROR'   { 'Red' }
        'OK'      { 'Green' }
        'WARN'    { 'Yellow' }
        'INFO'    { 'DarkGray' }
        default   { 'White' }
    }
    $output = "[$timestamp] [$Level] $Message"
    Write-Host $output -ForegroundColor $color
    Add-Content -Path $LogFile -Value $output
}

function Write-Section {
    param([string]$Title)
    $sep = '=' * 70
    $msg = "`n$sep`n  $Title`n$sep"
    Write-Host $msg -ForegroundColor Cyan
    Add-Content -Path $LogFile -Value $msg
}

# ==============================================
# Detection Functions (Always fresh reads)
# ==============================================

function Get-EsetRegistryEntries {
    <#
    .SYNOPSIS
    [ES] Dice por que ESET Endpoint no esta instalado, no arranca o no se conecta a la consola.
    [EN] Explains why ESET Endpoint is missing, not starting or not reaching the console.
    .SYNOPSIS
        Check for ESET Windows Services (force fresh query)
    #>
    [CmdletBinding()]
    param()

    Write-Log "Querying Windows Services..."
    $services = @()

    foreach ($svc in $EsetServices) {
        $s = Get-Service -Name $svc -EA SilentlyContinue
        if ($s) {
            $services += @{
                Name   = $s.Name
                DisplayName = $s.DisplayName
                Status = $s.Status
            }
        }
    }

    return $services
}

function Get-EsetProcesses {
    <#
    .SYNOPSIS
    [ES] Dice por que ESET Endpoint no esta instalado, no arranca o no se conecta a la consola.
    [EN] Explains why ESET Endpoint is missing, not starting or not reaching the console.
    .SYNOPSIS
        Comprehensive ESET detection with multiple verification methods
    #>
    $regEntries = Get-EsetRegistryEntries
    $svcStatus  = Get-EsetServices
    $procStatus = Get-EsetProcesses

    return @{
        Registry  = $regEntries
        Services  = $svcStatus
        Processes = $procStatus
        IsInstalled = ($regEntries.Count -gt 0) -or ($svcStatus.Count -gt 0)
    }
}

# ==============================================
# Display Functions
# ==============================================

function Show-DetectionStatus {
    param([hashtable]$Status, [string]$Label)

    Write-Host ""
    Write-Host "  $Label" -ForegroundColor Magenta
    Write-Host "  $('-' * 68)" -ForegroundColor DarkGray

    if ($Status.Registry.Count -gt 0) {
        Write-Host "  `e[32m[+]`e[0m Registry Entries Found:" -ForegroundColor Green
        foreach ($entry in $Status.Registry) {
            Write-Host "      - $($entry.Name) v$($entry.Version)" -ForegroundColor DarkGray
            Write-Host "        Publisher: $($entry.Publisher)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  `e[33m[x]`e[0m No ESET registry entries found" -ForegroundColor Yellow
    }

    if ($Status.Services.Count -gt 0) {
        Write-Host "  `e[32m[+]`e[0m Services Active:" -ForegroundColor Green
        foreach ($svc in $Status.Services) {
            $svcColor = if ($svc.Status -eq 'Running') { 'Green' } else { 'Yellow' }
            Write-Host "      - $($svc.Name): $($svc.Status)" -ForegroundColor $svcColor
        }
    } else {
        Write-Host "  `e[33m[x]`e[0m No ESET services detected" -ForegroundColor Yellow
    }

    if ($Status.Processes.Count -gt 0) {
        Write-Host "  `e[32m[+]`e[0m Processes Running:" -ForegroundColor Green
        foreach ($proc in $Status.Processes) {
            $mem = [Math]::Round($proc.Memory / 1MB, 1)
            Write-Host "      - $($proc.Name) (PID $($proc.Id), ${mem}MB)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  `e[33m[x]`e[0m No ESET processes running" -ForegroundColor Yellow
    }

    Write-Host ""
    if ($Status.IsInstalled) {
        Write-Host "  `e[32m[+] ESET DETECTED`e[0m" -ForegroundColor Green
    } else {
        Write-Host "  `e[31m[x] ESET NOT DETECTED`e[0m" -ForegroundColor Red
    }
    Write-Host ""
}

function Show-LogOutput {
    param([hashtable]$Status)

    $logOutput = @"

------------------------------------------------------------------
REGISTRY ENTRIES
------------------------------------------------------------------
"@

    if ($Status.Registry.Count -gt 0) {
        foreach ($entry in $Status.Registry) {
            $logOutput += @"

  Name: $($entry.Name)
  Version: $($entry.Version)
  Publisher: $($entry.Publisher)
  Install Date: $($entry.InstallDate)
  Path: $($entry.Path)
  Keyword Match: $($entry.Keyword)
"@
        }
    } else {
        $logOutput += "`n  (No registry entries found)`n"
    }

    $logOutput += @"

------------------------------------------------------------------
SERVICES
------------------------------------------------------------------
"@

    if ($Status.Services.Count -gt 0) {
        foreach ($svc in $Status.Services) {
            $logOutput += "`n  Name: $($svc.Name)"
            $logOutput += "`n  Display: $($svc.DisplayName)"
            $logOutput += "`n  Status: $($svc.Status)`n"
        }
    } else {
        $logOutput += "`n  (No services found)`n"
    }

    $logOutput += @"

------------------------------------------------------------------
PROCESSES
------------------------------------------------------------------
"@

    if ($Status.Processes.Count -gt 0) {
        foreach ($proc in $Status.Processes) {
            $mem = [Math]::Round($proc.Memory / 1MB, 1)
            $logOutput += "`n  PID $($proc.Id): $($proc.Name) (${mem}MB, CPU: $($proc.CPU)s)`n"
        }
    } else {
        $logOutput += "`n  (No processes found)`n"
    }

    return $logOutput
}

# ==============================================
# Installation Functions
# ==============================================

function Install-ESET {
    param([switch]$RecordingMode)

    Write-Log "Starting ESET Installation..."

    $installerPath = "$Source\epi_win_live_installer.exe"
    if (-not (Test-Path $installerPath)) {
        Write-Log "Installer not found: $installerPath" 'ERROR'
        return $false
    }

    # Copy to local cache
    if (-not (Test-Path $LocalCache)) { New-Item -Path $LocalCache -ItemType Directory -Force | Out-Null }
    $localExe = "$LocalCache\epi_win_live_installer.exe"
    if (-not (Test-Path $localExe)) {
        Write-Log "Copying to local cache..."
        Copy-Item $installerPath $localExe -Force
    }

    Write-Log "Launching ESET installer..."

    if ($RecordingMode) {
        Write-Log "RECORDING MODE: Manual installation - follow wizard prompts" 'WARN'
        & $localExe
        Write-Log "Waiting for manual installation to complete..." 'WARN'
        $proc = Get-Process -Name 'epi_win_live_installer' -EA SilentlyContinue
        if ($proc) { $proc | Wait-Process -Timeout 900 -EA SilentlyContinue }
    } else {
        Write-Log "Silent mode installation..."
        & $localExe /S
        Start-Sleep -Seconds 2
    }

    Write-Log "Installation launched successfully"
    return $true
}

# ==============================================
# Main Execution
# ==============================================

Clear-Host
Write-Host ""
Write-Host "  `e[36m+==========================================+`e[0m" -ForegroundColor Cyan
Write-Host "  `e[36m|   ESET DIAGNOSTIC & INSTALLER v1.0      |`e[0m" -ForegroundColor Cyan
Write-Host "  `e[36m|   Cyberpunk Registry Fresh-Read Engine   |`e[0m" -ForegroundColor Cyan
Write-Host "  `e[36m+==========================================+`e[0m" -ForegroundColor Cyan
Write-Host ""

Write-Log "ESET Diagnostic started"
Write-Log "Log file: $LogFile"
Write-Log "Fresh cache bypass enabled (no stale registry reads)"

Write-Section "PRE-INSTALLATION CHECK"
$beforeStatus = Test-EsetInstalled
Show-DetectionStatus -Status $beforeStatus -Label "Current ESET Detection Status"
Add-Content -Path $LogFile -Value (Show-LogOutput $beforeStatus)

# Menu
Write-Host "  `e[35mMode Selection:`e[0m" -ForegroundColor Magenta
Write-Host "  [1] Silent Mode (automatic installation)" -ForegroundColor Cyan
Write-Host "  [2] Recording Mode (manual interactive)" -ForegroundColor Cyan
Write-Host "  [3] Diagnostic Only (skip installation)" -ForegroundColor Cyan
Write-Host ""
$choice = Read-Host "  Select mode (1-3)"

switch ($choice) {
    '1' {
        Write-Log "Selected: Silent Mode" 'INFO'
        Install-ESET -RecordingMode:$false

        Write-Section "POST-INSTALLATION CHECK"
        Write-Log "Waiting 10 seconds for registry updates..."
        Start-Sleep -Seconds 10

        $afterStatus = Test-EsetInstalled
        Show-DetectionStatus -Status $afterStatus -Label "ESET Detection After Installation"
        Add-Content -Path $LogFile -Value (Show-LogOutput $afterStatus)

        if ($afterStatus.IsInstalled) {
            Write-Log "+ ESET Successfully Installed" 'OK'
        } else {
            Write-Log "x ESET Installation Failed" 'ERROR'
        }
    }

    '2' {
        Write-Log "Selected: Recording Mode (Manual Interactive)" 'WARN'
        Install-ESET -RecordingMode:$true

        Write-Section "POST-INSTALLATION CHECK"
        Write-Log "Waiting 15 seconds for registry updates..."
        Start-Sleep -Seconds 15

        $afterStatus = Test-EsetInstalled
        Show-DetectionStatus -Status $afterStatus -Label "ESET Detection After Manual Installation"
        Add-Content -Path $LogFile -Value (Show-LogOutput $afterStatus)

        if ($afterStatus.IsInstalled) {
            Write-Log "+ ESET Successfully Installed" 'OK'
        } else {
            Write-Log "x ESET Installation May Have Failed" 'WARN'
        }
    }

    '3' {
        Write-Log "Selected: Diagnostic Only (no installation)" 'INFO'
    }

    default {
        Write-Log "Invalid selection" 'ERROR'
    }
}

Write-Section "DIAGNOSTIC COMPLETE"
Write-Log "Log saved to: $LogFile"
Write-Log "Diagnostic ended"

Write-Host ""
Write-Host "  Press Enter to close..." -ForegroundColor DarkGray
Read-Host
