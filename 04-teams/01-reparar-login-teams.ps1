<#
.SYNOPSIS
    [ES] Arregla el inicio de sesion de Teams cuando se queda en bucle o no autentica.
    [EN] Fixes Teams sign-in when it loops or fails to authenticate.
.DESCRIPTION
    Soluciona el problema de "login atascado" en Microsoft Teams (Teams nuevo y clasico)
    cuando el usuario introduce credenciales pero el proceso se queda bloqueado y no completa.

    No se limita a borrar la cache: investiga el estado del sistema y corrige TODOS los
    componentes que suelen provocar un inicio de sesion atascado:

      - Procesos bloqueados de Teams / Update / WebView2.
      - Cache de Teams nuevo (paquete MSTeams) y Teams clasico (%APPDATA%).
      - Datos de WebView2 (EBWebView) usados por Teams nuevo.
      - Tokens de autenticacion WAM / TokenBroker.
      - Pila de identidad de Microsoft: IdentityCRL y OneAuth.
      - Credenciales atascadas en el Administrador de credenciales de Windows.
      - Identidad de Office / Microsoft 365 (registro HKCU).
      - Claves de registro de Teams y autenticacion.
      - Archivos temporales de Teams.
      - Higiene de red (cache DNS) y verificaciones de hora del sistema y hosts.
      - (Opcional) Re-registro/reparacion del paquete de Teams nuevo.

    Diseno orientado a maxima compatibilidad y resistencia en equipos lentos o con
    PowerShell inestable:
      - Compatible con Windows PowerShell 5.1 (el que trae Windows 11) y con PowerShell 7.
      - Sin modulos externos ni dependencias (usa cmdlets nativos + cmdkey/reg/dsregcmd).
      - Control de errores exhaustivo: cada accion va en try/catch y NUNCA detiene el script.
      - Verifica la existencia/estado de cada elemento ANTES de actuar y comprueba el
        resultado DESPUES.
      - Adaptativo: detecta version de Windows, Teams nuevo vs clasico, estado de union a
        Azure AD, y solo actua sobre lo que existe.
      - Copias de seguridad automaticas de claves de registro y de la lista de credenciales.
      - Modo simulacion (-DryRun) que muestra que se haria SIN borrar nada.

    IMPORTANTE - PERFIL DE USUARIO:
      Casi todo el problema vive en el perfil del USUARIO afectado (HKCU, %LOCALAPPDATA%,
      %APPDATA%). EJECUTA ESTE SCRIPT INICIANDO SESION COMO EL USUARIO AFECTADO Y SIN ELEVAR.
      Si se ejecuta "como administrador" con otra cuenta, se limpiaria el perfil equivocado.
      Los pocos pasos que requieren admin (sincronizar hora) se omiten con aviso si no hay
      privilegios; el resto funciona sin elevacion.

.PARAMETER DryRun
    Modo simulacion. Muestra exactamente que se cerraria/eliminaria pero NO realiza ningun
    cambio. RECOMENDADO para la primera ejecucion de prueba.

.PARAMETER Force
    Omite la pregunta de confirmacion interactiva (uso desatendido). Ignorado en -DryRun.

.PARAMETER Aggressive
    Habilita acciones mas amplias y potencialmente intrusivas:
      - Reset completo del WAM/AAD BrokerPlugin (cierra la sesion de TODAS las apps que
        usan cuentas de trabajo/Microsoft, no solo Teams; requiere reinicio despues).
      - Borrado completo (no solo cache) de las carpetas de datos de Teams.
      - Eliminacion de credenciales MSA/SSO genericas (virtualapp/didlogical, SSO_POP_Device).
    Usar solo si el modo normal no resuelve el bloqueo.

.PARAMETER IncludeOutlook
    Cierra tambien Outlook (comparte la pila de identidad OneAuth/WAM). Por defecto NO se
    cierra para no interrumpir trabajo sin guardar. Guarda tu trabajo antes de usarlo.

.PARAMETER RepairTeams
    Tras la limpieza, intenta re-registrar/reparar el paquete de Teams nuevo (si esta
    instalado) para regenerar archivos danados.

.PARAMETER LogPath
    Carpeta donde guardar el log y las copias de seguridad. Por defecto se crea una carpeta
    con marca de tiempo en %TEMP%.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Repair-TeamsLogin.ps1 -DryRun
    Prueba segura: muestra todo lo que se haria sin tocar nada. EJECUTAR ESTO PRIMERO.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Repair-TeamsLogin.ps1
    Ejecucion normal con confirmacion y copias de seguridad.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Repair-TeamsLogin.ps1 -Aggressive -RepairTeams -Force
    Reparacion profunda y desatendida (reiniciar el equipo al terminar).

.NOTES
    Autor : Generado para Andersen (entorno corporativo).
    Compat: Windows 11, Windows PowerShell 5.1 / PowerShell 7+.
    Forma de uso recomendada en equipos problematicos: GUARDAR este .ps1 y ejecutarlo con
    -File (no pegar el contenido en la consola). Ejemplo:
        powershell -NoProfile -ExecutionPolicy Bypass -File "C:\ruta\Repair-TeamsLogin.ps1" -DryRun
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Force,
    [switch]$Aggressive,
    [switch]$IncludeOutlook,
    [switch]$RepairTeams,
    [string]$LogPath
)

# ============================================================================
#  CONFIGURACION GLOBAL Y ARRANQUE RESILIENTE
# ============================================================================
# No detener nunca el script ante un error no controlado: cada paso gestiona el suyo.
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'   # evita barras de progreso lentas en equipos flojos
$script:DryRun         = [bool]$DryRun

# Contadores para el resumen final (hashtable normal: el incremento ++ es 100% fiable)
$script:Stats = @{
    Removed   = 0
    Skipped   = 0
    Warnings  = 0
    Errors    = 0
}

# --- Resolver carpeta de log/backup ---------------------------------------
try {
    $stamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
} catch {
    $stamp = 'run'
}
if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $base = $env:TEMP
    if ([string]::IsNullOrWhiteSpace($base)) { $base = $env:LOCALAPPDATA }
    if ([string]::IsNullOrWhiteSpace($base)) { $base = 'C:\Windows\Temp' }
    $script:BackupDir = Join-Path $base ("TeamsLoginFix_" + $stamp)
} else {
    $script:BackupDir = $LogPath
}
try {
    if (-not (Test-Path -LiteralPath $script:BackupDir)) {
        New-Item -ItemType Directory -Path $script:BackupDir -Force -ErrorAction Stop | Out-Null
    }
} catch {
    # Fallback final si no se puede crear: usar carpeta temporal del sistema
    $script:BackupDir = 'C:\Windows\Temp'
}
$script:LogFile = Join-Path $script:BackupDir 'Repair-TeamsLogin.log'

# ============================================================================
#  FUNCIONES AUXILIARES
# ============================================================================

function Write-Log {
    <#  Escribe en consola (con color) y en el archivo de log. Nunca lanza excepcion. #>
    param(
        [string]$Message,
        [ValidateSet('INFO','OK','WARN','ERROR','STEP','DRYRUN','HEAD')]
        [string]$Level = 'INFO'
    )
    $ts = ''
    try { $ts = (Get-Date).ToString('HH:mm:ss') } catch { $ts = '--:--:--' }
    $line = "[$ts] [$Level] $Message"

    switch ($Level) {
        'OK'     { $color = 'Green' }
        'WARN'   { $color = 'Yellow' }
        'ERROR'  { $color = 'Red' }
        'STEP'   { $color = 'Cyan' }
        'DRYRUN' { $color = 'Magenta' }
        'HEAD'   { $color = 'White' }
        default  { $color = 'Gray' }
    }
    if ($Level -eq 'WARN')  { $script:Stats.Warnings++ }
    if ($Level -eq 'ERROR') { $script:Stats.Errors++ }

    try { Write-Host $line -ForegroundColor $color } catch { try { Write-Host $line } catch {} }
    try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
}

function Write-Section {
    param([string]$Title)
    $bar = ('-' * 70)
    Write-Log $bar 'HEAD'
    Write-Log $Title 'STEP'
    Write-Log $bar 'HEAD'
}

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object Security.Principal.WindowsPrincipal($id)
        return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Test-PathSafe {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try { return (Test-Path -LiteralPath $Path) } catch { return $false }
}

function Remove-ItemSafe {
    <#
        Elimina una ruta de forma segura:
        - Verifica existencia antes de actuar.
        - En -DryRun solo informa.
        - -ContentsOnly borra el contenido pero conserva la carpeta raiz.
        - Verifica el resultado y reporta archivos bloqueados sin abortar.
    #>
    param(
        [string]$Path,
        [switch]$ContentsOnly,
        [string]$Label
    )
    if ([string]::IsNullOrWhiteSpace($Label)) { $Label = $Path }
    if ([string]::IsNullOrWhiteSpace($Path))  { return }

    if (-not (Test-PathSafe $Path)) {
        Write-Log "No existe (omitido): $Label" 'INFO'
        $script:Stats.Skipped++
        return
    }

    if ($script:DryRun) {
        if ($ContentsOnly) { Write-Log "[SIMULACION] Se vaciaria: $Label" 'DRYRUN' }
        else               { Write-Log "[SIMULACION] Se eliminaria: $Label" 'DRYRUN' }
        return
    }

    try {
        if ($ContentsOnly) {
            $children = @()
            try { $children = Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue } catch {}
            $failed = 0
            foreach ($c in $children) {
                try {
                    Remove-Item -LiteralPath $c.FullName -Recurse -Force -ErrorAction Stop
                } catch {
                    $failed++
                    Write-Log "Bloqueado/no borrado: $($c.FullName) ($($_.Exception.Message))" 'WARN'
                }
            }
            if ($failed -eq 0) { Write-Log "Vaciado: $Label" 'OK'; $script:Stats.Removed++ }
            else               { Write-Log "Vaciado parcial: $Label ($failed elementos en uso)" 'WARN' }
        } else {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            if (Test-PathSafe $Path) {
                Write-Log "Eliminacion parcial (en uso): $Label" 'WARN'
            } else {
                Write-Log "Eliminado: $Label" 'OK'
                $script:Stats.Removed++
            }
        }
    } catch {
        Write-Log "Error al eliminar '$Label': $($_.Exception.Message)" 'WARN'
    }
}

function Stop-ProcessSafe {
    <#
        Cierra procesos por nombre. Opcionalmente filtra por ruta (-PathLike) para no
        cerrar ejecutables homonimos de otras aplicaciones (p.ej. Update.exe).
    #>
    param(
        [string[]]$Names,
        [string]$PathLike
    )
    foreach ($n in $Names) {
        $procs = @()
        try { $procs = @(Get-Process -Name $n -ErrorAction SilentlyContinue) } catch {}
        if (-not $procs -or $procs.Count -eq 0) {
            Write-Log "Proceso no activo: $n" 'INFO'
            continue
        }
        foreach ($p in $procs) {
            if ($PathLike) {
                $pp = $null
                try { $pp = $p.Path } catch {}
                # Si se exige filtro de ruta y NO se puede verificar, NO se cierra (evita
                # matar ejecutables homonimos de otras apps, p.ej. otro Update.exe).
                if (-not $pp) {
                    Write-Log "Omitido (no se pudo leer la ruta): $n (PID $($p.Id))" 'INFO'
                    continue
                }
                if ($pp -notlike $PathLike) {
                    Write-Log "Omitido (ruta distinta): $n -> $pp" 'INFO'
                    continue
                }
            }
            if ($script:DryRun) {
                Write-Log "[SIMULACION] Se cerraria proceso: $n (PID $($p.Id))" 'DRYRUN'
                continue
            }
            try {
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
                Write-Log "Proceso cerrado: $n (PID $($p.Id))" 'OK'
            } catch {
                Write-Log "No se pudo cerrar $n (PID $($p.Id)): $($_.Exception.Message)" 'WARN'
            }
        }
    }
}

function ConvertTo-ProviderPath {
    param([string]$KeyPath)
    $p = $KeyPath
    $p = $p -replace '^HKCU\\', 'HKCU:\'
    $p = $p -replace '^HKLM\\', 'HKLM:\'
    $p = $p -replace '^HKCR\\', 'HKCR:\'
    return $p
}

function Backup-RegistryKey {
    <#  Exporta una clave de registro a un archivo .reg en la carpeta de backup. #>
    param([string]$KeyPath)
    $provider = ConvertTo-ProviderPath $KeyPath
    if (-not (Test-PathSafe $provider)) { return $false }
    $safe = ($KeyPath -replace '[\\:*?"<>|]', '_')
    $file = Join-Path $script:BackupDir ("reg_" + $safe + ".reg")
    try {
        $out = & reg.exe export "$KeyPath" "$file" /y 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Backup de registro: $KeyPath" 'OK'
            return $true
        } else {
            Write-Log "No se pudo exportar $KeyPath ($out)" 'WARN'
            return $false
        }
    } catch {
        Write-Log "Error exportando $KeyPath : $($_.Exception.Message)" 'WARN'
        return $false
    }
}

function Remove-RegistryKeySafe {
    param(
        [string]$KeyPath,
        [string]$Label
    )
    if ([string]::IsNullOrWhiteSpace($Label)) { $Label = $KeyPath }
    $provider = ConvertTo-ProviderPath $KeyPath
    if (-not (Test-PathSafe $provider)) {
        Write-Log "Clave no existe (omitida): $Label" 'INFO'
        $script:Stats.Skipped++
        return
    }
    Backup-RegistryKey -KeyPath $KeyPath | Out-Null
    if ($script:DryRun) {
        Write-Log "[SIMULACION] Se eliminaria clave: $Label" 'DRYRUN'
        return
    }
    try {
        Remove-Item -LiteralPath $provider -Recurse -Force -ErrorAction Stop
        Write-Log "Clave eliminada: $Label" 'OK'
        $script:Stats.Removed++
    } catch {
        Write-Log "Error al eliminar clave '$Label': $($_.Exception.Message)" 'WARN'
    }
}

function Invoke-Native {
    <#  Ejecuta una herramienta externa de forma segura y devuelve su salida como texto. #>
    param([string]$File, [string[]]$Arguments)
    try {
        $out = & $File @Arguments 2>&1 | Out-String
        return $out
    } catch {
        Write-Log "No se pudo ejecutar '$File': $($_.Exception.Message)" 'WARN'
        return ''
    }
}

# ============================================================================
#  INICIO
# ============================================================================
Clear-Host 2>$null
Write-Section 'REPARACION DE INICIO DE SESION DE MICROSOFT TEAMS (Windows 11)'
Write-Log "Carpeta de log y copias de seguridad: $script:BackupDir" 'INFO'

# Iniciar transcripcion (registro completo de la sesion). No es critico si falla.
try {
    Start-Transcript -Path (Join-Path $script:BackupDir 'transcript.txt') -Force -ErrorAction Stop | Out-Null
    $script:Transcript = $true
} catch {
    $script:Transcript = $false
}

if ($script:DryRun) {
    Write-Log 'MODO SIMULACION (-DryRun): no se realizara NINGUN cambio.' 'DRYRUN'
}

# Aviso de elevacion / perfil
$isAdmin = Test-IsAdmin
$whoami  = $env:USERNAME
if ($isAdmin) {
    Write-Log "Ejecutando con privilegios de administrador como '$whoami'." 'WARN'
    Write-Log "ASEGURATE de que '$whoami' es el USUARIO AFECTADO. Si no, ejecuta SIN elevar" 'WARN'
    Write-Log "con la cuenta del usuario: la limpieza actua sobre el perfil actual (HKCU/AppData)." 'WARN'
} else {
    Write-Log "Ejecutando como usuario '$whoami' (sin elevacion). Correcto para limpieza de perfil." 'OK'
    Write-Log "Algunos pasos de sistema (sincronizar hora) se omitiran por falta de permisos." 'INFO'
}

# ============================================================================
#  FASE 0 - DIAGNOSTICO (solo lectura)
# ============================================================================
Write-Section 'FASE 0 - Diagnostico del sistema (solo lectura)'

# --- Version de Windows ---
$winName = ''; $winBuild = ''; $winVer = ''
try {
    $cv = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $winName  = (Get-ItemProperty -Path $cv -Name 'ProductName'        -ErrorAction SilentlyContinue).ProductName
    $winBuild = (Get-ItemProperty -Path $cv -Name 'CurrentBuildNumber' -ErrorAction SilentlyContinue).CurrentBuildNumber
    $winVer   = (Get-ItemProperty -Path $cv -Name 'DisplayVersion'     -ErrorAction SilentlyContinue).DisplayVersion
} catch {}
Write-Log "Sistema: $winName  (Version $winVer, Build $winBuild)" 'INFO'
Write-Log "PowerShell: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))" 'INFO'

# --- Deteccion de Teams nuevo (paquete MSTeams) ---
$script:HasNewTeams   = $false
$script:NewTeamsPkg   = $null
try {
    $pkg = Get-AppxPackage -Name 'MSTeams' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkg) {
        $script:HasNewTeams = $true
        $script:NewTeamsPkg = $pkg
        Write-Log "Teams NUEVO detectado: version $($pkg.Version)" 'INFO'
    }
} catch {
    Write-Log "No se pudo consultar Appx (se continuara por rutas de carpeta)." 'WARN'
}
# Fallback por carpeta si Appx no respondio
$newTeamsData = Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe'
if (-not $script:HasNewTeams -and (Test-PathSafe $newTeamsData)) {
    $script:HasNewTeams = $true
    Write-Log "Datos de Teams NUEVO detectados en disco (Appx no respondio)." 'INFO'
}
if (-not $script:HasNewTeams) { Write-Log "Teams NUEVO no detectado." 'INFO' }

# --- Deteccion de Teams clasico ---
$classicData = Join-Path $env:APPDATA 'Microsoft\Teams'
$classicExe  = Join-Path $env:LOCALAPPDATA 'Microsoft\Teams\current\Teams.exe'
$script:HasClassicTeams = (Test-PathSafe $classicData) -or (Test-PathSafe $classicExe)
if ($script:HasClassicTeams) { Write-Log "Teams CLASICO detectado (datos o binarios presentes)." 'INFO' }
else                         { Write-Log "Teams CLASICO no detectado." 'INFO' }

# --- Estado de union a Azure AD (dsregcmd) ---
$dsreg = Invoke-Native 'dsregcmd.exe' @('/status')
if ($dsreg) {
    foreach ($k in 'AzureAdJoined','DomainJoined','WorkplaceJoined','WamDefaultSet','AzureAdPrt') {
        $m = [regex]::Match($dsreg, "(?im)^\s*$k\s*:\s*(\S+)")
        if ($m.Success) { Write-Log ("Identidad de dispositivo - {0,-16}: {1}" -f $k, $m.Groups[1].Value) 'INFO' }
    }
} else {
    Write-Log "dsregcmd no disponible (no critico)." 'INFO'
}

# --- Hora del sistema (un reloj desfasado rompe la validacion de tokens) ---
try {
    $now = Get-Date
    Write-Log "Hora local del equipo: $now" 'INFO'
} catch {}

# --- Hosts: comprobar que no se bloquean los endpoints de login ---
$hostsFile = Join-Path $env:WINDIR 'System32\drivers\etc\hosts'
if (Test-PathSafe $hostsFile) {
    try {
        $hostsContent = Get-Content -LiteralPath $hostsFile -ErrorAction SilentlyContinue
        $blockers = $hostsContent | Where-Object {
            $_ -notmatch '^\s*#' -and $_ -match '(login\.microsoftonline\.com|login\.windows\.net|teams\.microsoft\.com|office\.com|msftauth)'
        }
        if ($blockers) {
            Write-Log "ATENCION: el archivo hosts contiene entradas para endpoints de login/Teams:" 'WARN'
            foreach ($b in $blockers) { Write-Log "   hosts> $b" 'WARN' }
            Write-Log "Revisalas manualmente (este script NO modifica hosts por seguridad)." 'WARN'
        } else {
            Write-Log "Archivo hosts sin bloqueos de endpoints de login. Correcto." 'OK'
        }
    } catch {}
}

# ============================================================================
#  CONFIRMACION
# ============================================================================
if (-not $script:DryRun) {
    Write-Log '' 'INFO'
    Write-Log 'Se van a aplicar cambios destructivos: procesos, cache, tokens, credenciales y registro.' 'WARN'
    Write-Log "Se guardan copias de seguridad de registro y credenciales en: $script:BackupDir" 'WARN'
    if ($Aggressive)     { Write-Log 'MODO AGGRESSIVE activo: tambien se reinicia WAM (cierra sesion de TODAS las apps).' 'WARN' }
    if ($IncludeOutlook) { Write-Log 'Se cerrara Outlook: guarda tu trabajo antes de continuar.' 'WARN' }
    if (-not $Force) {
        $answer = ''
        try { $answer = Read-Host 'Escribe S y pulsa Enter para continuar (cualquier otra cosa cancela)' } catch { $answer = '' }
        if ($answer -notmatch '^[SsYy]') {
            Write-Log 'Operacion cancelada por el usuario.' 'WARN'
            if ($script:Transcript) { try { Stop-Transcript | Out-Null } catch {} }
            return
        }
    }
}

# ============================================================================
#  FASE 1 - CERRAR PROCESOS
# ============================================================================
Write-Section 'FASE 1 - Cerrar procesos de Teams y relacionados'

# Teams nuevo y clasico (los nombres varian segun version)
Stop-ProcessSafe -Names @('ms-teams','msteams','Teams','msteamsupdate','msteamsupdatecheck')
# Update.exe SOLO si pertenece a Teams clasico (evita matar otros 'Update.exe')
Stop-ProcessSafe -Names @('Update') -PathLike '*\Microsoft\Teams\*'
# Complemento de Teams para reuniones en Outlook
Stop-ProcessSafe -Names @('TeamsMeetingAddin','TeamsAddinLauncher')

if ($IncludeOutlook) {
    Stop-ProcessSafe -Names @('OUTLOOK')
    Stop-ProcessSafe -Names @('OneDrive')
}

# Pequena espera para liberar bloqueos de archivos (sin Start-Sleep largo en equipos lentos)
if (-not $script:DryRun) { try { Start-Sleep -Seconds 2 } catch {} }

# ============================================================================
#  FASE 2 - CACHE Y DATOS DE TEAMS
# ============================================================================
Write-Section 'FASE 2 - Limpieza de cache y datos de Teams'

# --- Teams NUEVO (paquete MSTeams) ---
if ($script:HasNewTeams) {
    $pkgRoot = Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe'
    if ($Aggressive) {
        # Reset profundo: vaciar todo el almacenamiento del paquete (se regenera al abrir)
        foreach ($sub in 'LocalCache','LocalState','TempState','AC','Settings') {
            Remove-ItemSafe -Path (Join-Path $pkgRoot $sub) -ContentsOnly -Label "Teams nuevo: $sub"
        }
    } else {
        # Limpieza estandar: cache, temporales y WebView2 (conserva configuracion basica)
        Remove-ItemSafe -Path (Join-Path $pkgRoot 'LocalCache') -ContentsOnly -Label 'Teams nuevo: LocalCache'
        Remove-ItemSafe -Path (Join-Path $pkgRoot 'TempState')  -ContentsOnly -Label 'Teams nuevo: TempState'
        Remove-ItemSafe -Path (Join-Path $pkgRoot 'AC\Temp')    -ContentsOnly -Label 'Teams nuevo: AC\Temp'
    }
}

# --- Teams CLASICO (%APPDATA%\Microsoft\Teams) ---
if ($script:HasClassicTeams -and (Test-PathSafe $classicData)) {
    if ($Aggressive) {
        # Borrado completo de datos del usuario (NO toca el ejecutable en %LOCALAPPDATA%)
        Remove-ItemSafe -Path $classicData -ContentsOnly -Label 'Teams clasico: datos de usuario completos'
    } else {
        # Solo subcarpetas de cache/sesion que retienen el bloqueo de login
        $classicSubs = @(
            'Cache','blob_storage','databases','GPUCache','IndexedDB','Local Storage',
            'tmp','Service Worker','Application Cache','Code Cache','Cookies',
            'Network','EBWebView','Partitions'
        )
        foreach ($s in $classicSubs) {
            Remove-ItemSafe -Path (Join-Path $classicData $s) -Label "Teams clasico: $s"
        }
    }
}

# ============================================================================
#  FASE 3 - WEBVIEW2 (motor web de Teams nuevo)
# ============================================================================
Write-Section 'FASE 3 - Datos de WebView2 (EBWebView)'

if ($script:HasNewTeams) {
    $pkgRoot   = Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe'
    # WebView2 de Teams nuevo puede residir en distintas rutas segun version: limpiar todas las que existan
    $webviewCandidates = @(
        (Join-Path $pkgRoot 'LocalCache\Microsoft\MSTeams\EBWebView'),
        (Join-Path $pkgRoot 'AC\Microsoft\MSTeams\EBWebView'),
        (Join-Path $pkgRoot 'LocalCache\EBWebView')
    )
    foreach ($w in $webviewCandidates) {
        if (Test-PathSafe $w) { Remove-ItemSafe -Path $w -ContentsOnly -Label "WebView2: $w" }
    }
}
# WebView2 de Teams clasico (si quedo en %APPDATA%)
$classicWebView = Join-Path $classicData 'EBWebView'
if (Test-PathSafe $classicWebView) { Remove-ItemSafe -Path $classicWebView -Label 'WebView2 (Teams clasico)' }

# ============================================================================
#  FASE 4 - TOKENS WAM / TOKENBROKER
# ============================================================================
Write-Section 'FASE 4 - Tokens de autenticacion (WAM / TokenBroker)'

# Cache de TokenBroker: borrar SOLO el contenido de la cache (seguro, se regenera)
$tokenBrokerCache = Join-Path $env:LOCALAPPDATA 'Microsoft\TokenBroker\Cache'
Remove-ItemSafe -Path $tokenBrokerCache -ContentsOnly -Label 'TokenBroker\Cache'

if ($Aggressive) {
    Write-Log 'Reset profundo de WAM (Microsoft.AAD.BrokerPlugin): cierra la sesion de TODAS las apps.' 'WARN'
    $aadBroker = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy'
    if (Test-PathSafe $aadBroker) {
        foreach ($sub in 'LocalState','AC\TokenBroker','TempState') {
            Remove-ItemSafe -Path (Join-Path $aadBroker $sub) -ContentsOnly -Label "WAM BrokerPlugin: $sub"
        }
        Write-Log 'Tras el reset de WAM se RECOMIENDA reiniciar el equipo.' 'WARN'
    }
}

# ============================================================================
#  FASE 5 - PILA DE IDENTIDAD (IdentityCRL / OneAuth)
# ============================================================================
Write-Section 'FASE 5 - Cache de identidad de Microsoft (IdentityCRL / OneAuth)'

# OneAuth: pila de autenticacion unificada moderna (Office/Teams). Causa frecuente de bloqueo.
Remove-ItemSafe -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\OneAuth') -ContentsOnly -Label 'OneAuth'
# IdentityCRL: cache clasica de identidad MSA/AAD
Remove-ItemSafe -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\IdentityCRL') -ContentsOnly -Label 'IdentityCRL (datos)'
Remove-RegistryKeySafe -KeyPath 'HKCU\Software\Microsoft\IdentityCRL' -Label 'IdentityCRL (registro)'

# ============================================================================
#  FASE 6 - ADMINISTRADOR DE CREDENCIALES DE WINDOWS
# ============================================================================
Write-Section 'FASE 6 - Credenciales atascadas (Administrador de credenciales)'

# Listar credenciales con cmdkey (rapido y fiable) y respaldar la lista
$credRaw = Invoke-Native 'cmdkey.exe' @('/list')
try { Set-Content -LiteralPath (Join-Path $script:BackupDir 'credentials_before.txt') -Value $credRaw -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}

# Patrones de credenciales relacionadas con Teams / Office / autenticacion AAD-MSA
$credPatterns = @(
    'msteams', 'MSTeams', 'Teams',
    'MicrosoftOffice16', 'Office',
    'Microsoft_AAD', 'MicrosoftAccount',
    'login.microsoftonline.com', 'login.windows.net',
    'office.com', 'officeapps',
    'adalsso', 'OneDrive', 'msft.sts', 'enterpriseregistration'
)
if ($Aggressive) {
    # Credenciales SSO/MSA mas amplias (afectan a mas apps; usar solo en modo agresivo)
    $credPatterns += @('virtualapp/didlogical', 'SSO_POP_Device', 'WindowsLive', 'MicrosoftAccount:target')
}

# Extraer los destinos de la salida de cmdkey.
# IMPORTANTE: la etiqueta esta LOCALIZADA (ES "Destino:", EN "Target:", etc.). Se cubren
# varios idiomas y, ademas, un metodo de respaldo independiente del idioma que detecta el
# valor por su contenido (prefijos de namespace o "target=").
$targets = New-Object System.Collections.Generic.List[string]
$seen    = @{}
foreach ($line in ($credRaw -split "`r?`n")) {
    $t = $line.Trim()
    if ($t -eq '') { continue }
    $value = $null

    # 1) Por etiqueta localizada (EN/ES/FR/DE/IT/PT)
    $m = [regex]::Match($t, '^(?:Target|Destino|Cible|Ziel|Destinazione|Alvo|Obiettivo)\s*:\s*(.+)$', 'IgnoreCase')
    if ($m.Success) {
        $value = $m.Groups[1].Value.Trim()
    } else {
        # 2) Respaldo por contenido (independiente del idioma)
        $m2 = [regex]::Match($t, '^[^:]+:\s*(.+)$')
        if ($m2.Success) {
            $cand = $m2.Groups[1].Value.Trim()
            if ($cand -match '(?i)(target=|LegacyGeneric|WindowsLive|^Domain:|MicrosoftAccount|Microsoft_AAD|MicrosoftOffice|msteams)') {
                $value = $cand
            }
        }
    }

    if ($value -and -not $seen.ContainsKey($value)) {
        $seen[$value] = $true
        [void]$targets.Add($value)
    }
}

if ($targets.Count -eq 0) {
    Write-Log 'No se encontraron credenciales almacenadas (o cmdkey no devolvio datos).' 'INFO'
} else {
    $delCount = 0
    foreach ($tgt in $targets) {
        $match = $false
        foreach ($p in $credPatterns) {
            if ($tgt -like "*$p*") { $match = $true; break }
        }
        if (-not $match) { continue }

        if ($script:DryRun) {
            Write-Log "[SIMULACION] Se eliminaria credencial: $tgt" 'DRYRUN'
            $delCount++
            continue
        }
        # Deteccion de exito por CODIGO DE SALIDA (independiente del idioma de Windows).
        # Se prueban dos formas de destino: la completa y la version sin el prefijo de tipo
        # (p.ej. 'LegacyGeneric:target='), porque segun el tipo de credencial cmdkey espera
        # una u otra.
        $null = Invoke-Native 'cmdkey.exe' @("/delete:$tgt")
        $ok   = ($LASTEXITCODE -eq 0)
        $usedTarget = $tgt
        if (-not $ok) {
            $alt = $tgt -replace '^[^:]+:target=', ''
            if ($alt -ne $tgt) {
                $null = Invoke-Native 'cmdkey.exe' @("/delete:$alt")
                $ok = ($LASTEXITCODE -eq 0)
                if ($ok) { $usedTarget = $alt }
            }
        }
        if ($ok) {
            Write-Log "Credencial eliminada: $usedTarget" 'OK'
            $script:Stats.Removed++
            $delCount++
        } else {
            Write-Log "No se pudo eliminar (o requiere otro metodo): $tgt" 'WARN'
        }
    }
    if ($delCount -eq 0) { Write-Log 'Ninguna credencial coincidio con los patrones de Teams/Office.' 'INFO' }
}

# ============================================================================
#  FASE 7 - IDENTIDAD DE OFFICE / MICROSOFT 365 (registro)
# ============================================================================
Write-Section 'FASE 7 - Identidad de Office / Microsoft 365'

# Se respalda y se eliminan SOLO las subclaves de identidad/sesion.
# NO se tocan las claves de licencia/activacion de Office.
$officeIdentity = 'HKCU\Software\Microsoft\Office\16.0\Common\Identity'
if (Test-PathSafe (ConvertTo-ProviderPath $officeIdentity)) {
    Backup-RegistryKey -KeyPath $officeIdentity | Out-Null
    Remove-RegistryKeySafe -KeyPath "$officeIdentity\Identities" -Label 'Office Identity\Identities'
    Remove-RegistryKeySafe -KeyPath "$officeIdentity\Profiles"   -Label 'Office Identity\Profiles'
} else {
    Write-Log 'No hay clave de identidad de Office 16.0 (omitido).' 'INFO'
    $script:Stats.Skipped++
}

# ============================================================================
#  FASE 8 - CLAVES DE REGISTRO DE TEAMS
# ============================================================================
Write-Section 'FASE 8 - Claves de registro de Teams'

Remove-RegistryKeySafe -KeyPath 'HKCU\Software\Microsoft\Office\Teams' -Label 'Office\Teams'
# Politica/estado de autostart que a veces queda inconsistente (se respalda)
$teamsAddin = 'HKCU\Software\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect'
if (Test-PathSafe (ConvertTo-ProviderPath $teamsAddin)) {
    Write-Log 'Complemento de Teams para Outlook detectado (no se elimina; informativo).' 'INFO'
}

# ============================================================================
#  FASE 9 - ARCHIVOS TEMPORALES DE TEAMS
# ============================================================================
Write-Section 'FASE 9 - Archivos temporales de Teams'

$tempRoot = $env:TEMP
if (Test-PathSafe $tempRoot) {
    try {
        $tmpItems = Get-ChildItem -LiteralPath $tempRoot -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match '(?i)teams|squirrel|webview' }
        if ($tmpItems) {
            foreach ($it in $tmpItems) { Remove-ItemSafe -Path $it.FullName -Label "Temp: $($it.Name)" }
        } else {
            Write-Log 'Sin temporales de Teams en %TEMP%.' 'INFO'
        }
    } catch {
        Write-Log "No se pudieron enumerar temporales: $($_.Exception.Message)" 'WARN'
    }
}

# ============================================================================
#  FASE 10 - HIGIENE DE RED Y HORA
# ============================================================================
Write-Section 'FASE 10 - Red y hora del sistema'

# Vaciar cache DNS (no requiere admin)
if ($script:DryRun) {
    Write-Log '[SIMULACION] Se vaciaria la cache DNS (ipconfig /flushdns).' 'DRYRUN'
} else {
    $dns = Invoke-Native 'ipconfig.exe' @('/flushdns')
    if ($dns -match 'correctamente|successfully|vaciado|flushed') { Write-Log 'Cache DNS vaciada.' 'OK' }
    else { Write-Log 'Comando de vaciado DNS ejecutado.' 'INFO' }
}

# Sincronizar hora (requiere admin + servicio de hora). Se omite con aviso si no hay permisos.
if ($isAdmin) {
    if ($script:DryRun) {
        Write-Log '[SIMULACION] Se intentaria sincronizar la hora (w32tm /resync).' 'DRYRUN'
    } else {
        try { Start-Service -Name 'w32time' -ErrorAction SilentlyContinue } catch {}
        $sync = Invoke-Native 'w32tm.exe' @('/resync')
        if ($sync) { Write-Log "Sincronizacion de hora: $($sync.Trim())" 'INFO' }
    }
} else {
    Write-Log 'Sincronizacion de hora omitida (requiere administrador). Verifica que la hora sea correcta.' 'INFO'
}

# ============================================================================
#  FASE 11 - REPARACION / RE-REGISTRO DE TEAMS NUEVO (opcional)
# ============================================================================
if ($RepairTeams) {
    Write-Section 'FASE 11 - Reparacion del paquete de Teams nuevo'
    if ($script:HasNewTeams) {
        if ($script:DryRun) {
            Write-Log '[SIMULACION] Se re-registraria el paquete MSTeams (Add-AppxPackage -Register).' 'DRYRUN'
        } else {
            try {
                $pkg = Get-AppxPackage -Name 'MSTeams' -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($pkg -and $pkg.InstallLocation) {
                    $manifest = Join-Path $pkg.InstallLocation 'AppxManifest.xml'
                    if (Test-PathSafe $manifest) {
                        Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop
                        Write-Log 'Paquete de Teams nuevo re-registrado correctamente.' 'OK'
                    } else {
                        Write-Log 'No se encontro AppxManifest.xml del paquete.' 'WARN'
                    }
                } else {
                    Write-Log 'No se pudo localizar la ruta de instalacion del paquete.' 'WARN'
                }
            } catch {
                Write-Log "Fallo al re-registrar Teams: $($_.Exception.Message)" 'WARN'
                Write-Log 'Alternativa: reinstalar con teamsbootstrapper.exe -p o desde Microsoft Store.' 'INFO'
            }
        }
    } else {
        Write-Log 'Teams nuevo no esta instalado. Para instalarlo: teamsbootstrapper.exe -p (requiere admin) o Microsoft Store.' 'INFO'
    }
}

# ============================================================================
#  RESUMEN FINAL
# ============================================================================
Write-Section 'RESUMEN'
Write-Log ("Elementos eliminados/limpiados : {0}" -f $script:Stats.Removed)  'INFO'
Write-Log ("Elementos omitidos (no existian): {0}" -f $script:Stats.Skipped) 'INFO'
Write-Log ("Avisos                         : {0}" -f $script:Stats.Warnings) 'INFO'
Write-Log ("Errores controlados            : {0}" -f $script:Stats.Errors)   'INFO'
Write-Log "Log y copias de seguridad en: $script:BackupDir" 'OK'

if ($script:DryRun) {
    Write-Log 'SIMULACION finalizada. No se cambio nada. Ejecuta sin -DryRun para aplicar.' 'DRYRUN'
} else {
    Write-Log 'Reparacion finalizada.' 'OK'
    Write-Log 'PASOS SIGUIENTES:' 'STEP'
    Write-Log '  1) REINICIA el equipo (recomendado, sobre todo si usaste -Aggressive).' 'INFO'
    Write-Log '  2) Abre Microsoft Teams e inicia sesion de nuevo.' 'INFO'
    Write-Log '  3) Si sigue atascado, vuelve a ejecutar con -Aggressive -RepairTeams.' 'INFO'
}

if ($script:Transcript) { try { Stop-Transcript | Out-Null } catch {} }
