# Conversor LEDES 98BI

Aplicación local para Windows. Convierte facturas en PDF al formato **LEDES 98BI**
(`LEDES98BI V5`: ASCII, 52 campos separados por `|`, cada línea terminada en `[]`),
el que admiten las plataformas de facturación legal.

No envía nada a internet.

## Uso

1. Doble clic en el acceso directo **Conversor LEDES 98BI**.
2. La primera vez, en **Configuración**: CIF del despacho y profesional por defecto.
   Queda guardado.
3. Arrastre los PDFs a la zona superior (o pulse para examinar). Se procesan solos.
4. Clic en un documento para revisarlo. **Doble clic en cualquier celda para rectificarla.**
5. **Generar fichero LEDES 98BI** → un `.txt` por documento.

## Qué rellena solo y qué no

Del PDF sale automáticamente: número de factura, fechas, periodo, CIF del cliente,
asunto, moneda, tipo de IVA, líneas de detalle con horas, tarifas e importes, y los
códigos UTBMS deducidos de la descripción.

Hay que teclear una vez, y luego se recuerdan para las siguientes facturas:
**código de cliente** y **código de asunto** (son códigos internos del despacho,
no aparecen en el PDF y la plataforma los exige).

## Qué revisar antes de subir

- Que base, IVA y total cuadren con el PDF. La app lo comprueba y avisa si no.
- Los **códigos UTBMS** (columnas CÓDIGO / ACT). Se asignan por palabras clave;
  un código erróneo es la causa más frecuente de rechazo.

Las partidas de extracción dudosa se marcan con fondo ámbar o rojizo y un punto.

## Retenciones (IRPF)

98BI no tiene campo para la retención. Si la factura la lleva, `INVOICE_TOTAL` es
base + IVA sin descontarla y el "total a pagar" del PDF será menor. Es correcto.
La app lo detecta y lo explica.

## PDFs escaneados

Si el PDF es una imagen sin capa de texto no se puede extraer nada. La app lo avisa;
hay que meter las líneas a mano o pasar un OCR antes.

## Por qué 98BI y no 98B ni XML 2.1

98B tiene 24 campos y **ningún campo de impuestos**: no sirve para facturar desde
España. XML 2.1 es más rico (permite aprobación línea a línea) pero más complejo y
con soporte desigual. 98BI tiene 52 campos, IVA, divisa y datos por profesional, y
está hecho para facturación fuera de EE. UU.

---

## Notas técnicas

```
run.pyw          lanzador (comprueba dependencias, sin consola)
app.py           interfaz
ui.py            tema y widgets planos
pdf_extract.py   extracción del PDF
ledes98bi.py     modelo, escritor y validador del formato
utbms.py         códigos UTBMS y clasificador ES/EN
Diagnostico.bat  arranque con consola visible, para ver errores
ejemplos/        dos facturas de prueba
```

Configuración en `%APPDATA%\Andersen-LEDES\config.json`.
Dependencias: Python 3.9+, `pip install pdfplumber pillow`.

Aritmética del formato, según la especificación:

```
LINE_ITEM_TAX_TOTAL = ((UNIT_COST * UNITS) + ADJUSTMENT) * TAX_RATE
LINE_ITEM_TOTAL     = (UNIT_COST * UNITS) + ADJUSTMENT + LINE_ITEM_TAX_TOTAL
INVOICE_TOTAL       = suma de LINE_ITEM_TOTAL      (bruto, IVA incluido)
INVOICE_NET_TOTAL   = INVOICE_TOTAL - INVOICE_TAX_TOTAL
```

`LINE_ITEM_TAX_RATE` va como decimal entre 0 y 1: el 21 % es `0.21`.

Decisiones que conviene conocer:

- **ASCII forzado** por defecto (`á`→`a`, `€`→`EUR`). El estándar define ASCII y
  varias plataformas rechazan el fichero si lleva acentos. Se puede desactivar.
- Los pipes y saltos de línea de las descripciones se sustituyen: romperían el fichero.
- Números en formato español e inglés (`1.234,56` y `1,234.56`) por la posición del
  último separador.
- Cuando pdfplumber devuelve una celda numérica contaminada (el texto de la columna
  vecina se desborda sobre ella), se descarta y las unidades se deducen de
  `importe / tarifa`, que sí cuadra al céntimo.
- **El tipo impositivo se reconcilia con los totales impresos.** Si base y total
  coinciden, no hay impuesto, aunque el texto mencione porcentajes; si constan
  base y cuota, el tipo se calcula de ellas. Nunca se presume un 21 % por defecto:
  suponer IVA donde no lo hay infla la factura.
- **Etiquetas con límite de palabra.** `num` casa dentro de `number` y `IVA`
  dentro de `LIVA`; una etiqueta solo se acepta si no va pegada a otra letra.
- **Documentos sin desglose horario** se declaran como honorario fijo con la
  clasificación `FLTFEE` del estándar. Poner `UNITS=1` y el importe como coste
  unitario afirmaría "una hora a ese precio", que es falso: la especificación
  define `LINE_ITEM_NUMBER_OF_UNITS` como el número de horas en las partidas de
  honorarios.
- La numeración de líneas es continua y única en todo el fichero, como exige la spec.

Fuentes de la especificación (descargadas de ledes.org):
`LEDES98BI-V5-Format-Rev-1-2020.xlsx`, `LEDES98BI-V5-Sample-File-1-2020.txt`
(en `assets/`) y el documento de timekeeper classifications rev. 6-2023.
La línea de cabecera generada es idéntica, campo por campo, al fichero de muestra
oficial.

---

## Distribución a otros equipos

El ejecutable se descarga de la
[última release](../../../../releases) del repositorio: `Conversor LEDES 98BI.exe`
(33 MB). **Lleva Python y las librerías dentro**, así que en el equipo de destino no
hace falta instalar nada: se copia el `.exe` donde sea y se hace doble clic.

El binario no se versiona en el repositorio; aquí está solo el código fuente y el
`build.spec` para reconstruirlo.

Requisitos reales del equipo de destino:

- Windows 10 o 11, 64 bits
- Nada más. **No** necesita Python, **no** necesita `pip`, **no** usa PowerShell
  (la aplicación es Python/tkinter; la versión de PowerShell del equipo es
  indiferente)

### Primer arranque en un equipo nuevo: SmartScreen

El ejecutable **no está firmado digitalmente**. La primera vez que se abra en otro
equipo, Windows mostrará *"Windows protegió tu PC"*. Hay que pulsar
**Más información → Ejecutar de todas formas**. Solo ocurre la primera vez.

Para evitarlo en un despliegue amplio hacen falta una de estas dos cosas:

- un **certificado de firma de código** (Authenticode) con el que firmar el `.exe`
- o distribuirlo por **Intune / GPO**, añadiéndolo a la lista de confianza

### Dónde escribe

- Ficheros generados: carpeta `salida\` **junto al `.exe`**. Si el `.exe` está en
  una ruta sin permiso de escritura (Program Files, unidad de red), pasa
  automáticamente a `Documentos\LEDES 98BI\`
- Configuración: `%APPDATA%\Andersen-LEDES\config.json`, por usuario

La configuración es por usuario, así que cada persona introduce una vez el CIF del
despacho y su profesional por defecto.

### Reconstruir el ejecutable

```
pip install pyinstaller
python -m PyInstaller build.spec --noconfirm
```

### Alternativa sin empaquetar

Si se prefiere distribuir el código fuente, el equipo necesita Python 3.9+ y
`pip install pdfplumber pillow`; se arranca con `run.pyw`. `Diagnostico.bat`
comprueba las dependencias y muestra los errores en consola.
