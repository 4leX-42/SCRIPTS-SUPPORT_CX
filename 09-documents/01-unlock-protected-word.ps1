#requires -version 3

<#
.SYNOPSIS
    [ES] Quita la proteccion de edicion de un documento de Word cuando se perdio la contrasena.
    [EN] Removes edit protection from a Word document when the password is lost.
.DESCRIPTION
    Un .docx/.docm es, por dentro, un archivo ZIP con varios XML. La opcion
    "Restringir edicion" / "solo lectura" se guarda como el elemento
    <w:documentProtection> dentro de word/settings.xml. Este script abre el
    ZIP, borra ese elemento (y <w:writeProtection> si existe) y lo vuelve a
    empaquetar. El documento queda totalmente editable.

    Antes de modificar nada crea una copia ".BACKUP.docx" junto al original.

    LIMITE REAL (no es una restriccion del script): si el archivo tiene
    CONTRASENA DE APERTURA, su contenido esta cifrado (AES) y no se puede
    leer sin la contrasena. Esos archivos se detectan y se avisan; no se tocan.

.PARAMETER Paths
    Uno o varios archivos. Se rellena solo al arrastrar ficheros sobre el .bat.

.PARAMETER NoPause
    No esperar una tecla al terminar. Util al llamarlo desde otro script.

.EXAMPLE
    Arrastra los .docx sobre "Desbloquear Word.bat".

.EXAMPLE
    Doble clic en el .bat -> elige los archivos en el cuadro de dialogo.
#>

param(
    [switch]$NoPause,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Paths
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Cabecera que se muestra al arrancar.
function Write-Title {
    Write-Host ''
    Write-Host '  ============================================' -ForegroundColor Cyan
    Write-Host '   DESBLOQUEAR WORD  -  quitar proteccion edicion' -ForegroundColor Cyan
    Write-Host '  ============================================' -ForegroundColor Cyan
    Write-Host ''
}

# Cuadro de dialogo para elegir archivos (cuando no se arrastra ninguno).
# Devuelve las rutas seleccionadas, o un array vacio si se cancela.
function Get-FilesFromDialog {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = 'Elige los documentos de Word a desbloquear'
    $dlg.Filter = 'Documentos de Word (*.docx;*.docm)|*.docx;*.docm|Todos (*.*)|*.*'
    $dlg.Multiselect = $true
    $dlg.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dlg.FileNames
    }
    return @()
}

# Detecta si el archivo esta cifrado con contrasena de apertura.
# Truco: un .docx normal es un ZIP y empieza por "PK" (50 4B). Uno cifrado
# es un contenedor OLE/CFB y empieza por la firma D0 CF 11 E0. Miramos los
# 4 primeros bytes: si coinciden con la firma OLE, esta cifrado.
function Test-IsEncrypted {
    param([string]$File)
    $fs = [System.IO.File]::OpenRead($File)
    try {
        $b = New-Object byte[] 4
        [void]$fs.Read($b, 0, 4)
    } finally { $fs.Dispose() }
    return ($b[0] -eq 0xD0 -and $b[1] -eq 0xCF -and $b[2] -eq 0x11 -and $b[3] -eq 0xE0)
}

# Desbloquea UN archivo. Devuelve $true si lo modifico, $false en cualquier
# otro caso (no valido, ya sin proteccion, cifrado o error). Imprime el motivo.
function Unlock-One {
    param([string]$File)

    $name = Split-Path $File -Leaf
    Write-Host "  -> $name" -ForegroundColor White

    # --- Validaciones previas ---
    if (-not (Test-Path $File)) {
        Write-Host "     [X] No existe el archivo." -ForegroundColor Red
        return $false
    }
    $ext = [System.IO.Path]::GetExtension($File).ToLower()
    if ($ext -ne '.docx' -and $ext -ne '.docm') {
        Write-Host "     [X] No es .docx/.docm (es $ext). Omitido." -ForegroundColor Yellow
        return $false
    }
    if (Test-IsEncrypted $File) {
        Write-Host "     [X] Tiene CONTRASENA DE APERTURA (archivo cifrado)." -ForegroundColor Red
        Write-Host "         Eso necesita la contrasena; esta herramienta no la rompe." -ForegroundColor Red
        return $false
    }

    # Carpeta temporal unica donde extraer el ZIP del documento.
    $work = Join-Path $env:TEMP ("unlockdocx_" + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Force $work | Out-Null
        [System.IO.Compression.ZipFile]::ExtractToDirectory($File, $work)

        # La proteccion vive en word/settings.xml. Si no existe, no hay nada que quitar.
        $settings = Join-Path $work 'word\settings.xml'
        if (-not (Test-Path $settings)) {
            Write-Host "     [i] Sin word/settings.xml; no hay proteccion que quitar." -ForegroundColor Yellow
            return $false
        }

        # Borrar los elementos de proteccion (auto-cerrados, formato <... />).
        $xml = [System.IO.File]::ReadAllText($settings)
        $new = $xml
        $new = [regex]::Replace($new, '<w:documentProtection\b[^>]*/>', '')
        $new = [regex]::Replace($new, '<w:writeProtection\b[^>]*/>', '')

        # Si el XML no cambio, el documento no estaba protegido. No tocar nada.
        if ($new -eq $xml) {
            Write-Host "     [i] No tenia proteccion de edicion. Sin cambios." -ForegroundColor Yellow
            return $false
        }

        # Copia de seguridad junto al original ANTES de sobrescribir.
        # ChangeExtension(...,$null) deja "nombre." -> queda "nombreBACKUP.docx".
        $bak = [System.IO.Path]::ChangeExtension($File, $null) + 'BACKUP' + $ext
        if (-not (Test-Path $bak)) { Copy-Item $File $bak -Force }

        # Guardar el settings.xml ya limpio dentro de la carpeta extraida.
        [System.IO.File]::WriteAllText($settings, $new)

        # Volver a comprimir la carpeta sobre el archivo original.
        Remove-Item $File -Force
        [System.IO.Compression.ZipFile]::CreateFromDirectory(
            $work, $File,
            [System.IO.Compression.CompressionLevel]::Optimal, $false)

        Write-Host "     [OK] Desbloqueado. Copia: $(Split-Path $bak -Leaf)" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "     [X] Error: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    finally {
        # Limpiar siempre la carpeta temporal, pase lo que pase.
        if (Test-Path $work) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# ---- main ----
Write-Title

# Sin archivos arrastrados -> abrir el selector directamente (sin avisos).
$files = @($Paths | Where-Object { $_ })
if ($files.Count -eq 0) {
    $files = @(Get-FilesFromDialog)
}
if ($files.Count -eq 0) { return }   # cancelo el dialogo: salir sin ruido

$ok = 0
foreach ($f in $files) { if (Unlock-One $f) { $ok++ } }

Write-Host ''
Write-Host "  Hecho. Desbloqueados: $ok de $($files.Count)." -ForegroundColor Cyan

if (-not $NoPause) {
    Write-Host '  Pulsa una tecla para cerrar...' -ForegroundColor Gray
    try { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { }
}
