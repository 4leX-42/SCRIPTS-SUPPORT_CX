<#
.SYNOPSIS
    [ES] Comprueba si el equipo llega a Microsoft 365: DNS, puerto 443, proxy y latencia.
    [EN] Checks whether the machine reaches Microsoft 365: DNS, port 443, proxy and latency.
.DESCRIPTION
    Solo lectura. Distingue los tres fallos que se confunden entre si:
      DNS no resuelve        -> problema de resolucion o de filtrado
      resuelve pero no abre  -> firewall o proxy bloqueando el 443
      abre pero tarda        -> latencia o inspeccion TLS por el medio
    Prueba los endpoints que de verdad hacen falta para Outlook, Teams y el inicio
    de sesion. Test-NetConnection es lento (~2 s por host): aqui se usa TcpClient
    con timeout corto.
.PARAMETER Hosts
    Endpoints adicionales a probar.
.PARAMETER TimeoutMs
    Timeout de la conexion TCP. Por defecto 3000.
.EXAMPLE
    .\01-test-conectividad-m365.ps1
.NOTES
    EJECUTAR COMO: cuenta del usuario. No necesita admin. El proxy de WinINET es por
    perfil, asi que elevar con otra cuenta mostraria un proxy que no es el suyo.
    PowerShell 5.1 y 7. Sin dependencias.
#>
[CmdletBinding()]
param(
    [string[]]$Hosts,
    [int]$TimeoutMs = 3000
)

$ErrorActionPreference = 'Continue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

$objetivos = @(
    @{ H = 'login.microsoftonline.com';   D = 'Inicio de sesion (Entra ID)' }
    @{ H = 'outlook.office365.com';       D = 'Outlook / Exchange Online'   }
    @{ H = 'teams.microsoft.com';         D = 'Teams'                       }
    @{ H = 'graph.microsoft.com';         D = 'Microsoft Graph'             }
    @{ H = 'oneclient.sfx.ms';            D = 'OneDrive (cliente)'          }
    @{ H = 'config.office.com';           D = 'Office (configuracion)'      }
    @{ H = 'enterpriseregistration.windows.net'; D = 'Registro de dispositivo / MDM' }
)
foreach ($h in $Hosts) { $objetivos += @{ H = $h; D = 'adicional' } }

function Test-Puerto {
    param([string]$H, [int]$P, [int]$Ms)
    $c = New-Object Net.Sockets.TcpClient
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $ar = $c.BeginConnect($H, $P, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($Ms, $false)) { return [pscustomobject]@{ Ok = $false; Ms = $Ms } }
        $c.EndConnect($ar)
        [pscustomobject]@{ Ok = $true; Ms = [int]$sw.ElapsedMilliseconds }
    } catch { [pscustomobject]@{ Ok = $false; Ms = [int]$sw.ElapsedMilliseconds } }
    finally { $c.Close() }
}

Write-Host ''
Write-Host '=== Conectividad Microsoft 365 ===' -ForegroundColor Cyan

$px = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
Write-Host ("  Proxy WinINET .....: {0}" -f $(if ($px.ProxyEnable -eq 1) { $px.ProxyServer } else { 'no' }))
$wh = (netsh winhttp show proxy) 2>$null | Select-String -Pattern 'Proxy Server|Servidor proxy' | Select-Object -First 1
Write-Host ("  Proxy WinHTTP .....: {0}" -f $(if ($wh) { $wh.ToString().Trim() } else { 'directo' }))
$dns = (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.ServerAddresses }).ServerAddresses | Select-Object -Unique
Write-Host ("  DNS ...............: {0}" -f ($dns -join ', '))
Write-Host ''

$fallos = 0
foreach ($o in $objetivos) {
    $ip = $null
    try { $ip = ([Net.Dns]::GetHostAddresses($o.H) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1).IPAddressToString } catch { }
    if (-not $ip) {
        $fallos++
        Write-Host ("  [FALLO] {0,-38} DNS no resuelve" -f $o.H) -ForegroundColor Red
        continue
    }
    $r = Test-Puerto $o.H 443 $TimeoutMs
    if (-not $r.Ok) {
        $fallos++
        Write-Host ("  [FALLO] {0,-38} {1,-15} 443 cerrado o filtrado" -f $o.H, $ip) -ForegroundColor Red
    } else {
        $col = if ($r.Ms -gt 400) { 'Yellow' } else { 'Green' }
        Write-Host ("  [ OK  ] {0,-38} {1,-15} {2,5} ms   {3}" -f $o.H, $ip, $r.Ms, $o.D) -ForegroundColor $col
    }
}

Write-Host ''
if ($fallos -eq 0) { Write-Host '  Todo alcanzable.' -ForegroundColor Green }
else { Write-Host ("  {0} endpoint/s inalcanzables. Revisar proxy, firewall o filtrado DNS." -f $fallos) -ForegroundColor Red }
Write-Host ''
