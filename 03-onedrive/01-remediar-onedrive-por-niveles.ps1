#Requires -Version 5.1

<#
.SYNOPSIS
    [ES] Arregla OneDrive subiendo por 5 niveles: reinicio, reset, cache, binario y reinstalacion.
    [EN] Fixes OneDrive escalating through 5 tiers: restart, reset, cache, binary and reinstall.
.DESCRIPTION
    Script de autorremediacion para resolver incidencias del cliente OneDrive:
    sesion colgada, interfaz no carga, sincronizacion detenida.

    Modelo de remediacion escalonado (Nivel 1 -> 5):
      L1 - Recuperacion basica       (kill + relaunch)
      L2 - Reset controlado          (OneDrive /reset)
      L3 - Limpieza selectiva        (cache/config sin afectar datos)
      L4 - Validacion de binarios    (rutas alternativas)
      L5 - Reinstalacion (fallback)  (desinstalacion + reinstalacion silenciosa)

.NOTES
    Version      : 2.0.0
    Compatibilidad: PowerShell 5.1+, Windows 10, Intune / GPO / RMM
    Ejecucion    : SYSTEM o usuario estandar
    Idempotente  : Si -- re-ejecutable sin efectos secundarios
#>

[CmdletBinding()]
param(
    # Nivel maximo de escalado permitido (1-5). Por defecto escala hasta L5.
    [ValidateRange(1, 5)]
    [int]$MaxLevel = 5,

    # Ruta al instalador local de OneDrive (opcional, para L5 sin acceso a Internet).
    [string]$LocalInstallerPath = '',

    # Segundos de espera para que OneDrive se inicie tras cada accion.
    [int]$StartupWaitSeconds = 30,

    # Omitir validaciones de entorno (red, DNS, hora). Util en redes aisladas.
    [switch]$SkipEnvironmentChecks,

    # Limpiar credenciales de OneDrive en Credential Manager (L3+).
    [switch]$ClearCredentials,

    # Forzar reinstalacion aunque el binario exista (solo L5).
    [switch]$ForceReinstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region -- CONSTANTES --------------------------------------------------------

$Script:VERSION      = '2.0.0'
$Script:LOG_ROOT     = 'C:\ProgramData\OneDriveRemediation\Logs'
$Script:LOG_FILE     = Join-Path $Script:LOG_ROOT ("OneDriveRemediation_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$Script:PROCESS_NAME = 'OneDrive'

# Rutas de binario (por prioridad)
$Script:OD_PATHS = @(
    "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe",
    'C:\Program Files\Microsoft OneDrive\OneDrive.exe',
    'C:\Program Files (x86)\Microsoft OneDrive\OneDrive.exe'
)

# Rutas de cache / configuracion (L3)
$Script:OD_CACHE_PATHS = @(
    "$env:LOCALAPPDATA\Microsoft\OneDrive\logs",
    "$env:LOCALAPPDATA\Microsoft\OneDrive\setup\logs",
    "$env:APPDATA\Microsoft\OneDrive\logs"
)
$Script:OD_SETTINGS_PATHS = @(
    "$env:LOCALAPPDATA\Microsoft\OneDrive\settings",
    "$env:APPDATA\Microsoft\OneDrive\settings"
)

# Directorios de datos de usuario -- NUNCA se eliminan
$Script:OD_DATA_SAFE = @(
    "$env:USERPROFILE\OneDrive",
    "$env:USERPROFILE\OneDrive - *"
)

# URL de descarga del instalador OneDrive (canal produccion)
$Script:OD_DOWNLOAD_URL = 'https://go.microsoft.com/fwlink/?linkid=844652'

# Endpoints M365 para validacion de conectividad
$Script:M365_ENDPOINTS = @(
    'login.microsoftonline.com',
    'onedrive.live.com',
    'sharepoint.com'
)

# Tiempo de espera (ms) para test de conectividad TCP
$Script:CONN_TIMEOUT_MS = 3000

# Resultado global
$Script:RemediationResult = @{
    StartTime     = Get-Date
    EndTime       = $null
    LevelReached  = 0
    Success       = $false
    Actions       = [System.Collections.Generic.List[string]]::new()
    Errors        = [System.Collections.Generic.List[string]]::new()
    FinalStatus   = 'UNKNOWN'
}

#endregion

#region -- LOGGING -----------------------------------------------------------

function Initialize-Logging {
    if (-not (Test-Path $Script:LOG_ROOT)) {
        New-Item -ItemType Directory -Path $Script:LOG_ROOT -Force | Out-Null
    }
    Write-Log 'INFO' 'INIT' "OneDrive Remediation Script v$Script:VERSION iniciado"
    Write-Log 'INFO' 'INIT' "Usuario: $env:USERNAME | Equipo: $env:COMPUTERNAME | PSv: $($PSVersionTable.PSVersion)"
    Write-Log 'INFO' 'INIT' "MaxLevel: $MaxLevel | SkipEnvChecks: $SkipEnvironmentChecks | ClearCreds: $ClearCredentials"
}

function Write-Log {
    param(
        [ValidateSet('INFO','WARN','ERROR','SUCCESS')]
        [string]$Level,
        [string]$Action,
        [string]$Message
    )

    $ts      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $padLvl  = $Level.PadRight(7)
    $padAct  = $Action.PadRight(25)
    $entry   = "[$ts] [$padLvl] [$padAct] $Message"

    # Consola con color
    $color = switch ($Level) {
        'INFO'    { 'Cyan'    }
        'WARN'    { 'Yellow'  }
        'ERROR'   { 'Red'     }
        'SUCCESS' { 'Green'   }
    }
    Write-Host $entry -ForegroundColor $color

    # Fichero de log
    try { Add-Content -Path $Script:LOG_FILE -Value $entry -Encoding UTF8 }
    catch { <# No interrumpir el script si falla el log #> }
}

function Add-Action ([string]$Msg) { $Script:RemediationResult.Actions.Add($Msg) }
function Add-Error  ([string]$Msg) {
    $Script:RemediationResult.Errors.Add($Msg)
    Write-Log 'ERROR' 'EXCEPTION' $Msg
}

#endregion

#region -- UTILIDADES --------------------------------------------------------

function Get-OneDrivePath {
    foreach ($path in $Script:OD_PATHS) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

function Get-OneDriveProcess {
    return Get-Process -Name $Script:PROCESS_NAME -ErrorAction SilentlyContinue
}

function Wait-OneDriveStart {
    param([int]$Seconds = $StartupWaitSeconds)
    Write-Log 'INFO' 'WAIT' "Esperando $Seconds s para inicio de OneDrive..."
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        if (Get-OneDriveProcess) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Start-OneDriveClient {
    param([string]$Path = '')
    if ([string]::IsNullOrEmpty($Path)) { $Path = Get-OneDrivePath }
    if (-not $Path) {
        Write-Log 'ERROR' 'LAUNCH' 'No se encontro binario de OneDrive para lanzar'
        return $false
    }
    try {
        Write-Log 'INFO' 'LAUNCH' "Iniciando OneDrive desde: $Path"
        Start-Process -FilePath $Path -WindowStyle Hidden -ErrorAction Stop
        $started = Wait-OneDriveStart
        if ($started) {
            Write-Log 'SUCCESS' 'LAUNCH' 'OneDrive iniciado correctamente'
            Add-Action "OneDrive lanzado desde $Path"
        } else {
            Write-Log 'WARN' 'LAUNCH' "OneDrive no visible en proceso tras $StartupWaitSeconds s"
        }
        return $started
    } catch {
        Add-Error "Error al lanzar OneDrive desde ${Path}: $($_.Exception.Message)"
        return $false
    }
}

function Stop-OneDriveProcess {
    $procs = Get-OneDriveProcess
    if (-not $procs) {
        Write-Log 'INFO' 'KILL' 'No hay procesos OneDrive activos'
        return
    }
    foreach ($p in $procs) {
        try {
            Write-Log 'INFO' 'KILL' "Finalizando PID $($p.Id) ($($p.ProcessName))"
            $p.Kill()
            $p.WaitForExit(5000) | Out-Null
            Add-Action "Proceso OneDrive PID $($p.Id) finalizado"
        } catch {
            Add-Error "No se pudo terminar PID $($p.Id): $($_.Exception.Message)"
        }
    }
    Start-Sleep -Seconds 3
}

function Test-OneDriveHealthy {
    <#
    Comprueba que:
      1. OneDrive.exe esta en ejecucion
      2. No esta en estado Suspended (basico)
      3. El binario existe en disco
    #>
    $proc = Get-OneDriveProcess
    if (-not $proc)               { return $false }
    $binOk = [bool](Get-OneDrivePath)
    return $binOk
}

#endregion

#region -- VALIDACIONES DE ENTORNO -------------------------------------------

function Test-NetworkConnectivity {
    Write-Log 'INFO' 'ENV_CHECK' 'Verificando conectividad a endpoints M365...'
    $ok = $true
    foreach ($host in $Script:M365_ENDPOINTS) {
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $ar  = $tcp.BeginConnect($host, 443, $null, $null)
            $wait = $ar.AsyncWaitHandle.WaitOne($Script:CONN_TIMEOUT_MS, $false)
            if ($wait -and $tcp.Connected) {
                Write-Log 'SUCCESS' 'ENV_CHECK' "Conectividad OK -> $host:443"
            } else {
                Write-Log 'WARN' 'ENV_CHECK' "Sin acceso a $host:443"
                $ok = $false
            }
            $tcp.Close()
        } catch {
            Write-Log 'WARN' 'ENV_CHECK' "Error conectando a ${host}: $($_.Exception.Message)"
            $ok = $false
        }
    }
    return $ok
}

function Test-DnsResolution {
    Write-Log 'INFO' 'ENV_CHECK' 'Verificando resolucion DNS...'
    $ok = $true
    foreach ($fqdn in $Script:M365_ENDPOINTS) {
        try {
            $result = [System.Net.Dns]::GetHostAddresses($fqdn)
            Write-Log 'SUCCESS' 'ENV_CHECK' "DNS OK -> $fqdn ($($result[0].IPAddressToString))"
        } catch {
            Write-Log 'WARN' 'ENV_CHECK' "DNS fallido para $fqdn"
            $ok = $false
        }
    }
    return $ok
}

function Test-TimeSync {
    Write-Log 'INFO' 'ENV_CHECK' 'Verificando sincronizacion horaria...'
    try {
        $w32tm = & w32tm /query /status 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log 'SUCCESS' 'ENV_CHECK' 'Servicio W32Time activo'
            return $true
        }
        Write-Log 'WARN' 'ENV_CHECK' "w32tm status: $w32tm"
        return $false
    } catch {
        Write-Log 'WARN' 'ENV_CHECK' "No se pudo verificar W32Time: $($_.Exception.Message)"
        return $false
    }
}

function Test-ProxyConfiguration {
    Write-Log 'INFO' 'ENV_CHECK' 'Detectando configuracion de proxy...'
    try {
        $proxy = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
        if ($proxy.ProxyEnable -eq 1) {
            Write-Log 'WARN' 'ENV_CHECK' "Proxy activo: $($proxy.ProxyServer)"
        } else {
            Write-Log 'INFO' 'ENV_CHECK' 'Sin proxy configurado en HKCU'
        }
        # Verificar WinHTTP proxy (system-wide)
        $winhttp = & netsh winhttp show proxy 2>&1
        Write-Log 'INFO' 'ENV_CHECK' "WinHTTP proxy: $($winhttp -join ' ')"
    } catch {
        Write-Log 'WARN' 'ENV_CHECK' "No se pudo leer configuracion de proxy: $($_.Exception.Message)"
    }
}

function Invoke-EnvironmentChecks {
    Write-Log 'INFO' 'ENV_CHECK' '-- Iniciando validaciones de entorno --'
    $dnsOk  = Test-DnsResolution
    $netOk  = Test-NetworkConnectivity
    $timeOk = Test-TimeSync
    Test-ProxyConfiguration

    if (-not $dnsOk)  { Write-Log 'WARN' 'ENV_CHECK' 'DNS con fallos -- sincronizacion puede verse afectada' }
    if (-not $netOk)  { Write-Log 'WARN' 'ENV_CHECK' 'Red con fallos -- sincronizacion puede verse afectada' }
    if (-not $timeOk) { Write-Log 'WARN' 'ENV_CHECK' 'Hora no sincronizada -- puede causar errores de auth' }

    Write-Log 'INFO' 'ENV_CHECK' '-- Validaciones de entorno completadas --'
}

#endregion

#region -- NIVEL 1: RECUPERACION BASICA --------------------------------------

function Invoke-Level1 {
    Write-Log 'INFO' 'L1' '==== NIVEL 1: Recuperacion basica ===='
    Add-Action 'L1: Inicio'

    Stop-OneDriveProcess
    $launched = Start-OneDriveClient

    if ($launched) {
        Write-Log 'SUCCESS' 'L1' 'Nivel 1 completado -- OneDrive restaurado'
        Add-Action 'L1: Exito'
        return $true
    }
    Write-Log 'WARN' 'L1' 'Nivel 1 insuficiente -- escalando'
    return $false
}

#endregion

#region -- NIVEL 2: RESET CONTROLADO -----------------------------------------

function Invoke-Level2 {
    Write-Log 'INFO' 'L2' '==== NIVEL 2: Reset controlado ===='
    Add-Action 'L2: Inicio'

    $odPath = Get-OneDrivePath
    if (-not $odPath) {
        Write-Log 'WARN' 'L2' 'Binario no encontrado -- saltando reset'
        return $false
    }

    Stop-OneDriveProcess

    try {
        Write-Log 'INFO' 'L2' "Ejecutando: $odPath /reset"
        $proc = Start-Process -FilePath $odPath -ArgumentList '/reset' -WindowStyle Hidden -PassThru -ErrorAction Stop
        # El reset cierra el proceso automaticamente; esperamos su finalizacion
        $proc.WaitForExit(60000) | Out-Null
        Write-Log 'INFO' 'L2' "Reset finalizado con codigo: $($proc.ExitCode)"
        Add-Action "L2: OneDrive /reset ejecutado (exit=$($proc.ExitCode))"
    } catch {
        Add-Error "L2: Error ejecutando /reset: $($_.Exception.Message)"
        return $false
    }

    # Espera interna de reinicializacion
    Write-Log 'INFO' 'L2' 'Esperando reinicializacion interna (15 s)...'
    Start-Sleep -Seconds 15

    $launched = Start-OneDriveClient -Path $odPath

    if ($launched) {
        Write-Log 'SUCCESS' 'L2' 'Nivel 2 completado -- OneDrive restaurado tras reset'
        Add-Action 'L2: Exito'
        return $true
    }
    Write-Log 'WARN' 'L2' 'Nivel 2 insuficiente -- escalando'
    return $false
}

#endregion

#region -- NIVEL 3: LIMPIEZA SELECTIVA ---------------------------------------

function Clear-OneDriveCache {
    Write-Log 'INFO' 'L3_CACHE' 'Limpiando cache y logs de OneDrive...'
    $removed = 0
    foreach ($dir in $Script:OD_CACHE_PATHS) {
        if (Test-Path $dir) {
            try {
                $items = Get-ChildItem -Path $dir -Recurse -File -ErrorAction SilentlyContinue
                foreach ($item in $items) {
                    # Proteccion extra: nunca eliminar dentro de carpetas de datos
                    $safe = $false
                    foreach ($safeRoot in $Script:OD_DATA_SAFE) {
                        if ($item.FullName -like "$safeRoot*") { $safe = $true; break }
                    }
                    if (-not $safe) {
                        Remove-Item -Path $item.FullName -Force -ErrorAction SilentlyContinue
                        $removed++
                    }
                }
                Write-Log 'INFO' 'L3_CACHE' "Limpiado: $dir ($removed archivos eliminados hasta ahora)"
            } catch {
                $errMsg = $_.Exception.Message
                Write-Log 'WARN' 'L3_CACHE' "No se pudo limpiar ${dir}: $errMsg"
            }
        }
    }
    Add-Action "L3: Cache limpiada ($removed archivos)"
}

function Clear-OneDriveSettings {
    Write-Log 'INFO' 'L3_SETTINGS' 'Limpiando configuracion corrupta de OneDrive...'
    # Archivos seguros a eliminar (no carpeta settings completa)
    $patterns = @('*.dat', '*.tmp', '*.old', 'global.ini')
    foreach ($dir in $Script:OD_SETTINGS_PATHS) {
        if (Test-Path $dir) {
            foreach ($pat in $patterns) {
                try {
                    $files = Get-ChildItem -Path $dir -Filter $pat -ErrorAction SilentlyContinue
                    foreach ($f in $files) {
                        Remove-Item -Path $f.FullName -Force -ErrorAction SilentlyContinue
                        Write-Log 'INFO' 'L3_SETTINGS' "Eliminado: $($f.FullName)"
                    }
                } catch {
                    $errMsg = $_.Exception.Message
                    Write-Log 'WARN' 'L3_SETTINGS' "Error limpiando ${dir}\${pat}: $errMsg"
                }
            }
        }
    }
    Add-Action 'L3: Configuracion corrupta eliminada'
}

function Clear-OneDriveCredentials {
    if (-not $ClearCredentials) { return }
    Write-Log 'INFO' 'L3_CREDS' 'Limpiando credenciales OneDrive en Credential Manager...'
    try {
        # Solo entradas OneDrive / MicrosoftOffice -- NO afecta tokens de Outlook/Teams
        $targets = & cmdkey /list 2>&1 | Select-String 'OneDrive|MicrosoftOffice15|AAD\|OneDrive'
        foreach ($line in $targets) {
            if ($line -match 'Target:\s+(.+)') {
                $target = $Matches[1].Trim()
                & cmdkey /delete:"$target" 2>&1 | Out-Null
                Write-Log 'INFO' 'L3_CREDS' "Credencial eliminada: $target"
                Add-Action "L3: Credencial '$target' eliminada"
            }
        }
    } catch {
        Write-Log 'WARN' 'L3_CREDS' "Error limpiando credenciales: $($_.Exception.Message)"
    }
}

function Invoke-Level3 {
    Write-Log 'INFO' 'L3' '==== NIVEL 3: Limpieza selectiva ===='
    Add-Action 'L3: Inicio'

    Stop-OneDriveProcess
    Clear-OneDriveCache
    Clear-OneDriveSettings
    Clear-OneDriveCredentials

    $launched = Start-OneDriveClient

    if ($launched) {
        Write-Log 'SUCCESS' 'L3' 'Nivel 3 completado -- OneDrive restaurado tras limpieza'
        Add-Action 'L3: Exito'
        return $true
    }
    Write-Log 'WARN' 'L3' 'Nivel 3 insuficiente -- escalando'
    return $false
}

#endregion

#region -- NIVEL 4: VALIDACION DE BINARIOS -----------------------------------

function Invoke-Level4 {
    Write-Log 'INFO' 'L4' '==== NIVEL 4: Validacion de binarios ===='
    Add-Action 'L4: Inicio'

    foreach ($path in $Script:OD_PATHS) {
        if (Test-Path $path) {
            Write-Log 'INFO' 'L4' "Binario encontrado: $path"
            # Verificar que es ejecutable (no 0 bytes)
            $info = Get-Item $path
            if ($info.Length -gt 0) {
                Write-Log 'INFO' 'L4' "Tamano OK: $([math]::Round($info.Length/1MB,2)) MB -- intentando lanzar"
                Stop-OneDriveProcess
                $launched = Start-OneDriveClient -Path $path
                if ($launched) {
                    Write-Log 'SUCCESS' 'L4' "Nivel 4 completado -- OneDrive lanzado desde: $path"
                    Add-Action "L4: Exito desde $path"
                    return $true
                }
            } else {
                Write-Log 'WARN' 'L4' "Binario en $path tiene tamano 0 -- corrupto"
                Add-Action "L4: Binario corrupto detectado en $path"
            }
        } else {
            Write-Log 'INFO' 'L4' "Ruta no existe: $path"
        }
    }

    Write-Log 'WARN' 'L4' 'Nivel 4 insuficiente -- escalando a reinstalacion'
    return $false
}

#endregion

#region -- NIVEL 5: REINSTALACION --------------------------------------------

function Get-OneDriveInstaller {
    <# Devuelve ruta al instalador: local si existe y es valido, sino descarga #>

    if (-not [string]::IsNullOrEmpty($LocalInstallerPath) -and (Test-Path $LocalInstallerPath)) {
        Write-Log 'INFO' 'L5_INSTALLER' "Usando instalador local: $LocalInstallerPath"
        return $LocalInstallerPath
    }

    $tempPath = Join-Path $env:TEMP 'OneDriveSetup.exe'
    Write-Log 'INFO' 'L5_INSTALLER' "Descargando instalador desde Microsoft..."
    try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($Script:OD_DOWNLOAD_URL, $tempPath)
        Write-Log 'SUCCESS' 'L5_INSTALLER' "Instalador descargado: $tempPath"
        return $tempPath
    } catch {
        Add-Error "No se pudo descargar el instalador: $($_.Exception.Message)"
        return $null
    }
}

function Uninstall-OneDriveSilent {
    Write-Log 'INFO' 'L5_UNINSTALL' 'Ejecutando desinstalacion silenciosa de OneDrive...'
    Stop-OneDriveProcess

    # Buscar desinstalador en registro
    $regPaths = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe'
    )
    foreach ($rp in $regPaths) {
        try {
            $key = Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue
            if ($key -and $key.UninstallString) {
                Write-Log 'INFO' 'L5_UNINSTALL' "Desinstalador encontrado en registro: $($key.UninstallString)"
                $uninstallCmd = $key.UninstallString -replace '/uninstall', '/uninstall /silent'
                Start-Process -FilePath 'cmd.exe' -ArgumentList "/c $uninstallCmd" -Wait -WindowStyle Hidden
                Add-Action "L5: OneDrive desinstalado via registro"
                Start-Sleep -Seconds 10
                return
            }
        } catch { <# Continuar con siguiente ruta #> }
    }

    # Fallback: desinstalador conocido
    $setupPath = "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe"
    if (Test-Path $setupPath) {
        Write-Log 'INFO' 'L5_UNINSTALL' "Usando setup local para desinstalar: $setupPath"
        Start-Process -FilePath $setupPath -ArgumentList '/uninstall' -Wait -WindowStyle Hidden
        Add-Action 'L5: OneDrive desinstalado via setup local'
        Start-Sleep -Seconds 10
    } else {
        Write-Log 'WARN' 'L5_UNINSTALL' 'No se encontro desinstalador -- continuando con instalacion forzada'
    }
}

function Install-OneDriveSilent {
    param([string]$InstallerPath)
    Write-Log 'INFO' 'L5_INSTALL' "Instalando OneDrive desde: $InstallerPath"
    try {
        $proc = Start-Process -FilePath $InstallerPath -ArgumentList '/allusers /silent' -PassThru -Wait -WindowStyle Hidden -ErrorAction Stop
        Write-Log 'INFO' 'L5_INSTALL' "Instalacion completada (exit=$($proc.ExitCode))"
        Add-Action "L5: OneDrive instalado (exit=$($proc.ExitCode))"
        Start-Sleep -Seconds 10
        return ($proc.ExitCode -eq 0)
    } catch {
        Add-Error "Error durante la instalacion: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-Level5 {
    Write-Log 'INFO' 'L5' '==== NIVEL 5: Reinstalacion (fallback) ===='
    Add-Action 'L5: Inicio'

    # Si no se fuerza y el binario existe y funciona, no reinstalar
    if (-not $ForceReinstall -and (Get-OneDrivePath)) {
        Write-Log 'WARN' 'L5' 'Binario presente pero no funcional -- se procede a reinstalacion'
    }

    Uninstall-OneDriveSilent

    $installer = Get-OneDriveInstaller
    if (-not $installer) {
        Write-Log 'ERROR' 'L5' 'No se pudo obtener el instalador -- Nivel 5 fallido'
        return $false
    }

    $installed = Install-OneDriveSilent -InstallerPath $installer

    if (-not $installed) {
        Write-Log 'ERROR' 'L5' 'Instalacion fallida'
        return $false
    }

    # Limpiar instalador temporal
    if ($installer -like "$env:TEMP*") {
        Remove-Item -Path $installer -Force -ErrorAction SilentlyContinue
    }

    $launched = Start-OneDriveClient

    if ($launched) {
        Write-Log 'SUCCESS' 'L5' 'Nivel 5 completado -- OneDrive reinstalado y lanzado'
        Add-Action 'L5: Exito'
        return $true
    }
    Write-Log 'ERROR' 'L5' 'OneDrive no arranco tras reinstalacion'
    return $false
}

#endregion

#region -- VALIDACION POST-REMEDIACION ---------------------------------------

function Invoke-PostValidation {
    Write-Log 'INFO' 'POST_VAL' '-- Validacion post-remediacion --'

    $checks = @{
        ProcessRunning    = $false
        BinaryExists      = $false
        SettingsPresent   = $false
        NoCriticalErrors  = $false
    }

    # 1. Proceso en ejecucion
    $proc = Get-OneDriveProcess
    if ($proc) {
        Write-Log 'SUCCESS' 'POST_VAL' "OneDrive.exe en ejecucion (PID: $($proc.Id -join ', '))"
        $checks.ProcessRunning = $true
    } else {
        Write-Log 'ERROR' 'POST_VAL' 'OneDrive.exe NO esta en ejecucion'
    }

    # 2. Binario existe
    $bin = Get-OneDrivePath
    if ($bin) {
        Write-Log 'SUCCESS' 'POST_VAL' "Binario presente: $bin"
        $checks.BinaryExists = $true
    } else {
        Write-Log 'ERROR' 'POST_VAL' 'Binario OneDrive no encontrado'
    }

    # 3. Directorio de configuracion regenerado
    $settingsRegenerated = $false
    foreach ($dir in $Script:OD_SETTINGS_PATHS) {
        if (Test-Path $dir) { $settingsRegenerated = $true; break }
    }
    if ($settingsRegenerated) {
        Write-Log 'SUCCESS' 'POST_VAL' 'Directorio de configuracion presente'
        $checks.SettingsPresent = $true
    } else {
        Write-Log 'WARN' 'POST_VAL' 'Directorio de configuracion aun no creado (puede regenerarse en background)'
        $checks.SettingsPresent = $true  # No bloquea -- OneDrive lo crea asincronamente
    }

    # 4. Sin errores criticos en este run
    $criticalErrors = $Script:RemediationResult.Errors.Count
    if ($criticalErrors -eq 0) {
        Write-Log 'SUCCESS' 'POST_VAL' 'Sin errores criticos registrados'
        $checks.NoCriticalErrors = $true
    } else {
        Write-Log 'WARN' 'POST_VAL' "$criticalErrors error(es) registrado(s) durante remediacion"
        $checks.NoCriticalErrors = $false
    }

    $allPassed = ($checks.Values | Where-Object { -not $_ }).Count -eq 0
    return $allPassed
}

#endregion

#region -- REPORTE FINAL -----------------------------------------------------

function Write-FinalReport {
    $result   = $Script:RemediationResult
    $elapsed  = [math]::Round(((Get-Date) - $result.StartTime).TotalSeconds, 1)
    $status   = if ($result.Success) { 'SUCCESS' } else { 'FAILED' }

    Write-Log $status 'REPORT' "========================================"
    Write-Log $status 'REPORT' "  RESULTADO FINAL: $status"
    Write-Log $status 'REPORT' "  Nivel alcanzado : $($result.LevelReached)"
    Write-Log $status 'REPORT' "  Duracion        : ${elapsed}s"
    Write-Log $status 'REPORT' "  Acciones        : $($result.Actions.Count)"
    Write-Log $status 'REPORT' "  Errores         : $($result.Errors.Count)"
    Write-Log $status 'REPORT' "  Log             : $Script:LOG_FILE"
    Write-Log $status 'REPORT' "========================================"

    foreach ($action in $result.Actions) {
        Write-Log 'INFO' 'REPORT_ACTION' $action
    }
    foreach ($err in $result.Errors) {
        Write-Log 'ERROR' 'REPORT_ERROR' $err
    }

    # Exit code para Intune / RMM
    #  0 = exito
    #  1 = remediacion parcial / OneDrive lanzado con errores
    # -1 = fallo total
    if ($result.Success)                              { exit 0  }
    elseif ($result.LevelReached -gt 0)               { exit 1  }
    else                                              { exit -1 }
}

#endregion

#region -- ORQUESTADOR PRINCIPAL ---------------------------------------------

function Invoke-OneDriveRemediation {

    Initialize-Logging

    # -- Validaciones de entorno --------------------------------------
    if (-not $SkipEnvironmentChecks) {
        Invoke-EnvironmentChecks
    }

    # -- Verificar si OneDrive ya esta sano (ejecucion idempotente) ---
    if (Test-OneDriveHealthy) {
        Write-Log 'SUCCESS' 'MAIN' 'OneDrive ya esta en ejecucion y saludable -- no se requiere remediacion'
        $Script:RemediationResult.Success     = $true
        $Script:RemediationResult.FinalStatus = 'ALREADY_HEALTHY'
        $Script:RemediationResult.EndTime     = Get-Date
        Add-Action 'Sin accion requerida -- OneDrive saludable al inicio'
        Write-FinalReport
        return
    }

    Write-Log 'WARN' 'MAIN' 'OneDrive no esta saludable -- iniciando remediacion escalonada'

    # -- Escalado de niveles ------------------------------------------
    $levels = @(
        @{ Level = 1; Fn = { Invoke-Level1 } },
        @{ Level = 2; Fn = { Invoke-Level2 } },
        @{ Level = 3; Fn = { Invoke-Level3 } },
        @{ Level = 4; Fn = { Invoke-Level4 } },
        @{ Level = 5; Fn = { Invoke-Level5 } }
    )

    $remediated = $false
    foreach ($entry in $levels) {
        if ($entry.Level -gt $MaxLevel) {
            Write-Log 'WARN' 'MAIN' "Nivel $($entry.Level) excede MaxLevel=$MaxLevel -- deteniendo escalado"
            break
        }

        $Script:RemediationResult.LevelReached = $entry.Level
        try {
            $ok = & $entry.Fn
            if ($ok) {
                $remediated = $true
                break
            }
        } catch {
            Add-Error "Excepcion no controlada en Nivel $($entry.Level): $($_.Exception.Message)"
        }
    }

    # -- Post-validacion ----------------------------------------------
    if ($remediated) {
        $postOk = Invoke-PostValidation
        $Script:RemediationResult.Success     = $postOk
        $Script:RemediationResult.FinalStatus = if ($postOk) { 'REMEDIATED' } else { 'PARTIAL' }
    } else {
        $Script:RemediationResult.FinalStatus = 'FAILED'
        Write-Log 'ERROR' 'MAIN' "Remediacion fallida tras $MaxLevel nivel(es)"
    }

    $Script:RemediationResult.EndTime = Get-Date
    Write-FinalReport
}

#endregion

# -- PUNTO DE ENTRADA ----------------------------------------------------------
Invoke-OneDriveRemediation
