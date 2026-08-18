<#
.SYNOPSIS
    Limpia credenciales y cuentas cacheadas de Microsoft Teams / Office en Windows 11.

.DESCRIPTION
    Cierra las aplicaciones de Microsoft y elimina:
      - Cache de Teams (version nueva MSTeams y clasica)
      - IdentityCache  (%LOCALAPPDATA%\Microsoft\IdentityCache)
      - OneAuth        (%LOCALAPPDATA%\Microsoft\OneAuth)
      - Identidades de Office en el registro (HKCU Office Identity)
      - Tokens WAM / SSO (TokenBroker del AAD.BrokerPlugin)  -> causa principal de
        "cuentas que salen iniciadas solas"
      - Credenciales de Microsoft en el Administrador de credenciales (cmdkey)

    Solo afecta al USUARIO ACTUAL. No requiere admin. No toca la union a dominio
    ni "Acceso a trabajo o escuela".

.PARAMETER KeepWAM
    No borra los tokens WAM (TokenBroker). Usalo si NO quieres que otras apps
    Microsoft (Outlook, OneDrive, Office) pidan login otra vez.

.PARAMETER NoStop
    No cierra las aplicaciones automaticamente (cierralas tu antes).

.PARAMETER NoPause
    No espera ENTER al terminar (modo desatendido).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Limpiar-CuentasMicrosoft.ps1

.EXAMPLE
    .\Limpiar-CuentasMicrosoft.ps1 -KeepWAM

.NOTES
    Autor: IT
    Doble click: usa el .bat incluido (Limpiar-CuentasMicrosoft.bat).
#>
[CmdletBinding()]
param(
    [switch]$KeepWAM,
    [switch]$NoStop,
    [switch]$NoPause
)

# ---------------------------------------------------------------------------
# Auto-relanzar con ExecutionPolicy Bypass si la politica actual lo bloquea
# (permite usar "Ejecutar con PowerShell" aunque la politica sea Restricted)
# ---------------------------------------------------------------------------
if ((Get-ExecutionPolicy) -in @('Restricted','AllSigned') -and -not $env:__MSCLEAN_RELAUNCHED) {
    $env:__MSCLEAN_RELAUNCHED = '1'
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    if ($KeepWAM) { $argList += '-KeepWAM' }
    if ($NoStop)  { $argList += '-NoStop' }
    if ($NoPause) { $argList += '-NoPause' }
    Start-Process powershell.exe -ArgumentList $argList
    return
}

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

# Estado / contadores -------------------------------------------------------
$script:Removed = 0
$script:Missing = 0
$script:Failed  = 0
$script:Creds   = 0
$LogFile = Join-Path $env:TEMP ("LimpiarCuentasMS_{0}.log" -f (Get-Process -Id $PID).StartTime.ToString('yyyyMMdd_HHmmss'))

function Write-Title($text) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor DarkCyan
    Write-Host "  $text" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor DarkCyan
}

function Log($text) { Add-Content -Path $LogFile -Value $text -ErrorAction SilentlyContinue }

# Borra una ruta de fichero o clave de registro, con reporte ----------------
function Remove-Target {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label
    )
    $target = $Path
    $exists = Test-Path -LiteralPath ($Path -replace '\\\*$','')   # comprueba la carpeta padre
    if (-not $exists) {
        Write-Host "  [--] No existe   : $Label" -ForegroundColor DarkGray
        Log "MISSING: $Label ($Path)"
        $script:Missing++
        return
    }
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        Write-Host "  [OK] Borrado     : $Label" -ForegroundColor Green
        Log "REMOVED: $Label ($Path)"
        $script:Removed++
    }
    catch {
        # Reintento sin LiteralPath (rutas con comodin)
        Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path ($Path -replace '\\\*$','')) {
            # comprobar si quedo contenido
            $rest = Get-ChildItem ($Path -replace '\\\*$','') -Force -ErrorAction SilentlyContinue
            if ($rest) {
                Write-Host "  [!!] Parcial     : $Label (algun fichero en uso)" -ForegroundColor Yellow
                Log "PARTIAL: $Label ($Path) :: $($_.Exception.Message)"
                $script:Failed++
                return
            }
        }
        Write-Host "  [OK] Borrado     : $Label" -ForegroundColor Green
        Log "REMOVED(retry): $Label ($Path)"
        $script:Removed++
    }
}

# Cierra las apps Microsoft de forma ordenada y luego forzada ---------------
function Stop-MicrosoftApps {
    $names = @(
        'Teams','ms-teams','msteams',
        'OUTLOOK','WINWORD','EXCEL','POWERPNT','ONENOTE','MSACCESS','MSPUB','VISIO','WINPROJ',
        'Lync','OneDrive'
    )
    $procs = Get-Process -Name $names -ErrorAction SilentlyContinue
    if (-not $procs) {
        Write-Host "  No hay aplicaciones Microsoft abiertas." -ForegroundColor DarkGray
        return
    }
    Write-Host ("  Cerrando {0} proceso(s)..." -f $procs.Count) -ForegroundColor Yellow
    # 1) intento limpio
    foreach ($p in $procs) { try { $p.CloseMainWindow() | Out-Null } catch {} }
    # esperar hasta 5s a que cierren solos
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Milliseconds 500
        if (-not (Get-Process -Name $names -ErrorAction SilentlyContinue)) { break }
    }
    # 2) forzar lo que quede
    Get-Process -Name $names -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    Write-Host "  Aplicaciones cerradas." -ForegroundColor Green
}

# Borra credenciales Microsoft del Administrador de credenciales -------------
function Clear-MicrosoftCredentials {
    $pattern = 'msteams|OneAuth|MicrosoftOffice|Office16|office|teams|MicrosoftAccount|login\.windows|login\.microsoftonline|live\.com|MicrosoftLive|WindowsLive|AAD|SSO_POP|Microsoft_'
    $list = cmdkey /list 2>$null
    foreach ($line in $list) {
        if ($line -match 'Target:\s*(.+)$') {
            $t = $matches[1].Trim()
            if ($t -match $pattern) {
                cmdkey /delete:$t 2>$null | Out-Null
                Write-Host "  [OK] $t" -ForegroundColor Green
                Log "CRED REMOVED: $t"
                $script:Creds++
            }
        }
    }
    if ($script:Creds -eq 0) {
        Write-Host "  No habia credenciales Microsoft guardadas." -ForegroundColor DarkGray
    }
}

# ===========================================================================
#  EJECUCION
# ===========================================================================
Clear-Host
Write-Host @"
 +--------------------------------------------------------+
 |   LIMPIEZA DE CUENTAS MICROSOFT / TEAMS - Windows 11   |
 +--------------------------------------------------------+
"@ -ForegroundColor White
Write-Host " Usuario : $env:USERNAME" -ForegroundColor Gray
Write-Host " Log     : $LogFile" -ForegroundColor Gray
if ($KeepWAM) { Write-Host " Modo    : conservar tokens WAM (-KeepWAM)" -ForegroundColor Yellow }
Log "=== INICIO $env:USERNAME ==="

# --- 1. Cerrar apps --------------------------------------------------------
if (-not $NoStop) {
    Write-Title "1/4  Cerrando aplicaciones Microsoft"
    Stop-MicrosoftApps
} else {
    Write-Title "1/4  (omitido) cierre de aplicaciones"
    Write-Host "  Cierra Teams/Office manualmente o los ficheros en uso no se borraran." -ForegroundColor Yellow
}

# --- 2. Cache de Teams -----------------------------------------------------
Write-Title "2/4  Borrando cache de Teams"
Remove-Target "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\*" "Teams nuevo (work/school) - LocalCache"
Remove-Target "$env:APPDATA\Microsoft\Teams\*"                                "Teams clasico"

# --- 3. Identidades / tokens de cuenta -------------------------------------
Write-Title "3/4  Borrando identidades y tokens de cuenta"
Remove-Target "$env:LOCALAPPDATA\Microsoft\IdentityCache\*"                                   "IdentityCache"
Remove-Target "$env:LOCALAPPDATA\Microsoft\OneAuth\*"                                         "OneAuth"
Remove-Target "HKCU:\Software\Microsoft\Office\16.0\Common\Identity\Identities"               "Office - Identidades (registro)"
Remove-Target "HKCU:\Software\Microsoft\Office\16.0\Common\Identity\Profiles"                 "Office - Perfiles (registro)"

if ($KeepWAM) {
    Write-Host "  [--] WAM/TokenBroker  : OMITIDO (-KeepWAM)" -ForegroundColor DarkGray
} else {
    Remove-Target "$env:LOCALAPPDATA\Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy\AC\TokenBroker\Accounts\*" "Tokens WAM / SSO (AAD BrokerPlugin)"
}

# --- 4. Administrador de credenciales --------------------------------------
Write-Title "4/4  Borrando credenciales del Administrador de credenciales"
Clear-MicrosoftCredentials

# --- Resumen ---------------------------------------------------------------
Write-Title "RESUMEN"
Write-Host ("  Rutas borradas      : {0}" -f $script:Removed)  -ForegroundColor Green
Write-Host ("  No existian         : {0}" -f $script:Missing)  -ForegroundColor DarkGray
Write-Host ("  Parciales (en uso)  : {0}" -f $script:Failed)   -ForegroundColor $(if($script:Failed){'Yellow'}else{'DarkGray'})
Write-Host ("  Credenciales borradas: {0}" -f $script:Creds)   -ForegroundColor Green
Log "=== FIN  Removed=$($script:Removed) Missing=$($script:Missing) Failed=$($script:Failed) Creds=$($script:Creds) ==="

Write-Host ""
if ($script:Failed -gt 0) {
    Write-Host " AVISO: hubo borrados parciales (ficheros en uso)." -ForegroundColor Yellow
    Write-Host "        Cierra TODO Office/Teams (o reinicia) y vuelve a ejecutar." -ForegroundColor Yellow
}
Write-Host " LISTO. Abre Teams: deberia pedir login limpio, sin cuentas precargadas." -ForegroundColor Green
if (-not $KeepWAM) {
    Write-Host " (Outlook/OneDrive/Office tambien pediran login de nuevo: es lo esperado.)" -ForegroundColor Gray
}
Write-Host ""
Write-Host " NOTA: si una cuenta de organizacion SIGUE reapareciendo, quitala en:" -ForegroundColor Gray
Write-Host "       Configuracion > Cuentas > Acceso a trabajo o escuela > Desconectar" -ForegroundColor Gray
Write-Host "       (no se automatiza: puede romper la union a Azure AD del equipo)" -ForegroundColor DarkGray

if (-not $NoPause -and $Host.Name -eq 'ConsoleHost') {
    Write-Host ""
    Read-Host " Pulsa ENTER para salir"
}
