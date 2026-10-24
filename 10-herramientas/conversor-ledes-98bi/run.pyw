"""
Lanzador del Convertidor LEDES 98BI.

Se ejecuta con pythonw.exe para que no aparezca ventana de consola.
Comprueba las dependencias antes de arrancar y, si falta algo o la
aplicacion falla, lo muestra en una ventana en lugar de morir en silencio.
"""

import os
import sys
import traceback

APP_DIR = os.path.dirname(os.path.abspath(__file__))
if APP_DIR not in sys.path:
    sys.path.insert(0, APP_DIR)

REQUIRED = [("pdfplumber", "pdfplumber"), ("PIL", "pillow")]


def show_error(title: str, message: str) -> None:
    try:
        import tkinter as tk
        from tkinter import scrolledtext

        root = tk.Tk()
        root.title(title)
        root.geometry("820x440")
        tk.Label(root, text=title, font=("Segoe UI", 12, "bold"),
                 fg="#BF1429").pack(anchor="w", padx=16, pady=(14, 4))
        box = scrolledtext.ScrolledText(root, wrap="word", font=("Consolas", 9))
        box.pack(fill="both", expand=True, padx=16, pady=(0, 16))
        box.insert("1.0", message)
        root.mainloop()
    except Exception:
        # sin tkinter no hay forma grafica de avisar: al menos dejar rastro
        try:
            with open(os.path.join(APP_DIR, "error.log"), "a", encoding="utf-8") as fh:
                fh.write(f"{title}\n{message}\n{'-' * 60}\n")
        except Exception:
            pass


def main() -> None:
    missing = []
    for module, package in REQUIRED:
        try:
            __import__(module)
        except ImportError:
            missing.append(package)

    if missing:
        show_error(
            "Faltan dependencias",
            "El convertidor necesita estos paquetes de Python:\n\n"
            + "\n".join(f"  - {m}" for m in missing)
            + "\n\nInstalalos abriendo una ventana de comandos y ejecutando:\n\n"
            f'  "{sys.executable}" -m pip install ' + " ".join(missing)
            + "\n\nDespues vuelve a abrir el acceso directo.",
        )
        return

    try:
        import app

        app.main()
    except Exception:
        show_error(
            "Error al arrancar el convertidor",
            "Se ha producido un error inesperado. Copia este texto y pasalo a "
            "soporte:\n\n" + traceback.format_exc()
            + f"\n\nPython: {sys.version}\nRuta: {APP_DIR}",
        )


if __name__ == "__main__":
    main()
