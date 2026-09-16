<#
.SYNOPSIS
    [ES] Solo lectura. Inventario de todo lo que puede colgar el selector de archivos de Windows.
    [EN] Read-only. Inventory of everything that can hang the Windows file picker.

.DESCRIPTION
    No modifica nada. Recoge, por orden de probabilidad real de ser la causa:

      1. ComDlg32 MRU  - carpeta inicial del picker POR APLICACION
                         (LastVisitedPidlMRU). Si apunta a UNC muerta / DMS /
                         OneDrive roto, el dialogo cuelga al enumerarla.
      2. Unidades de red y rutas UNC   - alcance probado con watchdog, para que
                         el propio diagnostico no se cuelgue igual que la app.
      3. Proveedores cloud / sync roots (OneDrive, DMS, gestores documentales).
      4. Extensiones de shell de terceros, resueltas a DLL + firmante.
      5. Eventos Application Hang (1002) e informes WER de cuelgue.
      6. Filtros de sistema de ficheros (AV/EDR) cargados.
      7. Elementos recientes que apuntan a UNC (parseo binario del .lnk, sin
         resolverlo: resolverlo colgaria este script igual que a la app).

    Compatible PowerShell 5.1 y 7. No requiere admin (sin admin la lista de
    fltmc puede venir incompleta; se avisa).

.PARAMETER OutDir
    Carpeta de salida de los CSV. Por defecto %TEMP%\FilePickerDiag.

.PARAMETER DiasEventos
    Ventana de busqueda de eventos de cuelgue. Por defecto 14.

.PARAMETER TimeoutRutaSegundos
    Segundos que se espera a cada ruta de red antes de darla por colgada. 5.

.PARAMETER SinFirmas
    Omite la verificacion Authenticode de los DLL (mas rapido, menos util).

.EXAMPLE
    .\01-diagnose-file-picker.ps1
.EXAMPLE
    .\01-diagnose-file-picker.ps1 -DiasEventos 30 -OutDir C:\Temp\diag

.NOTES
    PowerShell 5.1 y 7.
    Permisos: ninguno especial (local). Solo lectura.
#>
[CmdletBinding()]
param(
    [string]$OutDir,
    [int]$DiasEventos = 14,
    [int]$TimeoutRutaSegundos = 5,
    [switch]$SinFirmas
)
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

# ---------------------------------------------------------------- utilidades
function Resolve-OutDir {
    param([string]$Propuesto)
    if ($Propuesto) {
        $d = $Propuesto
    } else {
        $d = Join-Path $env:TEMP 'FilePickerDiag'
    }
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    return $d
}

function Write-Seccion {
    param([string]$Titulo)
    $ancho = [Math]::Max(0, 66 - $Titulo.Length)
    Write-Host ''
    Write-Host ('== ' + $Titulo + ' ' + ('=' * $ancho)) -ForegroundColor Cyan
}

# Extrae cadenas legibles de un blob binario (PIDL de registro, cuerpo de .lnk).
function Get-CadenasLegibles {
    param([byte[]]$Bytes, [int]$MinLongitud = 4)
    if (-not $Bytes -or $Bytes.Length -lt ($MinLongitud * 2)) { return @() }
    $out = New-Object System.Collections.Generic.List[string]
    $uni = [System.Text.Encoding]::Unicode.GetString($Bytes)
    foreach ($m in [regex]::Matches($uni, "[\u0020-\u007E]{$MinLongitud,}")) { $out.Add($m.Value.Trim()) }
    $ansi = [System.Text.Encoding]::ASCII.GetString($Bytes)
    foreach ($m in [regex]::Matches($ansi, "[\x20-\x7E]{$MinLongitud,}")) { $out.Add($m.Value.Trim()) }
    return ($out | Sort-Object -Unique)
}

# Prueba una ruta con watchdog: una UNC muerta bloquea el hilo indefinidamente.
function Test-RutaConTimeout {
    param([string]$Ruta, [int]$Segundos = 5)
    $job = Start-Job -ScriptBlock {
        param($p)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $ok = $false
        try { $ok = Test-Path -LiteralPath $p -ErrorAction SilentlyContinue } catch { $ok = $false }
        [pscustomobject]@{ Existe = $ok; Ms = [int]$sw.ElapsedMilliseconds }
    } -ArgumentList $Ruta
    $fin = Wait-Job $job -Timeout $Segundos
    if (-not $fin) {
        Stop-Job   $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        return [pscustomobject]@{ Estado = 'COLGADA'; Ms = ($Segundos * 1000) }
    }
    $r = Receive-Job $job
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    $estado = 'NO EXISTE'
    if ($r.Existe) { $estado = 'OK' }
    if ($r.Existe -and $r.Ms -gt 1500) { $estado = 'LENTA' }
    return [pscustomobject]@{ Estado = $estado; Ms = $r.Ms }
}

$script:CacheFirma = @{}
function Get-FirmanteDll {
    param([string]$Path)
    if ($SinFirmas) { return 'n/d (-SinFirmas)' }
    if (-not $Path)  { return 'n/d' }
    if ($script:CacheFirma.ContainsKey($Path)) { return $script:CacheFirma[$Path] }
    $val = 'FICHERO NO ENCONTRADO'
    if (Test-Path -LiteralPath $Path) {
        try {
            $s = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
            if ($s.SignerCertificate) {
                $cn = ($s.SignerCertificate.Subject -split ',' | Where-Object { $_ -match '^\s*CN=' }) -replace '^\s*CN=', ''
                if (-not $cn) { $cn = $s.SignerCertificate.Subject }
                $val = (($cn -join '') + ' [' + $s.Status + ']')
            } else {
                $val = 'SIN FIRMA'
            }
        } catch { $val = 'ERROR AL VERIFICAR' }
    }
    $script:CacheFirma[$Path] = $val
    return $val
}

function Expand-RutaDll {
    param([string]$Raw)
    if (-not $Raw) { return $null }
    $p = ([string]$Raw).Trim('"')
    $p = [Environment]::ExpandEnvironmentVariables($p)
    if ($p -notmatch '[\\/]') { $p = Join-Path $env:SystemRoot ('System32\' + $p) }
    return $p
}

function Get-ClsidInfo {
    param([string]$Clsid)
    $res = [pscustomobject]@{ Clsid = $Clsid; Nombre = ''; Dll = ''; Firmante = '' }
    $raices = @(
        'Registry::HKEY_CLASSES_ROOT\CLSID',
        'Registry::HKEY_CLASSES_ROOT\WOW6432Node\CLSID',
        'Registry::HKEY_CURRENT_USER\Software\Classes\CLSID'
    )
    foreach ($raiz in $raices) {
        $k = Join-Path $raiz $Clsid
        if (-not (Test-Path -LiteralPath $k)) { continue }
        try { $res.Nombre = (Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue).'(default)' } catch { }
        foreach ($srv in @('InProcServer32', 'LocalServer32')) {
            $ks = Join-Path $k $srv
            if (-not (Test-Path -LiteralPath $ks)) { continue }
            $d = $null
            try { $d = (Get-ItemProperty -LiteralPath $ks -ErrorAction SilentlyContinue).'(default)' } catch { }
            if ($d) { $res.Dll = Expand-RutaDll $d; break }
        }
        if ($res.Dll) { break }
    }
    if ($res.Dll) { $res.Firmante = Get-FirmanteDll $res.Dll }
    return $res
}

function Test-EsMicrosoft {
    param([string]$Firmante, [string]$Dll)
    if ($Firmante -match 'Microsoft (Corporation|Windows)') { return $true }
    if ($Dll -and $Dll -match '(?i)^[A-Z]:\\Windows\\(System32|SysWOW64)\\') { return $true }
    return $false
}

# ------------------------------------------------------------------ arranque
$OutDir  = Resolve-OutDir $OutDir
$stamp   = Get-Date -Format 'yyyyMMdd-HHmm'
$prefijo = Join-Path $OutDir ('filepicker-' + $env:COMPUTERNAME + '-' + $stamp)
$idn     = [Security.Principal.WindowsIdentity]::GetCurrent()
$esAdmin = (New-Object Security.Principal.WindowsPrincipal($idn)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host ''
Write-Host '############################################################' -ForegroundColor White
Write-Host ('  Diagnostico File Picker - ' + $env:COMPUTERNAME + ' / ' + $env:USERNAME) -ForegroundColor White
Write-Host ('  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm') + '   admin=' + $esAdmin + '   PS ' + $PSVersionTable.PSVersion) -ForegroundColor White
Write-Host '############################################################' -ForegroundColor White

# ------------------------------------------------------- 0. entorno / version
Write-Seccion '0. Entorno'
$os  = Get-CimInstance Win32_OperatingSystem
$ubr = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name UBR -ErrorAction SilentlyContinue).UBR
Write-Host ('  SO             : ' + $os.Caption + '  build ' + $os.BuildNumber + '.' + $ubr)
Write-Host ('  Ultimo arranque: ' + $os.LastBootUpTime)
$od = @(Get-Process OneDrive -ErrorAction SilentlyContinue)
if ($od.Count) {
    Write-Host ('  OneDrive       : ' + $od.Count + ' proceso(s), version ' + $od[0].FileVersion)
} else {
    Write-Host '  OneDrive       : no esta en ejecucion'
}

# --------------------------------------------- 1. ComDlg32 MRU (SOSPECHOSO #1)
Write-Seccion '1. ComDlg32 MRU - carpeta inicial del picker por aplicacion'
$mru    = New-Object System.Collections.Generic.List[object]
$baseCd = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32'
foreach ($sub in @('LastVisitedPidlMRU','LastVisitedPidlMRULegacy','OpenSavePidlMRU','CIDSizeMRU','FirstFolder')) {
    $k = Join-Path $baseCd $sub
    if (-not (Test-Path $k)) { continue }
    $claves = @(Get-Item $k) + @(Get-ChildItem -Path $k -Recurse -ErrorAction SilentlyContinue)
    foreach ($key in $claves) {
        $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -match '^PS' -or $p.Name -eq 'MRUListEx') { continue }
            if ($p.Value -isnot [byte[]]) { continue }
            $cad    = Get-CadenasLegibles -Bytes $p.Value -MinLongitud 4
            $exe    = @($cad | Where-Object { $_ -match '(?i)\.exe$' })    | Select-Object -First 1
            $ruta   = @($cad | Where-Object { $_ -match '^\\\\' -or $_ -match '^[A-Za-z]:\\' }) | Select-Object -First 1
            $pistas = (@($cad | Where-Object { $_.Length -ge 5 -and $_ -notmatch '(?i)\.exe$' }) | Select-Object -First 6) -join ' | '
            $mru.Add([pscustomobject]@{
                Clave         = $sub + '\' + $key.PSChildName
                Valor         = $p.Name
                Aplicacion    = $exe
                RutaDetectada = $ruta
                Pistas        = $pistas
            })
        }
    }
}
$sosp = @()
if ($mru.Count) {
    $mru | Export-Csv ($prefijo + '-comdlg32-mru.csv') -NoTypeInformation -Encoding UTF8
    $sosp = @($mru | Where-Object { $_.RutaDetectada -match '^\\\\' -or $_.Pistas -match '(?i)(onedrive|sharepoint|imanage|netdocuments|worksite|documentum|dropbox|box sync|egnyte)' })
    Write-Host ('  Entradas MRU  : ' + $mru.Count)
    $color = 'Green'
    if ($sosp.Count) { $color = 'Yellow' }
    Write-Host ('  Con UNC o DMS : ' + $sosp.Count) -ForegroundColor $color
    # En un PIDL la ruta no viene en texto plano: lo legible son los nombres de
    # carpeta. Por eso se muestra tambien la columna de pistas.
    $mru | Where-Object { $_.Aplicacion } | Select-Object -First 25 `
            Aplicacion,
            @{ n = 'CarpetaRecordada'; e = { if ($_.RutaDetectada) { $_.RutaDetectada } else { $_.Pistas } } } |
        Format-Table -AutoSize -Wrap | Out-String -Width 220 | Write-Host
    if ($sosp.Count) {
        Write-Host '  Entradas hacia red / gestor documental / nube:' -ForegroundColor Yellow
        $sosp | Select-Object Aplicacion, RutaDetectada, Pistas |
            Format-Table -AutoSize -Wrap | Out-String -Width 220 | Write-Host
    }
} else {
    Write-Host '  Sin entradas MRU (o ya limpiadas).' -ForegroundColor Green
}

# ------------------------------------------ 2. red mapeada y rutas alcanzables
Write-Seccion '2. Unidades de red y rutas UNC (probadas con watchdog)'
$rutas = New-Object System.Collections.Generic.List[object]
foreach ($c in @(Get-CimInstance Win32_NetworkConnection -ErrorAction SilentlyContinue)) {
    $rutas.Add([pscustomobject]@{ Origen = ('Unidad ' + $c.LocalName); Ruta = $c.RemoteName })
}
if (Test-Path 'HKCU:\Network') {
    foreach ($k in @(Get-ChildItem 'HKCU:\Network' -ErrorAction SilentlyContinue)) {
        $rp = (Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue).RemotePath
        if ($rp -and -not @($rutas | Where-Object { $_.Ruta -eq $rp }).Count) {
            $rutas.Add([pscustomobject]@{ Origen = ('Mapeo persistente ' + $k.PSChildName + ':'); Ruta = $rp })
        }
    }
}
foreach ($m in $mru) {
    if ($m.RutaDetectada -match '^\\\\') {
        $partes = $m.RutaDetectada -split '\\'
        $raiz   = ($partes | Select-Object -First 4) -join '\'
        if (-not @($rutas | Where-Object { $_.Ruta -eq $raiz }).Count) {
            $rutas.Add([pscustomobject]@{ Origen = 'MRU del picker'; Ruta = $raiz })
        }
    }
}
$res = @()
if ($rutas.Count) {
    $res = foreach ($r in $rutas) {
        $t = Test-RutaConTimeout -Ruta $r.Ruta -Segundos $TimeoutRutaSegundos
        [pscustomobject]@{ Origen = $r.Origen; Ruta = $r.Ruta; Estado = $t.Estado; Ms = $t.Ms }
    }
    $res | Export-Csv ($prefijo + '-rutas-red.csv') -NoTypeInformation -Encoding UTF8
    $res | Format-Table -AutoSize | Out-String -Width 220 | Write-Host
    $malas = @($res | Where-Object { $_.Estado -eq 'COLGADA' -or $_.Estado -eq 'NO EXISTE' -or $_.Estado -eq 'LENTA' })
    if ($malas.Count) {
        Write-Host ('  >> ' + $malas.Count + ' ruta(s) problematicas: candidatas directas a la causa.') -ForegroundColor Red
    }
} else {
    Write-Host '  Sin unidades de red ni UNC en el MRU.' -ForegroundColor Green
}

# ------------------------------------------------ 3. proveedores cloud / sync
Write-Seccion '3. Proveedores cloud y raices de sincronizacion'
$sync = New-Object System.Collections.Generic.List[object]
$srm  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SyncRootManager'
if (Test-Path $srm) {
    foreach ($k in @(Get-ChildItem $srm -ErrorAction SilentlyContinue)) {
        $ui   = Get-ItemProperty (Join-Path $k.PSPath 'UserSyncRoots') -ErrorAction SilentlyContinue
        $ruta = $null
        if ($ui) {
            $prop = @($ui.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }) | Select-Object -First 1
            if ($prop) { $ruta = $prop.Value }
        }
        $sync.Add([pscustomobject]@{ Proveedor = $k.PSChildName; Ruta = $ruta })
    }
}
foreach ($ns in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace',
                  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace')) {
    if (-not (Test-Path $ns)) { continue }
    foreach ($k in @(Get-ChildItem $ns -ErrorAction SilentlyContinue)) {
        $i = Get-ClsidInfo $k.PSChildName
        $sync.Add([pscustomobject]@{ Proveedor = ('NameSpace: ' + $i.Nombre + ' ' + $i.Clsid); Ruta = $i.Dll })
    }
}
if ($sync.Count) {
    $sync | Export-Csv ($prefijo + '-cloud-sync.csv') -NoTypeInformation -Encoding UTF8
    $sync | Format-Table -AutoSize | Out-String -Width 220 | Write-Host
} else {
    Write-Host '  Ninguno.'
}

# -------------------------------------------- 4. extensiones de shell terceros
Write-Seccion '4. Extensiones de shell (resueltas a DLL y firmante)'
if (-not (Get-PSDrive HKCR -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT -Scope Script | Out-Null
}
$hooks = @(
    'HKCR:\*\shellex\ContextMenuHandlers',
    'HKCR:\*\shellex\PropertySheetHandlers',
    'HKCR:\AllFilesystemObjects\shellex\ContextMenuHandlers',
    'HKCR:\Directory\shellex\ContextMenuHandlers',
    'HKCR:\Directory\Background\shellex\ContextMenuHandlers',
    'HKCR:\Directory\shellex\DragDropHandlers',
    'HKCR:\Directory\shellex\CopyHookHandlers',
    'HKCR:\Folder\shellex\ContextMenuHandlers',
    'HKCR:\Drive\shellex\ContextMenuHandlers'
)
$ext = New-Object System.Collections.Generic.List[object]
foreach ($h in $hooks) {
    # -LiteralPath obligatorio: la clave se llama literalmente "*" y sin el
    # PowerShell la trata como comodin y recorre los miles de nodos de HKCR.
    if (-not (Test-Path -LiteralPath $h)) { continue }
    foreach ($k in @(Get-ChildItem -LiteralPath $h -ErrorAction SilentlyContinue)) {
        $clsid = (Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue).'(default)'
        if (-not $clsid) { $clsid = $k.PSChildName }
        if ($clsid -notmatch '^\{') { continue }
        $i = Get-ClsidInfo $clsid
        $ext.Add([pscustomobject]@{
            Tipo        = ($h -replace '^HKCR:\\', '')
            Entrada     = $k.PSChildName
            Clsid       = $clsid
            Nombre      = $i.Nombre
            Dll         = $i.Dll
            Firmante    = $i.Firmante
            EsMicrosoft = (Test-EsMicrosoft $i.Firmante $i.Dll)
        })
    }
}
$ovl = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers'
if (Test-Path -LiteralPath $ovl) {
    foreach ($k in @(Get-ChildItem -LiteralPath $ovl -ErrorAction SilentlyContinue)) {
        $clsid = (Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue).'(default)'
        if ($clsid -notmatch '^\{') { continue }
        $i = Get-ClsidInfo $clsid
        $ext.Add([pscustomobject]@{
            Tipo        = 'ShellIconOverlayIdentifiers'
            Entrada     = $k.PSChildName
            Clsid       = $clsid
            Nombre      = $i.Nombre
            Dll         = $i.Dll
            Firmante    = $i.Firmante
            EsMicrosoft = (Test-EsMicrosoft $i.Firmante $i.Dll)
        })
    }
}
$ph = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PropertySystem\PropertyHandlers'
if (Test-Path -LiteralPath $ph) {
    foreach ($k in @(Get-ChildItem -LiteralPath $ph -ErrorAction SilentlyContinue)) {
        $clsid = (Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue).'(default)'
        if ($clsid -notmatch '^\{') { continue }
        $i = Get-ClsidInfo $clsid
        if (Test-EsMicrosoft $i.Firmante $i.Dll) { continue }   # solo terceros: hay cientos de Microsoft
        $ext.Add([pscustomobject]@{
            Tipo        = 'PropertyHandler'
            Entrada     = $k.PSChildName
            Clsid       = $clsid
            Nombre      = $i.Nombre
            Dll         = $i.Dll
            Firmante    = $i.Firmante
            EsMicrosoft = $false
        })
    }
}
$ext | Export-Csv ($prefijo + '-shell-extensions.csv') -NoTypeInformation -Encoding UTF8
$terceros = @($ext | Where-Object { -not $_.EsMicrosoft } | Sort-Object Dll -Unique)
Write-Host ('  Total enganches : ' + $ext.Count + '   de terceros (DLL unico): ' + $terceros.Count)
if ($terceros.Count) {
    $terceros | Select-Object Tipo, Entrada, Clsid, Dll, Firmante |
        Format-Table -AutoSize | Out-String -Width 240 | Write-Host
}
$blk = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'
if (Test-Path $blk) {
    Write-Host ('  Ya bloqueadas   : ' + (@((Get-Item $blk).Property) -join ', '))
} else {
    Write-Host '  Ya bloqueadas   : ninguna (la clave Blocked no existe)'
}

# ------------------------------------------------------------- 5. cuelgues WER
Write-Seccion ('5. Eventos de cuelgue (ultimos ' + $DiasEventos + ' dias)')
$desde = (Get-Date).AddDays(-$DiasEventos)
$ev = @()
try {
    $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = @(1000,1001,1002); StartTime = $desde } -ErrorAction Stop)
} catch { }
$hang = @($ev | Where-Object { $_.Id -eq 1002 })
$err  = @($ev | Where-Object { $_.Id -eq 1000 })
Write-Host ('  Application Hang  (1002): ' + $hang.Count + '   <- lo relevante para un freeze')
Write-Host ('  Application Error (1000): ' + $err.Count  + '   <- solo si ademas cierra')
$resumen = foreach ($e in ($ev | Select-Object -First 40)) {
    $p    = @($e.Properties | ForEach-Object { $_.Value })
    $tipo = 'Error'
    if ($e.Id -eq 1001) { $tipo = 'WER' }
    if ($e.Id -eq 1002) { $tipo = 'Hang' }
    $info = ''
    if ($e.Id -eq 1000 -and $p.Count -ge 4) { $info = $p[3] }
    else { $info = (@($p | Select-Object -Skip 1 -First 3) -join ' ') }
    [pscustomobject]@{
        Fecha       = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm')
        Id          = $e.Id
        Tipo        = $tipo
        App         = $p[0]
        ModuloOInfo = $info
    }
}
if ($resumen) {
    $resumen | Export-Csv ($prefijo + '-eventos.csv') -NoTypeInformation -Encoding UTF8
    # En pantalla solo cuelgues y errores de aplicacion: los 1001 son cubos de
    # WER (pantallazos, LiveKernelEvent) y solo aportan ruido aqui.
    $vista = @($resumen | Where-Object { $_.Id -eq 1002 -or $_.Id -eq 1000 })
    if ($vista.Count) {
        $vista | Select-Object -First 15 | Format-Table -AutoSize | Out-String -Width 240 | Write-Host
    } else {
        Write-Host '  Sin eventos 1000/1002 en la ventana (los 1001 quedan en el CSV).'
    }
}
$wer     = Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive'
$werHang = @()
if (Test-Path $wer) {
    $werHang = @(Get-ChildItem $wer -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'AppHang' -and $_.LastWriteTime -ge $desde })
}
Write-Host ('  Informes WER AppHang en ReportArchive: ' + $werHang.Count)
foreach ($w in ($werHang | Select-Object -First 5)) {
    $rep = Join-Path $w.FullName 'Report.wer'
    if (-not (Test-Path $rep)) { continue }
    Write-Host ('   - ' + $w.Name) -ForegroundColor DarkGray
    $sig = Select-String -Path $rep -Pattern '^(AppName|AppPath|HangType|Sig\[\d+\]\.Value)=' -ErrorAction SilentlyContinue
    $sig | Select-Object -First 8 | ForEach-Object { Write-Host ('     ' + $_.Line) -ForegroundColor DarkGray }
}
$cd = Join-Path $env:LOCALAPPDATA 'CrashDumps'
if (Test-Path $cd) {
    $dumps = @(Get-ChildItem $cd -Filter *.dmp -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $desde })
    Write-Host ('  Volcados en %LOCALAPPDATA%\CrashDumps: ' + $dumps.Count)
}

# ------------------------------------------------- 6. filtros de FS (AV / EDR)
Write-Seccion '6. Filtros de sistema de ficheros (AV / EDR / sync)'
try {
    $f = & fltmc.exe filters 2>&1
    @($f) | Select-Object -First 25 | ForEach-Object { Write-Host ('  ' + $_) }
    if (-not $esAdmin) { Write-Host '  (sin admin la lista puede venir incompleta)' -ForegroundColor Yellow }
} catch {
    Write-Host '  fltmc no disponible.' -ForegroundColor Yellow
}

# ------------------------------------------------ 7. recientes que apuntan UNC
Write-Seccion '7. Elementos recientes que apuntan a red (parseo binario, sin resolver)'
$rec  = Join-Path $env:APPDATA 'Microsoft\Windows\Recent'
$lnks = @()
if (Test-Path $rec) { $lnks = @(Get-ChildItem $rec -Filter *.lnk -ErrorAction SilentlyContinue) }
$conUnc = New-Object System.Collections.Generic.List[object]
foreach ($l in $lnks) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($l.FullName)
        $cad   = Get-CadenasLegibles -Bytes $bytes -MinLongitud 6
        $u     = @($cad | Where-Object { $_ -match '^\\\\[A-Za-z0-9._-]+\\' }) | Select-Object -First 1
        if ($u) { $conUnc.Add([pscustomobject]@{ Acceso = $l.Name; Destino = $u; Fecha = $l.LastWriteTime }) }
    } catch { }
}
Write-Host ('  .lnk recientes: ' + $lnks.Count + '   de ellos hacia UNC: ' + $conUnc.Count)
if ($conUnc.Count) {
    $conUnc | Export-Csv ($prefijo + '-recientes-unc.csv') -NoTypeInformation -Encoding UTF8
    $conUnc | Group-Object { (($_.Destino -split '\\') | Select-Object -First 4) -join '\' } |
        Select-Object @{ n = 'Servidor'; e = { $_.Name } }, Count |
        Format-Table -AutoSize | Out-String -Width 220 | Write-Host
}

# ---------------------------------------------------------------- conclusiones
Write-Seccion 'Resumen - por donde empezar'
$n = 0
$rutasMalas = @($res | Where-Object { $_.Estado -eq 'COLGADA' -or $_.Estado -eq 'NO EXISTE' })
if ($rutasMalas.Count) {
    $n++
    Write-Host ('  ' + $n + '. Hay rutas de red muertas o colgadas. Corregir/desmapear y limpiar el MRU con') -ForegroundColor Red
    Write-Host '     03-reset-file-picker-mru.ps1. Es la causa mas probable de un freeze del selector.' -ForegroundColor Red
}
if ($conUnc.Count -gt 0) {
    $n++
    Write-Host ('  ' + $n + '. ' + $conUnc.Count + ' accesos recientes apuntan a UNC: el picker los enumera al abrirse.') -ForegroundColor Yellow
}
if ($terceros.Count -gt 0) {
    $n++
    Write-Host ('  ' + $n + '. ' + $terceros.Count + ' extensiones de shell de terceros registradas.') -ForegroundColor Yellow
    Write-Host '     Confirmar cual con 02-test-file-picker-hang.ps1 (delta de modulos) antes de bloquear nada.' -ForegroundColor Yellow
}
if ($hang.Count -gt 0) {
    $n++
    Write-Host ('  ' + $n + '. Hay eventos Application Hang: revisar el CSV de eventos.') -ForegroundColor Yellow
}
if ($n -eq 0) {
    Write-Host '  Nada anomalo en el inventario. Pasar directo a 02-test-file-picker-hang.ps1.' -ForegroundColor Green
}
Write-Host ''
Write-Host ('  CSV en: ' + $OutDir) -ForegroundColor Cyan
Write-Host ''
