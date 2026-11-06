#Requires -Version 5.1

<#
.SYNOPSIS
    [ES] Detecta y acorta las rutas demasiado largas de OneDrive/SharePoint: limite del servidor (400), del PC (259) y accesos directos. Solo consola.
    [EN] Finds and shortens OneDrive/SharePoint paths that are too long: server limit (400), PC limit (259) and shortcuts. Console only.
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

    Accesos directos a otras bibliotecas: el analisis de la carpeta de arriba no los toca. Los mide y
    da el comando para analizar cada uno. Dentro de uno, los cambios los ve todo el que tenga acceso:
    antes de renombrar, valorar acortar el nombre del acceso directo o dejar de sincronizarlo.

    Si OneDrive avisa de "acorta la ruta N caracteres" y aqui nada pasa de 400: -LimiteLocal con la
    longitud de esa ruta menos N.
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
    Longitud maxima en el servidor. Por defecto 400. No cuenta la carpeta local de OneDrive ni el
    nombre del acceso directo: una ruta puede caber aqui y fallar en el PC.
.PARAMETER Margen
    Margen por debajo del limite. Por defecto 20: se trata toda ruta que pase de 380.
    Con -LimiteLocal, por defecto 0.
.PARAMETER LimiteLocal
    Longitud maxima de la ruta en el PC, por ejemplo 259 (el limite clasico de Windows). Planifica
    con el limite de servidor equivalente. Por defecto no se usa, pero el informe avisa de esas rutas.
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
.EXAMPLE
    .\03-shorten-long-paths.ps1 -Ruta "$env:OneDriveCommercial\CLIENTES" -LimiteLocal 259 -DryRun
    Plan para las rutas que fallan en el PC, no solo para las que pasan del limite del servidor.
.EXAMPLE
    .\03-shorten-long-paths.ps1 -Ruta "$env:OneDriveCommercial\NombreDelAccesoDirecto" -LimiteLocal 259 -DryRun
    Plan dentro de un acceso directo. No cambia nada; los renombrados se verian en la biblioteca compartida.
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
    [Alias('Path')][string]$Ruta,
    [string]$Upn,
    [string]$Raiz,
    [string]$Prefijo,
    [Alias('Limit')][ValidateRange(50, 400)][int]$Limite = 400,
    [Alias('Margin')][ValidateRange(0, 200)][int]$Margen = 20,
    [Alias('LocalLimit')][ValidateRange(0, 400)][int]$LimiteLocal = 0,
    [switch]$PermitirRecorte,
    [ValidateRange(3, 200)][int]$MinNombre = 20,
    [string[]]$Excluir = @(),
    [string[]]$Proteger = @(),
    [Alias('WhatIf')][switch]$DryRun,
    [switch]$SinConfirmar,
    [string]$Revertir,
    [string]$Version = 'latest',
    [switch]$Ascii
)

$ErrorActionPreference = 'Stop'
# Los alias son los nombres del motor: sus avisos dan los comandos con esos nombres.
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
        # .NET en vez de Get-FileHash y Expand-Archive: lanzado desde PowerShell 7, Windows PowerShell
        # hereda su PSModulePath y esos dos cmdlets no se encuentran.
        $sha = [Security.Cryptography.SHA256]::Create()
        $fs = [IO.File]::OpenRead($zip)
        try { $real = -join ($sha.ComputeHash($fs) | ForEach-Object { $_.ToString('X2') }) } finally { $fs.Dispose(); $sha.Dispose() }
        if ($real -ne $esperado) { throw "SHA-256 distinto (esperado $esperado, obtenido $real). No se ejecuta nada." }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($zip, (Join-Path $tmp 'app'))
        $psd1 = Join-Path $tmp 'app\PathShrink\PathShrink.psd1'
    } catch {
        if ($_.Exception.Message -like 'SHA-256*') { throw }
        $local = Join-Path $env:LOCALAPPDATA 'Programs\PathShrink\PathShrink\PathShrink.psd1'
        if (-not (Test-Path -LiteralPath $local)) { throw "No se pudo descargar PathShrink ($($_.Exception.Message)) y no hay copia instalada." }
        Write-Host 'Sin descarga: se usa la copia instalada de PathShrink.' -ForegroundColor Yellow
        $psd1 = $local
    }
    foreach ($x in Get-ChildItem -LiteralPath (Split-Path $psd1 -Parent) -Recurse -File) { Remove-Item -LiteralPath $x.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue }
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

    # Margin solo si se pide: con -LimiteLocal el motor usa 0 si no le llega ninguno.
    $a = @{ Limit = $Limite; AllowTrim = $PermitirRecorte; MinNameLength = $MinNombre; Exclude = $Excluir; Protect = $Proteger }
    foreach ($par in @(@('Ruta', 'Path'), @('Upn', 'Upn'), @('Raiz', 'Root'), @('Prefijo', 'Prefix'), @('Margen', 'Margin'), @('LimiteLocal', 'LocalLimit'))) {
        if ($PSBoundParameters.ContainsKey($par[0])) { $a[$par[1]] = $PSBoundParameters[$par[0]] }
    }
    if ($DryRun) { $a.WhatIf = $true }
    if ($SinConfirmar) { $a.Confirm = $false }
    Invoke-PathShrink @a
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
