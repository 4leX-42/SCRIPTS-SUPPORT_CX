"""
Modelo, escritor y validador del formato LEDES 98BI (V5, rev. 1-2020).

Spec oficial: https://ledes.org/ledes-98bi-format/
  - ASCII, delimitado por pipe "|"
  - 52 campos
  - Primera linea: LEDES98BI V2[]
  - Segunda linea: cabecera con los 52 nombres de campo
  - Cada linea (incluidas cabeceras) termina en "[]"

Aritmetica obligatoria segun spec:
  LINE_ITEM_TAX_TOTAL = ((UNIT_COST * UNITS) + ADJUSTMENT) * TAX_RATE
  LINE_ITEM_TOTAL     = (UNIT_COST * UNITS) + ADJUSTMENT + LINE_ITEM_TAX_TOTAL
  INVOICE_TOTAL       = suma de LINE_ITEM_TOTAL        (bruto, IVA incluido)
  INVOICE_TAX_TOTAL   = suma de LINE_ITEM_TAX_TOTAL
  INVOICE_NET_TOTAL   = INVOICE_TOTAL - INVOICE_TAX_TOTAL
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field
from decimal import Decimal, ROUND_HALF_UP

FORMAT_LINE = "LEDES98BI V2"
LINE_TERMINATOR = "[]"
DELIMITER = "|"

#: (nombre, tipo, longitud_max o None, obligatorio)
#: obligatorio: "R" requerido siempre, "O" opcional, "C" condicional
FIELDS: list[tuple[str, str, int | None, str]] = [
    ("INVOICE_DATE", "date", 8, "R"),
    ("INVOICE_NUMBER", "char", 50, "R"),
    ("CLIENT_ID", "char", 20, "R"),
    ("LAW_FIRM_MATTER_ID", "char", 20, "R"),
    ("INVOICE_TOTAL", "cur", None, "R"),
    ("BILLING_START_DATE", "date", 8, "R"),
    ("BILLING_END_DATE", "date", 8, "R"),
    ("INVOICE_DESCRIPTION", "char", None, "O"),
    ("LINE_ITEM_NUMBER", "char", 20, "R"),
    ("EXP/FEE/INV_ADJ_TYPE", "char", 2, "R"),
    ("LINE_ITEM_NUMBER_OF_UNITS", "num", None, "C"),
    ("LINE_ITEM_ADJUSTMENT_AMOUNT", "cur", None, "O"),
    ("LINE_ITEM_TOTAL", "cur", None, "R"),
    ("LINE_ITEM_DATE", "date", 8, "R"),
    ("LINE_ITEM_TASK_CODE", "char", 20, "C"),
    ("LINE_ITEM_EXPENSE_CODE", "char", 20, "C"),
    ("LINE_ITEM_ACTIVITY_CODE", "char", 20, "C"),
    ("TIMEKEEPER_ID", "char", 20, "C"),
    ("LINE_ITEM_DESCRIPTION", "char", None, "C"),
    ("LAW_FIRM_ID", "char", 50, "R"),
    ("LINE_ITEM_UNIT_COST", "cur", None, "C"),
    ("TIMEKEEPER_NAME", "char", 30, "C"),
    ("TIMEKEEPER_CLASSIFICATION", "char", 10, "C"),
    ("CLIENT_MATTER_ID", "char", 20, "C"),
    ("PO_NUMBER", "char", 100, "O"),
    ("CLIENT_TAX_ID", "char", 20, "R"),
    ("MATTER_NAME", "char", 255, "R"),
    ("INVOICE_TAX_TOTAL", "cur", None, "O"),
    ("INVOICE_NET_TOTAL", "cur", None, "R"),
    ("INVOICE_CURRENCY", "char", 3, "R"),
    ("TIMEKEEPER_LAST_NAME", "char", 30, "C"),
    ("TIMEKEEPER_FIRST_NAME", "char", 30, "C"),
    ("ACCOUNT_TYPE", "char", 1, "R"),
    ("LAW_FIRM_NAME", "char", 60, "O"),
    ("LAW_FIRM_ADDRESS_1", "char", 60, "O"),
    ("LAW_FIRM_ADDRESS_2", "char", 60, "O"),
    ("LAW_FIRM_CITY", "char", 40, "O"),
    ("LAW_FIRM_STATEorREGION", "char", 40, "O"),
    ("LAW_FIRM_POSTCODE", "char", 20, "O"),
    ("LAW_FIRM_COUNTRY", "char", 3, "O"),
    ("CLIENT_NAME", "char", 60, "O"),
    ("CLIENT_ADDRESS_1", "char", 60, "O"),
    ("CLIENT_ADDRESS_2", "char", 60, "O"),
    ("CLIENT_CITY", "char", 40, "O"),
    ("CLIENT_STATEorREGION", "char", 40, "O"),
    ("CLIENT_POSTCODE", "char", 20, "O"),
    ("CLIENT_COUNTRY", "char", 3, "O"),
    ("LINE_ITEM_TAX_RATE", "rate", None, "O"),
    ("LINE_ITEM_TAX_TOTAL", "cur", None, "R"),
    ("LINE_ITEM_TAX_TYPE", "char", 20, "O"),
    ("INVOICE_REPORTED_TAX_TOTAL", "cur", None, "O"),
    ("INVOICE_TAX_CURRENCY", "char", 3, "O"),
]

FIELD_NAMES = [f[0] for f in FIELDS]
assert len(FIELDS) == 52, "LEDES 98BI debe tener exactamente 52 campos"

VALID_LINE_TYPES = {"F", "E", "IF", "IE"}
VALID_ACCOUNT_TYPES = {"O", "T"}

#: clasificaciones que el estandar marca como "fee support only": no designan
#: a una persona, sino un honorario fijo o un ajuste de factura.
FEE_SUPPORT_CLASSIFICATIONS = {"FLTFEE", "ADJSMT"}

Q2 = Decimal("0.01")
Q4 = Decimal("0.0001")

# ---------------------------------------------------------------------------
# Normalizacion de texto a ASCII
# ---------------------------------------------------------------------------
_ASCII_MAP = {
    "€": "EUR", "£": "GBP", "¥": "JPY", "·": "-",
    "‘": "'", "’": "'", "“": '"', "”": '"',
    "–": "-", "—": "-", "…": "...", "º": "o",
    "ª": "a", "°": "o", "»": '"', "«": '"',
    "Ñ": "N", "ñ": "n", "Ç": "C", "ç": "c",
    "≥": ">=", "≤": "<=", "©": "(c)", "®": "(r)",
}


def to_ascii(text: str) -> str:
    """Transliteracion a ASCII puro. El estandar exige ASCII; muchas
    plataformas rechazan el fichero si aparecen acentos o simbolo de euro."""
    if not text:
        return ""
    out = []
    for ch in str(text):
        if ch in _ASCII_MAP:
            out.append(_ASCII_MAP[ch])
            continue
        if ord(ch) < 128:
            out.append(ch)
            continue
        decomposed = unicodedata.normalize("NFKD", ch)
        stripped = "".join(c for c in decomposed if not unicodedata.combining(c))
        stripped = "".join(c for c in stripped if ord(c) < 128)
        out.append(stripped if stripped else " ")
    return "".join(out)


def clean_text(value, *, maxlen: int | None = None, force_ascii: bool = True) -> str:
    """Limpia un valor de texto para un campo LEDES.

    - elimina el delimitador pipe y los saltos de linea (romperian el fichero)
    - colapsa espacios
    - opcionalmente transliterar a ASCII
    - trunca a la longitud maxima del campo
    """
    if value is None:
        return ""
    s = str(value)
    s = s.replace("\r", " ").replace("\n", " ").replace("\t", " ")
    s = s.replace(DELIMITER, "/")
    s = s.replace("[]", "( )")
    if force_ascii:
        s = to_ascii(s)
    s = re.sub(r"[\x00-\x1f\x7f]", " ", s)
    s = re.sub(r" {2,}", " ", s).strip()
    if maxlen is not None and len(s) > maxlen:
        s = s[:maxlen].rstrip()
    return s


def fmt_decimal(value, places: int = 2) -> str:
    """Numero -> texto plano con punto decimal, sin separador de millares."""
    if value is None or value == "":
        return ""
    d = value if isinstance(value, Decimal) else Decimal(str(value))
    q = Decimal(1).scaleb(-places)
    d = d.quantize(q, rounding=ROUND_HALF_UP)
    s = format(d, "f")
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return s or "0"


def fmt_rate(value) -> str:
    """Tipo impositivo como decimal 0..1 con hasta 6 decimales (0.21 = 21%)."""
    if value is None or value == "":
        return ""
    d = value if isinstance(value, Decimal) else Decimal(str(value))
    if d == 0:
        return "0"
    s = format(d.quantize(Decimal("0.000001"), rounding=ROUND_HALF_UP), "f")
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return s


def fmt_date(value) -> str:
    """Cualquier fecha razonable -> YYYYMMDD."""
    if value is None:
        return ""
    if hasattr(value, "strftime"):
        return value.strftime("%Y%m%d")
    s = re.sub(r"\D", "", str(value))
    return s[:8]


def dec(value, default: str = "0") -> Decimal:
    """Conversion tolerante a Decimal."""
    if isinstance(value, Decimal):
        return value
    if value is None or value == "":
        return Decimal(default)
    try:
        return Decimal(str(value).strip().replace(" ", ""))
    except Exception:
        return Decimal(default)


# ---------------------------------------------------------------------------
# Modelo
# ---------------------------------------------------------------------------
@dataclass
class LineItem:
    """Una linea de factura: honorario (F), gasto (E) o ajuste (IF / IE)."""

    line_type: str = "F"                  # F | E | IF | IE
    line_date: str = ""                   # YYYYMMDD
    description: str = ""
    units: Decimal = Decimal("1")         # horas (F) o unidades (E)
    unit_cost: Decimal = Decimal("0")     # tarifa/hora o coste unitario, sin IVA
    adjustment: Decimal = Decimal("0")    # descuento (negativo) o recargo
    task_code: str = ""                   # L1xx (solo F)
    activity_code: str = ""               # A1xx (solo F)
    expense_code: str = ""                # E1xx (solo E)
    timekeeper_id: str = ""
    timekeeper_last_name: str = ""
    timekeeper_first_name: str = ""
    timekeeper_classification: str = ""
    tax_rate: Decimal = Decimal("0")      # 0.21 = 21 %
    tax_type: str = "VAT"
    source_page: int = 0                  # trazabilidad: pagina del PDF
    confidence: float = 1.0               # 0-1, fiabilidad de la extraccion
    notes: str = ""                       # avisos de extraccion

    # --- importes derivados (spec 98BI) ---
    @property
    def is_adjustment(self) -> bool:
        return self.line_type in ("IF", "IE")

    @property
    def base(self) -> Decimal:
        """(UNIT_COST * UNITS) + ADJUSTMENT -> base imponible de la linea."""
        if self.is_adjustment:
            return dec(self.adjustment)
        return (dec(self.unit_cost) * dec(self.units) + dec(self.adjustment)).quantize(
            Q2, rounding=ROUND_HALF_UP
        )

    @property
    def tax_total(self) -> Decimal:
        return (self.base * dec(self.tax_rate)).quantize(Q2, rounding=ROUND_HALF_UP)

    @property
    def total(self) -> Decimal:
        return (self.base + self.tax_total).quantize(Q2, rounding=ROUND_HALF_UP)

    @property
    def timekeeper_name(self) -> str:
        """El estandar exige "Apellidos Nombre"."""
        last = (self.timekeeper_last_name or "").strip()
        first = (self.timekeeper_first_name or "").strip()
        return f"{last} {first}".strip()


@dataclass
class Invoice:
    """Una factura completa lista para exportar a 98BI."""

    # --- cabecera factura ---
    invoice_date: str = ""
    invoice_number: str = ""
    billing_start_date: str = ""
    billing_end_date: str = ""
    invoice_description: str = ""
    currency: str = "EUR"
    account_type: str = "O"               # O = own account, T = third party
    po_number: str = ""
    reported_tax_total: str = ""           # opcional, moneda nacional
    tax_currency: str = ""

    # --- identificadores ---
    client_id: str = ""
    law_firm_matter_id: str = ""
    client_matter_id: str = ""
    matter_name: str = ""
    law_firm_id: str = ""                 # CIF/NIF del despacho
    client_tax_id: str = ""               # CIF/NIF del cliente

    # --- datos de despacho ---
    law_firm_name: str = ""
    law_firm_address_1: str = ""
    law_firm_address_2: str = ""
    law_firm_city: str = ""
    law_firm_region: str = ""
    law_firm_postcode: str = ""
    law_firm_country: str = "ESP"

    # --- datos de cliente ---
    client_name: str = ""
    client_address_1: str = ""
    client_address_2: str = ""
    client_city: str = ""
    client_region: str = ""
    client_postcode: str = ""
    client_country: str = "ESP"

    lines: list[LineItem] = field(default_factory=list)

    # --- trazabilidad ---
    source_pdf: str = ""
    extraction_notes: list[str] = field(default_factory=list)
    #: totales leidos del PDF, para cuadrar contra lo calculado
    pdf_net_total: Decimal | None = None
    pdf_tax_total: Decimal | None = None
    pdf_gross_total: Decimal | None = None
    #: la factura lleva retencion (IRPF). LEDES 98BI no tiene campo para ella,
    #: asi que el "total a pagar" del PDF no puede cuadrar con INVOICE_TOTAL.
    has_retention: bool = False

    # --- totales calculados ---
    @property
    def invoice_total(self) -> Decimal:
        return sum((l.total for l in self.lines), Decimal("0")).quantize(Q2)

    @property
    def invoice_tax_total(self) -> Decimal:
        return sum((l.tax_total for l in self.lines), Decimal("0")).quantize(Q2)

    @property
    def invoice_net_total(self) -> Decimal:
        return (self.invoice_total - self.invoice_tax_total).quantize(Q2)


# ---------------------------------------------------------------------------
# Escritor
# ---------------------------------------------------------------------------
def _row_for_line(inv: Invoice, line: LineItem, index: int, force_ascii: bool) -> list[str]:
    ct = lambda v, n: clean_text(v, maxlen=n, force_ascii=force_ascii)  # noqa: E731

    is_fee = line.line_type in ("F", "IF")
    is_expense = line.line_type in ("E", "IE")

    values = {
        "INVOICE_DATE": fmt_date(inv.invoice_date),
        "INVOICE_NUMBER": ct(inv.invoice_number, 50),
        "CLIENT_ID": ct(inv.client_id, 20),
        "LAW_FIRM_MATTER_ID": ct(inv.law_firm_matter_id, 20),
        "INVOICE_TOTAL": fmt_decimal(inv.invoice_total),
        "BILLING_START_DATE": fmt_date(inv.billing_start_date),
        "BILLING_END_DATE": fmt_date(inv.billing_end_date),
        "INVOICE_DESCRIPTION": ct(inv.invoice_description, 4000),
        "LINE_ITEM_NUMBER": str(index),
        "EXP/FEE/INV_ADJ_TYPE": ct(line.line_type, 2).upper(),
        "LINE_ITEM_NUMBER_OF_UNITS": "" if line.is_adjustment else fmt_decimal(line.units, 4),
        "LINE_ITEM_ADJUSTMENT_AMOUNT": fmt_decimal(line.adjustment),
        "LINE_ITEM_TOTAL": fmt_decimal(line.total),
        "LINE_ITEM_DATE": fmt_date(line.line_date or inv.invoice_date),
        "LINE_ITEM_TASK_CODE": ct(line.task_code, 20) if is_fee else "",
        "LINE_ITEM_EXPENSE_CODE": ct(line.expense_code, 20) if is_expense else "",
        "LINE_ITEM_ACTIVITY_CODE": ct(line.activity_code, 20) if is_fee else "",
        "TIMEKEEPER_ID": ct(line.timekeeper_id, 20),
        "LINE_ITEM_DESCRIPTION": ct(line.description, 4000),
        "LAW_FIRM_ID": ct(inv.law_firm_id, 50),
        "LINE_ITEM_UNIT_COST": "" if line.is_adjustment else fmt_decimal(line.unit_cost, 4),
        "TIMEKEEPER_NAME": ct(line.timekeeper_name, 30),
        "TIMEKEEPER_CLASSIFICATION": ct(line.timekeeper_classification, 10),
        "CLIENT_MATTER_ID": ct(inv.client_matter_id, 20),
        "PO_NUMBER": ct(inv.po_number, 100),
        "CLIENT_TAX_ID": ct(inv.client_tax_id, 20),
        "MATTER_NAME": ct(inv.matter_name, 255),
        "INVOICE_TAX_TOTAL": fmt_decimal(inv.invoice_tax_total),
        "INVOICE_NET_TOTAL": fmt_decimal(inv.invoice_net_total),
        "INVOICE_CURRENCY": ct(inv.currency, 3).upper(),
        "TIMEKEEPER_LAST_NAME": ct(line.timekeeper_last_name, 30),
        "TIMEKEEPER_FIRST_NAME": ct(line.timekeeper_first_name, 30),
        "ACCOUNT_TYPE": ct(inv.account_type, 1).upper(),
        "LAW_FIRM_NAME": ct(inv.law_firm_name, 60),
        "LAW_FIRM_ADDRESS_1": ct(inv.law_firm_address_1, 60),
        "LAW_FIRM_ADDRESS_2": ct(inv.law_firm_address_2, 60),
        "LAW_FIRM_CITY": ct(inv.law_firm_city, 40),
        "LAW_FIRM_STATEorREGION": ct(inv.law_firm_region, 40),
        "LAW_FIRM_POSTCODE": ct(inv.law_firm_postcode, 20),
        "LAW_FIRM_COUNTRY": ct(inv.law_firm_country, 3).upper(),
        "CLIENT_NAME": ct(inv.client_name, 60),
        "CLIENT_ADDRESS_1": ct(inv.client_address_1, 60),
        "CLIENT_ADDRESS_2": ct(inv.client_address_2, 60),
        "CLIENT_CITY": ct(inv.client_city, 40),
        "CLIENT_STATEorREGION": ct(inv.client_region, 40),
        "CLIENT_POSTCODE": ct(inv.client_postcode, 20),
        "CLIENT_COUNTRY": ct(inv.client_country, 3).upper(),
        "LINE_ITEM_TAX_RATE": fmt_rate(line.tax_rate),
        "LINE_ITEM_TAX_TOTAL": fmt_decimal(line.tax_total),
        "LINE_ITEM_TAX_TYPE": ct(line.tax_type, 20),
        "INVOICE_REPORTED_TAX_TOTAL": fmt_decimal(inv.reported_tax_total)
        if inv.reported_tax_total not in ("", None)
        else "",
        "INVOICE_TAX_CURRENCY": ct(inv.tax_currency, 3).upper(),
    }
    return [values[name] for name in FIELD_NAMES]


def render(invoices: list[Invoice], *, force_ascii: bool = True) -> str:
    """Genera el contenido completo de un fichero LEDES 98BI.

    Varias facturas pueden ir en el mismo fichero; la numeracion de
    LINE_ITEM_NUMBER es unica y continua en todo el fichero, como exige la spec.
    """
    out = [FORMAT_LINE + LINE_TERMINATOR]
    out.append(DELIMITER.join(FIELD_NAMES) + LINE_TERMINATOR)
    counter = 0
    for inv in invoices:
        for line in inv.lines:
            counter += 1
            row = _row_for_line(inv, line, counter, force_ascii)
            out.append(DELIMITER.join(row) + LINE_TERMINATOR)
    return "\r\n".join(out) + "\r\n"


def write_file(path: str, invoices: list[Invoice], *, force_ascii: bool = True) -> str:
    """Escribe el fichero en disco. Devuelve la ruta escrita."""
    content = render(invoices, force_ascii=force_ascii)
    encoding = "ascii" if force_ascii else "utf-8"
    with open(path, "w", encoding=encoding, errors="replace", newline="") as fh:
        fh.write(content)
    return path


# ---------------------------------------------------------------------------
# Validador
# ---------------------------------------------------------------------------
#: severidades
ERROR = "ERROR"
WARN = "AVISO"


def validate(inv: Invoice) -> list[tuple[str, str]]:
    """Comprueba la factura contra las reglas del estandar 98BI.

    Devuelve lista de (severidad, mensaje). ERROR = la plataforma lo rechazara.
    AVISO = probablemente pasa, pero conviene revisarlo.
    """
    problems: list[tuple[str, str]] = []
    add = problems.append

    # --- campos obligatorios de cabecera ---
    required_header = [
        ("invoice_date", "INVOICE_DATE (fecha de factura)"),
        ("invoice_number", "INVOICE_NUMBER (numero de factura)"),
        ("client_id", "CLIENT_ID (código de cliente del despacho)"),
        ("law_firm_matter_id", "LAW_FIRM_MATTER_ID (código de asunto del despacho)"),
        ("billing_start_date", "BILLING_START_DATE (inicio del periodo)"),
        ("billing_end_date", "BILLING_END_DATE (fin del periodo)"),
        ("law_firm_id", "LAW_FIRM_ID (CIF/NIF del despacho)"),
        ("client_tax_id", "CLIENT_TAX_ID (CIF/NIF del cliente)"),
        ("matter_name", "MATTER_NAME (nombre del asunto)"),
        ("currency", "INVOICE_CURRENCY (moneda)"),
        ("account_type", "ACCOUNT_TYPE (O u T)"),
    ]
    for attr, label in required_header:
        if not str(getattr(inv, attr, "") or "").strip():
            add((ERROR, f"Falta campo obligatorio: {label}"))

    # --- formato de fechas ---
    for attr, label in (
        ("invoice_date", "INVOICE_DATE"),
        ("billing_start_date", "BILLING_START_DATE"),
        ("billing_end_date", "BILLING_END_DATE"),
    ):
        raw = fmt_date(getattr(inv, attr, ""))
        if raw and not re.fullmatch(r"(19|20)\d{2}(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])", raw):
            add((ERROR, f"{label} no es una fecha YYYYMMDD válida: '{raw}'"))

    start = fmt_date(inv.billing_start_date)
    end = fmt_date(inv.billing_end_date)
    if start and end and start > end:
        add((ERROR, f"BILLING_START_DATE ({start}) posterior a BILLING_END_DATE ({end})"))

    if len(str(inv.currency or "").strip()) != 3:
        add((ERROR, f"INVOICE_CURRENCY debe ser código ISO de 3 letras, no '{inv.currency}'"))

    if str(inv.account_type or "").upper() not in VALID_ACCOUNT_TYPES:
        add((ERROR, f"ACCOUNT_TYPE debe ser 'O' o 'T', no '{inv.account_type}'"))

    if not inv.lines:
        add((ERROR, "La factura no tiene ninguna línea"))
        return problems

    # --- lineas ---
    for i, line in enumerate(inv.lines, 1):
        tag = f"Línea {i}"
        lt = str(line.line_type or "").upper()
        if lt not in VALID_LINE_TYPES:
            add((ERROR, f"{tag}: EXP/FEE/INV_ADJ_TYPE debe ser F, E, IF o IE, no '{lt}'"))

        ldate = fmt_date(line.line_date or inv.invoice_date)
        if not ldate:
            add((ERROR, f"{tag}: falta LINE_ITEM_DATE"))
        elif not re.fullmatch(r"(19|20)\d{2}(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])", ldate):
            add((ERROR, f"{tag}: LINE_ITEM_DATE inválida '{ldate}'"))
        elif start and end and not (start <= ldate <= end):
            add((WARN, f"{tag}: la fecha {ldate} cae fuera del periodo facturado {start}-{end}"))

        if not line.is_adjustment:
            if dec(line.units) == 0:
                add((ERROR, f"{tag}: LINE_ITEM_NUMBER_OF_UNITS no puede ser 0 ni vacío"))
            if dec(line.unit_cost) == 0:
                add((ERROR, f"{tag}: LINE_ITEM_UNIT_COST no puede ser 0 ni vacío"))

        if lt == "F":
            if not line.task_code:
                add((ERROR, f"{tag}: línea de honorarios sin LINE_ITEM_TASK_CODE (UTBMS L1xx)"))
            if not line.activity_code:
                add((WARN, f"{tag}: línea de honorarios sin LINE_ITEM_ACTIVITY_CODE (A1xx)"))
            elif not line.task_code:
                add((ERROR, f"{tag}: no se puede usar activity code sin task code"))
            cls = str(line.timekeeper_classification or "").upper()
            if not cls:
                add((ERROR, f"{tag}: línea de honorarios sin TIMEKEEPER_CLASSIFICATION"))
            elif cls in FEE_SUPPORT_CLASSIFICATIONS:
                # FLTFEE / ADJSMT no designan a una persona: el estandar las
                # prevee para honorarios fijos y ajustes, sin profesional
                if line.timekeeper_id or line.timekeeper_last_name:
                    add((WARN, f"{tag}: clasificación {cls} no designa a un profesional; "
                               f"los datos de timekeeper se enviarán pero son informativos"))
            else:
                if not line.timekeeper_id:
                    add((ERROR, f"{tag}: línea de honorarios sin TIMEKEEPER_ID"))
                if not line.timekeeper_last_name:
                    add((ERROR, f"{tag}: línea de honorarios sin apellido del profesional"))
            if line.expense_code:
                add((WARN, f"{tag}: línea F con código de gasto; se ignorará al exportar"))

        if lt == "E":
            if not line.expense_code:
                add((ERROR, f"{tag}: línea de gasto sin LINE_ITEM_EXPENSE_CODE (UTBMS E1xx)"))
            if line.task_code or line.activity_code:
                add((WARN, f"{tag}: línea E con task/activity code; se ignorarán al exportar"))

        if not str(line.description or "").strip():
            sev = ERROR if lt == "F" else WARN
            add((sev, f"{tag}: falta LINE_ITEM_DESCRIPTION"))

        rate = dec(line.tax_rate)
        if rate < 0 or rate > 1:
            add((ERROR, f"{tag}: LINE_ITEM_TAX_RATE debe estar entre 0 y 1 (0.21 = 21%), no {rate}"))
        elif rate > Decimal("0.5"):
            add((WARN, f"{tag}: tipo impositivo {rate} parece alto; comprueba que no sea 21 en vez de 0,21"))

        if len(clean_text(line.timekeeper_name, force_ascii=False)) > 30:
            add((WARN, f"{tag}: TIMEKEEPER_NAME se truncará a 30 caracteres"))

    # --- numeracion unica ---
    if len({id(l) for l in inv.lines}) != len(inv.lines):
        add((ERROR, "Hay líneas duplicadas en memoria"))

    # --- cuadre contra los totales leidos del PDF ---
    tol = Decimal("0.05")
    if inv.pdf_net_total is not None:
        diff = abs(inv.invoice_net_total - inv.pdf_net_total)
        if diff > tol:
            add((WARN, f"Base imponible calculada {inv.invoice_net_total} != base del PDF "
                       f"{inv.pdf_net_total} (diferencia {diff})"))
    if inv.pdf_tax_total is not None:
        diff = abs(inv.invoice_tax_total - inv.pdf_tax_total)
        if diff > tol:
            add((WARN, f"IVA calculado {inv.invoice_tax_total} != IVA del PDF "
                       f"{inv.pdf_tax_total} (diferencia {diff})"))
    if inv.pdf_gross_total is not None:
        diff = abs(inv.invoice_total - inv.pdf_gross_total)
        if diff > tol and not inv.has_retention:
            add((WARN, f"Total calculado {inv.invoice_total} != total del PDF "
                       f"{inv.pdf_gross_total} (diferencia {diff})"))
        elif diff > tol:
            add((WARN, f"INVOICE_TOTAL calculado {inv.invoice_total}; el 'total a pagar' "
                       f"del PDF es {inv.pdf_gross_total} porque descuenta la retención "
                       f"(diferencia {diff}). En LEDES 98BI es correcto no descontarla."))

    # --- caracteres no ASCII ---
    for i, line in enumerate(inv.lines, 1):
        if any(ord(c) > 127 for c in str(line.description or "")):
            add((WARN, f"Línea {i}: la descripción tiene caracteres no ASCII; "
                       f"se transliterarán (acentos, símbolo de euro)"))
            break

    return problems


def summarize(problems: list[tuple[str, str]]) -> tuple[int, int]:
    """(numero de errores, numero de avisos)."""
    errs = sum(1 for s, _ in problems if s == ERROR)
    warns = sum(1 for s, _ in problems if s == WARN)
    return errs, warns
