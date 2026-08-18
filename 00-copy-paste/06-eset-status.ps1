$INFORME = & {
$ErrorActionPreference='SilentlyContinue'
'[INFORME] estado-eset v1'
"[FECHA] $(Get-Date -Format s)"
"[EQUIPO] $env:COMPUTERNAME"
"[ELEVADO] $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"
'[VENTANA_REQUERIDA] admin'
foreach($h in 'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','Registry::HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'){
  foreach($k in (Get-ChildItem $h)){
    $g=Get-ItemProperty ('Registry::'+$k.Name)
    if($g.DisplayName -match '(?i)eset'){ "[INSTALADO] nombre=$($g.DisplayName) version=$($g.DisplayVersion) editor=$($g.Publisher) ruta=$($g.InstallLocation)" }
  }
}
foreach($s in (Get-Service | Where-Object{$_.Name -match '(?i)ekrn|eset|EraAgent'})){
  "[SERVICIO] nombre=$($s.Name) display=$($s.DisplayName) estado=$($s.Status) inicio=$($s.StartType)"
}
foreach($p in (Get-Process | Where-Object{$_.Name -match '(?i)ekrn|egui|eset|ERAAgent'})){
  "[PROCESO] nombre=$($p.Name) pid=$($p.Id) mb=$([math]::Round($p.WorkingSet64/1MB,1)) responde=$($p.Responding)"
}
foreach($c in @("${env:ProgramFiles}\ESET\RemoteAdministrator\Agent\ERAAgent.exe","${env:ProgramFiles(x86)}\ESET\RemoteAdministrator\Agent\ERAAgent.exe","${env:ProgramFiles}\ESET\ESET Security\ekrn.exe")){
  if(Test-Path $c){
    $i=Get-Item $c
    $sig=Get-AuthenticodeSignature $c
    "[BINARIO] ruta=$c version=$($i.VersionInfo.FileVersion) firma=$($sig.Status) firmante=$($sig.SignerCertificate.Subject -replace '.*?CN=([^,]+).*','$1')"
  }
}
$logs=@("${env:ProgramData}\ESET\RemoteAdministrator\Agent\EraAgentApplicationData\Logs\trace.log","${env:ProgramData}\ESET\RemoteAdministrator\Agent\Logs\trace.log")
foreach($l in $logs){
  if(-not (Test-Path $l)){ continue }
  $i=Get-Item $l
  "[TRACE] ruta=$l mb=$([math]::Round($i.Length/1MB,2)) modificado=$($i.LastWriteTime.ToString('s')) horas_desde=$([math]::Round(((Get-Date)-$i.LastWriteTime).TotalHours,1))"
  $t=Get-Content $l -Tail 400
  $enr=$t | Select-String -Pattern 'enrol|Enrol' | Select-Object -Last 1
  if($enr){ "[TRACE_ENROLAMIENTO] $($enr.Line.Trim())" }
  foreach($e in ($t | Select-String -Pattern 'Error|Failed|Cannot connect' | Select-Object -Last 5)){ "[TRACE_ERROR] $($e.Line.Trim())" }
}
$cfg="${env:ProgramData}\ESET\RemoteAdministrator\Agent\EraAgentApplicationData\Configuration\last_configuration.xml"
if(Test-Path $cfg){
  $x=Get-Content $cfg -Raw
  if($x -match '<Hostname>([^<]+)</Hostname>'){ "[SERVIDOR_ECA] $($Matches[1])" }
  if($x -match '<Port>([^<]+)</Port>'){ "[PUERTO_ECA] $($Matches[1])" }
}
foreach($h in 'epns.eset.com','eca.eset.com','repository.eset.com'){
  $dns='FALLO'; $ip='-'
  try{ $r=Resolve-DnsName $h -Type A -ErrorAction Stop; $dns='OK'; $ip=($r | Where-Object{$_.IPAddress} | Select-Object -First 2 -ExpandProperty IPAddress) -join ',' }catch{}
  $tcp='FALLO'
  if($dns -eq 'OK'){ $c=New-Object Net.Sockets.TcpClient; if($c.ConnectAsync($h,443).Wait(5000)){$tcp='OK'}; $c.Close() }
  "[CONECTIVIDAD] host=$h dns=$dns ip=$ip tcp443=$tcp"
}
"[DEFENDER] servicio=$((Get-Service WinDefend).Status) rtp_desactivado=$((Get-MpPreference).DisableRealtimeMonitoring)"
foreach($a in (Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct)){
  "[ANTIVIRUS_REGISTRADO] nombre=$($a.displayName) estado=$($a.productState) ruta=$($a.pathToSignedProductExe)"
}
'[FIN]'
} | ForEach-Object { "$_" }; $INFORME = $INFORME -join [Environment]::NewLine; $copiado = 'no'; try{ Set-Clipboard -Value $INFORME -ErrorAction Stop; $copiado = 'si' }catch{}; $INFORME; ""; "--- fin del informe. copiado al portapapeles: $copiado. pegar en el chat con Ctrl+V ---"
