#Requires -RunAsAdministrator

<#
.SYNOPSIS
    [ES] Portatil con la CPU limitada (GHz bajos): quita los topes de energia de la CPU sin sobrecalentarla (Lenovo, Samsung, Surface, LG y cualquier otro).
    [EN] Laptop with a capped CPU (low GHz): removes CPU power caps without overheating it (Lenovo, Samsung, Surface, LG and any other brand).

.DESCRIPTION
    [ES]
    Para el caso "el portatil va lento" con la CPU clavada por debajo de su frecuencia base o
    sin llegar nunca al turbo. Corrige solo lo que limita la CPU por debajo de lo normal y
    respeta lo que el fabricante puso para controlar la temperatura. No toca pantalla, brillo,
    suspension ni hibernacion.

    Por que asi: la temperatura con carga la deciden los limites de potencia del firmware
    (PL1/PL2) y el modo termico del fabricante, no Windows. Lo que si calienta desde Windows es
    (1) no dejar bajar la CPU en reposo (estado minimo alto), (2) el modo "Maximo rendimiento"
    de Windows 11, que el fabricante enlaza a limites de potencia mas altos y que ademas apaga el
    Power Throttling de todas las apps, y (3) los ultimos escalones del turbo, que gastan mucho
    mas por cada MHz. Con Intel Speed Shift (HWP) el modo turbo de Windows apenas cuenta: lo que
    decide cuanto sube la CPU es el EPP.

    Perfil por defecto, sobre el plan activo (o el de -Plan):
      - CPU: minimo 5 % (baja en reposo), maximo 100 %, refrigeracion activa (ventilador antes
        que bajar la frecuencia).
      - EPP: como techo 33 con cargador y 50 en bateria. Solo se baja si el fabricante lo tiene
        mas alto (CPU perezosa); si ya esta mas bajo, se respeta.
      - Turbo: solo se activa si el fabricante lo desactivo.
      - Tope de frecuencia: solo se quita si esta por debajo de la base; uno por encima lo puso
        el fabricante para la temperatura y se respeta. -MaxMHz pone uno a mano.
      - Modo de energia de Windows 11: si esta en "Maximo rendimiento" pasa a Equilibrado.
      - No toca aparcado de nucleos, Power Throttling, PCIe ASPM, ahorro de disco/NVMe, USB ni
        ahorro de bateria. Si una ejecucion anterior (version que lo forzaba todo al 100 %, o
        -Max) los cambio, los devuelve al valor original de la copia de seguridad.
    Si aun asi se calienta demasiado:
      - -MaxMHz <n>: tope de frecuencia (p. ej. 3500 en un portatil cuyo turbo llega a 4,5-5
        GHz). Recorta los escalones mas calientes del turbo con poca perdida en uso de oficina.
      - -Cool: sin turbo (maximo 99 %). Lo mas fresco, pero en un procesador U/P se nota lento.
      - En la app del fabricante, modo equilibrado/optimo (el script dice donde).
    Un poco mas de rendimiento sin subir el techo de calor (la CPU ya no esta limitada y se
    quiere que responda mas): -Epp 15, sin tope. La CPU sube antes y llega al turbo completo en
    los picos de segundos (abrir una app), que no calientan el equipo: la masa del disipador los
    absorbe. Con carga larga y pesada manda el limite de potencia del firmware (PL1/PL2), que
    no se toca y ya baja la frecuencia por debajo del turbo. Lo unico que puede calentar algo
    mas es la carga ligera y continua (Teams, una web pesada): uno o dos nucleos al maximo
    durante minutos. Solo si ahi se nota calor o ventilador, anadir -MaxMHz <unos 200 MHz menos
    que el turbo maximo>; un tope recorta tambien los picos cortos.
    -Max: comportamiento antiguo, todo al maximo tambien en bateria (CPU fija al 100 %, EPP 0,
    sin aparcar nucleos, sin Power Throttling ni ahorro de PCIe/NVMe, "Maximo rendimiento" y
    BIOS Lenovo MaximizePerformance). Solo sobremesa o pruebas: un portatil fino llega a 90-100
    grados.

    Diagnostica primero: CPU, frecuencia base y actual, % de rendimiento (por encima de 100 =
    turbo), temperatura, plan y modo de energia, si hay politica (GPO/Intune) que fije el plan y
    los eventos 37 de Kernel-Processor-Power de los ultimos 7 dias (el firmware esta limitando la
    CPU: temperatura, cargador flojo o bateria).
    Actualizaciones (solo lectura): fecha de la BIOS, y en Lenovo compara BIOS y drivers con el
    catalogo oficial del modelo (el de System Update). En cualquier marca busca drivers y firmware
    pendientes en Windows Update; con -InstallDrivers los instala.

    Antes de escribir guarda los valores originales en un .json (solo la primera vez, para que
    -Restore vuelva siempre al estado de fabrica). Con -DryRun solo diagnostica y ensena lo que
    cambiaria.

    Si tras esto la CPU sigue limitada y salen eventos 37, no es software: cargador de menos
    vatios que el original, temperatura (polvo, pasta termica) o bateria degradada.

    [EN]
    For "the laptop is slow" with the CPU stuck below its base clock or never reaching turbo.
    Fixes only what holds the CPU below normal and respects what the OEM set for thermals.
    Load temperature is set by firmware power limits (PL1/PL2) and the OEM thermal mode; from
    Windows, heat comes from a high minimum state, the Windows 11 "Best performance" mode (tied
    by OEMs to higher power limits, and it turns Power Throttling off) and the top turbo bins.
    With Intel Speed Shift (HWP) the Windows boost mode barely matters; EPP decides.
    Default profile: min state 5 %, max 100 %, active cooling; EPP capped at 33 on AC / 50 on
    battery (only lowered when the OEM set it higher); boost only enabled if the OEM disabled it;
    frequency cap only removed when below base clock; "Best performance" mode goes back to
    Balanced. Core parking, Power Throttling, PCIe ASPM, disk/NVMe, USB and battery saver are left
    alone, and values an older run (or -Max) changed are restored from the backup. Still too hot:
    -MaxMHz <n> caps the clock (trims the hottest turbo bins), -Cool disables turbo (max state
    99 %), and the OEM app should be on its balanced mode. A bit more performance without a
    higher heat ceiling: -Epp 15 with no cap (faster ramp-up and full turbo on second-long
    bursts, which the heatsink absorbs; long heavy loads stay under the untouched firmware power
    limits). Only if long light loads (Teams, heavy web pages) run hot, add -MaxMHz <about
    200 MHz below max turbo>; a cap also trims short bursts. -Max keeps the old everything-at-100 %
    behaviour (desktops or tests only). Diagnosis shows clocks, temperature, power plan and mode,
    GPO/Intune pinning and event 37. Update check (read only) for BIOS and drivers (Lenovo catalog
    and Windows Update; -InstallDrivers installs). Original values are saved once to a .json;
    -Restore puts them back. -DryRun only diagnoses. Display, brightness, sleep and hibernate are
    left as they are.

.PARAMETER DryRun
    [ES] Solo diagnostico y plan de cambios. No escribe nada.
    [EN] Diagnosis and change plan only. Writes nothing.

.PARAMETER Restore
    [ES] Devuelve los valores guardados en la ultima ejecucion (o en -BackupFile).
    [EN] Restores the values saved by the last run (or by -BackupFile).

.PARAMETER Plan
    [ES] Plan de energia: Auto (el activo; si es Economizador pasa a Equilibrado), Balanced, High o Ultimate. El modo de Windows 11 solo actua sobre Equilibrado.
    [EN] Power plan: Auto (the active one; Power saver becomes Balanced), Balanced, High or Ultimate. The Windows 11 power mode only works on Balanced.

.PARAMETER Max
    [ES] Todo al maximo en corriente y bateria (CPU fija al 100 %, EPP 0, sin aparcar nucleos, sin Power Throttling, sin ahorro de PCIe/NVMe, BIOS Lenovo en bateria). Calienta mucho: solo sobremesa o pruebas.
    [EN] Everything at maximum on AC and battery (CPU pinned at 100 %, EPP 0, no core parking, no Power Throttling, no PCIe/NVMe power saving, Lenovo BIOS on battery). Runs hot: desktops or tests only.

.PARAMETER Cool
    [ES] Ademas del perfil por defecto, sin turbo (maximo 99 %): la CPU se queda en su frecuencia base. Lo mas fresco; en un procesador U/P se nota lento. Probar antes -MaxMHz.
    [EN] On top of the default profile, no turbo (max state 99 %): the CPU stays at base clock. Coolest option; feels slow on U/P chips. Try -MaxMHz first.

.PARAMETER MaxMHz
    [ES] Tope de frecuencia en MHz (nucleos P y E), p. ej. 3500. Recorta los escalones del turbo que mas calientan. Sin el, se respeta el tope del fabricante.
    [EN] Clock cap in MHz (P and E cores), e.g. 3500. Trims the hottest turbo bins. Without it the OEM cap is kept.

.PARAMETER Epp
    [ES] EPP con cargador (0 = rendimiento, 100 = ahorro), p. ej. 15: la CPU sube antes y mas en cargas cortas (abrir apps, navegar, Excel). En bateria sigue el perfil (50 como techo). El limite de potencia del firmware no cambia, asi que el maximo de temperatura tampoco; con carga ligera y continua puede gastar algo mas y el ventilador entrar antes. Sin tope los picos cortos van al turbo completo; -MaxMHz solo si esa carga continua calienta.
    [EN] EPP on AC (0 = performance, 100 = power saving), e.g. 15: the CPU ramps up sooner and higher on short loads. Battery keeps the profile (50 as a ceiling). Firmware power limits do not change, so the temperature ceiling does not either; long light loads may draw a bit more and spin the fan sooner. Without a cap short bursts get full turbo; add -MaxMHz only if that continuous load runs hot.

.PARAMETER AcOnly
    [ES] Aplica solo con el cargador conectado; en bateria deja los valores de Windows.
    [EN] Applies on AC only; on battery Windows values are kept.

.PARAMETER SkipBios
    [ES] No toca la BIOS de Lenovo.
    [EN] Does not touch the Lenovo BIOS.

.PARAMETER SkipUpdateCheck
    [ES] No busca actualizaciones de BIOS ni drivers (ahorra 1-5 minutos).
    [EN] Skips the BIOS and driver update check (saves 1-5 minutes).

.PARAMETER InstallDrivers
    [ES] Instala los drivers y el firmware pendientes de Windows Update. Los de Lenovo los indica, no los instala.
    [EN] Installs pending drivers and firmware from Windows Update. Lenovo catalog items are reported, not installed.

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
    .\05-unlock-cpu-performance.ps1 -MaxMHz 3500

.EXAMPLE
    .\05-unlock-cpu-performance.ps1 -Epp 15

.EXAMPLE
    .\05-unlock-cpu-performance.ps1 -Cool

.EXAMPLE
    .\05-unlock-cpu-performance.ps1 -Restore

.EXAMPLE
    .\05-unlock-cpu-performance.ps1 -InstallDrivers

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
    [switch]$Max,
    [switch]$Cool,
    [ValidateRange(800, 6500)]
    [int]$MaxMHz,
    [ValidateRange(0, 100)]
    [int]$Epp,
    [switch]$AcOnly,
    [switch]$SkipBios,
    [switch]$SkipUpdateCheck,
    [switch]$InstallDrivers,
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

# Ajuste, valor en corriente (Ac) y en bateria (Dc) del perfil por defecto, y XAc/XDc con -Max.
# Ac = $null: el perfil por defecto no lo toca (solo -Max). Los que no existan se saltan.
# K dice como se aplica en el perfil por defecto (con -Max siempre se fija el valor):
#   (vacio) se fija el valor.
#   ceil    techo: solo se baja si el fabricante lo tiene mas alto (EPP: 0 = rendimiento,
#           100 = ahorro; con Intel Speed Shift/HWP es lo que decide cuanto sube la CPU).
#   turbo   solo se activa si esta desactivado (0). Con HWP 2 y 4 se comportan igual
#           (Microsoft: options-for-perf-state-engine-perfboostmode); 4 es "eficiente" en
#           CPUs antiguas sin HWP.
#   freqcap tope en MHz: solo se quita si esta por debajo de la base (la CPU no llegaria ni a
#           su frecuencia nominal); un tope por encima de la base lo puso el fabricante para
#           controlar la temperatura y se respeta. -MaxMHz lo fija.
$Targets = @(
    @{ N = 'CPU estado minimo';               S = $SubProc; G = '893dee8e-2bef-41e0-89c6-b55d0929964c'; Ac = 5;     Dc = 5;     XAc = 100; XDc = 100 }
    @{ N = 'CPU estado minimo (nucleos E)';   S = $SubProc; G = '893dee8e-2bef-41e0-89c6-b55d0929964d'; Ac = 5;     Dc = 5;     XAc = 100; XDc = 100 }
    @{ N = 'CPU estado maximo';               S = $SubProc; G = 'bc5038f7-23e0-4960-96da-33abaf5935ec'; Ac = 100;   Dc = 100 }
    @{ N = 'CPU estado maximo (nucleos E)';   S = $SubProc; G = 'bc5038f7-23e0-4960-96da-33abaf5935ed'; Ac = 100;   Dc = 100 }
    @{ N = 'CPU tope de frecuencia (0=sin)';  S = $SubProc; G = '75b0ae3f-bce0-45a7-8c89-c9611c25e100'; Ac = 0;     Dc = 0;     K = 'freqcap' }
    @{ N = 'CPU tope de frecuencia (E)';      S = $SubProc; G = '75b0ae3f-bce0-45a7-8c89-c9611c25e101'; Ac = 0;     Dc = 0;     K = 'freqcap' }
    @{ N = 'CPU turbo';                       S = $SubProc; G = 'be337238-0d82-4146-a960-4f3749d470c7'; Ac = 4;     Dc = 4;     XAc = 2;   XDc = 2;   K = 'turbo' }
    @{ N = 'CPU politica de turbo';           S = $SubProc; G = '45bcc044-d885-43e2-8605-ee0ec6e96b59'; Ac = $null; Dc = $null; XAc = 100; XDc = 100 }
    @{ N = 'CPU EPP';                         S = $SubProc; G = '36687f9e-e3a5-4dbf-b1dc-15eb381c6863'; Ac = 33;    Dc = 50;    XAc = 0;   XDc = 0;   K = 'ceil' }
    @{ N = 'CPU EPP (nucleos E)';             S = $SubProc; G = '36687f9e-e3a5-4dbf-b1dc-15eb381c6864'; Ac = 33;    Dc = 50;    XAc = 0;   XDc = 0;   K = 'ceil' }
    @{ N = 'CPU nucleos sin aparcar (%)';     S = $SubProc; G = '0cc5b647-c1df-4637-891a-dec35c318583'; Ac = $null; Dc = $null; XAc = 100; XDc = 100 }
    @{ N = 'CPU nucleos sin aparcar E (%)';   S = $SubProc; G = '0cc5b647-c1df-4637-891a-dec35c318584'; Ac = $null; Dc = $null; XAc = 100; XDc = 100 }
    @{ N = 'Refrigeracion (1=activa)';        S = $SubProc; G = '94d3a615-a899-4ac5-ae2b-e4d8f634367f'; Ac = 1;     Dc = 1 }
    @{ N = 'Disco: apagar tras (0=nunca)';    S = $SubDisk; G = '6738e2c4-e8a5-4a42-b16a-e040e769756e'; Ac = $null; Dc = $null; XAc = 0;   XDc = 0 }
    @{ N = 'AHCI ahorro de enlace (0=no)';    S = $SubDisk; G = '0b2d69d7-a2a1-449c-9680-f91c70521c60'; Ac = $null; Dc = $null; XAc = 0;   XDc = 0 }
    @{ N = 'AHCI ahorro adaptativo (0=no)';   S = $SubDisk; G = 'dab60367-53fe-4fbc-825e-521d069d2456'; Ac = $null; Dc = $null; XAc = 0;   XDc = 0 }
    @{ N = 'NVMe NOPPME (0=no)';              S = $SubDisk; G = 'fc7372b6-ab2d-43ee-8797-15e9841f2cca'; Ac = $null; Dc = $null; XAc = 0;   XDc = 0 }
    @{ N = 'NVMe APST primario (0=no)';       S = $SubDisk; G = 'd639518a-e56d-4345-8af2-b9f32fb26109'; Ac = $null; Dc = $null; XAc = 0;   XDc = 0 }
    @{ N = 'NVMe APST secundario (0=no)';     S = $SubDisk; G = 'd3d55efd-c1ff-424e-9dc3-441be7833010'; Ac = $null; Dc = $null; XAc = 0;   XDc = 0 }
    @{ N = 'PCIe ASPM (0=no)';                S = $SubPci;  G = 'ee12f906-d277-404b-b6da-e5fa1a576df5'; Ac = $null; Dc = $null; XAc = 0;   XDc = 0 }
    @{ N = 'USB suspension selectiva (0=no)'; S = $SubUsb;  G = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'; Ac = $null; Dc = $null; XAc = 0;   XDc = 0 }
    @{ N = 'Ahorro de energia auto (0=nunca)';S = $SubSave; G = 'e69653ca-cf7f-4f05-aa73-cb833fa90ad4'; Ac = $null; Dc = $null; XAc = 0;   XDc = 0 }
)
$EppSet = $PSBoundParameters.ContainsKey('Epp')
if ($Max -and ($Cool -or $MaxMHz -or $EppSet)) { Write-Host '[ERROR] -Max no se combina con -Cool, -MaxMHz ni -Epp: elegir uno.' -ForegroundColor Red; exit 1 }
if ($Max) { foreach ($t in $Targets) { if ($t.ContainsKey('XAc')) { $t.Ac = $t.XAc; $t.Dc = $t.XDc } } }
# -Cool: maximo al 99 % = sin turbo. La CPU se queda en su frecuencia base; lo mas fresco, pero
# en un procesador U/P (base 1,3-2,5 GHz) se nota lento. Probar antes -MaxMHz.
if ($Cool) { foreach ($t in $Targets) { if ($t.N -like 'CPU estado maximo*') { $t.Ac = 99; $t.Dc = 99 } } }
$Targets = @($Targets | Where-Object { $null -ne $_.Ac })

# Valor final de un ajuste segun su tipo (K) y el valor actual. Ver la tabla de arriba.
function Get-Desired($t, $cur) {
    $r = @{ Ac = $t.Ac; Dc = $t.Dc }
    if ($t.K -eq 'freqcap' -and $MaxMHz) { return @{ Ac = $MaxMHz; Dc = $MaxMHz } }
    if ($Max -or -not $t.K) { return $r }
    # Se parte del valor ORIGINAL (copia de una ejecucion anterior) si lo hay: asi un -Max o un
    # -MaxMHz de antes no se queda puesto al volver al perfil normal.
    $orig = $null
    if ($prev) { $orig = @($prev.Settings) | Where-Object { $_ -and $_.G -eq $t.G } | Select-Object -First 1 }
    foreach ($side in 'Ac', 'Dc') {
        $c = if ($orig -and $null -ne $orig.$side) { $orig.$side } else { $cur.$side }
        if ($null -eq $c) { continue }
        switch ($t.K) {
            'ceil'    { if ($c -lt $r[$side]) { $r[$side] = $c } }
            'turbo'   { if ($c -ne 0) { $r[$side] = $c } }
            'freqcap' { if ($c -eq 0 -or -not $baseMHz -or $c -ge $baseMHz) { $r[$side] = [int]$c } }
        }
    }
    # -Epp: valor exacto con cargador (lo pide el tecnico, no es techo). La bateria sigue igual.
    if ($t.K -eq 'ceil' -and $EppSet) { $r.Ac = $Epp }
    return $r
}

function Get-ActiveScheme {
    $o = (& powercfg /getactivescheme) -join ' '
    if ($o -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { return $Matches[1].ToLower() }
    return $null
}

function Test-Scheme([string]$guid) {
    return (((& powercfg /list) -join "`n") -match [regex]::Escape($guid))
}

# Devuelve @{Ac;Dc} o $null si el ajuste no existe. Las dos ultimas lineas de la salida son
# los indices actuales en CA y CC en cualquier idioma de Windows. En un modo de energia
# (overlay) un valor no definido sale como "Ninguno"/"None": queda en $null.
# Con un modo de energia activo, lo que se lee del plan es el valor EFECTIVO (el modo manda
# sobre el plan en los ajustes que define, p. ej. EPP y nucleos aparcados en un LG).
function Get-PowerValue([string]$scheme, [string]$sub, [string]$setting) {
    $o = & powercfg /qh $scheme $sub $setting 2>&1
    if ($LASTEXITCODE -ne 0) { return $null }
    $lines = @($o | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    if ($lines.Count -lt 2) { return $null }
    $v = foreach ($l in $lines[-2], $lines[-1]) {
        if ($l -match '0x([0-9a-fA-F]{8})\s*$') { [Convert]::ToInt32($Matches[1], 16) } else { $null }
    }
    if ($null -eq $v[0] -and $null -eq $v[1]) { return $null }
    return @{ Ac = $v[0]; Dc = $v[1] }
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

function Get-OverlayName([string]$g) {
    switch ($g) {
        'ded574b5-45a0-4f42-8737-46345c09c238' { 'Maximo rendimiento' }
        '961cc777-2547-4f9d-8174-7d86181b8a7a' { 'Maxima eficiencia' }
        default { 'Equilibrado' }
    }
}

function Get-Overlay {
    $p = Get-ItemProperty -Path $OverlayKey -ErrorAction SilentlyContinue
    return @{ Ac = $p.ActiveOverlayAcPowerScheme; Dc = $p.ActiveOverlayDcPowerScheme }
}

# Ejecuta lineas de cmd como SYSTEM con una tarea programada de un solo uso; borra la tarea
# y el .cmd despues. La clave PowerSchemes y sus valores solo los escribe SYSTEM.
function Invoke-AsSystem([string[]]$cmdLines) {
    $id = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $name = "SCRIPTS-SUPPORT_CX-$id"
    $dir = Join-Path $env:ProgramData 'SCRIPTS-SUPPORT_CX'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $cmd = Join-Path $dir "sys-$id.cmd"
    [IO.File]::WriteAllText($cmd, "@echo off`r`n" + ($cmdLines -join "`r`n") + "`r`n", [Text.Encoding]::ASCII)
    try {
        $a = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\cmd.exe" -Argument "/c `"$cmd`""
        $p = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName $name -Action $a -Principal $p -Force -ErrorAction Stop | Out-Null
        Start-ScheduledTask -TaskName $name -ErrorAction Stop
        $sw = [Diagnostics.Stopwatch]::StartNew()
        do { Start-Sleep -Milliseconds 300; $t = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue }
        while ($t -and $t.State -eq 'Running' -and $sw.Elapsed.TotalSeconds -lt 20)
        Start-Sleep -Milliseconds 300
    } finally {
        Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item $cmd -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-RegAsSystem([string]$regArgs) { Invoke-AsSystem @("reg $regArgs") }

function Test-PowerMatch($cur, [int]$ac, [int]$dc, [bool]$doDc) {
    if ($null -eq $cur) { return $false }
    return ($cur.Ac -eq $ac) -and ((-not $doDc) -or $cur.Dc -eq $dc)
}

# powercfg /qh devuelve el valor EFECTIVO, que puede no ser el guardado: en un LG gram se leyo
# EPP 25 y, al recargar el plan, paso a 33 (el valor que habia escrito en el registro una
# ejecucion anterior). Si el registro tiene un valor propio para el ajuste, tiene que coincidir
# tambien; si no hay valor propio, vale lo efectivo.
function Test-StoredMatch([string]$scheme, [string]$sub, [string]$setting, [int]$ac, [int]$dc, [bool]$doDc) {
    $p = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$scheme\$sub\$setting"
    $r = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue
    if (-not $r) { return $true }
    if ($null -ne $r.ACSettingIndex -and [int]$r.ACSettingIndex -ne $ac) { return $false }
    if ($doDc -and $null -ne $r.DCSettingIndex -and [int]$r.DCSettingIndex -ne $dc) { return $false }
    return $true
}

# Modo de energia de Windows 11: vacio, $null y el GUID de ceros son lo mismo (Equilibrado).
# Al aplicarlo con la API, Windows escribe el GUID de ceros donde antes no habia nada.
function ConvertTo-OverlayKey($g) {
    $s = "$g".Trim().ToLower()
    if (-not $s -or $s -eq '00000000-0000-0000-0000-000000000000') { return '' }
    return $s
}

# powercfg devuelve 0 pero NO cambia los ajustes que el fabricante dejo preconfigurados
# (User\Default\PowerSchemes; visto en un LG gram con EPP y nucleos aparcados). Lo que tras
# powercfg no queda como se pidio se escribe en el registro como SYSTEM, todo en UNA tarea
# programada (antes una por ajuste: varios segundos cada una), y se recarga el plan.
# Lo que ya tiene el valor pedido no se escribe.
# Devuelve hashtable "plan|ajuste" -> 'ok', 'reinicio' (escrito, Windows lo aplicara al
# reiniciar) o 'fallo'.
function New-PowerItem([string]$scheme, [string]$sub, [string]$setting, $ac, $dc, [bool]$doDc) {
    return [pscustomobject]@{ Scheme = $scheme; S = $sub; G = $setting; Ac = [int]$ac; Dc = [int]$dc; DoDc = $doDc }
}

function Set-PowerValuesForced($items) {
    $res = @{}
    $pending = @()
    foreach ($i in @($items)) {
        if (-not $i) { continue }
        $k = "$($i.Scheme)|$($i.G)"
        $stored = Test-StoredMatch $i.Scheme $i.S $i.G $i.Ac $i.Dc $i.DoDc
        if ($stored -and (Test-PowerMatch (Get-PowerValue $i.Scheme $i.S $i.G) $i.Ac $i.Dc $i.DoDc)) { $res[$k] = 'ok'; continue }
        [void](Set-PowerValue $i.Scheme $i.S $i.G $i.Ac $i.Dc $i.DoDc)
        $stored = Test-StoredMatch $i.Scheme $i.S $i.G $i.Ac $i.Dc $i.DoDc
        if ($stored -and (Test-PowerMatch (Get-PowerValue $i.Scheme $i.S $i.G) $i.Ac $i.Dc $i.DoDc)) { $res[$k] = 'ok' } else { $pending += $i }
    }
    if ($pending.Count -eq 0) { return $res }
    $lines = @()
    foreach ($i in $pending) {
        $key = "HKLM\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$($i.Scheme)\$($i.S)\$($i.G)"
        $lines += "reg add $key /v ACSettingIndex /t REG_DWORD /d $($i.Ac) /f"
        if ($i.DoDc) { $lines += "reg add $key /v DCSettingIndex /t REG_DWORD /d $($i.Dc) /f" }
    }
    Invoke-AsSystem $lines
    & powercfg /setactive SCHEME_CURRENT 2>&1 | Out-Null
    foreach ($i in $pending) {
        $k = "$($i.Scheme)|$($i.G)"
        $p = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$($i.Scheme)\$($i.S)\$($i.G)"
        $r = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue
        $saved = $r -and $r.ACSettingIndex -eq $i.Ac -and ((-not $i.DoDc) -or $r.DCSettingIndex -eq $i.Dc)
        $now = Test-PowerMatch (Get-PowerValue $i.Scheme $i.S $i.G) $i.Ac $i.Dc $i.DoDc
        $res[$k] = if ($saved -and $now) { 'ok' } elseif ($saved) { 'reinicio' } else { 'fallo' }
    }
    return $res
}

function Set-Overlay([string]$ac, [string]$dc) {
    $isSystem = ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-18')
    $regKey = 'HKLM\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
    $changed = $false
    foreach ($p in @(@('ActiveOverlayAcPowerScheme', $ac), @('ActiveOverlayDcPowerScheme', $dc))) {
        $cur = (Get-ItemProperty -Path $OverlayKey -ErrorAction SilentlyContinue).($p[0])
        if ((ConvertTo-OverlayKey $cur) -eq (ConvertTo-OverlayKey $p[1])) { continue }
        $changed = $true
        if ($isSystem) {
            if ($p[1]) { Set-ItemProperty -Path $OverlayKey -Name $p[0] -Value $p[1] -Type String -Force }
            else { Remove-ItemProperty -Path $OverlayKey -Name $p[0] -ErrorAction SilentlyContinue }
        } elseif ($p[1]) { Invoke-RegAsSystem "add $regKey /v $($p[0]) /t REG_SZ /d $($p[1]) /f" }
        else { Invoke-RegAsSystem "delete $regKey /v $($p[0]) /f" }
    }
    # El registro guarda los dos; la API de Windows (la que usa Configuracion) lo aplica ya
    # para la fuente de energia actual. powercfg no tiene opcion para esto.
    # Solo si algo cambio: llamarla sin cambios recarga el modo y en un LG gram devolvio el EPP
    # efectivo de 25 a 33 (la CPU quedaba algo mas lenta que antes de lanzar el script).
    if (-not $changed) { return }
    $now =if ($bat -and $bat.BatteryStatus -eq 1) { $dc } else { $ac }
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

# ---------------------------------------------------------------- ACTUALIZACIONES (funciones)
function Get-XmlFromUrl([string]$url) {
    # Bytes y UTF-8 a mano: en 5.1 Invoke-WebRequest decodifica como ISO-8859-1 y el BOM de
    # los XML de Lenovo llega como basura que rompe el [xml].
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
    $wc = New-Object Net.WebClient
    try { $bytes = $wc.DownloadData($url) } finally { $wc.Dispose() }
    $t = [Text.Encoding]::UTF8.GetString($bytes)
    return [xml]($t.TrimStart([char]0xFEFF))
}

function Test-AnyLike([string]$value, $patterns) {
    foreach ($p in @($patterns)) { if ($p -and $value -like ([string]$p).Trim()) { return $true } }
    return $false
}

# Descarga varias URL a la vez (8 hilos). Devuelve hashtable url -> texto; la que falla no sale.
# Los XML de un catalogo de Lenovo son 50-150: de uno en uno tardaba minutos.
function Get-TextBatch([string[]]$urls, [int]$threads = 8) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
    if ([Net.ServicePointManager]::DefaultConnectionLimit -lt $threads) { [Net.ServicePointManager]::DefaultConnectionLimit = $threads }
    $pool = [runspacefactory]::CreateRunspacePool(1, $threads)
    $pool.Open()
    $jobs = foreach ($u in @($urls | Where-Object { $_ } | Select-Object -Unique)) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        [void]$ps.AddScript({
            param($url)
            $wc = New-Object Net.WebClient
            try { [Text.Encoding]::UTF8.GetString($wc.DownloadData($url)).TrimStart([char]0xFEFF) } catch { $null } finally { $wc.Dispose() }
        }).AddArgument($u)
        [pscustomobject]@{ Url = $u; Ps = $ps; H = $ps.BeginInvoke() }
    }
    $out = @{}
    foreach ($j in @($jobs)) {
        if ($j.H.AsyncWaitHandle.WaitOne(60000)) {
            $r = @($j.Ps.EndInvoke($j.H))
            if ($r.Count -and $r[0]) { $out[$j.Url] = [string]$r[0] }
            $j.Ps.Dispose()
        } else { [void]$j.Ps.BeginStop($null, $null) }
    }
    $pool.Close()
    return $out
}

# -1 = lo instalado es mas viejo; 0 = igual o mas nuevo; $null = no se puede comparar.
function Compare-DriverVersion([string]$installed, [string]$available) {
    $a = ($installed -replace '[^\d\.]', '').Trim('.')
    $b = ($available -replace '[^\d\.]', '').Trim('.')
    try { if ([version]$a -lt [version]$b) { return -1 } else { return 0 } } catch { return $null }
}

# Catalogo oficial de Lenovo por modelo (el mismo que usan System Update y Thin Installer):
# BIOS por patron de version y drivers por Hardware ID + version minima.
function Get-LenovoCatalogUpdates {
    $mtm = (($cs.Model -replace '\s', '') + '    ').Substring(0, 4)
    $os = if ([Environment]::OSVersion.Version.Build -ge 22000) { 'Win11' } else { 'Win10' }
    $res = [pscustomobject]@{ Catalog = $null; Pending = @(); Checked = 0; Skipped = 0; Error = $null }
    $url = "https://download.lenovo.com/catalog/${mtm}_$os.xml"
    try { $cat = Get-XmlFromUrl $url; $res.Catalog = $url }
    catch { $res.Error = "Lenovo no publica catalogo para $mtm ($os): $($_.Exception.Message)"; return $res }

    $biosVer = ([string](Get-CimInstance Win32_BIOS).SMBIOSBIOSVersion).Trim()
    $signed = @{}
    foreach ($d in Get-CimInstance Win32_PnPSignedDriver -Property DeviceID, DriverVersion, DriverDate) { if ($d.DeviceID) { $signed[$d.DeviceID.ToUpper()] = $d } }
    $hw = New-Object System.Collections.ArrayList
    foreach ($e in Get-CimInstance Win32_PnPEntity -Property DeviceID, HardwareID) {
        foreach ($h in @($e.HardwareID)) { if ($h) { [void]$hw.Add(@($h.ToUpper(), $e.DeviceID.ToUpper())) } }
    }

    $pkgXml = Get-TextBatch @($cat.packages.package | ForEach-Object { [string]$_.location })
    foreach ($p in @($cat.packages.package)) {
        $txt = $pkgXml[[string]$p.location]
        if (-not $txt) { $res.Skipped++; continue }
        try { $x = [xml]$txt } catch { $res.Skipped++; continue }
        $titleNode = $x.SelectSingleNode('/Package/Title/Desc')
        $title = if ($titleNode) { $titleNode.InnerText.Trim() } else { $x.Package.name }
        $date = [string]$x.Package.ReleaseDate
        $pkgVer = [string]$x.Package.version

        $bios = @($x.SelectNodes('/Package/DetectInstall//_Bios/Level') | ForEach-Object { $_.InnerText })
        if ($bios.Count -gt 0) {
            $res.Checked++
            if (Test-AnyLike $biosVer $bios) { continue }
            $dep = @($x.SelectNodes('/Package/Dependencies//_Bios/Level') | ForEach-Object { $_.InnerText })
            if ($dep.Count -eq 0 -or (Test-AnyLike $biosVer $dep)) {
                $res.Pending += [pscustomobject]@{ Type = 'BIOS'; Name = $title; Installed = $biosVer; Available = $pkgVer; Date = $date }
            }
            continue
        }

        $drv = $x.SelectSingleNode('/Package/DetectInstall//_Driver')
        if (-not $drv) { $res.Skipped++; continue }
        $ids = @($drv.SelectNodes('HardwareID') | ForEach-Object { $_.InnerText.Trim().ToUpper() })
        $verNode = $drv.SelectSingleNode('Version')
        $dateNode = $drv.SelectSingleNode('Date')
        $want = if ($verNode) { $verNode.InnerText -replace '\^', '' } else { $null }
        $devId = $null
        foreach ($pair in $hw) {
            foreach ($id in $ids) { if ($pair[0].StartsWith($id)) { $devId = $pair[1]; break } }
            if ($devId) { break }
        }
        if (-not $devId) { continue }   # este equipo no tiene ese hardware
        $res.Checked++
        $inst = $signed[$devId]
        $instVer = if ($inst) { [string]$inst.DriverVersion } else { '' }
        $old = $false
        if ($want -and $instVer) { $old = ((Compare-DriverVersion $instVer $want) -eq -1) }
        elseif ($dateNode -and $inst -and $inst.DriverDate) {
            try { $old = ([datetime]$inst.DriverDate -lt [datetime]$dateNode.InnerText) } catch {}
        } elseif (-not $instVer) { $old = $true }
        if ($old) {
            $res.Pending += [pscustomobject]@{ Type = 'Driver'; Name = $title; Installed = $(if ($instVer) { $instVer } else { 'sin driver' }); Available = $want; Date = $date }
        }
    }
    return $res
}

# Drivers y firmware pendientes en Windows Update. La busqueda tarda de uno a varios minutos:
# arranca en segundo plano al empezar y se recoge al final, mientras se cambia la energia. Con
# plazo: si el servicio se cuelga, el script sigue en vez de esperar sin fin.
function Start-WuDriverSearch {
    $ps = [powershell]::Create()
    [void]$ps.AddScript({
        $s = New-Object -ComObject Microsoft.Update.Session
        $q = $s.CreateUpdateSearcher()
        try { $q.ServerSelection = 2 } catch {}
        $r = $q.Search("IsInstalled=0 and Type='Driver' and IsHidden=0")
        foreach ($u in $r.Updates) {
            [pscustomobject]@{ Title = $u.Title; Class = $u.DriverClass; Date = $u.DriverVerDate; Id = $u.Identity.UpdateID }
        }
    })
    return [pscustomobject]@{ Ps = $ps; H = $ps.BeginInvoke(); Sw = [Diagnostics.Stopwatch]::StartNew() }
}

function Receive-WuDriverSearch($job, [int]$TimeoutSec = 180) {
    $left = [math]::Max(1, $TimeoutSec - [int]$job.Sw.Elapsed.TotalSeconds)
    if (-not $job.H.IsCompleted) { Write-Info "Esperando a Windows Update (como mucho $left s mas; -SkipUpdateCheck lo salta)..." }
    if (-not $job.H.AsyncWaitHandle.WaitOne($left * 1000)) {
        [void]$job.Ps.BeginStop($null, $null)
        throw "no respondio en $TimeoutSec s; mirar en Configuracion > Windows Update"
    }
    $out = @($job.Ps.EndInvoke($job.H))
    $err = if ($job.Ps.Streams.Error.Count) { $job.Ps.Streams.Error[0].Exception.Message } else { $null }
    $job.Ps.Dispose()
    if ($err -and $out.Count -eq 0) { throw $err }
    return $out
}

function Install-WuDriverUpdates([string[]]$ids) {
    $s = New-Object -ComObject Microsoft.Update.Session
    $q = $s.CreateUpdateSearcher()
    try { $q.ServerSelection = 2 } catch {}
    $r = $q.Search("IsInstalled=0 and Type='Driver' and IsHidden=0")
    $col = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $r.Updates) {
        if ($ids -contains $u.Identity.UpdateID) {
            if (-not $u.EulaAccepted) { $u.AcceptEula() }
            [void]$col.Add($u)
        }
    }
    if ($col.Count -eq 0) { return $null }
    $d = $s.CreateUpdateDownloader(); $d.Updates = $col; [void]$d.Download()
    $i = $s.CreateUpdateInstaller(); $i.Updates = $col
    $ir = $i.Install()
    $list = for ($k = 0; $k -lt $col.Count; $k++) {
        [pscustomobject]@{ Title = $col.Item($k).Title; Code = $ir.GetUpdateResult($k).ResultCode }
    }
    return [pscustomobject]@{ Results = $list; Reboot = $ir.RebootRequired }
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
    if ($DryRun) {
        foreach ($s in $b.Settings) { Write-Plan "$($s.N): CA $($s.Ac) / CC $($s.Dc)" }
        Write-Plan "Plan $($b.PreviousScheme), modo $($b.OverlayAc)/$($b.OverlayDc), PowerThrottlingOff $($b.PowerThrottlingOff)"
        foreach ($l in $b.LenovoBios) { Write-Plan "BIOS $($l.Name) -> $($l.Value)" }
        exit 0
    }
    $items = @(foreach ($s in $b.Settings) { New-PowerItem $b.Scheme $s.S $s.G $s.Ac $s.Dc $true })
    foreach ($s in @($b.OverlaySettings)) {
        if (-not $s) { continue }
        $base = @($b.Settings) | Where-Object { $_.G -eq $s.G } | Select-Object -First 1
        $ac = if ($null -ne $s.Ac) { $s.Ac } elseif ($base) { $base.Ac } else { $null }
        $dc = if ($null -ne $s.Dc) { $s.Dc } elseif ($base) { $base.Dc } else { $null }
        if ($null -ne $ac -and $null -ne $dc) { $items += New-PowerItem $OverlayBest $s.S $s.G $ac $dc $true }
    }
    $res = Set-PowerValuesForced $items
    foreach ($s in $b.Settings) {
        $r = $res["$($b.Scheme)|$($s.G)"]
        if ($r -eq 'ok') { Write-Ok "$($s.N): CA $($s.Ac) / CC $($s.Dc)" }
        elseif ($r -eq 'reinicio') { Write-Ok "$($s.N): CA $($s.Ac) / CC $($s.Dc) (al reiniciar)" }
        else { Write-Warn2 "$($s.N): no se pudo restaurar" }
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
$wuJob = $null
if (-not $SkipUpdateCheck) { try { $wuJob = Start-WuDriverSearch } catch {} }
Write-Section 'Equipo y CPU'
$cs  = Get-CimInstance Win32_ComputerSystem
$oem = "$($cs.Manufacturer) $($cs.Model)".Trim()
Write-Info "Equipo: $oem"
$baseMHz = $null
foreach ($cpu in Get-CimInstance Win32_Processor) {
    Write-Info "CPU: $($cpu.Name.Trim()) | base $($cpu.MaxClockSpeed) MHz | ahora $($cpu.CurrentClockSpeed) MHz"
    if (-not $baseMHz) { $baseMHz = [int]$cpu.MaxClockSpeed }
}
try {
    $pi = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'" -OperationTimeoutSec 10 -ErrorAction Stop
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

# Temperatura de la zona termica ACPI (decimas de Kelvin). No todos los portatiles la exponen.
try {
    $tz = @(Get-CimInstance -Namespace 'root/wmi' -ClassName 'MSAcpi_ThermalZoneTemperature' -OperationTimeoutSec 10 -ErrorAction Stop)
    $c = ($tz | ForEach-Object { [math]::Round($_.CurrentTemperature / 10 - 273.15) } | Measure-Object -Maximum).Maximum
    if ($c -ge 85) { Write-Warn2 "Temperatura ahora: $c C (alta)" } elseif ($c -gt 0) { Write-Info "Temperatura ahora: $c C" }
} catch {}

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
$bkFile = Join-Path $LogPath 'backup.json'
$prev = $null
if (Test-Path $bkFile) { try { $prev = Get-Content $bkFile -Raw | ConvertFrom-Json } catch {} }
$backup = @()
$changes = @()
foreach ($t in $Targets) {
    $cur = Get-PowerValue $readScheme $t.S $t.G
    if ($null -eq $cur) { Write-Info "$($t.N): no existe en este equipo, se salta"; continue }
    $backup += [pscustomobject]@{ N = $t.N; S = $t.S; G = $t.G; Ac = $cur.Ac; Dc = $cur.Dc }
    $d = Get-Desired $t $cur
    $t.Ac = $d.Ac; $t.Dc = $d.Dc
    $same = ($cur.Ac -eq $t.Ac) -and ((-not $doDc) -or $cur.Dc -eq $t.Dc)
    $storedOk = Test-StoredMatch $readScheme $t.S $t.G $t.Ac $t.Dc $doDc
    $line = "{0}: CA {1}->{2}{3}" -f $t.N, $cur.Ac, $t.Ac, $(if ($doDc) { " / CC $($cur.Dc)->$($t.Dc)" } else { '' })
    if ($same -and -not $storedOk) { $same = $false; $line += ' (el valor guardado no coincide con el efectivo: se corrige)' }
    if ($same) { Write-Ok "$($t.N): ya esta (CA $($cur.Ac) / CC $($cur.Dc))"; continue }
    $changes += $t
    if ($DryRun) { Write-Plan $line } else { Write-Info $line }
}
# Una ejecucion anterior (version que lo forzaba todo al 100 %) pudo dejar apagados el aparcado
# de nucleos, ASPM, APST o Power Throttling, y eso calienta. Si hay copia del estado original y
# este perfil ya no los toca, vuelven a su valor original.
$heal = @()
$healOv = @()
if ($prev) {
    $tg = @($Targets | ForEach-Object { $_.G })
    foreach ($s in @($prev.Settings)) {
        if (-not $s -or $tg -contains $s.G -or $null -eq $s.Ac -or $null -eq $s.Dc) { continue }
        $cur = Get-PowerValue $readScheme $s.S $s.G
        if ($null -eq $cur -or ($cur.Ac -eq $s.Ac -and $cur.Dc -eq $s.Dc)) { continue }
        $heal += $s
        $m = "$($s.N): CA $($cur.Ac)->$($s.Ac) / CC $($cur.Dc)->$($s.Dc) (vuelve al valor original)"
        if ($DryRun) { Write-Plan $m } else { Write-Info $m }
    }
    foreach ($s in @($prev.OverlaySettings)) {
        if (-not $s -or $tg -contains $s.G) { continue }
        $base = @($prev.Settings) | Where-Object { $_.G -eq $s.G } | Select-Object -First 1
        $ac = if ($null -ne $s.Ac) { $s.Ac } elseif ($base) { $base.Ac } else { $null }
        $dc = if ($null -ne $s.Dc) { $s.Dc } elseif ($base) { $base.Dc } else { $null }
        if ($null -ne $ac -and $null -ne $dc) { $healOv += [pscustomobject]@{ S = $s.S; G = $s.G; Ac = $ac; Dc = $dc } }
    }
}

# Modo de energia "Maximo rendimiento" solo con -Max: en LG, Surface, Samsung y Lenovo sube los
# limites de potencia del firmware (PL1/PL2) y con carga lleva la CPU a 90-100 grados tambien
# con cargador. Sin -Max se queda el del usuario; si una ejecucion anterior lo puso, vuelve.
$ovAc = $ov.Ac
$ovDc = $ov.Dc
if ($Max) { $ovAc = $OverlayBest; if ($doDc) { $ovDc = $OverlayBest } }
elseif ($prev) {
    if ($ov.Ac -eq $OverlayBest) { $ovAc = $prev.OverlayAc }
    if ($doDc -and $ov.Dc -eq $OverlayBest) { $ovDc = $prev.OverlayDc }
}
if ($ovAc -eq $OverlayBest -and -not $Max) { $ovAc = $null }
if ($ovDc -eq $OverlayBest -and -not $Max) { $ovDc = $null }

# Power Throttling: apagado solo con -Max; si no, el valor original.
$thrTarget = $thr
if ($Max) { $thrTarget = 1 } elseif ($prev) { $thrTarget = $prev.PowerThrottlingOff }

if ($DryRun) {
    if ((ConvertTo-OverlayKey $ovAc) -ne (ConvertTo-OverlayKey $ov.Ac) -or (ConvertTo-OverlayKey $ovDc) -ne (ConvertTo-OverlayKey $ov.Dc)) { Write-Plan "Modo de energia (CA/CC): $(Get-OverlayName $ov.Ac) / $(Get-OverlayName $ov.Dc) -> $(Get-OverlayName $ovAc) / $(Get-OverlayName $ovDc)" }
    else { Write-Ok "Modo de energia: $(Get-OverlayName $ovAc) / $(Get-OverlayName $ovDc), no se toca" }
    Write-Plan 'Los mismos valores dentro del modo Maximo rendimiento (si alguien lo activa, sus EPP y nucleos no mandan sobre el plan)'
    if ("$thrTarget" -ne "$thr") { Write-Plan "PowerThrottlingOff: $thr -> $(if ($null -eq $thrTarget) { 'sin definir' } else { $thrTarget })" }
}

# Lenovo ThinkPad: control termico en BIOS.
$lenovo = @()
$lenovoHeal = @()
$lenovoLocked = $false
if (-not $SkipBios -and $cs.Manufacturer -match 'LENOVO') {
    $lt = @(Get-LenovoThermal)
    # MaximizePerformance (sube limites de potencia y temperatura) solo con -Max; si una
    # ejecucion anterior lo puso, vuelve al valor original.
    if ($Max) { $lenovo = @($lt | Where-Object { $_.Value -ne 'MaximizePerformance' -and ($_.Name -eq 'AdaptiveThermalManagementAC' -or $doDc) }) }
    elseif ($prev) {
        foreach ($l in @($prev.LenovoBios)) {
            $curB = $lt | Where-Object { $l -and $_.Name -eq $l.Name } | Select-Object -First 1
            if ($l -and $l.Value -ne 'MaximizePerformance' -and $curB -and $curB.Value -eq 'MaximizePerformance') {
                $lenovoHeal += $l
                $m = "BIOS $($l.Name): MaximizePerformance -> $($l.Value) (vuelve al valor original)"
                if ($DryRun) { Write-Plan $m } else { Write-Info $m }
            }
        }
    }
    if ($lenovo.Count -gt 0 -or $lenovoHeal.Count -gt 0) {
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
    $bkFile = Join-Path $LogPath 'backup.json'
    $keepBackup = Test-Path $bkFile
    # Valores propios del modo "Maximo rendimiento": mandan sobre el plan (EPP, nucleos...).
    # Solo hacen falta para la copia, que solo se escribe la primera vez.
    $ovBackup = @()
    foreach ($t in @($Targets | Where-Object { -not $keepBackup })) {
        $cur = Get-PowerValue $OverlayBest $t.S $t.G
        if ($null -eq $cur) { continue }
        $ovBackup += [pscustomobject]@{ N = $t.N; S = $t.S; G = $t.G; Ac = $cur.Ac; Dc = $cur.Dc }
    }
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
        OverlaySettings    = $ovBackup
        LenovoBios         = @($lenovo | Where-Object { -not $lenovoLocked })
    }
    # Solo se guarda el estado ORIGINAL: si ya hay copia pendiente (el script se lanzo antes y
    # no se restauro), se conserva, para que -Restore vuelva a como estaba el equipo al principio.
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

    # Todo en una pasada: como mucho un arranque como SYSTEM para lo que el fabricante bloquea.
    # Mismos valores dentro del modo "Maximo rendimiento" (si alguien lo activa, sus EPP y
    # nucleos no mandan sobre el plan); lo que dejo una ejecucion anterior, al valor original.
    $exist = @($backup | ForEach-Object { $_.G })
    $items = @()
    foreach ($t in $changes) { $items += New-PowerItem $target $t.S $t.G $t.Ac $t.Dc $doDc }
    foreach ($t in $Targets) { if ($exist -contains $t.G) { $items += New-PowerItem $OverlayBest $t.S $t.G $t.Ac $t.Dc $doDc } }
    foreach ($s in $heal) { $items += New-PowerItem $target $s.S $s.G $s.Ac $s.Dc $true }
    foreach ($s in $healOv) { $items += New-PowerItem $OverlayBest $s.S $s.G $s.Ac $s.Dc $true }
    $res = Set-PowerValuesForced $items
    & powercfg /setactive $target 2>&1 | Out-Null

    $needReboot = @{}
    foreach ($t in $changes) {
        $r = $res["$target|$($t.G)"]
        if ($r -eq 'reinicio') { $needReboot[$t.G] = $true; Write-Info "$($t.N): impuesto por el fabricante; escrito en el registro, se aplica al reiniciar" }
        elseif ($r -eq 'fallo') { Write-Warn2 "$($t.N): Windows no acepta el valor" }
    }
    # Los del modo "Maximo rendimiento" no cuentan aqui: ese modo no esta activo y mezclarlos por
    # ajuste podia tapar un fallo del plan con un "se aplica al reiniciar".
    $healFail = 0
    foreach ($s in $heal) {
        $r = $res["$target|$($s.G)"]
        if ($r -eq 'ok') { Write-Ok "$($s.N): vuelve a CA $($s.Ac) / CC $($s.Dc)" }
        elseif ($r -eq 'reinicio') { Write-Ok "$($s.N): vuelve a CA $($s.Ac) / CC $($s.Dc) (al reiniciar)" }
        else { Write-Warn2 "$($s.N): no se pudo devolver al valor original"; $healFail++ }
    }
    Set-Overlay $ovAc $ovDc
    & powercfg /setactive $target 2>&1 | Out-Null
    if ("$thrTarget" -ne "$thr") {
        if ($null -eq $thrTarget) { Remove-ItemProperty -Path $ThrottleKey -Name 'PowerThrottlingOff' -ErrorAction SilentlyContinue }
        else {
            if (-not (Test-Path $ThrottleKey)) { New-Item -Path $ThrottleKey -Force | Out-Null }
            Set-ItemProperty -Path $ThrottleKey -Name 'PowerThrottlingOff' -Value ([int]$thrTarget) -Type DWord -Force
        }
    }

    if (-not $lenovoLocked) {
        foreach ($l in $lenovo) {
            $r = Set-LenovoBios $l.Name 'MaximizePerformance'
            if ($r -eq 'Success') { Write-Ok "BIOS $($l.Name) -> MaximizePerformance (al reiniciar)" } else { Write-Warn2 "BIOS $($l.Name): $r" }
        }
        foreach ($l in $lenovoHeal) {
            $r = Set-LenovoBios $l.Name $l.Value
            if ($r -eq 'Success') { Write-Ok "BIOS $($l.Name) -> $($l.Value) (al reiniciar)" } else { Write-Warn2 "BIOS $($l.Name): $r" }
        }
    } elseif ($lenovoHeal.Count -gt 0) { Write-Warn2 'BIOS con contrasena de supervisor: Adaptive Thermal Management hay que devolverlo a mano en F1 (Balanced).' }

    # ------------------------------------------------------------ VERIFICACION
    Write-Section 'Verificacion (releyendo el estado real)'
    $fail = 0
    foreach ($t in $Targets) {
        $cur = Get-PowerValue $target $t.S $t.G
        if ($null -eq $cur) { continue }
        $ok = ($cur.Ac -eq $t.Ac) -and ((-not $doDc) -or $cur.Dc -eq $t.Dc)
        if ($ok -and -not (Test-StoredMatch $target $t.S $t.G $t.Ac $t.Dc $doDc)) { Write-Err2 "$($t.N): CA $($cur.Ac) / CC $($cur.Dc) ahora, pero el registro guarda otro valor (volveria al reiniciar)"; $fail++ }
        elseif ($ok) { Write-Ok "$($t.N): CA $($cur.Ac) / CC $($cur.Dc)" }
        elseif ($needReboot[$t.G]) { Write-Warn2 "$($t.N): ahora CA $($cur.Ac) / CC $($cur.Dc); queda $($t.Ac) al reiniciar (valor de fabrica del OEM)" }
        else { Write-Err2 "$($t.N): CA $($cur.Ac) / CC $($cur.Dc)"; $fail++ }
    }
    $ov2 = Get-Overlay
    if ((ConvertTo-OverlayKey $ov2.Ac) -eq (ConvertTo-OverlayKey $ovAc) -and (ConvertTo-OverlayKey $ov2.Dc) -eq (ConvertTo-OverlayKey $ovDc)) { Write-Ok "Modo de energia (CA/CC): $(Get-OverlayName $ov2.Ac) / $(Get-OverlayName $ov2.Dc)" }
    else { Write-Err2 "Modo de energia: $($ov2.Ac) / $($ov2.Dc)"; $fail++ }
    $thr2 = (Get-ItemProperty -Path $ThrottleKey -ErrorAction SilentlyContinue).PowerThrottlingOff
    if ("$thr2" -eq "$thrTarget") { Write-Ok "Power Throttling: $(if ($thr2 -eq 1) { 'desactivado' } else { 'el de Windows (activo)' })" }
    else { Write-Err2 "PowerThrottlingOff = $thr2 (se esperaba $thrTarget)"; $fail++ }
    $fail += $healFail
    if ($target -ne $GuidBalanced) { Write-Info 'El modo de energia de Windows 11 solo actua con el plan Equilibrado; con este plan mandan los valores de arriba.' }
    if ($fail -eq 0 -and $needReboot.Count -eq 0) { Write-Ok 'Todo aplicado.' }
    elseif ($fail -eq 0) { Write-Ok "Todo aplicado; $($needReboot.Count) ajustes del fabricante entran al reiniciar (volver a lanzar despues para comprobarlo)." }
    else { Write-Err2 "$fail ajustes no quedaron como debian." }
}

# ---------------------------------------------------------------- ACTUALIZACIONES
# Solo lectura salvo -InstallDrivers. Un BIOS o un driver de chipset/graficos viejo tambien
# deja la CPU lenta o mal gestionada, asi que se revisa aqui.
if (-not $SkipUpdateCheck) {
    Write-Section 'Actualizaciones de BIOS y drivers'
    $bi = Get-CimInstance Win32_BIOS
    $age = if ($bi.ReleaseDate) { [int]((Get-Date) - $bi.ReleaseDate).TotalDays } else { $null }
    $msg = "BIOS instalada: $(([string]$bi.SMBIOSBIOSVersion).Trim())$(if ($bi.ReleaseDate) { ' del ' + $bi.ReleaseDate.ToString('yyyy-MM-dd') + " ($age dias)" })"
    if ($age -gt 540) { Write-Warn2 "$msg -> mas de 18 meses" } else { Write-Info $msg }

    if ($cs.Manufacturer -match 'LENOVO') {
        Write-Info 'Comparando con el catalogo oficial de Lenovo para este modelo...'
        $lc = Get-LenovoCatalogUpdates
        if ($lc.Error) { Write-Warn2 "$($lc.Error). Usar Lenovo Vantage." }
        else {
            Write-Info "Catalogo: $($lc.Catalog) ($($lc.Checked) paquetes aplicables comprobados)"
            if ($lc.Pending.Count -eq 0) { Write-Ok 'BIOS y drivers de Lenovo al dia.' }
            foreach ($u in $lc.Pending) {
                Write-Warn2 ("{0} pendiente: {1} | instalado {2} -> {3} ({4})" -f $u.Type, $u.Name, $u.Installed, $u.Available, $u.Date)
            }
            if ($lc.Pending.Count -gt 0) {
                Write-Info "Instalar: Lenovo Commercial Vantage / System Update, o https://pcsupport.lenovo.com/products/$(([string]$bi.SerialNumber).Trim())/downloads"
                if ($lc.Pending | Where-Object Type -eq 'BIOS') { Write-Info 'BIOS: con el cargador conectado y sin suspender BitLocker a mano (el instalador de Lenovo lo hace).' }
            }
        }
    }

    try {
        if (-not $wuJob) { throw 'no se pudo lanzar la busqueda' }
        $wu = @(Receive-WuDriverSearch $wuJob)
        if ($wu.Count -eq 0) { Write-Ok 'Windows Update: sin drivers ni firmware pendientes.' }
        foreach ($u in $wu) {
            $d = if ($u.Date) { ([datetime]$u.Date).ToString('yyyy-MM-dd') } else { '' }
            Write-Warn2 "Windows Update: $($u.Title) [$($u.Class)] $d"
        }
        if ($wu.Count -gt 0) {
            if ($InstallDrivers -and $DryRun) { Write-Plan "Se instalarian $($wu.Count) actualizaciones de drivers/firmware de Windows Update." }
            elseif ($InstallDrivers) {
                Write-Info "Instalando $($wu.Count) actualizaciones de Windows Update..."
                $ir = Install-WuDriverUpdates @($wu | ForEach-Object { $_.Id })
                foreach ($x in $ir.Results) {
                    if ($x.Code -eq 2) { Write-Ok "Instalado: $($x.Title)" }
                    elseif ($x.Code -eq 3) { Write-Warn2 "Instalado con avisos: $($x.Title)" }
                    else { Write-Err2 "No instalado (codigo $($x.Code)): $($x.Title)" }
                }
                if ($ir.Reboot) { Write-Warn2 'Windows Update pide reiniciar.' }
            } else { Write-Info 'Para instalarlas: el mismo comando con -InstallDrivers' }
        }
    } catch { Write-Warn2 "Windows Update no disponible: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------- FABRICANTE
Write-Section 'Fabricante'
switch -Regex ($cs.Manufacturer) {
    'LENOVO'    { Write-Info 'Lenovo: Lenovo Vantage > Dispositivo > Energia, Smart Performance/Intelligent Cooling en Equilibrado o Automatico. "Rendimiento maximo" (o Fn+Q) sube el limite de potencia y calienta; usarlo solo si va sobrado de temperatura.' }
    'SAMSUNG'   { Write-Info 'Samsung: Samsung Settings > Modo de rendimiento en Optimizado. "Alto rendimiento" calienta. No tiene API: hay que hacerlo en la app. BIOS y drivers: app Samsung Update.' }
    'Microsoft' { Write-Info 'Surface: lo controla el modo de energia de Windows (Equilibrado; Maximo rendimiento calienta). Usar el cargador original: con uno de menos vatios la CPU se limita. BIOS y drivers llegan por Windows Update.' }
    '^LG'       { Write-Info 'LG gram: LG Control Center (o LG Smart Assistant) > modo de rendimiento en Normal/Optimizado y ventilador en automatico. El modo Rendimiento sube el limite de potencia y es lo que lleva un gram a 90 grados con cargador. No tiene API: hay que hacerlo en la app. BIOS y drivers: LG Update.' }
    default     { Write-Info 'Si el fabricante tiene app de energia propia (Dell Optimizer, HP, MyASUS...), ponerla en rendimiento. BIOS y drivers: Dell Command Update, HP Image Assistant, MyASUS.' }
}

Write-Section 'Resumen'
if (-not $DryRun) {
    Write-Host "Log y copia: $LogPath" -ForegroundColor Cyan
    Write-Host 'Deshacer: el mismo comando con -Restore' -ForegroundColor Cyan
    Write-Host 'Reiniciar recomendado (obligatorio si se cambio la BIOS de Lenovo).' -ForegroundColor Yellow
    if (-not $Max -and -not $Cool -and -not $MaxMHz) { Write-Host 'Si con carga sigue pasando de 90 grados: el mismo comando con -MaxMHz 3500 (o -Cool para quitar el turbo), y la app del fabricante en modo equilibrado.' -ForegroundColor Yellow }
    if (-not $Max -and -not $EppSet) { Write-Host 'Para que responda algo mas sin subir el techo de calor: el mismo comando con -Epp 15 (sin tope: los picos cortos van al turbo completo). Si con carga ligera larga (Teams) calienta, anadir -MaxMHz con unos 200 MHz menos que el turbo.' -ForegroundColor Yellow }
    if ($Max) { Write-Host 'Perfil -Max: la CPU no baja de vueltas y se calienta. Volver al normal: el mismo comando sin -Max.' -ForegroundColor Yellow }
}
Write-Host 'Si tras reiniciar la CPU sigue limitada y hay eventos 37: cargador original de los vatios correctos, temperatura (polvo, pasta termica) o bateria.' -ForegroundColor Yellow

if (-not $DryRun) { Stop-Transcript | Out-Null }
