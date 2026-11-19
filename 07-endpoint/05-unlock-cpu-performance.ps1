#Requires -RunAsAdministrator

<#
.SYNOPSIS
    [ES] Portatil con la CPU limitada (GHz bajos): quita los limites de energia de CPU y disco (Lenovo, Samsung, Surface, LG y cualquier otro).
    [EN] Laptop with a capped CPU (low GHz): removes CPU and disk power limits (Lenovo, Samsung, Surface, LG and any other brand).

.DESCRIPTION
    [ES]
    Para el caso "el portatil va lento" con la CPU clavada por debajo de su frecuencia base o
    sin llegar nunca al turbo. Deja CPU y disco a rendimiento maximo en corriente y en bateria
    y no toca pantalla, brillo, suspension ni hibernacion: eso se queda como estaba.

    Diagnostica primero: CPU, frecuencia base y actual, % de rendimiento (por encima de 100 =
    turbo), plan de energia, modo de energia de Windows 11, si hay politica (GPO/Intune) que
    fije el plan y los eventos 37 de Kernel-Processor-Power de los ultimos 7 dias (el firmware
    esta limitando la CPU: temperatura, cargador flojo o bateria).

    Cambios, sobre el plan activo (o el de -Plan):
      - Modo de energia de Windows 11 en "Maximo rendimiento" (corriente y bateria). Es lo que
        leen Surface y el control termico de Lenovo, Samsung y LG.
      - CPU: estado minimo y maximo al 100 % (nucleos P y E), sin tope de frecuencia (MHz=0),
        turbo agresivo, preferencia de energia (EPP) a rendimiento, sin aparcar nucleos y
        refrigeracion activa (ventilador antes que bajar la frecuencia).
      - Power Throttling de Windows desactivado (no frena procesos en segundo plano).
      - Ahorro de energia de Windows: no se activa solo con bateria baja.
      - Disco: no se apaga nunca, AHCI y NVMe sin estados de ahorro (APST).
      - PCIe ASPM y suspension selectiva USB desactivados.
      - Lenovo ThinkPad: BIOS "Adaptive Thermal Management" a MaximizePerformance (CA y
        bateria) si la BIOS no tiene contrasena de supervisor. Necesita reinicio.
    Samsung Settings y LG Control Center tienen su propio modo de rendimiento sin API: el
    script lo detecta y dice donde cambiarlo.

    Antes de escribir guarda los valores actuales en un .json. -Restore los devuelve.
    Con -DryRun solo diagnostica y ensena lo que cambiaria.

    Si tras esto la CPU sigue limitada y salen eventos 37, no es software: cargador de menos
    vatios que el original, temperatura (polvo, pasta termica) o bateria degradada.

    [EN]
    For "the laptop is slow" with the CPU stuck below its base clock or never reaching turbo.
    Puts CPU and disk at maximum performance on AC and battery. Display, brightness, sleep and
    hibernate are left as they are.

    Diagnoses first: CPU, base and current clock, % processor performance (above 100 = turbo),
    power plan, Windows 11 power mode, any GPO/Intune policy pinning the plan and Kernel-
    Processor-Power event 37 over the last 7 days (firmware is limiting the CPU: heat, weak
    charger or battery).

    Changes on the active plan (or the one in -Plan): Windows 11 power mode "Best performance",
    CPU min/max state 100 % (P and E cores), no frequency cap, aggressive boost, EPP to
    performance, no core parking, active cooling, Windows Power Throttling off, energy saver
    never turns on by itself, disk never idles, AHCI/NVMe power saving off, PCIe ASPM and USB
    selective suspend off, and on Lenovo ThinkPads the BIOS Adaptive Thermal Management set to
    MaximizePerformance when no supervisor password is set (needs a reboot). Samsung Settings
    and LG Control Center have their own performance mode with no API: the script points to it.

    Current values are saved to a .json before writing; -Restore puts them back. -DryRun only
    diagnoses and shows what would change.

.PARAMETER DryRun
    [ES] Solo diagnostico y plan de cambios. No escribe nada.
    [EN] Diagnosis and change plan only. Writes nothing.

.PARAMETER Restore
    [ES] Devuelve los valores guardados en la ultima ejecucion (o en -BackupFile).
    [EN] Restores the values saved by the last run (or by -BackupFile).

.PARAMETER Plan
    [ES] Plan de energia: Auto (el activo; si es Economizador pasa a Equilibrado), Balanced, High o Ultimate. El modo de Windows 11 solo actua sobre Equilibrado.
    [EN] Power plan: Auto (the active one; Power saver becomes Balanced), Balanced, High or Ultimate. The Windows 11 power mode only works on Balanced.

.PARAMETER AcOnly
    [ES] Aplica solo con el cargador conectado; en bateria deja los valores de Windows.
    [EN] Applies on AC only; on battery Windows values are kept.

.PARAMETER SkipBios
    [ES] No toca la BIOS de Lenovo.
    [EN] Does not touch the Lenovo BIOS.

.PARAMETER BackupFile
    [ES] .json concreto para -Restore.
    [EN] Specific .json for -Restore.

.PARAMETER LogPath
    [ES] Carpeta de log y copia de seguridad.
    [EN] Log and backup folder.

.EXAMPLE
    .\05-unlock-cpu-performance.ps1 -DryRun

.EXAMPLE
    .\05-unlock-cpu-performance.ps1

.EXAMPLE
    .\05-unlock-cpu-performance.ps1 -Restore

.NOTES
    Contexto: admin
    Funciona tambien como SYSTEM (consola remota): todo lo que toca es de equipo, no de perfil.
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Restore,
    [ValidateSet('Auto', 'Balanced', 'High', 'Ultimate')]
    [string]$Plan = 'Auto',
    [switch]$AcOnly,
    [switch]$SkipBios,
    [string]$BackupFile,
    [string]$LogPath = (Join-Path $env:ProgramData 'SCRIPTS-SUPPORT_CX\cpu-performance')
)

$ErrorActionPreference = 'Continue'

function Write-Section([string]$t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Write-Ok([string]$m)      { Write-Host "[OK]    $m" -ForegroundColor Green }
function Write-Info([string]$m)    { Write-Host "[INFO]  $m" -ForegroundColor Gray }
function Write-Warn2([string]$m)   { Write-Host "[AVISO] $m" -ForegroundColor Yellow }
function Write-Err2([string]$m)    { Write-Host "[ERROR] $m" -ForegroundColor Red }
function Write-Plan([string]$m)    { Write-Host "[DRY]   $m" -ForegroundColor Magenta }

$GuidBalanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
$GuidHigh     = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$GuidUltimate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
$GuidUltimateCopy = 'e9a42b02-d5df-448d-aa00-03f14749eb62'   # copia propia del Ultimate (oculto)
$GuidSaver    = 'a1841308-3541-4fab-bc81-f71556f20b4a'
$OverlayBest  = 'ded574b5-45a0-4f42-8737-46345c09c238'
$OverlayKey   = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
$ThrottleKey  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling'
$PolicyKey    = 'HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings'

$SubProc = '54533251-82be-4824-96c1-47b60b740d00'
$SubDisk = '0012ee47-9041-4b5d-9b77-535fba8b1442'
$SubPci  = '501a4d13-42af-4429-9fd1-a8218c268e20'
$SubUsb  = '2a737441-1930-4402-8d77-b2bebba308a3'
$SubSave = 'de830923-a562-41af-a086-e3a2c6bad2da'

# Ajuste, valor en corriente, valor en bateria. Los que no existan en un equipo se saltan.
$Targets = @(
    @{ N = 'CPU estado minimo';               S = $SubProc; G = '893dee8e-2bef-41e0-89c6-b55d0929964c'; Ac = 100; Dc = 100 }
    @{ N = 'CPU estado minimo (nucleos E)';   S = $SubProc; G = '893dee8e-2bef-41e0-89c6-b55d0929964d'; Ac = 100; Dc = 100 }
    @{ N = 'CPU estado maximo';               S = $SubProc; G = 'bc5038f7-23e0-4960-96da-33abaf5935ec'; Ac = 100; Dc = 100 }
    @{ N = 'CPU estado maximo (nucleos E)';   S = $SubProc; G = 'bc5038f7-23e0-4960-96da-33abaf5935ed'; Ac = 100; Dc = 100 }
    @{ N = 'CPU tope de frecuencia (0=sin)';  S = $SubProc; G = '75b0ae3f-bce0-45a7-8c89-c9611c25e100'; Ac = 0;   Dc = 0 }
    @{ N = 'CPU tope de frecuencia (E)';      S = $SubProc; G = '75b0ae3f-bce0-45a7-8c89-c9611c25e101'; Ac = 0;   Dc = 0 }
    @{ N = 'CPU turbo (2=agresivo)';          S = $SubProc; G = 'be337238-0d82-4146-a960-4f3749d470c7'; Ac = 2;   Dc = 2 }
    @{ N = 'CPU politica de turbo';           S = $SubProc; G = '45bcc044-d885-43e2-8605-ee0ec6e96b59'; Ac = 100; Dc = 100 }
    @{ N = 'CPU EPP (0=rendimiento)';         S = $SubProc; G = '36687f9e-e3a5-4dbf-b1dc-15eb381c6863'; Ac = 0;   Dc = 0 }
    @{ N = 'CPU EPP (nucleos E)';             S = $SubProc; G = '36687f9e-e3a5-4dbf-b1dc-15eb381c6864'; Ac = 0;   Dc = 0 }
    @{ N = 'CPU nucleos sin aparcar (%)';     S = $SubProc; G = '0cc5b647-c1df-4637-891a-dec35c318583'; Ac = 100; Dc = 100 }
    @{ N = 'CPU nucleos sin aparcar E (%)';   S = $SubProc; G = '0cc5b647-c1df-4637-891a-dec35c318584'; Ac = 100; Dc = 100 }
    @{ N = 'Refrigeracion (1=activa)';        S = $SubProc; G = '94d3a615-a899-4ac5-ae2b-e4d8f634367f'; Ac = 1;   Dc = 1 }
    @{ N = 'Disco: apagar tras (0=nunca)';    S = $SubDisk; G = '6738e2c4-e8a5-4a42-b16a-e040e769756e'; Ac = 0;   Dc = 0 }
    @{ N = 'AHCI ahorro de enlace (0=no)';    S = $SubDisk; G = '0b2d69d7-a2a1-449c-9680-f91c70521c60'; Ac = 0;   Dc = 0 }
    @{ N = 'AHCI ahorro adaptativo (0=no)';   S = $SubDisk; G = 'dab60367-53fe-4fbc-825e-521d069d2456'; Ac = 0;   Dc = 0 }
    @{ N = 'NVMe NOPPME (0=no)';              S = $SubDisk; G = 'fc7372b6-ab2d-43ee-8797-15e9841f2cca'; Ac = 0;   Dc = 0 }
    @{ N = 'NVMe APST primario (0=no)';       S = $SubDisk; G = 'd639518a-e56d-4345-8af2-b9f32fb26109'; Ac = 0;   Dc = 0 }
    @{ N = 'NVMe APST secundario (0=no)';     S = $SubDisk; G = 'd3d55efd-c1ff-424e-9dc3-441be7833010'; Ac = 0;   Dc = 0 }
    @{ N = 'PCIe ASPM (0=no)';                S = $SubPci;  G = 'ee12f906-d277-404b-b6da-e5fa1a576df5'; Ac = 0;   Dc = 0 }
    @{ N = 'USB suspension selectiva (0=no)'; S = $SubUsb;  G = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'; Ac = 0;   Dc = 0 }
    @{ N = 'Ahorro de energia auto (0=nunca)';S = $SubSave; G = 'e69653ca-cf7f-4f05-aa73-cb833fa90ad4'; Ac = 0;   Dc = 0 }
)

function Get-ActiveScheme {
    $o = (& powercfg /getactivescheme) -join ' '
    if ($o -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { return $Matches[1].ToLower() }
    return $null
}

function Test-Scheme([string]$guid) {
    return (((& powercfg /list) -join "`n") -match [regex]::Escape($guid))
}

# Devuelve @{Ac;Dc} o $null si el ajuste no existe. Los dos ultimos 0x... de la salida son
# los indices actuales en CA y CC en cualquier idioma de Windows.
function Get-PowerValue([string]$scheme, [string]$sub, [string]$setting) {
    $o = & powercfg /qh $scheme $sub $setting 2>&1
    if ($LASTEXITCODE -ne 0) { return $null }
    $hex = @([regex]::Matches(($o -join "`n"), '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value })
    if ($hex.Count -lt 2) { return $null }
    return @{ Ac = [Convert]::ToInt32($hex[-2], 16); Dc = [Convert]::ToInt32($hex[-1], 16) }
}

function Set-PowerValue([string]$scheme, [string]$sub, [string]$setting, [int]$ac, [int]$dc, [bool]$doDc) {
    & powercfg /setacvalueindex $scheme $sub $setting $ac 2>&1 | Out-Null
    $ok = ($LASTEXITCODE -eq 0)
    if ($doDc) {
        & powercfg /setdcvalueindex $scheme $sub $setting $dc 2>&1 | Out-Null
        $ok = $ok -and ($LASTEXITCODE -eq 0)
    }
    return $ok
}

function Get-Overlay {
    $p = Get-ItemProperty -Path $OverlayKey -ErrorAction SilentlyContinue
    return @{ Ac = $p.ActiveOverlayAcPowerScheme; Dc = $p.ActiveOverlayDcPowerScheme }
}

function Set-Overlay([string]$ac, [string]$dc) {
    if (-not (Test-Path $OverlayKey)) { New-Item -Path $OverlayKey -Force | Out-Null }
    foreach ($p in @(@('ActiveOverlayAcPowerScheme', $ac), @('ActiveOverlayDcPowerScheme', $dc))) {
        if ($p[1]) { Set-ItemProperty -Path $OverlayKey -Name $p[0] -Value $p[1] -Type String -Force }
        else { Remove-ItemProperty -Path $OverlayKey -Name $p[0] -ErrorAction SilentlyContinue }
    }
    # El registro guarda los dos; la API de Windows (la que usa Configuracion) lo aplica ya
    # para la fuente de energia actual. powercfg no tiene opcion para esto.
    $now = if ($bat -and $bat.BatteryStatus -eq 1) { $dc } else { $ac }
    if (-not $now) { $now = '00000000-0000-0000-0000-000000000000' }
    try {
        if (-not ('PowrProf.Overlay' -as [type])) {
            Add-Type -Namespace PowrProf -Name Overlay -MemberDefinition '[DllImport("powrprof.dll")] public static extern uint PowerSetActiveOverlayScheme(Guid overlay);'
        }
        [void][PowrProf.Overlay]::PowerSetActiveOverlayScheme([Guid]$now)
    } catch {}
}

function Get-LenovoThermal {
    $r = @()
    try {
        $all = Get-CimInstance -Namespace 'root/wmi' -ClassName 'Lenovo_BiosSetting' -ErrorAction Stop
        foreach ($s in $all) {
            if ($s.CurrentSetting -match '^(AdaptiveThermalManagement(AC|Battery)),([^;]+)') {
                $r += [pscustomobject]@{ Name = $Matches[1]; Value = $Matches[3] }
            }
        }
    } catch {}
    return $r
}

function Get-LenovoPasswordSet {
    try {
        $p = Get-CimInstance -Namespace 'root/wmi' -ClassName 'Lenovo_BiosPasswordSettings' -ErrorAction Stop
        return ([int]$p.PasswordState -ne 0)
    } catch { return $true }
}

function Set-LenovoBios([string]$name, [string]$value) {
    try {
        $set = Get-CimInstance -Namespace 'root/wmi' -ClassName 'Lenovo_SetBiosSetting' -ErrorAction Stop
        $r = Invoke-CimMethod -InputObject $set -MethodName 'SetBiosSetting' -Arguments @{ parameter = "$name,$value" } -ErrorAction Stop
        if ($r.return -ne 'Success') { return $r.return }
        $save = Get-CimInstance -Namespace 'root/wmi' -ClassName 'Lenovo_SaveBiosSettings' -ErrorAction Stop
        $r = Invoke-CimMethod -InputObject $save -MethodName 'SaveBiosSettings' -Arguments @{ parameter = '' } -ErrorAction Stop
        return $r.return
    } catch { return $_.Exception.Message }
}

if (-not $DryRun -and -not (Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
if (-not $DryRun) { Start-Transcript -Path (Join-Path $LogPath "unlock-cpu_$stamp.log") -Force | Out-Null }

$bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1

# ---------------------------------------------------------------- RESTORE
if ($Restore) {
    Write-Section 'Restaurar valores anteriores'
    if (-not $BackupFile) { $BackupFile = Join-Path $LogPath 'backup.json' }
    if (-not $BackupFile -or -not (Test-Path $BackupFile)) {
        Write-Err2 "No hay copia de seguridad en $LogPath"
        if (-not $DryRun) { Stop-Transcript | Out-Null }
        exit 1
    }
    $b = Get-Content $BackupFile -Raw | ConvertFrom-Json
    Write-Info "Copia: $BackupFile ($($b.Date))"
    foreach ($s in $b.Settings) {
        if ($DryRun) { Write-Plan "$($s.N): CA $($s.Ac) / CC $($s.Dc)"; continue }
        if (Set-PowerValue $b.Scheme $s.S $s.G $s.Ac $s.Dc $true) { Write-Ok "$($s.N): CA $($s.Ac) / CC $($s.Dc)" }
        else { Write-Warn2 "$($s.N): no se pudo restaurar" }
    }
    if ($DryRun) {
        Write-Plan "Plan $($b.PreviousScheme), modo $($b.OverlayAc)/$($b.OverlayDc), PowerThrottlingOff $($b.PowerThrottlingOff)"
        foreach ($l in $b.LenovoBios) { Write-Plan "BIOS $($l.Name) -> $($l.Value)" }
        exit 0
    }
    Set-Overlay $b.OverlayAc $b.OverlayDc
    if ($null -eq $b.PowerThrottlingOff) { Remove-ItemProperty -Path $ThrottleKey -Name 'PowerThrottlingOff' -ErrorAction SilentlyContinue }
    else { Set-ItemProperty -Path $ThrottleKey -Name 'PowerThrottlingOff' -Value ([int]$b.PowerThrottlingOff) -Type DWord -Force }
    & powercfg /setactive $b.PreviousScheme 2>&1 | Out-Null
    Write-Ok "Plan activo: $(Get-ActiveScheme)"
    foreach ($l in $b.LenovoBios) {
        $r = Set-LenovoBios $l.Name $l.Value
        if ($r -eq 'Success') { Write-Ok "BIOS $($l.Name) -> $($l.Value) (al reiniciar)" } else { Write-Warn2 "BIOS $($l.Name): $r" }
    }
    if ($BackupFile -eq (Join-Path $LogPath 'backup.json')) {
        Rename-Item -Path $BackupFile -NewName "backup_restaurado_$stamp.json" -Force
    }
    Write-Ok 'Restaurado.'
    Stop-Transcript | Out-Null
    exit 0
}

# ---------------------------------------------------------------- DIAGNOSTICO
Write-Section 'Equipo y CPU'
$cs  = Get-CimInstance Win32_ComputerSystem
$oem = "$($cs.Manufacturer) $($cs.Model)".Trim()
Write-Info "Equipo: $oem"
foreach ($cpu in Get-CimInstance Win32_Processor) {
    Write-Info "CPU: $($cpu.Name.Trim()) | base $($cpu.MaxClockSpeed) MHz | ahora $($cpu.CurrentClockSpeed) MHz"
}
try {
    $pi = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'" -ErrorAction Stop
    $perf = [int]$pi.PercentProcessorPerformance
    Write-Info "Rendimiento CPU ahora: $perf % de la base (con carga, por debajo de 100 = limitada; por encima = turbo)"
} catch { Write-Info 'Contador de rendimiento de CPU no disponible.' }
if ($bat) {
    $src = if ($bat.BatteryStatus -eq 1) { 'BATERIA' } else { 'cargador' }
    Write-Info "Portatil: $($bat.EstimatedChargeRemaining) % de bateria, ahora con $src"
} else { Write-Info 'Sin bateria (sobremesa o VM).' }

try {
    $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Processor-Power'; Id = 37; StartTime = (Get-Date).AddDays(-7) } -ErrorAction Stop)
    Write-Warn2 "Eventos 37 en 7 dias: $($ev.Count). El FIRMWARE limita la CPU (temperatura, cargador o bateria). Ultimo: $($ev[0].TimeCreated)"
} catch { Write-Ok 'Sin eventos 37 (el firmware no ha limitado la CPU en 7 dias).' }

Write-Section 'Energia actual'
$active = Get-ActiveScheme
$activeName = ((& powercfg /getactivescheme) -join ' ') -replace '^[^(]*', ''
Write-Info "Plan activo: $active $activeName"
$ov = Get-Overlay
Write-Info "Modo de energia (CA/CC): $($ov.Ac) / $($ov.Dc)"
$pol = Get-ItemProperty -Path $PolicyKey -ErrorAction SilentlyContinue
if ($pol -and $pol.ActivePowerScheme) { Write-Warn2 "Una politica (GPO/Intune) fija el plan $($pol.ActivePowerScheme): puede deshacer el cambio." }
$thr = (Get-ItemProperty -Path $ThrottleKey -ErrorAction SilentlyContinue).PowerThrottlingOff
Write-Info "PowerThrottlingOff: $(if ($null -eq $thr) { 'sin definir (activo)' } else { $thr })"

# ---------------------------------------------------------------- PLAN DESTINO
$target = $active
switch ($Plan) {
    'Auto'     { if ($active -eq $GuidSaver) { $target = $GuidBalanced } }
    'Balanced' { $target = $GuidBalanced }
    'High'     { $target = $GuidHigh }
    'Ultimate' { $target = $GuidUltimateCopy }
}
$needCreate = -not (Test-Scheme $target)
$createFrom = if ($target -eq $GuidUltimateCopy) { $GuidUltimate } else { $target }

Write-Section 'Cambios'
if ($target -ne $active) {
    $m = "Plan: $active -> $target$(if ($needCreate) { ' (se crea)' })"
    if ($DryRun) { Write-Plan $m } else { Write-Info $m }
}
if ($DryRun -and $needCreate) {
    Write-Plan 'Los valores de abajo son los del plan actual; el nuevo se creara al ejecutar.'
}

$doDc = -not $AcOnly
$readScheme = if ($needCreate) { $active } else { $target }
$backup = @()
$changes = @()
foreach ($t in $Targets) {
    $cur = Get-PowerValue $readScheme $t.S $t.G
    if ($null -eq $cur) { Write-Info "$($t.N): no existe en este equipo, se salta"; continue }
    $backup += [pscustomobject]@{ N = $t.N; S = $t.S; G = $t.G; Ac = $cur.Ac; Dc = $cur.Dc }
    $same = ($cur.Ac -eq $t.Ac) -and ((-not $doDc) -or $cur.Dc -eq $t.Dc)
    $line = "{0}: CA {1}->{2}{3}" -f $t.N, $cur.Ac, $t.Ac, $(if ($doDc) { " / CC $($cur.Dc)->$($t.Dc)" } else { '' })
    if ($same) { Write-Ok "$($t.N): ya esta (CA $($cur.Ac) / CC $($cur.Dc))"; continue }
    $changes += $t
    if ($DryRun) { Write-Plan $line } else { Write-Info $line }
}
$ovDc = if ($doDc) { $OverlayBest } else { $ov.Dc }
if ($DryRun) {
    Write-Plan "Modo de energia -> Maximo rendimiento ($OverlayBest) en CA$(if ($doDc) { ' y CC' })"
    Write-Plan 'PowerThrottlingOff -> 1'
}

# Lenovo ThinkPad: control termico en BIOS.
$lenovo = @()
$lenovoLocked = $false
if (-not $SkipBios -and $cs.Manufacturer -match 'LENOVO') {
    $lenovo = @(Get-LenovoThermal | Where-Object { $_.Value -ne 'MaximizePerformance' -and ($doDc -or $_.Name -eq 'AdaptiveThermalManagementAC') })
    if ($lenovo.Count -gt 0) {
        $lenovoLocked = Get-LenovoPasswordSet
        foreach ($l in $lenovo) {
            $m = "BIOS $($l.Name): $($l.Value) -> MaximizePerformance"
            if ($lenovoLocked) { Write-Warn2 "$m (NO: la BIOS tiene contrasena de supervisor; cambiarlo en F1)" }
            elseif ($DryRun) { Write-Plan $m } else { Write-Info $m }
        }
    }
}

if ($DryRun) {
    Write-Section 'DryRun: no se ha cambiado nada'
} else {
    # Copia de seguridad antes de escribir.
    $bk = [pscustomobject]@{
        Date               = (Get-Date).ToString('s')
        Computer           = $env:COMPUTERNAME
        PreviousScheme     = $active
        Scheme             = $target
        OverlayAc          = $ov.Ac
        OverlayDc          = $ov.Dc
        PowerThrottlingOff = $thr
        Settings           = $backup
        LenovoBios         = @($lenovo | Where-Object { -not $lenovoLocked })
    }
    # Solo se guarda el estado ORIGINAL: si ya hay copia pendiente (el script se lanzo antes y
    # no se restauro), se conserva, para que -Restore vuelva a como estaba el equipo al principio.
    $bkFile = Join-Path $LogPath 'backup.json'
    $keepBackup = Test-Path $bkFile
    if ($keepBackup) { Write-Info "Ya hay copia del estado original ($bkFile): se conserva." }
    else {
        $bk | ConvertTo-Json -Depth 5 | Set-Content -Path $bkFile -Encoding UTF8
        Write-Ok "Copia de seguridad: $bkFile"
    }

    if ($needCreate) {
        & powercfg /duplicatescheme $createFrom $target 2>&1 | Out-Null
        if (Test-Scheme $target) { Write-Ok "Plan creado: $target" }
        else { Write-Warn2 "Windows no deja crear el plan $Plan en este equipo. Se queda en $active."; $target = $active }
        $bk.Scheme = $target
        if (-not $keepBackup) { $bk | ConvertTo-Json -Depth 5 | Set-Content -Path $bkFile -Encoding UTF8 }
        if ($target -ne $active) { $changes = $Targets }
    }
    if ($target -ne $active) {
        & powercfg /setactive $target 2>&1 | Out-Null
        if ((Get-ActiveScheme) -eq $target) { Write-Ok "Plan activo: $target" } else { Write-Err2 "No se pudo activar $target" }
    }

    foreach ($t in $changes) {
        if (-not (Set-PowerValue $target $t.S $t.G $t.Ac $t.Dc $doDc)) { Write-Warn2 "$($t.N): Windows no acepta el valor" }
    }
    & powercfg /setactive $target 2>&1 | Out-Null

    Set-Overlay $OverlayBest $ovDc
    if (-not (Test-Path $ThrottleKey)) { New-Item -Path $ThrottleKey -Force | Out-Null }
    Set-ItemProperty -Path $ThrottleKey -Name 'PowerThrottlingOff' -Value 1 -Type DWord -Force

    if (-not $lenovoLocked) {
        foreach ($l in $lenovo) {
            $r = Set-LenovoBios $l.Name 'MaximizePerformance'
            if ($r -eq 'Success') { Write-Ok "BIOS $($l.Name) -> MaximizePerformance (al reiniciar)" } else { Write-Warn2 "BIOS $($l.Name): $r" }
        }
    }

    # ------------------------------------------------------------ VERIFICACION
    Write-Section 'Verificacion (releyendo el estado real)'
    $fail = 0
    foreach ($t in $Targets) {
        $cur = Get-PowerValue $target $t.S $t.G
        if ($null -eq $cur) { continue }
        $ok = ($cur.Ac -eq $t.Ac) -and ((-not $doDc) -or $cur.Dc -eq $t.Dc)
        if ($ok) { Write-Ok "$($t.N): CA $($cur.Ac) / CC $($cur.Dc)" } else { Write-Err2 "$($t.N): CA $($cur.Ac) / CC $($cur.Dc)"; $fail++ }
    }
    $ov2 = Get-Overlay
    if ($ov2.Ac -eq $OverlayBest -and (-not $doDc -or $ov2.Dc -eq $OverlayBest)) { Write-Ok 'Modo de energia: Maximo rendimiento' }
    else { Write-Err2 "Modo de energia: $($ov2.Ac) / $($ov2.Dc)"; $fail++ }
    if ((Get-ItemProperty -Path $ThrottleKey -ErrorAction SilentlyContinue).PowerThrottlingOff -eq 1) { Write-Ok 'Power Throttling desactivado' }
    else { Write-Err2 'Power Throttling sigue activo'; $fail++ }
    if ($target -ne $GuidBalanced) { Write-Info 'El modo de energia de Windows 11 solo actua con el plan Equilibrado; con este plan mandan los valores de arriba.' }
    if ($fail -eq 0) { Write-Ok 'Todo aplicado.' } else { Write-Err2 "$fail ajustes no quedaron como debian." }
}

# ---------------------------------------------------------------- FABRICANTE
Write-Section 'Fabricante'
switch -Regex ($cs.Manufacturer) {
    'LENOVO'    { Write-Info 'Lenovo: en Lenovo Vantage > Dispositivo > Energia, "Smart Performance/Intelligent Cooling" en Rendimiento maximo (o Fn+Q en IdeaPad/Legion hasta el modo rendimiento).' }
    'SAMSUNG'   { Write-Info 'Samsung: Samsung Settings > Modo de rendimiento > Alto rendimiento. No tiene API: hay que hacerlo en la app.' }
    'Microsoft' { Write-Info 'Surface: lo controla el modo de energia de Windows (ya en Maximo rendimiento). Usar el cargador original: con uno de menos vatios la CPU se limita.' }
    '^LG'       { Write-Info 'LG gram: LG Control Center (o LG Smart Assistant) > modo de rendimiento/ventilador en Rendimiento. No tiene API: hay que hacerlo en la app.' }
    default     { Write-Info 'Si el fabricante tiene app de energia propia (Dell Optimizer, HP, MyASUS...), ponerla en rendimiento.' }
}

Write-Section 'Resumen'
if (-not $DryRun) {
    Write-Host "Log y copia: $LogPath" -ForegroundColor Cyan
    Write-Host 'Deshacer: el mismo comando con -Restore' -ForegroundColor Cyan
    Write-Host 'Reiniciar recomendado (obligatorio si se cambio la BIOS de Lenovo).' -ForegroundColor Yellow
}
Write-Host 'Si tras reiniciar la CPU sigue limitada y hay eventos 37: cargador original de los vatios correctos, temperatura (polvo, pasta termica) o bateria.' -ForegroundColor Yellow

if (-not $DryRun) { Stop-Transcript | Out-Null }
