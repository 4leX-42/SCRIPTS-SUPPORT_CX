"""
Tema y widgets base de la interfaz.

tkinter con aspecto plano y moderno: sin relieves 3D, sin bordes de sistema,
esquinas redondeadas dibujadas en canvas, un unico color de acento.
"""

from __future__ import annotations

import tkinter as tk
import tkinter.font as tkfont
from tkinter import ttk

# --- paleta corporativa: rojo del logotipo, negro y blanco -----------------
ACCENT = "#BF1429"          # rojo Andersen, muestreado del logotipo
ACCENT_HOVER = "#960E1E"
ACCENT_SOFT = "#FBEEF0"
ACCENT_LINE = "#E8A3AC"

INK = "#0B0C0E"             # negro corporativo
INK_BAR = "#141619"         # barras y cabeceras de tabla
INK_LINE = "#2A2D32"

BG = "#F4F4F5"
SURFACE = "#FFFFFF"
HAIRLINE = "#E4E5E7"
HAIRLINE_STRONG = "#C9CBCF"

TEXT = "#0B0C0E"
TEXT_SOFT = "#4A4E55"
TEXT_FAINT = "#8A8F97"
TEXT_ON_INK = "#F2F2F3"
TEXT_ON_INK_SOFT = "#9CA1A8"

#: estados. Se prescinde del verde: conforme se marca en negro corporativo.
OK = "#0B0C0E"
WARN = "#8A5A00"
WARN_SOFT = "#FDF6EA"
BAD = "#BF1429"
RED_SOFT = "#FBEEF0"
GREEN = OK                  # compatibilidad con llamadas existentes


def font_stack() -> tuple[str, str, str]:
    """(interfaz, monoespaciada, serif) disponibles en el sistema."""
    families = set(tkfont.families())
    ui = next((f for f in ("Segoe UI Variable Text", "Segoe UI", "Tahoma")
               if f in families), "TkDefaultFont")
    mono = next((f for f in ("Cascadia Mono", "Consolas", "Courier New")
                 if f in families), "TkFixedFont")
    # el logotipo es una serif: los titulos la recuperan
    serif = next((f for f in ("Georgia", "Times New Roman", "Cambria")
                  if f in families), ui)
    return ui, mono, serif


UI = "Segoe UI"
MONO = "Consolas"
SERIF = "Georgia"


def init_fonts() -> None:
    global UI, MONO, SERIF
    UI, MONO, SERIF = font_stack()


def f(size: int = 10, weight: str = "normal") -> tuple:
    return (UI, size, weight) if weight != "normal" else (UI, size)


def fs(size: int = 12, weight: str = "normal") -> tuple:
    """Fuente serif, para titulos."""
    return (SERIF, size, weight) if weight != "normal" else (SERIF, size)


def fm(size: int = 9) -> tuple:
    return (MONO, size)


# ---------------------------------------------------------------------------
def money(value, currency: str = "", *, decimals: int = 2) -> str:
    """Importe en formato español: 4.649,91 €.

    Solo para mostrar en pantalla. El fichero LEDES siempre lleva punto
    decimal y sin separador de millares (lo hace ledes98bi.fmt_decimal).
    """
    from decimal import Decimal, ROUND_HALF_UP

    if value is None or value == "":
        return ""
    d = value if isinstance(value, Decimal) else Decimal(str(value))
    d = d.quantize(Decimal(1).scaleb(-decimals), rounding=ROUND_HALF_UP)
    sign = "-" if d < 0 else ""
    whole, _, frac = f"{abs(d):.{decimals}f}".partition(".")
    groups = []
    while len(whole) > 3:
        groups.insert(0, whole[-3:])
        whole = whole[:-3]
    groups.insert(0, whole)
    out = sign + ".".join(groups) + ("," + frac if decimals else "")
    # solo el euro lleva simbolo; el resto, codigo ISO, que no admite confusion
    code = (currency or "").upper()
    if code == "EUR":
        return f"{out} €"
    return f"{out} {code}".strip()


def number(value, decimals: int = 2) -> str:
    """Cantidad en formato español, sin ceros decimales sobrantes: 1,5 / 4,25."""
    from decimal import Decimal

    if value is None or value == "":
        return ""
    text = money(value, decimals=decimals)
    if "," in text:
        text = text.rstrip("0").rstrip(",")
    return text or "0"


# ---------------------------------------------------------------------------
def round_rect(canvas: tk.Canvas, x1, y1, x2, y2, r, **kw):
    """Rectangulo de esquinas redondeadas como poligono suavizado."""
    r = min(r, abs(x2 - x1) / 2, abs(y2 - y1) / 2)
    points = [
        x1 + r, y1, x2 - r, y1, x2, y1, x2, y1 + r, x2, y2 - r, x2, y2,
        x2 - r, y2, x1 + r, y2, x1, y2, x1, y2 - r, x1, y1 + r, x1, y1,
    ]
    return canvas.create_polygon(points, smooth=True, splinesteps=24, **kw)


class Button(tk.Canvas):
    """Boton plano con esquinas redondeadas y estado hover."""

    def __init__(self, master, text, command=None, *, kind="ghost",
                 width=None, height=36, icon="", pad=18, **kw):
        self.kind = kind
        self.text = text
        self.icon = icon
        self.command = command
        self._enabled = True

        bg = master.cget("bg")
        font_ = f(10, "bold") if kind == "primary" else f(10)
        probe = tkfont.Font(font=font_)
        label = f"{icon}  {text}".strip() if icon else text
        w = width or probe.measure(label) + pad * 2

        super().__init__(master, width=w, height=height, bg=bg,
                         highlightthickness=0, bd=0, **kw)
        self._w_, self._h_ = w, height
        self._label = label
        self._font = font_
        self._draw(False)
        self.bind("<Enter>", self._on_enter)
        self.bind("<Leave>", self._on_leave)
        self.bind("<Button-1>", self._on_click)
        self.configure(cursor="hand2")

    def _colors(self, hover: bool):
        if not self._enabled:
            return SURFACE, HAIRLINE, TEXT_FAINT
        if self.kind == "primary":
            return (ACCENT_HOVER if hover else ACCENT), "", "#FFFFFF"
        if self.kind == "dark":
            return (ACCENT if hover else INK_BAR), "", "#FFFFFF"
        if self.kind == "quiet":
            return (BG if hover else SURFACE), "", (ACCENT if hover else TEXT_SOFT)
        if self.kind == "onink":
            return (INK_LINE if hover else INK_BAR), INK_LINE, \
                   ("#FFFFFF" if hover else TEXT_ON_INK_SOFT)
        if self.kind == "danger":
            return (RED_SOFT if hover else SURFACE), \
                   (ACCENT_LINE if hover else HAIRLINE), ACCENT
        return (SURFACE if hover else SURFACE), \
               (ACCENT if hover else HAIRLINE_STRONG), (ACCENT if hover else TEXT)

    def _draw(self, hover: bool):
        self.delete("all")
        fill, outline, fg = self._colors(hover)
        # radio pequeno: mas sobrio que una pastilla redondeada
        round_rect(self, 1, 1, self._w_ - 1, self._h_ - 1, 3,
                   fill=fill, outline=outline or fill, width=1)
        self.create_text(self._w_ / 2, self._h_ / 2 + 1, text=self._label,
                         fill=fg, font=self._font)

    def _on_enter(self, _e):
        if self._enabled:
            self._draw(True)

    def _on_leave(self, _e):
        self._draw(False)

    def _on_click(self, _e):
        if self._enabled and self.command:
            self.command()

    def set_enabled(self, value: bool):
        self._enabled = bool(value)
        self.configure(cursor="hand2" if value else "arrow")
        self._draw(False)

    def set_text(self, text: str):
        self.text = text
        self._label = f"{self.icon}  {text}".strip() if self.icon else text
        self._draw(False)


class Card(tk.Frame):
    """Superficie blanca con borde de 1 px."""

    def __init__(self, master, **kw):
        pad = kw.pop("pad", 0)
        super().__init__(master, bg=HAIRLINE, **kw)
        self.inner = tk.Frame(self, bg=SURFACE, padx=pad, pady=pad)
        self.inner.pack(fill="both", expand=True, padx=1, pady=1)


class Field(tk.Frame):
    """Etiqueta encima, entrada plana debajo."""

    def __init__(self, master, label, var, *, width=22, hint="", bg=SURFACE,
                 values=None, on_change=None):
        super().__init__(master, bg=bg)
        tk.Label(self, text=label.upper(), bg=bg, fg=TEXT_SOFT,
                 font=f(7, "bold")).pack(anchor="w")
        box = tk.Frame(self, bg=HAIRLINE_STRONG)
        box.pack(anchor="w", pady=(3, 0))
        if values:
            self.widget = ttk.Combobox(box, textvariable=var, width=width - 2,
                                       values=values, font=f(10), style="Flat.TCombobox")
        else:
            self.widget = tk.Entry(box, textvariable=var, width=width, font=f(10),
                                   bg=SURFACE, fg=TEXT, relief="flat", bd=0,
                                   insertbackground=ACCENT, highlightthickness=0)
        self.widget.pack(padx=1, pady=1, ipady=5, ipadx=6)
        if hint:
            tk.Label(self, text=hint, bg=bg, fg=TEXT_FAINT,
                     font=f(7)).pack(anchor="w", pady=(2, 0))
        if on_change:
            var.trace_add("write", lambda *_a: on_change())


class Check(tk.Frame):
    """Casilla plana dibujada a mano; la nativa de Windows rompe el estilo."""

    def __init__(self, master, text, variable: tk.BooleanVar, *, bg=SURFACE, wrap=0):
        super().__init__(master, bg=bg, cursor="hand2")
        self.var = variable
        self.box = tk.Canvas(self, width=17, height=17, bg=bg,
                             highlightthickness=0, bd=0)
        self.box.pack(side="left", pady=1)
        self.lbl = tk.Label(self, text=text, bg=bg, fg=TEXT_SOFT, font=f(9),
                            anchor="w", justify="left",
                            wraplength=wrap or 0, cursor="hand2")
        self.lbl.pack(side="left", padx=(9, 0))
        for w in (self, self.box, self.lbl):
            w.bind("<Button-1>", self._toggle)
        self._draw()
        variable.trace_add("write", lambda *_a: self._draw())

    def _toggle(self, _e=None):
        self.var.set(not self.var.get())

    def _draw(self):
        self.box.delete("all")
        on = bool(self.var.get())
        round_rect(self.box, 1, 1, 16, 16, 4,
                   fill=ACCENT if on else SURFACE,
                   outline=ACCENT if on else HAIRLINE_STRONG, width=1)
        if on:
            self.box.create_line(4.5, 9, 7.5, 12, 12.5, 5.5,
                                 fill="#FFFFFF", width=2, capstyle="round",
                                 joinstyle="round")


def apply_ttk_theme(root: tk.Misc) -> None:
    """Quita el aspecto de widget de sistema a los ttk que si usamos."""
    st = ttk.Style(root)
    try:
        st.theme_use("clam")
    except tk.TclError:
        pass

    # Treeview sin borde ni rejilla; cabecera en negro corporativo
    st.configure("Flat.Treeview", background=SURFACE, fieldbackground=SURFACE,
                 foreground=TEXT, rowheight=34, borderwidth=0, font=f(9))
    st.configure("Flat.Treeview.Heading", background=INK_BAR, foreground=TEXT_ON_INK,
                 font=f(7, "bold"), relief="flat", borderwidth=0, padding=(8, 11))
    st.map("Flat.Treeview.Heading", background=[("active", INK_BAR)],
           foreground=[("active", TEXT_ON_INK)])
    st.map("Flat.Treeview", background=[("selected", ACCENT)],
           foreground=[("selected", "#FFFFFF")])
    try:
        st.layout("Flat.Treeview", [("Flat.Treeview.treearea", {"sticky": "nswe"})])
    except tk.TclError:
        pass

    # barra de scroll fina
    st.configure("Flat.Vertical.TScrollbar", background=HAIRLINE_STRONG,
                 troughcolor=SURFACE, borderwidth=0, arrowsize=0,
                 relief="flat", width=8)
    st.map("Flat.Vertical.TScrollbar", background=[("active", TEXT_FAINT)])

    # combobox sin el boton 3D de Windows
    st.configure("Flat.TCombobox", fieldbackground=SURFACE, background=SURFACE,
                 foreground=TEXT, arrowcolor=TEXT_FAINT, borderwidth=0,
                 lightcolor=SURFACE, darkcolor=SURFACE, bordercolor=SURFACE,
                 relief="flat", arrowsize=12, padding=(4, 3))
    st.map("Flat.TCombobox",
           fieldbackground=[("readonly", SURFACE), ("!disabled", SURFACE)],
           background=[("active", SURFACE), ("!disabled", SURFACE)],
           arrowcolor=[("active", ACCENT)],
           bordercolor=[("focus", SURFACE)])
    try:
        st.layout("Flat.TCombobox", [
            ("Combobox.padding", {"sticky": "nswe", "children": [
                ("Combobox.textarea", {"sticky": "nswe"}),
                ("Combobox.downarrow", {"side": "right", "sticky": "ns"}),
            ]}),
        ])
    except tk.TclError:
        pass
    root.option_add("*TCombobox*Listbox.background", SURFACE)
    root.option_add("*TCombobox*Listbox.foreground", TEXT)
    root.option_add("*TCombobox*Listbox.selectBackground", ACCENT)
    root.option_add("*TCombobox*Listbox.selectForeground", "#FFFFFF")
    root.option_add("*TCombobox*Listbox.borderWidth", 0)

    st.configure("Flat.Horizontal.TProgressbar", background=ACCENT,
                 troughcolor=HAIRLINE, borderwidth=0, thickness=2)
