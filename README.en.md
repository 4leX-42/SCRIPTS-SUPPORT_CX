# SCRIPTS-SUPPORT_CX

Endpoint remediation on the user's machine. Self-contained, no dependencies. PowerShell 5.1 and 7, Windows 10 and 11.

🇪🇸 [Español](README.md)

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

| Report | Script | Window | What it reports |
|---|---|---|---|
| **Long path fix (MAX_PATH)** | [`91-long-paths`](00-copy-paste/91-long-paths.txt) | `admin` | Enables LongPathsEnabled and 8.3 names, and finds the paths beyond 255 characters in OneDrive and iManage |
| **Machine snapshot** | [`03-endpoint-report`](00-copy-paste/03-endpoint-report.ps1) | `admin` | Hardware, real Windows generation, Entra or domain join, MDM, disk, BitLocker, network and Office |
| **ESET agent state** | [`06-eset-status`](00-copy-paste/06-eset-status.ps1) | `admin` | Installation, services, binary signature, enrolment read from the trace log and ESET PROTECT connectivity |
| **Cached accounts and identities** | [`01-cached-accounts`](00-copy-paste/01-cached-accounts.ps1) | `user` | Cached account inventory: source of each one, GUID UPN detection and real tenantId per domain |
| **OneDrive state** | [`02-onedrive-status`](00-copy-paste/02-onedrive-status.ps1) | `user` | Process, version, linked accounts, deny ACEs, write test and log freshness |
| **M365 reachability** | [`04-m365-connectivity`](00-copy-paste/04-m365-connectivity.ps1) | `user` | Proxy, DNS, TCP 443, TLS version and latency across the 7 Microsoft 365 endpoints |
| **Office and Outlook state** | [`05-office-outlook-status`](00-copy-paste/05-office-outlook-status.ps1) | `user` | Version, licence, identities, profiles, .ost and .pst, add-ins and disabled items |

## 01 - Identity cache

| Function | Script |
|---|---|
| Clears cached work accounts. Removes them all except the ones you choose to keep. | [`01-clear-cached-accounts`](01-identity-cache/01-clear-cached-accounts.ps1) |
| Removes the account left over from an old tenant. Auto-detects the UPN and the tenant. | [`02-reset-stale-tenant-v2.1`](01-identity-cache/02-reset-stale-tenant-v2.1.ps1) |
| Repairs the Microsoft 365 credential cache in tiers, and can roll the changes back. | [`03-repair-credential-cache-with-restore`](01-identity-cache/03-repair-credential-cache-with-restore.ps1) |

## 02 - Outlook

| Function | Script |
|---|---|
| Rebuilds the classic Outlook profile while keeping .pst and .ost files. | [`01-reset-outlook-profile`](02-outlook/01-reset-outlook-profile.ps1) |
| Aggressive Outlook reset: profile, OST files and autocomplete cache. | [`02-full-outlook-reset`](02-outlook/02-full-outlook-reset.ps1) |

## 03 - OneDrive

| Function | Script |
|---|---|
| Fixes OneDrive escalating through 5 tiers: restart, reset, cache, binary and reinstall. | [`01-remediate-onedrive-tiered`](03-onedrive/01-remediate-onedrive-tiered.ps1) |
| Removes deny ACEs left behind by a domain GPO that make OneDrive prompt for admin. | [`02-fix-onedrive-permissions`](03-onedrive/02-fix-onedrive-permissions.ps1) |

Detailed runbook: [`02-fix-onedrive-permissions.md`](03-onedrive/02-fix-onedrive-permissions.md)

## 04 - Teams

| Function | Script |
|---|---|
| Fixes Teams sign-in when it loops or fails to authenticate. | [`01-repair-teams-signin`](04-teams/01-repair-teams-signin.ps1) |
| Restores the Teams meeting button when it disappears from Outlook. | [`02-repair-teams-outlook-addin`](04-teams/02-repair-teams-outlook-addin.ps1) |

## 05 - Office apps

| Function | Script |
|---|---|
| Repairs the Office installation: quick or online repair, plus reactivation. | [`01-repair-office-install`](05-office-apps/01-repair-office-install.ps1) |
| Unattended engine that diagnoses and repairs OneDrive, Outlook, Office, identity and network. | [`02-m365-remediation-engine`](05-office-apps/02-m365-remediation-engine.ps1) |

## 06 - Corporate applications

| Function | Script |
|---|---|
| Explains why ESET Endpoint is missing, not starting or not reaching the console. | [`01-diagnose-eset`](06-applications/01-diagnose-eset.ps1) |
| Installs ESET Endpoint unattended, even when the installer has no silent mode. | [`02-install-eset`](06-applications/02-install-eset.ps1) |
| Fully uninstalls iManage Work Desktop along with its Office add-ins. | [`03-uninstall-imanage`](06-applications/03-uninstall-imanage.ps1) |
| Installs PDFelement and iManage by driving their wizard, which has no silent mode. | [`04-install-pdfelement-imanage`](06-applications/04-install-pdfelement-imanage.ps1) |
| Inspects an installer package and reports its type and supported silent switches. | [`05-diagnose-installers`](06-applications/05-diagnose-installers.ps1) |

## 07 - Endpoint

| Function | Script |
|---|---|
| What is filling the disk: largest folders and reclaimable junk. | [`01-disk-usage`](07-endpoint/01-disk-usage.ps1) |
| Retrieves the BitLocker recovery key by serial number, device name or Entra device id. | [`02-bitlocker-recovery-key`](07-endpoint/02-bitlocker-recovery-key.ps1) |
| Diagnoses and fixes unexpected shutdowns and restarts. | [`03-fix-random-shutdowns`](07-endpoint/03-fix-random-shutdowns.ps1) |

## 08 - Network

| Function | Script |
|---|---|
| Disables Wi-Fi adapter power saving and switches to the high performance power plan. | [`01-optimize-wifi-adapter`](08-network/01-optimize-wifi-adapter.ps1) |

## 09 - Documents

| Function | Script |
|---|---|
| Removes edit protection from a Word document when the password is lost. | [`01-unlock-protected-word`](09-documents/01-unlock-protected-word.ps1) |

## 99 - Repo tools

| Function | Script |
|---|---|
| Validates every .ps1 in the repo: ASCII only, UTF-8 with BOM and syntax on 5.1 and 7. | [`01-validate-scripts`](99-repo-tools/01-validate-scripts.ps1) |
| Sandbox-tests the deletion logic behind the Outlook scripts. Never touches Outlook. | [`02-test-outlook-reset`](99-repo-tools/02-test-outlook-reset.ps1) |
| Rebuilds the index in README.md and README.en.md from each script's .SYNOPSIS. | [`03-generate-readme`](99-repo-tools/03-generate-readme.ps1) |

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
