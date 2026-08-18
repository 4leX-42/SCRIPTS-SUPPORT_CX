# Archive

**ES —** Scripts retirados. Se conservan por si hace falta ver cómo hacían algo, pero **no deben
usarse**: cada uno tiene un sustituto mejor. No se validan ni se mantienen.

**EN —** Retired scripts. Kept in case you need to see how something used to be done, but **do not
use them**: each has a better replacement. Not validated, not maintained.

## Retirados al pasar a modo `paste` / Retired on moving to `paste` mode

**ES —** Eran diagnósticos de solo lectura. Descargar un `.ps1` para no escribir nada no tiene
sentido: ahora se pegan en la consola y su salida va directa a una IA.

**EN —** These were read-only diagnostics. Downloading a `.ps1` just to change nothing makes no
sense: they are now pasted into the console and their output goes straight to an AI.

| Retirado / Retired | Sustituto / Replacement |
|---|---|
| `01-listar-cuentas-cacheadas.ps1` | `../00-copy-paste/01-cached-accounts.ps1` |
| `01-informe-del-equipo.ps1` | `../00-copy-paste/03-endpoint-report.ps1` |
| `01-probar-conectividad-m365.ps1` | `../00-copy-paste/04-m365-connectivity.ps1` |
| `02-estado-agente-eset.ps1` | `../00-copy-paste/06-eset-status.ps1` |

## Retirados por duplicidad / Retired as duplicates

| Retirado / Retired | Sustituto / Replacement |
|---|---|
| `reset-tenant-obsoleto-v1-Reset-CachedWorkAccount.ps1` | `../01-identity-cache/02-reset-stale-tenant-v2.1.ps1` |
| `Limpiar-CuentasMicrosoft.ps1` | `../01-identity-cache/01-clear-cached-accounts.ps1` |
| `Script2.0-reparar-identidad-office.txt` | `../01-identity-cache/01-clear-cached-accounts.ps1` |
| `ONEDRIVE-limpieza-sesion.txt` | `../01-identity-cache/01-clear-cached-accounts.ps1` |
| `Mod-ESET-v3-ui-automation.ps1` | `../06-applications/02-install-eset.ps1` |
| `Fix-Pendientes.ps1` | `../06-applications/04-install-pdfelement-imanage.ps1` |

## Las versiones de `reset-stale-tenant` / `reset-stale-tenant` versions

**ES —** La **v1** (`Reset-CachedWorkAccount.ps1`) obliga a pasarle `-Upn` y `-TenantViejo` a mano:
si no sabes de qué tenant viene la cuenta zombie, no sirve. La **v2.1** los descubre sola leyendo
el registro de Office, IdentityCRL, OneDrive, el broker WAM, el Administrador de credenciales y
`dsregcmd`; resuelve cada dominio contra los endpoints públicos de login para saber a qué tenant
pertenece, y te deja elegir con flechas, con un número o escribiéndolo a mano.

**EN —** **v1** (`Reset-CachedWorkAccount.ps1`) requires passing `-Upn` and `-TenantViejo` by hand:
if you don't know which tenant the zombie account came from, it's useless. **v2.1** finds both by
reading the Office registry, IdentityCRL, OneDrive, the WAM broker, Credential Manager and
`dsregcmd`; resolves each domain against the public login endpoints to determine its tenant, and
lets you pick with arrow keys, by number, or by typing it in.
