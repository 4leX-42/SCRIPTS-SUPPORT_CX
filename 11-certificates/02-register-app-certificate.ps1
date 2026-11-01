#Requires -Version 5.1

<#
.SYNOPSIS
    [ES] Crea un certificado en este equipo y lo registra en una app de Entra ID sin quitar los de otros equipos.
    [EN] Creates a certificate on this computer and adds it to an Entra ID app without removing other computers' certificates.

.DESCRIPTION
    [ES]
    Para conectar a Graph o Exchange Online sin usuario (app-only) cada equipo necesita su
    propio certificado: la clave privada se crea en Cert:\CurrentUser\My como no exportable
    y no sale del perfil. Los permisos no cuelgan del certificado sino de la app, asi que
    un certificado nuevo abre exactamente lo mismo que los que ya tiene.

    Pasos: inicio de sesion por codigo de dispositivo con una cuenta administradora, lectura
    de la app, certificado local (reutiliza uno valido si ya existe), registro en la app,
    prueba de conexion con el certificado y fichero con los datos de conexion.

    El registro se hace con PATCH de keyCredentials, que reescribe la coleccion entera. Para
    no borrar ni alterar los certificados de otros equipos se reenvian tal cual llegan, sin
    volver a serializarlos, y se aborta si alguno llega sin su clave publica. Si Graph
    rechaza el cambio queda el .cer exportado para subirlo a mano desde el portal.

    No necesita modulos: usa la API REST de Graph. La cuenta que inicia sesion debe ser
    Global Administrator, Application Administrator, Cloud Application Administrator o
    propietaria de la app.

    [EN]
    App-only connections to Graph or Exchange Online need one certificate per computer: the
    private key is created non-exportable in Cert:\CurrentUser\My and never leaves the
    profile. Permissions belong to the app, not the certificate, so a new certificate opens
    exactly what the existing ones do.

    Steps: device code sign-in with an admin account, app lookup, local certificate (reuses
    a valid one when present), registration on the app, connection test with the
    certificate and a file with the connection details.

    Registration uses a keyCredentials PATCH, which rewrites the whole collection. Existing
    credentials are sent back exactly as received, never re-serialized, and the run aborts
    if any arrives without its public key. If Graph rejects the change, the exported .cer
    is left for a manual upload in the portal.

    No modules required: it calls the Graph REST API. The signed-in account must be Global
    Administrator, Application Administrator, Cloud Application Administrator or an owner
    of the app.

.PARAMETER AppId
    [ES] Application (client) ID de la app. Si se omite se pide por consola.
    [EN] Application (client) ID of the app. Prompted when omitted.

.PARAMETER TenantId
    [ES] Tenant (ID o dominio). Por defecto, el de la cuenta con la que se inicia sesion.
    [EN] Tenant (ID or domain). Defaults to the tenant of the account that signs in.

.PARAMETER Years
    [ES] Validez del certificado nuevo en anos, de 1 a 5. Por defecto 2.
    [EN] Validity of the new certificate in years, 1 to 5. Defaults to 2.

.PARAMETER Subject
    [ES] Asunto del certificado. Por defecto CN=AppCert-<equipo>-<usuario>, para saber de quien es en el portal.
    [EN] Certificate subject. Defaults to CN=AppCert-<computer>-<user>, so the portal shows whose it is.

.PARAMETER OutDir
    [ES] Carpeta del .cer y del fichero de conexion. Por defecto, AppCertificate en el Escritorio.
    [EN] Folder for the .cer and the connection file. Defaults to AppCertificate on the Desktop.

.PARAMETER New
    [ES] Crea un certificado nuevo aunque ya haya uno valido con el mismo asunto.
    [EN] Creates a new certificate even if a valid one with the same subject exists.

.PARAMETER DryRun
    [ES] Inicia sesion solo con lectura, muestra la app y el plan, y no crea ni registra nada.
    [EN] Signs in read-only, shows the app and the plan, and creates or registers nothing.

.PARAMETER ClientId
    [ES] App publica para el inicio de sesion. Por defecto, Microsoft Graph Command Line Tools.
    [EN] Public client used to sign in. Defaults to Microsoft Graph Command Line Tools.

.EXAMPLE
    .\02-register-app-certificate.ps1 -AppId 00000000-0000-0000-0000-000000000000 -DryRun

.EXAMPLE
    .\02-register-app-certificate.ps1 -AppId 00000000-0000-0000-0000-000000000000

.EXAMPLE
    .\02-register-app-certificate.ps1 -AppId 00000000-0000-0000-0000-000000000000 -TenantId contoso.onmicrosoft.com -Years 1 -New

.NOTES
    Contexto: usuario
    PowerShell 5.1 y 7. Sin elevar: el certificado va al almacen del usuario que lo va a
    usar, y elevado con otra cuenta acabaria en el perfil equivocado.
#>
[CmdletBinding()]
param(
    [string]$AppId,
    [string]$TenantId = 'organizations',
    [ValidateRange(1, 5)][int]$Years = 2,
    [string]$Subject,
    [string]$OutDir,
    [switch]$New,
    [switch]$DryRun,
    [string]$ClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
$Graph = 'https://graph.microsoft.com/v1.0'
$Login = 'https://login.microsoftonline.com'

function Say([string]$m, [string]$c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Paso([string]$m) { Say "`n$m" 'Cyan' }

function ConvertTo-B64Url([byte[]]$b) { [Convert]::ToBase64String($b).TrimEnd('=').Replace('+', '-').Replace('/', '_') }

function Get-JwtClaims([string]$jwt) {
    $s = $jwt.Split('.')[1].Replace('-', '+').Replace('_', '/')
    switch ($s.Length % 4) { 2 { $s += '==' } 3 { $s += '=' } }
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s)) | ConvertFrom-Json
}

# Cuerpo JSON del error HTTP: ErrorDetails en 5.1 y en 7.
function Get-ErrorBody($err) {
    try { return ($err.ErrorDetails.Message | ConvertFrom-Json) } catch { return $null }
}

function Get-HttpStatus($err) {
    try { return [int]$err.Exception.Response.StatusCode } catch { return 0 }
}

function Get-DelegatedToken([string]$tenant, [string]$scope) {
    $dc = Invoke-RestMethod -Method Post -Uri "$Login/$tenant/oauth2/v2.0/devicecode" -Body @{ client_id = $ClientId; scope = $scope }
    Say "  Abre $($dc.verification_uri) e introduce el codigo:  $($dc.user_code)" 'Yellow'
    Say "  Caduca en $([int]($dc.expires_in / 60)) min." 'DarkGray'
    try { Set-Clipboard -Value $dc.user_code; Say '  Codigo copiado al portapapeles.' 'DarkGray' } catch { }
    try { Start-Process $dc.verification_uri } catch { }
    $espera = [int]$dc.interval
    if ($espera -lt 1) { $espera = 5 }
    $limite = (Get-Date).AddSeconds([int]$dc.expires_in)
    while ((Get-Date) -lt $limite) {
        Start-Sleep -Seconds $espera
        try {
            return Invoke-RestMethod -Method Post -Uri "$Login/$tenant/oauth2/v2.0/token" -Body @{
                grant_type  = 'urn:ietf:params:oauth:grant-type:device_code'
                client_id   = $ClientId
                device_code = $dc.device_code
            }
        } catch {
            $e = Get-ErrorBody $_
            if ($e -and $e.error -eq 'authorization_pending') { continue }
            if ($e -and $e.error -eq 'slow_down') { $espera += 5; continue }
            if ($e) { throw "Inicio de sesion fallido: $($e.error_description)" }
            throw
        }
    }
    throw 'El codigo ha caducado sin completar el inicio de sesion. Vuelve a ejecutar el script.'
}

# Texto crudo de la respuesta, decodificado como UTF-8 en 5.1 y en 7. Hace falta el
# texto literal de keyCredentials: ver el paso 4.
function Invoke-Graph([string]$method, [string]$uri, [string]$body) {
    $p = @{ Method = $method; Uri = $uri; Headers = @{ Authorization = "Bearer $script:token" }; UseBasicParsing = $true }
    if ($body) { $p.Body = [Text.Encoding]::UTF8.GetBytes($body); $p.ContentType = 'application/json; charset=utf-8' }
    $r = Invoke-WebRequest @p
    if ($r.RawContentStream) { return [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray()) }
    return [string]$r.Content
}

function Get-KeyCredentials([string]$objectId) {
    $raw = Invoke-Graph GET "$Graph/applications/$objectId`?`$select=keyCredentials"
    [pscustomobject]@{ Raw = $raw; Items = @(($raw | ConvertFrom-Json).keyCredentials) }
}

# Token app-only con el certificado: client_credentials con un JWT firmado por la clave privada.
function Get-AppToken($cert, [string]$tenant) {
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $aud = "$Login/$tenant/oauth2/v2.0/token"
    $hdr = @{ alg = 'RS256'; typ = 'JWT'; x5t = (ConvertTo-B64Url $cert.GetCertHash()) } | ConvertTo-Json -Compress
    $pay = @{ aud = $aud; iss = $AppId; sub = $AppId; jti = [guid]::NewGuid().ToString(); nbf = $now; iat = $now; exp = $now + 600 } | ConvertTo-Json -Compress
    $txt = (ConvertTo-B64Url ([Text.Encoding]::UTF8.GetBytes($hdr))) + '.' + (ConvertTo-B64Url ([Text.Encoding]::UTF8.GetBytes($pay)))
    $rsa = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
    $sig = $rsa.SignData([Text.Encoding]::ASCII.GetBytes($txt), [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    Invoke-RestMethod -Method Post -Uri $aud -Body @{
        client_id             = $AppId
        scope                 = 'https://graph.microsoft.com/.default'
        grant_type            = 'client_credentials'
        client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
        client_assertion      = "$txt.$(ConvertTo-B64Url $sig)"
    }
}

# --- Entrada -----------------------------------------------------------------------
if ($PSVersionTable.Platform -and $PSVersionTable.Platform -ne 'Win32NT') { throw 'Solo Windows: usa el almacen Cert:\CurrentUser\My.' }
if (-not $AppId) { $AppId = (Read-Host 'Application (client) ID de la app').Trim() }
if ($AppId -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') { throw "AppId no valido: '$AppId'" }
if (-not $Subject) { $Subject = "CN=AppCert-$env:COMPUTERNAME-$env:USERNAME" }
if ($Subject -notmatch '^CN=') { $Subject = "CN=$Subject" }
if (-not $OutDir) { $OutDir = Join-Path ([Environment]::GetFolderPath('Desktop')) 'AppCertificate' }

Say ''
Say "  App      : $AppId"
Say "  Asunto   : $Subject"
Say "  Equipo   : $env:COMPUTERNAME\$env:USERNAME  (PowerShell $($PSVersionTable.PSVersion))"
if ($DryRun) { Say '  Modo     : DryRun, no se crea ni se registra nada' 'Yellow' }

# --- 1. Inicio de sesion -------------------------------------------------------------
Paso '[1/6] Inicio de sesion (cuenta administradora)'
$permiso = 'Application.ReadWrite.All'
if ($DryRun) { $permiso = 'Application.Read.All' }
$tok = Get-DelegatedToken $TenantId "https://graph.microsoft.com/$permiso https://graph.microsoft.com/User.Read"
$script:token = $tok.access_token
$yo = Get-JwtClaims $tok.access_token
$tid = $yo.tid
$cuenta = @($yo.upn, $yo.unique_name, $yo.preferred_username) | Where-Object { $_ } | Select-Object -First 1
$dominio = $null
try {
    $org = @((Invoke-Graph GET "$Graph/organization?`$select=displayName,verifiedDomains" | ConvertFrom-Json).value)[0]
    $dominio = @($org.verifiedDomains | Where-Object { $_.isInitial } | ForEach-Object { $_.name })[0]
} catch { }
Say "   $cuenta  tenant $tid  $dominio" 'Green'

# --- 2. App y credenciales actuales -------------------------------------------------
Paso '[2/6] App y certificados actuales'
try {
    $app = Invoke-Graph GET "$Graph/applications(appId='$AppId')?`$select=id,displayName" | ConvertFrom-Json
} catch {
    $st = Get-HttpStatus $_
    if ($st -eq 404) { throw "No hay ninguna app con AppId $AppId en el tenant $tid." }
    if ($st -eq 403) { throw "La cuenta $cuenta no puede leer las apps del tenant. Hace falta uno de los roles de la ayuda (Get-Help -Full)." }
    throw
}
$antes = Get-KeyCredentials $app.id
$ahora = Get-Date
Say "   '$($app.displayName)'  objeto $($app.id)  certificados: $($antes.Items.Count)" 'Green'
foreach ($k in $antes.Items) {
    $fin = [datetime]$k.endDateTime
    $estado = 'vigente'
    if ($fin -lt $ahora) { $estado = 'CADUCADO' } elseif ($fin -lt $ahora.AddDays(30)) { $estado = 'caduca pronto' }
    Say ("     - {0,-50} {1:yyyy-MM-dd}  {2}" -f $k.displayName, $fin, $estado) 'DarkGray'
}

# El PATCH reescribe la coleccion entera: una credencial sin clave publica se perderia.
$sinClave = @($antes.Items | Where-Object { -not $_.key })
if ($sinClave.Count -gt 0) {
    throw "$($sinClave.Count) certificado(s) de la app llegan sin clave publica y el registro los borraria. Sube el certificado a mano: portal Entra > App registrations > $($app.displayName) > Certificates & secrets > Upload certificate."
}
$enApp = @{}
foreach ($k in $antes.Items) { $enApp[[string]$k.key] = $true }

# --- 3. Certificado local -----------------------------------------------------------
Paso '[3/6] Certificado de este equipo'
$cert = $null
$accion = 'crear'
if (-not $New) {
    $locales = @(Get-ChildItem Cert:\CurrentUser\My | Where-Object {
            $_.Subject -eq $Subject -and $_.HasPrivateKey -and $_.NotAfter -gt $ahora.AddDays(30)
        } | Sort-Object NotAfter -Descending)
    $yaEnApp = @($locales | Where-Object { $enApp.ContainsKey([Convert]::ToBase64String($_.RawData)) })
    if ($yaEnApp.Count -gt 0) { $cert = $yaEnApp[0]; $accion = 'ya registrado' }
    elseif ($locales.Count -gt 0) { $cert = $locales[0]; $accion = 'reutilizar' }
}
switch ($accion) {
    'ya registrado' { Say "   Ya hay uno en este equipo y en la app: $($cert.Thumbprint), caduca $($cert.NotAfter.ToString('yyyy-MM-dd')). No se cambia nada." 'Green' }
    'reutilizar' { Say "   Se reutiliza $($cert.Thumbprint) (caduca $($cert.NotAfter.ToString('yyyy-MM-dd'))), que aun no esta en la app." 'Green' }
    default { Say "   Se crea uno nuevo, no exportable, valido $Years ano(s)." 'Green' }
}

if ($DryRun) {
    Paso 'Plan (DryRun)'
    if ($accion -eq 'ya registrado') { Say '   Nada que hacer: solo se probaria la conexion.' }
    else {
        if ($accion -eq 'crear') { Say "   - Crear $Subject en Cert:\CurrentUser\My" }
        Say "   - Anadirlo a '$($app.displayName)' conservando los $($antes.Items.Count) certificados actuales"
        Say "   - Probar la conexion y dejar el .cer y el fichero de conexion en $OutDir"
    }
    return
}

if ($accion -eq 'crear') {
    $nuevo = New-SelfSignedCertificate -Subject $Subject -CertStoreLocation 'Cert:\CurrentUser\My' `
        -KeyAlgorithm RSA -KeyLength 2048 -KeySpec Signature -KeyUsage DigitalSignature `
        -KeyExportPolicy NonExportable -HashAlgorithm SHA256 -NotAfter $ahora.AddYears($Years) `
        -FriendlyName "App-only $AppId"
    # En 7 el cmdlet llega por compatibilidad y devuelve un objeto deserializado sin clave.
    $cert = Get-Item "Cert:\CurrentUser\My\$($nuevo.Thumbprint)"
    Say "   Creado $($cert.Thumbprint), caduca $($cert.NotAfter.ToString('yyyy-MM-dd'))." 'Green'
}

# El .cer sale antes de tocar la app: si Graph rechaza el cambio, se sube a mano.
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$cerPath = Join-Path $OutDir (($Subject -replace '^CN=', '' -replace '[^\w\-\.]', '_') + '.cer')
[IO.File]::WriteAllBytes($cerPath, $cert.RawData)

# --- 4. Registro en la app ----------------------------------------------------------
Paso '[4/6] Registro en la app'
if ($accion -eq 'ya registrado') {
    Say '   Omitido: ya estaba.' 'DarkGray'
} else {
    # Las credenciales existentes se reenvian como texto literal: al reserializarlas
    # cambian campos como customKeyIdentifier y Graph responde 400 KeyNotUpdatable.
    $m = [regex]::Match($antes.Raw, '"keyCredentials"\s*:\s*(\[.*\])\s*\}\s*$', 'Singleline')
    if (-not $m.Success) { throw "No se pudo aislar keyCredentials de la respuesta de Graph. Sube $cerPath a mano desde el portal." }
    $lista = $m.Groups[1].Value.Trim()
    $entrada = [ordered]@{
        type        = 'AsymmetricX509Cert'
        usage       = 'Verify'
        key         = [Convert]::ToBase64String($cert.RawData)
        displayName = $Subject
    } | ConvertTo-Json -Compress
    if ($lista -eq '[]') { $interior = $entrada } else { $interior = $lista.Substring(1, $lista.Length - 2).Trim() + ',' + $entrada }
    try {
        $null = Invoke-Graph PATCH "$Graph/applications/$($app.id)" ('{"keyCredentials":[' + $interior + ']}')
    } catch {
        $e = Get-ErrorBody $_
        $motivo = $_.Exception.Message
        if ($e -and $e.error) { $motivo = "$($e.error.code): $($e.error.message)" }
        Say "   Graph ha rechazado el cambio: $motivo" 'Red'
        if ((Get-HttpStatus $_) -eq 403) { Say "   La cuenta $cuenta no tiene rol para modificar la app." 'Yellow' }
        Say "   Alternativa sin riesgo: portal Entra > App registrations > $($app.displayName) > Certificates & secrets > Upload certificate" 'Yellow'
        Say "   Fichero: $cerPath" 'Yellow'
        throw
    }
    $despues = Get-KeyCredentials $app.id
    $esta = @($despues.Items | Where-Object { [string]$_.key -eq [Convert]::ToBase64String($cert.RawData) }).Count -gt 0
    if (-not $esta -or $despues.Items.Count -ne ($antes.Items.Count + 1)) {
        throw "Tras el registro la app tiene $($despues.Items.Count) certificados (antes $($antes.Items.Count)) y el nuevo $(if ($esta) { 'si' } else { 'no' }) aparece. Revisa el portal."
    }
    Say "   Registrado. La app tiene $($despues.Items.Count) certificados; los $($antes.Items.Count) anteriores siguen." 'Green'
}

# --- 5. Prueba con el certificado ---------------------------------------------------
Paso '[5/6] Prueba de conexion con el certificado'
$script:token = $null
$appTok = $null
$limite = (Get-Date).AddMinutes(3)
while (-not $appTok) {
    try { $appTok = Get-AppToken $cert $tid }
    catch {
        $e = Get-ErrorBody $_
        # AADSTS700027: la credencial nueva aun no se ha propagado.
        $propagando = $e -and $e.error_description -match 'AADSTS700027|AADSTS700024'
        if (-not $propagando -or (Get-Date) -gt $limite) {
            $d = $_.Exception.Message
            if ($e) { $d = $e.error_description }
            Say "   Sin token: $d" 'Yellow'
            Say '   El certificado ya esta en la app; si es propagacion, en unos minutos funcionara.' 'DarkGray'
            break
        }
        Say '   Esperando a que Entra propague el certificado...' 'DarkGray'
        Start-Sleep -Seconds 15
    }
}
if ($appTok) {
    $roles = @((Get-JwtClaims $appTok.access_token).roles | Where-Object { $_ } | Sort-Object)
    Say "   Token app-only obtenido. Permisos de Graph de la app: $($roles.Count)" 'Green'
    if ($roles.Count) { Say ('     ' + ($roles -join ', ')) 'DarkGray' }
}

# --- 6. Datos de conexion -----------------------------------------------------------
Paso '[6/6] Datos de conexion'
$conf = [ordered]@{
    TenantId       = $tid
    Organization   = $dominio
    AppId          = $AppId
    AppObjectId    = $app.id
    AppName        = $app.displayName
    CertThumbprint = $cert.Thumbprint
    CertSubject    = $Subject
    CertNotAfter   = $cert.NotAfter.ToString('o')
    Machine        = "$env:COMPUTERNAME\$env:USERNAME"
    RegisteredBy   = $cuenta
    UpdatedAt      = (Get-Date).ToString('o')
}
$confPath = Join-Path $OutDir 'app-certificate.json'
($conf | ConvertTo-Json) | Set-Content -LiteralPath $confPath -Encoding UTF8
Say "   $confPath" 'Green'
Say "   $cerPath" 'Green'

$org = $dominio
if (-not $org) { $org = '<dominio>.onmicrosoft.com' }
Say ''
Say "Connect-MgGraph -ClientId $AppId -TenantId $tid -CertificateThumbprint $($cert.Thumbprint) -NoWelcome" 'White'
Say "Connect-ExchangeOnline -AppId $AppId -Organization $org -CertificateThumbprint $($cert.Thumbprint) -ShowBanner:`$false" 'White'
Say ''
