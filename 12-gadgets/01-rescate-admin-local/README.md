<!--
[ES] Equipo sin administrador: devuelve una cuenta local a Administradores desde la recuperacion (WinRE). No borra datos.
[EN] PC with no administrator: restores a local account to Administrators from Windows Recovery (WinRE). No data loss.
Contexto: admin
Instalar: $f="E:\rescate-admin-local.bat"; [Net.ServicePointManager]::SecurityProtocol=3072; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/12-gadgets/01-rescate-admin-local/rescate-admin-local.bat -OutFile $f
-->
# Rescate de administrador local — ficha técnica

Documento técnico del `rescate-admin-local.bat`: **qué hace exactamente, paso a paso,
y cómo consigue devolver privilegios de administrador** a una cuenta local cuando el
equipo se ha quedado sin ningún administrador utilizable (el único admin sacado del
grupo y la cuenta `Administrador` integrada deshabilitada).

- **Guía de uso operativa** (cómo lanzarlo): [`GUIA.md`](GUIA.md)
- **El script**: [`rescate-admin-local.bat`](rescate-admin-local.bat)

No reinstala Windows, no borra datos, no toca ficheros de usuario. Solo cambia
**pertenencia a grupos locales** y, de forma temporal, **dos valores del registro**.
Todo reversible.

---

## Idea en una línea

Windows, al arrancar, si encuentra `HKLM\SYSTEM\Setup\SetupType = 2` y un
`HKLM\SYSTEM\Setup\CmdLine`, ejecuta esa orden **como `NT AUTHORITY\SYSTEM`, antes
del inicio de sesión** (es el mecanismo del *audit mode* de los fabricantes). `SYSTEM`
tiene más privilegios que cualquier administrador, así que puede meter la cuenta en
el grupo **Administradores** aunque en ese momento no exista ningún admin con el que
iniciar sesión. El rescate solo tiene que **dejar puesta esa marca desde WinRE** (donde
sí hay acceso de escritura al disco y al registro) y luego **limpiarla** cuando ya ha
hecho el trabajo.

---

## Árbol de procesos

```
rescate-admin-local.bat
│
├─ ¿primer argumento == "fase2"?
│     sí ─────────────────────────────────► salta a [FASE 2]
│     no  (arranque normal desde el USB) ──► [FASE 1]
│
├─ [FASE 1]  — se ejecuta DENTRO de WinRE, desde el USB (consola de recuperación)
│   │   Entorno: WinPE, disco del sistema montado y escribible, sin login.
│   │
│   ├─ USB = %~d0                         (letra desde la que corre el .bat)
│   ├─ LOG = %~dp0Rescate_Admin.log       (traza en el propio USB)
│   │
│   ├─ [1/4] Localizar el Windows del equipo
│   │     for %%D in (C D E ... Z) do call :findwin %%D
│   │        │
│   │        └─ :findwin <letra>
│   │              salta si  <letra> == USB   (no es el sistema a reparar)
│   │              salta si  <letra> == X:    (es el RAMDisk de WinPE)
│   │              exige     <letra>\Windows\System32\ntoskrnl.exe     (kernel)
│   │              exige     <letra>\Windows\explorer.exe              (shell)
│   │              exige     <letra>\Windows\System32\config\SYSTEM    (hive)
│   │              si cumple ─► WIN = <letra>   (y no sigue buscando)
│   │     si WIN no queda definido ─► [ERROR: no se encontró Windows] ─► fin
│   │
│   ├─ [2/4] Copiar el componente de rescate al disco del sistema
│   │     copy "%~f0" "%WIN%\Windows\Temp\Rescate_Admin.bat"
│   │        (así la FASE 2 corre desde el disco, no desde el USB que ya no estará)
│   │     si no se puede copiar ─► [ERROR: solo lectura o cifrado] ─► fin
│   │
│   ├─ [3/4] Marcar el arranque para el rescate automático
│   │     reg load  HKLM\RESCATE  %WIN%\Windows\System32\config\SYSTEM
│   │        (monta el hive SYSTEM del equipo bajo una rama temporal)
│   │     reg add HKLM\RESCATE\Setup  /v CmdLine  /t REG_EXPAND_SZ
│   │        /d "cmd.exe /c %SystemDrive%\Windows\Temp\Rescate_Admin.bat fase2"
│   │     reg add HKLM\RESCATE\Setup  /v SetupType /t REG_DWORD /d 2
│   │     ── verificación ──
│   │        relee SetupType ; reg unload HKLM\RESCATE
│   │        si SetupType != 0x2 ─► [ERROR: marca no puesta, nada cambiado] ─► fin
│   │
│   └─ [4/4] LISTO  ─►  exit  ─►  Continuar / reiniciar  (reinicio MANUAL, no auto)
│
└─ [FASE 2]  — la lanza Windows al arrancar, como NT AUTHORITY\SYSTEM, antes del login
    │   Entorno: Windows real a medio arrancar, token SYSTEM, sin UI de login todavía.
    │
    ├─ for %%U in (Usuario User usuario) do call :addadmin "%%U"
    │     │
    │     └─ :addadmin <cuenta>
    │           net user <cuenta>                 ¿existe la cuenta? si no, se salta
    │           net user <cuenta> /active:yes      la reactiva por si estaba deshabilitada
    │           powershell Add-LocalGroupMember -SID S-1-5-32-544 -Member <cuenta>
    │           net localgroup Administradores <cuenta> /add     (respaldo, ES)
    │           net localgroup Administrators  <cuenta> /add     (respaldo, EN)
    │
    ├─ net localgroup Administradores            (vuelca miembros al log)
    ├─ reg add HKLM\SYSTEM\Setup /v SetupType /t REG_DWORD /d 0   (quita la marca)
    ├─ reg add HKLM\SYSTEM\Setup /v CmdLine   /t REG_SZ    /d ""   (arranque normal)
    ├─ del  %SystemDrive%\Windows\Temp\Rescate_Admin.bat          (se autoborra)
    └─ shutdown /r /t 5    ─►  arranca al inicio de sesión normal; la cuenta YA es admin
```

---

## Cómo consigue reactivar el admin (el punto clave)

1. **El problema de privilegios.** Para meter una cuenta en *Administradores* hace falta
   ser administrador. Si no queda ninguno, desde el Windows arrancado no hay forma: es un
   candado circular.

2. **WinRE rompe el candado de acceso, no el de privilegios.** Arrancando en la
   recuperación (WinPE) el disco del sistema se monta y es **escribible**, y su hive de
   registro se puede cargar con `reg load`. Pero en WinRE todavía no se puede "añadir al
   grupo" directamente, porque ese grupo pertenece al Windows instalado, que no está
   corriendo.

3. **Se delega el trabajo en `SYSTEM`.** En vez de tocar el grupo a mano, se deja
   programado que el **propio Windows**, al arrancar, ejecute la orden con la identidad
   `NT AUTHORITY\SYSTEM`. `SYSTEM` es la cuenta de servicio del sistema operativo: tiene
   privilegios por encima de los de un administrador y **no necesita login**. Es quien, en
   la FASE 2, ejecuta `Add-LocalGroupMember` / `net localgroup`.

4. **El disparador es `SetupType=2` + `CmdLine`.** Es el mecanismo que usan los
   fabricantes para el *audit mode* (dejar un equipo preparado antes de la primera sesión):
   si al arrancar esos dos valores están puestos, Windows ejecuta `CmdLine` como `SYSTEM`
   antes de mostrar el login. El rescate se cuela por esa misma puerta.

5. **Se limpia solo.** La FASE 2, ya con la cuenta dentro de Administradores, pone
   `SetupType=0` y `CmdLine` vacío, borra el `.bat` de `Temp` y reinicia. El equipo
   vuelve a un arranque normal sin rastro de la marca.

> **Por qué NO usa el truco de `utilman.exe`/`sethc.exe`** (sustituir el ejecutable de
> accesibilidad por `cmd.exe` en la pantalla de login): en Windows 11 recientes lo bloquea
> un parche de seguridad y lo marca Defender. El camino `SetupType`/`CmdLine` es el soportado.

---

## Seguridad, reversibilidad y rastro

- **Qué toca**: pertenencia al grupo local *Administradores* + dos valores en
  `HKLM\SYSTEM\Setup` (temporales, revertidos en la FASE 2). Nada más.
- **Qué NO toca**: ficheros de usuario, Windows, arranque (BCD), BitLocker.
- **Reversible**: para volver atrás, sacar la cuenta del grupo
  (`net localgroup Administradores <cuenta> /delete`).
- **Rastro**: `Rescate_Admin.log` en el USB (FASE 1) y en
  `C:\Windows\Temp\Rescate_Admin.log` (FASE 2, con los miembros resultantes del grupo).
- **BitLocker**: si el volumen está **bloqueado**, WinRE no puede escribir el hive;
  hay que desbloquear antes (`manage-bde -unlock C: -RecoveryPassword <clave>`). En
  estado *clear key* (protección suspendida / sin protectores) el disco es legible y
  escribible sin pedir clave.

---

## Glosario (términos y siglas)

| Término | Qué es |
|---|---|
| **WinRE** (Windows Recovery Environment) | Entorno de recuperación de Windows. Un mini-sistema que arranca aparte para reparar, con consola (`cmd`) y acceso al disco. Se entra con Mayús+Reiniciar o tras fallos de arranque. |
| **WinPE** (Windows Preinstallation Environment) | El Windows mínimo sobre el que corre WinRE. Monta un disco RAM temporal, normalmente en la letra `X:`. |
| **`NT AUTHORITY\SYSTEM`** | Cuenta interna del sistema operativo. Privilegios por encima de un administrador, sin contraseña ni inicio de sesión. Los servicios de Windows corren bajo ella. La FASE 2 se ejecuta como SYSTEM. |
| **Integrity level** | Nivel de integridad (System > High/admin > Medium/usuario). Explica por qué SYSTEM puede lo que un usuario no. |
| **SID** (Security Identifier) | Identificador único de una cuenta o grupo. Los grupos integrados tienen un SID fijo igual en todos los Windows e **idioma-independiente** (por eso se usa el SID y no el nombre). |
| **`S-1-5-32-544`** | SID del grupo local **Administradores** / *Administrators*. Es el grupo al que se devuelve la cuenta. |
| **`S-1-5-32-545`** | SID del grupo local **Usuarios** / *Users*. |
| **HKLM** (`HKEY_LOCAL_MACHINE`) | Rama del registro con la configuración de la máquina (no del usuario). |
| **Hive** | Fichero físico de una rama del registro. El de `HKLM\SYSTEM` es `...\System32\config\SYSTEM`. En WinRE se carga con `reg load`. |
| **`reg load` / `reg unload`** | Montar / desmontar el hive de otro Windows (el del disco parado) bajo una rama temporal del registro de WinRE, para poder editarlo. |
| **`HKLM\SYSTEM\Setup`** | Clave que Windows lee muy temprano en el arranque; de ahí salen `SetupType` y `CmdLine`. |
| **`SetupType`** | Valor que indica en qué fase de instalación/setup está el equipo. `2` = ejecutar `CmdLine` como SYSTEM antes del login (audit/setup). `0` = arranque normal. |
| **`CmdLine`** | Orden que Windows ejecuta como SYSTEM cuando `SetupType=2`. Aquí: relanzar el `.bat` con el argumento `fase2`. |
| **`REG_DWORD`** | Tipo de dato del registro: entero de 32 bits. `SetupType` es un DWORD. |
| **`REG_EXPAND_SZ`** | Cadena con variables de entorno que se **expanden** al leerse (p. ej. `%SystemDrive%` → `C:`). `CmdLine` debe ser de este tipo; con `REG_SZ` (cadena literal) la variable no se expandiría y la FASE 2 no arrancaría. |
| **`%SystemDrive%`** | Variable de entorno = unidad donde está Windows (normalmente `C:`). |
| **`%~f0` / `%~d0` / `%~dp0`** | Referencias de `cmd` al propio `.bat`: ruta completa / letra de unidad / carpeta. Sirven para copiarse y para saber desde qué USB corre. |
| **`ntoskrnl.exe`** | Núcleo (kernel) de Windows. Su presencia confirma que esa unidad es una instalación de Windows real, no el USB ni el RAMDisk. |
| ***Audit mode*** | Fase de los fabricantes en la que se prepara el equipo (instalar apps, ajustes) **antes** del primer login, ejecutando tareas como SYSTEM. El rescate reutiliza su disparador. |
| **BCD** (Boot Configuration Data) | Base de datos de arranque de Windows. El rescate **no** la toca (se menciona solo para dejar claro qué queda intacto). |
| **BitLocker — *clear key*** | Estado en que el cifrado está suspendido / sin protectores: el volumen se lee y escribe desde WinRE sin pedir clave y arranca sin prompt. |
| **UIPI** (User Interface Privilege Isolation) | Aislamiento por nivel de integridad en la interfaz. No afecta a este rescate; se nombra aparte en DocUnlock (bloquea el arrastrar y soltar a ventanas elevadas). |
