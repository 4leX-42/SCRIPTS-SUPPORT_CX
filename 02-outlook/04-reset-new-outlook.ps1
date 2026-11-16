#requires -version 5.1

<#
.SYNOPSIS
    [ES] Reset del nuevo Outlook (olk): quita la cuenta guardada para poder entrar con otra (equipo unido a otra organizacion).
    [EN] New Outlook (olk) reset: clears the cached account so a different one can sign in (device joined to another organization).
.DESCRIPTION
    Caso tipico: el nuevo Outlook da OwaUserHasNoMailboxAndNoLicenseAssignedException aunque la
    cuenta tiene licencia y buzon. El equipo esta unido a Entra ID de otra organizacion y olk entra
    con la cuenta principal de Windows, que en el tenant correcto no tiene buzon.

    Cierra olk, renombra a .bak-<fecha> Olk, OneAuth e IdentityCache de %LOCALAPPDATA%\Microsoft
    (no borra nada) y resetea la app Microsoft.OutlookForWindows. Al abrirlo, elegir "Usar otra
    cuenta" y entrar con la cuenta del buzon. NO desconectar la cuenta de la otra organizacion en
    Configuracion > Cuentas > Acceso a trabajo o escuela: saca el equipo de su dominio.

    -SwitchToClassic vuelve a Outlook clasico (UseNewOutlook=0) si olk insiste con la cuenta mala.
    Se ejecuta en la sesion del usuario afectado, sin elevar.

    Deshacer: cerrar olk, borrar las carpetas Olk/OneAuth/IdentityCache nuevas y quitar el
    sufijo .bak-<fecha> a las renombradas.
.NOTES
    Contexto: usuario
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$SkipCredentialCache,
    [switch]$SkipAppReset,
    [switch]$SwitchToClassic,
    [switch]$NoStart
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

function Test-ElevatedSession {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "Sesion elevada como $($id.Name): se limpia el perfil de ESA cuenta. Debe correr el usuario afectado, sin elevar." 'WARN'
    }
}

function Show-JoinState {
    Write-Log 'Estado de union del equipo (dsregcmd)...' 'INFO'

    $out = & dsregcmd.exe /status 2>$null
    if (-not $out) {
        Write-Log 'dsregcmd no disponible' 'WARN'
        return
    }

    foreach ($campo in @('AzureAdJoined', 'DomainJoined', 'WorkplaceJoined', 'TenantName')) {
        $linea = $out | Where-Object { $_ -match "^\s*$campo\s*:" } | Select-Object -First 1
        if ($linea) { Write-Log $linea.Trim() 'INFO' }
    }
}

function Stop-NewOutlook {
    Write-Log 'Cerrando el nuevo Outlook...' 'INFO'

    Get-Process -Name 'olk' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    if (-not $WhatIfPreference -and (Get-Process -Name 'olk' -ErrorAction SilentlyContinue)) {
        Write-Log 'olk sigue abierto; cerrarlo a mano y repetir' 'ERR'
        exit 1
    }
}

function Backup-Folder {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Log "No existe: $Path" 'INFO'
        return
    }

    $nuevo = '{0}.bak-{1}' -f (Split-Path $Path -Leaf), $script:Stamp
    try {
        if ($PSCmdlet.ShouldProcess($Path, "Rename to $nuevo")) {
            Rename-Item -Path $Path -NewName $nuevo -ErrorAction Stop
        }
        Write-Log "Renombrado: $Path -> $nuevo" 'OK'
    }
    catch {
        Write-Log "No se pudo renombrar (en uso?): $Path" 'WARN'
    }
}

function Reset-NewOutlookApp {
    if ($SkipAppReset) {
        Write-Log 'Reset de la app omitido' 'WARN'
        return
    }

    $wi = $WhatIfPreference; $WhatIfPreference = $false
    Import-Module Appx -ErrorAction SilentlyContinue
    $WhatIfPreference = $wi
    $pkg = Get-AppxPackage -Name 'Microsoft.OutlookForWindows' -ErrorAction SilentlyContinue
    if (-not $pkg) {
        Write-Log 'Microsoft.OutlookForWindows no instalado para este usuario' 'WARN'
        return
    }

    if (-not (Get-Command Reset-AppxPackage -ErrorAction SilentlyContinue)) {
        Write-Log 'Reset-AppxPackage no disponible: Configuracion > Aplicaciones > Outlook (new) > Restablecer' 'WARN'
        return
    }

    try {
        if ($PSCmdlet.ShouldProcess($pkg.PackageFullName, 'Reset-AppxPackage')) {
            $pkg | Reset-AppxPackage -ErrorAction Stop
        }
        Write-Log 'App del nuevo Outlook reseteada' 'OK'
    }
    catch {
        Write-Log "Fallo Reset-AppxPackage: $($_.Exception.Message)" 'WARN'
    }
}

function Set-ClassicOutlook {
    $key = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Preferences'
    try {
        if ($PSCmdlet.ShouldProcess($key, 'UseNewOutlook=0')) {
            New-Item -Path $key -Force | Out-Null
            Set-ItemProperty -Path $key -Name 'UseNewOutlook' -Value 0 -Type DWord -ErrorAction Stop
        }
        Write-Log 'Outlook clasico por defecto (UseNewOutlook=0)' 'OK'
    }
    catch {
        Write-Log 'No se pudo fijar UseNewOutlook=0' 'WARN'
    }
}

$script:Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

Write-Log '==== RESET NUEVO OUTLOOK ====' 'INFO'
Test-ElevatedSession
Show-JoinState
Stop-NewOutlook

$carpetas = @('Olk')
if (-not $SkipCredentialCache) { $carpetas += @('OneAuth', 'IdentityCache') }
foreach ($c in $carpetas) {
    Backup-Folder -Path (Join-Path $env:LOCALAPPDATA "Microsoft\$c")
}

if ($SwitchToClassic) {
    Set-ClassicOutlook
    if (-not $NoStart) { Start-Process 'outlook.exe' }
}
else {
    Reset-NewOutlookApp
    if (-not $NoStart) { Start-Process 'shell:AppsFolder\Microsoft.OutlookForWindows_8wekyb3d8bbwe!Microsoft.OutlookforWindows' }
    Write-Log 'Al abrir: "Usar otra cuenta" y entrar con la cuenta del buzon, no con la de Windows' 'INFO'
}

if (-not $SkipCredentialCache) {
    Write-Log 'Teams/Word pueden pedir iniciar sesion una vez (cache de credenciales renombrada)' 'INFO'
}
Write-Log '==== RESET COMPLETADO ====' 'OK'
