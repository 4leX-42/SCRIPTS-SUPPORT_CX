@echo off
REM Arranca el convertidor con consola visible para ver los errores.
title Convertidor LEDES 98BI - diagnostico
cd /d "%~dp0"
echo === Comprobando Python ===
where python
python --version
echo.
echo === Comprobando dependencias ===
python -c "import pdfplumber, PIL; print('pdfplumber', pdfplumber.__version__); print('pillow OK')"
if errorlevel 1 (
  echo.
  echo Faltan dependencias. Instalalas con:
  echo     python -m pip install pdfplumber pillow
  echo.
  pause
  exit /b 1
)
echo.
echo === Arrancando aplicacion ===
python app.py
echo.
echo === La aplicacion se ha cerrado ===
pause
