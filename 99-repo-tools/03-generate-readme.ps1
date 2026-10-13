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

    Cada script que se ejecuta lleva en el indice su cuenta y sus parametros. La cuenta sale
    de la linea 'Contexto:' del .NOTES (usuario, admin o mixto); los parametros se leen del
    param() con el parser de PowerShell, asi que no hay lista a mano que se desincronice.

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

    Every runnable script gets its account and parameters in the index. The account comes
    from the 'Contexto:' line in .NOTES (usuario, admin or mixto); parameters are read from
    param() with the PowerShell parser, so there is no hand-kept list to drift.

.PARAMETER Comprobar
    [ES] No escribe: falla si algun README esta desactualizado. Para usar antes de commitear.
    [EN] Does not write: fails if either README is stale. Use it before committing.

.EXAMPLE
    .\03-generate-readme.ps1

.EXAMPLE
    .\03-generate-readme.ps1 -Comprobar

.NOTES
    Contexto: usuario
    PowerShell 5.1 y 7.
#>
[CmdletBinding()]
param([switch]$Comprobar)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path $PSScriptRoot -Parent

# Titulo de cada carpeta en los dos idiomas. El orden de esta lista es el orden del indice.
# Icono: SVG de Fluent UI System Icons (MIT) en .github/icons, mismo color en tema claro y oscuro.
$secciones = @(
    @{ Carpeta = '00-copy-paste';   ES = '00 - Copiar y pegar (diagnostico)'; EN = '00 - Copy and paste (diagnostics)'; Icono = 'clipboard_code' }
    @{ Carpeta = '01-identity-cache'; ES = '01 - Cache de identidad';         EN = '01 - Identity cache'; Icono = 'key' }
    @{ Carpeta = '02-outlook';      ES = '02 - Outlook';                      EN = '02 - Outlook'; Icono = 'mail' }
    @{ Carpeta = '03-onedrive';     ES = '03 - OneDrive';                     EN = '03 - OneDrive'; Icono = 'cloud' }
    @{ Carpeta = '04-teams';        ES = '04 - Teams';                        EN = '04 - Teams'; Icono = 'people_team' }
    @{ Carpeta = '05-office-apps';  ES = '05 - Aplicaciones de Office';       EN = '05 - Office apps'; Icono = 'apps' }
    @{ Carpeta = '06-applications'; ES = '06 - Aplicaciones corporativas';    EN = '06 - Corporate applications'; Icono = 'puzzle_piece' }
    @{ Carpeta = '07-endpoint';     ES = '07 - Equipo';                       EN = '07 - Endpoint'; Icono = 'laptop' }
    @{ Carpeta = '08-network';      ES = '08 - Red';                          EN = '08 - Network'; Icono = 'router' }
    @{ Carpeta = '09-documents';    ES = '09 - Documentos';                   EN = '09 - Documents'; Icono = 'document' }
    @{ Carpeta = '10-file-picker'; ES = '10 - Selector de archivos';         EN = '10 - File picker'; Icono = 'folder_open' }
    @{ Carpeta = '11-certificates'; ES = '11 - Certificados';                EN = '11 - Certificates'; Icono = 'certificate' }
    @{ Carpeta = '99-repo-tools';   ES = '99 - Herramientas del repo';        EN = '99 - Repo tools'; Icono = 'wrench' }
)

# Seccion 0: los que se usan a diario. No son copias, son los mismos ficheros que siguen
# viviendo en su carpeta; aqui solo se listan otra vez para tenerlos a mano. El orden es el
# de uso real en una incidencia de identidad, no el de las carpetas.
# El nombre va en ingles en los dos README: identifica la operacion, no la describe.
# Args: parametros que se anaden a la linea de How to run cuando el valor por defecto del
# script no arregla nada (03-repair-credential-cache arranca en Diagnose, solo lectura;
# aqui va en la reparacion segura de su ayuda, con backup y Restore para deshacer).
$destacados = @(
    @{ Ruta = '01-identity-cache/01-clear-cached-accounts.ps1'; Nombre = 'Identity Cache Purge' }
    @{ Ruta = '01-identity-cache/02-reset-stale-tenant-v2.1.ps1'; Nombre = 'Stale Tenant Reset' }
    @{ Ruta = '01-identity-cache/03-repair-credential-cache-with-restore.ps1'; Nombre = 'Credential Cache Repair'; Args = '-Mode Repair -CloseApps' }
    @{ Ruta = '03-onedrive/03-shorten-long-paths.ps1'; Nombre = 'OneDrive Long Path Fix' }
    @{ Ruta = '00-copy-paste/03-endpoint-report.ps1'; Nombre = 'Endpoint Technical Audit' }
    @{ Ruta = '03-onedrive/01-remediate-onedrive-tiered.ps1'; Nombre = 'OneDrive Tiered Remediation' }
    @{ Ruta = '04-teams/01-repair-teams-signin.ps1'; Nombre = 'Teams Authentication Reset' }
)

# Titulo corto de cada script, por sintoma: es la unica linea que se ve con el indice
# plegado, asi que tiene que leerse de un vistazo. ES sin tildes (las pone es-accents.ini).
# Un script sin entrada aqui sale con su .SYNOPSIS entero: largo, pero no se pierde.
$titulos = @{
    '01-clear-cached-accounts.ps1'                = @('Borrar cuentas de trabajo cacheadas', 'Clear cached work accounts')
    '02-reset-stale-tenant-v2.1.ps1'              = @('Cuenta de un tenant antiguo que no se va', 'Stale tenant account that keeps coming back')
    '03-repair-credential-cache-with-restore.ps1' = @('Reparar cache de credenciales M365', 'Repair M365 credential cache')
    '01-reset-outlook-profile.ps1'                = @('Rehacer el perfil de Outlook', 'Rebuild the Outlook profile')
    '02-full-outlook-reset.ps1'                   = @('Reset completo de Outlook', 'Full Outlook reset')
    '03-repair-signin-window.ps1'                 = @('Ventana de login en blanco en Outlook', 'Blank sign-in window in Outlook')
    '01-remediate-onedrive-tiered.ps1'            = @('OneDrive no sincroniza o no arranca', 'OneDrive not syncing or not starting')
    '02-fix-onedrive-permissions.ps1'             = @('OneDrive pide permisos de administrador', 'OneDrive asks for admin rights')
    '03-shorten-long-paths.ps1'                   = @('OneDrive: la ruta es demasiado larga', 'OneDrive: path too long')
    '01-repair-teams-signin.ps1'                  = @('Teams no inicia sesion', 'Teams will not sign in')
    '02-repair-teams-outlook-addin.ps1'           = @('Falta el boton de Teams en Outlook', 'Teams button missing in Outlook')
    '03-repair-teams-addin-com.ps1'               = @('Complemento de Teams en Outlook se desactiva', 'Teams Outlook add-in keeps turning off')
    '01-repair-office-install.ps1'                = @('Reparar la instalacion de Office', 'Repair the Office install')
    '02-m365-remediation-engine.ps1'              = @('Reparacion automatica de M365', 'Automatic M365 repair')
    '01-diagnose-eset.ps1'                        = @('ESET no instala, no arranca o no conecta', 'ESET not installed, running or connecting')
    '02-install-eset.ps1'                         = @('Instalar ESET', 'Install ESET')
    '03-uninstall-imanage.ps1'                    = @('Desinstalar iManage', 'Uninstall iManage')
    '04-install-pdfelement-imanage.ps1'           = @('Instalar PDFelement e iManage', 'Install PDFelement and iManage')
    '05-diagnose-installers.ps1'                  = @('Parametros silenciosos de un instalador','Which silent switches an installer takes')
    '06-repair-mitel-client.ps1'                  = @('Reparar Mitel Connect / MiCollab', 'Repair Mitel Connect / MiCollab')
    '01-disk-usage.ps1'                           = @('Disco lleno', 'Disk full')
    '02-bitlocker-recovery-key.ps1'               = @('Clave de recuperacion de BitLocker', 'BitLocker recovery key')
    '03-fix-random-shutdowns.ps1'                 = @('Apagados o reinicios inesperados', 'Unexpected shutdowns or restarts')
    '04-repair-time-sync.ps1'                     = @('Hora mal: no deja firmar en sedes electronicas', 'Wrong clock: e-signature portals fail')
    '05-enable-long-paths.ps1'                    = @('Activar rutas largas de Windows', 'Enable Windows long paths')
    '01-optimize-wifi-adapter.ps1'                = @('Wi-Fi lenta o que se corta', 'Slow or dropping Wi-Fi')
    '01-unlock-protected-word.ps1'                = @('Word protegido y sin contrasena', 'Protected Word file, password lost')
    '01-diagnose-file-picker.ps1'                 = @('Selector de archivos: diagnostico', 'File picker: diagnosis')
    '02-test-file-picker-hang.ps1'                = @('Selector de archivos se cuelga', 'File picker hangs')
    '03-reset-file-picker-mru.ps1'                = @('Limpiar carpetas recientes del selector', 'Clear file picker recent folders')
    '04-block-shell-extension.ps1'                = @('Bloquear una extension de shell', 'Block a shell extension')
    '05-diagnose-file-picker-crash.ps1'           = @('La app se cierra al Abrir o Guardar como', 'App crashes on Open or Save as')
    '01-repair-autofirma-certificate.ps1'         = @('AutoFirma no muestra el certificado', 'AutoFirma does not list the certificate')
    '01-validate-scripts.ps1'                     = @('Validar los scripts del repo', 'Validate repo scripts')
    '02-test-outlook-reset.ps1'                   = @('Probar el reset de Outlook en sandbox', 'Test the Outlook reset in a sandbox')
    '03-generate-readme.ps1'                      = @('Regenerar los README', 'Rebuild the READMEs')
}

$urlRaw ='https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main'

# Linea unica para pegar en la consola del usuario: descarga de main y ejecuta, en 5.1 y 7.
# - TLS 1.2 forzado: 5.1 en equipos viejos negocia TLS 1.0 y GitHub lo rechaza.
# - Lo de 00-copy-paste no lleva param() ni ayuda: va en memoria con iex y no le afecta la
#   politica de ejecucion.
# - El resto se baja a %TEMP% con su nombre y se lanza como fichero, no con iex: asi
#   funcionan param(), #Requires, $PSCommandPath (03-shorten-long-paths se relanza a si
#   mismo) y la copia que hace 03-repair-signin-window para la sesion del usuario. La
#   politica se abre solo para este proceso (-Scope Process): no queda cambiada.
function Get-UnaLinea([string]$ruta, [string]$argumentos) {
    $tls = '[Net.ServicePointManager]::SecurityProtocol=3072'
    if ($ruta.StartsWith('00-copy-paste/')) { return "$tls; irm $urlRaw/$ruta | iex" }
    $linea = "Set-ExecutionPolicy -Scope Process Bypass -Force; $tls; `$f=`"`$env:TEMP\$(Split-Path $ruta -Leaf)`"; irm $urlRaw/$ruta -OutFile `$f; & `$f"
    if ($argumentos) { $linea += " $argumentos" }
    return $linea
}

# Una ficha plegable por script en vez de fila de tabla: GitHub solo pone boton de copiar
# en los bloques de codigo, nunca en una celda. Plegada se ve una linea -consola en color y
# sintoma-; al abrirla, descripcion, linea para pegar y parametros. Ctrl+F del navegador
# encuentra el texto aunque este plegado. El summary es HTML: ahi no vale Markdown.
function Add-Ficha($sb, [string]$resumen, [string]$cuerpo, [string]$linea, [string]$pie) {
    [void]$sb.AppendLine("<details><summary>$resumen</summary>")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine($cuerpo)
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('```powershell')
    [void]$sb.AppendLine($linea)
    [void]$sb.AppendLine('```')
    if ($pie) { [void]$sb.AppendLine($pie) }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('</details>')
    # Linea en blanco obligatoria: un bloque HTML solo termina en linea vacia, y sin ella el
    # '## ' de la seccion siguiente se queda dentro y GitHub lo pinta tal cual.
    [void]$sb.AppendLine()
}

# Mismo slug que GitHub: minusculas, fuera todo lo que no sea letra, digito, espacio,
# guion o guion bajo, espacios a guiones. El <img> desaparece pero el espacio que lo
# sigue no, por eso el ancla de un encabezado con icono empieza por guion.
function Get-Ancla([string]$titulo) { '#-' + (($titulo.Trim().ToLower() -replace '[^\p{L}\p{Nd} _-]', '') -replace ' ', '-') }

function Get-Titulo([string]$nombre, [string]$idioma, [string]$porDefecto) {
    if (-not $titulos.ContainsKey($nombre)) { return $porDefecto }
    if ($idioma -eq 'EN') { return $titulos[$nombre][1] }
    return (Add-Tildes $titulos[$nombre][0])
}

# alt vacio: asi la imagen no entra en el ancla que GitHub genera para el encabezado.
function Get-Icono([string]$n) { "<img src=`".github/icons/$n.svg`" width=`"20`" height=`"20`" align=`"top`" alt=`"`">" }

function Get-Sinopsis([string]$ruta) {
    # Se lee el fichero en crudo en vez de usar Get-Help: Get-Help carga el script en una
    # sesion de ayuda y aqui solo hacen falta dos lineas de texto.
    $texto = [IO.File]::ReadAllText($ruta)
    $es = if ($texto -match '(?m)^\s*\[ES\]\s*(.+?)\s*$') { $Matches[1] } else { $null }
    $en = if ($texto -match '(?m)^\s*\[EN\]\s*(.+?)\s*$') { $Matches[1] } else { $null }
    return @{ ES = $es; EN = $en }
}

# Cuenta con la que se ejecuta. Sin linea Contexto: el generador falla: un script sin
# cuenta declarada es justo el que acaba lanzandose elevado con el perfil equivocado.
function Get-Contexto([string]$ruta, [string]$idioma) {
    $texto = [IO.File]::ReadAllText($ruta)
    if ($texto -notmatch '(?m)^\s*Contexto\s*:\s*(usuario|admin|mixto)\s*$') {
        throw "Falta 'Contexto: usuario|admin|mixto' en el .NOTES de $ruta"
    }
    return Get-Etiqueta $Matches[1] $idioma
}

# Consola en la que se lanza, en color para verla de un vistazo: verde sin elevar, rojo
# elevada. GitHub no colorea texto en Markdown, asi que son SVG de .github/icons. mixto
# pinta las dos: el script tiene fases en cada una (Get-Help -Full dice cual).
function Get-Etiqueta([string]$valor, [string]$idioma) {
    $user = if ($idioma -eq 'EN') { 'user' } else { 'usuario' }
    $img = { param($n, $alt) "<img src=`".github/icons/badge-$n.svg`" height=`"20`" align=`"top`" alt=`"$alt`">" }
    switch ($valor) {
        'admin' { return (& $img 'admin' 'admin') }
        'mixto' { return "$(& $img 'admin' 'admin') + $(& $img $user $user)" }
        default { return (& $img $user $user) }
    }
}

# Parametros tal y como los ve PowerShell: el parser lee el param() real, asi que lo que
# sale en el README es lo que acepta el script. -WhatIf entra si el script lo soporta.
function Get-Parametros([string]$ruta) {
    $tokens = $null; $errores = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($ruta, [ref]$tokens, [ref]$errores)
    $nombres = New-Object System.Collections.ArrayList
    if ($ast.ParamBlock) {
        foreach ($p in $ast.ParamBlock.Parameters) { [void]$nombres.Add('-' + $p.Name.VariablePath.UserPath) }
        $cb = $ast.ParamBlock.Attributes | Where-Object { $_.TypeName.Name -eq 'CmdletBinding' }
        $sp = $cb | ForEach-Object { $_.NamedArguments } | Where-Object { $_.ArgumentName -eq 'SupportsShouldProcess' }
        if ($sp -and $sp.Argument.Extent.Text -ne '$false' -and $nombres -notcontains '-WhatIf') { [void]$nombres.Add('-WhatIf') }
    }
    return @($nombres)
}

# Los .ps1 son ASCII, asi que las tildes del README en espanol salen de es-accents.ini.
$tildes = New-Object System.Collections.ArrayList
$rutaTildes = Join-Path $PSScriptRoot 'es-accents.ini'
if (Test-Path $rutaTildes) {
    foreach ($l in [IO.File]::ReadAllLines($rutaTildes, [Text.Encoding]::UTF8)) {
        if ($l -match '^\s*(#|$)' -or $l -notmatch '^([^=]+)=(.+)$') { continue }
        [void]$tildes.Add(@{ Patron = '(?i)\b' + [regex]::Escape($Matches[1].Trim()) + '\b'; Valor = $Matches[2].Trim() })
    }
}

function Add-Tildes([string]$texto) {
    if (-not $texto) { return $texto }
    foreach ($t in $tildes) {
        $valor = $t.Valor
        $texto = [regex]::Replace($texto, $t.Patron, {
            param($m)
            $inicio = if ([char]::IsUpper($m.Value[0])) { $valor.Substring(0, 1).ToUpper() } else { $valor.Substring(0, 1).ToLower() }
            $inicio + $valor.Substring(1)
        }.GetNewClosure())
    }
    return $texto
}

$indicePaste = $null
$rutaIndice = Join-Path $raiz '00-copy-paste\index.psd1'
# Parser + SafeGetValue en vez de Import-PowerShellDataFile: lanzado desde una consola de
# PS 7, el PSModulePath heredado hace que PS 5.1 no encuentre ese cmdlet.
if (Test-Path $rutaIndice) {
    $tk = $null; $er = $null
    $astIndice = [Management.Automation.Language.Parser]::ParseFile($rutaIndice, [ref]$tk, [ref]$er)
    $indicePaste = $astIndice.Find({ param($n) $n -is [Management.Automation.Language.HashtableAst] }, $false).SafeGetValue()
}

function New-Indice([string]$idioma) {
    $sb = New-Object Text.StringBuilder

    # Barra de saltos por area, sin etiqueta delante: el icono es lo que se busca con la
    # vista. Las anclas solo existen si cada '## ' va precedido de linea en blanco (Add-Ficha).
    $saltos = foreach ($sec in $secciones) {
        if (-not (Test-Path (Join-Path $raiz $sec.Carpeta))) { continue }
        # Icono fuera del enlace: GitHub envuelve cada <img> en su propio enlace y se anidarian.
        "$(Get-Icono $sec.Icono) [$($sec.EN -replace '^\d+ - ', '')]($(Get-Ancla $sec.EN))"
    }
    [void]$sb.AppendLine($saltos -join ' | ')
    [void]$sb.AppendLine()

    # Los destacados salen antes que ninguna carpeta: es la lista que se abre a diario.
    [void]$sb.AppendLine("## $(Get-Icono 'pin') 0 - LAS MAINS")
    [void]$sb.AppendLine()
    foreach ($d in $destacados) {
        # Un destacado que apunta a un fichero renombrado seria un enlace roto en la
        # primera tabla del README: mejor que falle la generacion.
        if (-not (Test-Path (Join-Path $raiz ($d.Ruta -replace '/', '\')))) {
            throw "Destacado inexistente: $($d.Ruta)"
        }
        $nombre = Split-Path $d.Ruta -Leaf
        $base = [IO.Path]::GetFileNameWithoutExtension($nombre)
        $esDe00 = $d.Ruta.StartsWith('00-copy-paste/')
        if ($esDe00) {
            $v = if ($indicePaste -and $indicePaste.ContainsKey($nombre)) { $indicePaste[$nombre].Ventana } else { 'usuario' }
            $cuenta = Get-Etiqueta $v $idioma
        } else {
            $cuenta = Get-Contexto (Join-Path $raiz ($d.Ruta -replace '/', '\')) $idioma
        }
        $icoD = Get-Icono ($secciones | Where-Object { $d.Ruta.StartsWith($_.Carpeta + '/') } | Select-Object -First 1).Icono
        $descD = if ($esDe00) { $indicePaste[$nombre].$idioma } else { (Get-Sinopsis (Join-Path $raiz ($d.Ruta -replace '/', '\'))).$idioma }
        if ($idioma -eq 'ES') { $descD = Add-Tildes $descD }
        Add-Ficha $sb "$cuenta $icoD <b>$($d.Nombre)</b>" "$descD<br>[``$base``]($($d.Ruta))" (Get-UnaLinea $d.Ruta $d.Args) $null
    }

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
        [void]$sb.AppendLine("## $(Get-Icono $sec.Icono) $($sec.EN)")
        [void]$sb.AppendLine()

        # Bajo cada encabezado van las fichas y nada mas: sin notas ni parrafos de contexto.
        $esPaste = ($sec.Carpeta -eq '00-copy-paste')
        # Las herramientas del repo trabajan sobre el checkout: bajadas a %TEMP% no tienen
        # README que regenerar ni scripts que validar. Su linea es la ruta local.
        $esLocal = ($sec.Carpeta -eq '99-repo-tools')
        $txtParams = if ($idioma -eq 'ES') { Add-Tildes 'Parametros' } else { 'Parameters' }

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
            if ($idioma -eq 'ES') { $desc = Add-Tildes $desc; $titulo = Add-Tildes $titulo }

            $ruta = "$($sec.Carpeta)/$($f.Name)"
            if ($esPaste) {
                # Titulo corto y tecnico para identificar el informe; el detalle, debajo.
                if (-not $titulo) { $titulo = $f.BaseName }
                if (-not $ventana) { $ventana = 'usuario' }
                Add-Ficha $sb "$(Get-Etiqueta $ventana $idioma) <b>$titulo</b>" "$desc<br>[``$($f.BaseName)``]($ruta)" (Get-UnaLinea $ruta $null) $null
            }
            else {
                $params = @(Get-Parametros $f.FullName)
                $pie = $null
                if ($params.Count) {
                    $lista = ($params | ForEach-Object { '`' + $_ + '`' }) -join ' '
                    $pie = "<sub>$txtParams`: $lista</sub>"
                }
                $linea = if ($esLocal) { ".\$($sec.Carpeta)\$($f.Name)" } else { Get-UnaLinea $ruta $null }
                $tit = Get-Titulo $f.Name $idioma $desc
                Add-Ficha $sb "$(Get-Contexto $f.FullName $idioma) <b>$tit</b>" "$desc<br>[``$($f.BaseName)``]($ruta)" $linea $pie
            }
        }

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
