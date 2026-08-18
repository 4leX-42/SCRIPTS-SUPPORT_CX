#Requires -Version 5.1

<#
.SYNOPSIS
    [ES] Prueba en sandbox la logica de borrado de los scripts de Outlook. No toca Outlook.
    [EN] Sandbox-tests the deletion logic behind the Outlook scripts. Never touches Outlook.

.DESCRIPTION
    NO toca la configuracion real de Outlook. Crea un arbol de registro
    de usar y tirar (HKCU:\Software\_OutlookCleanupTest) y una carpeta
    temporal con perfiles, XML de Autodiscover y archivos .pst/.ost FALSOS,
    ejecuta la MISMA logica de borrado/backup que el script real contra ese
    sandbox, y comprueba con aserciones que:
      - Se eliminan Profiles, AutoDiscover, DefaultProfile y ruta heredada.
      - Una version basura (8.0 sin Profiles) se omite sin error.
      - Se borran los XML de Autodiscover.
      - Se CONSERVAN los .pst y .ost (y otros datos).
      - Se crean copias .reg de backup antes de borrar.
    Al terminar elimina TODO el sandbox (registro + carpeta).

    Simula Windows 11 + Outlook Classic (Office 16.0).
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:fail = 0
$script:pass = 0

function Assert {
    param([string]$Name, [bool]$Condition)
    if ($Condition) { $script:pass++; Write-Host "  [PASS] $Name" -ForegroundColor Green }
    else            { $script:fail++; Write-Host "  [FAIL] $Name" -ForegroundColor Red }
}

# --- Helpers COPIADOS del script real (misma logica) -----------------------
$TestRoot   = 'HKCU:\Software\_OutlookCleanupTest'
$sandbox    = Join-Path $env:TEMP ('_OutlookTest_{0}' -f (Get-Date -Format 'HHmmssfff'))
$backupDir  = Join-Path $sandbox 'registry-backup'

function Backup-RegKey {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    $regPath = $Path.Replace(':', '')
    $safe    = ($Path -replace '[:\\]', '_')
    $out     = Join-Path $backupDir "$safe.reg"
    & reg.exe export "$regPath" "$out" /y *> $null
}
function Remove-RegKey {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 'skip' }
    Backup-RegKey -Path $Path
    Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
    return 'deleted'
}
function Remove-RegValue {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path $Path)) { return 'skip' }
    if ($null -eq (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue)) { return 'skip' }
    Backup-RegKey -Path $Path
    Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop
    return 'deleted'
}

try {
    Write-Host ''
    Write-Host '=== TEST AISLADO: Reset-OutlookClassic (W11 / Outlook Classic 16.0) ===' -ForegroundColor Cyan
    Write-Host "Sandbox registro: $TestRoot" -ForegroundColor DarkGray
    Write-Host "Sandbox disco   : $sandbox" -ForegroundColor DarkGray
    Write-Host ''

    # --- 1. Montar el sandbox (reg add crea rutas intermedias) -------------
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $o16 = "$TestRoot\Office\16.0\Outlook"
    $o8  = "$TestRoot\Office\8.0\Outlook"        # version basura sin Profiles
    $leg = "$TestRoot\WinMsgSubsys\Profiles"     # equivalente a la ruta heredada

    & reg.exe add ($o16.Replace(':','') + '\Profiles\Outlook\9375CFF0413111d3B88A00104B2A6676') /f *> $null
    & reg.exe add ($o16.Replace(':','') + '\AutoDiscover') /v 'user@es.andersen.com' /d 'cache' /f *> $null
    & reg.exe add  $o16.Replace(':','') /v 'DefaultProfile' /t REG_SZ /d 'Outlook' /f *> $null
    & reg.exe add ($o8.Replace(':','')) /v 'Dummy' /d 'x' /f *> $null
    & reg.exe add  $leg.Replace(':','') /v 'p' /d 'x' /f *> $null

    # Carpeta de datos: XML de autodiscover + datos a conservar (mismo dir)
    $dataDir = Join-Path $sandbox 'Microsoft\Outlook'
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    Set-Content (Join-Path $dataDir '1A2B3C4DAutodiscover.xml') 'x'   # debe borrarse
    Set-Content (Join-Path $dataDir 'autodiscover.xml')         'x'   # debe borrarse
    Set-Content (Join-Path $dataDir 'alejandro.andreu.ost')     'data' # CONSERVAR
    Set-Content (Join-Path $dataDir 'archivo-local.pst')        'data' # CONSERVAR
    Set-Content (Join-Path $dataDir 'extend.dat')               'data' # CONSERVAR (no match)

    # Verificacion del montaje
    Assert 'Sandbox: Profiles creado'      (Test-Path "$o16\Profiles")
    Assert 'Sandbox: AutoDiscover creado'  (Test-Path "$o16\AutoDiscover")
    Assert 'Sandbox: 5 archivos de datos'  ((Get-ChildItem $dataDir -File).Count -eq 5)

    # --- 2. Deteccion de versiones (misma regex que el script) -------------
    $officeRoots = @()
    Get-ChildItem "$TestRoot\Office" |
        Where-Object { $_.PSChildName -match '^\d+\.\d+$' } |
        ForEach-Object {
            $ok = "$TestRoot\Office\$($_.PSChildName)\Outlook"
            if (Test-Path $ok) { $officeRoots += $ok }
        }
    Assert 'Deteccion: encuentra 16.0 y 8.0' ($officeRoots.Count -eq 2)

    # --- 3. Ejecutar la logica de borrado ----------------------------------
    $r8profiles = 'skip'
    foreach ($root in $officeRoots) {
        Remove-RegKey   -Path "$root\Profiles"     | Out-Null
        Remove-RegKey   -Path "$root\AutoDiscover" | Out-Null
        Remove-RegValue -Path $root -Name 'DefaultProfile' | Out-Null
    }
    # ruta heredada
    Remove-RegKey -Path $leg | Out-Null

    # XML de autodiscover en disco (mismo filtro que el script)
    Get-ChildItem -Path $dataDir -Filter '*autodiscover*.xml' -File |
        ForEach-Object { Remove-Item $_.FullName -Force }

    # --- 4. ASERCIONES de resultado ----------------------------------------
    Write-Host ''
    Write-Host 'Resultados:' -ForegroundColor Cyan
    Assert 'Borrado: 16.0\Profiles eliminado'        (-not (Test-Path "$o16\Profiles"))
    Assert 'Borrado: 16.0\AutoDiscover eliminado'    (-not (Test-Path "$o16\AutoDiscover"))
    Assert 'Borrado: DefaultProfile eliminado'       ($null -eq (Get-ItemProperty -Path $o16 -Name 'DefaultProfile' -ErrorAction SilentlyContinue))
    Assert 'Conservado: clave 16.0\Outlook sigue'    (Test-Path $o16)
    Assert 'Omitido sin error: 8.0 (sin Profiles)'   (Test-Path $o8)
    Assert 'Borrado: ruta heredada eliminada'        (-not (Test-Path $leg))

    Assert 'Borrado: XML autodiscover (hash) fuera'  (-not (Test-Path (Join-Path $dataDir '1A2B3C4DAutodiscover.xml')))
    Assert 'Borrado: autodiscover.xml fuera'         (-not (Test-Path (Join-Path $dataDir 'autodiscover.xml')))

    Assert 'CONSERVADO: .ost intacto'                (Test-Path (Join-Path $dataDir 'alejandro.andreu.ost'))
    Assert 'CONSERVADO: .pst intacto'                (Test-Path (Join-Path $dataDir 'archivo-local.pst'))
    Assert 'CONSERVADO: .dat intacto'                (Test-Path (Join-Path $dataDir 'extend.dat'))

    $backups = Get-ChildItem $backupDir -Filter '*.reg' -ErrorAction SilentlyContinue
    Assert 'Backup: se generaron copias .reg'        ($backups.Count -ge 3)
}
finally {
    # --- 5. Limpieza TOTAL del sandbox -------------------------------------
    if (Test-Path $TestRoot) { Remove-Item $TestRoot -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $sandbox)  { Remove-Item $sandbox  -Recurse -Force -ErrorAction SilentlyContinue }
    Write-Host ''
    Write-Host 'Sandbox eliminado (registro + carpeta).' -ForegroundColor DarkGray
}

Write-Host ''
if ($script:fail -eq 0) {
    Write-Host "RESULTADO: TODO OK  ($script:pass aserciones pasadas)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "RESULTADO: $script:fail FALLOS, $script:pass OK" -ForegroundColor Red
    exit 1
}
