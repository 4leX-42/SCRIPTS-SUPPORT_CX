$INFORME = & {
$ErrorActionPreference='SilentlyContinue'
'[INFORME] conectividad-m365 v1'
"[FECHA] $(Get-Date -Format s)"
"[EQUIPO] $env:COMPUTERNAME"
"[ELEVADO] $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"
'[VENTANA_REQUERIDA] usuario'
$px=Get-ItemProperty 'Registry::HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
"[PROXY] activo=$($px.ProxyEnable) servidor=$($px.ProxyServer) pac=$($px.AutoConfigURL)"
"[PROXY_WINHTTP] $((netsh winhttp show proxy) -join ' ' -replace '\s+',' ')"
"[DNS_SERVIDORES] $((Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object{$_.ServerAddresses}).ServerAddresses -join ',')"
foreach($h in 'login.microsoftonline.com','outlook.office365.com','graph.microsoft.com','teams.microsoft.com','onedrive.live.com','sharepoint.com','autodiscover-s.outlook.com'){
  $ip='-'; $dns='FALLO'
  try{ $r=Resolve-DnsName $h -Type A -ErrorAction Stop; $ip=($r | Where-Object{$_.IPAddress} | Select-Object -First 3 -ExpandProperty IPAddress) -join ','; $dns='OK' }catch{}
  $tcp='FALLO'; $ms='-'
  if($dns -eq 'OK'){
    $sw=[Diagnostics.Stopwatch]::StartNew()
    $t=Test-NetConnection -ComputerName $h -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
    if($null -eq $t){ $c=New-Object Net.Sockets.TcpClient; $t=$c.ConnectAsync($h,443).Wait(5000); $c.Close() }
    $sw.Stop()
    if($t){ $tcp='OK'; $ms=$sw.ElapsedMilliseconds }
  }
  "[ENDPOINT] host=$h dns=$dns ip=$ip tcp443=$tcp ms=$ms"
}
foreach($h in 'login.microsoftonline.com','outlook.office365.com'){
  try{
    $c=New-Object Net.Sockets.TcpClient($h,443)
    $s=New-Object Net.Security.SslStream($c.GetStream(),$false,{$true})
    $s.AuthenticateAsClient($h)
    "[TLS] host=$h protocolo=$($s.SslProtocol) cifrado=$($s.CipherAlgorithm) emisor=$($s.RemoteCertificate.Issuer)"
    $s.Close(); $c.Close()
  }catch{ "[TLS] host=$h resultado=FALLO detalle=$($_.Exception.Message)" }
}
try{
  $sw=[Diagnostics.Stopwatch]::StartNew()
  $rl=Invoke-RestMethod 'https://login.microsoftonline.com/getuserrealm.srf?login=probe@microsoft.com&json=1' -TimeoutSec 15
  $sw.Stop()
  "[HTTPS] getuserrealm=OK ms=$($sw.ElapsedMilliseconds)"
}catch{ "[HTTPS] getuserrealm=FALLO detalle=$($_.Exception.Message)" }
foreach($h in 'login.microsoftonline.com','outlook.office365.com'){
  $p=Test-Connection $h -Count 2 -ErrorAction SilentlyContinue
  if($p){ "[ICMP] host=$h ms_medio=$([math]::Round(($p | Measure-Object -Property ResponseTime -Average).Average,0))" }
  else{ "[ICMP] host=$h resultado=sin_respuesta" }
}
"[RUTA_DEFECTO] $((Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Select-Object -First 1).NextHop)"
"[MTU] $((Get-NetIPInterface -AddressFamily IPv4 | Where-Object{$_.ConnectionState -eq 'Connected'} | Select-Object -First 1).NlMtu)"
'[FIN]'
} | ForEach-Object { "$_" }; $INFORME = $INFORME -join [Environment]::NewLine; $copiado = 'no'; try{ Set-Clipboard -Value $INFORME -ErrorAction Stop; $copiado = 'si' }catch{}; $INFORME; ""; "--- fin del informe. copiado al portapapeles: $copiado. pegar en el chat con Ctrl+V ---"
