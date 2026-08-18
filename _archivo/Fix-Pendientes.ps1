#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Fix-Pendientes v1.0
    Resuelve los 3 problemas pendientes:
      1. PDFelement - Extraer MSI interno y instalar directo (bypass NSIS GUI)
      2. iManage Work Desktop - Instalar prerequisitos VSTO + deploy correcto
      3. Outlook Add-ins - Limpieza Mitel/Social Connector + habilitar iManage
#>

$ErrorActionPreference = 'Continue'
$Source   = '\\servidor\utilidades\1.Node_Preparation'
$LogDir   = "$env:USERPROFILE\LOGS_Script"
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
$LogFile  = "$LogDir\Fix_Pendientes_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$TempDir  = "$env:TEMP\_FixPendientes"

if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force }
New-Item -Path $TempDir -ItemType Directory -Force | Out-Null

function Write-Log {
    param([string]$Msg, [string]$Level = 'INFO')
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Msg"
    switch ($Level) {
        'ERROR' { Write-Host $entry -ForegroundColor Red }
        'WARN'  { Write-Host $entry -ForegroundColor Yellow }
        'OK'    { Write-Host $entry -ForegroundColor Green }
        default { Write-Host $entry }
    }
    Add-Content -Path $LogFile -Value $entry
}

function Run-Process {
    param(
        [string]$File,
        [string]$Args,
        [int]$Timeout = 600
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $File
    $psi.Arguments              = $Args
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    try { [void]$proc.Start() } catch {
        Write-Log "  No se pudo lanzar: $_" 'ERROR'
        return -99
    }

    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()

    if (-not $proc.WaitForExit($Timeout * 1000)) {
        Write-Log "  TIMEOUT ${Timeout}s - matando PID $($proc.Id)" 'WARN'
        try { $proc.Kill() } catch {}
        return -1
    }
    $proc.WaitForExit()
    $code = $proc.ExitCode

    try {
        $stderr = $stderrTask.Result
        if ($stderr -and $stderr.Trim()) {
            Write-Log "  STDERR: $($stderr.Trim().Substring(0, [Math]::Min(200, $stderr.Trim().Length)))" 'WARN'
        }
    } catch {}

    $proc.Dispose()
    return $code
}

Write-Log "=========================================="
Write-Log " FIX PENDIENTES v1.0"
Write-Log "=========================================="
Write-Log "Log: $LogFile"
Write-Log ""

# ==============================================================
# 1. PDFELEMENT - EXTRAER MSI INTERNO E INSTALAR DIRECTO
# ==============================================================

Write-Log "== 1. PDFELEMENT =="

$pdfInstaller = "$Source\pdfelement_business-15066_10.1.5.exe"
$pdfExtractDir = "$TempDir\pdfelement"
New-Item -Path $pdfExtractDir -ItemType Directory -Force | Out-Null

# Buscar 7-Zip o NanaZip para extraer
$sevenZ = $null
@(
    "$env:ProgramFiles\7-Zip\7z.exe",
    "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
) | ForEach-Object { if ((Test-Path $_) -and -not $sevenZ) { $sevenZ = $_ } }

# Si no hay 7z, intentar con NanaZip (tiene 7z.exe compatible)
if (-not $sevenZ) {
    $nanaPath = Get-AppxPackage -Name '*NanaZip*' -EA SilentlyContinue |
                Select-Object -ExpandProperty InstallLocation -EA SilentlyContinue
    if ($nanaPath) {
        $candidate = Join-Path $nanaPath '7z.exe'
        if (Test-Path $candidate) { $sevenZ = $candidate }
    }
}

if (-not $sevenZ) {
    # Instalar 7-Zip temporalmente desde un MSI online o copiar del share
    Write-Log "  No se encontro 7-Zip. Intentando instalar 7-Zip primero..." 'WARN'
    # Intentar descargar 7-Zip
    $sevenZipUrl = 'https://www.7-zip.org/a/7z2409-x64.msi'
    $sevenZipMsi = "$TempDir\7z.msi"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $sevenZipUrl -OutFile $sevenZipMsi -UseBasicParsing -EA Stop
        $code = Run-Process -File 'msiexec.exe' -Args "/i `"$sevenZipMsi`" /qn /norestart" -Timeout 120
        Write-Log "  7-Zip instalado (code=$code)"
        $sevenZ = "$env:ProgramFiles\7-Zip\7z.exe"
    } catch {
        Write-Log "  No se pudo instalar 7-Zip: $_" 'ERROR'
    }
}

$pdfMsi = $null

if ($sevenZ -and (Test-Path $sevenZ)) {
    Write-Log "  Usando 7-Zip: $sevenZ"

    # Copiar instalador a local primero
    $localPdf = "$TempDir\pdfelement.exe"
    Write-Log "  Copiando instalador a local..."
    Copy-Item -Path $pdfInstaller -Destination $localPdf -Force

    # Extraer con 7z
    Write-Log "  Extrayendo contenido NSIS con 7-Zip..."
    $code = Run-Process -File $sevenZ -Args "x `"$localPdf`" -o`"$pdfExtractDir`" -y" -Timeout 120
    Write-Log "  7z exit code: $code"

    # Buscar MSIs dentro del contenido extraido
    $msis = Get-ChildItem $pdfExtractDir -Recurse -Filter '*.msi' -EA SilentlyContinue
    Write-Log "  MSIs encontrados: $($msis.Count)"
    foreach ($m in $msis) {
        Write-Log "    $($m.Name) ($([math]::Round($m.Length/1MB, 1)) MB)"
    }

    if ($msis.Count -gt 0) {
        # Usar el MSI mas grande (suele ser el principal)
        $pdfMsi = ($msis | Sort-Object Length -Descending | Select-Object -First 1).FullName
        Write-Log "  MSI principal: $([IO.Path]::GetFileName($pdfMsi))"
    } else {
        # Buscar EXEs internos que pudieran ser el instalador real
        $innerExes = Get-ChildItem $pdfExtractDir -Recurse -Filter '*.exe' -EA SilentlyContinue
        Write-Log "  No hay MSIs. EXEs internos:"
        foreach ($e in $innerExes) {
            Write-Log "    $($e.Name) ($([math]::Round($e.Length/1MB, 1)) MB)"
        }
    }

    # Listar todo lo extraido para diagnostico
    Write-Log ""
    Write-Log "  Contenido completo extraido:"
    Get-ChildItem $pdfExtractDir -Recurse | ForEach-Object {
        $rel = $_.FullName.Replace($pdfExtractDir, '').TrimStart('\')
        $size = if ($_.PSIsContainer) { '<DIR>' } else { "$([math]::Round($_.Length/1KB, 0)) KB" }
        Write-Log "    $rel  ($size)"
    }
}

if ($pdfMsi) {
    # Instalar MSI directamente con msiexec
    Write-Log ""
    Write-Log "  Instalando MSI directo con msiexec /qn..."
    $msiLog = "$LogDir\msi_pdfelement.log"
    $code = Run-Process `
        -File 'msiexec.exe' `
        -Args "/i `"$pdfMsi`" /qn /norestart LAUNCH_APP=0 /l*v `"$msiLog`"" `
        -Timeout 600
    Write-Log "  msiexec exit code: $code"

    if ($code -ne 0 -and $code -ne 3010) {
        Write-Log "  Revisando log MSI para errores..."
        if (Test-Path $msiLog) {
            $errors = Get-Content $msiLog | Select-String -Pattern 'error|failed|return value 3' -Context 2
            $errors | Select-Object -First 5 | ForEach-Object { Write-Log "    $_" 'WARN' }
        }
    }
} else {
    Write-Log ""
    Write-Log "  No se pudo extraer MSI. Alternativa: instalar con GUI automatizada..." 'WARN'
    Write-Log "  Intentando con flags alternativas de NSIS Wondershare..."

    $localPdf = if (Test-Path "$TempDir\pdfelement.exe") { "$TempDir\pdfelement.exe" }
                else { Copy-Item $pdfInstaller "$TempDir\pdfelement.exe" -Force -PassThru | Select -Expand FullName }

    # Intentar distintas combinaciones de flags
    $flagSets = @(
        '/S /NCRC',
        '/S /D=C:\Program Files\Wondershare\PDFelement',
        '-silent',
        '--silent',
        '/quiet',
        '/S /SUPPRESSMSGBOXES'
    )

    foreach ($flags in $flagSets) {
        Write-Log "  Probando: $flags"

        # Matar GUIs previas
        'PDFelement*','Wondershare*','wshelper*','WsAppService*' | ForEach-Object {
            Get-Process -Name $_ -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
        }

        $code = Run-Process -File $localPdf -Args $flags -Timeout 90

        # Verificar si se instalo
        Start-Sleep -Seconds 2
        $installed = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -EA SilentlyContinue |
            Where-Object { $_.DisplayName -like '*PDFelement*' -or $_.DisplayName -like '*Wondershare*' }

        if ($installed) {
            Write-Log "  EXITO con flags: $flags (code=$code)" 'OK'
            # Matar GUIs que haya abierto
            'PDFelement','Wondershare PDFelement','wshelper','WsAppService' | ForEach-Object {
                Get-Process -Name $_ -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
            }
            break
        } else {
            Write-Log "  No instalado con: $flags (code=$code)"
            # Matar cualquier GUI
            'PDFelement*','Wondershare*' | ForEach-Object {
                Get-Process -Name $_ -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
            }
        }
    }
}

# Verificacion final PDFelement
Start-Sleep -Seconds 2
$pdfCheck = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -EA SilentlyContinue |
    Where-Object { $_.DisplayName -like '*PDFelement*' -or $_.DisplayName -like '*Wondershare*' }
if ($pdfCheck) {
    Write-Log "  PDFelement VERIFICADO en registro: $($pdfCheck.DisplayName)" 'OK'
} else {
    Write-Log "  PDFelement NO detectado en registro tras todos los intentos" 'ERROR'
}

Write-Log ""

# ==============================================================
# 2. IMANAGE WORK DESKTOP - PREREQUISITOS + INSTALACION
# ==============================================================

Write-Log "== 2. IMANAGE WORK DESKTOP =="

$imExe = "$Source\Imanage 2.0\iManage Work Desktop for Windows 10.9.4.39 (x64 Office)\iManageWorkDesktopforWindowsx64.exe"

# Verificar si ya esta instalado
$imInstalled = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -EA SilentlyContinue |
    Where-Object { $_.DisplayName -like '*iManage Work*' }

if ($imInstalled) {
    Write-Log "  iManage Work Desktop ya instalado: $($imInstalled.DisplayName)" 'OK'
} else {
    # -- Paso 2a: Verificar prerequisitos --
    Write-Log "  Verificando prerequisitos..."

    # VSTO Runtime (Visual Studio Tools for Office)
    $vstoInstalled = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -EA SilentlyContinue |
        Where-Object { $_.DisplayName -like '*Visual Studio*Tools for Office*' -or
                       $_.DisplayName -like '*VSTO*' -or
                       $_.DisplayName -like '*Office Runtime*' }

    if ($vstoInstalled) {
        Write-Log "  VSTO Runtime encontrado: $($vstoInstalled.DisplayName | Select -First 1)" 'OK'
    } else {
        Write-Log "  VSTO Runtime NO encontrado - descargando e instalando..." 'WARN'

        $vstoUrl = 'https://aka.ms/VSTOInstallerDownload'
        $vstoExe = "$TempDir\vstor_redist.exe"

        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $vstoUrl -OutFile $vstoExe -UseBasicParsing -EA Stop
            Write-Log "  Instalando VSTO Runtime..."
            $code = Run-Process -File $vstoExe -Args '/quiet /norestart' -Timeout 300
            Write-Log "  VSTO Runtime exit code: $code"
        } catch {
            Write-Log "  Error descargando VSTO Runtime: $_" 'ERROR'
            Write-Log "  Intentando continuar sin VSTO..." 'WARN'
        }
    }

    # .NET Framework 4.8+
    $netVer = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -EA SilentlyContinue).Release
    if ($netVer -ge 528040) {
        Write-Log "  .NET Framework 4.8+ detectado (release=$netVer)" 'OK'
    } else {
        Write-Log "  .NET Framework 4.8 podria faltar (release=$netVer)" 'WARN'
    }

    # -- Paso 2b: Intentar instalacion de iManage Work Desktop --
    Write-Log ""
    Write-Log "  Instalando iManage Work Desktop..."

    if (-not (Test-Path $imExe)) {
        Write-Log "  Archivo no encontrado: $imExe" 'ERROR'
    } else {
        # Metodo 1: InstallShield con /s /SMS
        Write-Log "  Metodo 1: InstallShield /s /SMS /v`"/qn`""
        $code = Run-Process `
            -File $imExe `
            -Args '/s /SMS /v"/qn REBOOT=ReallySuppress"' `
            -Timeout 600
        Write-Log "  Exit code: $code"

        # Esperar msiexec hijos
        $sw2 = [Diagnostics.Stopwatch]::StartNew()
        Start-Sleep -Seconds 5
        while ($sw2.Elapsed.TotalSeconds -lt 120) {
            $msi = Get-Process -Name 'msiexec' -EA SilentlyContinue |
                   Where-Object { $_.SessionId -ne 0 }
            if (-not $msi) { break }
            Start-Sleep -Seconds 3
        }
        Write-Log "  msiexec hijos finalizados ($([int]$sw2.Elapsed.TotalSeconds)s)"

        # Verificar
        Start-Sleep -Seconds 3
        $imCheck = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -EA SilentlyContinue |
            Where-Object { $_.DisplayName -like '*iManage Work*' }

        if ($imCheck) {
            Write-Log "  iManage Work Desktop VERIFICADO: $($imCheck.DisplayName)" 'OK'
        } else {
            # Metodo 2: Extraer MSI interno e instalar directo
            Write-Log "  Metodo 1 fallido. Intentando extraer MSI interno..." 'WARN'

            $imExtract = "$TempDir\imanage_wd"
            New-Item -Path $imExtract -ItemType Directory -Force | Out-Null

            # InstallShield: extraer con /a (admin install)
            Write-Log "  Extrayendo con /a (admin install)..."
            $code = Run-Process -File $imExe -Args "/a /s /v`"/qn TARGETDIR=\`"$imExtract\`"`"" -Timeout 120

            $innerMsis = Get-ChildItem $imExtract -Recurse -Filter '*.msi' -EA SilentlyContinue
            if ($innerMsis) {
                foreach ($m in $innerMsis) {
                    Write-Log "    MSI: $($m.Name) ($([math]::Round($m.Length/1MB, 1)) MB)"
                }
                $mainMsi = ($innerMsis | Sort-Object Length -Descending | Select-Object -First 1).FullName
                Write-Log "  Instalando MSI directo: $([IO.Path]::GetFileName($mainMsi))"
                $code = Run-Process `
                    -File 'msiexec.exe' `
                    -Args "/i `"$mainMsi`" /qn /norestart REBOOT=ReallySuppress /l*v `"$LogDir\msi_imanage_wd.log`"" `
                    -Timeout 600
                Write-Log "  msiexec exit code: $code"
            } else {
                Write-Log "  No se encontraron MSIs internos" 'WARN'

                # Listar lo que hay en la carpeta del instalador
                Write-Log "  Contenido carpeta del instalador:"
                $imFolder = Split-Path $imExe
                Get-ChildItem $imFolder -Recurse | ForEach-Object {
                    $rel = $_.FullName.Replace($imFolder, '').TrimStart('\')
                    Write-Log "    $rel"
                }
            }

            # Verificar de nuevo
            Start-Sleep -Seconds 3
            $imCheck2 = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -EA SilentlyContinue |
                Where-Object { $_.DisplayName -like '*iManage Work*' }
            if ($imCheck2) {
                Write-Log "  iManage Work Desktop VERIFICADO (metodo 2): $($imCheck2.DisplayName)" 'OK'
            } else {
                Write-Log "  iManage Work Desktop NO se pudo instalar" 'ERROR'

                # Diagnostico adicional: buscar logs de InstallShield
                Write-Log ""
                Write-Log "  Buscando logs de error de InstallShield..."
                $isLogs = Get-ChildItem "$env:TEMP" -Filter '*.log' -EA SilentlyContinue |
                    Where-Object { $_.Name -match 'iManage|InstallShield|setup' -and
                                   $_.LastWriteTime -gt (Get-Date).AddMinutes(-10) }
                foreach ($l in $isLogs) {
                    Write-Log "    Log encontrado: $($l.FullName)"
                    $errors = Get-Content $l.FullName -EA SilentlyContinue |
                        Select-String -Pattern 'error|failed|abort|1603|0x8' -Context 2 |
                        Select-Object -First 5
                    foreach ($err in $errors) {
                        Write-Log "      $($err.Line.Trim())" 'WARN'
                    }
                }
            }
        }
    }
}

Write-Log ""

# ==============================================================
# 3. OUTLOOK ADD-INS - LIMPIEZA Y CONFIGURACION
# ==============================================================

Write-Log "== 3. OUTLOOK ADD-INS =="

# -- 3a: Buscar procesos de Outlook y cerrar --
$outlookProc = Get-Process -Name 'OUTLOOK' -EA SilentlyContinue
if ($outlookProc) {
    Write-Log "  Cerrando Outlook para modificar add-ins..."
    $outlookProc | Stop-Process -Force -EA SilentlyContinue
    Start-Sleep -Seconds 3
}

# -- 3b: Rutas de registro de add-ins de Outlook --
$addinPaths = @(
    # Outlook COM Add-ins (machine-level)
    'HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\Outlook\Addins',
    # Outlook COM Add-ins (user-level)
    'HKCU:\SOFTWARE\Microsoft\Office\Outlook\Addins',
    # Resiliency (disabled add-ins)
    'HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Resiliency\DisabledItems',
    'HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Resiliency\DoNotDisableAddinList',
    'HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Resiliency\NotificationReminderAddinData'
)

Write-Log ""
Write-Log "  --- Estado actual de add-ins ---"

# Listar todos los add-ins registrados
foreach ($regPath in @(
    'HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\Outlook\Addins',
    'HKCU:\SOFTWARE\Microsoft\Office\Outlook\Addins'
)) {
    if (Test-Path $regPath) {
        $addins = Get-ChildItem $regPath -EA SilentlyContinue
        foreach ($addin in $addins) {
            $props = Get-ItemProperty $addin.PSPath -EA SilentlyContinue
            $name = $addin.PSChildName
            $friendlyName = $props.FriendlyName
            $loadBehavior = $props.LoadBehavior
            Write-Log "    [$regPath] $name"
            Write-Log "      FriendlyName: $friendlyName"
            Write-Log "      LoadBehavior: $loadBehavior"
        }
    }
}

# -- 3c: ELIMINAR add-ins de Mitel Connect --
Write-Log ""
Write-Log "  --- Eliminando add-ins de Mitel ---"

$mitelPatterns = @('*Mitel*', '*MiCollab*', '*MiVoice*', '*UCB*Mitel*', '*ShoreTel*')

foreach ($regPath in @(
    'HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\Outlook\Addins',
    'HKCU:\SOFTWARE\Microsoft\Office\Outlook\Addins'
)) {
    if (-not (Test-Path $regPath)) { continue }
    $addins = Get-ChildItem $regPath -EA SilentlyContinue
    foreach ($addin in $addins) {
        $name = $addin.PSChildName
        $props = Get-ItemProperty $addin.PSPath -EA SilentlyContinue
        $friendly = $props.FriendlyName

        $isMitel = $false
        foreach ($pattern in $mitelPatterns) {
            if ($name -like $pattern -or $friendly -like $pattern) {
                $isMitel = $true
                break
            }
        }

        if ($isMitel) {
            Write-Log "    ELIMINANDO: $name ($friendly)" 'WARN'
            Remove-Item $addin.PSPath -Recurse -Force -EA SilentlyContinue
        }
    }
}

# -- 3d: ELIMINAR Outlook Social Connector 2016 --
Write-Log ""
Write-Log "  --- Eliminando Outlook Social Connector ---"

$oscPatterns = @('*Social*Connector*', '*OscAddin*', '*OSC*')

foreach ($regPath in @(
    'HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\Outlook\Addins',
    'HKCU:\SOFTWARE\Microsoft\Office\Outlook\Addins'
)) {
    if (-not (Test-Path $regPath)) { continue }
    $addins = Get-ChildItem $regPath -EA SilentlyContinue
    foreach ($addin in $addins) {
        $name = $addin.PSChildName
        $props = Get-ItemProperty $addin.PSPath -EA SilentlyContinue
        $friendly = $props.FriendlyName

        $isOSC = $false
        foreach ($pattern in $oscPatterns) {
            if ($name -like $pattern -or $friendly -like $pattern) {
                $isOSC = $true
                break
            }
        }

        if ($isOSC) {
            Write-Log "    ELIMINANDO: $name ($friendly)" 'WARN'
            Remove-Item $addin.PSPath -Recurse -Force -EA SilentlyContinue
        }
    }
}

# -- 3e: HABILITAR iManage Work Add-in for Outlook --
Write-Log ""
Write-Log "  --- Configurando iManage Work Add-in ---"

$imanageAddinFound = $false

foreach ($regPath in @(
    'HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\Outlook\Addins',
    'HKCU:\SOFTWARE\Microsoft\Office\Outlook\Addins'
)) {
    if (-not (Test-Path $regPath)) { continue }
    $addins = Get-ChildItem $regPath -EA SilentlyContinue
    foreach ($addin in $addins) {
        $name = $addin.PSChildName
        if ($name -like '*iManage*') {
            $imanageAddinFound = $true
            # LoadBehavior = 3 -> cargado al iniciar Outlook
            Set-ItemProperty -Path $addin.PSPath -Name 'LoadBehavior' -Value 3 -Type DWord -EA SilentlyContinue
            Write-Log "    iManage add-in habilitado (LoadBehavior=3): $name" 'OK'
        }
    }
}

# Limpiar resiliency (Outlook deshabilita add-ins lentos aqui)
$resiliencyPaths = @(
    'HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Resiliency\DisabledItems',
    'HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Resiliency\CrashingAddinList',
    'HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Resiliency\DoNotDisableAddinList'
)

foreach ($rp in $resiliencyPaths) {
    if (Test-Path $rp) {
        # Buscar entradas de iManage en DisabledItems y eliminarlas
        $props = Get-ItemProperty $rp -EA SilentlyContinue
        if ($props) {
            $props.PSObject.Properties | Where-Object {
                $_.Name -notmatch '^PS' -and $_.Value -match 'iManage'
            } | ForEach-Object {
                Write-Log "    Eliminando entrada de resiliency: $($_.Name)" 'OK'
                Remove-ItemProperty -Path $rp -Name $_.Name -EA SilentlyContinue
            }
        }
    }
}

# Asegurar que iManage NO este en la lista de deshabilitados
$doNotDisable = 'HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Resiliency\DoNotDisableAddinList'
if (-not (Test-Path $doNotDisable)) {
    New-Item -Path $doNotDisable -Force | Out-Null
}
# Buscar el ProgID del add-in de iManage
foreach ($regPath in @(
    'HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\Outlook\Addins',
    'HKCU:\SOFTWARE\Microsoft\Office\Outlook\Addins'
)) {
    if (-not (Test-Path $regPath)) { continue }
    Get-ChildItem $regPath -EA SilentlyContinue | Where-Object { $_.PSChildName -like '*iManage*' } | ForEach-Object {
        $progId = $_.PSChildName
        Set-ItemProperty -Path $doNotDisable -Name $progId -Value 1 -Type DWord -EA SilentlyContinue
        Write-Log "    Marcado como DoNotDisable: $progId" 'OK'
    }
}

if (-not $imanageAddinFound) {
    Write-Log "  AVISO: No se encontro ningun add-in de iManage registrado en Outlook" 'WARN'
    Write-Log "  Esto confirma que iManage Work Desktop no esta correctamente instalado" 'WARN'
    Write-Log "  El add-in VSTO requiere que iManage Work Desktop se instale primero" 'WARN'

    # Verificar si el archivo .vsto existe
    $vstoPath = 'C:\Program Files\iManage\Work10'
    if (Test-Path $vstoPath) {
        Write-Log "  Contenido de $vstoPath :"
        Get-ChildItem $vstoPath -Recurse -EA SilentlyContinue | ForEach-Object {
            Write-Log "    $($_.FullName.Replace($vstoPath, '').TrimStart('\'))  $($_.Length) bytes"
        }
    } else {
        Write-Log "  Carpeta $vstoPath NO existe" 'WARN'
    }
}

# -- 3f: Verificacion final de add-ins --
Write-Log ""
Write-Log "  --- Estado final de add-ins ---"

foreach ($regPath in @(
    'HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\Outlook\Addins',
    'HKCU:\SOFTWARE\Microsoft\Office\Outlook\Addins'
)) {
    if (-not (Test-Path $regPath)) { continue }
    $addins = Get-ChildItem $regPath -EA SilentlyContinue
    foreach ($addin in $addins) {
        $props = Get-ItemProperty $addin.PSPath -EA SilentlyContinue
        $status = switch ($props.LoadBehavior) {
            0 { 'Deshabilitado' }
            1 { 'Cargado (no al inicio)' }
            2 { 'Cargado al inicio (no conectado)' }
            3 { 'Habilitado (cargado al inicio)' }
            8 { 'Carga bajo demanda' }
            9 { 'Carga bajo demanda (conectado)' }
            16 { 'Cargado primera vez' }
            default { "Desconocido ($($props.LoadBehavior))" }
        }
        Write-Log "    $($addin.PSChildName)"
        Write-Log "      $($props.FriendlyName) -> $status"
    }
}

# -- Resumen --
Write-Log ""
Write-Log "=========================================="
Write-Log " RESUMEN FIX PENDIENTES"
Write-Log "=========================================="
Write-Log "  Log: $LogFile"
Write-Log "=========================================="

# Limpiar temp
# No limpiar todavia por si hay que revisar los archivos extraidos

Write-Host "`nPresiona Enter para cerrar..." -ForegroundColor Cyan
Read-Host
