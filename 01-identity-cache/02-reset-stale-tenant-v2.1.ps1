<#
.SYNOPSIS
    [ES] Quita la cuenta que sobrevive de un tenant antiguo. Detecta sola el UPN y el tenant.
    [EN] Removes the account left over from an old tenant. Auto-detects the UPN and the tenant.
.DESCRIPTION
    Version 2.0 de Reset-CachedWorkAccount.ps1. Misma limpieza, pero ya no hay que
    saberse de memoria ni el UPN ni el dominio inicial del tenant de origen: el
    script los descubre leyendo lo que hay cacheado en el equipo y los contrasta
    contra los endpoints publicos de login de Microsoft.

    Caso de uso: un dominio (p.ej. invabpo.com) se movio de un tenant a otro. Entra
    reescribio el UPN de la cuenta que quedaba en el tenant de origen a
    <objectId>@<dominioInicial>, y el equipo del usuario sigue ofreciendo ese tile
    GUID al iniciar sesion.

    Que aporta la 2.0
      - Inventario de identidades cacheadas con su procedencia (registro de Office,
        OneDrive, TokenBroker/WAM, Administrador de credenciales, dsregcmd).
      - Resolucion en linea de cada dominio candidato: tenantId real y marca del
        tenant (federationBrandName), para distinguir el tenant bueno del obsoleto.
      - Deteccion del patron exacto del incidente: identidades cuyo nombre local es
        un GUID en vez de un alias legible. Son las que generan el tile zombie.
      - Menu de seleccion con flechas, con numero directo o con entrada manual. En
        consolas sin teclado disponible (ISE, salida redirigida) cae a modo numerico.

    Se ejecuta EN EL EQUIPO DEL USUARIO AFECTADO, con su sesion de Windows y SIN
    admin. NO toca el tenant ni usa lib\AndersenLab.psm1 (el equipo destino no tiene
    ni el modulo ni el certificado): solo consulta endpoints publicos de login.

    Todo lo que borra se respalda antes: claves de registro exportadas a .reg y
    carpetas de cache MOVIDAS (no eliminadas). Reversible.

    Lo que NO hace por defecto:
      - dsregcmd /leave  -> tras -QuitarWorkplaceJoin, y aborta si AzureAdJoined = YES.
      - borrar cookies del navegador -> tras -BorrarCookiesEdge (borra TODAS las de Edge).

.PARAMETER Upn
    UPN correcto del usuario en el tenant destino. Si se omite, se detecta y se
    ofrece elegir entre los candidatos encontrados en el equipo.

.PARAMETER TenantOrigen
    Dominio inicial del tenant del que procede la identidad obsoleta
    (p.ej. contoso.onmicrosoft.com). Si se omite, se detecta y se ofrece elegir.
    Alias -TenantViejo por compatibilidad con la version 1.

.PARAMETER TenantEsperado
    federationBrandName que debe devolver getUserRealm para el UPN. Por defecto 'Andersen'.

.PARAMETER RutaRespaldo
    Carpeta donde dejar el respaldo y el log. Por defecto el Escritorio; si no es
    escribible (tipico cuando esta redirigido a un OneDrive averiado) se cae solo a
    %USERPROFILE%\Desktop, luego %LOCALAPPDATA%\LimpiezaCuenta y por ultimo %TEMP%.

.PARAMETER SoloDetectar
    Inventario y resolucion en linea, sin menu y sin tocar nada. Util para el ticket.

.PARAMETER NoInteractivo
    No muestra menus. Exige que -Upn y -TenantOrigen vengan por parametro.

.PARAMETER DryRun
    Simula: enumera todo lo que tocaria sin cambiar nada.

.EXAMPLE
    # Solo ver que hay cacheado y de que tenant viene cada cosa
    .\Reset-StaleTenantAccount.ps1 -SoloDetectar

.EXAMPLE
    # Deteccion + menu de seleccion + simulacion
    .\Reset-StaleTenantAccount.ps1 -DryRun

.EXAMPLE
    # Todo por parametro, desatendido
    .\Reset-StaleTenantAccount.ps1 -Upn usuario@invabpo.com `
        -TenantOrigen invataxlegal.onmicrosoft.com -NoInteractivo -Force
#>
[CmdletBinding()]
param(
    [string]$Upn,
    [Alias('TenantViejo')]
    [string]$TenantOrigen,
    [string]$TenantEsperado = 'Andersen',
    [string]$RutaRespaldo,
    [switch]$SoloDetectar,
    [switch]$NoInteractivo,
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

# ===========================================================================
#  RAIZ DE RESPALDO
# ===========================================================================
# El Escritorio suele estar redirigido a OneDrive (Known Folder Move). Si OneDrive
# esta en mal estado -que es justo el sintoma que trae aqui al usuario- la carpeta
# no admite escritura. Se prueban varias raices y se usa la primera donde se pueda
# crear un fichero de verdad.
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

$candidatasRaiz = @()
if ($RutaRespaldo) { $candidatasRaiz += $RutaRespaldo }
$candidatasRaiz += @(
    [Environment]::GetFolderPath('Desktop')
    (Join-Path $env:USERPROFILE 'Desktop')
    (Join-Path $env:LOCALAPPDATA 'LimpiezaCuenta')
    $env:TEMP
)

$raizElegida = $null
foreach ($c in $candidatasRaiz) {
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
$soloLectura = $DryRun -or $SoloDetectar
if (-not $soloLectura) { New-Item -ItemType Directory -Path $backup -Force | Out-Null }

function Reg([string]$m, [string]$c = 'Gray') {
    Write-Host $m -ForegroundColor $c
    if (-not $soloLectura) {
        Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) -Encoding utf8 -ErrorAction SilentlyContinue
    }
}

# ===========================================================================
#  MENU DE SELECCION
# ===========================================================================
# Tres formas de elegir sobre la misma lista: flechas + Enter, tecla numerica
# directa, o 'M' para escribir el valor a mano. Si la consola no admite ReadKey
# (ISE, entrada redirigida, sesion remota sin tty) se degrada a Read-Host.
function Test-ConsolaInteractiva {
    if ($Host.Name -eq 'Windows PowerShell ISE Host') { return $false }
    try { if ([Console]::IsInputRedirected) { return $false } } catch { return $false }
    try { $null = $Host.UI.RawUI.KeyAvailable; return $true } catch { return $false }
}

function Show-MenuSeleccion {
    param(
        [Parameter(Mandatory)][string]$Titulo,
        [Parameter(Mandatory)][array]$Opciones,   # objetos con .Valor y .Etiqueta
        [string]$TextoManual = 'Escribir el valor a mano',
        [string]$PromptManual = 'Valor'
    )

    if (-not $Opciones -or $Opciones.Count -eq 0) {
        Write-Host ""
        Write-Host $Titulo -ForegroundColor Cyan
        Write-Host '  no se ha detectado ningun candidato; hay que escribirlo a mano' -ForegroundColor Yellow
        $m = Read-Host $PromptManual
        if ([string]::IsNullOrWhiteSpace($m)) { return $null }
        return $m.Trim()
    }

    # --- Modo degradado: sin teclado disponible, lista numerada y Read-Host -----
    if (-not (Test-ConsolaInteractiva)) {
        Write-Host ""
        Write-Host $Titulo -ForegroundColor Cyan
        for ($i = 0; $i -lt $Opciones.Count; $i++) {
            Write-Host ("  [{0}] {1}" -f ($i + 1), $Opciones[$i].Etiqueta)
        }
        Write-Host ("  [M] {0}" -f $TextoManual)
        $r = Read-Host 'Numero de opcion (o M)'
        if ($r -match '^[Mm]$') {
            $m = Read-Host $PromptManual
            if ([string]::IsNullOrWhiteSpace($m)) { return $null }
            return $m.Trim()
        }
        $n = 0
        if ([int]::TryParse($r, [ref]$n) -and $n -ge 1 -and $n -le $Opciones.Count) {
            return $Opciones[$n - 1].Valor
        }
        return $null
    }

    # --- Modo interactivo: flechas, numero directo, M, Esc ---------------------
    $sel = 0
    $primeraVez = $true
    $filaInicio = $null

    while ($true) {
        if ($primeraVez) {
            Write-Host ""
            Write-Host $Titulo -ForegroundColor Cyan
            Write-Host '  flechas para moverse, Enter para elegir, numero para ir directo, M manual, Esc cancela' -ForegroundColor DarkGray
            try { $filaInicio = $Host.UI.RawUI.CursorPosition } catch { $filaInicio = $null }
            $primeraVez = $false
        } elseif ($filaInicio) {
            try { $Host.UI.RawUI.CursorPosition = $filaInicio } catch { }
        }

        for ($i = 0; $i -lt $Opciones.Count; $i++) {
            $marca  = if ($i -eq $sel) { '>' } else { ' ' }
            $color  = if ($i -eq $sel) { 'Green' } else { 'Gray' }
            $linea  = ("{0} [{1}] {2}" -f $marca, ($i + 1), $Opciones[$i].Etiqueta)
            # Se rellena a lo ancho para borrar restos de la linea anterior al redibujar.
            $ancho = 100
            try { $ancho = [Math]::Max(40, $Host.UI.RawUI.WindowSize.Width - 1) } catch { }
            if ($linea.Length -gt $ancho) { $linea = $linea.Substring(0, $ancho) }
            Write-Host $linea.PadRight($ancho) -ForegroundColor $color
        }
        $marcaM = if ($sel -eq $Opciones.Count) { '>' } else { ' ' }
        $colorM = if ($sel -eq $Opciones.Count) { 'Green' } else { 'Gray' }
        Write-Host ("{0} [M] {1}" -f $marcaM, $TextoManual).PadRight(60) -ForegroundColor $colorM

        $tecla = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        switch ($tecla.VirtualKeyCode) {
            38 { $sel = if ($sel -le 0) { $Opciones.Count } else { $sel - 1 } }              # flecha arriba
            40 { $sel = if ($sel -ge $Opciones.Count) { 0 } else { $sel + 1 } }              # flecha abajo
            27 { Write-Host ''; return $null }                                              # Esc
            13 {                                                                            # Enter
                Write-Host ''
                if ($sel -eq $Opciones.Count) {
                    $m = Read-Host $PromptManual
                    if ([string]::IsNullOrWhiteSpace($m)) { return $null }
                    return $m.Trim()
                }
                return $Opciones[$sel].Valor
            }
            default {
                $ch = $tecla.Character
                if ($ch -match '^[1-9]$') {
                    $n = [int]::Parse($ch)
                    if ($n -le $Opciones.Count) {
                        Write-Host ''
                        return $Opciones[$n - 1].Valor
                    }
                } elseif ($ch -match '^[Mm]$') {
                    Write-Host ''
                    $m = Read-Host $PromptManual
                    if ([string]::IsNullOrWhiteSpace($m)) { return $null }
                    return $m.Trim()
                }
            }
        }
    }
}

# ===========================================================================
#  DETECCION
# ===========================================================================
$rxUpn  = '(?i)^[^@\s"'']+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
$rxGuid = '(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

# Identidades encontradas: cada entrada lleva de donde ha salido, para poder
# explicarle al usuario por que el script propone lo que propone.
$hallazgos = New-Object System.Collections.ArrayList

function Add-Hallazgo([string]$identidad, [string]$origen) {
    if ([string]::IsNullOrWhiteSpace($identidad)) { return }
    $v = $identidad.Trim().Trim('"')
    if ($v -notmatch $rxUpn) { return }
    $null = $hallazgos.Add([pscustomobject]@{
        Identidad = $v
        Local     = $v.Split('@')[0]
        Dominio   = $v.Split('@')[1].ToLower()
        Origen    = $origen
    })
}

function Get-ValorRegistro([string]$clave, [string]$nombre) {
    try {
        $p = Get-ItemProperty -Path ('Registry::' + $clave) -Name $nombre -ErrorAction Stop
        return $p.$nombre
    } catch { return $null }
}

Reg "=== Limpieza de identidad de tenant obsoleto - $(Get-Date -Format 'yyyy-MM-dd HH:mm') ===" Cyan
Reg "Perfil que se inspecciona: $env:USERPROFILE"
Reg "Respaldo ................: $(if ($soloLectura) { '(no se escribe: modo lectura)' } else { $backup })"
Reg ''
Reg '--- A. Inventario de identidades cacheadas ---' Cyan

# --- A1. Identidades de Office en el registro -------------------------------
$rutaIdentidades = 'HKCU\Software\Microsoft\Office\16.0\Common\Identity\Identities'
if (Test-Path ('Registry::' + $rutaIdentidades)) {
    foreach ($k in (Get-ChildItem ('Registry::' + $rutaIdentidades) -ErrorAction SilentlyContinue)) {
        $hoja = Split-Path $k.Name -Leaf
        # Office guarda el UPN con el '@' sustituido por '_' en el nombre de la clave.
        Add-Hallazgo ($hoja -replace '_(?=[^_]+\.[^_]+$)', '@') 'registro Office\Identity\Identities'
        foreach ($n in 'EmailAddress', 'SignInName', 'FriendlyName') {
            Add-Hallazgo (Get-ValorRegistro $k.Name.Replace('HKEY_CURRENT_USER', 'HKCU') $n) "registro Office\Identities\$hoja"
        }
    }
}
foreach ($n in 'ADUserName', 'SignedOutADUserName') {
    Add-Hallazgo (Get-ValorRegistro 'HKCU\Software\Microsoft\Office\16.0\Common\Identity' $n) "registro Office\Identity ($n)"
}

# --- A2. IdentityCRL --------------------------------------------------------
$crl = 'HKCU\Software\Microsoft\IdentityCRL\UserExtendedProperties'
if (Test-Path ('Registry::' + $crl)) {
    foreach ($k in (Get-ChildItem ('Registry::' + $crl) -ErrorAction SilentlyContinue)) {
        Add-Hallazgo (Split-Path $k.Name -Leaf) 'registro IdentityCRL'
    }
}

# --- A3. OneDrive -----------------------------------------------------------
# Cada Business<n> es una cuenta de trabajo vinculada. Ademas del correo guarda el
# tenantId configurado y la URL de SharePoint, de la que sale el nombre del tenant.
$tenantIdsOneDrive = @{}
$cuentasOneDrive   = 'HKCU\Software\Microsoft\OneDrive\Accounts'
if (Test-Path ('Registry::' + $cuentasOneDrive)) {
    foreach ($k in (Get-ChildItem ('Registry::' + $cuentasOneDrive) -ErrorAction SilentlyContinue)) {
        $hoja  = Split-Path $k.Name -Leaf
        $clave = $k.Name.Replace('HKEY_CURRENT_USER', 'HKCU')
        Add-Hallazgo (Get-ValorRegistro $clave 'UserEmail') "registro OneDrive\$hoja"
        $tid = Get-ValorRegistro $clave 'ConfiguredTenantId'
        $spo = Get-ValorRegistro $clave 'SPOResourceId'
        if ($tid -and $spo -and $spo -match '(?i)https://([a-z0-9-]+?)(-my)?\.sharepoint\.com') {
            $tenantIdsOneDrive[("{0}.onmicrosoft.com" -f $Matches[1].ToLower())] = $tid
        }
    }
}

# --- A4. Administrador de credenciales --------------------------------------
$lineasCmdkey = (cmdkey /list) 2>$null
foreach ($l in $lineasCmdkey) {
    if ($l -match '(?i)([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})') {
        Add-Hallazgo $Matches[1] 'Administrador de credenciales'
    }
}

# --- A5. Cuentas del broker WAM ---------------------------------------------
$wam = "$env:LOCALAPPDATA\Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy\AC\TokenBroker\Accounts"
if (Test-Path $wam) {
    foreach ($f in (Get-ChildItem $wam -File -ErrorAction SilentlyContinue)) {
        try {
            $txt = Get-Content $f.FullName -Raw -Encoding Byte -ErrorAction Stop
            $s = [Text.Encoding]::Unicode.GetString($txt) + [Text.Encoding]::UTF8.GetString($txt)
            foreach ($m in [regex]::Matches($s, '(?i)[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')) {
                Add-Hallazgo $m.Value 'TokenBroker (WAM)'
            }
        } catch { }
    }
}

# --- A6. Estado del dispositivo ---------------------------------------------
$dsreg  = (dsregcmd /status) 2>$null
$estado = @{}
foreach ($k in 'AzureAdJoined', 'EnterpriseJoined', 'DomainJoined', 'WorkplaceJoined', 'TenantId', 'TenantName', 'Executing Account Name', 'UserPrincipalName') {
    $m = $dsreg | Select-String -Pattern ("^\s*{0}\s*:\s*(.+)$" -f [regex]::Escape($k)) | Select-Object -First 1
    if ($m) { $estado[$k] = $m.Matches[0].Groups[1].Value.Trim() }
}
Add-Hallazgo $estado['UserPrincipalName'] 'dsregcmd (cuenta registrada)'
Add-Hallazgo $estado['Executing Account Name'] 'dsregcmd (sesion)'
# whoami /upn devuelve 1 y escribe en stderr si el equipo no esta unido a Entra ni
# a un dominio. Es un caso normal aqui, asi que se traga el error y se restaura el
# codigo de salida para no dejar $LASTEXITCODE contaminado al terminar el script.
$exitPrevio = $global:LASTEXITCODE
try { Add-Hallazgo ((whoami /upn) 2>$null) 'whoami /upn' } catch { }
$global:LASTEXITCODE = $exitPrevio

# --- Consolidado ------------------------------------------------------------
$identidades = $hallazgos | Group-Object Identidad | ForEach-Object {
    [pscustomobject]@{
        Identidad = $_.Group[0].Identidad
        Local     = $_.Group[0].Local
        Dominio   = $_.Group[0].Dominio
        Origenes  = ($_.Group.Origen | Select-Object -Unique)
        EsGuid    = ($_.Group[0].Local -match $rxGuid)
    }
}

if (-not $identidades) {
    Reg '  no se ha encontrado ninguna identidad cacheada en este perfil' Yellow
} else {
    foreach ($i in ($identidades | Sort-Object -Property @{E={-not $_.EsGuid}}, Identidad)) {
        $etq = if ($i.EsGuid) { '  [GUID zombie] ' } else { '  ' }
        $col = if ($i.EsGuid) { 'Red' } else { 'Gray' }
        Reg ("{0}{1}" -f $etq, $i.Identidad) $col
        Reg ("      origen: {0}" -f ($i.Origenes -join '; ')) DarkGray
    }
}

# --- B. Resolucion en linea de cada dominio ---------------------------------
Reg ''
Reg '--- B. A que tenant pertenece cada dominio ---' Cyan

$dominios = @()
if ($identidades) { $dominios += ($identidades.Dominio | Select-Object -Unique) }
$dominios += ($tenantIdsOneDrive.Keys)
$dominios = $dominios | Where-Object { $_ } | Select-Object -Unique

$infoDominios = @{}
foreach ($d in $dominios) {
    $info = [pscustomobject]@{
        Dominio  = $d
        TenantId = $null
        Marca    = $null
        Tipo     = $null
        Vivo     = $false
    }
    try {
        $oid = Invoke-RestMethod "https://login.microsoftonline.com/$d/v2.0/.well-known/openid-configuration" -TimeoutSec 15 -ErrorAction Stop
        # El issuer tiene la forma https://login.microsoftonline.com/<tenantId>/v2.0
        if ($oid.issuer -match '(?i)([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') { $info.TenantId = $Matches[1] }
        $info.Vivo = $true
    } catch { }
    try {
        $realm = Invoke-RestMethod "https://login.microsoftonline.com/getuserrealm.srf?login=probe@$d&json=1" -TimeoutSec 15 -ErrorAction Stop
        $info.Marca = $realm.FederationBrandName
        $info.Tipo  = $realm.NameSpaceType
    } catch { }
    $infoDominios[$d] = $info

    $col = if (-not $info.Vivo) { 'Green' } elseif ($info.Marca -eq $TenantEsperado) { 'Cyan' } else { 'Yellow' }
    $txt = if (-not $info.Vivo) { 'ya no resuelve (tenant eliminado)' }
           else { "tenantId={0}  marca={1}  tipo={2}" -f ($info.TenantId, $info.Marca, $info.Tipo) }
    Reg ("  {0,-38} {1}" -f $d, $txt) $col
}

if ($SoloDetectar) {
    Reg ''
    Reg '=== Modo -SoloDetectar: no se ha tocado nada. ===' Cyan
    return
}

# ===========================================================================
#  SELECCION DE UPN Y DE TENANT DE ORIGEN
# ===========================================================================

# --- UPN --------------------------------------------------------------------
if (-not $Upn) {
    if ($NoInteractivo) {
        Reg 'ABORTADO: -NoInteractivo exige -Upn explicito.' Red
        return
    }
    # El UPN bueno es una identidad legible (no GUID) cuyo dominio resuelve al
    # tenant esperado. Esas van primero en la lista.
    $opcUpn = @()
    foreach ($i in ($identidades | Where-Object { -not $_.EsGuid })) {
        $inf   = $infoDominios[$i.Dominio]
        $marca = if ($inf -and $inf.Marca) { $inf.Marca } else { 'desconocida' }
        $bueno = ($inf -and $inf.Marca -eq $TenantEsperado)
        $opcUpn += [pscustomobject]@{
            Valor    = $i.Identidad
            Bueno    = $bueno
            Etiqueta = ("{0,-42} marca: {1}{2}" -f $i.Identidad, $marca, $(if ($bueno) { '  <- coincide con el tenant esperado' } else { '' }))
        }
    }
    $opcUpn = $opcUpn | Sort-Object -Property @{E={-not $_.Bueno}}, Valor
    $Upn = Show-MenuSeleccion -Titulo 'UPN correcto del usuario en el tenant destino:' `
                              -Opciones $opcUpn -TextoManual 'Escribir el UPN a mano' -PromptManual 'UPN'
    if (-not $Upn) { Reg 'Cancelado: sin UPN no se puede continuar.' Yellow; return }
}
if ($Upn -notmatch $rxUpn) { Reg "ABORTADO: '$Upn' no tiene forma de UPN." Red; return }

# --- Tenant de origen -------------------------------------------------------
if (-not $TenantOrigen) {
    if ($NoInteractivo) {
        Reg 'ABORTADO: -NoInteractivo exige -TenantOrigen explicito.' Red
        return
    }
    $dominioUpn = $Upn.Split('@')[1].ToLower()
    $tenantUpn  = if ($infoDominios.ContainsKey($dominioUpn)) { $infoDominios[$dominioUpn].TenantId } else { $null }

    # Candidato = dominio distinto del que usa el UPN bueno y que no pertenece al
    # mismo tenantId. Los que vienen de una identidad GUID van los primeros: son
    # el patron exacto del incidente.
    $opcTen = @()
    foreach ($d in $dominios) {
        if ($d -eq $dominioUpn) { continue }
        $inf = $infoDominios[$d]
        if ($inf -and $tenantUpn -and $inf.TenantId -eq $tenantUpn) { continue }
        $conGuid = [bool]($identidades | Where-Object { $_.Dominio -eq $d -and $_.EsGuid })
        $desc = if (-not $inf -or -not $inf.Vivo) { 'ya no resuelve' }
                else { "marca: {0}" -f $(if ($inf.Marca) { $inf.Marca } else { 'desconocida' }) }
        $opcTen += [pscustomobject]@{
            Valor    = $d
            Zombie   = $conGuid
            Etiqueta = ("{0,-38} {1}{2}" -f $d, $desc, $(if ($conGuid) { '  <- tiene identidad GUID cacheada' } else { '' }))
        }
    }
    $opcTen = $opcTen | Sort-Object -Property @{E={-not $_.Zombie}}, Valor
    $TenantOrigen = Show-MenuSeleccion -Titulo 'Tenant de origen a purgar (dominio inicial *.onmicrosoft.com):' `
                                       -Opciones $opcTen -TextoManual 'Escribir el dominio a mano' -PromptManual 'Dominio del tenant de origen'
    if (-not $TenantOrigen) { Reg 'Cancelado: sin tenant de origen no se puede continuar.' Yellow; return }
}

Reg ''
Reg "UPN destino .......: $Upn" Green
Reg "Tenant a purgar ...: $TenantOrigen" Yellow
Reg "Modo ..............: $(if($DryRun){'SIMULACION (no cambia nada)'}else{'APLICAR'})" $(if ($DryRun) { 'Yellow' } else { 'Green' })
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
foreach ($k in 'AzureAdJoined', 'EnterpriseJoined', 'DomainJoined', 'WorkplaceJoined', 'TenantId', 'TenantName') {
    if ($estado.ContainsKey($k)) { Reg ("  {0,-18}: {1}" -f $k, $estado[$k]) }
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

Reg '--- Tenant de origen ---'
try {
    $old = Invoke-RestMethod "https://login.microsoftonline.com/$TenantOrigen/v2.0/.well-known/openid-configuration" -TimeoutSec 20
    Reg ("  {0} sigue existiendo como tenant independiente: {1}" -f $TenantOrigen, $old.issuer) Yellow
    Reg '  La cuenta GUID vive alli. Si reaparece el tile, hay que deshabilitarla en ESE tenant.' Yellow
} catch { Reg "  $TenantOrigen ya no resuelve." Green }

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
Reg "Si el tile GUID vuelve a aparecer: la cuenta sigue activa en el tenant $TenantOrigen." Yellow
