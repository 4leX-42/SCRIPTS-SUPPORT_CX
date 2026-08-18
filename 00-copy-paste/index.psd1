# Descripciones de los scripts de copiar y pegar.
#
# Estos .ps1 no llevan ni un comentario a proposito: se pegan enteros en la consola y
# cualquier comentario es ruido para la IA que despues analiza la salida. Su titulo, su
# descripcion, la ventana en la que se pegan y el orden en que salen listados viven aqui,
# y de aqui los lee 99-repo-tools/03-generate-readme.ps1.
#
# Titulo  = nombre corto y tecnico, el que se ve en la tabla del README.
# ES / EN = descripcion larga, la que explica que saca el informe.
# Ventana = donde se pega. 'usuario' es PowerShell normal con la sesion del usuario
#           afectado (elevar cambiaria el HKCU que se lee); 'admin' es PowerShell como
#           administrador de ese mismo usuario.
# Orden   = orden en la tabla. Primero los de admin, que son los que hay que preparar
#           antes de sentarse con el usuario.
#
# Paste-ready scripts carry no comments on purpose: they get pasted whole into the console
# and any comment is noise for the AI that later parses the output. Their title, long
# description, target window and listing order live here, and 03-generate-readme.ps1 reads
# them from here. Admin ones are listed first.

@{
    '91-long-paths.txt' = @{
        Titulo = 'Arreglo de rutas largas (MAX_PATH)'
        TitleEN = 'Long path fix (MAX_PATH)'
        ES = 'Habilita LongPathsEnabled y nombres 8.3, y localiza las rutas que pasan de 255 caracteres en OneDrive e iManage'
        EN = 'Enables LongPathsEnabled and 8.3 names, and finds the paths beyond 255 characters in OneDrive and iManage'
        Ventana = 'admin'
        Orden = 1
    }
    '03-endpoint-report.ps1' = @{
        Titulo = 'Ficha tecnica del equipo'
        TitleEN = 'Machine snapshot'
        ES = 'Hardware, generacion real de Windows, join a Entra o dominio, MDM, disco, BitLocker, red y Office'
        EN = 'Hardware, real Windows generation, Entra or domain join, MDM, disk, BitLocker, network and Office'
        Ventana = 'admin'
        Orden = 2
    }
    '06-eset-status.ps1' = @{
        Titulo = 'Estado del agente ESET'
        TitleEN = 'ESET agent state'
        ES = 'Instalacion, servicios, firma del binario, enrolamiento leido del trace y conectividad con ESET PROTECT'
        EN = 'Installation, services, binary signature, enrolment read from the trace log and ESET PROTECT connectivity'
        Ventana = 'admin'
        Orden = 3
    }
    '01-cached-accounts.ps1' = @{
        Titulo = 'Cuentas cacheadas e identidades'
        TitleEN = 'Cached accounts and identities'
        ES = 'Inventario de cuentas cacheadas: origen de cada una, deteccion de UPN GUID y tenantId real de cada dominio'
        EN = 'Cached account inventory: source of each one, GUID UPN detection and real tenantId per domain'
        Ventana = 'usuario'
        Orden = 4
    }
    '02-onedrive-status.ps1' = @{
        Titulo = 'Estado de OneDrive'
        TitleEN = 'OneDrive state'
        ES = 'Proceso, version, cuentas vinculadas, ACE de denegacion, prueba de escritura y frescura de los logs'
        EN = 'Process, version, linked accounts, deny ACEs, write test and log freshness'
        Ventana = 'usuario'
        Orden = 5
    }
    '04-m365-connectivity.ps1' = @{
        Titulo = 'Conectividad con M365'
        TitleEN = 'M365 reachability'
        ES = 'Proxy, DNS, TCP 443, version de TLS y latencia contra los 7 endpoints de Microsoft 365'
        EN = 'Proxy, DNS, TCP 443, TLS version and latency across the 7 Microsoft 365 endpoints'
        Ventana = 'usuario'
        Orden = 6
    }
    '05-office-outlook-status.ps1' = @{
        Titulo = 'Estado de Office y Outlook'
        TitleEN = 'Office and Outlook state'
        ES = 'Version, licencia, identidades, perfiles, .ost y .pst, complementos y elementos deshabilitados'
        EN = 'Version, licence, identities, profiles, .ost and .pst, add-ins and disabled items'
        Ventana = 'usuario'
        Orden = 7
    }
}
