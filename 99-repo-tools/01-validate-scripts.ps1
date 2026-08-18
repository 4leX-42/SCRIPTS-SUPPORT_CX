<#
.SYNOPSIS
    [ES] Valida todos los .ps1 del repo: solo ASCII, UTF-8 con BOM y sintaxis en 5.1 y 7.
    [EN] Validates every .ps1 in the repo: ASCII only, UTF-8 with BOM and syntax on 5.1 and 7.
.DESCRIPTION
    Windows PowerShell 5.1 lee los .ps1 sin BOM como CP1252, no como UTF-8. Un guion
    largo (U+2014) se decodifica entonces como una comilla tipografica de cierre y
    rompe el fichero entero con errores en cascada. De ahi las dos reglas: ASCII puro
    y BOM siempre. Correr antes de cada commit.
.PARAMETER Corregir
    Reescribe con BOM los ficheros que no lo tengan. No toca caracteres no ASCII:
    eso se arregla a mano, redactando sin acentos.
.EXAMPLE
    .\Test-Toolkit.ps1
.NOTES
    PowerShell 5.1 y 7.
#>
[CmdletBinding()]
param([switch]$Corregir)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path $PSScriptRoot -Parent
$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source

$fallos = 0
Write-Host ''
Write-Host ("=== Validando {0} ===" -f $raiz) -ForegroundColor Cyan

foreach ($f in (Get-ChildItem $raiz -Filter *.ps1 -Recurse -File | Sort-Object FullName)) {
    $rel = $f.FullName.Substring($raiz.Length + 1)
    $problemas = New-Object System.Collections.ArrayList

    $bytes = [IO.File]::ReadAllBytes($f.FullName)
    $texto = [IO.File]::ReadAllText($f.FullName)

    $noAscii = [regex]::Matches($texto, '[^\x00-\x7F]')
    if ($noAscii.Count) {
        $ej = ($noAscii | ForEach-Object { $_.Value } | Sort-Object -Unique) -join ' '
        [void]$problemas.Add("$($noAscii.Count) caracteres no ASCII: $ej")
    }

    $tieneBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    if (-not $tieneBom) {
        if ($Corregir) {
            [IO.File]::WriteAllText($f.FullName, $texto, (New-Object Text.UTF8Encoding $true))
            Write-Host ("  [FIX ] {0}  BOM anadido" -f $rel) -ForegroundColor Yellow
        } else {
            [void]$problemas.Add('sin BOM UTF-8')
        }
    }

    $cmd = '$e=$null;$t=$null;[void][Management.Automation.Language.Parser]::ParseFile("' + $f.FullName + '",[ref]$t,[ref]$e); if($e){ $e | ForEach-Object { "L$($_.Extent.StartLineNumber): $($_.Message)" } }'
    foreach ($motor in @(@{ N = '5.1'; X = $ps51 }, @{ N = '7'; X = $pwsh })) {
        if (-not $motor.X -or -not (Test-Path $motor.X)) { continue }
        $salida = & $motor.X -NoProfile -Command $cmd 2>&1
        if ($salida) { [void]$problemas.Add(("sintaxis PS {0}: {1}" -f $motor.N, ($salida -join ' | '))) }
    }

    if ($problemas.Count) {
        $fallos++
        Write-Host ("  [FALLO] {0}" -f $rel) -ForegroundColor Red
        foreach ($p in $problemas) { Write-Host ("          {0}" -f $p) -ForegroundColor Red }
    } else {
        Write-Host ("  [ OK  ] {0}" -f $rel) -ForegroundColor Green
    }
}

Write-Host ''
if ($fallos) { Write-Host ("  {0} fichero/s con problemas." -f $fallos) -ForegroundColor Red; exit 1 }
Write-Host '  Todo correcto.' -ForegroundColor Green
Write-Host ''
