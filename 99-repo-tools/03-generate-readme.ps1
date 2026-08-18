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

# Nota al pie de cada carpeta, cuando hay algo que el .SYNOPSIS no puede decir.
$notas = @{
    '00-copy-paste' = @{
        ES = 'Se pegan enteros en la consola. Sin comentarios y sin color: la salida es texto plano `clave=valor` pensado para pasarsela a una IA. Todos son de solo lectura.'
        EN = 'Paste them whole into the console. No comments, no colour: the output is flat `key=value` text meant to be handed to an AI. All read-only.'
    }
    '01-identity-cache' = @{
        ES = 'Perfil del usuario, sin elevar. Alcance: registro de Office `Identity`, `IdentityCRL`, WAM/`TokenBroker`, `OneAuth`, `IdentityCache`, Administrador de credenciales, `OneDrive\Accounts` y licencias de Office.'
        EN = 'User profile, not elevated. Scope: Office `Identity` registry, `IdentityCRL`, WAM/`TokenBroker`, `OneAuth`, `IdentityCache`, Credential Manager, `OneDrive\Accounts` and Office licensing.'
    }
    '02-outlook' = @{
        ES = 'Perfil del usuario, sin elevar. Ninguno borra `.pst`.'
        EN = 'User profile, not elevated. Neither deletes `.pst`.'
    }
    '06-applications' = @{
        ES = 'Requieren admin. Origen de los paquetes: `$env:SOPORTE_ORIGEN_PAQUETES`.'
        EN = 'Require admin. Package source: `$env:SOPORTE_ORIGEN_PAQUETES`.'
    }
}

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
    $colModo    = if ($idioma -eq 'ES') { 'Modo' }    else { 'Mode' }

    foreach ($sec in $secciones) {
        $dir = Join-Path $raiz $sec.Carpeta
        if (-not (Test-Path $dir)) { continue }

        $ficheros = Get-ChildItem $dir -File |
            Where-Object { $_.Extension -in '.ps1', '.txt' -and $_.Name -ne 'index.psd1' } |
            Sort-Object Name
        if (-not $ficheros) { continue }

        # El titulo va en ingles en los dos README: es el nombre de la carpeta y funciona
        # como identificador. Lo que cambia de idioma son las descripciones.
        [void]$sb.AppendLine("## $($sec.EN)")
        [void]$sb.AppendLine()

        if ($notas.ContainsKey($sec.Carpeta)) {
            [void]$sb.AppendLine($notas[$sec.Carpeta].$idioma)
            [void]$sb.AppendLine()
        }

        # Sin tablas anidadas: el modo se deduce de la carpeta y se traduce aqui mismo.
        $esPaste = ($sec.Carpeta -eq '00-copy-paste')
        $modo = if ($idioma -eq 'ES') {
            if ($esPaste) { 'pegar' } else { 'descargar' }
        } else {
            if ($esPaste) { 'paste' } else { 'download' }
        }

        [void]$sb.AppendLine("| $colFuncion | Script | $colModo |")
        [void]$sb.AppendLine('|---|---|---|')

        foreach ($f in $ficheros) {
            $desc = $null
            if ($sec.Carpeta -eq '00-copy-paste' -and $indicePaste -and $indicePaste.ContainsKey($f.Name)) {
                $desc = $indicePaste[$f.Name].$idioma
            }
            elseif ($f.Extension -eq '.ps1') {
                $desc = (Get-Sinopsis $f.FullName).$idioma
            }
            if (-not $desc) { $desc = '(sin descripcion)' }

            $ruta = "$($sec.Carpeta)/$($f.Name)"
            [void]$sb.AppendLine("| $desc | [``$($f.BaseName)``]($ruta) | ``$modo`` |")
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
