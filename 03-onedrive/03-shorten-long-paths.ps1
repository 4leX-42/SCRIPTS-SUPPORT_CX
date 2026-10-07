#Requires -Version 5.1

<#
.SYNOPSIS
    [ES] Acorta las rutas de OneDrive de mas de 380 caracteres ("la ruta es demasiado larga") sin tocar el nombre de los documentos.
    [EN] Shortens OneDrive paths over 380 characters ("the path is too long") without renaming the documents.
.DESCRIPTION
    OneDrive y SharePoint no sincronizan un elemento cuya ruta, contada en el servidor y
    ya decodificada, supera 400 caracteres. Esa ruta es la de la biblioteca mas la ruta
    dentro de ella, por ejemplo:
        personal/nombre_apellido_empresa_com/Documents/Desktop/CLIENTES/...
    Formula calibrada con un caso real: el cliente pedia "acorta 2 caracteres" y da 402.
    LongPathsEnabled de Windows NO cambia este limite: es del servicio, no del disco.
    Cambiar espacios o caracteres raros por _ tampoco: el limite cuenta la ruta
    decodificada, asi que un espacio, una tilde o un _ valen 1 caracter cada uno.
    Lo unico que acorta es quitar caracteres.

    Flujo:
      1. Analiza la carpeta y calcula la longitud en el servidor de cada elemento.
      2. Para cada ruta que se pasa, decide el minimo de cambios que la deja en
         -Limite menos -Margen, en este orden y parando en cuanto cabe:
           a. Limpieza sin perdida: espacios dobles, espacios alrededor de - _ , y
              espacios o puntos al final del nombre.
           b. Quitar espacios de una carpeta con mayuscula en cada palabra:
              "Mejoras y modificaciones" -> "MejorasYModificaciones". No se pierde
              ninguna letra. Las carpetas en MAYUSCULAS se dejan para el final.
           c. SOLO con -PermitirRecorte: recortar letras de la carpeta mas larga (nunca
              por debajo de -MinNombre). El fichero solo si ya no queda carpeta, y con
              su extension. Sin ese parametro no se borra ninguna letra: lo que no cabe
              solo quitando espacios queda como SIN ARREGLO para revisarlo a mano.
      El nombre del FICHERO no se toca mientras alguna carpeta de la ruta se pueda
      acortar (incluido recortarla); sin -PermitirRecorte no se toca nunca.
      3. Muestra un PANEL con cada ruta afectada (longitud antes/despues y caracteres
         que se reducen), cada cambio de nombre y el resumen. No toca nada todavia.
      4. Pide confirmacion (escribir SI). Con -DryRun termina en el panel.
      5. Renombra, vuelve a analizar el disco y verifica que no queda nada por encima.

    Nunca renombra: las carpetas de primer nivel de OneDrive (Escritorio, Documentos,
    Imagenes), nada por encima de -Ruta, ni bibliotecas de SharePoint anadidas como
    acceso directo dentro de OneDrive (se saltan: su ruta en el servidor es otra y son
    de todo el equipo). Para tratar una biblioteca de SharePoint, pasala con -Ruta.

    Usa el prefijo \\?\ en todas las operaciones de disco: funciona en PowerShell 5.1
    aunque Windows no tenga activadas las rutas largas, y no se salta en silencio los
    elementos que justo son los problematicos.

    Informes en %TEMP%\OneDriveRutasLargas\<fecha>\ (guardar cambios.csv si se quiere poder deshacer mas adelante):
      panel.txt     el panel tal cual se mostro
      rutas.csv     cada ruta por encima del limite, antes y despues
      cambios.csv   renombrados aplicados (solo si se aplica); sirve para -Revertir
.PARAMETER Ruta
    Carpeta a revisar. Por defecto la raiz del OneDrive de empresa del usuario, que se
    detecta sola. Puede ser una subcarpeta o una biblioteca de SharePoint sincronizada.
.PARAMETER Upn
    Correo de la cuenta. Por defecto se lee de la configuracion de OneDrive.
.PARAMETER Raiz
    Raiz de OneDrive indicada a mano, sin leer el registro. Exige -Upn. Para pruebas
    o para analizar una carpeta copiada de otro equipo.
.PARAMETER Limite
    Longitud maxima en el servidor. Por defecto 400 (limite de Microsoft).
.PARAMETER Margen
    Margen de seguridad por debajo del limite. Por defecto 20: se trata TODA ruta que
    pase de 380 (400 - 20), aunque aun sincronice, para que el siguiente fichero con
    un nombre algo mas largo no vuelva a fallar.
.PARAMETER PermitirRecorte
    Permite el paso c (recortar letras). Por defecto NO: solo limpieza y espacios.
.PARAMETER MinNombre
    Longitud minima a la que se recorta un nombre con -PermitirRecorte. Por defecto 20.
.PARAMETER DryRun
    Muestra el panel y genera los informes. No renombra nada ni pregunta.
.PARAMETER SinConfirmar
    Aplica sin pedir confirmacion (ejecucion desatendida). El panel se muestra igual.
.PARAMETER Ascii
    Dibuja el panel con + - | en vez de lineas, para consolas sin esa fuente.
.PARAMETER Revertir
    cambios.csv de una ejecucion anterior: deshace esos renombrados.
.EXAMPLE
    .\03-shorten-long-paths.ps1 -DryRun
    Analiza el OneDrive del usuario y muestra el panel sin cambiar nada.
.EXAMPLE
    .\03-shorten-long-paths.ps1
    Analiza, muestra el panel, pide confirmacion y aplica.
.EXAMPLE
    .\03-shorten-long-paths.ps1 -Ruta "$env:OneDriveCommercial\Desktop\CLIENTES"
.EXAMPLE
    .\03-shorten-long-paths.ps1 -Revertir "$env:TEMP\OneDriveRutasLargas\20261007-131500-000\cambios.csv"
.NOTES
    EJECUTAR COMO: cuenta del usuario, SIN elevar. La cuenta y la carpeta de OneDrive
    salen de su perfil; elevando con otra cuenta se analizaria otro OneDrive.
    PowerShell 5.1 (el de Windows) y 7. Sin modulos externos.
    Avisar al usuario: los accesos directos y enlaces a las carpetas renombradas dejan
    de funcionar, igual que si se renombraran a mano.
#>
[CmdletBinding()]
param(
    [string]$Ruta,
    [string]$Upn,
    [string]$Raiz,
    [ValidateRange(50, 400)][int]$Limite = 400,
    [ValidateRange(0, 100)][int]$Margen = 20,
    [switch]$PermitirRecorte,
    [ValidateRange(5, 100)][int]$MinNombre = 20,
    [switch]$DryRun,
    [switch]$SinConfirmar,
    [switch]$Ascii,
    [string]$Revertir
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

# ======================================================================================
# Salida: todo lo que se pinta va tambien a panel.txt
# ======================================================================================
$script:log = New-Object System.Collections.Generic.List[string]
function Out-Linea {
    param([string]$Texto = '', [string]$Color = '')
    if ($Color) { Write-Host $Texto -ForegroundColor $Color } else { Write-Host $Texto }
    $script:log.Add($Texto)
}

if ($Ascii) {
    $B = @{ tl = '+'; tr = '+'; bl = '+'; br = '+'; h = '-'; v = '|'; lt = '+'; rt = '+'; tt = '+'; bt = '+'; x = '+' }
} else {
    $B = @{ tl = [string][char]0x250C; tr = [string][char]0x2510; bl = [string][char]0x2514; br = [string][char]0x2518
            h  = [string][char]0x2500; v  = [string][char]0x2502; lt = [string][char]0x251C; rt = [string][char]0x2524
            tt = [string][char]0x252C; bt = [string][char]0x2534; x  = [string][char]0x253C }
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
}

$W = 120
try { $W = [Math]::Min(200, [Math]::Max(100, $Host.UI.RawUI.WindowSize.Width - 1)) } catch { }

function Get-Vista {
    # Recorta por la IZQUIERDA: de una ruta lo que identifica es el final.
    param([string]$s, [int]$ancho)
    if ($s.Length -le $ancho) { return $s }
    '...' + $s.Substring($s.Length - ($ancho - 3))
}
function Split-Ancho {
    # Parte un texto en trozos de $ancho sin perder caracteres (nombres: no se recortan).
    param([string]$s, [int]$ancho)
    if ($s.Length -le $ancho) { return , @($s) }
    $r = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $s.Length; $i += $ancho) { $r.Add($s.Substring($i, [Math]::Min($ancho, $s.Length - $i))) }
    , $r.ToArray()
}
function Write-Caja {
    param([string]$Titulo, [string[]]$Lineas, [string]$Color = 'Cyan')
    $in = $W - 4
    Out-Linea ($B.tl + ($B.h * ($W - 2)) + $B.tr) $Color
    Out-Linea ($B.v + ' ' + $Titulo.PadRight($in) + ' ' + $B.v) $Color
    if ($Lineas) {
        Out-Linea ($B.lt + ($B.h * ($W - 2)) + $B.rt) $Color
        foreach ($l in $Lineas) { foreach ($p in (Split-Ancho $l $in)) { Out-Linea ($B.v + ' ' + $p.PadRight($in) + ' ' + $B.v) } }
    }
    Out-Linea ($B.bl + ($B.h * ($W - 2)) + $B.br) $Color
}
function Write-Tabla {
    # $Cols: @{ N = cabecera; A = ancho (0 = el resto); D = $true alinea a la derecha }
    # $Filas: arrays de celdas; la ultima celda puede ser un array (varias lineas).
    param([object[]]$Cols, [object[]]$Filas, [switch]$Separar, [string]$Color = 'Cyan')
    $fijos = 0; foreach ($c in $Cols) { if ($c.A) { $fijos += $c.A } }
    $anchos = foreach ($c in $Cols) { if ($c.A) { $c.A } else { $W - 1 - $fijos - 3 * $Cols.Count } }
    $sep = { param($i, $m, $f) $s = $i; for ($k = 0; $k -lt $anchos.Count; $k++) { $s += $B.h * ($anchos[$k] + 2); $s += $(if ($k -lt $anchos.Count - 1) { $m } else { $f }) }; $s }
    $celda = { param($t, $k) $t = Get-Vista ([string]$t) $anchos[$k]; if ($Cols[$k]['D']) { $t.PadLeft($anchos[$k]) } else { $t.PadRight($anchos[$k]) } }
    Out-Linea (& $sep $B.tl $B.tt $B.tr) $Color
    $l = $B.v; for ($k = 0; $k -lt $Cols.Count; $k++) { $l += ' ' + $Cols[$k].N.PadRight($anchos[$k]) + ' ' + $B.v }
    Out-Linea $l $Color
    Out-Linea (& $sep $B.lt $B.x $B.rt) $Color
    $n = 0
    foreach ($f in $Filas) {
        if ($Separar -and $n -gt 0) { Out-Linea (& $sep $B.lt $B.x $B.rt) $Color }
        $n++
        $ultima = @($f[$f.Count - 1])
        for ($j = 0; $j -lt $ultima.Count; $j++) {
            $l = $B.v
            for ($k = 0; $k -lt $Cols.Count; $k++) {
                $t = if ($k -eq $Cols.Count - 1) { $ultima[$j] } elseif ($j -eq 0) { $f[$k] } else { '' }
                $l += ' ' + (& $celda $t $k) + ' ' + $B.v
            }
            Out-Linea $l
        }
    }
    Out-Linea (& $sep $B.bl $B.bt $B.br) $Color
}

# ======================================================================================
# Disco: siempre con \\?\ (rutas largas en 5.1 sin depender de LongPathsEnabled)
# ======================================================================================
function ConvertTo-Largo([string]$p) { if ($p.StartsWith('\\?\')) { $p } elseif ($p.StartsWith('\\')) { '\\?\UNC\' + $p.Substring(2) } else { '\\?\' + $p } }
function ConvertFrom-Largo([string]$p) { if ($p.StartsWith('\\?\UNC\')) { '\\' + $p.Substring(8) } elseif ($p.StartsWith('\\?\')) { $p.Substring(4) } else { $p } }

# ======================================================================================
# Revertir
# ======================================================================================
if ($Revertir) {
    $filas = @(Import-Csv -LiteralPath $Revertir | Where-Object { $_.Resultado -eq 'OK' } | Sort-Object { [int]$_.Profundidad })
    Write-Caja 'REVERTIR RENOMBRADOS DE RUTAS LARGAS' @("Fichero: $Revertir", ("Renombrados a deshacer: {0}" -f $filas.Count))
    # De fuera hacia dentro: el padre recupera su nombre antes que sus hijos, y la ruta
    # actual de cada hijo se reconstruye ya con el padre restaurado.
    $ok = 0; $ko = 0
    foreach ($f in $filas) {
        $actual = Join-Path (Split-Path $f.RutaOriginal -Parent) $f.NombreNuevo
        if ($DryRun) { Out-Linea ("  {0}  ->  {1}" -f $actual, $f.NombreOriginal); continue }
        try { Rename-Item -LiteralPath (ConvertTo-Largo $actual) -NewName $f.NombreOriginal; $ok++ }
        catch { $ko++; Out-Linea ("  ERROR {0}: {1}" -f $actual, $_.Exception.Message) 'Red' }
    }
    if (-not $DryRun) { Out-Linea ("Revertidos: {0}   Fallos: {1}" -f $ok, $ko) $(if ($ko) { 'Yellow' } else { 'Green' }) }
    return
}

# ======================================================================================
# Donde esta OneDrive y que prefijo tiene en el servidor
# ======================================================================================
function Get-PrefijoUrl([string]$url) {
    # https://x-my.sharepoint.com/personal/u_d_com/Documents/  ->  personal/u_d_com/Documents/
    try {
        $p = [Uri]::UnescapeDataString(([Uri]$url).AbsolutePath).TrimStart('/')
        if (-not $p.EndsWith('/')) { $p += '/' }
        $p
    } catch { $null }
}

# Bibliotecas sincronizadas y accesos directos: carpeta local -> URL de la biblioteca.
$montajes = New-Object System.Collections.Generic.List[object]
foreach ($k in @(Get-ChildItem 'HKCU:\Software\SyncEngines\Providers\OneDrive' -ErrorAction SilentlyContinue)) {
    $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
    if (-not $p -or -not ($p.PSObject.Properties.Name -contains 'MountPoint') -or -not $p.MountPoint) { continue }
    $url = if ($p.PSObject.Properties.Name -contains 'UrlNamespace') { $p.UrlNamespace } else { $null }
    $tipo = if ($p.PSObject.Properties.Name -contains 'LibraryType') { [string]$p.LibraryType } else { '' }
    $montajes.Add([pscustomobject]@{ Local = ([string]$p.MountPoint).TrimEnd('\'); Prefijo = $(if ($url) { Get-PrefijoUrl $url }); Tipo = $tipo })
}

if ($Raiz) {
    if (-not $Upn) { throw '-Raiz exige -Upn.' }
    $cuentas = @([pscustomobject]@{ UserFolder = (Resolve-Path -LiteralPath $Raiz).Path; UserEmail = $Upn })
} else {
    $cuentas = @(Get-ChildItem 'HKCU:\Software\Microsoft\OneDrive\Accounts' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -like 'Business*' } |
        ForEach-Object { Get-ItemProperty $_.PSPath } |
        Where-Object { ($_.PSObject.Properties.Name -contains 'UserFolder') -and $_.UserFolder -and (Test-Path -LiteralPath $_.UserFolder) })
}
if (-not $cuentas.Count) { throw 'No hay ninguna cuenta de OneDrive de empresa configurada en este perfil de Windows.' }

if ($Ruta) { $Ruta = (Resolve-Path -LiteralPath $Ruta).Path.TrimEnd('\') }

# Biblioteca a la que pertenece la ruta: el montaje mas especifico que la contiene.
$personales = @($cuentas | ForEach-Object { $_.UserFolder.TrimEnd('\') })
$base = $null; $prefijo = $null; $origen = ''; $esPersonal = $false; $correo = $Upn
if (-not $Ruta) { $Ruta = $personales[0]; if ($cuentas.Count -gt 1) { Write-Host ("Hay {0} cuentas de OneDrive; se analiza {1}. Para otra, usa -Ruta." -f $cuentas.Count, $Ruta) -ForegroundColor Yellow } }
$cands = @($montajes | Where-Object { -not $Raiz -and ($Ruta -eq $_.Local -or $Ruta.StartsWith($_.Local + '\', [StringComparison]::OrdinalIgnoreCase)) } | Sort-Object { $_.Local.Length } -Descending)
$cuentaRuta = $cuentas | Where-Object { $r = $_.UserFolder.TrimEnd('\'); $Ruta -eq $r -or $Ruta.StartsWith($r + '\', [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
$montaje = if ($cands.Count) { $cands[0] } else { $null }
if ($montaje -and $cuentaRuta -and $montaje.Local.Length -le $cuentaRuta.UserFolder.TrimEnd('\').Length) { $montaje = $null }  # el personal manda si es el mas especifico

if ($montaje) {
    $base = $montaje.Local; $prefijo = $montaje.Prefijo; $origen = 'registro de OneDrive'
    if (-not $prefijo) { throw "No se pudo leer la URL de la biblioteca de $base." }
    $esPersonal = $prefijo -like 'personal/*'
} elseif ($cuentaRuta) {
    $base = $cuentaRuta.UserFolder.TrimEnd('\'); $esPersonal = $true
    if (-not $correo) { $correo = $cuentaRuta.UserEmail }
    if (-not $correo) { throw 'No se pudo leer el correo de la cuenta de OneDrive. Pasalo con -Upn.' }
    # La URL real del OneDrive, si el registro la tiene, manda sobre el correo: si el
    # UPN cambio despues de crearse, la URL conserva el nombre antiguo.
    $m = $montajes | Where-Object { $_.Local -eq $base -and $_.Prefijo -match '^personal/[^/]+/Documents/$' } | Select-Object -First 1
    if ($m -and -not $Raiz) { $prefijo = $m.Prefijo; $origen = 'registro de OneDrive' }
    else { $prefijo = 'personal/' + ($correo.ToLower() -replace '[.@]', '_') + '/Documents/'; $origen = 'calculado del correo' }
} else {
    throw ("La ruta no esta dentro de OneDrive ni de una biblioteca sincronizada: {0}" -f $Ruta)
}
if (-not $correo -and $cuentaRuta) { $correo = $cuentaRuta.UserEmail }

# Niveles que se pueden renombrar: nunca por encima de -Ruta; en el OneDrive personal,
# tampoco el primer nivel (Escritorio, Documentos, Imagenes redirigidos).
$profRuta = if ($Ruta -eq $base) { 0 } else { $Ruta.Substring($base.Length + 1).Split('\').Count }
$minK = if ($esPersonal) { [Math]::Max(1, $profRuta) } else { $profRuta }
$maximo = $Limite - $Margen

# Accesos directos a otras bibliotecas dentro de la ruta: se saltan.
$saltar = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($m in $montajes) { if ($m.Local -ne $base -and $m.Local.StartsWith($Ruta + '\', [StringComparison]::OrdinalIgnoreCase)) { [void]$saltar.Add($m.Local) } }

# ======================================================================================
# Inventario
# ======================================================================================
function Get-Inventario {
    $lista = New-Object System.Collections.Generic.List[object]
    $errores = New-Object System.Collections.Generic.List[string]
    $pila = New-Object System.Collections.Generic.Stack[string]
    $pila.Push($Ruta)
    while ($pila.Count) {
        $dir = $pila.Pop()
        try { $hijos = ([IO.DirectoryInfo](ConvertTo-Largo $dir)).GetFileSystemInfos() }
        catch { $errores.Add(("{0}: {1}" -f $dir, $_.Exception.InnerException.Message)); continue }
        foreach ($h in $hijos) {
            $full = ConvertFrom-Largo $h.FullName
            if ($saltar.Contains($full)) { continue }
            $rel = $full.Substring($base.Length + 1)
            $carpeta = [bool]($h.Attributes -band [IO.FileAttributes]::Directory)
            $lista.Add([pscustomobject]@{ Rel = $rel; Seg = $rel.Split('\'); EsCarpeta = $carpeta })
            if ($carpeta) { $pila.Push($full) }
        }
    }
    [pscustomobject]@{ Items = $lista; Errores = $errores }
}

Write-Host ("Analizando {0} ..." -f $Ruta) -ForegroundColor Cyan
$inv = Get-Inventario
$items = $inv.Items

$nuevo = @{}      # rel original -> nombre nuevo
$metodo = @{}     # rel original -> pasos aplicados
$hermanos = @{}   # carpeta padre (rel original) -> nombres en uso, para evitar choques
foreach ($it in $items) {
    $padre = if ($it.Seg.Count -gt 1) { $it.Seg[0..($it.Seg.Count - 2)] -join '\' } else { '' }
    if (-not $hermanos.ContainsKey($padre)) { $hermanos[$padre] = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase) }
    [void]$hermanos[$padre].Add($it.Seg[$it.Seg.Count - 1])
}

function Get-RelSeg([string[]]$seg, [int]$k) { $seg[0..$k] -join '\' }
function Get-Nombre([string[]]$seg, [int]$k) {
    $r = Get-RelSeg $seg $k
    if ($nuevo.ContainsKey($r)) { $nuevo[$r] } else { $seg[$k] }
}
function Get-LongServidor([string[]]$seg) {
    $n = $prefijo.Length + $seg.Count - 1
    for ($k = 0; $k -lt $seg.Count; $k++) { $n += (Get-Nombre $seg $k).Length }
    $n
}
function Get-RelNueva([string[]]$seg) { (0..($seg.Count - 1) | ForEach-Object { Get-Nombre $seg $_ }) -join '\' }
function Set-Nombre([string[]]$seg, [int]$k, [string]$candidato, [string]$paso) {
    $r = Get-RelSeg $seg $k
    $actual = Get-Nombre $seg $k
    if (-not $candidato -or $candidato -ceq $actual) { return $false }
    $padre = if ($k -gt 0) { Get-RelSeg $seg ($k - 1) } else { '' }
    $usados = $hermanos[$padre]
    $esF = ($k -eq $seg.Count - 1)
    $n = 2; $base0 = $candidato
    while ($usados.Contains($candidato) -and -not ($candidato -eq $actual)) {
        $ext = if ($esF) { [IO.Path]::GetExtension($base0) } else { '' }
        $sinExt = $base0.Substring(0, $base0.Length - $ext.Length)
        $candidato = '{0}~{1}{2}' -f $sinExt.Substring(0, [Math]::Max(1, $sinExt.Length - 2)), $n, $ext
        $n++
    }
    [void]$usados.Remove($actual); [void]$usados.Add($candidato)
    $nuevo[$r] = $candidato
    if ($metodo.ContainsKey($r)) { if ($metodo[$r] -notlike "*$paso*") { $metodo[$r] += " + $paso" } } else { $metodo[$r] = $paso }
    $true
}
function Limpiar([string]$s) {
    $s = $s -replace '\s{2,}', ' '
    $s = $s -replace '\s*([-_,])\s*', '$1'
    $s.Trim().TrimEnd('.')
}
function SinEspacios([string]$s) {
    $out = ''
    foreach ($w in ($s.Split(' ') | Where-Object { $_ })) {
        if ($out -and [char]::IsLower($w[0])) { $w = $w.Substring(0, 1).ToUpper() + $w.Substring(1) }
        $out += $w
    }
    $out
}
function Recortar([string]$s, [int]$cuanto, [bool]$esFichero) {
    $ext = if ($esFichero) { [IO.Path]::GetExtension($s) } else { '' }
    $b = $s.Substring(0, $s.Length - $ext.Length)
    $len = [Math]::Max($MinNombre, $b.Length - $cuanto)
    if ($len -ge $b.Length) { return $s }
    $b.Substring(0, $len).TrimEnd(' ', '.', '-', '_', ',') + $ext
}

# ======================================================================================
# Plan
# ======================================================================================
$largos = @($items | Where-Object { (Get-LongServidor $_.Seg) -gt $maximo } | Sort-Object { $_.Seg.Count })

function Invoke-Acortar {
    # Aplica a, b y (con -PermitirRecorte) c sobre los niveles $ks de la ruta $seg,
    # parando en cuanto cabe. $esFich indica si $ks es el nombre del fichero.
    param([string[]]$seg, [int[]]$ks, [bool]$esFich)
    $partir = { param($n) if ($esFich) { $e = [IO.Path]::GetExtension($n); , @($n.Substring(0, $n.Length - $e.Length), $e) } else { , @($n, '') } }
    # a. limpieza sin perdida, empezando por el nombre que mas ahorra
    foreach ($k in @($ks | Sort-Object @{ e = { $n = Get-Nombre $seg $_; $n.Length - (Limpiar $n).Length }; Descending = $true })) {
        if ((Get-LongServidor $seg) -le $maximo) { return }
        $p = & $partir (Get-Nombre $seg $k)
        [void](Set-Nombre $seg $k ((Limpiar $p[0]) + $p[1]) 'limpieza')
    }
    # b. quitar espacios con mayuscula por palabra; los nombres en MAYUSCULAS despues
    #    (sin espacios no se leen)
    $orden = @($ks | Sort-Object @{ e = { [int]((Get-Nombre $seg $_) -cmatch '[a-z]') }; Descending = $true },
                                 @{ e = { ([regex]::Matches((Get-Nombre $seg $_), ' ')).Count }; Descending = $true })
    foreach ($k in $orden) {
        if ((Get-LongServidor $seg) -le $maximo) { return }
        $p = & $partir (Get-Nombre $seg $k)
        [void](Set-Nombre $seg $k ((SinEspacios $p[0]) + $p[1]) 'sin espacios')
    }
    # c. solo con -PermitirRecorte: quitar letras del FINAL del nombre mas largo, de una
    #    en una. Asi el recorte se reparte entre los nombres largos y ninguno queda
    #    reducido a su comienzo (el cliente o el asunto suelen ir en mitad del nombre).
    #    Nunca por debajo de -MinNombre.
    $guardia = 0
    while ($PermitirRecorte -and (Get-LongServidor $seg) -gt $maximo -and $guardia -lt 5000) {
        $guardia++
        $cands = @($ks | Where-Object { $p = & $partir (Get-Nombre $seg $_); $p[0].Length -gt $MinNombre })
        if (-not $cands.Count) { return }
        # Empate: la carpeta mas profunda. Sin desempate fijo, 5.1 y 7 eligen distinto.
        $k = $cands | Sort-Object @{ e = { (& $partir (Get-Nombre $seg $_))[0].Length }; Descending = $true },
                                  @{ e = { $_ }; Descending = $true } | Select-Object -First 1
        if (-not (Set-Nombre $seg $k (Recortar (Get-Nombre $seg $k) 1 $esFich) 'recorte')) { return }
    }
}

foreach ($it in $largos) {
    $seg = $it.Seg
    $ultimo = $seg.Count - 1
    if ((Get-LongServidor $seg) -le $maximo -or $ultimo -lt $minK) { continue }
    # Primero SOLO carpetas, con todos los pasos. El nombre del documento se toca
    # unicamente si las carpetas ya no dan mas de si: en un despacho el nombre del
    # fichero importa mas que el de la carpeta que lo contiene. Sin -PermitirRecorte
    # el fichero no se toca nunca: lo que no cabe se ofrece recortar al final.
    $hastaCarpeta = if ($it.EsCarpeta) { $ultimo } else { $ultimo - 1 }
    if ($hastaCarpeta -ge $minK) { Invoke-Acortar $seg @($minK..$hastaCarpeta) $false }
    if (-not $it.EsCarpeta -and $PermitirRecorte -and (Get-LongServidor $seg) -gt $maximo) { Invoke-Acortar $seg @($ultimo) $true }
}

# Resultado por ruta (con TODOS los renombrados ya decididos)
$rutas = foreach ($it in $largos) {
    $antes = $prefijo.Length + $it.Rel.Length
    $desp = Get-LongServidor $it.Seg
    [pscustomobject]@{
        Ruta = $it.Rel; RutaNueva = (Get-RelNueva $it.Seg); Tipo = $(if ($it.EsCarpeta) { 'Carpeta' } else { 'Fichero' })
        Antes = $antes; Despues = $desp; Reduce = $antes - $desp
        Estado = $(if ($desp -le $maximo) { 'OK' } elseif ($desp -le $Limite) { 'CERCA' } else { 'NO SINCRONIZA' })
    }
}
$rutas = @($rutas)

$cambios = @(foreach ($r in $nuevo.Keys) {
    $orig = Split-Path $r -Leaf
    if ($nuevo[$r] -ceq $orig) { continue }
    $pref = $r + '\'
    $afecta = 1 + @($items | Where-Object { $_.Rel.StartsWith($pref, [StringComparison]::OrdinalIgnoreCase) }).Count
    $esCarpeta = ($items | Where-Object { $_.Rel -eq $r } | Select-Object -First 1).EsCarpeta
    [pscustomobject]@{
        Profundidad = $r.Split('\').Count; Tipo = $(if ($esCarpeta) { 'Carpeta' } else { 'Fichero' })
        RutaOriginal = Join-Path $base $r; Padre = (Split-Path $r -Parent)
        NombreOriginal = $orig; NombreNuevo = $nuevo[$r]; Reduce = $orig.Length - $nuevo[$r].Length
        Afecta = $afecta; Metodo = $metodo[$r]; Resultado = ''
    }
}) | Sort-Object RutaOriginal
$cambios = @($cambios)

# ======================================================================================
# Panel
# ======================================================================================
$lp = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -ErrorAction SilentlyContinue)
$lpOn = $lp -and ($lp.PSObject.Properties.Name -contains 'LongPathsEnabled') -and $lp.LongPathsEnabled -eq 1
$informe = Join-Path $env:TEMP ('OneDriveRutasLargas\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $informe -Force | Out-Null

Out-Linea ''
Write-Caja 'ACORTAR RUTAS LARGAS DE ONEDRIVE' @(
    ("Equipo / usuario   : {0} / {1}" -f $env:COMPUTERNAME, $env:USERNAME)
    ("Cuenta             : {0}" -f $correo)
    ("Biblioteca local   : {0}" -f $base)
    ("Carpeta analizada  : {0}" -f $Ruta)
    ("Ruta en servidor   : {0}<ruta>   ({1} caracteres, {2})" -f $prefijo, $prefijo.Length, $origen)
    ("Limite / objetivo  : {0} / {1} caracteres (margen {2})" -f $Limite, $maximo, $Margen)
    ("Modo               : {0}" -f $(if ($PermitirRecorte) { 'limpieza + quitar espacios + RECORTE de letras' } else { 'limpieza + quitar espacios (no se borra ninguna letra)' }))
    ("Elementos leidos   : {0}   Sin acceso: {1}   Accesos a SharePoint saltados: {2}" -f $items.Count, $inv.Errores.Count, $saltar.Count)
    ("Rutas largas Win   : {0}" -f $(if ($lpOn) { 'activadas' } else { 'DESACTIVADAS (no afecta a este script; si a otros programas)' }))
)
foreach ($e in $inv.Errores) { Out-Linea ("  Sin acceso: {0}" -f $e) 'Yellow' }

if (-not $rutas.Count) {
    Out-Linea ''
    Out-Linea ("Ninguna ruta supera {0} caracteres. No hay nada que cambiar." -f $maximo) 'Green'
    $script:log | Set-Content -LiteralPath (Join-Path $informe 'panel.txt') -Encoding UTF8
    return
}

Out-Linea ''
Out-Linea (" RUTAS POR ENCIMA DE {0} CARACTERES ({1})" -f $maximo, $rutas.Count) 'Cyan'
Out-Linea ("   OK = queda en {0} o menos  |  CERCA = sincroniza, pero sin margen  |  NO SINCRONIZA = sigue por encima de {1}" -f $maximo, $Limite) 'DarkGray'
$i = 0
Write-Tabla -Cols @(
    @{ N = '#'; A = 4; D = $true }, @{ N = 'Antes'; A = 5; D = $true }, @{ N = 'Despues'; A = 7; D = $true },
    @{ N = 'Reduce'; A = 6; D = $true }, @{ N = 'Estado'; A = 13 }, @{ N = 'Ruta (dentro de la biblioteca)'; A = 0 }
) -Filas @($rutas | ForEach-Object { $i++; , @($i, $_.Antes, $_.Despues, $(if ($_.Reduce) { '-' + $_.Reduce } else { '0' }), $_.Estado, $_.Ruta) })

if ($cambios.Count) {
    $anchoNom = $W - 1 - (4 + 6 + 6 + 23) - 3 * 5 - 4
    Out-Linea ''
    Out-Linea (" CAMBIOS DE NOMBRE ({0})" -f $cambios.Count) 'Cyan'
    $i = 0
    Write-Tabla -Separar -Cols @(
        @{ N = '#'; A = 4; D = $true }, @{ N = 'Reduce'; A = 6; D = $true }, @{ N = 'Afecta'; A = 6; D = $true },
        @{ N = 'Metodo'; A = 23 }, @{ N = 'Carpeta / nombre actual / nombre nuevo'; A = 0 }
    ) -Filas @($cambios | ForEach-Object {
        $i++
        $lin = @(('en  ' + (Get-Vista $(if ($_.Padre) { $_.Padre } else { '(raiz)' }) $anchoNom)))
        $lin += @(Split-Ancho $_.NombreOriginal $anchoNom | ForEach-Object -Begin { $p = 'de  ' } -Process { $p + $_; $p = '    ' })
        $lin += @(Split-Ancho $_.NombreNuevo $anchoNom | ForEach-Object -Begin { $p = 'a   ' } -Process { $p + $_; $p = '    ' })
        , @($i, ('-' + $_.Reduce), $_.Afecta, $_.Metodo, $lin)
    })
}

$ok = @($rutas | Where-Object Estado -eq 'OK')
$mal = @($rutas | Where-Object Estado -ne 'OK')
# Sumas a mano: Measure-Object sobre una lista vacia no devuelve Sum/Minimum y con
# StrictMode eso es un error (caso real: ninguna ruta con espacios que quitar).
$sumaRed = 0; foreach ($c in $cambios) { $sumaRed += $c.Reduce }
$redOk = @($ok | ForEach-Object { $_.Reduce } | Sort-Object)
Out-Linea ''
Write-Caja 'RESUMEN' @(
    ("Rutas por encima de {0}        : {1}" -f $maximo, $rutas.Count)
    ("  quedan por debajo de {0}     : {1}" -f $maximo, $ok.Count)
    ("  CERCA (sincronizan)          : {0}" -f @($rutas | Where-Object Estado -eq 'CERCA').Count)
    ("  NO SINCRONIZA (> {0})        : {1}{2}" -f $Limite, @($rutas | Where-Object Estado -eq 'NO SINCRONIZA').Count, $(if ($mal.Count) { $(if ($PermitirRecorte) { '  (mover la carpeta a un nivel menos profundo)' } else { '  (acortar a mano, o repetir con -PermitirRecorte)' }) } else { '' }))
    ("Elementos a renombrar          : {0}  ({1} carpetas, {2} ficheros)" -f $cambios.Count, @($cambios | Where-Object Tipo -eq 'Carpeta').Count, @($cambios | Where-Object Tipo -eq 'Fichero').Count)
    ("Caracteres eliminados          : {0} en nombres" -f $sumaRed)
    ("Reduccion por ruta             : {0}" -f $(if ($ok.Count) { $s = 0; foreach ($x in $redOk) { $s += $x }; 'min {0} / media {1:N1} / max {2}' -f $redOk[0], ($s / $redOk.Count), $redOk[$redOk.Count - 1] } else { '-' }))
    ("Informes                       : {0}" -f $informe)
) $(if ($mal.Count) { 'Yellow' } else { 'Cyan' })

$rutas | Export-Csv -LiteralPath (Join-Path $informe 'rutas.csv') -NoTypeInformation -Encoding UTF8
$guardarPanel = { $script:log | Set-Content -LiteralPath (Join-Path $informe 'panel.txt') -Encoding UTF8 }

# Lo que sigue sin sincronizar tras quitar espacios solo se arregla recortando letras.
# Se ofrece en la misma ejecucion: si el usuario acepta, se repite el analisis con
# -PermitirRecorte, que muestra su propio panel y pide su propia confirmacion.
$pendientes = @($rutas | Where-Object Estado -ne 'OK')
if ($pendientes.Count -and -not $PermitirRecorte -and -not $DryRun -and -not $SinConfirmar -and [Environment]::UserInteractive) {
    Out-Linea ''
    Out-Linea ("{0} rutas seguirian por encima de {1}: no caben solo quitando espacios y hay que recortar letras de alguna carpeta:" -f $pendientes.Count, $maximo) 'Yellow'
    foreach ($p in $pendientes) { Out-Linea ("  {0,4}  {1,-13}  {2}" -f $p.Despues, $p.Estado, (Get-Vista $p.Ruta ($W - 25))) 'Yellow' }
    $resp = Read-Host 'Recortar tambien letras para arreglarlas? Se muestra el plan antes de aplicar (SI / cualquier otra cosa = no)'
    $script:log.Add("Respuesta recorte: $resp")
    if ($resp -eq 'SI') {
        & $guardarPanel
        $p2 = @{}; foreach ($k in $PSBoundParameters.Keys) { $p2[$k] = $PSBoundParameters[$k] }
        $p2['PermitirRecorte'] = $true
        & $PSCommandPath @p2
        return
    }
}

if (-not $cambios.Count) { Out-Linea 'No hay ningun cambio posible de forma automatica.' 'Yellow'; & $guardarPanel; return }
if ($DryRun) { Out-Linea ''; Out-Linea 'DryRun: no se ha cambiado nada.' 'Yellow'; & $guardarPanel; return }

# ======================================================================================
# Confirmar y aplicar
# ======================================================================================
if (-not $SinConfirmar) {
    if (-not [Environment]::UserInteractive) { Out-Linea 'Sesion no interactiva: usa -SinConfirmar para aplicar sin preguntar.' 'Yellow'; & $guardarPanel; return }
    Out-Linea ''
    $resp = Read-Host ("Se van a renombrar {0} elementos. Escribe SI para aplicar (cualquier otra cosa cancela)" -f $cambios.Count)
    $script:log.Add("Respuesta: $resp")
    if ($resp -cne 'SI' -and $resp -cne 'si' -and $resp -cne 'Si') { Out-Linea 'Cancelado. No se ha cambiado nada.' 'Yellow'; & $guardarPanel; return }
}

# De dentro hacia fuera: el hijo se renombra con la ruta original del padre, que aun existe.
$nOk = 0; $nKo = 0
foreach ($c in ($cambios | Sort-Object Profundidad -Descending)) {
    try { Rename-Item -LiteralPath (ConvertTo-Largo $c.RutaOriginal) -NewName $c.NombreNuevo; $c.Resultado = 'OK'; $nOk++ }
    catch { $c.Resultado = 'ERROR: ' + $_.Exception.Message; $nKo++; Out-Linea ("  ERROR {0}: {1}" -f $c.RutaOriginal, $_.Exception.Message) 'Red' }
}
$csvCambios = Join-Path $informe 'cambios.csv'
$cambios | Select-Object Profundidad, Tipo, RutaOriginal, NombreOriginal, NombreNuevo, Reduce, Afecta, Metodo, Resultado |
    Export-Csv -LiteralPath $csvCambios -NoTypeInformation -Encoding UTF8

# Verificacion contra el disco: se vuelve a leer todo, no se da por bueno el Rename-Item.
$inv2 = Get-Inventario
$quedan = @($inv2.Items | Where-Object { ($prefijo.Length + $_.Rel.Length) -gt $maximo })
$noSinc = @($quedan | Where-Object { ($prefijo.Length + $_.Rel.Length) -gt $Limite })
$existen = @($rutas | Where-Object { $_.Estado -eq 'OK' -and (Test-Path -LiteralPath (ConvertTo-Largo (Join-Path $base $_.RutaNueva))) })
Out-Linea ''
Write-Caja 'RESULTADO' @(
    ("Renombrados correctos          : {0}" -f $nOk)
    ("Renombrados con error          : {0}{1}" -f $nKo, $(if ($nKo) { '  (fichero abierto o sin permiso: cerrar y repetir)' } else { '' }))
    ("Rutas arregladas comprobadas   : {0} de {1} existen con su nombre nuevo" -f $existen.Count, $ok.Count)
    ("Rutas aun por encima de {0}    : {1}  (de ellas, {2} por encima de {3}: no sincronizan)" -f $maximo, $quedan.Count, $noSinc.Count, $Limite)
    ("Deshacer                       : .\{0} -Revertir `"{1}`"" -f (Split-Path $PSCommandPath -Leaf), $csvCambios)
) $(if ($nKo -or $noSinc.Count -or $existen.Count -ne $ok.Count) { 'Yellow' } else { 'Green' })
foreach ($q in $quedan) { Out-Linea ("  sigue larga ({0}): {1}" -f ($prefijo.Length + $q.Rel.Length), $q.Rel) 'Yellow' }
Out-Linea 'OneDrive sincroniza los cambios solo; el aviso de ruta larga desaparece en unos minutos.'
& $guardarPanel
