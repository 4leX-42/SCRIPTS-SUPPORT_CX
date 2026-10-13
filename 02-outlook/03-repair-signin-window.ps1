#Requires -Version 5.1

<#
.SYNOPSIS
    [ES] Repara la ventana de inicio de sesion de Microsoft 365 que se queda en blanco o en "Un momento..." al agregar la cuenta en Outlook; con -BorrarCuentasWam quita las cuentas de trabajo guardadas en Windows que ofrecen Teams y Office.
    [EN] Repairs the Microsoft 365 sign-in window that stays blank or stuck on "One moment..." when adding the account in Outlook; with -BorrarCuentasWam removes the work accounts stored in Windows that Teams and Office offer.
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
      - Cuentas de trabajo: union del equipo (dsregcmd /status), cuentas WAM del usuario
        (dsregcmd /ListAccounts), cuentas que conoce Office y cuentas registradas de OTRA
        organizacion ("Acceso a trabajo o escuela"), que ningun borrado de cache quita.
      - Con la ventana en blanco abierta: DLL de terceros cargadas en el broker y en sus
        procesos WebView2, con su firmante (mismo patron que 10-file-picker).

    Fase 2 - Reparacion (salvo -SoloDiagnostico):
      1. Cierra, solo en la sesion del usuario, Outlook y el broker. Con -BorrarCuentasWam
         cierra tambien todo lo que usa esas cuentas: Outlook nuevo, Teams, OneDrive y las
         apps de Office (sin guardar: la confirmacion dice cuales estan abiertas).
      2. Quita DisableAADWAM, DisableADALatopWAMOverride y DisableMSAWAM (backup .reg).
      3. Renombra la cache web del broker (INetCache, INetCookies) a .bak: no cierra sesion.
      4. Con -BorrarCuentasWam: renombra a .bak las cuentas de WAM, la cache de TokenBroker,
         OneAuth e IdentityCache, y despues lanza dsregcmd /CleanupAccounts, que borra las
         cuentas WAM que quedan fuera de esas carpetas.
      5. Re-registra los tres paquetes (procedimiento oficial de Microsoft).
      6. Verifica: paquetes en Ok y, con -BorrarCuentasWam, que cuentas siguen en Windows.
         Si queda una cuenta registrada de otra organizacion, abre "Acceso a trabajo o
         escuela" para desconectarla a mano (no hay via soportada por linea de comandos).
      7. Reinicia TokenBroker, wlidsvc y cloudidsvc (requiere administrador).

    La cuenta con la que el equipo esta unido a Entra (la de la empresa) no se pierde: vuelve
    sola al reiniciar, porque sale del inicio de sesion de Windows y no de estas caches.

    Desde la consola de una herramienta remota (SYSTEM) el script se reparte solo: la parte
    de equipo (servicios, WebView2, red, modulos) la hace como SYSTEM, y la parte de perfil
    (pasos 1-6) la lanza como tarea programada dentro de la sesion del usuario conectado y
    muestra su log al terminar.

.PARAMETER SoloDiagnostico
    Solo la fase 1. No cambia nada.

.PARAMETER BorrarCuentasWam
    Quita las cuentas de trabajo guardadas en Windows: las que salen en "Elija una cuenta
    para continuar" de Teams y en el selector de Office. Cierra antes Outlook (clasico y
    nuevo), Teams, OneDrive y las apps de Office del usuario, renombra a .bak las caches de
    cuentas (WAM, TokenBroker, OneAuth, IdentityCache) y lanza dsregcmd /CleanupAccounts.
    Cierra la sesion de Office, Teams y OneDrive: habra que volver a iniciar sesion en todo.
    No quita las cuentas registradas de otra organizacion: las detecta y abre la pagina
    de Configuracion donde se desconectan.

.PARAMETER DryRun
    Muestra lo que haria sin tocar nada, incluidas las apps que cerraria.

.PARAMETER Force
    No pide confirmacion. Las apps abiertas se cierran sin guardar.

.PARAMETER FaseUsuario
    Uso interno: la parte de perfil, lanzada por el propio script desde SYSTEM.

.PARAMETER DirTrabajo
    Uso interno: carpeta compartida entre SYSTEM y la tarea del usuario para el log.

.EXAMPLE
    # Con la ventana de login en blanco abierta en pantalla:
    .\03-repair-signin-window.ps1 -SoloDiagnostico

.EXAMPLE
    .\03-repair-signin-window.ps1 -Force

.EXAMPLE
    # Quitar las cuentas que Teams sigue ofreciendo. Primero ver que haria:
    .\03-repair-signin-window.ps1 -BorrarCuentasWam -DryRun
    .\03-repair-signin-window.ps1 -BorrarCuentasWam

.NOTES
    Contexto: admin
    Vale PowerShell como administrador desde la sesion del usuario afectado, o una consola
    de otra cuenta con privilegios (SYSTEM de la herramienta remota, admin local) con el
    usuario conectado: la parte de perfil se lanza entonces como tarea en la sesion del
    usuario, detectada por el SID del propietario de explorer.exe.
    PowerShell 5.1 y 7. Windows 10 y 11.
    Referencia: learn.microsoft.com/troubleshoot/microsoft-365/admin/authentication/automatic-authentication-fails
#>

[CmdletBinding()]
param(
    [switch]$SoloDiagnostico,
    [switch]$BorrarCuentasWam,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$FaseUsuario,
    [string]$DirTrabajo
)

$ErrorActionPreference = 'Continue'
$stamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$logDir = if ($DirTrabajo) { $DirTrabajo } else { Join-Path $env:TEMP "SigninWindow_$stamp" }
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$logFile = Join-Path $logDir $(if ($FaseUsuario) { 'usuario.log' } else { 'repair.log' })
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

function Invoke-Paso([string]$Desc, [scriptblock]$Accion) {
    if ($DryRun) { Write-Log "[SIMULACION] $Desc" 'DRY'; return }
    try { & $Accion; Write-Log $Desc 'OK' } catch { Write-Log "$Desc -> $($_.Exception.Message)" 'ERROR' }
}

function Rename-Respaldo([string]$Ruta) {
    if (-not (Test-Path -LiteralPath $Ruta)) { Write-Log "No existe: $Ruta" 'SKIP'; return }
    $destino = "$(Split-Path $Ruta -Leaf).bak_$stamp"
    Invoke-Paso "Renombrado $Ruta -> $destino" { Rename-Item -LiteralPath $Ruta -NewName $destino -ErrorAction Stop }
}

$brokerData = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy'
$paquetes   = @(
    @{ Nombre = 'Microsoft.AAD.BrokerPlugin'; Carpeta = 'Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy'; Para = 'cuentas de trabajo' }
    @{ Nombre = 'Microsoft.AccountsControl'; Carpeta = 'Microsoft.AccountsControl_cw5n1h2txyewy'; Para = 'selector de cuentas' }
    @{ Nombre = 'Microsoft.Windows.CloudExperienceHost'; Carpeta = 'Microsoft.Windows.CloudExperienceHost_cw5n1h2txyewy'; Para = 'cuentas personales' }
)
$servicios  = @('TokenBroker', 'wlidsvc', 'cloudidsvc')
$identity   = 'HKCU:\Software\Microsoft\Office\16.0\Common\Identity'
$valoresWam = @('DisableAADWAM', 'DisableADALatopWAMOverride', 'DisableMSAWAM')
$endpoints  = @('login.microsoftonline.com', 'aadcdn.msftauth.net', 'aadcdn.msauth.net', 'logincdn.msftauth.net', 'login.live.com')

# Que se cierra antes de reparar. La reparacion base solo toca el broker y Outlook; borrar
# las cuentas afecta a todo lo que inicia sesion con ellas, y con la app abierta los
# ficheros estan en uso y la app vuelve a escribir la cuenta al cerrarse.
$appsBase    = @('OUTLOOK', 'Microsoft.AAD.BrokerPlugin')
$appsCuentas = @('olk', 'ms-teams', 'Teams', 'OneDrive', 'WINWORD', 'EXCEL', 'POWERPNT', 'ONENOTE', 'MSACCESS', 'MSPUB', 'VISIO', 'WINPROJ', 'lync')
$cierre      = if ($BorrarCuentasWam) { $appsBase + $appsCuentas } else { $appsBase }
$script:wpjAjena = $null

function Get-AppsAbiertas([int]$SesionId) {
    # Solo la sesion del usuario: en un servidor de terminales no se cierra lo de los demas.
    @(Get-Process -Name $cierre -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $SesionId })
}

function Get-EstadoDsreg {
    # dsregcmd no se traduce: las claves salen siempre en ingles. Vale la primera aparicion.
    $h = @{}
    foreach ($l in @(& dsregcmd.exe /status 2>$null)) {
        if ($l -match '^\s*([A-Za-z]+)\s*:\s*(.*?)\s*$' -and -not $h.ContainsKey($Matches[1])) { $h[$Matches[1]] = $Matches[2] }
    }
    $h
}

function Show-CuentasWindows {
    # Devuelve la organizacion ajena registrada en el perfil, o $null.
    $ds = Get-EstadoDsreg
    if (-not $ds.Count) { Write-Log 'dsregcmd /status no devolvio datos' 'WARN'; return $null }
    $orgEquipo = $ds['TenantName']
    if ($ds['AzureAdJoined'] -eq 'YES') { Write-Log "Equipo unido a Entra: $orgEquipo. Su cuenta no se quita: vuelve sola al reiniciar." 'INFO' }
    elseif ($ds['DomainJoined'] -eq 'YES') { Write-Log "Equipo en dominio $($ds['DomainName']), sin union a Entra" 'INFO' }
    else { Write-Log 'Equipo sin union a Entra ni a dominio' 'INFO' }

    $ajena = $null
    if ($ds['WorkplaceJoined'] -eq 'YES') {
        $orgWpj = $ds['WorkplaceTenantName']
        if (-not $orgWpj) { $orgWpj = $ds['WorkplaceTenantId'] }
        if ($orgEquipo -and $orgWpj -and $orgWpj -ne $orgEquipo) {
            $ajena = $orgWpj
            Write-Log "Cuenta registrada de otra organizacion: $orgWpj. Ningun borrado de cache la quita: Configuracion > Cuentas > Acceso a trabajo o escuela > Desconectar." 'WARN'
        } else { Write-Log "Cuenta registrada en Entra (Acceso a trabajo o escuela): $orgWpj" 'INFO' }
    }

    $lista = @(& dsregcmd.exe /ListAccounts 2>$null | ForEach-Object { "$_".Trim() } | Where-Object { $_ -and $_ -notmatch '^Call ListAccounts' })
    if ($lista.Count) { foreach ($l in $lista) { Write-Log "WAM: $l" 'INFO' } }
    else { Write-Log 'dsregcmd /ListAccounts no disponible en este Windows' 'SKIP' }

    $office = @(Get-ChildItem "$identity\Identities" -ErrorAction SilentlyContinue |
        ForEach-Object { (Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue).EmailAddress } |
        Where-Object { $_ } | Sort-Object -Unique)
    if ($office.Count) { Write-Log "Cuentas que conoce Office: $($office -join ', ')" 'INFO' }
    return $ajena
}

# ---------------------------------------------------------------------------
# Parte de perfil: corre siempre con la cuenta del usuario afectado
# ---------------------------------------------------------------------------
function Invoke-DiagUsuario {
    Write-Section 'Paquetes de cuentas de Windows'
    foreach ($p in $paquetes) {
        $pkg = @(Get-AppxPackage -Name $p.Nombre -ErrorAction SilentlyContinue) | Select-Object -First 1
        if (-not $pkg) { Write-Log "$($p.Nombre) ($($p.Para)): NO registrado para este usuario" 'WARN' }
        elseif ("$($pkg.Status)" -ne 'Ok') { Write-Log "$($p.Nombre): estado $($pkg.Status)" 'WARN' }
        else { Write-Log "$($p.Nombre): Ok ($($pkg.Version))" 'OK' }
    }

    Write-Section 'Registro de identidad de Office'
    $script:quitar = New-Object System.Collections.ArrayList
    foreach ($v in $valoresWam) {
        $val = (Get-ItemProperty -Path $identity -Name $v -ErrorAction SilentlyContinue).$v
        if ($null -ne $val) { Write-Log "$identity\$v = $val (desactiva o altera WAM)" 'WARN'; [void]$script:quitar.Add($v) }
    }
    $pol = 'HKCU:\Software\Policies\Microsoft\Office\16.0\Common\Identity'
    foreach ($v in $valoresWam) {
        $val = (Get-ItemProperty -Path $pol -Name $v -ErrorAction SilentlyContinue).$v
        if ($null -ne $val) { Write-Log "$pol\$v = $val viene por directiva: hay que quitarlo en la GPO/Intune, no aqui" 'WARN' }
    }
    if (-not $script:quitar.Count) { Write-Log 'Sin valores heredados que desactiven WAM' 'OK' }

    Write-Section 'Proxy del usuario'
    $ie = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    if ($ie.ProxyEnable -eq 1) { Write-Log "Proxy: $($ie.ProxyServer)" 'INFO' } else { Write-Log 'Sin proxy manual' 'INFO' }
    if ($ie.AutoConfigURL) { Write-Log "PAC: $($ie.AutoConfigURL)" 'INFO' }

    Write-Section 'Cuentas de trabajo en Windows'
    $script:wpjAjena = Show-CuentasWindows
}

function Invoke-ReparaUsuario {
    Write-Section 'Cerrar procesos'
    $abiertas = Get-AppsAbiertas (Get-Process -Id $PID).SessionId
    if (-not $abiertas.Count) { Write-Log "Nada abierto de: $($cierre -join ', ')" 'SKIP' }
    foreach ($g in ($abiertas | Group-Object ProcessName)) {
        $pr = $g.Group
        Invoke-Paso "Cerrado $($g.Name) ($($pr.Count))" { $pr | Stop-Process -Force -ErrorAction Stop }
    }
    if (-not $DryRun -and $abiertas.Count) { Start-Sleep -Seconds 3 }
    Write-Log 'Si sigue abierta la ventana "Correo" del Panel de control, cerrarla a mano.' 'INFO'

    Write-Section 'Registro de identidad'
    if ($script:quitar.Count) {
        $reg = Join-Path $logDir 'Identity.reg'
        Invoke-Paso "Backup $identity -> $reg" { & reg.exe export 'HKCU\Software\Microsoft\Office\16.0\Common\Identity' $reg /y | Out-Null }
        foreach ($v in $script:quitar) { Invoke-Paso "Quitado $v" { Remove-ItemProperty -Path $identity -Name $v -ErrorAction Stop } }
    } else { Write-Log 'Nada que quitar' 'SKIP' }

    Write-Section 'Cache web del broker'
    foreach ($sub in @('AC\INetCache', 'AC\INetCookies')) { Rename-Respaldo (Join-Path $brokerData $sub) }

    if ($BorrarCuentasWam) {
        Write-Section 'Cuentas guardadas (WAM, TokenBroker, OneAuth, IdentityCache)'
        # Primero el respaldo renombrando; CleanupAccounts borra lo que WAM guarde fuera.
        Rename-Respaldo (Join-Path $brokerData 'AC\TokenBroker\Accounts')
        Rename-Respaldo (Join-Path $env:LOCALAPPDATA 'Microsoft\TokenBroker\Cache')
        Rename-Respaldo (Join-Path $env:LOCALAPPDATA 'Microsoft\OneAuth')
        Rename-Respaldo (Join-Path $env:LOCALAPPDATA 'Microsoft\IdentityCache')
        if (@(& dsregcmd.exe /? 2>$null) -match '/CleanupAccounts') {
            Invoke-Paso 'dsregcmd /CleanupAccounts' {
                $out = & dsregcmd.exe /CleanupAccounts 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) { throw "codigo $LASTEXITCODE $($out.Trim())" }
            }
        } else { Write-Log 'dsregcmd sin /CleanupAccounts en este Windows: solo se renombran las caches' 'SKIP' }
    }

    # El registro es por usuario y sobre un paquete ya instalado en SystemApps: se intenta
    # aunque no haya elevacion, y si Windows lo deniega queda en el log.
    Write-Section 'Re-registro de paquetes'
    foreach ($p in $paquetes) {
        $manifest = Join-Path $env:windir "SystemApps\$($p.Carpeta)\AppxManifest.xml"
        if (-not (Test-Path $manifest)) { Write-Log "No existe $manifest" 'SKIP'; continue }
        Invoke-Paso "Re-registrado $($p.Nombre)" { Add-AppxPackage -Register $manifest -DisableDevelopmentMode -ForceApplicationShutdown -ErrorAction Stop }
    }

    Write-Section 'Verificacion'
    foreach ($p in $paquetes) {
        $pkg = @(Get-AppxPackage -Name $p.Nombre -ErrorAction SilentlyContinue) | Select-Object -First 1
        if ($pkg -and "$($pkg.Status)" -eq 'Ok') { Write-Log "$($p.Nombre): Ok" 'OK' } else { Write-Log "$($p.Nombre): sigue sin estar Ok" 'WARN' }
    }

    if ($BorrarCuentasWam -and -not $DryRun) {
        Write-Section 'Cuentas que quedan en Windows'
        $script:wpjAjena = Show-CuentasWindows
        if ($script:wpjAjena) {
            # Desconectar un registro de Entra no tiene via soportada por linea de comandos.
            Invoke-Paso "Abierta Configuracion > Acceso a trabajo o escuela para desconectar $($script:wpjAjena)" { Start-Process 'ms-settings:workplace' }
        }
    }
}

# ---------------------------------------------------------------------------
# Parte de equipo: vale desde cualquier cuenta con privilegios
# ---------------------------------------------------------------------------
function Invoke-DiagEquipo {
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

    Write-Section 'Red'
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
        return
    }
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
    if (-not $terceros.Count) { Write-Log "$($rutas.Count) modulos, todos de Microsoft" 'OK'; return }
    foreach ($t in ($terceros | Sort-Object Firmante, Ruta)) { Write-Log "SOSPECHOSO [$($t.Firmante)] $($t.Ruta) (en $($t.Proceso))" 'WARN' }
    $csv = Join-Path $logDir 'modulos-terceros.csv'
    $terceros | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
    Write-Log "Lista en $csv. Desactivar o desinstalar el producto de ese firmante y repetir el login." 'WARN'
}

function Invoke-ReparaServicios {
    Write-Section 'Servicios'
    foreach ($s in $servicios) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if (-not $svc) { continue }
        $modo = (Get-CimInstance Win32_Service -Filter "Name='$s'" -ErrorAction SilentlyContinue).StartMode
        if ($modo -eq 'Disabled') { Invoke-Paso "$s pasado a Manual" { Set-Service -Name $s -StartupType Manual -ErrorAction Stop } }
        if ($svc.Status -eq 'Running') { Invoke-Paso "Reiniciado $s" { Restart-Service -Name $s -Force -ErrorAction Stop } }
        else { Write-Log "${s}: parado, arranca bajo demanda" 'SKIP' }
    }
}

function Confirm-Reparacion {
    if ($Force -or $DryRun -or $SoloDiagnostico) { return $true }
    Write-Host ''
    Write-Host 'Se reparara el broker de inicio de sesion de Windows.' -ForegroundColor Yellow
    $abiertas = @(Get-AppsAbiertas $script:sesionId | Where-Object { $_.ProcessName -ne 'Microsoft.AAD.BrokerPlugin' })
    if ($abiertas.Count) {
        $nombres = ($abiertas | Group-Object ProcessName | ForEach-Object { $_.Name }) -join ', '
        Write-Host "Se cerraran SIN GUARDAR: $nombres" -ForegroundColor Yellow
    }
    if ($BorrarCuentasWam) { Write-Host 'Se quitaran las cuentas guardadas: habra que volver a iniciar sesion en Office, Teams y OneDrive.' -ForegroundColor Yellow }
    $resp = Read-Host 'Continuar? (S/N)'
    if ($resp -match '^[sSyY]') { return $true }
    Write-Log 'Cancelado por el usuario' 'SKIP'
    return $false
}

function Show-SiguientePaso {
    Write-Section 'Siguiente paso'
    # En modo remoto el aviso viene en el log de la tarea del usuario, no en esta variable.
    $ajena = $script:wpjAjena -or @($avisos -match 'otra organizacion').Count
    if ($BorrarCuentasWam) {
        Write-Host '  1. Reiniciar el equipo.'
        Write-Host '  2. Abrir Teams, Outlook y OneDrive e iniciar sesion con la cuenta de la empresa.'
        if ($ajena) { Write-Host '  3. Desconectar la cuenta de la otra organizacion en Configuracion > Cuentas > Acceso a trabajo o escuela (no la de la empresa).' -ForegroundColor Yellow }
    } else {
        Write-Host '  1. Abrir Outlook directamente (no desde Panel de control > Correo) y agregar la cuenta.'
        Write-Host '  2. Si la ventana sigue en blanco: reiniciar el equipo y repetir.'
        Write-Host '  3. Si persiste, o si Teams/Office ofrecen cuentas que sobran: volver a lanzar con -BorrarCuentasWam.'
        if ($ajena) { Write-Host '  -  Hay una cuenta registrada de otra organizacion: se quita en Acceso a trabajo o escuela > Desconectar.' -ForegroundColor Yellow }
    }
    Write-Host '  Si algun CDN sale SIN ACCESO: es proxy o firewall, no el equipo.'
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Fase lanzada por SYSTEM dentro de la sesion del usuario
# ---------------------------------------------------------------------------
if ($FaseUsuario) {
    Write-Section "Perfil de $env:USERDOMAIN\$env:USERNAME"
    Invoke-DiagUsuario
    if (-not $SoloDiagnostico) { Invoke-ReparaUsuario }
    exit 0
}

# ---------------------------------------------------------------------------
# Contexto
# ---------------------------------------------------------------------------
Write-Section 'Contexto'
$identidad = [Security.Principal.WindowsIdentity]::GetCurrent()
$esAdmin   = ([Security.Principal.WindowsPrincipal]$identidad).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$sesion    = $null
$sesionSid = $null
$script:sesionId = (Get-Process -Id $PID).SessionId
try {
    $exp = @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop) | Select-Object -First 1
    if ($exp) {
        $script:sesionId = [int]$exp.SessionId
        $o = Invoke-CimMethod -InputObject $exp -MethodName GetOwner -ErrorAction Stop
        if ($o.User) { $sesion = "$($o.Domain)\$($o.User)" }
        $sesionSid = (Invoke-CimMethod -InputObject $exp -MethodName GetOwnerSid -ErrorAction Stop).Sid
    }
} catch { }
Write-Log "Ejecuta : $($identidad.Name) [$($identidad.User.Value)]  (elevado: $esAdmin)"
Write-Log "Sesion  : $(if ($sesion) { "$sesion [$sesionSid]" } else { 'no detectada' })"
Write-Log "Windows : $([Environment]::OSVersion.Version)"

# Se compara por SID, no por nombre: las consolas de herramientas remotas corren como SYSTEM
# o como cuentas de servicio propias, y el nombre que exponen no es fiable.
$otraCuenta = $sesionSid -and $sesionSid -ne $identidad.User.Value
if (-not $otraCuenta) { $script:sesionId = (Get-Process -Id $PID).SessionId }

# ---------------------------------------------------------------------------
# Modo remoto (consola de otra cuenta, p. ej. SYSTEM): equipo aqui, perfil en tarea del usuario
# ---------------------------------------------------------------------------
if ($otraCuenta) {
    if (-not $esAdmin) {
        Write-Log "La consola es de $($identidad.Name), no de $sesion, y sin elevar no puede lanzar nada en su sesion." 'ERROR'
        exit 1
    }
    Write-Log "Consola de otra cuenta: la parte de perfil se ejecutara como tarea en la sesion de $sesion." 'INFO'

    Invoke-DiagEquipo
    if (-not (Confirm-Reparacion)) { exit 0 }

    # Carpeta que pueden leer y escribir SYSTEM y el usuario: el log vuelve por aqui.
    $trabajo = Join-Path $env:ProgramData "SigninWindow\$stamp"
    New-Item -ItemType Directory -Path $trabajo -Force | Out-Null
    & icacls.exe $trabajo /grant "${sesion}:(OI)(CI)M" | Out-Null
    $copia = Join-Path $trabajo 'repair-signin-window.ps1'
    Copy-Item -LiteralPath $PSCommandPath -Destination $copia -Force

    $argumentos = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$copia`" -FaseUsuario -Force -DirTrabajo `"$trabajo`""
    if ($SoloDiagnostico)  { $argumentos += ' -SoloDiagnostico' }
    if ($BorrarCuentasWam) { $argumentos += ' -BorrarCuentasWam' }
    if ($DryRun)           { $argumentos += ' -DryRun' }

    $tarea = "SigninWindowRepair_$stamp"
    try {
        $accion    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argumentos
        $principal = New-ScheduledTaskPrincipal -UserId $sesion -LogonType Interactive -RunLevel Highest
        $ajustes   = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
        Register-ScheduledTask -TaskName $tarea -Action $accion -Principal $principal -Settings $ajustes -Force | Out-Null
        Start-ScheduledTask -TaskName $tarea
        Write-Log "Tarea $tarea lanzada en la sesion de $sesion. Esperando..." 'INFO'
        $limite = (Get-Date).AddMinutes(5)
        do { Start-Sleep -Seconds 2 } while ((Get-ScheduledTask -TaskName $tarea).State -eq 'Running' -and (Get-Date) -lt $limite)
        $resultado = (Get-ScheduledTaskInfo -TaskName $tarea).LastTaskResult
        if ((Get-ScheduledTask -TaskName $tarea).State -eq 'Running') { Write-Log 'La parte de perfil no ha terminado en 5 minutos.' 'WARN' }
        elseif ($resultado -ne 0) { Write-Log "La parte de perfil termino con codigo $resultado" 'WARN' }
    } catch {
        Write-Log "No se pudo lanzar la tarea en la sesion del usuario: $($_.Exception.Message)" 'ERROR'
    } finally {
        Unregister-ScheduledTask -TaskName $tarea -Confirm:$false -ErrorAction SilentlyContinue
    }

    $logUsuario = Join-Path $trabajo 'usuario.log'
    if (Test-Path $logUsuario) {
        Write-Host ''
        foreach ($l in (Get-Content -Path $logUsuario -Encoding UTF8)) {
            $c = if ($l -match '\[(ERROR)') { 'Red' } elseif ($l -match '\[WARN') { 'Yellow' } elseif ($l -match '\[OK') { 'Green' } elseif ($l -match '^===') { 'Cyan' } elseif ($l -match '\[DRY') { 'Cyan' } else { 'Gray' }
            Write-Host $l -ForegroundColor $c
            if ($l -match '\[(WARN |ERROR)\]') { [void]$avisos.Add($l) }
        }
    } else { Write-Log "La parte de perfil no dejo log en $logUsuario" 'ERROR' }

    if (-not $SoloDiagnostico) { Invoke-ReparaServicios }
    if (-not $SoloDiagnostico) { Show-SiguientePaso }
    if ($avisos.Count) { Write-Log "$($avisos.Count) aviso/s. Logs: $trabajo y $logFile" 'WARN' } else { Write-Log "Terminado sin avisos. Logs: $trabajo" 'OK' }
    exit 0
}

# ---------------------------------------------------------------------------
# Modo consola del usuario
# ---------------------------------------------------------------------------
if (-not $sesionSid) {
    if ($identidad.IsSystem -or $identidad.User.Value -match '^S-1-5-(18|19|20|80-)') {
        Write-Log 'No hay ningun usuario con sesion abierta: la parte de perfil necesita que este conectado.' 'ERROR'
        exit 1
    }
    Write-Log 'No se detecta la sesion del usuario: se asume que esta consola es la suya.' 'WARN'
}
if (-not $esAdmin -and -not $SoloDiagnostico) { Write-Log 'Sin elevar: se omitira el reinicio de servicios.' 'WARN' }

Invoke-DiagUsuario
Invoke-DiagEquipo
if ($SoloDiagnostico) {
    Write-Section 'Resultado'
    Write-Log "Solo diagnostico. Log: $logFile"
    exit 0
}
if (-not (Confirm-Reparacion)) { exit 0 }
Invoke-ReparaUsuario
if ($esAdmin) { Invoke-ReparaServicios } else { Write-Log 'Reinicio de servicios omitido: requiere PowerShell como administrador' 'WARN' }
Show-SiguientePaso
if ($avisos.Count) { Write-Log "$($avisos.Count) aviso/s. Log: $logFile" 'WARN' } else { Write-Log "Terminado sin avisos. Log: $logFile" 'OK' }
