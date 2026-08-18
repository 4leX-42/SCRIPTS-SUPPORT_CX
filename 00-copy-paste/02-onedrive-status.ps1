$ErrorActionPreference='SilentlyContinue'
'[INFORME] estado-onedrive v1'
"[FECHA] $(Get-Date -Format s)"
"[EQUIPO] $env:COMPUTERNAME"
"[SESION] $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
$p=Get-Process OneDrive
"[PROCESO] corriendo=$([bool]$p) responde=$(if($p){$p[0].Responding}else{'na'}) instancias=$(if($p){$p.Count}else{0})"
foreach($c in @("$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe","$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe","${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe")){
  if(Test-Path $c){ $v=(Get-Item $c).VersionInfo.FileVersion; "[BINARIO] ruta=$c version=$v" }
}
"[ENV_ONEDRIVE] $env:OneDrive"
"[ENV_ONEDRIVE_COMMERCIAL] $env:OneDriveCommercial"
foreach($k in (Get-ChildItem 'Registry::HKCU\Software\Microsoft\OneDrive\Accounts')){
  $n=Split-Path $k.Name -Leaf
  $c='Registry::'+$k.Name.Replace('HKEY_CURRENT_USER','HKCU')
  $g=Get-ItemProperty $c
  "[CUENTA] id=$n email=$($g.UserEmail) tenantid=$($g.ConfiguredTenantId) spo=$($g.SPOResourceId) carpeta=$($g.UserFolder) errorlogin=$($g.LastSignInErrorCode)"
}
foreach($b in @($env:OneDrive,$env:OneDriveCommercial)){
  if(-not $b -or -not (Test-Path -LiteralPath $b)){ continue }
  $acl=Get-Acl -LiteralPath $b
  "[ACL_RAIZ] ruta=$b propietario=$($acl.Owner)"
  foreach($a in $acl.Access){ if($a.AccessControlType -eq 'Deny'){ "[ACL_DENY] ruta=$b quien=$($a.IdentityReference) derechos=$($a.FileSystemRights) heredada=$($a.IsInherited)" } }
  $n=0
  foreach($d in (Get-ChildItem -LiteralPath $b -Directory -Recurse -Depth 2)){
    foreach($a in (Get-Acl -LiteralPath $d.FullName).Access){ if($a.AccessControlType -eq 'Deny'){ $n++ } }
  }
  "[ACL_DENY_TOTAL] ruta=$b profundidad=2 denegaciones=$n"
  $t=Join-Path $b ('_p_'+[Guid]::NewGuid().ToString('N').Substring(0,6))
  try{ New-Item $t -ItemType Directory -ErrorAction Stop | Out-Null; Remove-Item $t -Force; "[ESCRITURA] ruta=$b resultado=OK" }
  catch{ "[ESCRITURA] ruta=$b resultado=FALLO detalle=$($_.Exception.Message)" }
}
$ld="$env:LOCALAPPDATA\Microsoft\OneDrive\logs"
foreach($d in (Get-ChildItem $ld -Directory)){
  $u=(Get-ChildItem $d.FullName -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
  if($u){ "[LOG] carpeta=$($d.Name) ultimo=$($u.Name) fecha=$($u.LastWriteTime.ToString('s')) horas_desde=$([math]::Round(((Get-Date)-$u.LastWriteTime).TotalHours,1))" }
}
"[CFA] $((Get-MpPreference).EnableControlledFolderAccess)"
foreach($e in (Get-WinEvent -FilterHashtable @{LogName='Application';StartTime=(Get-Date).AddHours(-24)} -MaxEvents 400 | Where-Object{$_.ProviderName -match 'OneDrive'})){
  "[EVENTO] fecha=$($e.TimeCreated.ToString('s')) nivel=$($e.LevelDisplayName) id=$($e.Id) proveedor=$($e.ProviderName)"
}
'[FIN]'
