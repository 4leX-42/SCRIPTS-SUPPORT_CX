<#
.SYNOPSIS
    [ES] Recupera el boton de reunion de Teams cuando desaparece de Outlook.
    [EN] Restores the Teams meeting button when it disappears from Outlook.

.DESCRIPTION
    [ES]
    Cierra Outlook y Teams, borra la cache de Teams y del complemento de reuniones,
    saca el complemento de las listas de "elementos deshabilitados" de Outlook -que es
    donde acaba cuando Outlook decide que tarda demasiado en cargar- y vuelve a
    registrar la clave del complemento para que aparezca en la cinta.

    Requiere admin. Al terminar hay que abrir Outlook: el boton tarda unos segundos
    en aparecer la primera vez.

    [EN]
    Closes Outlook and Teams, clears the Teams and meeting add-in caches, removes the
    add-in from Outlook's disabled items lists -where it ends up when Outlook decides
    it loads too slowly- and re-registers the add-in key so it shows up in the ribbon.

    Requires admin. Open Outlook afterwards: the button takes a few seconds to appear
    the first time.

.NOTES
    [ES] Requiere admin. PowerShell 5.1 y 7. Windows 10 y 11.
    [EN] Requires admin. PowerShell 5.1 and 7. Windows 10 and 11.
#>

$ErrorActionPreference = "SilentlyContinue"

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) { exit 1 }

$procList = @("Outlook","Teams","ms-teams","olk","OfficeClickToRun","Microsoft.AAD.BrokerPlugin")
foreach ($p in $procList) {
    Get-Process -Name $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

Start-Sleep -Seconds 3

$addinRegPath = "HKCU:\Software\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect"

$pathsToRemove = @(
    "$env:APPDATA\Microsoft\Teams",
    "$env:LOCALAPPDATA\Microsoft\Teams",
    "$env:LOCALAPPDATA\Microsoft\TeamsMeetingAddin",
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache",
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalState",
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\TempState",
    "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\RoamingState",
    "$env:LOCALAPPDATA\SquirrelTemp"
)

foreach ($path in $pathsToRemove) {
    if (Test-Path $path) {
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$resiliencyPaths = @(
    "HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency\DisabledItems",
    "HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency\CrashingAddinList",
    "HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency\DoNotDisableAddinList"
)

foreach ($rp in $resiliencyPaths) {
    if (Test-Path $rp) {
        Remove-Item $rp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (Test-Path $addinRegPath) {
    Remove-Item $addinRegPath -Recurse -Force -ErrorAction SilentlyContinue
}

New-Item -Path $addinRegPath -Force | Out-Null
New-ItemProperty -Path $addinRegPath -Name "FriendlyName" -Value "Microsoft Teams Meeting Add-in for Microsoft Office" -PropertyType String -Force | Out-Null
New-ItemProperty -Path $addinRegPath -Name "Description" -Value "Microsoft Teams Meeting Add-in for Microsoft Office" -PropertyType String -Force | Out-Null
New-ItemProperty -Path $addinRegPath -Name "LoadBehavior" -Value 3 -PropertyType DWord -Force | Out-Null

$teamsPkg = Get-AppxPackage *MSTeams*
if ($teamsPkg) {
    $teamsPkg | ForEach-Object {
        Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue
    }
}

Start-Sleep -Seconds 3

Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "*MSTeams*" } | ForEach-Object {
    Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
}

$winget = Get-Command winget -ErrorAction SilentlyContinue

if ($winget) {
    winget uninstall "Microsoft Teams" --silent --accept-source-agreements | Out-Null
    Start-Sleep -Seconds 2
    winget install "Microsoft Teams" --silent --accept-package-agreements --accept-source-agreements
}

Start-Sleep -Seconds 10

$searchRoots = @(
    "$env:LOCALAPPDATA\Microsoft",
    "$env:ProgramFiles\WindowsApps",
    "$env:ProgramFiles",
    "$env:ProgramFiles(x86)"
)

$dlls = @()
foreach ($root in $searchRoots) {
    if (Test-Path $root) {
        $dlls += Get-ChildItem -Path $root -Recurse -Filter "Microsoft.Teams.AddinLoader.dll" -ErrorAction SilentlyContinue
    }
}

$possibleTeamsExe = @(
    "$env:LOCALAPPDATA\Microsoft\WindowsApps\ms-teams.exe",
    "$env:ProgramFiles\WindowsApps\ms-teams.exe"
)

foreach ($exe in $possibleTeamsExe) {
    if (Test-Path $exe) {
        Start-Process $exe
        break
    }
}