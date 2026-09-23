<#
.SYNOPSIS
    [ES] Recupera el boton de reunion de Teams cuando desaparece de Outlook (clasico).
    [EN] Restores the Teams meeting button when it disappears from classic Outlook.

.DESCRIPTION
    [ES]
    Ejecutar como admin CON EL USUARIO AFECTADO CON SESION INICIADA en el equipo.
    Vale aunque el usuario no sea admin y se eleve con otra cuenta (admin local):
    detecta al usuario de la sesion (explorer.exe) y trabaja sobre SU perfil y
    SU registro (HKEY_USERS\<SID>), no sobre los de la cuenta que eleva.

    Pasos: cierra Outlook/Teams, limpia cache de Teams, quita las entradas de Teams
    de las listas de deshabilitados, fija LoadBehavior=3, anade Teams a
    DoNotDisableAddinList, registra Microsoft.Teams.AddinLoader.dll
    (regsvr32 /n /i:user) en el contexto del usuario, verifica y abre Teams.

    Solo modifica entradas de Teams. Otros add-ins (iManage, etc.) no se tocan:
    solo se listan y se avisa si iManage tiene LoadBehavior distinto de 3.

    [EN]
    Run as admin WITH THE AFFECTED USER LOGGED ON. Works when the user is not an
    admin and another account (local admin) elevates: it targets the session user's
    profile and registry hive (HKEY_USERS\<SID>), not the elevating account's.

    Closes Outlook/Teams, clears Teams cache, removes only Teams entries from the
    disabled items lists, sets LoadBehavior=3, adds Teams to DoNotDisableAddinList,
    registers Microsoft.Teams.AddinLoader.dll (regsvr32 /n /i:user) as the user,
    verifies and starts Teams. Other add-ins (iManage, etc.) are left untouched.

.PARAMETER User
    [ES] Opcional. Usuario objetivo (ej. "DOMINIO\juan" o "juan") si hay varias sesiones.
    [EN] Optional. Target user when more than one session is open.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\02-repair-teams-outlook-addin.ps1
    powershell -ExecutionPolicy Bypass -File .\02-repair-teams-outlook-addin.ps1 -User juan

.NOTES
    [ES] Exit code: 0 = OK, 1 = fallo, 2 = OK con avisos. Log en C:\Windows\Temp.
         Requiere admin. PowerShell 5.1 y 7. Windows 10 y 11. Solo Outlook clasico.
    [EN] Exit code: 0 = OK, 1 = failure, 2 = OK with warnings. Log in C:\Windows\Temp.
         Requires admin. PowerShell 5.1 and 7. Windows 10 and 11. Classic Outlook only.
#>
param([string]$User)

$ErrorActionPreference = "Stop"
$script:fails = 0
$script:warns = 0

function Ok($m)   { Write-Host "[OK]   $m" -ForegroundColor Green }
function Info($m) { Write-Host "[..]   $m" -ForegroundColor Gray }
function Warn($m) { $script:warns++; Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Fail($m) { $script:fails++; Write-Host "[FAIL] $m" -ForegroundColor Red }

function Finish {
    Write-Host ""
    if ($script:fails -gt 0) {
        Write-Host "RESULTADO: FALLO ($script:fails errores, $script:warns avisos)" -ForegroundColor Red; $rc = 1
    } elseif ($script:warns -gt 0) {
        Write-Host "RESULTADO: OK CON AVISOS ($script:warns). Abrir Outlook y comprobar boton." -ForegroundColor Yellow; $rc = 2
    } else {
        Write-Host "RESULTADO: OK. Abrir Outlook, el boton tarda unos segundos." -ForegroundColor Green; $rc = 0
    }
    Write-Host "Log: $logFile"
    try { Stop-Transcript | Out-Null } catch {}
    exit $rc
}

# Cualquier error no controlado se reporta como FAIL en vez de cortar sin resumen
trap {
    Fail "Error no controlado (linea $($_.InvocationInfo.ScriptLineNumber)): $($_.Exception.Message)"
    Finish
}

$logFile = "$env:SystemRoot\Temp\teams-addin-repair_$(Get-Date -Format yyyyMMdd_HHmmss).log"
try { Start-Transcript -Path $logFile | Out-Null } catch {}

# --- 1. Admin ---
$me = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]$me).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Fail "Sin privilegios de admin. Abrir PowerShell con 'Ejecutar como administrador'."
    Finish
}
Ok "Admin: $($me.Name)"

# --- 2. Usuario objetivo (dueno de explorer.exe) ---
$sessions = @{}
foreach ($p in Get-CimInstance Win32_Process -Filter "Name='explorer.exe'") {
    try {
        $o = Invoke-CimMethod -InputObject $p -MethodName GetOwner
        $s = (Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid).Sid
        if ($s) { $sessions[$s] = "$($o.Domain)\$($o.User)" }
    } catch {}
}
if ($User) {
    $match = @($sessions.GetEnumerator() | Where-Object { $_.Value -eq $User -or ($_.Value -split '\\')[-1] -eq $User })
} else {
    $match = @($sessions.GetEnumerator())
}
if ($match.Count -eq 0) {
    Fail "No hay sesion abierta del usuario objetivo. El usuario debe tener sesion iniciada. Sesiones: $($sessions.Values -join ', ')"
    Finish
}
if ($match.Count -gt 1) {
    Fail "Varias sesiones ($($sessions.Values -join ', ')). Relanzar con -User <usuario>."
    Finish
}
$sid      = $match[0].Key
$userName = $match[0].Value
$sameUser = ($sid -eq $me.User.Value)
$hku      = "Registry::HKEY_USERS\$sid"
$userProfile  = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid").ProfileImagePath
$localApp = Join-Path $userProfile "AppData\Local"
$roamApp  = Join-Path $userProfile "AppData\Roaming"
if (-not (Test-Path $hku)) { Fail "Hive HKU\$sid no cargado."; Finish }
Ok "Usuario objetivo: $userName ($sid)$(if (-not $sameUser) { ' [elevado por otra cuenta]' })"

# Ejecuta un comando en la sesion del usuario (no elevado) via tarea programada
function Invoke-AsUser([string]$Exe, [string]$Arguments, [switch]$NoWait) {
    if ($sameUser) {
        if ($NoWait) { Start-Process $Exe -ArgumentList $Arguments | Out-Null; return 0 }
        return (Start-Process $Exe -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden).ExitCode
    }
    $tn = "TeamsAddinRepair_" + [guid]::NewGuid().ToString("N").Substring(0, 8)
    $action    = New-ScheduledTaskAction -Execute $Exe -Argument $Arguments
    $principal = New-ScheduledTaskPrincipal -UserId $userName -LogonType Interactive -RunLevel Limited
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    Register-ScheduledTask -TaskName $tn -Action $action -Principal $principal -Settings $settings -Force | Out-Null
    try {
        Start-ScheduledTask -TaskName $tn
        if ($NoWait) { Start-Sleep -Seconds 3; return 0 }
        $t = 0
        do { Start-Sleep -Seconds 1; $t++; $st = (Get-ScheduledTask -TaskName $tn).State } while ($st -in @("Running", "Queued") -and $t -lt 60)
        return (Get-ScheduledTaskInfo -TaskName $tn).LastTaskResult
    } finally {
        Unregister-ScheduledTask -TaskName $tn -Confirm:$false
    }
}

# --- 3. Diagnostico previo ---
$newOutlook = (Get-ItemProperty "$hku\Software\Microsoft\Office\16.0\Outlook\Preferences" -ErrorAction SilentlyContinue).UseNewOutlook
if ($newOutlook -eq 1) { Warn "Usuario en Outlook NUEVO (UseNewOutlook=1). Los add-in COM no cargan ahi; volver a Outlook clasico." }

$policy = (Get-ItemProperty "$hku\Software\Policies\Microsoft\Office\16.0\Outlook\Resiliency\AddinList" -ErrorAction SilentlyContinue)."TeamsAddin.FastConnect"
if ($null -ne $policy -and "$policy" -ne "1") { Warn "GPO/Intune fuerza TeamsAddin.FastConnect=$policy (AddinList). Revisar politica." }

$teamsPkg = Get-AppxPackage -User $sid -Name MSTeams -ErrorAction SilentlyContinue | Select-Object -First 1
if ($teamsPkg) { Ok "Teams nuevo instalado: $($teamsPkg.Version)" } else { Warn "Teams nuevo (MSTeams) no instalado para este usuario." }

$officeArch = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue).Platform
if (-not $officeArch) { $officeArch = "x64"; Warn "No se detecta arquitectura de Office (C2R). Se asume x64." } else { Info "Office: $officeArch" }

# --- 4. Cerrar procesos ---
$procs = @(Get-Process -Name Outlook, olk, Teams, ms-teams -ErrorAction SilentlyContinue)
if ($procs.Count) {
    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    if (Get-Process -Name Outlook, ms-teams -ErrorAction SilentlyContinue) { Warn "Outlook/Teams siguen abiertos." } else { Ok "Cerrados $($procs.Count) procesos (Outlook/Teams)." }
} else { Ok "Outlook/Teams no estaban abiertos." }

# --- 5. Cache Teams ---
$caches = @(
    "$localApp\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams",
    "$roamApp\Microsoft\Teams"
)
foreach ($c in $caches) {
    if (Test-Path $c) {
        try { Remove-Item $c -Recurse -Force; Ok "Cache borrada: $c" }
        catch { Warn "No se pudo borrar por completo: $c ($($_.Exception.Message))" }
    }
}

# --- 6. Resiliency (solo entradas de Teams; el resto de add-ins no se toca) ---
$res = "$hku\Software\Microsoft\Office\16.0\Outlook\Resiliency"
foreach ($k in "DisabledItems", "CrashingAddinList") {
    if (-not (Test-Path "$res\$k")) { continue }
    $removed = 0; $kept = 0
    foreach ($name in @((Get-Item "$res\$k").Property)) {
        $val  = (Get-ItemProperty "$res\$k" -Name $name).$name
        $text = if ($val -is [byte[]]) { [Text.Encoding]::Unicode.GetString($val) } else { "$val" }
        if ("$name $text" -match "Teams") {
            Remove-ItemProperty -Path "$res\$k" -Name $name -Force
            $removed++
        } else { $kept++ }
    }
    Ok "Resiliency\$k : $removed entradas Teams quitadas, $kept de otros add-ins sin tocar."
}

# Add-ins COM de Outlook: solo lectura, informativo
$addinRoots = @(
    @{ Scope = "HKCU"; Path = "$hku\Software\Microsoft\Office\Outlook\Addins" },
    @{ Scope = "HKLM"; Path = "HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins" },
    @{ Scope = "HKLM32"; Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\Outlook\Addins" },
    @{ Scope = "C2R"; Path = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\REGISTRY\MACHINE\Software\Microsoft\Office\Outlook\Addins" },
    @{ Scope = "C2R32"; Path = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\REGISTRY\MACHINE\Software\WOW6432Node\Microsoft\Office\Outlook\Addins" }
)
foreach ($ar in $addinRoots) {
    Get-ChildItem $ar.Path -ErrorAction SilentlyContinue | ForEach-Object {
        $pr = Get-ItemProperty $_.PSPath
        $id = $_.PSChildName
        Info "Add-in: $id LoadBehavior=$($pr.LoadBehavior) [$($ar.Scope)]"
        if (($id -match "iManage|WorkSite|FileSite" -or "$($pr.FriendlyName)" -match "iManage|WorkSite|FileSite") -and $pr.LoadBehavior -ne 3) {
            Warn "$id (iManage) LoadBehavior=$($pr.LoadBehavior). El script NO lo modifica; revisar a mano."
        }
    }
}

# DoNotDisableAddinList: conservar entradas existentes, solo anadir Teams
$dnd = "$res\DoNotDisableAddinList"
if (-not (Test-Path $dnd)) { New-Item -Path $dnd | Out-Null }
New-ItemProperty -Path $dnd -Name "TeamsAddin.FastConnect" -Value 1 -PropertyType DWord -Force | Out-Null
Ok "DoNotDisableAddinList\TeamsAddin.FastConnect = 1 (resto de entradas conservadas)"

# --- 7. Clave del add-in ---
$addinKey = "$hku\Software\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect"
$prevLB = (Get-ItemProperty $addinKey -ErrorAction SilentlyContinue).LoadBehavior
if (-not (Test-Path $addinKey)) { New-Item -Path $addinKey -Force | Out-Null }
New-ItemProperty -Path $addinKey -Name "LoadBehavior" -Value 3 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $addinKey -Name "FriendlyName" -Value "Microsoft Teams Meeting Add-in for Microsoft Office" -PropertyType String -Force | Out-Null
New-ItemProperty -Path $addinKey -Name "Description"  -Value "Microsoft Teams Meeting Add-in for Microsoft Office" -PropertyType String -Force | Out-Null
Ok "LoadBehavior: $(if ($null -eq $prevLB) { 'no existia' } else { $prevLB }) -> 3"

# --- 8. Localizar y registrar DLL ---
$dll = $null
foreach ($root in "$localApp\Microsoft\TeamsMeetingAdd-in", "$localApp\Microsoft\TeamsMeetingAddin") {
    if (-not (Test-Path $root)) { continue }
    $dirs = Get-ChildItem $root -Directory | Sort-Object { try { [version]$_.Name } catch { [version]"0.0" } } -Descending
    foreach ($d in $dirs) {
        $cand = Join-Path $d.FullName "$officeArch\Microsoft.Teams.AddinLoader.dll"
        if (Test-Path $cand) { $dll = $cand; break }
    }
    if ($dll) { break }
}

if (-not $dll) {
    Fail "Microsoft.Teams.AddinLoader.dll ($officeArch) no encontrada en $localApp\Microsoft\TeamsMeetingAdd-in. Abrir Teams, esperar 2 min (instala el add-in) y relanzar."
} else {
    Info "DLL: $dll"
    $rc = Invoke-AsUser "regsvr32.exe" "/s /n /i:user `"$dll`""
    if ($rc -eq 0) { Ok "regsvr32 /n /i:user OK (contexto $userName)." } else { Fail "regsvr32 devolvio $rc." }
}

# --- 9. Verificacion ---
# Busca cualquier CLSID cuyo InprocServer32 sea AddinLoader.dll (usuario y maquina)
$classRoots = @(
    "Registry::HKEY_USERS\${sid}_Classes",
    "$hku\Software\Classes",
    "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes"
)
$found = @()
foreach ($r in $classRoots) {
    foreach ($base in "CLSID", "WOW6432Node\CLSID") {
        Get-ChildItem "$r\$base" -ErrorAction SilentlyContinue | ForEach-Object {
            $v = (Get-ItemProperty "$($_.PSPath)\InprocServer32" -ErrorAction SilentlyContinue).'(default)'
            if ($v -like "*Microsoft.Teams.AddinLoader.dll") { $found += [pscustomobject]@{ Root = ($r -replace '^Registry::', ''); Clsid = $_.PSChildName; Dll = $v } }
        }
    }
}
$found = @($found | Sort-Object Clsid, Dll -Unique)
if (-not $found) {
    Fail "Ningun CLSID apunta a Microsoft.Teams.AddinLoader.dll. regsvr32 no registro nada."
} else {
    foreach ($f in $found) {
        if (Test-Path $f.Dll) { Ok "COM registrado: $($f.Clsid) -> $($f.Dll) [$($f.Root)]" }
        else { Warn "COM huerfano (DLL no existe): $($f.Clsid) -> $($f.Dll) [$($f.Root)]" }
    }
    if (-not ($found | Where-Object { Test-Path $_.Dll })) { Fail "Todos los registros COM apuntan a DLL inexistente." }
}
foreach ($r in $classRoots) {
    if (Test-Path "$r\TeamsAddin.FastConnect") { Info "ProgID TeamsAddin.FastConnect en $($r -replace '^Registry::', '')" }
}
$lb = (Get-ItemProperty $addinKey -ErrorAction SilentlyContinue).LoadBehavior
if ($lb -eq 3) { Ok "LoadBehavior verificado = 3" } else { Fail "LoadBehavior = $lb" }

# --- 10. Abrir Teams en la sesion del usuario ---
if ($teamsPkg) {
    try { Invoke-AsUser "explorer.exe" "shell:AppsFolder\MSTeams_8wekyb3d8bbwe!MSTeams" -NoWait | Out-Null; Ok "Teams lanzado en la sesion de $userName." }
    catch { Warn "No se pudo lanzar Teams: $($_.Exception.Message)" }
}

Finish

