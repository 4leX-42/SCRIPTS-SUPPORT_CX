#Requires -RunAsAdministrator

<#
.SYNOPSIS
    [ES] Repara la instalacion de Office: reparacion rapida u online, y reactivacion.
    [EN] Repairs the Office installation: quick or online repair, plus reactivation.
.DESCRIPTION
    Instala Outlook Classic via Office Deployment Tool (ODT) + configuration.xml.
    - Copia OfficeSetup.exe + configuration.xml a local
    - Cierra procesos Office antes de instalar
    - Timeout 15 min (Office descarga ~2GB)
    - Verificacion post-instalacion
.NOTES
    v1.0 - 2026-04-11 - Modulo independiente
#>

$ErrorActionPreference = 'Continue'
$Source  = if ($env:SOPORTE_ORIGEN_PAQUETES) { $env:SOPORTE_ORIGEN_PAQUETES } else { '\\servidor\utilidades\1.Node_Preparation' }
$LogDir  = "$env:USERPROFILE\LOGS_Script"
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
$LogFile = "$LogDir\Mod_Office_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$Cache   = "$env:TEMP\_Mod_Office"

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

function Test-OfficeInstalled {
    <# Detecta Microsoft Outlook / Office 365 Apps #>
    $apps = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    ) | ForEach-Object { Get-ItemProperty $_ -EA SilentlyContinue } |
        Where-Object {
            $_.DisplayName -like '*Microsoft Outlook*' -or
            $_.DisplayName -like '*Microsoft 365 Apps*' -or
            $_.DisplayName -like '*Microsoft Office*'
        }

    # Tambien verificar via Click-to-Run
    $c2r = Test-Path 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    $c2rProducts = $null
    if ($c2r) {
        $c2rProducts = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -EA SilentlyContinue).ProductReleaseIds
    }

    # Verificar binario de Outlook
    $outlookExe = "$env:ProgramFiles\Microsoft Office\root\Office16\OUTLOOK.EXE"
    $outlookExists = Test-Path $outlookExe

    return @{
        Installed    = ($apps.Count -gt 0 -or $c2r)
        Registry     = $apps
        C2R          = $c2r
        C2RProducts  = $c2rProducts
        OutlookExe   = $outlookExists
    }
}

function Show-OfficeStatus {
    param([string]$Label)
    Write-Log "-- $Label --"

    # Registro
    $allOffice = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    ) | ForEach-Object { Get-ItemProperty $_ -EA SilentlyContinue } |
        Where-Object { $_.DisplayName -like '*Microsoft Office*' -or $_.DisplayName -like '*Microsoft 365*' -or $_.DisplayName -like '*Outlook*' }

    foreach ($app in $allOffice) {
        Write-Log "  $($app.DisplayName) v$($app.DisplayVersion)"
    }
    if (-not $allOffice) { Write-Log "  (sin entradas Office en registro)" }

    # Click-to-Run
    $c2rPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    if (Test-Path $c2rPath) {
        $c2r = Get-ItemProperty $c2rPath -EA SilentlyContinue
        Write-Log "  C2R Products: $($c2r.ProductReleaseIds)"
        Write-Log "  C2R Platform: $($c2r.Platform)"
        Write-Log "  C2R Channel:  $($c2r.CDNBaseUrl)"
        Write-Log "  C2R Version:  $($c2r.VersionToReport)"
    } else {
        Write-Log "  Click-to-Run: No instalado"
    }

    # Procesos Office activos
    $officeProcs = Get-Process | Where-Object { $_.Name -match 'OUTLOOK|WINWORD|EXCEL|POWERPNT|OfficeClickToRun|OfficeC2RClient' }
    if ($officeProcs) {
        foreach ($p in $officeProcs) {
            Write-Log "  Proceso: $($p.Name) (PID=$($p.Id))"
        }
    } else {
        Write-Log "  (sin procesos Office activos)"
    }
}

# ==============================================
# MAIN
# ==============================================

Write-Host ""
Write-Host "  MICROSOFT OFFICE / OUTLOOK - Modulo de Instalacion" -ForegroundColor Magenta
Write-Host "  Log: $LogFile" -ForegroundColor DarkGray
Write-Host ""

Write-Log "=== Mod-Office iniciado ==="

# -- Pre-check --
Show-OfficeStatus -Label 'PRE-CHECK'
$pre = Test-OfficeInstalled

if ($pre.Installed -and $pre.OutlookExe) {
    Write-Log "  Office ya instalado con Outlook presente" 'OK'
    Write-Host "  Office ya instalado:" -ForegroundColor Green
    foreach ($app in $pre.Registry) {
        Write-Host "    $($app.DisplayName) v$($app.DisplayVersion)" -ForegroundColor Green
    }
    if ($pre.C2RProducts) {
        Write-Host "    C2R: $($pre.C2RProducts)" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "  Presiona Enter para cerrar..." -ForegroundColor Cyan
    Read-Host
    exit 0
}

if ($pre.C2R -and -not $pre.OutlookExe) {
    Write-Log "  Office C2R detectado pero Outlook no presente - instalando Outlook" 'WARN'
    Write-Host "  Office C2R detectado pero Outlook no esta. Instalando Outlook..." -ForegroundColor Yellow
}

# -- Verificar archivos --
$officeExe = "$Source\OfficeSetup.exe"
$xmlFile   = "$Source\configuration.xml"

if (-not (Test-Path $officeExe)) {
    Write-Log "  OfficeSetup.exe no encontrado: $officeExe" 'ERROR'
    Write-Host "  Presiona Enter para cerrar..." -ForegroundColor Cyan
    Read-Host
    exit 1
}

if (-not (Test-Path $xmlFile)) {
    Write-Log "  configuration.xml no encontrado: $xmlFile" 'ERROR'
    Write-Host "  FALTA configuration.xml en $Source" -ForegroundColor Red
    Write-Host "  Presiona Enter para cerrar..." -ForegroundColor Cyan
    Read-Host
    exit 1
}

# Mostrar configuracion XML
Write-Log "  Contenido de configuration.xml:"
Get-Content $xmlFile | ForEach-Object { Write-Log "    $_" }

# -- Copiar a local --
if (-not (Test-Path $Cache)) { New-Item $Cache -ItemType Directory -Force | Out-Null }

$localExe = "$Cache\OfficeSetup.exe"
$localXml = "$Cache\configuration.xml"

Write-Log "  Copiando a local..."
Write-Host "  Copiando OfficeSetup + XML a local..." -ForegroundColor DarkGray
Copy-Item $officeExe $localExe -Force
Copy-Item $xmlFile $localXml -Force

# -- Cerrar procesos Office --
Write-Log "  Cerrando procesos Office..."
Write-Host "  Cerrando procesos Office..." -ForegroundColor DarkGray

$officeProcessNames = @('OUTLOOK','WINWORD','EXCEL','POWERPNT','ONENOTE','MSACCESS',
                         'OfficeClickToRun','OfficeC2RClient','AppVShNotify')
foreach ($pn in $officeProcessNames) {
    $p = Get-Process -Name $pn -EA SilentlyContinue
    if ($p) {
        Write-Log "  Matando $pn (PID=$($p.Id))"
        $p | Stop-Process -Force -EA SilentlyContinue
    }
}
Start-Sleep -Seconds 3

# -- Instalar --
Write-Log ""
Write-Log "  Iniciando instalacion: OfficeSetup.exe /configure configuration.xml"
Write-Host ""
Write-Host "  Instalando Outlook (esto puede tardar 10-15 min)..." -ForegroundColor Cyan
Write-Host "  Office descarga ~2GB de internet + instala" -ForegroundColor DarkGray
Write-Host ""

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName               = $localExe
$psi.Arguments              = "/configure `"$localXml`""
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

Write-Log "  PID=$($proc.Id), timeout=900s"

$stdoutTask = $proc.StandardOutput.ReadToEndAsync()
$stderrTask = $proc.StandardError.ReadToEndAsync()

# Spinner con progreso estimado
$spinChars = @('|','/','-','\')
$spinIdx = 0
$sw = [Diagnostics.Stopwatch]::StartNew()
$timeout = 900

while (-not $proc.HasExited -and $sw.Elapsed.TotalSeconds -lt $timeout) {
    $s = $spinChars[$spinIdx++ % 4]
    $t = [int]$sw.Elapsed.TotalSeconds
    $min = [int]($t / 60)
    $sec = $t % 60
    $pct = [Math]::Min(95, [int]($t / $timeout * 100))
    $bar = ('>' * [int]($pct / 5)) + ('-' * (20 - [int]($pct / 5)))
    Write-Host "`r  [$s] [$bar] ${pct}%  ${min}m ${sec}s  " -ForegroundColor DarkGray -NoNewline
    Start-Sleep -Seconds 3
}
Write-Host "`r  $(' ' * 60)" -NoNewline
Write-Host ""

$timedOut = -not $proc.HasExited
if ($timedOut) {
    Write-Log "  TIMEOUT ${timeout}s" 'WARN'
    Write-Host "  TIMEOUT tras 15 minutos" -ForegroundColor Red

    # Matar procesos relacionados
    @('OfficeClickToRun','OfficeC2RClient','setup') | ForEach-Object {
        Get-Process -Name $_ -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
    }
    try { $proc.Kill() } catch {}
}
$proc.WaitForExit()
$code = $proc.ExitCode
Write-Log "  Exit code: $code (${([int]$sw.Elapsed.TotalSeconds)}s)"

# Capturar output
try {
    $stderr = $stderrTask.Result
    if ($stderr -and $stderr.Trim()) { Write-Log "  STDERR: $stderr" 'WARN' }
} catch {}

$proc.Dispose()

# -- Post-check --
Write-Host ""
Write-Host "  Verificando instalacion..." -ForegroundColor DarkGray
Start-Sleep -Seconds 5

Show-OfficeStatus -Label 'POST-CHECK'
$post = Test-OfficeInstalled

Write-Host ""
if ($post.Installed -and $post.OutlookExe) {
    Write-Host "  Office/Outlook INSTALADO CORRECTAMENTE" -ForegroundColor Green
    Write-Log "  RESULTADO: Office INSTALADO" 'OK'
    foreach ($app in $post.Registry) {
        Write-Host "    $($app.DisplayName) v$($app.DisplayVersion)" -ForegroundColor Green
    }
} elseif ($post.C2R) {
    Write-Host "  C2R detectado pero Outlook.exe no encontrado aun" -ForegroundColor Yellow
    Write-Host "  Office puede estar terminando la configuracion en background" -ForegroundColor Yellow
    Write-Log "  RESULTADO: C2R presente, Outlook.exe pendiente" 'WARN'

    # Verificar si OfficeClickToRun sigue activo (configurando)
    $c2rProc = Get-Process -Name 'OfficeClickToRun' -EA SilentlyContinue
    if ($c2rProc) {
        Write-Host "  OfficeClickToRun sigue activo - esperando 60s mas..." -ForegroundColor Yellow
        Start-Sleep -Seconds 60
        $post2 = Test-OfficeInstalled
        if ($post2.OutlookExe) {
            Write-Host "  Outlook.exe encontrado tras espera adicional" -ForegroundColor Green
            Write-Log "  Outlook.exe encontrado tras 60s adicionales" 'OK'
        }
    }
} elseif ($code -eq 0) {
    Write-Host "  Exit code 0 pero Office no detectado en registro" -ForegroundColor Yellow
    Write-Host "  Puede requerir reinicio o mas tiempo de configuracion" -ForegroundColor Yellow
    Write-Log "  RESULTADO: code=0 pero no detectado" 'WARN'
} else {
    Write-Host "  Office NO INSTALADO (code=$code)" -ForegroundColor Red
    Write-Log "  RESULTADO: Office NO INSTALADO (code=$code)" 'ERROR'

    # Diagnostico adicional
    if ($code -eq 17002) {
        Write-Host "  Error 17002: No hay conexion a internet para descargar Office" -ForegroundColor Yellow
        Write-Log "  Error 17002: Sin conexion a internet"
    } elseif ($code -eq 17004) {
        Write-Host "  Error 17004: Producto ya instalado o conflicto de versiones" -ForegroundColor Yellow
        Write-Log "  Error 17004: Conflicto de versiones"
    } elseif ($code -eq 17006) {
        Write-Host "  Error 17006: Proceso bloqueado (otro Office en uso)" -ForegroundColor Yellow
        Write-Log "  Error 17006: Bloqueado por otro proceso"
    }
}

# Limpiar
if (Test-Path $Cache) { Remove-Item $Cache -Recurse -Force -EA SilentlyContinue }

Write-Host ""
Write-Host "  Log: $LogFile" -ForegroundColor DarkGray
Write-Host "  Presiona Enter para cerrar..." -ForegroundColor Cyan
Read-Host
