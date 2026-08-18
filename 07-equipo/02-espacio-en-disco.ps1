<#
.SYNOPSIS
    [ES] Que esta ocupando el disco: carpetas mas grandes y basura que se puede recuperar.
    [EN] What is filling the disk: largest folders and reclaimable junk.
.DESCRIPTION
    Solo lectura. Mide el primer nivel de la ruta indicada y lista las carpetas por
    tamano, mas un resumen de rutas tipicas de basura (temporales, cache de Windows
    Update, Papelera, volcados, cache de Teams).
    Usa [IO.Directory]::EnumerateFiles en vez de Get-ChildItem -Recurse: mismo dato,
    varias veces mas rapido y sin construir objetos que no se usan.
.PARAMETER Ruta
    Carpeta a analizar. Por defecto la unidad de sistema.
.PARAMETER Top
    Cuantas carpetas listar. Por defecto 15.
.PARAMETER SoloBasura
    Omite el analisis por carpetas y muestra solo la basura recuperable.
.EXAMPLE
    .\02-espacio-disco.ps1
.EXAMPLE
    .\02-espacio-disco.ps1 -Ruta C:\Users -Top 10
.NOTES
    PowerShell 5.1 y 7. No borra nada. Sin admin ve menos: lo omitido se cuenta aparte.
#>
[CmdletBinding()]
param(
    [string]$Ruta = "$env:SystemDrive\",
    [int]$Top = 15,
    [switch]$SoloBasura
)

$ErrorActionPreference = 'Continue'

function Get-TamanoCarpeta {
    param([string]$P)
    $bytes = [long]0
    $errores = 0
    try {
        $en = [IO.Directory]::EnumerateFiles($P, '*', [IO.SearchOption]::AllDirectories)
        foreach ($f in $en) {
            try { $bytes += (New-Object IO.FileInfo $f).Length } catch { $errores++ }
        }
    } catch { $errores++ }
    [pscustomobject]@{ Bytes = $bytes; Errores = $errores }
}

function Format-Tam {
    param([long]$B)
    if ($B -ge 1GB) { '{0,8:N1} GB' -f ($B / 1GB) }
    elseif ($B -ge 1MB) { '{0,8:N1} MB' -f ($B / 1MB) }
    else { '{0,8:N0} KB' -f ($B / 1KB) }
}

$d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($Ruta.Substring(0,2))'" -ErrorAction SilentlyContinue
Write-Host ''
if ($d) {
    Write-Host ("=== {0}  {1:N1} GB libres de {2:N1} GB  ({3:N0}% ocupado) ===" -f `
        $d.DeviceID, ($d.FreeSpace / 1GB), ($d.Size / 1GB), (100 - 100 * $d.FreeSpace / $d.Size)) -ForegroundColor Cyan
}

if (-not $SoloBasura) {
    Write-Host ''
    Write-Host ("--- Carpetas mas grandes en {0} ---" -f $Ruta) -ForegroundColor Cyan
    $dirs = @()
    try { $dirs = [IO.Directory]::GetDirectories($Ruta) } catch { Write-Host ("  no se puede leer {0}" -f $Ruta) -ForegroundColor Red }
    $res = foreach ($x in $dirs) {
        Write-Progress -Activity 'Midiendo' -Status $x
        $t = Get-TamanoCarpeta $x
        [pscustomobject]@{ Carpeta = $x; Bytes = $t.Bytes; Sin_acceso = $t.Errores }
    }
    Write-Progress -Activity 'Midiendo' -Completed
    foreach ($r in ($res | Sort-Object Bytes -Descending | Select-Object -First $Top)) {
        $aviso = if ($r.Sin_acceso) { "  ({0} sin acceso)" -f $r.Sin_acceso } else { '' }
        Write-Host ("  {0}  {1}{2}" -f (Format-Tam $r.Bytes), $r.Carpeta, $aviso)
    }
}

Write-Host ''
Write-Host '--- Basura recuperable ---' -ForegroundColor Cyan
$basura = [ordered]@{
    'Temp del usuario'          = $env:TEMP
    'Temp de Windows'           = "$env:SystemRoot\Temp"
    'Cache Windows Update'      = "$env:SystemRoot\SoftwareDistribution\Download"
    'Windows.old'               = "$env:SystemDrive\Windows.old"
    'Volcados de memoria'       = "$env:SystemRoot\Minidump"
    'Cache Teams (nuevo)'       = "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache"
    'Cache Edge'                = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
    'Descargas del usuario'     = "$env:USERPROFILE\Downloads"
    'Papelera'                  = "$env:SystemDrive\`$Recycle.Bin"
}
$total = [long]0
foreach ($k in $basura.Keys) {
    if (-not (Test-Path $basura[$k])) { continue }
    $t = (Get-TamanoCarpeta $basura[$k]).Bytes
    if ($t -eq 0) { continue }
    $total += $t
    Write-Host ("  {0}  {1,-24} {2}" -f (Format-Tam $t), $k, $basura[$k])
}
Write-Host ("  {0}  TOTAL recuperable aproximado" -f (Format-Tam $total)) -ForegroundColor Yellow
Write-Host ''
Write-Host '  Limpieza: comandos de 00-copy-paste/README.md, seccion 2.' -ForegroundColor DarkGray
Write-Host ''
