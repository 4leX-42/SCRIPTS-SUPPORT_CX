<#
.SYNOPSIS
    Limpia la cuenta de trabajo cacheada de un tenant antiguo en el EQUIPO DEL USUARIO
    y verifica que el UPN correcto resuelve al tenant esperado.

.DESCRIPTION
    Caso de uso: un dominio (p.ej. invabpo.com) se movio de un tenant a otro. Entra
    reescribio el UPN de la cuenta del tenant viejo a <objectId>@<dominioInicial>, y el
    equipo del usuario sigue ofreciendo ese tile GUID al iniciar sesion.

    Este script se ejecuta EN EL EQUIPO DEL USUARIO AFECTADO, con su sesion de Windows y
    SIN admin. NO toca el tenant ni usa lib\AndersenLab.psm1 (el equipo destino no tiene
    ni el modulo ni el certificado): solo consulta endpoints publicos de login para verificar.

    Todo lo que borra se respalda antes en el Escritorio: claves de registro exportadas a
    .reg y carpetas de cache MOVIDAS (no eliminadas). Reversible.

    Lo que NO hace por defecto:
      - dsregcmd /leave  -> tras -QuitarWorkplaceJoin, y aborta si AzureAdJoined = YES.
      - borrar cookies del navegador -> tras -BorrarCookiesEdge (borra TODAS las de Edge).

.PARAMETER Upn
    UPN correcto del usuario en el tenant nuevo.

.PARAMETER TenantViejo
    Dominio inicial del tenant del que procede el tile GUID (p.ej. contoso.onmicrosoft.com).

.PARAMETER TenantEsperado
    federationBrandName que debe devolver getUserRealm para el UPN. Por defecto 'Andersen'.

.PARAMETER RutaRespaldo
    Carpeta donde dejar el respaldo y el log. Por defecto el Escritorio; si no es
    escribible (tipico cuando esta redirigido a un OneDrive averiado) se cae solo a
    %USERPROFILE%\Desktop, luego %LOCALAPPDATA%\LimpiezaCuenta y por ultimo %TEMP%.

.PARAMETER DryRun
    Simula: enumera todo lo que tocaria sin cambiar nada.

.EXAMPLE
    .\Reset-CachedWorkAccount.ps1 -Upn usuario@invabpo.com -TenantViejo invataxlegal.onmicrosoft.com -DryRun

.EXAMPLE
    .\Reset-CachedWorkAccount.ps1 -Upn usuario@invabpo.com -TenantViejo invataxlegal.onmicrosoft.com -Force
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Upn,
    [Parameter(Mandatory)][string]$TenantViejo,
    [string]$TenantEsperado = 'Andersen',
    [string]$RutaRespaldo,
    [switch]$DryRun,
    [switch]$NoCerrarApps,
    [switch]$BorrarCookiesEdge,
    [switch]$QuitarWorkplaceJoin,
    [switch]$IgnorarPerfil,
    [switch]$Force
)

$ErrorActionPreference = 'Continue'

# Windows PowerShell 5.1 negocia TLS 1.0 por defecto; login.microsoftonline.com exige 1.2.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

$sello = Get-Date -Format 'yyyyMMdd-HHmm'

# El Escritorio suele estar redirigido a OneDrive (Known Folder Move). Si OneDrive
# esta en mal estado -que es justo el sintoma que trae aqui al usuario- la carpeta
# no admite escritura y el script moria antes de empezar. Se prueban varias raices
# y se usa la primera donde se pueda crear un fichero de verdad.
function Test-RaizEscribible([string]$raiz) {
    if ([string]::IsNullOrWhiteSpace($raiz)) { return $false }
    try {
        if (-not (Test-Path $raiz)) { New-Item -ItemType Directory -Path $raiz -Force -ErrorAction Stop | Out-Null }
        $sonda = Join-Path $raiz ".w$([Guid]::NewGuid().ToString('N').Substring(0,8))"
        Set-Content -Path $sonda -Value 'x' -ErrorAction Stop
        Remove-Item $sonda -Force -ErrorAction SilentlyContinue
        return $true
    } catch { return $false }
}

$candidatas = @()
if ($RutaRespaldo) { $candidatas += $RutaRespaldo }
$candidatas += @(
    [Environment]::GetFolderPath('Desktop')
    (Join-Path $env:USERPROFILE 'Desktop')
    (Join-Path $env:LOCALAPPDATA 'LimpiezaCuenta')
    $env:TEMP
)

$raizElegida = $null
foreach ($c in $candidatas) {
    if (Test-RaizEscribible $c) { $raizElegida = $c; break }
    if ($c) { Write-Host "  raiz no escribible, se descarta: $c" -ForegroundColor DarkYellow }
}

if (-not $raizElegida) {
    Write-Host 'ABORTADO: no hay ninguna carpeta donde escribir el respaldo.' -ForegroundColor Red
    Write-Host 'Relanza indicando una ruta valida, p.ej. -RutaRespaldo C:\Temp' -ForegroundColor Yellow
    return
}
if ($RutaRespaldo -and $raizElegida -ne $RutaRespaldo) {
    Write-Host "AVISO: -RutaRespaldo '$RutaRespaldo' no es escribible. Se usa: $raizElegida" -ForegroundColor Yellow
}

$backup = Join-Path $raizElegida "limpieza-cuenta-$sello"
$log    = Join-Path $backup 'limpieza.log'
if (-not $DryRun) { New-Item -ItemType Directory -Path $backup -Force | Out-Null }

function Reg([string]$m, [string]$c = 'Gray') {
    Write-Host $m -ForegroundColor $c
    if (-not $DryRun) {
        Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) -Encoding utf8 -ErrorAction SilentlyContinue
    }
}

Reg "=== Limpieza de cuenta cacheada - $(Get-Date -Format 'yyyy-MM-dd HH:mm') ===" Cyan
Reg "UPN destino .......: $Upn"
Reg "Tenant a purgar ...: $TenantViejo"
Reg "Perfil que se limpia: $env:USERPROFILE"
Reg "Modo ..............: $(if($DryRun){'SIMULACION (no cambia nada)'}else{'APLICAR'})" $(if ($DryRun) { 'Yellow' } else { 'Green' })
Reg "Respaldo ..........: $backup"
Reg ''

# --- 0. Comprobacion de perfil ----------------------------------------------
# Si la consola se abrio con "Ejecutar como administrador" usando OTRA cuenta,
# HKCU y %LOCALAPPDATA% apuntan al perfil del administrador y el script limpia
# el perfil equivocado: sale todo "no existe" y el problema sigue igual.
$yo = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$duenoSesion = $null
try {
    $expl = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop | Select-Object -First 1
    if ($expl) {
        $o = Invoke-CimMethod -InputObject $expl -MethodName GetOwner -ErrorAction Stop
        if ($o.User) { $duenoSesion = "$($o.Domain)\$($o.User)" }
    }
} catch { }

Reg '--- 0. Perfil sobre el que se va a actuar ---' Cyan
Reg "  ejecutando como ....: $yo"
Reg "  sesion interactiva ..: $(if ($duenoSesion) { $duenoSesion } else { 'no detectada' })"

if ($duenoSesion -and $yo -ne $duenoSesion) {
    Reg ''
    Reg "  ABORTADO: se esta ejecutando como '$yo' pero la sesion de Windows es de '$duenoSesion'." Red
    Reg "  HKCU y %LOCALAPPDATA% son los de '$yo', no los del usuario afectado." Red
    Reg '  Cierra esta consola y abre PowerShell SIN "Ejecutar como administrador",' Red
    Reg '  con la sesion del usuario afectado. Este script no necesita permisos de admin.' Red
    Reg "  Si aun asi quieres limpiar el perfil '$yo', relanza con -IgnorarPerfil." Yellow
    if (-not $IgnorarPerfil) { return }
    Reg '  -IgnorarPerfil indicado: se continua bajo tu responsabilidad.' Yellow
}
Reg ''

# --- 0b. Confirmacion -------------------------------------------------------
if (-not $DryRun -and -not $Force) {
    $ok = Read-Host 'Se cerraran Office/Teams/OneDrive/navegadores y se limpiaran credenciales cacheadas. Escribe SI para continuar'
    if ($ok -notmatch '^(SI|S|YES|Y)$') { Reg 'Cancelado por el usuario.' Yellow; return }
}

# --- 1. Estado previo -------------------------------------------------------
Reg '--- 1. Estado previo del dispositivo ---' Cyan
$dsreg  = (dsregcmd /status) 2>$null
$estado = @{}
foreach ($k in 'AzureAdJoined', 'EnterpriseJoined', 'DomainJoined', 'WorkplaceJoined', 'TenantId', 'TenantName') {
    $m = $dsreg | Select-String -Pattern ("^\s*{0}\s*:\s*(.+)$" -f $k) | Select-Object -First 1
    if ($m) { $estado[$k] = $m.Matches[0].Groups[1].Value.Trim(); Reg ("  {0,-18}: {1}" -f $k, $estado[$k]) }
}

# --- 2. Cerrar aplicaciones -------------------------------------------------
Reg ''
Reg '--- 2. Cerrando aplicaciones que retienen el token ---' Cyan
$procs = 'OUTLOOK', 'olk', 'ms-teams', 'Teams', 'OneDrive', 'WINWORD', 'EXCEL', 'POWERPNT',
         'ONENOTE', 'MSACCESS', 'MSPUB', 'lync', 'msedge', 'chrome', 'firefox', 'MSOSYNC', 'ONEDRIVEUPDATER'
if (-not $NoCerrarApps) {
    foreach ($p in $procs) {
        $vivos = Get-Process -Name $p -ErrorAction SilentlyContinue
        if ($vivos) {
            Reg "  cerrando $p ($($vivos.Count) proceso/s)" Yellow
            if (-not $DryRun) { $vivos | Stop-Process -Force -ErrorAction SilentlyContinue }
        }
    }
    if (-not $DryRun) { Start-Sleep -Seconds 3 }
} else { Reg '  omitido (-NoCerrarApps)' }

# --- 3. Identidades de Office en el registro --------------------------------
Reg ''
Reg '--- 3. Identidades de Office en el registro ---' Cyan
$claves = @(
    'HKCU\Software\Microsoft\Office\16.0\Common\Identity',
    'HKCU\Software\Microsoft\Office\Common\Identity',
    'HKCU\Software\Microsoft\Office\16.0\Common\Roaming\Identities',
    'HKCU\Software\Microsoft\Office\16.0\Common\ServicesManagerCache',
    'HKCU\Software\Microsoft\Office\16.0\Common\Internet\WebServiceCache',
    'HKCU\Software\Microsoft\Office\16.0\Common\Licensing',
    'HKCU\Software\Microsoft\IdentityCRL',
    'HKCU\Software\Microsoft\OneDrive\Accounts\Business1'
)

# Diagnostico: que identidades hay cacheadas ahora mismo (de aqui sale el tile)
$identidades = 'Registry::HKCU\Software\Microsoft\Office\16.0\Common\Identity\Identities'
if (Test-Path $identidades) {
    Reg '  identidades cacheadas encontradas:' Yellow
    Get-ChildItem $identidades -ErrorAction SilentlyContinue |
        ForEach-Object { Reg ("    - {0}" -f (Split-Path $_.Name -Leaf)) Yellow }
} else { Reg '  no hay identidades de Office cacheadas en este perfil' }

foreach ($c in $claves) {
    $ps = 'Registry::' + $c
    if (Test-Path $ps) {
        $file = Join-Path $backup (($c -replace '[\\:]', '_') + '.reg')
        Reg "  respaldando y borrando: $c" Yellow
        if (-not $DryRun) {
            & reg.exe export $c $file /y | Out-Null
            Remove-Item -Path $ps -Recurse -Force -ErrorAction SilentlyContinue
        }
    } else { Reg "  no existe: $c" }
}

# --- 4. Administrador de credenciales de Windows ----------------------------
Reg ''
Reg '--- 4. Credenciales cacheadas (cmdkey) ---' Cyan
$patrones = 'MicrosoftOffice', 'msteams', 'OneDrive', 'MicrosoftAccount', 'virtualapp/didlogical',
            'SSO_POP_Device', 'login.microsoftonline', 'login.windows.net', 'office', 'WindowsLive'
$lineas  = (cmdkey /list) 2>$null
$targets = foreach ($l in $lineas) { if ($l -match '^\s*(Target|Destino)\s*:\s*(.+?)\s*$') { $Matches[2] } }
$aBorrar = $targets | Where-Object { $t = $_; $patrones | Where-Object { $t -like "*$_*" } } | Select-Object -Unique
if (-not $aBorrar) { Reg '  nada que borrar' }
else {
    if (-not $DryRun) {
        ($aBorrar | Out-String).Trim() | Set-Content (Join-Path $backup 'credenciales-borradas.txt') -Encoding utf8 -ErrorAction SilentlyContinue
    }
    foreach ($t in $aBorrar) {
        Reg "  borrando credencial: $t" Yellow
        if (-not $DryRun) { & cmdkey.exe /delete:"$t" | Out-Null }
    }
}

# --- 5. Caches de token (WAM / OneAuth / IdentityCache) ---------------------
Reg ''
Reg '--- 5. Caches de token ---' Cyan
$carpetas = @(
    "$env:LOCALAPPDATA\Microsoft\IdentityCache",
    "$env:LOCALAPPDATA\Microsoft\OneAuth",
    "$env:LOCALAPPDATA\Microsoft\TokenBroker\Cache",
    "$env:LOCALAPPDATA\Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy\AC\TokenBroker\Accounts",
    "$env:LOCALAPPDATA\Microsoft\Office\16.0\Licensing",
    "$env:LOCALAPPDATA\Microsoft\Office\Licenses",
    "$env:LOCALAPPDATA\Microsoft\OneDrive\settings\Business1",
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\PerfCache",
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView"
)
foreach ($f in $carpetas) {
    if (Test-Path $f) {
        $dest = Join-Path $backup (Split-Path (Split-Path $f -Parent) -Leaf)
        Reg "  moviendo a respaldo: $f" Yellow
        if (-not $DryRun) {
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
            try { Move-Item -Path $f -Destination (Join-Path $dest (Split-Path $f -Leaf)) -Force -ErrorAction Stop }
            catch {
                Copy-Item $f (Join-Path $dest (Split-Path $f -Leaf)) -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item $f -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    } else { Reg "  no existe: $f" }
}

# --- 6. Navegador -----------------------------------------------------------
Reg ''
Reg '--- 6. Navegador ---' Cyan
if ($BorrarCookiesEdge) {
    $cookies = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Network\Cookies"
    if (Test-Path $cookies) {
        Reg '  ATENCION: borrando TODAS las cookies de Edge (perfil Default)' Red
        if (-not $DryRun) {
            Copy-Item $cookies (Join-Path $backup 'Edge-Cookies.bak') -Force -ErrorAction SilentlyContinue
            Remove-Item $cookies -Force -ErrorAction SilentlyContinue
        }
    } else { Reg '  no se encontro el fichero de cookies de Edge' }
} else { Reg '  cookies intactas. Se abrira el logout de Microsoft en InPrivate al final.' }

# --- 7. Registro del dispositivo (opcional) --------------------------------
Reg ''
Reg '--- 7. Registro del dispositivo ---' Cyan
if ($QuitarWorkplaceJoin) {
    if ($estado['AzureAdJoined'] -eq 'YES') {
        Reg '  ABORTADO: el equipo esta unido a Entra (AzureAdJoined = YES).' Red
        Reg '  dsregcmd /leave lo sacaria del dominio. No se ejecuta.' Red
    } elseif ($estado['WorkplaceJoined'] -eq 'YES') {
        Reg '  ejecutando dsregcmd /leave (quita solo el registro de usuario)' Yellow
        if (-not $DryRun) { & dsregcmd.exe /leave | Out-Null }
    } else { Reg '  no hay WorkplaceJoin que quitar' }
} else {
    Reg "  omitido. WorkplaceJoined = $($estado['WorkplaceJoined']); AzureAdJoined = $($estado['AzureAdJoined'])"
    if ($estado['WorkplaceJoined'] -eq 'YES' -and $estado['AzureAdJoined'] -ne 'YES') {
        Reg '  HAY una cuenta de trabajo registrada. Quitarla a mano en:' Yellow
        Reg '  Configuracion > Cuentas > Acceso a trabajo o escuela > Desconectar' Yellow
    }
}

# ============================ VERIFICACION =================================
Reg ''
Reg '=== VERIFICACION ===' Cyan

Reg '--- Identidades de Office restantes ---'
$rest = $claves | Where-Object { Test-Path ('Registry::' + $_) }
if ($rest) { $rest | ForEach-Object { Reg "  QUEDA: $_" Red } } else { Reg '  OK: ninguna' Green }

Reg '--- Credenciales restantes ---'
$lineas2 = (cmdkey /list) 2>$null
$t2 = foreach ($l in $lineas2) { if ($l -match '^\s*(Target|Destino)\s*:\s*(.+?)\s*$') { $Matches[2] } }
$q  = $t2 | Where-Object { $x = $_; $patrones | Where-Object { $x -like "*$_*" } } | Select-Object -Unique
if ($q) { $q | ForEach-Object { Reg "  QUEDA: $_" Red } } else { Reg '  OK: ninguna de Office/Teams/OneDrive' Green }

Reg '--- Caches de token restantes ---'
$c2 = $carpetas | Where-Object { Test-Path $_ }
if ($c2) { $c2 | ForEach-Object { Reg "  QUEDA: $_" Yellow } } else { Reg '  OK: todas movidas' Green }

Reg '--- Resolucion del UPN en el servicio (getUserRealm) ---'
try {
    $realm = Invoke-RestMethod "https://login.microsoftonline.com/getuserrealm.srf?login=$Upn&json=1" -TimeoutSec 20
    Reg ("  Login .............: {0}" -f $realm.Login)
    Reg ("  DomainName ........: {0}" -f $realm.DomainName)
    Reg ("  NameSpaceType .....: {0}" -f $realm.NameSpaceType)
    Reg ("  FederationBrandName: {0}" -f $realm.FederationBrandName) $(if ($realm.FederationBrandName -eq $TenantEsperado) { 'Green' } else { 'Red' })
    if ($realm.FederationBrandName -eq $TenantEsperado) { Reg "  OK: el UPN resuelve al tenant $TenantEsperado." Green }
    else { Reg "  AVISO: no resuelve a $TenantEsperado. Revisar el dominio en el tenant." Red }
} catch { Reg "  no se pudo consultar: $($_.Exception.Message)" Red }

Reg '--- Tenant viejo ---'
try {
    $old = Invoke-RestMethod "https://login.microsoftonline.com/$TenantViejo/v2.0/.well-known/openid-configuration" -TimeoutSec 20
    Reg ("  {0} sigue existiendo como tenant independiente: {1}" -f $TenantViejo, $old.issuer) Yellow
    Reg '  La cuenta GUID vive alli. Si reaparece el tile, hay que deshabilitarla en ESE tenant.' Yellow
} catch { Reg "  $TenantViejo ya no resuelve." Green }

# --- Cierre de sesion web + prueba -----------------------------------------
Reg ''
Reg '--- Abriendo logout y login limpio en InPrivate ---' Cyan
if (-not $DryRun) {
    $edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    if (-not (Test-Path $edge)) { $edge = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe" }
    if (Test-Path $edge) {
        Start-Process $edge -ArgumentList '--inprivate', 'https://login.microsoftonline.com/logout.srf'
        Start-Sleep -Seconds 4
        Start-Process $edge -ArgumentList '--inprivate', "https://outlook.office.com/mail/?login_hint=$Upn"
    } else {
        Start-Process 'https://login.microsoftonline.com/logout.srf'
        Start-Process "https://outlook.office.com/mail/?login_hint=$Upn"
    }
}

Reg ''
Reg "=== FIN. Log y respaldo en: $backup ===" Cyan
Reg "Siguiente paso manual: entrar escribiendo el UPN completo -> $Upn" Green
Reg "Si el tile GUID vuelve a aparecer: la cuenta sigue activa en el tenant $TenantViejo." Yellow
