#Requires -Version 5.1

<#
.SYNOPSIS
    [ES] Repara la cache de credenciales de Microsoft 365 por niveles, y sabe deshacer los cambios.
    [EN] Repairs the Microsoft 365 credential cache in tiers, and can roll the changes back.
.DESCRIPTION
    Sintoma objetivo (OWA al arrancar):
        err: AccountTerminationException  /  et: ServerError  /  st: 440  /  ehk: X-OWA-Error
    Cuando la MISMA cuenta funciona en otro equipo pero falla aqui (tanto en Outlook
    de escritorio como en OWA dentro del navegador), la causa habitual NO es la cuenta
    sino los artefactos de autenticacion cacheados localmente:
        - Administrador de credenciales de Windows (entradas de Office/MSAL/WAM)
        - OneAuth        : %LOCALAPPDATA%\Microsoft\OneAuth
        - TokenBroker    : %LOCALAPPDATA%\Microsoft\TokenBroker\Cache
        - IdentityCache  : %LOCALAPPDATA%\Microsoft\IdentityCache
        - Identidad Office (registro): HKCU\...\Office\16.0\Common\Identity
        - WAM / AAD.BrokerPlugin (SSO del navegador en equipos Entra-joined)
        - Cookies de los dominios de M365 en Edge/Chrome
        - Primary Refresh Token (PRT) del equipo

    Diseno SEGURO:
        - Modo por defecto = Diagnose (SOLO LECTURA). No toca nada.
        - Cada operacion destructiva hace BACKUP previo (carpetas via robocopy,
          registro via reg export) y queda registrada en un manifest.json.
        - Modo Restore deshace los cambios desde una sesion de backup.
        - Soporta -DryRun (simula) y pide confirmacion salvo -Force.
        - Los tiers invasivos (navegador, WAM, perfil de Outlook) son OPT-IN.
        - NUNCA borra .PST (datos locales). Solo .OST (cache re-descargable).

    IMPORTANTE: debe ejecutarse DENTRO de la sesion de Windows del usuario afectado
    (el usuario afectado), porque HKCU y %LOCALAPPDATA% son por-usuario. Si lo ejecutas como
    otro usuario limpiaras el cache equivocado. El script lo verifica y avisa.

.PARAMETER Mode
    Diagnose (def, solo lectura) | Repair | Restore

.PARAMETER Accounts
    Cuentas (UPN) afectadas. Se usan para acotar el match de credenciales/reporte.
    Por defecto: usuario@es.andersen.com

.PARAMETER Tiers
    Que limpiar en Repair. Set seguro por defecto. Invasivos opt-in:
    BrowserCookies, WamBroker, PRT, OutlookProfile.

.PARAMETER BackupRoot
    Raiz de backups/logs. Def: %LOCALAPPDATA%\M365CacheRepair

.PARAMETER RestoreFrom
    Carpeta Session_* a restaurar (solo Mode Restore).

.PARAMETER CloseApps
    Cierra Outlook/Teams/OneDrive (y navegadores si se limpia BrowserCookies) antes de limpiar.

.PARAMETER DryRun
    Simula: muestra que haria, sin tocar nada.

.PARAMETER Force
    No pide confirmacion interactiva.

.EXAMPLE
    # 1) Diagnostico (recomendado primero, no toca nada)
    .\Repair-M365CredentialCache.ps1 -Mode Diagnose

.EXAMPLE
    # 2) Reparacion segura (cierra apps, sin tocar navegador/WAM/perfil)
    .\Repair-M365CredentialCache.ps1 -Mode Repair -CloseApps

.EXAMPLE
    # 3) Reparacion + cookies de navegador (OWA falla en el navegador)
    .\Repair-M365CredentialCache.ps1 -Mode Repair -CloseApps `
        -Tiers CredentialManager,OneAuth,TokenBroker,IdentityCache,OfficeIdentityRegistry,BrowserCookies,WamBroker,PRT

.EXAMPLE
    # 4) Deshacer
    .\Repair-M365CredentialCache.ps1 -Mode Restore -RestoreFrom "$env:LOCALAPPDATA\M365CacheRepair\Session_20260622_101500"

.NOTES
    Autor: IT   |   Probado en Windows 10/11, PowerShell 5.1+
#>

[CmdletBinding()]
param(
    [ValidateSet('Diagnose','Repair','Restore')]
    [string]$Mode = 'Diagnose',

    [string[]]$Accounts = @('usuario@es.andersen.com'),

    [ValidateSet('CredentialManager','OneAuth','TokenBroker','IdentityCache',
                 'OfficeIdentityRegistry','BrowserCookies','WamBroker','PRT','OutlookProfile')]
    [string[]]$Tiers = @('CredentialManager','OneAuth','TokenBroker','IdentityCache','OfficeIdentityRegistry'),

    [string]$BackupRoot = (Join-Path $env:LOCALAPPDATA 'M365CacheRepair'),

    [string]$RestoreFrom,

    [switch]$CloseApps,

    [switch]$DryRun,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# ----------------------------------------------------------------------------
#  Estado global
# ----------------------------------------------------------------------------
$script:DryRun   = [bool]$DryRun
$script:Force    = [bool]$Force
$script:LogFile  = $null
$script:Manifest = New-Object System.Collections.Generic.List[object]

$LA = $env:LOCALAPPDATA

# Rutas de cache conocidas (por-usuario)
$script:CachePaths = @{
    OneAuth       = (Join-Path $LA 'Microsoft\OneAuth')
    TokenBroker   = (Join-Path $LA 'Microsoft\TokenBroker\Cache')
    IdentityCache = (Join-Path $LA 'Microsoft\IdentityCache')
}
$script:WamPkg      = (Join-Path $LA 'Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy')
$script:WamAccounts = (Join-Path $script:WamPkg 'AC\TokenBroker\Accounts')

# Clave de identidad de Office (16.0 = Office 2016/2019/2021/365)
$script:OfficeIdentityKey = 'HKCU:\Software\Microsoft\Office\16.0\Common\Identity'

# Patrones de credenciales relacionadas con M365 (substring, case-insensitive)
$script:CredPatterns = @(
    'MicrosoftOffice','MicrosoftAccount','OneAuthAccount','MicrosoftOfficeData',
    'msteams','Microsoft_OC1','SSO_POP_Device','login.microsoftonline.com',
    'login.windows.net','login.windows-ppe.net','msteams_adalsso','OneDrive',
    'office.com','outlook.office','MS.Online',
    'WindowsLive:target=virtualapp/didlogical'
) + $Accounts

# Dominios de cookies a indicar para limpieza manual dirigida (navegador)
$script:M365CookieDomains = @(
    'login.microsoftonline.com','login.live.com','login.windows.net',
    'office.com','office365.com','outlook.office.com','outlook.office365.com',
    'microsoft.com','microsoftonline.com','msauth.net','msftauth.net','sharepoint.com'
)

# ----------------------------------------------------------------------------
#  Utilidades
# ----------------------------------------------------------------------------
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','OK','STEP','DRY')]
        [string]$Level = 'INFO'
    )
    $ts   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$ts][$Level] $Message"
    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'OK'    { Write-Host $line -ForegroundColor Green }
        'STEP'  { Write-Host $line -ForegroundColor Cyan }
        'DRY'   { Write-Host $line -ForegroundColor Magenta }
        default { Write-Host $line }
    }
    if ($script:LogFile) {
        try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 } catch {}
    }
}

function New-SessionDir {
    param([string]$Root)
    $stamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $dir   = Join-Path $Root ("Session_$stamp")
    New-Item -ItemType Directory -Path (Join-Path $dir 'files')    -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $dir 'registry') -Force | Out-Null
    return $dir
}

function Confirm-Proceed {
    param([string]$Question)
    if ($script:Force) { return $true }
    $ans = Read-Host "$Question  [s/N]"
    return ($ans -match '^(s|si|si|y|yes)$')
}

function Add-Manifest {
    param([hashtable]$Entry)
    $script:Manifest.Add([pscustomobject]$Entry) | Out-Null
}

function Get-FolderInfo {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        $size = 0
        try {
            $size = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
                     Measure-Object -Property Length -Sum).Sum
            if (-not $size) { $size = 0 }
        } catch {}
        return [pscustomobject]@{ Path = $Path; Exists = $true; SizeMB = [math]::Round(($size / 1MB), 2) }
    }
    return [pscustomobject]@{ Path = $Path; Exists = $false; SizeMB = 0 }
}

function Test-Endpoint {
    param([string]$HostName, [int]$Port = 443, [int]$TimeoutMs = 3000)
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($HostName, $Port, $null, $null)
        $ok  = $iar.AsyncWaitHandle.WaitOne($TimeoutMs)
        if ($ok -and $client.Connected) { $client.EndConnect($iar); return $true }
        return $false
    } catch {
        return $false
    } finally {
        if ($client) { $client.Close() }
    }
}

function Get-DsRegStatus {
    $out = @{}
    try {
        $txt = & dsregcmd /status 2>$null
        foreach ($k in 'AzureAdJoined','EnterpriseJoined','DomainJoined','AzureAdPrt','TenantName','WamDefaultSet') {
            $m = $txt | Select-String -Pattern ('^\s*' + [regex]::Escape($k) + '\s*:\s*(.+)$')
            if ($m) { $out[$k] = ($m.Matches[0].Groups[1].Value).Trim() }
        }
    } catch {}
    return $out
}

# ----------------------------------------------------------------------------
#  Backup / borrado de carpetas (robocopy = soporta rutas largas y archivos bloqueados)
# ----------------------------------------------------------------------------
function Backup-Folder {
    param([string]$Path, [string]$SessionDir, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Log "No existe (omitido): $Path" 'INFO'
        return $null
    }
    $dest = Join-Path (Join-Path $SessionDir 'files') $Label
    if ($script:DryRun) { Write-Log "DRYRUN backup: '$Path' -> '$dest'" 'DRY'; return $dest }
    Write-Log "Backup: '$Path' -> '$dest'" 'STEP'
    & robocopy "$Path" "$dest" /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Write-Log "robocopy devolvio codigo $LASTEXITCODE para $Path (parcial)" 'WARN' }
    return $dest
}

function Clear-Folder {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if ($script:DryRun) { Write-Log "DRYRUN borraria: $Path" 'DRY'; return }
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        Write-Log "Borrado: $Path" 'OK'
    } catch {
        Write-Log "No se pudo borrar del todo '$Path': $($_.Exception.Message)" 'WARN'
    }
}

function Invoke-FolderTier {
    param([string]$Path, [string]$SessionDir, [string]$Label)
    $bk = Backup-Folder -Path $Path -SessionDir $SessionDir -Label $Label
    if ($bk) {
        Clear-Folder -Path $Path
        Add-Manifest @{ type = 'folder'; label = $Label; original = $Path; backup = $bk }
    }
}

# ----------------------------------------------------------------------------
#  Backup / borrado de registro
# ----------------------------------------------------------------------------
function ConvertTo-RegExePath {
    param([string]$ProviderPath)  # 'HKCU:\Software\...' -> 'HKCU\Software\...'
    return ($ProviderPath -replace '^HKCU:\\', 'HKCU\' -replace '^HKLM:\\', 'HKLM\')
}

function Backup-RegKey {
    param([string]$ProviderPath, [string]$SessionDir, [string]$Label)
    if (-not (Test-Path -LiteralPath $ProviderPath)) {
        Write-Log "Clave de registro ausente (omitido): $ProviderPath" 'INFO'
        return $null
    }
    $file   = Join-Path (Join-Path $SessionDir 'registry') ($Label + '.reg')
    $regKey = ConvertTo-RegExePath $ProviderPath
    if ($script:DryRun) { Write-Log "DRYRUN reg export '$regKey' -> '$file'" 'DRY'; return $file }
    & reg export "$regKey" "$file" /y | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Log "Exportado: $regKey -> $file" 'STEP'; return $file }
    Write-Log "Fallo reg export de $regKey" 'WARN'
    return $null
}

function Clear-RegKey {
    param([string]$ProviderPath)
    if (-not (Test-Path -LiteralPath $ProviderPath)) { return }
    if ($script:DryRun) { Write-Log "DRYRUN borraria clave: $ProviderPath" 'DRY'; return }
    try {
        Remove-Item -LiteralPath $ProviderPath -Recurse -Force -ErrorAction Stop
        Write-Log "Clave de registro borrada: $ProviderPath" 'OK'
    } catch {
        Write-Log "No se pudo borrar la clave '$ProviderPath': $($_.Exception.Message)" 'WARN'
    }
}

# ----------------------------------------------------------------------------
#  Cierre de aplicaciones
# ----------------------------------------------------------------------------
function Get-RunningTargets {
    param([switch]$IncludeBrowsers)
    $names = @('OUTLOOK','Teams','ms-teams','OneDrive','lync','UcMapi','WINWORD','EXCEL','POWERPNT','ONENOTE','MSACCESS')
    if ($IncludeBrowsers) { $names += @('msedge','chrome') }
    return Get-Process -Name $names -ErrorAction SilentlyContinue
}

function Stop-Apps {
    param([switch]$IncludeBrowsers)
    $procs = Get-RunningTargets -IncludeBrowsers:$IncludeBrowsers
    if (-not $procs) { Write-Log "No hay apps objetivo en ejecucion." 'INFO'; return }
    $list = ($procs | Select-Object -ExpandProperty ProcessName -Unique) -join ', '
    Write-Log "Apps en ejecucion: $list" 'WARN'
    Write-Log "AVISO: cierra correos/documentos sin guardar antes de continuar." 'WARN'
    if (-not (Confirm-Proceed "Cerrar estas aplicaciones a la fuerza?")) {
        Write-Log "El usuario opto por NO cerrar apps. Las rutas bloqueadas se omitiran." 'WARN'
        return
    }
    if ($script:DryRun) { Write-Log "DRYRUN cerraria: $list" 'DRY'; return }
    foreach ($p in $procs) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch {}
    }
    Start-Sleep -Seconds 2
    Write-Log "Aplicaciones cerradas." 'OK'
}

# ----------------------------------------------------------------------------
#  Tier: Administrador de credenciales de Windows
# ----------------------------------------------------------------------------
function Get-M365CredentialTargets {
    $raw = & cmdkey /list 2>$null
    $targets = @()
    foreach ($line in $raw) {
        if ($line -match '^\s*Target:\s*(.+?)\s*$') {
            $t = $matches[1]
            foreach ($p in $script:CredPatterns) {
                if ($t -match [regex]::Escape($p)) { $targets += $t; break }
            }
        }
    }
    return @($targets | Select-Object -Unique)
}

function Invoke-CredentialTier {
    param([string]$SessionDir)
    $targets = @(Get-M365CredentialTargets)
    $bkFile  = Join-Path $SessionDir 'credentials_removed.txt'
    if (-not $targets -or $targets.Count -eq 0) {
        Write-Log "No se encontraron credenciales M365 en el Administrador de credenciales." 'INFO'
        return
    }
    Write-Log ("Credenciales M365 encontradas: " + $targets.Count) 'STEP'
    if (-not $script:DryRun) {
        Set-Content -LiteralPath $bkFile -Value $targets -Encoding UTF8
    }
    foreach ($t in $targets) {
        if ($script:DryRun) { Write-Log "DRYRUN borraria credencial: $t" 'DRY'; continue }
        & cmdkey "/delete:$t" 2>$null | Out-Null
        $code = $LASTEXITCODE
        if ($code -ne 0 -and $t -match 'target=(.+)$') {
            & cmdkey "/delete:$($matches[1])" 2>$null | Out-Null
            $code = $LASTEXITCODE
        }
        if ($code -eq 0) { Write-Log "Credencial borrada: $t" 'OK' }
        else             { Write-Log "No se pudo borrar credencial: $t" 'WARN' }
    }
    Add-Manifest @{ type = 'credentials'; note = 'Las credenciales no se restauran; las apps re-autentican.'; listFile = $bkFile }
}

# ----------------------------------------------------------------------------
#  Tier: Identidad de Office (registro)
# ----------------------------------------------------------------------------
function Invoke-OfficeIdentityTier {
    param([string]$SessionDir)
    $bk = Backup-RegKey -ProviderPath $script:OfficeIdentityKey -SessionDir $SessionDir -Label 'Office16_Identity'
    if ($bk) {
        Add-Manifest @{ type = 'registry'; label = 'Office16_Identity'; key = $script:OfficeIdentityKey; backup = $bk }
        Clear-RegKey -ProviderPath (Join-Path $script:OfficeIdentityKey 'Identities')
        Clear-RegKey -ProviderPath (Join-Path $script:OfficeIdentityKey 'Profiles')
    }
}

# ----------------------------------------------------------------------------
#  Tier: WAM / AAD.BrokerPlugin (SSO del navegador en equipos Entra-joined)  [OPT-IN]
# ----------------------------------------------------------------------------
function Invoke-WamTier {
    param([string]$SessionDir)
    Write-Log "WAM/BrokerPlugin: limpia el SSO de cuentas de trabajo de Windows (reversible)." 'WARN'
    if (-not (Confirm-Proceed "Limpiar el cache de WAM (AAD.BrokerPlugin)?")) {
        Write-Log "Tier WamBroker omitido por el usuario." 'INFO'; return
    }
    Invoke-FolderTier -Path $script:WamAccounts -SessionDir $SessionDir -Label 'WAM_BrokerPlugin_Accounts'
}

# ----------------------------------------------------------------------------
#  Tier: Cookies de navegador (Edge/Chrome) para M365   [OPT-IN]
# ----------------------------------------------------------------------------
function Get-BrowserProfiles {
    $roots = @(
        @{ Name = 'Edge';   Path = (Join-Path $LA 'Microsoft\Edge\User Data') },
        @{ Name = 'Chrome'; Path = (Join-Path $LA 'Google\Chrome\User Data') }
    )
    $profiles = @()
    foreach ($r in $roots) {
        if (-not (Test-Path -LiteralPath $r.Path)) { continue }
        Get-ChildItem -LiteralPath $r.Path -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $cookieNew = Join-Path $_.FullName 'Network\Cookies'
            $cookieOld = Join-Path $_.FullName 'Cookies'
            if ((Test-Path $cookieNew) -or (Test-Path $cookieOld)) {
                $profiles += [pscustomobject]@{
                    Browser   = $r.Name
                    Profile   = $_.Name
                    CookieNew = $cookieNew
                    CookieOld = $cookieOld
                }
            }
        }
    }
    return $profiles
}

function Invoke-BrowserCookieTier {
    param([string]$SessionDir)
    Write-Log "AVISO: este tier borra TODAS las cookies de los perfiles Edge/Chrome (cierra sesion en todos los sitios)." 'WARN'
    Write-Log "Alternativa quirurgica (sin tocar otros sitios): en el navegador, borra cookies SOLO de:" 'WARN'
    foreach ($d in $script:M365CookieDomains) { Write-Host "      - $d" -ForegroundColor DarkYellow }
    if (-not (Confirm-Proceed "Borrar TODAS las cookies de los perfiles del navegador?")) {
        Write-Log "Tier BrowserCookies omitido. Usa la limpieza manual dirigida de arriba." 'INFO'; return
    }
    $profiles = Get-BrowserProfiles
    if (-not $profiles) { Write-Log "No se encontraron perfiles de navegador con cookies." 'INFO'; return }
    foreach ($p in $profiles) {
        $label = ("{0}_{1}_Cookies" -f $p.Browser, ($p.Profile -replace '\s', '_'))
        foreach ($cookieFile in @($p.CookieNew, $p.CookieOld)) {
            if (-not (Test-Path -LiteralPath $cookieFile)) { continue }
            $destDir = Join-Path (Join-Path $SessionDir 'files') $label
            if (-not $script:DryRun) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            $dest = Join-Path $destDir (Split-Path $cookieFile -Leaf)
            if ($script:DryRun) {
                Write-Log "DRYRUN backup+borrar cookie: $cookieFile" 'DRY'
            } else {
                try {
                    Copy-Item -LiteralPath $cookieFile -Destination $dest -Force -ErrorAction Stop
                    Remove-Item -LiteralPath $cookieFile -Force -ErrorAction Stop
                    Write-Log "Cookies borradas ($($p.Browser)/$($p.Profile)): $cookieFile" 'OK'
                    Add-Manifest @{ type = 'file'; label = $label; original = $cookieFile; backup = $dest }
                } catch {
                    Write-Log "No se pudo procesar '$cookieFile' (navegador abierto?): $($_.Exception.Message)" 'WARN'
                }
            }
        }
    }
}

# ----------------------------------------------------------------------------
#  Tier: PRT (Primary Refresh Token)   [OPT-IN, bajo riesgo]
# ----------------------------------------------------------------------------
function Invoke-PrtTier {
    $ds = Get-DsRegStatus
    if ($ds.ContainsKey('AzureAdJoined') -and $ds['AzureAdJoined'] -notmatch 'YES') {
        Write-Log "Equipo no Entra-joined (AzureAdJoined=$($ds['AzureAdJoined'])). PRT no aplica; se omite." 'INFO'
        return
    }
    Write-Log "PRT actual: AzureAdPrt=$($ds['AzureAdPrt'])  Tenant=$($ds['TenantName'])" 'STEP'
    if ($script:DryRun) { Write-Log "DRYRUN ejecutaria: dsregcmd /refreshprt" 'DRY'; return }
    try {
        $out = & dsregcmd /refreshprt 2>&1
        Write-Log ("dsregcmd /refreshprt -> " + ($out -join ' ')) 'OK'
    } catch {
        Write-Log "dsregcmd /refreshprt no disponible o fallo: $($_.Exception.Message)" 'WARN'
    }
    Write-Log "Si el PRT sigue mal, cierra sesion de Windows y vuelve a entrar (renueva el PRT)." 'INFO'
}

# ----------------------------------------------------------------------------
#  Tier: Perfil de Outlook (renombra .OST, NUNCA toca .PST)   [OPT-IN, mas invasivo]
# ----------------------------------------------------------------------------
function Invoke-OutlookProfileTier {
    param([string]$SessionDir)
    Write-Log "Perfil de Outlook: respalda el registro de perfiles y renombra .OST (cache). NO toca .PST." 'WARN'
    if (-not (Confirm-Proceed "Renombrar .OST y respaldar el registro de perfiles de Outlook?")) {
        Write-Log "Tier OutlookProfile omitido." 'INFO'; return
    }
    # Respaldo del registro de perfiles
    $profKey = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Profiles'
    $bk = Backup-RegKey -ProviderPath $profKey -SessionDir $SessionDir -Label 'Outlook16_Profiles'
    if ($bk) { Add-Manifest @{ type = 'registry'; label = 'Outlook16_Profiles'; key = $profKey; backup = $bk } }

    # Renombrar .OST (re-descargable). PST se ignora deliberadamente.
    $stamp     = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $ostFolder = Join-Path $LA 'Microsoft\Outlook'
    if (-not (Test-Path -LiteralPath $ostFolder)) { Write-Log "Carpeta de Outlook no encontrada." 'INFO'; return }
    $osts = Get-ChildItem -LiteralPath $ostFolder -Filter *.ost -ErrorAction SilentlyContinue
    foreach ($ost in $osts) {
        $newName = "$($ost.Name).bak_$stamp"
        if ($script:DryRun) { Write-Log "DRYRUN renombraria OST: $($ost.FullName) -> $newName" 'DRY'; continue }
        try {
            Rename-Item -LiteralPath $ost.FullName -NewName $newName -ErrorAction Stop
            Write-Log "OST renombrado: $($ost.Name) -> $newName" 'OK'
            Add-Manifest @{ type = 'rename'; original = $ost.FullName; renamed = (Join-Path $ostFolder $newName) }
        } catch {
            Write-Log "No se pudo renombrar OST (Outlook abierto?): $($_.Exception.Message)" 'WARN'
        }
    }
}

# ----------------------------------------------------------------------------
#  MODO: Diagnose (solo lectura)
# ----------------------------------------------------------------------------
function Invoke-Diagnose {
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    $reportDir = Join-Path $BackupRoot 'Diagnostics'
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    $stamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $script:LogFile = Join-Path $reportDir "Diagnose_$stamp.log"

    Write-Log "===== DIAGNOSTICO (solo lectura) =====" 'STEP'
    Write-Log ("Usuario Windows actual : {0}" -f $env:USERNAME) 'INFO'
    Write-Log ("USERPROFILE            : {0}" -f $env:USERPROFILE) 'INFO'
    Write-Log ("Cuentas objetivo       : {0}" -f ($Accounts -join ', ')) 'INFO'

    # Estado de union al dominio / Entra y PRT
    Write-Log "----- Estado de identidad del equipo (dsregcmd) -----" 'STEP'
    $ds = Get-DsRegStatus
    if ($ds.Count -gt 0) {
        foreach ($k in $ds.Keys) { Write-Log ("  {0,-16}: {1}" -f $k, $ds[$k]) 'INFO' }
        if ($ds.ContainsKey('AzureAdPrt') -and $ds['AzureAdPrt'] -notmatch 'YES') {
            Write-Log "  >> PRT ausente/invalido: probable causa del fallo de SSO en navegador." 'WARN'
        }
    } else { Write-Log "  dsregcmd no devolvio datos." 'WARN' }

    # Office ClickToRun
    Write-Log "----- Version de Office -----" 'STEP'
    try {
        $c2r = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction Stop
        Write-Log ("  Producto: {0}" -f $c2r.ProductReleaseIds) 'INFO'
        Write-Log ("  Version : {0}" -f $c2r.VersionToReport) 'INFO'
    } catch { Write-Log "  No se detecto Office ClickToRun." 'WARN' }

    # Credenciales M365
    Write-Log "----- Credenciales M365 en Administrador de credenciales -----" 'STEP'
    $targets = @(Get-M365CredentialTargets)
    if ($targets.Count -gt 0) { foreach ($t in $targets) { Write-Log "  $t" 'INFO' } }
    else { Write-Log "  Ninguna encontrada." 'INFO' }

    # Carpetas de cache
    Write-Log "----- Carpetas de cache de tokens -----" 'STEP'
    foreach ($key in $script:CachePaths.Keys) {
        $i = Get-FolderInfo $script:CachePaths[$key]
        Write-Log ("  {0,-14}: existe={1}  tamano={2} MB  ({3})" -f $key, $i.Exists, $i.SizeMB, $i.Path) 'INFO'
    }
    $wi = Get-FolderInfo $script:WamAccounts
    Write-Log ("  {0,-14}: existe={1}  tamano={2} MB" -f 'WAM_Accounts', $wi.Exists, $wi.SizeMB) 'INFO'

    # Identidad Office
    $idExists = Test-Path -LiteralPath $script:OfficeIdentityKey
    Write-Log ("  OfficeIdentity (registro): existe={0}" -f $idExists) 'INFO'

    # Perfiles de navegador
    Write-Log "----- Perfiles de navegador con cookies -----" 'STEP'
    $bp = Get-BrowserProfiles
    if ($bp) { foreach ($p in $bp) { Write-Log ("  {0} / {1}" -f $p.Browser, $p.Profile) 'INFO' } }
    else { Write-Log "  Ninguno detectado." 'INFO' }

    # OST/PST
    Write-Log "----- Archivos de datos de Outlook -----" 'STEP'
    $ostFolder = Join-Path $LA 'Microsoft\Outlook'
    if (Test-Path $ostFolder) {
        Get-ChildItem -LiteralPath $ostFolder -Include *.ost,*.pst -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Log ("  {0}  ({1} MB)" -f $_.FullName, [math]::Round($_.Length / 1MB, 2)) 'INFO'
        }
    }
    Write-Log "  (Solo se renombran .OST en el tier OutlookProfile; los .PST NUNCA se tocan.)" 'INFO'

    # Conectividad
    Write-Log "----- Conectividad a endpoints M365 (443) -----" 'STEP'
    foreach ($h in 'outlook.office365.com','login.microsoftonline.com','outlook.office.com') {
        $ok = Test-Endpoint -HostName $h
        Write-Log ("  {0,-32}: {1}" -f $h, ($(if ($ok) { 'OK' } else { 'SIN CONEXION' }))) ($(if ($ok) { 'OK' } else { 'WARN' }))
    }

    Write-Log "===== FIN DIAGNOSTICO =====" 'STEP'
    Write-Log "Reporte: $script:LogFile" 'OK'
    Write-Host ""
    Write-Host "Siguiente paso sugerido (dentro de la sesion de Windows del usuario afectado):" -ForegroundColor Cyan
    Write-Host "  .\Repair-M365CredentialCache.ps1 -Mode Repair -CloseApps" -ForegroundColor White
    Write-Host "  # Si OWA falla en el navegador, anade tiers BrowserCookies,WamBroker,PRT" -ForegroundColor DarkGray
}

# ----------------------------------------------------------------------------
#  MODO: Repair
# ----------------------------------------------------------------------------
function Invoke-Repair {
    $session = New-SessionDir -Root $BackupRoot
    $script:LogFile = Join-Path $session 'repair.log'

    Write-Log "===== REPARACION =====" 'STEP'
    Write-Log ("Modo simulacion (DryRun): {0}" -f $script:DryRun) ($(if ($script:DryRun) { 'DRY' } else { 'INFO' }))
    Write-Log ("Sesion de backup: {0}" -f $session) 'INFO'
    Write-Log ("Tiers: {0}" -f ($Tiers -join ', ')) 'INFO'

    # --- Verificacion CRITICA de contexto de usuario ---
    Write-Host ""
    Write-Host "  ##############################################################" -ForegroundColor Yellow
    Write-Host "  #  Limpiando el cache del usuario de Windows:" -ForegroundColor Yellow
    Write-Host ("  #    USUARIO     : {0}" -f $env:USERNAME) -ForegroundColor Yellow
    Write-Host ("  #    PERFIL      : {0}" -f $env:USERPROFILE) -ForegroundColor Yellow
    Write-Host ("  #    CUENTA(S)   : {0}" -f ($Accounts -join ', ')) -ForegroundColor Yellow
    Write-Host "  #  Debe ser la sesion del USUARIO AFECTADO (HKCU/%LOCALAPPDATA% son por-usuario)." -ForegroundColor Yellow
    Write-Host "  ##############################################################" -ForegroundColor Yellow
    Write-Host ""
    if (-not (Confirm-Proceed "Confirmas que esta es la sesion correcta y deseas continuar?")) {
        Write-Log "Cancelado por el usuario." 'WARN'; return
    }

    # --- Cierre de apps ---
    if ($CloseApps) {
        Stop-Apps -IncludeBrowsers:($Tiers -contains 'BrowserCookies')
    } else {
        $running = Get-RunningTargets -IncludeBrowsers:($Tiers -contains 'BrowserCookies')
        if ($running) {
            $list = ($running | Select-Object -ExpandProperty ProcessName -Unique) -join ', '
            Write-Log "Apps abiertas ($list). Sin -CloseApps; las rutas bloqueadas se omitiran." 'WARN'
        }
    }

    # --- Ejecucion de tiers ---
    foreach ($tier in $Tiers) {
        Write-Log "----- TIER: $tier -----" 'STEP'
        switch ($tier) {
            'CredentialManager'      { Invoke-CredentialTier -SessionDir $session }
            'OneAuth'                { Invoke-FolderTier -Path $script:CachePaths.OneAuth       -SessionDir $session -Label 'OneAuth' }
            'TokenBroker'            { Invoke-FolderTier -Path $script:CachePaths.TokenBroker   -SessionDir $session -Label 'TokenBroker_Cache' }
            'IdentityCache'          { Invoke-FolderTier -Path $script:CachePaths.IdentityCache -SessionDir $session -Label 'IdentityCache' }
            'OfficeIdentityRegistry' { Invoke-OfficeIdentityTier -SessionDir $session }
            'BrowserCookies'         { Invoke-BrowserCookieTier  -SessionDir $session }
            'WamBroker'              { Invoke-WamTier            -SessionDir $session }
            'PRT'                    { Invoke-PrtTier }
            'OutlookProfile'         { Invoke-OutlookProfileTier -SessionDir $session }
        }
    }

    # --- Manifest ---
    $manifestPath = Join-Path $session 'manifest.json'
    if (-not $script:DryRun) {
        $script:Manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
        Write-Log "Manifest guardado: $manifestPath" 'OK'
    } else {
        Write-Log "DRYRUN: no se escribe manifest." 'DRY'
    }

    Write-Log "===== REPARACION COMPLETADA =====" 'STEP'
    Write-Host ""
    Write-Host "PASOS FINALES:" -ForegroundColor Cyan
    Write-Host "  1) REINICIA el equipo (o cierra y abre sesion de Windows)." -ForegroundColor White
    Write-Host "  2) Abre Outlook -> aceptara el inicio de sesion moderno y re-autenticara." -ForegroundColor White
    Write-Host "  3) Abre OWA en el navegador (ventana nueva) e inicia sesion de nuevo." -ForegroundColor White
    Write-Host ""
    Write-Host "Para deshacer:" -ForegroundColor DarkGray
    Write-Host ("  .\Repair-M365CredentialCache.ps1 -Mode Restore -RestoreFrom `"{0}`"" -f $session) -ForegroundColor DarkGray
}

# ----------------------------------------------------------------------------
#  MODO: Restore
# ----------------------------------------------------------------------------
function Invoke-Restore {
    if (-not $RestoreFrom -or -not (Test-Path -LiteralPath $RestoreFrom)) {
        throw "Especifica -RestoreFrom con una carpeta Session_* valida."
    }
    $script:LogFile = Join-Path $RestoreFrom 'restore.log'
    $manifestPath = Join-Path $RestoreFrom 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw "No se encontro manifest.json en $RestoreFrom" }

    Write-Log "===== RESTAURACION =====" 'STEP'
    Write-Log "Origen: $RestoreFrom" 'INFO'
    if (-not (Confirm-Proceed "Restaurar el estado previo desde este backup?")) {
        Write-Log "Cancelado por el usuario." 'WARN'; return
    }

    $entries = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    foreach ($e in $entries) {
        switch ($e.type) {
            'folder' {
                if (Test-Path -LiteralPath $e.backup) {
                    Write-Log "Restaurando carpeta -> $($e.original)" 'STEP'
                    & robocopy "$($e.backup)" "$($e.original)" /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
                    Write-Log "Carpeta restaurada: $($e.original)" 'OK'
                }
            }
            'file' {
                if (Test-Path -LiteralPath $e.backup) {
                    $dir = Split-Path $e.original -Parent
                    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                    Copy-Item -LiteralPath $e.backup -Destination $e.original -Force
                    Write-Log "Archivo restaurado: $($e.original)" 'OK'
                }
            }
            'registry' {
                if (Test-Path -LiteralPath $e.backup) {
                    & reg import "$($e.backup)" | Out-Null
                    if ($LASTEXITCODE -eq 0) { Write-Log "Registro restaurado: $($e.key)" 'OK' }
                    else { Write-Log "Fallo reg import de $($e.backup)" 'WARN' }
                }
            }
            'rename' {
                if (Test-Path -LiteralPath $e.renamed) {
                    Rename-Item -LiteralPath $e.renamed -NewName (Split-Path $e.original -Leaf) -Force
                    Write-Log "OST restaurado: $($e.original)" 'OK'
                }
            }
            'credentials' {
                Write-Log "Las credenciales borradas NO se restauran; las apps re-autentican solas." 'INFO'
            }
        }
    }
    Write-Log "===== RESTAURACION COMPLETADA (reinicia el equipo) =====" 'STEP'
}

# ----------------------------------------------------------------------------
#  Punto de entrada
# ----------------------------------------------------------------------------
try {
    Write-Host ""
    Write-Host "  Repair-M365CredentialCache  |  Mode=$Mode  DryRun=$($script:DryRun)" -ForegroundColor Cyan
    switch ($Mode) {
        'Diagnose' { Invoke-Diagnose }
        'Repair'   { Invoke-Repair }
        'Restore'  { Invoke-Restore }
    }
    exit 0
} catch {
    Write-Log "ERROR FATAL: $($_.Exception.Message)" 'ERROR'
    Write-Log ($_.ScriptStackTrace) 'ERROR'
    exit 1
}
