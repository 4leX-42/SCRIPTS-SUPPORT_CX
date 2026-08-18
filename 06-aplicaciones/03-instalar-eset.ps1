#Requires -RunAsAdministrator

<#
.SYNOPSIS
    [ES] Instala ESET Endpoint sin asistencia, incluso cuando el instalador no admite modo silencioso.
    [EN] Installs ESET Endpoint unattended, even when the installer has no silent mode.
.DESCRIPTION
    - Deteccion precisa: busca "ESET Endpoint" (NO matchea "ESET Management Agent")
    - Modo Recording: lanza el instalador y espera a que termines manualmente
    - Diagnostico completo: pre/post install con registro, servicios y procesos
    - Log detallado en LOGS_Script
.PARAMETER Modo
    'Diagnostico' = Solo muestra estado actual (no instala)
    'Instalar'    = Recording mode: lanza instalador, espera interaccion manual
    'Silent'      = Intenta --silent --accepteula (puede no funcionar)
.EXAMPLE
    .\ESET-Deploy.ps1 -Modo Instalar
    .\ESET-Deploy.ps1 -Modo Diagnostico
#>
param(
    [ValidateSet('Diagnostico','Instalar','Silent')]
    [string]$Modo = 'Instalar'
)

$ErrorActionPreference = 'Continue'
$Source  = if ($env:SOPORTE_ORIGEN_PAQUETES) { $env:SOPORTE_ORIGEN_PAQUETES } else { '\\servidor\utilidades\1.Node_Preparation' }
$LogDir  = "$env:USERPROFILE\LOGS_Script"
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
$LogFile = "$LogDir\ESET_Deploy_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# ==============================================
# FUNCIONES
# ==============================================

function Write-Log {
    param([string]$Msg, [string]$Level = 'INFO')
    $entry = "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Msg"
    switch ($Level) {
        'ERROR' { Write-Host $entry -ForegroundColor Red }
        'WARN'  { Write-Host $entry -ForegroundColor Yellow }
        'OK'    { Write-Host $entry -ForegroundColor Green }
        default { Write-Host $entry }
    }
    Add-Content -Path $LogFile -Value $entry
}

function Get-ESETStatus {
    <#
    .SYNOPSIS  Diagnostico completo de ESET - registro, servicios, procesos
               Detecta SOLO "ESET Endpoint" (no confunde con Management Agent)
    #>
    param([string]$Label = 'CHECK')

    Write-Host ""
    Write-Host "  +====================================================+" -ForegroundColor Cyan
    Write-Host "  |  $Label" -ForegroundColor Cyan -NoNewline
    Write-Host (' ' * (50 - $Label.Length)) -NoNewline
    Write-Host "|" -ForegroundColor Cyan
    Write-Host "  +====================================================+" -ForegroundColor Cyan
    Write-Log ""
    Write-Log "== $Label =="

    # -- Registro: lectura FRESCA (sin cache) --
    Write-Log "  Leyendo registro (sin cache)..."
    $allApps = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    ) | ForEach-Object {
        Get-ItemProperty $_ -EA SilentlyContinue
    } | Where-Object { $_.DisplayName }

    # Buscar CUALQUIER entrada ESET para diagnostico
    $allEset = $allApps | Where-Object { $_.DisplayName -like '*ESET*' }
    # Buscar SOLO ESET Endpoint (la que nos importa)
    $endpointOnly = $allApps | Where-Object {
        $_.DisplayName -like '*ESET Endpoint*'
    }

    Write-Host ""
    Write-Host "  -- Registro (todas las entradas ESET) --" -ForegroundColor DarkGray
    Write-Log "  --- Registro: Todas las entradas ESET ---"

    if ($allEset) {
        foreach ($app in $allEset) {
            $isEndpoint = $app.DisplayName -like '*ESET Endpoint*'
            $marker = if ($isEndpoint) { ' ** ENDPOINT **' } else { ' (otro producto)' }
            $color  = if ($isEndpoint) { 'Green' } else { 'DarkGray' }

            Write-Host "    $($app.DisplayName)$marker" -ForegroundColor $color
            Write-Host "      Version: $($app.DisplayVersion)  |  Instalado: $($app.InstallDate)" -ForegroundColor DarkGray
            Write-Log "    $($app.DisplayName)$marker"
            Write-Log "      Version: $($app.DisplayVersion), InstallDate: $($app.InstallDate), Publisher: $($app.Publisher)"
        }
    } else {
        Write-Host "    (ninguna entrada ESET en registro)" -ForegroundColor Yellow
        Write-Log "    (ninguna entrada ESET en registro)"
    }

    # -- Servicios --
    Write-Host ""
    Write-Host "  -- Servicios ESET --" -ForegroundColor DarkGray
    Write-Log "  --- Servicios ---"

    $services = Get-Service | Where-Object {
        $_.DisplayName -match 'ESET|ekrn|esets' -or $_.Name -match 'ekrn|esets'
    }

    if ($services) {
        foreach ($svc in $services) {
            $statusColor = switch ($svc.Status) {
                'Running' { 'Green' }
                'Stopped' { 'Red' }
                default   { 'Yellow' }
            }
            Write-Host "    $($svc.Name) ($($svc.DisplayName))" -NoNewline
            Write-Host " -> $($svc.Status)" -ForegroundColor $statusColor
            Write-Log "    $($svc.Name) ($($svc.DisplayName)) -> $($svc.Status)"
        }
    } else {
        Write-Host "    (ningun servicio ESET activo)" -ForegroundColor Yellow
        Write-Log "    (ningun servicio ESET activo)"
    }

    # -- Procesos --
    Write-Host ""
    Write-Host "  -- Procesos ESET --" -ForegroundColor DarkGray
    Write-Log "  --- Procesos ---"

    $procs = Get-Process | Where-Object {
        $_.Name -match 'ekrn|egui|eset|esets|epi_win'
    }

    if ($procs) {
        foreach ($p in $procs) {
            $mem = [math]::Round($p.WorkingSet64 / 1MB, 1)
            Write-Host "    PID $($p.Id): $($p.Name) (${mem}MB)" -ForegroundColor DarkGray
            Write-Log "    PID $($p.Id): $($p.Name) (${mem}MB, Path: $($p.Path))"
        }
    } else {
        Write-Host "    (ningun proceso ESET corriendo)" -ForegroundColor Yellow
        Write-Log "    (ningun proceso ESET corriendo)"
    }

    # -- Ficheros en disco --
    Write-Host ""
    Write-Host "  -- Ficheros en disco --" -ForegroundColor DarkGray
    Write-Log "  --- Ficheros en disco ---"

    $esetPaths = @(
        "$env:ProgramFiles\ESET",
        "${env:ProgramFiles(x86)}\ESET",
        "$env:ProgramData\ESET"
    )
    foreach ($p in $esetPaths) {
        if (Test-Path $p) {
            $size = (Get-ChildItem $p -Recurse -EA SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $sizeMB = [math]::Round($size / 1MB, 1)
            Write-Host "    $p (${sizeMB}MB)" -ForegroundColor Green
            Write-Log "    EXISTE: $p (${sizeMB}MB)"
        } else {
            Write-Host "    $p (no existe)" -ForegroundColor DarkGray
            Write-Log "    NO EXISTE: $p"
        }
    }

    # -- Resultado --
    Write-Host ""
    $result = @{
        EndpointInstalled = ($endpointOnly.Count -gt 0)
        ServiceRunning    = ($services | Where-Object { $_.Status -eq 'Running' }).Count -gt 0
        AnyEset           = ($allEset.Count -gt 0)
        EndpointEntries   = $endpointOnly
    }

    if ($result.EndpointInstalled) {
        Write-Host "  RESULTADO: ESET Endpoint INSTALADO" -ForegroundColor Green
        Write-Log "  RESULTADO: ESET Endpoint INSTALADO"
        if ($result.ServiceRunning) {
            Write-Host "  Servicio ekrn: ACTIVO" -ForegroundColor Green
            Write-Log "  Servicio ekrn: ACTIVO"
        }
    } elseif ($result.AnyEset) {
        Write-Host "  RESULTADO: Hay productos ESET pero NO es Endpoint" -ForegroundColor Yellow
        Write-Host "  (ESET Management Agent u otro - NO cuenta como Endpoint instalado)" -ForegroundColor Yellow
        Write-Log "  RESULTADO: ESET presente pero NO Endpoint"
    } else {
        Write-Host "  RESULTADO: ESET Endpoint NO INSTALADO" -ForegroundColor Red
        Write-Log "  RESULTADO: ESET Endpoint NO INSTALADO"
    }

    return $result
}

# ==============================================
# EJECUCION
# ==============================================

Write-Host ""
Write-Host "  +====================================================+" -ForegroundColor Magenta
Write-Host "  |        ESET ENDPOINT - DEPLOY & DIAGNOSTIC        |" -ForegroundColor Magenta
Write-Host "  |            Modo: $Modo" -ForegroundColor Magenta -NoNewline
Write-Host (' ' * (30 - $Modo.Length)) -NoNewline
Write-Host "|" -ForegroundColor Magenta
Write-Host "  +====================================================+" -ForegroundColor Magenta
Write-Host ""
Write-Log "ESET Deploy iniciado - Modo: $Modo"
Write-Log "Log: $LogFile"

# -- Pre-check --
$preCheck = Get-ESETStatus -Label "PRE-INSTALACION"

if ($Modo -eq 'Diagnostico') {
    Write-Log "  Modo diagnostico - fin"
    Write-Host ""
    Write-Host "  Log: $LogFile" -ForegroundColor DarkGray
    Write-Host "  Presiona Enter para cerrar..." -ForegroundColor Cyan
    Read-Host
    exit 0
}

# -- Verificar si ya esta instalado --
if ($preCheck.EndpointInstalled -and $preCheck.ServiceRunning) {
    Write-Host ""
    Write-Host "  ESET Endpoint ya esta instalado y activo. No se requiere accion." -ForegroundColor Green
    Write-Log "  ESET Endpoint ya instalado y activo - saltando"
    Write-Host ""
    Write-Host "  Log: $LogFile" -ForegroundColor DarkGray
    Write-Host "  Presiona Enter para cerrar..." -ForegroundColor Cyan
    Read-Host
    exit 0
}

# -- Localizar instalador --
$esetExe = "$Source\epi_win_live_installer.exe"
if (-not (Test-Path $esetExe)) {
    Write-Log "  Archivo no encontrado: $esetExe" 'ERROR'
    Write-Host "  Presiona Enter para cerrar..." -ForegroundColor Cyan
    Read-Host
    exit 1
}

# -- Instalar --
Write-Host ""
Write-Host "  -- INSTALACION --" -ForegroundColor Magenta

switch ($Modo) {
    'Silent' {
        Write-Log "  Intentando instalacion silenciosa: --silent --accepteula"
        Write-Host "  Lanzando: --silent --accepteula (timeout 600s)" -ForegroundColor DarkGray

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName               = $esetExe
        $psi.Arguments              = '--silent --accepteula'
        $psi.UseShellExecute        = $false
        $psi.CreateNoWindow         = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi

        try { [void]$proc.Start() } catch {
            Write-Log "  Error al lanzar: $_" 'ERROR'
            Write-Host "  Presiona Enter para cerrar..." -ForegroundColor Cyan
            Read-Host
            exit 1
        }

        Write-Log "  PID: $($proc.Id)"
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()

        # Esperar con spinner
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $spinChars = @('/', '-', '\', '|')
        $spinIdx = 0

        while (-not $proc.HasExited -and $sw.Elapsed.TotalSeconds -lt 600) {
            $spin = $spinChars[$spinIdx % 4]
            $spinIdx++
            $elapsed = [int]$sw.Elapsed.TotalSeconds
            Write-Host "`r  [$spin] Instalando... ${elapsed}s" -ForegroundColor DarkGray -NoNewline
            Start-Sleep -Seconds 2
        }
        Write-Host "`r  " + (' ' * 50)

        if (-not $proc.HasExited) {
            Write-Log "  TIMEOUT 600s" 'WARN'
            try { $proc.Kill() } catch {}
        }
        $proc.WaitForExit()
        $code = $proc.ExitCode
        Write-Log "  Exit code: $code"

        try {
            $stderr = $stderrTask.Result
            if ($stderr -and $stderr.Trim()) {
                Write-Log "  STDERR: $($stderr.Trim().Substring(0, [Math]::Min(500, $stderr.Trim().Length)))" 'WARN'
            }
            $stdout = $stdoutTask.Result
            if ($stdout -and $stdout.Trim()) {
                Write-Log "  STDOUT: $($stdout.Trim().Substring(0, [Math]::Min(500, $stdout.Trim().Length)))"
            }
        } catch {}

        $proc.Dispose()
    }

    'Instalar' {
        Write-Host ""
        Write-Host "  +====================================================+" -ForegroundColor Yellow
        Write-Host "  |  MODO RECORDING (Instalacion Manual)              |" -ForegroundColor Yellow
        Write-Host "  |                                                    |" -ForegroundColor Yellow
        Write-Host "  |  Se abrira el instalador de ESET.                 |" -ForegroundColor Yellow
        Write-Host "  |  Completa la instalacion manualmente siguiendo    |" -ForegroundColor Yellow
        Write-Host "  |  el wizard.                                       |" -ForegroundColor Yellow
        Write-Host "  |                                                    |" -ForegroundColor Yellow
        Write-Host "  |  El script esperara a que termines y verificara   |" -ForegroundColor Yellow
        Write-Host "  |  que ESET Endpoint quede instalado correctamente. |" -ForegroundColor Yellow
        Write-Host "  +====================================================+" -ForegroundColor Yellow
        Write-Host ""

        Write-Log "  Modo Recording: instalacion manual"

        $proc = Start-Process -FilePath $esetExe -PassThru
        Write-Log "  Installer lanzado PID=$($proc.Id)"

        # Esperar a que el proceso termine (el usuario interactua)
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $spinChars = @('/', '-', '\', '|')
        $spinIdx = 0

        while (-not $proc.HasExited) {
            $spin = $spinChars[$spinIdx % 4]
            $spinIdx++
            $elapsed = [int]$sw.Elapsed.TotalSeconds
            $min = [int]($elapsed / 60)
            $sec = $elapsed % 60
            Write-Host "`r  [$spin] Esperando instalacion manual... ${min}m ${sec}s" -ForegroundColor Yellow -NoNewline
            Start-Sleep -Seconds 1
        }
        Write-Host "`r  Instalador cerrado. (code=$($proc.ExitCode))                    "
        Write-Log "  Instalador cerrado (code=$($proc.ExitCode), ${elapsed}s)"

        # Esperar a procesos hijos de ESET
        Write-Host "  Esperando servicios ESET..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 10

        # ESET a veces lanza procesos en background despues del installer
        $swPost = [Diagnostics.Stopwatch]::StartNew()
        while ($swPost.Elapsed.TotalSeconds -lt 60) {
            $esetProcs = Get-Process | Where-Object { $_.Name -match 'epi_win|eset.*install' }
            if (-not $esetProcs) { break }
            Start-Sleep -Seconds 3
        }
    }
}

# -- Post-check --
Write-Host ""
Write-Host "  Esperando 15s para que el registro se actualice..." -ForegroundColor DarkGray
Start-Sleep -Seconds 15

$postCheck = Get-ESETStatus -Label "POST-INSTALACION"

# -- Resultado final --
Write-Host ""
Write-Host "  +====================================================+" -ForegroundColor Cyan
Write-Host "  |  RESULTADO FINAL                                  |" -ForegroundColor Cyan
Write-Host "  +====================================================+" -ForegroundColor Cyan

if ($postCheck.EndpointInstalled) {
    $ver = ($postCheck.EndpointEntries | Select-Object -First 1).DisplayVersion
    Write-Host "  ESET Endpoint Security $ver -> INSTALADO" -ForegroundColor Green
    Write-Log "  RESULTADO FINAL: ESET Endpoint INSTALADO (v$ver)" 'OK'

    if ($postCheck.ServiceRunning) {
        Write-Host "  Servicio ekrn -> ACTIVO" -ForegroundColor Green
    } else {
        Write-Host "  Servicio ekrn -> PENDIENTE (puede requerir reinicio)" -ForegroundColor Yellow
    }
} elseif (-not $preCheck.EndpointInstalled -and $postCheck.AnyEset) {
    Write-Host "  Hay productos ESET pero Endpoint NO detectado aun" -ForegroundColor Yellow
    Write-Host "  Puede requerir reinicio o esperar a que termine la configuracion" -ForegroundColor Yellow
    Write-Log "  RESULTADO FINAL: ESET presente pero Endpoint no confirmado" 'WARN'
} else {
    Write-Host "  ESET Endpoint NO INSTALADO" -ForegroundColor Red
    Write-Log "  RESULTADO FINAL: ESET Endpoint NO INSTALADO" 'ERROR'
}

Write-Host ""
Write-Host "  Log: $LogFile" -ForegroundColor DarkGray
Write-Host "  Presiona Enter para cerrar..." -ForegroundColor Cyan
Read-Host
