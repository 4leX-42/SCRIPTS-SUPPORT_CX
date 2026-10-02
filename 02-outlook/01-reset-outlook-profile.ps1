#Requires -Version 5.1

<#
.SYNOPSIS
    [ES] Rehace el perfil de Outlook clasico conservando los .pst y .ost y lo recrea con la misma cuenta.
    [EN] Rebuilds the classic Outlook profile keeping .pst and .ost files and recreates it with the same account.
.DESCRIPTION
    Pensado para reconstruir desde cero los perfiles de Outlook cuando el
    cliente deja de recibir correo en la bandeja de entrada y no se localiza
    la causa.

    Acciones que realiza:
      1. Cierra Outlook Classic (outlook.exe) si esta en ejecucion.
      2. Lee las cuentas de correo de los perfiles ANTES de borrarlos
         (accounts.txt en la carpeta de log).
      3. Hace copia de seguridad (.reg) de cada clave ANTES de borrarla.
      4. Elimina perfiles y cuentas (ubicacion moderna y heredada del registro).
      5. Borra el valor DefaultProfile.
      6. Limpia la cache de Autodiscover (registro + archivos XML en disco).
      7. Limpia credenciales de Office/Outlook/Exchange del Administrador de
         credenciales de Windows (causa habitual de fallos de autenticacion).
      8. NO toca *.pst / *.ost ni ningun archivo de datos: los inventaria y
         los deja intactos.
      9. Recrea un perfil vacio, lo deja por defecto y abre Outlook con el:
           - Si la cuenta coincide con el UPN de Windows activa ZeroConfigExchange
             SOLO mientras se crea la cuenta: Outlook la configura sola y como
             mucho pide la contrasena. Despues se retira el valor.
           - Si no coincide, Outlook abre el asistente y el correo queda en el
             portapapeles (Ctrl+V + contrasena).
     10. Registra todas las acciones en un log.

.PARAMETER FullReset
    Ademas de lo anterior, elimina la clave COMPLETA de Outlook
    (HKCU\...\Office\<ver>\Outlook), borrando TODA la configuracion del
    cliente (vistas, barras, opciones, firmas configuradas en registro...).
    Usar solo si se quiere un reinicio total del cliente.

.PARAMETER ClearAutoComplete
    Vacia tambien la cache de autocompletado / destinatarios sugeridos
    (carpeta RoamCache). Por defecto se conserva.

.PARAMETER Email
    Cuenta con la que recrear el perfil. Si se omite se usa la cuenta del
    perfil por defecto que se borra; si no hay, la identidad de Office y por
    ultimo el UPN de Windows.

.PARAMETER ProfileName
    Nombre del perfil nuevo. Por defecto 'Outlook'.

.PARAMETER NoRecreate
    Solo limpia, sin crear el perfil nuevo ni abrir Outlook (comportamiento antiguo).

.PARAMETER WaitSeconds
    Tiempo maximo esperando a que Outlook cree la cuenta antes de retirar
    ZeroConfigExchange. Por defecto 600.

.PARAMETER Force
    No pide confirmacion interactiva. Util para despliegue desatendido.

.PARAMETER WhatIf
    Simulacion: registra lo que haria pero NO borra ni crea nada.

.NOTES
    - EJECUTAR EN LA SESION DEL USUARIO AFECTADO. Las claves estan en HKCU
      (por usuario); si se ejecuta como otro usuario/admin se limpiaria el
      perfil equivocado. No ejecutar elevado: Outlook se abriria como admin.
    - NO requiere permisos de administrador.
    - El script muestra el usuario actual y la cuenta detectada al inicio.

.EXAMPLE
    # Simulacion (no borra nada, solo registra):
    powershell -ExecutionPolicy Bypass -File .\01-reset-outlook-profile.ps1 -WhatIf

.EXAMPLE
    # Limpieza estandar + perfil nuevo con la misma cuenta:
    powershell -ExecutionPolicy Bypass -File .\01-reset-outlook-profile.ps1

.EXAMPLE
    # Forzar la cuenta del perfil nuevo:
    powershell -ExecutionPolicy Bypass -File .\01-reset-outlook-profile.ps1 -Email nombre.apellido@dominio.com

.EXAMPLE
    # Reinicio total del cliente, sin preguntar:
    powershell -ExecutionPolicy Bypass -File .\01-reset-outlook-profile.ps1 -FullReset -Force
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$FullReset,
    [switch]$ClearAutoComplete,
    [string]$Email,
    [string]$ProfileName = 'Outlook',
    [switch]$NoRecreate,
    [int]$WaitSeconds = 600,
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
$mailRx    = '^[^@\s]+@[^@\s]+\.[^@\s]+$'

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
# Helpers de cuentas
# ---------------------------------------------------------------------------
function ConvertFrom-RegText {
    param($Value)
    # MAPI guarda 'Account Name' / 'Email' como REG_BINARY UTF-16LE terminado en nulo
    if ($Value -is [byte[]]) { return [Text.Encoding]::Unicode.GetString($Value).Trim([char]0).Trim() }
    if ($null -ne $Value)    { return ([string]$Value).Trim() }
    return ''
}

function Get-OutlookAccounts {
    param([string[]]$Roots)
    $list = @(); $i = 0
    foreach ($root in $Roots) {
        $def = (Get-ItemProperty -Path $root -Name 'DefaultProfile' -ErrorAction SilentlyContinue).DefaultProfile
        foreach ($p in (Get-ChildItem -Path "$root\Profiles" -ErrorAction SilentlyContinue)) {
            $accRoot = Join-Path $p.PSPath '9375CFF0413111d3B88A00104B2A6676'
            foreach ($a in (Get-ChildItem -Path $accRoot -ErrorAction SilentlyContinue)) {
                $props = Get-ItemProperty -Path $a.PSPath -ErrorAction SilentlyContinue
                if (-not $props) { continue }
                foreach ($n in @('Account Name', 'Email')) {
                    $mail = ConvertFrom-RegText $props.$n
                    if ($mail -notmatch $mailRx) { continue }
                    $i++
                    $list += New-Object psobject -Property @{
                        Email    = $mail.ToLower()
                        Profile  = $p.PSChildName
                        Default  = ($p.PSChildName -eq $def)
                        Exchange = ((ConvertFrom-RegText $props.clsid) -eq '{ED475418-B0D6-11D2-8C3B-00104B2A6676}')
                        Order    = $i
                    }
                    break
                }
            }
        }
    }
    $seen = @{}
    $list | Sort-Object @{ Expression = { -not $_.Default } }, @{ Expression = { -not $_.Exchange } }, Order |
        Where-Object { if ($seen.ContainsKey($_.Email)) { $false } else { $seen[$_.Email] = 1; $true } }
}

# ---------------------------------------------------------------------------
# Deteccion previa: versiones de Office y cuentas (solo lectura)
# ---------------------------------------------------------------------------
$officeRoots = @()
$officeBase  = 'HKCU:\Software\Microsoft\Office'
if (Test-Path $officeBase) {
    $officeRoots = @(Get-ChildItem $officeBase -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^\d+\.\d+$' -and (Test-Path "$officeBase\$($_.PSChildName)\Outlook") } |
        Sort-Object { [version]$_.PSChildName } -Descending |
        ForEach-Object { "$officeBase\$($_.PSChildName)\Outlook" })
}
$mainVer  = if ($officeRoots) { Split-Path (Split-Path $officeRoots[0] -Parent) -Leaf } else { '16.0' }
$accounts = @(Get-OutlookAccounts -Roots $officeRoots)

$upn = ''
try { $upn = ([string](& whoami.exe /upn 2>$null)).Trim().ToLower() } catch { }
if ($upn -notmatch $mailRx) { $upn = '' }

$emailSource = 'parametro -Email'
if (-not $Email -and $accounts) { $Email = $accounts[0].Email; $emailSource = "perfil '$($accounts[0].Profile)'" }
if (-not $Email) {
    $Email = Get-ChildItem "$officeBase\$mainVer\Common\Identity\Identities" -ErrorAction SilentlyContinue |
        ForEach-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).EmailAddress } |
        Where-Object { $_ -match $mailRx } | Select-Object -First 1
    $emailSource = 'identidad de Office'
}
if (-not $Email -and $upn) { $Email = $upn; $emailSource = 'UPN de Windows' }
if ($Email) { $Email = $Email.Trim().ToLower() }

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
foreach ($a in $accounts) {
    Write-Log ("Cuenta detectada: {0}  (perfil '{1}'{2})" -f $a.Email, $a.Profile, $(if ($a.Default) { ', por defecto' } else { '' })) 'INFO'
}
if ($NoRecreate)  { Write-Log 'Perfil nuevo   : NO (-NoRecreate)' 'INFO' }
elseif ($Email)   { Write-Log "Perfil nuevo   : '$ProfileName' con $Email  [origen: $emailSource]" 'INFO' }
else              { Write-Log "Perfil nuevo   : '$ProfileName' vacio (no se detecto ninguna cuenta)" 'WARN' }
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
# 2. Versiones y cuentas (guardadas antes de borrar nada)
# ---------------------------------------------------------------------------
Write-Log '--- 2. Versiones de Outlook y cuentas de los perfiles ---' 'INFO'
foreach ($root in $officeRoots) { Write-Log "Detectado: $root" 'INFO' }
if (-not $officeRoots) { Write-Log 'No se detectaron claves de Outlook bajo Office.' 'WARN' }
$accFile = Join-Path $logDir 'accounts.txt'
if ($accounts) {
    $accounts | ForEach-Object { "{0}`t{1}`t{2}" -f $_.Email, $_.Profile, $(if ($_.Default) { 'default' } else { '' }) } |
        Set-Content -Path $accFile -Encoding UTF8 -WhatIf:$false
    Write-Log "Cuentas guardadas en $accFile" 'OK'
    if ($accounts.Count -gt 1) {
        Write-Log "Solo se recrea la principal. Anadir a mano: $(($accounts | Select-Object -Skip 1 | ForEach-Object { $_.Email }) -join ', ')" 'WARN'
    }
} else {
    Write-Log 'No se encontraron cuentas en los perfiles actuales.' 'SKIP'
}

# ---------------------------------------------------------------------------
# 3. Eliminar perfiles, cuentas, DefaultProfile y Autodiscover por version
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
# 4. Borrar archivos XML de cache de Autodiscover en disco
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
# 5. Limpiar credenciales cacheadas (Administrador de credenciales Windows)
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
# 6. (Opcional) Vaciar cache de autocompletado / destinatarios (RoamCache)
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
# 7. Inventario de archivos de datos (SE CONSERVAN, no se tocan)
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
# 8. Recrear perfil y abrir Outlook con la cuenta detectada
# ---------------------------------------------------------------------------
$recreated = $false
if (-not $NoRecreate) {
    Write-Log '--- 8. Recreando perfil de Outlook ---' 'INFO'
    $olRoot   = "$officeBase\$mainVer\Outlook"
    $newProf  = "$olRoot\Profiles\$ProfileName"
    $adKey    = "$olRoot\AutoDiscover"
    $polZero  = (Get-ItemProperty "HKCU:\Software\Policies\Microsoft\Office\$mainVer\Outlook\AutoDiscover" -ErrorAction SilentlyContinue).ZeroConfigExchange -eq 1
    $useZero  = (-not $polZero) -and $Email -and $upn -and ($Email -eq $upn)
    $olExe    = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE' -ErrorAction SilentlyContinue).'(default)'
    if (-not $olExe -or -not (Test-Path $olExe)) { $olExe = 'outlook.exe' }

    if     ($polZero) { Write-Log 'ZeroConfigExchange ya llega por directiva: Outlook configurara la cuenta solo.' 'INFO' }
    elseif ($useZero) { Write-Log "La cuenta coincide con el UPN de Windows: configuracion automatica (ZeroConfigExchange temporal)." 'INFO' }
    elseif ($Email -and -not $upn) { Write-Log 'Equipo sin UPN de dominio: se abrira el asistente con el correo en el portapapeles.' 'INFO' }
    elseif ($Email)   { Write-Log "La cuenta no coincide con el UPN ($upn): se abrira el asistente con el correo en el portapapeles." 'INFO' }

    if ($WhatIfPreference) {
        Write-Log "[SIMULACION] Crearia $newProf y DefaultProfile='$ProfileName'" 'INFO'
        if ($useZero) { Write-Log "[SIMULACION] Pondria ZeroConfigExchange=1 en $adKey hasta que se cree la cuenta" 'INFO' }
        Write-Log "[SIMULACION] Abriria: $olExe /profile `"$ProfileName`"" 'INFO'
    } else {
        try {
            New-Item -Path $newProf -Force -ErrorAction Stop | Out-Null
            Set-ItemProperty -Path $olRoot -Name 'DefaultProfile' -Value $ProfileName -Type String -ErrorAction Stop
            Write-Log "Perfil vacio creado y por defecto: $ProfileName" 'OK'
            $recreated = $true
        } catch {
            Write-Log "Error creando el perfil: $($_.Exception.Message)" 'ERROR'
        }
    }

    if ($recreated) {
        if ($useZero) {
            New-Item -Path $adKey -Force | Out-Null
            New-ItemProperty -Path $adKey -Name 'ZeroConfigExchange' -Value 1 -PropertyType DWord -Force | Out-Null
        }
        if ($Email) {
            try { Set-Clipboard -Value $Email; Write-Log "Correo copiado al portapapeles: $Email" 'OK' } catch { }
        }
        try {
            Start-Process -FilePath $olExe -ArgumentList '/profile', "`"$ProfileName`"" -ErrorAction Stop
            Write-Log 'Outlook abierto con el perfil nuevo.' 'OK'
        } catch {
            Write-Log "No se pudo abrir Outlook: $($_.Exception.Message)" 'ERROR'
        }

        if ($useZero) {
            Write-Log "Esperando a que Outlook cree la cuenta (max $WaitSeconds s). Introduce la contrasena si la pide." 'INFO'
            $deadline = (Get-Date).AddSeconds($WaitSeconds)
            $created  = $false
            Start-Sleep -Seconds 10
            while ((Get-Date) -lt $deadline) {
                if (Get-ChildItem "$newProf\9375CFF0413111d3B88A00104B2A6676" -ErrorAction SilentlyContinue) { $created = $true; break }
                if (-not (Get-Process -Name 'outlook' -ErrorAction SilentlyContinue)) { break }
                Start-Sleep -Seconds 5
            }
            # Con ZeroConfigExchange activo no se pueden crear perfiles a mano: se retira siempre
            Remove-ItemProperty -Path $adKey -Name 'ZeroConfigExchange' -Force -ErrorAction SilentlyContinue
            if ($created) { Write-Log "Cuenta creada en el perfil '$ProfileName'. ZeroConfigExchange retirado." 'OK' }
            else          { Write-Log 'Outlook no creo la cuenta a tiempo. ZeroConfigExchange retirado: al reabrir Outlook saldra el asistente (Ctrl+V + contrasena).' 'WARN' }
        }
    }
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
if ($recreated -and $Email) {
    Write-Host "SIGUIENTE PASO: en Outlook, si pide la cuenta pega $Email (Ctrl+V)" -ForegroundColor Green
    Write-Host 'y escribe la contrasena. Si solo pide la contrasena, introducirla.' -ForegroundColor Green
} elseif ($recreated) {
    Write-Host 'SIGUIENTE PASO: en Outlook, escribe el correo del usuario y la contrasena.' -ForegroundColor Green
} else {
    Write-Host 'SIGUIENTE PASO: abrir Outlook -> asistente de nuevo perfil,' -ForegroundColor Green
    Write-Host 'o crear el perfil desde Panel de control > Mail (Correo).' -ForegroundColor Green
}
Write-Host 'Para revertir el registro: doble clic en los .reg de backup.' -ForegroundColor Green
