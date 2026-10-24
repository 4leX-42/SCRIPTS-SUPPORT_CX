# -*- mode: python ; coding: utf-8 -*-
"""
Empaquetado del Conversor LEDES 98BI en un ejecutable autonomo.

  python -m PyInstaller build.spec --noconfirm

Genera dist/Conversor LEDES 98BI.exe, que no necesita Python ni pip
instalados en el equipo de destino.
"""

block_cipher = None

a = Analysis(
    ["run.pyw"],
    pathex=["."],
    binaries=[],
    datas=[
        ("assets/andersen_logo.png", "assets"),
        ("assets/andersen.ico", "assets"),
        ("assets/LEDES98BI-V5-Sample-Reference.txt", "assets"),
        ("LEEME.md", "."),
    ],
    hiddenimports=["app", "ui", "pdf_extract", "ledes98bi", "utbms"],
    hookspath=[],
    runtime_hooks=[],
    # se excluyen paquetes grandes que pdfplumber no necesita para leer texto
    excludes=[
        "matplotlib", "numpy.random._examples", "scipy", "pandas", "pytest",
        "tkinter.test", "test", "unittest", "pydoc_data", "setuptools",
        "pip", "wheel", "PyInstaller",
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name="Conversor LEDES 98BI",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    runtime_tmpdir=None,
    console=False,              # sin ventana de consola
    disable_windowed_traceback=False,
    icon="assets/andersen.ico",
    version_file=None,
)
