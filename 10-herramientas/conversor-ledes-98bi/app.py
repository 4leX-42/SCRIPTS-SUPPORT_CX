"""
PDF -> LEDES 98BI
Una sola pantalla: sueltas los PDFs, revisas, exportas.
"""

from __future__ import annotations

import copy
import json
import os
import sys
import threading
import traceback
from datetime import datetime
from decimal import Decimal

import tkinter as tk
from tkinter import filedialog, messagebox, ttk

APP_DIR = os.path.dirname(os.path.abspath(__file__))
if APP_DIR not in sys.path:
    sys.path.insert(0, APP_DIR)

#: Empaquetado con PyInstaller, APP_DIR apunta al directorio temporal que
#: Windows borra al cerrar la aplicacion. Los ficheros generados tienen que ir
#: junto al ejecutable, no ahi dentro.
FROZEN = getattr(sys, "frozen", False)
BASE_DIR = os.path.dirname(sys.executable) if FROZEN else APP_DIR


def default_output_dir() -> str:
    """Directorio de salida por defecto, escribible en el equipo de destino."""
    candidate = os.path.join(BASE_DIR, "salida")
    try:
        os.makedirs(candidate, exist_ok=True)
        probe = os.path.join(candidate, ".escritura")
        with open(probe, "w") as fh:
            fh.write("")
        os.remove(probe)
        return candidate
    except OSError:
        # el ejecutable esta en una ruta sin permiso de escritura
        # (Program Files, unidad de red): se usa Documentos
        docs = os.path.join(os.path.expanduser("~"), "Documents", "LEDES 98BI")
        try:
            os.makedirs(docs, exist_ok=True)
        except OSError:
            return os.path.expanduser("~")
        return docs

import ledes98bi as L
import pdf_extract
import ui as U
import utbms

APP_NAME = "Conversor LEDES 98BI"
CONFIG_DIR = os.path.join(os.environ.get("APPDATA", APP_DIR), "Andersen-LEDES")
CONFIG_PATH = os.path.join(CONFIG_DIR, "config.json")
#: los recursos empaquetados se extraen en sys._MEIPASS
ASSET_DIR = os.path.join(getattr(sys, "_MEIPASS", APP_DIR), "assets")
LOGO_PATH = os.path.join(ASSET_DIR, "andersen_logo.png")
ICON_PATH = os.path.join(ASSET_DIR, "andersen.ico")

DEFAULT_CONFIG = {
    "law_firm_id": "",
    "law_firm_name": "",
    "currency": "EUR",
    "account_type": "O",
    "default_timekeeper_id": "",
    "default_timekeeper_last_name": "",
    "default_timekeeper_first_name": "",
    "default_timekeeper_classification": "ASSOC",
    "output_dir": "",           # se resuelve al arrancar: default_output_dir()
    "force_ascii": True,
}

TASK_VALUES = [f"{k} - {v}" for k, v in utbms.TASK_CODES.items()]
EXPENSE_VALUES = [f"{k} - {v}" for k, v in utbms.EXPENSE_CODES.items()]
ACTIVITY_VALUES = [f"{k} - {v}" for k, v in utbms.ACTIVITY_CODES.items()]
CLASS_VALUES = [f"{k} - {v}" for k, v in utbms.TIMEKEEPER_CLASSIFICATIONS.items()]
TYPE_VALUES = ["F - honorarios", "E - gasto", "IF - ajuste honorarios", "IE - ajuste gastos"]


def load_config() -> dict:
    cfg = dict(DEFAULT_CONFIG)
    try:
        with open(CONFIG_PATH, encoding="utf-8") as fh:
            cfg.update(json.load(fh))
    except Exception:
        pass
    if not str(cfg.get("output_dir") or "").strip():
        cfg["output_dir"] = default_output_dir()
    return cfg


def save_config(cfg: dict) -> None:
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(CONFIG_PATH, "w", encoding="utf-8") as fh:
        json.dump(cfg, fh, indent=2, ensure_ascii=False)


def code_of(value: str) -> str:
    return (value or "").split(" - ")[0].strip()


#: campos de cabecera que son fechas: se muestran en formato español y se
#: guardan en el modelo como YYYYMMDD, que es lo que exige el estándar
DATE_FIELDS = ("invoice_date", "billing_start_date", "billing_end_date")


def date_to_display(value: str) -> str:
    v = str(value or "")
    return f"{v[6:8]}/{v[4:6]}/{v[0:4]}" if len(v) == 8 and v.isdigit() else v


def date_from_display(value: str) -> str:
    return L.fmt_date(pdf_extract.parse_date(value) or value)


# ---------------------------------------------------------------------------
class Settings(tk.Frame):
    """Panel de ajustes: solo lo que LEDES 98BI exige y el PDF no trae."""

    def __init__(self, master, app):
        super().__init__(master, bg=U.BG)
        self.app = app
        self.vars: dict[str, tk.StringVar] = {}

        head = tk.Frame(self, bg=U.BG)
        head.pack(fill="x", padx=34, pady=(26, 18))
        tk.Label(head, text="Configuración", bg=U.BG, fg=U.TEXT,
                 font=U.fs(17, "bold")).pack(side="left")
        U.Button(head, "Cerrar", app.show_list, kind="quiet").pack(side="right")

        wrap = tk.Frame(self, bg=U.BG)
        wrap.pack(fill="both", expand=True, padx=34)

        card = U.Card(wrap)
        card.pack(fill="x")
        body = tk.Frame(card.inner, bg=U.SURFACE, padx=24, pady=22)
        body.pack(fill="x")

        self._section(body, "Despacho emisor",
                      "Datos invariables, comunes a toda la facturación")
        row = tk.Frame(body, bg=U.SURFACE)
        row.pack(fill="x", pady=(0, 22))
        self._field(row, "law_firm_id", "CIF / NIF del despacho", 24,
                    "Obligatorio  ·  campo LAW_FIRM_ID")
        self._field(row, "law_firm_name", "Nombre del despacho", 32, "Opcional")
        self._field(row, "currency", "Moneda", 8, "ISO 3", values=["EUR", "GBP", "USD", "CHF"])
        self._field(row, "account_type", "Cuenta", 8, "O: cuenta propia  ·  T: terceros",
                    values=["O", "T"])

        self._section(body, "Profesional por defecto",
                      "Se imputa a las partidas de honorarios cuyo profesional no conste en el documento")
        row2 = tk.Frame(body, bg=U.SURFACE)
        row2.pack(fill="x", pady=(0, 22))
        self._field(row2, "default_timekeeper_id", "ID", 14, "TIMEKEEPER_ID")
        self._field(row2, "default_timekeeper_last_name", "Apellidos", 20)
        self._field(row2, "default_timekeeper_first_name", "Nombre", 16)
        self._field(row2, "default_timekeeper_classification", "Categoría", 22,
                    values=list(utbms.TIMEKEEPER_CLASSIFICATIONS))

        self._section(body, "Fichero de salida", "Destino de los ficheros generados")
        row3 = tk.Frame(body, bg=U.SURFACE)
        row3.pack(fill="x")
        self._field(row3, "output_dir", "Directorio de destino", 52)
        U.Button(row3, "Examinar", self._pick_dir, kind="ghost", height=32).pack(
            side="left", anchor="s", padx=(10, 0), pady=(0, 1))

        self.var_ascii = tk.BooleanVar(value=bool(app.cfg.get("force_ascii", True)))
        opt = tk.Frame(body, bg=U.SURFACE)
        opt.pack(fill="x", pady=(18, 0))
        U.Check(opt, "Transliterar a ASCII. El estándar define el formato como ASCII; "
                     "diversas plataformas rechazan el fichero si contiene "
                     "acentos o el símbolo de euro.",
                self.var_ascii, bg=U.SURFACE).pack(anchor="w")

        foot = tk.Frame(wrap, bg=U.BG)
        foot.pack(fill="x", pady=20)
        U.Button(foot, "Guardar configuración", self._save, kind="primary").pack(side="left")
        self.lbl_saved = tk.Label(foot, text="", bg=U.BG, fg=U.GREEN, font=U.f(9))
        self.lbl_saved.pack(side="left", padx=14)

        for key in DEFAULT_CONFIG:
            if key in self.vars:
                self.vars[key].set(str(app.cfg.get(key, "") or ""))

    def _section(self, parent, title, hint):
        box = tk.Frame(parent, bg=U.SURFACE)
        box.pack(fill="x", pady=(0, 10))
        tk.Label(box, text=title, bg=U.SURFACE, fg=U.TEXT,
                 font=U.f(10, "bold")).pack(side="left")
        if hint:
            tk.Label(box, text="   " + hint, bg=U.SURFACE, fg=U.TEXT_FAINT,
                     font=U.f(8)).pack(side="left")

    def _field(self, parent, key, label, width, hint="", values=None):
        var = tk.StringVar()
        self.vars[key] = var
        U.Field(parent, label, var, width=width, hint=hint,
                values=values).pack(side="left", padx=(0, 16), anchor="n")

    def _pick_dir(self):
        d = filedialog.askdirectory(title="Seleccione el directorio de destino")
        if d:
            self.vars["output_dir"].set(d)

    def _save(self):
        for key, var in self.vars.items():
            self.app.cfg[key] = var.get().strip()
        self.app.cfg["force_ascii"] = bool(self.var_ascii.get())
        try:
            save_config(self.app.cfg)
        except Exception as exc:
            messagebox.showerror(APP_NAME, f"No se pudo guardar:\n{exc}")
            return
        self.app.reapply_defaults()
        self.lbl_saved.configure(text="Configuración guardada")
        self.after(1800, lambda: self.lbl_saved.configure(text=""))


# ---------------------------------------------------------------------------
class DropZone(tk.Canvas):
    """Area punteada para soltar o elegir los PDFs."""

    TALL, SHORT = 164, 62

    def __init__(self, master, on_click):
        super().__init__(master, bg=U.BG, height=self.TALL,
                         highlightthickness=0, bd=0)
        self.on_click = on_click
        self._hover = False
        self._compact = False
        self.bind("<Configure>", lambda _e: self._draw())
        self.bind("<Enter>", lambda _e: self._set_hover(True))
        self.bind("<Leave>", lambda _e: self._set_hover(False))
        self.bind("<Button-1>", lambda _e: self.on_click())
        self.configure(cursor="hand2")

    def set_compact(self, value: bool):
        """Una vez hay facturas la zona se reduce a una franja."""
        if value == self._compact:
            return
        self._compact = value
        self.configure(height=self.SHORT if value else self.TALL)
        self._draw()

    def _set_hover(self, value):
        self._hover = value
        self._draw()

    def _draw(self):
        self.delete("all")
        w, h = self.winfo_width(), self.winfo_height()
        if w < 10:
            return
        fill = U.ACCENT_SOFT if self._hover else U.SURFACE
        edge = U.ACCENT if self._hover else U.HAIRLINE_STRONG
        U.round_rect(self, 2, 2, w - 2, h - 2, 12, fill=fill, outline=edge,
                     width=1, dash=(5, 4))
        if self._compact:
            self.create_text(w / 2, h / 2, text="Añadir más documentos  ·  arrastrar o pulsar para examinar",
                             fill=U.TEXT_SOFT, font=U.f(10))
        else:
            self.create_text(w / 2, h / 2 - 13, text="Arrastre los documentos de facturación",
                             fill=U.TEXT, font=U.f(13, "bold"))
            self.create_text(w / 2, h / 2 + 13, text="o pulse para examinar el equipo  ·  formato PDF",
                             fill=U.TEXT_FAINT, font=U.f(9))


class InvoiceRow(tk.Frame):
    """Fila de la lista de facturas."""

    def __init__(self, master, result, index, on_open, on_remove):
        super().__init__(master, bg=U.SURFACE, cursor="hand2")
        self.on_open = on_open
        inv = result.invoice
        errs, warns = L.summarize(L.validate(inv))

        if index:
            tk.Frame(self, bg=U.HAIRLINE, height=1).pack(fill="x")

        if errs:
            color, state = U.BAD, f"{errs} incidencia{'s' if errs > 1 else ''}"
        elif warns:
            color, state = U.WARN, f"{warns} advertencia{'s' if warns > 1 else ''}"
        else:
            color, state = U.OK, "Conforme"

        body = tk.Frame(self, bg=U.SURFACE)
        body.pack(fill="x")
        # filete de estado a la izquierda: rojo si hay incidencias
        self._edge = tk.Frame(body, bg=color if errs or warns else U.SURFACE, width=3)
        self._edge.pack(side="left", fill="y")
        self._edge_color = color if errs or warns else U.SURFACE

        row = tk.Frame(body, bg=U.SURFACE, padx=20, pady=14)
        row.pack(side="left", fill="x", expand=True)

        txt = tk.Frame(row, bg=U.SURFACE)
        txt.pack(side="left", fill="x", expand=True)
        title = inv.invoice_number or os.path.basename(inv.source_pdf)
        head = tk.Frame(txt, bg=U.SURFACE)
        head.pack(anchor="w")
        tk.Label(head, text=title, bg=U.SURFACE, fg=U.TEXT,
                 font=U.f(11, "bold"), anchor="w").pack(side="left")
        tk.Label(head, text=state.upper(), bg=U.SURFACE, fg=color,
                 font=U.f(7, "bold")).pack(side="left", padx=(10, 0), pady=(2, 0))
        sub = f"{os.path.basename(inv.source_pdf)}   ·   {len(inv.lines)} partida" \
              f"{'s' if len(inv.lines) != 1 else ''}"
        if inv.matter_name:
            sub += f"   ·   {inv.matter_name[:52]}"
        tk.Label(txt, text=sub, bg=U.SURFACE, fg=U.TEXT_FAINT,
                 font=U.f(8), anchor="w").pack(anchor="w", pady=(2, 0))

        amount = tk.Frame(row, bg=U.SURFACE)
        amount.pack(side="left", padx=(16, 14))
        tk.Label(amount, text=U.money(inv.invoice_total, inv.currency),
                 bg=U.SURFACE, fg=U.TEXT, font=U.f(12, "bold")).pack(anchor="e")
        tk.Label(amount, text=f"base {U.money(inv.invoice_net_total)}"
                             f"     IVA {U.money(inv.invoice_tax_total)}",
                 bg=U.SURFACE, fg=U.TEXT_FAINT, font=U.f(8)).pack(anchor="e")

        self._close = tk.Label(row, text="✕", bg=U.SURFACE, fg=U.TEXT_FAINT,
                               font=U.f(9), cursor="hand2")
        self._close.pack(side="left")
        self._close.bind("<Button-1>", lambda _e: on_remove(index))
        self._close.bind("<Enter>", lambda _e: self._close.configure(fg=U.ACCENT))
        self._close.bind("<Leave>", lambda _e: self._close.configure(fg=U.TEXT_FAINT))

        self._tinted = [body, row, txt, head, amount,
                        *txt.winfo_children(), *head.winfo_children(),
                        *amount.winfo_children()]
        for widget in (self, *self._tinted):
            if widget is self._close:
                continue
            widget.bind("<Button-1>", lambda _e, i=index: self.on_open(i))
            widget.bind("<Enter>", lambda _e: self._tint(True))
            widget.bind("<Leave>", lambda _e: self._tint(False))

    def _tint(self, hover: bool):
        bg = U.ACCENT_SOFT if hover else U.SURFACE
        for w in self._tinted:
            try:
                w.configure(bg=bg)
            except tk.TclError:
                pass
        try:
            self._close.configure(bg=bg)
            self._edge.configure(bg=U.ACCENT if hover else self._edge_color)
        except tk.TclError:
            pass


# ---------------------------------------------------------------------------
COLUMNS = [
    ("dot", "", 26, "center", False),
    ("type", "TIPO", 46, "center", True),
    ("date", "FECHA", 78, "center", True),
    ("desc", "DESCRIPCIÓN", 300, "w", True),
    ("code", "CÓDIGO", 62, "center", True),
    ("act", "ACT", 52, "center", True),
    ("tkid", "ID PROF.", 92, "w", True),
    ("who", "PROFESIONAL", 140, "w", True),
    ("cls", "CATEG.", 70, "center", True),
    ("units", "UDS", 52, "e", True),
    ("cost", "COSTE", 74, "e", True),
    ("rate", "IVA %", 52, "e", True),
    ("total", "TOTAL", 84, "e", False),
]


class Detail(tk.Frame):
    """Cabecera editable + tabla de lineas con edicion en la propia celda."""

    def __init__(self, master, app):
        super().__init__(master, bg=U.BG)
        self.app = app
        self.result = None
        self.hdr_vars: dict[str, tk.StringVar] = {}
        self._loading = False
        self._editor = None

        top = tk.Frame(self, bg=U.BG)
        top.pack(fill="x", padx=34, pady=(22, 14))
        U.Button(top, "←  Documentos", app.show_list, kind="quiet").pack(side="left")
        self.lbl_title = tk.Label(top, text="", bg=U.BG, fg=U.TEXT, font=U.fs(14, "bold"))
        self.lbl_title.pack(side="left", padx=(16, 0))
        self.lbl_totals = tk.Label(top, text="", bg=U.BG, fg=U.TEXT_SOFT, font=U.f(10))
        self.lbl_totals.pack(side="right")

        # --- cabecera ---
        hcard = U.Card(self)
        hcard.pack(fill="x", padx=34)
        hbody = tk.Frame(hcard.inner, bg=U.SURFACE, padx=20, pady=16)
        hbody.pack(fill="x")
        fields = [
            ("invoice_number", "Nº factura", 16), ("invoice_date", "Fecha", 11),
            ("billing_start_date", "Periodo desde", 11),
            ("billing_end_date", "Periodo hasta", 11),
            ("client_id", "Cód. cliente", 13), ("client_tax_id", "CIF cliente", 13),
            ("law_firm_matter_id", "Cód. asunto", 13), ("matter_name", "Asunto", 30),
        ]
        for key, label, width in fields:
            var = tk.StringVar()
            self.hdr_vars[key] = var
            U.Field(hbody, label, var, width=width,
                    on_change=lambda k=key: self._on_header(k)).pack(
                side="left", padx=(0, 14), anchor="n")

        # --- lineas ---
        bar = tk.Frame(self, bg=U.BG)
        bar.pack(fill="x", padx=34, pady=(18, 8))
        tk.Label(bar, text="PARTIDAS", bg=U.BG, fg=U.TEXT,
                 font=U.f(7, "bold")).pack(side="left")
        tk.Label(bar, text="   doble clic sobre una celda para rectificarla",
                 bg=U.BG, fg=U.TEXT_FAINT, font=U.f(8)).pack(side="left")
        U.Button(bar, "Eliminar", self.delete_line, kind="danger", height=30).pack(side="right")
        U.Button(bar, "Duplicar", self.duplicate_line, kind="ghost", height=30).pack(
            side="right", padx=(0, 8))
        U.Button(bar, "Añadir partida", self.add_line, kind="ghost", height=30).pack(
            side="right", padx=(0, 8))

        lcard = U.Card(self)
        lcard.pack(fill="both", expand=True, padx=34)
        holder = tk.Frame(lcard.inner, bg=U.SURFACE)
        holder.pack(fill="both", expand=True)

        self.tree = ttk.Treeview(holder, columns=[c[0] for c in COLUMNS],
                                 show="headings", style="Flat.Treeview",
                                 selectmode="browse")
        for key, title, width, anchor, _edit in COLUMNS:
            self.tree.heading(key, text=title)
            self.tree.column(key, width=width, anchor=anchor, stretch=(key == "desc"),
                             minwidth=26)
        self.tree.tag_configure("low", background=U.RED_SOFT)
        self.tree.tag_configure("mid", background=U.WARN_SOFT)
        vsb = ttk.Scrollbar(holder, orient="vertical", command=self.tree.yview,
                            style="Flat.Vertical.TScrollbar")
        self.tree.configure(yscrollcommand=vsb.set)
        self.tree.pack(side="left", fill="both", expand=True)
        vsb.pack(side="left", fill="y")
        self.tree.bind("<Double-1>", self._begin_edit)
        self.tree.bind("<Delete>", lambda _e: self.delete_line())
        self.tree.bind("<MouseWheel>", lambda _e: self._close_editor())

        # --- validacion ---
        self.problems = tk.Text(self, height=5, bg=U.BG, fg=U.TEXT_SOFT, relief="flat",
                                bd=0, font=U.f(9), wrap="word", highlightthickness=0)
        self.problems.tag_configure("ERROR", foreground=U.ACCENT)
        self.problems.tag_configure("AVISO", foreground=U.WARN)
        self.problems.tag_configure("OK", foreground=U.GREEN)
        self.problems.tag_configure("NOTA", foreground=U.TEXT_FAINT)
        self.problems.pack(fill="x", padx=34, pady=(14, 18))

    # -- carga --------------------------------------------------------------
    def load(self, result):
        self.result = result
        inv = result.invoice
        self.lbl_title.configure(text=inv.invoice_number or
                                 os.path.basename(inv.source_pdf))
        self._loading = True
        for key, var in self.hdr_vars.items():
            raw = str(getattr(inv, key, "") or "")
            var.set(date_to_display(raw) if key in DATE_FIELDS else raw)
        self._loading = False
        self.refresh()

    def refresh(self):
        self._close_editor()
        self.tree.delete(*self.tree.get_children())
        if not self.result:
            return
        inv = self.result.invoice
        for i, ln in enumerate(inv.lines):
            tag = "low" if ln.confidence < 0.45 else ("mid" if ln.confidence < 0.7 else "")
            self.tree.insert("", "end", iid=str(i), values=self._row_values(ln),
                             tags=(tag,) if tag else ())
        self.lbl_totals.configure(
            text=f"base  {U.money(inv.invoice_net_total)}        "
                 f"IVA  {U.money(inv.invoice_tax_total)}        "
                 f"total  {U.money(inv.invoice_total, inv.currency)}")
        self._show_problems()
        self.app.refresh_footer()

    @staticmethod
    def _row_values(ln: L.LineItem):
        dot = "●" if ln.confidence < 0.7 else ""
        code = ln.expense_code if ln.line_type in ("E", "IE") else ln.task_code
        act = "" if ln.line_type in ("E", "IE") else ln.activity_code
        pct = U.number(L.dec(ln.tax_rate) * 100)
        date = ln.line_date
        if len(date) == 8:
            date = f"{date[6:8]}/{date[4:6]}/{date[0:4]}"
        return (dot, ln.line_type, date, ln.description or "", code, act,
                ln.timekeeper_id, ln.timekeeper_name, ln.timekeeper_classification,
                U.number(ln.units), U.money(ln.unit_cost), pct,
                U.money(ln.total))

    def _show_problems(self):
        inv = self.result.invoice
        problems = L.validate(inv)
        self.problems.configure(state="normal")
        self.problems.delete("1.0", "end")
        if not problems:
            self.problems.insert(
                "end", "Conforme al estándar LEDES 98BI. Sin incidencias.\n", "OK")
        for sev, msg in problems:
            self.problems.insert("end", f"{sev}  {msg}\n", sev)
        for note in inv.extraction_notes:
            self.problems.insert("end", f"NOTA  {note}\n", "NOTA")
        self.problems.configure(state="disabled")

    def _on_header(self, key):
        if self._loading or not self.result:
            return
        value = self.hdr_vars[key].get()
        if key in DATE_FIELDS:
            value = date_from_display(value)
        setattr(self.result.invoice, key, value)
        self.app.remember(key, value)
        self._show_problems()
        self.app.refresh_footer()

    # -- edicion en celda ---------------------------------------------------
    def _close_editor(self):
        if self._editor is not None:
            try:
                self._editor.destroy()
            except tk.TclError:
                pass
            self._editor = None

    def _begin_edit(self, event):
        self._close_editor()
        row_id = self.tree.identify_row(event.y)
        col_id = self.tree.identify_column(event.x)
        if not row_id or not col_id:
            return
        col_index = int(col_id[1:]) - 1
        if not (0 <= col_index < len(COLUMNS)):
            return
        key, _title, _w, _anchor, editable = COLUMNS[col_index]
        if not editable:
            return
        bbox = self.tree.bbox(row_id, col_id)
        if not bbox:
            return
        x, y, w, h = bbox
        line = self.result.invoice.lines[int(row_id)]

        values = None
        current = self.tree.set(row_id, key)
        if key == "type":
            values = TYPE_VALUES
            current = next((v for v in TYPE_VALUES if v.startswith(line.line_type)), current)
        elif key == "code":
            values = EXPENSE_VALUES if line.line_type in ("E", "IE") else TASK_VALUES
            current = next((v for v in values if v.startswith(current + " ")), current)
        elif key == "act":
            values = ACTIVITY_VALUES
            current = next((v for v in values if v.startswith(current + " ")), current)
        elif key == "cls":
            values = CLASS_VALUES
            current = next((v for v in values if v.startswith(current + " ")), current)

        var = tk.StringVar(value=current)
        if values:
            widget = ttk.Combobox(self.tree, textvariable=var, values=values,
                                  font=U.f(9), style="Flat.TCombobox")
            widget.bind("<<ComboboxSelected>>", lambda _e: commit())
        else:
            widget = tk.Entry(self.tree, textvariable=var, font=U.f(9), bg=U.SURFACE,
                              fg=U.TEXT, relief="solid", bd=1,
                              insertbackground=U.ACCENT, highlightthickness=0)
        widget.place(x=x, y=y, width=max(w, 150 if values else w), height=h)
        widget.focus_set()
        if not values:
            widget.select_range(0, "end")
        self._editor = widget

        def commit(_e=None):
            self._apply_cell(int(row_id), key, var.get())
            self._close_editor()
            self.refresh()
            self.tree.selection_set(row_id)

        widget.bind("<Return>", commit)
        widget.bind("<FocusOut>", commit)
        widget.bind("<Escape>", lambda _e: self._close_editor())

    def _apply_cell(self, index: int, key: str, raw: str):
        ln = self.result.invoice.lines[index]
        raw = (raw or "").strip()
        if key == "type":
            ln.line_type = code_of(raw).upper() or "F"
            if ln.line_type in ("E", "IE"):
                if not ln.expense_code:
                    ln.expense_code = utbms.classify_expense(ln.description)[0]
                ln.task_code = ln.activity_code = ""
            else:
                if not ln.task_code:
                    ln.task_code, ln.activity_code, _ = utbms.classify_fee(ln.description)
                ln.expense_code = ""
        elif key == "date":
            ln.line_date = L.fmt_date(pdf_extract.parse_date(raw) or raw)
        elif key == "desc":
            ln.description = raw
        elif key == "code":
            code = code_of(raw).upper()
            if ln.line_type in ("E", "IE"):
                ln.expense_code = code
            else:
                ln.task_code = code
        elif key == "act":
            ln.activity_code = code_of(raw).upper()
        elif key == "tkid":
            ln.timekeeper_id = raw[:20]
        elif key == "who":
            if "," in raw:
                last, _, first = raw.partition(",")
                ln.timekeeper_last_name, ln.timekeeper_first_name = last.strip(), first.strip()
            else:
                parts = raw.split()
                ln.timekeeper_last_name = " ".join(parts[:-1]) if len(parts) > 1 else raw
                ln.timekeeper_first_name = parts[-1] if len(parts) > 1 else ""
            if not ln.timekeeper_id and raw:
                ln.timekeeper_id = pdf_extract._slug_id(raw)
        elif key == "cls":
            ln.timekeeper_classification = code_of(raw).upper()
        elif key == "units":
            ln.units = L.dec(pdf_extract.parse_number(raw) or 0)
        elif key == "cost":
            ln.unit_cost = L.dec(pdf_extract.parse_number(raw) or 0)
        elif key == "rate":
            pct = pdf_extract.parse_number(raw)
            ln.tax_rate = (L.dec(pct) / 100) if pct is not None else Decimal("0")
        ln.confidence = 1.0
        ln.notes = ""

    # -- lineas -------------------------------------------------------------
    def add_line(self):
        if not self.result:
            return
        inv = self.result.invoice
        cfg = self.app.cfg
        rate = inv.lines[0].tax_rate if inv.lines else Decimal("0.21")
        inv.lines.append(L.LineItem(
            line_type="F", line_date=inv.invoice_date, tax_rate=rate,
            units=Decimal("1"), unit_cost=Decimal("0"), confidence=1.0,
            task_code="L120", activity_code="A111",
            timekeeper_id=str(cfg.get("default_timekeeper_id", "") or ""),
            timekeeper_last_name=str(cfg.get("default_timekeeper_last_name", "") or ""),
            timekeeper_first_name=str(cfg.get("default_timekeeper_first_name", "") or ""),
            timekeeper_classification=str(cfg.get("default_timekeeper_classification", "") or ""),
        ))
        self.refresh()
        self.tree.selection_set(str(len(inv.lines) - 1))
        self.tree.see(str(len(inv.lines) - 1))

    def duplicate_line(self):
        sel = self.tree.selection()
        if not sel or not self.result:
            return
        i = int(sel[0])
        self.result.invoice.lines.insert(i + 1, copy.deepcopy(self.result.invoice.lines[i]))
        self.refresh()

    def delete_line(self):
        sel = self.tree.selection()
        if not sel or not self.result:
            return
        del self.result.invoice.lines[int(sel[0])]
        self.refresh()


# ---------------------------------------------------------------------------
class App(tk.Tk):
    def __init__(self):
        super().__init__()
        U.init_fonts()
        self.title(APP_NAME)
        self.geometry("1280x800")
        self.minsize(1120, 680)
        self.configure(bg=U.BG)
        try:
            if os.path.isfile(ICON_PATH):
                self.iconbitmap(ICON_PATH)
        except Exception:
            pass
        U.apply_ttk_theme(self)

        self.cfg = load_config()
        self.paths: list[str] = []
        self.results: list[pdf_extract.ExtractionResult] = []
        self._busy = False
        self._logo = None

        self._build_topbar()
        self.body = tk.Frame(self, bg=U.BG)
        self.body.pack(fill="both", expand=True)
        self._build_footer()

        self.view_list = tk.Frame(self.body, bg=U.BG)
        self.view_detail = Detail(self.body, self)
        self.view_settings = Settings(self.body, self)
        self._build_list()
        self.show_list()
        self._enable_dnd()

    # -- estructura ---------------------------------------------------------
    def _build_topbar(self):
        bar = tk.Frame(self, bg=U.SURFACE, height=62)
        bar.pack(fill="x")
        bar.pack_propagate(False)
        try:
            img = tk.PhotoImage(file=LOGO_PATH).subsample(2, 2)
            self._logo = img
            tk.Label(bar, image=img, bg=U.SURFACE).pack(side="left", padx=(28, 0))
        except Exception:
            tk.Label(bar, text="ANDERSEN", bg=U.SURFACE, fg=U.TEXT,
                     font=("Georgia", 15, "bold")).pack(side="left", padx=(28, 0))
        tk.Frame(bar, bg=U.HAIRLINE_STRONG, width=1).pack(side="left", fill="y",
                                                          pady=19, padx=20)
        tk.Label(bar, text="Conversión de facturación al estándar LEDES 98BI",
                 bg=U.SURFACE, fg=U.TEXT_SOFT, font=U.f(10)).pack(side="left")
        U.Button(bar, "Configuración", self.show_settings,
                 kind="quiet").pack(side="right", padx=(0, 24))
        # filete rojo corporativo bajo la cabecera
        tk.Frame(self, bg=U.ACCENT, height=2).pack(fill="x")

    def _build_footer(self):
        """Barra de acción en negro corporativo, con el botón primario en rojo."""
        bar = tk.Frame(self, bg=U.INK_BAR, height=66)
        bar.pack(fill="x", side="bottom")
        bar.pack_propagate(False)

        left = tk.Frame(bar, bg=U.INK_BAR)
        left.pack(side="left", padx=28)
        self.lbl_summary = tk.Label(left, text="", bg=U.INK_BAR, fg=U.TEXT_ON_INK,
                                    font=U.f(9), anchor="w", justify="left")
        self.lbl_summary.pack(anchor="w")
        self.lbl_summary_sub = tk.Label(left, text="", bg=U.INK_BAR,
                                        fg=U.TEXT_ON_INK_SOFT, font=U.f(8),
                                        anchor="w", justify="left")
        self.lbl_summary_sub.pack(anchor="w")

        self.btn_export = U.Button(bar, "Generar fichero LEDES 98BI", self.export,
                                   kind="primary", height=40, pad=22)
        self.btn_export.pack(side="right", padx=28)
        self.progress = ttk.Progressbar(bar, mode="determinate", length=170,
                                        style="Flat.Horizontal.TProgressbar")

    def _build_list(self):
        wrap = tk.Frame(self.view_list, bg=U.BG)
        wrap.pack(fill="both", expand=True, padx=34, pady=26)

        self.drop = DropZone(wrap, self.pick_files)
        self.drop.pack(fill="x")

        bar = tk.Frame(wrap, bg=U.BG)
        bar.pack(fill="x", pady=(20, 10))
        tk.Label(bar, text="DOCUMENTOS", bg=U.BG, fg=U.TEXT,
                 font=U.f(7, "bold")).pack(side="left")
        U.Button(bar, "Descartar todo", self.clear_all, kind="quiet", height=30).pack(side="right")
        U.Button(bar, "Examinar carpeta", self.pick_folder, kind="ghost",
                 height=30).pack(side="right", padx=(0, 8))

        self.list_card = U.Card(wrap)
        self.list_card.pack(fill="both", expand=True)
        self.list_holder = tk.Frame(self.list_card.inner, bg=U.SURFACE)
        self.list_holder.pack(fill="both", expand=True)
        self.empty = tk.Label(self.list_holder, bg=U.SURFACE, fg=U.TEXT_FAINT,
                              font=U.f(9),
                              text="Sin documentos cargados")
        self.empty.pack(expand=True)

    def _show(self, view):
        for v in (self.view_list, self.view_detail, self.view_settings):
            v.pack_forget()
        view.pack(fill="both", expand=True)

    def show_list(self):
        self._show(self.view_list)
        self.refresh_list()
        self.refresh_footer()

    def show_detail(self, index: int):
        if index >= len(self.results):
            return
        self.view_detail.load(self.results[index])
        self._show(self.view_detail)

    def show_settings(self):
        self._show(self.view_settings)

    # -- arrastrar y soltar -------------------------------------------------
    def _enable_dnd(self):
        try:
            self.tk.eval("package require tkdnd")
            self.tk.call("tkdnd::drop_target", "register", self._w, ("DND_Files",))
            self.bind("<<Drop>>", self._on_drop)
        except tk.TclError:
            pass

    def _on_drop(self, event):
        try:
            self.add_paths([p for p in self.tk.splitlist(event.data)
                            if p.lower().endswith(".pdf")])
        except Exception:
            pass

    # -- ficheros -----------------------------------------------------------
    def pick_files(self):
        paths = filedialog.askopenfilenames(title="Seleccione los documentos de facturación",
                                            filetypes=[("PDF", "*.pdf")])
        self.add_paths(list(paths))

    def pick_folder(self):
        folder = filedialog.askdirectory(title="Seleccione el directorio de documentos")
        if not folder:
            return
        self.add_paths([os.path.join(folder, f) for f in sorted(os.listdir(folder))
                        if f.lower().endswith(".pdf")])

    def add_paths(self, paths: list[str]):
        new = [os.path.abspath(p) for p in paths
               if p.lower().endswith(".pdf") and os.path.abspath(p) not in self.paths]
        if not new:
            return
        self.paths.extend(new)
        self.analyze()

    def clear_all(self):
        self.paths.clear()
        self.results.clear()
        self.show_list()

    def remove(self, index: int):
        if 0 <= index < len(self.paths):
            self.paths.pop(index)
            if index < len(self.results):
                self.results.pop(index)
            self.refresh_list()
            self.refresh_footer()

    # -- analisis -----------------------------------------------------------
    def analyze(self):
        if self._busy or not self.paths:
            return
        pending = self.paths[len(self.results):]
        if not pending:
            return
        self._busy = True
        self.btn_export.set_enabled(False)
        self.progress.pack(side="right", padx=(0, 16))
        self.progress.configure(maximum=len(pending), value=0)
        self.lbl_summary.configure(text="Procesando documentos...")
        threading.Thread(target=self._worker, args=(pending,), daemon=True).start()

    def _worker(self, pending):
        defaults = dict(self.cfg)
        out = []
        for i, path in enumerate(pending, 1):
            try:
                out.append(pdf_extract.extract(path, defaults))
            except Exception as exc:
                blank = L.Invoice(source_pdf=path)
                pdf_extract.apply_defaults(blank, defaults)
                blank.extraction_notes = [f"No se pudo leer el PDF: {exc}"]
                out.append(pdf_extract.ExtractionResult(blank, 0.0, blank.extraction_notes))
                self.after(0, lambda e=exc: print("extract:", e, file=sys.stderr))
            self.after(0, self.progress.configure, {"value": i})
        self.after(0, self._done, out)

    def _done(self, results):
        self.results.extend(results)
        self._busy = False
        self.progress.pack_forget()
        self.btn_export.set_enabled(True)
        self.show_list()

    # -- lista --------------------------------------------------------------
    def refresh_list(self):
        self.drop.set_compact(bool(self.results))
        for w in self.list_holder.winfo_children():
            w.destroy()
        if not self.results:
            tk.Label(self.list_holder, bg=U.SURFACE, fg=U.TEXT_FAINT, font=U.f(9),
                     text="Sin documentos cargados").pack(expand=True)
            return
        for i, res in enumerate(self.results):
            InvoiceRow(self.list_holder, res, i, self.show_detail,
                       self.remove).pack(fill="x")

    def refresh_footer(self):
        if not self.results:
            self.lbl_summary.configure(text="Sin documentos cargados")
            self.btn_export.set_enabled(False)
            return
        lines = sum(len(r.invoice.lines) for r in self.results)
        errs = warns = 0
        total = Decimal("0")
        for r in self.results:
            e, w = L.summarize(L.validate(r.invoice))
            errs += e
            warns += w
            total += r.invoice.invoice_total
        cur = self.results[0].invoice.currency
        self.lbl_summary.configure(
            text=f"{len(self.results)} documento{'s' if len(self.results) != 1 else ''}"
                 f"   ·   {lines} partida{'s' if lines != 1 else ''}"
                 f"   ·   {U.money(total, cur)}",
            fg=U.TEXT_ON_INK)
        if errs:
            estado = (f"{errs} incidencia{'s' if errs != 1 else ''} bloqueante"
                      f"{'s' if errs != 1 else ''}: la plataforma rechazaría el fichero")
            color = U.ACCENT_LINE
        elif warns:
            estado = (f"{warns} advertencia{'s' if warns != 1 else ''} "
                      f"pendiente{'s' if warns != 1 else ''} de revisión")
            color = U.TEXT_ON_INK_SOFT
        else:
            estado = "Conforme al estándar LEDES 98BI"
            color = U.TEXT_ON_INK_SOFT
        self.lbl_summary_sub.configure(text=estado, fg=color)
        self.btn_export.set_enabled(True)

    #: codigos internos del despacho: no vienen en el PDF, pero se repiten
    #: entre facturas del mismo cliente, asi que se recuerda el ultimo valor
    REMEMBERED = ("client_id", "law_firm_matter_id", "client_matter_id")

    def remember(self, key: str, value: str):
        if key not in self.REMEMBERED:
            return
        value = (value or "").strip()
        if not value or self.cfg.get(key) == value:
            return
        self.cfg[key] = value
        try:
            save_config(self.cfg)
        except Exception:
            pass

    def reapply_defaults(self):
        for res in self.results:
            pdf_extract.apply_defaults(res.invoice, dict(self.cfg))
        if self.view_detail.result:
            self.view_detail.load(self.view_detail.result)
        self.refresh_footer()

    # -- exportar -----------------------------------------------------------
    def export(self):
        if not self.results:
            return
        bad = []
        for res in self.results:
            errs, _ = L.summarize(L.validate(res.invoice))
            if errs:
                bad.append(f"  {os.path.basename(res.invoice.source_pdf)} — "
                           f"{errs} incidencia{'s' if errs > 1 else ''}")
        if bad:
            if not messagebox.askyesno(
                    APP_NAME,
                    "Los siguientes documentos presentan incidencias y serán "
                    "rechazados por la plataforma de facturación:\n\n"
                    + "\n".join(bad[:10])
                    + "\n\n¿Desea generar el fichero de todos modos?"):
                return

        outdir = str(self.cfg.get("output_dir") or "").strip() or default_output_dir()
        ascii_mode = bool(self.cfg.get("force_ascii", True))
        try:
            os.makedirs(outdir, exist_ok=True)
            written = []
            for res in self.results:
                inv = res.invoice
                base = self._safe(inv.invoice_number) or \
                    self._safe(os.path.splitext(os.path.basename(inv.source_pdf))[0])
                path = os.path.join(outdir, f"{base}.txt")
                n = 2
                while os.path.exists(path):
                    path = os.path.join(outdir, f"{base}_{n}.txt")
                    n += 1
                L.write_file(path, [inv], force_ascii=ascii_mode)
                written.append(path)
        except Exception as exc:
            messagebox.showerror(APP_NAME, f"Falló la exportación:\n{exc}\n\n"
                                           f"{traceback.format_exc()}")
            return

        self.lbl_summary.configure(
            text=f"{len(written)} fichero{'s' if len(written) != 1 else ''} "
                 f"en {outdir}", fg=U.GREEN)
        plural = "s" if len(written) != 1 else ""
        if messagebox.askyesno(
                APP_NAME,
                f"Se {'han' if len(written) != 1 else 'ha'} generado {len(written)} "
                f"fichero{plural} LEDES 98BI.\n\n"
                f"¿Desea abrir el directorio de destino?"):
            try:
                os.startfile(outdir)
            except Exception:
                pass

    @staticmethod
    def _safe(text: str) -> str:
        import re
        return re.sub(r"[^A-Za-z0-9._\-]+", "_", L.to_ascii(str(text or ""))).strip("._-")[:80]


def main():
    args = [a for a in sys.argv[1:] if a.lower().endswith(".pdf") and os.path.isfile(a)]
    app = App()
    if args:
        app.after(250, lambda: app.add_paths(args))
    app.mainloop()


if __name__ == "__main__":
    main()
