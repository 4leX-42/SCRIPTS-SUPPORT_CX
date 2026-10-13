#Requires -Version 5.1

<#
.SYNOPSIS
    [ES] Repara la ventana de inicio de sesion de Microsoft 365 que se queda en blanco o en "Un momento..." al agregar la cuenta en Outlook.
    [EN] Repairs the Microsoft 365 sign-in window that stays blank or stuck on "One moment..." when adding the account in Outlook.
.DESCRIPTION
    La ventana de login de la organizacion no la dibuja Outlook: la abre el broker de
    cuentas de Windows (WAM, paquete Microsoft.AAD.BrokerPlugin). Si ese paquete esta
    mal registrado, su cache web corrupta, WebView2 roto o los CDN del login bloqueados,
    la ventana sale vacia con el "Un momento..." girando para siempre.

    Fase 1 - Diagnostico (siempre, solo lectura):
      - Paquetes Microsoft.AAD.BrokerPlugin, Microsoft.AccountsControl y
        Microsoft.Windows.CloudExperienceHost registrados y en estado Ok.
      - Version de WebView2 Runtime.
      - Servicios TokenBroker, wlidsvc y cloudidsvc.
      - Valores heredados en HKCU\...\Office\16.0\Common\Identity que desactivan WAM.
      - Proxy y acceso HTTPS a login.microsoftonline.com y a los CDN que pintan la pagina.
      - Con la ventana en blanco abierta: DLL de terceros cargadas en el broker y en sus
        procesos WebView2, con su firmante (mismo patron que 10-file-picker).

    Fase 2 - Reparacion (salvo -SoloDiagnostico):
      1. Cierra Outlook y el broker.
      2. Quita DisableAADWAM, DisableADALatopWAMOverride y DisableMSAWAM (backup .reg).
      3. Renombra la cache web del broker (INetCache, INetCookies) a .bak: no cierra sesion.
      4. Con -BorrarCuentasWam, renombra tambien las cuentas de WAM, OneAuth e IdentityCache.
      5. Re-registra los tres paquetes (procedimiento oficial de Microsoft).
      6. Reinicia TokenBroker, wlidsvc y cloudidsvc.

    Los pasos 5 y 6 necesitan administrador. Sin elevar, el script hace el resto y avisa.

.PARAMETER SoloDiagnostico
    Solo la fase 1. No cambia nada.

.PARAMETER BorrarCuentasWam
    Ademas renombra las cuentas cacheadas de WAM, OneAuth e IdentityCache. Cierra la sesion
    de Office, Teams y OneDrive: habra que volver a iniciar sesion en todo.

.PARAMETER DryRun
    Muestra lo que haria sin tocar nada.

.PARAMETER Force
    No pide confirmacion.

.EXAMPLE
    # Con la ventana de login en blanco abierta en pantalla:
    .\03-repair-signin-window.ps1 -SoloDiagnostico

.EXAMPLE
    .\03-repair-signin-window.ps1

.EXAMPLE
    .\03-repair-signin-window.ps1 -BorrarCuentasWam -Force

.NOTES
    Contexto: admin
    PowerShell como administrador DESDE LA SESION DEL USUARIO AFECTADO. Los paquetes se
    registran y la cache se limpia para la cuenta que ejecuta: elevar con otra cuenta
    repararia el perfil equivocado, y el script lo detecta contra explorer.exe y aborta.
    PowerShell 5.1 y 7. Windows 10 y 11.
    Referencia: learn.microsoft.com/troubleshoot/microsoft-365/admin/authentication/automatic-authentication-fails
#>

[CmdletBinding()]
param(
    [switch]$SoloDiagnostico,
    [switch]$BorrarCuentasWam,
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = 'Continue'
$stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$logDir  = Join-Path $env:TEMP "SigninWindow_$stamp"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$logFile = Join-Path $logDir 'repair.log'
$avisos  = New-Object System.Collections.ArrayList

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR','OK','SKIP','DRY')] [string]$Level = 'INFO')
    $line  = '{0} [{1}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level.PadRight(5), $Message
    $color = switch ($Level) { 'ERROR' { 'Red' } 'WARN' { 'Yellow' } 'OK' { 'Green' } 'SKIP' { 'DarkGray' } 'DRY' { 'Cyan' } default { 'Gray' } }
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $logFile -Value $line -Encoding UTF8
    if ($Level -in 'WARN', 'ERROR') { [void]$avisos.Add($Message) }
}

function Write-Section([string]$t) { Write-Host ''; Write-Host "=== $t ===" -ForegroundColor Cyan; Add-Content -Path $logFile -Value "=== $t ===" -Encoding UTF8 }

$broker     = 'Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy'
$brokerData = Join-Path $env:LOCALAPPDATA "Packages\$broker"
$paquetes   = @(
    @{ Nombre = 'Microsoft.AAD.BrokerPlugin'; Carpeta = 'Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy'; Para = 'cuentas de trabajo' }
    @{ Nombre = 'Microsoft.AccountsControl'; Carpeta = 'Microsoft.AccountsControl_cw5n1h2txyewy'; Para = 'selector de cuentas' }
    @{ Nombre = 'Microsoft.Windows.CloudExperienceHost'; Carpeta = 'Microsoft.Windows.CloudExperienceHost_cw5n1h2txyewy'; Para = 'cuentas personales' }
)
$servicios  = @('TokenBroker', 'wlidsvc', 'cloudidsvc')
$identity   = 'HKCU:\Software\Microsoft\Office\16.0\Common\Identity'
$valoresWam = @('DisableAADWAM', 'DisableADALatopWAMOverride', 'DisableMSAWAM')
$endpoints  = @('login.microsoftonline.com', 'aadcdn.msftauth.net', 'aadcdn.msauth.net', 'logincdn.msftauth.net', 'login.live.com')

# ---------------------------------------------------------------------------
# Contexto: la cuenta que ejecuta debe ser la del usuario de la sesion
# ---------------------------------------------------------------------------
Write-Section 'Contexto'
$yo      = "$env:USERDOMAIN\$env:USERNAME"
$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$sesion  = $null
try {
    $exp = @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop) | Select-Object -First 1
    if ($exp) {
        $o = Invoke-CimMethod -InputObject $exp -MethodName GetOwner -ErrorAction Stop
        if ($o.User) { $sesion = "$($o.Domain)\$($o.User)" }
    }
} catch { }
Write-Log "Ejecuta : $yo  (elevado: $esAdmin)"
Write-Log "Sesion  : $(if ($sesion) { $sesion } else { 'no detectada' })"
Write-Log "Windows : $([Environment]::OSVersion.Version)"
if ($sesion -and $sesion -ne $yo) {
    Write-Log "La consola es de $yo pero la sesion es de $sesion. Se repararia el perfil equivocado." 'ERROR'
    Write-Log 'Abrir PowerShell como administrador desde la sesion del usuario afectado (su propia cuenta).' 'ERROR'
    exit 1
}
if (-not $esAdmin -and -not $SoloDiagnostico) {
    Write-Log 'Sin elevar: se omitiran el re-registro de paquetes y el reinicio de servicios.' 'WARN'
}

# ---------------------------------------------------------------------------
# Fase 1 - Diagnostico
# ---------------------------------------------------------------------------
Write-Section 'Paquetes de cuentas de Windows'
foreach ($p in $paquetes) {
    $pkg = @(Get-AppxPackage -Name $p.Nombre -ErrorAction SilentlyContinue) | Select-Object -First 1
    if (-not $pkg) { Write-Log "$($p.Nombre) ($($p.Para)): NO registrado para este usuario" 'WARN' }
    elseif ("$($pkg.Status)" -ne 'Ok') { Write-Log "$($p.Nombre): estado $($pkg.Status)" 'WARN' }
    else { Write-Log "$($p.Nombre): Ok ($($pkg.Version))" 'OK' }
}

Write-Section 'WebView2 Runtime'
$wv2Id  = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
$wv2Ver = $null
foreach ($k in @("HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$wv2Id", "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$wv2Id", "HKCU:\Software\Microsoft\EdgeUpdate\Clients\$wv2Id")) {
    $pv = (Get-ItemProperty -Path $k -Name pv -ErrorAction SilentlyContinue).pv
    if ($pv -and $pv -ne '0.0.0.0') { $wv2Ver = $pv; break }
}
if ($wv2Ver) { Write-Log "WebView2 $wv2Ver" 'OK' }
else { Write-Log 'WebView2 Runtime no instalado o roto. Instalar el Evergreen Bootstrapper de Microsoft.' 'WARN' }

Write-Section 'Servicios'
foreach ($s in $servicios) {
    $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
    if (-not $svc) { Write-Log "${s}: no existe en este Windows" 'SKIP'; continue }
    $modo = (Get-CimInstance Win32_Service -Filter "Name='$s'" -ErrorAction SilentlyContinue).StartMode
    if ($modo -eq 'Disabled') { Write-Log "${s}: DESHABILITADO. WAM no puede funcionar." 'WARN' }
    else { Write-Log "${s}: $($svc.Status) ($modo)" 'OK' }
}

Write-Section 'Registro de identidad de Office'
$quitar = New-Object System.Collections.ArrayList
foreach ($v in $valoresWam) {
    $val = (Get-ItemProperty -Path $identity -Name $v -ErrorAction SilentlyContinue).$v
    if ($null -ne $val) { Write-Log "$identity\$v = $val (desactiva o altera WAM)" 'WARN'; [void]$quitar.Add($v) }
}
$pol = 'HKCU:\Software\Policies\Microsoft\Office\16.0\Common\Identity'
foreach ($v in $valoresWam) {
    $val = (Get-ItemProperty -Path $pol -Name $v -ErrorAction SilentlyContinue).$v
    if ($null -ne $val) { Write-Log "$pol\$v = $val viene por directiva: hay que quitarlo en la GPO/Intune, no aqui" 'WARN' }
}
if (-not $quitar.Count) { Write-Log 'Sin valores heredados que desactiven WAM' 'OK' }

Write-Section 'Red'
$proxyHkcu = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
if ($proxyHkcu.ProxyEnable -eq 1) { Write-Log "Proxy de usuario: $($proxyHkcu.ProxyServer)" 'INFO' }
if ($proxyHkcu.AutoConfigURL) { Write-Log "PAC: $($proxyHkcu.AutoConfigURL)" 'INFO' }
$winhttp = (& netsh winhttp show proxy 2>$null) -join ' '
if ($winhttp -match 'Direct access|Acceso directo') { Write-Log 'WinHTTP: acceso directo' 'INFO' } else { Write-Log "WinHTTP: $($winhttp -replace '\s+', ' ')" 'INFO' }
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
foreach ($h in $endpoints) {
    $ok = $false; $det = ''
    try {
        $r = Invoke-WebRequest -Uri "https://$h/" -Method Head -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        $ok = $true; $det = "HTTP $($r.StatusCode)"
    } catch {
        # Un 400/404 tambien demuestra que la conexion TLS llega: lo que falla es la ruta, no la red.
        if ($_.Exception.Response) { $ok = $true; $det = 'responde' } else { $det = $_.Exception.Message }
    }
    if ($ok) { Write-Log "$h : $det" 'OK' } else { Write-Log "$h : SIN ACCESO ($det). La pagina de login no puede cargarse." 'WARN' }
}

# Mismo patron que el selector de archivos (10-file-picker): la ventana la pinta otro proceso
# y lo que la deja en blanco suele ser una DLL de terceros cargada dentro. Solo sirve con la
# ventana en blanco abierta delante: entonces el broker y sus WebView2 estan vivos.
Write-Section 'Modulos de terceros en la ventana de login'
$brk = @(Get-CimInstance Win32_Process -Filter "Name='Microsoft.AAD.BrokerPlugin.exe'" -ErrorAction SilentlyContinue)
if (-not $brk.Count) {
    Write-Log 'El broker no esta abierto. Para esta prueba, lanzar con la ventana en blanco en pantalla.' 'SKIP'
} else {
    $ids   = @($brk | ForEach-Object { $_.ProcessId })
    $hijos = @(Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe'" -ErrorAction SilentlyContinue | Where-Object { $ids -contains $_.ParentProcessId })
    $ids  += @($hijos | ForEach-Object { $_.ProcessId })
    Write-Log "Broker PID $(@($brk | ForEach-Object { $_.ProcessId }) -join ',') con $($hijos.Count) proceso/s WebView2"
    if (-not $hijos.Count) { Write-Log 'El broker no ha lanzado WebView2: la pagina ni siquiera empieza a cargarse.' 'WARN' }
    $rutas = @{}
    foreach ($id in $ids) {
        $pr = Get-Process -Id $id -ErrorAction SilentlyContinue
        if (-not $pr) { continue }
        try { foreach ($m in $pr.Modules) { if ($m.FileName) { $rutas[$m.FileName.ToLower()] = $pr.ProcessName } } }
        catch { Write-Log "No se pueden leer los modulos de $($pr.ProcessName) ($id): $($_.Exception.Message)" 'SKIP' }
    }
    $terceros = New-Object System.Collections.ArrayList
    foreach ($r in $rutas.Keys) {
        # Los binarios de Windows van firmados por catalogo: si no se puede verificar la firma
        # (PS 5.1 con el PSModulePath de PS 7 no carga Get-AuthenticodeSignature), cuenta la ruta.
        if ($r -match '^[a-z]:\\windows\\' -or $r -match '\\microsoft\\edgewebview\\application\\') { continue }
        $firma = $null
        try { $firma = (Get-AuthenticodeSignature -LiteralPath $r -ErrorAction Stop).SignerCertificate.Subject }
        catch { try { $firma = [Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile($r).Subject } catch { } }
        if ($firma -match 'O=Microsoft (Corporation|Windows)') { continue }
        $emisor = if ($firma -match 'O=([^,]+)') { $Matches[1].Trim('"') } else { 'SIN FIRMA' }
        [void]$terceros.Add([pscustomobject]@{ Proceso = $rutas[$r]; Firmante = $emisor; Ruta = $r })
    }
    if (-not $terceros.Count) { Write-Log "$($rutas.Count) modulos, todos de Microsoft" 'OK' }
    else {
        foreach ($t in ($terceros | Sort-Object Firmante, Ruta)) { Write-Log "SOSPECHOSO [$($t.Firmante)] $($t.Ruta) (en $($t.Proceso))" 'WARN' }
        $csv = Join-Path $logDir 'modulos-terceros.csv'
        $terceros | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
        Write-Log "Lista en $csv. Desactivar o desinstalar el producto de ese firmante y repetir el login." 'WARN'
    }
}

if ($SoloDiagnostico) {
    Write-Section 'Resultado'
    Write-Log "Solo diagnostico. Log: $logFile"
    exit 0
}

# ---------------------------------------------------------------------------
# Fase 2 - Reparacion
# ---------------------------------------------------------------------------
if (-not $Force -and -not $DryRun) {
    Write-Host ''
    Write-Host 'Se cerrara Outlook y se reparara el broker de inicio de sesion.' -ForegroundColor Yellow
    if ($BorrarCuentasWam) { Write-Host 'Con -BorrarCuentasWam habra que volver a iniciar sesion en Office, Teams y OneDrive.' -ForegroundColor Yellow }
    $resp = Read-Host 'Continuar? (S/N)'
    if ($resp -notmatch '^[sSyY]') { Write-Log 'Cancelado por el usuario' 'SKIP'; exit 0 }
}

function Invoke-Paso([string]$Desc, [scriptblock]$Accion) {
    if ($DryRun) { Write-Log "[SIMULACION] $Desc" 'DRY'; return }
    try { & $Accion; Write-Log $Desc 'OK' } catch { Write-Log "$Desc -> $($_.Exception.Message)" 'ERROR' }
}

function Rename-Respaldo([string]$Ruta) {
    if (-not (Test-Path -LiteralPath $Ruta)) { Write-Log "No existe: $Ruta" 'SKIP'; return }
    $destino = "$(Split-Path $Ruta -Leaf).bak_$stamp"
    Invoke-Paso "Renombrado $Ruta -> $destino" { Rename-Item -LiteralPath $Ruta -NewName $destino -ErrorAction Stop }
}

Write-Section 'Cerrar procesos'
foreach ($n in @('OUTLOOK', 'Microsoft.AAD.BrokerPlugin')) {
    $pr = @(Get-Process -Name $n -ErrorAction SilentlyContinue)
    if (-not $pr.Count) { Write-Log "${n}: no esta abierto" 'SKIP'; continue }
    Invoke-Paso "Cerrado $n ($($pr.Count))" { $pr | Stop-Process -Force -ErrorAction Stop }
}
if (-not $DryRun) { Start-Sleep -Seconds 2 }
Write-Log 'Si sigue abierta la ventana "Correo" del Panel de control, cerrarla a mano.' 'INFO'

Write-Section 'Registro de identidad'
if ($quitar.Count) {
    $reg = Join-Path $logDir 'Identity.reg'
    Invoke-Paso "Backup $identity -> $reg" { & reg.exe export 'HKCU\Software\Microsoft\Office\16.0\Common\Identity' $reg /y | Out-Null }
    foreach ($v in $quitar) { Invoke-Paso "Quitado $v" { Remove-ItemProperty -Path $identity -Name $v -ErrorAction Stop } }
} else { Write-Log 'Nada que quitar' 'SKIP' }

Write-Section 'Cache web del broker'
foreach ($sub in @('AC\INetCache', 'AC\INetCookies')) { Rename-Respaldo (Join-Path $brokerData $sub) }

if ($BorrarCuentasWam) {
    Write-Section 'Cuentas cacheadas (WAM, OneAuth, IdentityCache)'
    Rename-Respaldo (Join-Path $brokerData 'AC\TokenBroker\Accounts')
    Rename-Respaldo (Join-Path $env:LOCALAPPDATA 'Microsoft\OneAuth')
    Rename-Respaldo (Join-Path $env:LOCALAPPDATA 'Microsoft\IdentityCache')
}

Write-Section 'Re-registro de paquetes'
if (-not $esAdmin) { Write-Log 'Omitido: requiere PowerShell como administrador' 'WARN' }
else {
    foreach ($p in $paquetes) {
        $manifest = Join-Path $env:windir "SystemApps\$($p.Carpeta)\AppxManifest.xml"
        if (-not (Test-Path $manifest)) { Write-Log "No existe $manifest" 'SKIP'; continue }
        Invoke-Paso "Re-registrado $($p.Nombre)" { Add-AppxPackage -Register $manifest -DisableDevelopmentMode -ForceApplicationShutdown -ErrorAction Stop }
    }
}

Write-Section 'Servicios'
if (-not $esAdmin) { Write-Log 'Omitido: requiere PowerShell como administrador' 'WARN' }
else {
    foreach ($s in $servicios) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if (-not $svc) { continue }
        $modo = (Get-CimInstance Win32_Service -Filter "Name='$s'" -ErrorAction SilentlyContinue).StartMode
        if ($modo -eq 'Disabled') { Invoke-Paso "$s pasado a Manual" { Set-Service -Name $s -StartupType Manual -ErrorAction Stop } }
        if ($svc.Status -eq 'Running') { Invoke-Paso "Reiniciado $s" { Restart-Service -Name $s -Force -ErrorAction Stop } }
        else { Write-Log "${s}: parado, arranca bajo demanda" 'SKIP' }
    }
}

# ---------------------------------------------------------------------------
# Verificacion
# ---------------------------------------------------------------------------
Write-Section 'Verificacion'
foreach ($p in $paquetes) {
    $pkg = @(Get-AppxPackage -Name $p.Nombre -ErrorAction SilentlyContinue) | Select-Object -First 1
    if ($pkg -and "$($pkg.Status)" -eq 'Ok') { Write-Log "$($p.Nombre): Ok" 'OK' } else { Write-Log "$($p.Nombre): sigue sin estar Ok" 'WARN' }
}

Write-Section 'Siguiente paso'
Write-Host '  1. Abrir Outlook directamente (no desde Panel de control > Correo) y agregar la cuenta.'
Write-Host '  2. Si la ventana sigue en blanco: reiniciar el equipo y repetir.'
Write-Host '  3. Si persiste: volver a lanzar con -BorrarCuentasWam.'
Write-Host '  4. Si algun CDN sale SIN ACCESO: es proxy o firewall, no el equipo.'
Write-Host ''
if ($avisos.Count) { Write-Log "$($avisos.Count) aviso/s. Log: $logFile" 'WARN' } else { Write-Log "Terminado sin avisos. Log: $logFile" 'OK' }
