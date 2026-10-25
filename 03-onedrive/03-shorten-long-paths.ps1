#Requires -Version 5.1

<#
.SYNOPSIS
    [ES] Acorta las rutas de OneDrive/SharePoint de mas de 400 caracteres ("la ruta es demasiado larga"). Solo consola, automatico.
    [EN] Shortens OneDrive/SharePoint paths over 400 characters ("the path is too long"). Console only, automatic.
.DESCRIPTION
    Lanzador del motor de PathShrink (github.com/4leX-42/PathShrink), sin ventana ni instalacion:
    descarga la release a %TEMP%, comprueba su SHA-256, carga el modulo, ejecuta y borra lo descargado.
    Si no hay red y PathShrink ya esta instalado, usa esa copia.

    Respecto a la version anterior de este script, el motor nuevo:
      - detecta solo las cuentas y bibliotecas de OneDrive y SharePoint sincronizadas;
      - calcula el prefijo real del servidor, no una estimacion;
      - avisa de problemas de sincronizacion (nombres reservados, caracteres no validos);
      - renombra de lo mas profundo a lo superficial, apunta cada cambio en undo.csv al momento
        y verifica en disco al terminar;
      - deshace solo lo que sigue donde se dejo y nunca pisa nada (-Revertir).

    Flujo: analiza, muestra el plan, pide confirmacion, renombra y verifica. -DryRun solo muestra
    el plan; -SinConfirmar aplica sin preguntar (desatendido).
    Informes y undo.csv en %LOCALAPPDATA%\PathShrink\Reports\<fecha>\.
.PARAMETER Ruta
    Carpeta a revisar. Por defecto el OneDrive de empresa del usuario, detectado solo.
.PARAMETER Upn
    Correo de la cuenta. Por defecto se lee de la configuracion de OneDrive.
.PARAMETER Raiz
    Carpeta analizada a mano, sin leer el registro (copia de otro equipo). Exige -Prefijo o -Upn.
.PARAMETER Prefijo
    Prefijo de servidor de esa carpeta, por ejemplo "sites/Legal/Shared Documents/". Con -Raiz.
.PARAMETER Limite
    Longitud maxima en el servidor. Por defecto 400.
.PARAMETER Margen
    Margen por debajo del limite. Por defecto 20: se trata toda ruta que pase de 380.
.PARAMETER PermitirRecorte
    Permite recortar letras de los nombres (nunca por debajo de -MinNombre). Por defecto no.
.PARAMETER MinNombre
    Longitud minima de un nombre recortado. Por defecto 20.
.PARAMETER Excluir
    Patrones de carpetas o ficheros que no se analizan.
.PARAMETER Proteger
    Patrones que se analizan pero nunca se renombran.
.PARAMETER DryRun
    Solo muestra el plan y genera los informes. No renombra nada ni pregunta.
.PARAMETER SinConfirmar
    Aplica sin pedir confirmacion.
.PARAMETER Revertir
    undo.csv de una ejecucion anterior: restaura los nombres originales.
.PARAMETER Version
    Release de PathShrink a usar, por ejemplo v1.0.1. Por defecto la ultima.
.PARAMETER Ascii
    Aceptado por compatibilidad con la version anterior; no hace nada.
.EXAMPLE
    .\03-shorten-long-paths.ps1 -DryRun
    Analiza el OneDrive del usuario y muestra el plan sin cambiar nada.
.EXAMPLE
    .\03-shorten-long-paths.ps1
    Analiza, muestra el plan, pide confirmacion y aplica.
.EXAMPLE
    .\03-shorten-long-paths.ps1 -Ruta "$env:OneDriveCommercial\Desktop\CLIENTES" -SinConfirmar
.EXAMPLE
    .\03-shorten-long-paths.ps1 -Revertir "$env:LOCALAPPDATA\PathShrink\Reports\20261024-101500-000\undo.csv"
.NOTES
    Contexto: usuario
    EJECUTAR COMO: cuenta del usuario, SIN elevar. La cuenta y la carpeta de OneDrive
    salen de su perfil; elevando con otra cuenta se analizaria otro OneDrive.
    PowerShell 5.1 (el de Windows) y 7. Descarga ~1 MB de GitHub; el hash se verifica.
    Avisar al usuario: los accesos directos y enlaces a las carpetas renombradas dejan
    de funcionar, igual que si se renombraran a mano.
    Los cambios.csv de la version anterior (en %TEMP%\OneDriveRutasLargas) no se pueden
    revertir con este script; los nuevos undo.csv si.
#>
[CmdletBinding()]
param(
    [string]$Ruta,
    [string]$Upn,
    [string]$Raiz,
    [string]$Prefijo,
    [ValidateRange(50, 400)][int]$Limite = 400,
    [ValidateRange(0, 200)][int]$Margen = 20,
    [switch]$PermitirRecorte,
    [ValidateRange(3, 200)][int]$MinNombre = 20,
    [string[]]$Excluir = @(),
    [string[]]$Proteger = @(),
    [switch]$DryRun,
    [switch]$SinConfirmar,
    [string]$Revertir,
    [string]$Version = 'latest',
    [switch]$Ascii
)

$ErrorActionPreference = 'Stop'
$repo = 'https://github.com/4leX-42/PathShrink'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('PathShrink-' + [guid]::NewGuid().ToString('N'))
$psd1 = $null
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
    $base = if ($Version -eq 'latest') { "$repo/releases/latest/download" } else { "$repo/releases/download/$Version" }
    try {
        New-Item -ItemType Directory -Path $tmp | Out-Null
        $zip = Join-Path $tmp 'PathShrink.zip'
        Invoke-WebRequest -Uri "$base/PathShrink.zip" -OutFile $zip -UseBasicParsing
        Invoke-WebRequest -Uri "$base/PathShrink.zip.sha256" -OutFile "$zip.sha256" -UseBasicParsing
        $esperado = ((Get-Content -LiteralPath "$zip.sha256" -Raw).Trim() -split '\s+')[0]
        $real = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
        if ($real -ne $esperado) { throw "SHA-256 distinto (esperado $esperado, obtenido $real). No se ejecuta nada." }
        Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $tmp 'app') -Force
        $psd1 = Join-Path $tmp 'app\PathShrink\PathShrink.psd1'
    } catch {
        if ($_.Exception.Message -like 'SHA-256*') { throw }
        $local = Join-Path $env:LOCALAPPDATA 'Programs\PathShrink\PathShrink\PathShrink.psd1'
        if (-not (Test-Path -LiteralPath $local)) { throw "No se pudo descargar PathShrink ($($_.Exception.Message)) y no hay copia instalada." }
        Write-Host 'Sin descarga: se usa la copia instalada de PathShrink.' -ForegroundColor Yellow
        $psd1 = $local
    }
    Get-ChildItem -LiteralPath (Split-Path $psd1 -Parent) -Recurse -File | Unblock-File
    Import-Module $psd1 -Force

    if ($Revertir) {
        $cab = (Get-Content -LiteralPath $Revertir -TotalCount 1)
        if ($cab -notmatch 'OriginalPath' -or $cab -notmatch 'OriginalName') { throw "$Revertir no es un undo.csv de PathShrink (los cambios.csv de la version anterior no se pueden revertir aqui)." }
        $c = @{ WhatIf = [bool]$DryRun }
        if ($SinConfirmar) { $c.Confirm = $false }
        $r = Undo-PathShrink -UndoFile $Revertir @c
        if ($r) { Write-Host ('Restaurados: {0} | Omitidos: {1} | Ya estaban: {2} | Errores: {3}' -f $r.Restored, $r.Skipped, $r.AlreadyRestored, $r.Failed) -ForegroundColor Green }
        return
    }

    $a = @{ Limit = $Limite; Margin = $Margen; AllowTrim = $PermitirRecorte; MinNameLength = $MinNombre; Exclude = $Excluir; Protect = $Proteger }
    foreach ($par in @(@('Ruta', 'Path'), @('Upn', 'Upn'), @('Raiz', 'Root'), @('Prefijo', 'Prefix'))) {
        if ($PSBoundParameters.ContainsKey($par[0])) { $a[$par[1]] = $PSBoundParameters[$par[0]] }
    }
    if ($DryRun) { $a.WhatIf = $true }
    if ($SinConfirmar) { $a.Confirm = $false }
    Invoke-PathShrink @a
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
