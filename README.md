# SCRIPTS-SUPPORT_CX

🇬🇧 [English](README.en.md)

---

<!-- INDICE-INICIO: generado por 99-repo-tools/03-generate-readme.ps1, no editar a mano -->

<img src=".github/icons/clipboard_code.svg" width="20" height="20" align="top" alt=""> [Copy and paste (diagnostics)](#-00---copy-and-paste-diagnostics) | <img src=".github/icons/key.svg" width="20" height="20" align="top" alt=""> [Identity cache](#-01---identity-cache) | <img src=".github/icons/mail.svg" width="20" height="20" align="top" alt=""> [Outlook](#-02---outlook) | <img src=".github/icons/cloud.svg" width="20" height="20" align="top" alt=""> [OneDrive](#-03---onedrive) | <img src=".github/icons/people_team.svg" width="20" height="20" align="top" alt=""> [Teams](#-04---teams) | <img src=".github/icons/apps.svg" width="20" height="20" align="top" alt=""> [Office apps](#-05---office-apps) | <img src=".github/icons/puzzle_piece.svg" width="20" height="20" align="top" alt=""> [Corporate applications](#-06---corporate-applications) | <img src=".github/icons/laptop.svg" width="20" height="20" align="top" alt=""> [Endpoint](#-07---endpoint) | <img src=".github/icons/router.svg" width="20" height="20" align="top" alt=""> [Network](#-08---network) | <img src=".github/icons/document.svg" width="20" height="20" align="top" alt=""> [Documents](#-09---documents) | <img src=".github/icons/folder_open.svg" width="20" height="20" align="top" alt=""> [File picker](#-10---file-picker) | <img src=".github/icons/certificate.svg" width="20" height="20" align="top" alt=""> [Certificates](#-11---certificates) | <img src=".github/icons/wrench.svg" width="20" height="20" align="top" alt=""> [Repo tools](#-99---repo-tools)

## <img src=".github/icons/pin.svg" width="20" height="20" align="top" alt=""> 0 - LAS MAINS

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <img src=".github/icons/key.svg" width="20" height="20" align="top" alt=""> <b>Identity Cache Purge</b></summary>

Borra las cuentas de trabajo cacheadas. Las quita todas salvo las que decidas conservar.<br>[`01-clear-cached-accounts`](01-identity-cache/01-clear-cached-accounts.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-clear-cached-accounts.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/01-identity-cache/01-clear-cached-accounts.ps1 -OutFile $f; & $f
```

</details>

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <img src=".github/icons/key.svg" width="20" height="20" align="top" alt=""> <b>Stale Tenant Reset</b></summary>

Quita la cuenta que sobrevive de un tenant antiguo. Detecta sola el UPN y el tenant.<br>[`02-reset-stale-tenant-v2.1`](01-identity-cache/02-reset-stale-tenant-v2.1.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\02-reset-stale-tenant-v2.1.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/01-identity-cache/02-reset-stale-tenant-v2.1.ps1 -OutFile $f; & $f
```

</details>

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <img src=".github/icons/key.svg" width="20" height="20" align="top" alt=""> <b>Credential Cache Repair</b></summary>

Repara la caché de credenciales de Microsoft 365 por niveles, y sabe deshacer los cambios.<br>[`03-repair-credential-cache-with-restore`](01-identity-cache/03-repair-credential-cache-with-restore.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\03-repair-credential-cache-with-restore.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/01-identity-cache/03-repair-credential-cache-with-restore.ps1 -OutFile $f; & $f -Mode Repair -CloseApps
```

</details>

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <img src=".github/icons/cloud.svg" width="20" height="20" align="top" alt=""> <b>OneDrive Long Path Fix</b></summary>

Acorta las rutas de OneDrive de mas de 380 caracteres ("la ruta es demasiado larga") sin tocar el nombre de los documentos.<br>[`03-shorten-long-paths`](03-onedrive/03-shorten-long-paths.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\03-shorten-long-paths.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/03-onedrive/03-shorten-long-paths.ps1 -OutFile $f; & $f
```

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <img src=".github/icons/clipboard_code.svg" width="20" height="20" align="top" alt=""> <b>Endpoint Technical Audit</b></summary>

Hardware, generación real de Windows, join a Entra o dominio, MDM, disco, BitLocker, red y Office<br>[`03-endpoint-report`](00-copy-paste/03-endpoint-report.ps1)

```powershell
[Net.ServicePointManager]::SecurityProtocol=3072; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/00-copy-paste/03-endpoint-report.ps1 | iex
```

</details>

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <img src=".github/icons/cloud.svg" width="20" height="20" align="top" alt=""> <b>OneDrive Tiered Remediation</b></summary>

Arregla OneDrive subiendo por 5 niveles: reinicio, reset, caché, binario y reinstalación.<br>[`01-remediate-onedrive-tiered`](03-onedrive/01-remediate-onedrive-tiered.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-remediate-onedrive-tiered.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/03-onedrive/01-remediate-onedrive-tiered.ps1 -OutFile $f; & $f
```

</details>

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <img src=".github/icons/people_team.svg" width="20" height="20" align="top" alt=""> <b>Teams Authentication Reset</b></summary>

Arregla el inicio de sesión de Teams cuando se queda en bucle o no autentica.<br>[`01-repair-teams-signin`](04-teams/01-repair-teams-signin.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-repair-teams-signin.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/04-teams/01-repair-teams-signin.ps1 -OutFile $f; & $f
```

</details>

## <img src=".github/icons/clipboard_code.svg" width="20" height="20" align="top" alt=""> 00 - Copy and paste (diagnostics)

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Ficha técnica del equipo</b></summary>

Hardware, generación real de Windows, join a Entra o dominio, MDM, disco, BitLocker, red y Office<br>[`03-endpoint-report`](00-copy-paste/03-endpoint-report.ps1)

```powershell
[Net.ServicePointManager]::SecurityProtocol=3072; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/00-copy-paste/03-endpoint-report.ps1 | iex
```

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Estado del agente ESET</b></summary>

Instalación, servicios, firma del binario, enrolamiento leído del trace y conectividad con ESET PROTECT<br>[`06-eset-status`](00-copy-paste/06-eset-status.ps1)

```powershell
[Net.ServicePointManager]::SecurityProtocol=3072; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/00-copy-paste/06-eset-status.ps1 | iex
```

</details>

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>Cuentas cacheadas e identidades</b></summary>

Inventario de cuentas cacheadas: origen de cada una, detección de UPN GUID y tenantId real de cada dominio<br>[`01-cached-accounts`](00-copy-paste/01-cached-accounts.ps1)

```powershell
[Net.ServicePointManager]::SecurityProtocol=3072; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/00-copy-paste/01-cached-accounts.ps1 | iex
```

</details>

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>Estado de OneDrive</b></summary>

Proceso, versión, cuentas vinculadas, ACE de denegación, prueba de escritura y frescura de los logs<br>[`02-onedrive-status`](00-copy-paste/02-onedrive-status.ps1)

```powershell
[Net.ServicePointManager]::SecurityProtocol=3072; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/00-copy-paste/02-onedrive-status.ps1 | iex
```

</details>

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>Conectividad con M365</b></summary>

Proxy, DNS, TCP 443, versión de TLS y latencia contra los 7 endpoints de Microsoft 365<br>[`04-m365-connectivity`](00-copy-paste/04-m365-connectivity.ps1)

```powershell
[Net.ServicePointManager]::SecurityProtocol=3072; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/00-copy-paste/04-m365-connectivity.ps1 | iex
```

</details>

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>Estado de Office y Outlook</b></summary>

Versión, licencia, identidades, perfiles, .ost y .pst, complementos y elementos deshabilitados<br>[`05-office-outlook-status`](00-copy-paste/05-office-outlook-status.ps1)

```powershell
[Net.ServicePointManager]::SecurityProtocol=3072; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/00-copy-paste/05-office-outlook-status.ps1 | iex
```

</details>

## <img src=".github/icons/key.svg" width="20" height="20" align="top" alt=""> 01 - Identity cache

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>Borrar cuentas de trabajo cacheadas</b></summary>

Borra las cuentas de trabajo cacheadas. Las quita todas salvo las que decidas conservar.<br>[`01-clear-cached-accounts`](01-identity-cache/01-clear-cached-accounts.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-clear-cached-accounts.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/01-identity-cache/01-clear-cached-accounts.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-Excluir` `-Quitar` `-NoCerrarApps` `-Detalle` `-DryRun` `-Force`</sub>

</details>

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>Cuenta de un tenant antiguo que no se va</b></summary>

Quita la cuenta que sobrevive de un tenant antiguo. Detecta sola el UPN y el tenant.<br>[`02-reset-stale-tenant-v2.1`](01-identity-cache/02-reset-stale-tenant-v2.1.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\02-reset-stale-tenant-v2.1.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/01-identity-cache/02-reset-stale-tenant-v2.1.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-Upn` `-TenantOrigen` `-TenantEsperado` `-RutaRespaldo` `-SoloDetectar` `-NoInteractivo` `-DryRun` `-NoCerrarApps` `-BorrarCookiesEdge` `-QuitarWorkplaceJoin` `-IgnorarPerfil` `-Force`</sub>

</details>

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>Reparar caché de credenciales M365</b></summary>

Repara la caché de credenciales de Microsoft 365 por niveles, y sabe deshacer los cambios.<br>[`03-repair-credential-cache-with-restore`](01-identity-cache/03-repair-credential-cache-with-restore.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\03-repair-credential-cache-with-restore.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/01-identity-cache/03-repair-credential-cache-with-restore.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-Mode` `-Accounts` `-Tiers` `-BackupRoot` `-RestoreFrom` `-CloseApps` `-DryRun` `-Force`</sub>

</details>

## <img src=".github/icons/mail.svg" width="20" height="20" align="top" alt=""> 02 - Outlook

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>Rehacer el perfil de Outlook</b></summary>

Rehace el perfil de Outlook clásico conservando los .pst y .ost y lo recrea con la misma cuenta.<br>[`01-reset-outlook-profile`](02-outlook/01-reset-outlook-profile.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-reset-outlook-profile.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/02-outlook/01-reset-outlook-profile.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-FullReset` `-ClearAutoComplete` `-Email` `-ProfileName` `-NoRecreate` `-WaitSeconds` `-Force` `-WhatIf`</sub>

</details>

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>Reset completo de Outlook</b></summary>

Reset agresivo de Outlook: perfil, OST y caché de autocompletado.<br>[`02-full-outlook-reset`](02-outlook/02-full-outlook-reset.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\02-full-outlook-reset.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/02-outlook/02-full-outlook-reset.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-SkipProfileReset` `-SkipOST` `-SkipRoamCache` `-DeleteWholeLocalOutlookFolder` `-WhatIf`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Ventana de login en blanco en Outlook</b></summary>

Repara la ventana de inicio de sesión de Microsoft 365 que se queda en blanco o en "Un momento..." al agregar la cuenta en Outlook; con -BorrarCuentasWam quita las cuentas de trabajo guardadas en Windows que ofrecen Teams y Office.<br>[`03-repair-signin-window`](02-outlook/03-repair-signin-window.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\03-repair-signin-window.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/02-outlook/03-repair-signin-window.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-SoloDiagnostico` `-BorrarCuentasWam` `-DryRun` `-Force` `-FaseUsuario` `-DirTrabajo`</sub>

</details>

## <img src=".github/icons/cloud.svg" width="20" height="20" align="top" alt=""> 03 - OneDrive

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>OneDrive no sincroniza o no arranca</b></summary>

Arregla OneDrive subiendo por 5 niveles: reinicio, reset, caché, binario y reinstalación.<br>[`01-remediate-onedrive-tiered`](03-onedrive/01-remediate-onedrive-tiered.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-remediate-onedrive-tiered.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/03-onedrive/01-remediate-onedrive-tiered.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-MaxLevel` `-LocalInstallerPath` `-StartupWaitSeconds` `-SkipEnvironmentChecks` `-ClearCredentials` `-ForceReinstall`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> + <img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>OneDrive pide permisos de administrador</b></summary>

Quita las ACE de denegación que dejó una GPO de dominio y hacen que OneDrive pida admin.<br>[`02-fix-onedrive-permissions`](03-onedrive/02-fix-onedrive-permissions.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\02-fix-onedrive-permissions.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/03-onedrive/02-fix-onedrive-permissions.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-Fase` `-Ruta` `-DryRun`</sub>

</details>

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>OneDrive: la ruta es demasiado larga</b></summary>

Acorta las rutas de OneDrive de mas de 380 caracteres ("la ruta es demasiado larga") sin tocar el nombre de los documentos.<br>[`03-shorten-long-paths`](03-onedrive/03-shorten-long-paths.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\03-shorten-long-paths.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/03-onedrive/03-shorten-long-paths.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-Ruta` `-Upn` `-Raiz` `-Limite` `-Margen` `-PermitirRecorte` `-MinNombre` `-DryRun` `-SinConfirmar` `-Ascii` `-Revertir`</sub>

</details>

Runbook detallado: [`02-fix-onedrive-permissions.md`](03-onedrive/02-fix-onedrive-permissions.md)

## <img src=".github/icons/people_team.svg" width="20" height="20" align="top" alt=""> 04 - Teams

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>Teams no inicia sesión</b></summary>

Arregla el inicio de sesión de Teams cuando se queda en bucle o no autentica.<br>[`01-repair-teams-signin`](04-teams/01-repair-teams-signin.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-repair-teams-signin.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/04-teams/01-repair-teams-signin.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-DryRun` `-Force` `-Aggressive` `-IncludeOutlook` `-RepairTeams` `-LogPath`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Falta el botón de Teams en Outlook</b></summary>

Recupera el botón de reunión de Teams cuando desaparece de Outlook (clásico).<br>[`02-repair-teams-outlook-addin`](04-teams/02-repair-teams-outlook-addin.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\02-repair-teams-outlook-addin.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/04-teams/02-repair-teams-outlook-addin.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-User`</sub>

</details>

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>Complemento de Teams en Outlook se desactiva</b></summary>

Re-registra el complemento de reunión de Teams en Outlook clásico y lo blinda.<br>[`03-repair-teams-addin-com`](04-teams/03-repair-teams-addin-com.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\03-repair-teams-addin-com.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/04-teams/03-repair-teams-addin-com.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-NoKillOutlook`</sub>

</details>

## <img src=".github/icons/apps.svg" width="20" height="20" align="top" alt=""> 05 - Office apps

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Reparar la instalación de Office</b></summary>

Repara la instalación de Office: reparación rápida u online, y reactivación.<br>[`01-repair-office-install`](05-office-apps/01-repair-office-install.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-repair-office-install.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/05-office-apps/01-repair-office-install.ps1 -OutFile $f; & $f
```

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Reparación automática de M365</b></summary>

Motor desatendido que diagnostica y repara OneDrive, Outlook, Office, identidad y red.<br>[`02-m365-remediation-engine`](05-office-apps/02-m365-remediation-engine.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\02-m365-remediation-engine.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/05-office-apps/02-m365-remediation-engine.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-TargetService` `-MaxLevel` `-DiagnosticOnly` `-LogPath`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Instalar o reparar impresoras Ricoh y Canon</b></summary>

PrintDeploy: escanea la red, ve qué impresoras responden e instala Ricoh, Canon y colas de servidor con el driver correcto.<br>[`03-printdeploy`](05-office-apps/03-printdeploy)

```powershell
dotnet build -c Release .\05-office-apps\03-printdeploy\PrintDeploy.csproj
```

</details>

## <img src=".github/icons/puzzle_piece.svg" width="20" height="20" align="top" alt=""> 06 - Corporate applications

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>ESET no instala, no arranca o no conecta</b></summary>

Dice por qué ESET Endpoint no está instalado, no arranca o no se conecta a la consola.<br>[`01-diagnose-eset`](06-applications/01-diagnose-eset.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-diagnose-eset.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/06-applications/01-diagnose-eset.ps1 -OutFile $f; & $f
```

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Instalar ESET</b></summary>

Instala ESET Endpoint sin asistencia, incluso cuando el instalador no admite modo silencioso.<br>[`02-install-eset`](06-applications/02-install-eset.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\02-install-eset.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/06-applications/02-install-eset.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-Modo`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Desinstalar iManage</b></summary>

Desinstala iManage Work Desktop por completo, con sus complementos de Office.<br>[`03-uninstall-imanage`](06-applications/03-uninstall-imanage.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\03-uninstall-imanage.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/06-applications/03-uninstall-imanage.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-WhatIf`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Instalar PDFelement e iManage</b></summary>

Instala PDFelement e iManage automatizando su asistente, que no admite modo silencioso.<br>[`04-install-pdfelement-imanage`](06-applications/04-install-pdfelement-imanage.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\04-install-pdfelement-imanage.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/06-applications/04-install-pdfelement-imanage.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-Modo`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Parámetros silenciosos de un instalador</b></summary>

Analiza un paquete de instalación y dice qué tipo es y qué parámetros silenciosos admite.<br>[`05-diagnose-installers`](06-applications/05-diagnose-installers.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\05-diagnose-installers.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/06-applications/05-diagnose-installers.ps1 -OutFile $f; & $f
```

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> + <img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>Reparar Mitel Connect / MiCollab</b></summary>

Repara el cliente Mitel Connect / MiCollab: caché, registro, Outlook, credenciales y DNS.<br>[`06-repair-mitel-client`](06-applications/06-repair-mitel-client.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\06-repair-mitel-client.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/06-applications/06-repair-mitel-client.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-DryRun` `-Force` `-AllUsers` `-KeepOutlookAddin` `-DisableOutlookAddin` `-KeepCredentials` `-ServerHost` `-FixDns` `-DnsServers` `-DnsSuffix` `-FixHosts` `-FixFirewall` `-Reinstall` `-LogPath`</sub>

</details>

## <img src=".github/icons/laptop.svg" width="20" height="20" align="top" alt=""> 07 - Endpoint

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Disco lleno</b></summary>

Qué está ocupando el disco: carpetas más grandes y basura que se puede recuperar.<br>[`01-disk-usage`](07-endpoint/01-disk-usage.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-disk-usage.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/07-endpoint/01-disk-usage.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-Ruta` `-Top` `-SoloBasura`</sub>

</details>

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>Clave de recuperación de BitLocker</b></summary>

Saca la clave de recuperación de BitLocker por número de serie, nombre o id de dispositivo.<br>[`02-bitlocker-recovery-key`](07-endpoint/02-bitlocker-recovery-key.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\02-bitlocker-recovery-key.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/07-endpoint/02-bitlocker-recovery-key.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-Serie` `-Nombre` `-DeviceId` `-RutaCsv` `-ConfigPath`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Apagados o reinicios inesperados</b></summary>

Diagnostica y corrige apagados y reinicios inesperados del equipo.<br>[`03-fix-random-shutdowns`](07-endpoint/03-fix-random-shutdowns.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\03-fix-random-shutdowns.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/07-endpoint/03-fix-random-shutdowns.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-SkipDiag` `-SkipWifi`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Hora mal: no deja firmar en sedes electrónicas</b></summary>

Deja el reloj en hora para poder firmar en sedes electrónicas: detecta la ubicación, empareja zona horaria y NTP del país, y repara W32Time.<br>[`04-repair-time-sync`](07-endpoint/04-repair-time-sync.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\04-repair-time-sync.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/07-endpoint/04-repair-time-sync.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-DryRun` `-Force` `-DiagnoseOnly` `-TimeZoneId` `-NtpServers` `-SkipGeo` `-NoTimeZoneChange` `-PersistPublicNtp` `-AllowStepTime` `-NoStepTime` `-AutoTimeZoneService` `-PollSeconds` `-LogPath`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Activar rutas largas de Windows</b></summary>

Activa las rutas largas de Windows (mas de 260 caracteres) y desactiva los nombres cortos 8.3.<br>[`05-enable-long-paths`](07-endpoint/05-enable-long-paths.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\05-enable-long-paths.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/07-endpoint/05-enable-long-paths.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-DryRun`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Equipo sin administrador (rescate desde WinRE)</b></summary>

Devuelve una cuenta local al grupo Administradores cuando el equipo se ha quedado sin ningún administrador. No borra datos; se ejecuta desde la recuperación de Windows (WinRE), no por `irm`.<br>[`06-rescate-admin-local`](07-endpoint/06-rescate-admin-local.bat) · [guía](07-endpoint/06-rescate-admin-local.md)

```
Login > Mayús+Reiniciar > Solucionar problemas > Opciones avanzadas > Símbolo del sistema
Copia el .bat a un USB.  Letra:  wmic logicaldisk get deviceid,volumename
Ejecuta (letra del USB, p.ej. E:):  E:\06-rescate-admin-local.bat
Cuando diga [4/4] LISTO:  exit  y  Continuar.  Entra con tu cuenta, ya admin.
```
<sub>Cuentas: `set "CUENTAS=Usuario User usuario"` (editable en el .bat). Método manual y BitLocker en la guía.</sub>

</details>

## <img src=".github/icons/router.svg" width="20" height="20" align="top" alt=""> 08 - Network

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Wi-Fi lenta o que se corta</b></summary>

Quita el ahorro de energía de la tarjeta Wi-Fi y pone el plan de alto rendimiento.<br>[`01-optimize-wifi-adapter`](08-network/01-optimize-wifi-adapter.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-optimize-wifi-adapter.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/08-network/01-optimize-wifi-adapter.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-Adaptador` `-DryRun`</sub>

</details>

## <img src=".github/icons/document.svg" width="20" height="20" align="top" alt=""> 09 - Documents

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>Word protegido y sin contraseña</b></summary>

Quita la protección de edición de un documento de Word cuando se perdió la contraseña.<br>[`01-unlock-protected-word`](09-documents/01-unlock-protected-word.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-unlock-protected-word.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/09-documents/01-unlock-protected-word.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-NoPause` `-Paths`</sub>

</details>

## <img src=".github/icons/folder_open.svg" width="20" height="20" align="top" alt=""> 10 - File picker

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>Selector de archivos: diagnóstico</b></summary>

Solo lectura. Inventario de todo lo que puede colgar el selector de archivos de Windows.<br>[`01-diagnose-file-picker`](10-file-picker/01-diagnose-file-picker.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-diagnose-file-picker.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/10-file-picker/01-diagnose-file-picker.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-OutDir` `-DiasEventos` `-TimeoutRutaSegundos` `-SinFirmas`</sub>

</details>

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>Selector de archivos se cuelga</b></summary>

Solo lectura. Reproduce el cuelgue del selector y captura el DLL que lo provoca.<br>[`02-test-file-picker-hang`](10-file-picker/02-test-file-picker-hang.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\02-test-file-picker-hang.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/10-file-picker/02-test-file-picker-hang.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-TimeoutSegundos` `-Proceso` `-CarpetaInicial` `-Volcado` `-RutaProcdump` `-OutDir`</sub>

</details>

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>Limpiar carpetas recientes del selector</b></summary>

Limpia la memoria de carpetas del selector de archivos (ComDlg32 MRU). DryRun por defecto.<br>[`03-reset-file-picker-mru`](10-file-picker/03-reset-file-picker-mru.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\03-reset-file-picker-mru.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/10-file-picker/03-reset-file-picker-mru.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-Execute` `-IncluirRecientes` `-ReiniciarExplorer` `-Restore` `-BackupDir`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> <b>Bloquear una extensión de shell</b></summary>

Desactiva extensiones de shell por CLSID de forma reversible. DryRun por defecto.<br>[`04-block-shell-extension`](10-file-picker/04-block-shell-extension.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\04-block-shell-extension.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/10-file-picker/04-block-shell-extension.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-Clsid` `-ClsidFile` `-DesdeCsv` `-FiltroDll` `-Quitar` `-Listar` `-Execute` `-ReiniciarExplorer` `-Motivo` `-BackupDir`</sub>

</details>

<details><summary><img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> + <img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>La app se cierra al Abrir o Guardar como</b></summary>

Solo lectura. Diagnóstico del crash de una aplicación al abrir el diálogo Abrir/Guardar como.<br>[`05-diagnose-file-picker-crash`](10-file-picker/05-diagnose-file-picker-crash.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\05-diagnose-file-picker-crash.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/10-file-picker/05-diagnose-file-picker-crash.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-ProcessName` `-OutDir` `-Interactive` `-EnableDumps` `-DryRun` `-SkipSignatures` `-TimeoutSec`</sub>

</details>

## <img src=".github/icons/certificate.svg" width="20" height="20" align="top" alt=""> 11 - Certificates

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>AutoFirma no muestra el certificado</b></summary>

Repara un certificado concreto que AutoFirma no lista, sin tocar el resto del almacén.<br>[`01-repair-autofirma-certificate`](11-certificates/01-repair-autofirma-certificate.ps1)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\01-repair-autofirma-certificate.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/11-certificates/01-repair-autofirma-certificate.ps1 -OutFile $f; & $f
```
<sub>Parámetros: `-Mode` `-P12` `-Password` `-Match` `-Thumbprint` `-DryRun` `-Force` `-Log`</sub>

</details>

## <img src=".github/icons/wrench.svg" width="20" height="20" align="top" alt=""> 99 - Repo tools

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>Validar los scripts del repo</b></summary>

Valida todos los .ps1 del repo: solo ASCII, UTF-8 con BOM, Contexto declarado y sintaxis en 5.1 y 7.<br>[`01-validate-scripts`](99-repo-tools/01-validate-scripts.ps1)

```powershell
.\99-repo-tools\01-validate-scripts.ps1
```
<sub>Parámetros: `-Corregir`</sub>

</details>

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>Probar el reset de Outlook en sandbox</b></summary>

Prueba en sandbox la lógica de borrado de los scripts de Outlook. No toca Outlook.<br>[`02-test-outlook-reset`](99-repo-tools/02-test-outlook-reset.ps1)

```powershell
.\99-repo-tools\02-test-outlook-reset.ps1
```

</details>

<details><summary><img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> <b>Regenerar los README</b></summary>

Regenera el índice de README.md y README.en.md leyendo el .SYNOPSIS de cada script.<br>[`03-generate-readme`](99-repo-tools/03-generate-readme.ps1)

```powershell
.\99-repo-tools\03-generate-readme.ps1
```
<sub>Parámetros: `-Comprobar`</sub>

</details>

<!-- INDICE-FIN -->

---

## Parámetros y ejecución

Una línea por script, para pegar en la consola del usuario. Descarga de `main` a `%TEMP%`,
abre la política de ejecución **solo para ese proceso** y lo lanza; igual en PowerShell 5.1 y 7.
Los parámetros van al final, detrás de `& $f`:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; [Net.ServicePointManager]::SecurityProtocol=3072; $f="$env:TEMP\<script>.ps1"; irm https://raw.githubusercontent.com/4leX-42/SCRIPTS-SUPPORT_CX/main/<carpeta>/<script>.ps1 -OutFile $f; & $f -DryRun
```

Los de `00-copy-paste` no llevan parámetros y se ejecutan en memoria (`irm <url> | iex`).
Con el fichero ya en el equipo:

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
| `-Mode`, `-P12`, `-Thumbprint` | `11/01` | `Diag` \| `Fix` \| `ResetPrefs`, fichero PKCS#12 y huella del certificado a reparar |
| `-Fase` | `03/02` | `Reparar` \| `Comprobar` \| `Verificar` |
| `-TargetService`, `-MaxLevel`, `-DiagnosticOnly` | `05/02` | servicio, nivel máximo de escalado, solo diagnóstico |
| `-RutaRespaldo` | `01/02` | destino del respaldo si el Escritorio no admite escritura |
| `-ProcessName`, `-EnableDumps`, `-Interactive` | `10/05` | procesos a inspeccionar, volcado WER del próximo crash, prueba real del diálogo en 64 y 32 bits |
| `$env:SOPORTE_ORIGEN_PAQUETES` | `05/01`, `06/*` | ruta del share de instaladores |

Los de modo `pegar` no llevan parámetros: se pegan y ya. La lista completa de parámetros de
cada script está en su ficha del índice, leída del `param()` real.

## Contexto de ejecución

La etiqueta de color de cada script en el índice dice con qué consola se lanza:

| Valor | Cómo se lanza |
|---|---|
| <img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> | PowerShell normal, en la sesión del usuario afectado, **sin elevar** |
| <img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> | PowerShell **como administrador**, desde la sesión del usuario afectado |
| <img src=".github/icons/badge-admin.svg" height="20" align="top" alt="admin"> + <img src=".github/icons/badge-usuario.svg" height="20" align="top" alt="usuario"> | por fases: unas elevado y otras sin elevar; la ayuda del script (`Get-Help -Full`) dice cuál |

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
.\99-repo-tools\01-validate-scripts.ps1      # ASCII, BOM, Contexto y sintaxis en 5.1 y 7
.\99-repo-tools\03-generate-readme.ps1       # regenera el índice de los dos README
```

- Solo ASCII en código. UTF-8 con BOM.
- PowerShell 5.1 y 7. Windows 10 y 11.
- `-DryRun` o `-WhatIf` en todo lo que escriba.
- `param()`, sin rutas ni cuentas cableadas.
- `.SYNOPSIS` con línea `[ES]` y línea `[EN]` — de ahí sale el índice del README.
- Autónomo: sin módulos externos ni certificados.
- `#Requires` separado del bloque `<#` por una línea en blanco, o `Get-Help` no lee el synopsis.
- `.NOTES` con línea `Contexto: usuario`, `Contexto: admin` o `Contexto: mixto` — de ahí sale la
  columna Ejecución. El validador falla si falta.
- Los de `00-copy-paste` son la excepción: **sin bloque de ayuda y sin comentarios**. Su
  descripción va en [`00-copy-paste/index.psd1`](00-copy-paste/index.psd1).

El índice de este README se genera solo. Cambias un script, ejecutas el generador, un commit.
