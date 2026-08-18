# SCRIPTS-SUPPORT_CX

🇬🇧 [English](README.en.md)

---

<!-- INDICE-INICIO: generado por 99-repo-tools/03-generate-readme.ps1, no editar a mano -->

## 0 - LAS MAINS

| Operation | Script | How to run |
|---|---|---|
| **Identity Cache Purge** | [`01-clear-cached-accounts`](01-identity-cache/01-clear-cached-accounts.ps1) | `.\01-clear-cached-accounts.ps1` |
| **Stale Tenant Reset** | [`02-reset-stale-tenant-v2.1`](01-identity-cache/02-reset-stale-tenant-v2.1.ps1) | `.\02-reset-stale-tenant-v2.1.ps1` |
| **Long Path Remediation** | [`91-long-paths`](00-copy-paste/91-long-paths.txt) | `paste (admin)` |
| **Endpoint Technical Audit** | [`03-endpoint-report`](00-copy-paste/03-endpoint-report.ps1) | `paste (admin)` |
| **OneDrive Tiered Remediation** | [`01-remediate-onedrive-tiered`](03-onedrive/01-remediate-onedrive-tiered.ps1) | `.\01-remediate-onedrive-tiered.ps1` |
| **Teams Authentication Reset** | [`01-repair-teams-signin`](04-teams/01-repair-teams-signin.ps1) | `.\01-repair-teams-signin.ps1` |

## 00 - Copy and paste (diagnostics)

| Informe | Script | Ventana | Que saca |
|---|---|---|---|
| **Arreglo de rutas largas (MAX_PATH)** | [`91-long-paths`](00-copy-paste/91-long-paths.txt) | `admin` | Habilita LongPathsEnabled y nombres 8.3, y localiza las rutas que pasan de 255 caracteres en OneDrive e iManage |
| **Ficha tecnica del equipo** | [`03-endpoint-report`](00-copy-paste/03-endpoint-report.ps1) | `admin` | Hardware, generacion real de Windows, join a Entra o dominio, MDM, disco, BitLocker, red y Office |
| **Estado del agente ESET** | [`06-eset-status`](00-copy-paste/06-eset-status.ps1) | `admin` | Instalacion, servicios, firma del binario, enrolamiento leido del trace y conectividad con ESET PROTECT |
| **Cuentas cacheadas e identidades** | [`01-cached-accounts`](00-copy-paste/01-cached-accounts.ps1) | `usuario` | Inventario de cuentas cacheadas: origen de cada una, deteccion de UPN GUID y tenantId real de cada dominio |
| **Estado de OneDrive** | [`02-onedrive-status`](00-copy-paste/02-onedrive-status.ps1) | `usuario` | Proceso, version, cuentas vinculadas, ACE de denegacion, prueba de escritura y frescura de los logs |
| **Conectividad con M365** | [`04-m365-connectivity`](00-copy-paste/04-m365-connectivity.ps1) | `usuario` | Proxy, DNS, TCP 443, version de TLS y latencia contra los 7 endpoints de Microsoft 365 |
| **Estado de Office y Outlook** | [`05-office-outlook-status`](00-copy-paste/05-office-outlook-status.ps1) | `usuario` | Version, licencia, identidades, perfiles, .ost y .pst, complementos y elementos deshabilitados |

## 01 - Identity cache

| Funcion | Script |
|---|---|
| Borra las cuentas de trabajo cacheadas. Las quita todas salvo las que decidas conservar. | [`01-clear-cached-accounts`](01-identity-cache/01-clear-cached-accounts.ps1) |
| Quita la cuenta que sobrevive de un tenant antiguo. Detecta sola el UPN y el tenant. | [`02-reset-stale-tenant-v2.1`](01-identity-cache/02-reset-stale-tenant-v2.1.ps1) |
| Repara la cache de credenciales de Microsoft 365 por niveles, y sabe deshacer los cambios. | [`03-repair-credential-cache-with-restore`](01-identity-cache/03-repair-credential-cache-with-restore.ps1) |

## 02 - Outlook

| Funcion | Script |
|---|---|
| Rehace el perfil de Outlook clasico conservando los .pst y .ost. | [`01-reset-outlook-profile`](02-outlook/01-reset-outlook-profile.ps1) |
| Reset agresivo de Outlook: perfil, OST y cache de autocompletado. | [`02-full-outlook-reset`](02-outlook/02-full-outlook-reset.ps1) |

## 03 - OneDrive

| Funcion | Script |
|---|---|
| Arregla OneDrive subiendo por 5 niveles: reinicio, reset, cache, binario y reinstalacion. | [`01-remediate-onedrive-tiered`](03-onedrive/01-remediate-onedrive-tiered.ps1) |
| Quita las ACE de denegacion que dejo una GPO de dominio y hacen que OneDrive pida admin. | [`02-fix-onedrive-permissions`](03-onedrive/02-fix-onedrive-permissions.ps1) |

Runbook detallado: [`02-fix-onedrive-permissions.md`](03-onedrive/02-fix-onedrive-permissions.md)

## 04 - Teams

| Funcion | Script |
|---|---|
| Arregla el inicio de sesion de Teams cuando se queda en bucle o no autentica. | [`01-repair-teams-signin`](04-teams/01-repair-teams-signin.ps1) |
| Recupera el boton de reunion de Teams cuando desaparece de Outlook. | [`02-repair-teams-outlook-addin`](04-teams/02-repair-teams-outlook-addin.ps1) |

## 05 - Office apps

| Funcion | Script |
|---|---|
| Repara la instalacion de Office: reparacion rapida u online, y reactivacion. | [`01-repair-office-install`](05-office-apps/01-repair-office-install.ps1) |
| Motor desatendido que diagnostica y repara OneDrive, Outlook, Office, identidad y red. | [`02-m365-remediation-engine`](05-office-apps/02-m365-remediation-engine.ps1) |

## 06 - Corporate applications

| Funcion | Script |
|---|---|
| Dice por que ESET Endpoint no esta instalado, no arranca o no se conecta a la consola. | [`01-diagnose-eset`](06-applications/01-diagnose-eset.ps1) |
| Instala ESET Endpoint sin asistencia, incluso cuando el instalador no admite modo silencioso. | [`02-install-eset`](06-applications/02-install-eset.ps1) |
| Desinstala iManage Work Desktop por completo, con sus complementos de Office. | [`03-uninstall-imanage`](06-applications/03-uninstall-imanage.ps1) |
| Instala PDFelement e iManage automatizando su asistente, que no admite modo silencioso. | [`04-install-pdfelement-imanage`](06-applications/04-install-pdfelement-imanage.ps1) |
| Analiza un paquete de instalacion y dice que tipo es y que parametros silenciosos admite. | [`05-diagnose-installers`](06-applications/05-diagnose-installers.ps1) |

## 07 - Endpoint

| Funcion | Script |
|---|---|
| Que esta ocupando el disco: carpetas mas grandes y basura que se puede recuperar. | [`01-disk-usage`](07-endpoint/01-disk-usage.ps1) |
| Saca la clave de recuperacion de BitLocker por numero de serie, nombre o id de dispositivo. | [`02-bitlocker-recovery-key`](07-endpoint/02-bitlocker-recovery-key.ps1) |
| Diagnostica y corrige apagados y reinicios inesperados del equipo. | [`03-fix-random-shutdowns`](07-endpoint/03-fix-random-shutdowns.ps1) |

## 08 - Network

| Funcion | Script |
|---|---|
| Quita el ahorro de energia de la tarjeta Wi-Fi y pone el plan de alto rendimiento. | [`01-optimize-wifi-adapter`](08-network/01-optimize-wifi-adapter.ps1) |

## 09 - Documents

| Funcion | Script |
|---|---|
| Quita la proteccion de edicion de un documento de Word cuando se perdio la contrasena. | [`01-unlock-protected-word`](09-documents/01-unlock-protected-word.ps1) |

## 99 - Repo tools

| Funcion | Script |
|---|---|
| Valida todos los .ps1 del repo: solo ASCII, UTF-8 con BOM y sintaxis en 5.1 y 7. | [`01-validate-scripts`](99-repo-tools/01-validate-scripts.ps1) |
| Prueba en sandbox la logica de borrado de los scripts de Outlook. No toca Outlook. | [`02-test-outlook-reset`](99-repo-tools/02-test-outlook-reset.ps1) |
| Regenera el indice de README.md y README.en.md leyendo el .SYNOPSIS de cada script. | [`03-generate-readme`](99-repo-tools/03-generate-readme.ps1) |

<!-- INDICE-FIN -->

---

## Parámetros y ejecución

```powershell
powershell -ExecutionPolicy Bypass -File .\script.ps1     # sin tocar la política
Unblock-File .\script.ps1                                 # si viene de descarga o unidad de red
Get-Help .\script.ps1 -Full                               # parámetros y ejemplos, ES y EN
```

| Parámetro | Presente en | Efecto |
|---|---|---|
| `-DryRun` / `-WhatIf` | todo lo que escribe | enumera y no cambia nada |
| `-Force` | lo que pide confirmación | sin prompt interactivo |
| `-SoloDetectar` | `01/02` | inventario y resolución de tenant, sin tocar |
| `-Upn`, `-TenantOrigen` | `01/02` | si se omiten, se autodetectan y se ofrecen en menú |
| `-Excluir`, `-Quitar` | `01/01` | cuentas que se conservan o que se purgan |
| `-Mode`, `-RestoreFrom` | `01/03` | `Diagnose` \| `Repair` \| `Restore` |
| `-Fase` | `03/02` | `Reparar` \| `Comprobar` \| `Verificar` |
| `-TargetService`, `-MaxLevel`, `-DiagnosticOnly` | `05/02` | servicio, nivel máximo de escalado, solo diagnóstico |
| `-RutaRespaldo` | `01/02` | destino del respaldo si el Escritorio no admite escritura |
| `$env:SOPORTE_ORIGEN_PAQUETES` | `05/01`, `06/*` | ruta del share de instaladores |

Los de modo `pegar` no llevan parámetros: se pegan y ya.

## Contexto de ejecución

| Ámbito que toca el script | Cuenta |
|---|---|
| `HKCU`, `%APPDATA%`, `%LOCALAPPDATA%`, credenciales, Office, OneDrive, Teams | usuario, **sin elevar** |
| `HKLM`, servicios, `C:\Windows`, red, spooler, Windows Update, instaladores | admin |

Elevar con otra cuenta redirige `HKCU` y `%LOCALAPPDATA%` a ese perfil. Los scripts de
`01-identity-cache` lo detectan contra el propietario de `explorer.exe` y abortan.

## Retirados

En [`_archive/`](_archive/), solo consulta.

| Retirado | Sustituto |
|---|---|
| `01-listar-cuentas-cacheadas.ps1` | `00-copy-paste/01-cached-accounts.ps1` |
| `01-informe-del-equipo.ps1` | `00-copy-paste/03-endpoint-report.ps1` |
| `01-probar-conectividad-m365.ps1` | `00-copy-paste/04-m365-connectivity.ps1` |
| `02-estado-agente-eset.ps1` | `00-copy-paste/06-eset-status.ps1` |
| `reset-tenant-obsoleto-v1-Reset-CachedWorkAccount.ps1` | `01-identity-cache/02-reset-stale-tenant-v2.1.ps1` |
| `Limpiar-CuentasMicrosoft.ps1` | `01-identity-cache/01-clear-cached-accounts.ps1` |
| `Script2.0-reparar-identidad-office.txt` | `01-identity-cache/01-clear-cached-accounts.ps1` |
| `ONEDRIVE-limpieza-sesion.txt` | `01-identity-cache/01-clear-cached-accounts.ps1` |
| `Mod-ESET-v3-ui-automation.ps1` | `06-applications/02-install-eset.ps1` |
| `Fix-Pendientes.ps1` | `06-applications/04-install-pdfelement-imanage.ps1` |

Los cuatro primeros se retiraron al pasar a modo `pegar`: eran diagnósticos de solo lectura,
y para eso no hace falta descargar nada.

## Estándar

Antes de cada commit:

```powershell
.\99-repo-tools\01-validate-scripts.ps1      # ASCII, BOM y sintaxis en 5.1 y 7
.\99-repo-tools\03-generate-readme.ps1       # regenera el índice de los dos README
```

- Solo ASCII en código. UTF-8 con BOM.
- PowerShell 5.1 y 7. Windows 10 y 11.
- `-DryRun` o `-WhatIf` en todo lo que escriba.
- `param()`, sin rutas ni cuentas cableadas.
- `.SYNOPSIS` con línea `[ES]` y línea `[EN]` — de ahí sale el índice del README.
- Autónomo: sin módulos externos ni certificados.
- `#Requires` separado del bloque `<#` por una línea en blanco, o `Get-Help` no lee el synopsis.
- Los de `00-copy-paste` son la excepción: **sin bloque de ayuda y sin comentarios**. Su
  descripción va en [`00-copy-paste/index.psd1`](00-copy-paste/index.psd1).

El índice de este README se genera solo. Cambias un script, ejecutas el generador, un commit.
