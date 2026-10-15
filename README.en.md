# SCRIPTS-SUPPORT_CX

Endpoint remediation on the user's machine. Self-contained, no dependencies. PowerShell 5.1 and 7, Windows 10 and 11.

🇪🇸 [Español](README.md)

---

<!-- INDICE-INICIO: generado por 99-repo-tools/03-generate-readme.ps1, no editar a mano -->

<img src=".github/icons/clipboard_code.svg" width="20" height="20" align="top" alt=""> [Copy and paste (diagnostics)](#-00---copy-and-paste-diagnostics) | <img src=".github/icons/key.svg" width="20" height="20" align="top" alt=""> [Identity cache](#-01---identity-cache) | <img src=".github/icons/mail.svg" width="20" height="20" align="top" alt=""> [Outlook](#-02---outlook) | <img src=".github/icons/cloud.svg" width="20" height="20" align="top" alt=""> [OneDrive](#-03---onedrive) | <img src=".github/icons/people_team.svg" width="20" height="20" align="top" alt=""> [Teams](#-04---teams) | <img src=".github/icons/apps.svg" width="20" height="20" align="top" alt=""> [Office apps](#-05---office-apps) | <img src=".github/icons/puzzle_piece.svg" width="20" height="20" align="top" alt=""> [Corporate applications](#-06---corporate-applications) | <img src=".github/icons/laptop.svg" width="20" height="20" align="top" alt=""> [Endpoint](#-07---endpoint) | <img src=".github/icons/router.svg" width="20" height="20" align="top" alt=""> [Network](#-08---network) | <img src=".github/icons/document.svg" width="20" height="20" align="top" alt=""> [Documents](#-09---documents) | <img src=".github/icons/folder_open.svg" width="20" height="20" align="top" alt=""> [File picker](#-10---file-picker) | <img src=".github/icons/certificate.svg" width="20" height="20" align="top" alt=""> [Certificates](#-11---certificates) | <img src=".github/icons/wrench.svg" width="20" height="20" align="top" alt=""> [Repo tools](#-99---repo-tools)

## <img src=".github/icons/pin.svg" width="20" height="20" align="top" alt=""> 0 - LAS MAINS

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <img src=".github/icons/key.svg" width="20" height="20" align="top" alt=""> <b>Identity Cache Purge</b></summary>

Clears cached work accounts. Removes them all except the ones you choose to keep.<br>[`01-clear-cached-accounts`](01-identity-cache/01-clear-cached-accounts.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-clear-cached-accounts.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/01-identity-cache/01-clear-cached-accounts.ps1 -OutFile $f; & $f
```

</details>

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <img src=".github/icons/key.svg" width="20" height="20" align="top" alt=""> <b>Stale Tenant Reset</b></summary>

Removes the account left over from an old tenant. Auto-detects the UPN and the tenant.<br>[`02-reset-stale-tenant-v2.1`](01-identity-cache/02-reset-stale-tenant-v2.1.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\02-reset-stale-tenant-v2.1.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/01-identity-cache/02-reset-stale-tenant-v2.1.ps1 -OutFile $f; & $f
```

</details>

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <img src=".github/icons/key.svg" width="20" height="20" align="top" alt=""> <b>Credential Cache Repair</b></summary>

Repairs the Microsoft 365 credential cache in tiers, and can roll the changes back.<br>[`03-repair-credential-cache-with-restore`](01-identity-cache/03-repair-credential-cache-with-restore.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\03-repair-credential-cache-with-restore.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/01-identity-cache/03-repair-credential-cache-with-restore.ps1 -OutFile $f; & $f -Mode Repair -CloseApps
```

</details>

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <img src=".github/icons/cloud.svg" width="20" height="20" align="top" alt=""> <b>OneDrive Long Path Fix</b></summary>

Shortens OneDrive paths over 380 characters ("the path is too long") without renaming the documents.<br>[`03-shorten-long-paths`](03-onedrive/03-shorten-long-paths.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\03-shorten-long-paths.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/03-onedrive/03-shorten-long-paths.ps1 -OutFile $f; & $f
```

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <img src=".github/icons/clipboard_code.svg" width="20" height="20" align="top" alt=""> <b>Endpoint Technical Audit</b></summary>

Hardware, real Windows generation, Entra or domain join, MDM, disk, BitLocker, network and Office<br>[`03-endpoint-report`](00-copy-paste/03-endpoint-report.ps1)

```powershell
[Net.ServicePointManager]::SecurityProtocol=3072; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/00-copy-paste/03-endpoint-report.ps1 | iex
```

</details>

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <img src=".github/icons/cloud.svg" width="20" height="20" align="top" alt=""> <b>OneDrive Tiered Remediation</b></summary>

Fixes OneDrive escalating through 5 tiers: restart, reset, cache, binary and reinstall.<br>[`01-remediate-onedrive-tiered`](03-onedrive/01-remediate-onedrive-tiered.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-remediate-onedrive-tiered.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/03-onedrive/01-remediate-onedrive-tiered.ps1 -OutFile $f; & $f
```

</details>

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <img src=".github/icons/people_team.svg" width="20" height="20" align="top" alt=""> <b>Teams Authentication Reset</b></summary>

Fixes Teams sign-in when it loops or fails to authenticate.<br>[`01-repair-teams-signin`](04-teams/01-repair-teams-signin.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-repair-teams-signin.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/04-teams/01-repair-teams-signin.ps1 -OutFile $f; & $f
```

</details>

## <img src=".github/icons/clipboard_code.svg" width="20" height="20" align="top" alt=""> 00 - Copy and paste (diagnostics)

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Machine snapshot</b></summary>

Hardware, real Windows generation, Entra or domain join, MDM, disk, BitLocker, network and Office<br>[`03-endpoint-report`](00-copy-paste/03-endpoint-report.ps1)

```powershell
[Net.ServicePointManager]::SecurityProtocol=3072; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/00-copy-paste/03-endpoint-report.ps1 | iex
```

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>ESET agent state</b></summary>

Installation, services, binary signature, enrolment read from the trace log and ESET PROTECT connectivity<br>[`06-eset-status`](00-copy-paste/06-eset-status.ps1)

```powershell
[Net.ServicePointManager]::SecurityProtocol=3072; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/00-copy-paste/06-eset-status.ps1 | iex
```

</details>

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>Cached accounts and identities</b></summary>

Cached account inventory: source of each one, GUID UPN detection and real tenantId per domain<br>[`01-cached-accounts`](00-copy-paste/01-cached-accounts.ps1)

```powershell
[Net.ServicePointManager]::SecurityProtocol=3072; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/00-copy-paste/01-cached-accounts.ps1 | iex
```

</details>

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>OneDrive state</b></summary>

Process, version, linked accounts, deny ACEs, write test and log freshness<br>[`02-onedrive-status`](00-copy-paste/02-onedrive-status.ps1)

```powershell
[Net.ServicePointManager]::SecurityProtocol=3072; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/00-copy-paste/02-onedrive-status.ps1 | iex
```

</details>

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>M365 reachability</b></summary>

Proxy, DNS, TCP 443, TLS version and latency across the 7 Microsoft 365 endpoints<br>[`04-m365-connectivity`](00-copy-paste/04-m365-connectivity.ps1)

```powershell
[Net.ServicePointManager]::SecurityProtocol=3072; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/00-copy-paste/04-m365-connectivity.ps1 | iex
```

</details>

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>Office and Outlook state</b></summary>

Version, licence, identities, profiles, .ost and .pst, add-ins and disabled items<br>[`05-office-outlook-status`](00-copy-paste/05-office-outlook-status.ps1)

```powershell
[Net.ServicePointManager]::SecurityProtocol=3072; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/00-copy-paste/05-office-outlook-status.ps1 | iex
```

</details>

## <img src=".github/icons/key.svg" width="20" height="20" align="top" alt=""> 01 - Identity cache

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>Clear cached work accounts</b></summary>

Clears cached work accounts. Removes them all except the ones you choose to keep.<br>[`01-clear-cached-accounts`](01-identity-cache/01-clear-cached-accounts.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-clear-cached-accounts.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/01-identity-cache/01-clear-cached-accounts.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-Excluir` `-Quitar` `-NoCerrarApps` `-Detalle` `-DryRun` `-Force`</sub>

</details>

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>Stale tenant account that keeps coming back</b></summary>

Removes the account left over from an old tenant. Auto-detects the UPN and the tenant.<br>[`02-reset-stale-tenant-v2.1`](01-identity-cache/02-reset-stale-tenant-v2.1.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\02-reset-stale-tenant-v2.1.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/01-identity-cache/02-reset-stale-tenant-v2.1.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-Upn` `-TenantOrigen` `-TenantEsperado` `-RutaRespaldo` `-SoloDetectar` `-NoInteractivo` `-DryRun` `-NoCerrarApps` `-BorrarCookiesEdge` `-QuitarWorkplaceJoin` `-IgnorarPerfil` `-Force`</sub>

</details>

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>Repair M365 credential cache</b></summary>

Repairs the Microsoft 365 credential cache in tiers, and can roll the changes back.<br>[`03-repair-credential-cache-with-restore`](01-identity-cache/03-repair-credential-cache-with-restore.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\03-repair-credential-cache-with-restore.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/01-identity-cache/03-repair-credential-cache-with-restore.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-Mode` `-Accounts` `-Tiers` `-BackupRoot` `-RestoreFrom` `-CloseApps` `-DryRun` `-Force`</sub>

</details>

## <img src=".github/icons/mail.svg" width="20" height="20" align="top" alt=""> 02 - Outlook

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>Rebuild the Outlook profile</b></summary>

Rebuilds the classic Outlook profile keeping .pst and .ost files and recreates it with the same account.<br>[`01-reset-outlook-profile`](02-outlook/01-reset-outlook-profile.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-reset-outlook-profile.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/02-outlook/01-reset-outlook-profile.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-FullReset` `-ClearAutoComplete` `-Email` `-ProfileName` `-NoRecreate` `-WaitSeconds` `-Force` `-WhatIf`</sub>

</details>

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>Full Outlook reset</b></summary>

Aggressive Outlook reset: profile, OST files and autocomplete cache.<br>[`02-full-outlook-reset`](02-outlook/02-full-outlook-reset.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\02-full-outlook-reset.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/02-outlook/02-full-outlook-reset.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-SkipProfileReset` `-SkipOST` `-SkipRoamCache` `-DeleteWholeLocalOutlookFolder` `-WhatIf`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Blank sign-in window in Outlook</b></summary>

Repairs the Microsoft 365 sign-in window that stays blank or stuck on "One moment..." when adding the account in Outlook; with -BorrarCuentasWam removes the work accounts stored in Windows that Teams and Office offer.<br>[`03-repair-signin-window`](02-outlook/03-repair-signin-window.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\03-repair-signin-window.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/02-outlook/03-repair-signin-window.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-SoloDiagnostico` `-BorrarCuentasWam` `-DryRun` `-Force` `-FaseUsuario` `-DirTrabajo`</sub>

</details>

## <img src=".github/icons/cloud.svg" width="20" height="20" align="top" alt=""> 03 - OneDrive

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>OneDrive not syncing or not starting</b></summary>

Fixes OneDrive escalating through 5 tiers: restart, reset, cache, binary and reinstall.<br>[`01-remediate-onedrive-tiered`](03-onedrive/01-remediate-onedrive-tiered.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-remediate-onedrive-tiered.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/03-onedrive/01-remediate-onedrive-tiered.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-MaxLevel` `-LocalInstallerPath` `-StartupWaitSeconds` `-SkipEnvironmentChecks` `-ClearCredentials` `-ForceReinstall`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> + <img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>OneDrive asks for admin rights</b></summary>

Removes deny ACEs left behind by a domain GPO that make OneDrive prompt for admin.<br>[`02-fix-onedrive-permissions`](03-onedrive/02-fix-onedrive-permissions.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\02-fix-onedrive-permissions.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/03-onedrive/02-fix-onedrive-permissions.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-Fase` `-Ruta` `-DryRun`</sub>

</details>

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>OneDrive: path too long</b></summary>

Shortens OneDrive paths over 380 characters ("the path is too long") without renaming the documents.<br>[`03-shorten-long-paths`](03-onedrive/03-shorten-long-paths.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\03-shorten-long-paths.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/03-onedrive/03-shorten-long-paths.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-Ruta` `-Upn` `-Raiz` `-Limite` `-Margen` `-PermitirRecorte` `-MinNombre` `-DryRun` `-SinConfirmar` `-Ascii` `-Revertir`</sub>

</details>

Detailed runbook: [`02-fix-onedrive-permissions.md`](03-onedrive/02-fix-onedrive-permissions.md)

## <img src=".github/icons/people_team.svg" width="20" height="20" align="top" alt=""> 04 - Teams

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>Teams will not sign in</b></summary>

Fixes Teams sign-in when it loops or fails to authenticate.<br>[`01-repair-teams-signin`](04-teams/01-repair-teams-signin.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-repair-teams-signin.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/04-teams/01-repair-teams-signin.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-DryRun` `-Force` `-Aggressive` `-IncludeOutlook` `-RepairTeams` `-LogPath`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Teams button missing in Outlook</b></summary>

Restores the Teams meeting button when it disappears from classic Outlook.<br>[`02-repair-teams-outlook-addin`](04-teams/02-repair-teams-outlook-addin.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\02-repair-teams-outlook-addin.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/04-teams/02-repair-teams-outlook-addin.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-User`</sub>

</details>

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>Teams Outlook add-in keeps turning off</b></summary>

Re-registers the Teams meeting add-in in classic Outlook and hardens it.<br>[`03-repair-teams-addin-com`](04-teams/03-repair-teams-addin-com.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\03-repair-teams-addin-com.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/04-teams/03-repair-teams-addin-com.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-NoKillOutlook`</sub>

</details>

## <img src=".github/icons/apps.svg" width="20" height="20" align="top" alt=""> 05 - Office apps

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Repair the Office install</b></summary>

Repairs the Office installation: quick or online repair, plus reactivation.<br>[`01-repair-office-install`](05-office-apps/01-repair-office-install.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-repair-office-install.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/05-office-apps/01-repair-office-install.ps1 -OutFile $f; & $f
```

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Automatic M365 repair</b></summary>

Unattended engine that diagnoses and repairs OneDrive, Outlook, Office, identity and network.<br>[`02-m365-remediation-engine`](05-office-apps/02-m365-remediation-engine.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\02-m365-remediation-engine.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/05-office-apps/02-m365-remediation-engine.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-TargetService` `-MaxLevel` `-DiagnosticOnly` `-LogPath`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Install or repair Ricoh and Canon printers</b></summary>

PrintDeploy: installs and repairs Ricoh and Canon printers, auto-detects the model and enables the bypass tray.<br>[`03-printdeploy`](05-office-apps/03-printdeploy)

```powershell
dotnet build -c Release .\05-office-apps\03-printdeploy\PrintDeploy.csproj
```

</details>

## <img src=".github/icons/puzzle_piece.svg" width="20" height="20" align="top" alt=""> 06 - Corporate applications

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>ESET not installed, running or connecting</b></summary>

Explains why ESET Endpoint is missing, not starting or not reaching the console.<br>[`01-diagnose-eset`](06-applications/01-diagnose-eset.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-diagnose-eset.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/06-applications/01-diagnose-eset.ps1 -OutFile $f; & $f
```

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Install ESET</b></summary>

Installs ESET Endpoint unattended, even when the installer has no silent mode.<br>[`02-install-eset`](06-applications/02-install-eset.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\02-install-eset.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/06-applications/02-install-eset.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-Modo`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Uninstall iManage</b></summary>

Fully uninstalls iManage Work Desktop along with its Office add-ins.<br>[`03-uninstall-imanage`](06-applications/03-uninstall-imanage.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\03-uninstall-imanage.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/06-applications/03-uninstall-imanage.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-WhatIf`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Install PDFelement and iManage</b></summary>

Installs PDFelement and iManage by driving their wizard, which has no silent mode.<br>[`04-install-pdfelement-imanage`](06-applications/04-install-pdfelement-imanage.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\04-install-pdfelement-imanage.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/06-applications/04-install-pdfelement-imanage.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-Modo`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Which silent switches an installer takes</b></summary>

Inspects an installer package and reports its type and supported silent switches.<br>[`05-diagnose-installers`](06-applications/05-diagnose-installers.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\05-diagnose-installers.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/06-applications/05-diagnose-installers.ps1 -OutFile $f; & $f
```

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> + <img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>Repair Mitel Connect / MiCollab</b></summary>

Repairs the Mitel Connect / MiCollab client: cache, registry, Outlook, credentials and DNS.<br>[`06-repair-mitel-client`](06-applications/06-repair-mitel-client.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\06-repair-mitel-client.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/06-applications/06-repair-mitel-client.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-DryRun` `-Force` `-AllUsers` `-KeepOutlookAddin` `-DisableOutlookAddin` `-KeepCredentials` `-ServerHost` `-FixDns` `-DnsServers` `-DnsSuffix` `-FixHosts` `-FixFirewall` `-Reinstall` `-LogPath`</sub>

</details>

## <img src=".github/icons/laptop.svg" width="20" height="20" align="top" alt=""> 07 - Endpoint

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Disk full</b></summary>

What is filling the disk: largest folders and reclaimable junk.<br>[`01-disk-usage`](07-endpoint/01-disk-usage.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-disk-usage.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/07-endpoint/01-disk-usage.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-Ruta` `-Top` `-SoloBasura`</sub>

</details>

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>BitLocker recovery key</b></summary>

Retrieves the BitLocker recovery key by serial number, device name or Entra device id.<br>[`02-bitlocker-recovery-key`](07-endpoint/02-bitlocker-recovery-key.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\02-bitlocker-recovery-key.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/07-endpoint/02-bitlocker-recovery-key.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-Serie` `-Nombre` `-DeviceId` `-RutaCsv` `-ConfigPath`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Unexpected shutdowns or restarts</b></summary>

Diagnoses and fixes unexpected shutdowns and restarts.<br>[`03-fix-random-shutdowns`](07-endpoint/03-fix-random-shutdowns.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\03-fix-random-shutdowns.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/07-endpoint/03-fix-random-shutdowns.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-SkipDiag` `-SkipWifi`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Wrong clock: e-signature portals fail</b></summary>

Gets the clock back in sync so e-government signing works: detects location, matches time zone and country NTP servers, and repairs W32Time.<br>[`04-repair-time-sync`](07-endpoint/04-repair-time-sync.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\04-repair-time-sync.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/07-endpoint/04-repair-time-sync.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-DryRun` `-Force` `-DiagnoseOnly` `-TimeZoneId` `-NtpServers` `-SkipGeo` `-NoTimeZoneChange` `-PersistPublicNtp` `-AllowStepTime` `-NoStepTime` `-AutoTimeZoneService` `-PollSeconds` `-LogPath`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Enable Windows long paths</b></summary>

Enables Windows long paths (over 260 characters) and disables 8.3 short names.<br>[`05-enable-long-paths`](07-endpoint/05-enable-long-paths.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\05-enable-long-paths.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/07-endpoint/05-enable-long-paths.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-DryRun`</sub>

</details>

## <img src=".github/icons/router.svg" width="20" height="20" align="top" alt=""> 08 - Network

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Slow or dropping Wi-Fi</b></summary>

Disables Wi-Fi adapter power saving and switches to the high performance power plan.<br>[`01-optimize-wifi-adapter`](08-network/01-optimize-wifi-adapter.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-optimize-wifi-adapter.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/08-network/01-optimize-wifi-adapter.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-Adaptador` `-DryRun`</sub>

</details>

## <img src=".github/icons/document.svg" width="20" height="20" align="top" alt=""> 09 - Documents

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>Protected Word file, password lost</b></summary>

Removes edit protection from a Word document when the password is lost.<br>[`01-unlock-protected-word`](09-documents/01-unlock-protected-word.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-unlock-protected-word.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/09-documents/01-unlock-protected-word.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-NoPause` `-Paths`</sub>

</details>

## <img src=".github/icons/folder_open.svg" width="20" height="20" align="top" alt=""> 10 - File picker

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>File picker: diagnosis</b></summary>

Read-only. Inventory of everything that can hang the Windows file picker.<br>[`01-diagnose-file-picker`](10-file-picker/01-diagnose-file-picker.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-diagnose-file-picker.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/10-file-picker/01-diagnose-file-picker.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-OutDir` `-DiasEventos` `-TimeoutRutaSegundos` `-SinFirmas`</sub>

</details>

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>File picker hangs</b></summary>

Read-only. Reproduces the file picker hang and captures the DLL behind it.<br>[`02-test-file-picker-hang`](10-file-picker/02-test-file-picker-hang.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\02-test-file-picker-hang.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/10-file-picker/02-test-file-picker-hang.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-TimeoutSegundos` `-Proceso` `-CarpetaInicial` `-Volcado` `-RutaProcdump` `-OutDir`</sub>

</details>

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>Clear file picker recent folders</b></summary>

Clears the file picker's remembered folders (ComDlg32 MRU). DryRun by default.<br>[`03-reset-file-picker-mru`](10-file-picker/03-reset-file-picker-mru.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\03-reset-file-picker-mru.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/10-file-picker/03-reset-file-picker-mru.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-Execute` `-IncluirRecientes` `-ReiniciarExplorer` `-Restore` `-BackupDir`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Block a shell extension</b></summary>

Disables shell extensions by CLSID, reversibly. DryRun by default.<br>[`04-block-shell-extension`](10-file-picker/04-block-shell-extension.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\04-block-shell-extension.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/10-file-picker/04-block-shell-extension.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-Clsid` `-ClsidFile` `-DesdeCsv` `-FiltroDll` `-Quitar` `-Listar` `-Execute` `-ReiniciarExplorer` `-Motivo` `-BackupDir`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> + <img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>App crashes on Open or Save as</b></summary>

Read-only. Diagnoses an application crashing when it opens the Open/Save As dialog.<br>[`05-diagnose-file-picker-crash`](10-file-picker/05-diagnose-file-picker-crash.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\05-diagnose-file-picker-crash.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/10-file-picker/05-diagnose-file-picker-crash.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-ProcessName` `-OutDir` `-Interactive` `-EnableDumps` `-DryRun` `-SkipSignatures` `-TimeoutSec`</sub>

</details>

## <img src=".github/icons/certificate.svg" width="20" height="20" align="top" alt=""> 11 - Certificates

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>AutoFirma does not list the certificate</b></summary>

Repairs one specific certificate AutoFirma cannot list, leaving the rest of the store untouched.<br>[`01-repair-autofirma-certificate`](11-certificates/01-repair-autofirma-certificate.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-repair-autofirma-certificate.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/11-certificates/01-repair-autofirma-certificate.ps1 -OutFile $f; & $f
```
<sub>Parameters: `-Mode` `-P12` `-Password` `-Match` `-Thumbprint` `-DryRun` `-Force` `-Log`</sub>

</details>

## <img src=".github/icons/wrench.svg" width="20" height="20" align="top" alt=""> 99 - Repo tools

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>Validate repo scripts</b></summary>

Validates every .ps1 in the repo: ASCII only, UTF-8 with BOM, declared Contexto and syntax on 5.1 and 7.<br>[`01-validate-scripts`](99-repo-tools/01-validate-scripts.ps1)

```powershell
.\99-repo-tools\01-validate-scripts.ps1
```
<sub>Parameters: `-Corregir`</sub>

</details>

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>Test the Outlook reset in a sandbox</b></summary>

Sandbox-tests the deletion logic behind the Outlook scripts. Never touches Outlook.<br>[`02-test-outlook-reset`](99-repo-tools/02-test-outlook-reset.ps1)

```powershell
.\99-repo-tools\02-test-outlook-reset.ps1
```

</details>

<details><summary><img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> <b>Rebuild the READMEs</b></summary>

Rebuilds the index in README.md and README.en.md from each script's .SYNOPSIS.<br>[`03-generate-readme`](99-repo-tools/03-generate-readme.ps1)

```powershell
.\99-repo-tools\03-generate-readme.ps1
```
<sub>Parameters: `-Comprobar`</sub>

</details>

<!-- INDICE-FIN -->

---

## Parameters and execution

One line per script, to paste into the user's console. It downloads from `main` to `%TEMP%`,
opens the execution policy **for that process only** and runs it; same in PowerShell 5.1 and 7.
Parameters go at the end, after `& $f`:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\<script>.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/<folder>/<script>.ps1 -OutFile $f; & $f -DryRun
```

`00-copy-paste` scripts take no parameters and run in memory (`irm <url> | iex`).
With the file already on the machine:

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
in its index entry, read from the actual `param()`.

## Execution context

The colour label on each script in the index says which console runs it:

| Value | How to launch |
|---|---|
| <img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> | regular PowerShell, in the affected user's session, **not elevated** |
| <img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> | PowerShell **as administrator**, from the affected user's session |
| <img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> + <img src=".github/icons/badge-user.svg" height="20" align="top" alt="user"> | in phases: some elevated, some not; the script's help (`Get-Help -Full`) says which |

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
