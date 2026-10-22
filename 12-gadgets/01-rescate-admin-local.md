# Rescate de administrador local (WinRE)

Devuelve una cuenta local (p. ej. `Usuario`) al grupo **Administradores** cuando el
equipo se ha quedado **sin ningún administrador**. No reinstala Windows, no borra datos:
solo cambia grupos locales. Es reversible.

Es un `.bat`, no un `.ps1`: se ejecuta **desde la recuperación de Windows (WinRE)**, no
por `irm` en el sistema arrancado, porque el equipo no tiene con qué iniciar sesión como admin.

## Cómo funciona

Marca el registro del equipo (`HKLM\SYSTEM\Setup`: `SetupType=2` + `CmdLine`). Al
arrancar, Windows ejecuta esa orden **como SYSTEM antes del login** (el "modo auditoría"
de los fabricantes). Esa orden mete a la cuenta en Administradores y luego deja el arranque
normal. **No usa el truco de `utilman.exe`**: en Windows 11 recientes lo bloquea un parche de
seguridad y lo detecta Defender.

## Preparar el USB (en un PC que funcione, antes de ir al equipo roto)

Dentro de WinRE no hay internet, así que el `.bat` se baja **antes** a la raíz del USB.
En PowerShell, con el USB como `E:` (cámbialo por su letra):

```powershell
$f="E:\01-rescate-admin-local.bat"; [Net.ServicePointManager]::SecurityProtocol=3072; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/12-gadgets/01-rescate-admin-local.bat -OutFile $f
```

(O descárgalo a mano desde GitHub y cópialo al USB.) El fichero va en CRLF a
propósito: en LF el `cmd` de la recuperación puede fallar con los `goto`.

## Uso (método automático)

1. En la pantalla de inicio de sesión del equipo roto: con **Mayús** pulsada, **Encendido → Reiniciar**.
2. **Solucionar problemas → Opciones avanzadas → Símbolo del sistema**.
3. Enchufa el USB ya preparado y mira su letra:
   ```
   wmic logicaldisk get deviceid,volumename
   ```
4. Ejecútalo con esa letra (p. ej. `E:`):
   ```
   E:\01-rescate-admin-local.bat
   ```
5. Debe llegar a **[4/4] LISTO**. Entonces `exit` y **Continuar** (o apaga y enciende).
6. Al arrancar hace el rescate solo (ventana negra 1-2 s) y llega al login. Entra con tu
   cuenta: ya será administrador.

Cuentas que recupera: `Usuario`, `User`, `usuario` (editable en la línea `set "CUENTAS=..."`).
Deja registro en el USB (`Rescate_Admin.log`) y en `C:\Windows\Temp\Rescate_Admin.log`.

## Método manual (respaldo, si el .bat falla)

Mismo mecanismo, a mano, en el Símbolo del sistema de la recuperación. Localiza el disco de
Windows (`dir C:\Windows`; si no, prueba `D:`, `E:`...) y con esa letra:

```
reg load HKLM\TMP C:\Windows\System32\config\SYSTEM
reg add HKLM\TMP\Setup /v CmdLine /t REG_EXPAND_SZ /d "cmd.exe" /f
reg add HKLM\TMP\Setup /v SetupType /t REG_DWORD /d 2 /f
reg unload HKLM\TMP
```

`exit` y arranca normal. Antes del login se abre una consola **SYSTEM**; en ella:

```
net localgroup Administradores Usuario /add
reg add HKLM\SYSTEM\Setup /v SetupType /t REG_DWORD /d 0 /f
exit
```

## Si dice "No encuentro Windows"

- BitLocker: `manage-bde -status`; si está **Bloqueado**, desbloquéalo con
  `manage-bde -unlock C: -RecoveryPassword <clave>` (clave en account.microsoft.com/devices
  o en Entra/AD).
- O la letra del disco es otra: `wmic logicaldisk get deviceid,volumename`.
