# 10 - Herramientas

Aplicaciones con interfaz gráfica, a diferencia del resto del repositorio, que son
scripts de PowerShell para ejecutar en consola.

Cada herramienta vive en su propia carpeta con su `README.md`.

| Herramienta | Función | Stack |
|---|---|---|
| [`conversor-ledes-98bi`](conversor-ledes-98bi/) | Convierte facturas en PDF al formato LEDES 98BI para las plataformas de facturación legal | Python 3.9+ / tkinter |

## Por qué no siguen el estándar del repositorio

El estándar del repositorio (`.ps1`, solo ASCII, UTF-8 con BOM, PowerShell 5.1 y 7)
aplica a los scripts de soporte. Las herramientas de esta sección son aplicaciones
completas y no lo cumplen:

- no son PowerShell, así que `99-repo-tools/01-validate-scripts.ps1` no las valida
- no tienen `.SYNOPSIS`, así que `99-repo-tools/03-generate-readme.ps1` no las indexa;
  el índice de esta sección se mantiene a mano
- llevan dependencias externas, frente a la regla de «autónomo, sin módulos externos»

## Binarios

Los ejecutables **no se versionan**: se publican como *assets* de una
[release](../../../releases). El repositorio guarda solo el código fuente y el
`.spec` para reconstruirlos.
