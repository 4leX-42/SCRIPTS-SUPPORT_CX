#Requires -RunAsAdministrator

<#
.SYNOPSIS
    [ES] Quita el ahorro de energia de la tarjeta Wi-Fi y pone el plan de alto rendimiento.
    [EN] Disables Wi-Fi adapter power saving and switches to the high performance power plan.

.DESCRIPTION
    [ES]
    Para el caso tipico de "se me corta el wifi cada dos por tres" en portatiles: Windows
    apaga la radio de la tarjeta para ahorrar bateria y la conexion se cae o se vuelve
    intermitente. Actua sobre dos frentes:

      1. Plan de energia del sistema -> Alto rendimiento. Si el plan no existe en el equipo
         (algunos OEM lo quitan), lo duplica desde la plantilla de Windows; si tampoco puede,
         se queda en Equilibrado y avisa.
      2. Propiedades avanzadas del adaptador: apaga el ahorro de energia, desactiva el modo
         de suspension, sube la agresividad de roaming y la potencia de transmision al
         maximo que declare el driver, y activa el refuerzo de rendimiento si existe.

    Los nombres de las propiedades avanzadas los pone cada fabricante de driver, asi que el
    script no los da por supuestos: recorre las que el adaptador declara y solo toca las que
    existen y admiten el valor buscado. En un adaptador que no exponga ninguna, no hace nada
    y lo dice.

    [EN]
    For the classic "my wifi drops every few minutes" on laptops: Windows powers down the
    adapter radio to save battery and the link drops or turns flaky. It works on two fronts:

      1. System power plan -> High performance. If that plan is missing (some OEMs strip it),
         it is duplicated from the Windows template; if that also fails, the machine stays on
         Balanced and the script says so.
      2. Adapter advanced properties: turn off power saving, disable selective suspend, raise
         roaming aggressiveness and transmit power to the highest value the driver declares,
         and enable throughput boost where present.

    Advanced property names are chosen by each driver vendor, so nothing is assumed: the
    script walks the properties the adapter actually declares and only touches those that
    exist and accept the target value. On an adapter exposing none, it changes nothing and
    reports that.

.PARAMETER Adaptador
    [ES] Nombre del adaptador. Por defecto busca el Wi-Fi activo.
    [EN] Adapter name. Defaults to the active Wi-Fi adapter.

.PARAMETER DryRun
    [ES] Enumera lo que cambiaria sin tocar nada.
    [EN] Lists what would change without touching anything.

.EXAMPLE
    .\02-optimizar-tarjeta-wifi.ps1 -DryRun

.EXAMPLE
    .\02-optimizar-tarjeta-wifi.ps1 -Adaptador 'Wi-Fi 2'

.NOTES
    [ES] Requiere admin (toca el plan de energia y el driver). Reiniciar para aplicarlo todo.
         Sube el consumo de bateria: es el precio de que no se corte.
    [EN] Requires admin (touches the power plan and the driver). Reboot to apply everything.
         Battery drain goes up: that is the trade-off for a stable link.

    PowerShell 5.1 y 7. Windows 10 y 11.
#>
[CmdletBinding()]
param(
    [string]$Adaptador,
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'

# GUID de los planes de energia de Windows. Son fijos en todas las instalaciones.
$PLAN_ALTO_RENDIMIENTO = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$PLAN_EQUILIBRADO      = 'e9a42b02-d5df-448d-aa00-03f14749eb61'

function Escribir([string]$texto, [string]$color = 'Gray') { Write-Host $texto -ForegroundColor $color }

Escribir ''
Escribir '=== Optimizacion de la tarjeta Wi-Fi ===' Cyan
if ($DryRun) { Escribir '    modo simulacion: no se cambia nada' Yellow }
Escribir ''

# --- 1. Plan de energia -----------------------------------------------------
Escribir '--- Plan de energia ---' Cyan
$planPrevio = (powercfg /getactivescheme) -replace '.*:\s*', ''
Escribir "  plan actual: $planPrevio"

if ($DryRun) {
    Escribir '  [SIM] se activaria Alto rendimiento' Yellow
}
else {
    powercfg /setactive $PLAN_ALTO_RENDIMIENTO 2>$null
    if (-not $?) {
        # Algunos OEM eliminan el plan; se recrea desde la plantilla de Windows.
        Escribir '  Alto rendimiento no existe, duplicandolo desde la plantilla' Yellow
        powercfg /duplicatescheme $PLAN_ALTO_RENDIMIENTO 2>$null
        powercfg /setactive $PLAN_ALTO_RENDIMIENTO 2>$null
    }
    if ($?) {
        Escribir '  [OK] Alto rendimiento activado' Green
    }
    else {
        powercfg /setactive $PLAN_EQUILIBRADO 2>$null
        Escribir '  [AVISO] no se pudo activar Alto rendimiento; se deja Equilibrado' Red
    }
}

# --- 2. Localizar el adaptador ---------------------------------------------
Escribir ''
Escribir '--- Adaptador ---' Cyan
if ($Adaptador) {
    $nombre = $Adaptador
}
else {
    # Primero por nombre visible, luego por descripcion del driver: hay equipos donde el
    # adaptador se llama "Ethernet 3" aunque sea inalambrico.
    $nombre = (Get-NetAdapter | Where-Object {
        $_.Status -eq 'Up' -and ($_.Name -like '*Wi-Fi*' -or $_.Name -like '*WiFi*' -or $_.Name -like '*Wireless*')
    } | Select-Object -First 1).Name

    if (-not $nombre) {
        $nombre = (Get-NetAdapter | Where-Object {
            $_.InterfaceDescription -like '*Wireless*' -or $_.InterfaceDescription -like '*Wi-Fi*'
        } | Select-Object -First 1).Name
    }
}

if (-not $nombre) {
    Escribir '  ABORTADO: no se ha encontrado ninguna tarjeta Wi-Fi.' Red
    Escribir '  Indicalo a mano con -Adaptador "<nombre>". Lista con: Get-NetAdapter' Yellow
    return
}
Escribir "  usando: $nombre" Green

# --- 3. Propiedades avanzadas ----------------------------------------------
# Cada fabricante nombra estas propiedades a su manera, asi que se recorren las que el
# adaptador declara y se comparan contra los valores admitidos que el propio driver expone.
$reglas = @(
    @{ Patron = '*Power*Save*';                        Valores = @('Off', 'Disabled') }
    @{ Patron = '*Sleep*';                             Valores = @('Disabled', 'Off') }
    @{ Patron = '*MIMO*';                              Valores = @('No SMPS') }
    @{ Patron = '*Throughput*';                        Valores = @('Enabled') }
    @{ Patron = '*Roaming*';                           Maximo  = $true }
    @{ Patron = '*Transmit Power*';                    Maximo  = $true }
    @{ Patron = '*Tx Power*';                          Maximo  = $true }
)

Escribir ''
Escribir '--- Propiedades avanzadas ---' Cyan
$props = Get-NetAdapterAdvancedProperty -Name $nombre -ErrorAction SilentlyContinue
if (-not $props) {
    Escribir '  el driver no expone propiedades avanzadas: nada que ajustar' Yellow
}

$tocadas = 0
foreach ($p in $props) {
    foreach ($regla in $reglas) {
        if ($p.DisplayName -notlike $regla.Patron) { continue }

        $destino = $null
        if ($regla.Maximo) {
            # El driver lista los valores de menor a mayor: el ultimo es el maximo.
            $destino = $p.ValidDisplayValues | Select-Object -Last 1
        }
        else {
            foreach ($v in $regla.Valores) {
                if ($p.ValidDisplayValues -contains $v) { $destino = $v; break }
            }
        }

        if (-not $destino -or $p.DisplayValue -eq $destino) { continue }

        if ($DryRun) {
            Escribir ("  [SIM] {0}: {1} -> {2}" -f $p.DisplayName, $p.DisplayValue, $destino) Yellow
        }
        else {
            try {
                Set-NetAdapterAdvancedProperty -Name $nombre -DisplayName $p.DisplayName -DisplayValue $destino -ErrorAction Stop
                Escribir ("  [OK] {0}: {1} -> {2}" -f $p.DisplayName, $p.DisplayValue, $destino) Green
            }
            catch {
                Escribir ("  [ERROR] {0}: {1}" -f $p.DisplayName, $_.Exception.Message) Red
            }
        }
        $tocadas++
        break
    }
}

if ($tocadas -eq 0) { Escribir '  todo estaba ya en el valor correcto' Green }

Escribir ''
Escribir '=== Terminado. Reinicia el equipo para aplicarlo todo. ===' Cyan
