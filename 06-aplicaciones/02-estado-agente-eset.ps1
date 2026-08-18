<#
.SYNOPSIS
    [ES] Comprueba si el agente de ESET esta instalado, corriendo y enrolado en ESET PROTECT.
    [EN] Checks whether the ESET agent is installed, running and enrolled in ESET PROTECT.
.DESCRIPTION
    Intune solo sabe si una app esta PRESENTE, porque eso es lo unico que puede comprobar su
    regla de deteccion. La del ESET Management Agent hace un OR de tres cosas -clave del
    registro, ERAAgent.exe y el servicio EraAgentSvc-, asi que devuelve "instalada" aunque
    el servicio este parado y aunque el agente nunca haya conseguido hablar con la consola.

    Y esa diferencia importa: si el agente queda UNENROLLED no aparece en ESET PROTECT y,
    como el antivirus (ESET Endpoint) se reparte DESDE la consola y no desde Intune, el
    equipo se queda sin antivirus de ESET para siempre sin que Intune informe de nada.

    Este script separa las cuatro preguntas:
      1. Esta el binario y que version?
      2. Esta el servicio y en que estado?
      3. Hay conectividad TCP con el servidor ECA de ESET PROTECT Cloud?
      4. Que dice el propio agente en su log/estado sobre el enrolamiento?

    No modifica nada. Funciona con cuenta de usuario estandar para casi todo; los apartados
    marcados como (admin) necesitan elevacion y se omiten con aviso si no la hay.

    Compatible con Windows PowerShell 5.1 y PowerShell 7.

.PARAMETER Servidor
    Nombre del servidor ECA de ESET PROTECT Cloud (P_HOSTNAME del install_config.ini).

.PARAMETER Puerto
    Puerto del servidor ECA. 443 en ESET PROTECT Cloud.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Get-EsetAgentStatus.ps1

.EXAMPLE
    .\Get-EsetAgentStatus.ps1 -Servidor otro.ecaserver.eset.com | Tee-Object eset.txt

.NOTES
    Este script NO se conecta a Graph ni usa lib\AndersenLab.psm1: corre en el endpoint,
    donde no hay certificado del lab ni modulos del laboratorio.
#>
[CmdletBinding()]
param(
    [string]$Servidor = 'kb4t5os6uqdehdokdn2p3ftmvq.a.ecaserver.eset.com',
    [int]$Puerto = 443
)

$ErrorActionPreference = 'SilentlyContinue'

function Write-Titulo { param([string]$t) Write-Host "`n=== $t" -ForegroundColor Cyan }
function Write-Ok     { param([string]$m) Write-Host "  [OK]   $m" -ForegroundColor Green }
function Write-No     { param([string]$m) Write-Host "  [NO]   $m" -ForegroundColor Red }
function Write-Aviso  { param([string]$m) Write-Host "  [!!]   $m" -ForegroundColor Yellow }
function Write-Dato   { param([string]$m) Write-Host "         $m" -ForegroundColor Gray }

$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host ''
Write-Host '=======================================================' -ForegroundColor White
Write-Host " ESET Management Agent - estado real en $env:COMPUTERNAME" -ForegroundColor White
Write-Host " $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')   usuario: $env:USERNAME   admin: $esAdmin"  -ForegroundColor DarkGray
Write-Host '=======================================================' -ForegroundColor White

$veredicto = [ordered]@{
    Binario      = $false
    Servicio     = $false
    Conectividad = $false
    Enrolado     = $null
}

# ------------------------------------------------------------------
# 1. Binario
# ------------------------------------------------------------------
Write-Titulo '1. Binario del agente'
$rutas = @(
    (Join-Path $env:ProgramFiles        'ESET\RemoteAdministrator\Agent\ERAAgent.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'ESET\RemoteAdministrator\Agent\ERAAgent.exe')
)
$exe = $rutas | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if ($exe) {
    $veredicto.Binario = $true
    $v = (Get-Item -LiteralPath $exe).VersionInfo
    Write-Ok "ERAAgent.exe presente"
    Write-Dato "ruta    : $exe"
    Write-Dato "version : $($v.FileVersion)"
} else {
    Write-No 'ERAAgent.exe NO existe en ninguna de las rutas conocidas'
    foreach ($r in $rutas) { Write-Dato "buscado : $r" }
}

# ------------------------------------------------------------------
# 2. Registro de desinstalacion
# ------------------------------------------------------------------
Write-Titulo '2. Entradas de desinstalacion (lo que ve la deteccion de Intune)'
$claves = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$eset = Get-ItemProperty $claves | Where-Object { $_.DisplayName -like '*ESET*' }
if ($eset) {
    foreach ($e in $eset) { Write-Ok "$($e.DisplayName)  $($e.DisplayVersion)" }
} else {
    Write-No 'ninguna entrada de ESET en el registro'
}

# ------------------------------------------------------------------
# 3. Servicio
# ------------------------------------------------------------------
Write-Titulo '3. Servicio EraAgentSvc'
$svc = Get-Service -Name 'EraAgentSvc' -ErrorAction SilentlyContinue
if ($svc) {
    $inicio = (Get-CimInstance Win32_Service -Filter "Name='EraAgentSvc'").StartMode
    if ($svc.Status -eq 'Running') {
        $veredicto.Servicio = $true
        Write-Ok "EraAgentSvc: $($svc.Status)  (inicio: $inicio)"
    } else {
        Write-No "EraAgentSvc existe pero esta $($svc.Status)  (inicio: $inicio)"
        Write-Aviso 'La deteccion de Intune da esto por INSTALADO igualmente.'
    }
} else {
    Write-No 'EraAgentSvc no existe'
}

# ------------------------------------------------------------------
# 4. Conectividad con ESET PROTECT Cloud
# ------------------------------------------------------------------
Write-Titulo "4. Conectividad con ${Servidor}:${Puerto}"
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $async = $tcp.BeginConnect($Servidor, $Puerto, $null, $null)
    if ($async.AsyncWaitHandle.WaitOne(5000, $false) -and $tcp.Connected) {
        $veredicto.Conectividad = $true
        Write-Ok "conexion TCP establecida"
    } else {
        Write-No 'sin respuesta en 5 s (firewall, proxy o DNS)'
    }
    $tcp.Close()
} catch {
    Write-No "fallo de conexion: $($_.Exception.Message)"
}
$dns = Resolve-DnsName -Name $Servidor -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress }
if ($dns) { Write-Dato ("DNS     : {0}" -f (($dns.IPAddress) -join ', ')) }
else      { Write-Aviso 'el nombre no resuelve por DNS' }

# ------------------------------------------------------------------
# 5. Enrolamiento (lo que Intune NO puede saber)
# ------------------------------------------------------------------
Write-Titulo '5. Enrolamiento en ESET PROTECT Cloud'
$datos = Join-Path $env:ProgramData 'ESET\RemoteAdministrator\Agent\EraAgentApplicationData'
$logs  = Join-Path $datos 'Logs'
$status = Join-Path $logs 'status.html'
$trace  = Join-Path $logs 'trace.log'

if (-not (Test-Path -LiteralPath $datos)) {
    Write-No "no existe $datos : el agente no ha llegado a arrancar nunca"
} else {
    Write-Ok "carpeta de datos: $datos"

    if (Test-Path -LiteralPath $status) {
        $t = (Get-Item -LiteralPath $status).LastWriteTime
        Write-Dato "status.html actualizado: $($t.ToString('yyyy-MM-dd HH:mm:ss'))"
        if ($t -lt (Get-Date).AddHours(-2)) { Write-Aviso 'lleva mas de 2 h sin actualizarse: el agente no esta replicando' }
    }

    if (Test-Path -LiteralPath $trace) {
        $lineas = Get-Content -LiteralPath $trace -Tail 400 -ErrorAction SilentlyContinue
        if (-not $lineas) {
            Write-Aviso 'trace.log ilegible con esta cuenta (necesita admin)'
        } else {
            $ok    = @($lineas | Where-Object { $_ -match 'Replication.*(finished|succeeded)|Connected to server|Successfully connected' })
            $error = @($lineas | Where-Object { $_ -match 'unenrolled|Peer certificate|not authorized|Connection.*failed|CReplicationModule.*Error' })

            if ($ok.Count -gt 0) {
                $veredicto.Enrolado = $true
                Write-Ok "el agente replica con la consola ($($ok.Count) marcas recientes)"
                Write-Dato ($ok[-1].Trim())
            }
            if ($error.Count -gt 0) {
                if (-not $veredicto.Enrolado) { $veredicto.Enrolado = $false }
                Write-No "errores de conexion/enrolamiento en trace.log ($($error.Count))"
                foreach ($l in ($error | Select-Object -Last 3)) { Write-Dato $l.Trim() }
            }
            if ($ok.Count -eq 0 -and $error.Count -eq 0) {
                Write-Aviso 'trace.log no dice nada concluyente en las ultimas 400 lineas'
            }
        }
    } else {
        Write-Aviso "no hay trace.log en $logs"
    }
}

# ------------------------------------------------------------------
# 6. Log de la instalacion por Intune
# ------------------------------------------------------------------
Write-Titulo '6. Log de la instalacion (wrapper de Intune)'
foreach ($l in @('C:\Windows\Temp\ND_EsetAgent_wrapper.log', 'C:\Windows\Temp\ND_EsetAgent.log')) {
    if (Test-Path -LiteralPath $l) {
        $i = Get-Item -LiteralPath $l
        Write-Ok ("{0}  {1:n0} KB  {2}" -f $i.Name, ($i.Length / 1KB), $i.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
        if ($i.Name -like '*wrapper*') {
            foreach ($linea in (Get-Content -LiteralPath $l -Tail 12 -ErrorAction SilentlyContinue)) { Write-Dato $linea }
        } else {
            $res = Get-Content -LiteralPath $l -ErrorAction SilentlyContinue |
                   Where-Object { $_ -match 'Installation success or error status|MainEngineThread is returning' } |
                   Select-Object -Last 2
            foreach ($linea in $res) { Write-Dato $linea.Trim() }
        }
    } else {
        Write-Aviso "no existe $l"
    }
}

# ------------------------------------------------------------------
# Veredicto
# ------------------------------------------------------------------
Write-Titulo 'VEREDICTO'
foreach ($k in $veredicto.Keys) {
    $v = $veredicto[$k]
    $txt = if ($null -eq $v) { 'no concluyente' } elseif ($v) { 'si' } else { 'NO' }
    $col = if ($null -eq $v) { 'Yellow' } elseif ($v) { 'Green' } else { 'Red' }
    Write-Host ("  {0,-14} {1}" -f $k, $txt) -ForegroundColor $col
}

Write-Host ''
if (-not $veredicto.Binario) {
    Write-Host '  => El agente NO esta instalado. Intune deberia estar informando de un fallo:' -ForegroundColor Red
    Write-Host '     revisar ND_EsetAgent.log y el codigo de salida del msiexec.' -ForegroundColor Red
} elseif (-not $veredicto.Servicio) {
    Write-Host '  => Instalado pero el servicio no corre. Intune lo da por instalado igualmente.' -ForegroundColor Red
} elseif ($veredicto.Enrolado -eq $false -or -not $veredicto.Conectividad) {
    Write-Host '  => Instalado y corriendo, pero SIN ENROLAR en ESET PROTECT Cloud.' -ForegroundColor Red
    Write-Host '     El equipo no aparecera en la consola y NUNCA recibira el antivirus ESET,' -ForegroundColor Red
    Write-Host '     porque ESET Endpoint se reparte desde la consola, no desde Intune.' -ForegroundColor Red
} elseif ($veredicto.Enrolado) {
    Write-Host '  => Instalado, corriendo y enrolado. Confirmar que el equipo aparece en ESET PROTECT.' -ForegroundColor Green
} else {
    Write-Host '  => Instalado y corriendo. El enrolamiento no se puede confirmar desde aqui:' -ForegroundColor Yellow
    Write-Host "     buscar $env:COMPUTERNAME en la consola de ESET PROTECT Cloud." -ForegroundColor Yellow
}
Write-Host ''
