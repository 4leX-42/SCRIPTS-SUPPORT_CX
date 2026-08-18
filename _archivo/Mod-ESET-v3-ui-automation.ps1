#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Mod-ESET.ps1 v3 - ESET Endpoint via UI Automation
.DESCRIPTION
    El live installer de ESET siempre abre GUI (--silent no funciona).
    Este modulo copia a local y automatiza los clicks del wizard.
    v3: Deteccion de estancamiento en fase de progreso, busqueda amplia
        de controles (Sciter custom GUI), fallback ENTER + coords.
.NOTES
    v3.0 - 2026-04-11
#>

$ErrorActionPreference = 'Continue'
$Source  = '\\servidor\utilidades\1.Node_Preparation'
$LogDir  = "$env:USERPROFILE\LOGS_Script"
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
$LogFile = "$LogDir\Mod_ESET_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$Cache   = "$env:TEMP\_Mod_ESET"

function Write-Log {
    param([string]$Msg, [string]$Level = 'INFO')
    $entry = "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Msg"
    switch ($Level) {
        'ERROR' { Write-Host $entry -ForegroundColor Red }
        'WARN'  { Write-Host $entry -ForegroundColor Yellow }
        'OK'    { Write-Host $entry -ForegroundColor Green }
        default { Write-Host $entry }
    }
    Add-Content -Path $LogFile -Value $entry
}

function Test-ESETEndpoint {
    $apps = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    ) | ForEach-Object { Get-ItemProperty $_ -EA SilentlyContinue } |
        Where-Object { $_.DisplayName -like '*ESET Endpoint*' }

    $svcRunning = (Get-Service -Name 'ekrn' -EA SilentlyContinue).Status -eq 'Running'
    return @{
        Installed = ($apps.Count -gt 0)
        Service   = $svcRunning
        Version   = ($apps | Select-Object -First 1).DisplayVersion
        Name      = ($apps | Select-Object -First 1).DisplayName
    }
}

function Show-ESETStatus {
    param([string]$Label)
    Write-Log "-- $Label --"
    $allEset = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    ) | ForEach-Object { Get-ItemProperty $_ -EA SilentlyContinue } |
        Where-Object { $_.DisplayName -like '*ESET*' }
    foreach ($app in $allEset) {
        $tag = if ($app.DisplayName -like '*ESET Endpoint*') { '** TARGET **' } else { '(ignorado)' }
        Write-Log "  $($app.DisplayName) v$($app.DisplayVersion) $tag"
    }
    if (-not $allEset) { Write-Log "  (sin entradas ESET en registro)" }
    $svcs = Get-Service -EA SilentlyContinue | Where-Object { $_.DisplayName -match 'ESET|ekrn' }
    foreach ($s in $svcs) { Write-Log "  Svc: $($s.Name) = $($s.Status)" }
    if (-not $svcs) { Write-Log "  (sin servicios ESET)" }
}

# ==============================================
# MAIN
# ==============================================

Write-Host ""
Write-Host "  ESET ENDPOINT - UI Automation v3" -ForegroundColor Magenta
Write-Host "  Log: $LogFile" -ForegroundColor DarkGray
Write-Host ""
Write-Log "=== Mod-ESET v3 ==="

# -- Pre-check --
Show-ESETStatus -Label 'PRE-CHECK'
$pre = Test-ESETEndpoint

if ($pre.Installed -and $pre.Service) {
    Write-Host "  ESET Endpoint ya instalado y activo: $($pre.Name) v$($pre.Version)" -ForegroundColor Green
    Write-Log "  Ya instalado - saltando" 'OK'
    Write-Host "  Presiona Enter para cerrar..." -ForegroundColor Cyan
    Read-Host
    exit 0
}

# -- Copiar a local --
$esetExe = "$Source\epi_win_live_installer.exe"
if (-not (Test-Path $esetExe)) {
    Write-Log "  No encontrado: $esetExe" 'ERROR'
    Write-Host "  Presiona Enter para cerrar..." -ForegroundColor Cyan
    Read-Host
    exit 1
}

if (-not (Test-Path $Cache)) { New-Item $Cache -ItemType Directory -Force | Out-Null }
$localExe = "$Cache\epi_win_live_installer.exe"
if (-not (Test-Path $localExe)) {
    Write-Log "  Copiando a local..."
    Write-Host "  Copiando instalador a local..." -ForegroundColor DarkGray
    Copy-Item $esetExe $localExe -Force
}

# -- Cargar UI Automation --
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -MemberDefinition @'
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, uint d, int e);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
'@ -Name 'W32' -Namespace 'ESET' -EA SilentlyContinue

# -- Funciones UI --

function ESET-FindWindow {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $wins = $root.FindAll(
        [System.Windows.Automation.TreeScope]::Children,
        [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($w in $wins) {
        try {
            $t = $w.Current.Name
            # EXCLUIR: editores, exploradores, terminales, desinstaladores
            if ($t -match 'Bloc de notas|Notepad|Visual Studio|Code|Explorer|Bulk|Uninstall|Update|Notification|Terminal|PowerShell|pwsh|cmd') {
                continue
            }
            # Solo ventanas ESET reales
            if ($t -match 'ESET|Endpoint.*Security|Package Installer') {
                # Traer al frente (el | Out-Null evita que el bool contamine el return)
                try { [ESET.W32]::SetForegroundWindow($w.Current.NativeWindowHandle) | Out-Null } catch {}
                return $w
            }
        } catch {}
    }
    return $null
}

function ESET-FindBtn {
    param($Win, [string[]]$Names)
    foreach ($n in $Names) {
        $cN = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty, $n)
        $cT = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Button)
        $el = $Win.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
            (New-Object System.Windows.Automation.AndCondition($cN, $cT)))
        if ($el) { return @{ E = $el; N = $n } }
    }
    return $null
}

function ESET-FindByType {
    param($Win, [System.Windows.Automation.ControlType]$Type)
    $c = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $Type)
    return $Win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $c)
}

function ESET-Click {
    param($El, [string]$Label)
    # Invoke
    try {
        $ip = $El.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        $ip.Invoke(); Write-Log "    Click (Invoke): '$Label'" 'OK'; return $true
    } catch {}
    # Select (radio)
    try {
        $sp = $El.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        $sp.Select(); Write-Log "    Click (Select): '$Label'" 'OK'; return $true
    } catch {}
    # Coords
    try {
        $rect = $El.Current.BoundingRectangle
        if ($rect.Width -gt 0) {
            $x = [int]($rect.X + $rect.Width / 2)
            $y = [int]($rect.Y + $rect.Height / 2)
            [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
            Start-Sleep -Milliseconds 150
            [ESET.W32]::mouse_event(0x0002,0,0,0,0)
            [ESET.W32]::mouse_event(0x0004,0,0,0,0)
            Write-Log "    Click (xy=$x,$y): '$Label'" 'OK'; return $true
        }
    } catch {}
    return $false
}

function ESET-FindAnyByName {
    # Busca CUALQUIER elemento (no solo Button) cuyo Name contenga alguno de los textos dados.
    # Necesario porque el GUI Sciter de ESET no siempre expone botones como ControlType::Button.
    param($Win, [string[]]$Names)
    $all = $Win.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($el in $all) {
        try {
            $n = $el.Current.Name
            if (-not $n -or $n.Length -eq 0) { continue }
            foreach ($target in $Names) {
                if ($n -eq $target) {
                    # Verificar que sea clickable (tiene InvokePattern, o coords validas)
                    $clickable = $false
                    try { $null = $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern); $clickable = $true } catch {}
                    if (-not $clickable) {
                        try {
                            $r = $el.Current.BoundingRectangle
                            if ($r.Width -gt 0 -and $r.Height -gt 0) { $clickable = $true }
                        } catch {}
                    }
                    if ($clickable) {
                        $ct = $el.Current.ControlType.ProgrammaticName
                        return @{ E = $el; N = "$target [$ct]" }
                    }
                }
            }
        } catch {}
    }
    return $null
}

function ESET-ClickCoords {
    # Click en coordenadas RELATIVAS a la ventana ESET (porcentaje 0.0-1.0)
    # Usado como ultimo recurso cuando UI Automation no expone el control (Sciter).
    param($Win, [double]$RelX, [double]$RelY, [string]$Label)
    try {
        $rect = $Win.Current.BoundingRectangle
        if ($rect.Width -le 0 -or $rect.Height -le 0) { return $false }
        $x = [int]($rect.X + $rect.Width  * $RelX)
        $y = [int]($rect.Y + $rect.Height * $RelY)
        [ESET.W32]::SetForegroundWindow($Win.Current.NativeWindowHandle) | Out-Null
        Start-Sleep -Milliseconds 200
        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
        Start-Sleep -Milliseconds 150
        [ESET.W32]::mouse_event(0x0002,0,0,0,0)  # LEFTDOWN
        [ESET.W32]::mouse_event(0x0004,0,0,0,0)  # LEFTUP
        Write-Log "    Click COORDS (${RelX},${RelY} -> abs=$x,$y): '$Label'" 'OK'
        return $true
    } catch {
        Write-Log "    Click COORDS fallo: $_" 'ERROR'
        return $false
    }
}

# Coordenadas relativas del boton "Continuar" en la pantalla de licencia ESET
# Medidas del screenshot: boton centrado en ~36% X, ~95% Y de la ventana
$btnContinuarRelX = 0.36
$btnContinuarRelY = 0.95

function ESET-DumpControls {
    param($Win)
    Write-Log "    -- DUMP --"
    try {
        $all = $Win.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($el in $all) {
            try {
                $n = $el.Current.Name; $t = $el.Current.ControlType.ProgrammaticName
                $en = $el.Current.IsEnabled
                if ($n -and $n.Length -gt 0) { Write-Log "      [$t] '$n' enabled=$en" }
            } catch {}
        }
    } catch {}
    Write-Log "    -- FIN DUMP --"
}

# -- Lanzar instalador --
Write-Log "  Lanzando desde local: $localExe"
Write-Host "  Lanzando instalador ESET..." -ForegroundColor Cyan
$proc = Start-Process -FilePath $localExe -PassThru
Write-Log "  PID=$($proc.Id)"

# -- Bucle UI Automation --
Write-Host "  UI Automation activa - automatizando wizard..." -ForegroundColor Cyan
Write-Host ""

$maxWait    = 600
$swTotal    = [Diagnostics.Stopwatch]::StartNew()
$clickCount = 0
$pageHash   = ''
$stuckCount = 0
$progressStuckCount = 0   # Iteraciones estancadas DENTRO de isProgress

# Botones en espanol + ingles
# IMPORTANTE: NO incluir Cancelar/Cerrar/Close - provocan cancelacion durante descarga
$continueBtns = @('Continuar','Continue','Seguir')
$nextBtns     = @('Siguiente','Next','Siguiente >','Next >')
$acceptBtns   = @('Acepto','Aceptar','Accept','I Agree','I Accept','Agree')
$installBtns  = @('Instalar','Install','Comenzar instalacion','Start installation')
$finishBtns   = @('Finalizar','Finish','Listo','Done','Hecho')   # SIN Cerrar/Close
$acceptRadio  = @('Acepto','I accept','I agree','Acepto los terminos',
                   'accept the terms','accept the license','accept the agreement',
                   'Acepto el acuerdo','Acepto las condiciones')

# Deteccion de progreso: se basa en BOTONES visibles, no en el titulo
# (el titulo de ESET concatena todo el texto de la ventana, incluyendo pasos previos)

while ($swTotal.Elapsed.TotalSeconds -lt $maxWait) {
    # Verificar si proceso termino
    # IMPORTANTE: el downloader puede salir pero la ventana del instalador real sigue abierta
    # Solo salir del bucle si el proceso termino Y no hay ventana ESET visible
    if ($proc.HasExited) {
        $winCheck = ESET-FindWindow
        if (-not $winCheck) {
            Write-Log "  Proceso cerrado y sin ventana ESET (code=$($proc.ExitCode))"
            break
        }
        # Hay ventana ESET abierta todavia -> seguir interactuando
    }

    # Buscar ventana ESET
    $win = ESET-FindWindow
    if (-not $win) {
        Start-Sleep -Seconds 3
        continue
    }

    # Detectar pagina
    $title = $win.Current.Name
    $bState = ''
    try {
        $btns = ESET-FindByType -Win $win -Type ([System.Windows.Automation.ControlType]::Button)
        foreach ($b in $btns) { try { $bState += $b.Current.Name + $b.Current.IsEnabled } catch {} }
    } catch {}
    $hash = "$title|$bState"

    if ($hash -ne $pageHash) {
        $pageHash = $hash; $stuckCount = 0
        # Titulo corto para el log (el titulo de ESET es gigante)
        $shortTitle = if ($title.Length -gt 80) { $title.Substring(0, 80) + '...' } else { $title }
        Write-Log "  Pagina: '$shortTitle'"
        Write-Host "  Pantalla: $shortTitle" -ForegroundColor DarkGray
    } else {
        $stuckCount++
    }

    # == DETECCION DE PROGRESO ==
    # Solo esperar si el UNICO boton es "Cancelar" (descarga/instalacion activa)
    # Comprobar via los botones reales, no el titulo (que concatena todo)
    $hasCancel   = $bState -match 'Cancelar|Cancel'
    $hasAction   = $bState -match 'Continuar|Continue|Siguiente|Next|Instalar|Install|Finalizar|Finish|Acepto|Accept'
    $isProgress  = $hasCancel -and -not $hasAction

    if ($isProgress) {
        # Contar iteraciones sin cambio de hash dentro de progreso
        if ($stuckCount -gt 0) {
            $progressStuckCount++
        } else {
            $progressStuckCount = 0
        }

        # Si estancado >30s en "progreso" sin cambio: puede ser 2da pantalla no detectada
        # El GUI Sciter NO expone "Continuar" como ningun ControlType -> $hasAction falso
        if ($progressStuckCount -ge 6) {
            Write-Log "  Progreso estancado ${progressStuckCount} iter - intentando fallbacks..." 'WARN'

            # Dump unico para diagnostico
            if ($progressStuckCount -eq 6) {
                ESET-DumpControls -Win $win
            }

            # === FALLBACK 1: Busqueda amplia por Name (iter 6+) ===
            $anyBtn = ESET-FindAnyByName -Win $win -Names ($continueBtns + $acceptBtns + $installBtns + $nextBtns)
            if ($anyBtn) {
                Write-Log "  Encontrado via busqueda amplia: '$($anyBtn.N)'" 'OK'
                if (ESET-Click -El $anyBtn.E -Label $anyBtn.N) {
                    $clickCount++
                    $progressStuckCount = 0
                    Start-Sleep -Seconds 3
                    continue
                }
            }

            # === FALLBACK 2: Click por coordenadas en posicion de "Continuar" (iter 7+) ===
            # El boton "Continuar" de la pantalla de licencia esta siempre en ~36% X, ~95% Y
            if ($progressStuckCount -ge 7 -and $progressStuckCount % 2 -eq 1) {
                Write-Log "  Fallback COORDS: click en posicion de Continuar ($btnContinuarRelX, $btnContinuarRelY)" 'WARN'
                if (ESET-ClickCoords -Win $win -RelX $btnContinuarRelX -RelY $btnContinuarRelY -Label 'Continuar (coords)') {
                    $clickCount++
                    $progressStuckCount = 0
                    Start-Sleep -Seconds 3
                    continue
                }
            }

            # === FALLBACK 3: SendKeys ENTER (iter 8+) ===
            if ($progressStuckCount -ge 8 -and $progressStuckCount % 2 -eq 0) {
                Write-Log "  Fallback: ENTER en ventana ESET" 'WARN'
                try {
                    [ESET.W32]::SetForegroundWindow($win.Current.NativeWindowHandle) | Out-Null
                    Start-Sleep -Milliseconds 300
                    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
                    $clickCount++
                    Start-Sleep -Seconds 3
                    continue
                } catch {}
            }

            # === FALLBACK 4: TAB+ENTER (iter 10+) ===
            if ($progressStuckCount -ge 10 -and $progressStuckCount % 4 -eq 0) {
                Write-Log "  Fallback: TAB+ENTER en ventana ESET" 'WARN'
                try {
                    [ESET.W32]::SetForegroundWindow($win.Current.NativeWindowHandle) | Out-Null
                    Start-Sleep -Milliseconds 300
                    [System.Windows.Forms.SendKeys]::SendWait('{TAB}')
                    Start-Sleep -Milliseconds 200
                    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
                    $clickCount++
                    Start-Sleep -Seconds 3
                    continue
                } catch {}
            }
        }

        $t = [int]$swTotal.Elapsed.TotalSeconds
        $spinChars = @('|','/','-','\')
        $s = $spinChars[$t % 4]
        $extra = if ($progressStuckCount -gt 0) { " stall=$progressStuckCount" } else { '' }
        Write-Host "`r  [$s] ESET descargando/instalando... ${t}s (esperando$extra)" -ForegroundColor DarkGray -NoNewline
        Start-Sleep -Seconds 5
        continue
    } else {
        $progressStuckCount = 0
    }

    # == DIALOGO DE CONFIRMACION DE CANCELACION: pulsar "No" ==
    if ($title -match 'seguro|sure|cancel.*confirm|cerrar.*asistente') {
        Write-Log "  Dialogo de cancelacion detectado - pulsando No" 'WARN'
        $noBtn = ESET-FindBtn -Win $win -Names @('No')
        if ($noBtn) {
            ESET-Click -El $noBtn.E -Label 'No (cancelar cancelacion)'
            $clickCount++
            Start-Sleep -Seconds 2
            continue
        }
    }

    # Dump si atascado 6 iteraciones (no durante progreso)
    if ($stuckCount -eq 6) {
        Write-Log "  ATASCADO en pagina no-progreso" 'WARN'
        ESET-DumpControls -Win $win
    }

    # Enter si muy atascado (solo en paginas no-progreso)
    if ($stuckCount -ge 15 -and $stuckCount % 5 -eq 0) {
        Write-Log "  Enviando Enter..." 'WARN'
        try {
            [ESET.W32]::SetForegroundWindow($win.Current.NativeWindowHandle)
            Start-Sleep -Milliseconds 200
            [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
            $clickCount++
            Start-Sleep -Seconds 2
            continue
        } catch {}
    }

    $clicked = $false

    # -- 1. Radio buttons de licencia --
    if (-not $clicked) {
        $rbs = ESET-FindByType -Win $win -Type ([System.Windows.Automation.ControlType]::RadioButton)
        foreach ($rb in $rbs) {
            try {
                $rn = $rb.Current.Name
                foreach ($p in $acceptRadio) {
                    if ($rn -like "*$p*") {
                        $clicked = ESET-Click -El $rb -Label "Radio: $rn"
                        if ($clicked) {
                            Start-Sleep -Milliseconds 500
                            $nb = ESET-FindBtn -Win $win -Names ($nextBtns + $continueBtns)
                            if ($nb) { ESET-Click -El $nb.E -Label $nb.N | Out-Null; $clickCount++ }
                        }
                        break
                    }
                }
            } catch {}
            if ($clicked) { break }
        }
    }

    # -- 2. Checkboxes de licencia --
    # Si estamos en pagina de "Acuerdo de licencia", marcar CUALQUIER checkbox
    if (-not $clicked) {
        $isLicensePage = ($title -match 'Acuerdo|License|licencia|EULA')
        $cbs = ESET-FindByType -Win $win -Type ([System.Windows.Automation.ControlType]::CheckBox)
        foreach ($cb in $cbs) {
            try {
                $cn = $cb.Current.Name
                $shouldCheck = $false

                # Marcar si el nombre matchea patrones de aceptacion
                foreach ($p in $acceptRadio) {
                    if ($cn -like "*$p*") { $shouldCheck = $true; break }
                }
                # En pagina de licencia, marcar CUALQUIER checkbox no marcado
                if ($isLicensePage -and -not $shouldCheck) { $shouldCheck = $true }

                if ($shouldCheck) {
                    try {
                        $tg = $cb.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
                        if ($tg.Current.ToggleState -ne 'On') {
                            $tg.Toggle()
                            Write-Log "    Checkbox marcado: '$cn'" 'OK'
                            $clicked = $true
                            Start-Sleep -Milliseconds 500
                            $nb = ESET-FindBtn -Win $win -Names ($nextBtns + $continueBtns)
                            if ($nb) { ESET-Click -El $nb.E -Label $nb.N | Out-Null; $clickCount++ }
                        }
                    } catch {}
                }
            } catch {}
            if ($clicked) { break }
        }
    }

    # -- 3. Boton Continuar --
    if (-not $clicked) {
        $b = ESET-FindBtn -Win $win -Names $continueBtns
        if ($b) { $clicked = ESET-Click -El $b.E -Label $b.N }
    }

    # -- 4. Botones Accept --
    if (-not $clicked) {
        $b = ESET-FindBtn -Win $win -Names $acceptBtns
        if ($b) { $clicked = ESET-Click -El $b.E -Label $b.N }
    }

    # -- 5. Boton Install --
    if (-not $clicked) {
        $b = ESET-FindBtn -Win $win -Names $installBtns
        if ($b) { $clicked = ESET-Click -El $b.E -Label $b.N }
    }

    # -- 6. Boton Next/Siguiente (solo si habilitado) --
    if (-not $clicked) {
        $b = ESET-FindBtn -Win $win -Names $nextBtns
        if ($b -and $b.E.Current.IsEnabled) { $clicked = ESET-Click -El $b.E -Label $b.N }
    }

    # -- 7. Finish/Finalizar (solo si NO hay progreso activo) --
    if (-not $clicked) {
        $b = ESET-FindBtn -Win $win -Names $finishBtns
        if ($b) { $clicked = ESET-Click -El $b.E -Label $b.N }
    }

    # -- 8. Busqueda amplia (cualquier ControlType con nombre de accion) --
    # Sciter no siempre expone botones como Button; buscar por Name en todos los tipos
    if (-not $clicked) {
        $anyBtn = ESET-FindAnyByName -Win $win -Names ($continueBtns + $acceptBtns + $installBtns + $nextBtns + $finishBtns)
        if ($anyBtn) {
            Write-Log "    Encontrado (busqueda amplia): '$($anyBtn.N)'"
            $clicked = ESET-Click -El $anyBtn.E -Label $anyBtn.N
        }
    }

    # -- 9. Hyperlinks clickables --
    if (-not $clicked) {
        $hls = ESET-FindByType -Win $win -Type ([System.Windows.Automation.ControlType]::Hyperlink)
        foreach ($hl in $hls) {
            try {
                $hn = $hl.Current.Name
                $safeTargets = $continueBtns + $acceptBtns + $nextBtns
                foreach ($target in $safeTargets) {
                    if ($hn -like "*$target*") {
                        $clicked = ESET-Click -El $hl -Label "Link: $hn"
                        break
                    }
                }
            } catch {}
            if ($clicked) { break }
        }
    }

    # -- 10. Fallback coords: si nada funciono y estamos atascados en pagina de licencia --
    if (-not $clicked -and $stuckCount -ge 4 -and $title -match 'Acuerdo|License|licencia|EULA') {
        Write-Log "    Pagina licencia sin boton detectable - click coords Continuar" 'WARN'
        $clicked = ESET-ClickCoords -Win $win -RelX $btnContinuarRelX -RelY $btnContinuarRelY -Label 'Continuar (coords-licencia)'
    }

    if ($clicked) {
        $clickCount++
        Start-Sleep -Seconds 3
    } else {
        Start-Sleep -Seconds 2
    }
}

# -- Esperar procesos ESET post-install --
Write-Host ""
Write-Host "  Esperando a que ESET termine de configurarse..." -ForegroundColor DarkGray
Write-Log "  Esperando procesos ESET post-install..."

$swPost = [Diagnostics.Stopwatch]::StartNew()
Start-Sleep -Seconds 10

while ($swPost.Elapsed.TotalSeconds -lt 120) {
    $ep = Get-Process | Where-Object { $_.Name -match 'epi_win|eset.*install|msiexec' -and $_.SessionId -ne 0 }
    if (-not $ep) { break }
    $t = [int]$swPost.Elapsed.TotalSeconds
    Write-Host "`r  Procesos activos... ${t}s  " -ForegroundColor DarkGray -NoNewline
    Start-Sleep -Seconds 5
}
Write-Host "`r  $(' ' * 40)"
Write-Log "  Procesos finalizados ($([int]$swPost.Elapsed.TotalSeconds)s)"

# -- Resultado --
Write-Host ""
Start-Sleep -Seconds 5
Show-ESETStatus -Label 'POST-CHECK'
$final = Test-ESETEndpoint

if ($final.Installed) {
    Write-Host ""
    Write-Host "  ESET Endpoint $($final.Version) INSTALADO" -ForegroundColor Green
    Write-Log "  RESULTADO: INSTALADO v$($final.Version) ($clickCount acciones)" 'OK'
    if ($final.Service) {
        Write-Host "  Servicio ekrn ACTIVO" -ForegroundColor Green
    } else {
        Write-Host "  Servicio ekrn pendiente (puede requerir reinicio)" -ForegroundColor Yellow
    }
} else {
    Write-Host ""
    Write-Host "  ESET Endpoint NO INSTALADO" -ForegroundColor Red
    Write-Log "  RESULTADO: NO INSTALADO ($clickCount acciones)" 'ERROR'
    Write-Host "  Acciones UI realizadas: $clickCount" -ForegroundColor Yellow
    Write-Host "  Revisar log para diagnostico" -ForegroundColor Yellow
}

# Limpiar
if (Test-Path $Cache) { Remove-Item $Cache -Recurse -Force -EA SilentlyContinue }

Write-Host ""
Write-Host "  Log: $LogFile" -ForegroundColor DarkGray
Write-Host "  Presiona Enter para cerrar..." -ForegroundColor Cyan
Read-Host
