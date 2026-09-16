<#
.SYNOPSIS
    [ES] Desactiva extensiones de shell por CLSID de forma reversible. DryRun por defecto.
    [EN] Disables shell extensions by CLSID, reversibly. DryRun by default.

.DESCRIPTION
    Windows ofrece una lista de bloqueo oficial de extensiones de shell:

        HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked

    Un CLSID presente ahi (valor REG_SZ, el dato puede ir vacio o con una nota)
    deja de cargarse en los procesos que usan el shell: Explorador, dialogos de
    abrir/guardar, Outlook, etc. Es el metodo soportado y reversible: no se toca
    el registro del producto, no se desinstala y se revierte borrando el valor.

    Uso tipico: 02-test-file-picker-hang.ps1 devuelve una lista corta de DLL de
    terceros cargados por el picker; se bloquean sus CLSID, se reinicia el shell,
    se prueba. Si deja de colgarse, se desbloquean de uno en uno hasta dar con el
    responsable, y solo entonces se actualiza o desinstala ese producto.

    Requiere administrador (escribe en HKLM).

.PARAMETER Clsid
    Uno o varios CLSID entre llaves. Ejemplo: '{B5DB2D80-...}','{0C1A...}'

.PARAMETER ClsidFile
    Fichero de texto con un CLSID por linea (lineas vacias y # ignoradas).

.PARAMETER DesdeCsv
    CSV generado por 01-diagnose-file-picker.ps1 (-shell-extensions.csv). Toma los
    CLSID cuya columna EsMicrosoft sea False. Combinado con -FiltroDll acota.

.PARAMETER FiltroDll
    Expresion regular sobre la ruta del DLL para filtrar lo que viene de -DesdeCsv.
    Ejemplo: -FiltroDll 'imanage|adobe'

.PARAMETER Quitar
    Desbloquea en vez de bloquear (borra el valor de la clave Blocked).

.PARAMETER Listar
    Solo muestra lo que hay bloqueado ahora mismo y sale. No escribe.

.PARAMETER Execute
    Aplica los cambios. Sin este parametro es dry-run.

.PARAMETER ReiniciarExplorer
    Reinicia explorer.exe al terminar. Las aplicaciones ya abiertas (Outlook)
    mantienen el DLL cargado: hay que cerrarlas y volver a abrirlas.

.PARAMETER BackupDir
    Donde dejar la copia .reg de la clave Blocked. Por defecto %TEMP%\FilePickerDiag.

.EXAMPLE
    .\04-block-shell-extension.ps1 -Listar
.EXAMPLE
    .\04-block-shell-extension.ps1 -Clsid '{12345678-1234-1234-1234-123456789012}'
.EXAMPLE
    .\04-block-shell-extension.ps1 -DesdeCsv ..\..\exports\filepicker-PC-20260916-1100-shell-extensions.csv -FiltroDll 'imanage' -Execute -ReiniciarExplorer
.EXAMPLE
    .\04-block-shell-extension.ps1 -Clsid '{1234...}' -Quitar -Execute

.NOTES
    Solicitante: soporte IT   Motivo: aislamiento del cuelgue del selector de archivos
    Reversible: si (-Quitar, y copia .reg automatica de la clave completa).
    Requiere: administrador local.
#>
[CmdletBinding()]
param(
    [string[]]$Clsid,
    [string]$ClsidFile,
    [string]$DesdeCsv,
    [string]$FiltroDll,
    [switch]$Quitar,
    [switch]$Listar,
    [switch]$Execute,
    [switch]$ReiniciarExplorer,
    [string]$Motivo = 'Aislamiento de cuelgue del File Picker',
    [string]$BackupDir
)
$ErrorActionPreference = 'Stop'

$clavePS  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'
$claveReg = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'

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

function Get-NombreClsid {
    param([string]$C)
    foreach ($raiz in @('Registry::HKEY_CLASSES_ROOT\CLSID','Registry::HKEY_CLASSES_ROOT\WOW6432Node\CLSID')) {
        $k = Join-Path $raiz $C
        if (-not (Test-Path $k)) { continue }
        $n = (Get-ItemProperty -Path $k -ErrorAction SilentlyContinue).'(default)'
        $d = (Get-ItemProperty -Path (Join-Path $k 'InProcServer32') -ErrorAction SilentlyContinue).'(default)'
        return [pscustomobject]@{ Nombre = $n; Dll = $d }
    }
    return [pscustomobject]@{ Nombre = '(no registrado)'; Dll = '' }
}

# ------------------------------------------------------------------- listar
Write-Host ''
Write-Host '############################################################' -ForegroundColor White
Write-Host '  Bloqueo reversible de extensiones de shell' -ForegroundColor White
Write-Host '############################################################' -ForegroundColor White
Write-Host ''
Write-Host '  Actualmente bloqueadas:'
if (Test-Path $clavePS) {
    $actuales = @((Get-Item $clavePS).Property)
    if ($actuales.Count) {
        $actuales | ForEach-Object {
            $i = Get-NombreClsid $_
            Write-Host ('   ' + $_ + '  ' + $i.Nombre + '  ' + $i.Dll)
        }
    } else { Write-Host '   (ninguna)' }
} else {
    $actuales = @()
    Write-Host '   (la clave Blocked no existe todavia)'
}
if ($Listar) { Write-Host ''; return }

# ------------------------------------------------------------ objetivos
$objetivos = New-Object System.Collections.Generic.List[string]
if ($Clsid) { foreach ($c in $Clsid) { $objetivos.Add($c.Trim()) } }
if ($ClsidFile) {
    if (-not (Test-Path -LiteralPath $ClsidFile)) { throw ('No existe: ' + $ClsidFile) }
    foreach ($l in (Get-Content -LiteralPath $ClsidFile)) {
        $t = $l.Trim()
        if ($t -and $t -notmatch '^#') { $objetivos.Add($t) }
    }
}
if ($DesdeCsv) {
    if (-not (Test-Path -LiteralPath $DesdeCsv)) { throw ('No existe: ' + $DesdeCsv) }
    $filas = @(Import-Csv -LiteralPath $DesdeCsv | Where-Object { $_.EsMicrosoft -eq 'False' })
    if ($FiltroDll) { $filas = @($filas | Where-Object { $_.Dll -match $FiltroDll }) }
    foreach ($f in ($filas | Sort-Object Clsid -Unique)) { $objetivos.Add($f.Clsid) }
}

$objetivos = @($objetivos | Where-Object { $_ -match '^\{[0-9A-Fa-f-]{36}\}$' } | Sort-Object -Unique)
if (-not $objetivos.Count) {
    Write-Host ''
    Write-Host '  No hay CLSID validos que procesar. Usar -Clsid, -ClsidFile o -DesdeCsv.' -ForegroundColor Yellow
    Write-Host '  (Formato esperado: {XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX})' -ForegroundColor Yellow
    Write-Host ''
    return
}

$accion = 'BLOQUEAR'
if ($Quitar) { $accion = 'DESBLOQUEAR' }
$modo = 'DRY-RUN'
if ($Execute) { $modo = 'EXECUTE' }

Write-Host ''
Write-Host ('== PLAN: ' + $accion + ' (' + $modo + ') ==') -ForegroundColor Cyan
$plan = foreach ($c in $objetivos) {
    $i  = Get-NombreClsid $c
    $ya = ($actuales -contains $c)
    $est = 'no bloqueado'
    if ($ya) { $est = 'YA bloqueado' }
    [pscustomobject]@{ Clsid = $c; Nombre = $i.Nombre; Dll = $i.Dll; Estado = $est }
}
$plan | Format-Table -AutoSize | Out-String -Width 240 | Write-Host
Write-Host ('  Afectados  : ' + $objetivos.Count + ' CLSID')
Write-Host  '  Alcance    : HKLM, todo el equipo y todos los usuarios'
Write-Host  '  Riesgo     : la funcionalidad de esa extension (menus, iconos, integracion DMS)'
Write-Host  '               deja de estar disponible hasta desbloquearla. No desinstala nada.'
Write-Host  '  Reversible : si, con -Quitar o reimportando la copia .reg'

$idn     = [Security.Principal.WindowsIdentity]::GetCurrent()
$esAdmin = (New-Object Security.Principal.WindowsPrincipal($idn)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $esAdmin) {
    Write-Host ''
    Write-Host '  Se necesita PowerShell como administrador para escribir en HKLM.' -ForegroundColor Red
    if ($Execute) { return }
}

if (-not $Execute) {
    Write-Host ''
    Write-Host '  DRY-RUN: no se ha cambiado nada. Anadir -Execute para aplicar.' -ForegroundColor Yellow
    Write-Host ''
    return
}

# --------------------------------------------------------------- ejecucion
$BackupDir = Resolve-BackupDir $BackupDir
$stamp     = Get-Date -Format 'yyyyMMdd-HHmm'
$backup    = Join-Path $BackupDir ('shellext-blocked-backup-' + $stamp + '.reg')
$logDir    = $BackupDir
$trans     = $null
if (Test-Path $logDir) {
    $trans = Join-Path $logDir ($stamp + '-block-shellextension.log')
    Start-Transcript -Path $trans -Force | Out-Null
    Write-Host ('  Motivo: ' + $Motivo + '   Usuario: ' + $env:USERNAME)
}
try {
    if (Test-Path $clavePS) {
        & reg.exe export $claveReg $backup /y | Out-Null
        if (Test-Path $backup) { Write-Host ('  Copia de seguridad: ' + $backup) -ForegroundColor Green }
    } else {
        New-Item -Path $clavePS -Force | Out-Null
        Write-Host '  Clave Blocked creada.' -ForegroundColor Green
    }

    foreach ($c in $objetivos) {
        if ($Quitar) {
            if ((Get-Item $clavePS).Property -contains $c) {
                Remove-ItemProperty -Path $clavePS -Name $c -Force
                Write-Host ('  Desbloqueado: ' + $c) -ForegroundColor Green
            } else {
                Write-Host ('  No estaba bloqueado: ' + $c) -ForegroundColor DarkGray
            }
        } else {
            New-ItemProperty -Path $clavePS -Name $c -Value $Motivo -PropertyType String -Force | Out-Null
            Write-Host ('  Bloqueado: ' + $c) -ForegroundColor Green
        }
    }

    if ($ReiniciarExplorer) {
        Write-Host '  Reiniciando explorer.exe ...'
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        if (-not @(Get-Process explorer -ErrorAction SilentlyContinue).Count) { Start-Process explorer.exe }
    }

    # verificacion contra el registro, no contra el codigo de retorno
    $final = @((Get-Item $clavePS).Property)
    Write-Host ''
    Write-Host '  Estado verificado de la clave Blocked:'
    if ($final.Count) { $final | ForEach-Object { Write-Host ('   ' + $_) } } else { Write-Host '   (vacia)' }
    $ok = $true
    foreach ($c in $objetivos) {
        $dentro = ($final -contains $c)
        if ($Quitar -and $dentro)        { $ok = $false; Write-Host ('  FALLO: sigue bloqueado ' + $c) -ForegroundColor Red }
        if (-not $Quitar -and -not $dentro) { $ok = $false; Write-Host ('  FALLO: no se bloqueo ' + $c) -ForegroundColor Red }
    }
    if ($ok) { Write-Host '  Verificado: el registro refleja lo pedido.' -ForegroundColor Green }

    Write-Host ''
    Write-Host '  Importante: Outlook y demas aplicaciones ya abiertas conservan el DLL en' -ForegroundColor Yellow
    Write-Host '  memoria. Cerrarlas del todo y volver a abrirlas antes de dar por buena la prueba.' -ForegroundColor Yellow
    Write-Host ''
} finally {
    if ($trans) { Stop-Transcript | Out-Null }
}
