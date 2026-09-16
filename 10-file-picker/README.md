# 10 - File picker

La aplicación se congela al pulsar **Adjuntar archivo** y hay que matarla desde el
Administrador de tareas. Arrastrar y soltar el mismo fichero funciona sin problema.
Suele afectar a varias aplicaciones a la vez (Outlook, clientes de IA, navegadores).

| Script | Qué hace |
|---|---|
| `01-diagnose-file-picker.ps1` | Solo lectura. Inventario completo: MRU de ComDlg32, unidades de red probadas con watchdog, proveedores cloud, extensiones de shell de terceros con su firmante, eventos de cuelgue, filtros de sistema de ficheros y recientes hacia UNC. ~5 s. |
| `02-test-file-picker-hang.ps1` | Solo lectura. Reproduce el cuelgue en un proceso aislado y captura el **delta de módulos** que carga el selector: los DLL de terceros de esa lista son los sospechosos. |
| `03-reset-file-picker-mru.ps1` | Escritura (DryRun por defecto). Borra la memoria de carpetas del selector en HKCU, con copia `.reg` previa y `-Restore`. |
| `04-block-shell-extension.ps1` | Escritura (DryRun por defecto). Bloquea o desbloquea extensiones de shell por CLSID. Reversible, no desinstala nada. Requiere administrador. |

Todo se ejecuta en la sesión **del usuario afectado**: el MRU y los recientes viven en `HKCU`.
Una sesión elevada con otra cuenta lee otro registro y el diagnóstico sale limpio aunque el
equipo esté roto. Los CSV y las copias `.reg` se dejan en `%TEMP%\FilePickerDiag` salvo que se
indique `-OutDir`.

---

## Por qué falla

El cuadro de diálogo no pertenece a la aplicación: es el **Common Item Dialog** del sistema
(`IFileOpenDialog`). No es un proceso aparte — corre dentro del proceso que lo invoca (o en
`PickerHost.exe` si la aplicación está empaquetada como MSIX, caso del Outlook nuevo). De ahí:

1. El componente que cuelga está cargado **en el proceso de la aplicación**, así que la prueba
   decisiva es su lista de módulos, no el Visor de eventos.
2. Que falle en varias aplicaciones distintas descarta a las aplicaciones y señala a la capa
   común: Shell, proveedores de espacio de nombres, red o extensiones de terceros.
3. Que **arrastrar y soltar funcione** es el dato más informativo: arrastrar no enumera
   carpetas, no resuelve la ruta inicial y no carga los manejadores del diálogo.

### La causa más frecuente

`HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\LastVisitedPidlMRU` guarda,
**por ejecutable**, la última carpeta en la que ese programa abrió un diálogo. No la guarda
como texto: la guarda como **PIDL**, una referencia binaria al objeto del Shell.

Un PIDL hay que *resolverlo*, y resolverlo significa despertar al proveedor del espacio de
nombres que lo posee, cargar su DLL y pedirle que enumere. El diálogo hace eso **antes de
dibujarse** y **en el hilo de interfaz**, de forma síncrona y sin tiempo límite. Si el
proveedor no contesta —un recurso de red caído, un gestor documental sobre SharePoint sin
sesión, OneDrive desincronizado— no hay ventana, no hay barra de progreso y no hay cancelar:
la aplicación se queda congelada.

### Dos errores habituales al diagnosticarlo

- **Buscar un `Application Error` (1000) en el Visor de eventos.** Un *freeze* no genera ese
  evento; genera como mucho un `Application Hang` (**1002**), y muchas veces ni eso mientras el
  proceso sigue vivo. Filtrar por nivel "Error" devuelve ruido no relacionado.
- **Empezar por `sfc /scannow` y `DISM`.** Veinte minutos que casi nunca arreglan un cuelgue de
  enumeración. Van al final, y solo si el módulo señalado es un componente de Windows.

---

## Procedimiento

### 1 - Inventario

```powershell
.\01-diagnose-file-picker.ps1
```

Termina con un resumen ordenado de por dónde empezar. Si sale una ruta de red en `COLGADA`,
ya está la causa sin tocar nada más.

### 2 - Reproducir y capturar la prueba

```powershell
.\02-test-file-picker-hang.ps1
```

Lanza un proceso hijo propio, fotografía sus módulos **antes** de abrir el diálogo, lo abre, y
si supera el tiempo de espera vuelve a fotografiarlos. El **delta** son exactamente los DLL que
cargó el selector; los que no son de Microsoft forman la lista corta de sospechosos.

Sobre una aplicación ya colgada, sin reproducir nada (con la aplicación congelada delante):

```powershell
.\02-test-file-picker-hang.ps1 -Proceso PickerHost
.\02-test-file-picker-hang.ps1 -Proceso outlook
```

### 3 - Separar "la carpeta" de "el código"

```powershell
.\02-test-file-picker-hang.ps1 -CarpetaInicial C:\
```

| Resultado | Conclusión |
|---|---|
| Con `-CarpetaInicial C:\` abre bien, sin el parámetro cuelga | Es la carpeta recordada → paso 4 |
| Cuelga en los dos casos | Es código cargado en el proceso → paso 5 |
| Abre bien en los dos casos | Mirar qué comparten las aplicaciones afectadas (WebView2, complemento del gestor documental, perfil de usuario) |

### 4 - Limpiar la memoria de carpetas

```powershell
.\03-reset-file-picker-mru.ps1
.\03-reset-file-picker-mru.ps1 -Execute -IncluirRecientes -ReiniciarExplorer
```

Exporta una copia `.reg` antes de borrar. Para deshacer:
`.\03-reset-file-picker-mru.ps1 -Restore <ruta del .reg>`

Windows recrea las claves vacías y el selector vuelve a abrirse en Documentos. **Es alivio del
síntoma, no arreglo de la causa**: la entrada se regenera en cuanto el usuario vuelva a navegar
al mismo destino desde un diálogo. Si reaparece, el problema está en ese proveedor.

### 5 - Aislar la extensión culpable

```powershell
.\04-block-shell-extension.ps1 -Listar
.\04-block-shell-extension.ps1 -DesdeCsv <csv del paso 1> -FiltroDll 'imanage|adobe' -Execute -ReiniciarExplorer
```

Se bloquean todos los candidatos, se comprueba que el selector vuelve a abrir, y se desbloquean
**de uno en uno** (`-Clsid '{...}' -Quitar -Execute`) hasta que reaparece el fallo: el último
desbloqueado es el responsable. Las aplicaciones abiertas conservan el DLL en memoria, así que
hay que cerrarlas del todo entre prueba y prueba.

### 6 - Solo entonces, reparar Windows

```powershell
sfc /scannow
DISM /Online /Cleanup-Image /RestoreHealth
```

---

## Notas de implementación

- **`-LiteralPath` es obligatorio al recorrer `HKCR:\*\shellex\...`**: la clave se llama
  literalmente `*` y, sin ese parámetro, PowerShell lo trata como comodín y recorre los miles de
  nodos de `HKEY_CLASSES_ROOT`. Con el comodín el inventario tardaba más de cinco minutos; con
  `-LiteralPath`, cinco segundos.
- Las rutas de red se prueban dentro de un `Start-Job` con tiempo límite. Un `Test-Path` sobre
  una UNC muerta bloquea el hilo indefinidamente: el diagnóstico se colgaría igual que la
  aplicación que intenta diagnosticar.
- Los `.lnk` de recientes se parsean leyendo sus bytes, nunca resolviendo el acceso directo, por
  el mismo motivo.
- Un PIDL del registro no guarda la ruta en texto plano: lo legible son los nombres de carpeta.
  Por eso la columna `Pistas` del CSV suele ser más informativa que `RutaDetectada`.
- La detección de cuelgue combina dos señales: que la ventana de clase `#32770` llegue a
  aparecer, y que responda a un `SendMessageTimeout` con `SMTO_ABORTIFHUNG`. Un diálogo puede
  dibujarse y quedarse congelado enumerando; solo la segunda señal lo distingue.
