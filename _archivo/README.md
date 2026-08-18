# Archivo / Archive

**ES —** Scripts retirados. Se conservan por si hace falta consultar cómo hacían algo, pero
**no deben usarse**: cada uno tiene un sustituto mejor en el repo. Ninguno se valida ni se
mantiene.

**EN —** Retired scripts. Kept for reference on how something used to be done, but **do not use
them**: each has a better replacement in the repo. None of these are validated or maintained.

| Retirado / Retired | Sustituto / Replacement |
|---|---|
| `reset-tenant-obsoleto-v1-Reset-CachedWorkAccount.ps1` | `../01-cuentas-y-credenciales/03-reset-tenant-obsoleto-v2.1.ps1` |
| `Limpiar-CuentasMicrosoft.ps1` | `../01-cuentas-y-credenciales/02-limpiar-cuentas-cacheadas.ps1` |
| `Script2.0-reparar-identidad-office.txt` | `../01-cuentas-y-credenciales/02-limpiar-cuentas-cacheadas.ps1` |
| `ONEDRIVE-limpieza-sesion.txt` | `../01-cuentas-y-credenciales/02-limpiar-cuentas-cacheadas.ps1` |
| `Mod-ESET-v3-ui-automation.ps1` | `../06-aplicaciones/03-instalar-eset.ps1` |
| `Fix-Pendientes.ps1` | `../06-aplicaciones/05-instalar-pdfelement-e-imanage.ps1` |

## Sobre las versiones de `reset-tenant-obsoleto`

**ES —** La **v1** (`Reset-CachedWorkAccount.ps1`) obliga a pasarle `-Upn` y `-TenantViejo` a mano:
si no sabes de qué tenant viene la cuenta zombie, no sirve. La **v2.1** los descubre sola leyendo
el registro de Office, IdentityCRL, OneDrive, el broker WAM, el administrador de credenciales y
`dsregcmd`, resuelve cada dominio contra los endpoints públicos de login para saber a qué tenant
pertenece, y te deja elegir con flechas, con un número o escribiéndolo a mano.

**EN —** **v1** (`Reset-CachedWorkAccount.ps1`) requires you to pass `-Upn` and `-TenantViejo` by
hand: if you don't know which tenant the zombie account came from, it's useless. **v2.1** finds
both by reading the Office registry, IdentityCRL, OneDrive, the WAM broker, Credential Manager and
`dsregcmd`, resolves every domain against the public login endpoints to determine its tenant, and
lets you pick with arrow keys, by number, or by typing it in.
