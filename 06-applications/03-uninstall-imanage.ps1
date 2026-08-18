#requires -version 5.1

<#
.SYNOPSIS
    [ES] Desinstala iManage Work Desktop por completo, con sus complementos de Office.
    [EN] Fully uninstalls iManage Work Desktop along with its Office add-ins.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'SilentlyContinue'
$ConfirmPreference = 'None'

# =========================
# CONFIG
# =========================
$LogRoot = "C:\Scripts\Logs"
$LogPath = Join-Path $LogRoot ("Remove-iManage_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO','OK','WARN','ERR')]
        [string]$Level = 'INFO'
    )

    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"

    Add-Content -Path $LogPath -Value $line

    $color = switch ($Level) {
        'INFO' { 'Cyan' }
        'OK'   { 'Green' }
        'WARN' { 'Yellow' }
        'ERR'  { 'Red' }
    }

    Write-Host $line -ForegroundColor $color
}

function Remove-PathSafe {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        Write-Log "Encontrada ruta: $Path" 'INFO'
        if ($PSCmdlet.ShouldProcess($Path, 'Eliminar carpeta/archivo')) {
            try {
                Remove-Item -LiteralPath $Path -Recurse -Force -Confirm:$false -ErrorAction Stop
                Write-Log "Eliminado: $Path" 'OK'
            }
            catch {
                Write-Log "No se pudo eliminar: ${Path} | $($_.Exception.Message)" 'ERR'
            }
        }
    }
    else {
        Write-Log "[NO ESTA] $Path" 'INFO'
    }
}

function Remove-RegistryKeySafe {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        Write-Log "Encontrada clave: $Path" 'INFO'
        if ($PSCmdlet.ShouldProcess($Path, 'Eliminar clave de registro')) {
            try {
                Remove-Item -LiteralPath $Path -Recurse -Force -Confirm:$false -ErrorAction Stop
                Write-Log "Eliminada clave: $Path" 'OK'
            }
            catch {
                Write-Log "No se pudo eliminar clave: ${Path} | $($_.Exception.Message)" 'ERR'
            }
        }
    }
    else {
        Write-Log "[NO ESTA] $Path" 'INFO'
    }
}

function Stop-ProcessesByPattern {
    param(
        [string[]]$Patterns
    )

    $allProcs = Get-Process -ErrorAction SilentlyContinue
    foreach ($proc in $allProcs) {
        foreach ($pattern in $Patterns) {
            if ($proc.ProcessName -like $pattern) {
                Write-Log "Proceso detectado: $($proc.ProcessName) (PID $($proc.Id))" 'WARN'
                if ($PSCmdlet.ShouldProcess($proc.ProcessName, 'Detener proceso')) {
                    try {
                        Stop-Process -Id $proc.Id -Force -Confirm:$false -ErrorAction Stop
                        Write-Log "Proceso detenido: $($proc.ProcessName)" 'OK'
                    }
                    catch {
                        Write-Log "No se pudo detener $($proc.ProcessName): $($_.Exception.Message)" 'ERR'
                    }
                }
                break
            }
        }
    }
}

function Stop-ServicesByPattern {
    param(
        [string[]]$Patterns
    )

    $services = Get-Service -ErrorAction SilentlyContinue
    foreach ($svc in $services) {
        foreach ($pattern in $Patterns) {
            if ($svc.Name -like $pattern -or $svc.DisplayName -like $pattern) {
                Write-Log "Servicio detectado: $($svc.Name) / $($svc.DisplayName)" 'WARN'
                if ($PSCmdlet.ShouldProcess($svc.Name, 'Detener servicio')) {
                    try {
                        if ($svc.Status -ne 'Stopped') {
                            Stop-Service -Name $svc.Name -Force -Confirm:$false -ErrorAction Stop
                            Write-Log "Servicio detenido: $($svc.Name)" 'OK'
                        }
                        else {
                            Write-Log "[YA PARADO] $($svc.Name)" 'INFO'
                        }
                    }
                    catch {
                        Write-Log "No se pudo detener servicio $($svc.Name): $($_.Exception.Message)" 'ERR'
                    }
                }
                break
            }
        }
    }
}

function Get-UninstallEntries {
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $entries = foreach ($root in $roots) {
        Get-ItemProperty -Path $root -ErrorAction SilentlyContinue
    }

    $entries | Where-Object {
        $_.DisplayName -and (
            $_.DisplayName -match 'iManage' -or
            $_.DisplayName -match 'WorkSite' -or
            $_.Publisher   -match 'iManage'
        )
    }
}

function Invoke-UninstallEntry {
    param(
        [Parameter(Mandatory)]
        $App
    )

    $displayName = $App.DisplayName
    $uninstallString = $App.UninstallString
    $quietString = $App.QuietUninstallString

    Write-Log "Aplicacion detectada: $displayName" 'INFO'

    $cmd = $null
    $args = $null

    if ($quietString) {
        Write-Log "Usando QuietUninstallString para: $displayName" 'INFO'
        $raw = $quietString.Trim()
    }
    elseif ($uninstallString) {
        Write-Log "Usando UninstallString para: $displayName" 'INFO'
        $raw = $uninstallString.Trim()
    }
    else {
        Write-Log "No hay cadena de desinstalacion para: $displayName" 'WARN'
        return
    }

    if ($raw -match 'MsiExec(\.exe)?\s+.*?({[A-Z0-9\-]+})') {
        $productCode = $Matches[2]
        $cmd = 'msiexec.exe'
        $args = "/x $productCode /qn /norestart"
    }
    elseif ($raw -match '^"([^"]+)"\s*(.*)$') {
        $cmd = $Matches[1]
        $args = $Matches[2]
    }
    else {
        $parts = $raw -split '\s+', 2
        $cmd = $parts[0]
        $args = if ($parts.Count -gt 1) { $parts[1] } else { '' }
    }

    if ($cmd -match 'msiexec(\.exe)?$') {
        if ($args -match '/I\s*({[A-Z0-9\-]+})') {
            $guid = $Matches[1]
            $args = "/x $guid /qn /norestart"
        }
        elseif ($args -notmatch '/x' -and $args -notmatch '/X') {
            $args = "$args /qn /norestart"
        }
    }

    if ($PSCmdlet.ShouldProcess($displayName, 'Desinstalar aplicacion')) {
        try {
            Write-Log "Ejecutando: $cmd $args" 'WARN'
            $p = Start-Process -FilePath $cmd -ArgumentList $args -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
            Write-Log "Codigo de salida para '$displayName': $($p.ExitCode)" 'INFO'

            if ($p.ExitCode -eq 0) {
                Write-Log "Desinstalado correctamente: $displayName" 'OK'
            }
            else {
                Write-Log "Desinstalacion finalizada con codigo $($p.ExitCode): $displayName" 'WARN'
            }
        }
        catch {
            Write-Log "Error desinstalando '${displayName}': $($_.Exception.Message)" 'ERR'
        }
    }
}

function Remove-OfficeAddins {
    Write-Log "Revisando add-ins de Office relacionados con iManage..." 'INFO'

    $officeAddinRoots = @(
        'HKCU:\Software\Microsoft\Office\Outlook\Addins',
        'HKCU:\Software\Microsoft\Office\Word\Addins',
        'HKCU:\Software\Microsoft\Office\Excel\Addins',
        'HKLM:\Software\Microsoft\Office\Outlook\Addins',
        'HKLM:\Software\Microsoft\Office\Word\Addins',
        'HKLM:\Software\Microsoft\Office\Excel\Addins',
        'HKLM:\Software\WOW6432Node\Microsoft\Office\Outlook\Addins',
        'HKLM:\Software\WOW6432Node\Microsoft\Office\Word\Addins',
        'HKLM:\Software\WOW6432Node\Microsoft\Office\Excel\Addins'
    )

    foreach ($root in $officeAddinRoots) {
        if (Test-Path $root) {
            Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
                $name = $_.PSChildName
                if ($name -match 'iManage|WorkSite') {
                    Write-Log "Add-in detectado: $name en $root" 'WARN'
                    if ($PSCmdlet.ShouldProcess($_.PSPath, 'Eliminar add-in Office')) {
                        try {
                            Remove-Item -LiteralPath $_.PSPath -Recurse -Force -Confirm:$false -ErrorAction Stop
                            Write-Log "Add-in eliminado: $name" 'OK'
                        }
                        catch {
                            Write-Log "No se pudo eliminar add-in ${name}: $($_.Exception.Message)" 'ERR'
                        }
                    }
                }
            }
        }
    }
}

function Remove-ScheduledTasksByName {
    Write-Log "Revisando tareas programadas relacionadas con iManage..." 'INFO'
    try {
        $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
            $_.TaskName -match 'iManage|WorkSite' -or $_.TaskPath -match 'iManage|WorkSite'
        }

        foreach ($task in $tasks) {
            $fullTask = "$($task.TaskPath)$($task.TaskName)"
            Write-Log "Tarea detectada: $fullTask" 'WARN'
            if ($PSCmdlet.ShouldProcess($fullTask, 'Eliminar tarea programada')) {
                try {
                    Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction Stop
                    Write-Log "Tarea eliminada: $fullTask" 'OK'
                }
                catch {
                    Write-Log "No se pudo eliminar tarea ${fullTask}: $($_.Exception.Message)" 'ERR'
                }
            }
        }
    }
    catch {
        Write-Log "No se pudieron revisar las tareas programadas: $($_.Exception.Message)" 'ERR'
    }
}

Write-Log "========================================" 'INFO'
Write-Log "INICIO DESINSTALACION COMPLETA IMANAGE" 'INFO'
Write-Log "Equipo: $env:COMPUTERNAME" 'INFO'
Write-Log "Usuario: $env:USERNAME" 'INFO'
Write-Log "Log: $LogPath" 'INFO'
Write-Log "========================================" 'INFO'

$processPatterns = @(
    'imanage*',
    'imdrive*',
    'imwork*',
    'worksite*',
    'iw*'
)
Stop-ProcessesByPattern -Patterns $processPatterns

$servicePatterns = @(
    '*iManage*',
    '*WorkSite*',
    '*imDrive*'
)
Stop-ServicesByPattern -Patterns $servicePatterns

Write-Log "Buscando productos instalados relacionados con iManage..." 'INFO'
$apps = Get-UninstallEntries

if ($apps) {
    foreach ($app in $apps | Sort-Object DisplayName -Unique) {
        Invoke-UninstallEntry -App $app
    }
}
else {
    Write-Log "No se encontraron entradas de desinstalacion de iManage/WorkSite." 'WARN'
}

Stop-ProcessesByPattern -Patterns $processPatterns

Write-Log "Eliminando carpetas residuales..." 'INFO'

$pathsToRemove = @(
    "$env:LOCALAPPDATA\iManage",
    "$env:APPDATA\iManage",
    "$env:LOCALAPPDATA\WorkSite",
    "$env:APPDATA\WorkSite",
    "$env:LOCALAPPDATA\IMANAGE",
    "$env:APPDATA\IMANAGE",
    "$env:LOCALAPPDATA\iManage Work",
    "$env:APPDATA\iManage Work",
    "$env:LOCALAPPDATA\iManage Drive",
    "$env:APPDATA\iManage Drive",
    "$env:USERPROFILE\AppData\Local\iManage",
    "$env:USERPROFILE\AppData\Roaming\iManage",
    "$env:USERPROFILE\AppData\Local\WorkSite",
    "$env:USERPROFILE\AppData\Roaming\WorkSite",
    "C:\Program Files\iManage",
    "C:\Program Files (x86)\iManage",
    "C:\ProgramData\iManage",
    "C:\ProgramData\WorkSite"
)

$pathsToRemove | Select-Object -Unique | ForEach-Object {
    Remove-PathSafe -Path $_
}

Write-Log "Eliminando claves de registro..." 'INFO'

$regKeys = @(
    'HKCU:\Software\iManage',
    'HKCU:\Software\WorkSite',
    'HKCU:\Software\Classes\iManage',
    'HKLM:\Software\iManage',
    'HKLM:\Software\WorkSite',
    'HKLM:\Software\WOW6432Node\iManage',
    'HKLM:\Software\WOW6432Node\WorkSite'
)

$regKeys | Select-Object -Unique | ForEach-Object {
    Remove-RegistryKeySafe -Path $_
}

Remove-OfficeAddins
Remove-ScheduledTasksByName

Write-Log "Limpiando temporales del usuario..." 'INFO'
try {
    if ($PSCmdlet.ShouldProcess($env:TEMP, 'Eliminar temporales del usuario')) {
        Get-ChildItem -Path $env:TEMP -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -Confirm:$false -ErrorAction Stop
            }
            catch { }
        }
        Write-Log "Temporales limpiados: $env:TEMP" 'OK'
    }
}
catch {
    Write-Log "Error limpiando temporales: $($_.Exception.Message)" 'ERR'
}

Write-Log "========================================" 'INFO'
Write-Log "FIN DESINSTALACION COMPLETA IMANAGE" 'OK'
Write-Log "Recomendado: reiniciar el equipo antes de reinstalar" 'WARN'
Write-Log "LOG FINAL: $LogPath" 'INFO'
Write-Log "========================================" 'INFO'

Write-Host ""
Write-Host "Listo. Revisa el log en:" -ForegroundColor Green
Write-Host $LogPath -ForegroundColor Yellow