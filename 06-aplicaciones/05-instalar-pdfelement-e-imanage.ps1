#Requires -RunAsAdministrator

<#
.SYNOPSIS
    [ES] Instala PDFelement e iManage automatizando su asistente, que no admite modo silencioso.
    [EN] Installs PDFelement and iManage by driving their wizard, which has no silent mode.
.PARAMETER Modo
    'Todo'     = Instala PDFelement + iManage Work Desktop (UI Automation)
    'Solo-PDF' = Solo instala PDFelement
    'Solo-IM'  = Solo instala iManage Work Desktop

.EXAMPLE
    # Instalar ambos (desatendido via UI Automation)
    .\Fix-PDFelement-iManage.ps1 -Modo Todo

    # Solo uno
    .\Fix-PDFelement-iManage.ps1 -Modo Solo-IM
#>
param(
    [ValidateSet('Todo','Solo-PDF','Solo-IM')]
    [string]$Modo = 'Todo'
)

$ErrorActionPreference = 'Continue'
$Source    = if ($env:SOPORTE_ORIGEN_PAQUETES) { $env:SOPORTE_ORIGEN_PAQUETES } else { '\\servidor\utilidades\1.Node_Preparation' }
$LogDir    = "$env:USERPROFILE\LOGS_Script"
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
$LogFile   = "$LogDir\Fix_PDFiM_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$LocalDir  = "$env:TEMP\_FixInstallers"

if (-not (Test-Path $LocalDir)) { New-Item $LocalDir -ItemType Directory -Force | Out-Null }

# ==============================================
# FUNCIONES COMUNES
# ==============================================

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

function Test-AppInstalled {
    param([string[]]$Keywords)
    $apps = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    ) | ForEach-Object { Get-ItemProperty $_ -EA SilentlyContinue } |
        Where-Object { $_.DisplayName }
    foreach ($kw in $Keywords) {
        if ($apps | Where-Object { $_.DisplayName -like "*$kw*" }) { return $true }
    }
    return $false
}

# ==============================================================
# PDFELEMENT - UI AUTOMATION
# ==============================================================

function Install-PDFelement {
    Write-Log "== PDFELEMENT - UI AUTOMATION v2 =="

    if (Test-AppInstalled -Keywords @('PDFelement','Wondershare')) {
        Write-Log "  PDFelement ya instalado - SKIP" 'OK'
        return
    }

    $pdfExe = "$Source\pdfelement_business-15066_10.1.5.exe"
    if (-not (Test-Path $pdfExe)) {
        Write-Log "  Archivo no encontrado: $pdfExe" 'ERROR'
        return
    }

    # Copiar a local
    $localPdf = "$LocalDir\pdfelement_setup.exe"
    if (-not (Test-Path $localPdf)) {
        Write-Log "  Copiando a cache local..."
        Copy-Item $pdfExe $localPdf -Force
    }

    # Cargar ensamblados de UI Automation
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    Add-Type -AssemblyName System.Windows.Forms

    # Importar mouse_event una sola vez
    Add-Type -MemberDefinition @'
        [DllImport("user32.dll")]
        public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, int dwExtraInfo);
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);
'@ -Name 'Win32UI' -Namespace 'PInvoke' -EA SilentlyContinue

    # -- Funciones auxiliares --

    function Click-Element {
        <# Hace click en un AutomationElement via InvokePattern o coords #>
        param([System.Windows.Automation.AutomationElement]$Element, [string]$Label)
        # Metodo 1: InvokePattern
        try {
            $ip = $Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
            $ip.Invoke()
            Write-Log "    Click (Invoke): '$Label'" 'OK'
            return $true
        } catch {}
        # Metodo 2: SelectionItemPattern (para radio buttons)
        try {
            $sp = $Element.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
            $sp.Select()
            Write-Log "    Click (Select): '$Label'" 'OK'
            return $true
        } catch {}
        # Metodo 3: Coordenadas fisicas
        try {
            $rect = $Element.Current.BoundingRectangle
            if ($rect.Width -gt 0 -and $rect.Height -gt 0) {
                $x = [int]($rect.X + $rect.Width / 2)
                $y = [int]($rect.Y + $rect.Height / 2)
                [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
                Start-Sleep -Milliseconds 150
                [PInvoke.Win32UI]::mouse_event(0x0002, 0, 0, 0, 0)  # LEFTDOWN
                [PInvoke.Win32UI]::mouse_event(0x0004, 0, 0, 0, 0)  # LEFTUP
                Write-Log "    Click (coords $x,$y): '$Label'" 'OK'
                return $true
            }
        } catch {}
        return $false
    }

    function Find-ElementByName {
        param(
            [System.Windows.Automation.AutomationElement]$Parent,
            [string]$Name,
            [System.Windows.Automation.ControlType]$Type = $null
        )
        if ($Type) {
            $cName = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::NameProperty, $Name)
            $cType = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $Type)
            $cAnd  = New-Object System.Windows.Automation.AndCondition($cName, $cType)
            return $Parent.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cAnd)
        } else {
            $c = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::NameProperty, $Name)
            return $Parent.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $c)
        }
    }

    function Find-FirstButton {
        <# Busca el primer boton que exista de una lista de nombres #>
        param(
            [System.Windows.Automation.AutomationElement]$Window,
            [string[]]$Names
        )
        foreach ($n in $Names) {
            $el = Find-ElementByName -Parent $Window -Name $n -Type ([System.Windows.Automation.ControlType]::Button)
            if ($el) { return @{ Element = $el; Name = $n } }
        }
        return $null
    }

    function Select-RadioButton {
        <# Busca y selecciona un radio button por texto parcial #>
        param(
            [System.Windows.Automation.AutomationElement]$Window,
            [string[]]$Patterns
        )
        # Buscar todos los RadioButton
        $rbCondition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::RadioButton)
        $radios = $Window.FindAll(
            [System.Windows.Automation.TreeScope]::Descendants, $rbCondition)

        foreach ($rb in $radios) {
            try {
                $rbName = $rb.Current.Name
                foreach ($pat in $Patterns) {
                    if ($rbName -like "*$pat*") {
                        $clicked = Click-Element -Element $rb -Label "RadioButton: $rbName"
                        if ($clicked) { return $true }
                    }
                }
            } catch {}
        }
        return $false
    }

    function Dump-AllControls {
        <# Log de todos los controles visibles para diagnostico #>
        param([System.Windows.Automation.AutomationElement]$Window)
        Write-Log "    --- DUMP controles visibles ---"
        $all = $Window.FindAll(
            [System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($el in $all) {
            try {
                $n = $el.Current.Name
                $t = $el.Current.ControlType.ProgrammaticName
                $enabled = $el.Current.IsEnabled
                if ($n -and $n.Length -gt 0) {
                    Write-Log "      [$t] '$n' (enabled=$enabled)"
                }
            } catch {}
        }
        Write-Log "    --- FIN DUMP ---"
    }

    function Get-InstallerWindow {
        param([int]$TimeoutSec = 10)
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $root = [System.Windows.Automation.AutomationElement]::RootElement
        while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
            $windows = $root.FindAll(
                [System.Windows.Automation.TreeScope]::Children,
                [System.Windows.Automation.Condition]::TrueCondition)
            foreach ($w in $windows) {
                try {
                    $title = $w.Current.Name
                    if ($title -match 'PDFelement|Wondershare|Instalar -|Setup|Select Setup') {
                        return $w
                    }
                } catch {}
            }
            Start-Sleep -Milliseconds 400
        }
        return $null
    }

    # -- Lanzar instalador --
    Write-Log "  Lanzando instalador..."
    $proc = Start-Process -FilePath $localPdf -PassThru

    # -- Bucle de automatizacion inteligente --
    Write-Log "  UI Automation v2 - bucle inteligente con deteccion de pagina"
    $maxWait        = 600
    $swTotal        = [Diagnostics.Stopwatch]::StartNew()
    $clickCount     = 0
    $samePageCount  = 0      # Contador de iteraciones en la misma pagina
    $lastDumpTime   = 0
    $pageHash       = ''     # Hash para detectar cambio de pagina

    # Botones en espanol (Inno Setup es: idioma detectado como espanol)
    $nextBtns   = @('Siguiente >','Siguiente','Next >','Next')
    $acceptBtns = @('Acepto','I Agree','Accept','Aceptar','OK','Agree',
                     'I accept the agreement','Acepto el acuerdo')
    $installBtns = @('Instalar','Install','Install Now','Instalar ahora')
    $finishBtns  = @('Finalizar','Finish','Close','Cerrar','Done','Listo')
    $skipBtns    = @('Omitir','Skip','No, gracias','No thanks','Later','Despues','Cancel')
    $closeBtns   = @('Close','Cerrar','X')

    # Radio buttons para pagina de licencia
    $acceptRadio = @('Acepto el acuerdo','Acepto','I accept the agreement',
                      'I accept','Acepto los','I agree')

    while ($swTotal.Elapsed.TotalSeconds -lt $maxWait) {
        # Verificar si el proceso termino
        if ($proc.HasExited) {
            Write-Log "  Proceso finalizado (code=$($proc.ExitCode))"
            break
        }

        # Buscar ventana
        $win = Get-InstallerWindow -TimeoutSec 5
        if (-not $win) {
            Start-Sleep -Seconds 2
            continue
        }

        # Detectar cambio de pagina
        $currentTitle = $win.Current.Name
        # Crear hash simple del estado de la pagina
        $btnState = ''
        try {
            $btns = $win.FindAll(
                [System.Windows.Automation.TreeScope]::Descendants,
                (New-Object System.Windows.Automation.PropertyCondition(
                    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                    [System.Windows.Automation.ControlType]::Button)))
            foreach ($b in $btns) {
                try { $btnState += $b.Current.Name + $b.Current.IsEnabled.ToString() } catch {}
            }
        } catch {}
        $newHash = "$currentTitle|$btnState"

        if ($newHash -ne $pageHash) {
            # Pagina nueva
            $pageHash = $newHash
            $samePageCount = 0
            Write-Log "  Pagina: '$currentTitle'"
        } else {
            $samePageCount++
        }

        # Si llevamos 3+ iteraciones en la misma pagina, hacer dump de controles
        if ($samePageCount -eq 3) {
            Write-Log "  ATASCADO en: '$currentTitle' - analizando controles..." 'WARN'
            Dump-AllControls -Window $win
        }

        # Si llevamos 10+ iteraciones, intentar tecla Enter como ultimo recurso
        if ($samePageCount -ge 10 -and $samePageCount % 5 -eq 0) {
            Write-Log "  Intentando Enter como ultimo recurso..." 'WARN'
            try {
                [PInvoke.Win32UI]::SetForegroundWindow($win.Current.NativeWindowHandle)
                Start-Sleep -Milliseconds 200
                [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
                $clickCount++
                Start-Sleep -Seconds 2
                continue
            } catch {}
        }

        $clicked = $false

        # -- PASO 1: Seleccionar radio button de licencia (si existe) --
        if (-not $clicked) {
            $rbSelected = Select-RadioButton -Window $win -Patterns $acceptRadio
            if ($rbSelected) {
                $clicked = $true
                Start-Sleep -Milliseconds 500
                # Despues de seleccionar radio, pulsar Siguiente inmediatamente
                $nextBtn = Find-FirstButton -Window $win -Names $nextBtns
                if ($nextBtn) {
                    Start-Sleep -Milliseconds 300
                    Click-Element -Element $nextBtn.Element -Label $nextBtn.Name | Out-Null
                    $clickCount++
                }
            }
        }

        # -- PASO 2: Buscar checkboxes de acuerdo (algunos usan checkbox en vez de radio) --
        if (-not $clicked) {
            $cbCondition = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::CheckBox)
            $checkboxes = $win.FindAll(
                [System.Windows.Automation.TreeScope]::Descendants, $cbCondition)
            foreach ($cb in $checkboxes) {
                try {
                    $cbName = $cb.Current.Name
                    foreach ($pat in $acceptRadio) {
                        if ($cbName -like "*$pat*") {
                            $toggle = $cb.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
                            if ($toggle.Current.ToggleState -ne 'On') {
                                $toggle.Toggle()
                                Write-Log "    Checkbox marcado: '$cbName'" 'OK'
                                $clicked = $true
                                Start-Sleep -Milliseconds 500
                                # Pulsar Siguiente
                                $nextBtn = Find-FirstButton -Window $win -Names $nextBtns
                                if ($nextBtn) {
                                    Click-Element -Element $nextBtn.Element -Label $nextBtn.Name | Out-Null
                                    $clickCount++
                                }
                            }
                            break
                        }
                    }
                } catch {}
                if ($clicked) { break }
            }
        }

        # -- PASO 3: Botones Accept/Agree --
        if (-not $clicked) {
            $btn = Find-FirstButton -Window $win -Names $acceptBtns
            if ($btn) { $clicked = Click-Element -Element $btn.Element -Label $btn.Name }
        }

        # -- PASO 4: Boton Install --
        if (-not $clicked) {
            $btn = Find-FirstButton -Window $win -Names $installBtns
            if ($btn) { $clicked = Click-Element -Element $btn.Element -Label $btn.Name }
        }

        # -- PASO 5: Boton Siguiente --
        if (-not $clicked) {
            $btn = Find-FirstButton -Window $win -Names $nextBtns
            if ($btn -and $btn.Element.Current.IsEnabled) {
                $clicked = Click-Element -Element $btn.Element -Label $btn.Name
            }
        }

        # -- PASO 6: Boton Skip/Omitir --
        if (-not $clicked) {
            $btn = Find-FirstButton -Window $win -Names $skipBtns
            if ($btn) { $clicked = Click-Element -Element $btn.Element -Label $btn.Name }
        }

        # -- PASO 7: Boton Finish/Cerrar --
        if (-not $clicked) {
            $btn = Find-FirstButton -Window $win -Names $finishBtns
            if ($btn) { $clicked = Click-Element -Element $btn.Element -Label $btn.Name }
        }

        if ($clicked) {
            $clickCount++
            Start-Sleep -Seconds 2
        } else {
            Start-Sleep -Seconds 2
        }
    }

    # Matar GUIs residuales de Wondershare
    Start-Sleep -Seconds 3
    'PDFelement','Wondershare PDFelement','wshelper','WsAppService',
    'ElevationService','Wondershare Helper Compact' | ForEach-Object {
        Get-Process -Name $_ -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
    }

    # Verificacion final
    Start-Sleep -Seconds 2
    if (Test-AppInstalled -Keywords @('PDFelement','Wondershare')) {
        Write-Log "  PDFelement INSTALADO OK ($clickCount acciones)" 'OK'
    } else {
        Write-Log "  PDFelement no detectado en registro" 'ERROR'
        Write-Log "  Acciones realizadas: $clickCount" 'WARN'
    }
}

# ==============================================================
# IMANAGE WORK DESKTOP - UI AUTOMATION (mismo sistema que PDFelement)
# ==============================================================

function Install-iManageWork {
    <#
    .SYNOPSIS
        Instala iManage Work Desktop via UI Automation.
        Wizard: Welcome (Next) -> Licencia (Accept + Next) -> Install -> Finish
        Luego espera a que terminen los procesos msiexec hijos.
    #>
    Write-Log "== IMANAGE WORK DESKTOP - UI AUTOMATION =="

    if (Test-AppInstalled -Keywords @('iManage Work Desktop','iManage Work')) {
        Write-Log "  iManage Work Desktop ya instalado - SKIP" 'OK'
        return
    }

    $imExe = "$Source\Imanage 2.0\iManage Work Desktop for Windows 10.9.4.39 (x64 Office)\iManageWorkDesktopforWindowsx64.exe"

    if (-not (Test-Path $imExe)) {
        Write-Log "  Archivo no encontrado: $imExe" 'ERROR'
        return
    }

    # Cargar UI Automation si no esta cargado (por si se ejecuta Solo-IM)
    Add-Type -AssemblyName UIAutomationClient -EA SilentlyContinue
    Add-Type -AssemblyName UIAutomationTypes -EA SilentlyContinue
    Add-Type -AssemblyName System.Windows.Forms -EA SilentlyContinue
    Add-Type -MemberDefinition @'
        [DllImport("user32.dll")]
        public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, int dwExtraInfo);
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);
'@ -Name 'Win32UI' -Namespace 'PInvoke' -EA SilentlyContinue

    # Reutilizar funciones ya definidas en Install-PDFelement
    # Si se ejecuta Solo-IM, necesitamos las funciones aqui tambien

    function IM-ClickElement {
        param([System.Windows.Automation.AutomationElement]$Element, [string]$Label)
        try {
            $ip = $Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
            $ip.Invoke()
            Write-Log "    Click (Invoke): '$Label'" 'OK'
            return $true
        } catch {}
        try {
            $sp = $Element.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
            $sp.Select()
            Write-Log "    Click (Select): '$Label'" 'OK'
            return $true
        } catch {}
        try {
            $rect = $Element.Current.BoundingRectangle
            if ($rect.Width -gt 0 -and $rect.Height -gt 0) {
                $x = [int]($rect.X + $rect.Width / 2)
                $y = [int]($rect.Y + $rect.Height / 2)
                [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
                Start-Sleep -Milliseconds 150
                [PInvoke.Win32UI]::mouse_event(0x0002, 0, 0, 0, 0)
                [PInvoke.Win32UI]::mouse_event(0x0004, 0, 0, 0, 0)
                Write-Log "    Click (coords $x,$y): '$Label'" 'OK'
                return $true
            }
        } catch {}
        return $false
    }

    function IM-FindFirstButton {
        param(
            [System.Windows.Automation.AutomationElement]$Window,
            [string[]]$Names
        )
        foreach ($n in $Names) {
            $cName = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::NameProperty, $n)
            $cType = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::Button)
            $cAnd  = New-Object System.Windows.Automation.AndCondition($cName, $cType)
            $el = $Window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cAnd)
            if ($el) { return @{ Element = $el; Name = $n } }
        }
        return $null
    }

    function IM-SelectRadio {
        param(
            [System.Windows.Automation.AutomationElement]$Window,
            [string[]]$Patterns
        )
        $rbCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::RadioButton)
        $radios = $Window.FindAll(
            [System.Windows.Automation.TreeScope]::Descendants, $rbCond)
        foreach ($rb in $radios) {
            try {
                $rbName = $rb.Current.Name
                foreach ($pat in $Patterns) {
                    if ($rbName -like "*$pat*") {
                        return (IM-ClickElement -Element $rb -Label "Radio: $rbName")
                    }
                }
            } catch {}
        }
        return $false
    }

    function IM-GetWindow {
        param([int]$TimeoutSec = 10)
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $root = [System.Windows.Automation.AutomationElement]::RootElement
        while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
            $windows = $root.FindAll(
                [System.Windows.Automation.TreeScope]::Children,
                [System.Windows.Automation.Condition]::TrueCondition)
            foreach ($w in $windows) {
                try {
                    $title = $w.Current.Name
                    if ($title -match 'iManage|InstallShield|Work Desktop') {
                        return $w
                    }
                } catch {}
            }
            Start-Sleep -Milliseconds 400
        }
        return $null
    }

    # -- Lanzar instalador --
    Write-Log "  Lanzando instalador iManage Work Desktop..."
    $proc = Start-Process -FilePath $imExe -PassThru

    # -- Bucle UI Automation --
    Write-Log "  UI Automation - detectando wizard iManage..."
    $maxWait       = 600
    $swTotal       = [Diagnostics.Stopwatch]::StartNew()
    $clickCount    = 0
    $samePageCount = 0
    $pageHash      = ''

    # Botones del wizard iManage (InstallShield - ingles normalmente)
    $nextBtns    = @('Next >','Next','Siguiente >','Siguiente')
    $acceptBtns  = @('I Agree','I Accept','Accept','Yes','Acepto','Aceptar','OK')
    $installBtns = @('Install','Instalar')
    $finishBtns  = @('Finish','Finalizar','Close','Cerrar','Done','Complete')
    $acceptRadio = @('I accept','I agree','Acepto','accept the terms',
                      'accept the license','accept the agreement')

    while ($swTotal.Elapsed.TotalSeconds -lt $maxWait) {
        if ($proc.HasExited) {
            Write-Log "  Proceso wrapper finalizado (code=$($proc.ExitCode))"
            # InstallShield: el wrapper sale pero msiexec puede seguir
            break
        }

        $win = IM-GetWindow -TimeoutSec 5
        if (-not $win) {
            Start-Sleep -Seconds 2
            continue
        }

        # Detectar cambio de pagina
        $currentTitle = $win.Current.Name
        $btnState = ''
        try {
            $btns = $win.FindAll(
                [System.Windows.Automation.TreeScope]::Descendants,
                (New-Object System.Windows.Automation.PropertyCondition(
                    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                    [System.Windows.Automation.ControlType]::Button)))
            foreach ($b in $btns) {
                try { $btnState += $b.Current.Name + $b.Current.IsEnabled.ToString() } catch {}
            }
        } catch {}
        $newHash = "$currentTitle|$btnState"

        if ($newHash -ne $pageHash) {
            $pageHash = $newHash
            $samePageCount = 0
            Write-Log "  Pagina: '$currentTitle'"
        } else {
            $samePageCount++
        }

        # Dump de controles si atascado
        if ($samePageCount -eq 4) {
            Write-Log "  ATASCADO - dump de controles:" 'WARN'
            try {
                $all = $win.FindAll(
                    [System.Windows.Automation.TreeScope]::Descendants,
                    [System.Windows.Automation.Condition]::TrueCondition)
                foreach ($el in $all) {
                    try {
                        $n = $el.Current.Name
                        $t = $el.Current.ControlType.ProgrammaticName
                        if ($n -and $n.Length -gt 0) {
                            Write-Log "      [$t] '$n' (enabled=$($el.Current.IsEnabled))"
                        }
                    } catch {}
                }
            } catch {}
        }

        # Enter como ultimo recurso
        if ($samePageCount -ge 8 -and $samePageCount % 4 -eq 0) {
            Write-Log "  Intentando Enter..." 'WARN'
            try {
                [PInvoke.Win32UI]::SetForegroundWindow($win.Current.NativeWindowHandle)
                Start-Sleep -Milliseconds 200
                [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
                $clickCount++
                Start-Sleep -Seconds 2
                continue
            } catch {}
        }

        $clicked = $false

        # 1. Radio buttons de licencia
        if (-not $clicked) {
            $rbClicked = IM-SelectRadio -Window $win -Patterns $acceptRadio
            if ($rbClicked) {
                $clicked = $true
                Start-Sleep -Milliseconds 500
                $nextBtn = IM-FindFirstButton -Window $win -Names $nextBtns
                if ($nextBtn) {
                    IM-ClickElement -Element $nextBtn.Element -Label $nextBtn.Name | Out-Null
                    $clickCount++
                }
            }
        }

        # 2. Checkboxes de acuerdo
        if (-not $clicked) {
            try {
                $cbCond = New-Object System.Windows.Automation.PropertyCondition(
                    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                    [System.Windows.Automation.ControlType]::CheckBox)
                $cbs = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cbCond)
                foreach ($cb in $cbs) {
                    $cbName = $cb.Current.Name
                    foreach ($pat in $acceptRadio) {
                        if ($cbName -like "*$pat*") {
                            $toggle = $cb.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
                            if ($toggle.Current.ToggleState -ne 'On') {
                                $toggle.Toggle()
                                Write-Log "    Checkbox: '$cbName'" 'OK'
                                $clicked = $true
                                Start-Sleep -Milliseconds 500
                                $nextBtn = IM-FindFirstButton -Window $win -Names $nextBtns
                                if ($nextBtn) {
                                    IM-ClickElement -Element $nextBtn.Element -Label $nextBtn.Name | Out-Null
                                    $clickCount++
                                }
                            }
                            break
                        }
                    }
                    if ($clicked) { break }
                }
            } catch {}
        }

        # 3. Botones Accept
        if (-not $clicked) {
            $btn = IM-FindFirstButton -Window $win -Names $acceptBtns
            if ($btn) { $clicked = IM-ClickElement -Element $btn.Element -Label $btn.Name }
        }

        # 4. Boton Install
        if (-not $clicked) {
            $btn = IM-FindFirstButton -Window $win -Names $installBtns
            if ($btn) { $clicked = IM-ClickElement -Element $btn.Element -Label $btn.Name }
        }

        # 5. Boton Next (solo si habilitado)
        if (-not $clicked) {
            $btn = IM-FindFirstButton -Window $win -Names $nextBtns
            if ($btn -and $btn.Element.Current.IsEnabled) {
                $clicked = IM-ClickElement -Element $btn.Element -Label $btn.Name
            }
        }

        # 6. Finish
        if (-not $clicked) {
            $btn = IM-FindFirstButton -Window $win -Names $finishBtns
            if ($btn) { $clicked = IM-ClickElement -Element $btn.Element -Label $btn.Name }
        }

        if ($clicked) {
            $clickCount++
            Start-Sleep -Seconds 2
        } else {
            Start-Sleep -Seconds 2
        }
    }

    # -- Esperar msiexec hijos (InstallShield lanza msiexec internamente) --
    Write-Log "  Esperando procesos msiexec hijos..."
    $swMsi = [Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Seconds 5
    while ($swMsi.Elapsed.TotalSeconds -lt 300) {
        $msi = Get-Process -Name 'msiexec' -EA SilentlyContinue |
               Where-Object { $_.SessionId -ne 0 }
        if (-not $msi) { break }
        Write-Log "  msiexec activo... ($([int]$swMsi.Elapsed.TotalSeconds)s)"
        Start-Sleep -Seconds 5
    }
    Write-Log "  msiexec hijos finalizados ($([int]$swMsi.Elapsed.TotalSeconds)s)"

    # Verificacion
    Start-Sleep -Seconds 3
    if (Test-AppInstalled -Keywords @('iManage Work Desktop','iManage Work')) {
        Write-Log "  iManage Work Desktop INSTALADO OK ($clickCount acciones)" 'OK'
    } else {
        Write-Log "  iManage Work Desktop NO detectado en registro" 'ERROR'
    }
}

# ==============================================================
# EJECUCION
# ==============================================================

Write-Log "=========================================="
Write-Log " FIX PDFelement + iManage v2.0"
Write-Log " Modo: $Modo"
Write-Log "=========================================="
Write-Log "Log: $LogFile"
Write-Log ""

switch ($Modo) {
    'Solo-PDF' {
        Install-PDFelement
    }
    'Solo-IM' {
        Install-iManageWork
    }
    default {
        # 'Todo' o 'Grabar' (Grabar ya no existe, se usa UI Automation)
        Install-PDFelement
        Write-Log ""
        Install-iManageWork
    }
}

Write-Log ""
Write-Log "=========================================="
Write-Log " COMPLETADO"
Write-Log "=========================================="

# Limpiar
if (Test-Path $LocalDir) {
    Remove-Item $LocalDir -Recurse -Force -EA SilentlyContinue
}

Write-Host "`nPresiona Enter para cerrar..." -ForegroundColor Cyan
Read-Host
