#Requires -RunAsAdministrator

<#
.SYNOPSIS
    [ES] Diagnostica y corrige apagados y reinicios inesperados del equipo.
    [EN] Diagnoses and fixes unexpected shutdowns and restarts.
#>

[CmdletBinding()]
param(
    [switch]$SkipDiag,
    [switch]$SkipWifi
)

$ErrorActionPreference = 'Continue'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$log   = Join-Path $env:TEMP "Fix-RandomShutdowns_$stamp.log"
Start-Transcript -Path $log -Force | Out-Null

function Write-Section($title) {
    Write-Host "`n=== $title ===" -ForegroundColor Cyan
}
function Write-Ok($msg)   { Write-Host "[OK]  $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "[AVISO] $msg" -ForegroundColor Yellow }
function Write-Err2($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }

if (-not $SkipDiag) {
    Write-Section 'Diagnostico: ultimos apagados inesperados'

    $since = (Get-Date).AddDays(-7)
    $ids = @(41, 1001, 6008, 18, 19, 117, 124)
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = 'System'
            StartTime = $since
            Id        = $ids
        } -ErrorAction Stop |
            Select-Object TimeCreated, Id, ProviderName, LevelDisplayName,
                          @{n='Mensaje';e={ $_.Message.Split("`n")[0] }}

        if ($events) {
            $events | Format-Table -AutoSize | Out-String | Write-Host
            Write-Warn2 "Total eventos criticos en 7 dias: $($events.Count)"
        } else {
            Write-Ok 'Sin eventos criticos en 7 dias.'
        }
    } catch {
        Write-Err2 "No se pudieron leer eventos: $($_.Exception.Message)"
    }

    Write-Section 'Temperatura CPU (sensor ACPI - puede no estar disponible)'
    try {
        $t = Get-CimInstance -Namespace 'root/wmi' -ClassName 'MSAcpi_ThermalZoneTemperature' -ErrorAction Stop
        foreach ($z in $t) {
            $c = [math]::Round(($z.CurrentTemperature / 10) - 273.15, 1)
            $msg = "Zona $($z.InstanceName): $c C"
            if ($c -ge 85) { Write-Err2 $msg }
            elseif ($c -ge 75) { Write-Warn2 $msg }
            else { Write-Ok $msg }
        }
    } catch {
        Write-Warn2 'Sensor termico no expuesto. Usa HWiNFO64 o Core Temp para monitorizar.'
    }

    Write-Section 'Salud del disco (SMART)'
    try {
        Get-PhysicalDisk | Select-Object FriendlyName, MediaType, HealthStatus, OperationalStatus |
            Format-Table -AutoSize | Out-String | Write-Host
    } catch { Write-Warn2 $_.Exception.Message }

    Write-Section 'Bateria (si es portatil)'
    try {
        $b = Get-CimInstance Win32_Battery -ErrorAction Stop
        if ($b) {
            $b | Select-Object Name, EstimatedChargeRemaining, BatteryStatus, DesignCapacity, FullChargeCapacity |
                Format-List | Out-String | Write-Host
        } else { Write-Ok 'No es portatil o sin bateria.' }
    } catch { Write-Ok 'Sin bateria detectada.' }
}

Write-Section 'Plan de energia: Ultimate / Alto Rendimiento'

$ultimate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
$high     = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'

$schemes = (powercfg /list) -join "`n"
if ($schemes -notmatch $ultimate) {
    powercfg /duplicatescheme $ultimate | Out-Null
}
$active = $null
foreach ($g in @($ultimate, $high)) {
    powercfg /setactive $g 2>$null
    if ($LASTEXITCODE -eq 0) { $active = $g; break }
}
if ($active) { Write-Ok "Plan activo: $active" }
else { Write-Err2 'No se pudo fijar el plan de energia.' }

Write-Section 'Suspension / Hibernacion / Inicio Rapido DESACTIVADOS'
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /change hibernate-timeout-ac 0
powercfg /change hibernate-timeout-dc 0
powercfg /change monitor-timeout-ac 0
powercfg /change disk-timeout-ac 0
powercfg /hibernate off
Write-Ok 'Suspension e hibernacion desactivadas.'

$hiber = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
Set-ItemProperty -Path $hiber -Name 'HiberbootEnabled' -Value 0 -Type DWord -Force
Write-Ok 'Inicio Rapido desactivado.'

powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
Write-Ok 'Suspension selectiva USB desactivada.'

powercfg /setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0
Write-Ok 'PCIe ASPM desactivado.'

powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100
Write-Ok 'Estado min/max de CPU al 100% (CA).'

powercfg /setactive SCHEME_CURRENT

if (-not $SkipWifi) {
    Write-Section 'Adaptador WiFi'

    $adapter = Get-NetAdapter | Where-Object {
        $_.Status -eq 'Up' -and (
            $_.Name -match 'Wi-?Fi|Wireless' -or
            $_.InterfaceDescription -match 'Wi-?Fi|Wireless'
        )
    } | Select-Object -First 1

    if (-not $adapter) {
        Write-Warn2 'Sin adaptador WiFi activo.'
    } else {
        Write-Ok "Adaptador: $($adapter.Name) - $($adapter.InterfaceDescription)"

        try {
            $pnp = Get-PnpDevice -InstanceId $adapter.PnPDeviceID -ErrorAction Stop
            Disable-PnpDeviceProperty -InstanceId $adapter.PnPDeviceID -KeyName 'DEVPKEY_Device_PowerData' -ErrorAction SilentlyContinue
        } catch {}

        $rules = @(
            @{ Match = '*Power*Save*';            Values = @('Disabled','Off') }
            @{ Match = '*Energy*Efficient*';      Values = @('Disabled','Off') }
            @{ Match = '*Selective*Suspend*';     Values = @('Disabled','Off') }
            @{ Match = '*MIMO*Power*';            Values = @('No SMPS') }
            @{ Match = '*Roaming*Aggressive*';    Values = @('Highest') }
            @{ Match = '*Roaming Tendency*';      Values = @('Aggressive') }
            @{ Match = '*Transmit Power*';        Values = @('Highest','5. Highest') }
            @{ Match = '*Tx Power*';              Values = @('Highest','5. Highest') }
            @{ Match = '*Throughput*Booster*';    Values = @('Enabled') }
            @{ Match = '*Sleep*';                 Values = @('Disabled') }
            @{ Match = '*U-APSD*';                Values = @('Disabled') }
        )

        $props = Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue
        foreach ($p in $props) {
            foreach ($r in $rules) {
                if ($p.DisplayName -like $r.Match) {
                    $target = $r.Values | Where-Object { $p.ValidDisplayValues -contains $_ } | Select-Object -First 1
                    if (-not $target -and $p.DisplayName -match 'Transmit Power|Tx Power|Roaming Aggressive') {
                        $target = $p.ValidDisplayValues | Select-Object -Last 1
                    }
                    if ($target -and $p.DisplayValue -ne $target) {
                        try {
                            Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $p.DisplayName -DisplayValue $target -ErrorAction Stop
                            Write-Ok "$($p.DisplayName) -> $target"
                        } catch {
                            Write-Warn2 "$($p.DisplayName): $($_.Exception.Message)"
                        }
                    }
                    break
                }
            }
        }
    }
}

Write-Section 'Resumen'
Write-Host "Log: $log" -ForegroundColor Cyan
Write-Host "Reinicia el equipo para aplicar los cambios." -ForegroundColor Yellow
Write-Host ""
Write-Host "Si los apagones continuan tras reiniciar, NO es software. Revisa:" -ForegroundColor Yellow
Write-Host "  1. Temperaturas con HWiNFO64 (CPU >90C = apagado termico)" -ForegroundColor Yellow
Write-Host "  2. Fuente de alimentacion (PSU): sustituir si tiene mas de 5 anios o cargas altas" -ForegroundColor Yellow
Write-Host "  3. RAM: ejecutar mdsched.exe (Diagnostico de memoria de Windows)" -ForegroundColor Yellow
Write-Host "  4. Polvo o pasta termica seca" -ForegroundColor Yellow
Write-Host "  5. Bateria hinchada (en portatiles)" -ForegroundColor Yellow

Stop-Transcript | Out-Null
