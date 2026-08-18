# SCRIPTS-SUPPORT_CX

Endpoint remediation on the user's machine. Self-contained, no dependencies. PowerShell 5.1 and 7, Windows 10 and 11.

🇪🇸 [Español](README.md)

**Two usage modes**, and every script states its own in the last column:

| Mode | What it is | What for |
|---|---|---|
| `paste` | Copy the whole `.ps1` and paste it into the console | Diagnostics. Flat `key=value` output, no comments and no colour: hand it to an AI to parse |
| `download` | Download the `.ps1` and run it | Repair. These carry `-DryRun`, backups and confirmation, which pasting blind would not give you |

---

<!-- INDICE-INICIO: generado por 99-repo-tools/03-generate-readme.ps1, no editar a mano -->

## 00 - Copy and paste (diagnostics)

Paste them whole into the console. No comments, no colour: the output is flat `key=value` text meant to be handed to an AI. All read-only.

| Function | Script | Mode |
|---|---|---|
| Cached account inventory: source of each one, GUID UPN detection and real tenantId per domain | [`01-cached-accounts`](00-copy-paste/01-cached-accounts.ps1) | `paste` |
| OneDrive state: process, version, linked accounts, deny ACEs, write test and log freshness | [`02-onedrive-status`](00-copy-paste/02-onedrive-status.ps1) | `paste` |
| Machine snapshot: hardware, real Windows generation, join, MDM, disk, BitLocker, network and Office | [`03-endpoint-report`](00-copy-paste/03-endpoint-report.ps1) | `paste` |
| M365 reachability: proxy, DNS, TCP 443, TLS version and latency across 7 endpoints | [`04-m365-connectivity`](00-copy-paste/04-m365-connectivity.ps1) | `paste` |
| Office and Outlook state: version, licence, identities, profiles, .ost/.pst, add-ins and disabled items | [`05-office-outlook-status`](00-copy-paste/05-office-outlook-status.ps1) | `paste` |
| ESET state: installation, services, binary signature, enrolment from the trace log and ESET PROTECT connectivity | [`06-eset-status`](00-copy-paste/06-eset-status.ps1) | `paste` |
| Commands for handling paths beyond MAX_PATH in OneDrive and iManage | [`91-long-paths`](00-copy-paste/91-long-paths.txt) | `paste` |

## 01 - Identity cache

User profile, not elevated. Scope: Office `Identity` registry, `IdentityCRL`, WAM/`TokenBroker`, `OneAuth`, `IdentityCache`, Credential Manager, `OneDrive\Accounts` and Office licensing.

| Function | Script | Mode |
|---|---|---|
| Clears cached work accounts. Removes them all except the ones you choose to keep. | [`01-clear-cached-accounts`](01-identity-cache/01-clear-cached-accounts.ps1) | `download` |
| Removes the account left over from an old tenant. Auto-detects the UPN and the tenant. | [`02-reset-stale-tenant-v2.1`](01-identity-cache/02-reset-stale-tenant-v2.1.ps1) | `download` |
| Repairs the Microsoft 365 credential cache in tiers, and can roll the changes back. | [`03-repair-credential-cache-with-restore`](01-identity-cache/03-repair-credential-cache-with-restore.ps1) | `download` |

## 02 - Outlook

User profile, not elevated. Neither deletes `.pst`.

| Function | Script | Mode |
|---|---|---|
| Rebuilds the classic Outlook profile while keeping .pst and .ost files. | [`01-reset-outlook-profile`](02-outlook/01-reset-outlook-profile.ps1) | `download` |
| Aggressive Outlook reset: profile, OST files and autocomplete cache. | [`02-full-outlook-reset`](02-outlook/02-full-outlook-reset.ps1) | `download` |

## 03 - OneDrive

| Function | Script | Mode |
|---|---|---|
| Fixes OneDrive escalating through 5 tiers: restart, reset, cache, binary and reinstall. | [`01-remediate-onedrive-tiered`](03-onedrive/01-remediate-onedrive-tiered.ps1) | `download` |
| Removes deny ACEs left behind by a domain GPO that make OneDrive prompt for admin. | [`02-fix-onedrive-permissions`](03-onedrive/02-fix-onedrive-permissions.ps1) | `download` |

Detailed runbook: [`02-fix-onedrive-permissions.md`](03-onedrive/02-fix-onedrive-permissions.md)

## 04 - Teams

| Function | Script | Mode |
|---|---|---|
| Fixes Teams sign-in when it loops or fails to authenticate. | [`01-repair-teams-signin`](04-teams/01-repair-teams-signin.ps1) | `download` |
| Restores the Teams meeting button when it disappears from Outlook. | [`02-repair-teams-outlook-addin`](04-teams/02-repair-teams-outlook-addin.ps1) | `download` |

## 05 - Office apps

| Function | Script | Mode |
|---|---|---|
| Repairs the Office installation: quick or online repair, plus reactivation. | [`01-repair-office-install`](05-office-apps/01-repair-office-install.ps1) | `download` |
| Unattended engine that diagnoses and repairs OneDrive, Outlook, Office, identity and network. | [`02-m365-remediation-engine`](05-office-apps/02-m365-remediation-engine.ps1) | `download` |

## 06 - Corporate applications

Require admin. Package source: `$env:SOPORTE_ORIGEN_PAQUETES`.

| Function | Script | Mode |
|---|---|---|
| Explains why ESET Endpoint is missing, not starting or not reaching the console. | [`01-diagnose-eset`](06-applications/01-diagnose-eset.ps1) | `download` |
| Installs ESET Endpoint unattended, even when the installer has no silent mode. | [`02-install-eset`](06-applications/02-install-eset.ps1) | `download` |
| Fully uninstalls iManage Work Desktop along with its Office add-ins. | [`03-uninstall-imanage`](06-applications/03-uninstall-imanage.ps1) | `download` |
| Installs PDFelement and iManage by driving their wizard, which has no silent mode. | [`04-install-pdfelement-imanage`](06-applications/04-install-pdfelement-imanage.ps1) | `download` |
| Inspects an installer package and reports its type and supported silent switches. | [`05-diagnose-installers`](06-applications/05-diagnose-installers.ps1) | `download` |

## 07 - Endpoint

| Function | Script | Mode |
|---|---|---|
| What is filling the disk: largest folders and reclaimable junk. | [`01-disk-usage`](07-endpoint/01-disk-usage.ps1) | `download` |
| Retrieves the BitLocker recovery key by serial number, device name or Entra device id. | [`02-bitlocker-recovery-key`](07-endpoint/02-bitlocker-recovery-key.ps1) | `download` |
| Diagnoses and fixes unexpected shutdowns and restarts. | [`03-fix-random-shutdowns`](07-endpoint/03-fix-random-shutdowns.ps1) | `download` |

## 08 - Network

| Function | Script | Mode |
|---|---|---|
| Disables Wi-Fi adapter power saving and switches to the high performance power plan. | [`01-optimize-wifi-adapter`](08-network/01-optimize-wifi-adapter.ps1) | `download` |

## 09 - Documents

| Function | Script | Mode |
|---|---|---|
| Removes edit protection from a Word document when the password is lost. | [`01-unlock-protected-word`](09-documents/01-unlock-protected-word.ps1) | `download` |

## 99 - Repo tools

| Function | Script | Mode |
|---|---|---|
| Validates every .ps1 in the repo: ASCII only, UTF-8 with BOM and syntax on 5.1 and 7. | [`01-validate-scripts`](99-repo-tools/01-validate-scripts.ps1) | `download` |
| Sandbox-tests the deletion logic behind the Outlook scripts. Never touches Outlook. | [`02-test-outlook-reset`](99-repo-tools/02-test-outlook-reset.ps1) | `download` |
| Rebuilds the index in README.md and README.en.md from each script's .SYNOPSIS. | [`03-generate-readme`](99-repo-tools/03-generate-readme.ps1) | `download` |

<!-- INDICE-FIN -->

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
| `-SoloDetectar` | `01/02` | inventory and tenant resolution, read only |
| `-Upn`, `-TenantOrigen` | `01/02` | omitted: auto-detected and offered in a menu |
| `-Excluir`, `-Quitar` | `01/01` | accounts to keep, or accounts to purge |
| `-Mode`, `-RestoreFrom` | `01/03` | `Diagnose` \| `Repair` \| `Restore` |
| `-Fase` | `03/02` | `Reparar` \| `Comprobar` \| `Verificar` |
| `-TargetService`, `-MaxLevel`, `-DiagnosticOnly` | `05/02` | service, max escalation tier, diagnose only |
| `-RutaRespaldo` | `01/02` | backup target when the Desktop is not writable |
| `$env:SOPORTE_ORIGEN_PAQUETES` | `05/01`, `06/*` | installer share path |

`paste` mode scripts take no parameters: paste and go.

## Execution context

| Scope the script touches | Account |
|---|---|
| `HKCU`, `%APPDATA%`, `%LOCALAPPDATA%`, credentials, Office, OneDrive, Teams | user, **not elevated** |
| `HKLM`, services, `C:\Windows`, network, spooler, Windows Update, installers | admin |

Elevating with a different account redirects `HKCU` and `%LOCALAPPDATA%` to that profile. Scripts
under `01-identity-cache` detect this against the owner of `explorer.exe` and abort.

## Retired

In [`_archive/`](_archive/), reference only.

| Retired | Replacement |
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

The first four were retired on moving to `paste` mode: they were read-only diagnostics, and that
needs no download.

## Standard

Before every commit:

```powershell
.\99-repo-tools\01-validate-scripts.ps1      # ASCII, BOM and syntax on 5.1 and 7
.\99-repo-tools\03-generate-readme.ps1       # rebuilds the index in both READMEs
```

- ASCII only in code. UTF-8 with BOM.
- PowerShell 5.1 and 7. Windows 10 and 11.
- `-DryRun` or `-WhatIf` on anything that writes.
- `param()`, no hard-coded paths or accounts.
- `.SYNOPSIS` with an `[ES]` line and an `[EN]` line — the README index is built from those.
- Self-contained: no external modules, no certificates.
- `#Requires` separated from the `<#` block by a blank line, or `Get-Help` won't read the synopsis.
- `00-copy-paste` is the exception: **no help block and no comments**. Descriptions live in
  [`00-copy-paste/index.psd1`](00-copy-paste/index.psd1).

This README's index is generated. Change a script, run the generator, one commit.
