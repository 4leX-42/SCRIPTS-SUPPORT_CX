# SCRIPTS-SUPPORT_CX

🇬🇧 [English](README.en.md)

---

## 01 — Cuentas y credenciales

Perfil del usuario, sin elevar.

| Función | Script |
|---|---|
| Inventario de cuentas cacheadas y su ubicación — solo lectura | [`01-listar-cuentas-cacheadas.ps1`](01-cuentas-y-credenciales/01-listar-cuentas-cacheadas.ps1) |
| Purga de credenciales cacheadas con exclusiones | [`02-limpiar-cuentas-cacheadas.ps1`](01-cuentas-y-credenciales/02-limpiar-cuentas-cacheadas.ps1) |
| Purga de identidad huérfana de tenant migrado — autodetecta UPN y tenant | [`03-reset-tenant-obsoleto-v2.1.ps1`](01-cuentas-y-credenciales/03-reset-tenant-obsoleto-v2.1.ps1) |
| Reparación de caché de credenciales M365 por niveles, con rollback | [`04-reparar-cache-credenciales-con-restore.ps1`](01-cuentas-y-credenciales/04-reparar-cache-credenciales-con-restore.ps1) |

Alcance: registro de Office `Identity`, `IdentityCRL`, WAM/`TokenBroker`, `OneAuth`, `IdentityCache`,
Administrador de credenciales, `OneDrive\Accounts`, licencias de Office. `03` además resuelve cada
dominio contra `getuserrealm` y `openid-configuration` para determinar su tenantId.

## 02 — Outlook

Perfil del usuario, sin elevar. Ninguno borra `.pst`.

| Función | Script |
|---|---|
| Reconstrucción de perfil, cuentas y Autodiscover — conserva `.pst` y `.ost` | [`01-reset-perfil-outlook-clasico.ps1`](02-outlook/01-reset-perfil-outlook-clasico.ps1) |
| Reset total: perfil, `.ost` y `RoamCache` de autocompletado | [`02-reset-completo-outlook.ps1`](02-outlook/02-reset-completo-outlook.ps1) |

## 03 — OneDrive

| Función | Script |
|---|---|
| Remediación escalonada L1-L5: restart, `/reset`, caché, firma del binario, reinstalación | [`01-remediar-onedrive-por-niveles.ps1`](03-onedrive/01-remediar-onedrive-por-niveles.ps1) |
| Purga de ACE `Everyone:(DENY)` residuales de GPO — el usuario pide admin en su propio OneDrive | [`02-reparar-permisos-onedrive.ps1`](03-onedrive/02-reparar-permisos-onedrive.ps1) |

`02` tiene runbook en [`02-reparar-permisos-onedrive.md`](03-onedrive/02-reparar-permisos-onedrive.md).
Fases `Reparar` y `Comprobar` con admin; `Verificar` en la sesión del usuario **sin elevar**.

## 04 — Teams

| Función | Script |
|---|---|
| Reparación de autenticación: caché, `EBWebView`, tokens WAM | [`01-reparar-login-teams.ps1`](04-teams/01-reparar-login-teams.ps1) |
| Re-registro del add-in de reuniones y purga de `Resiliency\DisabledItems` | [`02-reparar-complemento-teams-en-outlook.ps1`](04-teams/02-reparar-complemento-teams-en-outlook.ps1) |

## 05 — Office

| Función | Script |
|---|---|
| Reparación de instalación Click-to-Run y reactivación de licencia | [`01-reparar-instalacion-office.ps1`](05-office-apps/01-reparar-instalacion-office.ps1) |
| Motor desatendido de diagnóstico y remediación — OneDrive, Outlook, Office, identidad, red | [`02-motor-remediacion-m365-desatendido.ps1`](05-office-apps/02-motor-remediacion-m365-desatendido.ps1) |

`02` es no interactivo e idempotente, para Intune, GPO o RMM. Acepta `-TargetService`, `-MaxLevel`, `-DiagnosticOnly`.

## 06 — Aplicaciones

Requieren admin.

| Función | Script |
|---|---|
| Diagnóstico de ESET Endpoint: binario, servicio, conectividad con la consola | [`01-diagnosticar-eset.ps1`](06-aplicaciones/01-diagnosticar-eset.ps1) |
| Estado de enrolamiento del ESET Management Agent en ESET PROTECT | [`02-estado-agente-eset.ps1`](06-aplicaciones/02-estado-agente-eset.ps1) |
| Instalación desatendida de ESET Endpoint vía UI Automation | [`03-instalar-eset.ps1`](06-aplicaciones/03-instalar-eset.ps1) |
| Desinstalación completa de iManage Work Desktop y sus add-ins | [`04-desinstalar-imanage.ps1`](06-aplicaciones/04-desinstalar-imanage.ps1) |
| Instalación de PDFelement e iManage vía UI Automation | [`05-instalar-pdfelement-e-imanage.ps1`](06-aplicaciones/05-instalar-pdfelement-e-imanage.ps1) |
| Identificación de tipo de instalador y modificadores silenciosos admitidos | [`06-diagnosticar-instaladores.ps1`](06-aplicaciones/06-diagnosticar-instaladores.ps1) |

Origen de paquetes: `$env:SOPORTE_ORIGEN_PAQUETES`.

## 07 — Equipo

| Función | Script |
|---|---|
| Inventario: hardware, build de Windows, estado de join, MDM, disco, red, Office | [`01-informe-del-equipo.ps1`](07-equipo/01-informe-del-equipo.ps1) |
| Ocupación de disco por carpeta y espacio reclamable | [`02-espacio-en-disco.ps1`](07-equipo/02-espacio-en-disco.ps1) |
| Clave de recuperación de BitLocker por serie, nombre o `deviceId` ⚠️ | [`03-clave-recuperacion-bitlocker.ps1`](07-equipo/03-clave-recuperacion-bitlocker.ps1) |
| Diagnóstico y corrección de apagados y reinicios inesperados | [`04-reparar-apagados-aleatorios.ps1`](07-equipo/04-reparar-apagados-aleatorios.ps1) |

> ⚠️ La clave cuelga del objeto de dispositivo de Entra. Si ese objeto se borra, la clave se pierde
> y el disco queda irrecuperable. Extraerla **antes** de restablecer o borrar nada.

## 08 — Red

| Función | Script |
|---|---|
| Test de alcance a M365: DNS, TCP 443, proxy y latencia contra 7 endpoints | [`01-probar-conectividad-m365.ps1`](08-red/01-probar-conectividad-m365.ps1) |
| Desactivación del ahorro de energía del adaptador Wi-Fi y plan de alto rendimiento | [`02-optimizar-tarjeta-wifi.ps1`](08-red/02-optimizar-tarjeta-wifi.ps1) |

## 09 — Documentos

| Función | Script |
|---|---|
| Eliminación de la protección de edición de un `.docx` | [`01-desbloquear-word-protegido.ps1`](09-documentos/01-desbloquear-word-protegido.ps1) |

## 99 — Herramientas del repo

| Función | Script |
|---|---|
| Validación de ASCII, BOM y sintaxis en 5.1 y 7 — correr antes de cada commit | [`01-validar-scripts.ps1`](99-herramientas-repo/01-validar-scripts.ps1) |
| Prueba en sandbox de la lógica de borrado de los scripts de Outlook | [`02-test-reset-outlook.ps1`](99-herramientas-repo/02-test-reset-outlook.ps1) |

## 00 — Copiar y pegar

| Función | Fichero |
|---|---|
| Comandos sueltos: disco, Office, identidad, Intune, red, impresión, Windows Update | [`README.md`](00-copiar-pegar/README.md) |
| Rutas largas de OneDrive e iManage | [`01-rutas-largas.txt`](00-copiar-pegar/01-rutas-largas.txt) |

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
| `-SoloDetectar` | `01/03` | inventario y resolución de tenant, sin tocar |
| `-Upn`, `-TenantOrigen` | `01/03` | si se omiten, se autodetectan y se ofrecen en menú |
| `-Excluir`, `-Quitar` | `01/02` | cuentas que se conservan o que se purgan |
| `-Mode`, `-RestoreFrom` | `01/04` | `Diagnose` \| `Repair` \| `Restore` |
| `-TargetService`, `-MaxLevel`, `-DiagnosticOnly` | `05/02` | servicio, nivel máximo de escalado, solo diagnóstico |
| `-RutaRespaldo` | `01/03` | destino del respaldo si el Escritorio no admite escritura |
| `$env:SOPORTE_ORIGEN_PAQUETES` | `05/01`, `06/*` | ruta del share de instaladores |

## Contexto de ejecución

| Ámbito que toca el script | Cuenta |
|---|---|
| `HKCU`, `%APPDATA%`, `%LOCALAPPDATA%`, credenciales, Office, OneDrive, Teams | usuario, **sin elevar** |
| `HKLM`, servicios, `C:\Windows`, red, spooler, Windows Update, instaladores | admin |

Elevar con otra cuenta redirige `HKCU` y `%LOCALAPPDATA%` a ese perfil. Los scripts de `01-`
lo detectan contra el propietario de `explorer.exe` y abortan.

## Retirados

En [`_archivo/`](_archivo/), solo consulta.

| Retirado | Sustituto |
|---|---|
| `reset-tenant-obsoleto-v1-Reset-CachedWorkAccount.ps1` | `01/03-reset-tenant-obsoleto-v2.1` |
| `Limpiar-CuentasMicrosoft.ps1` | `01/02-limpiar-cuentas-cacheadas` |
| `Script2.0-reparar-identidad-office.txt` | `01/02-limpiar-cuentas-cacheadas` |
| `ONEDRIVE-limpieza-sesion.txt` | `01/02-limpiar-cuentas-cacheadas` |
| `Mod-ESET-v3-ui-automation.ps1` | `06/03-instalar-eset` |
| `Fix-Pendientes.ps1` | `06/05-instalar-pdfelement-e-imanage` |

## Estándar

Verificado por `99-herramientas-repo/01-validar-scripts.ps1`:

- Solo ASCII en código. UTF-8 con BOM.
- PowerShell 5.1 y 7. Windows 10 y 11.
- `-DryRun` o `-WhatIf` en todo lo que escriba.
- `param()`, sin rutas ni cuentas cableadas.
- `.SYNOPSIS` con línea `[ES]` y línea `[EN]`.
- Autónomo: sin módulos externos ni certificados.
- `#Requires` separado del bloque `<#` por una línea en blanco, o `Get-Help` no lee el synopsis.
