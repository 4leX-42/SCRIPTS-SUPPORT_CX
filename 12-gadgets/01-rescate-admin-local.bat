@echo off
REM ==================================================================
REM .SYNOPSIS
REM   [ES] Equipo sin administrador: devuelve una cuenta local a Administradores desde la recuperacion (WinRE). No borra datos.
REM   [EN] PC with no administrator: restores a local account to Administrators from Windows Recovery (WinRE). No data loss.
REM .NOTES
REM   Contexto: admin
REM ==================================================================
REM  01-rescate-admin-local.bat  (Rescate_Admin)  -  v3
REM  Devuelve una cuenta local al grupo Administradores cuando el equipo
REM  se ha quedado SIN ningun administrador.
REM  NO borra datos ni reinstala Windows. Solo toca grupos locales.
REM
REM  Metodo: HKLM\SYSTEM\Setup  SetupType=2 + CmdLine  (modo auditoria de
REM  fabricante). Al arrancar, Windows ejecuta la fase 2 como SYSTEM, antes
REM  del login. No usa el truco de utilman (lo bloquea Defender / parches).
REM
REM  USO (desde el cmd de la recuperacion - WinRE):
REM    1) Login del equipo > con MAYUS pulsada, Encendido > Reiniciar.
REM    2) Solucionar problemas > Opciones avanzadas > Simbolo del sistema.
REM    3) Enchufa este USB.  Letra:   wmic logicaldisk get deviceid,volumename
REM    4) Ejecuta (con la letra del USB, p.ej. E:):   E:\01-rescate-admin-local.bat
REM    5) Cuando diga OK: cierra, arranca normal; el rescate se hace solo.
REM
REM  Cuentas a devolver a Administradores (separadas por espacio):
set "CUENTAS=Usuario User usuario"
REM ==================================================================
setlocal EnableExtensions
if /i "%~1"=="fase2" goto :FASE2

REM ---------------- FASE 1: en WinRE, desde el USB ----------------
set "USB=%~d0"
set "LOG=%~dp0Rescate_Admin.log"
echo ==================================================================> "%LOG%" 2>nul
echo %DATE% %TIME%  Rescate_Admin v3 - FASE 1   (USB=%USB%)>> "%LOG%" 2>nul

cls
echo ==================================================================
echo    RESCATE DE ADMINISTRADOR   (no borra nada)
echo ==================================================================
echo.
echo  [1/4] Buscando el Windows del equipo...
echo.

REM --- Deteccion: una subrutina por unidad (sin parentesis anidados ni
REM     expansion retardada, que fallaba en WinRE). Marca en WIN la primera
REM     unidad con Windows real que no sea el USB ni el X: de la recuperacion.
set "WIN="
for %%D in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do call :findwin %%D
if not defined WIN goto :no_windows

echo  [OK] Windows encontrado en: %WIN%
echo Windows del equipo: %WIN%>> "%LOG%"
echo.
echo  [2/4] Copiando el componente de rescate...
copy /y "%~f0" "%WIN%\Windows\Temp\Rescate_Admin.bat" >nul 2>&1
if not exist "%WIN%\Windows\Temp\Rescate_Admin.bat" goto :no_copy
echo  [OK] Copiado a %WIN%\Windows\Temp
echo Copiado el bat a %WIN%\Windows\Temp>> "%LOG%"
echo.

echo  [3/4] Marcando el arranque para el rescate automatico...
reg load "HKLM\RESCATE" "%WIN%\Windows\System32\config\SYSTEM" >> "%LOG%" 2>&1
if errorlevel 1 goto :no_reg
REM CmdLine como REG_EXPAND_SZ para que %SystemDrive% se expanda al arrancar.
reg add "HKLM\RESCATE\Setup" /v CmdLine /t REG_EXPAND_SZ /d "cmd.exe /c %%SystemDrive%%\Windows\Temp\Rescate_Admin.bat fase2" /f >> "%LOG%" 2>&1
reg add "HKLM\RESCATE\Setup" /v SetupType /t REG_DWORD /d 2 /f >> "%LOG%" 2>&1

REM Verificacion: releer SetupType antes de descargar el hive.
set "VER_TYPE="
for /f "tokens=3" %%A in ('reg query "HKLM\RESCATE\Setup" /v SetupType 2^>nul ^| find /i "SetupType"') do set "VER_TYPE=%%A"
reg unload "HKLM\RESCATE" >> "%LOG%" 2>&1
echo Verificacion: SetupType=%VER_TYPE%>> "%LOG%"
if /i not "%VER_TYPE%"=="0x2" goto :no_mark
echo  [OK] Marca puesta y verificada (SetupType=%VER_TYPE%).
echo.

echo  [4/4] LISTO.
echo ==================================================================
echo.
echo   AHORA:
echo     1) Escribe:   exit
echo     2) Pulsa:     Continuar  (o apaga y enciende).
echo     3) Al arrancar veras una ventana negra 1-2 s (el rescate).
echo        Luego llega al inicio de sesion.
echo     4) Entra con tu cuenta: ya sera administrador.
echo.
echo   Log:  %LOG%
echo ==================================================================
echo.
echo FASE 1 OK. Esperando reinicio manual.>> "%LOG%"
echo Pulsa una tecla para cerrar (NO reinicia solo).
pause >nul
endlocal
exit /b 0

:findwin
REM %1 = letra de unidad. Marca WIN si es un Windows real y no es USB/X:.
if defined WIN goto :eof
if /i "%~1:"=="%USB%" goto :eof
if /i "%~1:"=="X:" goto :eof
if not exist "%~1:\Windows\System32\ntoskrnl.exe" goto :eof
if not exist "%~1:\Windows\explorer.exe" goto :eof
if not exist "%~1:\Windows\System32\config\SYSTEM" goto :eof
set "WIN=%~1:"
echo   candidato Windows: %~1:>> "%LOG%"
goto :eof

:no_windows
echo No se encontro Windows.>> "%LOG%"
echo  [ERROR] No encuentro Windows en ningun disco.
echo.
echo    - Si el disco tiene BitLocker:  manage-bde -unlock C: -RecoveryPassword ^<clave^>
echo    - O la letra es otra:           wmic logicaldisk get deviceid,volumename
wmic logicaldisk get DeviceID,VolumeName,Description >> "%LOG%" 2>nul
goto :fin_error

:no_copy
echo No se pudo copiar a Temp.>> "%LOG%"
echo  [ERROR] No pude escribir en %WIN%\Windows\Temp (solo lectura o cifrado).
goto :fin_error

:no_reg
echo reg load fallo.>> "%LOG%"
echo  [ERROR] No pude abrir el registro de %WIN%.
goto :fin_error

:no_mark
echo SetupType no quedo en 0x2 (leido: %VER_TYPE%).>> "%LOG%"
echo  [ERROR] No se pudo dejar la marca. Nada cambiado.
goto :fin_error

:fin_error
echo.
echo   No se ha cambiado nada. Log:  %LOG%
echo.
echo Pulsa una tecla para cerrar.
pause >nul
endlocal
exit /b 1

REM ---------------- FASE 2: Windows la lanza al arrancar, como SYSTEM ----------------
:FASE2
set "LOG=%SystemDrive%\Windows\Temp\Rescate_Admin.log"
echo %DATE% %TIME%  Rescate_Admin v3 - FASE 2 (SYSTEM)> "%LOG%"
for %%U in (%CUENTAS%) do call :addadmin "%%U"
echo --- Miembros de Administradores: >> "%LOG%"
net localgroup Administradores >> "%LOG%" 2>&1
reg add "HKLM\SYSTEM\Setup" /v SetupType /t REG_DWORD /d 0 /f >> "%LOG%" 2>&1
reg add "HKLM\SYSTEM\Setup" /v CmdLine /t REG_SZ /d "" /f >> "%LOG%" 2>&1
echo %DATE% %TIME%  FASE 2 completada. Reiniciando a login normal.>> "%LOG%"
del "%SystemDrive%\Windows\Temp\Rescate_Admin.bat" >nul 2>&1
shutdown /r /t 5 /c "Rescate completado. Reiniciando al inicio de sesion."
exit /b 0

:addadmin
net user %1 >nul 2>&1 || goto :eof
net user %1 /active:yes >> "%LOG%" 2>&1
powershell -NoProfile -Command "Add-LocalGroupMember -SID 'S-1-5-32-544' -Member %1 -ErrorAction SilentlyContinue" >> "%LOG%" 2>&1
net localgroup Administradores %1 /add >> "%LOG%" 2>&1
net localgroup Administrators %1 /add >> "%LOG%" 2>&1
echo %~1 -^> Administradores >> "%LOG%"
goto :eof
