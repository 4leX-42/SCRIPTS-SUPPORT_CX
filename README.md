# SCRIPTS-SUPPORT_CX

🇬🇧 [English](README.en.md)

---

<!-- INDICE-INICIO: generado por 99-repo-tools/03-generate-readme.ps1, no editar a mano -->

**Ir a:** <img src=".github/icons/clipboard_code.svg" width="20" height="20" align="top" alt=""> [Copy and paste (diagnostics)](#-00---copy-and-paste-diagnostics) | <img src=".github/icons/key.svg" width="20" height="20" align="top" alt=""> [Identity cache](#-01---identity-cache) | <img src=".github/icons/mail.svg" width="20" height="20" align="top" alt=""> [Outlook](#-02---outlook) | <img src=".github/icons/cloud.svg" width="20" height="20" align="top" alt=""> [OneDrive](#-03---onedrive) | <img src=".github/icons/people_team.svg" width="20" height="20" align="top" alt=""> [Teams](#-04---teams) | <img src=".github/icons/apps.svg" width="20" height="20" align="top" alt=""> [Office apps](#-05---office-apps) | <img src=".github/icons/puzzle_piece.svg" width="20" height="20" align="top" alt=""> [Corporate applications](#-06---corporate-applications) | <img src=".github/icons/laptop.svg" width="20" height="20" align="top" alt=""> [Endpoint](#-07---endpoint) | <img src=".github/icons/router.svg" width="20" height="20" align="top" alt=""> [Network](#-08---network) | <img src=".github/icons/document.svg" width="20" height="20" align="top" alt=""> [Documents](#-09---documents) | <img src=".github/icons/folder_open.svg" width="20" height="20" align="top" alt=""> [File picker](#-10---file-picker) | <img src=".github/icons/certificate.svg" width="20" height="20" align="top" alt=""> [Certificates](#-11---certificates) | <img src=".github/icons/wrench.svg" width="20" height="20" align="top" alt=""> [Repo tools](#-99---repo-tools)

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

| Informe | Script | Ventana | Qué saca |
|---|---|---|---|
| **Ficha técnica del equipo** | [`03-endpoint-report`](00-copy-paste/03-endpoint-report.ps1) | `admin` | Hardware, generación real de Windows, join a Entra o dominio, MDM, disco, BitLocker, red y Office |
| **Estado del agente ESET** | [`06-eset-status`](00-copy-paste/06-eset-status.ps1) | `admin` | Instalación, servicios, firma del binario, enrolamiento leído del trace y conectividad con ESET PROTECT |
| **Cuentas cacheadas e identidades** | [`01-cached-accounts`](00-copy-paste/01-cached-accounts.ps1) | `usuario` | Inventario de cuentas cacheadas: origen de cada una, detección de UPN GUID y tenantId real de cada dominio |
| **Estado de OneDrive** | [`02-onedrive-status`](00-copy-paste/02-onedrive-status.ps1) | `usuario` | Proceso, versión, cuentas vinculadas, ACE de denegación, prueba de escritura y frescura de los logs |
| **Conectividad con M365** | [`04-m365-connectivity`](00-copy-paste/04-m365-connectivity.ps1) | `usuario` | Proxy, DNS, TCP 443, versión de TLS y latencia contra los 7 endpoints de Microsoft 365 |
| **Estado de Office y Outlook** | [`05-office-outlook-status`](00-copy-paste/05-office-outlook-status.ps1) | `usuario` | Versión, licencia, identidades, perfiles, .ost y .pst, complementos y elementos deshabilitados |

## <img src=".github/icons/key.svg" width="20" height="20" align="top" alt=""> 01 - Identity cache

| Función | Script | Ejecución | Parámetros |
|---|---|---|---|
| Borra las cuentas de trabajo cacheadas. Las quita todas salvo las que decidas conservar. | [`01-clear-cached-accounts`](01-identity-cache/01-clear-cached-accounts.ps1) | `usuario` | `-Excluir` `-Quitar` `-NoCerrarApps` `-Detalle` `-DryRun` `-Force` |
| Quita la cuenta que sobrevive de un tenant antiguo. Detecta sola el UPN y el tenant. | [`02-reset-stale-tenant-v2.1`](01-identity-cache/02-reset-stale-tenant-v2.1.ps1) | `usuario` | `-Upn` `-TenantOrigen` `-TenantEsperado` `-RutaRespaldo` `-SoloDetectar` `-NoInteractivo` `-DryRun` `-NoCerrarApps` `-BorrarCookiesEdge` `-QuitarWorkplaceJoin` `-IgnorarPerfil` `-Force` |
| Repara la caché de credenciales de Microsoft 365 por niveles, y sabe deshacer los cambios. | [`03-repair-credential-cache-with-restore`](01-identity-cache/03-repair-credential-cache-with-restore.ps1) | `usuario` | `-Mode` `-Accounts` `-Tiers` `-BackupRoot` `-RestoreFrom` `-CloseApps` `-DryRun` `-Force` |

## <img src=".github/icons/mail.svg" width="20" height="20" align="top" alt=""> 02 - Outlook

| Función | Script | Ejecución | Parámetros |
|---|---|---|---|
| Rehace el perfil de Outlook clásico conservando los .pst y .ost y lo recrea con la misma cuenta. | [`01-reset-outlook-profile`](02-outlook/01-reset-outlook-profile.ps1) | `usuario` | `-FullReset` `-ClearAutoComplete` `-Email` `-ProfileName` `-NoRecreate` `-WaitSeconds` `-Force` `-WhatIf` |
| Reset agresivo de Outlook: perfil, OST y caché de autocompletado. | [`02-full-outlook-reset`](02-outlook/02-full-outlook-reset.ps1) | `usuario` | `-SkipProfileReset` `-SkipOST` `-SkipRoamCache` `-DeleteWholeLocalOutlookFolder` `-WhatIf` |
| Repara la ventana de inicio de sesión de Microsoft 365 que se queda en blanco o en "Un momento..." al agregar la cuenta en Outlook. | [`03-repair-signin-window`](02-outlook/03-repair-signin-window.ps1) | `admin` | `-SoloDiagnostico` `-BorrarCuentasWam` `-DryRun` `-Force` |

## <img src=".github/icons/cloud.svg" width="20" height="20" align="top" alt=""> 03 - OneDrive

| Función | Script | Ejecución | Parámetros |
|---|---|---|---|
| Arregla OneDrive subiendo por 5 niveles: reinicio, reset, caché, binario y reinstalación. | [`01-remediate-onedrive-tiered`](03-onedrive/01-remediate-onedrive-tiered.ps1) | `usuario` | `-MaxLevel` `-LocalInstallerPath` `-StartupWaitSeconds` `-SkipEnvironmentChecks` `-ClearCredentials` `-ForceReinstall` |
| Quita las ACE de denegación que dejó una GPO de dominio y hacen que OneDrive pida admin. | [`02-fix-onedrive-permissions`](03-onedrive/02-fix-onedrive-permissions.ps1) | `admin + usuario` | `-Fase` `-Ruta` `-DryRun` |
| Acorta las rutas de OneDrive de mas de 380 caracteres ("la ruta es demasiado larga") sin tocar el nombre de los documentos. | [`03-shorten-long-paths`](03-onedrive/03-shorten-long-paths.ps1) | `usuario` | `-Ruta` `-Upn` `-Raiz` `-Limite` `-Margen` `-PermitirRecorte` `-MinNombre` `-DryRun` `-SinConfirmar` `-Ascii` `-Revertir` |

Runbook detallado: [`02-fix-onedrive-permissions.md`](03-onedrive/02-fix-onedrive-permissions.md)

## <img src=".github/icons/people_team.svg" width="20" height="20" align="top" alt=""> 04 - Teams

| Función | Script | Ejecución | Parámetros |
|---|---|---|---|
| Arregla el inicio de sesión de Teams cuando se queda en bucle o no autentica. | [`01-repair-teams-signin`](04-teams/01-repair-teams-signin.ps1) | `usuario` | `-DryRun` `-Force` `-Aggressive` `-IncludeOutlook` `-RepairTeams` `-LogPath` |
| Recupera el botón de reunión de Teams cuando desaparece de Outlook (clásico). | [`02-repair-teams-outlook-addin`](04-teams/02-repair-teams-outlook-addin.ps1) | `admin` | `-User` |
| Re-registra el complemento de reunión de Teams en Outlook clásico y lo blinda. | [`03-repair-teams-addin-com`](04-teams/03-repair-teams-addin-com.ps1) | `usuario` | `-NoKillOutlook` |

## <img src=".github/icons/apps.svg" width="20" height="20" align="top" alt=""> 05 - Office apps

| Función | Script | Ejecución | Parámetros |
|---|---|---|---|
| Repara la instalación de Office: reparación rápida u online, y reactivación. | [`01-repair-office-install`](05-office-apps/01-repair-office-install.ps1) | `admin` | ninguno |
| Motor desatendido que diagnostica y repara OneDrive, Outlook, Office, identidad y red. | [`02-m365-remediation-engine`](05-office-apps/02-m365-remediation-engine.ps1) | `admin` | `-TargetService` `-MaxLevel` `-DiagnosticOnly` `-LogPath` |

## <img src=".github/icons/puzzle_piece.svg" width="20" height="20" align="top" alt=""> 06 - Corporate applications

| Función | Script | Ejecución | Parámetros |
|---|---|---|---|
| Dice por qué ESET Endpoint no está instalado, no arranca o no se conecta a la consola. | [`01-diagnose-eset`](06-applications/01-diagnose-eset.ps1) | `admin` | ninguno |
| Instala ESET Endpoint sin asistencia, incluso cuando el instalador no admite modo silencioso. | [`02-install-eset`](06-applications/02-install-eset.ps1) | `admin` | `-Modo` |
| Desinstala iManage Work Desktop por completo, con sus complementos de Office. | [`03-uninstall-imanage`](06-applications/03-uninstall-imanage.ps1) | `admin` | `-WhatIf` |
| Instala PDFelement e iManage automatizando su asistente, que no admite modo silencioso. | [`04-install-pdfelement-imanage`](06-applications/04-install-pdfelement-imanage.ps1) | `admin` | `-Modo` |
| Analiza un paquete de instalación y dice qué tipo es y qué parámetros silenciosos admite. | [`05-diagnose-installers`](06-applications/05-diagnose-installers.ps1) | `admin` | ninguno |
| Repara el cliente Mitel Connect / MiCollab: caché, registro, Outlook, credenciales y DNS. | [`06-repair-mitel-client`](06-applications/06-repair-mitel-client.ps1) | `admin + usuario` | `-DryRun` `-Force` `-AllUsers` `-KeepOutlookAddin` `-DisableOutlookAddin` `-KeepCredentials` `-ServerHost` `-FixDns` `-DnsServers` `-DnsSuffix` `-FixHosts` `-FixFirewall` `-Reinstall` `-LogPath` |

## <img src=".github/icons/laptop.svg" width="20" height="20" align="top" alt=""> 07 - Endpoint

| Función | Script | Ejecución | Parámetros |
|---|---|---|---|
| Qué está ocupando el disco: carpetas más grandes y basura que se puede recuperar. | [`01-disk-usage`](07-endpoint/01-disk-usage.ps1) | `admin` | `-Ruta` `-Top` `-SoloBasura` |
| Saca la clave de recuperación de BitLocker por número de serie, nombre o id de dispositivo. | [`02-bitlocker-recovery-key`](07-endpoint/02-bitlocker-recovery-key.ps1) | `usuario` | `-Serie` `-Nombre` `-DeviceId` `-RutaCsv` `-ConfigPath` |
| Diagnostica y corrige apagados y reinicios inesperados del equipo. | [`03-fix-random-shutdowns`](07-endpoint/03-fix-random-shutdowns.ps1) | `admin` | `-SkipDiag` `-SkipWifi` |
| Deja el reloj en hora para poder firmar en sedes electrónicas: detecta la ubicación, empareja zona horaria y NTP del país, y repara W32Time. | [`04-repair-time-sync`](07-endpoint/04-repair-time-sync.ps1) | `admin` | `-DryRun` `-Force` `-DiagnoseOnly` `-TimeZoneId` `-NtpServers` `-SkipGeo` `-NoTimeZoneChange` `-PersistPublicNtp` `-AllowStepTime` `-NoStepTime` `-AutoTimeZoneService` `-PollSeconds` `-LogPath` |
| Activa las rutas largas de Windows (mas de 260 caracteres) y desactiva los nombres cortos 8.3. | [`05-enable-long-paths`](07-endpoint/05-enable-long-paths.ps1) | `admin` | `-DryRun` |

## <img src=".github/icons/router.svg" width="20" height="20" align="top" alt=""> 08 - Network

| Función | Script | Ejecución | Parámetros |
|---|---|---|---|
| Quita el ahorro de energía de la tarjeta Wi-Fi y pone el plan de alto rendimiento. | [`01-optimize-wifi-adapter`](08-network/01-optimize-wifi-adapter.ps1) | `admin` | `-Adaptador` `-DryRun` |

## <img src=".github/icons/document.svg" width="20" height="20" align="top" alt=""> 09 - Documents

| Función | Script | Ejecución | Parámetros |
|---|---|---|---|
| Quita la protección de edición de un documento de Word cuando se perdió la contraseña. | [`01-unlock-protected-word`](09-documents/01-unlock-protected-word.ps1) | `usuario` | `-NoPause` `-Paths` |

## <img src=".github/icons/folder_open.svg" width="20" height="20" align="top" alt=""> 10 - File picker

| Función | Script | Ejecución | Parámetros |
|---|---|---|---|
| Solo lectura. Inventario de todo lo que puede colgar el selector de archivos de Windows. | [`01-diagnose-file-picker`](10-file-picker/01-diagnose-file-picker.ps1) | `usuario` | `-OutDir` `-DiasEventos` `-TimeoutRutaSegundos` `-SinFirmas` |
| Solo lectura. Reproduce el cuelgue del selector y captura el DLL que lo provoca. | [`02-test-file-picker-hang`](10-file-picker/02-test-file-picker-hang.ps1) | `usuario` | `-TimeoutSegundos` `-Proceso` `-CarpetaInicial` `-Volcado` `-RutaProcdump` `-OutDir` |
| Limpia la memoria de carpetas del selector de archivos (ComDlg32 MRU). DryRun por defecto. | [`03-reset-file-picker-mru`](10-file-picker/03-reset-file-picker-mru.ps1) | `usuario` | `-Execute` `-IncluirRecientes` `-ReiniciarExplorer` `-Restore` `-BackupDir` |
| Desactiva extensiones de shell por CLSID de forma reversible. DryRun por defecto. | [`04-block-shell-extension`](10-file-picker/04-block-shell-extension.ps1) | `admin` | `-Clsid` `-ClsidFile` `-DesdeCsv` `-FiltroDll` `-Quitar` `-Listar` `-Execute` `-ReiniciarExplorer` `-Motivo` `-BackupDir` |
| Solo lectura. Diagnóstico del crash de una aplicación al abrir el diálogo Abrir/Guardar como. | [`05-diagnose-file-picker-crash`](10-file-picker/05-diagnose-file-picker-crash.ps1) | `admin + usuario` | `-ProcessName` `-OutDir` `-Interactive` `-EnableDumps` `-DryRun` `-SkipSignatures` `-TimeoutSec` |

## <img src=".github/icons/certificate.svg" width="20" height="20" align="top" alt=""> 11 - Certificates

| Función | Script | Ejecución | Parámetros |
|---|---|---|---|
| Repara un certificado concreto que AutoFirma no lista, sin tocar el resto del almacén. | [`01-repair-autofirma-certificate`](11-certificates/01-repair-autofirma-certificate.ps1) | `usuario` | `-Mode` `-P12` `-Password` `-Match` `-Thumbprint` `-DryRun` `-Force` `-Log` |

## <img src=".github/icons/wrench.svg" width="20" height="20" align="top" alt=""> 99 - Repo tools

| Función | Script | Ejecución | Parámetros |
|---|---|---|---|
| Valida todos los .ps1 del repo: solo ASCII, UTF-8 con BOM, Contexto declarado y sintaxis en 5.1 y 7. | [`01-validate-scripts`](99-repo-tools/01-validate-scripts.ps1) | `usuario` | `-Corregir` |
| Prueba en sandbox la lógica de borrado de los scripts de Outlook. No toca Outlook. | [`02-test-outlook-reset`](99-repo-tools/02-test-outlook-reset.ps1) | `usuario` | ninguno |
| Regenera el índice de README.md y README.en.md leyendo el .SYNOPSIS de cada script. | [`03-generate-readme`](99-repo-tools/03-generate-readme.ps1) | `usuario` | `-Comprobar` |

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
| `-Mode`, `-P12`, `-Thumbprint` | `11/01` | `Diag` \| `Fix` \| `ResetPrefs`, fichero PKCS#12 y huella del certificado a reparar |
| `-Fase` | `03/02` | `Reparar` \| `Comprobar` \| `Verificar` |
| `-TargetService`, `-MaxLevel`, `-DiagnosticOnly` | `05/02` | servicio, nivel máximo de escalado, solo diagnóstico |
| `-RutaRespaldo` | `01/02` | destino del respaldo si el Escritorio no admite escritura |
| `-ProcessName`, `-EnableDumps`, `-Interactive` | `10/05` | procesos a inspeccionar, volcado WER del próximo crash, prueba real del diálogo en 64 y 32 bits |
| `$env:SOPORTE_ORIGEN_PAQUETES` | `05/01`, `06/*` | ruta del share de instaladores |

Los de modo `pegar` no llevan parámetros: se pegan y ya. La lista completa de parámetros de
cada script está en su fila del índice, leída del `param()` real.

## Contexto de ejecución

La columna **Ejecución** del índice dice con qué cuenta se lanza cada script:

| Valor | Cómo se lanza |
|---|---|
| `usuario` | PowerShell normal, en la sesión del usuario afectado, **sin elevar** |
| `admin` | PowerShell **como administrador**, desde la sesión del usuario afectado |
| `admin + usuario` | por fases: unas elevado y otras sin elevar; la ayuda del script (`Get-Help -Full`) dice cuál |

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
