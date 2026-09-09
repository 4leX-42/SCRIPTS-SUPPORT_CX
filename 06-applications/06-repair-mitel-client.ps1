<#
.SYNOPSIS
    [ES] Repara el cliente Mitel Connect / MiCollab: cache, registro, Outlook, credenciales y DNS.
    [EN] Repairs the Mitel Connect / MiCollab client: cache, registry, Outlook, credentials and DNS.

.DESCRIPTION
    [ES]
    Para el caso tipico de "el Mitel no arranca", "se queda conectando", "pide credenciales
    en bucle" o "no conecta al servidor". Diagnostica primero y solo actua sobre lo que
    existe, en dos mitades que no cubre la misma cuenta:

      Cliente : procesos y servicios Mitel, cache y perfil (%APPDATA% y %LOCALAPPDATA%,
                incluida la herencia de ShoreTel), %PROGRAMDATA%, HKCU\Software\Mitel,
                complemento de Outlook (se retira por defecto: no hace falta para
                telefonear) y lista de resiliencia de Outlook (DisabledItems /
                CrashingAddinList), y credenciales guardadas.
      Red     : servidores DNS del adaptador fisico, sufijo DNS de busqueda, archivo hosts,
                reglas de firewall del ejecutable del cliente y caches de resolucion
                (DNS, ARP, NetBIOS).

    Descubre el servidor Mitel sin que haya que decirlo: lo saca de las credenciales
    guardadas (el cliente las guarda como Mitel/<servidor>/<usuario>), de la configuracion
    y el registro del cliente, de los registros SRV de voz del dominio y de nombres
    habituales contra el sufijo DNS del equipo. Descarta webs publicas y telemetria para no
    perseguir hosts que no son el PBX. Con el candidato elegido comprueba resolucion DNS y
    puertos 443, 5060, 5061, 5222 y 31453, y prueba cada servidor DNS del adaptador por
    separado para senalar cual es el que no resuelve.

    Limites deliberados: no reinicia el equipo, no resetea Winsock ni la pila TCP/IP, no
    toca otros servicios ni otras aplicaciones, y excluye adaptadores virtuales
    (VMware, Hyper-V, Npcap, loopback). Antes de modificar algo copia a la carpeta de log
    cada clave de registro (.reg), el archivo hosts y la configuracion DNS previa, esta con
    el comando exacto de reversion en dns_backup.txt.

    Con -FixDns solo devuelve a DHCP los servidores DNS FIJOS que no resuelven el servidor
    Mitel; si resuelven, no los toca.

    [EN]
    For the usual "Mitel won't start", "stuck on connecting", "credential prompt loop" or
    "cannot connect to server" cases. Diagnoses first and only acts on what exists, split in
    two halves that require different accounts:

      Client  : Mitel processes and services, cache and profile (%APPDATA%, %LOCALAPPDATA%,
                including ShoreTel leftovers), %PROGRAMDATA%, HKCU\Software\Mitel, the
                Outlook add-in and Outlook resiliency lists, and stored credentials.
      Network : DNS servers on physical adapters, DNS search suffix, hosts file, firewall
                rules for the client executable and name resolution caches.

    Discovers the Mitel server on its own from stored credentials, client configuration and
    registry, domain voice SRV records and common host names against the machine DNS
    suffixes, then checks DNS resolution and ports 443, 5060, 5061, 5222 and 31453, testing
    each configured DNS server separately.

    Never reboots, never resets Winsock or the TCP/IP stack, never touches unrelated
    services. Registry keys, the hosts file and the previous DNS configuration are backed up
    before any change, with the exact revert command in dns_backup.txt.

.PARAMETER DryRun
    Simula la ejecucion completa sin cambiar nada. Recomendado en la primera pasada.

.PARAMETER Force
    Omite la confirmacion interactiva. Se ignora con -DryRun.

.PARAMETER AllUsers
    Limpia el perfil de todos los usuarios del equipo, montando su NTUSER.DAT cuando no
    tienen sesion abierta. Requiere administrador.

.PARAMETER KeepOutlookAddin
    Conserva el complemento Mitel de Outlook y lo reactiva si Outlook lo dejo desactivado.
    Por defecto el complemento se ELIMINA: no es necesario para telefonear y es una causa
    habitual de arranques lentos y cuelgues de Outlook. La clave se exporta a .reg en la
    carpeta de log, asi que se puede restaurar con un doble clic.

.PARAMETER DisableOutlookAddin
    En vez de eliminarlo, lo deja instalado pero desactivado (LoadBehavior=0). Util cuando
    el complemento lo despliega una GPO y volveria a aparecer al siguiente ciclo.

.PARAMETER KeepCredentials
    No borra las credenciales guardadas de Mitel.

.PARAMETER ServerHost
    Servidor Mitel contra el que verificar DNS y puertos. Si se omite, se descubre solo.

.PARAMETER FixDns
    Corrige la configuracion DNS: devuelve a DHCP los DNS fijos que no resuelven y aplica el
    sufijo de busqueda. Requiere administrador.

.PARAMETER DnsServers
    Servidores DNS a fijar en los adaptadores fisicos activos, en orden. Implica -FixDns.

.PARAMETER DnsSuffix
    Sufijo DNS a anadir a la lista de busqueda, necesario si el cliente usa el nombre corto
    del servidor. Implica -FixDns.

.PARAMETER FixHosts
    Comenta las entradas Mitel del archivo hosts cuya IP no responde. Requiere administrador.

.PARAMETER FixFirewall
    Crea reglas de permiso de entrada y salida para el ejecutable del cliente si no existen.
    Requiere administrador.

.PARAMETER Reinstall
    Ruta al instalador del cliente. Tras la limpieza lo ejecuta en silencio con
    /s /v"/qn REBOOT=ReallySuppress". Requiere administrador.

.PARAMETER LogPath
    Carpeta de log y copias de seguridad. Por defecto una carpeta con marca de tiempo en %TEMP%.

.EXAMPLE
    .\06-repair-mitel-client.ps1 -DryRun
    Simulacion completa: diagnostico y lo que se haria, sin cambiar nada.

.EXAMPLE
    .\06-repair-mitel-client.ps1
    Pasada de usuario, con la sesion del usuario afectado y sin elevar: cache, HKCU,
    Outlook y credenciales.

.EXAMPLE
    .\06-repair-mitel-client.ps1 -AllUsers -FixDns -FixHosts -FixFirewall -Force
    Pasada de maquina en consola de administrador. Es la que resuelve el "no conecta al
    servidor", porque ahi vive el DNS.

.EXAMPLE
    .\06-repair-mitel-client.ps1 -DnsServers 10.10.0.10,10.10.0.11 -DnsSuffix midominio.local -Force
    Fija los DNS del dominio y el sufijo de busqueda cuando el equipo de red los facilita.

.EXAMPLE
    .\06-repair-mitel-client.ps1 -KeepOutlookAddin
    Limpieza conservando el complemento de Outlook (lo reactiva si estaba desactivado).

.NOTES
    PowerShell 5.1 y 7.
    Dos pasadas: primero sin admin en la sesion del usuario afectado (perfil, HKCU, Outlook,
    credenciales), luego en consola de administrador (ProgramData, servicios, DNS, hosts,
    firewall). El script detecta con que cuenta se ejecuta, omite con aviso lo que no puede
    hacer y al final imprime el comando de la pasada que falta.
#>


[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Force,
    [switch]$AllUsers,
    [switch]$KeepOutlookAddin,
    [switch]$DisableOutlookAddin,
    [switch]$KeepCredentials,
    [string]$ServerHost,
    [switch]$FixDns,
    [string[]]$DnsServers,
    [string]$DnsSuffix,
    [switch]$FixHosts,
    [switch]$FixFirewall,
    [string]$Reinstall,
    [string]$LogPath
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
$script:DryRun         = [bool]$DryRun
$script:Stats          = @{ Removed = 0; Skipped = 0; Warnings = 0; Errors = 0 }
$script:Findings       = New-Object System.Collections.ArrayList
$script:StoppedSvcs    = New-Object System.Collections.ArrayList
$script:TestName       = $null
$script:ServerCands    = @()

try { $stamp = (Get-Date).ToString('yyyyMMdd_HHmmss') } catch { $stamp = 'run' }
if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $base = $env:TEMP
    if ([string]::IsNullOrWhiteSpace($base)) { $base = $env:LOCALAPPDATA }
    if ([string]::IsNullOrWhiteSpace($base)) { $base = 'C:\Windows\Temp' }
    $script:BackupDir = Join-Path $base ("MitelFix_" + $stamp)
} else {
    $script:BackupDir = $LogPath
}
try {
    if (-not (Test-Path -LiteralPath $script:BackupDir)) {
        New-Item -ItemType Directory -Path $script:BackupDir -Force -ErrorAction Stop | Out-Null
    }
} catch { $script:BackupDir = 'C:\Windows\Temp' }
$script:LogFile = Join-Path $script:BackupDir 'Repair-MitelClient.log'

$script:MitelProcNames = @(
    'MitelConnect','ConnectAgent','Mitel.Connect','MiCollab','MiVoice',
    'ShoreTel','ShoreTelCommunicator','ShoreTelAgent','MitelSoftphone','MiCollabClient'
)
$script:UserRelPaths = @(
    'AppData\Roaming\Mitel','AppData\Local\Mitel',
    'AppData\Roaming\ShoreTel','AppData\Local\ShoreTel',
    'AppData\Roaming\MiCollab','AppData\Local\MiCollab',
    'AppData\Local\Temp\Mitel','AppData\Local\Temp\ShoreTel'
)
$script:MachinePaths = @(
    (Join-Path $env:ProgramData 'Mitel'),
    (Join-Path $env:ProgramData 'ShoreTel'),
    (Join-Path $env:ProgramData 'MiCollab')
)
$script:UserRegSuffixes = @('Software\Mitel','Software\ShoreTel','Software\MiCollab')
$script:AddinRegRoots = @(
    'HKCU\Software\Microsoft\Office\Outlook\Addins',
    'HKLM\SOFTWARE\Microsoft\Office\Outlook\Addins',
    'HKLM\SOFTWARE\WOW6432Node\Microsoft\Office\Outlook\Addins'
)
$script:MitelAddinPatterns = @('*Mitel*','*MiCollab*','*MiVoice*','*ShoreTel*')
$script:VoiceRegex   = 'mitel|shoretel|micollab|mivoice|director|pbx|voip|sip|telef|phone|ucb|mbg'
$script:CommonNames  = @('hq','mitel','micollab','connect','mbg','ucb','mivoice','shoretel','director','pbx')
$script:SrvRecords   = @('_sip._tcp','_sip._udp','_sipinternaltls._tcp','_xmpp-client._tcp')
$script:VirtualNic   = 'VMware|VirtualBox|Hyper-V|Loopback|Npcap|TAP-|Bluetooth|WSL|vEthernet'
$script:MitelPorts = @(
    @{ Port = 443;   Desc = 'HTTPS / MiCollab' },
    @{ Port = 5060;  Desc = 'SIP' },
    @{ Port = 5061;  Desc = 'SIP TLS' },
    @{ Port = 5222;  Desc = 'XMPP presencia' },
    @{ Port = 31453; Desc = 'Mitel Connect servicios' }
)

# ---------------------------------------------------------------- utilidades

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
    try { Write-Host $line -ForegroundColor $color } catch { try { Write-Host $line } catch {} }
    try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
}

function Write-Section {
    param([string]$Title)
    Write-Log ('-' * 70) 'HEAD'
    Write-Log $Title 'STEP'
    Write-Log ('-' * 70) 'HEAD'
}

function Add-Finding { param([string]$Text) try { [void]$script:Findings.Add($Text) } catch {} }

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Test-PathSafe {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try { return (Test-Path -LiteralPath $Path) } catch { return $false }
}

function Get-FolderSizeMB {
    param([string]$Path)
    if (-not (Test-PathSafe $Path)) { return 0 }
    try {
        $b = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
              Measure-Object -Property Length -Sum).Sum
        if (-not $b) { return 0 }
        return [math]::Round($b / 1MB, 1)
    } catch { return 0 }
}

function Remove-ItemSafe {
    param([string]$Path, [string]$Label)
    if ([string]::IsNullOrWhiteSpace($Label)) { $Label = $Path }
    if ([string]::IsNullOrWhiteSpace($Path))  { return }
    if (-not (Test-PathSafe $Path)) { $script:Stats.Skipped++; return }
    $mb = Get-FolderSizeMB $Path
    if ($script:DryRun) { Write-Log "[SIMULACION] Se eliminaria: $Label ($mb MB)" 'DRYRUN'; return }
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        if (Test-PathSafe $Path) { Write-Log "Parcial (archivos en uso): $Label" 'WARN' }
        else { Write-Log "Eliminado: $Label ($mb MB)" 'OK'; $script:Stats.Removed++ }
    } catch { Write-Log "No se pudo eliminar '$Label': $($_.Exception.Message)" 'WARN' }
}

function Stop-ProcessSafe {
    param([string[]]$Names)
    foreach ($n in $Names) {
        $procs = @()
        try { $procs = @(Get-Process -Name $n -ErrorAction SilentlyContinue) } catch {}
        foreach ($p in $procs) {
            if ($script:DryRun) { Write-Log "[SIMULACION] Se cerraria: $n (PID $($p.Id))" 'DRYRUN'; continue }
            try {
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
                Write-Log "Proceso cerrado: $n (PID $($p.Id))" 'OK'
            } catch { Write-Log "No se pudo cerrar $n : $($_.Exception.Message)" 'WARN' }
        }
    }
}

function ConvertTo-ProviderPath {
    param([string]$KeyPath)
    $p = $KeyPath
    $p = $p -replace '^HKCU\\', 'HKCU:\'
    $p = $p -replace '^HKLM\\', 'HKLM:\'
    $p = $p -replace '^HKU\\',  'Registry::HKEY_USERS\'
    return $p
}

function Backup-RegistryKey {
    param([string]$KeyPath)
    if (-not (Test-PathSafe (ConvertTo-ProviderPath $KeyPath))) { return $false }
    $file = Join-Path $script:BackupDir ("reg_" + ($KeyPath -replace '[\\:*?"<>|]', '_') + ".reg")
    try {
        $out = & reg.exe export "$KeyPath" "$file" /y 2>&1
        if ($LASTEXITCODE -eq 0) { return $true }
        Write-Log "No se pudo exportar $KeyPath ($out)" 'WARN'
        return $false
    } catch { Write-Log "Error exportando $KeyPath : $($_.Exception.Message)" 'WARN'; return $false }
}

function Remove-RegistryKeySafe {
    param([string]$KeyPath, [string]$Label)
    if ([string]::IsNullOrWhiteSpace($Label)) { $Label = $KeyPath }
    $provider = ConvertTo-ProviderPath $KeyPath
    if (-not (Test-PathSafe $provider)) { $script:Stats.Skipped++; return }
    Backup-RegistryKey -KeyPath $KeyPath | Out-Null
    if ($script:DryRun) { Write-Log "[SIMULACION] Se eliminaria clave: $Label" 'DRYRUN'; return }
    try {
        Remove-Item -LiteralPath $provider -Recurse -Force -ErrorAction Stop
        Write-Log "Clave eliminada: $Label" 'OK'
        $script:Stats.Removed++
    } catch { Write-Log "Error al eliminar '$Label': $($_.Exception.Message)" 'WARN' }
}

function Invoke-Native {
    param([string]$File, [string[]]$Arguments)
    try { return (& $File @Arguments 2>&1 | Out-String) }
    catch { Write-Log "No se pudo ejecutar '$File': $($_.Exception.Message)" 'WARN'; return '' }
}

function Invoke-NativeStep {
    param([string]$File, [string[]]$Arguments, [string]$Label)
    if ([string]::IsNullOrWhiteSpace($Label)) { $Label = "$File $($Arguments -join ' ')" }
    if ($script:DryRun) { Write-Log "[SIMULACION] Se ejecutaria: $Label" 'DRYRUN'; return }
    $cmd = $null
    try { $cmd = Get-Command $File -ErrorAction Stop } catch {}
    if (-not $cmd) { Write-Log "Herramienta no disponible: $File" 'WARN'; return }
    $null = Invoke-Native -File $File -Arguments $Arguments
    if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) { Write-Log "OK: $Label" 'OK' }
    else { Write-Log "Fallo (codigo $LASTEXITCODE): $Label" 'WARN' }
}

# --------------------------------------------------------------------- perfiles

function Get-UserProfileList {
    $result = New-Object System.Collections.ArrayList
    if (-not $AllUsers) {
        [void]$result.Add([pscustomobject]@{ Name = $env:USERNAME; Path = $env:USERPROFILE; Sid = $null; Current = $true })
        return $result
    }
    $plKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    $currentSid = $null
    try { $currentSid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value } catch {}
    $subs = @()
    try { $subs = @(Get-ChildItem -LiteralPath $plKey -ErrorAction SilentlyContinue) } catch {}
    foreach ($s in $subs) {
        $sid = $s.PSChildName
        if ($sid -notmatch '^S-1-5-21-') { continue }
        $pp = $null
        try { $pp = (Get-ItemProperty -LiteralPath $s.PSPath -ErrorAction SilentlyContinue).ProfileImagePath } catch {}
        if (-not (Test-PathSafe $pp)) { continue }
        [void]$result.Add([pscustomobject]@{
            Name = (Split-Path $pp -Leaf); Path = $pp; Sid = $sid; Current = ($sid -eq $currentSid)
        })
    }
    if ($result.Count -eq 0) {
        [void]$result.Add([pscustomobject]@{ Name = $env:USERNAME; Path = $env:USERPROFILE; Sid = $null; Current = $true })
    }
    return $result
}

function Clear-UserRegistryHive {
    param([pscustomobject]$UserProfile)

    if ($UserProfile.Current -or -not $UserProfile.Sid) {
        foreach ($suf in $script:UserRegSuffixes) {
            Remove-RegistryKeySafe -KeyPath ("HKCU\" + $suf) -Label "HKCU\$suf [$($UserProfile.Name)]"
        }
        return
    }
    if (Test-PathSafe "Registry::HKEY_USERS\$($UserProfile.Sid)") {
        foreach ($suf in $script:UserRegSuffixes) {
            Remove-RegistryKeySafe -KeyPath ("HKU\$($UserProfile.Sid)\" + $suf) -Label "$($UserProfile.Name)\$suf"
        }
        return
    }
    $dat = Join-Path $UserProfile.Path 'NTUSER.DAT'
    if (-not (Test-PathSafe $dat)) { return }
    if (-not (Test-IsAdmin)) { Write-Log "Sin admin para montar el registro de $($UserProfile.Name)." 'WARN'; return }
    if ($script:DryRun) { Write-Log "[SIMULACION] Se montaria NTUSER.DAT de $($UserProfile.Name)" 'DRYRUN'; return }

    $mount = 'MitelFix_' + ($UserProfile.Name -replace '[^A-Za-z0-9]', '_')
    $null = Invoke-Native -File 'reg.exe' -Arguments @('load', "HKU\$mount", $dat)
    if ($LASTEXITCODE -ne 0) { Write-Log "Registro de $($UserProfile.Name) en uso: omitido." 'WARN'; return }
    try {
        foreach ($suf in $script:UserRegSuffixes) {
            Remove-RegistryKeySafe -KeyPath ("HKU\$mount\" + $suf) -Label "$($UserProfile.Name)\$suf"
        }
    } finally {
        try { [gc]::Collect(); [gc]::WaitForPendingFinalizers() } catch {}
        $null = Invoke-Native -File 'reg.exe' -Arguments @('unload', "HKU\$mount")
    }
}

# -------------------------------------------------------------------- red / DNS

function Get-ActiveAdapterInfo {
    $list = New-Object System.Collections.ArrayList
    if (Get-Command Get-NetIPConfiguration -ErrorAction SilentlyContinue) {
        $cfgs = @()
        try { $cfgs = @(Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPv4Address }) } catch {}
        foreach ($c in $cfgs) {
            $dns = @()
            try {
                $d = Get-DnsClientServerAddress -InterfaceIndex $c.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
                if ($d) { $dns = @($d.ServerAddresses) }
            } catch {}
            $static = $false
            $desc   = ''
            try {
                $na = Get-NetAdapter -InterfaceIndex $c.InterfaceIndex -ErrorAction SilentlyContinue
                if ($na) {
                    $desc = [string]$na.InterfaceDescription
                    $rk = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($na.InterfaceGuid)"
                    if (Test-PathSafe $rk) {
                        $ns = (Get-ItemProperty -LiteralPath $rk -ErrorAction SilentlyContinue).NameServer
                        if (-not [string]::IsNullOrWhiteSpace($ns)) { $static = $true }
                    }
                }
            } catch {}
            $connSuffix = ''
            try { $connSuffix = (Get-DnsClient -InterfaceIndex $c.InterfaceIndex -ErrorAction SilentlyContinue).ConnectionSpecificSuffix } catch {}
            $gw = $null
            try { $gw = ($c.IPv4DefaultGateway | Select-Object -First 1).NextHop } catch {}
            $ip = $null
            try { $ip = ($c.IPv4Address | Select-Object -First 1).IPAddress } catch {}
            [void]$list.Add([pscustomobject]@{
                Index = $c.InterfaceIndex; Name = $c.InterfaceAlias; Desc = $desc
                IPv4 = $ip; Gateway = $gw; DnsServers = $dns; StaticDns = $static; ConnSuffix = $connSuffix
            })
        }
        return $list
    }
    $adapters = @()
    try { $adapters = @(Get-CimInstance Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPEnabled }) } catch {}
    foreach ($a in $adapters) {
        [void]$list.Add([pscustomobject]@{
            Index = $a.InterfaceIndex; Name = $a.Description; Desc = $a.Description
            IPv4 = ($a.IPAddress | Where-Object { $_ -notmatch ':' } | Select-Object -First 1)
            Gateway = ($a.DefaultIPGateway | Select-Object -First 1)
            DnsServers = @($a.DNSServerSearchOrder); StaticDns = (-not $a.DHCPEnabled)
            ConnSuffix = [string]$a.DNSDomain
        })
    }
    return $list
}

function Get-RelevantAdapters {
    param([array]$Adapters)
    return @($Adapters | Where-Object {
        $_.Gateway -and $_.Name -notmatch $script:VirtualNic -and $_.Desc -notmatch $script:VirtualNic
    })
}

function Test-DnsResolution {
    param([string]$Name, [string]$Server)
    $res = [pscustomobject]@{ Ok = $false; Ips = @() }
    if ([string]::IsNullOrWhiteSpace($Name)) { return $res }
    if (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue) {
        try {
            $p = @{ Name = $Name; Type = 'A'; DnsOnly = $true; ErrorAction = 'SilentlyContinue' }
            if (-not [string]::IsNullOrWhiteSpace($Server)) { $p['Server'] = $Server }
            $ips = @(Resolve-DnsName @p | Where-Object { $_.IPAddress } | Select-Object -ExpandProperty IPAddress -Unique)
            if ($ips.Count -gt 0) { $res.Ok = $true; $res.Ips = $ips; return $res }
        } catch {}
    }
    if ([string]::IsNullOrWhiteSpace($Server)) {
        try {
            $ips = @([System.Net.Dns]::GetHostAddresses($Name) | ForEach-Object { $_.IPAddressToString })
            if ($ips.Count -gt 0) { $res.Ok = $true; $res.Ips = $ips }
        } catch {}
    }
    return $res
}

function Get-DnsSuffixList {
    if ($script:SuffixCache) { return $script:SuffixCache }
    $suffixes = New-Object System.Collections.ArrayList
    $add = {
        param($s)
        if ([string]::IsNullOrWhiteSpace($s)) { return }
        $v = $s.Trim().TrimStart('.')
        if ($v -and -not $suffixes.Contains($v)) { [void]$suffixes.Add($v) }
    }
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        if ($cs -and $cs.PartOfDomain) { & $add $cs.Domain }
    } catch {}
    & $add $env:USERDNSDOMAIN
    try {
        $tcp = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -ErrorAction SilentlyContinue
        if ($tcp) {
            & $add $tcp.'NV Domain'
            & $add $tcp.Domain
            if ($tcp.SearchList) { foreach ($s in ($tcp.SearchList -split ',')) { & $add $s } }
        }
    } catch {}
    foreach ($ad in $script:Adapters) { & $add $ad.ConnSuffix }
    $script:SuffixCache = $suffixes
    return $suffixes
}

function Test-LooksLikeMitelHost {
    param([string]$HostName)
    if ([string]::IsNullOrWhiteSpace($HostName)) { return $false }
    $h = $HostName.Trim().TrimEnd('.').ToLower()
    $blacklist = 'newrelic|instagram|facebook|google|gstatic|akamai|cloudfront|azureedge|' +
                 'microsoft\.com|windows\.com|msftconnecttest|office\.com|office365|live\.com|' +
                 'digicert|verisign|globalsign|sectigo|entrust|godaddy|schemas|w3\.org|localhost|' +
                 'example\.|apple\.com|mozilla|adobe|cloudflare|doubleclick|youtube|twitter|' +
                 'linkedin|amazonaws|sentry\.io|crashlytics|bing\.com'
    if ($h -match $blacklist) { return $false }
    if ($h -notmatch '^[a-z0-9][a-z0-9._-]*[a-z0-9]$') { return $false }
    # webs publicas del fabricante y portales, no servidores de telefonia
    if ($h -match '^(www|support|docs|kb|help|community|status|blog|api|cdn|download|login)\.') { return $false }
    if ($h -match '(^|\.)(mitel|shoretel|micollab)\.(com|net|org|co\.uk|es)$') { return $false }
    if ($h -match $script:VoiceRegex) { return $true }
    foreach ($suf in (Get-DnsSuffixList)) {
        if ($h -like ("*." + $suf.ToLower()) -or $h -eq $suf.ToLower()) { return $true }
    }
    foreach ($ip in (Test-DnsResolution -Name $h).Ips) {
        if ($ip -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)') { return $true }
    }
    return $false
}

function Get-MitelCredentialHosts {
    # El cliente guarda credenciales como LegacyGeneric:target=Mitel/<servidor>/<usuario>
    $found = New-Object System.Collections.ArrayList
    foreach ($line in ((Invoke-Native -File 'cmdkey.exe' -Arguments @('/list')) -split "`r?`n")) {
        if ($line -notmatch 'Mitel|ShoreTel|MiCollab') { continue }
        foreach ($m in [regex]::Matches($line, '[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9][A-Za-z0-9-]*)+')) {
            $c = $m.Value.Trim('.', '/', '\', ' ')
            if ($c -match '^(LegacyGeneric|Domain|WindowsLive)') { continue }
            if ($c -notmatch '\.') { continue }
            if (-not $found.Contains($c)) { [void]$found.Add($c) }
        }
    }
    return $found
}

function Get-MitelConfigHosts {
    $found = New-Object System.Collections.ArrayList
    $regRoots = @('HKCU:\Software\Mitel','HKCU:\Software\ShoreTel','HKLM:\SOFTWARE\Mitel','HKLM:\SOFTWARE\WOW6432Node\Mitel')
    foreach ($root in $regRoots) {
        if (-not (Test-PathSafe $root)) { continue }
        $keys = @()
        try {
            $keys = @(Get-Item -LiteralPath $root -ErrorAction SilentlyContinue) +
                    @(Get-ChildItem -LiteralPath $root -Recurse -ErrorAction SilentlyContinue)
        } catch {}
        foreach ($k in $keys) {
            $props = $null
            try { $props = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue } catch {}
            if (-not $props) { continue }
            foreach ($p in $props.PSObject.Properties) {
                if ($p.Name -notmatch 'server|host|hq|url|address|sip|domain') { continue }
                $val = [string]$p.Value
                if ([string]::IsNullOrWhiteSpace($val)) { continue }
                $h = $val
                if ($val -match '^[a-z]+://([^/:\s]+)') { $h = $Matches[1] }
                if ($h -match '^[A-Za-z0-9][A-Za-z0-9._-]{2,}$' -and -not $found.Contains($h)) { [void]$found.Add($h) }
            }
        }
    }
    $cfgRoots = @((Join-Path $env:APPDATA 'Mitel'), (Join-Path $env:LOCALAPPDATA 'Mitel'), (Join-Path $env:APPDATA 'ShoreTel'))
    foreach ($cr in $cfgRoots) {
        if (-not (Test-PathSafe $cr)) { continue }
        $files = @()
        try {
            $files = @(Get-ChildItem -LiteralPath $cr -Recurse -File -Include *.xml,*.config,*.json,*.ini -ErrorAction SilentlyContinue |
                       Select-Object -First 40)
        } catch {}
        foreach ($f in $files) {
            $txt = ''
            try { $txt = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction SilentlyContinue } catch {}
            if (-not $txt) { continue }
            foreach ($m in [regex]::Matches($txt, '(?i)https?://([A-Za-z0-9][A-Za-z0-9._-]{2,})')) {
                $h = $m.Groups[1].Value
                if (-not $found.Contains($h)) { [void]$found.Add($h) }
            }
        }
    }
    return $found
}

function Find-MitelServer {
    param([string[]]$Explicit)
    $cands = New-Object System.Collections.ArrayList
    $seen  = New-Object System.Collections.ArrayList

    $addCand = {
        param($HostName, $Source, $Trusted)
        if ([string]::IsNullOrWhiteSpace($HostName)) { return }
        $h = $HostName.Trim().TrimEnd('.')
        if ($seen.Contains($h.ToLower())) { return }
        if (-not $Trusted -and -not (Test-LooksLikeMitelHost $h)) { return }
        [void]$seen.Add($h.ToLower())
        [void]$cands.Add([pscustomobject]@{
            Host = $h; Source = $Source; Dns = $false; Ips = @(); OpenPorts = @()
        })
    }

    foreach ($e in @($Explicit)) { & $addCand $e '-ServerHost' $true }
    foreach ($c in (Get-MitelCredentialHosts)) { & $addCand $c 'credencial guardada' $false }
    foreach ($c in (Get-MitelConfigHosts))     { & $addCand $c 'configuracion del cliente' $false }

    $suffixes = Get-DnsSuffixList
    if ($suffixes.Count -gt 0) { Write-Log "Sufijos DNS: $($suffixes -join ', ')" 'INFO' }
    if (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue) {
        foreach ($suf in $suffixes) {
            foreach ($srv in $script:SrvRecords) {
                try {
                    $r = Resolve-DnsName -Name "$srv.$suf" -Type SRV -ErrorAction SilentlyContinue
                    foreach ($rec in @($r | Where-Object { $_.NameTarget })) { & $addCand $rec.NameTarget "SRV $srv.$suf" $true }
                } catch {}
            }
            foreach ($cn in $script:CommonNames) {
                $fqdn = "$cn.$suf"
                if ((Test-DnsResolution -Name $fqdn).Ok) { & $addCand $fqdn 'nombre habitual' $true }
            }
        }
    }

    foreach ($c in $cands) {
        $t = Test-DnsResolution -Name $c.Host
        $c.Dns = $t.Ok
        $c.Ips = $t.Ips
        if (-not $t.Ok) { continue }
        $open = New-Object System.Collections.ArrayList
        foreach ($p in $script:MitelPorts) {
            try {
                $cl  = New-Object System.Net.Sockets.TcpClient
                $iar = $cl.BeginConnect($c.Host, $p.Port, $null, $null)
                if ($iar.AsyncWaitHandle.WaitOne(1200, $false) -and $cl.Connected) { [void]$open.Add($p.Port) }
                try { $cl.Close() } catch {}
            } catch {}
        }
        $c.OpenPorts = @($open)
    }

    return @($cands | Sort-Object -Property `
        @{ Expression = { switch -Regex ($_.Source) { '-ServerHost' { 3 } 'credencial|SRV' { 2 } default { 1 } } }; Descending = $true }, `
        @{ Expression = { $_.OpenPorts.Count }; Descending = $true }, `
        @{ Expression = { [int]$_.Dns };        Descending = $true })
}

function Test-MitelConnectivity {
    param([string]$HostName)
    if ([string]::IsNullOrWhiteSpace($HostName)) { return }
    Write-Log "Servidor: $HostName" 'STEP'
    $t = Test-DnsResolution -Name $HostName
    if (-not $t.Ok) {
        Write-Log "  DNS NO RESUELVE" 'ERROR'
        Add-Finding "'$HostName' no resuelve por DNS. Revisa DNS del adaptador, sufijo de busqueda y VPN."
        return
    }
    Write-Log "  DNS OK -> $($t.Ips -join ', ')" 'OK'
    foreach ($p in $script:MitelPorts) {
        $ok = $false
        try {
            $cl  = New-Object System.Net.Sockets.TcpClient
            $iar = $cl.BeginConnect($HostName, $p.Port, $null, $null)
            $ok = $iar.AsyncWaitHandle.WaitOne(2000, $false) -and $cl.Connected
            try { $cl.Close() } catch {}
        } catch {}
        if ($ok) { Write-Log ("  puerto {0,-6} abierto - {1}" -f $p.Port, $p.Desc) 'OK' }
        else     { Write-Log ("  puerto {0,-6} cerrado - {1}" -f $p.Port, $p.Desc) 'INFO' }
    }
}

function Backup-DnsConfig {
    param([array]$Adapters)
    $file  = Join-Path $script:BackupDir 'dns_backup.txt'
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add("Configuracion DNS previa - $env:COMPUTERNAME")
    foreach ($a in $Adapters) {
        [void]$lines.Add("")
        [void]$lines.Add("$($a.Name) (idx $($a.Index)) IP=$($a.IPv4) GW=$($a.Gateway)")
        [void]$lines.Add("  DNS: $($a.DnsServers -join ', ')  origen: " + $(if ($a.StaticDns) { 'FIJO' } else { 'DHCP' }))
        if ($a.StaticDns -and $a.DnsServers.Count -gt 0) {
            [void]$lines.Add("  revertir: Set-DnsClientServerAddress -InterfaceIndex $($a.Index) -ServerAddresses $($a.DnsServers -join ',')")
        } else {
            [void]$lines.Add("  revertir: Set-DnsClientServerAddress -InterfaceIndex $($a.Index) -ResetServerAddresses")
        }
    }
    try {
        Set-Content -LiteralPath $file -Value $lines -Encoding UTF8 -ErrorAction Stop
        Write-Log "DNS previo guardado en: $file" 'OK'
    } catch { Write-Log "No se pudo guardar dns_backup.txt: $($_.Exception.Message)" 'WARN' }
}

function Repair-DnsConfiguration {
    param([array]$Adapters, [string]$TestName)
    if (-not $script:IsAdmin) { Write-Log 'Sin admin: no se cambia el DNS.' 'WARN'; return }
    $targets = Get-RelevantAdapters -Adapters $Adapters
    if ($targets.Count -eq 0) { Write-Log 'No hay adaptadores fisicos activos que ajustar.' 'WARN'; return }
    Backup-DnsConfig -Adapters $targets

    if ($DnsServers -and $DnsServers.Count -gt 0) {
        foreach ($a in $targets) {
            if ($script:DryRun) { Write-Log "[SIMULACION] DNS $($DnsServers -join ', ') en '$($a.Name)'" 'DRYRUN'; continue }
            try {
                Set-DnsClientServerAddress -InterfaceIndex $a.Index -ServerAddresses $DnsServers -ErrorAction Stop
                Write-Log "DNS fijados en '$($a.Name)': $($DnsServers -join ', ')" 'OK'
                $script:Stats.Removed++
            } catch { Write-Log "No se pudieron fijar DNS en '$($a.Name)': $($_.Exception.Message)" 'WARN' }
        }
    } else {
        foreach ($a in $targets) {
            if (-not $a.StaticDns) { Write-Log "'$($a.Name)': DNS por DHCP. No se toca." 'INFO'; continue }
            $probe = $TestName
            if ([string]::IsNullOrWhiteSpace($probe)) { $probe = 'www.microsoft.com' }
            $works = $false
            foreach ($ds in $a.DnsServers) {
                if ((Test-DnsResolution -Name $probe -Server $ds).Ok) { $works = $true; break }
            }
            if ($works) { Write-Log "'$($a.Name)': DNS fijos resuelven '$probe'. No se tocan." 'OK'; continue }
            Write-Log "'$($a.Name)': DNS fijos $($a.DnsServers -join ', ') no resuelven '$probe'. Se devuelve a DHCP." 'WARN'
            Add-Finding "El adaptador '$($a.Name)' tenia DNS fijos que no resuelven el servidor Mitel ($($a.DnsServers -join ', ')). Devuelto a DHCP; revertir con dns_backup.txt."
            if ($script:DryRun) { Write-Log "[SIMULACION] Set-DnsClientServerAddress -InterfaceIndex $($a.Index) -ResetServerAddresses" 'DRYRUN'; continue }
            try {
                Set-DnsClientServerAddress -InterfaceIndex $a.Index -ResetServerAddresses -ErrorAction Stop
                Write-Log "'$($a.Name)': DNS devueltos a DHCP." 'OK'
                $script:Stats.Removed++
            } catch { Write-Log "No se pudo devolver a DHCP '$($a.Name)': $($_.Exception.Message)" 'WARN' }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($DnsSuffix)) {
        $current = @()
        try {
            $sl = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -ErrorAction SilentlyContinue).SearchList
            if ($sl) { $current = @($sl -split ',' | Where-Object { $_.Trim() }) }
        } catch {}
        if ($current -contains $DnsSuffix) { Write-Log "Sufijo '$DnsSuffix' ya presente." 'OK'; return }
        $newList = @($DnsSuffix) + $current
        if ($script:DryRun) { Write-Log "[SIMULACION] Sufijos DNS: $($newList -join ', ')" 'DRYRUN'; return }
        $done = $false
        if (Get-Command Set-DnsClientGlobalSetting -ErrorAction SilentlyContinue) {
            try { Set-DnsClientGlobalSetting -SuffixSearchList $newList -ErrorAction Stop; $done = $true } catch {}
        }
        if (-not $done) {
            try {
                Set-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' `
                                 -Name 'SearchList' -Value ($newList -join ',') -ErrorAction Stop
                $done = $true
            } catch { Write-Log "No se pudo escribir SearchList: $($_.Exception.Message)" 'WARN' }
        }
        if ($done) { Write-Log "Sufijos DNS: $($newList -join ', ')" 'OK'; $script:Stats.Removed++ }
    }
}

function Repair-HostsFile {
    param([string]$Path)
    if (-not (Test-PathSafe $Path)) { return }
    $content = @()
    try { $content = @(Get-Content -LiteralPath $Path -ErrorAction Stop) } catch { Write-Log "hosts ilegible: $($_.Exception.Message)" 'WARN'; return }
    $idx = @()
    for ($i = 0; $i -lt $content.Count; $i++) {
        if ($content[$i] -match '^\s*#') { continue }
        if ($content[$i] -match 'mitel|shoretel|micollab') { $idx += $i }
    }
    if ($idx.Count -eq 0) { Write-Log 'hosts: sin entradas Mitel activas.' 'OK'; return }
    if (-not $script:IsAdmin) { Write-Log 'hosts: hay entradas Mitel pero falta admin.' 'WARN'; return }
    try {
        Copy-Item -LiteralPath $Path -Destination (Join-Path $script:BackupDir 'hosts.original') -Force -ErrorAction Stop
    } catch { Write-Log "No se pudo copiar hosts: $($_.Exception.Message)" 'WARN' }

    $changed = 0
    foreach ($i in $idx) {
        $line = $content[$i]
        $ip = ($line -split '\s+' | Where-Object { $_ } | Select-Object -First 1)
        $alive = $false
        if ($ip -match '^\d{1,3}(\.\d{1,3}){3}$') {
            try { $alive = Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue } catch {}
            if (-not $alive) {
                try {
                    $cl  = New-Object System.Net.Sockets.TcpClient
                    $iar = $cl.BeginConnect($ip, 443, $null, $null)
                    $alive = $iar.AsyncWaitHandle.WaitOne(1500, $false) -and $cl.Connected
                    try { $cl.Close() } catch {}
                } catch {}
            }
        }
        if ($alive) { Write-Log "hosts: '$($line.Trim())' responde. Se conserva." 'INFO'; continue }
        if ($script:DryRun) { Write-Log "[SIMULACION] Se comentaria: $($line.Trim())" 'DRYRUN'; continue }
        $content[$i] = "# [Repair-MitelClient] " + $line
        $changed++
        Write-Log "hosts: comentada (IP sin respuesta): $($line.Trim())" 'OK'
    }
    if ($changed -gt 0 -and -not $script:DryRun) {
        try {
            Set-Content -LiteralPath $Path -Value $content -Encoding ASCII -ErrorAction Stop
            Write-Log "hosts actualizado ($changed lineas)." 'OK'
            $script:Stats.Removed++
        } catch { Write-Log "No se pudo escribir hosts: $($_.Exception.Message)" 'ERROR' }
    }
}

function Test-ProxyConfig {
    try {
        $ie = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
        if ($ie -and $ie.ProxyEnable -eq 1) {
            Write-Log "Proxy activo: $($ie.ProxyServer) | excepciones: $($ie.ProxyOverride)" 'WARN'
            Add-Finding "Proxy activo ($($ie.ProxyServer)). El servidor Mitel interno debe figurar en las excepciones."
        }
    } catch {}
}

function Repair-FirewallRules {
    param([string]$ExePath)
    if (-not (Test-PathSafe $ExePath)) { return }
    if (-not (Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue)) { return }
    $blocking = @(); $allowing = @()
    try {
        $apps = @(Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue | Where-Object { $_.Program -and $_.Program -ieq $ExePath })
        foreach ($ap in $apps) {
            $rules = @()
            try { $rules = @($ap | Get-NetFirewallRule -ErrorAction SilentlyContinue) } catch {}
            foreach ($r in $rules) {
                if ("$($r.Enabled)" -ne 'True') { continue }
                if ("$($r.Action)" -eq 'Block') { $blocking += $r } else { $allowing += $r }
            }
        }
    } catch {}
    foreach ($b in $blocking) {
        Write-Log "Firewall: regla de BLOQUEO '$($b.DisplayName)' ($($b.Direction))" 'ERROR'
        Add-Finding "Firewall bloquea el cliente Mitel con la regla '$($b.DisplayName)'. Revisala (puede venir por GPO)."
    }
    if ($allowing.Count -gt 0) { Write-Log "Firewall: $($allowing.Count) reglas de permiso para el cliente." 'OK'; return }
    Write-Log 'Firewall: sin reglas de permiso para el cliente.' 'WARN'
    if (-not $FixFirewall) { return }
    if (-not $script:IsAdmin) { Write-Log 'Firewall: -FixFirewall requiere admin.' 'WARN'; return }
    foreach ($dir in @('Inbound','Outbound')) {
        $name = "Mitel Connect Client ($dir) - Repair-MitelClient"
        $exists = $null
        try { $exists = Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue } catch {}
        if ($exists) { continue }
        if ($script:DryRun) { Write-Log "[SIMULACION] Se crearia regla '$name'" 'DRYRUN'; continue }
        try {
            New-NetFirewallRule -DisplayName $name -Direction $dir -Action Allow -Program $ExePath `
                                -Profile Any -Enabled True -ErrorAction Stop | Out-Null
            Write-Log "Firewall: regla creada '$name'." 'OK'
            $script:Stats.Removed++
        } catch { Write-Log "Firewall: no se pudo crear '$name': $($_.Exception.Message)" 'WARN' }
    }
}

# ============================================================================
#  INICIO
# ============================================================================
try { Clear-Host } catch {}
Write-Section 'REPARACION DEL CLIENTE MITEL CONNECT / MICOLLAB'
Write-Log "Log y backups: $script:BackupDir" 'INFO'
try {
    Start-Transcript -Path (Join-Path $script:BackupDir 'transcript.txt') -Force -ErrorAction Stop | Out-Null
    $script:Transcript = $true
} catch { $script:Transcript = $false }
if ($script:DryRun) { Write-Log 'MODO SIMULACION (-DryRun): no se cambia nada.' 'DRYRUN' }

$script:IsAdmin = Test-IsAdmin
$isAdmin = $script:IsAdmin
$whoami  = $env:USERNAME

if ($AllUsers -and -not $isAdmin) { Write-Log '-AllUsers requiere admin. Solo perfil actual.' 'WARN'; $AllUsers = $false }
if (($DnsServers -and $DnsServers.Count -gt 0) -or -not [string]::IsNullOrWhiteSpace($DnsSuffix)) {
    if (-not $FixDns) { $FixDns = $true; Write-Log '-FixDns activado automaticamente.' 'INFO' }
}
if ($FixDns -and -not $isAdmin)      { Write-Log '-FixDns requiere admin. Solo diagnostico DNS.' 'WARN'; $FixDns = $false }
if ($Reinstall -and -not $isAdmin)   { Write-Log '-Reinstall requiere admin. Omitido.' 'WARN'; $Reinstall = '' }
if ($isAdmin -and -not $AllUsers) {
    Write-Log "Admin como '$whoami': se limpia SOLO ese perfil. Usa -AllUsers si el afectado es otro." 'WARN'
} elseif (-not $isAdmin) {
    Write-Log "Usuario '$whoami' sin elevacion: correcto para su perfil; los pasos de maquina se omiten." 'OK'
}

# ---------------------------------------------------------------- FASE 0 cliente
Write-Section 'FASE 0 - Diagnostico del cliente'

try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) { Write-Log "Sistema: $($os.Caption) build $($os.BuildNumber)" 'INFO' }
} catch {}
Write-Log "PowerShell: $($PSVersionTable.PSVersion)" 'INFO'

$installed = @()
foreach ($ur in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
                  'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')) {
    if (-not (Test-PathSafe $ur)) { continue }
    try {
        $installed += Get-ChildItem -LiteralPath $ur -ErrorAction SilentlyContinue |
            ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue } |
            Where-Object { $_.DisplayName -match 'Mitel|MiCollab|MiVoice|ShoreTel' }
    } catch {}
}
if ($installed.Count -gt 0) {
    foreach ($i in ($installed | Sort-Object DisplayName -Unique)) { Write-Log "Instalado: $($i.DisplayName) $($i.DisplayVersion)" 'OK' }
} else {
    Write-Log 'Sin producto Mitel/ShoreTel en el registro de desinstalacion.' 'WARN'
    Add-Finding 'No se detecta Mitel instalado. Valora -Reinstall <ruta al MitelConnect.exe>.'
}

$exeCandidates = New-Object System.Collections.ArrayList
$pfRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
foreach ($root in $pfRoots) {
    foreach ($rel in @('Mitel\Connect Client\ConnectAgent.exe','Mitel\Connect Client\MitelConnect.exe',
                       'Mitel\MiCollab\MiCollab.exe','ShoreTel\ShoreTel Communicator\ShoreTel.exe')) {
        try { [void]$exeCandidates.Add((Join-Path $root $rel)) } catch {}
    }
}
$clientExe = @($exeCandidates | Where-Object { Test-PathSafe $_ } | Select-Object -First 1)
if ($clientExe -is [array]) { $clientExe = $clientExe[0] }
if ($clientExe) { Write-Log "Ejecutable: $clientExe" 'OK' } else { Write-Log 'Ejecutable del cliente no encontrado.' 'WARN' }

$mitelSvcs = @()
try {
    $mitelSvcs = @(Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'Mitel|ShoreTel|MiCollab' -or $_.DisplayName -match 'Mitel|ShoreTel|MiCollab' })
} catch {}
foreach ($s in $mitelSvcs) { Write-Log "Servicio: $($s.Name) estado=$($s.Status)" 'INFO' }

$profiles = Get-UserProfileList
Write-Log "Perfiles: $((($profiles | Select-Object -ExpandProperty Name) -join ', '))" 'INFO'
$totalMB = 0
foreach ($pf in $profiles) {
    foreach ($rel in $script:UserRelPaths) {
        $full = Join-Path $pf.Path $rel
        if (Test-PathSafe $full) {
            $mb = Get-FolderSizeMB $full
            $totalMB += $mb
            Write-Log ("  cache: {0} ({1} MB)" -f $full, $mb) 'INFO'
        }
    }
}
Write-Log ("Cache total: {0} MB" -f [math]::Round($totalMB,1)) 'INFO'

$addinsFound = New-Object System.Collections.ArrayList
foreach ($ar in $script:AddinRegRoots) {
    $prov = ConvertTo-ProviderPath $ar
    if (-not (Test-PathSafe $prov)) { continue }
    $items = @()
    try { $items = @(Get-ChildItem -LiteralPath $prov -ErrorAction SilentlyContinue) } catch {}
    foreach ($it in $items) {
        $props = $null
        try { $props = Get-ItemProperty -LiteralPath $it.PSPath -ErrorAction SilentlyContinue } catch {}
        $fname = ''
        if ($props) { $fname = [string]$props.FriendlyName }
        $isMitel = $false
        foreach ($pat in $script:MitelAddinPatterns) {
            if ($it.PSChildName -like $pat -or $fname -like $pat) { $isMitel = $true; break }
        }
        if (-not $isMitel) { continue }
        $lb = 'n/d'
        if ($props -and $null -ne $props.LoadBehavior) { $lb = $props.LoadBehavior }
        Write-Log "Complemento Outlook: $($it.PSChildName) | $fname | LoadBehavior=$lb" 'INFO'
        [void]$addinsFound.Add([pscustomobject]@{ KeyPath = ($ar + '\' + $it.PSChildName); Name = $it.PSChildName; Load = $lb })
        if ($lb -eq 2 -or $lb -eq 0) { Add-Finding "Complemento Outlook '$($it.PSChildName)' desactivado (LoadBehavior=$lb)." }
    }
}

$credLines = @()
try {
    $credLines = @((Invoke-Native -File 'cmdkey.exe' -Arguments @('/list')) -split "`r?`n" |
                   Where-Object { $_ -match 'Destino|Target' } | Where-Object { $_ -match 'Mitel|ShoreTel|MiCollab' })
} catch {}
foreach ($cl in $credLines) { Write-Log "Credencial: $($cl.Trim())" 'INFO' }

$hostsFile = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
if (Test-PathSafe $hostsFile) {
    try {
        $badHosts = @(Get-Content -LiteralPath $hostsFile -ErrorAction SilentlyContinue |
                      Where-Object { $_ -notmatch '^\s*#' -and $_ -match 'mitel|shoretel|micollab' })
        foreach ($bh in $badHosts) { Write-Log "hosts: $($bh.Trim())" 'WARN' }
        if ($badHosts.Count -gt 0) { Add-Finding "El hosts tiene entradas Mitel. Revisalas o usa -FixHosts." }
    } catch {}
}

# ------------------------------------------------------------------- FASE 0b red
Write-Section 'FASE 0b - Diagnostico de red y DNS'

$script:Adapters = @(Get-ActiveAdapterInfo)
$relevant = Get-RelevantAdapters -Adapters $script:Adapters
if ($relevant.Count -eq 0) {
    Write-Log 'Ningun adaptador fisico con puerta de enlace. Sin red util.' 'ERROR'
    Add-Finding 'El equipo no tiene un adaptador fisico con gateway: primero hay que arreglar la conectividad.'
}
foreach ($a in $relevant) {
    $origen = 'DHCP'
    if ($a.StaticDns) { $origen = 'FIJO' }
    Write-Log ("{0} (idx {1}) IP={2} GW={3}" -f $a.Name, $a.Index, $a.IPv4, $a.Gateway) 'INFO'
    Write-Log ("  DNS [{0}]: {1}" -f $origen, ($a.DnsServers -join ', ')) 'INFO'
    if ($a.ConnSuffix) { Write-Log "  sufijo: $($a.ConnSuffix)" 'INFO' }
    if ($a.DnsServers.Count -eq 0) {
        Write-Log "  sin servidores DNS" 'ERROR'
        Add-Finding "El adaptador '$($a.Name)' no tiene servidores DNS. Usa -FixDns o -DnsServers."
    }
}
try {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    if ($cs) {
        if ($cs.PartOfDomain) { Write-Log "Dominio: $($cs.Domain)" 'OK' } else { Write-Log 'Equipo en grupo de trabajo.' 'INFO' }
    }
} catch {}
try {
    $vpn = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.Status -eq 'Up' -and ($_.InterfaceDescription -match 'VPN|Fortinet|AnyConnect|GlobalProtect|Zscaler|WireGuard|Pulse|SonicWall|OpenVPN' -or $_.Name -match 'VPN')
    })
    if ($vpn.Count -gt 0) { Write-Log "VPN activa: $((($vpn | Select-Object -ExpandProperty Name) -join ', '))" 'OK' }
    else { Write-Log 'Sin VPN activa.' 'INFO' }
} catch {}
Test-ProxyConfig

Write-Log 'Buscando servidor Mitel (credenciales, configuracion, SRV, nombres habituales)...' 'STEP'
$script:ServerCands = @(Find-MitelServer -Explicit @($ServerHost))
if ($script:ServerCands.Count -eq 0) {
    Write-Log 'Sin candidatos a servidor Mitel.' 'WARN'
    Add-Finding 'No se descubrio el servidor Mitel. Indicalo con -ServerHost <nombre_o_ip>.'
} else {
    foreach ($c in $script:ServerCands) {
        if ($c.OpenPorts.Count -gt 0) { Write-Log ("ALCANZABLE {0} [{1}] IP={2} puertos: {3}" -f $c.Host, $c.Source, ($c.Ips -join ','), ($c.OpenPorts -join ',')) 'OK' }
        elseif ($c.Dns)               { Write-Log ("resuelve pero no responde: {0} [{1}] IP={2}" -f $c.Host, $c.Source, ($c.Ips -join ',')) 'WARN' }
        else                          { Write-Log ("no resuelve: {0} [{1}]" -f $c.Host, $c.Source) 'ERROR' }
    }
    $best = $script:ServerCands | Select-Object -First 1
    $script:TestName = $best.Host
    if ($best.OpenPorts.Count -eq 0) {
        if ($best.Dns) { Add-Finding "'$($best.Host)' resuelve a $($best.Ips -join ',') pero no acepta conexiones: firewall, VPN o servicio caido." }
        else           { Add-Finding "Ningun candidato resuelve por DNS: el problema es de DNS, no del cliente. Usa -FixDns (y -DnsSuffix <dominio> si el cliente usa nombre corto)." }
    }
}
foreach ($a in $relevant) {
    foreach ($ds in $a.DnsServers) {
        $probe = $script:TestName
        if ([string]::IsNullOrWhiteSpace($probe)) { $probe = 'www.microsoft.com' }
        if ((Test-DnsResolution -Name $probe -Server $ds).Ok) { Write-Log "DNS $ds resuelve '$probe'." 'OK' }
        else {
            Write-Log "DNS $ds NO resuelve '$probe'." 'ERROR'
            Add-Finding "El servidor DNS $ds no resuelve '$probe'. Es la causa del 'no conecta': usa -FixDns."
        }
    }
}
if ($script:TestName) { Test-MitelConnectivity -HostName $script:TestName }

# ------------------------------------------------------------------ confirmacion
if (-not $script:DryRun -and -not $Force) {
    Write-Section 'CONFIRMACION'
    Write-Log 'Se cerrara el cliente Mitel y se borrara su cache, registro de usuario y credenciales.' 'WARN'
    Write-Log 'Habra que volver a iniciar sesion en el cliente. No se reinicia el equipo ni se toca la pila de red.' 'WARN'
    if ($addinsFound.Count -gt 0 -and -not $KeepOutlookAddin) {
        if ($DisableOutlookAddin) { Write-Log "El complemento Mitel de Outlook quedara desactivado ($($addinsFound.Count) entradas)." 'WARN' }
        else { Write-Log "Se retirara el complemento Mitel de Outlook ($($addinsFound.Count) entradas, restaurable desde el .reg)." 'WARN' }
    }
    if ($FixDns) { Write-Log "Ademas se ajustara el DNS de: $((($relevant | Select-Object -ExpandProperty Name) -join ', ')) (copia en dns_backup.txt)." 'WARN' }
    $resp = ''
    try { $resp = Read-Host 'Escribe SI para continuar' } catch { $resp = '' }
    if ($resp -notmatch '^(s|si|y|yes)$') {
        Write-Log 'Cancelado. Nada modificado.' 'INFO'
        try { if ($script:Transcript) { Stop-Transcript | Out-Null } } catch {}
        return
    }
}

# ------------------------------------------------------------------ FASE 1 cerrar
Write-Section 'FASE 1 - Cerrar cliente y servicios'
Stop-ProcessSafe -Names $script:MitelProcNames
try {
    $extra = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $p = $null
        try { $p = $_.Path } catch {}
        $p -and ($p -match '\\Mitel\\|\\ShoreTel\\')
    })
    foreach ($e in $extra) {
        if ($script:DryRun) { Write-Log "[SIMULACION] Se cerraria: $($e.Name) (PID $($e.Id))" 'DRYRUN'; continue }
        try { Stop-Process -Id $e.Id -Force -ErrorAction Stop; Write-Log "Proceso cerrado: $($e.Name)" 'OK' }
        catch { Write-Log "No se pudo cerrar $($e.Name): $($_.Exception.Message)" 'WARN' }
    }
} catch {}
foreach ($s in $mitelSvcs) {
    if ($s.Status -ne 'Running') { continue }
    if (-not $isAdmin) { Write-Log "Sin admin para detener $($s.Name)." 'WARN'; continue }
    if ($script:DryRun) { Write-Log "[SIMULACION] Se detendria: $($s.Name)" 'DRYRUN'; continue }
    try {
        Stop-Service -Name $s.Name -Force -ErrorAction Stop
        [void]$script:StoppedSvcs.Add($s.Name)
        Write-Log "Servicio detenido: $($s.Name)" 'OK'
    } catch { Write-Log "No se pudo detener $($s.Name): $($_.Exception.Message)" 'WARN' }
}
if (-not $script:DryRun) { Start-Sleep -Seconds 2 }

# ------------------------------------------------------------------- FASE 2 cache
Write-Section 'FASE 2 - Cache y perfil del cliente'
foreach ($pf in $profiles) {
    foreach ($rel in $script:UserRelPaths) {
        Remove-ItemSafe -Path (Join-Path $pf.Path $rel) -Label "$($pf.Name): $rel"
    }
}

Write-Section 'FASE 3 - ProgramData'
if ($isAdmin) { foreach ($mp in $script:MachinePaths) { Remove-ItemSafe -Path $mp -Label $mp } }
else { Write-Log 'Sin admin: ProgramData omitido.' 'WARN' }

Write-Section 'FASE 4 - Registro de usuario'
foreach ($pf in $profiles) { Clear-UserRegistryHive -UserProfile $pf }

# ----------------------------------------------------------------- FASE 5 Outlook
Write-Section 'FASE 5 - Outlook: complemento y resiliencia'
if ($addinsFound.Count -eq 0) {
    Write-Log 'Sin complemento Mitel en Outlook.' 'INFO'
} elseif ($KeepOutlookAddin) {
    foreach ($ai in $addinsFound) {
        if ($ai.Load -ne 2 -and $ai.Load -ne 0) { Write-Log "Complemento conservado: $($ai.Name)" 'INFO'; continue }
        $prov = ConvertTo-ProviderPath $ai.KeyPath
        if ($script:DryRun) { Write-Log "[SIMULACION] LoadBehavior=3 en $($ai.Name)" 'DRYRUN'; continue }
        try {
            Set-ItemProperty -LiteralPath $prov -Name 'LoadBehavior' -Value 3 -Type DWord -ErrorAction Stop
            Write-Log "Complemento reactivado: $($ai.Name)" 'OK'
        } catch { Write-Log "No se pudo reactivar $($ai.Name): $($_.Exception.Message)" 'WARN' }
    }
} elseif ($DisableOutlookAddin) {
    foreach ($ai in $addinsFound) {
        $prov = ConvertTo-ProviderPath $ai.KeyPath
        if ($script:DryRun) { Write-Log "[SIMULACION] LoadBehavior=0 en $($ai.Name)" 'DRYRUN'; continue }
        Backup-RegistryKey -KeyPath $ai.KeyPath | Out-Null
        try {
            Set-ItemProperty -LiteralPath $prov -Name 'LoadBehavior' -Value 0 -Type DWord -ErrorAction Stop
            Write-Log "Complemento desactivado (LoadBehavior=0): $($ai.Name)" 'OK'
            $script:Stats.Removed++
        } catch { Write-Log "No se pudo desactivar $($ai.Name): $($_.Exception.Message)" 'WARN' }
    }
} else {
    foreach ($ai in $addinsFound) {
        Remove-RegistryKeySafe -KeyPath $ai.KeyPath -Label "Complemento Outlook: $($ai.Name)"
    }
    Write-Log 'Complemento Mitel retirado de Outlook. Restaurable desde el .reg de la carpeta de log.' 'INFO'
}
foreach ($ov in @('16.0','15.0','14.0')) {
    foreach ($rk in @('DisabledItems','CrashingAddinList')) {
        $kp = "HKCU\Software\Microsoft\Office\$ov\Outlook\Resiliency\$rk"
        if (Test-PathSafe (ConvertTo-ProviderPath $kp)) { Remove-RegistryKeySafe -KeyPath $kp -Label "Outlook $ov $rk" }
    }
}

# ------------------------------------------------------------- FASE 6 credenciales
Write-Section 'FASE 6 - Credenciales'
if ($KeepCredentials) {
    Write-Log 'Credenciales conservadas (-KeepCredentials).' 'INFO'
} else {
    foreach ($cl in $credLines) {
        $target = ($cl -replace '^.*?(Destino|Target)\s*:\s*', '').Trim()
        if ([string]::IsNullOrWhiteSpace($target)) { continue }
        if ($script:DryRun) { Write-Log "[SIMULACION] Se eliminaria credencial: $target" 'DRYRUN'; continue }
        $out = Invoke-Native -File 'cmdkey.exe' -Arguments @("/delete:$target")
        if ($LASTEXITCODE -eq 0) { Write-Log "Credencial eliminada: $target" 'OK'; $script:Stats.Removed++ }
        else { Write-Log "No se pudo eliminar '$target': $($out.Trim())" 'WARN' }
    }
}

# ---------------------------------------------------------------------- FASE 7 red
Write-Section 'FASE 7 - Red: DNS, hosts, firewall, caches'
if ($FixDns) { Repair-DnsConfiguration -Adapters $script:Adapters -TestName $script:TestName }
else { Write-Log 'DNS sin cambios (usa -FixDns).' 'INFO' }

if ($FixHosts) { Repair-HostsFile -Path $hostsFile } else { Write-Log 'hosts sin cambios (usa -FixHosts).' 'INFO' }

Repair-FirewallRules -ExePath $clientExe

if (Get-Command Clear-DnsClientCache -ErrorAction SilentlyContinue) {
    if ($script:DryRun) { Write-Log '[SIMULACION] Clear-DnsClientCache' 'DRYRUN' }
    else {
        try { Clear-DnsClientCache -ErrorAction Stop; Write-Log 'Cache DNS vaciada.' 'OK' }
        catch { Write-Log "Clear-DnsClientCache: $($_.Exception.Message)" 'WARN' }
    }
}
Invoke-NativeStep -File 'ipconfig.exe' -Arguments @('/flushdns')    -Label 'ipconfig /flushdns'
Invoke-NativeStep -File 'ipconfig.exe' -Arguments @('/registerdns') -Label 'ipconfig /registerdns'
if ($isAdmin) {
    Invoke-NativeStep -File 'arp.exe'     -Arguments @('-d','*') -Label 'arp -d *'
    Invoke-NativeStep -File 'nbtstat.exe' -Arguments @('-R')     -Label 'nbtstat -R'
} else {
    Write-Log 'Sin admin: arp/nbtstat omitidos.' 'WARN'
}

# -------------------------------------------------------------- FASE 8 reinstalar
if (-not [string]::IsNullOrWhiteSpace($Reinstall)) {
    Write-Section 'FASE 8 - Reinstalacion'
    if (-not (Test-PathSafe $Reinstall)) { Write-Log "Instalador no encontrado: $Reinstall" 'ERROR' }
    elseif ($script:DryRun) { Write-Log "[SIMULACION] $Reinstall /s /v`"/qn REBOOT=ReallySuppress`"" 'DRYRUN' }
    else {
        try {
            $proc = Start-Process -FilePath $Reinstall -ArgumentList '/s','/v"/qn REBOOT=ReallySuppress"' -Wait -PassThru -ErrorAction Stop
            if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                Write-Log "Instalacion terminada (codigo $($proc.ExitCode))." 'OK'
                if ($proc.ExitCode -eq 3010) { Add-Finding 'El instalador pide reinicio (3010). El script no reinicia: hazlo cuando puedas.' }
            } else { Write-Log "Instalador codigo $($proc.ExitCode)." 'WARN' }
        } catch { Write-Log "Fallo la instalacion: $($_.Exception.Message)" 'ERROR' }
    }
}

# -------------------------------------------------------------- FASE 9 verificar
Write-Section 'FASE 9 - Verificacion'
foreach ($svcName in $script:StoppedSvcs) {
    if ($script:DryRun) { continue }
    try { Start-Service -Name $svcName -ErrorAction Stop; Write-Log "Servicio reiniciado: $svcName" 'OK' }
    catch { Write-Log "No se pudo reiniciar $svcName : $($_.Exception.Message)" 'WARN' }
}
$dnsProblema = $false
if ($script:TestName) {
    Test-MitelConnectivity -HostName $script:TestName
    if (-not (Test-DnsResolution -Name $script:TestName).Ok) {
        $dnsProblema = $true
        Add-Finding "'$($script:TestName)' sigue sin resolver. Pide al equipo de red el DNS y el dominio correctos y aplica: -DnsServers <ip1>,<ip2> -DnsSuffix <dominio>"
    }
} elseif ($script:ServerCands -and @($script:ServerCands | Where-Object { $_.Dns }).Count -eq 0) {
    $dnsProblema = $true
}
if (-not $script:DryRun) {
    $leftovers = New-Object System.Collections.ArrayList
    foreach ($pf in $profiles) {
        foreach ($rel in $script:UserRelPaths) {
            $full = Join-Path $pf.Path $rel
            if (Test-PathSafe $full) { [void]$leftovers.Add($full) }
        }
    }
    if ($leftovers.Count -eq 0) { Write-Log 'Cache eliminada por completo.' 'OK' }
    else {
        foreach ($l in $leftovers) { Write-Log "Queda (en uso): $l" 'WARN' }
        Add-Finding 'Quedan carpetas en uso: cierra la sesion del usuario y repite.'
    }
}

# ------------------------------------------------------------------------ resumen
Write-Section 'RESUMEN'
Write-Log ("Eliminados/ajustados: {0}" -f $script:Stats.Removed)  'INFO'
Write-Log ("Omitidos            : {0}" -f $script:Stats.Skipped)  'INFO'
Write-Log ("Avisos              : {0}" -f $script:Stats.Warnings) 'INFO'
Write-Log ("Errores             : {0}" -f $script:Stats.Errors)   'INFO'
Write-Log "Log y backups: $script:BackupDir" 'INFO'

if ($script:Findings.Count -gt 0) {
    Write-Log '' 'INFO'
    Write-Log 'PUNTOS DE ATENCION:' 'STEP'
    $i = 1
    foreach ($f in $script:Findings) { Write-Log ("  {0}. {1}" -f $i, $f) 'WARN'; $i++ }
}

Write-Log '' 'INFO'
Write-Log 'SIGUIENTES PASOS:' 'STEP'
$n = 1
if ($script:DryRun) {
    Write-Log ("  {0}. Simulacion: nada cambiado. Repite sin -DryRun." -f $n) 'DRYRUN'; $n++
} else {
    Write-Log ("  {0}. Abre el cliente Mitel e inicia sesion (pedira credenciales)." -f $n) 'INFO'; $n++
    if ($addinsFound.Count -gt 0) { Write-Log ("  {0}. Cierra y abre Outlook por completo." -f $n) 'INFO'; $n++ }
}
if (-not $isAdmin -and ($dnsProblema -or $FixDns -or $FixHosts -or $FixFirewall)) {
    Write-Log ("  {0}. Falta la pasada de MAQUINA (admin):" -f $n) 'WARN'; $n++
    Write-Log '     powershell -NoProfile -ExecutionPolicy Bypass -File ".\06-repair-mitel-client.ps1" -AllUsers -FixDns -FixHosts -FixFirewall -Force' 'WARN'
}
if ($dnsProblema -and -not $FixDns) {
    Write-Log ("  {0}. El diagnostico apunta al DNS. Como administrador:" -f $n) 'WARN'; $n++
    Write-Log '     .\06-repair-mitel-client.ps1 -FixDns -FixHosts -FixFirewall -Force' 'WARN'
    Write-Log '     .\06-repair-mitel-client.ps1 -DnsServers <ip1>,<ip2> -DnsSuffix <dominio> -Force' 'WARN'
}
Write-Log ("  {0}. Revertir DNS: comandos exactos en $script:BackupDir\dns_backup.txt" -f $n) 'INFO'

try { if ($script:Transcript) { Stop-Transcript | Out-Null } } catch {}
