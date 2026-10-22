<#
.SYNOPSIS
    [ES] Motor de PrintDeploy: reinstala colas Ricoh y agrega nuevas con el driver de su modelo.
    [EN] PrintDeploy engine: reinstalls Ricoh queues and adds new ones with their model driver.

.DESCRIPTION
    Lo lanza PrintDeploy.exe (ya elevado); no esta pensado para ejecutarse a mano.
    Entrada -JobsB64: base64(UTF8) de lineas separadas por tabulador:
      E <tab> nombre <tab> driver <tab> inf            reinstalar cola existente (mismo nombre/puerto)
      N <tab> nombre <tab> driver <tab> inf <tab> ip   agregar cola nueva
    Salida por lineas para la interfaz:
      STEP|<porcentaje>|<texto>   OK|..  WARN|..  ERR|..  LOG|..  SUMMARY|..

.NOTES
    Contexto: admin
    PowerShell 5.1.
#>
param([Parameter(Mandatory)] [string]$JobsB64)

$ErrorActionPreference = 'Stop'
# sin barras de progreso: con la salida redirigida llegan como CLIXML por el canal de errores
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Out-Line($kind, $text) { [Console]::Out.WriteLine("$kind|$text"); [Console]::Out.Flush() }
function Step($pct, $text) { Out-Line 'STEP' "$pct|$text" }

function Enable-PortSnmp($portName) {
    $key = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Monitors\Standard TCP/IP Port\Ports\$portName"
    if (-not (Test-Path $key)) { return $false }
    Set-ItemProperty $key -Name 'SNMP Enabled' -Value 1 -Type DWord
    Set-ItemProperty $key -Name 'SNMP Index' -Value 1 -Type DWord
    Set-ItemProperty $key -Name 'SNMP Community' -Value 'public'
    $true
}

function Remove-UnusedDriver($name) {
    if ($name -match '^Microsoft|Class Driver|Universal Print') { Out-Line 'LOG' "Driver de Windows conservado: $name"; return }
    if (Get-Printer | Where-Object DriverName -eq $name) { Out-Line 'LOG' "Driver conservado (lo usa otra impresora): $name"; return }
    if (-not (Get-PrinterDriver -Name $name -ErrorAction SilentlyContinue)) { return }
    try {
        Remove-PrinterDriver -Name $name -RemoveFromDriverStore -ErrorAction Stop
        Out-Line 'OK' "Driver eliminado: $name"
    } catch {
        try { Remove-PrinterDriver -Name $name -ErrorAction Stop; Out-Line 'OK' "Driver eliminado (paquete en uso): $name" }
        catch { Out-Line 'WARN' "No se pudo eliminar el driver $name : $($_.Exception.Message)" }
    }
}

$jobs = @(
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($JobsB64)) -split "`n" | Where-Object { $_.Trim() } | ForEach-Object {
        $f = $_.TrimEnd("`r") -split "`t"
        [pscustomobject]@{ Kind = $f[0]; Name = $f[1]; Driver = $f[2]; Inf = $f[3]; Ip = $(if ($f.Count -gt 4) { $f[4] } else { '' }) }
    }
)
$errors = 0

try {
    # 1. Guardar configuracion y quitar colas existentes
    Step 5 'Guardando configuracion de las impresoras seleccionadas'
    $default = (Get-CimInstance Win32_Printer -Filter 'Default=TRUE' -ErrorAction SilentlyContinue).Name
    $saved = @()
    foreach ($j in $jobs | Where-Object Kind -eq 'E') {
        $p = Get-Printer -Name $j.Name -ErrorAction SilentlyContinue
        if (-not $p) { Out-Line 'WARN' "No existe la impresora '$($j.Name)', se omite"; continue }
        $saved += [pscustomobject]@{
            Name = $p.Name; Port = $p.PortName; OldDriver = $p.DriverName; Driver = $j.Driver
            Shared = $p.Shared; ShareName = $p.ShareName; Location = $p.Location; Comment = $p.Comment
            Default = ($p.Name -eq $default)
        }
        Out-Line 'LOG' "Guardada: $($p.Name) | puerto $($p.PortName) | driver $($p.DriverName) -> $($j.Driver)"
    }

    $targets = @($jobs | Select-Object Driver, Inf -Unique)

    if ($saved.Count) {
        Step 15 'Desinstalando impresoras seleccionadas'
        foreach ($s in $saved) {
            Get-PrintJob -PrinterName $s.Name -ErrorAction SilentlyContinue | Remove-PrintJob -ErrorAction SilentlyContinue
            Remove-Printer -Name $s.Name
            Out-Line 'OK' "Impresora desinstalada: $($s.Name)"
        }

        Step 30 'Reiniciando la cola de impresion'
        Restart-Service Spooler -Force -WarningAction SilentlyContinue

        Step 40 'Limpiando drivers antiguos'
        foreach ($d in (@($saved.OldDriver) + @($targets.Driver) | Select-Object -Unique)) { Remove-UnusedDriver $d }
    }

    # 2. Drivers Ricoh necesarios
    $n = 0
    foreach ($t in $targets) {
        $n++
        Step (45 + [int](15 * $n / $targets.Count)) "Instalando driver $($t.Driver)"
        $pnp = & pnputil.exe /add-driver $t.Inf /install 2>&1
        foreach ($l in $pnp) { if ("$l".Trim()) { Out-Line 'LOG' "$l".Trim() } }
        if (-not (Get-PrinterDriver -Name $t.Driver -ErrorAction SilentlyContinue)) { Add-PrinterDriver -Name $t.Driver }
        Out-Line 'OK' "Driver instalado: $($t.Driver)"
    }

    # 3. Recrear colas existentes
    $snmp = $false
    $i = 0
    foreach ($s in $saved) {
        $i++
        Step (62 + [int](18 * $i / [Math]::Max(1, $saved.Count))) "Reinstalando $($s.Name)"
        try {
            Add-Printer -Name $s.Name -DriverName $s.Driver -PortName $s.Port
            $extra = @{}
            if ($s.Location) { $extra.Location = $s.Location }
            if ($s.Comment)  { $extra.Comment  = $s.Comment }
            if ($s.Shared)   { $extra.Shared = $true; $extra.ShareName = $s.ShareName }
            if ($extra.Count) { Set-Printer -Name $s.Name @extra }
            if ($s.Default) {
                Get-CimInstance Win32_Printer -Filter ("Name='" + ($s.Name -replace "'", "\'") + "'") |
                    Invoke-CimMethod -MethodName SetDefaultPrinter | Out-Null
            }
            if (Enable-PortSnmp $s.Port) { $snmp = $true }
            Out-Line 'OK' "Reinstalada: $($s.Name) ($($s.Port)) con $($s.Driver)"
            Out-Line 'SUMMARY' "$($s.Name)  -  $($s.Driver) en $($s.Port) (antes: $($s.OldDriver))"
        } catch {
            $errors++
            Out-Line 'ERR' "No se pudo recrear $($s.Name): $($_.Exception.Message)"
            Out-Line 'SUMMARY' "$($s.Name)  -  ERROR al recrear (puerto $($s.Port))"
        }
    }

    # 4. Colas nuevas por IP
    foreach ($j in $jobs | Where-Object Kind -eq 'N') {
        Step 85 "Agregando $($j.Name) ($($j.Ip))"
        try {
            $portName = "IP_$($j.Ip)"
            if (-not (Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue)) {
                Add-PrinterPort -Name $portName -PrinterHostAddress $j.Ip
            }
            Add-Printer -Name $j.Name -DriverName $j.Driver -PortName $portName
            if (Enable-PortSnmp $portName) { $snmp = $true }
            Out-Line 'OK' "Agregada: $($j.Name) ($portName) con $($j.Driver)"
            Out-Line 'SUMMARY' "$($j.Name)  -  nueva en $($j.Ip) con $($j.Driver)"
        } catch {
            $errors++
            Out-Line 'ERR' "No se pudo agregar $($j.Name): $($_.Exception.Message)"
            Out-Line 'SUMMARY' "$($j.Name)  -  ERROR al agregar"
        }
    }

    if ($snmp) {
        Step 95 'Aplicando configuracion (SNMP para detectar bandejas)'
        Restart-Service Spooler -Force -WarningAction SilentlyContinue
    }
    Step 100 'Finalizado'
} catch {
    $errors++
    Out-Line 'ERR' $_.Exception.Message
}

exit $errors
