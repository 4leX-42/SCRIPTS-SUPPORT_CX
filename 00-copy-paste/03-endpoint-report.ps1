$INFORME = & {
$ErrorActionPreference='SilentlyContinue'
'[INFORME] equipo v1'
"[FECHA] $(Get-Date -Format s)"
"[EQUIPO] $env:COMPUTERNAME"
"[SESION] $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
"[ELEVADO] $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"
'[VENTANA_REQUERIDA] admin'
$cs=Get-CimInstance Win32_ComputerSystem
$bi=Get-CimInstance Win32_BIOS
$os=Get-CimInstance Win32_OperatingSystem
"[HARDWARE] fabricante=$($cs.Manufacturer) modelo=$($cs.Model) serie=$($bi.SerialNumber) ram_gb=$([math]::Round($cs.TotalPhysicalMemory/1GB,1))"
"[CPU] $((Get-CimInstance Win32_Processor).Name -join '; ')"
$cv='Registry::HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$g=Get-ItemProperty $cv
$gen=if([int]$g.CurrentBuild -ge 22000){'Windows 11'}else{'Windows 10'}
"[WINDOWS] generacion=$gen producto_registro=$($g.ProductName) display=$($g.DisplayVersion) build=$($g.CurrentBuild).$($g.UBR) edicion=$($g.EditionID)"
"[ARRANQUE] ultimo=$($os.LastBootUpTime.ToString('s')) uptime_h=$([math]::Round(((Get-Date)-$os.LastBootUpTime).TotalHours,1))"
"[SECUREBOOT] $(Confirm-SecureBootUEFI)"
"[TPM] presente=$((Get-CimInstance -Namespace root\cimv2\security\microsofttpm -Class Win32_Tpm).IsEnabled_InitialValue)"
$ds=dsregcmd /status
foreach($c in 'AzureAdJoined','EnterpriseJoined','DomainJoined','WorkplaceJoined','TenantName','TenantId','DeviceId','AzureAdPrt'){
  $m=$ds | Select-String -Pattern "^\s*$c\s*:\s*(.+)$" | Select-Object -First 1
  if($m){ "[JOIN] $c=$($m.Matches[0].Groups[1].Value.Trim())" }
}
foreach($k in (Get-ChildItem 'Registry::HKLM\SOFTWARE\Microsoft\Enrollments')){
  $e=Get-ItemProperty ('Registry::'+$k.Name)
  if($e.UPN -or $e.ProviderID){ "[MDM] proveedor=$($e.ProviderID) upn=$($e.UPN) estado=$($e.EnrollmentState)" }
}
"[INTUNE_SERVICIO] $((Get-Service IntuneManagementExtension).Status)"
foreach($d in (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')){
  "[DISCO] letra=$($d.DeviceID) total_gb=$([math]::Round($d.Size/1GB,1)) libre_gb=$([math]::Round($d.FreeSpace/1GB,1)) libre_pct=$([math]::Round(($d.FreeSpace/$d.Size)*100,1))"
}
foreach($v in (Get-BitLockerVolume)){ "[BITLOCKER] volumen=$($v.MountPoint) estado=$($v.ProtectionStatus) cifrado_pct=$($v.EncryptionPercentage) metodo=$($v.EncryptionMethod)" }
foreach($n in (Get-NetAdapter | Where-Object{$_.Status -eq 'Up'})){
  $ip=(Get-NetIPAddress -InterfaceIndex $n.ifIndex -AddressFamily IPv4).IPAddress -join ','
  "[RED] nombre=$($n.Name) tipo=$($n.MediaType) velocidad=$($n.LinkSpeed) ip=$ip driver=$($n.DriverVersion)"
}
"[DNS] $((Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object{$_.ServerAddresses}).ServerAddresses -join ',')"
$px=Get-ItemProperty 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
"[PROXY] activo=$($px.ProxyEnable) servidor=$($px.ProxyServer)"
foreach($c in (Get-ChildItem 'Registry::HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration')){}
$c2r=Get-ItemProperty 'Registry::HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
if($c2r){ "[OFFICE] version=$($c2r.VersionToReport) canal=$($c2r.CDNBaseUrl) productos=$($c2r.ProductReleaseIds) plataforma=$($c2r.Platform)" }
"[DEFENDER] servicio=$((Get-Service WinDefend).Status) rtp=$((Get-MpPreference).DisableRealtimeMonitoring)"
foreach($s in @('wuauserv','bits','Spooler','WSearch')){ "[SERVICIO] $s=$((Get-Service $s).Status)" }
'[FIN]'
} | ForEach-Object { "$_" }; $INFORME = $INFORME -join [Environment]::NewLine; $copiado = 'no'; try{ Set-Clipboard -Value $INFORME -ErrorAction Stop; $copiado = 'si' }catch{}; $INFORME; ""; "--- fin del informe. copiado al portapapeles: $copiado. pegar en el chat con Ctrl+V ---"
