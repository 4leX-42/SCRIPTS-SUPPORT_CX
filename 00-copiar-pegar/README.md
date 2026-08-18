# 00 — Comandos sueltos para copiar y pegar

Un comando por problema. No hay que descargar nada: se copia la linea y se pega
en la consola de PowerShell. `[ADMIN]` = hay que abrirla como administrador.
Todos funcionan en PowerShell 5.1 y en 7.

---

## 1. Rutas y ficheros

### 1.1 Rutas largas + nombres 8.3 `[ADMIN]`
El clasico "ruta demasiado larga" de OneDrive, iManage y unidades de red.
Tambien en fichero aparte: [`01-long-paths.txt`](01-long-paths.txt)

```powershell
Write-Host "== FileSystem Tweaks ==" -ForegroundColor Cyan; try{Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -Type DWord -Force; Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "NtfsDisable8dot3NameCreation" -Value 1 -Type DWord -Force; $lp=(Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem").LongPathsEnabled; $sn=(Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem").NtfsDisable8dot3NameCreation; $lpTag=if($lp -eq 1){"[OK]"}else{"[FAIL]"}; $snTag=if($sn -eq 1){"[OK]"}else{"[FAIL]"}; Write-Host ("LongPathsEnabled            -> {0} {1}" -f $lp,$lpTag); Write-Host ("NtfsDisable8dot3NameCreation -> {0} {1}" -f $sn,$snTag)}catch{Write-Host ("ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red}
```

Hay que reiniciar el equipo. `NtfsDisable8dot3NameCreation` solo afecta a ficheros nuevos.

### 1.2 Encontrar las rutas que pasan de 255 caracteres
```powershell
$r="$env:USERPROFILE\OneDrive"; [IO.Directory]::EnumerateFiles($r,'*',[IO.SearchOption]::AllDirectories) | Where-Object { $_.Length -gt 255 } | Sort-Object Length -Descending | Select-Object -First 20 | ForEach-Object { "{0,4}  {1}" -f $_.Length,$_ }
```

### 1.3 Desbloquear ficheros descargados de Internet
```powershell
Get-ChildItem "$env:USERPROFILE\Downloads" -Recurse | Unblock-File
```

---

## 2. Limpieza de disco

### 2.1 Temporales y cache de Windows Update `[ADMIN]`
```powershell
$antes=(Get-PSDrive C).Free; Stop-Service wuauserv,bits -Force -ErrorAction SilentlyContinue; foreach($p in @($env:TEMP,"$env:SystemRoot\Temp","$env:SystemRoot\SoftwareDistribution\Download")){ Get-ChildItem $p -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }; Start-Service wuauserv,bits -ErrorAction SilentlyContinue; Clear-RecycleBin -Force -ErrorAction SilentlyContinue; "{0:N2} GB liberados" -f ((( Get-PSDrive C).Free-$antes)/1GB)
```

### 2.2 Limpiar componentes de Windows (WinSxS) `[ADMIN]`
```powershell
Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
```

### 2.3 Perfiles de usuario sin usar hace 90 dias `[ADMIN]`
Lista, no borra. Quitar el `Where-Object` final para ver todos.
```powershell
Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special -and $_.LastUseTime -and $_.LastUseTime -lt (Get-Date).AddDays(-90) } | Select-Object LocalPath, LastUseTime, @{n='GB';e={[math]::Round((Get-ChildItem $_.LocalPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum/1GB,2)}} | Sort-Object GB -Descending | Format-Table -AutoSize
```

---

## 3. Office / Microsoft 365

### 3.1 Estado de activacion de Office
```powershell
$o=(Get-ChildItem "$env:ProgramFiles\Microsoft Office\Office16\ospp.vbs","${env:ProgramFiles(x86)}\Microsoft Office\Office16\ospp.vbs" -ErrorAction SilentlyContinue | Select-Object -First 1); if($o){ cscript //nologo $o.FullName /dstatus } else { Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' | Select-Object ProductReleaseIds,VersionToReport,CDNBaseUrl }
```

### 3.2 Forzar actualizacion de Office (Click-to-Run)
```powershell
& "$env:ProgramFiles\Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe" /update user updatepromptuser=true
```

### 3.3 Reiniciar el cliente de OneDrive
```powershell
Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 3; Start-Process "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
```

### 3.4 Resetear OneDrive (conserva los ficheros, rehace la sincronizacion)
```powershell
& "$env:LOCALAPPDATA\Microsoft\OneDrive\onedrive.exe" /reset; Start-Sleep 10; Start-Process "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
```

### 3.5 Limpiar cache de Teams (nuevo)
```powershell
Get-Process ms-teams -ErrorAction SilentlyContinue | Stop-Process -Force; Remove-Item "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\*" -Recurse -Force -ErrorAction SilentlyContinue; "Cache de Teams limpiada. Vuelve a abrir Teams."
```

### 3.6 A que tenant pertenece un dominio o un usuario
```powershell
$u='usuario@dominio.com'; Invoke-RestMethod "https://login.microsoftonline.com/getuserrealm.srf?login=$u&json=1" | Select-Object Login,DomainName,NameSpaceType,FederationBrandName
```

---

## 4. Identidad y sesion

### 4.1 Estado de union del equipo (Entra / dominio / MDM)
```powershell
dsregcmd /status | Select-String 'AzureAdJoined|DomainJoined|WorkplaceJoined|TenantName|MdmUrl|DeviceId'
```

### 4.2 Credenciales guardadas en el equipo
```powershell
cmdkey /list | Select-String 'Target|Destino'
```

### 4.3 Cerrar la sesion web de Microsoft (deja el navegador limpio)
```powershell
Start-Process msedge '--inprivate','https://login.microsoftonline.com/logout.srf'
```

### 4.4 Quien ha iniciado sesion en este equipo
```powershell
Get-CimInstance Win32_LoggedOnUser | ForEach-Object { $_.Antecedent } | Select-Object -Unique Domain,Name
```

---

## 5. Intune / MDM

### 5.1 Forzar sincronizacion con Intune
```powershell
Get-ScheduledTask -TaskPath '\Microsoft\Windows\EnterpriseMgmt\*' -TaskName 'PushLaunch' -ErrorAction SilentlyContinue | Start-ScheduledTask; "Sincronizacion lanzada."
```

### 5.2 Errores recientes del agente de Intune
```powershell
Get-Content "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\AppWorkload.log" -Tail 400 | Select-String 'error|failed|0x8' | Select-Object -Last 30
```

### 5.3 Aplicaciones que Intune ha desplegado en este equipo
```powershell
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps' -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^[0-9a-f-]{36}$' } | Select-Object -ExpandProperty PSChildName -Unique
```

---

## 6. Red

### 6.1 Reset completo de pila de red `[ADMIN]`
Requiere reinicio.
```powershell
netsh winsock reset; netsh int ip reset; ipconfig /flushdns; ipconfig /registerdns; "Hecho. Reiniciar el equipo."
```

### 6.2 Renovar IP y DNS
```powershell
ipconfig /release; ipconfig /renew; ipconfig /flushdns
```

### 6.3 Que proceso ocupa un puerto
```powershell
$p=443; Get-NetTCPConnection -LocalPort $p -ErrorAction SilentlyContinue | Select-Object LocalAddress,LocalPort,State,@{n='Proceso';e={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName}}
```

### 6.4 Proxy configurado
```powershell
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' | Select-Object ProxyEnable,ProxyServer,AutoConfigURL; netsh winhttp show proxy
```

---

## 7. Impresion

### 7.1 Reiniciar la cola de impresion `[ADMIN]`
```powershell
Stop-Service spooler -Force; Remove-Item "$env:SystemRoot\System32\spool\PRINTERS\*" -Force -ErrorAction SilentlyContinue; Start-Service spooler; "Cola reiniciada."
```

### 7.2 Impresoras y su estado
```powershell
Get-Printer | Select-Object Name,DriverName,PortName,PrinterStatus | Sort-Object Name | Format-Table -AutoSize
```

---

## 8. Reparacion de Windows

### 8.1 Integridad del sistema `[ADMIN]`
```powershell
Dism.exe /Online /Cleanup-Image /RestoreHealth; sfc /scannow
```

### 8.2 Reiniciar Windows Update `[ADMIN]`
```powershell
Stop-Service wuauserv,bits,cryptsvc -Force; Rename-Item "$env:SystemRoot\SoftwareDistribution" "SoftwareDistribution.old" -ErrorAction SilentlyContinue; Start-Service wuauserv,bits,cryptsvc; "Windows Update reiniciado."
```

### 8.3 Ultimos errores criticos del sistema
```powershell
Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2;StartTime=(Get-Date).AddDays(-7)} -MaxEvents 30 | Select-Object TimeCreated,Id,ProviderName,@{n='Mensaje';e={($_.Message -split "`n")[0]}} | Format-Table -AutoSize
```

### 8.4 Arranques y apagados de los ultimos 7 dias
```powershell
Get-WinEvent -FilterHashtable @{LogName='System';Id=6005,6006,6008,1074;StartTime=(Get-Date).AddDays(-7)} -ErrorAction SilentlyContinue | Select-Object TimeCreated,Id,@{n='Evento';e={switch($_.Id){6005{'Arranque'}6006{'Apagado limpio'}6008{'Apagado inesperado'}1074{'Reinicio solicitado'}}}} | Format-Table -AutoSize
```

---

## 9. Software

### 9.1 Software instalado (rapido, sin Win32_Product)
`Win32_Product` dispara una reconfiguracion de cada MSI. Leer el registro.
```powershell
$k='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'; Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object DisplayName | Select-Object DisplayName,DisplayVersion,Publisher,InstallDate | Sort-Object DisplayName | Format-Table -AutoSize
```

### 9.2 Actualizar todo con winget
```powershell
winget upgrade --all --silent --accept-source-agreements --accept-package-agreements
```

### 9.3 Que se ha instalado esta semana
```powershell
Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='MsiInstaller';StartTime=(Get-Date).AddDays(-7)} -ErrorAction SilentlyContinue | Select-Object TimeCreated,@{n='Mensaje';e={($_.Message -split "`n")[0]}} | Format-Table -AutoSize
```
