#Requires -Version 5.1

<#
.SYNOPSIS
    [ES] Rehace el perfil de Outlook clasico conservando los .pst y .ost.
    [EN] Rebuilds the classic Outlook profile while keeping .pst and .ost files.
.DESCRIPTION
    Pensado para reconstruir desde cero los perfiles de Outlook cuando el
    cliente deja de recibir correo en la bandeja de entrada y no se localiza
    la causa.

    Acciones que realiza:
      1. Cierra Outlook Classic (outlook.exe) si esta en ejecucion.
      2. Hace copia de seguridad (.reg) de cada clave ANTES de borrarla.
      3. Elimina perfiles y cuentas (ubicacion moderna y heredada del registro).
      4. Borra el valor DefaultProfile.
      5. Limpia la cache de Autodiscover (registro + archivos XML en disco).
      6. Limpia credenciales de Office/Outlook/Exchange del Administrador de
         credenciales de Windows (causa habitual de fallos de autenticacion).
      7. NO toca *.pst / *.ost ni ningun archivo de datos: los inventaria y
         los deja intactos.
      8. Registra todas las acciones en un log.

.PARAMETER FullReset
    Ademas de lo anterior, elimina la clave COMPLETA de Outlook
    (HKCU\...\Office\<ver>\Outlook), borrando TODA la configuracion del
    cliente (vistas, barras, opciones, firmas configuradas en registro...).
    Usar solo si se quiere un reinicio total del cliente.

.PARAMETER ClearAutoComplete
    Vacia tambien la cache de autocompletado / destinatarios sugeridos
    (carpeta RoamCache). Por defecto se conserva.

.PARAMETER Force
    No pide confirmacion interactiva. Util para despliegue desatendido.

.PARAMETER WhatIf
    Simulacion: registra lo que haria pero NO borra nada.

.NOTES
    - EJECUTAR EN LA SESION DEL USUARIO AFECTADO. Las claves estan en HKCU
      (por usuario); si se ejecuta como otro usuario/admin se limpiaria el
      perfil equivocado.
    - NO requiere permisos de administrador.
    - El script muestra el usuario actual al inicio: verificar que es correcto.

.EXAMPLE
    # Simulacion (no borra nada, solo registra):
    powershell -ExecutionPolicy Bypass -File .\Reset-OutlookClassic.ps1 -WhatIf

.EXAMPLE
    # Limpieza estandar (conserva .pst/.ost):
    powershell -ExecutionPolicy Bypass -File .\Reset-OutlookClassic.ps1

.EXAMPLE
    # Reinicio total del cliente, sin preguntar:
    powershell -ExecutionPolicy Bypass -File .\Reset-OutlookClassic.ps1 -FullReset -Force
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$FullReset,
    [switch]$ClearAutoComplete,
    [switch]$Force
)

# ---------------------------------------------------------------------------
# Preparacion: carpeta de trabajo, log y backup
# ---------------------------------------------------------------------------
$stamp     = Get-Date -Format 'yyyyMMdd_HHmmss'
$logDir    = Join-Path $env:TEMP "Outlook-Cleanup_$stamp"
$backupDir = Join-Path $logDir 'registry-backup'
New-Item -ItemType Directory -Path $backupDir -Force -WhatIf:$false | Out-Null
$logFile   = Join-Path $logDir 'cleanup.log'

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','OK','SKIP')] [string]$Level = 'INFO'
    )
    $line  = '{0} [{1}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level.PadRight(5), $Message
    $color = switch ($Level) {
        'ERROR' { 'Red' }    'WARN' { 'Yellow' } 'OK' { 'Green' }
        'SKIP'  { 'DarkGray' } default { 'Gray' }
    }
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $logFile -Value $line -Encoding UTF8 -WhatIf:$false
}

# ---------------------------------------------------------------------------
# Helpers de registro (con backup previo y soporte -WhatIf)
# ---------------------------------------------------------------------------
function Backup-RegKey {
    param([string]$Path)            # Ruta estilo PowerShell: HKCU:\Software\...
    if (-not (Test-Path $Path)) { return }
    $regPath = $Path.Replace(':', '')                       # -> HKCU\Software\...
    $safe    = ($Path -replace '[:\\]', '_')
    $out     = Join-Path $backupDir "$safe.reg"
    & reg.exe export "$regPath" "$out" /y *> $null
    if (Test-Path $out) { Write-Log "Backup -> $out" 'INFO' }
}

function Remove-RegKey {
    param([string]$Path, [string]$Desc)
    if (-not (Test-Path $Path)) { Write-Log "Omitido (no existe): $Desc" 'SKIP'; return }
    if ($WhatIfPreference)      { Write-Log "[SIMULACION] Eliminaria: $Desc" 'INFO'; return }
    Backup-RegKey -Path $Path
    try {
        Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
        Write-Log "Eliminado: $Desc" 'OK'
    } catch {
        Write-Log "Error al eliminar ${Desc}: $($_.Exception.Message)" 'ERROR'
    }
}

function Remove-RegValue {
    param([string]$Path, [string]$Name, [string]$Desc)
    if (-not (Test-Path $Path)) { Write-Log "Omitido (no existe ruta): $Desc" 'SKIP'; return }
    if ($null -eq (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue)) {
        Write-Log "Omitido (no existe valor): $Desc" 'SKIP'; return
    }
    if ($WhatIfPreference) { Write-Log "[SIMULACION] Borraria valor: $Desc" 'INFO'; return }
    Backup-RegKey -Path $Path
    try {
        Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop
        Write-Log "Valor borrado: $Desc" 'OK'
    } catch {
        Write-Log "Error en valor ${Desc}: $($_.Exception.Message)" 'ERROR'
    }
}

# ---------------------------------------------------------------------------
# Cabecera y confirmacion
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '===========================================================' -ForegroundColor Cyan
Write-Host '   LIMPIEZA DE PERFILES Y CUENTAS - OUTLOOK CLASSIC' -ForegroundColor Cyan
Write-Host '===========================================================' -ForegroundColor Cyan
Write-Host ''
Write-Log "Usuario actual : $env:USERDOMAIN\$env:USERNAME" 'INFO'
Write-Log "Equipo         : $env:COMPUTERNAME" 'INFO'
Write-Log "Carpeta de log : $logDir" 'INFO'
Write-Log "Modo FullReset : $($FullReset.IsPresent)  |  AutoComplete: $($ClearAutoComplete.IsPresent)  |  WhatIf: $($WhatIfPreference)" 'INFO'
Write-Host ''
Write-Host 'Se CONSERVAN los archivos de datos (.pst / .ost).' -ForegroundColor Green
Write-Host 'Se ELIMINAN perfiles, cuentas, Autodiscover y credenciales cacheadas.' -ForegroundColor Yellow
Write-Host ''

if (-not $Force -and -not $WhatIfPreference) {
    Write-Host "Verifica que el usuario de arriba ($env:USERNAME) es el AFECTADO." -ForegroundColor Yellow
    $answer = Read-Host 'Continuar con la limpieza? (S/N)'
    if ($answer -notmatch '^[sSyY]$') {
        Write-Log 'Cancelado por el usuario.' 'WARN'
        return
    }
}

# ---------------------------------------------------------------------------
# 1. Cerrar Outlook Classic
# ---------------------------------------------------------------------------
Write-Log '--- 1. Cerrando Outlook Classic ---' 'INFO'
$procs = Get-Process -Name 'outlook' -ErrorAction SilentlyContinue
if (-not $procs) {
    Write-Log 'Outlook no esta en ejecucion.' 'SKIP'
} elseif ($WhatIfPreference) {
    Write-Log "[SIMULACION] Cerraria Outlook (PID: $($procs.Id -join ', '))" 'INFO'
} else {
    Write-Log "Cerrando Outlook (PID: $($procs.Id -join ', '))..." 'INFO'
    $procs | ForEach-Object { $_.CloseMainWindow() | Out-Null }   # cierre limpio
    Start-Sleep -Seconds 3
    $procs = Get-Process -Name 'outlook' -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Log 'Cierre limpio fallido. Forzando cierre...' 'WARN'
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    if (Get-Process -Name 'outlook' -ErrorAction SilentlyContinue) {
        Write-Log 'NO se pudo cerrar Outlook. Cierralo manualmente y reintenta.' 'ERROR'
    } else {
        Write-Log 'Outlook cerrado.' 'OK'
    }
}

# ---------------------------------------------------------------------------
# 2. Detectar versiones de Office instaladas (16.0 = 2016/2019/2021/365)
# ---------------------------------------------------------------------------
Write-Log '--- 2. Detectando versiones de Outlook en el registro ---' 'INFO'
$officeRoots = @()
$officeBase  = 'HKCU:\Software\Microsoft\Office'
if (Test-Path $officeBase) {
    Get-ChildItem $officeBase -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^\d+\.\d+$' } |
        ForEach-Object {
            $ver = $_.PSChildName
            $ok  = "HKCU:\Software\Microsoft\Office\$ver\Outlook"
            if (Test-Path $ok) {
                $officeRoots += $ok
                Write-Log "Detectado: Office $ver" 'INFO'
            }
        }
}
if (-not $officeRoots) { Write-Log 'No se detectaron claves de Outlook bajo Office.' 'WARN' }

# ---------------------------------------------------------------------------
# 3-4. Eliminar perfiles, cuentas, DefaultProfile y Autodiscover por version
# ---------------------------------------------------------------------------
Write-Log '--- 3. Eliminando perfiles, cuentas y Autodiscover (registro) ---' 'INFO'
foreach ($root in $officeRoots) {
    Write-Log "Procesando: $root" 'INFO'
    Remove-RegKey   -Path "$root\Profiles"     -Desc "Perfiles y cuentas ($root\Profiles)"
    Remove-RegKey   -Path "$root\AutoDiscover" -Desc "Cache Autodiscover ($root\AutoDiscover)"
    Remove-RegValue -Path $root -Name 'DefaultProfile' -Desc "DefaultProfile ($root)"
    if ($FullReset) {
        Remove-RegKey -Path $root -Desc "Clave Outlook COMPLETA ($root)  [FullReset]"
    }
}

# Ubicacion heredada de perfiles (Outlook antiguo / MAPI clasico)
$legacy = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows Messaging Subsystem\Profiles'
Remove-RegKey -Path $legacy -Desc 'Perfiles heredados (Windows Messaging Subsystem)'

# ---------------------------------------------------------------------------
# 5. Borrar archivos XML de cache de Autodiscover en disco
#    (solo *.xml de autodiscover; NUNCA .pst/.ost)
# ---------------------------------------------------------------------------
Write-Log '--- 4. Limpiando cache de Autodiscover en disco ---' 'INFO'
$outlookData = Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook'
if (Test-Path $outlookData) {
    $xmlFiles = Get-ChildItem -Path $outlookData -Filter '*autodiscover*.xml' -File -ErrorAction SilentlyContinue
    if (-not $xmlFiles) {
        Write-Log 'Sin archivos XML de Autodiscover en cache.' 'SKIP'
    }
    foreach ($f in $xmlFiles) {
        if ($WhatIfPreference) { Write-Log "[SIMULACION] Borraria XML: $($f.Name)" 'INFO'; continue }
        try {
            Remove-Item $f.FullName -Force -ErrorAction Stop
            Write-Log "XML Autodiscover borrado: $($f.Name)" 'OK'
        } catch {
            Write-Log "Error al borrar $($f.Name): $($_.Exception.Message)" 'ERROR'
        }
    }
} else {
    Write-Log "Carpeta no encontrada: $outlookData" 'SKIP'
}

# ---------------------------------------------------------------------------
# 6. Limpiar credenciales cacheadas (Administrador de credenciales Windows)
#    Causa muy habitual de fallos de autenticacion / no recibir correo.
# ---------------------------------------------------------------------------
Write-Log '--- 5. Limpiando credenciales de Office/Outlook/Exchange ---' 'INFO'
$credPatterns = @('MicrosoftOffice', 'Outlook', 'Exchange', 'outlook.office365.com', 'autodiscover', 'msoidssp')
try {
    $targets = cmdkey /list |
        Select-String -Pattern 'Target:' |
        ForEach-Object { ($_ -replace '.*Target:\s*', '').Trim() } |
        Where-Object { $_ }
    $matched = $targets | Where-Object {
        $t = $_; ($credPatterns | Where-Object { $t -match [regex]::Escape($_) })
    }
    if (-not $matched) {
        Write-Log 'No se encontraron credenciales relacionadas.' 'SKIP'
    }
    foreach ($t in $matched) {
        if ($WhatIfPreference) { Write-Log "[SIMULACION] Borraria credencial: $t" 'INFO'; continue }
        & cmdkey "/delete:$t" *> $null
        if ($LASTEXITCODE -eq 0) { Write-Log "Credencial borrada: $t" 'OK' }
        else                     { Write-Log "No se pudo borrar credencial: $t" 'WARN' }
    }
} catch {
    Write-Log "Error procesando credenciales: $($_.Exception.Message)" 'WARN'
}

# ---------------------------------------------------------------------------
# 7. (Opcional) Vaciar cache de autocompletado / destinatarios (RoamCache)
# ---------------------------------------------------------------------------
if ($ClearAutoComplete) {
    Write-Log '--- 6. Vaciando cache de autocompletado (RoamCache) ---' 'INFO'
    $roam = Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook\RoamCache'
    if (Test-Path $roam) {
        if ($WhatIfPreference) {
            Write-Log '[SIMULACION] Vaciaria RoamCache' 'INFO'
        } else {
            try {
                Get-ChildItem $roam -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
                Write-Log 'RoamCache (autocompletado) vaciada.' 'OK'
            } catch {
                Write-Log "Error en RoamCache: $($_.Exception.Message)" 'WARN'
            }
        }
    } else {
        Write-Log 'RoamCache no encontrada.' 'SKIP'
    }
}

# ---------------------------------------------------------------------------
# 8. Inventario de archivos de datos (SE CONSERVAN, no se tocan)
# ---------------------------------------------------------------------------
Write-Log '--- 7. Inventario de archivos de datos (SE CONSERVAN) ---' 'INFO'
$dataDirs = @(
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook'),
    (Join-Path $env:USERPROFILE  'Documents\Outlook Files'),
    (Join-Path $env:USERPROFILE  'Documents')
) | Select-Object -Unique

$dataFiles = @()
foreach ($d in $dataDirs) {
    if (Test-Path $d) {
        $dataFiles += Get-ChildItem -Path $d -Include '*.pst', '*.ost' -File -Recurse -ErrorAction SilentlyContinue
    }
}
$dataFiles = $dataFiles | Sort-Object FullName -Unique
if ($dataFiles) {
    foreach ($f in $dataFiles) {
        Write-Log ('  CONSERVADO: {0} ({1:N1} MB)' -f $f.FullName, ($f.Length / 1MB)) 'INFO'
    }
} else {
    Write-Log '  No se encontraron .pst/.ost en las rutas habituales.' 'WARN'
}

# ---------------------------------------------------------------------------
# Resumen final
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '===========================================================' -ForegroundColor Cyan
Write-Log 'LIMPIEZA FINALIZADA.' 'OK'
Write-Host "  Log           : $logFile" -ForegroundColor Cyan
Write-Host "  Backups (.reg): $backupDir" -ForegroundColor Cyan
Write-Host '===========================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'SIGUIENTE PASO: abrir Outlook -> asistente de nuevo perfil,' -ForegroundColor Green
Write-Host 'o crear el perfil desde Panel de control > Mail (Correo).' -ForegroundColor Green
Write-Host 'Para revertir el registro: doble clic en los .reg de backup.' -ForegroundColor Green
