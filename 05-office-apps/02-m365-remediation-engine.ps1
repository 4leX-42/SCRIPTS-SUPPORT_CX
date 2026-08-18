#Requires -Version 5.1

<#
.SYNOPSIS
    [ES] Motor desatendido que diagnostica y repara OneDrive, Outlook, Office, identidad y red.
    [EN] Unattended engine that diagnoses and repairs OneDrive, Outlook, Office, identity and network.
.DESCRIPTION
    Autonomous troubleshooting motor that detects, classifies, and remediates
    issues across OneDrive, Outlook, Office Apps, and Authentication/Identity
    services in Microsoft 365 environments.

    Designed for mass deployment via Intune, GPO, or RMM platforms.
    Runs as SYSTEM or user context. Idempotent. Non-interactive.
.NOTES
    Version : 2.0.0
    Platform: Windows 11 / Windows 10 21H2+
    PSVer   : 5.1+
    Context : SYSTEM or CurrentUser
#>

[CmdletBinding()]
param(
    [ValidateSet('Auto','OneDrive','Outlook','Office','Auth','Network')]
    [string]$TargetService = 'Auto',

    [ValidateRange(1,5)]
    [int]$MaxLevel = 5,

    [switch]$DiagnosticOnly,

    [string]$LogPath = 'C:\ProgramData\M365Remediation\Logs'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region ============================================================
#  GLOBAL STATE
#region ============================================================

$script:RunTimestamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:LogFile        = $null
$script:DiagResult     = @{
    Category        = 'UNKNOWN'
    AffectedService = @()
    Details         = @()
    EnvironmentOk   = $true
}
$script:RemediationLog = [System.Collections.Generic.List[PSObject]]::new()

# Classification categories
$script:Categories = @(
    'ONEDRIVE_SYNC_ISSUE',
    'ONEDRIVE_CLIENT_HUNG',
    'OUTLOOK_PROFILE_CORRUPT',
    'OUTLOOK_NOT_OPENING',
    'OFFICE_ACTIVATION_ISSUE',
    'OFFICE_APP_CRASH',
    'AUTH_TOKEN_ISSUE',
    'NETWORK_OR_PROXY_ISSUE',
    'UNKNOWN'
)

#endregion

#region ============================================================
#  LOGGING MODULE
#region ============================================================

function Initialize-Logging {
    if (-not (Test-Path $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }
    $script:LogFile = Join-Path $LogPath "M365Remediation_$($script:RunTimestamp).log"
    Write-Log -Level INFO -Module CORE -Action Initialize -Result "Logging started at $($script:LogFile)"
}

function Write-Log {
    param(
        [ValidateSet('INFO','WARN','ERROR','SUCCESS')]
        [string]$Level,
        [string]$Module,
        [string]$Action,
        [string]$Result
    )
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] [$Module] [$Action] [$Result]"

    if ($script:LogFile) {
        try { $line | Out-File -FilePath $script:LogFile -Append -Encoding UTF8 } catch {}
    }

    switch ($Level) {
        'ERROR'   { Write-Warning $line }
        'WARN'    { Write-Warning $line }
        default   { Write-Verbose $line }
    }

    $script:RemediationLog.Add([PSCustomObject]@{
        Timestamp = $ts; Level = $Level; Module = $Module
        Action = $Action; Result = $Result
    })
}

#endregion

#region ============================================================
#  ENVIRONMENT VALIDATION
#region ============================================================

function Test-M365Connectivity {
    [CmdletBinding()]
    param()

    $endpoints = @(
        @{ Name = 'login.microsoftonline.com';   Port = 443 }
        @{ Name = 'outlook.office365.com';        Port = 443 }
        @{ Name = 'graph.microsoft.com';          Port = 443 }
        @{ Name = 'onedrive.live.com';            Port = 443 }
        @{ Name = 'officecdn.microsoft.com';      Port = 443 }
    )

    $results = @{}
    foreach ($ep in $endpoints) {
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $ar  = $tcp.BeginConnect($ep.Name, $ep.Port, $null, $null)
            $ok  = $ar.AsyncWaitHandle.WaitOne(5000, $false)
            if ($ok -and $tcp.Connected) {
                $results[$ep.Name] = $true
                Write-Log -Level INFO -Module NETWORK -Action "TestEndpoint:$($ep.Name)" -Result 'REACHABLE'
            } else {
                $results[$ep.Name] = $false
                Write-Log -Level WARN -Module NETWORK -Action "TestEndpoint:$($ep.Name)" -Result 'UNREACHABLE'
            }
            $tcp.Close()
        } catch {
            $results[$ep.Name] = $false
            Write-Log -Level ERROR -Module NETWORK -Action "TestEndpoint:$($ep.Name)" -Result $_.Exception.Message
        }
    }
    return $results
}

function Test-DnsResolution {
    $hosts = @('login.microsoftonline.com','outlook.office365.com','graph.microsoft.com')
    $ok = $true
    foreach ($h in $hosts) {
        try {
            $r = @([System.Net.Dns]::GetHostAddresses($h))
            if ($r.Count -eq 0) { $ok = $false; Write-Log -Level WARN -Module NETWORK -Action "DNS:$h" -Result 'NO_RECORDS' }
            else { Write-Log -Level INFO -Module NETWORK -Action "DNS:$h" -Result ($r.IPAddressToString -join ',') }
        } catch {
            $ok = $false
            Write-Log -Level ERROR -Module NETWORK -Action "DNS:$h" -Result $_.Exception.Message
        }
    }
    return $ok
}

function Test-NtpDrift {
    try {
        $w32tm = & w32tm /stripchart /computer:time.windows.com /dataonly /samples:1 2>&1
        $line  = $w32tm | Select-String -Pattern '[\+\-]\d+\.\d+s' | Select-Object -Last 1
        if ($line -match '([\+\-]?\d+\.\d+)s') {
            $drift = [math]::Abs([double]$Matches[1])
            if ($drift -gt 120) {
                Write-Log -Level WARN -Module NETWORK -Action 'NTPDrift' -Result "${drift}s drift detected"
                return $false
            }
            Write-Log -Level INFO -Module NETWORK -Action 'NTPDrift' -Result "${drift}s (OK)"
            return $true
        }
        Write-Log -Level WARN -Module NETWORK -Action 'NTPDrift' -Result 'UNABLE_TO_PARSE'
        return $true
    } catch {
        Write-Log -Level WARN -Module NETWORK -Action 'NTPDrift' -Result $_.Exception.Message
        return $true
    }
}

function Test-ProxyConfiguration {
    $proxyInfo = @{ HasProxy = $false; ProxyServer = ''; PacUrl = '' }
    try {
        $reg = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
        if ($reg.ProxyEnable -eq 1) {
            $proxyInfo.HasProxy    = $true
            $proxyInfo.ProxyServer = $reg.ProxyServer
            Write-Log -Level INFO -Module NETWORK -Action 'ProxyDetect' -Result "Proxy: $($reg.ProxyServer)"
        }
        $autoConfigUrl = $null
        try { $autoConfigUrl = $reg.AutoConfigURL } catch {}
        if ($autoConfigUrl) {
            $proxyInfo.PacUrl = $autoConfigUrl
            Write-Log -Level INFO -Module NETWORK -Action 'PACDetect' -Result "PAC: $autoConfigUrl"
        }
        $wpProxy = [System.Net.WebRequest]::GetSystemWebProxy()
        $testUri = [Uri]'https://login.microsoftonline.com'
        $resolved = $wpProxy.GetProxy($testUri)
        if ($resolved.AbsoluteUri -ne $testUri.AbsoluteUri) {
            $proxyInfo.HasProxy = $true
            Write-Log -Level INFO -Module NETWORK -Action 'SystemProxy' -Result "Resolved proxy: $($resolved.AbsoluteUri)"
        }
    } catch {
        Write-Log -Level WARN -Module NETWORK -Action 'ProxyDetect' -Result $_.Exception.Message
    }
    return $proxyInfo
}

function Test-InternetConnection {
    try {
        $req = [System.Net.HttpWebRequest]::Create('http://www.msftconnecttest.com/connecttest.txt')
        $req.Timeout = 10000
        $req.Method  = 'GET'
        $resp = $req.GetResponse()
        $sr   = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $body = $sr.ReadToEnd()
        $sr.Close(); $resp.Close()
        $connected = $body -match 'Microsoft Connect Test'
        Write-Log -Level $(if ($connected) {'INFO'} else {'WARN'}) -Module NETWORK -Action 'InternetTest' -Result $(if ($connected) {'CONNECTED'} else {'NO_INTERNET'})
        return $connected
    } catch {
        Write-Log -Level ERROR -Module NETWORK -Action 'InternetTest' -Result $_.Exception.Message
        return $false
    }
}

function Invoke-EnvironmentValidation {
    Write-Log -Level INFO -Module CORE -Action 'EnvValidation' -Result 'Starting environment checks'

    $internet = Test-InternetConnection
    $dns      = Test-DnsResolution
    $ntp      = Test-NtpDrift
    $proxy    = Test-ProxyConfiguration
    $m365     = Test-M365Connectivity

    $allEndpointsOk = @($m365.Values | Where-Object { $_ -eq $false }).Count -eq 0

    if (-not $internet -or -not $dns) {
        $script:DiagResult.Category    = 'NETWORK_OR_PROXY_ISSUE'
        $script:DiagResult.EnvironmentOk = $false
        $script:DiagResult.Details += 'Base connectivity or DNS failure detected'
        Write-Log -Level ERROR -Module CORE -Action 'EnvValidation' -Result 'NETWORK_FAILURE'
    } elseif (-not $allEndpointsOk) {
        $failed = ($m365.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key }) -join ', '
        $script:DiagResult.Details += "Unreachable M365 endpoints: $failed"
        Write-Log -Level WARN -Module CORE -Action 'EnvValidation' -Result "Some endpoints unreachable: $failed"
    }

    if (-not $ntp) {
        $script:DiagResult.Details += 'NTP drift > 2 minutes - may cause auth failures'
    }

    if ($proxy.HasProxy) {
        $script:DiagResult.Details += "Proxy detected: $($proxy.ProxyServer) $($proxy.PacUrl)"
    }

    Write-Log -Level INFO -Module CORE -Action 'EnvValidation' -Result 'Environment validation complete'
}

#endregion

#region ============================================================
#  PHASE 0 - INTELLIGENT DETECTION
#region ============================================================

function Get-ProcessHealth {
    param([string]$ProcessName)
    $procs = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if (-not $procs) {
        return @{ Running = $false; Count = 0; Responding = $false; Hung = $false; Ids = @() }
    }
    $hung = @($procs | Where-Object { -not $_.Responding })
    return @{
        Running    = $true
        Count      = $procs.Count
        Responding = ($hung.Count -eq 0)
        Hung       = ($hung.Count -gt 0)
        Ids        = @($procs.Id)
    }
}

function Get-RecentEventLogs {
    param(
        [string]$LogName = 'Application',
        [string[]]$SourceFilter,
        [int]$Hours = 2,
        [string[]]$LevelFilter = @('Error','Warning')
    )
    $after  = (Get-Date).AddHours(-$Hours)
    $filter = @{ LogName = $LogName; StartTime = $after }
    $levels = [System.Collections.Generic.List[int]]::new()
    if ($LevelFilter -contains 'Error')   { $levels.Add(1); $levels.Add(2) }
    if ($LevelFilter -contains 'Warning') { $levels.Add(3) }
    if ($levels.Count -gt 0) { $filter['Level'] = @($levels) }

    try {
        $raw = Get-WinEvent -FilterHashtable $filter -MaxEvents 50 -ErrorAction SilentlyContinue
        if (-not $raw) { return ,@() }
        $events = @($raw)
        if ($SourceFilter) {
            $events = @($events | Where-Object { $_ -and $SourceFilter -contains $_.ProviderName })
        }
        return ,$events
    } catch {
        return ,@()
    }
}

function Test-OneDriveHealth {
    Write-Log -Level INFO -Module ONEDRIVE -Action 'HealthCheck' -Result 'Starting'

    $issues = @()
    $proc   = Get-ProcessHealth -ProcessName 'OneDrive'

    if (-not $proc.Running) {
        $issues += 'ONEDRIVE_NOT_RUNNING'
        Write-Log -Level WARN -Module ONEDRIVE -Action 'ProcessCheck' -Result 'NOT_RUNNING'
    } elseif ($proc.Hung) {
        $issues += 'ONEDRIVE_HUNG'
        Write-Log -Level WARN -Module ONEDRIVE -Action 'ProcessCheck' -Result 'HUNG'
    }

    # Check OneDrive logs for errors
    $odLogPath = Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\logs\Business1'
    if (-not (Test-Path $odLogPath)) {
        $odLogPath = Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\logs\Personal'
    }
    if (Test-Path $odLogPath) {
        $recentLogs = Get-ChildItem -Path $odLogPath -Filter '*.odl' -ErrorAction SilentlyContinue |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($recentLogs) {
            $age = (Get-Date) - $recentLogs.LastWriteTime
            if ($age.TotalHours -gt 6 -and $proc.Running) {
                $issues += 'ONEDRIVE_STALE_LOGS'
                Write-Log -Level WARN -Module ONEDRIVE -Action 'LogCheck' -Result 'Logs stale (>6h)'
            }
        }
    }

    # Check sync status via registry
    $syncIssue = $false
    $odSettingsPath = 'HKCU:\Software\Microsoft\OneDrive\Accounts'
    if (Test-Path $odSettingsPath) {
        $accounts = Get-ChildItem $odSettingsPath -ErrorAction SilentlyContinue
        foreach ($acc in $accounts) {
            $props = Get-ItemProperty -Path $acc.PSPath -ErrorAction SilentlyContinue
            $signInErr = $null; try { $signInErr = $props.LastSignInErrorCode } catch {}
            if ($signInErr -and $signInErr -ne 0) {
                $syncIssue = $true
                $issues += 'ONEDRIVE_SIGNIN_ERROR'
                Write-Log -Level WARN -Module ONEDRIVE -Action 'RegistryCheck' -Result "SignInError: $($props.LastSignInErrorCode)"
            }
        }
    }

    # Event log check
    $events = Get-RecentEventLogs -SourceFilter @('Microsoft OneDrive','OneDriveSetup') -Hours 2
    if ($events.Count -gt 5) {
        $issues += 'ONEDRIVE_EXCESSIVE_ERRORS'
        Write-Log -Level WARN -Module ONEDRIVE -Action 'EventLogCheck' -Result "$($events.Count) recent errors"
    }

    return $issues
}

function Test-OutlookHealth {
    Write-Log -Level INFO -Module OUTLOOK -Action 'HealthCheck' -Result 'Starting'

    $issues = @()
    $proc   = Get-ProcessHealth -ProcessName 'OUTLOOK'

    if (-not $proc.Running) {
        # Check if Outlook should be running (was recently running)
        $crashEvents = Get-RecentEventLogs -SourceFilter @('Application Error','Microsoft Outlook') -Hours 1
        $outlookCrashes = @($crashEvents | Where-Object { $_.Message -match 'OUTLOOK|outlook' })
        if ($outlookCrashes) {
            $issues += 'OUTLOOK_CRASHED'
            Write-Log -Level WARN -Module OUTLOOK -Action 'CrashDetect' -Result 'Recent crash events found'
        }
    } elseif ($proc.Hung) {
        $issues += 'OUTLOOK_HUNG'
        Write-Log -Level WARN -Module OUTLOOK -Action 'ProcessCheck' -Result 'HUNG'
    }

    # Check OST file health
    $ostPath = Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook'
    if (Test-Path $ostPath) {
        $ostFiles = Get-ChildItem -Path $ostPath -Filter '*.ost' -ErrorAction SilentlyContinue
        foreach ($ost in $ostFiles) {
            if ($ost.Length -gt 50GB) {
                $issues += 'OUTLOOK_OST_OVERSIZED'
                Write-Log -Level WARN -Module OUTLOOK -Action 'OSTCheck' -Result "OST oversized: $([math]::Round($ost.Length/1GB,2))GB"
            }
            # Check if locked (in-use/corrupted)
            try {
                $fs = [System.IO.File]::Open($ost.FullName, 'Open', 'Read', 'Read')
                $fs.Close()
            } catch {
                if (-not $proc.Running) {
                    $issues += 'OUTLOOK_OST_LOCKED'
                    Write-Log -Level WARN -Module OUTLOOK -Action 'OSTCheck' -Result "OST locked without Outlook running: $($ost.Name)"
                }
            }
        }
    }

    # Check profile integrity via registry
    $profilePath = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Profiles'
    if (Test-Path $profilePath) {
        $profiles = @(Get-ChildItem $profilePath -ErrorAction SilentlyContinue)
        if ($profiles.Count -eq 0) {
            $issues += 'OUTLOOK_NO_PROFILE'
            Write-Log -Level WARN -Module OUTLOOK -Action 'ProfileCheck' -Result 'No profiles found'
        }
    } else {
        $issues += 'OUTLOOK_NO_PROFILE_KEY'
        Write-Log -Level WARN -Module OUTLOOK -Action 'ProfileCheck' -Result 'Profile registry key missing'
    }

    # Outlook-specific event log errors
    $events = Get-RecentEventLogs -SourceFilter @('Microsoft Outlook','Outlook') -Hours 2
    if ($events.Count -gt 3) {
        $issues += 'OUTLOOK_EVENT_ERRORS'
        Write-Log -Level WARN -Module OUTLOOK -Action 'EventLogCheck' -Result "$($events.Count) recent errors"
    }

    return $issues
}

function Test-OfficeHealth {
    Write-Log -Level INFO -Module OFFICE -Action 'HealthCheck' -Result 'Starting'

    $issues   = @()
    $offApps  = @('WINWORD','EXCEL','POWERPNT','MSACCESS','MSPUB')

    foreach ($app in $offApps) {
        $proc = Get-ProcessHealth -ProcessName $app
        if ($proc.Hung) {
            $issues += "OFFICE_APP_HUNG:$app"
            Write-Log -Level WARN -Module OFFICE -Action "ProcessCheck:$app" -Result 'HUNG'
        }
    }

    # Activation check
    $licPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    if (Test-Path $licPath) {
        $config = Get-ItemProperty -Path $licPath -ErrorAction SilentlyContinue
        $scl = $null; try { $scl = $config.SharedComputerLicensing } catch {}
        if ($scl -eq 1) {
            Write-Log -Level INFO -Module OFFICE -Action 'LicenseCheck' -Result 'SharedComputerLicensing enabled'
        }
        # Check version channel
        $cdn = $null; try { $cdn = $config.CDNBaseUrl } catch {}
        if ($cdn) {
            Write-Log -Level INFO -Module OFFICE -Action 'ChannelCheck' -Result "Channel: $cdn"
        }
    }

    # Check for licensing tokens
    $tokenPath = Join-Path $env:LOCALAPPDATA 'Microsoft\Office\Licenses5'
    if (-not (Test-Path $tokenPath) -or @(Get-ChildItem $tokenPath -ErrorAction SilentlyContinue).Count -eq 0) {
        $tokenPathAlt = Join-Path $env:LOCALAPPDATA 'Microsoft\Office\16.0\Licensing'
        if (-not (Test-Path $tokenPathAlt) -or @(Get-ChildItem $tokenPathAlt -ErrorAction SilentlyContinue).Count -eq 0) {
            $issues += 'OFFICE_NO_LICENSE_TOKENS'
            Write-Log -Level WARN -Module OFFICE -Action 'LicenseCheck' -Result 'No license tokens found'
        }
    }

    # Application crash events
    $events = Get-RecentEventLogs -SourceFilter @('Application Error','Microsoft Office Alerts','OAlerts') -Hours 2
    $officeCrashes = @($events | Where-Object {
        $_.Message -match 'WINWORD|EXCEL|POWERPNT|OUTLOOK|OfficeClickToRun'
    })
    if ($officeCrashes.Count -gt 2) {
        $issues += 'OFFICE_FREQUENT_CRASHES'
        Write-Log -Level WARN -Module OFFICE -Action 'CrashDetect' -Result "$($officeCrashes.Count) crash events"
    }

    # Click-to-Run service
    $c2rSvc = Get-Service -Name 'ClickToRunSvc' -ErrorAction SilentlyContinue
    if ($c2rSvc -and $c2rSvc.Status -ne 'Running') {
        $issues += 'OFFICE_C2R_STOPPED'
        Write-Log -Level WARN -Module OFFICE -Action 'C2RCheck' -Result "C2R service: $($c2rSvc.Status)"
    }

    return $issues
}

function Test-AuthHealth {
    Write-Log -Level INFO -Module AUTH -Action 'HealthCheck' -Result 'Starting'

    $issues = @()

    # AAD join status
    try {
        $dsregResult = & dsregcmd /status 2>&1
        $dsregText   = $dsregResult -join "`n"

        if ($dsregText -match 'AzureAdJoined\s*:\s*YES') {
            Write-Log -Level INFO -Module AUTH -Action 'AADJoinCheck' -Result 'AzureAD Joined'
        } elseif ($dsregText -match 'DomainJoined\s*:\s*YES') {
            Write-Log -Level INFO -Module AUTH -Action 'DomainCheck' -Result 'Domain Joined'
        }

        if ($dsregText -match 'AzureAdPrt\s*:\s*NO') {
            $issues += 'AUTH_NO_PRT'
            Write-Log -Level WARN -Module AUTH -Action 'PRTCheck' -Result 'No Primary Refresh Token'
        } elseif ($dsregText -match 'AzureAdPrt\s*:\s*YES') {
            Write-Log -Level INFO -Module AUTH -Action 'PRTCheck' -Result 'PRT present'
        }

        if ($dsregText -match 'AzureAdPrtAuthority\s*:\s*(.+)') {
            Write-Log -Level INFO -Module AUTH -Action 'PRTAuthority' -Result $Matches[1].Trim()
        }
    } catch {
        $issues += 'AUTH_DSREG_FAILED'
        Write-Log -Level ERROR -Module AUTH -Action 'DSRegCmd' -Result $_.Exception.Message
    }

    # WAM / token broker
    $tokenBroker = Get-Process -Name 'Microsoft.AAD.BrokerPlugin' -ErrorAction SilentlyContinue
    if (-not $tokenBroker) {
        # Not critical - starts on demand
        Write-Log -Level INFO -Module AUTH -Action 'TokenBroker' -Result 'Not running (on-demand)'
    }

    # Credential Manager entries
    try {
        $cmdkeyOutput = & cmdkey /list 2>&1
        $m365Creds = @($cmdkeyOutput | Select-String -Pattern 'microsoftonline|office|outlook|sharepoint').Count
        if ($m365Creds -eq 0) {
            $issues += 'AUTH_NO_CACHED_CREDS'
            Write-Log -Level WARN -Module AUTH -Action 'CredentialCheck' -Result 'No M365 credentials cached'
        } else {
            Write-Log -Level INFO -Module AUTH -Action 'CredentialCheck' -Result "$m365Creds M365 credential entries"
        }
    } catch {
        Write-Log -Level WARN -Module AUTH -Action 'CredentialCheck' -Result $_.Exception.Message
    }

    return $issues
}

function Invoke-SmartDiagnosis {
    Write-Log -Level INFO -Module CORE -Action 'Diagnosis' -Result 'Starting intelligent detection'

    # Environment first
    Invoke-EnvironmentValidation

    if (-not $script:DiagResult.EnvironmentOk) {
        Write-Log -Level ERROR -Module CORE -Action 'Diagnosis' -Result "Classification: $($script:DiagResult.Category)"
        return
    }

    # Collect all health signals
    $odIssues   = Test-OneDriveHealth
    $olIssues   = Test-OutlookHealth
    $offIssues  = Test-OfficeHealth
    $authIssues = Test-AuthHealth

    # Classification logic - prioritize by severity
    if ($authIssues -contains 'AUTH_NO_PRT') {
        $script:DiagResult.Category = 'AUTH_TOKEN_ISSUE'
        $script:DiagResult.AffectedService += 'Auth'
    }

    if ($odIssues -contains 'ONEDRIVE_HUNG') {
        $script:DiagResult.Category = 'ONEDRIVE_CLIENT_HUNG'
        $script:DiagResult.AffectedService += 'OneDrive'
    } elseif ($odIssues | Where-Object { $_ -match 'SYNC|SIGNIN|STALE' }) {
        $script:DiagResult.Category = 'ONEDRIVE_SYNC_ISSUE'
        $script:DiagResult.AffectedService += 'OneDrive'
    }

    if ($olIssues -contains 'OUTLOOK_HUNG' -or $olIssues -contains 'OUTLOOK_CRASHED') {
        $script:DiagResult.Category = 'OUTLOOK_NOT_OPENING'
        $script:DiagResult.AffectedService += 'Outlook'
    } elseif ($olIssues | Where-Object { $_ -match 'PROFILE|OST' }) {
        $script:DiagResult.Category = 'OUTLOOK_PROFILE_CORRUPT'
        $script:DiagResult.AffectedService += 'Outlook'
    }

    if ($offIssues | Where-Object { $_ -match 'LICENSE|ACTIVATION' }) {
        $script:DiagResult.Category = 'OFFICE_ACTIVATION_ISSUE'
        $script:DiagResult.AffectedService += 'Office'
    } elseif ($offIssues | Where-Object { $_ -match 'CRASH|HUNG' }) {
        $script:DiagResult.Category = 'OFFICE_APP_CRASH'
        $script:DiagResult.AffectedService += 'Office'
    }

    # If only auth issues and nothing else
    if ($script:DiagResult.AffectedService.Count -eq 0 -and $authIssues.Count -gt 0) {
        $script:DiagResult.Category = 'AUTH_TOKEN_ISSUE'
        $script:DiagResult.AffectedService += 'Auth'
    }

    # If nothing detected
    if ($script:DiagResult.AffectedService.Count -eq 0) {
        $script:DiagResult.Category = 'UNKNOWN'
        Write-Log -Level INFO -Module CORE -Action 'Diagnosis' -Result 'No actionable issues detected'
    }

    $script:DiagResult.Details += "OneDrive: $($odIssues -join ', ')"
    $script:DiagResult.Details += "Outlook:  $($olIssues -join ', ')"
    $script:DiagResult.Details += "Office:   $($offIssues -join ', ')"
    $script:DiagResult.Details += "Auth:     $($authIssues -join ', ')"

    Write-Log -Level INFO -Module CORE -Action 'Diagnosis' -Result "Classification: $($script:DiagResult.Category)"
    Write-Log -Level INFO -Module CORE -Action 'Diagnosis' -Result "Affected: $($script:DiagResult.AffectedService -join ', ')"
}

#endregion

#region ============================================================
#  REMEDIATION - ONEDRIVE
#region ============================================================

function Find-OneDriveExe {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'),
        (Join-Path ${env:ProgramFiles} 'Microsoft OneDrive\OneDrive.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive\OneDrive.exe'),
        'C:\Program Files\Microsoft OneDrive\OneDrive.exe',
        'C:\Program Files (x86)\Microsoft OneDrive\OneDrive.exe'
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) {
            Write-Log -Level INFO -Module ONEDRIVE -Action 'FindExe' -Result $c
            return $c
        }
    }
    Write-Log -Level ERROR -Module ONEDRIVE -Action 'FindExe' -Result 'NOT_FOUND'
    return $null
}

function Test-OneDriveRecovery {
    Start-Sleep -Seconds 5
    $proc = Get-ProcessHealth -ProcessName 'OneDrive'
    if ($proc.Running -and $proc.Responding) {
        Write-Log -Level SUCCESS -Module ONEDRIVE -Action 'Validation' -Result 'Process running and responding'
        return $true
    }
    Write-Log -Level WARN -Module ONEDRIVE -Action 'Validation' -Result "Running=$($proc.Running) Responding=$($proc.Responding)"
    return $false
}

function Invoke-OneDriveRemediation {
    [CmdletBinding()]
    param([int]$MaxLevel = 5)

    Write-Log -Level INFO -Module ONEDRIVE -Action 'Remediation' -Result 'Starting escalated remediation'

    # --- Level 1: Kill & Restart ---
    if ($MaxLevel -ge 1) {
        Write-Log -Level INFO -Module ONEDRIVE -Action 'Level1' -Result 'Kill and restart'
        try {
            Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            $exe = Find-OneDriveExe
            if ($exe) {
                Start-Process -FilePath $exe -ErrorAction SilentlyContinue
                if (Test-OneDriveRecovery) {
                    Write-Log -Level SUCCESS -Module ONEDRIVE -Action 'Level1' -Result 'RESOLVED'
                    return $true
                }
            }
        } catch {
            Write-Log -Level ERROR -Module ONEDRIVE -Action 'Level1' -Result $_.Exception.Message
        }
    }

    # --- Level 2: /reset ---
    if ($MaxLevel -ge 2) {
        Write-Log -Level INFO -Module ONEDRIVE -Action 'Level2' -Result 'OneDrive /reset'
        try {
            Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            $exe = Find-OneDriveExe
            if ($exe) {
                $resetProc = Start-Process -FilePath $exe -ArgumentList '/reset' -PassThru -Wait -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 5
                # Relaunch
                Start-Process -FilePath $exe -ErrorAction SilentlyContinue
                if (Test-OneDriveRecovery) {
                    Write-Log -Level SUCCESS -Module ONEDRIVE -Action 'Level2' -Result 'RESOLVED'
                    return $true
                }
            }
        } catch {
            Write-Log -Level ERROR -Module ONEDRIVE -Action 'Level2' -Result $_.Exception.Message
        }
    }

    # --- Level 3: Cache cleanup (preserve synced data) ---
    if ($MaxLevel -ge 3) {
        Write-Log -Level INFO -Module ONEDRIVE -Action 'Level3' -Result 'Cache cleanup'
        try {
            Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3

            $cachePaths = @(
                (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\logs'),
                (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\setup\logs'),
                (Join-Path $env:APPDATA 'Microsoft\OneDrive\logs')
            )
            foreach ($cp in $cachePaths) {
                if (Test-Path $cp) {
                    Remove-Item -Path $cp -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Log -Level INFO -Module ONEDRIVE -Action 'CleanCache' -Result "Cleaned: $cp"
                }
            }

            $exe = Find-OneDriveExe
            if ($exe) {
                Start-Process -FilePath $exe -ErrorAction SilentlyContinue
                if (Test-OneDriveRecovery) {
                    Write-Log -Level SUCCESS -Module ONEDRIVE -Action 'Level3' -Result 'RESOLVED'
                    return $true
                }
            }
        } catch {
            Write-Log -Level ERROR -Module ONEDRIVE -Action 'Level3' -Result $_.Exception.Message
        }
    }

    # --- Level 4: Validate binaries ---
    if ($MaxLevel -ge 4) {
        Write-Log -Level INFO -Module ONEDRIVE -Action 'Level4' -Result 'Binary validation'
        try {
            $exe = Find-OneDriveExe
            if (-not $exe) {
                Write-Log -Level ERROR -Module ONEDRIVE -Action 'Level4' -Result 'No valid binary found - escalate to Level 5'
            } else {
                $sig = Get-AuthenticodeSignature -FilePath $exe -ErrorAction SilentlyContinue
                if ($sig.Status -ne 'Valid') {
                    Write-Log -Level WARN -Module ONEDRIVE -Action 'Level4' -Result "Signature invalid: $($sig.Status)"
                } else {
                    Write-Log -Level INFO -Module ONEDRIVE -Action 'Level4' -Result 'Binary signature valid'
                    # Try reset again with fresh binary validation
                    Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                    Start-Process -FilePath $exe -ArgumentList '/reset' -Wait -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 5
                    Start-Process -FilePath $exe -ErrorAction SilentlyContinue
                    if (Test-OneDriveRecovery) {
                        Write-Log -Level SUCCESS -Module ONEDRIVE -Action 'Level4' -Result 'RESOLVED'
                        return $true
                    }
                }
            }
        } catch {
            Write-Log -Level ERROR -Module ONEDRIVE -Action 'Level4' -Result $_.Exception.Message
        }
    }

    # --- Level 5: Reinstall ---
    if ($MaxLevel -ge 5) {
        Write-Log -Level INFO -Module ONEDRIVE -Action 'Level5' -Result 'Reinstallation'
        try {
            Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3

            # Uninstall
            $setupPaths = @(
                (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\Update\OneDriveSetup.exe'),
                (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDriveSetup.exe'),
                'C:\Windows\SysWOW64\OneDriveSetup.exe'
            )
            $setupExe = $setupPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
            if ($setupExe) {
                Write-Log -Level INFO -Module ONEDRIVE -Action 'Uninstall' -Result "Using: $setupExe"
                Start-Process -FilePath $setupExe -ArgumentList '/uninstall' -Wait -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 5
            }

            # Reinstall
            if ($setupExe -and (Test-Path $setupExe)) {
                Write-Log -Level INFO -Module ONEDRIVE -Action 'Reinstall' -Result "Using: $setupExe"
                Start-Process -FilePath $setupExe -ArgumentList '/silent' -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 15
                if (Test-OneDriveRecovery) {
                    Write-Log -Level SUCCESS -Module ONEDRIVE -Action 'Level5' -Result 'RESOLVED'
                    return $true
                }
            } else {
                Write-Log -Level ERROR -Module ONEDRIVE -Action 'Level5' -Result 'No setup binary available for reinstall'
            }
        } catch {
            Write-Log -Level ERROR -Module ONEDRIVE -Action 'Level5' -Result $_.Exception.Message
        }
    }

    Write-Log -Level ERROR -Module ONEDRIVE -Action 'Remediation' -Result 'ALL_LEVELS_EXHAUSTED'
    return $false
}

#endregion

#region ============================================================
#  REMEDIATION - OUTLOOK
#region ============================================================

function Find-OutlookExe {
    $candidates = @(
        (Join-Path ${env:ProgramFiles} 'Microsoft Office\root\Office16\OUTLOOK.EXE'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Office\root\Office16\OUTLOOK.EXE'),
        'C:\Program Files\Microsoft Office\root\Office16\OUTLOOK.EXE',
        'C:\Program Files (x86)\Microsoft Office\root\Office16\OUTLOOK.EXE'
    )
    # Also check ClickToRun paths
    $c2rPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    if (Test-Path $c2rPath) {
        $installPath = $null; try { $installPath = (Get-ItemProperty -Path $c2rPath -ErrorAction SilentlyContinue).InstallationPath } catch {}
        if ($installPath) {
            $candidates = @((Join-Path $installPath 'root\Office16\OUTLOOK.EXE')) + $candidates
        }
    }

    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) {
            Write-Log -Level INFO -Module OUTLOOK -Action 'FindExe' -Result $c
            return $c
        }
    }
    Write-Log -Level ERROR -Module OUTLOOK -Action 'FindExe' -Result 'NOT_FOUND'
    return $null
}

function Test-OutlookRecovery {
    param([int]$WaitSeconds = 10)
    Start-Sleep -Seconds $WaitSeconds
    $proc = Get-ProcessHealth -ProcessName 'OUTLOOK'
    if ($proc.Running -and $proc.Responding) {
        Write-Log -Level SUCCESS -Module OUTLOOK -Action 'Validation' -Result 'Process running and responding'
        return $true
    }
    Write-Log -Level WARN -Module OUTLOOK -Action 'Validation' -Result "Running=$($proc.Running) Responding=$($proc.Responding)"
    return $false
}

function Invoke-OutlookRemediation {
    [CmdletBinding()]
    param([int]$MaxLevel = 5)

    Write-Log -Level INFO -Module OUTLOOK -Action 'Remediation' -Result 'Starting escalated remediation'

    # --- Level 1: Kill & Restart ---
    if ($MaxLevel -ge 1) {
        Write-Log -Level INFO -Module OUTLOOK -Action 'Level1' -Result 'Kill and restart'
        try {
            Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            $exe = Find-OutlookExe
            if ($exe) {
                Start-Process -FilePath $exe -ErrorAction SilentlyContinue
                if (Test-OutlookRecovery) {
                    Write-Log -Level SUCCESS -Module OUTLOOK -Action 'Level1' -Result 'RESOLVED'
                    return $true
                }
            }
        } catch {
            Write-Log -Level ERROR -Module OUTLOOK -Action 'Level1' -Result $_.Exception.Message
        }
    }

    # --- Level 2: Safe Mode ---
    if ($MaxLevel -ge 2) {
        Write-Log -Level INFO -Module OUTLOOK -Action 'Level2' -Result 'Safe Mode launch'
        try {
            Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            $exe = Find-OutlookExe
            if ($exe) {
                Start-Process -FilePath $exe -ArgumentList '/safe' -ErrorAction SilentlyContinue
                if (Test-OutlookRecovery -WaitSeconds 15) {
                    Write-Log -Level SUCCESS -Module OUTLOOK -Action 'Level2' -Result 'RESOLVED (safe mode)'
                    # Close safe mode and restart normally
                    Start-Sleep -Seconds 2
                    Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 3
                    Start-Process -FilePath $exe -ErrorAction SilentlyContinue
                    if (Test-OutlookRecovery) {
                        Write-Log -Level SUCCESS -Module OUTLOOK -Action 'Level2' -Result 'Normal mode restored'
                        return $true
                    }
                    # Safe mode works but normal doesn't - likely add-in issue
                    Write-Log -Level WARN -Module OUTLOOK -Action 'Level2' -Result 'Safe mode OK, normal mode fails - add-in conflict likely'
                    # Disable add-ins
                    $addinPath = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Resiliency\DisabledItems'
                    if (-not (Test-Path $addinPath)) {
                        New-Item -Path $addinPath -Force | Out-Null
                    }
                    # Disable load behavior for COM add-ins
                    $addinLoadPath = 'HKCU:\Software\Microsoft\Office\Outlook\Addins'
                    if (Test-Path $addinLoadPath) {
                        Get-ChildItem $addinLoadPath -ErrorAction SilentlyContinue | ForEach-Object {
                            Set-ItemProperty -Path $_.PSPath -Name 'LoadBehavior' -Value 0 -ErrorAction SilentlyContinue
                            Write-Log -Level INFO -Module OUTLOOK -Action 'DisableAddin' -Result $_.PSChildName
                        }
                    }
                    Start-Process -FilePath $exe -ErrorAction SilentlyContinue
                    if (Test-OutlookRecovery) {
                        Write-Log -Level SUCCESS -Module OUTLOOK -Action 'Level2' -Result 'RESOLVED after disabling add-ins'
                        return $true
                    }
                }
            }
        } catch {
            Write-Log -Level ERROR -Module OUTLOOK -Action 'Level2' -Result $_.Exception.Message
        }
    }

    # --- Level 3: Profile repair ---
    if ($MaxLevel -ge 3) {
        Write-Log -Level INFO -Module OUTLOOK -Action 'Level3' -Result 'Profile repair'
        try {
            Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3

            $profileRoot = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Profiles'
            if (Test-Path $profileRoot) {
                $profiles = Get-ChildItem $profileRoot -ErrorAction SilentlyContinue
                $defaultProfile = $null; try { $defaultProfile = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Office\16.0\Outlook' -Name 'DefaultProfile' -ErrorAction SilentlyContinue).DefaultProfile } catch {}

                if ($profiles.Count -gt 0 -and $defaultProfile) {
                    # Backup-rename corrupted profile
                    $backupName = "${defaultProfile}_backup_$(Get-Date -Format 'yyyyMMddHHmmss')"
                    $srcPath  = Join-Path $profileRoot $defaultProfile
                    if (Test-Path $srcPath) {
                        Rename-Item -Path $srcPath -NewName $backupName -ErrorAction SilentlyContinue
                        Write-Log -Level INFO -Module OUTLOOK -Action 'ProfileBackup' -Result "Renamed to $backupName"
                    }
                }

                # Create a new default profile via registry - Outlook will run first-run wizard
                $newProfileName = 'Outlook_Remediated'
                New-Item -Path (Join-Path $profileRoot $newProfileName) -Force | Out-Null
                Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Office\16.0\Outlook' -Name 'DefaultProfile' -Value $newProfileName
                Write-Log -Level INFO -Module OUTLOOK -Action 'NewProfile' -Result "Created profile: $newProfileName"

                $exe = Find-OutlookExe
                if ($exe) {
                    Start-Process -FilePath $exe -ErrorAction SilentlyContinue
                    if (Test-OutlookRecovery -WaitSeconds 20) {
                        Write-Log -Level SUCCESS -Module OUTLOOK -Action 'Level3' -Result 'RESOLVED with new profile'
                        return $true
                    }
                }
            }
        } catch {
            Write-Log -Level ERROR -Module OUTLOOK -Action 'Level3' -Result $_.Exception.Message
        }
    }

    # --- Level 4: OST rebuild ---
    if ($MaxLevel -ge 4) {
        Write-Log -Level INFO -Module OUTLOOK -Action 'Level4' -Result 'OST rebuild'
        try {
            Get-Process -Name 'OUTLOOK' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5

            $ostDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Outlook'
            if (Test-Path $ostDir) {
                $ostFiles = Get-ChildItem -Path $ostDir -Filter '*.ost' -ErrorAction SilentlyContinue
                foreach ($ost in $ostFiles) {
                    $backupName = "$($ost.BaseName)_backup_$(Get-Date -Format 'yyyyMMddHHmmss').ost"
                    $backupPath = Join-Path $ostDir $backupName
                    try {
                        Rename-Item -Path $ost.FullName -NewName $backupName -ErrorAction Stop
                        Write-Log -Level INFO -Module OUTLOOK -Action 'OSTBackup' -Result "Renamed: $($ost.Name) -> $backupName"
                    } catch {
                        # File might be locked
                        Write-Log -Level WARN -Module OUTLOOK -Action 'OSTBackup' -Result "Cannot rename $($ost.Name): $($_.Exception.Message)"
                    }
                }
            }

            $exe = Find-OutlookExe
            if ($exe) {
                Start-Process -FilePath $exe -ErrorAction SilentlyContinue
                if (Test-OutlookRecovery -WaitSeconds 20) {
                    Write-Log -Level SUCCESS -Module OUTLOOK -Action 'Level4' -Result 'RESOLVED - OST will resync'
                    return $true
                }
            }
        } catch {
            Write-Log -Level ERROR -Module OUTLOOK -Action 'Level4' -Result $_.Exception.Message
        }
    }

    # --- Level 5: Office Repair ---
    if ($MaxLevel -ge 5) {
        Write-Log -Level INFO -Module OUTLOOK -Action 'Level5' -Result 'Office repair for Outlook'
        try {
            $repaired = Invoke-OfficeRepair -RepairType 'Quick'
            if ($repaired) {
                $exe = Find-OutlookExe
                if ($exe) {
                    Start-Process -FilePath $exe -ErrorAction SilentlyContinue
                    if (Test-OutlookRecovery -WaitSeconds 20) {
                        Write-Log -Level SUCCESS -Module OUTLOOK -Action 'Level5' -Result 'RESOLVED after Quick Repair'
                        return $true
                    }
                }
            }

            # Online repair
            $repaired = Invoke-OfficeRepair -RepairType 'Online'
            if ($repaired) {
                $exe = Find-OutlookExe
                if ($exe) {
                    Start-Process -FilePath $exe -ErrorAction SilentlyContinue
                    if (Test-OutlookRecovery -WaitSeconds 30) {
                        Write-Log -Level SUCCESS -Module OUTLOOK -Action 'Level5' -Result 'RESOLVED after Online Repair'
                        return $true
                    }
                }
            }
        } catch {
            Write-Log -Level ERROR -Module OUTLOOK -Action 'Level5' -Result $_.Exception.Message
        }
    }

    Write-Log -Level ERROR -Module OUTLOOK -Action 'Remediation' -Result 'ALL_LEVELS_EXHAUSTED'
    return $false
}

#endregion

#region ============================================================
#  REMEDIATION - OFFICE (GENERAL)
#region ============================================================

function Stop-AllOfficeApps {
    $officeProcs = @('WINWORD','EXCEL','POWERPNT','MSACCESS','MSPUB','OUTLOOK','ONENOTE','lync','Teams')
    foreach ($p in $officeProcs) {
        $running = Get-Process -Name $p -ErrorAction SilentlyContinue
        if ($running) {
            $running | Stop-Process -Force -ErrorAction SilentlyContinue
            Write-Log -Level INFO -Module OFFICE -Action 'StopApp' -Result "Stopped: $p"
        }
    }
    Start-Sleep -Seconds 3
}

function Invoke-OfficeRepair {
    [CmdletBinding()]
    param(
        [ValidateSet('Quick','Online')]
        [string]$RepairType = 'Quick'
    )

    Write-Log -Level INFO -Module OFFICE -Action "Repair:$RepairType" -Result 'Starting'

    # Find ClickToRun executable
    $c2rClient = $null
    $c2rPaths = @(
        'C:\Program Files\Common Files\Microsoft Shared\ClickToRun\OfficeClickToRun.exe',
        'C:\Program Files (x86)\Common Files\Microsoft Shared\ClickToRun\OfficeClickToRun.exe'
    )
    $c2rClient = $c2rPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $c2rClient) {
        Write-Log -Level ERROR -Module OFFICE -Action "Repair:$RepairType" -Result 'ClickToRun client not found'
        return $false
    }

    try {
        $scenario = if ($RepairType -eq 'Quick') { 'RepairBoot' } else { 'Repair' }
        $platform = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }

        # Get product IDs from registry
        $c2rConfig = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
        $productIds = $null; try { $productIds = $c2rConfig.ProductReleaseIds } catch {}
        if (-not $productIds) {
            $productIds = 'O365ProPlusRetail'
            Write-Log -Level WARN -Module OFFICE -Action "Repair:$RepairType" -Result 'ProductReleaseIds not found, using default'
        }

        # Construct repair command
        $repairArgs = "scenario=$scenario platform=$platform culture=en-us productstorepair=$productIds"
        if ($RepairType -eq 'Online') {
            $repairArgs += ' forceappshutdown=True'
        }

        Write-Log -Level INFO -Module OFFICE -Action "Repair:$RepairType" -Result "Executing: $c2rClient $repairArgs"

        Stop-AllOfficeApps

        $process = Start-Process -FilePath $c2rClient -ArgumentList $repairArgs -PassThru -Wait -WindowStyle Hidden -ErrorAction Stop
        if ($process.ExitCode -eq 0) {
            Write-Log -Level SUCCESS -Module OFFICE -Action "Repair:$RepairType" -Result 'Repair completed successfully'
            return $true
        } else {
            Write-Log -Level WARN -Module OFFICE -Action "Repair:$RepairType" -Result "Exit code: $($process.ExitCode)"
            return $false
        }
    } catch {
        Write-Log -Level ERROR -Module OFFICE -Action "Repair:$RepairType" -Result $_.Exception.Message
        return $false
    }
}

function Invoke-OfficeGeneralRemediation {
    [CmdletBinding()]
    param([int]$MaxLevel = 4)

    Write-Log -Level INFO -Module OFFICE -Action 'Remediation' -Result 'Starting general Office remediation'

    # --- Level 1: Restart Apps ---
    if ($MaxLevel -ge 1) {
        Write-Log -Level INFO -Module OFFICE -Action 'Level1' -Result 'Restart all Office apps'
        try {
            Stop-AllOfficeApps
            Start-Sleep -Seconds 2

            # Restart ClickToRun service
            $c2rSvc = Get-Service -Name 'ClickToRunSvc' -ErrorAction SilentlyContinue
            if ($c2rSvc -and $c2rSvc.Status -ne 'Running') {
                Start-Service -Name 'ClickToRunSvc' -ErrorAction SilentlyContinue
                Write-Log -Level INFO -Module OFFICE -Action 'C2RRestart' -Result 'ClickToRun service restarted'
            }

            # Validate - try opening Word briefly
            $wordExe = @(
                (Join-Path ${env:ProgramFiles} 'Microsoft Office\root\Office16\WINWORD.EXE'),
                (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Office\root\Office16\WINWORD.EXE')
            ) | Where-Object { Test-Path $_ } | Select-Object -First 1

            if ($wordExe) {
                $wp = Start-Process -FilePath $wordExe -PassThru -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 8
                $proc = Get-ProcessHealth -ProcessName 'WINWORD'
                if ($proc.Running -and $proc.Responding) {
                    $wp | Stop-Process -Force -ErrorAction SilentlyContinue
                    Write-Log -Level SUCCESS -Module OFFICE -Action 'Level1' -Result 'RESOLVED'
                    return $true
                }
                $wp | Stop-Process -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Log -Level ERROR -Module OFFICE -Action 'Level1' -Result $_.Exception.Message
        }
    }

    # --- Level 2: Quick Repair ---
    if ($MaxLevel -ge 2) {
        Write-Log -Level INFO -Module OFFICE -Action 'Level2' -Result 'Quick Repair'
        if (Invoke-OfficeRepair -RepairType 'Quick') {
            Write-Log -Level SUCCESS -Module OFFICE -Action 'Level2' -Result 'RESOLVED'
            return $true
        }
    }

    # --- Level 3: Online Repair ---
    if ($MaxLevel -ge 3) {
        Write-Log -Level INFO -Module OFFICE -Action 'Level3' -Result 'Online Repair'
        if (Invoke-OfficeRepair -RepairType 'Online') {
            Write-Log -Level SUCCESS -Module OFFICE -Action 'Level3' -Result 'RESOLVED'
            return $true
        }
    }

    # --- Level 4: Reinstall fallback ---
    if ($MaxLevel -ge 4) {
        Write-Log -Level WARN -Module OFFICE -Action 'Level4' -Result 'Reinstall required - manual intervention or deployment tool needed'
        # Full reinstall requires ODT or Intune - log recommendation
        Write-Log -Level INFO -Module OFFICE -Action 'Level4' -Result 'Recommendation: Deploy via ODT setup.exe /configure or Intune Win32 app'
    }

    Write-Log -Level ERROR -Module OFFICE -Action 'Remediation' -Result 'ALL_LEVELS_EXHAUSTED'
    return $false
}

#endregion

#region ============================================================
#  REMEDIATION - AUTHENTICATION / TOKENS
#region ============================================================

function Invoke-AuthRemediation {
    [CmdletBinding()]
    param([switch]$ForceRejoin)

    Write-Log -Level INFO -Module AUTH -Action 'Remediation' -Result 'Starting authentication remediation'

    # Step 1: Clear selective credentials from Windows Credential Manager
    Write-Log -Level INFO -Module AUTH -Action 'ClearCredentials' -Result 'Removing M365-related credentials'
    try {
        $targets = @(
            'MicrosoftOffice16_Data:*',
            'Microsoft_OC1:*',
            'MicrosoftOffice15_Data:*',
            '*office*',
            '*microsoftonline*',
            '*sharepoint*'
        )

        $cmdkeyList = & cmdkey /list 2>&1
        foreach ($line in $cmdkeyList) {
            if ($line -match 'Target:\s*(.+)') {
                $target = $Matches[1].Trim()
                foreach ($pattern in $targets) {
                    if ($target -like $pattern) {
                        & cmdkey /delete:$target 2>&1 | Out-Null
                        Write-Log -Level INFO -Module AUTH -Action 'DeleteCredential' -Result "Removed: $target"
                        break
                    }
                }
            }
        }
    } catch {
        Write-Log -Level ERROR -Module AUTH -Action 'ClearCredentials' -Result $_.Exception.Message
    }

    # Step 2: Clear Office identity cache
    Write-Log -Level INFO -Module AUTH -Action 'ClearIdentityCache' -Result 'Clearing Office identity tokens'
    try {
        $identityPaths = @(
            'HKCU:\Software\Microsoft\Office\16.0\Common\Identity',
            'HKCU:\Software\Microsoft\Office\16.0\Common\Internet\WebServiceCache'
        )
        foreach ($idPath in $identityPaths) {
            if (Test-Path $idPath) {
                Remove-Item -Path $idPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log -Level INFO -Module AUTH -Action 'ClearIdentity' -Result "Cleared: $idPath"
            }
        }

        # Clear WAM token cache
        $wamPath = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.AAD.BrokerPlugin_*\AC\TokenBroker\Accounts'
        $wamDirs = Resolve-Path $wamPath -ErrorAction SilentlyContinue
        foreach ($dir in $wamDirs) {
            if (Test-Path $dir) {
                Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
                Write-Log -Level INFO -Module AUTH -Action 'ClearWAM' -Result "Cleared WAM cache: $dir"
            }
        }
    } catch {
        Write-Log -Level WARN -Module AUTH -Action 'ClearIdentityCache' -Result $_.Exception.Message
    }

    # Step 3: Clear Office license token files
    try {
        $licPaths = @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\Office\Licenses5'),
            (Join-Path $env:LOCALAPPDATA 'Microsoft\Office\16.0\Licensing')
        )
        foreach ($lp in $licPaths) {
            if (Test-Path $lp) {
                Get-ChildItem -Path $lp -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
                Write-Log -Level INFO -Module AUTH -Action 'ClearLicenseTokens' -Result "Cleared: $lp"
            }
        }
    } catch {
        Write-Log -Level WARN -Module AUTH -Action 'ClearLicenseTokens' -Result $_.Exception.Message
    }

    # Step 4: Force Azure AD PRT refresh (non-destructive)
    Write-Log -Level INFO -Module AUTH -Action 'PRTRefresh' -Result 'Attempting PRT refresh'
    try {
        $dsregStatus = & dsregcmd /status 2>&1
        $hasNoPrt = ($dsregStatus -join "`n") -match 'AzureAdPrt\s*:\s*NO'

        if ($hasNoPrt) {
            # Try refreshing PRT with /RefreshPrt (Win 10 2004+)
            & dsregcmd /RefreshPrt 2>&1 | Out-Null
            Start-Sleep -Seconds 5
            Write-Log -Level INFO -Module AUTH -Action 'PRTRefresh' -Result 'RefreshPrt command executed'
        }
    } catch {
        Write-Log -Level WARN -Module AUTH -Action 'PRTRefresh' -Result $_.Exception.Message
    }

    # Step 5: dsregcmd /leave + rejoin - ONLY if critical and explicitly requested
    if ($ForceRejoin) {
        Write-Log -Level WARN -Module AUTH -Action 'ForceRejoin' -Result 'Performing AAD leave + rejoin (CRITICAL ACTION)'
        try {
            & dsregcmd /leave 2>&1 | Out-Null
            Start-Sleep -Seconds 5
            & dsregcmd /join 2>&1 | Out-Null
            Start-Sleep -Seconds 10
            Write-Log -Level INFO -Module AUTH -Action 'ForceRejoin' -Result 'AAD rejoin completed'
        } catch {
            Write-Log -Level ERROR -Module AUTH -Action 'ForceRejoin' -Result $_.Exception.Message
        }
    }

    # Validate
    Start-Sleep -Seconds 3
    try {
        $dsregPost = & dsregcmd /status 2>&1
        $prtOk = ($dsregPost -join "`n") -match 'AzureAdPrt\s*:\s*YES'
        if ($prtOk) {
            Write-Log -Level SUCCESS -Module AUTH -Action 'Validation' -Result 'PRT present after remediation'
            return $true
        } else {
            Write-Log -Level WARN -Module AUTH -Action 'Validation' -Result 'PRT still not present - may require user re-authentication'
            return $false
        }
    } catch {
        Write-Log -Level ERROR -Module AUTH -Action 'Validation' -Result $_.Exception.Message
        return $false
    }
}

#endregion

#region ============================================================
#  POST-REMEDIATION VALIDATION
#region ============================================================

function Test-PostRemediationHealth {
    param([string[]]$Services)

    Write-Log -Level INFO -Module CORE -Action 'PostValidation' -Result 'Starting post-remediation validation'
    $results = @{}

    foreach ($svc in $Services) {
        switch ($svc) {
            'OneDrive' {
                $proc = Get-ProcessHealth -ProcessName 'OneDrive'
                $results['OneDrive'] = @{
                    ProcessActive    = $proc.Running
                    ProcessResponding = $proc.Responding
                    Status = if ($proc.Running -and $proc.Responding) { 'HEALTHY' } else { 'DEGRADED' }
                }
                Write-Log -Level $(if ($results['OneDrive'].Status -eq 'HEALTHY') {'SUCCESS'} else {'WARN'}) `
                    -Module ONEDRIVE -Action 'PostValidation' -Result $results['OneDrive'].Status
            }
            'Outlook' {
                $proc = Get-ProcessHealth -ProcessName 'OUTLOOK'
                $results['Outlook'] = @{
                    ProcessActive    = $proc.Running
                    ProcessResponding = $proc.Responding
                    Status = if ($proc.Running -and $proc.Responding) { 'HEALTHY' } else { 'DEGRADED' }
                }
                Write-Log -Level $(if ($results['Outlook'].Status -eq 'HEALTHY') {'SUCCESS'} else {'WARN'}) `
                    -Module OUTLOOK -Action 'PostValidation' -Result $results['Outlook'].Status
            }
            'Office' {
                $c2rSvc = Get-Service -Name 'ClickToRunSvc' -ErrorAction SilentlyContinue
                $c2rOk  = $c2rSvc -and $c2rSvc.Status -eq 'Running'
                $results['Office'] = @{
                    C2RRunning = $c2rOk
                    Status = if ($c2rOk) { 'HEALTHY' } else { 'DEGRADED' }
                }
                Write-Log -Level $(if ($c2rOk) {'SUCCESS'} else {'WARN'}) `
                    -Module OFFICE -Action 'PostValidation' -Result $results['Office'].Status
            }
            'Auth' {
                try {
                    $dsreg = & dsregcmd /status 2>&1
                    $prt   = ($dsreg -join "`n") -match 'AzureAdPrt\s*:\s*YES'
                    $results['Auth'] = @{
                        PRTPresent = $prt
                        Status = if ($prt) { 'HEALTHY' } else { 'DEGRADED' }
                    }
                    Write-Log -Level $(if ($prt) {'SUCCESS'} else {'WARN'}) `
                        -Module AUTH -Action 'PostValidation' -Result $results['Auth'].Status
                } catch {
                    $results['Auth'] = @{ Status = 'ERROR' }
                    Write-Log -Level ERROR -Module AUTH -Action 'PostValidation' -Result $_.Exception.Message
                }
            }
        }
    }

    return $results
}

#endregion

#region ============================================================
#  MAIN ORCHESTRATOR
#region ============================================================

function Invoke-M365Remediation {
    [CmdletBinding()]
    param()

    Initialize-Logging

    Write-Log -Level INFO -Module CORE -Action 'Start' -Result "M365 Remediation Engine v2.0 | Target=$TargetService | MaxLevel=$MaxLevel | DiagOnly=$DiagnosticOnly"
    Write-Log -Level INFO -Module CORE -Action 'Context' -Result "User=$env:USERNAME | Machine=$env:COMPUTERNAME | IsAdmin=$(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"

    # Phase 0 - Intelligent Detection
    Invoke-SmartDiagnosis

    Write-Log -Level INFO -Module CORE -Action 'DiagResult' -Result "Category=$($script:DiagResult.Category) | Services=$($script:DiagResult.AffectedService -join ',')"

    if ($DiagnosticOnly) {
        Write-Log -Level INFO -Module CORE -Action 'DiagOnly' -Result 'Diagnostic-only mode - skipping remediation'
        return [PSCustomObject]@{
            Timestamp       = $script:RunTimestamp
            Category        = $script:DiagResult.Category
            AffectedService = $script:DiagResult.AffectedService
            Details         = $script:DiagResult.Details
            Remediated      = $false
            LogFile         = $script:LogFile
        }
    }

    # Determine services to remediate
    $servicesToFix = if ($TargetService -ne 'Auto') {
        @($TargetService)
    } else {
        $script:DiagResult.AffectedService
    }

    if ($servicesToFix.Count -eq 0 -and $script:DiagResult.Category -eq 'UNKNOWN') {
        Write-Log -Level INFO -Module CORE -Action 'NoAction' -Result 'No actionable issues detected - exiting'
        return [PSCustomObject]@{
            Timestamp       = $script:RunTimestamp
            Category        = 'UNKNOWN'
            AffectedService = @()
            Details         = $script:DiagResult.Details
            Remediated      = $false
            LogFile         = $script:LogFile
        }
    }

    # Phase 1 - Escalated Remediation
    $remediationResults = @{}

    foreach ($svc in $servicesToFix) {
        Write-Log -Level INFO -Module CORE -Action 'Remediate' -Result "Starting remediation for: $svc"

        switch ($svc) {
            'OneDrive' {
                $remediationResults['OneDrive'] = Invoke-OneDriveRemediation -MaxLevel $MaxLevel
            }
            'Outlook' {
                $remediationResults['Outlook'] = Invoke-OutlookRemediation -MaxLevel $MaxLevel
            }
            'Office' {
                $remediationResults['Office'] = Invoke-OfficeGeneralRemediation -MaxLevel $MaxLevel
            }
            'Auth' {
                $remediationResults['Auth'] = Invoke-AuthRemediation
            }
            'Network' {
                Write-Log -Level WARN -Module NETWORK -Action 'Remediate' -Result 'Network issues require infrastructure-level intervention'
                $remediationResults['Network'] = $false
            }
        }
    }

    # Post-Remediation Validation
    $postHealth = Test-PostRemediationHealth -Services $servicesToFix

    # Final report
    $allResolved = @($remediationResults.Values | Where-Object { $_ -eq $false }).Count -eq 0
    $finalStatus = if ($allResolved) { 'RESOLVED' } else { 'PARTIAL_OR_FAILED' }

    Write-Log -Level $(if ($allResolved) {'SUCCESS'} else {'WARN'}) `
        -Module CORE -Action 'FinalResult' -Result "$finalStatus | Category=$($script:DiagResult.Category)"

    $output = [PSCustomObject]@{
        Timestamp       = $script:RunTimestamp
        Category        = $script:DiagResult.Category
        AffectedService = $script:DiagResult.AffectedService
        Details         = $script:DiagResult.Details
        Remediated      = $allResolved
        RemediationResults = $remediationResults
        PostHealth      = $postHealth
        LogFile         = $script:LogFile
    }

    # Write summary to log
    Write-Log -Level INFO -Module CORE -Action 'Summary' -Result ($output | ConvertTo-Json -Depth 3 -Compress)
    Write-Log -Level INFO -Module CORE -Action 'End' -Result 'M365 Remediation Engine completed'

    return $output
}

#endregion

#region ============================================================
#  ENTRY POINT
#region ============================================================

# Execute
try {
    $result = Invoke-M365Remediation
    $result
    exit 0
} catch {
    Write-Log -Level ERROR -Module CORE -Action 'UnhandledException' -Result $_.Exception.Message
    Write-Error "M365 Remediation Engine fatal error: $($_.Exception.Message)"
    exit 1
}

#endregion
