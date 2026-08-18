#Requires -RunAsAdministrator

<#
.SYNOPSIS
    [ES] Analiza un paquete de instalacion y dice que tipo es y que parametros silenciosos admite.
    [EN] Inspects an installer package and reports its type and supported silent switches.
#>

$ErrorActionPreference = 'Continue'
$Source  = if ($env:SOPORTE_ORIGEN_PAQUETES) { $env:SOPORTE_ORIGEN_PAQUETES } else { '\\servidor\utilidades\1.Node_Preparation' }
$LogDir  = "$env:USERPROFILE\LOGS_Script"
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
$TempDir = "$env:TEMP\Diag_Instaladores"
$Report  = "$LogDir\Diag_Instaladores_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

# Limpiar y crear directorio temporal
if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force }
New-Item -Path $TempDir -ItemType Directory -Force | Out-Null

function Write-Section {
    param([string]$Title)
    $sep = '=' * 60
    $msg = "`n$sep`n  $Title`n$sep"
    Write-Host $msg -ForegroundColor Cyan
    Add-Content -Path $Report -Value $msg
}

function Write-Out {
    param([string]$Msg)
    Write-Host $Msg
    Add-Content -Path $Report -Value $Msg
}

function Start-WithTimeout {
    param(
        [string]$FilePath,
        [string]$Arguments,
        [int]$Timeout = 14
    )
    $proc = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru -NoNewWindow -ErrorAction SilentlyContinue
    if (-not $proc) {
        Write-Out "  [!] No se pudo lanzar: $FilePath"
        return $null
    }
    $finished = $proc | Wait-Process -Timeout $Timeout -ErrorAction SilentlyContinue
    if (-not $proc.HasExited) {
        Write-Out "  [!] Timeout ${Timeout}s alcanzado - matando proceso $($proc.Id)"
        $proc | Stop-Process -Force -ErrorAction SilentlyContinue
        return $null
    }
    return $proc.ExitCode
}

Write-Out "Diagnostico iniciado: $(Get-Date)"
Write-Out "Reporte: $Report"

# ==============================================================
Write-Section '1. PDFelement (Wondershare) - Extraer contenido'
# ==============================================================

$pdfFile = "$Source\pdfelement_business-15066_10.1.5.exe"

if (Test-Path $pdfFile) {
    Write-Out "`n--- FileVersionInfo ---"
    $info = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($pdfFile)
    Write-Out "  ProductName     : $($info.ProductName)"
    Write-Out "  CompanyName     : $($info.CompanyName)"
    Write-Out "  FileDescription : $($info.FileDescription)"
    Write-Out "  OriginalFilename: $($info.OriginalFilename)"
    Write-Out "  FileVersion     : $($info.FileVersion)"

    # Intentar extraccion con distintos metodos
    $pdfExtract = "$TempDir\pdfelement"
    New-Item -Path $pdfExtract -ItemType Directory -Force | Out-Null

    Write-Out "`n--- Intento 1: /extract ---"
    $code = Start-WithTimeout -FilePath $pdfFile -Arguments "/extract `"$pdfExtract`"" -Timeout 14
    Write-Out "  Exit code: $code"

    $extracted = Get-ChildItem $pdfExtract -Recurse -ErrorAction SilentlyContinue
    if (-not $extracted -or $extracted.Count -eq 0) {
        Write-Out "`n--- Intento 2: /D= /extract ---"
        $code = Start-WithTimeout -FilePath $pdfFile -Arguments "/D=`"$pdfExtract`" /extract" -Timeout 14
        Write-Out "  Exit code: $code"
        $extracted = Get-ChildItem $pdfExtract -Recurse -ErrorAction SilentlyContinue
    }

    if (-not $extracted -or $extracted.Count -eq 0) {
        Write-Out "`n--- Intento 3: 7-Zip / NanaZip extraccion directa ---"
        $sevenZ = $null
        @(
            "$env:ProgramFiles\7-Zip\7z.exe",
            "$env:ProgramFiles\NanaZip\NanaZip.exe",
            "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
        ) | ForEach-Object { if ((Test-Path $_) -and -not $sevenZ) { $sevenZ = $_ } }

        if ($sevenZ) {
            Write-Out "  Usando: $sevenZ"
            Start-WithTimeout -FilePath $sevenZ -Arguments "x `"$pdfFile`" -o`"$pdfExtract`" -y" -Timeout 14
        } else {
            Write-Out "  No se encontro 7-Zip / NanaZip para extraer"
        }
        $extracted = Get-ChildItem $pdfExtract -Recurse -ErrorAction SilentlyContinue
    }

    if ($extracted -and $extracted.Count -gt 0) {
        Write-Out "`n--- Contenido extraido ---"
        $extracted | Select-Object FullName, Length | Format-Table -Auto | Out-String | ForEach-Object { Write-Out $_ }

        # Buscar MSIs dentro
        $msis = $extracted | Where-Object { $_.Extension -eq '.msi' }
        if ($msis) {
            Write-Out "  [*] MSIs encontrados:"
            foreach ($m in $msis) {
                Write-Out "      $($m.FullName) ($([math]::Round($m.Length/1MB, 1)) MB)"
            }
        }
    } else {
        Write-Out "`n  [!] No se pudo extraer contenido con ningun metodo"
    }

    # Probar flags silenciosas conocidas de Wondershare
    Write-Out "`n--- Flags conocidas de Wondershare ---"
    Write-Out "  /silent, --silent, -silent, /S, /quiet"
    Write-Out "  Nota: Wondershare a veces requiere: /NCRC /S o usa Burn/WiX bootstrapper"

    # Verificar si tiene manifest o config embebido (indicador de Burn/WiX)
    $bytes = [System.IO.File]::ReadAllBytes($pdfFile)
    $text  = [System.Text.Encoding]::ASCII.GetString($bytes[0..4095])
    if ($text -match 'Burn') {
        Write-Out "  [*] DETECTADO: WiX Burn bootstrapper"
    } elseif ($text -match 'Inno') {
        Write-Out "  [*] DETECTADO: Inno Setup"
    } elseif ($text -match 'NSIS') {
        Write-Out "  [*] DETECTADO: NSIS"
    } elseif ($text -match 'InstallShield') {
        Write-Out "  [*] DETECTADO: InstallShield"
    } else {
        # Buscar mas adentro (primeros 64KB)
        $chunk = [System.Text.Encoding]::ASCII.GetString($bytes[0..([Math]::Min(65535, $bytes.Length - 1))])
        $frameworks = @('Burn','WiX','Inno Setup','NSIS','InstallShield','InstallScript','Nullsoft','7zS')
        foreach ($fw in $frameworks) {
            if ($chunk -match [regex]::Escape($fw)) {
                Write-Out "  [*] DETECTADO (64KB scan): $fw"
            }
        }
    }
} else {
    Write-Out "  [!] Archivo no encontrado: $pdfFile"
}

# ==============================================================
Write-Section '2. iManage Work Desktop - InstallShield InstallScript'
# ==============================================================

$imBase = "$Source\Imanage 2.0\iManage Work Desktop for Windows 10.9.4.39 (x64 Office)"
$imExe  = "$imBase\iManageWorkDesktopforWindowsx64.exe"

if (Test-Path $imExe) {
    $imExtract = "$TempDir\imanage_workdesktop"
    New-Item -Path $imExtract -ItemType Directory -Force | Out-Null

    Write-Out "`n--- Intento extraccion: /s /extract_all ---"
    $code = Start-WithTimeout -FilePath $imExe -Arguments "/s /extract_all:`"$imExtract`"" -Timeout 14
    Write-Out "  Exit code: $code"

    $imFiles = Get-ChildItem $imExtract -Recurse -ErrorAction SilentlyContinue
    if (-not $imFiles -or $imFiles.Count -eq 0) {
        Write-Out "`n--- Intento 2: /a /extract ---"
        $code = Start-WithTimeout -FilePath $imExe -Arguments "/a /s /v`"/qn TARGETDIR=\`"$imExtract\`"`"" -Timeout 14
        Write-Out "  Exit code: $code"
        $imFiles = Get-ChildItem $imExtract -Recurse -ErrorAction SilentlyContinue
    }

    if ($imFiles -and $imFiles.Count -gt 0) {
        Write-Out "`n--- Contenido extraido ---"
        $imFiles | Where-Object { $_.Extension -in '.msi','.exe','.cab','.ini' } |
            Select-Object FullName, Length | Format-Table -Auto | Out-String | ForEach-Object { Write-Out $_ }
    } else {
        Write-Out "  [!] No se pudo extraer. Listando contenido de la carpeta original:"
        Get-ChildItem $imBase -Recurse | Select-Object FullName, Length |
            Format-Table -Auto | Out-String | ForEach-Object { Write-Out $_ }
    }

    # Scan del binario para detectar framework
    Write-Out "`n--- Scan binario (64KB) ---"
    $bytes = [System.IO.File]::ReadAllBytes($imExe)
    $chunk = [System.Text.Encoding]::ASCII.GetString($bytes[0..([Math]::Min(65535, $bytes.Length - 1))])
    @('InstallShield','InstallScript','MSI','setup.exe','msiexec','.msi') | ForEach-Object {
        if ($chunk -match [regex]::Escape($_)) {
            Write-Out "  [*] Encontrado: $_"
        }
    }
} else {
    Write-Out "  [!] No encontrado: $imExe"
}

# ==============================================================
Write-Section '3. iManage Drive + Drive Native - Contenido carpetas'
# ==============================================================

$driveBase = "$Source\Imanage 2.0\iManage Drive for Windows 10.10.0.410"

Write-Out "`n--- iManage Drive ---"
$drivePath = "$driveBase\iManage Drive for Windows 10.10.0.410"
if (Test-Path $drivePath) {
    Get-ChildItem $drivePath -Recurse | Select-Object FullName, Length |
        Format-Table -Auto | Out-String | ForEach-Object { Write-Out $_ }

    # Scan binario
    $driveExe = "$drivePath\iManageDriveSetup.exe"
    if (Test-Path $driveExe) {
        $bytes = [System.IO.File]::ReadAllBytes($driveExe)
        $chunk = [System.Text.Encoding]::ASCII.GetString($bytes[0..([Math]::Min(65535, $bytes.Length - 1))])
        @('Burn','WiX','Inno','NSIS','InstallShield','InstallScript','Squirrel','Electron') | ForEach-Object {
            if ($chunk -match [regex]::Escape($_)) {
                Write-Out "  [*] Drive - Detectado: $_"
            }
        }
    }
} else {
    Write-Out "  [!] Carpeta no encontrada: $drivePath"
}

Write-Out "`n--- iManage Drive Native ---"
$nativePath = "$driveBase\iManageDrive Native 10.6.1.15"
if (Test-Path $nativePath) {
    Get-ChildItem $nativePath -Recurse | Select-Object FullName, Length |
        Format-Table -Auto | Out-String | ForEach-Object { Write-Out $_ }

    $nativeExe = "$nativePath\iManageDriveNative.exe"
    if (Test-Path $nativeExe) {
        $bytes = [System.IO.File]::ReadAllBytes($nativeExe)
        $chunk = [System.Text.Encoding]::ASCII.GetString($bytes[0..([Math]::Min(65535, $bytes.Length - 1))])
        @('Burn','WiX','Inno','NSIS','InstallShield','InstallScript','Squirrel','Electron','MSIX') | ForEach-Object {
            if ($chunk -match [regex]::Escape($_)) {
                Write-Out "  [*] Native - Detectado: $_"
            }
        }
    }
} else {
    Write-Out "  [!] Carpeta no encontrada: $nativePath"
}

# ==============================================================
Write-Section '4. MDR / Cortex XDR - Estado actual'
# ==============================================================

Write-Out "`n--- Registro (instalacion) ---"
$cortex = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
) | ForEach-Object {
    Get-ItemProperty $_ -ErrorAction SilentlyContinue
} | Where-Object { $_.DisplayName -match 'Cortex|MDR|Palo Alto|Traps' }

if ($cortex) {
    $cortex | Select-Object DisplayName, DisplayVersion, InstallDate, UninstallString |
        Format-List | Out-String | ForEach-Object { Write-Out $_ }
} else {
    Write-Out "  No se encontro Cortex/MDR en el registro"
}

Write-Out "`n--- Servicios Cortex/Traps ---"
$svc = Get-Service | Where-Object { $_.DisplayName -match 'Cortex|cyserver|traps|cytool' }
if ($svc) {
    $svc | Select-Object Name, DisplayName, Status |
        Format-Table -Auto | Out-String | ForEach-Object { Write-Out $_ }
} else {
    Write-Out "  No se encontraron servicios de Cortex activos"
}

Write-Out "`n--- Log MSI del error 1603 ---"
$msiLog = "$env:TEMP\msi_MDR_Windows_Andersen_8_2_x64.log"
if (Test-Path $msiLog) {
    $matches = Get-Content $msiLog | Select-String -Pattern 'error|failed|1603|CustomAction|return value 3' -Context 3
    if ($matches) {
        $matches | Out-String | ForEach-Object { Write-Out $_ }
    } else {
        Write-Out "  No se encontraron lineas de error adicionales"
    }
} else {
    Write-Out "  Log MSI no encontrado (se genera al ejecutar el script principal)"
}

# ==============================================================
Write-Section '5. Resumen de recomendaciones'
# ==============================================================

Write-Out @"

  Reporte guardado en: $Report
  Archivos temporales en: $TempDir

  Pega el contenido de $Report en el chat para que pueda
  ajustar el script de instalacion con los flags correctos.

"@

Write-Host "`nDiagnostico completado. Presiona Enter para cerrar..." -ForegroundColor Cyan
Read-Host
