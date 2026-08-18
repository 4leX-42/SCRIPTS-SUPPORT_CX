<#
.SYNOPSIS
    [ES] Lista las cuentas de trabajo cacheadas en el equipo y donde esta guardada cada una.
    [EN] Lists the cached work accounts on this computer and where each one is stored.
.DESCRIPTION
    Solo lectura. Revisa Office Identity, Office Roaming, IdentityCRL, WAM/TokenBroker,
    OneDrive y el administrador de credenciales, y agrupa los hallazgos por cuenta.
    Sirve para saber que cuenta vieja sigue apareciendo al iniciar sesion y por que.
    Ejecutar con la sesion del usuario afectado, sin elevar.
.PARAMETER Detalle
    Imprime la ruta de cada hallazgo.
.PARAMETER PassThru
    Devuelve objetos en vez de imprimir tabla.
.EXAMPLE
    .\01-list-office-accounts.ps1 -Detalle
.NOTES
    EJECUTAR COMO: la sesion del usuario afectado, SIN elevar. Lee HKCU y su perfil;
    elevar con otra cuenta apunta a otro perfil y no encuentra nada.
    PowerShell 5.1 y 7. Sin dependencias.
#>
[CmdletBinding()]
param(
    [switch]$Detalle,
    [switch]$PassThru
)

$ErrorActionPreference = 'Continue'
$RX_UPN = '[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,63}'

function Add-Hallazgo {
    param($Tabla, [string]$Upn, [string]$Fuente, [string]$Ruta)
    if ([string]::IsNullOrWhiteSpace($Upn) -or $Upn -notmatch "^$RX_UPN$") { return }
    $k = $Upn.ToLowerInvariant()
    if (-not $Tabla.ContainsKey($k)) {
        $Tabla[$k] = [pscustomobject]@{
            Upn       = $Upn
            Dominio   = ($Upn -split '@')[-1]
            EsGuid    = [bool](($Upn -split '@')[0] -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$')
            Hallazgos = New-Object System.Collections.ArrayList
        }
    }
    [void]$Tabla[$k].Hallazgos.Add([pscustomobject]@{ Fuente = $Fuente; Ruta = $Ruta })
}

# Office nombra la subclave 'usuario_dominio_com': primer '_' es la arroba
function ConvertFrom-ClaveOffice {
    param([string]$Nombre)
    $n = $Nombre -replace '_(ADAL|LiveId|OrgId)$', ''
    if ($n -match '^(.+?)_(.+)$') { '{0}@{1}' -f $Matches[1], ($Matches[2] -replace '_', '.') }
}

function Get-CuentasCacheadas {
    $t = @{}
    $reg = @(
        @{ P = 'HKCU:\Software\Microsoft\Office\16.0\Common\Identity\Identities'; F = 'Office Identity' }
        @{ P = 'HKCU:\Software\Microsoft\Office\15.0\Common\Identity\Identities'; F = 'Office Identity' }
        @{ P = 'HKCU:\Software\Microsoft\Office\16.0\Common\Roaming\Identities';  F = 'Office Roaming'  }
        @{ P = 'HKCU:\Software\Microsoft\IdentityCRL\UserExtendedProperties';     F = 'IdentityCRL'     }
    )
    foreach ($r in $reg) {
        if (-not (Test-Path $r.P)) { continue }
        foreach ($k in (Get-ChildItem $r.P -ErrorAction SilentlyContinue)) {
            $upn = (Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue).EmailAddress
            if (-not $upn) { $upn = ConvertFrom-ClaveOffice $k.PSChildName }
            if (-not $upn -and $k.PSChildName -match "^$RX_UPN$") { $upn = $k.PSChildName }
            Add-Hallazgo $t $upn $r.F ($r.P + '\' + $k.PSChildName)
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
                    Add-Hallazgo $t $u 'WAM' $f.FullName
                }
            } catch { }
        }
    }

    $od = 'HKCU:\Software\Microsoft\OneDrive\Accounts'
    if (Test-Path $od) {
        foreach ($k in (Get-ChildItem $od -ErrorAction SilentlyContinue)) {
            Add-Hallazgo $t (Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue).UserEmail 'OneDrive' ($od + '\' + $k.PSChildName)
        }
    }

    foreach ($l in ((cmdkey /list) 2>$null)) {
        if ($l -match '^\s*(Target|Destino)\s*:\s*(.+?)\s*$') {
            $tg = $Matches[2]
            foreach ($m in [regex]::Matches($tg, $RX_UPN)) { Add-Hallazgo $t $m.Value 'Credencial' $tg }
        }
    }
    $t.Values | Sort-Object EsGuid, Upn
}

function Test-PerfilCorrecto {
    $yo = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $dueno = $null
    try {
        $p = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop | Select-Object -First 1
        if ($p) { $o = Invoke-CimMethod -InputObject $p -MethodName GetOwner -ErrorAction Stop; if ($o.User) { $dueno = "$($o.Domain)\$($o.User)" } }
    } catch { }
    [pscustomobject]@{ Yo = $yo; Sesion = $dueno; Coincide = (-not $dueno -or $yo -eq $dueno) }
}

$inv = @(Get-CuentasCacheadas)
if ($PassThru) { return $inv }

$perfil = Test-PerfilCorrecto
Write-Host ''
Write-Host '=== Cuentas cacheadas ===' -ForegroundColor Cyan
Write-Host ("  Perfil ....: {0}" -f $env:USERPROFILE)
Write-Host ("  Ejecuta ...: {0}" -f $perfil.Yo)
if (-not $perfil.Coincide) {
    Write-Host ("  AVISO: la sesion de Windows es de '{0}'. Estas leyendo otro perfil." -f $perfil.Sesion) -ForegroundColor Red
    Write-Host '  Abre PowerShell sin elevar, con la sesion del usuario afectado.' -ForegroundColor Red
}

$ds = (dsregcmd /status) 2>$null
Write-Host ''
foreach ($k in 'AzureAdJoined', 'DomainJoined', 'WorkplaceJoined', 'TenantName') {
    $m = $ds | Select-String -Pattern ("^\s*{0}\s*:\s*(.+)$" -f $k) | Select-Object -First 1
    if ($m) { Write-Host ("  {0,-16}: {1}" -f $k, $m.Matches[0].Groups[1].Value.Trim()) }
}

Write-Host ''
if (-not $inv) { Write-Host '  Ninguna cuenta de trabajo cacheada.' -ForegroundColor Green; return }

$i = 0
foreach ($c in $inv) {
    $i++
    $nota = if ($c.EsGuid) { '   <- UPN tipo GUID: cuenta reescrita por Entra, suele venir de un tenant antiguo' } else { '' }
    Write-Host ("  [{0}] {1}{2}" -f $i, $c.Upn, $nota) -ForegroundColor $(if ($c.EsGuid) { 'Yellow' } else { 'White' })
    Write-Host ("      {0}" -f ((($c.Hallazgos | Group-Object Fuente | Sort-Object Name) | ForEach-Object { '{0} x{1}' -f $_.Name, $_.Count }) -join '  '))
    if ($Detalle) { foreach ($h in $c.Hallazgos) { Write-Host ("        {0,-15} {1}" -f $h.Fuente, $h.Ruta) -ForegroundColor DarkGray } }
    Write-Host ''
}
Write-Host ("  {0} cuenta/s. Para quitar una: .\02-clear-office-creds-tenant.ps1" -f $inv.Count) -ForegroundColor Cyan
Write-Host ''
