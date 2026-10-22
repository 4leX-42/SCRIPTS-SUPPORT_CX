<!--
[ES] PrintDeploy: instala y repara impresoras Ricoh y Canon, detecta el modelo solo y deja la bandeja bypass.
[EN] PrintDeploy: installs and repairs Ricoh and Canon printers, auto-detects the model and enables the bypass tray.
Contexto: admin
-->
# PrintDeploy

Aplicación Windows (WinForms, .NET Framework 4.8) para desplegar y reparar drivers de impresora. Un único `.exe` que pide elevación al abrir.

## Qué hace

**Ricoh** (IM C4510A, IM C4500 y cualquier otra con el driver universal)

- Detecta el modelo de la impresora sin preguntar: SNMP (`sysDescr`, `hrDeviceDescr`), IPP (`printer-make-and-model`, puerto 631) y la web de la impresora.
- Elige el driver: el específico del modelo si lo lleva embebido; si no, el **RICOH PCL6 UniversalDriver**.
- No instala nada si en la IP no responde nada o hay otra marca.
- Colas ya instaladas: guarda nombre, puerto, predeterminada, compartida, ubicación y comentario; las borra, limpia los drivers antiguos que ya no use ninguna otra cola (nunca los de Windows) y las recrea con el driver correcto.
- Activa SNMP en el puerto TCP/IP para que el driver lea las bandejas (bandeja bypass).

**Canon**: lanza el asistente oficial Canon Generic Plus PCL6 sin modificarlo.

**Escáner** (tarjeta 01 o botón `ESCÁNER` en la cabecera): el camino más rápido para instalar.

- Comprueba el directorio de oficinas y escanea un rango (por defecto el /24 del equipo; acepta `192.168.4.1-254`, `192.168.4.0/24` o `IP-IP`, máx. 1024). Una red /24: ~2 s.
- Por IP: ping (ICMP) + puertos TCP 9100 (RAW), 631 (IPP) y 515 (LPD; solo cuenta si además se identifica como impresora, porque los servidores Windows también lo abren). Sin ping ni puertos no pregunta nada más.
- Identificación en cascada: una consulta SNMP (v2c, con v1 de reserva) trae modelo (`hrDeviceDescr` / `sysDescr`), nombre (`sysName`) y ubicación (`sysLocation`); IPP y web solo si SNMP no basta. El modelo se limpia de firmware y sufijos.
- Colas compartidas `\\servidor\cola`: puerto 445 (SMB) del servidor y apertura real de la cola (winspool): driver, estado, ubicación y comentario. Distingue servidor caído, SMB cerrado, cola inexistente y falta de permisos.
- Nombre legible: `PROCESAL_DCH` + `C/ Mayor 1 Plt3 Derecha` → *Procesal Dcha · P3*. Ignora los nombres de fábrica (el modelo o derivados de la MAC). Al instalar una impresora que no está en el directorio, la cola se llama `Marca - nombre` (p. ej. *Canon - Procesal Dcha · P3*).
- **Verde** = online (impresora detectada) · **rojo** = offline / no es impresora / cola inaccesible.
- **Instalar** (doble clic o Enter) con el modelo ya detectado, sin volver a comprobarlo. Ricoh: driver del modelo o universal; si ya hay una cola en esa IP se reinstala, si no se crea. Canon: asistente oficial con la IP en el portapapeles. Cola compartida: `Add-Printer -ConnectionName` para el usuario actual y `printui /ga` para todos los usuarios.
- Al cerrarlo se oculta: los resultados se conservan mientras la app siga abierta.

**Dispositivos e impresoras**: icono de impresora junto a minimizar / cerrar (ventana principal y escáner) → `shell:::{A8A91A66-3A7D-4424-8D24-04E180695C7A}`.

Registro de cada ejecución en `%ProgramData%\PrintDeploy\Logs\`.

## Compilar

Requiere el SDK de .NET (cualquiera reciente; descarga las *reference assemblies* de net48 desde nuget.org).

```powershell
dotnet build -c Release .\05-office-apps\03-printdeploy\PrintDeploy.csproj
# -> 05-office-apps\03-printdeploy\bin\Release\net48\PrintDeploy.exe
```

Lo que **no** está en el repo y se añade antes de compilar:

| Qué | Dónde | Por qué |
|---|---|---|
| Paquetes de driver Canon/Ricoh | `Payload\*.zip` — ver [`Payload/README.md`](Payload/README.md) | Software de fabricante, no se redistribuye |
| Directorio de oficinas | `oficinas.txt` — formato en [`oficinas.example.txt`](oficinas.example.txt) | IPs internas |

Sin ellos compila igualmente: el `.exe` avisa del paquete que falta y el directorio puede ir como `oficinas.txt` junto al `.exe` o en `%ProgramData%\PrintDeploy\`.

## Ficheros

| Fichero | Para qué |
|---|---|
| `MainForm.cs` | Interfaz y flujo: elegir fabricante, colas, IP nueva, progreso |
| `PrinterProbe.cs` | Detección del dispositivo y modelo (SNMP, IPP, HTTP) |
| `RicohModels.cs` | Modelos soportados, su driver y su paquete; driver universal de reserva |
| `PrinterDirectory.cs` | Lectura del directorio de oficinas (`oficinas.txt`) |
| `NetworkScan.cs` | Escáner: ping, puertos, identificación, colas compartidas y rangos |
| `ScannerForm.cs` | Ventana del escáner (lista verde / rojo, detalle, instalar) |
| `Theme.cs` | Estilo (negro, blanco y rojo) y controles dibujados |
| `engine.ps1` | Motor que desinstala, limpia drivers e instala; lo lanza el `.exe` |

## Añadir un modelo Ricoh

1. Zip con la carpeta `disk1\` del PCL 6 Driver en `Payload\`.
2. Entrada en `RicohModels.All` con su `DriverName` exacto (el del INF), el zip, el INF y la expresión que lo reconoce.
3. `EmbeddedResource` del zip en `PrintDeploy.csproj`.

---

**EN** — WinForms (.NET Framework 4.8) tool that deploys and repairs Ricoh/Canon printer drivers. It auto-detects the Ricoh model (SNMP, IPP, web), installs the matching driver or falls back to the Ricoh universal driver, cleans up wrong drivers and rebuilds existing queues keeping name and IP. Vendor driver packages and the office directory are not in the repo: see `Payload/README.md` and `oficinas.example.txt`. Build with `dotnet build -c Release`.
