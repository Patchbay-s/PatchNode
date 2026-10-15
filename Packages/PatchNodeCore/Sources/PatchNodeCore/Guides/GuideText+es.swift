// Spanish translations of the built-in guides, keyed by the English text.
// Generated from the translation tables; to be proofread by a native speaker.
// A missing entry falls back to English (GuideLibraryTests checks there is none).

extension GuideText {
    static let es: [String: String] = [
        "Disks in standby: reading SMART makes Proxmox run smartctl on every disk, which wakes up disks that went to sleep (spindown). PatchNode reads the disks only as you choose for each service in Disk health: Off (no request to the disks at all, no disk notification), On demand (the default: only with the button) or Automatic, once a day from a chosen time. A read covers the disk list with SMART and the ZFS pools; in between, the screen and the disk notifications use the last read, with its date. Pick a time when the disks already spin, for example during a scheduled backup.":
            "Discos en reposo: leer SMART hace que Proxmox ejecute smartctl en cada disco, lo que despierta los discos dormidos (spindown). PatchNode solo lee los discos como elijas para cada servicio en Salud de los discos: Desactivado (ninguna petición a los discos, ninguna notificación de disco), Bajo demanda (por defecto: solo con el botón) o Automático, una vez al día a partir de una hora elegida. Una lectura incluye la lista de discos con SMART y los pools ZFS; entre dos lecturas, la pantalla y las notificaciones de disco usan la última lectura, con su fecha. Elige una hora en la que los discos ya giren, por ejemplo durante una copia de seguridad programada.",
        "1. VPN. With Tailscale, install it on the server running the reverse proxy and on the iPhone, then advertise your LAN as a subnet route:":
            "1. VPN. Con Tailscale, instálalo en el servidor del proxy inverso y en el iPhone, y anuncia tu LAN como ruta de subred:",
        "100.64.0.0/10 is Tailscale's range. Select this Access List on each proxy host. Other proxies (Traefik, Caddy) have an equivalent IP allow-list.":
            "100.64.0.0/10 es el rango de Tailscale. Elige esta Access List en cada proxy host. Otros proxies (Traefik, Caddy) tienen una lista de IP permitidas equivalente.",
        "2. Split DNS. Give every service a name in your domain (proxmox.example.invalid…) that resolves to the reverse proxy's LAN address, for example with an AdGuard Home or Pi-hole rewrite:":
            "2. Split DNS. Da a cada servicio un nombre en tu dominio (proxmox.example.invalid…) que resuelva a la dirección LAN del proxy inverso, por ejemplo con una reescritura de AdGuard Home o Pi-hole:",
        "3. Certificate. A wildcard certificate for *.example.com from Let's Encrypt with a DNS challenge works without opening any port to the internet.":
            "3. Certificado. Un certificado comodín para *.example.com de Let's Encrypt con desafío DNS funciona sin abrir ningún puerto a internet.",
        "301 Moved Permanently":
            "301 Moved Permanently",
        "400 Bad Request behind the proxy":
            "400 Bad Request detrás del proxy",
        "403: scope missing":
            "403: falta un scope",
        "421 Misdirected Request":
            "421 Misdirected Request",
        "A VPN such as Tailscale or WireGuard for access from outside.":
            "Una VPN como Tailscale o WireGuard para acceder desde fuera.",
        "A bouncer key only reads decisions: it can't add or remove any. PatchNode has no action on CrowdSec.":
            "Una clave de bouncer solo lee decisiones: no puede añadir ni quitar ninguna. PatchNode no tiene acciones sobre CrowdSec.",
        "A cluster is one service: add any of its nodes. Nodes outside a cluster are separate services: add one service per node.":
            "Un clúster es un servicio: añade cualquiera de sus nodos. Los nodos fuera de un clúster son servicios distintos: añade un servicio por nodo.",
        "A dashboard asks to sign in":
            "Un panel pide iniciar sesión",
        "A non-admin user can read states and call services, but not change the configuration. PatchNode only runs the scenes and scripts you pinned, after a confirmation.":
            "Un usuario no administrador puede leer estados y llamar a servicios, pero no cambiar la configuración. PatchNode solo ejecuta las escenas y scripts que hayas fijado, tras una confirmación.",
        "A saved chart shows an error":
            "Un gráfico guardado muestra un error",
        "API Token tab › Add: user monitor@pbs, Token Name patchnode. Copy the secret.":
            "Pestaña API Token › Add: usuario monitor@pbs, Token Name patchnode. Copia el secreto.",
        "Access List: allow your LAN and VPN ranges (100.64.0.0/10 for Tailscale).":
            "Access List: permite los rangos de tu LAN y tu VPN (100.64.0.0/10 para Tailscale).",
        "Access Lists › Add Access List › Details: tick Satisfy All (both the password and the address are required).":
            "Access Lists › Add Access List › Details: marca Satisfy All (se exigen la contraseña y la dirección).",
        "Access blocked by the reverse proxy (403 page)":
            "Acceso bloqueado por el proxy inverso (página 403)",
        "Access restricted to your LAN and VPN.":
            "Acceso restringido a tu LAN y tu VPN.",
        "Access tab: allow 192.0.2.0/24 and 100.64.0.0/10, deny all.":
            "Pestaña Access: permite 192.0.2.0/24 y 100.64.0.0/10, deniega todo lo demás.",
        "Access token rejected (401)":
            "Token de acceso rechazado (401)",
        "Actions: POST=1, only while you need them. With POST=0, PatchNode shows “actions disabled”.":
            "Acciones: POST=1, solo mientras las necesites. Con POST=0, PatchNode muestra «acciones desactivadas».",
        "Actions: rather than PVEVMUser (which also allows the console and more), create a role with the VM.PowerMgmt privilege only, on /vms, or /vms/100 for a single VM, with PVEAuditor next to it (see the warning below):":
            "Acciones: en lugar de PVEVMUser (que también permite la consola y más), crea un rol solo con el privilegio VM.PowerMgmt, en /vms, o /vms/100 para una sola VM, junto con PVEAuditor (ver la advertencia más abajo):",
        "Active alerts sorted by severity.":
            "Alertas activas ordenadas por gravedad.",
        "Active bans of your Local API.":
            "Bloqueos activos de tu Local API.",
        "AdGuard Home":
            "AdGuard Home",
        "AdGuard Home compares with the bcrypt hash of AdGuardHome.yaml: generate it again, then restart AdGuard Home.":
            "AdGuard Home compara con el hash bcrypt de AdGuardHome.yaml: vuelve a generarlo y reinicia AdGuard Home.",
        "AdGuard Home has no read-only role: this user can change the DNS settings. Keep AdGuard Home reachable only through your LAN and VPN. PatchNode only reads.":
            "AdGuard Home no tiene rol de solo lectura: este usuario puede cambiar los ajustes DNS. Mantén AdGuard Home accesible solo a través de tu LAN y tu VPN. PatchNode solo lee.",
        "Add a dedicated user to the users section of AdGuardHome.yaml, with a bcrypt password hash, then restart AdGuard Home:":
            "Añade un usuario dedicado a la sección users de AdGuardHome.yaml, con un hash bcrypt de la contraseña, y reinicia AdGuard Home:",
        "Add service account token, no expiry or a long one. Copy it (glsa_…).":
            "Add service account token, sin caducidad o con una larga. Cópialo (glsa_…).",
        "Add the monitors to show, then Save.":
            "Añade los monitores que mostrar y pulsa Save.",
        "Administration › User-related › Users › Add user: a standard (non-admin) user, e.g. patchnode.":
            "Administration › User-related › Users › Add user: un usuario estándar (no administrador), p. ej. patchnode.",
        "Administration › Users and access › Service accounts › Add service account: name patchnode, role Viewer.":
            "Administration › Users and access › Service accounts › Add service account: nombre patchnode, rol Viewer.",
        "Alertmanager":
            "Alertmanager",
        "Allow-list the same ranges in your IPS, so a wrong token (repeated 401/403) never bans your own phone. With CrowdSec:":
            "Añade los mismos rangos a la lista blanca de tu IPS, para que un token erróneo (401/403 repetidos) nunca bloquee tu propio teléfono. Con CrowdSec:",
        "Allow-list your LAN and VPN in CrowdSec (see Network prerequisites), so a wrong key never bans your own phone.":
            "Añade tu LAN y tu VPN a la lista blanca de CrowdSec (ver Requisitos de red), para que una clave errónea nunca bloquee tu propio teléfono.",
        "An HTTPS reverse proxy with a valid certificate in front of every service (PatchNode refuses plain HTTP and invalid certificates).":
            "Un proxy inverso HTTPS con un certificado válido delante de cada servicio (PatchNode rechaza HTTP sin cifrar y los certificados no válidos).",
        "An action refused with “insufficient rights” needs VM.PowerMgmt (the PatchNodePower role in Minimum rights).":
            "Una acción rechazada por «derechos insuficientes» necesita VM.PowerMgmt (el rol PatchNodePower de Derechos mínimos).",
        "An alert is missing":
            "Falta una alerta",
        "An environment shows as unreachable":
            "Un entorno aparece como inaccesible",
        "Attach Nginx Proxy Manager's container to the same proxy network. If the reverse proxy runs on another host, publish the port on the LAN address only (never 0.0.0.0) and let only the proxy's address through:":
            "Conecta el contenedor de Nginx Proxy Manager a la misma red proxy. Si el proxy inverso está en otro host, publica el puerto solo en la dirección LAN (nunca 0.0.0.0) y deja pasar solo la dirección del proxy:",
        "Authorization tab: add a user name and password.":
            "Pestaña Authorization: añade un usuario y una contraseña.",
        "Banned by CrowdSec or fail2ban: list and remove the decision, then allow-list your ranges (see Network prerequisites).":
            "Bloqueado por CrowdSec o fail2ban: lista y elimina la decisión, y añade tus rangos a la lista blanca (ver Requisitos de red).",
        "Business Edition: give the user the Read-only user role for reading only. Community Edition has no read-only role: a standard user can act on the containers of its environments.":
            "Business Edition: da al usuario el rol Read-only user para solo lectura. Community Edition no tiene rol de solo lectura: un usuario estándar puede actuar sobre los contenedores de sus entornos.",
        "CONTAINERS=1 also lets the reader see containers' environment variables, which often hold passwords. That's why the proxy must require authentication and stay on your LAN.":
            "CONTAINERS=1 también permite ver las variables de entorno de los contenedores, que a menudo contienen contraseñas. Por eso el proxy debe exigir autenticación y quedarse en tu LAN.",
        "CPU, memory, load, disks and temperatures of a host.":
            "CPU, memoria, carga, discos y temperaturas de un host.",
        "Check it hasn't expired or been revoked in the service.":
            "Comprueba que no haya caducado ni se haya revocado en el servicio.",
        "Check it with curl (Verify section of the service's guide).":
            "Compruébalo con curl (sección Verificar de la guía del servicio).",
        "Check the host's load.":
            "Comprueba la carga del host.",
        "Client rejected (401)":
            "Cliente rechazado (401)",
        "Configuration › Access Control › User Management › Add: user monitor, realm pbs (monitor@pbs).":
            "Configuration › Access Control › User Management › Add: usuario monitor, realm pbs (monitor@pbs).",
        "Containers and stacks of every Docker environment managed by Portainer.":
            "Contenedores y stacks de cada entorno Docker gestionado por Portainer.",
        "Containers of a Docker host through a read-only socket proxy.":
            "Contenedores de un host Docker a través de un socket proxy de solo lectura.",
        "Copy the client ID and the client secret (tskey-client-…), shown once.":
            "Copia el client ID y el client secret (tskey-client-…), que solo se muestran una vez.",
        "Copy the key (shown once) and paste it in PatchNode.":
            "Copia la clave (solo se muestra una vez) y pégala en PatchNode.",
        "Copy the secret now: Proxmox shows it only once.":
            "Copia el secreto ahora: Proxmox solo lo muestra una vez.",
        "Copy the token (shown once) and paste it in PatchNode.":
            "Copia el token (solo se muestra una vez) y pégalo en PatchNode.",
        "Copy the token again: a missing character, a space or a line break is enough to break it.":
            "Vuelve a copiar el token: basta un carácter de menos, un espacio o un salto de línea para estropearlo.",
        "Create an access token (My account › Access tokens), not an Edge key or an API key of another tool.":
            "Crea un token de acceso (My account › Access tokens), no una clave Edge ni una clave API de otra herramienta.",
        "CrowdSec":
            "CrowdSec",
        "CrowdSec answers 403 for an unknown key. Check it with cscli bouncers list, or create a new one.":
            "CrowdSec responde 403 a una clave desconocida. Compruébala con cscli bouncers list o crea una nueva.",
        "Dashboards and Grafana alerts.":
            "Paneles y alertas de Grafana.",
        "Datacenter › Permissions › API Tokens › Add: user monitor@pve, Token ID patchnode. Keep Privilege Separation ticked (recommended).":
            "Datacenter › Permissions › API Tokens › Add: usuario monitor@pve, Token ID patchnode. Deja marcado Privilege Separation (recomendado).",
        "Datacenter › Permissions › Users › Add: user monitor, realm Proxmox VE authentication server (monitor@pve). No password is needed for API use.":
            "Datacenter › Permissions › Users › Add: usuario monitor, realm Proxmox VE authentication server (monitor@pve). No hace falta contraseña para usar la API.",
        "Datastores, latest backup of every guest, failed jobs.":
            "Datastores, última copia de cada invitado, tareas fallidas.",
        "Devices of your tailnet: online, offline, keys about to expire.":
            "Dispositivos de tu tailnet: conectados, desconectados, claves a punto de caducar.",
        "Devices › Core › Read only. PatchNode has no action on Tailscale.":
            "Devices › Core › solo Read. PatchNode no tiene acciones sobre Tailscale.",
        "Docker (socket proxy)":
            "Docker (socket proxy)",
        "Does split DNS answer through the VPN? Otherwise the name resolves to nothing, or to a public address.":
            "¿Responde el split DNS a través de la VPN? Si no, el nombre no resuelve a nada, o a una dirección pública.",
        "Does the Access List allow 100.64.0.0/10?":
            "¿Permite la Access List 100.64.0.0/10?",
        "Does the name resolve? A typo in the URL gives the same error.":
            "¿Resuelve el nombre? Una errata en la URL da el mismo error.",
        "Don't set listen_uri to the LAN address alone: cscli and the bouncers on 127.0.0.1 would lose the API and bans would stop being applied. cscli lapi status must still answer.":
            "No pongas listen_uri solo en la dirección LAN: cscli y los bouncers en 127.0.0.1 perderían la API y los bloqueos dejarían de aplicarse. cscli lapi status debe seguir respondiendo.",
        "Don't use the API access keys of Settings › Keys: they expire within 90 days and carry all your rights. The OAuth client is limited to reading devices, and PatchNode exchanges it for a one-hour token kept in memory only.":
            "No uses las claves de acceso API de Settings › Keys: caducan en 90 días y tienen todos tus derechos. El cliente OAuth se limita a leer los dispositivos, y PatchNode lo cambia por un token de una hora guardado solo en memoria.",
        "E-mail or password rejected":
            "Correo o contraseña rechazados",
        "Empty list, or “token without rights”":
            "Lista vacía, o «token sin derechos»",
        "Enter client-id:client-secret, separated by a colon.":
            "Introduce client-id:client-secret, separados por dos puntos.",
        "Enter the user and password of the Access List's Authorization tab, not those of Nginx Proxy Manager's admin.":
            "Introduce el usuario y la contraseña de la pestaña Authorization de la Access List, no los del administrador de Nginx Proxy Manager.",
        "Environments › your environment › Manage access: give this user access to the environments to monitor.":
            "Environments › tu entorno › Manage access: da a este usuario acceso a los entornos que supervisar.",
        "From a computer on the VPN, check that the name resolves to the proxy and that the certificate is valid:":
            "Desde un ordenador en la VPN, comprueba que el nombre resuelve al proxy y que el certificado es válido:",
        "Generate a new client with Devices › Core › Read.":
            "Genera un cliente nuevo con Devices › Core › Read.",
        "Give PatchNode dedicated accounts and tokens, read-only first. Add the rights for actions (start, stop, restart) only once reading works, and only on what you want to control.":
            "Da a PatchNode cuentas y tokens dedicados, primero de solo lectura. Añade los derechos para acciones (iniciar, detener, reiniciar) solo cuando la lectura funcione, y solo sobre lo que quieras controlar.",
        "Give the user View Only on Proxy Hosts (Users › the user › Permissions).":
            "Da al usuario View Only en Proxy Hosts (Users › el usuario › Permissions).",
        "Glances":
            "Glances",
        "Glances 3 answers on /api/3/cpu; PatchNode tries both.":
            "Glances 3 responde en /api/3/cpu; PatchNode prueba ambos.",
        "Glances only reads. With --password, it asks for a password (default user glances): enter the user and password in PatchNode; without it, leave both fields empty and rely on the Access List.":
            "Glances solo lee. Con --password, pide una contraseña (usuario por defecto glances): introduce el usuario y la contraseña en PatchNode; sin ella, deja ambos campos vacíos y confía en la Access List.",
        "Grafana":
            "Grafana",
        "Grant Audit on / to the user and the token. A datastore refused alone (per-datastore permissions) is shown without its details.":
            "Concede Audit en / al usuario y al token. Un datastore rechazado por separado (permisos por datastore) se muestra sin sus detalles.",
        "Home Assistant":
            "Home Assistant",
        "Home Assistant must trust the proxy, in configuration.yaml:":
            "Home Assistant debe confiar en el proxy, en configuration.yaml:",
        "Home Assistant refuses forwarded requests from an untrusted proxy: add use_x_forwarded_for and trusted_proxies (Reverse proxy section), then restart.":
            "Home Assistant rechaza las peticiones reenviadas por un proxy no fiable: añade use_x_forwarded_for y trusted_proxies (sección Proxy inverso) y reinicia.",
        "If it keeps happening, Settings › Diagnostics shows the requests (protocol, connection reused). That log contains your services' names and API paths: read it before sharing it with anyone.":
            "Si sigue pasando, Ajustes › Diagnóstico muestra las peticiones (protocolo, conexión reutilizada). Ese registro contiene los nombres de tus servicios y las rutas de API: léelo antes de compartirlo.",
        "In PatchNode, enter client-id:client-secret. No URL to type.":
            "En PatchNode, introduce client-id:client-secret. No hay que escribir URL.",
        "In PatchNode, enter the e-mail and the password. PatchNode gets a session token from them, kept in memory only.":
            "En PatchNode, introduce el correo y la contraseña. PatchNode obtiene con ellos un token de sesión, guardado solo en memoria.",
        "In PatchNode, enter the same user name and password in the two fields.":
            "En PatchNode, introduce el mismo usuario y contraseña en los dos campos.",
        "In PatchNode, enter the status page's URL, ending with /status/<slug>. No token.":
            "En PatchNode, introduce la URL de la página de estado, terminada en /status/<slug>. Sin token.",
        "In PatchNode, enter this user name and password.":
            "En PatchNode, introduce este usuario y contraseña.",
        "In PatchNode, open Home Assistant › Choose entities.":
            "En PatchNode, abre Home Assistant › Elegir entidades.",
        "In PatchNode, paste the full value: user@realm!tokenid=secret.":
            "En PatchNode, pega el valor completo: user@realm!tokenid=secret.",
        "In PatchNode, paste the token.":
            "En PatchNode, pega el token.",
        "In PatchNode, paste user@realm!tokenid:secret — with a colon, unlike Proxmox VE.":
            "En PatchNode, pega user@realm!tokenid:secret, con dos puntos, a diferencia de Proxmox VE.",
        "In PatchNode, use Portainer's own URL and paste the token.":
            "En PatchNode, usa la URL del propio Portainer y pega el token.",
        "In Nginx Proxy Manager, create an Access List with a user and password, and your LAN and VPN ranges:":
            "En Nginx Proxy Manager, crea una Access List con un usuario y una contraseña, y los rangos de tu LAN y tu VPN:",
        "In Uptime Kuma, Status Pages › New Status Page: a name and a slug, e.g. homelab.":
            "En Uptime Kuma, Status Pages › New Status Page: un nombre y un slug, p. ej. homelab.",
        "In the Tailscale admin console, Machines › the server › Edit route settings: approve the route.":
            "En la consola de administración de Tailscale, Machines › el servidor › Edit route settings: aprueba la ruta.",
        "In the Tailscale admin console: Settings › Trust credentials (formerly OAuth clients) › Generate OAuth client.":
            "En la consola de administración de Tailscale: Settings › Trust credentials (antes OAuth clients) › Generate OAuth client.",
        "In zsh and bash, the ! of the token name must be inside single quotes ('monitor@pve!patchnode'), otherwise the shell tries to expand it.":
            "En zsh y bash, el ! del nombre del token debe ir entre comillas simples ('monitor@pve!patchnode'); si no, el shell intenta expandirlo.",
        "Insufficient rights (403 from the service)":
            "Derechos insuficientes (403 del servicio)",
        "Is the VPN connected on the iPhone?":
            "¿Está conectada la VPN en el iPhone?",
        "Is the certificate valid for this name? PatchNode refuses invalid and self-signed certificates.":
            "¿Es válido el certificado para este nombre? PatchNode rechaza los certificados no válidos y autofirmados.",
        "Is the reverse proxy up, and the service behind it?":
            "¿Están en marcha el proxy inverso y el servicio que hay detrás?",
        "Is the subnet route approved in the Tailscale admin console?":
            "¿Está aprobada la ruta de subred en la consola de administración de Tailscale?",
        "It works at home but not outside":
            "Funciona en casa pero no fuera",
        "It's the only service reached outside your private network: api.tailscale.com.":
            "Es el único servicio contactado fuera de tu red privada: api.tailscale.com.",
        "Key rejected (403 from CrowdSec)":
            "Clave rechazada (403 de CrowdSec)",
        "PatchNode lists active decisions (bans and captchas) from local detections and manual bans: IP or range, scenario, time left. Community blocklists aren't listed.":
            "PatchNode muestra las decisiones activas (bloqueos y captchas) de las detecciones locales y los bloqueos manuales: IP o rango, escenario, tiempo restante. Las listas de bloqueo de la comunidad no se muestran.",
        "PatchNode lists every Docker environment of Portainer, their containers grouped by stack, with health, logs, CPU and memory, and can start, stop and restart a container.":
            "PatchNode muestra cada entorno Docker de Portainer y sus contenedores agrupados por stack, con salud, registros, CPU y memoria, y puede iniciar, detener y reiniciar un contenedor.",
        "PatchNode lists the host's containers grouped by Compose project, with health, status, image, CPU and memory, logs, ports and volumes. With POST allowed, it can start, stop and restart a container.":
            "PatchNode muestra los contenedores del host agrupados por proyecto Compose, con salud, estado, imagen, CPU y memoria, registros, puertos y volúmenes. Con POST permitido, puede iniciar, detener y reiniciar un contenedor.",
        "PatchNode lists the scrape targets with those down first, and draws the PromQL queries you save as charts (CPU, memory, disks…).":
            "PatchNode muestra los destinos de scrape, primero los caídos, y dibuja como gráficos las consultas PromQL que guardes (CPU, memoria, discos…).",
        "PatchNode lists your dashboards (they open in an embedded browser where you sign in as usual) and shows Grafana's unified alerting alerts with the others.":
            "PatchNode muestra tus paneles (se abren en un navegador integrado donde inicias sesión como siempre) y las alertas del unified alerting de Grafana junto a las demás.",
        "PatchNode lists your proxy hosts: enabled or not, destination, certificate, and in red those nginx refused (bad upstream, configuration error).":
            "PatchNode muestra tus proxy hosts: activados o no, destino, certificado, y en rojo los que nginx rechazó (upstream incorrecto, error de configuración).",
        "PatchNode lists your tailnet's devices: online or last seen, address, OS, and flags those offline for more than a day, keys expiring within 14 days and devices waiting for approval.":
            "PatchNode muestra los dispositivos de tu tailnet: conectado o última vez visto, dirección, sistema, y señala los desconectados desde hace más de un día, las claves que caducan en menos de 14 días y los dispositivos pendientes de aprobación.",
        "PatchNode pauses the service and tries again after 30 s, 60 s, then every 2 minutes, to avoid being banned.":
            "PatchNode pone el servicio en pausa y vuelve a intentarlo tras 30 s, 60 s y luego cada 2 minutos, para evitar ser bloqueado.",
        "PatchNode reads a public status page of Uptime Kuma: each monitor's state, 24-hour uptime and latest heartbeats. A monitor down becomes an alert.":
            "PatchNode lee una página de estado pública de Uptime Kuma: estado de cada monitor, disponibilidad en 24 horas y últimos latidos. Un monitor caído se convierte en alerta.",
        "PatchNode shows Prometheus's own message. Test the query in Prometheus's web interface (Graph) first, then paste it again.":
            "PatchNode muestra el mensaje del propio Prometheus. Prueba primero la consulta en la interfaz web de Prometheus (Graph) y luego vuelve a pegarla.",
        "PatchNode shows a host's CPU, memory and swap, load, file systems (orange above 85 %) and temperatures.":
            "PatchNode muestra la CPU, la memoria y el swap, la carga, los sistemas de archivos (naranja por encima del 85 %) y las temperaturas de un host.",
        "PatchNode shows active alerts sorted by severity (critical, warning, info) with a badge on the tab. Silenced and inhibited alerts are left out.":
            "PatchNode muestra las alertas activas ordenadas por gravedad (critical, warning, info) con una insignia en la pestaña. Las alertas silenciadas e inhibidas se omiten.",
        "PatchNode shows each datastore's space, the latest backup of every VM and container (in orange after two days) and recent backup, verify, prune and garbage collection tasks.":
            "PatchNode muestra el espacio de cada datastore, la última copia de cada VM y contenedor (en naranja pasados dos días) y las tareas recientes de copia, verificación, purga y recolección de basura.",
        "PatchNode shows the sensors, lights and switches you pick, with their state, and can run the scenes and scripts you pick after a confirmation naming them.":
            "PatchNode muestra los sensores, luces e interruptores que elijas, con su estado, y puede ejecutar las escenas y scripts que elijas tras una confirmación que los nombra.",
        "PatchNode shows whether protection is on, the number of queries and the share blocked, the average processing time, and the most queried and blocked domains.":
            "PatchNode muestra si la protección está activada, el número de consultas y la parte bloqueada, el tiempo medio de procesamiento y los dominios más consultados y bloqueados.",
        "PatchNode shows your nodes (CPU, memory, disks, storage), every VM and container with charts per hour, day or week, and recent tasks with failures first. With the right role, it can start, shut down, stop or reboot a VM or container after a confirmation.":
            "PatchNode muestra tus nodos (CPU, memoria, discos, almacenamiento), cada VM y contenedor con gráficos por hora, día o semana, y las tareas recientes, primero las fallidas. Con el rol adecuado, puede iniciar, apagar, detener o reiniciar una VM o un contenedor tras una confirmación.",
        "PatchNode talks directly from your iPhone to your servers. Nothing goes through a server of ours, so your iPhone must reach them: at home on Wi-Fi, and elsewhere through a VPN.":
            "PatchNode habla directamente desde tu iPhone con tus servidores. Nada pasa por un servidor nuestro, así que tu iPhone debe alcanzarlos: en casa por Wi-Fi y fuera a través de una VPN.",
        "PatchNode waits 10 seconds per request. A slow VPN route, an overloaded host or a heavy endpoint can exceed it.":
            "PatchNode espera 10 segundos por petición. Una ruta VPN lenta, un host sobrecargado o un endpoint pesado pueden superarlos.",
        "Monitors of a status page, with uptime and latest heartbeats.":
            "Monitores de una página de estado, con disponibilidad y últimos latidos.",
        "Network prerequisites":
            "Requisitos de red",
        "Never expose /var/run/docker.sock or the raw port 2375, even on your LAN: whoever reaches it is root on the host. Always go through a socket proxy and an authenticated reverse proxy.":
            "Nunca expongas /var/run/docker.sock ni el puerto 2375 sin protección, ni siquiera en tu LAN: quien llegue a él es root en el host. Pasa siempre por un socket proxy y un proxy inverso con autenticación.",
        "Never expose these services directly to the internet: PatchNode doesn't need it.":
            "Nunca expongas estos servicios directamente a internet: PatchNode no lo necesita.",
        "Nginx Proxy Manager":
            "Nginx Proxy Manager",
        "No active local ban: the API answers null. PatchNode shows “No active bans”.":
            "Ningún bloqueo local activo: la API responde null. PatchNode muestra «Ningún bloqueo activo».",
        "No datastore, or 403":
            "Ningún datastore, o 403",
        "No proxy host listed":
            "No aparece ningún proxy host",
        "Nodes outside a cluster are separate services: add each one as its own service. PatchNode shows the service name first so they stay distinct.":
            "Los nodos fuera de un clúster son servicios distintos: añade cada uno como su propio servicio. PatchNode muestra primero el nombre del servicio para distinguirlos.",
        "Nodes, VMs and containers, storage, tasks, power actions.":
            "Nodos, VM y contenedores, almacenamiento, tareas, acciones de encendido.",
        "None: PatchNode calls api.tailscale.com directly, over HTTPS.":
            "Ninguno: PatchNode llama directamente a api.tailscale.com, por HTTPS.",
        "Nothing to create in Prometheus: PatchNode only reads its HTTP API. Add a proxy host in front of it (below), then the URL in PatchNode.":
            "Nada que crear en Prometheus: PatchNode solo lee su API HTTP. Añade un proxy host delante (abajo) y luego la URL en PatchNode.",
        "Nothing to create: PatchNode reads the v2 API. Set a severity label on your alert rules (critical, warning, info) to get them sorted.":
            "Nada que crear: PatchNode lee la API v2. Pon una etiqueta severity en tus reglas de alerta (critical, warning, info) para ordenarlas.",
        "Nothing to grant: only the monitors placed on this page are read. PatchNode has no action on Uptime Kuma.":
            "Nada que conceder: solo se leen los monitores de esta página. PatchNode no tiene acciones sobre Uptime Kuma.",
        "On the CrowdSec host, create a bouncer key for PatchNode:":
            "En el host de CrowdSec, crea una clave de bouncer para PatchNode:",
        "On the iPhone, open the Tailscale app and connect.":
            "En el iPhone, abre la app Tailscale y conéctate.",
        "PBS listens in HTTPS on port 8007: forward with the https scheme.":
            "PBS escucha en HTTPS en el puerto 8007: reenvía con el esquema https.",
        "PBS uses a colon between the token ID and the secret: user@realm!tokenid:secret.":
            "PBS usa dos puntos entre el ID del token y el secreto: user@realm!tokenid:secret.",
        "Paste the full value user@realm!tokenid=secret, with = before the secret.":
            "Pega el valor completo user@realm!tokenid=secret, con = antes del secreto.",
        "Permissions: Proxy Hosts › View Only, everything else Hidden.":
            "Permissions: Proxy Hosts › View Only, todo lo demás Hidden.",
        "Port 9443 is Portainer's HTTPS port (scheme https); 9000 is plain HTTP (scheme http).":
            "El puerto 9443 es el puerto HTTPS de Portainer (esquema https); el 9000 es HTTP sin cifrar (esquema http).",
        "Portainer":
            "Portainer",
        "Portainer itself can't reach this environment (agent stopped, host off). Check it in Portainer's Environments page.":
            "El propio Portainer no alcanza este entorno (agente detenido, host apagado). Compruébalo en la página Environments de Portainer.",
        "Privilege Separation is ticked and the token has no permission of its own, or its user has none: the token's rights are the intersection of both. Grant PVEAuditor on / to the user and to the token.":
            "Privilege Separation está marcado y el token no tiene permisos propios, o su usuario no tiene ninguno: los derechos del token son la intersección de ambos. Concede PVEAuditor en / al usuario y al token.",
        "Prometheus":
            "Prometheus",
        "Prometheus and Alertmanager have no token. Keep them on your LAN and VPN only; for a password, add an Access List with a user in Nginx Proxy Manager (Authorization tab, Satisfy All) and enter the same user and password in PatchNode. Without authentication, leave both fields empty.":
            "Prometheus y Alertmanager no tienen token. Mantenlos solo en tu LAN y tu VPN; para una contraseña, añade una Access List con un usuario en Nginx Proxy Manager (pestaña Authorization, Satisfy All) e introduce el mismo usuario y contraseña en PatchNode. Sin autenticación, deja ambos campos vacíos.",
        "Protection state and DNS statistics.":
            "Estado de la protección y estadísticas DNS.",
        "Proxmox Backup Server":
            "Proxmox Backup Server",
        "Proxmox VE":
            "Proxmox VE",
        "Proxmox itself listens in HTTPS on port 8006. In Nginx Proxy Manager, the proxy host must forward with the https scheme:":
            "Proxmox escucha en HTTPS en el puerto 8006. En Nginx Proxy Manager, el proxy host debe reenviar con el esquema https:",
        "Proxmox › Backups (Proxmox VE) lists the backup jobs, the guests no job covers, the latest archive of every guest (from the storages holding backups, NFS and Proxmox Backup Server storages included) and the failed backup tasks. It needs no other right than PVEAuditor.":
            "Proxmox › Copias (Proxmox VE) muestra las tareas de copia, los invitados que ninguna tarea cubre, el último archivo de cada invitado (en los almacenamientos con copias, incluidos NFS y Proxmox Backup Server) y las copias fallidas. No necesita más derecho que PVEAuditor.",
        "Proxmox › Disk health shows, for each online node, the SMART status and remaining life of every disk (Disks in the node's menu) and the state and fill of every ZFS pool. It needs Sys.Audit, which PVEAuditor on / already gives. SMART data comes from smartmontools on the node; disks behind a USB bridge or a RAID controller often report none.":
            "Proxmox › Salud de los discos muestra, para cada nodo en línea, el estado SMART y la vida restante de cada disco (Disks en el menú del nodo) y el estado y la ocupación de cada pool ZFS. Necesita Sys.Audit, que PVEAuditor en / ya da. Los datos SMART vienen de smartmontools en el nodo; los discos tras un adaptador USB o una controladora RAID a menudo no dan ninguno.",
        "Proxy host docker.example.com → http://docker-socket-proxy:2375 (same Docker network) with this Access List and your certificate.":
            "Proxy host docker.example.com → http://docker-socket-proxy:2375 (misma red Docker) con esta Access List y tu certificado.",
        "Proxy hosts, certificates, and hosts refused by nginx.":
            "Proxy hosts, certificados y hosts rechazados por nginx.",
        "Read-only: role Audit on /, for the user and the token (a token's rights are also limited by its user's). PatchNode has no action on PBS.":
            "Solo lectura: rol Audit en /, para el usuario y el token (los derechos de un token también están limitados por los de su usuario). PatchNode no tiene acciones sobre PBS.",
        "Reading: CONTAINERS=1, INFO=1, POST=0 (the default above).":
            "Lectura: CONTAINERS=1, INFO=1, POST=0 (el valor por defecto de arriba).",
        "Reading: role PVEAuditor on /. With Privilege Separation, a token only has the rights both it and its user have (the intersection): grant the role to both, or the lists stay empty.":
            "Lectura: rol PVEAuditor en /. Con Privilege Separation, un token solo tiene los derechos comunes a él y a su usuario (la intersección): concede el rol a ambos, o las listas quedarán vacías.",
        "Requests stay paused until you pull to refresh, so a wrong token isn't retried and can't get your IP banned. To change it: Settings › the service › enter the new token.":
            "Las peticiones quedan en pausa hasta que deslices para actualizar, así un token erróneo no se reintenta y no puede hacer que bloqueen tu IP. Para cambiarlo: Ajustes › el servicio › introduce el nuevo token.",
        "Restrict every proxy host to your LAN and VPN. In Nginx Proxy Manager: Access Lists › Add Access List › Access tab:":
            "Restringe cada proxy host a tu LAN y tu VPN. En Nginx Proxy Manager: Access Lists › Add Access List › pestaña Access:",
        "Role Viewer: it reads dashboards and alerts, and can't change anything. The token is never put in a dashboard URL.":
            "Rol Viewer: lee paneles y alertas y no puede cambiar nada. El token nunca va en la URL de un panel.",
        "Run Glances in web server mode, for example with Docker. --disable-plugin processlist makes each refresh much lighter:":
            "Ejecuta Glances en modo servidor web, por ejemplo con Docker. --disable-plugin processlist hace cada actualización mucho más ligera:",
        "Run tecnativa/docker-socket-proxy without publishing any port, on a Docker network shared with the reverse proxy: only the proxy (and its authentication) can reach it.":
            "Ejecuta tecnativa/docker-socket-proxy sin publicar ningún puerto, en una red Docker compartida con el proxy inverso: solo el proxy (y su autenticación) puede alcanzarlo.",
        "Scopes: Devices › Core, Read only. Nothing else.":
            "Scopes: Devices › Core, solo Read. Nada más.",
        "Service unreachable":
            "Servicio inaccesible",
        "Set a password for this user.":
            "Pon una contraseña a este usuario.",
        "Set root_url in grafana.ini to your public name, so links and sign-in redirect correctly:":
            "Configura root_url en grafana.ini con tu nombre público, para que los enlaces y el inicio de sesión redirijan bien:",
        "Settings › People › Add person: a dedicated user patchnode, allowed to log in, not an administrator.":
            "Settings › People › Add person: un usuario dedicado patchnode, con permiso para iniciar sesión, no administrador.",
        "Several services share one reverse proxy and one wildcard certificate: iOS may reuse an HTTP/2 connection opened for another name, and the proxy answers 421. PatchNode retries once on a new connection automatically.":
            "Varios servicios comparten un proxy inverso y un certificado comodín: iOS puede reutilizar una conexión HTTP/2 abierta para otro nombre, y el proxy responde 421. PatchNode reintenta automáticamente una vez con una conexión nueva.",
        "Sign in as this user, then My account › Access tokens › Add access token. Copy it (shown once).":
            "Inicia sesión con este usuario y luego My account › Access tokens › Add access token. Cópialo (solo se muestra una vez).",
        "Sign in as this user, then Profile › Security › Long-lived access tokens › Create token.":
            "Inicia sesión con este usuario y luego Perfil › Seguridad › Tokens de acceso de larga duración › Crear token.",
        "Silenced and inhibited alerts are not shown. Check Alertmanager's web interface (Silences).":
            "Las alertas silenciadas e inhibidas no se muestran. Revisa la interfaz web de Alertmanager (Silences).",
        "Slow refreshes or timeouts":
            "Actualizaciones lentas o tiempos agotados",
        "Split DNS so the same names work at home and through the VPN.":
            "Split DNS para que los mismos nombres funcionen en casa y a través de la VPN.",
        "Tailscale":
            "Tailscale",
        "Targets down and your own PromQL charts.":
            "Destinos caídos y tus propios gráficos PromQL.",
        "That's expected: the embedded browser uses your own Grafana session, separate from the token. The session is cleared when PatchNode goes to the background.":
            "Es normal: el navegador integrado usa tu propia sesión de Grafana, distinta del token. La sesión se borra cuando PatchNode pasa a segundo plano.",
        "The API also allows creating silences: keep Alertmanager on your LAN and VPN only, behind authentication. PatchNode only reads.":
            "La API también permite crear silencios: mantén Alertmanager solo en tu LAN y tu VPN, con autenticación. PatchNode solo lee.",
        "The HTTP API is read-only by default. Don't start Prometheus with --web.enable-admin-api or --web.enable-lifecycle behind this proxy host.":
            "La API HTTP es de solo lectura por defecto. No inicies Prometheus con --web.enable-admin-api ni --web.enable-lifecycle detrás de este proxy host.",
        "The Local API listens on 127.0.0.1:8080 by default, and cscli and the local bouncers use that address. Simplest: a reverse proxy on the same host forwards to 127.0.0.1:8080. Otherwise listen on all addresses and let only the proxy through the firewall:":
            "La Local API escucha en 127.0.0.1:8080 por defecto, y cscli y los bouncers locales usan esa dirección. Lo más sencillo: un proxy inverso en el mismo host reenvía a 127.0.0.1:8080. Si no, escucha en todas las direcciones y deja pasar solo al proxy por el cortafuegos:",
        "The URL must end with /status/<slug> — the slug chosen when creating the status page, not the dashboard URL.":
            "La URL debe terminar en /status/<slug>: el slug elegido al crear la página de estado, no la URL del panel.",
        "The admin interface (port 81) can be published by Nginx Proxy Manager itself, restricted to your LAN and VPN:":
            "La interfaz de administración (puerto 81) puede publicarla el propio Nginx Proxy Manager, restringida a tu LAN y tu VPN:",
        "The answer is an HTML 403 page: the reverse proxy refused the request before it reached the service. Your token isn't the cause.":
            "La respuesta es una página 403 en HTML: el proxy inverso rechazó la petición antes de que llegara al servicio. Tu token no es la causa.",
        "The answer is {\"message\":\"API running.\"}.":
            "La respuesta es {\"message\":\"API running.\"}.",
        "The client may have been revoked in Settings › Trust credentials.":
            "El cliente puede haberse revocado en Settings › Trust credentials.",
        "The entities you choose, scenes and scripts.":
            "Las entidades que elijas, escenas y scripts.",
        "The first command must print the proxy's LAN address; the second must answer without a certificate error.":
            "El primer comando debe mostrar la dirección LAN del proxy; el segundo debe responder sin error de certificado.",
        "The list is empty":
            "La lista está vacía",
        "The process list makes Glances's answer heavy. Start it with --disable-plugin processlist.":
            "La lista de procesos hace pesada la respuesta de Glances. Inícialo con --disable-plugin processlist.",
        "The reverse proxy forwards in http to port 8006. Set Scheme to https on the proxy host.":
            "El proxy inverso reenvía en http al puerto 8006. Pon Scheme en https en el proxy host.",
        "The same from the node's shell:":
            "Lo mismo desde el shell del nodo:",
        "The service answers too slowly (timeout)":
            "El servicio responde demasiado despacio (tiempo agotado)",
        "The socket proxy refuses POST requests: set POST=1 and recreate the container, only while you need actions.":
            "El socket proxy rechaza las peticiones POST: pon POST=1 y recrea el contenedor, solo mientras necesites acciones.",
        "The token is valid but not allowed to read this information. Grant the read-only role described in the Minimum rights section of the service's guide.":
            "El token es válido pero no puede leer esta información. Concede el rol de solo lectura descrito en la sección Derechos mínimos de la guía del servicio.",
        "The token may have expired (Expire field) or been deleted.":
            "El token puede haber caducado (campo Expire) o haberse eliminado.",
        "Then, in the Tailscale admin console, DNS › Nameservers › Add nameserver › Custom: your DNS server, restricted to your domain (Split DNS).":
            "Luego, en la consola de administración de Tailscale, DNS › Nameservers › Add nameserver › Custom: tu servidor DNS, restringido a tu dominio (Split DNS).",
        "This service goes through the internet, not your VPN: check the iPhone's internet access, or a DNS filter blocking tailscale.com.":
            "Este servicio pasa por internet, no por tu VPN: comprueba el acceso a internet del iPhone, o un filtro DNS que bloquee tailscale.com.",
        "Toggle the VPN off and on: PatchNode then opens new connections.":
            "Desactiva y vuelve a activar la VPN: PatchNode abrirá conexiones nuevas.",
        "Token or password rejected (401)":
            "Token o contraseña rechazados (401)",
        "Token rejected (401)":
            "Token rechazado (401)",
        "Tokens stay in the iPhone's Keychain (this device only) and are sent only to the service they belong to.":
            "Los tokens se quedan en el llavero del iPhone (solo este dispositivo) y solo se envían al servicio al que pertenecen.",
        "Try again on Wi-Fi at home to rule out the VPN.":
            "Vuelve a intentarlo con la Wi-Fi de casa para descartar la VPN.",
        "Two nodes named the same (pve)":
            "Dos nodos con el mismo nombre (pve)",
        "Type the token without it being displayed, then call the API:":
            "Escribe el token sin que se muestre y luego llama a la API:",
        "Uptime Kuma":
            "Uptime Kuma",
        "Use a service account token (glsa_…), not an API key from an older Grafana nor your password.":
            "Usa un token de cuenta de servicio (glsa_…), no una clave API de un Grafana antiguo ni tu contraseña.",
        "Use the dedicated user's e-mail and password. Two-factor authentication isn't supported: use a user without it.":
            "Usa el correo y la contraseña del usuario dedicado. La autenticación en dos pasos no es compatible: usa un usuario sin ella.",
        "User or password rejected":
            "Usuario o contraseña rechazados",
        "User or password rejected (401)":
            "Usuario o contraseña rechazados (401)",
        "Users › Add User: full name PatchNode, e-mail e.g. patchnode@example.com, not an administrator.":
            "Users › Add User: nombre completo PatchNode, correo p. ej. patchnode@example.com, no administrador.",
        "VPN connected? At home, is the iPhone on your Wi-Fi?":
            "¿VPN conectada? En casa, ¿está el iPhone en tu Wi-Fi?",
        "VPN off: turn it on, then pull to refresh.":
            "VPN desactivada: actívala y desliza para actualizar.",
        "VPN, HTTPS reverse proxy, split DNS, LAN-only access and IPS allow-list.":
            "VPN, proxy inverso HTTPS, split DNS, acceso solo desde la LAN y lista blanca del IPS.",
        "View Only on Proxy Hosts is enough. PatchNode has no action on Nginx Proxy Manager.":
            "Basta con View Only en Proxy Hosts. PatchNode no tiene acciones sobre Nginx Proxy Manager.",
        "With Scheme http, Proxmox answers 301 Moved Permanently and PatchNode can't read anything.":
            "Con Scheme http, Proxmox responde 301 Moved Permanently y PatchNode no puede leer nada.",
        "Without authentication, drop -u monitor.":
            "Sin autenticación, quita -u monitor.",
        "You should get a token in return.":
            "Deberías recibir un token como respuesta.",
        "You should see your datastores.":
            "Deberías ver tus datastores.",
        "You should see your environments.":
            "Deberías ver tus entornos.",
        "You should see your nodes, VMs and storage. A list with only nodes and no CPU or memory means the token lacks rights.":
            "Deberías ver tus nodos, VM y almacenamiento. Una lista solo con nodos y sin CPU ni memoria significa que al token le faltan derechos.",
        "Your LAN and VPN ranges allow-listed in your IPS (CrowdSec, fail2ban).":
            "Los rangos de tu LAN y tu VPN en la lista blanca de tu IPS (CrowdSec, fail2ban).",
        "api.tailscale.com unreachable":
            "api.tailscale.com inaccesible",
        "curl asks for the password, then prints the Docker version. Without the password you must get a 401.":
            "curl pide la contraseña y luego muestra la versión de Docker. Sin la contraseña debes recibir un 401.",
        "null means no active ban: that's a valid answer.":
            "null significa que no hay ningún bloqueo activo: es una respuesta válida.",
        "“Actions disabled” (403 from the socket proxy)":
            "«Acciones desactivadas» (403 del socket proxy)",
        "“Enter the status page URL”":
            "«Introduce la URL de la página de estado»",
        "Consoles: the Console button of a node, a container or a VM opens a terminal inside PatchNode (the node's shell, the container, or the VM's serial port), or the graphical console of a VM without a serial port. Face ID is asked every time. Consoles with an API token need Proxmox VE 9.1 or later.":
            "Consolas: el botón Consola de un nodo, un contenedor o una VM abre un terminal dentro de PatchNode (el shell del nodo, el contenedor o el puerto serie de la VM), o la consola gráfica de una VM sin puerto serie. Se pide Face ID cada vez. Las consolas con un token de API requieren Proxmox VE 9.1 o posterior.",
        "Consoles: a PatchNodeConsole role with VM.Console only, on the guest (/vms/101), and for a node's shell a PatchNodeNodeConsole role with Sys.Console only, on the node (/nodes/node-a) — never Sys.Console on a guest. On / (everything), the role alone is enough. A node's shell opened by another user than root@pam asks for a Linux login.":
            "Consolas: un rol PatchNodeConsole solo con VM.Console, en el invitado (/vms/101), y para el shell de un nodo un rol PatchNodeNodeConsole solo con Sys.Console, en el nodo (/nodes/node-a); nunca Sys.Console en un invitado. En / (todo), basta con el rol solo. El shell de un nodo abierto por otro usuario que root@pam pide un inicio de sesión de Linux.",
        "A console gives a shell on the guest or the node: grant it only where you need it.":
            "Una consola da un shell en el invitado o el nodo: concédela solo donde la necesites.",
        "Consoles go through a websocket: in Nginx Proxy Manager, Websockets Support must be on for the Proxmox host.":
            "Las consolas pasan por un websocket: en Nginx Proxy Manager, Websockets Support debe estar activado para el host de Proxmox.",
        "Console: the token lacks the console privilege":
            "Consola: el token no tiene el privilegio de consola",
        "Grant PatchNodeConsole on the guest (/vms/<id>) or PatchNodeNodeConsole on the node (/nodes/<node>), always with PVEAuditor, to the user and to the token (Minimum rights). PatchNode shows the exact commands to copy.":
            "Concede PatchNodeConsole en el invitado (/vms/<id>) o PatchNodeNodeConsole en el nodo (/nodes/<nodo>), siempre con PVEAuditor, al usuario y al token (Permisos mínimos). PatchNode muestra los comandos exactos para copiar.",
        "Console: Proxmox refused the token":
            "Consola: Proxmox rechazó el token",
        "Before Proxmox VE 9.1, consoles only accept a password session, not an API token. Update the nodes to 9.1 or later (apt full-upgrade).":
            "Antes de Proxmox VE 9.1, las consolas solo aceptan una sesión con contraseña, no un token de API. Actualiza los nodos a 9.1 o posterior (apt full-upgrade).",
        "Graphical console only: add a serial port":
            "Solo consola gráfica: añadir un puerto serie",
        "A VM gets a text terminal in PatchNode when it has a serial port. Add one, enable a login on it inside the VM, then restart the VM:":
            "Una VM tiene un terminal de texto en PatchNode cuando tiene un puerto serie. Añade uno, activa un inicio de sesión en él dentro de la VM y reinicia la VM:",
        "Without a serial port, PatchNode opens the VM's graphical console.":
            "Sin puerto serie, PatchNode abre la consola gráfica de la VM.",
        "SSH terminal":
            "Terminal SSH",
        "A dedicated user, this device's key, sudo or the docker group, risks and revocation.":
            "Un usuario dedicado, la clave de este dispositivo, sudo o el grupo docker, riesgos y revocación.",
        "PatchNode opens SSH sessions to your own servers (Proxmox nodes, Docker hosts, containers, VMs) and, for a Docker host, runs docker compose in a project's folder. It connects only to the hosts you add, with a key generated on this device; nothing goes through a server of ours.":
            "PatchNode abre sesiones SSH hacia tus propios servidores (nodos Proxmox, hosts Docker, contenedores, VM) y, para un host Docker, ejecuta docker compose en la carpeta de un proyecto. Solo se conecta a los hosts que añades, con una clave creada en este dispositivo; nada pasa por un servidor nuestro.",
        "Every session asks for Face ID. The first connection to a host shows its fingerprint: compare it with the server's own before trusting it. PatchNode then refuses any other key for that host.":
            "Cada sesión pide Face ID. La primera conexión a un host muestra su huella: compárala con la del servidor antes de confiar en ella. Después, PatchNode rechaza cualquier otra clave para ese host.",
        "On the server, create a dedicated user, for example patchnode.":
            "En el servidor, crea un usuario dedicado, por ejemplo patchnode.",
        "In PatchNode, Settings › SSH: turn on the SSH terminal, open This device's public key and copy the authorized_keys line.":
            "En PatchNode, Ajustes › SSH: activa el terminal SSH, abre la clave pública de este dispositivo y copia la línea authorized_keys.",
        "On the server, add the line to ~/.ssh/authorized_keys of that user (folder 700, file 600).":
            "En el servidor, añade la línea al ~/.ssh/authorized_keys de ese usuario (carpeta 700, archivo 600).",
        "Settings › SSH › Add a host: address, port, user. Link it to its Proxmox node or Docker host for the shortcuts.":
            "Ajustes › SSH › Añadir un host: dirección, puerto, usuario. Vincúlalo a su nodo Proxmox o host Docker para los atajos.",
        "Docker: add the user to the docker group so docker compose runs without sudo. The docker group is equivalent to root on that host: keep the key's from= restriction.":
            "Docker: añade el usuario al grupo docker para ejecutar docker compose sin sudo. El grupo docker equivale a root en ese host: mantén la restricción from= de la clave.",
        "Proxmox: “Enter the container” runs pct enter, which needs root. Connect as root with the key only (PermitRootLogin prohibit-password), or allow just that command with sudo (edit with visudo):":
            "Proxmox: «Entrar en el contenedor» ejecuta pct enter, que requiere root. Conéctate como root solo con la clave (PermitRootLogin prohibit-password), o permite solo ese comando con sudo (edítalo con visudo):",
        "Prefer the key to a password. A password is asked only when the server refuses the key, used for that connection, and never stored.":
            "Prefiere la clave a una contraseña. Solo se pide una contraseña si el servidor rechaza la clave; se usa para esa conexión y nunca se guarda.",
        "A session gives a full shell: whatever the user can do, PatchNode can do once unlocked.":
            "Una sesión da un shell completo: todo lo que el usuario puede hacer, PatchNode puede hacerlo una vez desbloqueado.",
        "Keep SSH reachable only through your VPN, never exposed on the internet.":
            "Mantén SSH accesible solo a través de tu VPN, nunca expuesto a internet.",
        "from= limits where the key is accepted from; the no-…-forwarding options limit what it can do.":
            "from= limita desde dónde se acepta la clave; las opciones no-…-forwarding limitan lo que puede hacer.",
        "Terminal content is never stored or logged; Diagnostics keep only the opening, closing, duration and error code.":
            "El contenido del terminal nunca se guarda ni se registra; Diagnóstico solo guarda la apertura, el cierre, la duración y el código de error.",
        "Lost device, or a key you no longer trust: delete its line from authorized_keys on every server. The comment at the end of the line (patchnode-iPhone-…) tells which device it is.":
            "Dispositivo perdido o clave en la que ya no confías: borra su línea de authorized_keys en cada servidor. El comentario al final de la línea (patchnode-iPhone-…) indica de qué dispositivo se trata.",
        "Settings › SSH › Replace the key creates a new key and deletes the old one from this device.":
            "Ajustes › SSH › Sustituir la clave crea una clave nueva y borra la anterior de este dispositivo.",
        "Host key changed? If you reinstalled the server, check its new fingerprint, then Settings › SSH › the host › Forget the host key.":
            "¿Cambió la clave del host? Si reinstalaste el servidor, comprueba su nueva huella y luego Ajustes › SSH › el host › Olvidar la clave del host.",
        "Connection refused or unreachable":
            "Conexión rechazada o inaccesible",
        "Check the VPN, the address and the port (22 by default), and that the SSH server runs on the host.":
            "Comprueba la VPN, la dirección y el puerto (22 por defecto), y que el servidor SSH funcione en el host.",
        "Key refused":
            "Clave rechazada",
        "The line is missing from that user's authorized_keys, or the file's permissions are too open (sshd then ignores it). The server's log says why:":
            "Falta la línea en el authorized_keys de ese usuario, o los permisos del archivo son demasiado abiertos (sshd lo ignora). El registro del servidor indica por qué:",
        "This rule is root in every container of the node, and nearly root on the node itself for a privileged container: keep it for a dedicated user, with the key's from= restriction.":
            "Esta regla equivale a root en todos los contenedores del nodo, y casi a root en el propio nodo para un contenedor privilegiado: resérvala a un usuario dedicado, con la restricción from= de la clave.",
        "A role on a deeper path replaces, for the same user or token, the roles inherited from above: PatchNodeConsole alone on /vms/101 takes PVEAuditor away there, and the guest vanishes from PatchNode. On any path other than /, always grant PVEAuditor with the role, and PatchNodePower too if the guest keeps its actions ('PVEAuditor,PatchNodePower,PatchNodeConsole'), to the user and to the token. Use a user dedicated to PatchNode: on your own account, such an ACL would also replace your other roles on that path.":
            "Un rol en una ruta más precisa sustituye, para el mismo usuario o token, los roles heredados de arriba: PatchNodeConsole solo en /vms/101 quita ahí PVEAuditor, y el invitado desaparece de PatchNode. En cualquier ruta distinta de /, concede siempre PVEAuditor con el rol, y también PatchNodePower si el invitado conserva sus acciones ('PVEAuditor,PatchNodePower,PatchNodeConsole'), al usuario y al token. Usa un usuario dedicado a PatchNode: en tu propia cuenta, una ACL así sustituiría también tus otros roles en esa ruta.",
        "Check the token's effective rights on a path (user, token ID, path):":
            "Comprueba los derechos efectivos del token en una ruta (usuario, ID del token, ruta):",
        "A guest vanished after a role was granted on its path (/vms/<id>, /vms): that ACL replaced PVEAuditor inherited from /. Grant 'PVEAuditor,<role>' on that path instead, then check:":
            "Un invitado desapareció tras conceder un rol en su ruta (/vms/<id>, /vms): esa ACL sustituyó el PVEAuditor heredado de /. Concede en su lugar 'PVEAuditor,<rol>' en esa ruta y luego comprueba:",
    ]
}
