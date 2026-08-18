# Descripciones de los scripts de copiar y pegar.
#
# Estos .ps1 no llevan bloque de ayuda a proposito: se pegan enteros en la consola y
# cualquier comentario es ruido para la IA que despues analiza la salida. Sus
# descripciones viven aqui, y de aqui las lee 99-repo-tools/03-generate-readme.ps1.
#
# Paste-ready scripts have no help block on purpose: they get pasted whole into the
# console, and any comment is noise for the AI that later parses the output. Their
# descriptions live here, and 03-generate-readme.ps1 reads them from here.

@{
    '01-cached-accounts.ps1' = @{
        ES = 'Inventario de cuentas cacheadas: origen de cada una, deteccion de UPN GUID y tenantId real de cada dominio'
        EN = 'Cached account inventory: source of each one, GUID UPN detection and real tenantId per domain'
    }
    '02-onedrive-status.ps1' = @{
        ES = 'Estado de OneDrive: proceso, version, cuentas vinculadas, ACE de denegacion, prueba de escritura y frescura de logs'
        EN = 'OneDrive state: process, version, linked accounts, deny ACEs, write test and log freshness'
    }
    '03-endpoint-report.ps1' = @{
        ES = 'Ficha del equipo: hardware, generacion real de Windows, join, MDM, disco, BitLocker, red y Office'
        EN = 'Machine snapshot: hardware, real Windows generation, join, MDM, disk, BitLocker, network and Office'
    }
    '04-m365-connectivity.ps1' = @{
        ES = 'Alcance a M365: proxy, DNS, TCP 443, version de TLS y latencia contra 7 endpoints'
        EN = 'M365 reachability: proxy, DNS, TCP 443, TLS version and latency across 7 endpoints'
    }
    '05-office-outlook-status.ps1' = @{
        ES = 'Estado de Office y Outlook: version, licencia, identidades, perfiles, .ost/.pst, complementos y elementos deshabilitados'
        EN = 'Office and Outlook state: version, licence, identities, profiles, .ost/.pst, add-ins and disabled items'
    }
    '06-eset-status.ps1' = @{
        ES = 'Estado de ESET: instalacion, servicios, firma del binario, enrolamiento en el trace y conectividad con ESET PROTECT'
        EN = 'ESET state: installation, services, binary signature, enrolment from the trace log and ESET PROTECT connectivity'
    }
    '91-long-paths.txt' = @{
        ES = 'Comandos para tratar rutas que superan MAX_PATH en OneDrive e iManage'
        EN = 'Commands for handling paths beyond MAX_PATH in OneDrive and iManage'
    }
}
