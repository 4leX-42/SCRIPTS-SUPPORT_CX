# SCRIPTS-SUPPORT_CX

Endpoint remediation on the user's machine. Self-contained, no dependencies. PowerShell 5.1 and 7, Windows 10 and 11.

🇪🇸 [Español](README.md)

---

## 01 — Accounts and credentials

User profile, not elevated.

| Function | Script |
|---|---|
| Inventory of cached accounts and where each is stored — read only | [`01-listar-cuentas-cacheadas.ps1`](01-cuentas-y-credenciales/01-listar-cuentas-cacheadas.ps1) |
| Purge cached credentials, with exclusions | [`02-limpiar-cuentas-cacheadas.ps1`](01-cuentas-y-credenciales/02-limpiar-cuentas-cacheadas.ps1) |
| Purge orphaned identity from a migrated tenant — auto-detects UPN and tenant | [`03-reset-tenant-obsoleto-v2.1.ps1`](01-cuentas-y-credenciales/03-reset-tenant-obsoleto-v2.1.ps1) |
| Tiered M365 credential cache repair, with rollback | [`04-reparar-cache-credenciales-con-restore.ps1`](01-cuentas-y-credenciales/04-reparar-cache-credenciales-con-restore.ps1) |

Scope: Office `Identity` registry, `IdentityCRL`, WAM/`TokenBroker`, `OneAuth`, `IdentityCache`,
Credential Manager, `OneDrive\Accounts`, Office licensing. `03` also resolves each domain against
`getuserrealm` and `openid-configuration` to determine its tenantId.

## 02 — Outlook

User profile, not elevated. Neither deletes `.pst`.

| Function | Script |
|---|---|
| Rebuild profile, accounts and Autodiscover — keeps `.pst` and `.ost` | [`01-reset-perfil-outlook-clasico.ps1`](02-outlook/01-reset-perfil-outlook-clasico.ps1) |
| Full reset: profile, `.ost` and `RoamCache` autocomplete | [`02-reset-completo-outlook.ps1`](02-outlook/02-reset-completo-outlook.ps1) |

## 03 — OneDrive

| Function | Script |
|---|---|
| Tiered L1-L5 remediation: restart, `/reset`, cache, binary signature, reinstall | [`01-remediar-onedrive-por-niveles.ps1`](03-onedrive/01-remediar-onedrive-por-niveles.ps1) |
| Purge residual GPO `Everyone:(DENY)` ACEs — user is prompted for admin in their own OneDrive | [`02-reparar-permisos-onedrive.ps1`](03-onedrive/02-reparar-permisos-onedrive.ps1) |

`02` has a runbook in [`02-reparar-permisos-onedrive.md`](03-onedrive/02-reparar-permisos-onedrive.md).
Phases `Reparar` and `Comprobar` need admin; `Verificar` runs in the user's session, **not elevated**.

## 04 — Teams

| Function | Script |
|---|---|
| Authentication repair: cache, `EBWebView`, WAM tokens | [`01-reparar-login-teams.ps1`](04-teams/01-reparar-login-teams.ps1) |
| Re-register the meeting add-in and purge `Resiliency\DisabledItems` | [`02-reparar-complemento-teams-en-outlook.ps1`](04-teams/02-reparar-complemento-teams-en-outlook.ps1) |

## 05 — Office

| Function | Script |
|---|---|
| Click-to-Run installation repair and licence reactivation | [`01-reparar-instalacion-office.ps1`](05-office-apps/01-reparar-instalacion-office.ps1) |
| Unattended diagnostics and remediation engine — OneDrive, Outlook, Office, identity, network | [`02-motor-remediacion-m365-desatendido.ps1`](05-office-apps/02-motor-remediacion-m365-desatendido.ps1) |

`02` is non-interactive and idempotent, for Intune, GPO or RMM. Takes `-TargetService`, `-MaxLevel`, `-DiagnosticOnly`.

## 06 — Applications

Require admin.

| Function | Script |
|---|---|
| ESET Endpoint diagnostics: binary, service, console connectivity | [`01-diagnosticar-eset.ps1`](06-aplicaciones/01-diagnosticar-eset.ps1) |
| ESET Management Agent enrolment status in ESET PROTECT | [`02-estado-agente-eset.ps1`](06-aplicaciones/02-estado-agente-eset.ps1) |
| Unattended ESET Endpoint install via UI Automation | [`03-instalar-eset.ps1`](06-aplicaciones/03-instalar-eset.ps1) |
| Full uninstall of iManage Work Desktop and its add-ins | [`04-desinstalar-imanage.ps1`](06-aplicaciones/04-desinstalar-imanage.ps1) |
| PDFelement and iManage install via UI Automation | [`05-instalar-pdfelement-e-imanage.ps1`](06-aplicaciones/05-instalar-pdfelement-e-imanage.ps1) |
| Identify installer type and supported silent switches | [`06-diagnosticar-instaladores.ps1`](06-aplicaciones/06-diagnosticar-instaladores.ps1) |

Package source: `$env:SOPORTE_ORIGEN_PAQUETES`.

## 07 — Machine

| Function | Script |
|---|---|
| Inventory: hardware, Windows build, join state, MDM, disk, network, Office | [`01-informe-del-equipo.ps1`](07-equipo/01-informe-del-equipo.ps1) |
| Disk usage by folder and reclaimable space | [`02-espacio-en-disco.ps1`](07-equipo/02-espacio-en-disco.ps1) |
| BitLocker recovery key by serial, name or `deviceId` ⚠️ | [`03-clave-recuperacion-bitlocker.ps1`](07-equipo/03-clave-recuperacion-bitlocker.ps1) |
| Diagnose and fix unexpected shutdowns and restarts | [`04-reparar-apagados-aleatorios.ps1`](07-equipo/04-reparar-apagados-aleatorios.ps1) |

> ⚠️ The key hangs off the Entra device object. If that object is deleted, the key is lost and the
> disk is unrecoverable. Extract it **before** resetting or deleting anything.

## 08 — Network

| Function | Script |
|---|---|
| M365 reachability test: DNS, TCP 443, proxy and latency across 7 endpoints | [`01-probar-conectividad-m365.ps1`](08-red/01-probar-conectividad-m365.ps1) |
| Disable Wi-Fi adapter power saving and set the high performance power plan | [`02-optimizar-tarjeta-wifi.ps1`](08-red/02-optimizar-tarjeta-wifi.ps1) |

## 09 — Documents

| Function | Script |
|---|---|
| Remove edit protection from a `.docx` | [`01-desbloquear-word-protegido.ps1`](09-documentos/01-desbloquear-word-protegido.ps1) |

## 99 — Repo tooling

| Function | Script |
|---|---|
| Validate ASCII, BOM and syntax on 5.1 and 7 — run before every commit | [`01-validar-scripts.ps1`](99-herramientas-repo/01-validar-scripts.ps1) |
| Sandbox test of the deletion logic behind the Outlook scripts | [`02-test-reset-outlook.ps1`](99-herramientas-repo/02-test-reset-outlook.ps1) |

## 00 — Copy and paste

| Function | File |
|---|---|
| Loose commands: disk, Office, identity, Intune, network, printing, Windows Update | [`README.md`](00-copiar-pegar/README.md) |
| Long path handling for OneDrive and iManage | [`01-rutas-largas.txt`](00-copiar-pegar/01-rutas-largas.txt) |

---

## Parameters and execution

```powershell
powershell -ExecutionPolicy Bypass -File .\script.ps1     # without changing the policy
Unblock-File .\script.ps1                                 # if downloaded or from a network drive
Get-Help .\script.ps1 -Full                               # parameters and examples, ES and EN
```

| Parameter | Present in | Effect |
|---|---|---|
| `-DryRun` / `-WhatIf` | everything that writes | enumerates, changes nothing |
| `-Force` | anything that prompts | no interactive confirmation |
| `-SoloDetectar` | `01/03` | inventory and tenant resolution, read only |
| `-Upn`, `-TenantOrigen` | `01/03` | omitted: auto-detected and offered in a menu |
| `-Excluir`, `-Quitar` | `01/02` | accounts to keep, or accounts to purge |
| `-Mode`, `-RestoreFrom` | `01/04` | `Diagnose` \| `Repair` \| `Restore` |
| `-Fase` | `03/02` | `Reparar` \| `Comprobar` \| `Verificar` |
| `-TargetService`, `-MaxLevel`, `-DiagnosticOnly` | `05/02` | service, max escalation tier, diagnose only |
| `-RutaRespaldo` | `01/03` | backup target when the Desktop is not writable |
| `$env:SOPORTE_ORIGEN_PAQUETES` | `05/01`, `06/*` | installer share path |

## Execution context

| Scope the script touches | Account |
|---|---|
| `HKCU`, `%APPDATA%`, `%LOCALAPPDATA%`, credentials, Office, OneDrive, Teams | user, **not elevated** |
| `HKLM`, services, `C:\Windows`, network, spooler, Windows Update, installers | admin |

Elevating with a different account redirects `HKCU` and `%LOCALAPPDATA%` to that profile. Scripts
under `01-` detect this against the owner of `explorer.exe` and abort.

## Retired

In [`_archivo/`](_archivo/), reference only.

| Retired | Replacement |
|---|---|
| `reset-tenant-obsoleto-v1-Reset-CachedWorkAccount.ps1` | `01/03-reset-tenant-obsoleto-v2.1` |
| `Limpiar-CuentasMicrosoft.ps1` | `01/02-limpiar-cuentas-cacheadas` |
| `Script2.0-reparar-identidad-office.txt` | `01/02-limpiar-cuentas-cacheadas` |
| `ONEDRIVE-limpieza-sesion.txt` | `01/02-limpiar-cuentas-cacheadas` |
| `Mod-ESET-v3-ui-automation.ps1` | `06/03-instalar-eset` |
| `Fix-Pendientes.ps1` | `06/05-instalar-pdfelement-e-imanage` |

## Standard

Enforced by `99-herramientas-repo/01-validar-scripts.ps1`:

- ASCII only in code. UTF-8 with BOM.
- PowerShell 5.1 and 7. Windows 10 and 11.
- `-DryRun` or `-WhatIf` on anything that writes.
- `param()`, no hard-coded paths or accounts.
- `.SYNOPSIS` with an `[ES]` line and an `[EN]` line.
- Self-contained: no external modules, no certificates.
- `#Requires` separated from the `<#` block by a blank line, or `Get-Help` won't read the synopsis.
