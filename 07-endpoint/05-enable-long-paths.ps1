#Requires -RunAsAdministrator

<#
.SYNOPSIS
    [ES] Activa las rutas largas de Windows (mas de 260 caracteres) y desactiva los nombres cortos 8.3.
    [EN] Enables Windows long paths (over 260 characters) and disables 8.3 short names.
.DESCRIPTION
    Ajusta dos valores de HKLM\SYSTEM\CurrentControlSet\Control\FileSystem:

      LongPathsEnabled = 1
          Levanta el limite LOCAL de 260 caracteres por ruta: carpetas profundas de
          iManage, unidades de red y programas que no abren rutas largas.

      NtfsDisable8dot3NameCreation = 1
          Deja de crear el nombre corto tipo NOMBRE~1 en cada fichero nuevo. Solo
          afecta a lo que se cree a partir de ahora.

    NO arregla el aviso de OneDrive "la ruta es demasiado larga": ese es un limite del
    servidor (400 caracteres) que no depende de Windows. Para eso:
    03-onedrive\03-shorten-long-paths.ps1

    Muestra el valor anterior y el nuevo de cada clave. Hace falta reiniciar.
.PARAMETER DryRun
    Muestra el estado actual y lo que cambiaria, sin escribir nada.
.EXAMPLE
    .\05-enable-long-paths.ps1
.EXAMPLE
    .\05-enable-long-paths.ps1 -DryRun
.NOTES
    EJECUTAR COMO: administrador (escribe en HKLM). PowerShell 5.1 y 7.
    Revertir: poner los dos valores a 0 y reiniciar.
#>
[CmdletBinding()]
param([switch]$DryRun)

$ErrorActionPreference = 'Stop'
$clave = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
$valores = [ordered]@{ LongPathsEnabled = 1; NtfsDisable8dot3NameCreation = 1 }

function Get-Valor([string]$n) {
    $p = Get-ItemProperty -Path $clave -ErrorAction SilentlyContinue
    if ($p -and ($p.PSObject.Properties.Name -contains $n)) { $p.$n } else { '(no existe)' }
}

Write-Host ''
Write-Host '== Rutas largas y nombres 8.3 ==' -ForegroundColor Cyan
$cambiado = $false
foreach ($n in $valores.Keys) {
    $antes = Get-Valor $n
    if ("$antes" -eq "$($valores[$n])") {
        Write-Host ("  {0,-30} {1}  [OK, ya estaba]" -f $n, $antes) -ForegroundColor Green
        continue
    }
    if ($DryRun) {
        Write-Host ("  {0,-30} {1} -> {2}  [DryRun, sin cambios]" -f $n, $antes, $valores[$n]) -ForegroundColor Yellow
        continue
    }
    try {
        Set-ItemProperty -Path $clave -Name $n -Value $valores[$n] -Type DWord -Force
        $despues = Get-Valor $n
        $ok = "$despues" -eq "$($valores[$n])"
        Write-Host ("  {0,-30} {1} -> {2}  [{3}]" -f $n, $antes, $despues, $(if ($ok) { 'OK' } else { 'FALLO' })) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
        if ($ok) { $cambiado = $true }
    } catch {
        Write-Host ("  {0,-30} ERROR: {1}" -f $n, $_.Exception.Message) -ForegroundColor Red
    }
}
Write-Host ''
if ($cambiado) { Write-Host 'Reinicia el equipo para que surta efecto.' -ForegroundColor Yellow }
Write-Host 'El aviso de OneDrive "ruta demasiado larga" (limite 400) se arregla con 03-onedrive\03-shorten-long-paths.ps1' -ForegroundColor DarkGray
Write-Host ''
