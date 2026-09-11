<#
.SYNOPSIS
    [ES] Deja el reloj en hora para poder firmar en sedes electronicas: detecta la ubicacion, empareja zona horaria y NTP del pais, y repara W32Time.
    [EN] Gets the clock back in sync so e-government signing works: detects location, matches time zone and country NTP servers, and repairs W32Time.

.DESCRIPTION
    [ES]
    Para el caso tipico de "no puedo firmar en Hacienda", "la AEAT me rechaza el
    certificado" o "el portatil va con la hora cambiada". Las sedes electronicas y la firma
    con certificado toleran pocos minutos de desfase, asi que un reloj sin sincronizar
    bloquea el tramite entero.

    Diagnostica primero: estado y tipo de inicio de W32Time, configuracion de registro
    (Type, NtpServer, NtpClient), fuente actual y ultima sincronizacion correcta. Un origen
    "Local CMOS Clock" significa que el equipo no esta sincronizando con nadie.

    La ubicacion se resuelve por geolocalizacion de la IP publica y se traduce de zona IANA
    a zona de Windows (Europe/Madrid a Romance Standard Time, Atlantic/Canary a GMT Standard
    Time). Sin salida a Internet cae a la region configurada en Windows, y en ultimo termino
    asume Espana peninsular. Con esa ubicacion empareja los servidores NTP: los oficiales del
    pais primero -en Espana los del ROA y RedIRIS-, despues el pool nacional y
    time.windows.com.

    Mide el desfase contra todos los candidatos con /stripchart, calcula la mediana y
    descarta los servidores incoherentes, de forma que uno con la hora mala no arrastre la
    correccion. Si el firewall bloquea UDP 123 usa como referencia la cabecera Date de un
    HTTPS publico, con precision de un segundo, suficiente para firmar.

    La estrategia se elige sola segun donde este el equipo:

      Dominio con DC alcanzable : jerarquia de dominio, se respeta la GPO corporativa.
      Dominio sin ver el DC     : correccion puntual con NTP publico SIN persistir la
                                  configuracion, para que el portatil vuelva al DC en cuanto
                                  se conecte por VPN. Con -PersistPublicNtp se persiste.
      Fuera de dominio          : NTP publico del pais detectado.

    Ajusta ademas MaxPosPhaseCorrection y MaxNegPhaseCorrection: con el valor por defecto
    W32Time se niega a corregir saltos grandes y el equipo se queda desfasado sin dar error.
    Si aun asi el reloj no entra en tolerancia, propone escribir la hora directamente con
    Set-Date, avisando antes de que un salto de hora cierra sesiones de aplicaciones e
    invalida tickets Kerberos.

    Distingue las causas que no son software: un desfase de mas de doce horas apunta a pila
    CMOS agotada, RealTimeIsUniversal=1 a reloj de hardware leido en UTC por arranque dual
    con Linux, y un desfase de un numero exacto de horas a zona horaria mal puesta. Tambien
    recoge los eventos del servicio de hora de los ultimos catorce dias.

    Limites deliberados: no reinicia el equipo, no toca la pila de red, no instala nada y no
    modifica GPO. Cada clave de registro se exporta a .reg en la carpeta de log antes de
    escribirse, y al final se imprime el comando de reversion.

    [EN]
    For the usual "I cannot sign at the tax agency", "my certificate is rejected" or "the
    laptop shows the wrong time" cases. E-government portals and certificate signing only
    tolerate a few minutes of drift, so an unsynchronised clock blocks the whole filing.

    Diagnoses first: W32Time status and start type, registry configuration, current source
    and last successful sync. A "Local CMOS Clock" source means the machine is not syncing
    with anything.

    Location comes from public IP geolocation and is mapped from IANA to Windows time zone
    (Europe/Madrid to Romance Standard Time, Atlantic/Canary to GMT Standard Time), with the
    Windows region as fallback and Spain as last resort. That location selects the NTP
    servers: official national ones first, then the country pool and time.windows.com.

    Offsets are measured against every candidate with /stripchart, then reduced to a median
    with incoherent servers discarded, so a single server with bad time cannot skew the
    correction. If UDP 123 is blocked, the Date header of a public HTTPS endpoint is used as
    reference, accurate to about one second.

    Strategy is picked automatically: domain hierarchy when a DC is reachable (GPO is
    respected), a one-off public NTP correction without persisting configuration when the
    machine is domain-joined but off the corporate network, and public country NTP when it is
    not domain-joined.

    It also relaxes MaxPosPhaseCorrection and MaxNegPhaseCorrection, since the defaults make
    W32Time refuse large corrections silently. If the clock still will not come into
    tolerance, it offers to set the time directly, warning first that a time step closes
    application sessions and invalidates Kerberos tickets.

    Physical causes are separated out: drift beyond twelve hours suggests a dead CMOS
    battery, RealTimeIsUniversal=1 means the hardware clock is read as UTC (Linux dual boot),
    and a whole number of hours points to the time zone, not to drift.

    Never reboots, never touches the network stack, installs nothing and does not modify GPO.
    Registry keys are exported to .reg before any change and the revert command is printed at
    the end.

.PARAMETER DryRun
    Simula la ejecucion completa sin cambiar nada. Recomendado en la primera pasada.

.PARAMETER Force
    Omite las confirmaciones interactivas, incluida la del cambio de zona horaria.

.PARAMETER DiagnoseOnly
    Solo diagnostica e informa: no cambia servicio, registro, zona horaria ni hora.

.PARAMETER TimeZoneId
    Fuerza la zona horaria de Windows, por ejemplo "Romance Standard Time". Si se omite se
    deduce de la ubicacion detectada.

.PARAMETER NtpServers
    Fuerza los servidores NTP a evaluar en vez de los del pais detectado.

.PARAMETER SkipGeo
    No sale a Internet a geolocalizar: usa la region configurada en Windows. Para redes con
    proxy que bloquea las APIs de geolocalizacion.

.PARAMETER NoTimeZoneChange
    No cambia la zona horaria aunque no coincida con la ubicacion; solo lo reporta.

.PARAMETER PersistPublicNtp
    Persiste los servidores NTP publicos aunque el equipo este en dominio. Para portatiles
    que van a estar semanas fuera de la red corporativa. Una GPO de hora puede revertirlo al
    reconectar al dominio, que suele ser lo deseado.

.PARAMETER AllowStepTime
    Ajusta la hora del sistema con Set-Date sin preguntar cuando NTP no puede corregir el
    desfase. Sin este parametro se pide confirmacion.

.PARAMETER NoStepTime
    Prohibe ajustar la hora del sistema en cualquier caso.

.PARAMETER AutoTimeZoneService
    Habilita el ajuste automatico de zona horaria de Windows (servicio tzautoupdate).
    Requiere los servicios de ubicacion activos.

.PARAMETER PollSeconds
    Intervalo de sondeo NTP en segundos. Por defecto 3600.

.PARAMETER LogPath
    Carpeta de log y copias de seguridad. Por defecto una carpeta con marca de tiempo en %TEMP%.

.EXAMPLE
    .\04-repair-time-sync.ps1 -DiagnoseOnly
    Diagnostico sin tocar nada: fuente de hora, desfase real y causa.

.EXAMPLE
    .\04-repair-time-sync.ps1 -Force
    Pasada normal en consola de administrador. Resuelve el caso habitual.

.EXAMPLE
    .\04-repair-time-sync.ps1 -Force -AllowStepTime
    Cuando el desfase es tan grande que NTP no lo corrige y hay prisa por tramitar.

.EXAMPLE
    .\04-repair-time-sync.ps1 -Force -PersistPublicNtp
    Portatil en dominio que va a estar fuera de la red corporativa una temporada.

.EXAMPLE
    .\04-repair-time-sync.ps1 -SkipGeo -TimeZoneId "Romance Standard Time" -Force
    Red con proxy que bloquea la geolocalizacion: se le indica la zona horaria a mano.

.NOTES
    PowerShell 5.1 y 7. Requiere administrador para reparar; sin el solo diagnostica.
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Force,
    [switch]$DiagnoseOnly,
    [string]$TimeZoneId,
    [string[]]$NtpServers,
    [switch]$SkipGeo,
    [switch]$NoTimeZoneChange,
    [switch]$PersistPublicNtp,
    [switch]$AllowStepTime,
    [switch]$NoStepTime,
    [switch]$AutoTimeZoneService,
    [int]$PollSeconds = 3600,
    [string]$LogPath
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
$script:DryRun      = [bool]$DryRun
$script:Stats       = @{ Changed = 0; Skipped = 0; Warnings = 0; Errors = 0 }
$script:Findings    = New-Object System.Collections.ArrayList
$script:NextSteps   = New-Object System.Collections.ArrayList
$script:Backups     = New-Object System.Collections.ArrayList
$script:IsAdmin     = $false
$script:W32tm       = Join-Path $env:SystemRoot 'System32\w32tm.exe'
$script:RegExe      = Join-Path $env:SystemRoot 'System32\reg.exe'
$script:TzUtil      = Join-Path $env:SystemRoot 'System32\tzutil.exe'
$script:Invariant   = [System.Globalization.CultureInfo]::InvariantCulture

$script:GoodOffsetSec  = 2.0     # tolerancia para firma electronica
$script:OutlierSec     = 5.0     # descarte por incoherencia con la mediana
$script:CmosSuspectSec = 43200   # 12 h: sospecha de pila CMOS
$script:RtcUtcSuspect  = 3300    # ~55 min: sospecha de zona horaria o RTC en UTC

$script:RegW32Time   = 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time'
$script:RegParams    = "$script:RegW32Time\Parameters"
$script:RegConfig    = "$script:RegW32Time\Config"
$script:RegNtpClient = "$script:RegW32Time\TimeProviders\NtpClient"
$script:RegTzAuto    = 'HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate'
$script:RegTzInfo    = 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation'

try { $stamp = (Get-Date).ToString('yyyyMMdd_HHmmss') } catch { $stamp = 'run' }
if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $base = $env:TEMP
    if ([string]::IsNullOrWhiteSpace($base)) { $base = 'C:\Windows\Temp' }
    $script:BackupDir = Join-Path $base ("TimeSyncFix_" + $stamp)
} else { $script:BackupDir = $LogPath }
try {
    if (-not (Test-Path -LiteralPath $script:BackupDir)) {
        New-Item -ItemType Directory -Path $script:BackupDir -Force -ErrorAction Stop | Out-Null
    }
} catch { $script:BackupDir = 'C:\Windows\Temp' }
$logName = 'repair-time-sync'
try { if ($MyInvocation.MyCommand.Path) { $logName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Path) } } catch {}
$script:LogFile = Join-Path $script:BackupDir ($logName + '.log')

# Servidores nacionales por pais; se completan con el pool del pais y time.windows.com.
$script:NtpByCountry = @{
    'ES' = @('hora.roa.es','minuto.roa.es','hora.rediris.es')
    'PT' = @('ntp01.oal.ul.pt');            'FR' = @('ntp.obspm.fr')
    'DE' = @('ptbtime1.ptb.de','ptbtime2.ptb.de'); 'IT' = @('ntp1.inrim.it')
    'GB' = @('ntp1.npl.co.uk');             'NL' = @('ntp.time.nl')
    'BE' = @('ntp1.oma.be');                'CH' = @('ntp.metas.ch')
    'PL' = @('tempus1.gum.gov.pl');         'US' = @('time.nist.gov')
    'MX' = @('cronos.cenam.mx');            'AR' = @('time.afip.gov.ar')
    'CL' = @('ntp.shoa.cl');                'CO' = @('hora.sic.gov.co')
}

$script:IanaToWindows = @{
    'Europe/Madrid' = 'Romance Standard Time';  'Africa/Ceuta'   = 'Romance Standard Time'
    'Atlantic/Canary' = 'GMT Standard Time';    'Europe/Lisbon'  = 'GMT Standard Time'
    'Atlantic/Azores' = 'Azores Standard Time'; 'Europe/London'  = 'GMT Standard Time'
    'Europe/Dublin' = 'GMT Standard Time';      'Europe/Paris'   = 'Romance Standard Time'
    'Europe/Brussels' = 'Romance Standard Time';'Europe/Copenhagen' = 'Romance Standard Time'
    'Europe/Berlin' = 'W. Europe Standard Time';'Europe/Amsterdam' = 'W. Europe Standard Time'
    'Europe/Rome' = 'W. Europe Standard Time';  'Europe/Vienna'  = 'W. Europe Standard Time'
    'Europe/Zurich' = 'W. Europe Standard Time';'Europe/Stockholm' = 'W. Europe Standard Time'
    'Europe/Oslo' = 'W. Europe Standard Time';  'Europe/Warsaw'  = 'Central European Standard Time'
    'Europe/Prague' = 'Central Europe Standard Time'; 'Europe/Budapest' = 'Central Europe Standard Time'
    'Europe/Bucharest' = 'GTB Standard Time';   'Europe/Athens'  = 'GTB Standard Time'
    'Europe/Helsinki' = 'FLE Standard Time';    'Europe/Istanbul' = 'Turkey Standard Time'
    'America/New_York' = 'Eastern Standard Time'; 'America/Chicago' = 'Central Standard Time'
    'America/Denver' = 'Mountain Standard Time';  'America/Los_Angeles' = 'Pacific Standard Time'
    'America/Mexico_City' = 'Central Standard Time (Mexico)'
    'America/Bogota' = 'SA Pacific Standard Time';'America/Lima' = 'SA Pacific Standard Time'
    'America/Panama' = 'SA Pacific Standard Time';'America/Santiago' = 'Pacific SA Standard Time'
    'America/Argentina/Buenos_Aires' = 'Argentina Standard Time'
    'America/Sao_Paulo' = 'E. South America Standard Time'
    'America/Montevideo' = 'Montevideo Standard Time'; 'America/Caracas' = 'Venezuela Standard Time'
}

$script:TzByCountry = @{
    'ES' = 'Romance Standard Time'; 'PT' = 'GMT Standard Time'; 'FR' = 'Romance Standard Time'
    'BE' = 'Romance Standard Time'; 'GB' = 'GMT Standard Time'; 'IE' = 'GMT Standard Time'
    'DE' = 'W. Europe Standard Time'; 'IT' = 'W. Europe Standard Time'
    'NL' = 'W. Europe Standard Time'; 'CH' = 'W. Europe Standard Time'
    'AT' = 'W. Europe Standard Time'; 'PL' = 'Central European Standard Time'
}

$script:GeoIdToCountry = @{
    217 = 'ES'; 193 = 'PT'; 84 = 'FR'; 94 = 'DE'; 118 = 'IT'; 242 = 'GB'; 176 = 'NL'
    21 = 'BE'; 223 = 'CH'; 14 = 'AT'; 191 = 'PL'; 244 = 'US'; 166 = 'MX'; 11 = 'AR'
    46 = 'CL'; 51 = 'CO'; 68 = 'IE'
}

# ------------------------------------------------------------------ utilidades

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','OK','WARN','ERROR','STEP','DRYRUN','HEAD')][string]$Level = 'INFO'
    )
    $ts = ''
    try { $ts = (Get-Date).ToString('HH:mm:ss') } catch { $ts = '--:--:--' }
    $line = "[$ts] [$Level] $Message"
    switch ($Level) {
        'OK'     { $color = 'Green' }
        'WARN'   { $color = 'Yellow' }
        'ERROR'  { $color = 'Red' }
        'STEP'   { $color = 'Cyan' }
        'DRYRUN' { $color = 'Magenta' }
        'HEAD'   { $color = 'White' }
        default  { $color = 'Gray' }
    }
    if ($Level -eq 'WARN')  { $script:Stats.Warnings++ }
    if ($Level -eq 'ERROR') { $script:Stats.Errors++ }
    try { Write-Host $line -ForegroundColor $color } catch { Write-Host $line }
    try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
}

function Write-Section {
    param([string]$Title)
    Write-Log ('-' * 70) 'HEAD'
    Write-Log $Title 'STEP'
    Write-Log ('-' * 70) 'HEAD'
}

function Add-Finding  { param([string]$Text) try { [void]$script:Findings.Add($Text) } catch {} }
function Add-NextStep { param([string]$Text) try { [void]$script:NextSteps.Add($Text) } catch {} }

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Confirm-Action {
    param([string]$Question)
    if ($script:DryRun -or $Force) { return $true }
    $a = ''
    try { $a = Read-Host "$Question [s/N]" } catch { return $false }
    return ($a -match '^(s|si|y|yes)$')
}

function Format-Offset {
    param([double]$Seconds)
    $abs = [math]::Abs($Seconds)
    if ($abs -lt 1)    { return ("{0:+0.000;-0.000;0.000} s" -f $Seconds) }
    if ($abs -lt 120)  { return ("{0:+0.00;-0.00;0.00} s"    -f $Seconds) }
    if ($abs -lt 7200) { return ("{0:+0.0;-0.0;0.0} min"     -f ($Seconds / 60)) }
    return ("{0:+0.00;-0.00;0.00} h" -f ($Seconds / 3600))
}

function Invoke-Exe {
    # Timeout duro: w32tm se cuelga contra servidores que no responden y no debe
    # bloquear la sesion remota de soporte.
    param([string]$FilePath, [string]$Arguments = '', [int]$TimeoutSec = 25)
    $tag  = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $fOut = Join-Path $script:BackupDir "_exe_$tag.out"
    $fErr = Join-Path $script:BackupDir "_exe_$tag.err"
    $res  = New-Object psobject -Property @{ ExitCode = -1; Output = ''; TimedOut = $false }
    try {
        $splat = @{
            FilePath = $FilePath; NoNewWindow = $true; PassThru = $true
            RedirectStandardOutput = $fOut; RedirectStandardError = $fErr; ErrorAction = 'Stop'
        }
        if (-not [string]::IsNullOrWhiteSpace($Arguments)) { $splat['ArgumentList'] = $Arguments }
        $proc = Start-Process @splat
        if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
            $res.TimedOut = $true
            try { $proc.Kill() } catch {}
            try { [void]$proc.WaitForExit(3000) } catch {}
        }
        try { $res.ExitCode = $proc.ExitCode } catch {}
    } catch {
        $res.Output = $_.Exception.Message
        return $res
    }
    $text = ''
    foreach ($f in @($fOut, $fErr)) {
        try {
            if (Test-Path -LiteralPath $f) {
                $c = Get-Content -LiteralPath $f -Raw -ErrorAction SilentlyContinue
                if ($c) { $text += $c }
            }
        } catch {}
        try { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } catch {}
    }
    $res.Output = $text
    return $res
}

function Invoke-W32tm {
    param([string]$Arguments, [int]$TimeoutSec = 25)
    return (Invoke-Exe -FilePath $script:W32tm -Arguments $Arguments -TimeoutSec $TimeoutSec)
}

function Test-TcpPort {
    param([string]$ComputerName, [int]$Port, [int]$TimeoutSec = 3)
    $c = $null
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect($ComputerName, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutSec * 1000, $false)) { return $false }
        $c.EndConnect($iar)
        return $true
    } catch { return $false }
    finally { if ($c) { try { $c.Close() } catch {} } }
}

function Backup-RegKey {
    param([string]$Path, [string]$Label)
    if ($script:DryRun) { return }
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $file = Join-Path $script:BackupDir ("$Label.reg")
    if (Test-Path -LiteralPath $file) { return }
    $regPath = $Path -replace '^HKLM:\\', 'HKLM\' -replace '^HKCU:\\', 'HKCU\'
    $r = Invoke-Exe -FilePath $script:RegExe -Arguments "export `"$regPath`" `"$file`" /y" -TimeoutSec 15
    if ($r.ExitCode -eq 0) {
        Write-Log "Backup de registro: $file" 'INFO'
        try { [void]$script:Backups.Add($file) } catch {}
    } else { Write-Log "No se pudo exportar $regPath" 'WARN' }
}

function Set-RegValueSafe {
    param(
        [string]$Path, [string]$Name, $Value,
        [ValidateSet('DWord','String')][string]$Type = 'DWord',
        [string]$Label
    )
    if ([string]::IsNullOrWhiteSpace($Label)) { $Label = "$Path\$Name" }
    $cur = $null
    try { $cur = (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name } catch {}
    if ($null -ne $cur -and "$cur" -eq "$Value") {
        Write-Log "Ya correcto: $Label = $Value" 'INFO'
        $script:Stats.Skipped++
        return $true
    }
    if ($script:DryRun) {
        Write-Log "[SIMULACION] $Label = $Value (actual: $cur)" 'DRYRUN'
        return $true
    }
    try {
        if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        Write-Log "Aplicado: $Label = $Value (antes: $cur)" 'OK'
        $script:Stats.Changed++
        return $true
    } catch {
        # Respaldo por reg.exe: New-ItemProperty rechaza algunos DWORD fuera de Int32.
        $regPath = $Path -replace '^HKLM:\\', 'HKLM\' -replace '^HKCU:\\', 'HKCU\'
        $t = 'REG_SZ'
        $d = "$Value"
        if ($Type -eq 'DWord') { $t = 'REG_DWORD'; $d = ('0x{0:X8}' -f ([uint32]([int]$Value))) }
        $r = Invoke-Exe -FilePath $script:RegExe -Arguments "add `"$regPath`" /v $Name /t $t /d $d /f" -TimeoutSec 15
        if ($r.ExitCode -eq 0) {
            Write-Log "Aplicado por reg.exe: $Label = $d" 'OK'
            $script:Stats.Changed++
            return $true
        }
        Write-Log "No se pudo escribir $Label" 'WARN'
        return $false
    }
}

# ------------------------------------------------------------------ estado

function Get-W32TimeState {
    $s = New-Object psobject -Property @{
        ServiceExists = $false; Status = 'Ausente'; StartType = ''
        Source = ''; LastSync = ''; TypeValue = ''; PeerList = ''; NtpClientOn = $null
    }
    $svc = $null
    try { $svc = Get-Service -Name W32Time -ErrorAction Stop } catch {}
    if ($svc) {
        $s.ServiceExists = $true
        $s.Status = "$($svc.Status)"
        try { $s.StartType = "$($svc.StartType)" } catch {}
        if ([string]::IsNullOrWhiteSpace($s.StartType)) {
            try { $s.StartType = (Get-CimInstance Win32_Service -Filter "Name='W32Time'" -ErrorAction Stop).StartMode } catch {}
        }
    }
    try { $s.TypeValue   = (Get-ItemProperty -LiteralPath $script:RegParams -Name 'Type' -ErrorAction Stop).Type } catch {}
    try { $s.PeerList    = (Get-ItemProperty -LiteralPath $script:RegParams -Name 'NtpServer' -ErrorAction Stop).NtpServer } catch {}
    try { $s.NtpClientOn = (Get-ItemProperty -LiteralPath $script:RegNtpClient -Name 'Enabled' -ErrorAction Stop).Enabled } catch {}
    if ($s.Status -eq 'Running') {
        $q = Invoke-W32tm -Arguments '/query /status' -TimeoutSec 20
        foreach ($line in ($q.Output -split "`r?`n")) {
            if ($line -match '^\s*(Source|Origen|Fuente)\s*:\s*(.+)$') { $s.Source = $Matches[2].Trim() }
            if ($line -match '(Last Successful Sync Time|ltima sincronizaci)') {
                $p = $line -split ':', 2
                if ($p.Count -eq 2) { $s.LastSync = $p[1].Trim() }
            }
        }
    }
    return $s
}

function Get-DomainInfo {
    $i = New-Object psobject -Property @{ PartOfDomain = $false; Domain = ''; DcCandidates = @(); DcReachable = '' }
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $i.PartOfDomain = [bool]$cs.PartOfDomain
        if ($i.PartOfDomain) { $i.Domain = "$($cs.Domain)" }
    } catch {}
    if (-not $i.PartOfDomain) { return $i }
    $c = New-Object System.Collections.ArrayList
    if (-not [string]::IsNullOrWhiteSpace($env:LOGONSERVER)) {
        $ls = $env:LOGONSERVER.TrimStart('\')
        if ($ls) {
            if ($i.Domain -and $ls -notlike '*.*') { [void]$c.Add("$ls.$($i.Domain)") }
            [void]$c.Add($ls)
        }
    }
    try {
        $srv = Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$($i.Domain)" -Type SRV -ErrorAction Stop |
               Where-Object { $_.NameTarget } | Select-Object -First 4
        foreach ($r in $srv) { [void]$c.Add($r.NameTarget) }
    } catch {}
    if ($i.Domain) { [void]$c.Add($i.Domain) }
    $i.DcCandidates = @($c | Where-Object { $_ } | Select-Object -Unique)
    foreach ($dc in $i.DcCandidates) {
        if (Test-TcpPort -ComputerName $dc -Port 389) { $i.DcReachable = $dc; break }
        if (Test-TcpPort -ComputerName $dc -Port 135) { $i.DcReachable = $dc; break }
    }
    return $i
}

# ------------------------------------------------------------------ ubicacion

function Get-GeoLocation {
    $g = New-Object psobject -Property @{ Source = 'ninguna'; CountryCode = ''; Country = ''; City = ''; Iana = '' }
    if ($SkipGeo) {
        Write-Log 'Geolocalizacion omitida (-SkipGeo)' 'INFO'
    } else {
        $providers = @(
            @{ Url = 'http://ip-api.com/json/?fields=status,country,countryCode,city,timezone'; Cc = 'countryCode'; Co = 'country'; Ci = 'city'; Tz = 'timezone' },
            @{ Url = 'https://ipwho.is/';  Cc = 'country_code'; Co = 'country';      Ci = 'city'; Tz = 'timezone' },
            @{ Url = 'https://ipapi.co/json/'; Cc = 'country_code'; Co = 'country_name'; Ci = 'city'; Tz = 'timezone' }
        )
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
        foreach ($p in $providers) {
            $d = $null
            try { $d = Invoke-RestMethod -Uri $p.Url -TimeoutSec 8 -UseBasicParsing -ErrorAction Stop } catch { continue }
            if (-not $d) { continue }
            $cc = "$($d.($p.Cc))"
            if ([string]::IsNullOrWhiteSpace($cc)) { continue }
            $tz = "$($d.($p.Tz))"
            if ([string]::IsNullOrWhiteSpace($tz) -and $d.timezone -and $d.timezone.id) { $tz = "$($d.timezone.id)" }
            $g.Source = $p.Url; $g.CountryCode = $cc.ToUpper(); $g.Country = "$($d.($p.Co))"
            $g.City = "$($d.($p.Ci))"; $g.Iana = $tz
            Write-Log "Ubicacion: $($g.City) / $($g.Country) [$($g.CountryCode)] zona IANA: $($g.Iana)" 'OK'
            return $g
        }
        Write-Log 'Ningun proveedor de geolocalizacion respondio (proxy o red restringida)' 'WARN'
    }
    $cc = ''
    try {
        $wh = Get-WinHomeLocation -ErrorAction Stop
        if ($wh -and $script:GeoIdToCountry.ContainsKey([int]$wh.GeoId)) { $cc = $script:GeoIdToCountry[[int]$wh.GeoId] }
    } catch {}
    if ([string]::IsNullOrWhiteSpace($cc)) {
        try { $cc = (New-Object System.Globalization.RegionInfo ((Get-Culture).Name)).TwoLetterISORegionName } catch {}
    }
    if ([string]::IsNullOrWhiteSpace($cc)) { $cc = 'ES' }
    $g.Source = 'region de Windows'; $g.CountryCode = $cc.ToUpper()
    Write-Log "Ubicacion por region de Windows: $($g.CountryCode)" 'INFO'
    return $g
}

function Resolve-WindowsTimeZone {
    param([string]$Iana, [string]$CountryCode)
    if ($Iana -and $script:IanaToWindows.ContainsKey($Iana)) { return $script:IanaToWindows[$Iana] }
    if ($CountryCode -and $script:TzByCountry.ContainsKey($CountryCode)) { return $script:TzByCountry[$CountryCode] }
    return ''
}

function Get-NtpCandidateList {
    param([string]$CountryCode)
    if ($NtpServers -and $NtpServers.Count -gt 0) { return @($NtpServers | Where-Object { $_ } | Select-Object -Unique) }
    $l = New-Object System.Collections.ArrayList
    if ($script:NtpByCountry.ContainsKey($CountryCode)) {
        foreach ($s in $script:NtpByCountry[$CountryCode]) { [void]$l.Add($s) }
    }
    if ($CountryCode) { [void]$l.Add(('{0}.pool.ntp.org' -f $CountryCode.ToLower())) }
    [void]$l.Add('pool.ntp.org')
    [void]$l.Add('time.windows.com')
    return @($l | Where-Object { $_ } | Select-Object -Unique)
}

# ------------------------------------------------------------------ medicion

function Get-NtpOffset {
    # Desfase en segundos contra un servidor, o $null si no responde.
    # w32tm localizado imprime la muestra con coma decimal; se acepta coma o punto.
    param([string]$Server, [int]$TimeoutSec = 12)
    $r = Invoke-W32tm -Arguments "/stripchart /computer:$Server /samples:1 /dataonly /period:1" -TimeoutSec $TimeoutSec
    if ($r.TimedOut) { return $null }
    $m = [regex]::Matches("$($r.Output)", '([+-]\d+[.,]\d+)s')
    if ($m.Count -eq 0) { return $null }
    $val = $m[$m.Count - 1].Groups[1].Value -replace ',', '.'
    $num = 0.0
    if ([double]::TryParse($val, [System.Globalization.NumberStyles]::Float, $script:Invariant, [ref]$num)) { return $num }
    return $null
}

function Get-HttpUtcTime {
    # Respaldo cuando UDP 123 esta bloqueado: cabecera Date de un HTTPS publico.
    # Precision ~1 s, suficiente para firma electronica.
    $urls = @('https://www.microsoft.com','https://www.google.com','https://www.agenciatributaria.gob.es')
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
    foreach ($u in $urls) {
        try {
            $t0 = [DateTime]::UtcNow
            $resp = Invoke-WebRequest -Uri $u -Method Head -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
            $rtt = ([DateTime]::UtcNow - $t0).TotalSeconds
            $hdr = $null
            try { $hdr = $resp.Headers['Date'] } catch {}
            if (-not $hdr) { continue }
            $parsed = [DateTime]::MinValue
            $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
            if (-not [DateTime]::TryParse($hdr, $script:Invariant, $styles, [ref]$parsed)) { continue }
            $refUtc = $parsed.AddSeconds($rtt / 2.0)
            Write-Log "Referencia HTTP ($u): $($refUtc.ToString('yyyy-MM-dd HH:mm:ss')) UTC, RTT $([math]::Round($rtt,2)) s" 'INFO'
            return $refUtc
        } catch { continue }
    }
    return $null
}

function Measure-NtpCandidates {
    param([string[]]$Servers)
    $res = New-Object System.Collections.ArrayList
    foreach ($s in $Servers) {
        $off = Get-NtpOffset -Server $s
        if ($null -eq $off) {
            Write-Log "NTP $s : sin respuesta" 'INFO'
            [void]$res.Add((New-Object psobject -Property @{ Server = $s; Reachable = $false; Offset = $null; Outlier = $false }))
        } else {
            Write-Log "NTP $s : desfase $(Format-Offset $off)" 'OK'
            [void]$res.Add((New-Object psobject -Property @{ Server = $s; Reachable = $true; Offset = [double]$off; Outlier = $false }))
        }
    }
    $ok = @($res | Where-Object { $_.Reachable })
    if ($ok.Count -ge 3) {
        # Mediana y descarte: protege de un servidor con hora mala.
        $sorted = @($ok | Sort-Object Offset)
        $median = $sorted[[int][math]::Floor($sorted.Count / 2)].Offset
        foreach ($r in $ok) {
            if ([math]::Abs($r.Offset - $median) -gt $script:OutlierSec) {
                $r.Outlier = $true
                Write-Log "Descartado $($r.Server): $(Format-Offset $r.Offset) incoherente con la mediana $(Format-Offset $median)" 'WARN'
            }
        }
    }
    return @($res)
}

# ------------------------------------------------------------------ acciones

function Repair-W32TimeService {
    if (-not $script:IsAdmin) {
        Write-Log 'Sin permisos de administrador: no se toca el servicio W32Time' 'WARN'
        return $false
    }
    $svc = $null
    try { $svc = Get-Service -Name W32Time -ErrorAction Stop } catch {}
    if (-not $svc) {
        Write-Log 'El servicio W32Time no existe' 'ERROR'
        Add-NextStep 'Reregistrar el servicio: w32tm /unregister ; w32tm /register ; reiniciar el equipo.'
        return $false
    }
    $st = ''
    try { $st = "$($svc.StartType)" } catch {}
    if ($st -ne 'Automatic') {
        if ($script:DryRun) { Write-Log "[SIMULACION] W32Time $st -> Automatic" 'DRYRUN' }
        else {
            try {
                Set-Service -Name W32Time -StartupType Automatic -ErrorAction Stop
                Write-Log "Inicio de W32Time: $st -> Automatic" 'OK'
                $script:Stats.Changed++
            } catch {
                Write-Log "No se pudo poner W32Time en Automatic: $($_.Exception.Message)" 'WARN'
                Add-Finding 'El tipo de inicio de W32Time no se pudo cambiar (posible GPO).'
            }
        }
    }
    if ($svc.Status -ne 'Running') {
        if ($script:DryRun) { Write-Log '[SIMULACION] Se arrancaria W32Time' 'DRYRUN' }
        else {
            try {
                Start-Service -Name W32Time -ErrorAction Stop
                Write-Log 'Servicio W32Time arrancado' 'OK'
                $script:Stats.Changed++
            } catch {
                Write-Log "No se pudo arrancar W32Time: $($_.Exception.Message)" 'ERROR'
                return $false
            }
        }
    }
    return $true
}

function Set-W32TimeHardening {
    # Sin estos valores W32Time se niega a corregir saltos grandes y el equipo
    # se queda desfasado indefinidamente. -1 se almacena como 0xFFFFFFFF.
    if (-not $script:IsAdmin) { return }
    Backup-RegKey -Path $script:RegNtpClient -Label 'W32Time_NtpClient'
    Backup-RegKey -Path $script:RegConfig    -Label 'W32Time_Config'
    Set-RegValueSafe -Path $script:RegNtpClient -Name 'Enabled'             -Value 1            -Type DWord -Label 'NtpClient\Enabled' | Out-Null
    Set-RegValueSafe -Path $script:RegNtpClient -Name 'SpecialPollInterval' -Value $PollSeconds -Type DWord -Label 'NtpClient\SpecialPollInterval' | Out-Null
    Set-RegValueSafe -Path $script:RegConfig -Name 'MaxPosPhaseCorrection' -Value -1 -Type DWord -Label 'Config\MaxPosPhaseCorrection' | Out-Null
    Set-RegValueSafe -Path $script:RegConfig -Name 'MaxNegPhaseCorrection' -Value -1 -Type DWord -Label 'Config\MaxNegPhaseCorrection' | Out-Null
}

function Set-TimeZoneSafe {
    param([string]$Id, [string]$Reason)
    if ([string]::IsNullOrWhiteSpace($Id)) { return }
    $cur = ''
    try { $cur = (Get-TimeZone -ErrorAction Stop).Id } catch {
        try { $cur = (Get-ItemProperty -LiteralPath $script:RegTzInfo -Name 'TimeZoneKeyName' -ErrorAction Stop).TimeZoneKeyName } catch {}
    }
    if ($cur -eq $Id) { Write-Log "Zona horaria ya correcta: $cur" 'OK'; return }
    if ($NoTimeZoneChange) {
        Write-Log "Zona horaria $cur distinta de la detectada $Id; no se cambia (-NoTimeZoneChange)" 'WARN'
        Add-Finding "Zona horaria configurada '$cur' no coincide con la ubicacion detectada ('$Id')."
        return
    }
    $valid = $true
    try { $valid = @(Get-TimeZone -ListAvailable -ErrorAction Stop | Where-Object { $_.Id -eq $Id }).Count -gt 0 } catch {}
    if (-not $valid) { Write-Log "La zona horaria '$Id' no existe en este Windows" 'WARN'; return }
    if (-not (Confirm-Action "Cambiar zona horaria de '$cur' a '$Id' ($Reason). Continuar?")) {
        Write-Log 'Cambio de zona horaria cancelado' 'WARN'
        return
    }
    if ($script:DryRun) { Write-Log "[SIMULACION] Zona horaria '$cur' -> '$Id'" 'DRYRUN'; return }
    $done = $false
    try { Set-TimeZone -Id $Id -ErrorAction Stop; $done = $true } catch {}
    if (-not $done) { $done = ((Invoke-Exe -FilePath $script:TzUtil -Arguments "/s `"$Id`"" -TimeoutSec 15).ExitCode -eq 0) }
    if ($done) {
        Write-Log "Zona horaria: '$cur' -> '$Id'" 'OK'
        $script:Stats.Changed++
        Add-Finding "Zona horaria corregida de '$cur' a '$Id'."
    } else { Write-Log "No se pudo cambiar la zona horaria a '$Id'" 'ERROR' }
}

function Set-AutoTimeZoneService {
    if (-not $AutoTimeZoneService -or -not $script:IsAdmin) { return }
    Backup-RegKey -Path $script:RegTzAuto -Label 'tzautoupdate'
    Set-RegValueSafe -Path $script:RegTzAuto -Name 'Start' -Value 3 -Type DWord -Label 'tzautoupdate\Start' | Out-Null
    Write-Log 'Ajuste automatico de zona horaria habilitado (requiere servicios de ubicacion)' 'INFO'
}

function Invoke-DomainHierarchyConfig {
    param([string]$Dc)
    if (-not $script:IsAdmin) { return }
    Backup-RegKey -Path $script:RegParams -Label 'W32Time_Parameters'
    if ($script:DryRun) { Write-Log "[SIMULACION] w32tm /config /syncfromflags:domhier /update (DC: $Dc)" 'DRYRUN'; return }
    $r = Invoke-W32tm -Arguments '/config /syncfromflags:domhier /update' -TimeoutSec 30
    if ($r.ExitCode -eq 0) {
        Write-Log "Sincronizacion por jerarquia de dominio (DC: $Dc)" 'OK'
        $script:Stats.Changed++
    } else { Write-Log "w32tm /config domhier devolvio $($r.ExitCode)" 'WARN' }
    try { Restart-Service -Name W32Time -Force -ErrorAction Stop; Write-Log 'W32Time reiniciado' 'OK' }
    catch { Write-Log "No se pudo reiniciar W32Time: $($_.Exception.Message)" 'WARN' }
}

function Invoke-PublicNtpConfig {
    param([string[]]$Peers)
    if (-not $script:IsAdmin -or -not $Peers -or $Peers.Count -eq 0) { return }
    $peerList = (($Peers | Select-Object -First 4 | ForEach-Object { "$_,0x8" }) -join ' ')
    Backup-RegKey -Path $script:RegParams -Label 'W32Time_Parameters'
    if ($script:DryRun) { Write-Log "[SIMULACION] manualpeerlist: $peerList" 'DRYRUN'; return }
    $r = Invoke-W32tm -Arguments "/config /manualpeerlist:`"$peerList`" /syncfromflags:manual /reliable:no /update" -TimeoutSec 30
    if ($r.ExitCode -eq 0) {
        Write-Log "Servidores NTP configurados: $peerList" 'OK'
        $script:Stats.Changed++
    } else { Write-Log "w32tm /config manualpeerlist devolvio $($r.ExitCode)" 'WARN' }
    Set-RegValueSafe -Path $script:RegParams -Name 'Type' -Value 'NTP' -Type String -Label 'Parameters\Type' | Out-Null
    try { Restart-Service -Name W32Time -Force -ErrorAction Stop; Write-Log 'W32Time reiniciado' 'OK' }
    catch { Write-Log "No se pudo reiniciar W32Time: $($_.Exception.Message)" 'WARN' }
}

function Invoke-Resync {
    param([int]$Attempts = 3)
    if (-not $script:IsAdmin) { return $false }
    if ($script:DryRun) { Write-Log '[SIMULACION] w32tm /resync /force' 'DRYRUN'; return $true }
    for ($i = 1; $i -le $Attempts; $i++) {
        $r = Invoke-W32tm -Arguments '/resync /force' -TimeoutSec 40
        if ($r.ExitCode -eq 0 -and $r.Output -notmatch '(?i)error|0x800') {
            Write-Log "Resincronizacion correcta (intento $i)" 'OK'
            return $true
        }
        $short = ''
        try { $short = (($r.Output -split "`r?`n") | Where-Object { $_ -match '\S' } | Select-Object -Last 1).Trim() } catch {}
        Write-Log "Resync intento $i fallido: $short" 'WARN'
        if ($i -lt $Attempts) { Start-Sleep -Seconds 3 }
    }
    return $false
}

function Set-SystemTimeFromReference {
    # Ultimo recurso cuando NTP no puede corregir el salto (GPO o pila CMOS).
    param([double]$OffsetSeconds, [string]$SourceLabel)
    if ($NoStepTime) { Write-Log 'Ajuste directo prohibido por -NoStepTime' 'WARN'; return $false }
    if (-not $script:IsAdmin) { Write-Log 'Sin admin: no se puede ajustar la hora' 'WARN'; return $false }
    $target = (Get-Date).AddSeconds($OffsetSeconds)
    Write-Host ''
    Write-Host "AVISO: se va a cambiar la hora del sistema de $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) a $($target.ToString('yyyy-MM-dd HH:mm:ss')) (fuente: $SourceLabel)." -ForegroundColor Yellow
    Write-Host 'Un salto de hora puede cerrar sesiones de aplicaciones, invalidar tickets Kerberos y obligar a reautenticar. El script no lo revierte.' -ForegroundColor Yellow
    Write-Host ''
    if (-not ($AllowStepTime -or (Confirm-Action 'Aplicar el cambio de hora ahora?'))) {
        Write-Log 'Ajuste directo de la hora cancelado' 'WARN'
        Add-NextStep ("Ajuste manual pendiente: Set-Date -Date '" + $target.ToString('yyyy-MM-dd HH:mm:ss') + "'")
        return $false
    }
    if ($script:DryRun) { Write-Log "[SIMULACION] Set-Date $($target.ToString('yyyy-MM-dd HH:mm:ss'))" 'DRYRUN'; return $true }
    try {
        Set-Date -Date $target -ErrorAction Stop | Out-Null
        Write-Log "Hora ajustada a $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))" 'OK'
        $script:Stats.Changed++
        Add-Finding "Hora del sistema ajustada manualmente ($(Format-Offset $OffsetSeconds), fuente: $SourceLabel)."
        return $true
    } catch {
        Write-Log "No se pudo ajustar la hora: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

function Test-PhysicalClockIssues {
    param([double]$InitialOffset)
    $abs = [math]::Abs($InitialOffset)
    if ($abs -ge $script:CmosSuspectSec) {
        Add-Finding "Desfase inicial $(Format-Offset $InitialOffset): compatible con pila CMOS agotada."
        Add-NextStep 'Si tras reiniciar la hora vuelve a descuadrarse, la pila CMOS esta agotada: cambio de pila, no se arregla por software.'
    }
    $rtc = $null
    try { $rtc = (Get-ItemProperty -LiteralPath $script:RegTzInfo -Name 'RealTimeIsUniversal' -ErrorAction Stop).RealTimeIsUniversal } catch {}
    if ($null -ne $rtc -and [int]$rtc -ne 0) {
        Add-Finding 'RealTimeIsUniversal=1: Windows lee el reloj de hardware en UTC (arranque dual con Linux).'
        Add-NextStep 'Si el equipo no tiene arranque dual, revisar RealTimeIsUniversal en HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation.'
    } elseif ($abs -gt $script:RtcUtcSuspect -and $abs -lt $script:CmosSuspectSec) {
        $h = $abs / 3600.0
        if ([math]::Abs($h - [math]::Round($h, 0)) -lt 0.05) {
            Add-Finding "Desfase de casi exactamente $([int][math]::Round($h,0)) h: apunta a zona horaria mal configurada o reloj de hardware en UTC, no a deriva."
        }
    }
    try {
        $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Time-Service'; Level = @(2,3); StartTime = (Get-Date).AddDays(-14) } -MaxEvents 5 -ErrorAction Stop)
        foreach ($e in $ev) {
            $msg = ''
            try { $msg = ($e.Message -split "`r?`n")[0] } catch {}
            Write-Log "Evento W32Time $($e.TimeCreated.ToString('yyyy-MM-dd HH:mm')) id $($e.Id): $msg" 'INFO'
        }
        if ($ev.Count -gt 0) { Add-Finding "$($ev.Count) eventos de aviso/error de W32Time en los ultimos 14 dias." }
    } catch {}
}

# ------------------------------------------------------------------ flujo

Write-Log ('=' * 70) 'HEAD'
Write-Log 'Repair-TimeSync.ps1 - sincronizacion horaria de Windows' 'HEAD'
Write-Log ('=' * 70) 'HEAD'
$script:IsAdmin = Test-IsAdmin
Write-Log "Equipo: $env:COMPUTERNAME  Usuario: $env:USERNAME  Admin: $script:IsAdmin" 'INFO'
Write-Log "Log y backups: $script:BackupDir" 'INFO'
if ($script:DryRun) { Write-Log 'MODO SIMULACION: no se aplica ningun cambio' 'DRYRUN' }
if ($DiagnoseOnly)  { Write-Log 'MODO DIAGNOSTICO: solo lectura' 'INFO' }
if (-not $script:IsAdmin -and -not $DiagnoseOnly) {
    Write-Log 'Sin permisos de administrador: solo se podra diagnosticar' 'WARN'
    Add-NextStep 'Relanzar en consola de administrador: powershell -NoProfile -ExecutionPolicy Bypass -File .\Repair-TimeSync.ps1 -Force'
}

Write-Section '1. Estado actual'
$tzNow = ''
try { $tzNow = (Get-TimeZone -ErrorAction Stop).Id } catch {}
Write-Log "Hora local: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))  UTC: $([DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss'))" 'INFO'
Write-Log "Zona horaria: $tzNow" 'INFO'
$state = Get-W32TimeState
Write-Log "W32Time: estado=$($state.Status) inicio=$($state.StartType)" 'INFO'
Write-Log "Type=$($state.TypeValue)  NtpServer=$($state.PeerList)" 'INFO'
if ($state.Source)   { Write-Log "Fuente actual: $($state.Source)" 'INFO' }
if ($state.LastSync) { Write-Log "Ultima sincronizacion: $($state.LastSync)" 'INFO' }
if ($state.Source -match '(?i)CMOS|local') { Add-Finding 'La fuente de hora es el reloj local (CMOS): no sincroniza con nadie.' }
if ($state.Status -ne 'Running') { Add-Finding "El servicio W32Time no estaba en ejecucion (estado: $($state.Status))." }
if ($state.StartType -match '(?i)disabled|deshabilit') { Add-Finding 'El servicio W32Time estaba deshabilitado.' }

Write-Section '2. Ubicacion y emparejamiento'
$geo = Get-GeoLocation
$tzTarget = $TimeZoneId
if ([string]::IsNullOrWhiteSpace($tzTarget)) {
    $tzTarget = Resolve-WindowsTimeZone -Iana $geo.Iana -CountryCode $geo.CountryCode
    if ([string]::IsNullOrWhiteSpace($tzTarget)) {
        $tzTarget = 'Romance Standard Time'
        Write-Log 'Zona no deducible; se asume Espana peninsular (Romance Standard Time)' 'WARN'
    }
} else { Write-Log "Zona horaria forzada por parametro: $tzTarget" 'INFO' }
Write-Log "Zona horaria objetivo: $tzTarget" 'OK'
$candidates = Get-NtpCandidateList -CountryCode $geo.CountryCode
Write-Log "Servidores NTP a evaluar: $($candidates -join ', ')" 'INFO'

$domain = Get-DomainInfo
if ($domain.PartOfDomain) {
    Write-Log "Equipo en dominio: $($domain.Domain)" 'INFO'
    if ($domain.DcReachable) { Write-Log "DC alcanzable: $($domain.DcReachable)" 'OK' }
    else {
        Write-Log 'Ningun controlador de dominio alcanzable (portatil fuera de la red o sin VPN)' 'WARN'
        Add-Finding 'Equipo en dominio sin ver el DC: la jerarquia de dominio no le puede dar la hora ahora.'
    }
} else { Write-Log 'Equipo fuera de dominio (grupo de trabajo o Entra ID)' 'INFO' }

Write-Section '3. Medicion del desfase'
if ($state.Status -ne 'Running' -and $script:IsAdmin -and -not $DiagnoseOnly) {
    Repair-W32TimeService | Out-Null   # /stripchart necesita el servicio arrancado
}
$measure = @()
if ($state.Status -eq 'Running' -or ($script:IsAdmin -and -not $DiagnoseOnly)) {
    $measure = Measure-NtpCandidates -Servers $candidates
} else { Write-Log 'Servicio parado y sin permisos para arrancarlo: no se puede medir por NTP' 'WARN' }
$usable = @($measure | Where-Object { $_.Reachable -and -not $_.Outlier })
$refOffset = $null
$refLabel  = ''
if ($usable.Count -gt 0) {
    # Mediana de los servidores coherentes: mas robusta que un solo servidor.
    $srt = @($usable | Sort-Object Offset)
    $refOffset = $srt[[int][math]::Floor($srt.Count / 2)].Offset
    $refLabel  = "NTP (mediana de $($usable.Count) servidores)"
} else {
    if (@($measure).Count -gt 0) {
        Write-Log 'Ningun servidor NTP respondio: UDP 123 probablemente bloqueado' 'WARN'
        Add-Finding 'Ningun servidor NTP respondio (UDP 123 bloqueado en la red).'
        Add-NextStep 'Abrir salida UDP 123 hacia los servidores NTP, o dar hora por jerarquia de dominio / VPN.'
    }
    $httpUtc = Get-HttpUtcTime
    if ($httpUtc) {
        $refOffset = ($httpUtc - [DateTime]::UtcNow).TotalSeconds
        $refLabel  = 'cabecera HTTP Date'
    }
}
if ($null -ne $refOffset) {
    Write-Log "Desfase medido: $(Format-Offset $refOffset) (referencia: $refLabel)" 'OK'
    if ([math]::Abs($refOffset) -le $script:GoodOffsetSec) { Write-Log 'Reloj dentro de tolerancia para firma electronica' 'OK' }
    else { Add-Finding "Desfase real del reloj: $(Format-Offset $refOffset) (referencia: $refLabel)." }
    Test-PhysicalClockIssues -InitialOffset $refOffset
} else {
    Write-Log 'No se pudo medir el desfase (sin salida NTP ni HTTP)' 'ERROR'
    Add-Finding 'Desfase no medible: sin salida NTP ni HTTP desde el equipo.'
}

if ($DiagnoseOnly) {
    Write-Section 'Diagnostico terminado (-DiagnoseOnly): sin cambios'
} else {
    Write-Section '4. Zona horaria'
    Set-TimeZoneSafe -Id $tzTarget -Reason "ubicacion detectada por $($geo.Source)"
    Set-AutoTimeZoneService

    Write-Section '5. Servicio y configuracion'
    if (Repair-W32TimeService) {
        Set-W32TimeHardening
        if ($domain.PartOfDomain -and $domain.DcReachable -and -not $PersistPublicNtp) { $strategy = 'DomainHierarchy' }
        elseif ($domain.PartOfDomain -and -not $PersistPublicNtp)                      { $strategy = 'OneShotPublic' }
        else                                                                           { $strategy = 'PublicNtp' }
        switch ($strategy) {
            'DomainHierarchy' {
                Write-Log 'Estrategia: jerarquia de dominio (se respeta la configuracion corporativa)' 'STEP'
                Invoke-DomainHierarchyConfig -Dc $domain.DcReachable
            }
            'OneShotPublic' {
                Write-Log 'Estrategia: correccion puntual con NTP publico, sin cambiar la configuracion de dominio' 'STEP'
                Write-Log 'Al reconectar por VPN el equipo volvera a tomar la hora del DC' 'INFO'
                Add-NextStep 'Para persistir NTP publico en este portatil (contra la GPO), relanzar con -PersistPublicNtp.'
            }
            'PublicNtp' {
                Write-Log 'Estrategia: NTP publico del pais detectado' 'STEP'
                # Orden de preferencia: nacionales/oficiales primero, no el de menor desfase.
                $peers = @($candidates | Where-Object { $usable.Server -contains $_ })
                if ($peers.Count -eq 0) { $peers = @($candidates | Select-Object -First 3) }
                Invoke-PublicNtpConfig -Peers $peers
            }
        }

        Write-Section '6. Resincronizacion y verificacion'
        if ($strategy -ne 'OneShotPublic') { Invoke-Resync -Attempts 3 | Out-Null }
        else { Write-Log 'Se omite /resync: la jerarquia de dominio no es alcanzable ahora' 'INFO' }

        $finalOffset = $null
        if ($usable.Count -gt 0) {
            $bestSrv = @($candidates | Where-Object { $usable.Server -contains $_ })[0]
            $finalOffset = Get-NtpOffset -Server $bestSrv
            if ($null -ne $finalOffset) { Write-Log "Desfase tras sincronizar (contra $bestSrv): $(Format-Offset $finalOffset)" 'INFO' }
        }
        if ($null -eq $finalOffset) {
            $h2 = Get-HttpUtcTime
            if ($h2) { $finalOffset = ($h2 - [DateTime]::UtcNow).TotalSeconds }
        }
        if ($null -ne $finalOffset -and [math]::Abs($finalOffset) -le $script:GoodOffsetSec) {
            Write-Log "Reloj en hora: desfase $(Format-Offset $finalOffset). El usuario ya puede firmar y tramitar" 'OK'
        } elseif ($null -ne $finalOffset) {
            Write-Log "El reloj sigue desfasado $(Format-Offset $finalOffset) tras sincronizar" 'WARN'
            if ($script:DryRun) { Write-Log "[SIMULACION] Se ajustaria la hora $(Format-Offset $finalOffset)" 'DRYRUN' }
            else {
                if (Set-SystemTimeFromReference -OffsetSeconds $finalOffset -SourceLabel $refLabel) {
                    if (Invoke-Resync -Attempts 1) { Write-Log 'Sincronizacion normal restablecida tras el ajuste' 'OK' }
                }
            }
        } else { Write-Log 'No se pudo verificar el desfase final' 'WARN' }
    }
}

Write-Section 'Resumen'
$end = Get-W32TimeState
$tzEnd = ''
try { $tzEnd = (Get-TimeZone -ErrorAction Stop).Id } catch {}
Write-Log "Hora local: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))" 'INFO'
Write-Log "Zona horaria: $tzEnd" 'INFO'
Write-Log "W32Time: $($end.Status) / $($end.StartType)  Fuente: $($end.Source)" 'INFO'
Write-Log "Ultima sincronizacion: $($end.LastSync)" 'INFO'
Write-Log "Cambios: $($script:Stats.Changed)  Sin cambio: $($script:Stats.Skipped)  Avisos: $($script:Stats.Warnings)  Errores: $($script:Stats.Errors)" 'INFO'
if ($script:Findings.Count -gt 0) {
    Write-Log 'Hallazgos (para el ticket):' 'STEP'
    foreach ($f in $script:Findings) { Write-Log " - $f" 'INFO' }
}
if ($script:NextSteps.Count -gt 0) {
    Write-Log 'Siguientes pasos:' 'STEP'
    foreach ($n in $script:NextSteps) { Write-Log " - $n" 'WARN' }
}
if ($script:Backups.Count -gt 0) {
    Write-Log 'Rollback de registro si hiciera falta:' 'STEP'
    foreach ($b in $script:Backups) { Write-Log " reg import `"$b`"" 'INFO' }
}
Write-Log "Log completo: $script:LogFile" 'INFO'
