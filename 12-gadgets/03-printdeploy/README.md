<!--
[ES] PrintDeploy: escanea la red, ve qué impresoras responden e instala Ricoh, Canon y colas de servidor con el driver correcto.
[EN] PrintDeploy: scans the network, shows which printers respond and installs Ricoh, Canon and server queues with the right driver.
Contexto: admin
-->
# PrintDeploy

Aplicación Windows (WinForms, .NET Framework 4.8) para desplegar y reparar impresoras. Un único `.exe` portátil que pide elevación al abrir.

## Qué hace

**01 · Escáner** (tecla `1` o botón `ESCÁNER`)

- Directorio de oficinas (`oficinas.txt`) + rango de red (por defecto el /24 del equipo; acepta `192.168.4.1-254`, `192.168.4.0/24` o `IP-IP`, máx. 1024). Un /24 en ~2 s.
- Por IP: ICMP + TCP 9100 (RAW), 631 (IPP), 515 (LPD; solo cuenta si además se identifica como impresora). Host sin respuesta: no se consulta más.
- Identificación: una consulta SNMP v2c (v1 de reserva) con `hrDeviceDescr` / `sysDescr`, `sysName` y `sysLocation`; IPP y HTTP solo si SNMP no basta. Modelo sin firmware ni sufijos.
- Colas de servidor `\\servidor\cola`: TCP 445 (SMB) + `OpenPrinter` / `GetPrinter` nivel 2: driver, estado, ubicación, comentario y puerto (pool de puertos, puerto `nul` de retención PaperCut). Distingue servidor caído, SMB cerrado, cola inexistente (1801) y sin permiso (5 / 1326).
- Sin permiso: **Instalar** pasa a **Credenciales**. Sesión `IPC$` con usuario del servidor (valida al momento) + credencial en el Administrador de credenciales de Windows; recomprueba las colas de ese servidor.
- Nombre legible: `PROCESAL_DCH` + `C/ Mayor 1 Plt3 Derecha` → *Procesal Dcha · P3*. Nombres de fábrica (modelo, derivados de la MAC) ignorados.
- Ubicación: oficina con una impresora en el mismo /24 que el equipo; si no, la del sitio de Active Directory. Esa oficina arriba y abierta; el resto plegadas al final.
- Indicador: esfera negra con núcleo verde (online) o rojo (offline / sin impresión / cola inaccesible). Fila desplegable con IP, latencia, puertos, datos SNMP y acción de **Instalar**.
- **Instalar** (doble clic / Enter) con el modelo ya detectado. Ricoh: driver del modelo o universal, reinstala si ya hay cola en esa IP. Canon: como 03, sin asistente. Cola de servidor: `Add-Printer -ConnectionName` (usuario actual) + `printui /ga` (todos los usuarios).
- **Escanear** / `F5`: rango. **Recomprobar oficinas**: directorio. Botones con haz de escáner animado durante la comprobación.

**02 · Ricoh** (IM C4510A, IM C4500, resto con el universal)

- Modelo por SNMP, IPP (`printer-make-and-model`) y web. Driver específico embebido o **RICOH PCL6 UniversalDriver**.
- No instala si la IP no responde o es otra marca.
- Colas existentes: guarda nombre, puerto, predeterminada, compartida, ubicación y comentario; elimina, limpia drivers sin uso (nunca los de Windows) y recrea.
- SNMP activo en el puerto TCP/IP: el driver lee bandejas (bypass).
- Indicador verde / rojo por cola instalada (la IP de su puerto responde como impresora o no).

**03 · Canon** (Generic Plus PCL6, por IP)

- Sin asistente: usa el driver instalado (cualquier versión) o lo instala del paquete (`pnputil` + `Add-PrinterDriver`). Puerto TCP/IP estándar con SNMP y cola; si esa IP ya tiene cola, actualiza su driver.
- Evita el bloqueo del asistente oficial cuando hay una versión posterior del driver («Ya está instalada una versión posterior del controlador»).
- **Asistente Canon** sigue disponible; corre como proceso aparte y cerrarlo no cierra PrintDeploy.

**General**

- Portátil: un solo `PrintDeploy.exe` (drivers y directorio embebidos; .NET Framework 4.8 incluido en Windows 10/11). Funciona desde USB o carpeta de red.
- Teclas: `1` escáner · `2` Ricoh · `3` Canon · `F5` reescanear · `Esc` volver / salir.
- Al terminar una instalación, **Volver** regresa al inicio o al escáner; la app no se cierra.
- Icono de impresora en las cabeceras → *Dispositivos e impresoras* (`shell:::{A8A91A66-3A7D-4424-8D24-04E180695C7A}`).
- Registro de cada ejecución en `%ProgramData%\PrintDeploy\Logs\`.

## Compilar

Requiere el SDK de .NET (cualquiera reciente; descarga las *reference assemblies* de net48 desde nuget.org).

```powershell
dotnet build -c Release .\12-gadgets\03-printdeploy\PrintDeploy.csproj
# -> 12-gadgets\03-printdeploy\bin\Release\net48\PrintDeploy.exe
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
| `MainForm.cs` | Interfaz y flujo: inicio, Ricoh, Canon, progreso, instalación desde el escáner |
| `ScannerForm.cs` | Ventana del escáner (grupos por oficina, filas desplegables, credenciales) |
| `NetworkScan.cs` | Escáner: ping, puertos, identificación, colas de servidor, ubicación, rangos, credenciales |
| `PrinterProbe.cs` | Detección del dispositivo y modelo (SNMP, IPP, HTTP) |
| `RicohModels.cs` | Modelos Ricoh soportados, driver y paquete; universal de reserva |
| `PrinterDirectory.cs` | Lectura de `oficinas.txt` |
| `ThemedDialog.cs` | Avisos, confirmaciones y credenciales con el estilo de la app |
| `Theme.cs` | Estilo (carbón, blanco, dorado; rojo solo para errores) y controles dibujados |
| `engine.ps1` | Motor Ricoh: desinstala, limpia drivers e instala; lo lanza el `.exe` |

## Añadir un modelo Ricoh

1. Zip con la carpeta `disk1\` del PCL 6 Driver en `Payload\`.
2. Entrada en `RicohModels.All` con su `DriverName` exacto (el del INF), el zip, el INF y la expresión que lo reconoce.
3. `EmbeddedResource` del zip en `PrintDeploy.csproj`.

---

**EN** — Portable WinForms (.NET Framework 4.8) tool that scans the network for printers (ICMP, TCP 9100/631/515, SNMP, SMB for server queues), shows online/offline per office with the local office first, and installs Ricoh (model-specific or universal driver, rebuilding existing queues), Canon Generic Plus PCL6 (direct TCP/IP port and queue, no vendor wizard) and shared server queues (with optional server credentials). Vendor driver packages and the office directory are not in the repo: see `Payload/README.md` and `oficinas.example.txt`. Build with `dotnet build -c Release`.
