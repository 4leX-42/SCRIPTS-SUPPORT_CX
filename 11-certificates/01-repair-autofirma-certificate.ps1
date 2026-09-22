#Requires -Version 5.1

<#
.SYNOPSIS
    [ES] Repara un certificado concreto que AutoFirma no lista, sin tocar el resto del almacen.
    [EN] Repairs one specific certificate AutoFirma cannot list, leaving the rest of the store untouched.

.DESCRIPTION
    [ES]
    AutoFirma accede al almacen de Windows mediante SunMSCAPI, que solo admite claves
    CryptoAPI legacy (CSP). Un certificado cuya clave quedo en CNG, o cuyo contenedor de
    clave esta roto, se ve en certmgr.msc pero no aparece en el selector de AutoFirma.

    El modo Diag inventaria el almacen Personal y clasifica cada clave por proveedor. El
    modo Fix abre el PKCS#12 indicado, toma la huella del certificado que contiene y actua
    solo sobre esa entrada: primero reimporta encima forzando un CSP legacy, sin borrar
    nada, y unicamente si eso no corrige el proveedor pide confirmacion para eliminar esa
    entrada concreta y volver a importar. Ningun otro certificado del almacen se toca.

    El modo ResetPrefs borra las preferencias de AutoFirma del usuario, que es donde viven
    los filtros del selector capaces de ocultar un certificado de representante.

    [EN]
    AutoFirma reaches the Windows store through SunMSCAPI, which only supports legacy
    CryptoAPI (CSP) keys. A certificate whose key ended up under CNG, or whose key
    container is broken, shows in certmgr.msc but never in AutoFirma's picker.

    Diag mode inventories the Personal store and classifies every key by provider. Fix mode
    opens the given PKCS#12, takes the thumbprint of the certificate inside and acts on
    that entry alone: it first reimports over it forcing a legacy CSP without deleting
    anything, and only if the provider is still wrong does it ask before removing that one
    entry and importing again. No other certificate in the store is touched.

    ResetPrefs clears the user's AutoFirma preferences, where the picker filters that can
    hide a representative certificate are stored.

.PARAMETER Mode
    [ES] Diag (inventario y comprobaciones), Fix (reparacion), ResetPrefs (preferencias).
    [EN] Diag (inventory and checks), Fix (repair), ResetPrefs (preferences).

.PARAMETER P12
    [ES] Ruta del fichero .p12 o .pfx. Obligatorio en modo Fix.
    [EN] Path to the .p12 or .pfx file. Required in Fix mode.

.PARAMETER Password
    [ES] Contrasena del fichero. Si se omite se pide por consola sin mostrarla.
    [EN] File password. Prompted without echo when omitted.

.PARAMETER Thumbprint
    [ES] Huella del certificado a reparar. Por defecto se toma la del fichero.
    [EN] Thumbprint of the certificate to repair. Defaults to the one inside the file.

.PARAMETER Match
    [ES] Expresion regular aplicada al asunto y al nombre descriptivo en modo Diag.
    [EN] Regular expression matched against subject and friendly name in Diag mode.

.PARAMETER DryRun
    [ES] Enumera lo que se haria y no modifica nada.
    [EN] Lists what would be done and changes nothing.

.PARAMETER Force
    [ES] Omite las confirmaciones interactivas.
    [EN] Skips interactive confirmations.

.PARAMETER Log
    [ES] Guarda un informe de la ejecucion en el Escritorio.
    [EN] Saves an execution report on the Desktop.

.EXAMPLE
    .\01-repair-autofirma-certificate.ps1 -Mode Diag -Log

.EXAMPLE
    .\01-repair-autofirma-certificate.ps1 -Mode Fix -P12 "C:\temp\cert.p12" -DryRun

.NOTES
    PowerShell 5.1 y 7. Sesion del usuario afectado, sin elevar: el almacen Personal del
    administrador es otro distinto.
#>
[CmdletBinding()]
param(
  [ValidateSet('Diag','Fix','ResetPrefs')][string]$Mode = 'Diag',
  [string]$P12,
  [string]$Password,
  [string]$Match = '.',
  [string]$Thumbprint,
  [switch]$DryRun,
  [switch]$Force,
  [switch]$Log
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = '2.0'
$LogFile = $null
if($Log){
  $LogFile = Join-Path ([Environment]::GetFolderPath('Desktop')) ('AutoFirma-Diag-{0}-{1:yyyyMMdd-HHmmss}.txt' -f $env:USERNAME,(Get-Date))
  try { Start-Transcript -Path $LogFile -Force | Out-Null } catch { $LogFile = $null }
}
$CSPList = @(
  'Microsoft Enhanced RSA and AES Cryptographic Provider',
  'Microsoft Enhanced Cryptographic Provider v1.0',
  'Microsoft Base Cryptographic Provider v1.0'
)
$PrefKey    = 'HKCU:\Software\JavaSoft\Prefs\es\gob\afirma'
$PrefKeyReg = 'HKCU\Software\JavaSoft\Prefs\es\gob\afirma'
$BackupDir  = Join-Path $env:LOCALAPPDATA ('AutoFirmaFix\{0:yyyyMMdd-HHmmss}' -f (Get-Date))

function Head($t){ Write-Host ''; Write-Host ("== " + $t) -ForegroundColor Cyan }
function Ok($t)  { Write-Host ("  [OK]    " + $t) -ForegroundColor Green }
function Bad($t) { Write-Host ("  [ERROR] " + $t) -ForegroundColor Red }
function Warn($t){ Write-Host ("  [AVISO] " + $t) -ForegroundColor Yellow }
function Info($t){ Write-Host ("  " + $t) -ForegroundColor Gray }

function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Decode-JavaPref([string]$n){
  [regex]::Replace($n, '/([a-z])', { param($m) $m.Groups[1].Value.ToUpper() })
}

function Get-ProviderName($cert,[string]$Location){
  $cargs = @()
  if($Location -ne 'LocalMachine'){ $cargs += '-user' }
  $cargs += @('-store','My',$cert.Thumbprint)
  try{ $out = & certutil.exe @cargs 2>&1 | Out-String } catch { return $null }
  $m = [regex]::Match($out,'(?im)^\s*(?:Provider|Proveedor)\s*=\s*(.+)$')
  if($m.Success){ return $m.Groups[1].Value.Trim() }
  return $null
}

function Resolve-Kind([string]$prov){
  if($prov -match 'Key Storage Provider|almacenamiento de claves'){ return 'CNG' }
  if($prov -match 'Smart Card|tarjeta inteligente'){ return 'TOKEN' }
  return 'CSP'
}

function Get-KeyInfo($cert,[string]$Location='CurrentUser'){
  if(-not $cert.HasPrivateKey){ return [pscustomobject]@{ Kind='NOKEY'; Provider='(sin clave privada)' } }
  $prov = $null
  try{
    $k = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
    if($k){
      if($k.GetType().Name -eq 'RSACng'){ $prov = $k.Key.Provider.Provider }
      else{ $prov = $k.CspKeyContainerInfo.ProviderName }
    }
  } catch {}
  if(-not $prov){ $prov = Get-ProviderName $cert $Location }
  if($prov){ return [pscustomobject]@{ Kind=(Resolve-Kind $prov); Provider=$prov } }
  return [pscustomobject]@{ Kind='NOACCESS'; Provider='(clave registrada pero no accesible)' }
}

function Test-CaCert($cert){
  foreach($e in $cert.Extensions){
    if($e.Oid.Value -eq '2.5.29.19'){
      $bc = New-Object System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension
      $bc.CopyFrom($e)
      return $bc.CertificateAuthority
    }
  }
  return $false
}

function Find-Certs([string]$Location){
  $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('My',$Location)
  try{
    $store.Open('ReadOnly')
    @($store.Certificates | Where-Object {
      ($_.Subject -match $Match -or $_.FriendlyName -match $Match) -and -not (Test-CaCert $_)
    })
  } finally { $store.Close() }
}

function Show-Cert($c,[string]$Location){
  $ki   = Get-KeyInfo $c $Location
  $days = [int]([datetime]$c.NotAfter - (Get-Date)).TotalDays
  Info ("Ubicacion   : " + $Location + "\My")
  Info ("Asunto      : " + $c.Subject)
  Info ("Emisor      : " + $c.Issuer)
  Info ("Serie       : " + $c.SerialNumber)
  Info ("Huella      : " + $c.Thumbprint)
  Info ("Valido hasta: " + $c.NotAfter + "  (" + $days + " dias)")
  if($days -lt 0){ Bad "Certificado caducado. AutoFirma lo oculta salvo que se desactive el filtro." }

  $eku = @($c.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.37' })
  if($eku.Count){
    $usos = @($eku[0].EnhancedKeyUsages | ForEach-Object { $_.FriendlyName })
    Info ("EKU         : " + ($usos -join ', '))
  }

  switch($ki.Kind){
    'CSP'      { Ok  ("Proveedor   : CSP legacy -> " + $ki.Provider + "  (compatible con AutoFirma)") }
    'CNG'      { Bad ("Proveedor   : CNG/KSP -> " + $ki.Provider + "  (no compatible con AutoFirma). Requiere -Mode Fix") }
    'NOKEY'    { Bad  "Proveedor   : sin clave privada asociada. Reimportar el PKCS#12 con -Mode Fix" }
    'TOKEN'    { Ok  ("Proveedor   : tarjeta o token -> " + $ki.Provider + "  (compatible con AutoFirma)") }
    'NOACCESS' { Bad  "Proveedor   : clave registrada pero ilegible. Contenedor huerfano o perteneciente a otro perfil. Requiere -Mode Fix" }
    default    { Bad ("Proveedor   : " + $ki.Provider) }
  }

  $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
  $chain.ChainPolicy.RevocationMode = 'NoCheck'
  $built = $chain.Build($c)
  if($built){ Ok "Cadena      : completa y de confianza" }
  else{
    Warn "Cadena      : incompleta o no confiable"
    foreach($s in $chain.ChainStatus){ Info ("  - " + $s.Status + ": " + $s.StatusInformation.Trim()) }
    Info "  Falta instalar las CA intermedias de la entidad emisora."
  }
  Write-Host ''
}

function Invoke-Diag {
  Head "Contexto"
  Info ("Version : " + $ScriptVersion)
  Info ("Usuario : " + $env:USERDOMAIN + "\" + $env:USERNAME)
  Info ("Equipo  : " + $env:COMPUTERNAME)
  if(Test-Admin){ Warn "Sesion elevada: el almacen CurrentUser es el del administrador, no el del usuario. Reejecutar sin elevacion." }
  else{ Ok "Sesion de usuario sin elevacion" }

  Head "AutoFirma"
  $af = @(
    (Join-Path $env:ProgramFiles 'AutoFirma\AutoFirma\AutoFirma.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'AutoFirma\AutoFirma\AutoFirma.exe'),
    (Join-Path $env:LOCALAPPDATA 'AutoFirma\AutoFirma\AutoFirma.exe')
  ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
  if($af){
    Ok ("Instalado: " + $af)
    Info ("Version  : " + (Get-Item $af).VersionInfo.ProductVersion)
  } else { Bad "AutoFirma.exe no encontrado en rutas estandar" }

  $proc = @(Get-Process -Name AutoFirma,javaw,java -ErrorAction SilentlyContinue)
  if($proc.Count){
    Warn ("Procesos abiertos: " + (($proc | ForEach-Object { $_.ProcessName + "/" + $_.Id }) -join ', ') + ". Cerrarlos antes de repetir la prueba.")
  }

  Head ("Certificados de usuario que coinciden con '" + $Match + "'")
  $found = 0
  foreach($loc in 'CurrentUser','LocalMachine'){
    $certs = @()
    try { $certs = Find-Certs $loc } catch { Warn ("No se pudo leer " + $loc + ": " + $_.Exception.Message) }
    foreach($c in $certs){ $found++; Show-Cert $c $loc }
  }
  if($found -eq 0){
    Bad ("Ningun certificado coincide con '" + $Match + "' en Personal.")
    Info "Ajustar el filtro con -Match o comprobar si la importacion se hizo en otro perfil de usuario."
  }

  Head "Inventario completo del almacen Personal"
  foreach($loc in 'CurrentUser','LocalMachine'){
    $all = @()
    try{
      $st = New-Object System.Security.Cryptography.X509Certificates.X509Store('My',$loc)
      $st.Open('ReadOnly'); $all = @($st.Certificates); $st.Close()
    } catch { Warn ("No se pudo leer " + $loc + ": " + $_.Exception.Message) }
    Info ($loc + "\My  ->  " + $all.Count + " certificado(s)")
    foreach($c in $all){
      $ki = Get-KeyInfo $c $loc
      $cn = ($c.Subject -split ',' | Where-Object { $_ -match 'CN=' } | Select-Object -First 1)
      if(-not $cn){ $cn = $c.Subject }
      $tag = if(Test-CaCert $c){ 'CA' } else { $ki.Kind }
      Info ("   [" + $tag + "] " + $cn.Trim() + "  | caduca " + $c.NotAfter.ToString('yyyy-MM-dd') + " | " + $c.Thumbprint)
    }
  }
  Info "CSP: compatible con AutoFirma. CNG: no compatible. NOKEY: sin clave privada."
  Info "CA: certificado de entidad emisora, no utilizable para firmar."
  Info "TOKEN: clave en tarjeta o dispositivo criptografico."
  Info "NOACCESS: clave registrada en el almacen pero ilegible."

  Head "Almacen de Firefox/Mozilla"
  $ffProfiles = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
  if(Test-Path $ffProfiles){
    Info "Perfiles de Firefox presentes. Con el almacen de Mozilla seleccionado"
    Info "AutoFirma no lista los certificados de Windows. Debe usar 'Almacen de Windows'."
  } else { Ok "Sin perfiles de Firefox" }

  Head "Preferencias de AutoFirma (registro)"
  if(Test-Path $PrefKey){
    Get-ChildItem $PrefKey -Recurse | ForEach-Object {
      $props = Get-ItemProperty $_.PSPath
      $names = @($props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })
      if($names.Count){
        Info ($_.Name -replace '^.*JavaSoft\\Prefs\\','')
        foreach($n in $names){ Info ("    " + (Decode-JavaPref $n.Name) + " = " + $n.Value) }
      }
    }
    $sel = 'HKCU:\Software\JavaSoft\Prefs\es\gob\afirma\ui\core\jse\certificateselection'
    if(Test-Path $sel){
      $cv = (Get-ItemProperty $sel).'cert/View'
      if($cv){
        $cvDec = ($cv -replace '/','')
        if($cvDec -ne 'TODOS'){
          Warn ("Filtro del selector: certView = " + $cvDec)
          Info "  Los certificados de representante o seudonimo pueden quedar ocultos."
          Info "  Seleccionar la vista 'Todos' en el dialogo de firma, o eliminar el valor:"
          Info ("  Remove-ItemProperty '" + $sel + "' -Name 'cert/View'")
        }
      }
    }
    Info ''
    Info "Verificar en AutoFirma: almacen por defecto = Almacen de Windows y filtros"
    Info "'ocultar caducados' y 'solo certificados de firma' desactivados."
    Info "Restablecer configuracion:  .\Repair-AutoFirmaCert.ps1 -Mode ResetPrefs"
  } else {
    Info "Sin preferencias guardadas (AutoFirma usara los valores por defecto)."
  }

  Head "Accion recomendada"
  Info "Certificados marcados como CNG, NOKEY o NOACCESS:"
  Info '  .\Repair-AutoFirmaCert.ps1 -Mode Fix -P12 "C:\ruta\cert.p12"'
}

function Read-P12Password([string]$Path){
  Read-Host ("Contrasena de " + (Split-Path $Path -Leaf)) -AsSecureString
}

function ConvertTo-Plain($sec){
  $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

function Get-P12Leaf([string]$Path,[string]$Plain){
  $col = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
  $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
  $col.Import($Path,$Plain,$flags)
  $leaf = @($col | Where-Object { -not (Test-CaCert $_) })
  if($leaf.Count -eq 0){ $leaf = @($col) }
  return $leaf
}

function Get-StoreCert([string]$Thumb,[string]$Location){
  $st = New-Object System.Security.Cryptography.X509Certificates.X509Store('My',$Location)
  try{
    $st.Open('ReadOnly')
    @($st.Certificates | Where-Object { $_.Thumbprint -eq $Thumb }) | Select-Object -First 1
  } finally { $st.Close() }
}

function Remove-StoreCert($cert,[string]$Location){
  $st = New-Object System.Security.Cryptography.X509Certificates.X509Store('My',$Location)
  try{
    $st.Open('ReadWrite')
    $st.Remove($cert)
    $true
  } catch {
    Bad ("No se pudo eliminar de " + $Location + ": " + $_.Exception.Message)
    $false
  } finally { $st.Close() }
}

function Import-P12([string]$Path,[string]$Plain){
  foreach($csp in $CSPList){
    Info ("Proveedor: " + $csp)
    $cargs = @('-user','-f')
    if($Plain){ $cargs += @('-p',$Plain) }
    $cargs += @('-csp',$csp,'-importpfx','My',$Path,'NoExport')
    & certutil.exe @cargs | Out-Null
    if($LASTEXITCODE -eq 0){ Ok ("Importado con " + $csp); return $csp }
    Warn ("Error " + $LASTEXITCODE + " con ese proveedor, se prueba el siguiente")
  }
  return $null
}

function Invoke-Fix {
  Head ("Reparacion de certificado - version " + $ScriptVersion)
  Info "Actua solo sobre el certificado contenido en el fichero indicado."
  if(-not $P12){ throw "Falta -P12 con la ruta al fichero .p12 o .pfx" }
  if(-not (Test-Path -LiteralPath $P12)){ throw ("No existe el fichero: " + $P12) }
  if(Test-Admin){ Warn "Sesion elevada: la importacion se realizara en el perfil del administrador." }

  $plain = if($Password){ $Password } else { ConvertTo-Plain (Read-P12Password $P12) }
  $leaf = $null
  try { $leaf = Get-P12Leaf $P12 $plain }
  catch { throw "No se pudo abrir el fichero. Contrasena incorrecta o fichero danado." }

  Head "Contenido del fichero"
  foreach($l in $leaf){
    Info ("Asunto : " + $l.Subject)
    Info ("Huella : " + $l.Thumbprint)
  }

  $targets = @($leaf | ForEach-Object { $_.Thumbprint })
  if($Thumbprint){ $targets = @($Thumbprint.Replace(' ','').ToUpper()) }

  Head "Certificados afectados en el almacen Personal"
  $victims = @()
  foreach($t in $targets){
    foreach($loc in 'CurrentUser','LocalMachine'){
      $c = Get-StoreCert $t $loc
      if($c){ $victims += [pscustomobject]@{ Cert=$c; Location=$loc } }
    }
  }
  if($victims.Count -eq 0){ Info "Ninguno. Solo se importara el fichero." }
  foreach($v in $victims){ Info ($v.Location + "  " + $v.Cert.Thumbprint + "  " + $v.Cert.Subject) }
  Info ""
  Info "Ningun otro certificado del almacen se toca."

  if($DryRun){
    Head "Simulacion"
    Info "Acciones que se realizarian:"
    Info ("  1. Copia de seguridad de las entradas listadas en " + $BackupDir)
    Info "  2. Cierre de AutoFirma y de los procesos java asociados."
    Info "  3. certutil -importpfx sobre la entrada existente forzando un CSP legacy."
    Info "  4. Solo si el proveedor siguiera siendo incorrecto, eliminacion de esas"
    Info "     entradas y nueva importacion, previa confirmacion."
    Info "Nada se ha modificado."
    return
  }

  New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
  Info ("Copia de seguridad: " + $BackupDir)
  foreach($v in $victims){
    $cerFile = Join-Path $BackupDir ($v.Location + '-' + $v.Cert.Thumbprint + '.cer')
    [IO.File]::WriteAllBytes($cerFile, $v.Cert.RawData)
  }
  if(Test-Path $PrefKey){
    & reg.exe export $PrefKeyReg (Join-Path $BackupDir 'autofirma-prefs.reg') /y | Out-Null
  }

  Head "Cerrando AutoFirma"
  $proc = @(Get-Process -Name AutoFirma,javaw,java -ErrorAction SilentlyContinue)
  if($proc.Count -eq 0){ Info "Sin procesos abiertos." }
  foreach($pr in $proc){
    Info ("Cerrando " + $pr.ProcessName + "/" + $pr.Id)
    try { Stop-Process -Id $pr.Id -Force -ErrorAction Stop } catch { Warn ("No se pudo cerrar " + $pr.Id) }
  }

  Head "Reimportacion sobre la entrada existente"
  Info "Primer intento sin eliminar nada del almacen."
  $csp = Import-P12 $P12 $plain
  if(-not $csp){ throw "certutil no pudo importar el fichero con ningun proveedor legacy." }

  $okNow = $true
  foreach($t in $targets){
    $c = Get-StoreCert $t 'CurrentUser'
    if(-not $c){ $okNow = $false; continue }
    $ki = Get-KeyInfo $c 'CurrentUser'
    if($ki.Kind -ne 'CSP' -and $ki.Kind -ne 'TOKEN'){ $okNow = $false }
  }

  if(-not $okNow -and $victims.Count -gt 0){
    Head "La reimportacion no corrigio el proveedor"
    Info "Segundo intento: eliminar unicamente las entradas listadas arriba y reimportar."
    foreach($v in $victims){ Info ($v.Location + "  " + $v.Cert.Thumbprint) }
    $go = $Force
    if(-not $go){
      $r = Read-Host "Eliminar esas entradas y reimportar? (s/N)"
      $go = ($r -match '^[sSyY]$')
    }
    if($go){
      foreach($v in $victims){
        if(Remove-StoreCert $v.Cert $v.Location){ Ok ("Eliminado de " + $v.Location + ": " + $v.Cert.Thumbprint) }
        elseif($v.Location -eq 'LocalMachine'){ Info "  LocalMachine requiere elevacion. Eliminar con certlm.msc." }
        else{ Info "  Entrada protegida. Posible itinerancia de credenciales de Active Directory." }
      }
      $csp = Import-P12 $P12 $plain
      if(-not $csp){ throw "certutil no pudo reimportar el fichero." }
    } else { Info "Cancelado. No se elimino nada." }
  }

  Head "Verificacion"
  foreach($t in $targets){
    $c = Get-StoreCert $t 'CurrentUser'
    if(-not $c){ Bad ("El certificado " + $t + " no esta en CurrentUser\My tras la importacion."); continue }
    Show-Cert $c 'CurrentUser'
    $ki = Get-KeyInfo $c 'CurrentUser'
    if($ki.Kind -eq 'CSP' -or $ki.Kind -eq 'TOKEN'){
      Ok "Clave accesible mediante CryptoAPI legacy."
      Info "Comprobar en AutoFirma: Herramientas > Preferencias > Almacen de claves = Almacen de Windows."
    } else {
      Bad ("Proveedor tras la reparacion: " + $ki.Kind + " -> " + $ki.Provider)
    }
  }
}

function Invoke-ResetPrefs {
  if(-not (Test-Path $PrefKey)){ Info "No existen preferencias de AutoFirma para este usuario."; return }
  if($DryRun){
    Info ("Se exportaria " + $PrefKeyReg + " a " + $BackupDir + " y despues se eliminaria la clave.")
    Info "Nada se ha modificado."
    return
  }
  New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
  $bak = Join-Path $BackupDir 'autofirma-prefs.reg'
  & reg.exe export $PrefKeyReg $bak /y | Out-Null
  Ok ("Backup guardado en: " + $bak)
  if(-not $Force){
    $r = Read-Host "Borrar las preferencias de AutoFirma de este usuario? (s/N)"
    if($r -notmatch '^[sSyY]$'){ Info "Cancelado."; return }
  }
  Get-Process -Name AutoFirma,javaw,java -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Remove-Item $PrefKey -Recurse -Force
  Ok "Preferencias eliminadas. AutoFirma las regenera al iniciarse."
}

try{
  switch($Mode){
    'Diag'       { Invoke-Diag }
    'Fix'        { Invoke-Fix }
    'ResetPrefs' { Invoke-ResetPrefs }
  }
} finally {
  if($LogFile){
    try { Stop-Transcript | Out-Null } catch {}
    Write-Host ''
    Write-Host ("Informe guardado en: " + $LogFile) -ForegroundColor Cyan
  }
}
