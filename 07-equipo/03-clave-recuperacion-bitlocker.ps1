<#
.SYNOPSIS
    [ES] Saca la clave de recuperacion de BitLocker por numero de serie, nombre o id de dispositivo.
    [EN] Retrieves the BitLocker recovery key by serial number, device name or Entra device id.
.DESCRIPTION
    Es la consulta urgente tipica: el equipo pide la clave de recuperacion en una pantalla
    azul y hay alguien esperando delante. Buscarla a mano son tres saltos entre consolas
    (Intune -> numero de serie -> objeto de Entra -> pestana de claves), y el buscador de
    dispositivos de Intune NO encuentra por numero de serie, solo por nombre: por eso este
    script acepta las dos cosas.

    Resolucion, en este orden:
      1. -Serie  -> identidad de Autopilot  -> azureActiveDirectoryDeviceId
                    (si no esta en Autopilot, se prueba con managedDevices)
      2. -Nombre -> managedDevices          -> azureADDeviceId
      3. -DeviceId -> directo

    Despues: informationProtection/bitlocker/recoveryKeys filtrando por deviceId, y una
    segunda llamada por cada clave para leer el campo 'key', que NUNCA viene en el listado.

    AVISO IMPORTANTE: la clave cuelga del objeto de dispositivo de Entra. Si ese objeto se
    borra -y en un flujo de restablecimiento es facil que acabe borrandose-, la clave
    desaparece con el y el disco queda irrecuperable. Sacarla y guardarla ANTES de borrar
    nada.

    No escribe nada, pero SI muestra un secreto por pantalla: no dejar la salida en un log
    ni en un ticket. Por eso no exporta a fichero salvo que se pida con -RutaCsv.

.PARAMETER Serie
    Numero de serie del equipo (lo que se ve en la pegatina y en Autopilot).

.PARAMETER Nombre
    Nombre del equipo en Intune / Entra.

.PARAMETER DeviceId
    deviceId de Entra, si ya se conoce.

.PARAMETER RutaCsv
    Si se indica, ademas vuelca el resultado a ese CSV. Pensarlo dos veces: es un secreto.

.EXAMPLE
    .\Get-BitlockerRecoveryKey.ps1 -Serie PW0NFE5Y

.EXAMPLE
    .\Get-BitlockerRecoveryKey.ps1 -Nombre TESTEOINTUNE

.NOTES
    Solicitante: soporte.ti@ejemplo.com
    Permiso requerido: BitlockerKey.Read.All (concedido) + DeviceManagementServiceConfig.Read.All
    y DeviceManagementManagedDevices.Read.All para resolver la serie y el nombre.
    Endpoint: informationProtection/bitlocker/recoveryKeys
#>
[CmdletBinding(DefaultParameterSetName = 'Serie')]
param(
    [Parameter(ParameterSetName = 'Serie', Mandatory, Position = 0)][string[]]$Serie,
    [Parameter(ParameterSetName = 'Nombre', Mandatory)][string[]]$Nombre,
    [Parameter(ParameterSetName = 'DeviceId', Mandatory)][string[]]$DeviceId,
    [string]$RutaCsv,
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\..\config\exo-app-params.json')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..\..\lib\AndersenLab.psm1') -Force
Connect-LabGraph -ConfigPath $ConfigPath | Out-Null

function Write-Ok   { param([string]$m) Write-Host "  [OK]   $m" -ForegroundColor Green }
function Write-Info { param([string]$m) Write-Host "  [ .. ] $m" -ForegroundColor Gray }
function Write-Err  { param([string]$m) Write-Host "  [FAIL] $m" -ForegroundColor Red }
function Get-Prop {
    param($Obj, [string]$Name, $Default = $null)
    if ($Obj -and $Obj.PSObject.Properties.Name -contains $Name) { return $Obj.$Name }
    return $Default
}

# ------------------------------------------------------------------
# Resolver los equipos a deviceId de Entra
# ------------------------------------------------------------------
$objetivos = [System.Collections.Generic.List[object]]::new()

if ($PSCmdlet.ParameterSetName -eq 'DeviceId') {
    foreach ($d in $DeviceId) { $objetivos.Add([pscustomobject]@{ Etiqueta = $d; DeviceId = $d }) }
}
else {
    # Los managedDevices se traen una vez: filtrar en local es mas barato que N consultas,
    # y ademas $filter sobre serialNumber no es fiable en el endpoint de Autopilot.
    $md = @(Invoke-LabGraph 'deviceManagement/managedDevices?$select=id,deviceName,serialNumber,azureADDeviceId' -All)

    if ($PSCmdlet.ParameterSetName -eq 'Serie') {
        $ap = @(Invoke-LabGraph 'deviceManagement/windowsAutopilotDeviceIdentities' -All)
        foreach ($s in $Serie) {
            $id = $null
            $cand = @($ap | Where-Object { (Get-Prop $_ 'serialNumber') -eq $s })
            foreach ($c in $cand) {
                $aad = Get-Prop $c 'azureActiveDirectoryDeviceId'
                if ($aad -and $aad -ne '00000000-0000-0000-0000-000000000000') { $id = $aad; break }
            }
            if (-not $id) {
                $m = @($md | Where-Object { (Get-Prop $_ 'serialNumber') -eq $s })
                if ($m.Count -ge 1) { $id = Get-Prop $m[0] 'azureADDeviceId' }
            }
            if ($id) { $objetivos.Add([pscustomobject]@{ Etiqueta = "serie $s"; DeviceId = $id }) }
            else     { Write-Err "serie $s : no se pudo resolver a un objeto de dispositivo de Entra" }
        }
    }
    else {
        foreach ($n in $Nombre) {
            $m = @($md | Where-Object { (Get-Prop $_ 'deviceName') -eq $n })
            if ($m.Count -eq 0) { Write-Err "nombre $n : no esta en Intune"; continue }
            if ($m.Count -gt 1) { Write-Err "nombre $n : $($m.Count) coincidencias, usa -Serie o -DeviceId"; continue }
            $objetivos.Add([pscustomobject]@{ Etiqueta = "nombre $n"; DeviceId = (Get-Prop $m[0] 'azureADDeviceId') })
        }
    }
}

if ($objetivos.Count -eq 0) { throw 'Ningun equipo resuelto. Nada que consultar.' }

# ------------------------------------------------------------------
# Claves
# ------------------------------------------------------------------
$tiposVolumen = @{ 0 = 'desconocido'; 1 = 'sistema operativo'; 2 = 'volumen fijo'; 3 = 'volumen extraible' }
$resultados = [System.Collections.Generic.List[object]]::new()

Write-Host "`n== CLAVES DE RECUPERACION DE BITLOCKER ==" -ForegroundColor Cyan
Write-Host  '   La clave cuelga del objeto de dispositivo de Entra: si ese objeto se borra,' -ForegroundColor Yellow
Write-Host  '   la clave se pierde con el. Guardarla ANTES de restablecer o borrar el equipo.' -ForegroundColor Yellow

foreach ($o in $objetivos) {
    Write-Host ''
    Write-Host ("  {0}   deviceId={1}" -f $o.Etiqueta, $o.DeviceId) -ForegroundColor White

    # Nombre real, para que se vea a que equipo corresponde
    $nombreReal = '(desconocido)'
    try {
        $f = "deviceId eq '$($o.DeviceId)'"
        $dev = @(Invoke-LabGraph ('devices?$filter={0}&$select=displayName' -f [uri]::EscapeDataString($f)))
        if ($dev.Count -ge 1) { $nombreReal = Get-Prop $dev[0] 'displayName' '(sin nombre)' }
    } catch { }
    Write-Info "objeto de Entra: $nombreReal"

    try {
        $f = "deviceId eq '$($o.DeviceId)'"
        $claves = @(Invoke-LabGraph ('informationProtection/bitlocker/recoveryKeys?$filter={0}' -f [uri]::EscapeDataString($f)) -All)
    } catch {
        $m = $_.ErrorDetails.Message; if (-not $m) { $m = $_.Exception.Message }
        Write-Err ('no se pudieron leer las claves: ' + ($m -split "`n")[0])
        continue
    }

    if ($claves.Count -eq 0) {
        Write-Err 'sin claves escrowadas para ese equipo (o el objeto de Entra ya no existe)'
        continue
    }

    foreach ($k in $claves) {
        $vol = Get-Prop $k 'volumeType' 0
        $volTxt = if ($tiposVolumen.ContainsKey([int]$vol)) { $tiposVolumen[[int]$vol] } else { "tipo $vol" }
        # El campo 'key' NUNCA viene en el listado: hay que pedirlo clave a clave.
        $valor = '(no se pudo leer)'
        try { $valor = (Invoke-LabGraph ('informationProtection/bitlocker/recoveryKeys/{0}?$select=key' -f $k.id)).key } catch { }

        Write-Ok ("volumen: {0}   escrowada: {1}" -f $volTxt, (Get-Prop $k 'createdDateTime'))
        Write-Host ("         id    : {0}" -f $k.id) -ForegroundColor DarkGray
        Write-Host ("         CLAVE : {0}" -f $valor) -ForegroundColor White

        $resultados.Add([pscustomobject]@{
            Equipo      = $nombreReal
            Referencia  = $o.Etiqueta
            DeviceId    = $o.DeviceId
            ClaveId     = $k.id
            Volumen     = $volTxt
            Escrowada   = (Get-Prop $k 'createdDateTime')
            Clave       = $valor
        })
    }
}

if ($RutaCsv) {
    $resultados | Export-Csv -LiteralPath $RutaCsv -NoTypeInformation -Encoding UTF8
    Write-Host ''
    Write-Host ("  CSV escrito en {0}" -f $RutaCsv) -ForegroundColor Yellow
    Write-Host  '  Contiene claves de recuperacion en claro: borrarlo en cuanto se use.' -ForegroundColor Yellow
}

Write-Host ''
