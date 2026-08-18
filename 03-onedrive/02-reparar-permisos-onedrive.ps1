<#
.SYNOPSIS
    [ES] Quita las ACE de denegacion que dejo una GPO de dominio y hacen que OneDrive pida admin.
    [EN] Removes deny ACEs left behind by a domain GPO that make OneDrive prompt for admin.

.DESCRIPTION
    [ES]
    Sintoma: un usuario estandar no puede crear carpetas dentro de su propio OneDrive. El
    Explorador pide credenciales de administrador, y solo ocurre en rutas de OneDrive.

    Causa: ACE de denegacion 'Everyone:(DENY)(D,WD,AD,DC)' escritas carpeta por carpeta por
    una GPO de dominio. Al sacar el equipo del dominio la GPO desaparece, pero los ACL siguen
    grabados en la MFT de NTFS. No son heredables -no llevan (OI)(CI)-, estan en cada carpeta
    de forma individual, y en NTFS una denegacion siempre gana sobre una concesion: por eso
    el usuario falla aunque tenga (F) heredado y sea el propietario.

    Tres fases, y cada una se ejecuta en un contexto distinto:

      Reparar   -> ADMIN. 'icacls /reset /T /C /Q' descarta las ACE explicitas y restablece
                   la herencia del perfil.
      Comprobar -> ADMIN. Cuenta las ACE de denegacion que queden. Debe dar 0.
      Verificar -> SESION DEL USUARIO, SIN ELEVAR. Crea y borra una carpeta de prueba. Es la
                   unica prueba que cuenta: elevado pasa siempre y no demuestra nada.

    Sin -Fase ejecuta Reparar y Comprobar, y recuerda que Verificar va aparte.

.PARAMETER Fase
    [ES] Reparar | Comprobar | Verificar. Por defecto Reparar + Comprobar.
    [EN] Reparar | Comprobar | Verificar. Defaults to Reparar + Comprobar.

.PARAMETER Ruta
    [ES] Raiz de OneDrive. Por defecto %OneDrive% de la sesion actual.
    [EN] OneDrive root. Defaults to %OneDrive% of the current session.

.PARAMETER DryRun
    [ES] Cuenta las denegaciones y no cambia nada.
    [EN] Counts deny ACEs and changes nothing.

.EXAMPLE
    # 1) Reparar y comprobar, en PowerShell elevado
    .\02-reparar-permisos-onedrive.ps1 -Ruta "C:\Users\jperez\OneDrive - Contoso"

.EXAMPLE
    # 2) Ver cuantas denegaciones hay, sin tocar nada
    .\02-reparar-permisos-onedrive.ps1 -DryRun -Ruta "C:\Users\jperez\OneDrive - Contoso"

.EXAMPLE
    # 3) Verificar, en la sesion del usuario y SIN elevar
    .\02-reparar-permisos-onedrive.ps1 -Fase Verificar

.NOTES
    [ES] El arreglo es permanente: sin dominio nada vuelve a aplicar esas ACE. No concede
         privilegios de admin -los permisos NTFS y el grupo Administradores son sistemas
         independientes-, el usuario sigue siendo estandar.
         Pausar la sincronizacion de OneDrive antes: icacls puede disparar la descarga de
         los archivos en la nube y tardar muchisimo.
    [EN] The fix is permanent: with no domain, nothing reapplies those ACEs. It grants no
         admin privileges -NTFS permissions and the Administrators group are separate
         systems-, the user stays standard.
         Pause OneDrive sync first: icacls can trigger downloading cloud-only files and
         take a very long time.

    PowerShell 5.1 y 7. Windows 10 y 11.
#>
[CmdletBinding()]
param(
    [ValidateSet('Reparar', 'Comprobar', 'Verificar')]
    [string]$Fase,
    [string]$Ruta,
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'

function Escribir([string]$t, [string]$c = 'Gray') { Write-Host $t -ForegroundColor $c }

function Test-Elevado {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-RaizOneDrive {
    if ($Ruta) { return $Ruta }
    if ($env:OneDrive) { return $env:OneDrive }
    if ($env:OneDriveCommercial) { return $env:OneDriveCommercial }
    return $null
}

function Measure-Denegaciones([string]$raiz) {
    # Se cuenta sobre la salida de icacls: Get-Acl por elemento sobre decenas de miles de
    # carpetas es ordenes de magnitud mas lento.
    $salida = & icacls.exe $raiz /T /C 2>$null
    return @($salida | Select-String -SimpleMatch 'DENY').Count
}

Escribir ''
Escribir '=== Permisos de OneDrive: ACE de denegacion residuales ===' Cyan

$fases = if ($Fase) { @($Fase) } else { @('Reparar', 'Comprobar') }

# --- Verificar: contexto del usuario, sin elevar ----------------------------
if ($fases -contains 'Verificar') {
    $raiz = Get-RaizOneDrive
    if (-not $raiz) {
        Escribir '  ABORTADO: no hay %OneDrive% en esta sesion. Indica -Ruta.' Red
        return
    }
    if (Test-Elevado) {
        Escribir '  AVISO: consola elevada. Elevado la prueba pasa siempre y no demuestra nada.' Red
        Escribir '  Abre PowerShell SIN elevar, en la sesion del usuario afectado.' Yellow
    }

    Escribir ''
    Escribir "--- Prueba de escritura real en: $raiz ---" Cyan
    $rutas = @($raiz, (Join-Path $raiz 'Documentos'), (Join-Path $raiz 'Documents'),
               (Join-Path $raiz 'Escritorio'), (Join-Path $raiz 'Desktop'))
    $fallos = 0
    foreach ($b in $rutas) {
        if (-not (Test-Path -LiteralPath $b)) { Escribir "  (no existe)  $b" DarkGray; continue }
        $tmp = Join-Path $b ('_prueba_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
        try {
            New-Item -Path $tmp -ItemType Directory -ErrorAction Stop | Out-Null
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            Escribir "  [OK]    $b" Green
        }
        catch {
            $fallos++
            Escribir ("  [FALLO] {0} :: {1}" -f $b, $_.Exception.Message) Red
        }
    }
    Escribir ''
    if ($fallos -eq 0) {
        Escribir '  Resuelto. Confirmalo tambien desde el Explorador: clic derecho > Nuevo > Carpeta.' Green
    }
    else {
        Escribir "  Quedan $fallos ruta/s sin permiso. Repite la fase Reparar." Red
    }
    if ($fases.Count -eq 1) { return }
}

# --- Reparar y Comprobar: requieren admin ----------------------------------
$raiz = Get-RaizOneDrive
if (-not $raiz) {
    Escribir '  ABORTADO: indica la raiz con -Ruta (p.ej. "C:\Users\jperez\OneDrive - Contoso").' Red
    return
}
if (-not (Test-Path -LiteralPath $raiz)) {
    Escribir "  ABORTADO: no existe la ruta '$raiz'." Red
    return
}
if (-not (Test-Elevado)) {
    Escribir '  ABORTADO: Reparar y Comprobar necesitan consola elevada (modificar ACL).' Red
    Escribir '  Windows > escribe powershell > clic derecho > Ejecutar como administrador.' Yellow
    return
}

Escribir "  raiz: $raiz"

if ($fases -contains 'Comprobar' -or $DryRun) {
    Escribir ''
    Escribir '--- Recuento previo de denegaciones ---' Cyan
    Escribir '  recorriendo el arbol, puede tardar...' DarkGray
    $previas = Measure-Denegaciones $raiz
    Escribir ("  ACE de denegacion encontradas: {0}" -f $previas) $(if ($previas -gt 0) { 'Yellow' } else { 'Green' })
    if ($previas -eq 0 -and -not $DryRun) {
        Escribir '  No hay nada que reparar. Si el usuario sigue fallando, mira los descartes del .md.' Green
        return
    }
}

if ($DryRun) {
    Escribir ''
    Escribir '  [SIM] se ejecutaria: icacls "<raiz>" /reset /T /C /Q' Yellow
    Escribir '  Modo simulacion: no se ha cambiado nada.' Yellow
    return
}

if ($fases -contains 'Reparar') {
    Escribir ''
    Escribir '--- Reparando ---' Cyan
    Escribir '  icacls /reset /T /C /Q  (descarta ACE explicitas, restablece herencia)' DarkGray
    # /Q es imprescindible: sin el, icacls emite una linea por elemento y en un OneDrive
    # grande vuelca cientos de miles de lineas a la consola.
    & icacls.exe $raiz /reset /T /C /Q
    Escribir ''
    Escribir '  Los fallos por "no se encuentra la ruta" son rutas que pasan de 260 caracteres' DarkGray
    Escribir '  (MAX_PATH), no errores de permisos. Unos cientos sobre decenas de miles esta bien.' DarkGray
}

if ($fases -contains 'Comprobar') {
    Escribir ''
    Escribir '--- Comprobacion posterior ---' Cyan
    $restantes = Measure-Denegaciones $raiz
    if ($restantes -eq 0) {
        Escribir '  [OK] 0 ACE de denegacion.' Green
    }
    else {
        Escribir "  [AVISO] quedan $restantes. Vuelve a ejecutar la fase Reparar." Red
    }
}

Escribir ''
Escribir '=== Siguiente paso: fase Verificar, en la sesion del usuario y SIN elevar ===' Cyan
Escribir '    .\02-reparar-permisos-onedrive.ps1 -Fase Verificar' Yellow
