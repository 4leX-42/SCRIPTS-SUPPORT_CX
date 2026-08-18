<#
.SYNOPSIS
    [ES] Regenera el indice de README.md y README.en.md leyendo el .SYNOPSIS de cada script.
    [EN] Rebuilds the index in README.md and README.en.md from each script's .SYNOPSIS.

.DESCRIPTION
    [ES]
    Existe para no tener que editar dos README a mano cada vez que se toca un script. Lee
    la linea [ES] y la linea [EN] del .SYNOPSIS de cada .ps1, y con eso reescribe las
    tablas de indice de los dos README. Todo lo demas del fichero -cabecera, parametros,
    contexto de ejecucion, retirados, estandar- se conserva intacto: solo se sustituye lo
    que hay entre los marcadores INDICE-INICIO e INDICE-FIN.

    El modo de uso no se declara en ningun sitio, se deduce de la carpeta: lo que vive en
    00-copy-paste es para pegar en la consola, y el resto se descarga y se ejecuta. Asi no
    hay una etiqueta mas que mantener sincronizada.

    Los scripts de 00-copy-paste no tienen bloque de ayuda -serian ruido al pegarlos-, asi
    que sus descripciones se leen de 00-copy-paste/index.psd1.

    [EN]
    Exists so nobody has to hand-edit two READMEs every time a script changes. It reads the
    [ES] and [EN] lines from each .ps1 .SYNOPSIS and rewrites the index tables in both
    READMEs. Everything else in the file -header, parameters, execution context, retired,
    standard- is preserved: only the content between the INDICE-INICIO and INDICE-FIN
    markers is replaced.

    Usage mode is not declared anywhere, it is derived from the folder: anything under
    00-copy-paste is meant to be pasted into the console, everything else is downloaded and
    run. One less label to keep in sync.

    Scripts in 00-copy-paste carry no help block -it would be noise when pasted- so their
    descriptions come from 00-copy-paste/index.psd1.

.PARAMETER Comprobar
    [ES] No escribe: falla si algun README esta desactualizado. Para usar antes de commitear.
    [EN] Does not write: fails if either README is stale. Use it before committing.

.EXAMPLE
    .\03-generate-readme.ps1

.EXAMPLE
    .\03-generate-readme.ps1 -Comprobar

.NOTES
    PowerShell 5.1 y 7.
#>
[CmdletBinding()]
param([switch]$Comprobar)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path $PSScriptRoot -Parent

# Titulo de cada carpeta en los dos idiomas. El orden de esta lista es el orden del indice.
$secciones = @(
    @{ Carpeta = '00-copy-paste';   ES = '00 - Copiar y pegar (diagnostico)'; EN = '00 - Copy and paste (diagnostics)' }
    @{ Carpeta = '01-identity-cache'; ES = '01 - Cache de identidad';         EN = '01 - Identity cache' }
    @{ Carpeta = '02-outlook';      ES = '02 - Outlook';                      EN = '02 - Outlook' }
    @{ Carpeta = '03-onedrive';     ES = '03 - OneDrive';                     EN = '03 - OneDrive' }
    @{ Carpeta = '04-teams';        ES = '04 - Teams';                        EN = '04 - Teams' }
    @{ Carpeta = '05-office-apps';  ES = '05 - Aplicaciones de Office';       EN = '05 - Office apps' }
    @{ Carpeta = '06-applications'; ES = '06 - Aplicaciones corporativas';    EN = '06 - Corporate applications' }
    @{ Carpeta = '07-endpoint';     ES = '07 - Equipo';                       EN = '07 - Endpoint' }
    @{ Carpeta = '08-network';      ES = '08 - Red';                          EN = '08 - Network' }
    @{ Carpeta = '09-documents';    ES = '09 - Documentos';                   EN = '09 - Documents' }
    @{ Carpeta = '99-repo-tools';   ES = '99 - Herramientas del repo';        EN = '99 - Repo tools' }
)

# Seccion 0: los que se usan a diario. No son copias, son los mismos ficheros que siguen
# viviendo en su carpeta; aqui solo se listan otra vez para tenerlos a mano. El orden es el
# de uso real en una incidencia de identidad, no el de las carpetas.
# El nombre va en ingles en los dos README: identifica la operacion, no la describe.
$destacados = @(
    @{ Ruta = '01-identity-cache/01-clear-cached-accounts.ps1'; Nombre = 'Identity Cache Purge' }
    @{ Ruta = '01-identity-cache/02-reset-stale-tenant-v2.1.ps1'; Nombre = 'Stale Tenant Reset' }
    @{ Ruta = '00-copy-paste/91-long-paths.txt'; Nombre = 'Long Path Remediation' }
    @{ Ruta = '00-copy-paste/03-endpoint-report.ps1'; Nombre = 'Endpoint Technical Audit' }
    @{ Ruta = '03-onedrive/01-remediate-onedrive-tiered.ps1'; Nombre = 'OneDrive Tiered Remediation' }
    @{ Ruta = '04-teams/01-repair-teams-signin.ps1'; Nombre = 'Teams Authentication Reset' }
)

function Get-Sinopsis([string]$ruta) {
    # Se lee el fichero en crudo en vez de usar Get-Help: Get-Help carga el script en una
    # sesion de ayuda y aqui solo hacen falta dos lineas de texto.
    $texto = [IO.File]::ReadAllText($ruta)
    $es = if ($texto -match '(?m)^\s*\[ES\]\s*(.+?)\s*$') { $Matches[1] } else { $null }
    $en = if ($texto -match '(?m)^\s*\[EN\]\s*(.+?)\s*$') { $Matches[1] } else { $null }
    return @{ ES = $es; EN = $en }
}

$indicePaste = $null
$rutaIndice = Join-Path $raiz '00-copy-paste\index.psd1'
if (Test-Path $rutaIndice) { $indicePaste = Import-PowerShellDataFile $rutaIndice }

function New-Indice([string]$idioma) {
    $sb = New-Object Text.StringBuilder
    $colFuncion = if ($idioma -eq 'ES') { 'Funcion' } else { 'Function' }

    # Los destacados salen antes que ninguna carpeta: es la lista que se abre a diario.
    [void]$sb.AppendLine('## 0 - LAS MAINS')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| Operation | Script | How to run |')
    [void]$sb.AppendLine('|---|---|---|')
    foreach ($d in $destacados) {
        # Un destacado que apunta a un fichero renombrado seria un enlace roto en la
        # primera tabla del README: mejor que falle la generacion.
        if (-not (Test-Path (Join-Path $raiz ($d.Ruta -replace '/', '\')))) {
            throw "Destacado inexistente: $($d.Ruta)"
        }
        $nombre = Split-Path $d.Ruta -Leaf
        $base = [IO.Path]::GetFileNameWithoutExtension($nombre)
        $esDe00 = $d.Ruta.StartsWith('00-copy-paste/')
        # Tres formas de lanzarlo: pegar en consola de admin, pegar en la del usuario, o
        # ejecutar el fichero. En ese ultimo caso la celda ya es la linea que se escribe.
        $como = if ($esDe00) {
            $v = if ($indicePaste -and $indicePaste.ContainsKey($nombre)) { $indicePaste[$nombre].Ventana } else { 'usuario' }
            "paste ($(if ($v -eq 'admin') { 'admin' } else { 'user' }))"
        } else {
            ".\$nombre"
        }
        [void]$sb.AppendLine("| **$($d.Nombre)** | [``$base``]($($d.Ruta)) | ``$como`` |")
    }
    [void]$sb.AppendLine()

    foreach ($sec in $secciones) {
        $dir = Join-Path $raiz $sec.Carpeta
        if (-not (Test-Path $dir)) { continue }

        $ficheros = Get-ChildItem $dir -File |
            Where-Object { $_.Extension -in '.ps1', '.txt' -and $_.Name -ne 'index.psd1' } |
            Sort-Object Name
        if (-not $ficheros) { continue }

        # En 00-copy-paste el orden lo fija index.psd1, no el nombre: primero los que
        # piden consola de administrador, que hay que preparar antes de ir al usuario.
        if ($sec.Carpeta -eq '00-copy-paste' -and $indicePaste) {
            $ficheros = $ficheros | Sort-Object @{
                Expression = {
                    if ($indicePaste.ContainsKey($_.Name) -and $indicePaste[$_.Name].Orden) { [int]$indicePaste[$_.Name].Orden } else { 999 }
                }
            }, Name
        }

        # El titulo va en ingles en los dos README: es el nombre de la carpeta y funciona
        # como identificador. Lo que cambia de idioma son las descripciones.
        [void]$sb.AppendLine("## $($sec.EN)")
        [void]$sb.AppendLine()

        # Bajo cada encabezado va la tabla y nada mas: sin notas ni parrafos de contexto.
        $esPaste = ($sec.Carpeta -eq '00-copy-paste')

        # En 00-copy-paste la primera celda es un titulo corto y tecnico, para identificar
        # el informe de un vistazo; lo que hace en detalle va en la ultima columna. Solo
        # ahi se declara ventana: en el resto la abre el script al ejecutarse.
        if ($esPaste) {
            $colVentana = if ($idioma -eq 'ES') { 'Ventana' } else { 'Window' }
            $colDetalle = if ($idioma -eq 'ES') { 'Que saca' } else { 'What it reports' }
            $colInforme = if ($idioma -eq 'ES') { 'Informe' } else { 'Report' }
            [void]$sb.AppendLine("| $colInforme | Script | $colVentana | $colDetalle |")
            [void]$sb.AppendLine('|---|---|---|---|')
        }
        else {
            [void]$sb.AppendLine("| $colFuncion | Script |")
            [void]$sb.AppendLine('|---|---|')
        }

        foreach ($f in $ficheros) {
            $desc = $null
            $titulo = $null
            $ventana = $null
            if ($sec.Carpeta -eq '00-copy-paste' -and $indicePaste -and $indicePaste.ContainsKey($f.Name)) {
                $desc = $indicePaste[$f.Name].$idioma
                $titulo = if ($idioma -eq 'ES') { $indicePaste[$f.Name].Titulo } else { $indicePaste[$f.Name].TitleEN }
                $ventana = $indicePaste[$f.Name].Ventana
            }
            elseif ($f.Extension -eq '.ps1') {
                $desc = (Get-Sinopsis $f.FullName).$idioma
            }
            if (-not $desc) { $desc = '(sin descripcion)' }

            $ruta = "$($sec.Carpeta)/$($f.Name)"
            if ($esPaste) {
                if (-not $titulo) { $titulo = $f.BaseName }
                if (-not $ventana) { $ventana = 'usuario' }
                $ventanaTxt = if ($idioma -eq 'ES') {
                    if ($ventana -eq 'admin') { 'admin' } else { 'usuario' }
                } else {
                    if ($ventana -eq 'admin') { 'admin' } else { 'user' }
                }
                [void]$sb.AppendLine("| **$titulo** | [``$($f.BaseName)``]($ruta) | ``$ventanaTxt`` | $desc |")
            }
            else {
                [void]$sb.AppendLine("| $desc | [``$($f.BaseName)``]($ruta) |")
            }
        }
        [void]$sb.AppendLine()

        # Runbooks: un .md con el mismo nombre base que un .ps1 documenta ese script.
        foreach ($md in (Get-ChildItem $dir -Filter *.md -File)) {
            if ($md.Name -eq 'README.md') { continue }
            $par = Join-Path $dir ($md.BaseName + '.ps1')
            if (Test-Path $par) {
                $txt = if ($idioma -eq 'ES') { 'Runbook detallado' } else { 'Detailed runbook' }
                [void]$sb.AppendLine("$txt`: [``$($md.Name)``]($($sec.Carpeta)/$($md.Name))")
                [void]$sb.AppendLine()
            }
        }
    }
    return $sb.ToString().TrimEnd()
}

$INICIO = '<!-- INDICE-INICIO: generado por 99-repo-tools/03-generate-readme.ps1, no editar a mano -->'
$FIN    = '<!-- INDICE-FIN -->'

$desactualizados = 0
foreach ($par in @(@{ F = 'README.md'; I = 'ES' }, @{ F = 'README.en.md'; I = 'EN' })) {
    $ruta = Join-Path $raiz $par.F
    if (-not (Test-Path $ruta)) { Write-Host "  FALTA: $($par.F)" -ForegroundColor Red; $desactualizados++; continue }

    $actual = [IO.File]::ReadAllText($ruta)
    $iInicio = $actual.IndexOf($INICIO)
    $iFin    = $actual.IndexOf($FIN)
    if ($iInicio -lt 0 -or $iFin -lt 0) {
        Write-Host "  $($par.F): faltan los marcadores INDICE-INICIO / INDICE-FIN" -ForegroundColor Red
        $desactualizados++
        continue
    }

    $nuevo = $actual.Substring(0, $iInicio + $INICIO.Length) + "`r`n`r`n" +
             (New-Indice $par.I) + "`r`n`r`n" + $actual.Substring($iFin)

    if ($nuevo -eq $actual) {
        Write-Host "  [ OK  ] $($par.F) al dia" -ForegroundColor Green
    }
    elseif ($Comprobar) {
        Write-Host "  [STALE] $($par.F) desactualizado" -ForegroundColor Red
        $desactualizados++
    }
    else {
        [IO.File]::WriteAllText($ruta, $nuevo, (New-Object Text.UTF8Encoding $true))
        Write-Host "  [ESCRITO] $($par.F)" -ForegroundColor Yellow
    }
}

if ($Comprobar -and $desactualizados -gt 0) {
    Write-Host ''
    Write-Host "  $desactualizados README sin regenerar. Ejecuta: .\99-repo-tools\03-generate-readme.ps1" -ForegroundColor Red
    exit 1
}
Write-Host ''
