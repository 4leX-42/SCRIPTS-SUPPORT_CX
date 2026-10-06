<#
.SYNOPSIS
    [ES] Solo lectura. Diagnostico del crash de una aplicacion al abrir el dialogo Abrir/Guardar como.
    [EN] Read-only. Diagnoses an application crashing when it opens the Open/Save As dialog.

.DESCRIPTION
    Sintoma: la aplicacion (Teams, Outlook, navegador, cliente Electron...) se cierra
    de golpe al pulsar Adjuntar, Abrir o Guardar como. No se congela: muere.
    Para el cuelgue (ventana congelada) usar 01 y 02 de esta carpeta.

    Solo lectura salvo -EnableDumps, que configura WER LocalDumps (con -DryRun
    solo muestra lo que haria).

    Recoge, por bloques:
      1  Sistema y actualizaciones
      2  Crashes: Event Log 1000/1002, WER 1001, Report.wer, volcados existentes
      3  Apps: Outlook clasico y nuevo, Teams, WebView2, Electron, complementos
      4  Carpetas conocidas, redirecciones, OneDrive KFM, unidades de red, recientes
      5  Shell extensions, namespace extensions, preview/thumbnail/property handlers
      6  Inyeccion de DLL (AppInit/AppCert/IFEO), AV/EDR/DLP, minifilters, WDAC/ASR
      7  Politicas de Explorer y ComDlg32
      8  Integridad de los DLL del dialogo, CBS.log, disco
      9  Modulos no-Microsoft cargados en los procesos afectados
      10 Tests no interactivos del shell (enumeracion e instanciar COM del dialogo)
      11 Test interactivo del dialogo real en 64 y 32 bits (con -Interactive)

    Las rutas de red se prueban con limite de tiempo para que el diagnostico no se
    cuelgue en el mismo recurso que tumba a la aplicacion.

.PARAMETER ProcessName
    Procesos a inspeccionar (sin .exe). Se suman a los que aparezcan en los ultimos
    eventos de crash. Por defecto: outlook, olk, ms-teams, msedgewebview2, explorer.

.PARAMETER OutDir
    Carpeta del informe. Por defecto %TEMP%\FilePickerDiag.

.PARAMETER Interactive
    Ejecuta el test del dialogo real en 64 y 32 bits arrancando en varias carpetas
    conocidas. Abre ventanas: requiere la sesion interactiva del usuario afectado.

.PARAMETER EnableDumps
    Configura WER LocalDumps (volcado completo) para capturar el proximo crash.
    Requiere elevacion. Es la unica escritura del script.

.PARAMETER DryRun
    Con -EnableDumps, muestra lo que configuraria sin escribir nada.

.PARAMETER SkipSignatures
    Omite Authenticode. Mas rapido, pero se pierde la columna Firma.

.PARAMETER TimeoutSec
    Limite por cada prueba de ruta de red. Por defecto 3.

.EXAMPLE
    .\05-diagnose-file-picker-crash.ps1 -Interactive

.EXAMPLE
    .\05-diagnose-file-picker-crash.ps1 -ProcessName ms-teams -EnableDumps -DryRun

.NOTES
    PowerShell 5.1 y 7.
    Ejecutar en la sesion del usuario afectado: HKCU, recientes y OneDrive son suyos.
    Si no es administrador, lanzar dos veces: sin elevar (HKCU correcto) y elevado
    (HKLM, minifilters, modulos). La cabecera del informe dice que perfil se leyo.
    Abrir la aplicacion afectada antes de lanzarlo: la seccion 9 solo ve procesos vivos.
#>

[CmdletBinding()]
param(
    [string[]] $ProcessName = @('outlook', 'olk', 'ms-teams', 'msedgewebview2', 'explorer'),
    [string]   $OutDir,
    [switch]   $Interactive,
    [switch]   $EnableDumps,
    [switch]   $DryRun,
    [switch]   $SkipSignatures,
    [ValidateRange(1, 60)]
    [int]      $TimeoutSec = 3
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

# ---------------------------------------------------------------- infraestructura

if (-not $OutDir) { $OutDir = Join-Path $env:TEMP 'FilePickerDiag' }
$OutFile = Join-Path $OutDir ("FileDialogCrash_{0}_{1}.txt" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss'))

$ProcessName = @($ProcessName -split ',' | ForEach-Object { ([string]$_).Trim() -replace '\.exe$', '' } | Where-Object { $_ })
try {
    Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error', 'Application Hang'; Id = 1000, 1002 } -MaxEvents 20 -ErrorAction Stop |
        ForEach-Object { ([string]$_.Properties[0].Value) -replace '\.exe$', '' } |
        Where-Object { $_ -match '^[\w.-]+$' } | ForEach-Object { $ProcessName += $_ }
} catch {}
$ProcessName = @($ProcessName | Sort-Object -Unique)

$netRoots = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=4' | ForEach-Object { $_.DeviceID.ToUpper() })

function Test-PathFast {
    param([string]$Path)
    if (-not $Path) { return $false }
    $remote = $Path -like '\\*'
    if (-not $remote -and $Path.Length -ge 2 -and $netRoots -contains $Path.Substring(0, 2).ToUpper()) { $remote = $true }
    if (-not $remote) { return (Test-Path -LiteralPath $Path) }
    $ps = [PowerShell]::Create()
    try {
        [void]$ps.AddCommand('Test-Path').AddParameter('LiteralPath', $Path)
        $h = $ps.BeginInvoke()
        if ($h.AsyncWaitHandle.WaitOne($TimeoutSec * 1000)) {
            $r = [bool]($ps.EndInvoke($h) | Select-Object -First 1)
            $ps.Dispose()
            return $r
        }
        [void]$ps.BeginStop($null, $null)
        [void]$flags.Add("RUTA QUE NO RESPONDE EN ${TimeoutSec}s: $Path")
        return $false
    }
    catch { return $false }
}

$report    = New-Object System.Text.StringBuilder
$sigCache  = @{}
$archCache = @{}
$flags     = New-Object System.Collections.ArrayList

function Write-Line { param($Text) [void]$report.AppendLine([string]$Text) }

function Write-Block {
    param($Data)
    if ($null -eq $Data) { Write-Line '(sin datos)'; return }
    $t = ($Data | Out-String -Width 400).TrimEnd()
    if ($t) { Write-Line $t } else { Write-Line '(sin datos)' }
}

function Write-Section {
    param([string]$Title)
    Write-Line ''
    Write-Line ('=' * 78)
    Write-Line "## $Title"
    Write-Line ('=' * 78)
}

function Invoke-Probe {
    param([Parameter(Mandatory)][string]$Title, [Parameter(Mandatory)][scriptblock]$Body)
    Write-Section $Title
    Write-Host "  -> $Title" -ForegroundColor DarkGray
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try   { Write-Block (& $Body) }
    catch { Write-Line ('ERROR: ' + $_.Exception.Message) }
    $sw.Stop()
    Write-Line ('[{0} ms]' -f $sw.ElapsedMilliseconds)
}

function Get-RegDefault {
    param([string]$Path)
    try { (Get-ItemProperty -LiteralPath $Path -ErrorAction Stop).'(default)' } catch { $null }
}

function Get-PeArch {
    param([string]$File)
    if (-not $File) { return '' }
    if ($archCache.ContainsKey($File)) { return $archCache[$File] }
    $arch = 'n/a'
    try {
        $fs = [IO.File]::Open($File, 'Open', 'Read', 'ReadWrite')
        $br = New-Object IO.BinaryReader($fs)
        $fs.Position = 0x3C
        $pe = $br.ReadInt32()
        $fs.Position = $pe + 4
        $machine = $br.ReadUInt16()
        $fs.Close()
        switch ($machine) {
            0x014c  { $arch = 'x86'   }
            0x8664  { $arch = 'x64'   }
            0xAA64  { $arch = 'arm64' }
            0x01c4  { $arch = 'arm32' }
            default { $arch = ('0x{0:X}' -f $machine) }
        }
    } catch { $arch = 'n/a' }
    $archCache[$File] = $arch
    $arch
}

function Get-Signer {
    param([string]$File)
    if (-not $File) { return '' }
    if ($SkipSignatures) { return '(omitido)' }
    if ($sigCache.ContainsKey($File)) { return $sigCache[$File] }
    $val = 'n/a'
    try {
        $sig = Get-AuthenticodeSignature -FilePath $File -ErrorAction Stop
        if ($sig.SignerCertificate) {
            $cn = ($sig.SignerCertificate.Subject -split ',' | Where-Object { $_ -match 'CN=' }) -join ''
            if (-not $cn) { $cn = ($sig.SignerCertificate.Subject -split ',')[0] }
            $val = ($cn -replace '^\s*CN=', '').Trim()
        }
        else { $val = "SIN FIRMA ($($sig.Status))" }
    } catch { $val = 'n/a' }
    $sigCache[$File] = $val
    $val
}

function Test-MsSigner { param([string]$Signer) $Signer -match '^Microsoft (Corporation|Windows)' }

function Resolve-ClsidDll {
    param([string]$Clsid)
    if ($Clsid -notmatch '^\{') { return '' }
    foreach ($k in @(
        "HKLM:\SOFTWARE\Classes\CLSID\$Clsid\InprocServer32",
        "HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID\$Clsid\InprocServer32",
        "HKCU:\SOFTWARE\Classes\CLSID\$Clsid\InprocServer32",
        "HKLM:\SOFTWARE\Classes\CLSID\$Clsid\LocalServer32")) {
        $d = Get-RegDefault $k
        if ($d) { return ([Environment]::ExpandEnvironmentVariables([string]$d)).Trim('"') }
    }
    ''
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
              [Security.Principal.WindowsBuiltInRole]::Administrator)

# ---------------------------------------------------------------------- cabecera

Write-Host ''
Write-Host 'DIAG FILE-DIALOG CRASH' -ForegroundColor Cyan
Write-Host ("Elevado={0}  Interactive={1}  EnableDumps={2}  DryRun={3}" -f $isAdmin, [bool]$Interactive, [bool]$EnableDumps, [bool]$DryRun) -ForegroundColor DarkCyan
Write-Host ("Procesos: {0}" -f ($ProcessName -join ', ')) -ForegroundColor DarkCyan
Write-Host ''

Write-Line 'INFORME DE DIAGNOSTICO - CRASH AL ABRIR DIALOGO DE ARCHIVOS'
Write-Line ('Generado         : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
Write-Line ('Equipo           : ' + $env:COMPUTERNAME)
Write-Line ('Contexto usuario : ' + (whoami))
Write-Line ('Perfil HKCU      : ' + $env:USERPROFILE)
Write-Line ('Elevado          : ' + $isAdmin)
Write-Line ('PSVersion        : ' + $PSVersionTable.PSVersion + '  (' + $PSVersionTable.PSEdition + ')')
Write-Line ('Proceso PS       : ' + $(if ([Environment]::Is64BitProcess) { 'x64' } else { 'x86' }))
Write-Line ('OS 64-bit        : ' + [Environment]::Is64BitOperatingSystem)
Write-Line ('Firmas           : ' + $(if ($SkipSignatures) { 'OMITIDAS' } else { 'verificadas' }))
Write-Line ('Procesos         : ' + ($ProcessName -join ', '))
if (-not $isAdmin) {
    Write-Line ''
    Write-Line '*** AVISO: sin elevacion. HKLM, minifilters y modulos pueden salir incompletos.'
}

# ------------------------------------------------- 0. accion opcional: LocalDumps

if ($EnableDumps) {
    Write-Section '0. WER LOCALDUMPS (unica accion de escritura)'
    if (-not $isAdmin) {
        Write-Line 'OMITIDO: requiere consola elevada.'
        Write-Host '  !! -EnableDumps ignorado: falta elevacion' -ForegroundColor Yellow
    }
    elseif ($DryRun) {
        $dumpDir = Join-Path $env:PUBLIC 'CrashDumps'
        Write-Line "DRYRUN: se crearia $dumpDir y LocalDumps con DumpFolder=$dumpDir, DumpType=2, DumpCount=10."
        Write-Host "  .. DryRun: LocalDumps no se ha tocado" -ForegroundColor Yellow
    }
    else {
        try {
            $dumpKey = 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps'
            $dumpDir = Join-Path $env:PUBLIC 'CrashDumps'
            if (-not (Test-Path $dumpDir)) { New-Item -ItemType Directory -Path $dumpDir -Force | Out-Null }
            if (-not (Test-Path $dumpKey)) { New-Item -Path $dumpKey -Force | Out-Null }
            New-ItemProperty -Path $dumpKey -Name DumpFolder -Value $dumpDir -PropertyType ExpandString -Force | Out-Null
            New-ItemProperty -Path $dumpKey -Name DumpCount  -Value 10 -PropertyType DWord -Force | Out-Null
            New-ItemProperty -Path $dumpKey -Name DumpType   -Value 2  -PropertyType DWord -Force | Out-Null
            Write-Line "LocalDumps activo. Carpeta: $dumpDir (DumpType=2 completo, DumpCount=10)"
            Write-Line 'Reproducir el crash y recoger el .dmp de esa carpeta.'
            Write-Host "  ++ LocalDumps ON -> $dumpDir" -ForegroundColor Green
        } catch { Write-Line ('ERROR configurando LocalDumps: ' + $_.Exception.Message) }
    }
}

# ------------------------------------------------------------------- 1. sistema

Invoke-Probe '1. SISTEMA / HARDWARE' {
    $cs = Get-CimInstance Win32_ComputerSystem
    $os = Get-CimInstance Win32_OperatingSystem
    $bi = Get-CimInstance Win32_BIOS
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    [PSCustomObject]@{
        Fabricante  = $cs.Manufacturer
        Modelo      = $cs.Model
        ProductName = (Get-CimInstance Win32_ComputerSystemProduct).Name
        Serial      = $bi.SerialNumber
        BIOS        = ('{0} / {1}' -f $bi.SMBIOSBIOSVersion, $bi.ReleaseDate)
        OS          = $os.Caption
        Build       = ('{0}.{1}' -f $cv.CurrentBuild, $cv.UBR)
        DisplayVer  = $cv.DisplayVersion
        InstallDate = $os.InstallDate
        LastBoot    = $os.LastBootUpTime
        RAM_GB      = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        CPU         = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
        Dominio     = $cs.Domain
        EnDominio   = $cs.PartOfDomain
        UsuarioSes  = $cs.UserName
    } | Format-List
}

Invoke-Probe '1b. ULTIMAS ACTUALIZACIONES (12)' {
    Get-CimInstance Win32_QuickFixEngineering |
        Sort-Object InstalledOn -Descending | Select-Object -First 12 HotFixID, Description, InstalledOn |
        Format-Table -AutoSize
}

# ------------------------------------------------------------------- 2. crashes

Invoke-Probe '2. EVENT LOG - Application Error / Hang (20)' {
    Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000, 1002 } -MaxEvents 40 |
        Where-Object { $_.ProviderName -match 'Application (Error|Hang)' } |
        Select-Object -First 20 | ForEach-Object {
            $v = @($_.Properties | ForEach-Object { $_.Value })
            [PSCustomObject]@{
                Hora           = $_.TimeCreated
                Id             = $_.Id
                App            = $v[0]
                AppVersion     = $v[1]
                ModuloCulpable = $v[3]
                ModuloVersion  = $v[4]
                CodigoExcepcion= $v[6]
                Offset         = $v[7]
                RutaApp        = $v[9]
                RutaModulo     = $v[10]
            }
        } | Format-List
}

Invoke-Probe '2b. EVENT LOG - Windows Error Reporting 1001 (15)' {
    Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Windows Error Reporting'; Id = 1001 } -MaxEvents 15 |
        Select-Object -First 15 | ForEach-Object {
            $l = $_.Message -split "`r?`n" |
                 Where-Object { $_ -match 'Nombre de la aplicaci|Application Name|Fault Module|m.dulo con error|Sig\[|Bucket|^P[1-9]' }
            [PSCustomObject]@{ Hora = $_.TimeCreated; Datos = (($l | ForEach-Object { $_.Trim() }) -join ' | ') }
        } | Format-List
}

Invoke-Probe '2c. WER Report.wer (6 mas recientes, parseado)' {
    $dirs = @(
        (Join-Path $env:PROGRAMDATA  'Microsoft\Windows\WER\ReportArchive'),
        (Join-Path $env:PROGRAMDATA  'Microsoft\Windows\WER\ReportQueue'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER\ReportArchive'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER\ReportQueue')
    ) | Where-Object { Test-Path $_ }
    if (-not $dirs) { return '(sin carpetas WER accesibles)' }
    Get-ChildItem -Path $dirs -Recurse -Filter 'Report.wer' |
        Sort-Object LastWriteTime -Descending | Select-Object -First 6 | ForEach-Object {
            "----- $($_.FullName)   [$($_.LastWriteTime)]"
            Get-Content $_.FullName |
                Where-Object { $_ -match '^(EventType|EventTime|AppName|AppPath|AppVersion|ModName|ModVersion|ModTimeStamp|Exception|Sig\[|DynamicSig\[|TargetAppId|OsInfo\[0)' }
            ''
        }
}

Invoke-Probe '2d. Volcados existentes' {
    @((Join-Path $env:LOCALAPPDATA 'CrashDumps'), (Join-Path $env:PUBLIC 'CrashDumps')) |
        Where-Object { Test-Path $_ } | ForEach-Object {
            "----- $_"
            Get-ChildItem $_ -File | Sort-Object LastWriteTime -Descending | Select-Object -First 10 `
                Name, @{n='MB';e={[math]::Round($_.Length/1MB,1)}}, LastWriteTime | Format-Table -AutoSize
        }
}

Invoke-Probe '2e. Configuracion actual de LocalDumps' {
    $k = 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps'
    if (Test-Path $k) {
        Get-ItemProperty -LiteralPath $k | Select-Object * -ExcludeProperty PS* | Format-List
        Get-ChildItem -LiteralPath $k | ForEach-Object {
            "-- override por app: $($_.PSChildName)"
            Get-ItemProperty -LiteralPath $_.PSPath | Select-Object * -ExcludeProperty PS* | Format-List
        }
    }
    else { '(no configurado -> relanzar con -EnableDumps para capturar el stack del proximo crash)' }
}

# ---------------------------------------------------------------------- 3. apps

Invoke-Probe '3. OUTLOOK CLASICO (Office Click-to-Run / MSI)' {
    $c2r = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    if ($c2r) {
        $c2r | Select-Object Platform, ClientVersionToReport, ClientCulture, UpdateChannel,
                             ProductReleaseIds, InstallationPath, SharedComputerLicensing | Format-List
    }
    else { '(sin clave ClickToRun)' }

    '--- binarios OUTLOOK.EXE localizados:'
    @(
        (Join-Path $env:ProgramFiles        'Microsoft Office\root\Office16\OUTLOOK.EXE'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Office\root\Office16\OUTLOOK.EXE'),
        (Join-Path $env:ProgramFiles        'Microsoft Office\Office16\OUTLOOK.EXE'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Office\Office16\OUTLOOK.EXE')
    ) | Where-Object { $_ -and (Test-Path $_) } | ForEach-Object {
        [PSCustomObject]@{ Ruta = $_; Arch = (Get-PeArch $_); Version = (Get-Item $_).VersionInfo.FileVersion; Fecha = (Get-Item $_).LastWriteTime }
    } | Format-List

    '--- perfiles de Outlook:'
    Get-ChildItem 'HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Profiles' | Select-Object -ExpandProperty PSChildName
    '--- OST/PST:'
    Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook') -Filter '*.?st' |
        Select-Object Name, @{n='GB';e={[math]::Round($_.Length/1GB,2)}}, LastWriteTime | Format-Table -AutoSize
}

Invoke-Probe '3b. APPX relevantes (nuevo Outlook, Teams, runtimes, codecs)' {
    Get-AppxPackage | Where-Object {
        $_.Name -match 'OutlookForWindows|MSTeams|MicrosoftTeams|WindowsAppRuntime|VCLibs|communicationsapps|HEIFImage|HEVCVideo|WebpImage|RawImage|Windows\.Photos|FilePicker'
    } | Select-Object Name, Version, Architecture, Status | Sort-Object Name | Format-Table -AutoSize
}

Invoke-Probe '3c. APPS INSTALADAS de los procesos objetivo y Electron/WebView2' {
    $pat = (@('Electron', 'WebView2', 'Teams') + ($ProcessName | ForEach-Object { [regex]::Escape($_) })) -join '|'
    Get-ItemProperty -Path @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') |
        Where-Object { $_.DisplayName -match $pat } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation | Sort-Object DisplayName | Format-List

    '--- ejecutables bajo LOCALAPPDATA\Programs:'
    Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Programs') -Directory | ForEach-Object {
        $exe = Get-ChildItem $_.FullName -Filter '*.exe' -File | Sort-Object Length -Descending | Select-Object -First 1
        if ($exe) {
            [PSCustomObject]@{
                App      = $_.Name
                Exe      = $exe.Name
                Arch     = (Get-PeArch $exe.FullName)
                Version  = $exe.VersionInfo.FileVersion
                Electron = (Test-Path (Join-Path $_.FullName 'resources\app.asar'))
            }
        }
    } | Format-Table -AutoSize

    '--- procesos objetivo abiertos:'
    Get-Process -Name $ProcessName | Select-Object Id, ProcessName, StartTime, Path | Format-Table -AutoSize -Wrap
}

Invoke-Probe '3d. WEBVIEW2 RUNTIME / EDGE' {
    $g = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    @("HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$g",
      "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$g",
      "HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$g") | ForEach-Object {
        $p = Get-ItemProperty -LiteralPath $_
        if ($p) { [PSCustomObject]@{ Clave = $_; Nombre = $p.name; Version = $p.pv } }
    } | Format-List

    '--- msedge.exe:'
    @((Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
      (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe')) |
        Where-Object { $_ -and (Test-Path $_) } |
        ForEach-Object { [PSCustomObject]@{ Ruta = $_; Version = (Get-Item $_).VersionInfo.FileVersion; Arch = (Get-PeArch $_) } } | Format-List
}

Invoke-Probe '3e. COMPLEMENTOS DE OUTLOOK (LoadBehavior)' {
    @('HKCU:\SOFTWARE\Microsoft\Office\Outlook\Addins\*',
      'HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins\*',
      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\Outlook\Addins\*') |
        ForEach-Object { Get-ItemProperty -Path $_ } | ForEach-Object {
            [PSCustomObject]@{
                Addin        = $_.PSChildName
                FriendlyName = $_.FriendlyName
                LoadBehavior = $_.LoadBehavior
                Vista        = $(if ($_.PSPath -match 'WOW6432Node') { 'HKLM32' } elseif ($_.PSPath -match 'HKEY_LOCAL_MACHINE') { 'HKLM64' } else { 'HKCU' })
            }
        } | Sort-Object Addin -Unique | Format-Table -AutoSize -Wrap

    '--- deshabilitados por Office (Resiliency):'
    Get-ChildItem 'HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Resiliency' -Recurse | ForEach-Object {
        $p = Get-ItemProperty -LiteralPath $_.PSPath
        if ($p) { "$($_.PSChildName) :: " + (($p.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { $_.Name }) -join ', ') }
    }
}

# ------------------------------------------------- 4. carpetas conocidas y red

Invoke-Probe '4. USER SHELL FOLDERS (HKCU) - redirecciones y validez' {
    $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    $rows = (Get-Item -LiteralPath $k).Property | ForEach-Object {
        $n   = $_
        $raw = (Get-ItemProperty -LiteralPath $k -Name $n).$n
        $exp = [Environment]::ExpandEnvironmentVariables([string]$raw)
        [PSCustomObject]@{ Nombre = $n; Valor = $raw; Expandido = $exp; Existe = (Test-PathFast $exp); EsUNC = ($exp -like '\\*') }
    }
    $roto = $rows | Where-Object { -not $_.Existe }
    if ($roto) { [void]$flags.Add('CARPETAS CONOCIDAS ROTAS: ' + (($roto | ForEach-Object { "$($_.Nombre)=$($_.Expandido)" }) -join ' ; ')) }
    $rows | Sort-Object Existe, Nombre | Format-Table -AutoSize -Wrap
}

Invoke-Probe '4b. SHELL FOLDERS (HKCU) - rutas resueltas' {
    $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'
    (Get-Item -LiteralPath $k).Property | ForEach-Object {
        $n = $_; $v = (Get-ItemProperty -LiteralPath $k -Name $n).$n
        [PSCustomObject]@{ Nombre = $n; Ruta = $v; Existe = (Test-PathFast ([string]$v)) }
    } | Sort-Object Existe, Nombre | Format-Table -AutoSize -Wrap
}

Invoke-Probe '4c. KNOWN FOLDERS via .NET - solo las problematicas' {
    $bad = [Enum]::GetNames([Environment+SpecialFolder]) | ForEach-Object {
        $p = [Environment]::GetFolderPath($_)
        if ($p) { [PSCustomObject]@{ Carpeta = $_; Ruta = $p; Existe = (Test-PathFast $p) } }
    } | Where-Object { -not $_.Existe -or $_.Ruta -like '\\*' }
    if ($bad) { $bad | Format-Table -AutoSize -Wrap }
    else { 'Todas las known folders resuelven a rutas existentes.' }
}

Invoke-Probe '4d. ONEDRIVE / KFM' {
    Get-ChildItem 'HKCU:\Software\Microsoft\OneDrive\Accounts' | ForEach-Object {
        $p = Get-ItemProperty -LiteralPath $_.PSPath
        [PSCustomObject]@{
            Cuenta     = $_.PSChildName
            UserFolder = $p.UserFolder
            Existe     = (Test-PathFast ([string]$p.UserFolder))
            Email      = $p.UserEmail
            KFM        = (($p.PSObject.Properties | Where-Object { $_.Name -match 'Kfm' } | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '; ')
        }
    } | Format-List
    '--- proceso OneDrive:'
    Get-Process OneDrive | Select-Object Id, StartTime, Path
    '--- politica OneDrive por GPO:'
    Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\OneDrive' | Select-Object * -ExcludeProperty PS* | Format-List
}

Invoke-Probe '4e. UNIDADES DE RED Y ALCANZABILIDAD' {
    Get-CimInstance Win32_MappedLogicalDisk |
        Select-Object DeviceID, ProviderName, @{n='FreeGB';e={[math]::Round($_.FreeSpace/1GB,1)}} | Format-Table -AutoSize
    '--- HKCU:\Network (mapeos persistentes):'
    $net = Get-ChildItem 'HKCU:\Network' | ForEach-Object {
        $p = Get-ItemProperty -LiteralPath $_.PSPath
        [PSCustomObject]@{ Letra = $_.PSChildName; Remoto = $p.RemotePath; Alcanzable = (Test-PathFast ([string]$p.RemotePath)) }
    }
    $muerto = $net | Where-Object { -not $_.Alcanzable }
    if ($muerto) { [void]$flags.Add('UNIDADES DE RED NO ALCANZABLES: ' + (($muerto | ForEach-Object { "$($_.Letra)=$($_.Remoto)" }) -join ' ; ')) }
    $net | Format-Table -AutoSize
    '--- PSDrives:'
    Get-PSDrive -PSProvider FileSystem | Select-Object Name, Root,
        @{n='UsedGB';e={[math]::Round($_.Used/1GB,1)}}, @{n='FreeGB';e={[math]::Round($_.Free/1GB,1)}} | Format-Table -AutoSize
    '--- accesos directos apuntando a UNC o destino inexistente:'
    @([Environment]::GetFolderPath('Desktop'), (Join-Path $env:USERPROFILE 'Links')) |
        Where-Object { $_ -and (Test-Path $_) } |
        ForEach-Object { Get-ChildItem $_ -Filter '*.lnk' } | ForEach-Object {
            $ws = New-Object -ComObject WScript.Shell
            $t  = $ws.CreateShortcut($_.FullName).TargetPath
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ws)
            if ($t -like '\\*' -or ($t -and -not (Test-PathFast $t))) {
                [PSCustomObject]@{ Lnk = $_.Name; Destino = $t; Existe = (Test-PathFast $t) }
            }
        } | Format-Table -AutoSize -Wrap
}

Invoke-Probe '4f. RECIENTES / JUMPLISTS (volumen)' {
    @((Join-Path $env:APPDATA 'Microsoft\Windows\Recent'),
      (Join-Path $env:APPDATA 'Microsoft\Windows\Recent\AutomaticDestinations'),
      (Join-Path $env:APPDATA 'Microsoft\Windows\Recent\CustomDestinations')) | ForEach-Object {
        $f   = Get-ChildItem $_ -File
        $big = $f | Sort-Object Length -Descending | Select-Object -First 1
        [PSCustomObject]@{
            Ruta        = $_
            Archivos    = @($f).Count
            TotalKB     = [math]::Round((($f | Measure-Object Length -Sum).Sum) / 1KB, 0)
            MasGrande   = $big.Name
            MasGrandeKB = [math]::Round($big.Length / 1KB, 0)
        }
    } | Format-Table -AutoSize -Wrap
}

# ------------------------------------------------- 5. shell extensions/handlers

Invoke-Probe '5. SHELL EXTENSIONS NO-MICROSOFT (con arquitectura del DLL)' {
    $roots = @(
        'HKLM:\SOFTWARE\Classes\*\shellex\ContextMenuHandlers',
        'HKLM:\SOFTWARE\Classes\*\shellex\PropertySheetHandlers',
        'HKLM:\SOFTWARE\Classes\AllFilesystemObjects\shellex\ContextMenuHandlers',
        'HKLM:\SOFTWARE\Classes\Directory\shellex\ContextMenuHandlers',
        'HKLM:\SOFTWARE\Classes\Directory\shellex\DragDropHandlers',
        'HKLM:\SOFTWARE\Classes\Directory\shellex\CopyHookHandlers',
        'HKLM:\SOFTWARE\Classes\Directory\Background\shellex\ContextMenuHandlers',
        'HKLM:\SOFTWARE\Classes\Folder\shellex\ContextMenuHandlers',
        'HKLM:\SOFTWARE\Classes\Drive\shellex\ContextMenuHandlers',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers',
        'HKCU:\SOFTWARE\Classes\*\shellex\ContextMenuHandlers',
        'HKCU:\SOFTWARE\Classes\Directory\shellex\ContextMenuHandlers',
        'HKCU:\SOFTWARE\Classes\Folder\shellex\ContextMenuHandlers'
    )
    $all = New-Object System.Collections.ArrayList
    foreach ($r in $roots) {
        Get-ChildItem -LiteralPath $r | ForEach-Object {
            $clsid = Get-RegDefault $_.PSPath
            if (-not $clsid) { $clsid = (Get-ItemProperty -LiteralPath $_.PSPath).CLSID }
            if ($clsid -notmatch '^\{') { return }
            $dll = Resolve-ClsidDll $clsid
            if (-not $dll) { return }
            $nombre = Get-RegDefault "HKLM:\SOFTWARE\Classes\CLSID\$clsid"
            if (-not $nombre) { $nombre = Get-RegDefault "HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID\$clsid" }
            [void]$all.Add([PSCustomObject]@{
                Handler = $_.PSChildName
                Nombre  = $nombre
                Arch    = (Get-PeArch $dll)
                Firma   = (Get-Signer $dll)
                Existe  = (Test-PathFast $dll)
                DLL     = $dll
                Origen  = ($r -replace 'HK(LM|CU):\\SOFTWARE\\', '$1:')
            })
        }
    }
    $noMs = $all | Where-Object { -not (Test-MsSigner $_.Firma) -or -not $_.Existe }
    $uniq = $noMs | Sort-Object DLL -Unique
    if ($noMs) { $noMs | Sort-Object DLL, Handler -Unique | Format-Table -AutoSize -Wrap }
    else { 'Sin shell extensions de terceros en estas claves.' }
    ''
    "TOTAL handlers inspeccionados : $(@($all).Count)"
    "DLL unicos no-Microsoft       : $(@($uniq).Count)"
    "  de ellos x86                : $(@($uniq | Where-Object { $_.Arch -eq 'x86' }).Count)"
    "  de ellos inexistentes       : $(@($uniq | Where-Object { -not $_.Existe }).Count)"
    $fantasma = $uniq | Where-Object { -not $_.Existe }
    if ($fantasma) { [void]$flags.Add('SHELL EXTENSIONS APUNTANDO A DLL INEXISTENTE: ' + (($fantasma | ForEach-Object { $_.DLL }) -join ' ; ')) }
}

Invoke-Probe '5b. NAMESPACE EXTENSIONS (paneles del dialogo)' {
    @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace',
      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace',
      'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace',
      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace',
      'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace',
      'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace') | ForEach-Object {
        $root = $_
        Get-ChildItem -LiteralPath $root | ForEach-Object {
            $dll = Resolve-ClsidDll $_.PSChildName
            [PSCustomObject]@{
                Ubicacion = ($root -replace '.*Explorer\\', '') + $(if ($root -match 'HKCU') { ' (HKCU)' } elseif ($root -match 'WOW6432') { ' (32)' } else { ' (HKLM)' })
                CLSID     = $_.PSChildName
                Nombre    = (Get-RegDefault $_.PSPath)
                Arch      = (Get-PeArch $dll)
                Firma     = (Get-Signer $dll)
                DLL       = $dll
            }
        }
    } | Format-Table -AutoSize -Wrap
}

Invoke-Probe '5c. PREVIEW HANDLERS no-Microsoft' {
    $ph = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PreviewHandlers'
    if (-not $ph) { return '(sin clave PreviewHandlers)' }
    $ph.PSObject.Properties | Where-Object { $_.Name -match '^\{' } | ForEach-Object {
        $dll = Resolve-ClsidDll $_.Name
        [PSCustomObject]@{ Nombre = $_.Value; Arch = (Get-PeArch $dll); Firma = (Get-Signer $dll); DLL = $dll }
    } | Where-Object { -not (Test-MsSigner $_.Firma) } | Format-Table -AutoSize -Wrap
}

Invoke-Probe '5d. THUMBNAIL PROVIDERS por extension' {
    $iid = '{e357fccd-a995-4576-b01f-234630154e96}'
    '.pdf','.jpg','.jpeg','.png','.heic','.tif','.tiff','.gif','.bmp','.webp',
    '.docx','.xlsx','.pptx','.msg','.eml','.zip','.rar','.7z','.dwg','.psd','.mp4' | ForEach-Object {
        $ext   = $_
        $clsid = Get-RegDefault "HKLM:\SOFTWARE\Classes\$ext\ShellEx\$iid"
        if (-not $clsid) {
            $prog = Get-RegDefault "HKLM:\SOFTWARE\Classes\$ext"
            if ($prog) { $clsid = Get-RegDefault "HKLM:\SOFTWARE\Classes\$prog\ShellEx\$iid" }
        }
        if (-not $clsid) { $clsid = Get-RegDefault "HKCU:\SOFTWARE\Classes\$ext\ShellEx\$iid" }
        if ($clsid) {
            $dll = Resolve-ClsidDll $clsid
            [PSCustomObject]@{ Ext = $ext; Arch = (Get-PeArch $dll); Firma = (Get-Signer $dll); DLL = $dll }
        }
    } | Format-Table -AutoSize -Wrap
}

Invoke-Probe '5e. PROPERTY HANDLERS no-Microsoft' {
    Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PropertySystem\PropertyHandlers' | ForEach-Object {
        $dll = Resolve-ClsidDll (Get-RegDefault $_.PSPath)
        if ($dll) { [PSCustomObject]@{ Ext = $_.PSChildName; Arch = (Get-PeArch $dll); Firma = (Get-Signer $dll); DLL = $dll } }
    } | Where-Object { -not (Test-MsSigner $_.Firma) } | Sort-Object DLL, Ext | Format-Table -AutoSize -Wrap
}

Invoke-Probe '5f. Shell Extensions Approved - entradas no-Microsoft' {
    $a = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved'
    if (-not $a) { return '(sin clave Approved)' }
    $a.PSObject.Properties | Where-Object { $_.Name -match '^\{' } | ForEach-Object {
        $dll = Resolve-ClsidDll $_.Name
        if ($dll) {
            $f = Get-Signer $dll
            if (-not (Test-MsSigner $f)) {
                [PSCustomObject]@{ Nombre = $_.Value; Arch = (Get-PeArch $dll); Firma = $f; Existe = (Test-PathFast $dll); DLL = $dll }
            }
        }
    } | Sort-Object DLL -Unique | Format-Table -AutoSize -Wrap
}

# ------------------------------------------------------ 6. inyeccion y seguridad

Invoke-Probe '6. INYECCION GLOBAL DE DLL (AppInit / AppCert / IFEO / SilentProcessExit)' {
    '--- AppInit_DLLs:'
    $ai = @('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows') | ForEach-Object {
        $p = Get-ItemProperty -LiteralPath $_
        [PSCustomObject]@{
            Vista         = $(if ($_ -match 'WOW6432') { '32-bit' } else { '64-bit' })
            AppInit_DLLs  = $p.AppInit_DLLs
            LoadAppInit   = $p.LoadAppInit_DLLs
            RequireSigned = $p.RequireSignedAppInit_DLLs
        }
    }
    $ai | Format-Table -AutoSize -Wrap
    $hit = $ai | Where-Object { $_.AppInit_DLLs }
    if ($hit) { [void]$flags.Add('APPINIT_DLLS PRESENTE: ' + (($hit | ForEach-Object { "$($_.Vista)=$($_.AppInit_DLLs)" }) -join ' ; ')) }

    '--- AppCertDlls:'
    $ac = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\AppCertDlls'
    if ($ac) { $ac | Select-Object * -ExcludeProperty PS* | Format-List } else { '(vacio)' }

    '--- IFEO con Debugger / GlobalFlag / VerifierDlls:'
    Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options' | ForEach-Object {
        $p = Get-ItemProperty -LiteralPath $_.PSPath
        if ($p.Debugger -or $p.GlobalFlag -or $p.VerifierDlls -or $p.MitigationOptions) {
            [PSCustomObject]@{ Imagen = $_.PSChildName; Debugger = $p.Debugger; GlobalFlag = $p.GlobalFlag; VerifierDlls = $p.VerifierDlls; Mitigation = $p.MitigationOptions }
        }
    } | Format-Table -AutoSize -Wrap

    '--- SilentProcessExit:'
    Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SilentProcessExit' | ForEach-Object {
        $p = Get-ItemProperty -LiteralPath $_.PSPath
        [PSCustomObject]@{ Imagen = $_.PSChildName; ReportingMode = $p.ReportingMode; MonitorProcess = $p.MonitorProcess; DumpFolder = $p.LocalDumpFolder }
    } | Format-Table -AutoSize -Wrap
}

Invoke-Probe '6b. ANTIVIRUS / EDR / DLP / SYNC DE NUBE' {
    '--- Security Center:'
    Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct |
        Select-Object displayName, @{n='productState';e={'0x{0:X}' -f $_.productState}}, pathToSignedProductExe | Format-List

    '--- software relevante instalado:'
    @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
      'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') |
        ForEach-Object { Get-ItemProperty -Path $_ } |
        Where-Object { $_.DisplayName -match 'Sophos|Trellix|McAfee|Symantec|Broadcom|CrowdStrike|SentinelOne|Cortex|Palo Alto|Netskope|Forcepoint|Zscaler|Trend Micro|ESET|Kaspersky|Bitdefender|WithSecure|F-Secure|Cisco|Umbrella|Digital Guardian|Endpoint Protector|Safend|Information Protection|Purview|Rights Management|iCloud|Dropbox|Google Drive|Box |Egnyte|pCloud|MEGA|Nextcloud|ownCloud|Citrix|VMware|Nitro|Foxit|Adobe Acrobat|WinZip|WinRAR|7-Zip|Bandizip|TeamViewer|AnyDesk|Lenovo|Glance|Nuance|Kofax|Autodesk|SOLIDWORKS|DocuWare|Kyocera|Xerox|Canon|Ricoh|Sharp' } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate | Sort-Object DisplayName -Unique | Format-Table -AutoSize -Wrap

    '--- servicios en ejecucion no-Microsoft:'
    Get-CimInstance Win32_Service |
        Where-Object { $_.State -eq 'Running' -and $_.PathName -and $_.PathName -notmatch 'Windows\\(System32|SysWOW64|servicing)' } |
        Select-Object Name, DisplayName, StartMode, PathName | Sort-Object DisplayName | Format-Table -AutoSize -Wrap
}

Invoke-Probe '6c. MINIFILTERS DEL SISTEMA DE ARCHIVOS' {
    if ($isAdmin) { & fltmc.exe filters } else { 'OMITIDO: requiere elevacion.' }
}

Invoke-Probe '6d. WDAC / APPLOCKER / DEFENDER ASR / MITIGACIONES' {
    '--- AppLocker efectivo:'
    $al = Get-AppLockerPolicy -Effective
    if ($al) { $al.RuleCollections | ForEach-Object { [PSCustomObject]@{ Tipo = $_.RuleCollectionType; Modo = $_.EnforcementMode; Reglas = @($_).Count } } | Format-Table -AutoSize }
    else { '(sin politica AppLocker)' }

    '--- Device Guard / WDAC:'
    Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard |
        Select-Object CodeIntegrityPolicyEnforcementStatus, UsermodeCodeIntegrityPolicyEnforcementStatus,
                      SecurityServicesConfigured, SecurityServicesRunning, VirtualizationBasedSecurityStatus | Format-List
    Get-ChildItem (Join-Path $env:WINDIR 'System32\CodeIntegrity\CiPolicies\Active') | Select-Object Name, LastWriteTime | Format-Table -AutoSize

    '--- Defender ASR / Controlled Folder Access:'
    $mp = Get-MpPreference
    if ($mp) {
        [PSCustomObject]@{
            ASR_Ids     = ($mp.AttackSurfaceReductionRules_Ids -join ', ')
            ASR_Actions = ($mp.AttackSurfaceReductionRules_Actions -join ', ')
            CFA         = $mp.EnableControlledFolderAccess
            CFA_Folders = ($mp.ControlledFolderAccessProtectedFolders -join '; ')
            CFA_Allowed = ($mp.ControlledFolderAccessAllowedApplications -join '; ')
            Exclusiones = ($mp.ExclusionPath -join '; ')
        } | Format-List
    }
    Get-MpComputerStatus | Select-Object AMProductVersion, AMEngineVersion, AntivirusSignatureVersion, RealTimeProtectionEnabled, IsTamperProtected | Format-List

    '--- ProcessMitigations por imagen:'
    @($ProcessName + 'msedge' + 'powershell' | ForEach-Object { "$_.exe" } | Sort-Object -Unique) | ForEach-Object {
        $m = Get-ProcessMitigation -Name $_
        if ($m) {
            [PSCustomObject]@{
                Exe           = $_
                CFG           = $m.CFG.Enable
                DEP           = $m.DEP.Enable
                ForceASLR     = $m.ASLR.ForceRelocateImages
                BlockRemote   = $m.ImageLoad.BlockRemoteImageLoads
                BlockLowLabel = $m.ImageLoad.BlockLowLabelImageLoads
                EAF           = $m.PayloadRestriction.EnableExportAddressFilter
                IAF           = $m.PayloadRestriction.EnableImportAddressFilter
                NoChildProc   = $m.ChildProcess.DisallowChildProcessCreation
            }
        }
    } | Format-Table -AutoSize
}

# ------------------------------------------------------------------ 7. politicas

Invoke-Probe '7. POLITICAS DE EXPLORER Y COMDLG32' {
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer',
      'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\ComDlg32',
      'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer',
      'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer',
      'HKCU:\Software\Policies\Microsoft\Windows\Explorer',
      'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced',
      'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32',
      'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent') | ForEach-Object {
        if (Test-Path -LiteralPath $_) {
            "----- $_"
            Get-ItemProperty -LiteralPath $_ | Select-Object * -ExcludeProperty PS* | Format-List
            $sub = Get-ChildItem -LiteralPath $_ | Select-Object -ExpandProperty PSChildName
            if ($sub) { '   subclaves: ' + ($sub -join ', ') }
        }
    }
    '--- GPO aplicadas:'
    $gpo = foreach ($ext in @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\History')) {
        try {
            Get-ChildItem -LiteralPath $ext.PSPath -ErrorAction Stop |
                ForEach-Object { (Get-ItemProperty -LiteralPath $_.PSPath).DisplayName }
        } catch {}
    }
    $gpo | Where-Object { $_ } | Sort-Object -Unique
}

# ----------------------------------------------------------------- 8. integridad

Invoke-Probe '8. INTEGRIDAD DE LOS DLL DEL DIALOGO' {
    'comdlg32.dll','shell32.dll','windows.storage.dll','shcore.dll','ntdll.dll','twinui.dll',
    'twinui.pcshell.dll','explorerframe.dll','propsys.dll','windows.ui.dll','wintypes.dll',
    'shlwapi.dll','combase.dll','thumbcache.dll','ucrtbase.dll' | Sort-Object -Unique | ForEach-Object {
        $p = Join-Path $env:WINDIR "System32\$_"
        if (Test-Path $p) {
            $i = Get-Item $p
            [PSCustomObject]@{
                DLL     = $_
                Version = $i.VersionInfo.FileVersion
                Fecha   = $i.LastWriteTime
                KB      = [math]::Round($i.Length / 1KB, 0)
                Firma   = $(if ($SkipSignatures) { "(omitido)" } else { (Get-AuthenticodeSignature $p).Status })
            }
        }
    } | Format-Table -AutoSize
}

Invoke-Probe '8b. CBS.log - errores de corrupcion recientes' {
    $cbs = Join-Path $env:WINDIR 'Logs\CBS\CBS.log'
    if (-not (Test-Path $cbs)) { return '(sin CBS.log)' }
    $hits = Get-Content $cbs -Tail 6000 |
        Select-String -Pattern 'Cannot repair|cannot repair|corrupt|Repair failed|Hashes for file member' |
        Select-Object -Last 25 | ForEach-Object { $_.Line.Trim() }
    if ($hits) { $hits } else { '(sin entradas de corrupcion en la cola del log)' }
}

Invoke-Probe '8c. DISCO / VOLUMENES / ERRORES DE ALMACENAMIENTO' {
    Get-Volume | Where-Object DriveLetter |
        Select-Object DriveLetter, FileSystem, HealthStatus,
            @{n='LibreGB';e={[math]::Round($_.SizeRemaining/1GB,1)}},
            @{n='TotalGB';e={[math]::Round($_.Size/1GB,1)}} | Format-Table -AutoSize
    Get-PhysicalDisk | Select-Object DeviceId, FriendlyName, MediaType, HealthStatus, OperationalStatus,
        @{n='TamGB';e={[math]::Round($_.Size/1GB,0)}} | Format-Table -AutoSize
    '--- eventos de disco/filesystem (10):'
    Get-WinEvent -LogName System -MaxEvents 400 |
        Where-Object { $_.Id -in 7,11,51,55,98,129,153,157 } |
        Select-Object -First 10 TimeCreated, Id, ProviderName, @{n='Msg';e={($_.Message -split "`r?`n")[0]}} |
        Format-Table -AutoSize -Wrap
}

# ------------------------------------------------------------------- 9. modulos

Invoke-Probe '9. MODULOS NO-MICROSOFT EN LOS PROCESOS AFECTADOS' {
    $procs = Get-Process -Name $ProcessName
    if (-not $procs) { return ('Ninguno de los procesos objetivo esta abierto ({0}). Abrir la aplicacion afectada y repetir.' -f ($ProcessName -join ', ')) }
    foreach ($p in $procs) {
        $arch = if ($p.Path) { Get-PeArch $p.Path } else { '?' }
        "----- $($p.ProcessName)  PID=$($p.Id)  Arch=$arch"
        "      Path: $($p.Path)"
        try {
            $mods = $p.Modules | Where-Object {
                $_.FileName -and $_.FileName -notmatch '\\Windows\\(System32|SysWOW64|WinSxS|SystemApps|assembly|Microsoft\.NET)\\'
            }
            if ($mods) {
                $mods | ForEach-Object {
                    [PSCustomObject]@{ Modulo = $_.ModuleName; Version = $_.FileVersionInfo.FileVersion; Empresa = $_.FileVersionInfo.CompanyName; Ruta = $_.FileName }
                } | Sort-Object Modulo | Format-Table -AutoSize -Wrap
            }
            else { '      (solo modulos de System32)' }
        }
        catch { '      (sin acceso a modulos: ' + $_.Exception.Message + ')' }
        ''
    }
}

Invoke-Probe '9b. AUTORUNS - claves Run' {
    @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
      'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
      'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce') | ForEach-Object {
        $k = $_
        $p = Get-ItemProperty -LiteralPath $k
        if ($p) {
            $p.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
                [PSCustomObject]@{ Vista = ($k -replace 'HK(LM|CU):\\SOFTWARE\\', '$1:'); Nombre = $_.Name; Comando = $_.Value }
            }
        }
    } | Format-Table -AutoSize -Wrap
}

# ------------------------------------------------------- 10. tests del shell

Invoke-Probe '10. TEST: enumeracion de carpetas conocidas via Shell COM' {
    $sh = New-Object -ComObject Shell.Application
    $map = @{ 0='Escritorio'; 5='Mis documentos'; 6='Favoritos'; 8='Recientes'; 11='Menu Inicio';
              16='Escritorio (fs)'; 17='Este equipo'; 18='Red'; 20='Fuentes'; 26='AppData';
              33='Imagenes'; 38='Program Files'; 39='Mis imagenes'; 40='Perfil de usuario' }
    $res = foreach ($id in ($map.Keys | Sort-Object)) {
        try {
            $f = $sh.NameSpace([int]$id)
            if ($f) { [PSCustomObject]@{ CSIDL=$id; Etiqueta=$map[$id]; Titulo=$f.Title; Ruta=$f.Self.Path; Items=@($f.Items()).Count; Estado='OK' } }
            else    { [PSCustomObject]@{ CSIDL=$id; Etiqueta=$map[$id]; Titulo=''; Ruta=''; Items=-1; Estado='NULL' } }
        }
        catch { [PSCustomObject]@{ CSIDL=$id; Etiqueta=$map[$id]; Titulo=''; Ruta=$_.Exception.Message; Items=-1; Estado='ERROR' } }
    }
    $res | Format-Table -AutoSize -Wrap
    $err = $res | Where-Object { $_.Estado -ne 'OK' }
    if ($err) { [void]$flags.Add('SHELL NO PUEDE ENUMERAR: ' + (($err | ForEach-Object { $_.Etiqueta }) -join ' ; ')) }
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($sh)
}

Invoke-Probe '10b. TEST: enumeracion de shell:Recent' {
    $sh = New-Object -ComObject Shell.Application
    try {
        $r = $sh.NameSpace('shell:Recent')
        if (-not $r) { return 'shell:Recent devolvio NULL' }
        $items = @($r.Items())
        "Elementos en Recientes: $($items.Count)"
        $items | Select-Object -First 60 | ForEach-Object {
            [PSCustomObject]@{ Nombre = $_.Name; Ruta = $_.Path; Existe = (Test-PathFast $_.Path); EsUNC = ($_.Path -like '\\*') }
        } | Where-Object { -not $_.Existe -or $_.EsUNC } | Format-Table -AutoSize -Wrap
        '(solo se listan los que no existen o son UNC)'
    }
    catch { 'ERROR enumerando shell:Recent -> ' + $_.Exception.Message }
    finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($sh) }
}

Invoke-Probe '10c. TEST: instanciar los COM del dialogo de archivos' {
    @(@{ N='FileOpenDialog';   C='{DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7}' },
      @{ N='FileSaveDialog';   C='{C0B4E2F3-BA21-4773-8DBA-335EC946EB8B}' },
      @{ N='KnownFolderMgr';   C='{4df0c730-df9d-4ae3-9153-aa6b82e9795a}' },
      @{ N='ShellItemFactory'; C='{9ac9fbe1-e0a2-4ad6-b4ee-e212013ea917}' }) | ForEach-Object {
        $r = 'OK'
        try {
            $t = [Type]::GetTypeFromCLSID([Guid]$_.C)
            $o = [Activator]::CreateInstance($t)
            if ($o) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($o) } else { $r = 'NULL' }
        }
        catch { $r = 'FALLO: ' + $_.Exception.Message }
        [PSCustomObject]@{ Componente = $_.N; CLSID = $_.C; Resultado = $r }
    } | Format-Table -AutoSize -Wrap
}

# ------------------------------------------------------- 11. test interactivo

if ($Interactive) {
    Invoke-Probe '11. TEST INTERACTIVO: OpenFileDialog en 64 y 32 bits' {
        $probe = {
            Add-Type -AssemblyName System.Windows.Forms
            foreach ($t in 'MyDocuments','MyPictures','Desktop','UserProfile','Recent','MyComputer') {
                $path = [Environment]::GetFolderPath($t)
                try {
                    $dlg = New-Object System.Windows.Forms.OpenFileDialog
                    $dlg.AutoUpgradeEnabled = $true
                    if ($path) { $dlg.InitialDirectory = $path }
                    $null = $dlg.ShowDialog()
                    $dlg.Dispose()
                    Write-Output "OK     :: $t -> $path"
                }
                catch { Write-Output ("CRASH  :: $t -> $path :: " + $_.Exception.Message) }
            }
        }

        $bits = if ([Environment]::Is64BitProcess) { '64-bit' } else { '32-bit' }
        "===== proceso actual ($bits) ====="
        Write-Host "    dialogos $bits`: cerrar cada ventana con Cancelar" -ForegroundColor Yellow
        & $probe
        if (-not [Environment]::Is64BitProcess) { return }

        '===== proceso 32-bit (SysWOW64) ====='
        $ps32 = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
        if (Test-Path $ps32) {
            Write-Host '    dialogos 32-bit: cerrar cada ventana con Cancelar' -ForegroundColor Yellow
            $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($probe.ToString()))
            $o = & $ps32 -NoProfile -EncodedCommand $enc 2>&1
            if ($o) { $o } else { "SIN SALIDA del proceso 32-bit -> indicio fuerte de crash en 32 bits" }
            "ExitCode 32-bit: $LASTEXITCODE"
            if (-not $o) { [void]$flags.Add('EL PROCESO 32-BIT MURIO AL ABRIR EL DIALOGO -> shell extension x86 (ver seccion 5, columna Arch=x86)') }
        }
        else { '(no existe SysWOW64\WindowsPowerShell: equipo ARM o sin WOW64)' }
    }
}
else {
    Write-Section '11. TEST INTERACTIVO'
    Write-Line 'OMITIDO. Relanzar con -Interactive en la sesion del usuario afectado.'
}

# ---------------------------------------------------------------------- cierre

Write-Section 'RESUMEN AUTOMATICO DE INDICIOS'
try {
    $last = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000 } -MaxEvents 10 |
        Where-Object { $_.ProviderName -match 'Application Error' } | Select-Object -First 1
    if ($last) {
        $v = @($last.Properties | ForEach-Object { $_.Value })
        [void]$flags.Add(('ULTIMO CRASH: {0} v{1} -> modulo {2} v{3}  exc={4} off={5}  ({6})' -f $v[0], $v[1], $v[3], $v[4], $v[6], $v[7], $last.TimeCreated))
    }
} catch {}

if ($flags.Count -gt 0) { $flags | ForEach-Object { Write-Line ('* ' + $_) } }
else { Write-Line 'Sin indicios automaticos. Revisar a mano las secciones 2, 5 y 9.' }

Write-Section 'FIN DEL INFORME'
Write-Line ('Archivo: ' + $OutFile)

$dir = Split-Path $OutFile -Parent
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$report.ToString() | Out-File -FilePath $OutFile -Encoding UTF8 -Force

Write-Host ''
Write-Host ('LISTO -> ' + $OutFile) -ForegroundColor Green
Write-Host ('Tamano: ' + [math]::Round((Get-Item $OutFile).Length / 1KB, 1) + ' KB') -ForegroundColor Green
if ($flags.Count -gt 0) {
    Write-Host ''
    Write-Host 'INDICIOS DETECTADOS:' -ForegroundColor Yellow
    $flags | ForEach-Object { Write-Host ('  * ' + $_) -ForegroundColor Yellow }
}
Write-Host ''
