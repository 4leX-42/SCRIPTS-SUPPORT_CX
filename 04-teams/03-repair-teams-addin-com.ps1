<#
.SYNOPSIS
    [ES] Re-registra el complemento de reunion de Teams en Outlook clasico y lo blinda.
    [EN] Re-registers the Teams meeting add-in in classic Outlook and hardens it.

.DESCRIPTION
    [ES]
    Va un paso mas alla que 02-repair-teams-outlook-addin: en vez de borrar caches,
    ataca el registro COM. Cierra Outlook, localiza Microsoft.Teams.AddinLoader.dll
    con la arquitectura que le toca a Outlook, lo vuelve a registrar por usuario
    (regsvr32 /n /i:user), fuerza LoadBehavior = 3, limpia Resiliency y anade el
    ProgID a doNotDisableAddinList y addinlist por policy de usuario, para que
    Outlook no lo vuelva a deshabilitar por lento.

    Se ejecuta como el usuario afectado; no necesita admin (las claves de HKLM se
    saltan si no hay permisos). Usar cuando el complemento reaparece deshabilitado
    una y otra vez despues de limpiar caches.

    [EN]
    Goes one step further than 02-repair-teams-outlook-addin: instead of clearing
    caches it goes after the COM registration. Closes Outlook, locates
    Microsoft.Teams.AddinLoader.dll for Outlook's own bitness, re-registers it
    per-user (regsvr32 /n /i:user), forces LoadBehavior = 3, clears Resiliency and
    adds the ProgID to doNotDisableAddinList and addinlist through user policy, so
    Outlook stops disabling it for being slow.

    Runs as the affected user; admin not required (HKLM keys are skipped when
    permissions are missing). Use it when the add-in keeps coming back disabled
    after cache cleanups.

.PARAMETER NoKillOutlook
    [ES] No cierra Outlook. El re-registro COM puede no aplicar hasta reiniciarlo.
    [EN] Leaves Outlook running. The COM re-registration may not apply until restart.

.EXAMPLE
    .-repair-teams-addin-com.ps1

.EXAMPLE
    .-repair-teams-addin-com.ps1 -NoKillOutlook

.NOTES
    [ES] Se ejecuta como el usuario afectado. PowerShell 5.1 y 7. Windows 10 y 11.
    [EN] Run as the affected user. PowerShell 5.1 and 7. Windows 10 and 11.
#>

[CmdletBinding()]
param(
    [switch]$NoKillOutlook
)

$ErrorActionPreference = 'Stop'
$ProgId = 'TeamsAddin.FastConnect'

function Write-Step  { param($m) Write-Host "[*] $m" -ForegroundColor Cyan }
function Write-Ok    { param($m) Write-Host "[+] $m" -ForegroundColor Green }
function Write-Warn2 { param($m) Write-Host "[!] $m" -ForegroundColor Yellow }

# ---------------------------------------------------------------- 0. Outlook
if (-not $NoKillOutlook) {
    $ol = Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue
    if ($ol) {
        Write-Step "Cerrando Outlook..."
        $ol | ForEach-Object { $_.CloseMainWindow() | Out-Null }
        Start-Sleep -Seconds 5
        Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 2
        Write-Ok "Outlook cerrado."
    } else {
        Write-Ok "Outlook no estaba abierto."
    }
}

# ------------------------------------------------- 1. Localizar AddinLoader
Write-Step "Buscando Microsoft.Teams.AddinLoader.dll ..."

$searchRoots = @(
    (Join-Path $env:LOCALAPPDATA 'Microsoft\TeamsMeetingAddin'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\TeamsMeetingAdd-in'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\TeamsMeetingAddins')
) | Where-Object { Test-Path $_ }

$dlls = @()
foreach ($root in $searchRoots) {
    $dlls += Get-ChildItem -Path $root -Filter 'Microsoft.Teams.AddinLoader.dll' -Recurse -ErrorAction SilentlyContinue
}

if (-not $dlls) {
    Write-Warn2 "No se encontro AddinLoader.dll. Reinstala/actualiza el cliente de Teams (el add-in se despliega con Teams)."
} else {
    # Bitness de Outlook decide x64 vs x86
    $bitness = 'x64'
    try {
        $plat = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction Stop).Platform
        if ($plat -eq 'x86') { $bitness = 'x86' }
    } catch {
        if (-not [Environment]::Is64BitOperatingSystem) { $bitness = 'x86' }
    }
    Write-Ok "Outlook detectado como $bitness."

    $target = $dlls |
        Where-Object { $_.FullName -match "\\$bitness\\" } |
        Sort-Object { try { [version]($_.Directory.Parent.Name) } catch { [version]'0.0.0.0' } } -Descending |
        Select-Object -First 1

    if (-not $target) { $target = $dlls | Select-Object -First 1 }
    Write-Ok "DLL: $($target.FullName)"

    if ($bitness -eq 'x86') {
        $regsvr = Join-Path $env:WINDIR 'SysWOW64\regsvr32.exe'
    } else {
        $regsvr = Join-Path $env:WINDIR 'System32\regsvr32.exe'
    }

    Write-Step "Re-registrando COM por usuario (regsvr32 /n /i:user) ..."
    & $regsvr /s /u "$($target.FullName)" 2>$null
    Start-Sleep -Seconds 1
    & $regsvr /n /i:user /s "$($target.FullName)"
    Start-Sleep -Seconds 2
    Write-Ok "regsvr32 ejecutado."
}

# --------------------------------------------- 2. LoadBehavior en HKCU/HKLM
Write-Step "Forzando LoadBehavior = 3 ..."

$addinKeys = @(
    "HKCU:\SOFTWARE\Microsoft\Office\Outlook\Addins\$ProgId",
    "HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins\$ProgId",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\Outlook\Addins\$ProgId"
)

foreach ($k in $addinKeys) {
    if (Test-Path $k) {
        try {
            Set-ItemProperty -Path $k -Name 'LoadBehavior' -Value 3 -Type DWord -Force
            Write-Ok "LoadBehavior=3 -> $k"
        } catch {
            Write-Warn2 "Sin permisos para $k (requiere admin). Continuo."
        }
    }
}

$hkcuAddin = "HKCU:\SOFTWARE\Microsoft\Office\Outlook\Addins\$ProgId"
if (-not (Test-Path $hkcuAddin)) {
    New-Item -Path $hkcuAddin -Force | Out-Null
    New-ItemProperty -Path $hkcuAddin -Name 'LoadBehavior' -Value 3 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $hkcuAddin -Name 'FriendlyName' -Value 'Microsoft Teams Meeting Add-in for Microsoft Office' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $hkcuAddin -Name 'Description'  -Value 'Microsoft Teams Meeting Add-in for Microsoft Office' -PropertyType String -Force | Out-Null
    Write-Ok "Clave HKCU del add-in creada."
}

# ------------------------------------------------------- 3. Limpiar Resiliency
Write-Step "Limpiando Resiliency (DisabledItems / CrashingAddinList) ..."

$officeVersions = @('16.0','15.0','14.0')
$cleaned = 0

foreach ($v in $officeVersions) {
    $resBase = "HKCU:\SOFTWARE\Microsoft\Office\$v\Outlook\Resiliency"
    if (-not (Test-Path $resBase)) { continue }

    foreach ($sub in @('DisabledItems','CrashingAddinList','DoNotDisableAddinList','NotificationReminderApps')) {
        $p = Join-Path $resBase $sub
        if (Test-Path $p) {
            Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue
            Write-Ok "Borrado: $p"
            $cleaned++
        }
    }
}
if ($cleaned -eq 0) { Write-Ok "Nada que limpiar en Resiliency." }

# ------------------------------- 4. Blindar contra auto-deshabilitado
Write-Step "Blindando add-in contra auto-deshabilitado ..."

$polRes = 'HKCU:\SOFTWARE\Policies\Microsoft\Office\16.0\outlook\resiliency\doNotDisableAddinList'
New-Item -Path $polRes -Force | Out-Null
New-ItemProperty -Path $polRes -Name $ProgId -Value 1 -PropertyType DWord -Force | Out-Null
Write-Ok "doNotDisableAddinList <- $ProgId = 1"

$polAddinList = 'HKCU:\SOFTWARE\Policies\Microsoft\Office\16.0\outlook\resiliency\addinlist'
New-Item -Path $polAddinList -Force | Out-Null
New-ItemProperty -Path $polAddinList -Name $ProgId -Value 1 -PropertyType DWord -Force | Out-Null
Write-Ok "addinlist <- $ProgId = 1 (siempre habilitado)"

$polOutlook = 'HKCU:\SOFTWARE\Policies\Microsoft\Office\16.0\outlook\options\general'
New-Item -Path $polOutlook -Force | Out-Null
New-ItemProperty -Path $polOutlook -Name 'DisableAddinCrashDetection'    -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $polOutlook -Name 'DisableAllAddinCrashDetection' -Value 1 -PropertyType DWord -Force | Out-Null
Write-Ok "Deteccion de crash de add-ins desactivada (policy de usuario)."

# ------------------------------------------- 5. Limpiar caches
Write-Step "Limpiando caches relacionadas ..."

$caches = @(
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Office\16.0\WebServiceCache'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Teams\meeting-addin')
)
foreach ($c in $caches) {
    if (Test-Path $c) {
        Remove-Item -Path (Join-Path $c '*') -Recurse -Force -ErrorAction SilentlyContinue
        Write-Ok "Cache limpiada: $c"
    }
}

# ------------------------------------------------------------- 6. Verificacion
Write-Host ""
Write-Step "Estado final:"
foreach ($k in $addinKeys) {
    if (Test-Path $k) {
        $lb = (Get-ItemProperty -Path $k -ErrorAction SilentlyContinue).LoadBehavior
        Write-Host ("    {0}  LoadBehavior={1}" -f $k, $lb)
    }
}

$stillDisabled = $false
foreach ($v in $officeVersions) {
    if (Test-Path "HKCU:\SOFTWARE\Microsoft\Office\$v\Outlook\Resiliency\DisabledItems") { $stillDisabled = $true }
}
if ($stillDisabled) { Write-Warn2 "DisabledItems reaparecio." } else { Write-Ok "DisabledItems limpio." }

Write-Host ""
Write-Ok "Listo. Abre Outlook y comprueba Archivo > Opciones > Complementos."
Write-Host "    Si vuelve a caer: Archivo > Opciones > Centro de confianza > Configuracion" -ForegroundColor DarkGray
Write-Host "    del Centro de confianza > Complementos (desmarcar 'Requerir firma de editor de confianza')." -ForegroundColor DarkGray
