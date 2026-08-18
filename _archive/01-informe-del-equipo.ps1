<#
.SYNOPSIS
    [ES] Ficha completa del equipo en una pasada: hardware, Windows, Entra, Intune, disco, red y Office.
    [EN] Full machine report in one pass: hardware, Windows, Entra, Intune, disk, network and Office.
.DESCRIPTION
    Solo lectura. Lo que se pregunta siempre al abrir un ticket, sin abrir cinco ventanas.
    Una sola consulta CIM por clase; nada en bucle.
.PARAMETER Csv
    Guarda tambien la ficha en un CSV plano (clave;valor) en la ruta indicada.
.EXAMPLE
    .\01-ficha-equipo.ps1
.EXAMPLE
    .\01-ficha-equipo.ps1 -Csv "$env:USERPROFILE\Desktop\ficha.csv"
.NOTES
    PowerShell 5.1 y 7. Sin dependencias. No requiere admin (BitLocker y algun dato si).
#>
[CmdletBinding()]
param([string]$Csv)

$ErrorActionPreference = 'Continue'
$f = [ordered]@{}

$cs  = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
$os  = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$bios= Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue

$f['Equipo']       = $env:COMPUTERNAME
$f['Usuario']      = "$env:USERDOMAIN\$env:USERNAME"
$f['Fabricante']   = "$($cs.Manufacturer) $($cs.Model)"
$f['NumeroSerie']  = $bios.SerialNumber
$f['RAM_GB']       = if ($cs.TotalPhysicalMemory) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 1) } else { $null }
$f['CPU']          = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Name

$f['SO']           = $os.Caption
$f['Version']      = "$($os.Version) (build $($os.BuildNumber))"
$f['Arranque']     = if ($os.LastBootUpTime) { $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm') } else { $null }
$f['UptimeDias']   = if ($os.LastBootUpTime) { [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 1) } else { $null }
$f['Idioma']       = (Get-Culture).Name
$f['ZonaHoraria']  = (Get-TimeZone -ErrorAction SilentlyContinue).Id

# Join / MDM
$ds = (dsregcmd /status) 2>$null
foreach ($k in 'AzureAdJoined', 'DomainJoined', 'WorkplaceJoined', 'TenantName', 'DeviceId') {
    $m = $ds | Select-String -Pattern ("^\s*{0}\s*:\s*(.+)$" -f $k) | Select-Object -First 1
    $f[$k] = if ($m) { $m.Matches[0].Groups[1].Value.Trim() } else { 'n/d' }
}
$f['Dominio'] = if ($cs.PartOfDomain) { $cs.Domain } else { 'grupo de trabajo' }
# Solo las inscripciones reales: las que tienen servidor de descubrimiento
$mdm = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue |
       ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
       Where-Object { $_.DiscoveryServiceFullURL } |
       ForEach-Object { '{0} ({1})' -f $_.ProviderID, $_.UPN } | Select-Object -Unique
$f['MDM'] = if ($mdm) { $mdm -join ', ' } else { 'no inscrito' }

# Disco de sistema
$d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction SilentlyContinue
if ($d) {
    $f['DiscoTotalGB']  = [math]::Round($d.Size / 1GB, 1)
    $f['DiscoLibreGB']  = [math]::Round($d.FreeSpace / 1GB, 1)
    $f['DiscoLibrePct'] = if ($d.Size) { [math]::Round(100 * $d.FreeSpace / $d.Size, 1) } else { $null }
}
$bl = Get-CimInstance -Namespace 'Root\CIMV2\Security\MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume `
      -Filter "DriveLetter='$env:SystemDrive'" -ErrorAction SilentlyContinue
$f['BitLocker'] = if ($null -eq $bl) { 'n/d (requiere admin)' } elseif ($bl.ProtectionStatus -eq 1) { 'activado' } else { 'desactivado' }

# Red: solo el adaptador con la ruta por defecto
$ruta = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1
if ($ruta) {
    $ip = Get-NetIPAddress -InterfaceIndex $ruta.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
    $f['Adaptador'] = (Get-NetAdapter -InterfaceIndex $ruta.InterfaceIndex -ErrorAction SilentlyContinue).InterfaceDescription
    $f['IP']        = if ($ip) { "$($ip.IPAddress)/$($ip.PrefixLength)" }
    $f['Gateway']   = $ruta.NextHop
    $f['DNS']       = ((Get-DnsClientServerAddress -InterfaceIndex $ruta.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses) -join ', '
}

# Office
$oc = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
if (Test-Path $oc) {
    $p = Get-ItemProperty $oc -ErrorAction SilentlyContinue
    $f['Office'] = "$($p.ProductReleaseIds) $($p.VersionToReport)"
    $canales = @{
        '492350f6-3a01-4f97-b9c0-c7c6ddf67d60' = 'Current Channel'
        '55336b82-a18d-4dd6-b5f6-9e5095c314a6' = 'Monthly Enterprise Channel'
        '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114' = 'Semi-Annual Enterprise Channel'
        'b8f9b850-328d-4355-9145-c59439a0c4cf' = 'Current Channel (Preview)'
        '5440fd1f-7ecb-4221-8110-145efaa6372f' = 'Beta Channel'
        'f2e724c1-748f-4b47-8fb8-8e0d210e9208' = 'Perpetuo (LTSC)'
    }
    $g = $p.CDNBaseUrl -replace '.*/', ''
    $f['OfficeCanal'] = if ($canales.ContainsKey($g)) { $canales[$g] } else { $g }
}
$idn = Get-ChildItem 'HKCU:\Software\Microsoft\Office\16.0\Common\Identity\Identities' -ErrorAction SilentlyContinue
$f['CuentasOfficeCacheadas'] = if ($idn) { $idn.Count } else { 0 }

Write-Host ''
Write-Host '=== Ficha del equipo ===' -ForegroundColor Cyan
foreach ($k in $f.Keys) { Write-Host ("  {0,-24}: {1}" -f $k, $f[$k]) }
Write-Host ''

if ($Csv) {
    $f.Keys | ForEach-Object { [pscustomobject]@{ Clave = $_; Valor = $f[$_] } } |
        Export-Csv -Path $Csv -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Write-Host ("  Guardado en {0}" -f $Csv) -ForegroundColor Green
    Write-Host ''
}
