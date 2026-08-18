$ErrorActionPreference='SilentlyContinue'
'[INFORME] office-outlook v1'
"[FECHA] $(Get-Date -Format s)"
"[EQUIPO] $env:COMPUTERNAME"
"[SESION] $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
$c2r=Get-ItemProperty 'Registry::HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
if($c2r){ "[OFFICE] version=$($c2r.VersionToReport) productos=$($c2r.ProductReleaseIds) plataforma=$($c2r.Platform) canal=$($c2r.UpdateChannel)" }
foreach($p in 'OUTLOOK','olk','WINWORD','EXCEL','POWERPNT','ONENOTE','ms-teams','Teams','OneDrive'){
  $x=Get-Process $p
  if($x){ "[PROCESO] nombre=$p instancias=$($x.Count) responde=$($x[0].Responding)" }
}
$lic="$env:LOCALAPPDATA\Microsoft\Office\Licenses"
"[LICENCIA_CARPETA] existe=$(Test-Path $lic) ficheros=$((Get-ChildItem $lic -Recurse -File).Count)"
$osp='Registry::HKCU\Software\Microsoft\Office\16.0\Common\Identity'
$oi=Get-ItemProperty $osp
"[IDENTIDAD] adusername=$($oi.ADUserName) signedout=$($oi.SignedOutADUserName)"
foreach($k in (Get-ChildItem "$osp\Identities")){
  $n=Split-Path $k.Name -Leaf
  $g=Get-ItemProperty ('Registry::'+$k.Name.Replace('HKEY_CURRENT_USER','HKCU'))
  "[IDENTIDAD_CACHE] clave=$n email=$($g.EmailAddress) proveedor=$($g.ProviderId) tipo=$($g.IdentityType)"
}
foreach($v in '16.0','15.0') {
  $base="Registry::HKCU\Software\Microsoft\Office\$v\Outlook\Profiles"
  foreach($k in (Get-ChildItem $base)){ "[PERFIL_OUTLOOK] version=$v nombre=$(Split-Path $k.Name -Leaf)" }
}
$dp=Get-ItemProperty 'Registry::HKCU\Software\Microsoft\Office\16.0\Outlook' -Name DefaultProfile
"[PERFIL_DEFECTO] $($dp.DefaultProfile)"
foreach($d in @("$env:LOCALAPPDATA\Microsoft\Outlook","$env:USERPROFILE\Documents\Archivos de Outlook","$env:USERPROFILE\Documents\Outlook Files")){
  foreach($f in (Get-ChildItem $d -Include *.ost,*.pst -File -Recurse)){
    "[FICHERO_DATOS] tipo=$($f.Extension) nombre=$($f.Name) mb=$([math]::Round($f.Length/1MB,0)) modificado=$($f.LastWriteTime.ToString('s'))"
  }
}
foreach($h in 'Registry::HKCU\Software\Microsoft\Office\Outlook\Addins','Registry::HKLM\SOFTWARE\Microsoft\Office\Outlook\Addins','Registry::HKLM\SOFTWARE\WOW6432Node\Microsoft\Office\Outlook\Addins'){
  foreach($k in (Get-ChildItem $h)){
    $g=Get-ItemProperty ('Registry::'+$k.Name)
    "[COMPLEMENTO] ambito=$(if($h -match 'HKCU'){'usuario'}else{'maquina'}) id=$(Split-Path $k.Name -Leaf) nombre=$($g.FriendlyName) carga=$($g.LoadBehavior)"
  }
}
foreach($r in 'DisabledItems','CrashingAddinList','DoNotDisableAddinList'){
  $p="Registry::HKCU\Software\Microsoft\Office\16.0\Outlook\Resiliency\$r"
  if(Test-Path $p){ "[RESILIENCY] lista=$r entradas=$((Get-Item $p).ValueCount)" }
}
foreach($d in @("$env:LOCALAPPDATA\Microsoft\OneAuth","$env:LOCALAPPDATA\Microsoft\IdentityCache","$env:LOCALAPPDATA\Microsoft\TokenBroker\Cache")){
  "[CACHE_TOKEN] ruta=$d existe=$(Test-Path $d) ficheros=$((Get-ChildItem $d -Recurse -File).Count)"
}
foreach($l in (cmdkey /list)){ if($l -match '^\s*(Target|Destino):\s*(.+?)\s*$'){ $t=$Matches[2]; if($t -match '(?i)office|msteams|onedrive|microsoft|login\.windows|SSO_POP'){ "[CREDENCIAL] $t" } } }
foreach($e in (Get-WinEvent -FilterHashtable @{LogName='Application';StartTime=(Get-Date).AddHours(-24)} -MaxEvents 500 | Where-Object{$_.ProviderName -match 'Outlook|Office' -and $_.LevelDisplayName -in 'Error','Warning'})){
  "[EVENTO] fecha=$($e.TimeCreated.ToString('s')) nivel=$($e.LevelDisplayName) id=$($e.Id) proveedor=$($e.ProviderName)"
}
'[FIN]'
