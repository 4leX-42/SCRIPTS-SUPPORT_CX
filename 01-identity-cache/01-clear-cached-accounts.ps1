<#
.SYNOPSIS
    [ES] Borra las cuentas de trabajo cacheadas. Las quita todas salvo las que decidas conservar.
    [EN] Clears cached work accounts. Removes them all except the ones you choose to keep.
.DESCRIPTION
    Se lanza sin parametros. Enumera las cuentas, pregunta si hay que excluir alguna
    y limpia el resto: Office Identity, Office Roaming, IdentityCRL, WAM, OneDrive,
    credenciales y las caches globales de token y licencia.

    Todo lo que borra se respalda antes en el Escritorio: claves exportadas a .reg y
    ficheros movidos, no eliminados.

    Ejecutar con la sesion del usuario afectado, sin elevar.
.PARAMETER Excluir
    UPN o UPNs que no se tocan. Sin esto, el menu lo pregunta.
.PARAMETER Quitar
    Modo desatendido: limpia solo estos UPN y no pregunta nada mas.
.PARAMETER NoCerrarApps
    No cierra Office, Teams, OneDrive ni navegadores. Por defecto si los cierra:
    mientras corren, reescriben la cache que se acaba de borrar.
.PARAMETER Detalle
    Muestra la ruta de cada objeto, no solo el recuento por tipo.
.PARAMETER DryRun
    Enumera lo que tocaria sin cambiar nada.
.PARAMETER Force
    No pide confirmacion.
.EXAMPLE
    .\02-clear-office-creds-tenant.ps1
.EXAMPLE
    .\02-clear-office-creds-tenant.ps1 -Excluir buena@contoso.com -Force
.NOTES
    EJECUTAR COMO: la sesion del usuario afectado, SIN elevar. Borra de HKCU y de su
    perfil; elevado con otra cuenta limpiaria el perfil equivocado. El script lo
    detecta comparando con el dueno de explorer.exe y aborta.
    PowerShell 5.1 y 7. Sin dependencias.
#>
[CmdletBinding()]
param(
    [string[]]$Excluir,
    [string[]]$Quitar,
    [switch]$NoCerrarApps,
    [switch]$Detalle,
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = 'Continue'
# PS 5.1 negocia TLS 1.0 por defecto; login.microsoftonline.com lo rechaza
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

$RX_UPN = '[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,63}'
$sello  = Get-Date -Format 'yyyyMMdd-HHmm'
$backup = Join-Path ([Environment]::GetFolderPath('Desktop')) "limpieza-cuenta-$sello"
$log    = Join-Path $backup 'limpieza.log'

function Reg {
    param([string]$M, [string]$C = 'Gray')
    Write-Host $M -ForegroundColor $C
    if (-not $DryRun -and (Test-Path $backup)) {
        Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $M) -Encoding utf8 -ErrorAction SilentlyContinue
    }
}

function ConvertFrom-ClaveOffice {
    param([string]$Nombre)
    $n = $Nombre -replace '_(ADAL|LiveId|OrgId)$', ''
    if ($n -match '^(.+?)_(.+)$') { '{0}@{1}' -f $Matches[1], ($Matches[2] -replace '_', '.') }
}

function Get-Rastros {
    $r = New-Object System.Collections.ArrayList
    $reg = @(
        @{ P = 'HKCU:\Software\Microsoft\Office\16.0\Common\Identity\Identities'; T = 'Office Identity' }
        @{ P = 'HKCU:\Software\Microsoft\Office\15.0\Common\Identity\Identities'; T = 'Office Identity' }
        @{ P = 'HKCU:\Software\Microsoft\Office\16.0\Common\Roaming\Identities';  T = 'Office Roaming'  }
        @{ P = 'HKCU:\Software\Microsoft\IdentityCRL\UserExtendedProperties';     T = 'IdentityCRL'     }
    )
    foreach ($x in $reg) {
        if (-not (Test-Path $x.P)) { continue }
        foreach ($k in (Get-ChildItem $x.P -ErrorAction SilentlyContinue)) {
            $upn = (Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue).EmailAddress
            if (-not $upn) { $upn = ConvertFrom-ClaveOffice $k.PSChildName }
            if (-not $upn -and $k.PSChildName -match "^$RX_UPN$") { $upn = $k.PSChildName }
            if ($upn) { [void]$r.Add([pscustomobject]@{ Tipo = $x.T; Ruta = ($x.P + '\' + $k.PSChildName); Upn = $upn }) }
        }
    }

    # WAM: los .tbacct son binarios con el UPN en Unicode
    $wam = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy\AC\TokenBroker\Accounts'
    if (Test-Path $wam) {
        foreach ($f in (Get-ChildItem $wam -File -ErrorAction SilentlyContinue)) {
            try {
                $b = [IO.File]::ReadAllBytes($f.FullName)
                $txt = [Text.Encoding]::Unicode.GetString($b) + ' ' + [Text.Encoding]::UTF8.GetString($b)
                foreach ($u in ([regex]::Matches($txt, $RX_UPN) | ForEach-Object { $_.Value } | Sort-Object -Unique)) {
                    [void]$r.Add([pscustomobject]@{ Tipo = 'WAM'; Ruta = $f.FullName; Upn = $u })
                }
            } catch { }
        }
    }

    $od = 'HKCU:\Software\Microsoft\OneDrive\Accounts'
    if (Test-Path $od) {
        foreach ($k in (Get-ChildItem $od -ErrorAction SilentlyContinue)) {
            $m = (Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue).UserEmail
            if ($m) { [void]$r.Add([pscustomobject]@{ Tipo = 'OneDrive'; Ruta = ($od + '\' + $k.PSChildName); Upn = $m }) }
        }
    }

    foreach ($l in ((cmdkey /list) 2>$null)) {
        if ($l -match '^\s*(Target|Destino)\s*:\s*(.+?)\s*$') {
            $tg = $Matches[2]
            foreach ($m in [regex]::Matches($tg, $RX_UPN)) {
                [void]$r.Add([pscustomobject]@{ Tipo = 'Credencial'; Ruta = $tg; Upn = $m.Value })
            }
        }
    }
    $r
}

function Remove-Rastro {
    param($R)
    switch ($R.Tipo) {
        'Credencial' { & cmdkey.exe /delete:"$($R.Ruta)" | Out-Null }
        'WAM' {
            Copy-Item $R.Ruta (Join-Path $backup ('WAM-' + (Split-Path $R.Ruta -Leaf))) -Force -ErrorAction SilentlyContinue
            Remove-Item $R.Ruta -Force -ErrorAction SilentlyContinue
        }
        default {
            $hive = $R.Ruta -replace '^HKCU:', 'HKCU'
            & reg.exe export $hive (Join-Path $backup (($R.Ruta -replace '[\\:*?"<>|]', '_') + '.reg')) /y 2>$null | Out-Null
            Remove-Item $R.Ruta -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# --- Perfil: elevar con otra cuenta apuntaria a HKCU y %LOCALAPPDATA% ajenos ---
$yo = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$dueno = $null
try {
    $p = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop | Select-Object -First 1
    if ($p) { $o = Invoke-CimMethod -InputObject $p -MethodName GetOwner -ErrorAction Stop; if ($o.User) { $dueno = "$($o.Domain)\$($o.User)" } }
} catch { }

Write-Host ''
Write-Host '=== Limpieza de cuentas de Office cacheadas ===' -ForegroundColor Cyan
Write-Host ("  Perfil ..: {0}" -f $env:USERPROFILE)
if ($DryRun) { Write-Host '  Modo ....: SIMULACION, no cambia nada' -ForegroundColor Yellow }

if ($dueno -and $yo -ne $dueno) {
    Write-Host ''
    Write-Host ("  ABORTADO: la sesion de Windows es de '{0}' y ejecutas como '{1}'." -f $dueno, $yo) -ForegroundColor Red
    Write-Host '  Abre PowerShell sin "Ejecutar como administrador", con la sesion del usuario.' -ForegroundColor Red
    return
}

$rastros = @(Get-Rastros)
$cuentas = @($rastros | Group-Object { $_.Upn.ToLowerInvariant() } | Sort-Object Name | ForEach-Object { $_.Group[0].Upn })
if (-not $cuentas) { Write-Host ''; Write-Host '  No hay cuentas cacheadas en este perfil.' -ForegroundColor Green; return }

Write-Host ''
$i = 0
foreach ($u in $cuentas) {
    $i++
    $guid = ($u -split '@')[0] -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'
    $nota = if ($guid) { '  <- tenant antiguo' } else { '' }
    Write-Host ("  [{0}] {1}{2}" -f $i, $u, $nota) -ForegroundColor $(if ($guid) { 'Yellow' } else { 'White' })
}

# --- Menu: por defecto se quitan todas ---
if (-not $Quitar) {
    if (-not $Excluir -and -not $Force) {
        Write-Host ''
        Write-Host '  Por defecto se quitan TODAS.' -ForegroundColor Yellow
        $sel = Read-Host '  Cual conservar? (numeros separados por coma, Enter = ninguna)'
        if ($sel.Trim()) {
            $Excluir = foreach ($n in ($sel -split '[,\s]+' | Where-Object { $_ })) {
                if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $cuentas.Count) { $cuentas[[int]$n - 1] }
                else { Write-Host ("  numero ignorado: {0}" -f $n) -ForegroundColor DarkGray }
            }
        }
    }
    $Quitar = @($cuentas | Where-Object { $u = $_; -not ($Excluir | Where-Object { $_ -ieq $u }) })
}
if (-not $Quitar) { Write-Host ''; Write-Host '  No queda ninguna cuenta que quitar.' -ForegroundColor Yellow; return }

# Las caches globales solo cuando se arrasa: sin ellas los tokens sobreviven
$profundo = @($Quitar).Count -eq $cuentas.Count

$objetivo = @($rastros | Where-Object { $u = $_.Upn; $Quitar | Where-Object { $_ -ieq $u } })

# Un .tbacct puede contener varias cuentas: si tambien es de una excluida, no se toca
$protegidos = @()
if ($Excluir) {
    $rutasBuenas = @($rastros | Where-Object { $u = $_.Upn; $Excluir | Where-Object { $_ -ieq $u } } | ForEach-Object { $_.Ruta })
    $protegidos  = @($objetivo | Where-Object { $rutasBuenas -contains $_.Ruta })
    $objetivo    = @($objetivo | Where-Object { $rutasBuenas -notcontains $_.Ruta })
}
if (-not $objetivo) { Write-Host ''; Write-Host '  No hay nada que borrar.' -ForegroundColor Yellow; return }

Write-Host ''
Write-Host ("--- Se quitan {0} de {1} cuenta/s ---" -f @($Quitar).Count, $cuentas.Count) -ForegroundColor Cyan
foreach ($u in $Quitar) { Write-Host ("  quitar   {0}" -f $u) -ForegroundColor Yellow }
foreach ($u in $Excluir) { Write-Host ("  conservar {0}" -f $u) -ForegroundColor Green }
Write-Host ''
foreach ($g in ($objetivo | Group-Object Tipo | Sort-Object Name)) {
    Write-Host ("  {0,-16} {1}" -f $g.Name, $g.Count)
    if ($Detalle) { foreach ($r in $g.Group) { Write-Host ("      {0}" -f $r.Ruta) -ForegroundColor DarkGray } }
}
if ($protegidos) { Write-Host ("  {0} objeto/s compartidos con las conservadas: no se tocan" -f $protegidos.Count) -ForegroundColor Green }
if ($profundo) { Write-Host '  + caches globales de token y licencia' -ForegroundColor Yellow }
if (-not $NoCerrarApps) { Write-Host '  + se cerraran Office, Teams, OneDrive y navegadores' -ForegroundColor Yellow }
Write-Host ("  respaldo en {0}" -f $backup) -ForegroundColor DarkGray

if ($DryRun) { Write-Host ''; Write-Host '  SIMULACION: sin cambios. Quita -DryRun para aplicar.' -ForegroundColor Yellow; return }
if (-not $Force) {
    Write-Host ''
    $ok = Read-Host '  Escribe SI para aplicar'
    if ($ok -notmatch '^(SI|S|YES|Y)$') { Write-Host '  Cancelado.' -ForegroundColor Yellow; return }
}

New-Item -ItemType Directory -Path $backup -Force | Out-Null
Reg ("Limpieza en {0}: {1}" -f $env:USERPROFILE, ($Quitar -join ', ')) Cyan

if (-not $NoCerrarApps) {
    Reg '--- Cerrando aplicaciones ---' Cyan
    foreach ($n in 'OUTLOOK', 'olk', 'ms-teams', 'Teams', 'OneDrive', 'WINWORD', 'EXCEL', 'POWERPNT', 'ONENOTE', 'MSACCESS', 'lync', 'msedge', 'chrome', 'firefox') {
        $v = Get-Process -Name $n -ErrorAction SilentlyContinue
        if ($v) { Reg ("  {0} ({1})" -f $n, $v.Count) Yellow; $v | Stop-Process -Force -ErrorAction SilentlyContinue }
    }
    Start-Sleep -Seconds 3
}

Reg '--- Borrando ---' Cyan
foreach ($g in ($objetivo | Group-Object Tipo | Sort-Object Name)) {
    Reg ("  {0,-16} {1}" -f $g.Name, $g.Count) Yellow
    foreach ($r in $g.Group) { Remove-Rastro $r }
}

if ($profundo) {
    Reg '--- Caches globales ---' Cyan
    $globales = @(
        "$env:LOCALAPPDATA\Microsoft\IdentityCache"
        "$env:LOCALAPPDATA\Microsoft\OneAuth"
        "$env:LOCALAPPDATA\Microsoft\TokenBroker\Cache"
        "$env:LOCALAPPDATA\Microsoft\Office\16.0\Licensing"
        "$env:LOCALAPPDATA\Microsoft\Office\Licenses"
    )
    foreach ($g in $globales) {
        if (-not (Test-Path $g)) { continue }
        Reg ("  {0}" -f $g) Yellow
        $dest = Join-Path $backup ('global-' + (Split-Path $g -Leaf))
        try { Move-Item $g $dest -Force -ErrorAction Stop }
        catch { Copy-Item $g $dest -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item $g -Recurse -Force -ErrorAction SilentlyContinue }
    }
    foreach ($t in 'MicrosoftAccount:target=SSO_POP_Device', 'WindowsLive:target=virtualapp/didlogical') {
        & cmdkey.exe /delete:"$t" 2>$null | Out-Null
    }
    Reg '  credenciales globales de SSO borradas' Yellow
}

Reg ''
Reg '--- Verificacion ---' Cyan
$quedan = @(Get-Rastros | Where-Object { $u = $_.Upn; $Quitar | Where-Object { $_ -ieq $u } })
if ($quedan) { foreach ($q in $quedan) { Reg ("  QUEDA: {0} {1}" -f $q.Upn, $q.Tipo) Red } }
else { Reg ("  OK: {0} cuenta/s fuera del equipo." -f @($Quitar).Count) Green }

foreach ($u in $Excluir) {
    try {
        $realm = Invoke-RestMethod ("https://login.microsoftonline.com/getuserrealm.srf?login={0}&json=1" -f $u) -TimeoutSec 20
        Reg ("  {0} resuelve a {1} ({2})" -f $u, $realm.FederationBrandName, $realm.NameSpaceType) Green
    } catch { Reg ("  no se pudo verificar {0}" -f $u) Yellow }
}

Reg ''
Reg ("Respaldo en {0}" -f $backup) Cyan
Reg 'Abrir Office e iniciar sesion escribiendo el UPN completo.' Green
