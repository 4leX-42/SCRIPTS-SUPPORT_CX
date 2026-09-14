"""
Motor de extraccion de facturas en PDF -> modelo Invoice.

Estrategia en cascada, de mas fiable a mas especulativa:

  1. Cabecera de factura por etiquetas (regex ES/EN): numero, fecha, periodo,
     CIF/NIF, cliente, asunto, moneda, tipo de IVA, totales.
  2. Lineas de detalle:
       a) tablas nativas del PDF (pdfplumber.extract_tables)
       b) si no hay tablas, agrupacion de palabras por coordenada Y y
          deduccion de columnas por coordenada X
       c) si tampoco, una sola linea agregada con el importe total
  3. Cuadre: se comparan base/IVA/total calculados contra los leidos del PDF
     y se anota la discrepancia como aviso.

Cada campo extraido lleva una confianza. Nada se exporta sin que el usuario
lo vea en la tabla de revision.
"""

from __future__ import annotations

import os
import re
import unicodedata
from decimal import Decimal, ROUND_HALF_UP, InvalidOperation

import pdfplumber

from ledes98bi import Invoice, LineItem, dec
import utbms

Q2 = Decimal("0.01")

# ---------------------------------------------------------------------------
# Utilidades de texto y numero
# ---------------------------------------------------------------------------


def strip_accents(text: str) -> str:
    t = unicodedata.normalize("NFKD", str(text or ""))
    return "".join(c for c in t if not unicodedata.combining(c))


def norm(text: str) -> str:
    return re.sub(r"[\s ]+", " ", strip_accents(text).lower()).strip()


_NUM_RE = re.compile(r"-?\(?\s*\d{1,3}(?:[., \s]\d{3})*(?:[.,]\d{1,4})?\s*\)?|-?\d+(?:[.,]\d{1,4})?")


def parse_number(raw: str) -> Decimal | None:
    """Convierte un numero de factura en Decimal.

    Soporta formato espanol (1.234,56), ingles (1,234.56), sin separadores
    y negativos con parentesis o signo.
    """
    if raw is None:
        return None
    s = str(raw).strip()
    if not s:
        return None
    s = s.replace(" ", " ")
    s = re.sub(r"[^\d,.\-()]", "", s)
    if not re.search(r"\d", s):
        return None

    negative = s.startswith("-") or ("(" in s and ")" in s)
    s = s.replace("(", "").replace(")", "").replace("-", "")

    has_comma, has_dot = "," in s, "." in s
    if has_comma and has_dot:
        # el separador decimal es el que aparece mas a la derecha
        if s.rfind(",") > s.rfind("."):
            s = s.replace(".", "").replace(",", ".")
        else:
            s = s.replace(",", "")
    elif has_comma:
        # una sola coma: decimal si deja 1-2 decimales o no agrupa de 3 en 3
        parts = s.split(",")
        if len(parts) == 2 and len(parts[1]) != 3:
            s = s.replace(",", ".")
        elif len(parts) == 2 and len(parts[1]) == 3 and len(parts[0]) > 3:
            s = s.replace(",", "")          # 1,234 -> millar
        else:
            s = s.replace(",", ".")
    elif has_dot:
        parts = s.split(".")
        if len(parts) > 2:
            s = s.replace(".", "")          # 1.234.567
        elif len(parts) == 2 and len(parts[1]) == 3 and len(parts[0]) <= 3:
            # ambiguo: 1.234 -> se trata como millar solo si no hay decimales
            s = s.replace(".", "")
    try:
        value = Decimal(s)
    except (InvalidOperation, ValueError):
        return None
    return -value if negative else value


_CLEAN_NUM_TOKEN = re.compile(
    r"[-+(]?[\d., ]+\)?\s*(?:%|€|eur|usd|gbp|\$|£)?$", re.I)


def parse_numeric_cell(raw: str) -> Decimal | None:
    """Numero de una celda de tabla de PDF, o None si la celda esta corrupta.

    pdfplumber entremezcla columnas cuando el texto de una celda se desborda
    sobre la vecina: "proce1s,a5l0" es "procesal" + "1,50" fusionados y el
    numero es irrecuperable. Devolver None permite deducirlo despues de la
    aritmetica de la fila (importe / tarifa), que si es fiable.

    Casos que si se recuperan: texto desbordado como token aparte
    ("cional 180,00"), simbolo de moneda o porcentaje pegado ("300,00 EUR").
    """
    if raw is None:
        return None
    s = str(raw).strip()
    if not s:
        return None
    tokens = [t for t in re.split(r"[\s ]+", s) if t]
    # descartar tokens sin ningun digito: son texto de la columna vecina
    numeric_tokens = [t for t in tokens if any(c.isdigit() for c in t)]
    if len(numeric_tokens) != 1:
        return None                      # ninguno, o varios -> ambiguo
    token = numeric_tokens[0]
    if not _CLEAN_NUM_TOKEN.fullmatch(token):
        return None                      # letras pegadas a los digitos
    return parse_number(token)




def find_numbers(text: str) -> list[Decimal]:
    out = []
    for m in _NUM_RE.finditer(text or ""):
        v = parse_number(m.group())
        if v is not None:
            out.append(v)
    return out


# ---------------------------------------------------------------------------
# Fechas
# ---------------------------------------------------------------------------
_MONTHS = {
    "enero": 1, "febrero": 2, "marzo": 3, "abril": 4, "mayo": 5, "junio": 6,
    "julio": 7, "agosto": 8, "septiembre": 9, "setiembre": 9, "octubre": 10,
    "noviembre": 11, "diciembre": 12,
    "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6,
    "july": 7, "august": 8, "september": 9, "october": 10, "november": 11,
    "december": 12,
    "ene": 1, "feb": 2, "mar": 3, "abr": 4, "may": 5, "jun": 6, "jul": 7,
    "ago": 8, "sep": 9, "sept": 9, "oct": 10, "nov": 11, "dic": 12,
    "jan": 1, "apr": 4, "aug": 8, "dec": 12,
}

_DATE_PATTERNS = [
    # 12/03/2025  12-03-2025  12.03.2025
    (re.compile(r"\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})\b"), "dmy"),
    # 2025/03/12  2025-03-12
    (re.compile(r"\b(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})\b"), "ymd"),
    # 12 de marzo de 2025 / 12 marzo 2025 / 12-mar-2025
    (re.compile(r"\b(\d{1,2})\s*(?:de\s+)?[-\s]?([a-zA-Z]{3,12})\.?\s*(?:de\s+)?[-\s]?(\d{4})\b"), "dMy"),
    # March 12, 2025
    (re.compile(r"\b([a-zA-Z]{3,12})\.?\s+(\d{1,2}),?\s+(\d{4})\b"), "Mdy"),
    # 12/03/25
    (re.compile(r"\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2})\b"), "dmy2"),
    # 20250312
    (re.compile(r"\b((?:19|20)\d{2})(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])\b"), "compact"),
]


def parse_date(text: str) -> str | None:
    """Primera fecha reconocible del texto -> YYYYMMDD, o None."""
    if not text:
        return None
    t = strip_accents(str(text))
    for rx, kind in _DATE_PATTERNS:
        m = rx.search(t)
        if not m:
            continue
        try:
            if kind == "dmy":
                d, mo, y = int(m.group(1)), int(m.group(2)), int(m.group(3))
            elif kind == "ymd":
                y, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
            elif kind == "dmy2":
                d, mo, y = int(m.group(1)), int(m.group(2)), 2000 + int(m.group(3))
            elif kind == "compact":
                y, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
            elif kind == "dMy":
                mo = _MONTHS.get(m.group(2).lower())
                if not mo:
                    continue
                d, y = int(m.group(1)), int(m.group(3))
            else:  # Mdy
                mo = _MONTHS.get(m.group(1).lower())
                if not mo:
                    continue
                d, y = int(m.group(2)), int(m.group(3))
            if not (1 <= mo <= 12 and 1 <= d <= 31 and 1900 <= y <= 2100):
                continue
            return f"{y:04d}{mo:02d}{d:02d}"
        except (ValueError, TypeError):
            continue
    return None


def _first_date_in_order(text: str) -> str | None:
    """Primera fecha segun su posicion en el texto, no por orden cronologico."""
    best_pos, best = None, None
    t = strip_accents(str(text or ""))
    for rx, _ in _DATE_PATTERNS:
        for m in rx.finditer(t):
            d = parse_date(m.group())
            if d and (best_pos is None or m.start() < best_pos):
                best_pos, best = m.start(), d
    return best


def all_dates(text: str) -> list[str]:
    """Todas las fechas del texto, en YYYYMMDD, ordenadas."""
    found: set[str] = set()
    t = strip_accents(str(text or ""))
    for rx, _ in _DATE_PATTERNS:
        for m in rx.finditer(t):
            d = parse_date(m.group())
            if d:
                found.add(d)
    return sorted(found)


# ---------------------------------------------------------------------------
# Cabecera de factura: etiquetas ES / EN
# ---------------------------------------------------------------------------
#: Ojo con el orden y con los limites: "num" casa dentro de "number" y "nu"
#: dentro de "num". Las alternativas largas van primero y _label_value exige
#: que detras de la etiqueta no venga otra letra.
_LABEL_INVOICE_NUMBER = [
    r"n[uú]mero\s*(?:de\s*)?factura", r"n[uú]m\.?\s*(?:de\s*)?factura",
    r"n[ºo°]\.?\s*(?:de\s*)?factura", r"referencia\s*(?:de\s*)?factura",
    r"factura\s*n[uú]mero", r"factura\s*n[uú]m\.?", r"factura\s*n[ºo°]\.?",
    r"invoice\s*number", r"invoice\s*n[ºo°]\.?", r"invoice\s*(?:no|num|nbr|#)\.?",
    r"factura\s*simplificada",
]
_LABEL_INVOICE_DATE = [
    r"fecha\s*(?:de\s*)?(?:la\s*)?factura", r"fecha\s*(?:de\s*)?emisi[oó]n",
    r"invoice\s*date", r"date\s*of\s*invoice", r"fecha\s*expedici[oó]n", r"^fecha\b",
]
_LABEL_DUE = [r"fecha\s*(?:de\s*)?vencimiento", r"due\s*date", r"vencimiento"]
_LABEL_PERIOD = [
    r"periodo\s*(?:de\s*)?facturaci[oó]n", r"per[ií]odo", r"billing\s*period",
    r"periodo\s*facturado", r"servicios\s*prestados\s*(?:entre|del)",
]
_LABEL_MATTER = [
    r"asunto", r"expediente", r"matter", r"referencia\s*(?:del\s*)?asunto",
    r"n[uo]?\.?\s*expediente", r"caso", r"case\b", r"proyecto", r"nuestra\s*referencia",
    r"our\s*ref", r"ref\.?\s*asunto",
]
_LABEL_CLIENT_REF = [
    r"su\s*referencia", r"your\s*ref", r"referencia\s*(?:del\s*)?cliente",
    r"client\s*(?:matter\s*)?ref", r"client\s*matter",
    r"\bexp(?:ediente)?\.?\s*(?:n[uo]?\.?)?\s*(?=\d)",
]
_LABEL_PO = [
    r"n[uo]?\.?\s*(?:de\s*)?pedido", r"purchase\s*order", r"\bp\.?\s*o\.?\s*n[uo]",
    r"\bp\.?\s*o\.?\s*(?:number)?\s*:", r"\bpo\s*:", r"orden\s*de\s*compra",
]
#: codigo interno de cliente del despacho -> CLIENT_ID
_LABEL_CLIENT_ID = [
    r"c[oó]digo\s*(?:de\s*)?cliente", r"c[oó]d\.?\s*cliente", r"cod\.?\s*cliente",
    r"client\s*(?:code|id|number|no)", r"n[uo]?\.?\s*(?:de\s*)?cliente",
    r"cuenta\s*(?:de\s*)?cliente",
]
_LABEL_CLIENT_NAME = [
    r"facturar\s*a", r"bill\s*to", r"destinatario", r"raz[oó]n\s*social",
    r"^\s*cliente\s*:", r"^\s*client\s*:", r"customer",
]
#: sufijos de forma societaria: identifican la linea del nombre del cliente
_COMPANY_SUFFIX = re.compile(
    r"\b(s\.?\s?l\.?\s?u?\.?|s\.?\s?a\.?\s?u?\.?|s\.?\s?l\.?\s?p\.?|s\.?\s?c\.?\s?p\.?"
    r"|s\.?\s?comm?\.?|a\.?\s?i\.?\s?e\.?|c\.?\s?b\.?|u\.?\s?t\.?\s?e\.?"
    r"|ltd|limited|plc|gmbh|inc|llc|b\.?v\.?|n\.?v\.?|s\.?a\.?s\.?|s\.?r\.?l\.?)\s*$",
    re.I)
_LABEL_NET = [
    r"base\s*imponible", r"subtotal", r"total\s*(?:de\s*)?honorarios\s*y\s*suplidos",
    r"net\s*(?:total|amount)", r"total\s*sin\s*iva", r"importe\s*neto", r"base\b",
]
#: cuota de impuesto. No confundir con el numero de identificacion fiscal:
#: "VAT number", "NIF", "CIF" quedan excluidos explicitamente.
_LABEL_TAX = [
    r"cuota\s*(?:de\s*)?i\.?v\.?a\.?", r"total\s*impuestos",
    r"impuesto\s*sobre\s*el\s*valor\s*a[nñ]adido",
    r"i\.?v\.?a\.?(?!\s*(?:number|no\b|n[ºo°]|id\b|reg))",
    r"\bigic\b", r"\bipsi\b",
    r"\bvat(?!\s*(?:number|no\b|n[ºo°]|id\b|reg|registration))\b",
]
_LABEL_GROSS = [
    r"total\s*factura", r"total\s*a\s*pagar", r"importe\s*total", r"total\s*general",
    r"total\s*(?:con\s*)?iva", r"invoice\s*total", r"total\s*due", r"grand\s*total",
    r"^total\b",
]
_LABEL_RETENTION = [r"retenci[oó]n", r"\birpf\b", r"withholding"]
_LABEL_TAXID = [r"\bc\.?i\.?f\.?\b", r"\bn\.?i\.?f\.?\b", r"\bvat\s*(?:no|number|id)",
                r"\bnif\b", r"\bcif\b", r"tax\s*id", r"\bn\.?i\.?e\.?\b"]

_TAXID_VALUE = re.compile(
    r"\b((?:ES)?[A-HJ-NP-SUVW]\s?\d{7}\s?[0-9A-J]|(?:ES)?\d{8}\s?[A-Z]|(?:ES)?[XYZ]\s?\d{7}\s?[A-Z]|[A-Z]{2}\d{8,12})\b",
    re.I,
)

_CURRENCY_HINTS = [
    (r"€|\beur\b|\beuros?\b", "EUR"),
    (r"\bgbp\b|£|\blibras?\b|\bpounds?\b", "GBP"),
    (r"\busd\b|\bus\$|\bd[oó]lar", "USD"),
    (r"\bchf\b|\bfrancos?\s*suizos?\b", "CHF"),
    (r"\bmxn\b|\bpesos?\s*mexicanos?\b", "MXN"),
    (r"\bbrl\b|\breais\b|\breales\b", "BRL"),
    (r"\bcop\b|\bpesos?\s*colombianos?\b", "COP"),
    (r"\bars\b|\bpesos?\s*argentinos?\b", "ARS"),
]


#: en un PDF las etiquetas suelen ir en la misma linea de texto extraida
#: ("Asunto: X   Su referencia: Y"). Para no arrastrar el valor siguiente hay
#: que cortar en la etiqueta posterior.
_ALL_LABELS = (
    _LABEL_INVOICE_NUMBER + _LABEL_INVOICE_DATE + _LABEL_DUE + _LABEL_PERIOD
    + _LABEL_MATTER + _LABEL_CLIENT_REF + _LABEL_PO + _LABEL_CLIENT_ID
    + _LABEL_CLIENT_NAME + _LABEL_NET
    + _LABEL_TAX + _LABEL_GROSS + _LABEL_RETENTION + _LABEL_TAXID
)
_NEXT_LABEL_RE = re.compile(
    r"(?:" + "|".join(f"(?:{p})" for p in _ALL_LABELS) + r")\s*[:\-–]",
    re.I,
)
#: cualquier etiqueta corta seguida de dos puntos, por si no esta en la lista
_GENERIC_LABEL_RE = re.compile(r"\s[A-ZÀ-Ý][\wÀ-ÿ.]{1,22}\s*:")


#: etiqueta de identificacion fiscal sin dos puntos ("... - NIF B96551234")
_TRAILING_TAXID_RE = re.compile(
    r"[\s–—\-,;(]+(?:" + "|".join(f"(?:{p})" for p in _LABEL_TAXID) + r")\b", re.I)


def _cut_at_next_label(value: str) -> str:
    """Recorta el valor en la siguiente etiqueta de la misma linea."""
    if not value:
        return value
    cut = len(value)
    for rx in (_NEXT_LABEL_RE, _GENERIC_LABEL_RE, _TRAILING_TAXID_RE):
        m = rx.search(value, 1)
        if m and m.start() > 0:
            cut = min(cut, m.start())
    # los puntos finales son parte del valor ("S.A."), no separadores
    trimmed = value[:cut].strip(" :;,-–—|")
    return trimmed or value.strip()


def _label_value(lines: list[str], labels: list[str], *, want: str = "text") -> tuple[str, float]:
    """Busca una etiqueta en las lineas y devuelve (valor, confianza).

    Mira primero a la derecha de la etiqueta en la misma linea; si no hay nada,
    mira la linea siguiente.
    """
    for idx, raw in enumerate(lines):
        line = strip_accents(raw)
        low = line.lower()
        for label in labels:
            m = re.search(label, low)
            if not m:
                continue
            # la etiqueta no puede ser el prefijo de otra palabra: "num" dentro
            # de "number", "nu" dentro de "num", "iva" dentro de "LIVA"
            if m.end() < len(low) and low[m.end()].isalpha():
                continue
            if m.start() > 0 and low[m.start() - 1].isalpha():
                continue
            rest = line[m.end():]
            rest = re.sub(r"^\s*[:\-–.#]+\s*", "", rest).strip()
            candidates = [(rest, 0.85)]
            # los importes de totales van siempre en la misma linea que su
            # etiqueta; mirar la siguiente haria que "IVA: exento" se llevase
            # el total de la linea de debajo
            if idx + 1 < len(lines) and want != "money":
                candidates.append((strip_accents(lines[idx + 1]).strip(), 0.5))
            for cand, conf in candidates:
                if not cand:
                    continue
                if want == "date":
                    d = parse_date(cand)
                    if d:
                        return d, conf
                elif want == "number":
                    nums = find_numbers(cand)
                    if nums:
                        return str(nums[-1]), conf
                elif want == "money":
                    # un importe de factura lleva decimales o simbolo de moneda.
                    # Asi no se confunde "articulo 69 LIVA" con una cuota de IVA.
                    if not re.search(r"\d[.,]\d{2}\b|€|\beur\b|\$|\busd\b|"
                                     r"£|\bgbp\b|\bchf\b", cand, re.I):
                        continue
                    nums = find_numbers(cand)
                    if nums:
                        return str(nums[-1]), conf
                elif want == "taxid":
                    tm = _TAXID_VALUE.search(cand)
                    if tm:
                        return tm.group(1).replace(" ", "").upper(), conf
                elif want == "code":
                    # ".-" separa campos en una misma linea: no forma parte del codigo
                    cand = re.split(r"\.\s*-", cand)[0]
                    cm = re.search(r"[A-Za-z0-9][A-Za-z0-9._/\-]{1,29}", cand)
                    if cm:
                        return cm.group(0).strip(" .-/"), conf
                else:
                    cleaned = _cut_at_next_label(cand.strip(" .:-–"))
                    if cleaned:
                        return cleaned, conf
    return "", 0.0


def _detect_currency(text: str) -> tuple[str, float]:
    low = norm(text)
    for pattern, code in _CURRENCY_HINTS:
        if re.search(pattern, low):
            return code, 0.8
    return "EUR", 0.2


def _detect_tax_rate(text: str) -> tuple[Decimal, str, float]:
    """Devuelve (tipo como decimal 0-1, tipo de impuesto, confianza)."""
    t = strip_accents(text)
    tax_type = "VAT"
    if re.search(r"\bigic\b", t, re.I):
        tax_type = "IGIC"
    elif re.search(r"\bipsi\b", t, re.I):
        tax_type = "IPSI"
    elif re.search(r"\bgst\b", t, re.I):
        tax_type = "GST"

    # "IVA 21%", "I.V.A. (21 %)", "VAT @ 20%"
    patterns = [
        r"(?:i\.?v\.?a\.?|vat|igic|ipsi|gst|impuesto)[^\d%\n]{0,20}(\d{1,2}(?:[.,]\d{1,2})?)\s*%",
        r"(\d{1,2}(?:[.,]\d{1,2})?)\s*%\s*(?:de\s*)?(?:i\.?v\.?a\.?|vat|igic)",
    ]
    for pattern in patterns:
        m = re.search(pattern, t, re.I)
        if m:
            v = parse_number(m.group(1))
            if v is not None and 0 <= v <= 40:
                return (v / Decimal(100)).quantize(Decimal("0.000001")), tax_type, 0.85

    if re.search(r"exent|exempt|no\s*sujet|inversi[oó]n\s*del\s*sujeto\s*pasivo|reverse\s*charge", t, re.I):
        return Decimal("0"), tax_type, 0.8

    # cualquier porcentaje suelto plausible
    m = re.search(r"\b(4|10|21)\s*%", t)
    if m:
        return (Decimal(m.group(1)) / Decimal(100)), tax_type, 0.5
    # sin ninguna pista: 0, no 21%. Suponer IVA donde no lo hay infla la factura
    # (facturas en USD/GBP sin IVA, operaciones no sujetas). El tipo real se
    # deduce despues de los totales del PDF, si los trae.
    return Decimal("0"), tax_type, 0.0


# ---------------------------------------------------------------------------
# Deteccion de columnas en filas de detalle
# ---------------------------------------------------------------------------
_HEADER_HINTS = {
    "date": [r"\bfecha\b", r"\bdate\b", r"\bdia\b", r"\bf\.?\s*trabajo"],
    "desc": [r"descripci", r"concepto", r"detalle", r"description", r"trabajo",
             r"actuacion", r"narrative", r"servicio"],
    "who": [r"profesional", r"timekeeper", r"abogado", r"letrado", r"iniciales",
            r"\bnombre\b", r"\bname\b", r"\bpersona\b", r"responsable"],
    "units": [r"\bhoras\b", r"\bhrs?\b", r"\bhours?\b", r"\bcantidad\b", r"\bunidades\b",
              r"\btiempo\b", r"\bqty\b", r"\bnum\.?\s*unid", r"\bud\b"],
    "rate": [r"\btarifa\b", r"\brate\b", r"precio\s*(?:unitario|/\s*hora|hora)",
             r"\b(?:eur|€|\$)\s*/\s*h", r"coste\s*unitario", r"\bp\.?\s*unit"],
    "amount": [r"\bimporte\b", r"\btotal\b", r"\bamount\b", r"\bsubtotal\b", r"\bvalor\b"],
    "role": [r"\bcategoria\b", r"\bcargo\b", r"\bclasificaci", r"\bposition\b", r"\bnivel\b"],
}


def _classify_header_cell(cell: str) -> str | None:
    c = norm(cell)
    if not c:
        return None
    for key, patterns in _HEADER_HINTS.items():
        for p in patterns:
            if re.search(p, c):
                return key
    return None


def _map_table_header(row: list[str]) -> dict[int, str] | None:
    """Cabecera de tabla -> {indice_columna: rol}. None si no parece cabecera."""
    mapping: dict[int, str] = {}
    for i, cell in enumerate(row):
        role = _classify_header_cell(cell or "")
        if role and role not in mapping.values():
            mapping[i] = role
    # se considera cabecera valida si identifica descripcion o importe + otra cosa
    roles = set(mapping.values())
    if ("desc" in roles or "amount" in roles) and len(roles) >= 2:
        return mapping
    return None


# ---------------------------------------------------------------------------
# Extraccion principal
# ---------------------------------------------------------------------------
class ExtractionResult:
    def __init__(self, invoice: Invoice, confidence: float, notes: list[str]):
        self.invoice = invoice
        self.confidence = confidence
        self.notes = notes


def _page_text(page) -> str:
    try:
        return page.extract_text(x_tolerance=1.6, y_tolerance=2.6) or ""
    except Exception:
        try:
            return page.extract_text() or ""
        except Exception:
            return ""


def _rows_from_words(page) -> list[list[tuple[float, float, str]]]:
    """Agrupa palabras por coordenada Y en filas: [(x0, x1, texto), ...]."""
    try:
        words = page.extract_words(x_tolerance=1.6, y_tolerance=2.6, keep_blank_chars=False)
    except Exception:
        return []
    buckets: dict[int, list] = {}
    for w in words:
        key = int(round(float(w["top"]) / 3.2))
        buckets.setdefault(key, []).append(w)
    rows = []
    for key in sorted(buckets):
        ws = sorted(buckets[key], key=lambda w: float(w["x0"]))
        rows.append([(float(w["x0"]), float(w["x1"]), w["text"]) for w in ws])
    return rows


def _row_text(row: list[tuple[float, float, str]]) -> str:
    return " ".join(t for _, _, t in row)


def _split_row_by_columns(row, boundaries: list[float]) -> list[str]:
    """Reparte las palabras de una fila en celdas segun los limites X dados."""
    cells = [""] * (len(boundaries) + 1)
    for x0, _x1, text in row:
        idx = 0
        while idx < len(boundaries) and x0 >= boundaries[idx]:
            idx += 1
        cells[idx] = (cells[idx] + " " + text).strip()
    return cells


def _extract_lines_from_tables(pdf, tax_rate, currency) -> tuple[list[LineItem], list[str]]:
    """Estrategia A: tablas nativas del PDF."""
    items: list[LineItem] = []
    notes: list[str] = []
    for pno, page in enumerate(pdf.pages, 1):
        try:
            tables = page.extract_tables()
        except Exception:
            continue
        for table in tables or []:
            if not table or len(table) < 2:
                continue
            header_map = None
            start = 0
            for i, row in enumerate(table[:3]):
                m = _map_table_header([(c or "") for c in row])
                if m:
                    header_map, start = m, i + 1
                    break
            if not header_map:
                continue
            for row in table[start:]:
                cells = [(c or "").strip() for c in row]
                if not any(cells):
                    continue
                item = _row_to_item(cells, header_map, tax_rate, pno)
                if item is not None:
                    items.append(item)
            if items:
                notes.append(f"Detalle leído de tabla nativa en página {pno}")
    return items, notes


def _row_to_item(cells: list[str], header_map: dict[int, str],
                 tax_rate: Decimal, page_no: int) -> LineItem | None:
    """Fila de tabla -> LineItem, o None si es fila de totales/ruido."""
    get = lambda role: next(  # noqa: E731
        (cells[i] for i, r in header_map.items() if r == role and i < len(cells)), ""
    )
    desc = get("desc").strip()
    raw_amount = get("amount")
    raw_units = get("units")
    raw_rate = get("rate")
    raw_date = get("date")
    raw_who = get("who")
    raw_role = get("role")

    joined = norm(" ".join(cells))
    if re.search(r"^(total|subtotal|base\s*imponible|iva|vat|suma|importe\s*total|"
                 r"total\s*factura|retencion|a\s*pagar)", joined):
        return None

    amount = parse_numeric_cell(raw_amount)
    units = parse_numeric_cell(raw_units)
    rate = parse_numeric_cell(raw_rate)
    units_was_dirty = units is None and bool(str(raw_units or "").strip())

    if amount is None and rate is None:
        return None
    if not desc:
        # sin descripcion pero con importe: aprovechar cualquier celda textual larga
        text_cells = [c for c in cells if c and len(c) > 12
                      and not re.fullmatch(r"[\d.,\s€$%-]+", c)]
        if text_cells:
            desc = max(text_cells, key=len)
    if not desc and amount is None:
        return None
    # las celdas con texto ajustado traen saltos de linea
    desc = re.sub(r"\s+", " ", desc).strip()


    is_expense = utbms.looks_like_expense(desc)
    line_type = "E" if is_expense else "F"

    # reconstruir la aritmetica que falte
    if units is None and rate is not None and amount is not None and rate != 0:
        units = (amount / rate).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    if rate is None and units is not None and amount is not None and units != 0:
        rate = (amount / units).quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP)
    if units is None:
        units = Decimal("1")
    if rate is None:
        rate = amount if amount is not None else Decimal("0")
        units = Decimal("1")

    confidence = 0.8
    note = ""
    if amount is not None:
        recomputed = (rate * units).quantize(Q2, rounding=ROUND_HALF_UP)
        if abs(recomputed - amount) > Decimal("0.02"):
            confidence = 0.45
            note = f"el importe del PDF ({amount}) no cuadra con tarifa x unidades ({recomputed})"
        elif units_was_dirty:
            # las unidades se dedujeron, pero reproducen el importe del PDF
            # al centimo: la linea es correcta
            note = "unidades deducidas de importe / tarifa; cuadran con el importe del PDF"
    elif units_was_dirty:
        confidence = 0.5
        note = "columna de unidades ilegible en el PDF y sin importe con el que cuadrar"

    item = LineItem(
        line_type=line_type,
        line_date=parse_date(raw_date) or "",
        description=desc,
        units=units,
        unit_cost=rate,
        tax_rate=tax_rate,
        source_page=page_no,
        confidence=confidence,
        notes=note,
    )
    _assign_codes(item)
    _assign_timekeeper(item, raw_who, raw_role)
    return item


def _extract_lines_from_words(pdf, tax_rate) -> tuple[list[LineItem], list[str]]:
    """Estrategia B: filas por coordenadas, columnas deducidas de la cabecera."""
    items: list[LineItem] = []
    notes: list[str] = []
    for pno, page in enumerate(pdf.pages, 1):
        rows = _rows_from_words(page)
        if not rows:
            continue
        header_idx = None
        col_roles: list[tuple[float, str]] = []
        for i, row in enumerate(rows):
            roles: list[tuple[float, str]] = []
            for x0, _x1, text in row:
                role = _classify_header_cell(text)
                if role and role not in [r for _, r in roles]:
                    roles.append((x0, role))
            names = {r for _, r in roles}
            if len(names) >= 3 and ("desc" in names or "amount" in names):
                header_idx, col_roles = i, sorted(roles)
                break
        if header_idx is None:
            continue

        boundaries = [(col_roles[i][0] + col_roles[i + 1][0]) / 2 for i in range(len(col_roles) - 1)]
        header_map = {i: role for i, (_x, role) in enumerate(col_roles)}

        pending: list[str] | None = None
        for row in rows[header_idx + 1:]:
            text = _row_text(row)
            if not text.strip():
                continue
            low = norm(text)
            if re.match(r"^(total|subtotal|base\s*imponible|iva\b|vat\b|suma|"
                        r"importe\s*total|retencion|a\s*pagar|total\s*factura)", low):
                pending = None
                continue
            cells = _split_row_by_columns(row, boundaries)
            has_money = any(parse_number(cells[i]) is not None
                            for i, r in header_map.items()
                            if r in ("amount", "rate") and i < len(cells))
            if not has_money and pending is not None:
                # continuacion de la descripcion de la fila anterior
                di = next((i for i, r in header_map.items() if r == "desc"), None)
                if di is not None and di < len(cells) and cells[di]:
                    pending[di] = (pending[di] + " " + cells[di]).strip()
                continue
            item = _row_to_item(cells, header_map, tax_rate, pno)
            if item is not None:
                items.append(item)
                pending = cells
            else:
                pending = None
        if items:
            notes.append(f"Detalle deducido por posición de columnas en página {pno}")
    return items, notes


def _assign_codes(item: LineItem) -> None:
    """Asigna codigos UTBMS segun el tipo y la descripcion."""
    if item.line_type in ("E", "IE"):
        code, conf = utbms.classify_expense(item.description)
        item.expense_code = code
        item.task_code = ""
        item.activity_code = ""
        item.confidence = min(item.confidence, 0.4 + conf / 2)
        if conf < 0.3:
            item.notes = (item.notes + "; código de gasto por defecto E124; revisar").strip("; ")
    else:
        task, activity, conf = utbms.classify_fee(item.description)
        item.task_code = task
        item.activity_code = activity
        item.expense_code = ""
        item.confidence = min(item.confidence, 0.4 + conf / 2)
        if conf < 0.3:
            item.notes = (item.notes + "; código UTBMS por defecto L120/A111; revisar").strip("; ")


_NAME_RE = re.compile(
    r"\b([A-ZÀ-Ý][\wÀ-ÿ'\-]+(?:\s+(?:de|del|la|las|los|van|von|di|da)\s+)?"
    r"(?:\s+[A-ZÀ-Ý][\wÀ-ÿ'\-]+){1,3})\b"
)


def _assign_timekeeper(item: LineItem, who: str, role: str) -> None:
    """Reparte el nombre en apellidos/nombre e infiere la clasificacion."""
    if item.line_type in ("E", "IE"):
        return
    who = (who or "").strip(" .,;:-")
    if who:
        parts = [p for p in re.split(r"[\s,]+", who) if p]
        if "," in who:
            last, _, first = who.partition(",")
            item.timekeeper_last_name = last.strip()
            item.timekeeper_first_name = first.strip()
        elif len(parts) >= 2:
            # convencion espanola: Nombre Apellido1 Apellido2
            item.timekeeper_first_name = parts[0]
            item.timekeeper_last_name = " ".join(parts[1:])
        else:
            item.timekeeper_last_name = parts[0]
        item.timekeeper_id = _slug_id(who)
    cls = utbms.classify_role(role) or utbms.classify_role(who)
    if cls:
        item.timekeeper_classification = cls


def _slug_id(text: str) -> str:
    s = re.sub(r"[^A-Za-z0-9]+", "", strip_accents(text)).upper()
    return s[:20] or ""


def _extract_timekeeper_directory(text: str) -> dict[str, str]:
    """Busca un cuadro de profesionales/tarifas: nombre -> cargo."""
    directory: dict[str, str] = {}
    for raw in text.splitlines():
        line = strip_accents(raw).strip()
        if not line or len(line) > 160:
            continue
        role = utbms.classify_role(line)
        if not role:
            continue
        m = _NAME_RE.search(line)
        if m:
            directory[norm(m.group(1))] = role
    return directory


#: tipos de IVA vigentes en España, para redondear un tipo deducido
_KNOWN_RATES = [Decimal("0"), Decimal("0.04"), Decimal("0.05"), Decimal("0.075"),
                Decimal("0.10"), Decimal("0.21")]


def _reconcile_tax_rate(rate: Decimal, confidence: float,
                        inv: Invoice) -> tuple[Decimal, str]:
    """Ajusta el tipo impositivo contra base e IVA leidos del documento.

    Los totales impresos son el dato mas fiable de una factura. Si la base y la
    cuota estan, el tipo se deduce de ellas; si base y total coinciden, no hay
    impuesto, por mucho que el texto mencione porcentajes.
    """
    net, tax, gross = inv.pdf_net_total, inv.pdf_tax_total, inv.pdf_gross_total

    # base y total iguales -> operacion sin impuesto
    if net is not None and gross is not None and abs(net - gross) <= Decimal("0.02"):
        if rate != 0:
            return Decimal("0"), (
                f"El texto sugería un tipo del {rate * 100:.0f}%, pero la base y el "
                f"total del documento coinciden ({net}): se factura sin impuesto.")
        return Decimal("0"), ""

    # base y cuota disponibles -> el tipo se calcula
    if net and tax is not None and net != 0:
        derived = (dec(tax) / dec(net)).quantize(Decimal("0.000001"))
        near = min(_KNOWN_RATES, key=lambda k: abs(k - derived))
        chosen = near if abs(near - derived) <= Decimal("0.004") else derived
        if abs(chosen - rate) > Decimal("0.004"):
            return chosen, (
                f"Tipo impositivo deducido de los totales del documento: "
                f"{chosen * 100:.2f}% (cuota {tax} sobre base {net}).")
        return rate, ""

    # base y total disponibles, sin cuota -> el tipo sale de la diferencia
    if net and gross is not None and net != 0:
        derived = ((dec(gross) - dec(net)) / dec(net)).quantize(Decimal("0.000001"))
        if derived >= 0:
            near = min(_KNOWN_RATES, key=lambda k: abs(k - derived))
            chosen = near if abs(near - derived) <= Decimal("0.004") else derived
            if abs(chosen - rate) > Decimal("0.004"):
                return chosen, (
                    f"Tipo impositivo deducido de base y total del documento: "
                    f"{chosen * 100:.2f}%.")
    if confidence <= 0.0 and rate == 0:
        return rate, ("No se ha encontrado ningún tipo impositivo en el documento: "
                      "se factura sin impuesto. Verifíquelo.")
    return rate, ""


def _guess_client_name(lines: list[str]) -> tuple[str, float]:
    """Nombre del cliente sin etiqueta: linea con forma societaria (S.L., S.A.).

    En las facturas españolas el bloque del destinatario suele ir sin etiqueta:
    nombre, direccion y N.I.F. en lineas seguidas.
    """
    for raw in lines[:40]:
        candidate = strip_accents(raw).strip(" .:,-")
        if not (4 < len(candidate) <= 70):
            continue
        low = norm(candidate)
        if re.search(r"factura|iban|swift|banco|vencimiento|confidencial|total|iva|base",
                     low):
            continue
        if _COMPANY_SUFFIX.search(candidate):
            return candidate[:60], 0.7
    return "", 0.0


#: "1407.-Impugnacion acuerdo junta general ... EXP. 2026000455.-P.O.: 4500098712"
#: El punto antes del guion es obligatorio: sin el, una fila que empiece por
#: una fecha ISO ("2026-01-08 Klein, Sarah ...") se tomaria por codigo de asunto.
_CONCEPT_LINE = re.compile(r"^\s*(\d{3,8})\s*\.\s*-\s*(?!\d{1,2}-)(.+)$")


def _parse_concept_line(inv: Invoice, lines: list[str]) -> None:
    """Linea de concepto que agrupa codigo de asunto, nombre, expediente y PO.

    Muchos despachos la escriben en una sola linea con el codigo interno
    delante. Rellena lo que aun este vacio; no sobreescribe nada.
    """
    for raw in lines:
        candidate = strip_accents(raw).strip()
        m = _CONCEPT_LINE.match(candidate)
        if not m:
            continue
        # ".-" es el separador que usa este formato de linea
        chunks = [c.strip(" .:,-–") for c in re.split(r"\.\s*-", m.group(2))]
        chunks = [c for c in chunks if c]
        if not chunks:
            continue
        name, exp_value, po_value = "", "", ""
        for chunk in chunks:
            em = re.match(r"exp(?:ediente)?\.?\s*(?:n[uo]?\.?)?\s*:?\s*([A-Za-z0-9/_\-]+)",
                          chunk, re.I)
            pm = re.match(r"p\.?\s*o\.?\s*(?:n[uo]?\.?)?\s*:?\s*([A-Za-z0-9/_\-]+)",
                          chunk, re.I)
            if em:
                exp_value = exp_value or em.group(1)
            elif pm:
                po_value = po_value or pm.group(1)
            elif not name:
                name = chunk
        # el expediente puede ir pegado al final del nombre: "... junta EXP. 2026000455"
        tail = re.search(r"\bexp(?:ediente)?\.?\s*(?:n[uo]?\.?)?\s*:?\s*([A-Za-z0-9/_\-]+)\s*$",
                         name, re.I)
        if tail:
            exp_value = exp_value or tail.group(1)
            name = name[:tail.start()].strip(" .:,-–")
        if not name or len(name) < 4:
            continue
        if not inv.law_firm_matter_id:
            inv.law_firm_matter_id = m.group(1)[:20]
        if not inv.matter_name:
            inv.matter_name = name[:255]
        if exp_value and not inv.client_matter_id:
            inv.client_matter_id = exp_value[:20]
        if po_value and not inv.po_number:
            inv.po_number = po_value[:100]
        return


def _fallback_single_line(inv: Invoice, text: str, tax_rate: Decimal,
                          gross: Decimal | None, net: Decimal | None) -> LineItem:
    """Ultimo recurso: una sola linea con el importe total de la factura."""
    base = net if net is not None else (
        (gross / (Decimal(1) + tax_rate)).quantize(Q2) if gross is not None else Decimal("0")
    )
    # se busca la frase narrativa del concepto, no una linea de cabecera
    # etiquetada ("Asunto: ...") que describiria el asunto, no el trabajo.
    best, best_score = "", 0
    for raw in text.splitlines():
        candidate = strip_accents(raw).strip()
        low = norm(candidate)
        if not low or len(candidate) < 18:
            continue
        if _NEXT_LABEL_RE.match(candidate) or re.match(r"^[a-z\s.]{0,24}:", low):
            continue                      # es un campo etiquetado, no el concepto
        score = 0
        if re.search(r"por\s*los\s*servicios|se\s*facturan|en\s*concepto\s*de", low):
            score = 5
        elif re.search(r"honorarios|servicios\s*profesionales|professional\s*fees|"
                       r"provision\s*de\s*fondos|retainer|anticipo\s*a\s*cuenta", low):
            score = 4
        elif re.search(r"asesoramiento|asistencia\s*(juridica|legal)|advisory", low):
            score = 3
        if score > best_score:
            best, best_score = candidate, score
    desc_source = best
    # la linea de concepto suele traer el importe pegado; fuera, no es descripcion
    desc_source = re.sub(
        r"[\s ]+-?\d{1,3}(?:[., ]\d{3})*(?:[.,]\d{1,2})?\s*"
        r"(?:€|eur|\$|usd|£|gbp)?\s*$", "", desc_source, flags=re.I).strip()
    desc = desc_source or (inv.matter_name and f"Servicios profesionales - {inv.matter_name}") \
        or "Servicios profesionales prestados"
    # Sin desglose horario, declarar UNITS=1 y UNIT_COST=importe seria afirmar
    # "1 hora a ese precio": la spec define UNITS como el numero de horas en las
    # lineas de honorarios. El estandar prevee este caso con la clasificacion
    # FLTFEE (Flat/Fixed Fee), que marca la linea como honorario fijo y no
    # requiere un profesional concreto.
    item = LineItem(
        line_type="F",
        line_date=inv.invoice_date,
        description=desc[:900],
        units=Decimal("1"),
        unit_cost=base,
        tax_rate=tax_rate,
        timekeeper_classification="FLTFEE",
        confidence=0.25,
        notes="importe agregado sin desglose horario; se declara como honorario "
              "fijo (FLTFEE)",
    )
    _assign_codes(item)
    return item


def extract(pdf_path: str, defaults: dict | None = None) -> ExtractionResult:
    """Convierte un PDF de factura en un objeto Invoice.

    `defaults` aporta los valores fijos del despacho (CIF, direccion, ID de
    timekeeper por defecto, etc.) que casi nunca vienen fiables en el PDF.
    """
    defaults = defaults or {}
    notes: list[str] = []
    inv = Invoice(source_pdf=pdf_path)

    with pdfplumber.open(pdf_path) as pdf:
        pages_text = [_page_text(p) for p in pdf.pages]
        full_text = "\n".join(pages_text)
        lines = [l for l in full_text.splitlines()]

        if not full_text.strip():
            notes.append("El PDF no contiene texto extraíble: probablemente es un "
                         "escaneo. Hace falta OCR o introducir los datos a mano.")

        # --- cabecera ---
        inv.invoice_number, c_num = _label_value(lines, _LABEL_INVOICE_NUMBER, want="code")
        inv.invoice_date, c_date = _label_value(lines, _LABEL_INVOICE_DATE, want="date")
        currency, c_cur = _detect_currency(full_text)
        inv.currency = currency
        tax_rate, tax_type, c_tax = _detect_tax_rate(full_text)

        matter, c_matter = _label_value(lines, _LABEL_MATTER)
        inv.matter_name = matter[:255]
        client_ref, _ = _label_value(lines, _LABEL_CLIENT_REF, want="code")
        inv.client_matter_id = client_ref[:20]
        po, _ = _label_value(lines, _LABEL_PO, want="code")
        inv.po_number = po[:100]
        client_code, _ = _label_value(lines, _LABEL_CLIENT_ID, want="code")
        inv.client_id = client_code[:20]
        client_name, c_client = _label_value(lines, _LABEL_CLIENT_NAME)
        if client_name and not re.fullmatch(r"[\d\s.\-/]+", client_name):
            inv.client_name = client_name[:60]
        else:
            c_client = 0.0
        if not inv.client_name:
            inv.client_name, c_client = _guess_client_name(lines)

        # CIF/NIF: el del despacho viene de los ajustes (el emisor suele tenerlo
        # en el logotipo, que no es texto). Los que aparecen en el PDF son del
        # cliente, salvo que coincidan con el del despacho.
        own = str(defaults.get("law_firm_id", "") or "").replace(" ", "").upper()
        taxids: list[str] = []
        for m in _TAXID_VALUE.finditer(strip_accents(full_text)):
            v = m.group(1).replace(" ", "").upper()
            if v not in taxids:
                taxids.append(v)
        foreign = [v for v in taxids if v != own and v.lstrip("ES") != own.lstrip("ES")]
        if foreign:
            inv.client_tax_id = foreign[0]
        elif taxids and not own:
            # sin CIF de despacho configurado no se puede distinguir: se asume
            # que el unico del documento es el del cliente y se avisa
            inv.client_tax_id = taxids[0]
            notes.append(f"Se ha encontrado un solo CIF/NIF ({taxids[0]}) y se asigna al "
                         f"cliente. Configura el CIF del despacho en Ajustes para que "
                         f"la app pueda distinguirlos.")

        # --- linea de concepto tipo "1407.-Asunto ... EXP. 123.-P.O.: 456" ---
        _parse_concept_line(inv, lines)

        # --- periodo facturado ---
        period_raw, _ = _label_value(lines, _LABEL_PERIOD)
        period_dates = all_dates(period_raw) if period_raw else []
        if len(period_dates) >= 2:
            inv.billing_start_date, inv.billing_end_date = period_dates[0], period_dates[-1]

        # --- totales del PDF ---
        net_raw, _ = _label_value(lines, _LABEL_NET, want="money")
        tax_raw, _ = _label_value(lines, _LABEL_TAX, want="money")
        gross_raw, _ = _label_value(lines, _LABEL_GROSS, want="money")
        inv.pdf_net_total = parse_number(net_raw) if net_raw else None
        inv.pdf_tax_total = parse_number(tax_raw) if tax_raw else None
        inv.pdf_gross_total = parse_number(gross_raw) if gross_raw else None

        if re.search(r"retencion|\birpf\b|withholding", strip_accents(full_text), re.I):
            inv.has_retention = True
            notes.append("La factura lleva retención (IRPF). LEDES 98BI no tiene campo de "
                         "retención: no se incluye en el fichero. INVOICE_TOTAL será la base "
                         "más el IVA, sin descontarla; la retención solo afecta al cobro.")

        # --- el tipo impositivo se reconcilia con los totales del documento ---
        tax_rate, tax_note = _reconcile_tax_rate(tax_rate, c_tax, inv)
        if tax_note:
            notes.append(tax_note)

        # --- detalle ---
        items, tnotes = _extract_lines_from_tables(pdf, tax_rate, currency)
        notes.extend(tnotes)
        if not items:
            items, wnotes = _extract_lines_from_words(pdf, tax_rate)
            notes.extend(wnotes)
        if not items:
            notes.append("El documento no contiene desglose de partidas. Se genera una "
                         "única partida por el importe total, declarada como honorario "
                         "fijo (clasificación FLTFEE del estándar). Si la plataforma del "
                         "cliente exige desglose horario, deberá detallarse manualmente.")
            items = [_fallback_single_line(inv, full_text, tax_rate,
                                           inv.pdf_gross_total, inv.pdf_net_total)]

        # --- completar timekeepers con el cuadro de profesionales ---
        directory = _extract_timekeeper_directory(full_text)
        for item in items:
            item.tax_type = tax_type
            if item.line_type == "F" and not item.timekeeper_classification:
                key = norm(f"{item.timekeeper_first_name} {item.timekeeper_last_name}")
                for name, role in directory.items():
                    if key and (key in name or name in key):
                        item.timekeeper_classification = role
                        break

        inv.lines = items

    # --- fechas de respaldo ---
    doc_dates = all_dates(full_text)
    if not inv.invoice_date and doc_dates:
        # sin etiqueta, la fecha de factura es la que aparece antes en el
        # documento: va en la cabecera, no en las condiciones de pago
        first_in_text = _first_date_in_order(full_text) or doc_dates[0]
        inv.invoice_date = first_in_text
        pretty = f"{first_in_text[6:8]}/{first_in_text[4:6]}/{first_in_text[0:4]}"
        notes.append(f"La fecha de factura no viene etiquetada: se usa la primera del "
                     f"documento ({pretty}). Compruébala.")
    line_dates = sorted(d for d in (l.line_date for l in inv.lines) if d)
    if not inv.billing_start_date:
        inv.billing_start_date = line_dates[0] if line_dates else inv.invoice_date
    if not inv.billing_end_date:
        inv.billing_end_date = line_dates[-1] if line_dates else inv.invoice_date
    for item in inv.lines:
        if not item.line_date:
            item.line_date = inv.invoice_date or inv.billing_end_date

    if not inv.invoice_number:
        stem = os.path.splitext(os.path.basename(pdf_path))[0]
        m = re.search(r"[A-Za-z0-9][A-Za-z0-9/_.\-]{2,}", stem)
        inv.invoice_number = (m.group(0) if m else stem)[:50]
        notes.append(f"Número de factura no encontrado: se usa el nombre del fichero "
                     f"('{inv.invoice_number}'). Verificar.")

    # --- aplicar valores fijos del despacho ---
    apply_defaults(inv, defaults)

    # --- confianza global ---
    field_conf = [c_num, c_date, c_cur, c_tax, c_matter, c_client]
    line_conf = [l.confidence for l in inv.lines] or [0.0]
    confidence = (sum(field_conf) / len(field_conf) * 0.4
                  + sum(line_conf) / len(line_conf) * 0.6)
    inv.extraction_notes = notes
    return ExtractionResult(inv, round(confidence, 2), notes)


def apply_defaults(inv: Invoice, defaults: dict) -> None:
    """Rellena con los valores fijos del despacho lo que el PDF no aporta.

    Los campos marcados como `force_*` en la configuracion sobreescriben
    siempre lo extraido (util cuando el PDF trae el dato mal).
    """
    if not defaults:
        return

    mapping = {
        "law_firm_id": "law_firm_id",
        "law_firm_name": "law_firm_name",
        "law_firm_address_1": "law_firm_address_1",
        "law_firm_address_2": "law_firm_address_2",
        "law_firm_city": "law_firm_city",
        "law_firm_region": "law_firm_region",
        "law_firm_postcode": "law_firm_postcode",
        "law_firm_country": "law_firm_country",
        "client_id": "client_id",
        "client_tax_id": "client_tax_id",
        "client_name": "client_name",
        "client_address_1": "client_address_1",
        "client_address_2": "client_address_2",
        "client_city": "client_city",
        "client_region": "client_region",
        "client_postcode": "client_postcode",
        "client_country": "client_country",
        "law_firm_matter_id": "law_firm_matter_id",
        "client_matter_id": "client_matter_id",
        "matter_name": "matter_name",
        "po_number": "po_number",
        "account_type": "account_type",
        "invoice_description": "invoice_description",
        "currency": "currency",
    }
    force = set(defaults.get("force_fields") or [])
    for cfg_key, attr in mapping.items():
        value = str(defaults.get(cfg_key, "") or "").strip()
        if not value:
            continue
        current = str(getattr(inv, attr, "") or "").strip()
        if not current or cfg_key in force:
            setattr(inv, attr, value)

    # timekeeper por defecto para lineas de honorarios incompletas
    tk_id = str(defaults.get("default_timekeeper_id", "") or "").strip()
    tk_last = str(defaults.get("default_timekeeper_last_name", "") or "").strip()
    tk_first = str(defaults.get("default_timekeeper_first_name", "") or "").strip()
    tk_cls = str(defaults.get("default_timekeeper_classification", "") or "").strip()
    for item in inv.lines:
        if item.line_type != "F":
            continue
        if str(item.timekeeper_classification or "").upper() in ("FLTFEE", "ADJSMT"):
            continue          # honorario fijo: no lleva profesional
        if not item.timekeeper_id and tk_id:
            item.timekeeper_id = tk_id
        if not item.timekeeper_last_name and tk_last:
            item.timekeeper_last_name = tk_last
        if not item.timekeeper_first_name and tk_first:
            item.timekeeper_first_name = tk_first
        if not item.timekeeper_classification and tk_cls:
            item.timekeeper_classification = tk_cls
        if not item.timekeeper_id and item.timekeeper_last_name:
            item.timekeeper_id = _slug_id(item.timekeeper_last_name + item.timekeeper_first_name)
