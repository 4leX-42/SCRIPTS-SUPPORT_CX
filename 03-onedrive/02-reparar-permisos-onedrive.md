# ACL de OneDrive — residuo de GPO de dominio

Runbook de [`02-reparar-permisos-onedrive.ps1`](02-reparar-permisos-onedrive.ps1).

**ES —** Un usuario estándar no puede crear carpetas dentro de su propio OneDrive: el Explorador
pide credenciales de admin. Solo en rutas de OneDrive.

**EN —** A standard user cannot create folders inside their own OneDrive: Explorer prompts for
admin credentials. Only on OneDrive paths.

## Causa / Root cause

**ES —** ACE de denegación `Everyone:(DENY)(D,WD,AD,DC)` escritas carpeta por carpeta por una GPO
de dominio. Al sacar el equipo del dominio la GPO desaparece pero los ACL quedan grabados en la
MFT de NTFS. No se heredan (sin `(OI)(CI)`), están en cada carpeta individualmente, y en NTFS una
denegación siempre gana sobre una concesión — por eso el usuario falla aunque tenga `(F)` heredado
y sea el propietario.

**EN —** `Everyone:(DENY)(D,WD,AD,DC)` ACEs written folder by folder by a domain GPO. Unjoining the
machine removes the GPO but the ACLs stay written in the NTFS MFT. They are not inheritable (no
`(OI)(CI)`), they sit on each folder individually, and in NTFS a deny always beats a grant — which
is why the user fails despite holding inherited `(F)` and being the owner.

---

## 1. Reparar — PowerShell COMO ADMINISTRADOR

```powershell
$r = "C:\Users\jperez\OneDrive - Contoso"
icacls "$r" /reset /T /C /Q
```

| Flag | Función |
|---|---|
| `/reset` | Descarta todas las ACE explícitas y restablece la herencia del perfil |
| `/T` | Recorre todo el árbol |
| `/C` | Continúa aunque alguna ruta falle |
| `/Q` | Silencia el `processed file:` de cada elemento — clave para que no vuelque 100k líneas |

Salida esperada: `Successfully processed 100515 files; Failed processing 334 files`

Los fallos con `The system cannot find the path specified` son rutas que superan los 260
caracteres de `MAX_PATH`. **No son errores de permisos.** Unos cientos sobre decenas de miles es
un resultado correcto.

## 2. Comprobar — COMO ADMINISTRADOR

```powershell
$r = "C:\Users\jperez\OneDrive - Contoso"
(icacls "$r" /T /C 2>$null | Select-String 'DENY').Count
```

Debe devolver **`0`**. Si devuelve más, repetir el paso 1.

Comprobación puntual de una carpeta concreta, sin recorrer el árbol:

```powershell
icacls "C:\Users\jperez\OneDrive - Contoso\Escritorio\Proyecto"
```

No debe aparecer ninguna línea con `(DENY)`. Todas las ACE deben llevar `(I)` (heredadas):
`SYSTEM (F)`, `Administradores (F)`, `<usuario> (F)`.

## 3. Verificar — EN LA SESIÓN DEL USUARIO AFECTADO, SIN ELEVAR

Esta es la única prueba que cuenta. Elevado pasa siempre y no dice nada.

```powershell
.\02-reparar-permisos-onedrive.ps1 -Fase Verificar
```

Todo `OK` = resuelto. Confirmar también desde el Explorador (clic derecho → Nuevo → Carpeta), que
es donde el usuario veía el aviso.

---

## Quién ejecuta qué

| Paso | Sesión | Elevación | Por qué |
|---|---|---|---|
| 1. Reset | Cualquiera con cuenta admin | **Sí** | Modificar ACL requiere privilegios |
| 2. Contar DENY | Cualquiera con cuenta admin | **Sí** | Leer ACL de todo el árbol |
| 3. Prueba de escritura | **La del usuario afectado** | **No** | Elevado pasa siempre; hay que probar con su token real |

Ojo: si te conectas a la sesión del usuario con *Cambiar de usuario*, cada uno tiene su propio
`$env:OneDrive`. Ejecutar el paso 3 desde tu sesión apuntaría a tu OneDrive, no al suyo.

---

## Notas

- **Es permanente.** Los ACL viven en la MFT de NTFS. Sin dominio, nada los vuelve a aplicar. No
  se deshace con reinicios ni actualizaciones.
- **No concede privilegios de admin.** Los permisos NTFS (por carpeta) y la pertenencia al grupo
  `Administradores` (instalar software, `HKLM`, servicios) son sistemas independientes. El usuario
  sigue siendo estándar.
- **Si tarda demasiado o se queda colgado:** casi siempre es `icacls` disparando la descarga de
  archivos en la nube. Pausar la sincronización antes (icono de la nube → Pausar sincronización →
  8 horas).
- **`Users` vs `Usuarios`:** el mismo grupo, SID `S-1-5-32-545`. `net localgroup` falla con
  **error 1376** si usas el nombre en el idioma equivocado. En scripts, usar siempre el SID.
- **`takeown` no hace falta** si el propietario ya es el usuario (`(Get-Acl $r).Owner`). Y si lo
  necesitas, `/D` acepta `Y`/`N` según el idioma de la build, no `S`.

## Descartes rápidos si el reset no lo arregla

| Hipótesis | Comprobación |
|---|---|
| OneDrive fuera del perfil | `echo %OneDrive%` → debe estar bajo `C:\Users\<usuario>` |
| Acceso controlado a carpetas | `(Get-MpPreference).EnableControlledFolderAccess` → `0` = off |
| OneDrive en solo lectura (cuota/licencia) | Banner en el portal de Microsoft 365 → OneDrive |
| Propietario incorrecto | `(Get-Acl $r).Owner` |
| Reaparecen las ACE tras reiniciar | El equipo se reunió al dominio, o hay software de seguridad reaplicándolas |

Si `Get-MpPreference` devuelve `0x800106ba`, el servicio de Defender no está corriendo — típico en
equipos sacados de dominio. Comprobar con `Get-Service WinDefend | Select-Object Status,StartType`.
