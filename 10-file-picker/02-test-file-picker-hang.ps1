<#
.SYNOPSIS
    [ES] Solo lectura. Reproduce el cuelgue del selector y captura el DLL que lo provoca.
    [EN] Read-only. Reproduces the file picker hang and captures the DLL behind it.

.DESCRIPTION
    El Common Item Dialog (IFileOpenDialog) NO es un proceso aparte: corre dentro
    del proceso que lo invoca. Por eso el componente que lo cuelga esta cargado
    en ese mismo proceso, y la prueba decisiva no es el Visor de eventos sino la
    lista de modulos cargados en el momento del cuelgue.

    Modo REPRO (por defecto):
      1. Lanza un powershell.exe -STA hijo que prepara un OpenFileDialog y
         espera a una senal, sin abrirlo todavia.
      2. Toma la foto de modulos cargados (linea base limpia).
      3. Da la senal y cronometra hasta que aparece la ventana del dialogo
         (clase Win32 #32770) y hasta que esa ventana responde a un mensaje.
      4. Si supera el timeout: vuelve a fotografiar los modulos. El DELTA son
         exactamente los DLL que cargo el picker; los de terceros en esa lista
         son la lista corta de sospechosos.
      5. Cierra el dialogo y mata el hijo. No deja nada.

    Modo ADJUNTAR (-Proceso outlook):
      Sobre una aplicacion YA colgada: modulos de terceros cargados, estado de
      los hilos y, si hay procdump.exe disponible, volcado completo para WinDbg.

    Ventaja del modo repro: no hay que colgar Outlook ni pedirle al usuario que
    reproduzca nada, y el resultado es la misma pila de codigo.

    Compatible PowerShell 5.1 y 7. No requiere admin salvo para volcar procesos
    de otra sesion.

.PARAMETER TimeoutSegundos
    Espera maxima a que el dialogo aparezca y responda. Por defecto 20.

.PARAMETER Proceso
    Nombre o PID de un proceso YA colgado al que adjuntarse en vez de reproducir.

.PARAMETER CarpetaInicial
    Fuerza la carpeta de arranque del dialogo. Sirve para senalar al culpable:
    si con -CarpetaInicial C:\ no cuelga y sin parametro si, la causa esta en la
    carpeta que el MRU recuerda para esa aplicacion.

.PARAMETER Volcado
    Genera volcado completo con procdump.exe si esta en PATH o en -RutaProcdump.

.PARAMETER RutaProcdump
    Ruta a procdump.exe (Sysinternals) si no esta en PATH.

.PARAMETER OutDir
    Carpeta de salida. Por defecto %TEMP%\FilePickerDiag.

.EXAMPLE
    .\02-test-file-picker-hang.ps1
.EXAMPLE
    .\02-test-file-picker-hang.ps1 -CarpetaInicial C:\ -TimeoutSegundos 30
.EXAMPLE
    .\02-test-file-picker-hang.ps1 -Proceso outlook -Volcado

.NOTES
    PowerShell 5.1 y 7.
    No modifica el sistema. El unico proceso que crea es su propio hijo de prueba.
#>
[CmdletBinding()]
param(
    [int]$TimeoutSegundos = 20,
    [string]$Proceso,
    [string]$CarpetaInicial,
    [switch]$Volcado,
    [string]$RutaProcdump,
    [string]$OutDir
)
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

# ------------------------------------------------------------------- interop
if (-not ('W11Picker.Win32' -as [type])) {
    Add-Type -Namespace W11Picker -Name Win32 -MemberDefinition @'
[DllImport("user32.dll")]
public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, System.IntPtr lParam);
public delegate bool EnumWindowsProc(System.IntPtr hWnd, System.IntPtr lParam);
[DllImport("user32.dll")]
public static extern uint GetWindowThreadProcessId(System.IntPtr hWnd, out uint pid);
[DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Auto)]
public static extern int GetClassName(System.IntPtr hWnd, System.Text.StringBuilder buf, int n);
[DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Auto)]
public static extern int GetWindowText(System.IntPtr hWnd, System.Text.StringBuilder buf, int n);
[DllImport("user32.dll")]
public static extern bool IsWindowVisible(System.IntPtr hWnd);
[DllImport("user32.dll", SetLastError = true)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint msg, System.IntPtr wp, System.IntPtr lp, uint flags, uint timeout, out System.IntPtr result);
[DllImport("user32.dll")]
public static extern bool PostMessage(System.IntPtr hWnd, uint msg, System.IntPtr wp, System.IntPtr lp);
'@
}

function Get-VentanasDe {
    param([int]$ProcId)
    $lista = New-Object System.Collections.Generic.List[object]
    $cb = [W11Picker.Win32+EnumWindowsProc] {
        param($h, $l)
        $p = 0
        [void][W11Picker.Win32]::GetWindowThreadProcessId($h, [ref]$p)
        if ($p -eq $ProcId) {
            $sbC = New-Object System.Text.StringBuilder 256
            [void][W11Picker.Win32]::GetClassName($h, $sbC, 256)
            $sbT = New-Object System.Text.StringBuilder 512
            [void][W11Picker.Win32]::GetWindowText($h, $sbT, 512)
            $lista.Add([pscustomobject]@{
                Handle  = $h
                Clase   = $sbC.ToString()
                Titulo  = $sbT.ToString()
                Visible = [W11Picker.Win32]::IsWindowVisible($h)
            })
        }
        return $true
    }
    [void][W11Picker.Win32]::EnumWindows($cb, [IntPtr]::Zero)
    return $lista
}

function Test-VentanaResponde {
    param([IntPtr]$Handle, [int]$Ms = 2000)
    $r = [IntPtr]::Zero
    # WM_NULL = 0x0000 ; SMTO_ABORTIFHUNG (0x0002) | SMTO_BLOCK (0x0001)
    $ret = [W11Picker.Win32]::SendMessageTimeout($Handle, 0, [IntPtr]::Zero, [IntPtr]::Zero, 3, [uint32]$Ms, [ref]$r)
    return ($ret -ne [IntPtr]::Zero)
}

function Resolve-OutDir {
    param([string]$Propuesto)
    if ($Propuesto) {
        $d = $Propuesto
    } else {
        $d = Join-Path $env:TEMP 'FilePickerDiag'
    }
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    return $d
}

$script:CacheFirma = @{}
function Get-FirmanteDll {
    param([string]$Path)
    if (-not $Path) { return 'n/d' }
    if ($script:CacheFirma.ContainsKey($Path)) { return $script:CacheFirma[$Path] }
    $val = 'FICHERO NO ENCONTRADO'
    if (Test-Path -LiteralPath $Path) {
        try {
            $s = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
            if ($s.SignerCertificate) {
                $cn = ($s.SignerCertificate.Subject -split ',' | Where-Object { $_ -match '^\s*CN=' }) -replace '^\s*CN=', ''
                if (-not $cn) { $cn = $s.SignerCertificate.Subject }
                $val = ($cn -join '')
            } else { $val = 'SIN FIRMA' }
        } catch { $val = 'ERROR AL VERIFICAR' }
    }
    $script:CacheFirma[$Path] = $val
    return $val
}

function Test-EsMicrosoft {
    param([string]$Firmante, [string]$Dll)
    if ($Firmante -match 'Microsoft (Corporation|Windows)') { return $true }
    if ($Dll -and $Dll -match '(?i)^[A-Z]:\\Windows\\(System32|SysWOW64|WinSxS)\\') { return $true }
    return $false
}

function Get-Modulos {
    param([System.Diagnostics.Process]$P)
    $out = New-Object System.Collections.Generic.List[object]
    try {
        $P.Refresh()
        foreach ($m in $P.Modules) {
            $out.Add([pscustomobject]@{ Nombre = $m.ModuleName; Ruta = $m.FileName })
        }
    } catch {
        Write-Host ('  No se pudo leer la lista de modulos: ' + $_.Exception.Message) -ForegroundColor Yellow
    }
    return $out
}

function Show-ModulosTerceros {
    param([object[]]$Modulos, [string]$Titulo)
    $t = foreach ($m in $Modulos) {
        $f = Get-FirmanteDll $m.Ruta
        if (Test-EsMicrosoft $f $m.Ruta) { continue }
        [pscustomobject]@{ Modulo = $m.Nombre; Firmante = $f; Ruta = $m.Ruta }
    }
    $t = @($t)
    Write-Host ''
    Write-Host ('  ' + $Titulo + ': ' + $t.Count + ' modulo(s) de terceros') -ForegroundColor Yellow
    if ($t.Count) { $t | Format-Table -AutoSize | Out-String -Width 240 | Write-Host }
    return $t
}

function Invoke-Procdump {
    param([int]$ProcId, [string]$Destino)
    $exe = $RutaProcdump
    if (-not $exe) {
        $c = Get-Command procdump.exe -ErrorAction SilentlyContinue
        if ($c) { $exe = $c.Source }
    }
    if (-not $exe -or -not (Test-Path $exe)) {
        Write-Host '  procdump.exe no encontrado. Alternativa sin instalar nada:' -ForegroundColor Yellow
        Write-Host '  Administrador de tareas > Detalles > clic derecho en el proceso > Crear archivo de volcado.' -ForegroundColor Yellow
        return
    }
    Write-Host ('  Volcando PID ' + $ProcId + ' con ' + $exe + ' ...')
    & $exe -accepteula -ma $ProcId $Destino 2>&1 | Select-Object -Last 3 | ForEach-Object { Write-Host ('  ' + $_) }
}

# ------------------------------------------------------------------- arranque
$OutDir = Resolve-OutDir $OutDir
$stamp  = Get-Date -Format 'yyyyMMdd-HHmm'

Write-Host ''
Write-Host '############################################################' -ForegroundColor White
Write-Host '  Prueba de cuelgue del File Picker (IFileOpenDialog)' -ForegroundColor White
Write-Host ('  ' + $env:COMPUTERNAME + ' / ' + $env:USERNAME + '   ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')) -ForegroundColor White
Write-Host '############################################################' -ForegroundColor White

# ------------------------------------------------------------ modo ADJUNTAR
if ($Proceso) {
    $procs = @()
    if ($Proceso -match '^\d+$') { $procs = @(Get-Process -Id ([int]$Proceso) -ErrorAction SilentlyContinue) }
    else { $procs = @(Get-Process -Name ($Proceso -replace '\.exe$','') -ErrorAction SilentlyContinue) }
    if (-not $procs.Count) { Write-Host ('  No hay ningun proceso ' + $Proceso) -ForegroundColor Red; return }

    foreach ($p in $procs) {
        Write-Host ''
        Write-Host ('== PID ' + $p.Id + '  ' + $p.ProcessName + '  responde=' + $p.Responding) -ForegroundColor Cyan
        $mods = Get-Modulos $p
        Write-Host ('  Modulos cargados: ' + $mods.Count)
        $terceros = Show-ModulosTerceros -Modulos $mods -Titulo 'Cargados en el proceso'
        $csv = Join-Path $OutDir ('hang-modulos-' + $p.ProcessName + '-' + $p.Id + '-' + $stamp + '.csv')
        $mods | ForEach-Object {
            $f = Get-FirmanteDll $_.Ruta
            [pscustomobject]@{ Modulo = $_.Nombre; Firmante = $f; EsMicrosoft = (Test-EsMicrosoft $f $_.Ruta); Ruta = $_.Ruta }
        } | Export-Csv $csv -NoTypeInformation -Encoding UTF8
        Write-Host ('  CSV: ' + $csv)

        Write-Host ''
        Write-Host '  Hilos en espera (los primeros 10 por tiempo de CPU):'
        try {
            $p.Threads | Sort-Object -Property TotalProcessorTime -Descending | Select-Object -First 10 |
                Select-Object Id, ThreadState, WaitReason, @{n='CPU';e={$_.TotalProcessorTime}} |
                Format-Table -AutoSize | Out-String -Width 200 | Write-Host
        } catch { Write-Host '  (sin acceso a los hilos)' -ForegroundColor Yellow }

        $v = @(Get-VentanasDe -ProcId $p.Id | Where-Object { $_.Visible })
        Write-Host ('  Ventanas visibles: ' + $v.Count)
        foreach ($w in $v) {
            $r = Test-VentanaResponde -Handle $w.Handle -Ms 2000
            $et = 'RESPONDE'
            if (-not $r) { $et = 'NO RESPONDE' }
            $col = 'Gray'
            if (-not $r) { $col = 'Red' }
            Write-Host ('   [' + $et + '] clase=' + $w.Clase + '  titulo=' + $w.Titulo) -ForegroundColor $col
        }
        if ($Volcado) {
            Invoke-Procdump -ProcId $p.Id -Destino (Join-Path $OutDir ('hang-' + $p.ProcessName + '-' + $p.Id + '-' + $stamp + '.dmp'))
        }
    }
    Write-Host ''
    Write-Host '  Lectura: el DLL de terceros mas sospechoso es el que pertenezca a una' -ForegroundColor Cyan
    Write-Host '  extension de shell, un cliente DMS o un agente de seguridad.' -ForegroundColor Cyan
    Write-Host '  Bloquearlo de forma reversible con 04-block-shell-extension.ps1.' -ForegroundColor Cyan
    return
}

# --------------------------------------------------------------- modo REPRO
$tmp   = Join-Path $env:TEMP ('picker-test-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$ready = Join-Path $tmp 'ready.flag'
$go    = Join-Path $tmp 'go.flag'

$carpeta = ''
if ($CarpetaInicial) { $carpeta = $CarpetaInicial }

$hijo = @'
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
$d = New-Object System.Windows.Forms.OpenFileDialog
$d.AutoUpgradeEnabled = $true      # fuerza IFileOpenDialog, el mismo del problema
$d.Title = 'PRUEBA FILE PICKER - se cierra sola'
$d.RestoreDirectory = $false
if ($env:PICKER_DIR) { $d.InitialDirectory = $env:PICKER_DIR }
New-Item -ItemType File -Path $env:PICKER_READY -Force | Out-Null
while (-not (Test-Path $env:PICKER_GO)) { Start-Sleep -Milliseconds 50 }
[void]$d.ShowDialog()
'@
$hijoB64 = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($hijo))

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName        = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
$psi.Arguments       = '-STA -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand ' + $hijoB64
$psi.UseShellExecute = $false
$psi.EnvironmentVariables['PICKER_READY'] = $ready
$psi.EnvironmentVariables['PICKER_GO']    = $go
$psi.EnvironmentVariables['PICKER_DIR']   = $carpeta

Write-Host ''
if ($carpeta) { Write-Host ('  Carpeta inicial forzada : ' + $carpeta) }
else          { Write-Host '  Carpeta inicial         : la que recuerde el sistema (comportamiento real)' }
Write-Host ('  Timeout                 : ' + $TimeoutSegundos + ' s')

$proc = [System.Diagnostics.Process]::Start($psi)
Write-Host ('  Proceso de prueba       : PID ' + $proc.Id)

# esperar a que el hijo este listo pero SIN haber abierto el dialogo
$t0 = [System.Diagnostics.Stopwatch]::StartNew()
while (-not (Test-Path $ready) -and $t0.Elapsed.TotalSeconds -lt 30 -and -not $proc.HasExited) {
    Start-Sleep -Milliseconds 100
}
if (-not (Test-Path $ready)) {
    Write-Host '  El proceso de prueba no llego a estar listo. Abortando.' -ForegroundColor Red
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    return
}

$base = Get-Modulos $proc
Write-Host ('  Linea base de modulos   : ' + $base.Count + ' (antes de abrir el dialogo)')

# senal: abre el dialogo
New-Item -ItemType File -Path $go -Force | Out-Null
$sw = [System.Diagnostics.Stopwatch]::StartNew()

$hwnd     = [IntPtr]::Zero
$msVisible = -1
$responde = $false
while ($sw.Elapsed.TotalSeconds -lt $TimeoutSegundos) {
    if ($hwnd -eq [IntPtr]::Zero) {
        $v = @(Get-VentanasDe -ProcId $proc.Id | Where-Object { $_.Clase -eq '#32770' -and $_.Visible })
        if ($v.Count) {
            $hwnd = $v[0].Handle
            $msVisible = [int]$sw.ElapsedMilliseconds
            Write-Host ('  Dialogo visible en      : ' + $msVisible + ' ms') -ForegroundColor Green
        }
    } else {
        if (Test-VentanaResponde -Handle $hwnd -Ms 1500) { $responde = $true; break }
    }
    Start-Sleep -Milliseconds 150
}
$msTotal = [int]$sw.ElapsedMilliseconds

Write-Host ''
if ($responde) {
    Write-Host ('  RESULTADO: el dialogo abrio y responde. Total ' + $msTotal + ' ms.') -ForegroundColor Green
    if ($msVisible -gt 3000) {
        Write-Host '  Aviso: mas de 3 s hasta aparecer ya es sintoma de enumeracion lenta.' -ForegroundColor Yellow
    }
} elseif ($hwnd -ne [IntPtr]::Zero) {
    Write-Host ('  RESULTADO: el dialogo aparecio a los ' + $msVisible + ' ms pero NO RESPONDE.') -ForegroundColor Red
    Write-Host '  Cuelgue durante la enumeracion de la carpeta o de un proveedor de espacio de nombres.' -ForegroundColor Red
} else {
    Write-Host ('  RESULTADO: el dialogo NO llego a aparecer en ' + $TimeoutSegundos + ' s. CUELGUE CONFIRMADO.') -ForegroundColor Red
}

# delta de modulos: esto es la prueba
$post  = Get-Modulos $proc
$nBase = @($base | ForEach-Object { $_.Nombre })
$delta = @($post | Where-Object { $nBase -notcontains $_.Nombre })
Write-Host ''
Write-Host ('  Modulos cargados por el picker (delta): ' + $delta.Count) -ForegroundColor Cyan
$tabla = foreach ($m in $delta) {
    $f = Get-FirmanteDll $m.Ruta
    [pscustomobject]@{
        Modulo      = $m.Nombre
        Firmante    = $f
        EsMicrosoft = (Test-EsMicrosoft $f $m.Ruta)
        Ruta        = $m.Ruta
    }
}
$tabla = @($tabla)
$csv = Join-Path $OutDir ('picker-delta-modulos-' + $stamp + '.csv')
if ($tabla.Count) { $tabla | Export-Csv $csv -NoTypeInformation -Encoding UTF8 }
$sospechosos = @($tabla | Where-Object { -not $_.EsMicrosoft })
if ($sospechosos.Count) {
    Write-Host ''
    Write-Host '  >> SOSPECHOSOS (cargados por el picker y NO de Microsoft):' -ForegroundColor Red
    $sospechosos | Select-Object Modulo, Firmante, Ruta | Format-Table -AutoSize | Out-String -Width 240 | Write-Host
} else {
    Write-Host '  Ningun modulo de terceros en el delta: el cuelgue no viene de una extension' -ForegroundColor Yellow
    Write-Host '  de shell de terceros. Mirar carpeta inicial (MRU), red y proveedores cloud.' -ForegroundColor Yellow
}
if ($tabla.Count) { Write-Host ('  CSV: ' + $csv) }

if ($Volcado -and -not $responde) {
    Invoke-Procdump -ProcId $proc.Id -Destino (Join-Path $OutDir ('picker-hang-' + $stamp + '.dmp'))
}

# limpieza: cerrar el dialogo por las buenas y luego matar el hijo
if ($hwnd -ne [IntPtr]::Zero) {
    [void][W11Picker.Win32]::PostMessage($hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)   # WM_CLOSE
    Start-Sleep -Milliseconds 500
}
if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '  Siguiente paso:' -ForegroundColor Cyan
Write-Host '   - Si cuelga sin carpeta forzada pero NO con -CarpetaInicial C:\  -> es el MRU:' -ForegroundColor Cyan
Write-Host '     03-reset-file-picker-mru.ps1 lo limpia (con copia de seguridad .reg).' -ForegroundColor Cyan
Write-Host '   - Si hay sospechosos de terceros -> 04-block-shell-extension.ps1 los desactiva' -ForegroundColor Cyan
Write-Host '     de forma reversible, sin desinstalar nada.' -ForegroundColor Cyan
Write-Host ''
