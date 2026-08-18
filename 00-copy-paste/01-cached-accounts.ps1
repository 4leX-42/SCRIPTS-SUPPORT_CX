$ErrorActionPreference='SilentlyContinue'
$RX='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,63}'
$H=@{}
function A($u,$f){ if($u -and $u -match "^$RX$"){ $k=$u.ToLower(); if(-not $H[$k]){$H[$k]=New-Object System.Collections.ArrayList}; if($H[$k] -notcontains $f){[void]$H[$k].Add($f)} } }
'[INFORME] cuentas-cacheadas v1'
"[FECHA] $(Get-Date -Format s)"
"[EQUIPO] $env:COMPUTERNAME"
"[SESION] $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
"[PERFIL] $env:USERPROFILE"
$el=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
"[ELEVADO] $el"
$ex=Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | Select-Object -First 1
if($ex){ $o=Invoke-CimMethod -InputObject $ex -MethodName GetOwner; "[DUENO_SESION] $($o.Domain)\$($o.User)" }
foreach($k in (Get-ChildItem 'Registry::HKCU\Software\Microsoft\Office\16.0\Common\Identity\Identities')){
  $n=Split-Path $k.Name -Leaf
  A ($n -replace '_(?=[^_]+\.[^_]+$)','@') 'OfficeIdentities'
  foreach($v in 'EmailAddress','SignInName','FriendlyName'){ A (Get-ItemProperty ('Registry::'+$k.Name.Replace('HKEY_CURRENT_USER','HKCU')) -Name $v).$v 'OfficeIdentities' }
}
foreach($v in 'ADUserName','SignedOutADUserName'){ A (Get-ItemProperty 'Registry::HKCU\Software\Microsoft\Office\16.0\Common\Identity' -Name $v).$v 'OfficeIdentity' }
foreach($k in (Get-ChildItem 'Registry::HKCU\Software\Microsoft\IdentityCRL\UserExtendedProperties')){ A (Split-Path $k.Name -Leaf) 'IdentityCRL' }
foreach($k in (Get-ChildItem 'Registry::HKCU\Software\Microsoft\OneDrive\Accounts')){
  $c='Registry::'+$k.Name.Replace('HKEY_CURRENT_USER','HKCU')
  A (Get-ItemProperty $c -Name UserEmail).UserEmail "OneDrive:$(Split-Path $k.Name -Leaf)"
  $t=(Get-ItemProperty $c -Name ConfiguredTenantId).ConfiguredTenantId
  $s=(Get-ItemProperty $c -Name SPOResourceId).SPOResourceId
  if($t){ "[ONEDRIVE] cuenta=$(Split-Path $k.Name -Leaf) tenantid=$t spo=$s" }
}
foreach($l in (cmdkey /list)){ if($l -match "($RX)"){ A $Matches[1] 'CredentialManager' } }
$wam="$env:LOCALAPPDATA\Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy\AC\TokenBroker\Accounts"
foreach($f in (Get-ChildItem $wam -File)){
  $b=[IO.File]::ReadAllBytes($f.FullName)
  $s=[Text.Encoding]::Unicode.GetString($b)+[Text.Encoding]::UTF8.GetString($b)
  foreach($m in [regex]::Matches($s,$RX)){ A $m.Value 'WAM' }
}
$ds=dsregcmd /status
foreach($c in 'AzureAdJoined','EnterpriseJoined','DomainJoined','WorkplaceJoined','TenantId','TenantName','UserPrincipalName'){
  $m=$ds | Select-String -Pattern "^\s*$c\s*:\s*(.+)$" | Select-Object -First 1
  if($m){ "[DSREG] $c=$($m.Matches[0].Groups[1].Value.Trim())" }
}
$doms=New-Object System.Collections.ArrayList
foreach($k in ($H.Keys | Sort-Object)){
  $loc=$k.Split('@')[0]; $dom=$k.Split('@')[1]
  $g=if($loc -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'){'si'}else{'no'}
  "[CUENTA] upn=$k dominio=$dom guid_zombie=$g fuentes=$($H[$k] -join ';')"
  if($doms -notcontains $dom){[void]$doms.Add($dom)}
}
try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072}catch{}
foreach($d in $doms){
  $tid='?'; $marca='?'; $tipo='?'; $vivo='no'
  try{ $oid=Invoke-RestMethod "https://login.microsoftonline.com/$d/v2.0/.well-known/openid-configuration" -TimeoutSec 12; $vivo='si'; if($oid.issuer -match '([0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12})'){$tid=$Matches[1]} }catch{}
  try{ $rl=Invoke-RestMethod "https://login.microsoftonline.com/getuserrealm.srf?login=probe@$d&json=1" -TimeoutSec 12; $marca=$rl.FederationBrandName; $tipo=$rl.NameSpaceType }catch{}
  "[DOMINIO] $d vivo=$vivo tenantid=$tid marca=$marca tipo=$tipo"
}
'[FIN]'
