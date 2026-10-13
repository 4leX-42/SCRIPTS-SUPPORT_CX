# SCRIPTS-SUPPORT_CX

Endpoint remediation on the user's machine. Self-contained, no dependencies. PowerShell 5.1 and 7, Windows 10 and 11.

🇪🇸 [Español](README.md)

---

<!-- INDICE-INICIO: generado por 99-repo-tools/03-generate-readme.ps1, no editar a mano -->

**Jump to:** <img src=".github/icons/clipboard_code.svg" width="20" height="20" align="top" alt=""> [Copy and paste (diagnostics)](#-00---copy-and-paste-diagnostics) | <img src=".github/icons/key.svg" width="20" height="20" align="top" alt=""> [Identity cache](#-01---identity-cache) | <img src=".github/icons/mail.svg" width="20" height="20" align="top" alt=""> [Outlook](#-02---outlook) | <img src=".github/icons/cloud.svg" width="20" height="20" align="top" alt=""> [OneDrive](#-03---onedrive) | <img src=".github/icons/people_team.svg" width="20" height="20" align="top" alt=""> [Teams](#-04---teams) | <img src=".github/icons/apps.svg" width="20" height="20" align="top" alt=""> [Office apps](#-05---office-apps) | <img src=".github/icons/puzzle_piece.svg" width="20" height="20" align="top" alt=""> [Corporate applications](#-06---corporate-applications) | <img src=".github/icons/laptop.svg" width="20" height="20" align="top" alt=""> [Endpoint](#-07---endpoint) | <img src=".github/icons/router.svg" width="20" height="20" align="top" alt=""> [Network](#-08---network) | <img src=".github/icons/document.svg" width="20" height="20" align="top" alt=""> [Documents](#-09---documents) | <img src=".github/icons/folder_open.svg" width="20" height="20" align="top" alt=""> [File picker](#-10---file-picker) | <img src=".github/icons/certificate.svg" width="20" height="20" align="top" alt=""> [Certificates](#-11---certificates) | <img src=".github/icons/wrench.svg" width="20" height="20" align="top" alt=""> [Repo tools](#-99---repo-tools)

## <img src=".github/icons/pin.svg" width="20" height="20" align="top" alt=""> 0 - LAS MAINS

| Operation | Script | How to run | Run as |
|---|---|---|---|
| <img src=".github/icons/key.svg" width="20" height="20" align="top" alt=""> **Identity Cache Purge** | [`01-clear-cached-accounts`](01-identity-cache/01-clear-cached-accounts.ps1) | `.\01-clear-cached-accounts.ps1` | `user` |
| <img src=".github/icons/key.svg" width="20" height="20" align="top" alt=""> **Stale Tenant Reset** | [`02-reset-stale-tenant-v2.1`](01-identity-cache/02-reset-stale-tenant-v2.1.ps1) | `.\02-reset-stale-tenant-v2.1.ps1` | `user` |
| <img src=".github/icons/key.svg" width="20" height="20" align="top" alt=""> **Credential Cache Repair** | [`03-repair-credential-cache-with-restore`](01-identity-cache/03-repair-credential-cache-with-restore.ps1) | `.\03-repair-credential-cache-with-restore.ps1` | `user` |
| <img src=".github/icons/cloud.svg" width="20" height="20" align="top" alt=""> **OneDrive Long Path Fix** | [`03-shorten-long-paths`](03-onedrive/03-shorten-long-paths.ps1) | `.\03-shorten-long-paths.ps1` | `user` |
| <img src=".github/icons/clipboard_code.svg" width="20" height="20" align="top" alt=""> **Endpoint Technical Audit** | [`03-endpoint-report`](00-copy-paste/03-endpoint-report.ps1) | `paste` | `admin` |
| <img src=".github/icons/cloud.svg" width="20" height="20" align="top" alt=""> **OneDrive Tiered Remediation** | [`01-remediate-onedrive-tiered`](03-onedrive/01-remediate-onedrive-tiered.ps1) | `.\01-remediate-onedrive-tiered.ps1` | `user` |
| <img src=".github/icons/people_team.svg" width="20" height="20" align="top" alt=""> **Teams Authentication Reset** | [`01-repair-teams-signin`](04-teams/01-repair-teams-signin.ps1) | `.\01-repair-teams-signin.ps1` | `user` |

## <img src=".github/icons/clipboard_code.svg" width="20" height="20" align="top" alt=""> 00 - Copy and paste (diagnostics)

| Report | Script | Window | What it reports |
|---|---|---|---|
| **Machine snapshot** | [`03-endpoint-report`](00-copy-paste/03-endpoint-report.ps1) | `admin` | Hardware, real Windows generation, Entra or domain join, MDM, disk, BitLocker, network and Office |
| **ESET agent state** | [`06-eset-status`](00-copy-paste/06-eset-status.ps1) | `admin` | Installation, services, binary signature, enrolment read from the trace log and ESET PROTECT connectivity |
| **Cached accounts and identities** | [`01-cached-accounts`](00-copy-paste/01-cached-accounts.ps1) | `user` | Cached account inventory: source of each one, GUID UPN detection and real tenantId per domain |
| **OneDrive state** | [`02-onedrive-status`](00-copy-paste/02-onedrive-status.ps1) | `user` | Process, version, linked accounts, deny ACEs, write test and log freshness |
| **M365 reachability** | [`04-m365-connectivity`](00-copy-paste/04-m365-connectivity.ps1) | `user` | Proxy, DNS, TCP 443, TLS version and latency across the 7 Microsoft 365 endpoints |
| **Office and Outlook state** | [`05-office-outlook-status`](00-copy-paste/05-office-outlook-status.ps1) | `user` | Version, licence, identities, profiles, .ost and .pst, add-ins and disabled items |

## <img src=".github/icons/key.svg" width="20" height="20" align="top" alt=""> 01 - Identity cache

| Function | Script | Run as | Parameters |
|---|---|---|---|
| Clears cached work accounts. Removes them all except the ones you choose to keep. | [`01-clear-cached-accounts`](01-identity-cache/01-clear-cached-accounts.ps1) | `user` | `-Excluir` `-Quitar` `-NoCerrarApps` `-Detalle` `-DryRun` `-Force` |
| Removes the account left over from an old tenant. Auto-detects the UPN and the tenant. | [`02-reset-stale-tenant-v2.1`](01-identity-cache/02-reset-stale-tenant-v2.1.ps1) | `user` | `-Upn` `-TenantOrigen` `-TenantEsperado` `-RutaRespaldo` `-SoloDetectar` `-NoInteractivo` `-DryRun` `-NoCerrarApps` `-BorrarCookiesEdge` `-QuitarWorkplaceJoin` `-IgnorarPerfil` `-Force` |
| Repairs the Microsoft 365 credential cache in tiers, and can roll the changes back. | [`03-repair-credential-cache-with-restore`](01-identity-cache/03-repair-credential-cache-with-restore.ps1) | `user` | `-Mode` `-Accounts` `-Tiers` `-BackupRoot` `-RestoreFrom` `-CloseApps` `-DryRun` `-Force` |

## <img src=".github/icons/mail.svg" width="20" height="20" align="top" alt=""> 02 - Outlook

| Function | Script | Run as | Parameters |
|---|---|---|---|
| Rebuilds the classic Outlook profile keeping .pst and .ost files and recreates it with the same account. | [`01-reset-outlook-profile`](02-outlook/01-reset-outlook-profile.ps1) | `user` | `-FullReset` `-ClearAutoComplete` `-Email` `-ProfileName` `-NoRecreate` `-WaitSeconds` `-Force` `-WhatIf` |
| Aggressive Outlook reset: profile, OST files and autocomplete cache. | [`02-full-outlook-reset`](02-outlook/02-full-outlook-reset.ps1) | `user` | `-SkipProfileReset` `-SkipOST` `-SkipRoamCache` `-DeleteWholeLocalOutlookFolder` `-WhatIf` |
| Repairs the Microsoft 365 sign-in window that stays blank or stuck on "One moment..." when adding the account in Outlook. | [`03-repair-signin-window`](02-outlook/03-repair-signin-window.ps1) | `admin` | `-SoloDiagnostico` `-BorrarCuentasWam` `-DryRun` `-Force` |

## <img src=".github/icons/cloud.svg" width="20" height="20" align="top" alt=""> 03 - OneDrive

| Function | Script | Run as | Parameters |
|---|---|---|---|
| Fixes OneDrive escalating through 5 tiers: restart, reset, cache, binary and reinstall. | [`01-remediate-onedrive-tiered`](03-onedrive/01-remediate-onedrive-tiered.ps1) | `user` | `-MaxLevel` `-LocalInstallerPath` `-StartupWaitSeconds` `-SkipEnvironmentChecks` `-ClearCredentials` `-ForceReinstall` |
| Removes deny ACEs left behind by a domain GPO that make OneDrive prompt for admin. | [`02-fix-onedrive-permissions`](03-onedrive/02-fix-onedrive-permissions.ps1) | `admin + user` | `-Fase` `-Ruta` `-DryRun` |
| Shortens OneDrive paths over 380 characters ("the path is too long") without renaming the documents. | [`03-shorten-long-paths`](03-onedrive/03-shorten-long-paths.ps1) | `user` | `-Ruta` `-Upn` `-Raiz` `-Limite` `-Margen` `-PermitirRecorte` `-MinNombre` `-DryRun` `-SinConfirmar` `-Ascii` `-Revertir` |

Detailed runbook: [`02-fix-onedrive-permissions.md`](03-onedrive/02-fix-onedrive-permissions.md)

## <img src=".github/icons/people_team.svg" width="20" height="20" align="top" alt=""> 04 - Teams

| Function | Script | Run as | Parameters |
|---|---|---|---|
| Fixes Teams sign-in when it loops or fails to authenticate. | [`01-repair-teams-signin`](04-teams/01-repair-teams-signin.ps1) | `user` | `-DryRun` `-Force` `-Aggressive` `-IncludeOutlook` `-RepairTeams` `-LogPath` |
| Restores the Teams meeting button when it disappears from classic Outlook. | [`02-repair-teams-outlook-addin`](04-teams/02-repair-teams-outlook-addin.ps1) | `admin` | `-User` |
| Re-registers the Teams meeting add-in in classic Outlook and hardens it. | [`03-repair-teams-addin-com`](04-teams/03-repair-teams-addin-com.ps1) | `user` | `-NoKillOutlook` |

## <img src=".github/icons/apps.svg" width="20" height="20" align="top" alt=""> 05 - Office apps

| Function | Script | Run as | Parameters |
|---|---|---|---|
| Repairs the Office installation: quick or online repair, plus reactivation. | [`01-repair-office-install`](05-office-apps/01-repair-office-install.ps1) | `admin` | none |
| Unattended engine that diagnoses and repairs OneDrive, Outlook, Office, identity and network. | [`02-m365-remediation-engine`](05-office-apps/02-m365-remediation-engine.ps1) | `admin` | `-TargetService` `-MaxLevel` `-DiagnosticOnly` `-LogPath` |

## <img src=".github/icons/puzzle_piece.svg" width="20" height="20" align="top" alt=""> 06 - Corporate applications

| Function | Script | Run as | Parameters |
|---|---|---|---|
| Explains why ESET Endpoint is missing, not starting or not reaching the console. | [`01-diagnose-eset`](06-applications/01-diagnose-eset.ps1) | `admin` | none |
| Installs ESET Endpoint unattended, even when the installer has no silent mode. | [`02-install-eset`](06-applications/02-install-eset.ps1) | `admin` | `-Modo` |
| Fully uninstalls iManage Work Desktop along with its Office add-ins. | [`03-uninstall-imanage`](06-applications/03-uninstall-imanage.ps1) | `admin` | `-WhatIf` |
| Installs PDFelement and iManage by driving their wizard, which has no silent mode. | [`04-install-pdfelement-imanage`](06-applications/04-install-pdfelement-imanage.ps1) | `admin` | `-Modo` |
| Inspects an installer package and reports its type and supported silent switches. | [`05-diagnose-installers`](06-applications/05-diagnose-installers.ps1) | `admin` | none |
| Repairs the Mitel Connect / MiCollab client: cache, registry, Outlook, credentials and DNS. | [`06-repair-mitel-client`](06-applications/06-repair-mitel-client.ps1) | `admin + user` | `-DryRun` `-Force` `-AllUsers` `-KeepOutlookAddin` `-DisableOutlookAddin` `-KeepCredentials` `-ServerHost` `-FixDns` `-DnsServers` `-DnsSuffix` `-FixHosts` `-FixFirewall` `-Reinstall` `-LogPath` |

## <img src=".github/icons/laptop.svg" width="20" height="20" align="top" alt=""> 07 - Endpoint

| Function | Script | Run as | Parameters |
|---|---|---|---|
| What is filling the disk: largest folders and reclaimable junk. | [`01-disk-usage`](07-endpoint/01-disk-usage.ps1) | `admin` | `-Ruta` `-Top` `-SoloBasura` |
| Retrieves the BitLocker recovery key by serial number, device name or Entra device id. | [`02-bitlocker-recovery-key`](07-endpoint/02-bitlocker-recovery-key.ps1) | `user` | `-Serie` `-Nombre` `-DeviceId` `-RutaCsv` `-ConfigPath` |
| Diagnoses and fixes unexpected shutdowns and restarts. | [`03-fix-random-shutdowns`](07-endpoint/03-fix-random-shutdowns.ps1) | `admin` | `-SkipDiag` `-SkipWifi` |
| Gets the clock back in sync so e-government signing works: detects location, matches time zone and country NTP servers, and repairs W32Time. | [`04-repair-time-sync`](07-endpoint/04-repair-time-sync.ps1) | `admin` | `-DryRun` `-Force` `-DiagnoseOnly` `-TimeZoneId` `-NtpServers` `-SkipGeo` `-NoTimeZoneChange` `-PersistPublicNtp` `-AllowStepTime` `-NoStepTime` `-AutoTimeZoneService` `-PollSeconds` `-LogPath` |
| Enables Windows long paths (over 260 characters) and disables 8.3 short names. | [`05-enable-long-paths`](07-endpoint/05-enable-long-paths.ps1) | `admin` | `-DryRun` |

## <img src=".github/icons/router.svg" width="20" height="20" align="top" alt=""> 08 - Network

| Function | Script | Run as | Parameters |
|---|---|---|---|
| Disables Wi-Fi adapter power saving and switches to the high performance power plan. | [`01-optimize-wifi-adapter`](08-network/01-optimize-wifi-adapter.ps1) | `admin` | `-Adaptador` `-DryRun` |

## <img src=".github/icons/document.svg" width="20" height="20" align="top" alt=""> 09 - Documents

| Function | Script | Run as | Parameters |
|---|---|---|---|
| Removes edit protection from a Word document when the password is lost. | [`01-unlock-protected-word`](09-documents/01-unlock-protected-word.ps1) | `user` | `-NoPause` `-Paths` |

## <img src=".github/icons/folder_open.svg" width="20" height="20" align="top" alt=""> 10 - File picker

| Function | Script | Run as | Parameters |
|---|---|---|---|
| Read-only. Inventory of everything that can hang the Windows file picker. | [`01-diagnose-file-picker`](10-file-picker/01-diagnose-file-picker.ps1) | `user` | `-OutDir` `-DiasEventos` `-TimeoutRutaSegundos` `-SinFirmas` |
| Read-only. Reproduces the file picker hang and captures the DLL behind it. | [`02-test-file-picker-hang`](10-file-picker/02-test-file-picker-hang.ps1) | `user` | `-TimeoutSegundos` `-Proceso` `-CarpetaInicial` `-Volcado` `-RutaProcdump` `-OutDir` |
| Clears the file picker's remembered folders (ComDlg32 MRU). DryRun by default. | [`03-reset-file-picker-mru`](10-file-picker/03-reset-file-picker-mru.ps1) | `user` | `-Execute` `-IncluirRecientes` `-ReiniciarExplorer` `-Restore` `-BackupDir` |
| Disables shell extensions by CLSID, reversibly. DryRun by default. | [`04-block-shell-extension`](10-file-picker/04-block-shell-extension.ps1) | `admin` | `-Clsid` `-ClsidFile` `-DesdeCsv` `-FiltroDll` `-Quitar` `-Listar` `-Execute` `-ReiniciarExplorer` `-Motivo` `-BackupDir` |
| Read-only. Diagnoses an application crashing when it opens the Open/Save As dialog. | [`05-diagnose-file-picker-crash`](10-file-picker/05-diagnose-file-picker-crash.ps1) | `admin + user` | `-ProcessName` `-OutDir` `-Interactive` `-EnableDumps` `-DryRun` `-SkipSignatures` `-TimeoutSec` |

## <img src=".github/icons/certificate.svg" width="20" height="20" align="top" alt=""> 11 - Certificates

| Function | Script | Run as | Parameters |
|---|---|---|---|
| Repairs one specific certificate AutoFirma cannot list, leaving the rest of the store untouched. | [`01-repair-autofirma-certificate`](11-certificates/01-repair-autofirma-certificate.ps1) | `user` | `-Mode` `-P12` `-Password` `-Match` `-Thumbprint` `-DryRun` `-Force` `-Log` |

## <img src=".github/icons/wrench.svg" width="20" height="20" align="top" alt=""> 99 - Repo tools

| Function | Script | Run as | Parameters |
|---|---|---|---|
| Validates every .ps1 in the repo: ASCII only, UTF-8 with BOM, declared Contexto and syntax on 5.1 and 7. | [`01-validate-scripts`](99-repo-tools/01-validate-scripts.ps1) | `user` | `-Corregir` |
| Sandbox-tests the deletion logic behind the Outlook scripts. Never touches Outlook. | [`02-test-outlook-reset`](99-repo-tools/02-test-outlook-reset.ps1) | `user` | none |
| Rebuilds the index in README.md and README.en.md from each script's .SYNOPSIS. | [`03-generate-readme`](99-repo-tools/03-generate-readme.ps1) | `user` | `-Comprobar` |

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
| `-Mode`, `-P12`, `-Thumbprint` | `11/01` | `Diag` \| `Fix` \| `ResetPrefs`, PKCS#12 file and thumbprint of the certificate to repair |
| `-Fase` | `03/02` | `Reparar` \| `Comprobar` \| `Verificar` |
| `-TargetService`, `-MaxLevel`, `-DiagnosticOnly` | `05/02` | service, max escalation tier, diagnose only |
| `-RutaRespaldo` | `01/02` | backup target when the Desktop is not writable |
| `-ProcessName`, `-EnableDumps`, `-Interactive` | `10/05` | processes to inspect, WER dump of the next crash, real dialog test in 64 and 32 bits |
| `$env:SOPORTE_ORIGEN_PAQUETES` | `05/01`, `06/*` | installer share path |

`paste` mode scripts take no parameters: paste and go. Each script's full parameter list is
in its index row, read from the actual `param()`.

## Execution context

The **Run as** column in the index says which account runs each script:

| Value | How to launch |
|---|---|
| `user` | regular PowerShell, in the affected user's session, **not elevated** |
| `admin` | PowerShell **as administrator**, from the affected user's session |
| `admin + user` | in phases: some elevated, some not; the script's help (`Get-Help -Full`) says which |

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
.\99-repo-tools\01-validate-scripts.ps1      # ASCII, BOM, Contexto and syntax on 5.1 and 7
.\99-repo-tools\03-generate-readme.ps1       # rebuilds the index in both READMEs
```

- ASCII only in code. UTF-8 with BOM.
- PowerShell 5.1 and 7. Windows 10 and 11.
- `-DryRun` or `-WhatIf` on anything that writes.
- `param()`, no hard-coded paths or accounts.
- `.SYNOPSIS` with an `[ES]` line and an `[EN]` line — the README index is built from those.
- Self-contained: no external modules, no certificates.
- `#Requires` separated from the `<#` block by a blank line, or `Get-Help` won't read the synopsis.
- `.NOTES` with a `Contexto: usuario`, `Contexto: admin` or `Contexto: mixto` line — the Run as
  column comes from it. The validator fails if it is missing.
- `00-copy-paste` is the exception: **no help block and no comments**. Descriptions live in
  [`00-copy-paste/index.psd1`](00-copy-paste/index.psd1).

This README's index is generated. Change a script, run the generator, one commit.
