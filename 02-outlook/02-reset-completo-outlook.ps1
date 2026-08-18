#requires -version 5.1

<#
.SYNOPSIS
    [ES] Reset agresivo de Outlook: perfil, OST y cache de autocompletado.
    [EN] Aggressive Outlook reset: profile, OST files and autocomplete cache.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$SkipProfileReset,
    [switch]$SkipOST,
    [switch]$SkipRoamCache,
    [switch]$DeleteWholeLocalOutlookFolder
)

$ErrorActionPreference = 'SilentlyContinue'

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','OK','WARN','ERR')]
        [string]$Level = 'INFO'
    )

    $color = switch ($Level) {
        'INFO' { 'Cyan' }
        'OK'   { 'Green' }
        'WARN' { 'Yellow' }
        'ERR'  { 'Red' }
    }

    Write-Host "[$Level] $Message" -ForegroundColor $color
}

function Stop-OutlookProcesses {
    Write-Log 'Cerrando procesos de Outlook...' 'INFO'

    $names = @('outlook','olk','ucmapi')
    foreach ($name in $names) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Seconds 3
}

function Disable-OutlookAddins {
    Write-Log 'Deshabilitando COM Add-ins...' 'INFO'

    $regPaths = @(
        'HKCU:\Software\Microsoft\Office\Outlook\Addins',
        'HKLM:\Software\Microsoft\Office\Outlook\Addins',
        'HKLM:\Software\WOW6432Node\Microsoft\Office\Outlook\Addins'
    )

    foreach ($path in $regPaths) {
        if (Test-Path $path) {
            Get-ChildItem -Path $path | ForEach-Object {
                try {
                    if ($PSCmdlet.ShouldProcess($_.PSPath, 'Set LoadBehavior=0')) {
                        Set-ItemProperty -Path $_.PSPath -Name 'LoadBehavior' -Value 0 -Type DWord -ErrorAction Stop
                    }
                    Write-Log "Add-in deshabilitado: $($_.PSChildName)" 'OK'
                }
                catch {
                    Write-Log "No se pudo deshabilitar: $($_.PSChildName)" 'WARN'
                }
            }
        }
    }
}

function Clear-OutlookResiliency {
    Write-Log 'Limpiando resiliency...' 'INFO'

    $resiliencyBase = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency'
    $targets = @(
        "$resiliencyBase\DisabledItems",
        "$resiliencyBase\CrashingAddinList",
        "$resiliencyBase\StartupItems"
    )

    foreach ($target in $targets) {
        if (Test-Path $target) {
            try {
                if ($PSCmdlet.ShouldProcess($target, 'Remove registry item')) {
                    Remove-Item -Path $target -Recurse -Force -ErrorAction Stop
                }
                Write-Log "Eliminado: $target" 'OK'
            }
            catch {
                Write-Log "No se pudo eliminar: $target" 'WARN'
            }
        }
    }
}

function Reset-NavigationPane {
    Write-Log 'Reset Navigation Pane...' 'INFO'

    $outlookExe = Join-Path $env:ProgramFiles 'Microsoft Office\root\Office16\OUTLOOK.EXE'
    if (-not (Test-Path $outlookExe)) {
        $outlookExe = 'outlook.exe'
    }

    try {
        Start-Process -FilePath $outlookExe -ArgumentList '/resetnavpane' -WindowStyle Hidden
        Start-Sleep -Seconds 6
        Stop-OutlookProcesses
        Write-Log 'Navigation Pane reseteado' 'OK'
    }
    catch {
        Write-Log 'Fallo al ejecutar /resetnavpane' 'WARN'
    }
}

function Remove-FilesByPattern {
    param(
        [string]$BasePath,
        [string[]]$Patterns,
        [switch]$Recurse
    )

    if (-not (Test-Path $BasePath)) { return }

    foreach ($pattern in $Patterns) {
        try {
            $items = Get-ChildItem -Path $BasePath -Filter $pattern -File -Force -ErrorAction SilentlyContinue -Recurse:$Recurse
            foreach ($item in $items) {
                try {
                    if ($PSCmdlet.ShouldProcess($item.FullName, 'Delete file')) {
                        Remove-Item -Path $item.FullName -Force -ErrorAction Stop
                    }
                    Write-Log "Borrado: $($item.FullName)" 'OK'
                }
                catch {
                    Write-Log "No se pudo borrar: $($item.FullName)" 'WARN'
                }
            }
        }
        catch {
            Write-Log "Error leyendo patron $pattern en $BasePath" 'WARN'
        }
    }
}

function Remove-FolderContent {
    param(
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        Write-Log "La ruta no existe: $Path" 'WARN'
        return
    }

    try {
        Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                if ($PSCmdlet.ShouldProcess($_.FullName, 'Delete item')) {
                    Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction Stop
                }
                Write-Log "Eliminado: $($_.FullName)" 'OK'
            }
            catch {
                Write-Log "No se pudo eliminar: $($_.FullName)" 'WARN'
            }
        }
    }
    catch {
        Write-Log "No se pudo procesar: $Path" 'WARN'
    }
}

function Remove-LocalOutlookFolderContent {
    $localOutlook = Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook'

    Write-Log "Borrando contenido completo de: $localOutlook" 'INFO'
    Remove-FolderContent -Path $localOutlook
}

function Clear-OutlookCaches {
    Write-Log 'Limpiando AppData / caches Outlook...' 'INFO'

    $localOutlook = Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook'
    $roamOutlook  = Join-Path $env:APPDATA 'Microsoft\Outlook'
    $officeUI     = Join-Path $env:LOCALAPPDATA 'Microsoft\Office'
    $officeRoam   = Join-Path $env:APPDATA 'Microsoft\Office'
    $inetCacheOLK = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\INetCache\Content.Outlook'
    $formsCache   = Join-Path $env:LOCALAPPDATA 'Microsoft\FORMS'
    $tempFolder   = Join-Path $env:TEMP 'Outlook Logging'

    Remove-FilesByPattern -BasePath $officeUI   -Patterns @('*.officeUI') -Recurse
    Remove-FilesByPattern -BasePath $officeRoam -Patterns @('*.officeUI') -Recurse

    if ($DeleteWholeLocalOutlookFolder) {
        Remove-LocalOutlookFolderContent
    }
    else {
        Remove-FilesByPattern -BasePath $localOutlook -Patterns @('*.xml','*.dat','*.tmp','*.oab','*.fav') -Recurse

        if (-not $SkipOST) {
            Remove-FilesByPattern -BasePath $localOutlook -Patterns @('*.ost') -Recurse
        }
    }

    Remove-FilesByPattern -BasePath $roamOutlook -Patterns @('*.xml','*.dat','*.tmp','*.srs') -Recurse

    if (-not $SkipRoamCache) {
        Remove-FolderContent -Path $inetCacheOLK
        Remove-FolderContent -Path $formsCache
        Remove-FolderContent -Path $tempFolder
    }
}

function Backup-And-RemoveProfiles {
    if ($SkipProfileReset) {
        Write-Log 'Profile reset omitido' 'WARN'
        return
    }

    Write-Log 'Backup y borrado de perfiles Outlook...' 'INFO'

    $profilePath = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Profiles'
    $backupDir   = Join-Path $env:USERPROFILE 'Desktop\Outlook_Profile_Backup'
    $backupFile  = Join-Path $backupDir ("Profiles_{0}.reg" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

    if (Test-Path $profilePath) {
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null

        try {
            & reg.exe export 'HKCU\Software\Microsoft\Office\16.0\Outlook\Profiles' $backupFile /y | Out-Null
            Write-Log "Backup perfiles: $backupFile" 'OK'
        }
        catch {
            Write-Log 'No se pudo exportar el backup de perfiles' 'WARN'
        }

        try {
            if ($PSCmdlet.ShouldProcess($profilePath, 'Remove Outlook profiles')) {
                Remove-Item -Path $profilePath -Recurse -Force -ErrorAction Stop
            }
            Write-Log 'Perfiles Outlook eliminados' 'OK'
        }
        catch {
            Write-Log 'No se pudieron eliminar los perfiles' 'WARN'
        }
    }
}

function Start-OutlookClean {
    Write-Log 'Iniciando Outlook...' 'INFO'
    Start-Process 'outlook.exe'
}

Write-Log '==== OUTLOOK DEEP RESET PRO ====' 'INFO'
Stop-OutlookProcesses
Disable-OutlookAddins
Clear-OutlookResiliency
Reset-NavigationPane
Clear-OutlookCaches
Backup-And-RemoveProfiles
Start-OutlookClean
Write-Log '==== RESET COMPLETADO ====' 'OK'