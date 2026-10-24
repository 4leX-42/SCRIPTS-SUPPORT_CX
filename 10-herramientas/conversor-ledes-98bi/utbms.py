"""
Tablas de codigos UTBMS y clasificador inteligente ES/EN.

Fuentes oficiales:
  - Task codes (Litigation L1xx-L5xx): UTBMS / ABA Litigation Code Set
  - Activity codes A101-A111: LOC Revised Activity Codes
  - Expense codes E101-E124: 2013 LOC Revised UTBMS Expense Codes
  - Timekeeper classifications: LEDES Revised Timekeeper Classifications
    Reference Document 6-2023 (ledes.org)

El clasificador mapea texto libre de factura (castellano o ingles) al codigo
UTBMS mas probable. Es una ayuda, NO una verdad absoluta: la interfaz permite
corregir cada linea antes de exportar.
"""

from __future__ import annotations

import re
import unicodedata

# ---------------------------------------------------------------------------
# Task codes - UTBMS Litigation code set
# ---------------------------------------------------------------------------
TASK_CODES: dict[str, str] = {
    "L100": "Case Assessment, Development and Administration",
    "L110": "Fact Investigation / Development",
    "L120": "Analysis / Strategy",
    "L130": "Experts / Consultants",
    "L140": "Document / File Management",
    "L150": "Budgeting",
    "L160": "Settlement / Non-Binding ADR",
    "L190": "Other Case Assessment, Development and Administration",
    "L200": "Pre-Trial Pleadings and Motions",
    "L210": "Pleadings",
    "L220": "Preliminary Injunctions / Provisional Remedies",
    "L230": "Court Mandated Conferences",
    "L240": "Dispositive Motions",
    "L250": "Other Written Motions and Submissions",
    "L260": "Class Action Certification and Notice",
    "L300": "Discovery",
    "L310": "Written Discovery",
    "L320": "Document Production",
    "L330": "Depositions",
    "L340": "Expert Discovery",
    "L350": "Discovery Motions",
    "L390": "Other Discovery",
    "L400": "Trial Preparation and Trial",
    "L410": "Fact Witnesses",
    "L420": "Expert Witnesses",
    "L430": "Written Motions and Submissions",
    "L440": "Other Trial Preparation and Support",
    "L450": "Trial and Hearing Attendance",
    "L460": "Post-Trial Motions and Submissions",
    "L470": "Enforcement",
    "L500": "Appeal",
    "L510": "Appellate Motions and Submissions",
    "L520": "Appellate Briefs",
    "L530": "Oral Argument",
}

# ---------------------------------------------------------------------------
# Activity codes - LOC Revised Activity Codes
# ---------------------------------------------------------------------------
ACTIVITY_CODES: dict[str, str] = {
    "A101": "Plan and prepare for",
    "A102": "Research",
    "A103": "Draft / revise",
    "A104": "Review / analyze",
    "A105": "Communicate (in firm)",
    "A106": "Communicate (with client)",
    "A107": "Communicate (other outside counsel)",
    "A108": "Communicate (other external)",
    "A109": "Appear for / attend",
    "A110": "Manage data / files",
    "A111": "Other",
}

# ---------------------------------------------------------------------------
# Expense codes - 2013 LOC Revised UTBMS Expense Codes
# ---------------------------------------------------------------------------
EXPENSE_CODES: dict[str, str] = {
    "E101": "Copying",
    "E102": "Outside printing",
    "E103": "Word processing",
    "E104": "Facsimile",
    "E105": "Telephone",
    "E106": "Online research",
    "E107": "Delivery services / messengers",
    "E108": "Postage",
    "E109": "Local travel",
    "E110": "Out-of-town travel",
    "E111": "Meals",
    "E112": "Court fees",
    "E113": "Subpoena fees",
    "E114": "Witness fees",
    "E115": "Deposition transcripts",
    "E116": "Trial transcripts",
    "E117": "Trial exhibits",
    "E118": "Litigation support vendors",
    "E119": "Experts",
    "E120": "Private investigators",
    "E121": "Arbitrators / mediators",
    "E122": "Local counsel",
    "E123": "Other professionals",
    "E124": "Other",
}

# ---------------------------------------------------------------------------
# Timekeeper classifications - LEDES Revised Timekeeper Classifications 6-2023
# Subconjunto habitual en despacho (lista completa en el fichero oficial).
# ---------------------------------------------------------------------------
TIMEKEEPER_CLASSIFICATIONS: dict[str, str] = {
    "PARTNR": "Partner",
    "OFCOUN": "Of Counsel",
    "ASSOC": "Associate",
    "TRANEE": "Associate Trainee",
    "STFATT": "Staff Attorney",
    "TEMPAT": "Contract Attorney",
    "SECNDE": "Secondee",
    "PARALG": "Paralegal",
    "LGLAST": "Legal Assistant",
    "LGLINT": "Legal Intern",
    "LGPRMG": "Legal Project Manager",
    "CLKSEC": "Clerk or Secretary",
    "ANALST": "Analyst",
    "CONSLT": "Consultant",
    "EXPERT": "Expert",
    "RSRCHR": "Research Specialist / Researcher",
    "LIBRRN": "Librarian",
    "TRANSL": "Translator",
    "HLNLPF": "High-Level Non-Lawyer Professional",
    "IPAGNT": "IP Agent",
    "CSTCNS": "Costs Counsel",
    "TEMPOS": "Contract Other Staff",
    "NBOTHR": "Other",
    "FLTFEE": "Flat / Fixed Fee",
    "ADJSMT": "Adjustment",
}

#: Clasificaciones que el estandar considera "fee support only": no son
#: personas, sirven para marcar lineas de honorario fijo o ajustes.
NON_PERSON_CLASSIFICATIONS = {"FLTFEE", "ADJSMT"}

# ---------------------------------------------------------------------------
# Mapeo cargo (texto libre ES/EN) -> codigo de clasificacion
# ---------------------------------------------------------------------------
_ROLE_PATTERNS: list[tuple[str, str]] = [
    (r"\bof\s*counsel\b", "OFCOUN"),
    (r"\bsocio|\bpartner\b|\bsocia\b", "PARTNR"),
    (r"\bcounsel\b", "OFCOUN"),
    (r"\bdirector\b|\bdirectora\b", "HLNLPF"),
    (r"\bsenior\s*associate\b|\basociado\s*senior\b", "ASSOC"),
    (r"\basociad|\bassociate\b|\babogad", "ASSOC"),
    (r"\bbecari|\btrainee\b|\bjunior\s*lawyer\b", "TRANEE"),
    (r"\bpasante\b|\bintern\b", "LGLINT"),
    (r"\bparalegal\b", "PARALG"),
    (r"\bgraduado\s*social\b", "HLNLPF"),
    (r"\beconomist|\beconomic", "ANALST"),
    (r"\bconsultor|\bconsultant\b", "CONSLT"),
    (r"\banalist|\banalyst\b", "ANALST"),
    (r"\bperit|\bexpert\b", "EXPERT"),
    (r"\btraduct|\btranslator\b", "TRANSL"),
    (r"\bsecretari|\bsecretary\b|\badministrativ", "CLKSEC"),
    (r"\bproject\s*manager\b|\bgestor\s*de\s*proyect", "LGPRMG"),
    (r"\bauxiliar\b|\bassistant\b|\basistente\b", "LGLAST"),
    (r"\bfiscalist|\btax\s*(adviser|advisor|manager)\b", "HLNLPF"),
]

# ---------------------------------------------------------------------------
# Mapeo descripcion -> (task_code, activity_code)
# Orden = prioridad. Primer patron que casa, gana.
# ---------------------------------------------------------------------------
_FEE_PATTERNS: list[tuple[str, str, str]] = [
    # --- Vistas, juicios, comparecencias ---
    (r"\b(juicio|vista\s*oral|vista\b|comparecenc|audienc|hearing|trial\b)", "L450", "A109"),
    (r"\b(senalamiento|citacion\s*judicial)", "L450", "A109"),
    # --- Recursos y apelacion ---
    (r"\b(recurso\s*de\s*apelacion|apelacion|appeal\b|apelatori)", "L510", "A103"),
    (r"\b(recurso\s*de\s*casacion|casacion|cassation)", "L510", "A103"),
    (r"\b(recurso\s*de\s*amparo|constitucional)", "L510", "A103"),
    (r"\b(recurso\s*de\s*reposicion|recurso\s*de\s*reforma)", "L250", "A103"),
    (r"\b(recurso\s*(de\s*)?(alzada|reclamacion\s*economico))", "L510", "A103"),
    # --- Escritos y demandas ---
    (r"\b(demanda|contestacion\s*a\s*la\s*demanda|contestacion|querella|denuncia)", "L210", "A103"),
    (r"\b(complaint\b|answer\s*to\s*complaint|pleading)", "L210", "A103"),
    (r"\b(medidas\s*cautelares|cautelar|injunction|embargo\s*preventivo)", "L220", "A103"),
    (r"\b(alegaciones|escrito\s*de\s*alegaciones|escrito\b|redaccion\s*de\s*escrito)", "L250", "A103"),
    (r"\b(conclusiones)", "L430", "A103"),
    # --- Ejecucion ---
    (r"\b(ejecucion\s*(de\s*)?(sentencia|titulo)|ejecutiv|enforcement|apremio)", "L470", "A103"),
    # --- Prueba / discovery ---
    (r"\b(prueba\s*documental|aportacion\s*de\s*documentos|document\s*production)", "L320", "A110"),
    (r"\b(prueba\s*pericial|informe\s*pericial|dictamen\s*pericial|expert\s*report)", "L340", "A104"),
    (r"\b(interrogatorio|declaracion\s*de\s*(testigo|parte)|deposition)", "L330", "A109"),
    (r"\b(testigo|witness)", "L410", "A101"),
    (r"\b(requerimiento\s*de\s*informacion|written\s*discovery)", "L310", "A103"),
    # --- Negociacion / acuerdo / ADR ---
    (r"\b(mediacion|arbitraje|conciliacion|acto\s*de\s*conciliacion|mediation|arbitration)", "L160", "A109"),
    (r"\b(acuerdo\s*transaccional|transaccion|settlement|allanamiento)", "L160", "A103"),
    (r"\b(negociacion|negotiat)", "L160", "A108"),
    # --- Analisis, estrategia, dictamen ---
    (r"\b(dictamen|opinion\s*legal|legal\s*opinion|nota\s*(juridica|legal)|memorandum|memo\b)", "L120", "A104"),
    (r"\b(estrategia|strategy|viabilidad|analisis\s*(juridic|legal)|due\s*diligence)", "L120", "A104"),
    (r"\b(revision\s*de|revisar|review\s*of|analisis\s*de|examen\s*de)", "L120", "A104"),
    # --- Investigacion ---
    (r"\b(investigacion\s*(de\s*)?(hechos|factual)|fact\s*(finding|investigation)|averiguacion)", "L110", "A110"),
    (r"\b(busqueda\s*de\s*jurisprudencia|jurisprudencia|doctrina|research\b|investigacion\s*juridica)", "L120", "A102"),
    # --- Comunicaciones ---
    (r"\b(reunion\s*con\s*(el\s*)?cliente|llamada\s*(con|al)\s*(el\s*)?cliente|conferencia\s*con\s*(el\s*)?cliente)", "L120", "A106"),
    (r"\b(correo|email|e-mail|mail\b|comunicacion)\s*(con|al|a\s*la)?\s*(el\s*)?client", "L120", "A106"),
    (r"\b(cliente\b|client\b)", "L120", "A106"),
    (r"\b(letrado\s*contrario|abogado\s*(de\s*la\s*)?contrari|opposing\s*counsel|contraparte)", "L120", "A107"),
    (r"\b(juzgado|tribunal|secretaria\s*judicial|court\b|registro\b|notaria|administracion)", "L120", "A108"),
    (r"\b(reunion\s*interna|reunion\s*de\s*equipo|internal\s*meeting)", "L120", "A105"),
    (r"\b(reunion|conferencia|llamada|telefonic|conference\s*call|videoconferencia)", "L120", "A108"),
    # --- Contratos / societario / asesoramiento general ---
    (r"\b(contrato|contract\b|clausul|acuerdo\s*marco|nda\b)", "L120", "A103"),
    (r"\b(junta\s*general|consejo\s*de\s*administracion|acta\b|estatutos|societari)", "L120", "A103"),
    (r"\b(constitucion\s*de\s*sociedad|escritura|elevacion\s*a\s*publico)", "L120", "A103"),
    # --- Gestion documental / expediente ---
    (r"\b(gestion\s*(del?\s*)?(expediente|documentacion|archivo)|file\s*management|organizacion\s*de\s*documentos)", "L140", "A110"),
    # --- Presupuesto / facturacion ---
    (r"\b(presupuesto|budget|estimacion\s*de\s*costes|fee\s*estimate)", "L150", "A101"),
    # --- Verbos en ingles: el activity code sale del verbo de la narrativa ---
    (r"\b(draft|drafting|redraft|revise|revising|prepare\s*(?:the\s*)?(?:draft|agreement|contract))", "L120", "A103"),
    (r"\b(review\s*and\s*(?:analy[sz]e|comment)|review|analy[sz]e|analy[sz]ing|"
     r"examine|assess|consider\s*the)", "L120", "A104"),
    (r"\b(legal\s*research|research\s*(?:on|into|regarding)|case\s*law|precedent)", "L120", "A102"),
    (r"\b(attend|attendance|hearing|appear\s*(?:at|for)|court\s*appearance)", "L450", "A109"),
    (r"\b(call\s*with\s*(?:the\s*)?client|meeting\s*with\s*(?:the\s*)?client|"
     r"correspond(?:ence)?\s*with\s*(?:the\s*)?client|update\s*(?:the\s*)?client)", "L120", "A106"),
    (r"\b(manage\s*(?:data\s*room|files?|documents?)|data\s*room|file\s*organi[sz]ation|"
     r"document\s*management|bundle\s*preparation)", "L140", "A110"),
    (r"\b(disclosure\s*schedul|due\s*diligence\s*report|closing\s*checklist)", "L120", "A103"),
    (r"\b(telephone\s*conference|conference\s*call|call\s*with|email\s*to|"
     r"correspond(?:ence)?\s*with)", "L120", "A108"),
    (r"\b(plan\s*and\s*prepare|preparation\s*(?:of|for)|prepare\s*for)", "L440", "A101"),
    # --- Preparacion generica ---
    (r"\b(preparacion|preparar|preparation|prepare\b)", "L440", "A101"),
    # --- Asesoramiento generico (muy comun en Andersen) ---
    (r"\b(asesoramiento|asistencia\s*(juridica|legal)|advice\b|advisory|consulta)", "L120", "A104"),
    (r"\b(seguimiento|follow[\s-]*up|monitorizacion)", "L120", "A104"),
    (r"\b(honorarios\s*profesionales|honorarios|professional\s*fees|servicios\s*profesionales)", "L120", "A111"),
    (r"\b(provision\s*de\s*fondos|retainer|anticipo)", "L120", "A111"),
]

_EXPENSE_PATTERNS: list[tuple[str, str]] = [
    (r"\b(tasa\s*judicial|tasas\s*judiciales|court\s*(?:filing\s*)?fee|filing\s*fee|"
     r"arancel|deposito\s*para\s*recurrir|stamp\s*duty)", "E112"),
    (r"\b(procurador|procuradora|derechos\s*de\s*procurador)", "E122"),
    (r"\b(abogado\s*local|local\s*counsel|corresponsal)", "E122"),
    (r"\b(notari|notary|arancel\s*notarial)", "E123"),
    (r"\b(registro\s*(mercantil|de\s*la\s*propiedad)|registral|land\s*registry)", "E123"),
    (r"\b(perit|expert\s*fee|honorarios\s*de\s*perito)", "E119"),
    (r"\b(arbitr|mediador|mediation\s*fee)", "E121"),
    (r"\b(detective|investigador\s*privado|private\s*investigator)", "E120"),
    (r"\b(traduccion|traductor|translation|interprete|jurad)", "E123"),
    (r"\b(transcripcion|transcript|estenotipia)", "E115"),
    (r"\b(fotocopias|copias|copying|reprografia|impresion\s*interna)", "E101"),
    (r"\b(imprenta|impresion\s*externa|outside\s*printing|encuadernacion)", "E102"),
    (r"\b(fax\b|facsimil)", "E104"),
    (r"\b(telefono|telefonia|telephone|movil|llamadas)", "E105"),
    (r"\b(base\s*de\s*datos|aranzadi|lexnex|la\s*ley|westlaw|vlex|online\s*research|consulta\s*bbdd)", "E106"),
    (r"\b(mensajeria|courier|correos\s*urgente|delivery|burofax)", "E107"),
    (r"\b(franqueo|sellos|postage|correo\s*postal)", "E108"),
    (r"\b(taxi|parking|aparcamiento|kilometraje|desplazamiento\s*local|local\s*travel|metro\b|autobus)", "E109"),
    (r"\b(viaje|billete|avion|tren|ave\b|hotel|alojamiento|dieta|travel\b|flight|vuelo)", "E110"),
    (r"\b(comida|almuerzo|cena|restaurante|catering|meal|manutencion)", "E111"),
    (r"\b(suplid|gasto|expense|desembolso|disbursement)", "E124"),
]


def _norm(text: str) -> str:
    """Minusculas sin acentos, espacios colapsados. Para casar patrones."""
    if not text:
        return ""
    t = unicodedata.normalize("NFKD", str(text))
    t = "".join(c for c in t if not unicodedata.combining(c))
    t = t.lower()
    t = re.sub(r"[\s ]+", " ", t)
    return t.strip()


def classify_fee(description: str) -> tuple[str, str, float]:
    """Devuelve (task_code, activity_code, confianza 0-1) para una linea de honorarios."""
    t = _norm(description)
    if not t:
        return "L120", "A111", 0.0
    for pattern, task, activity in _FEE_PATTERNS:
        if re.search(pattern, t):
            return task, activity, 0.75
    return "L120", "A111", 0.15


def classify_expense(description: str) -> tuple[str, float]:
    """Devuelve (expense_code, confianza 0-1) para una linea de suplido/gasto."""
    t = _norm(description)
    if not t:
        return "E124", 0.0
    for pattern, code in _EXPENSE_PATTERNS:
        if re.search(pattern, t):
            return code, 0.75
    return "E124", 0.15


def classify_role(role_text: str) -> str:
    """Cargo en texto libre -> codigo de clasificacion de timekeeper."""
    t = _norm(role_text)
    if not t:
        return ""
    for pattern, code in _ROLE_PATTERNS:
        if re.search(pattern, t):
            return code
    return ""


#: terminos que identifican un suplido o gasto repercutido, no honorarios
_EXPENSE_MARKERS = (
    # castellano
    r"\b(suplid|gasto|desembolso|tasa\s*judicial|tasas\s*judiciales|arancel|"
    r"procurador|notari|registro\s*mercantil|registro\s*de\s*la\s*propiedad|"
    r"mensajeria|burofax|taxi|hotel|billete|dieta|manutencion|fotocopias|"
    r"franqueo|traduccion|interprete|kilometraje|parking|aparcamiento|"
    r"deposito\s*para\s*recurrir|provision\s*de\s*fondos|honorarios\s*de\s*perito)"
    # ingles
    r"|\b(disbursement|expense|court\s*fee|filing\s*fee|search\s*fee|registry\s*fee|"
    r"stamp\s*duty|courier|postage|photocopy|photocopies|out-of-pocket|"
    r"travel\s*(?:cost|expense)|accommodation|subsistence|translation\s*fee|"
    r"expert\s*fee|counsel\s*fee|local\s*counsel|process\s*server|transcript\s*fee)"
)


def looks_like_expense(description: str) -> bool:
    """Heuristica: la linea parece un suplido/gasto en lugar de honorarios."""
    t = _norm(description)
    if not t:
        return False
    return bool(re.search(_EXPENSE_MARKERS, t))
