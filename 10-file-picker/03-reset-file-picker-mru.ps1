<#
.SYNOPSIS
    [ES] Limpia la memoria de carpetas del selector de archivos (ComDlg32 MRU). DryRun por defecto.
    [EN] Clears the file picker's remembered folders (ComDlg32 MRU). DryRun by default.

.DESCRIPTION
    El selector de archivos de Windows recuerda la ULTIMA CARPETA VISITADA por
    cada aplicacion en:

        HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32
            LastVisitedPidlMRU        <- carpeta inicial por ejecutable
            LastVisitedPidlMRULegacy
            OpenSavePidlMRU           <- ultimas carpetas por tipo de fichero
            CIDSizeMRU
            FirstFolder

    Si esa carpeta ya no es alcanzable (recurso UNC caido, DMS desconectado,
    OneDrive desincronizado, unidad mapeada muerta), el dialogo se cuelga al
    intentar enumerarla ANTES de dibujarse. Arrastrar y soltar no pasa por ahi,
    y por eso sigue funcionando: es la firma tipica de este fallo.

    Borrar estas claves es seguro y reversible: Windows las recrea vacias y el
    picker vuelve a abrirse en Documentos. Lo unico que se pierde es la lista de
    carpetas recientes del dialogo.

    Sin -Execute no toca nada: solo ensena lo que hay y lo que borraria.
    Con -Execute exporta primero una copia .reg de todo lo que va a borrar.

.PARAMETER Execute
    Aplica los cambios. Sin este parametro es dry-run.

.PARAMETER IncluirRecientes
    Ademas vacia los accesos recientes del Explorador:
      %APPDATA%\Microsoft\Windows\Recent\*.lnk
      ...\Recent\AutomaticDestinations\*  y  ...\CustomDestinations\*
    (Quick Access / listas de salto). Tambien reversible: se recrean solos.

.PARAMETER ReiniciarExplorer
    Reinicia explorer.exe al terminar para que el cambio surta efecto sin
    cerrar sesion. Cierra las ventanas del Explorador abiertas.

.PARAMETER Restore
    Ruta a un .reg generado por una ejecucion anterior de este script; lo
    reimporta y deja el MRU como estaba. Excluyente con el resto.

.PARAMETER BackupDir
    Donde dejar la copia .reg. Por defecto %TEMP%\FilePickerDiag.

.EXAMPLE
    .\03-reset-file-picker-mru.ps1
.EXAMPLE
    .\03-reset-file-picker-mru.ps1 -Execute -IncluirRecientes -ReiniciarExplorer
.EXAMPLE
    .\03-reset-file-picker-mru.ps1 -Restore C:\...\comdlg32-backup-20260916-1120.reg

.NOTES
    PowerShell 5.1 y 7.
    Ambito: solo HKCU del usuario que lo ejecuta. No requiere admin.
    Reversible: si (copia .reg automatica + -Restore).
#>
[CmdletBinding()]
param(
    [switch]$Execute,
    [switch]$IncluirRecientes,
    [switch]$ReiniciarExplorer,
    [string]$Restore,
    [string]$BackupDir
)
$ErrorActionPreference = 'Stop'

function Resolve-BackupDir {
    param([string]$Propuesto)
    if ($Propuesto) {
        $d = $Propuesto
    } else {
        $d = Join-Path $env:TEMP 'FilePickerDiag'
    }
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    return $d
}

$BackupDir = Resolve-BackupDir $BackupDir
$claveReg  = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32'
$clavePS   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32'
$subclaves = @('LastVisitedPidlMRU','LastVisitedPidlMRULegacy','OpenSavePidlMRU','CIDSizeMRU','FirstFolder')

# ---------------------------------------------------------------- restaurar
if ($Restore) {
    if (-not (Test-Path -LiteralPath $Restore)) { throw ('No existe el fichero: ' + $Restore) }
    Write-Host ''
    Write-Host ('== RESTAURAR MRU desde ' + $Restore) -ForegroundColor Cyan
    & reg.exe import $Restore
    if ($LASTEXITCODE -eq 0) { Write-Host '  Importado correctamente.' -ForegroundColor Green }
    else { Write-Host ('  reg.exe devolvio ' + $LASTEXITCODE) -ForegroundColor Red }
    return
}

# ------------------------------------------------------------ estado actual
Write-Host ''
Write-Host '############################################################' -ForegroundColor White
Write-Host '  Limpieza del MRU del File Picker (ComDlg32)' -ForegroundColor White
Write-Host ('  ' + $env:COMPUTERNAME + ' / ' + $env:USERNAME) -ForegroundColor White
Write-Host '############################################################' -ForegroundColor White

$existentes = @()
foreach ($s in $subclaves) {
    $p = Join-Path $clavePS $s
    if (Test-Path $p) {
        $n = @(Get-ChildItem $p -Recurse -ErrorAction SilentlyContinue).Count
        $v = @((Get-Item $p).Property | Where-Object { $_ -ne 'MRUListEx' }).Count
        $existentes += [pscustomobject]@{ Subclave = $s; Subclaves = $n; Valores = $v }
    }
}
if ($existentes.Count) {
    $existentes | Format-Table -AutoSize | Out-String -Width 120 | Write-Host
} else {
    Write-Host '  No hay ninguna subclave de MRU. Nada que limpiar aqui.' -ForegroundColor Green
}

$recentDir = Join-Path $env:APPDATA 'Microsoft\Windows\Recent'
$nLnk = 0; $nAuto = 0; $nCust = 0
if (Test-Path $recentDir) {
    $nLnk  = @(Get-ChildItem $recentDir -Filter *.lnk -ErrorAction SilentlyContinue).Count
    $nAuto = @(Get-ChildItem (Join-Path $recentDir 'AutomaticDestinations') -ErrorAction SilentlyContinue).Count
    $nCust = @(Get-ChildItem (Join-Path $recentDir 'CustomDestinations')   -ErrorAction SilentlyContinue).Count
}

$modo = 'DRY-RUN'
if ($Execute) { $modo = 'EXECUTE' }
Write-Host ''
Write-Host ('== PLAN (' + $modo + ') ==') -ForegroundColor Cyan
Write-Host ('  Borrar subclaves MRU    : ' + $existentes.Count + ' bajo ' + $claveReg)
if ($IncluirRecientes) {
    Write-Host ('  Vaciar recientes        : ' + $nLnk + ' .lnk, ' + $nAuto + ' AutomaticDestinations, ' + $nCust + ' CustomDestinations')
} else {
    Write-Host ('  Vaciar recientes        : NO (hay ' + $nLnk + ' .lnk; anadir -IncluirRecientes)')
}
Write-Host ('  Reiniciar explorer.exe  : ' + [bool]$ReiniciarExplorer)
Write-Host  '  Alcance                 : solo HKCU del usuario actual'
Write-Host  '  Riesgo                  : se pierde la lista de carpetas recientes del dialogo'
Write-Host  '  Reversible              : si, copia .reg automatica antes de borrar'

if (-not $Execute) {
    Write-Host ''
    Write-Host '  DRY-RUN: no se ha cambiado nada. Anadir -Execute para aplicar.' -ForegroundColor Yellow
    Write-Host ''
    return
}

# --------------------------------------------------------------- ejecucion
$stamp  = Get-Date -Format 'yyyyMMdd-HHmm'
$backup = Join-Path $BackupDir ('comdlg32-backup-' + $env:USERNAME + '-' + $stamp + '.reg')
$logDir = $BackupDir
$trans  = $null
if (Test-Path $logDir) {
    $trans = Join-Path $logDir ($stamp + '-reset-filepicker-mru.log')
    Start-Transcript -Path $trans -Force | Out-Null
}
try {
    Write-Host ''
    if (Test-Path $clavePS) {
        & reg.exe export $claveReg $backup /y | Out-Null
        if (Test-Path $backup) { Write-Host ('  Copia de seguridad: ' + $backup) -ForegroundColor Green }
        else { throw 'No se pudo generar la copia .reg; se aborta sin borrar nada.' }
    }

    foreach ($s in $subclaves) {
        $p = Join-Path $clavePS $s
        if (-not (Test-Path $p)) { continue }
        Remove-Item -Path $p -Recurse -Force
        Write-Host ('  Borrada: ' + $s) -ForegroundColor Green
    }

    if ($IncluirRecientes -and (Test-Path $recentDir)) {
        Get-ChildItem $recentDir -Filter *.lnk -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        foreach ($sub in @('AutomaticDestinations','CustomDestinations')) {
            $d = Join-Path $recentDir $sub
            if (Test-Path $d) { Get-ChildItem $d -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue }
        }
        Write-Host '  Recientes y listas de salto vaciados.' -ForegroundColor Green
    }

    if ($ReiniciarExplorer) {
        Write-Host '  Reiniciando explorer.exe ...'
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        if (-not @(Get-Process explorer -ErrorAction SilentlyContinue).Count) { Start-Process explorer.exe }
    }

    # verificacion
    $quedan = @($subclaves | Where-Object { Test-Path (Join-Path $clavePS $_) })
    Write-Host ''
    if ($quedan.Count) {
        Write-Host ('  AVISO: siguen existiendo ' + ($quedan -join ', ')) -ForegroundColor Yellow
    } else {
        Write-Host '  Verificado: ninguna subclave de MRU queda en el registro.' -ForegroundColor Green
    }
    Write-Host ''
    Write-Host '  Probar ahora: 02-test-file-picker-hang.ps1   (o abrir Adjuntar en Outlook).' -ForegroundColor Cyan
    Write-Host ('  Deshacer    : .\03-reset-file-picker-mru.ps1 -Restore "' + $backup + '"') -ForegroundColor Cyan
    Write-Host ''
} finally {
    if ($trans) { Stop-Transcript | Out-Null }
}
