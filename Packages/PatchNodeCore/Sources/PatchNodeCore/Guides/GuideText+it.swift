// Italian translations of the built-in guides, keyed by the English text.
// Generated from the translation tables; to be proofread by a native speaker.
// A missing entry falls back to English (GuideLibraryTests checks there is none).

extension GuideText {
    static let it: [String: String] = [
        "Disks in standby: reading SMART makes Proxmox run smartctl on every disk, which wakes up disks that went to sleep (spindown). PatchNode reads the disks only as you choose for each service in Disk health: Off (no request to the disks at all, no disk notification), On demand (the default: only with the button) or Automatic, once a day from a chosen time. A read covers the disk list with SMART and the ZFS pools; in between, the screen and the disk notifications use the last read, with its date. Pick a time when the disks already spin, for example during a scheduled backup.":
            "Dischi in standby: leggere SMART fa eseguire a Proxmox smartctl su ogni disco, il che risveglia i dischi addormentati (spindown). PatchNode legge i dischi solo come scegli per ogni servizio in Stato dei dischi: Disattivato (nessuna richiesta ai dischi, nessuna notifica sui dischi), Su richiesta (predefinito: solo con il pulsante) o Automatico, una volta al giorno a partire da un’ora scelta. Una lettura comprende l’elenco dei dischi con SMART e i pool ZFS; tra due letture, la schermata e le notifiche sui dischi usano l’ultima lettura, con la sua data. Scegli un’ora in cui i dischi girano già, per esempio durante un backup pianificato.",
        "1. VPN. With Tailscale, install it on the server running the reverse proxy and on the iPhone, then advertise your LAN as a subnet route:":
            "1. VPN. Con Tailscale, installalo sul server del reverse proxy e sull’iPhone, poi annuncia la tua LAN come route di sottorete:",
        "100.64.0.0/10 is Tailscale's range. Select this Access List on each proxy host. Other proxies (Traefik, Caddy) have an equivalent IP allow-list.":
            "100.64.0.0/10 è l’intervallo di Tailscale. Seleziona questa Access List su ogni proxy host. Altri proxy (Traefik, Caddy) hanno una allow-list di IP equivalente.",
        "2. Split DNS. Give every service a name in your domain (proxmox.example.invalid…) that resolves to the reverse proxy's LAN address, for example with an AdGuard Home or Pi-hole rewrite:":
            "2. Split DNS. Dai a ogni servizio un nome nel tuo dominio (proxmox.example.invalid…) che risolva all’indirizzo LAN del reverse proxy, per esempio con una riscrittura di AdGuard Home o Pi-hole:",
        "3. Certificate. A wildcard certificate for *.example.com from Let's Encrypt with a DNS challenge works without opening any port to the internet.":
            "3. Certificato. Un certificato wildcard per *.example.com da Let’s Encrypt con challenge DNS funziona senza aprire alcuna porta verso internet.",
        "301 Moved Permanently":
            "301 Moved Permanently",
        "400 Bad Request behind the proxy":
            "400 Bad Request dietro il proxy",
        "403: scope missing":
            "403: scope mancante",
        "421 Misdirected Request":
            "421 Misdirected Request",
        "A VPN such as Tailscale or WireGuard for access from outside.":
            "Una VPN come Tailscale o WireGuard per l’accesso dall’esterno.",
        "A bouncer key only reads decisions: it can't add or remove any. PatchNode has no action on CrowdSec.":
            "Una chiave bouncer legge solo le decisioni: non può aggiungerne né rimuoverne. PatchNode non ha azioni su CrowdSec.",
        "A cluster is one service: add any of its nodes. Nodes outside a cluster are separate services: add one service per node.":
            "Un cluster è un servizio: aggiungi uno qualsiasi dei suoi nodi. I nodi fuori da un cluster sono servizi distinti: aggiungi un servizio per nodo.",
        "A dashboard asks to sign in":
            "Una dashboard chiede di accedere",
        "A non-admin user can read states and call services, but not change the configuration. PatchNode only runs the scenes and scripts you pinned, after a confirmation.":
            "Un utente non amministratore può leggere gli stati e chiamare servizi, ma non modificare la configurazione. PatchNode esegue solo le scene e gli script che hai fissato, dopo una conferma.",
        "A saved chart shows an error":
            "Un grafico salvato mostra un errore",
        "API Token tab › Add: user monitor@pbs, Token Name patchnode. Copy the secret.":
            "Scheda API Token › Add: utente monitor@pbs, Token Name patchnode. Copia il segreto.",
        "Access List: allow your LAN and VPN ranges (100.64.0.0/10 for Tailscale).":
            "Access List: consenti gli intervalli della tua LAN e VPN (100.64.0.0/10 per Tailscale).",
        "Access Lists › Add Access List › Details: tick Satisfy All (both the password and the address are required).":
            "Access Lists › Add Access List › Details: spunta Satisfy All (servono sia la password sia l’indirizzo).",
        "Access blocked by the reverse proxy (403 page)":
            "Accesso bloccato dal reverse proxy (pagina 403)",
        "Access restricted to your LAN and VPN.":
            "Accesso limitato alla tua LAN e VPN.",
        "Access tab: allow 192.0.2.0/24 and 100.64.0.0/10, deny all.":
            "Scheda Access: consenti 192.0.2.0/24 e 100.64.0.0/10, nega tutto il resto.",
        "Access token rejected (401)":
            "Token di accesso rifiutato (401)",
        "Actions: POST=1, only while you need them. With POST=0, PatchNode shows “actions disabled”.":
            "Azioni: POST=1, solo finché ti servono. Con POST=0, PatchNode mostra «azioni disattivate».",
        "Actions: rather than PVEVMUser (which also allows the console and more), create a role with the VM.PowerMgmt privilege only, on /vms, or /vms/100 for a single VM, with PVEAuditor next to it (see the warning below):":
            "Azioni: invece di PVEVMUser (che permette anche la console e altro), crea un ruolo con il solo privilegio VM.PowerMgmt, su /vms, o /vms/100 per una sola VM, insieme a PVEAuditor (vedi l’avvertenza più sotto):",
        "Active alerts sorted by severity.":
            "Allerte attive ordinate per gravità.",
        "Active bans of your Local API.":
            "Ban attivi della tua Local API.",
        "AdGuard Home":
            "AdGuard Home",
        "AdGuard Home compares with the bcrypt hash of AdGuardHome.yaml: generate it again, then restart AdGuard Home.":
            "AdGuard Home confronta con l’hash bcrypt di AdGuardHome.yaml: rigeneralo, poi riavvia AdGuard Home.",
        "AdGuard Home has no read-only role: this user can change the DNS settings. Keep AdGuard Home reachable only through your LAN and VPN. PatchNode only reads.":
            "AdGuard Home non ha un ruolo in sola lettura: questo utente può modificare le impostazioni DNS. Rendi AdGuard Home raggiungibile solo dalla tua LAN e VPN. PatchNode legge soltanto.",
        "Add a dedicated user to the users section of AdGuardHome.yaml, with a bcrypt password hash, then restart AdGuard Home:":
            "Aggiungi un utente dedicato alla sezione users di AdGuardHome.yaml, con un hash bcrypt della password, poi riavvia AdGuard Home:",
        "Add service account token, no expiry or a long one. Copy it (glsa_…).":
            "Add service account token, senza scadenza o con una lunga. Copialo (glsa_…).",
        "Add the monitors to show, then Save.":
            "Aggiungi i monitor da mostrare, poi Save.",
        "Administration › User-related › Users › Add user: a standard (non-admin) user, e.g. patchnode.":
            "Administration › User-related › Users › Add user: un utente standard (non admin), es. patchnode.",
        "Administration › Users and access › Service accounts › Add service account: name patchnode, role Viewer.":
            "Administration › Users and access › Service accounts › Add service account: nome patchnode, ruolo Viewer.",
        "Alertmanager":
            "Alertmanager",
        "Allow-list the same ranges in your IPS, so a wrong token (repeated 401/403) never bans your own phone. With CrowdSec:":
            "Metti gli stessi intervalli nella allow-list del tuo IPS, così un token sbagliato (401/403 ripetuti) non banna mai il tuo telefono. Con CrowdSec:",
        "Allow-list your LAN and VPN in CrowdSec (see Network prerequisites), so a wrong key never bans your own phone.":
            "Metti la tua LAN e VPN nella allow-list di CrowdSec (vedi Requisiti di rete), così una chiave sbagliata non banna mai il tuo telefono.",
        "An HTTPS reverse proxy with a valid certificate in front of every service (PatchNode refuses plain HTTP and invalid certificates).":
            "Un reverse proxy HTTPS con un certificato valido davanti a ogni servizio (PatchNode rifiuta HTTP in chiaro e certificati non validi).",
        "An action refused with “insufficient rights” needs VM.PowerMgmt (the PatchNodePower role in Minimum rights).":
            "Un’azione rifiutata per «diritti insufficienti» richiede VM.PowerMgmt (il ruolo PatchNodePower in Diritti minimi).",
        "An alert is missing":
            "Manca un’allerta",
        "An environment shows as unreachable":
            "Un ambiente risulta irraggiungibile",
        "Attach Nginx Proxy Manager's container to the same proxy network. If the reverse proxy runs on another host, publish the port on the LAN address only (never 0.0.0.0) and let only the proxy's address through:":
            "Collega il container di Nginx Proxy Manager alla stessa rete proxy. Se il reverse proxy è su un altro host, pubblica la porta solo sull’indirizzo LAN (mai 0.0.0.0) e lascia passare solo l’indirizzo del proxy:",
        "Authorization tab: add a user name and password.":
            "Scheda Authorization: aggiungi nome utente e password.",
        "Banned by CrowdSec or fail2ban: list and remove the decision, then allow-list your ranges (see Network prerequisites).":
            "Bannato da CrowdSec o fail2ban: elenca e rimuovi la decisione, poi metti i tuoi intervalli nella allow-list (vedi Requisiti di rete).",
        "Business Edition: give the user the Read-only user role for reading only. Community Edition has no read-only role: a standard user can act on the containers of its environments.":
            "Business Edition: assegna all’utente il ruolo Read-only user per la sola lettura. La Community Edition non ha un ruolo in sola lettura: un utente standard può agire sui container dei suoi ambienti.",
        "CONTAINERS=1 also lets the reader see containers' environment variables, which often hold passwords. That's why the proxy must require authentication and stay on your LAN.":
            "CONTAINERS=1 permette anche di vedere le variabili d’ambiente dei container, che spesso contengono password. Per questo il proxy deve richiedere l’autenticazione e restare nella tua LAN.",
        "CPU, memory, load, disks and temperatures of a host.":
            "CPU, memoria, carico, dischi e temperature di un host.",
        "Check it hasn't expired or been revoked in the service.":
            "Controlla che non sia scaduto o revocato nel servizio.",
        "Check it with curl (Verify section of the service's guide).":
            "Verificalo con curl (sezione Verifica della guida del servizio).",
        "Check the host's load.":
            "Controlla il carico dell’host.",
        "Client rejected (401)":
            "Client rifiutato (401)",
        "Configuration › Access Control › User Management › Add: user monitor, realm pbs (monitor@pbs).":
            "Configuration › Access Control › User Management › Add: utente monitor, realm pbs (monitor@pbs).",
        "Containers and stacks of every Docker environment managed by Portainer.":
            "Container e stack di ogni ambiente Docker gestito da Portainer.",
        "Containers of a Docker host through a read-only socket proxy.":
            "Container di un host Docker tramite un socket proxy in sola lettura.",
        "Copy the client ID and the client secret (tskey-client-…), shown once.":
            "Copia il client ID e il client secret (tskey-client-…), mostrati una sola volta.",
        "Copy the key (shown once) and paste it in PatchNode.":
            "Copia la chiave (mostrata una sola volta) e incollala in PatchNode.",
        "Copy the secret now: Proxmox shows it only once.":
            "Copia subito il segreto: Proxmox lo mostra una sola volta.",
        "Copy the token (shown once) and paste it in PatchNode.":
            "Copia il token (mostrato una sola volta) e incollalo in PatchNode.",
        "Copy the token again: a missing character, a space or a line break is enough to break it.":
            "Copia di nuovo il token: basta un carattere mancante, uno spazio o un a capo per romperlo.",
        "Create an access token (My account › Access tokens), not an Edge key or an API key of another tool.":
            "Crea un token di accesso (My account › Access tokens), non una chiave Edge né una chiave API di un altro strumento.",
        "CrowdSec":
            "CrowdSec",
        "CrowdSec answers 403 for an unknown key. Check it with cscli bouncers list, or create a new one.":
            "CrowdSec risponde 403 a una chiave sconosciuta. Verificala con cscli bouncers list o creane una nuova.",
        "Dashboards and Grafana alerts.":
            "Dashboard e allerte di Grafana.",
        "Datacenter › Permissions › API Tokens › Add: user monitor@pve, Token ID patchnode. Keep Privilege Separation ticked (recommended).":
            "Datacenter › Permissions › API Tokens › Add: utente monitor@pve, Token ID patchnode. Lascia spuntato Privilege Separation (consigliato).",
        "Datacenter › Permissions › Users › Add: user monitor, realm Proxmox VE authentication server (monitor@pve). No password is needed for API use.":
            "Datacenter › Permissions › Users › Add: utente monitor, realm Proxmox VE authentication server (monitor@pve). Per l’uso dell’API non serve una password.",
        "Datastores, latest backup of every guest, failed jobs.":
            "Datastore, ultimo backup di ogni guest, job non riusciti.",
        "Devices of your tailnet: online, offline, keys about to expire.":
            "Dispositivi della tua tailnet: online, offline, chiavi in scadenza.",
        "Devices › Core › Read only. PatchNode has no action on Tailscale.":
            "Devices › Core › solo Read. PatchNode non ha azioni su Tailscale.",
        "Docker (socket proxy)":
            "Docker (socket proxy)",
        "Does split DNS answer through the VPN? Otherwise the name resolves to nothing, or to a public address.":
            "Lo split DNS risponde tramite la VPN? Altrimenti il nome non risolve a nulla, o a un indirizzo pubblico.",
        "Does the Access List allow 100.64.0.0/10?":
            "L’Access List consente 100.64.0.0/10?",
        "Does the name resolve? A typo in the URL gives the same error.":
            "Il nome viene risolto? Un errore di battitura nell’URL dà lo stesso errore.",
        "Don't set listen_uri to the LAN address alone: cscli and the bouncers on 127.0.0.1 would lose the API and bans would stop being applied. cscli lapi status must still answer.":
            "Non impostare listen_uri solo sull’indirizzo LAN: cscli e i bouncer su 127.0.0.1 perderebbero l’API e i ban smetterebbero di essere applicati. cscli lapi status deve continuare a rispondere.",
        "Don't use the API access keys of Settings › Keys: they expire within 90 days and carry all your rights. The OAuth client is limited to reading devices, and PatchNode exchanges it for a one-hour token kept in memory only.":
            "Non usare le chiavi di accesso API di Settings › Keys: scadono entro 90 giorni e hanno tutti i tuoi diritti. Il client OAuth è limitato alla lettura dei dispositivi, e PatchNode lo scambia con un token di un’ora conservato solo in memoria.",
        "E-mail or password rejected":
            "E-mail o password rifiutati",
        "Empty list, or “token without rights”":
            "Elenco vuoto, o «token senza diritti»",
        "Enter client-id:client-secret, separated by a colon.":
            "Inserisci client-id:client-secret, separati da due punti.",
        "Enter the user and password of the Access List's Authorization tab, not those of Nginx Proxy Manager's admin.":
            "Inserisci utente e password della scheda Authorization dell’Access List, non quelli dell’amministratore di Nginx Proxy Manager.",
        "Environments › your environment › Manage access: give this user access to the environments to monitor.":
            "Environments › il tuo ambiente › Manage access: dai a questo utente accesso agli ambienti da monitorare.",
        "From a computer on the VPN, check that the name resolves to the proxy and that the certificate is valid:":
            "Da un computer sulla VPN, verifica che il nome risolva al proxy e che il certificato sia valido:",
        "Generate a new client with Devices › Core › Read.":
            "Genera un nuovo client con Devices › Core › Read.",
        "Give PatchNode dedicated accounts and tokens, read-only first. Add the rights for actions (start, stop, restart) only once reading works, and only on what you want to control.":
            "Dai a PatchNode account e token dedicati, prima in sola lettura. Aggiungi i diritti per le azioni (avvia, arresta, riavvia) solo quando la lettura funziona, e solo su ciò che vuoi controllare.",
        "Give the user View Only on Proxy Hosts (Users › the user › Permissions).":
            "Assegna all’utente View Only sui Proxy Hosts (Users › l’utente › Permissions).",
        "Glances":
            "Glances",
        "Glances 3 answers on /api/3/cpu; PatchNode tries both.":
            "Glances 3 risponde su /api/3/cpu; PatchNode prova entrambi.",
        "Glances only reads. With --password, it asks for a password (default user glances): enter the user and password in PatchNode; without it, leave both fields empty and rely on the Access List.":
            "Glances legge soltanto. Con --password chiede una password (utente predefinito glances): inserisci utente e password in PatchNode; senza, lascia vuoti entrambi i campi e affidati all’Access List.",
        "Grafana":
            "Grafana",
        "Grant Audit on / to the user and the token. A datastore refused alone (per-datastore permissions) is shown without its details.":
            "Concedi Audit su / all’utente e al token. Un datastore rifiutato singolarmente (permessi per datastore) viene mostrato senza dettagli.",
        "Home Assistant":
            "Home Assistant",
        "Home Assistant must trust the proxy, in configuration.yaml:":
            "Home Assistant deve fidarsi del proxy, in configuration.yaml:",
        "Home Assistant refuses forwarded requests from an untrusted proxy: add use_x_forwarded_for and trusted_proxies (Reverse proxy section), then restart.":
            "Home Assistant rifiuta le richieste inoltrate da un proxy non attendibile: aggiungi use_x_forwarded_for e trusted_proxies (sezione Reverse proxy), poi riavvia.",
        "If it keeps happening, Settings › Diagnostics shows the requests (protocol, connection reused). That log contains your services' names and API paths: read it before sharing it with anyone.":
            "Se continua, Impostazioni › Diagnostica mostra le richieste (protocollo, connessione riutilizzata). Quel registro contiene i nomi dei tuoi servizi e i percorsi API: leggilo prima di condividerlo.",
        "In PatchNode, enter client-id:client-secret. No URL to type.":
            "In PatchNode, inserisci client-id:client-secret. Nessun URL da digitare.",
        "In PatchNode, enter the e-mail and the password. PatchNode gets a session token from them, kept in memory only.":
            "In PatchNode, inserisci e-mail e password. PatchNode ne ottiene un token di sessione, conservato solo in memoria.",
        "In PatchNode, enter the same user name and password in the two fields.":
            "In PatchNode, inserisci gli stessi nome utente e password nei due campi.",
        "In PatchNode, enter the status page's URL, ending with /status/<slug>. No token.":
            "In PatchNode, inserisci l’URL della pagina di stato, che termina con /status/<slug>. Nessun token.",
        "In PatchNode, enter this user name and password.":
            "In PatchNode, inserisci questo nome utente e password.",
        "In PatchNode, open Home Assistant › Choose entities.":
            "In PatchNode, apri Home Assistant › Scegli le entità.",
        "In PatchNode, paste the full value: user@realm!tokenid=secret.":
            "In PatchNode, incolla il valore completo: user@realm!tokenid=secret.",
        "In PatchNode, paste the token.":
            "In PatchNode, incolla il token.",
        "In PatchNode, paste user@realm!tokenid:secret — with a colon, unlike Proxmox VE.":
            "In PatchNode, incolla user@realm!tokenid:secret, con i due punti, a differenza di Proxmox VE.",
        "In PatchNode, use Portainer's own URL and paste the token.":
            "In PatchNode, usa l’URL di Portainer stesso e incolla il token.",
        "In Nginx Proxy Manager, create an Access List with a user and password, and your LAN and VPN ranges:":
            "In Nginx Proxy Manager, crea un’Access List con utente e password e gli intervalli della tua LAN e VPN:",
        "In Uptime Kuma, Status Pages › New Status Page: a name and a slug, e.g. homelab.":
            "In Uptime Kuma, Status Pages › New Status Page: un nome e uno slug, es. homelab.",
        "In the Tailscale admin console, Machines › the server › Edit route settings: approve the route.":
            "Nella console di amministrazione di Tailscale, Machines › il server › Edit route settings: approva la route.",
        "In the Tailscale admin console: Settings › Trust credentials (formerly OAuth clients) › Generate OAuth client.":
            "Nella console di amministrazione di Tailscale: Settings › Trust credentials (prima OAuth clients) › Generate OAuth client.",
        "In zsh and bash, the ! of the token name must be inside single quotes ('monitor@pve!patchnode'), otherwise the shell tries to expand it.":
            "In zsh e bash, il ! del nome del token deve stare tra apici singoli ('monitor@pve!patchnode'), altrimenti la shell prova a espanderlo.",
        "Insufficient rights (403 from the service)":
            "Diritti insufficienti (403 dal servizio)",
        "Is the VPN connected on the iPhone?":
            "La VPN è connessa sull’iPhone?",
        "Is the certificate valid for this name? PatchNode refuses invalid and self-signed certificates.":
            "Il certificato è valido per questo nome? PatchNode rifiuta certificati non validi e autofirmati.",
        "Is the reverse proxy up, and the service behind it?":
            "Il reverse proxy è attivo, e il servizio dietro di esso?",
        "Is the subnet route approved in the Tailscale admin console?":
            "La route di sottorete è approvata nella console di amministrazione di Tailscale?",
        "It works at home but not outside":
            "Funziona a casa ma non fuori",
        "It's the only service reached outside your private network: api.tailscale.com.":
            "È l’unico servizio contattato fuori dalla tua rete privata: api.tailscale.com.",
        "Key rejected (403 from CrowdSec)":
            "Chiave rifiutata (403 da CrowdSec)",
        "PatchNode lists active decisions (bans and captchas) from local detections and manual bans: IP or range, scenario, time left. Community blocklists aren't listed.":
            "PatchNode elenca le decisioni attive (ban e captcha) da rilevamenti locali e ban manuali: IP o intervallo, scenario, tempo rimanente. Le blocklist della community non sono elencate.",
        "PatchNode lists every Docker environment of Portainer, their containers grouped by stack, with health, logs, CPU and memory, and can start, stop and restart a container.":
            "PatchNode elenca ogni ambiente Docker di Portainer e i suoi container raggruppati per stack, con salute, log, CPU e memoria, e può avviare, arrestare e riavviare un container.",
        "PatchNode lists the host's containers grouped by Compose project, with health, status, image, CPU and memory, logs, ports and volumes. With POST allowed, it can start, stop and restart a container.":
            "PatchNode elenca i container dell’host raggruppati per progetto Compose, con salute, stato, immagine, CPU e memoria, log, porte e volumi. Con POST consentito, può avviare, arrestare e riavviare un container.",
        "PatchNode lists the scrape targets with those down first, and draws the PromQL queries you save as charts (CPU, memory, disks…).":
            "PatchNode elenca i target di scrape, prima quelli down, e disegna come grafici le query PromQL che salvi (CPU, memoria, dischi…).",
        "PatchNode lists your dashboards (they open in an embedded browser where you sign in as usual) and shows Grafana's unified alerting alerts with the others.":
            "PatchNode elenca le tue dashboard (si aprono in un browser integrato dove accedi come al solito) e mostra le allerte dell’unified alerting di Grafana insieme alle altre.",
        "PatchNode lists your proxy hosts: enabled or not, destination, certificate, and in red those nginx refused (bad upstream, configuration error).":
            "PatchNode elenca i tuoi proxy host: attivi o no, destinazione, certificato, e in rosso quelli rifiutati da nginx (upstream errato, errore di configurazione).",
        "PatchNode lists your tailnet's devices: online or last seen, address, OS, and flags those offline for more than a day, keys expiring within 14 days and devices waiting for approval.":
            "PatchNode elenca i dispositivi della tua tailnet: online o visto l’ultima volta, indirizzo, sistema, e segnala quelli offline da più di un giorno, le chiavi in scadenza entro 14 giorni e i dispositivi in attesa di approvazione.",
        "PatchNode pauses the service and tries again after 30 s, 60 s, then every 2 minutes, to avoid being banned.":
            "PatchNode mette in pausa il servizio e riprova dopo 30 s, 60 s e poi ogni 2 minuti, per evitare di essere bannato.",
        "PatchNode reads a public status page of Uptime Kuma: each monitor's state, 24-hour uptime and latest heartbeats. A monitor down becomes an alert.":
            "PatchNode legge una pagina di stato pubblica di Uptime Kuma: stato di ogni monitor, uptime nelle 24 ore e ultimi heartbeat. Un monitor down diventa un’allerta.",
        "PatchNode shows Prometheus's own message. Test the query in Prometheus's web interface (Graph) first, then paste it again.":
            "PatchNode mostra il messaggio di Prometheus stesso. Prova prima la query nell’interfaccia web di Prometheus (Graph), poi incollala di nuovo.",
        "PatchNode shows a host's CPU, memory and swap, load, file systems (orange above 85 %) and temperatures.":
            "PatchNode mostra CPU, memoria e swap, carico, file system (arancione oltre l’85 %) e temperature di un host.",
        "PatchNode shows active alerts sorted by severity (critical, warning, info) with a badge on the tab. Silenced and inhibited alerts are left out.":
            "PatchNode mostra le allerte attive ordinate per gravità (critical, warning, info) con un badge sulla scheda. Le allerte silenziate e inibite sono escluse.",
        "PatchNode shows each datastore's space, the latest backup of every VM and container (in orange after two days) and recent backup, verify, prune and garbage collection tasks.":
            "PatchNode mostra lo spazio di ogni datastore, l’ultimo backup di ogni VM e container (in arancione dopo due giorni) e le attività recenti di backup, verifica, prune e garbage collection.",
        "PatchNode shows the sensors, lights and switches you pick, with their state, and can run the scenes and scripts you pick after a confirmation naming them.":
            "PatchNode mostra i sensori, le luci e gli interruttori che scegli, con il loro stato, e può eseguire le scene e gli script che scegli dopo una conferma che li nomina.",
        "PatchNode shows whether protection is on, the number of queries and the share blocked, the average processing time, and the most queried and blocked domains.":
            "PatchNode mostra se la protezione è attiva, il numero di richieste e la quota bloccata, il tempo medio di elaborazione e i domini più richiesti e bloccati.",
        "PatchNode shows your nodes (CPU, memory, disks, storage), every VM and container with charts per hour, day or week, and recent tasks with failures first. With the right role, it can start, shut down, stop or reboot a VM or container after a confirmation.":
            "PatchNode mostra i tuoi nodi (CPU, memoria, dischi, storage), ogni VM e container con grafici per ora, giorno o settimana, e le attività recenti, prima quelle non riuscite. Con il ruolo giusto, può avviare, spegnere, arrestare o riavviare una VM o un container dopo una conferma.",
        "PatchNode talks directly from your iPhone to your servers. Nothing goes through a server of ours, so your iPhone must reach them: at home on Wi-Fi, and elsewhere through a VPN.":
            "PatchNode comunica direttamente dal tuo iPhone con i tuoi server. Nulla passa da un nostro server, quindi l’iPhone deve raggiungerli: a casa via Wi-Fi, altrove tramite una VPN.",
        "PatchNode waits 10 seconds per request. A slow VPN route, an overloaded host or a heavy endpoint can exceed it.":
            "PatchNode attende 10 secondi per richiesta. Una route VPN lenta, un host sovraccarico o un endpoint pesante possono superarli.",
        "Monitors of a status page, with uptime and latest heartbeats.":
            "Monitor di una pagina di stato, con uptime e ultimi heartbeat.",
        "Network prerequisites":
            "Requisiti di rete",
        "Never expose /var/run/docker.sock or the raw port 2375, even on your LAN: whoever reaches it is root on the host. Always go through a socket proxy and an authenticated reverse proxy.":
            "Non esporre mai /var/run/docker.sock né la porta 2375 non protetta, nemmeno nella LAN: chi la raggiunge è root sull’host. Passa sempre da un socket proxy e da un reverse proxy con autenticazione.",
        "Never expose these services directly to the internet: PatchNode doesn't need it.":
            "Non esporre mai questi servizi direttamente su internet: PatchNode non ne ha bisogno.",
        "Nginx Proxy Manager":
            "Nginx Proxy Manager",
        "No active local ban: the API answers null. PatchNode shows “No active bans”.":
            "Nessun ban locale attivo: l’API risponde null. PatchNode mostra «Nessun ban attivo».",
        "No datastore, or 403":
            "Nessun datastore, o 403",
        "No proxy host listed":
            "Nessun proxy host elencato",
        "Nodes outside a cluster are separate services: add each one as its own service. PatchNode shows the service name first so they stay distinct.":
            "I nodi fuori da un cluster sono servizi distinti: aggiungili ciascuno come servizio a sé. PatchNode mostra prima il nome del servizio, così restano distinti.",
        "Nodes, VMs and containers, storage, tasks, power actions.":
            "Nodi, VM e container, storage, attività, azioni di accensione.",
        "None: PatchNode calls api.tailscale.com directly, over HTTPS.":
            "Nessuno: PatchNode chiama direttamente api.tailscale.com, via HTTPS.",
        "Nothing to create in Prometheus: PatchNode only reads its HTTP API. Add a proxy host in front of it (below), then the URL in PatchNode.":
            "Niente da creare in Prometheus: PatchNode legge solo la sua API HTTP. Aggiungi un proxy host davanti (sotto), poi l’URL in PatchNode.",
        "Nothing to create: PatchNode reads the v2 API. Set a severity label on your alert rules (critical, warning, info) to get them sorted.":
            "Niente da creare: PatchNode legge l’API v2. Imposta un’etichetta severity nelle regole di allerta (critical, warning, info) per ordinarle.",
        "Nothing to grant: only the monitors placed on this page are read. PatchNode has no action on Uptime Kuma.":
            "Niente da concedere: vengono letti solo i monitor di questa pagina. PatchNode non ha azioni su Uptime Kuma.",
        "On the CrowdSec host, create a bouncer key for PatchNode:":
            "Sull’host CrowdSec, crea una chiave bouncer per PatchNode:",
        "On the iPhone, open the Tailscale app and connect.":
            "Sull’iPhone, apri l’app Tailscale e connettiti.",
        "PBS listens in HTTPS on port 8007: forward with the https scheme.":
            "PBS ascolta in HTTPS sulla porta 8007: inoltra con lo schema https.",
        "PBS uses a colon between the token ID and the secret: user@realm!tokenid:secret.":
            "PBS usa i due punti tra l’ID del token e il segreto: user@realm!tokenid:secret.",
        "Paste the full value user@realm!tokenid=secret, with = before the secret.":
            "Incolla il valore completo user@realm!tokenid=secret, con = prima del segreto.",
        "Permissions: Proxy Hosts › View Only, everything else Hidden.":
            "Permissions: Proxy Hosts › View Only, tutto il resto Hidden.",
        "Port 9443 is Portainer's HTTPS port (scheme https); 9000 is plain HTTP (scheme http).":
            "La porta 9443 è la porta HTTPS di Portainer (schema https); la 9000 è HTTP in chiaro (schema http).",
        "Portainer":
            "Portainer",
        "Portainer itself can't reach this environment (agent stopped, host off). Check it in Portainer's Environments page.":
            "Portainer stesso non raggiunge questo ambiente (agente fermo, host spento). Controlla nella pagina Environments di Portainer.",
        "Privilege Separation is ticked and the token has no permission of its own, or its user has none: the token's rights are the intersection of both. Grant PVEAuditor on / to the user and to the token.":
            "Privilege Separation è spuntato e il token non ha permessi propri, o il suo utente non ne ha: i diritti del token sono l’intersezione dei due. Concedi PVEAuditor su / all’utente e al token.",
        "Prometheus":
            "Prometheus",
        "Prometheus and Alertmanager have no token. Keep them on your LAN and VPN only; for a password, add an Access List with a user in Nginx Proxy Manager (Authorization tab, Satisfy All) and enter the same user and password in PatchNode. Without authentication, leave both fields empty.":
            "Prometheus e Alertmanager non hanno token. Tienili solo nella tua LAN e VPN; per una password, aggiungi un’Access List con un utente in Nginx Proxy Manager (scheda Authorization, Satisfy All) e inserisci gli stessi utente e password in PatchNode. Senza autenticazione, lascia vuoti entrambi i campi.",
        "Protection state and DNS statistics.":
            "Stato della protezione e statistiche DNS.",
        "Proxmox Backup Server":
            "Proxmox Backup Server",
        "Proxmox VE":
            "Proxmox VE",
        "Proxmox itself listens in HTTPS on port 8006. In Nginx Proxy Manager, the proxy host must forward with the https scheme:":
            "Proxmox stesso ascolta in HTTPS sulla porta 8006. In Nginx Proxy Manager, il proxy host deve inoltrare con lo schema https:",
        "Proxmox › Backups (Proxmox VE) lists the backup jobs, the guests no job covers, the latest archive of every guest (from the storages holding backups, NFS and Proxmox Backup Server storages included) and the failed backup tasks. It needs no other right than PVEAuditor.":
            "Proxmox › Backup (Proxmox VE) elenca i job di backup, i guest non coperti da alcun job, l’ultimo archivio di ogni guest (dagli storage che contengono backup, NFS e Proxmox Backup Server compresi) e i backup non riusciti. Non serve altro diritto che PVEAuditor.",
        "Proxmox › Disk health shows, for each online node, the SMART status and remaining life of every disk (Disks in the node's menu) and the state and fill of every ZFS pool. It needs Sys.Audit, which PVEAuditor on / already gives. SMART data comes from smartmontools on the node; disks behind a USB bridge or a RAID controller often report none.":
            "Proxmox › Salute dei dischi mostra, per ogni nodo online, lo stato SMART e la vita residua di ogni disco (Disks nel menu del nodo) e lo stato e il riempimento di ogni pool ZFS. Serve Sys.Audit, che PVEAuditor su / già concede. I dati SMART provengono da smartmontools sul nodo; i dischi dietro un adattatore USB o un controller RAID spesso non ne forniscono.",
        "Proxy host docker.example.com → http://docker-socket-proxy:2375 (same Docker network) with this Access List and your certificate.":
            "Proxy host docker.example.com → http://docker-socket-proxy:2375 (stessa rete Docker) con questa Access List e il tuo certificato.",
        "Proxy hosts, certificates, and hosts refused by nginx.":
            "Proxy host, certificati e host rifiutati da nginx.",
        "Read-only: role Audit on /, for the user and the token (a token's rights are also limited by its user's). PatchNode has no action on PBS.":
            "Sola lettura: ruolo Audit su /, per l’utente e il token (i diritti di un token sono limitati anche da quelli del suo utente). PatchNode non ha azioni su PBS.",
        "Reading: CONTAINERS=1, INFO=1, POST=0 (the default above).":
            "Lettura: CONTAINERS=1, INFO=1, POST=0 (il valore predefinito sopra).",
        "Reading: role PVEAuditor on /. With Privilege Separation, a token only has the rights both it and its user have (the intersection): grant the role to both, or the lists stay empty.":
            "Lettura: ruolo PVEAuditor su /. Con Privilege Separation, un token ha solo i diritti comuni a lui e al suo utente (l’intersezione): concedi il ruolo a entrambi, altrimenti gli elenchi restano vuoti.",
        "Requests stay paused until you pull to refresh, so a wrong token isn't retried and can't get your IP banned. To change it: Settings › the service › enter the new token.":
            "Le richieste restano in pausa finché non trascini per aggiornare, così un token sbagliato non viene ritentato e non può far bannare il tuo IP. Per cambiarlo: Impostazioni › il servizio › inserisci il nuovo token.",
        "Restrict every proxy host to your LAN and VPN. In Nginx Proxy Manager: Access Lists › Add Access List › Access tab:":
            "Limita ogni proxy host alla tua LAN e VPN. In Nginx Proxy Manager: Access Lists › Add Access List › scheda Access:",
        "Role Viewer: it reads dashboards and alerts, and can't change anything. The token is never put in a dashboard URL.":
            "Ruolo Viewer: legge dashboard e allerte e non può modificare nulla. Il token non finisce mai nell’URL di una dashboard.",
        "Run Glances in web server mode, for example with Docker. --disable-plugin processlist makes each refresh much lighter:":
            "Avvia Glances in modalità server web, per esempio con Docker. --disable-plugin processlist rende ogni aggiornamento molto più leggero:",
        "Run tecnativa/docker-socket-proxy without publishing any port, on a Docker network shared with the reverse proxy: only the proxy (and its authentication) can reach it.":
            "Avvia tecnativa/docker-socket-proxy senza pubblicare alcuna porta, su una rete Docker condivisa con il reverse proxy: solo il proxy (e la sua autenticazione) può raggiungerlo.",
        "Scopes: Devices › Core, Read only. Nothing else.":
            "Scope: Devices › Core, solo Read. Nient’altro.",
        "Service unreachable":
            "Servizio irraggiungibile",
        "Set a password for this user.":
            "Imposta una password per questo utente.",
        "Set root_url in grafana.ini to your public name, so links and sign-in redirect correctly:":
            "Imposta root_url in grafana.ini con il tuo nome pubblico, così link e accesso reindirizzano correttamente:",
        "Settings › People › Add person: a dedicated user patchnode, allowed to log in, not an administrator.":
            "Settings › People › Add person: un utente dedicato patchnode, autorizzato ad accedere, non amministratore.",
        "Several services share one reverse proxy and one wildcard certificate: iOS may reuse an HTTP/2 connection opened for another name, and the proxy answers 421. PatchNode retries once on a new connection automatically.":
            "Più servizi condividono un reverse proxy e un certificato wildcard: iOS può riutilizzare una connessione HTTP/2 aperta per un altro nome, e il proxy risponde 421. PatchNode riprova automaticamente una volta con una nuova connessione.",
        "Sign in as this user, then My account › Access tokens › Add access token. Copy it (shown once).":
            "Accedi con questo utente, poi My account › Access tokens › Add access token. Copialo (mostrato una sola volta).",
        "Sign in as this user, then Profile › Security › Long-lived access tokens › Create token.":
            "Accedi con questo utente, poi Profilo › Sicurezza › Token di accesso a lunga durata › Crea token.",
        "Silenced and inhibited alerts are not shown. Check Alertmanager's web interface (Silences).":
            "Le allerte silenziate e inibite non sono mostrate. Controlla l’interfaccia web di Alertmanager (Silences).",
        "Slow refreshes or timeouts":
            "Aggiornamenti lenti o timeout",
        "Split DNS so the same names work at home and through the VPN.":
            "Split DNS, così gli stessi nomi funzionano a casa e tramite la VPN.",
        "Tailscale":
            "Tailscale",
        "Targets down and your own PromQL charts.":
            "Target down e i tuoi grafici PromQL.",
        "That's expected: the embedded browser uses your own Grafana session, separate from the token. The session is cleared when PatchNode goes to the background.":
            "È normale: il browser integrato usa la tua sessione Grafana, separata dal token. La sessione viene cancellata quando PatchNode passa in background.",
        "The API also allows creating silences: keep Alertmanager on your LAN and VPN only, behind authentication. PatchNode only reads.":
            "L’API permette anche di creare silenzi: tieni Alertmanager solo nella tua LAN e VPN, dietro autenticazione. PatchNode legge soltanto.",
        "The HTTP API is read-only by default. Don't start Prometheus with --web.enable-admin-api or --web.enable-lifecycle behind this proxy host.":
            "L’API HTTP è in sola lettura per impostazione predefinita. Non avviare Prometheus con --web.enable-admin-api o --web.enable-lifecycle dietro questo proxy host.",
        "The Local API listens on 127.0.0.1:8080 by default, and cscli and the local bouncers use that address. Simplest: a reverse proxy on the same host forwards to 127.0.0.1:8080. Otherwise listen on all addresses and let only the proxy through the firewall:":
            "La Local API ascolta su 127.0.0.1:8080 per impostazione predefinita, e cscli e i bouncer locali usano quell’indirizzo. La cosa più semplice: un reverse proxy sullo stesso host inoltra a 127.0.0.1:8080. Altrimenti ascolta su tutti gli indirizzi e lascia passare solo il proxy dal firewall:",
        "The URL must end with /status/<slug> — the slug chosen when creating the status page, not the dashboard URL.":
            "L’URL deve terminare con /status/<slug>: lo slug scelto creando la pagina di stato, non l’URL della dashboard.",
        "The admin interface (port 81) can be published by Nginx Proxy Manager itself, restricted to your LAN and VPN:":
            "L’interfaccia di amministrazione (porta 81) può essere pubblicata da Nginx Proxy Manager stesso, limitata alla tua LAN e VPN:",
        "The answer is an HTML 403 page: the reverse proxy refused the request before it reached the service. Your token isn't the cause.":
            "La risposta è una pagina 403 in HTML: il reverse proxy ha rifiutato la richiesta prima che raggiungesse il servizio. Il tuo token non c’entra.",
        "The answer is {\"message\":\"API running.\"}.":
            "La risposta è {\"message\":\"API running.\"}.",
        "The client may have been revoked in Settings › Trust credentials.":
            "Il client potrebbe essere stato revocato in Settings › Trust credentials.",
        "The entities you choose, scenes and scripts.":
            "Le entità che scegli, scene e script.",
        "The first command must print the proxy's LAN address; the second must answer without a certificate error.":
            "Il primo comando deve stampare l’indirizzo LAN del proxy; il secondo deve rispondere senza errori di certificato.",
        "The list is empty":
            "L’elenco è vuoto",
        "The process list makes Glances's answer heavy. Start it with --disable-plugin processlist.":
            "L’elenco dei processi appesantisce la risposta di Glances. Avvialo con --disable-plugin processlist.",
        "The reverse proxy forwards in http to port 8006. Set Scheme to https on the proxy host.":
            "Il reverse proxy inoltra in http alla porta 8006. Imposta Scheme su https nel proxy host.",
        "The same from the node's shell:":
            "Lo stesso dalla shell del nodo:",
        "The service answers too slowly (timeout)":
            "Il servizio risponde troppo lentamente (timeout)",
        "The socket proxy refuses POST requests: set POST=1 and recreate the container, only while you need actions.":
            "Il socket proxy rifiuta le richieste POST: imposta POST=1 e ricrea il container, solo finché ti servono le azioni.",
        "The token is valid but not allowed to read this information. Grant the read-only role described in the Minimum rights section of the service's guide.":
            "Il token è valido ma non può leggere questa informazione. Concedi il ruolo in sola lettura descritto nella sezione Diritti minimi della guida del servizio.",
        "The token may have expired (Expire field) or been deleted.":
            "Il token potrebbe essere scaduto (campo Expire) o essere stato eliminato.",
        "Then, in the Tailscale admin console, DNS › Nameservers › Add nameserver › Custom: your DNS server, restricted to your domain (Split DNS).":
            "Poi, nella console di amministrazione di Tailscale, DNS › Nameservers › Add nameserver › Custom: il tuo server DNS, limitato al tuo dominio (Split DNS).",
        "This service goes through the internet, not your VPN: check the iPhone's internet access, or a DNS filter blocking tailscale.com.":
            "Questo servizio passa da internet, non dalla tua VPN: controlla l’accesso a internet dell’iPhone, o un filtro DNS che blocca tailscale.com.",
        "Toggle the VPN off and on: PatchNode then opens new connections.":
            "Spegni e riaccendi la VPN: PatchNode aprirà nuove connessioni.",
        "Token or password rejected (401)":
            "Token o password rifiutati (401)",
        "Token rejected (401)":
            "Token rifiutato (401)",
        "Tokens stay in the iPhone's Keychain (this device only) and are sent only to the service they belong to.":
            "I token restano nel Portachiavi dell’iPhone (solo questo dispositivo) e vengono inviati solo al servizio a cui appartengono.",
        "Try again on Wi-Fi at home to rule out the VPN.":
            "Riprova con il Wi-Fi di casa per escludere la VPN.",
        "Two nodes named the same (pve)":
            "Due nodi con lo stesso nome (pve)",
        "Type the token without it being displayed, then call the API:":
            "Digita il token senza che venga mostrato, poi chiama l’API:",
        "Uptime Kuma":
            "Uptime Kuma",
        "Use a service account token (glsa_…), not an API key from an older Grafana nor your password.":
            "Usa un token di account di servizio (glsa_…), non una chiave API di un Grafana più vecchio né la tua password.",
        "Use the dedicated user's e-mail and password. Two-factor authentication isn't supported: use a user without it.":
            "Usa e-mail e password dell’utente dedicato. L’autenticazione a due fattori non è supportata: usa un utente senza.",
        "User or password rejected":
            "Utente o password rifiutati",
        "User or password rejected (401)":
            "Utente o password rifiutati (401)",
        "Users › Add User: full name PatchNode, e-mail e.g. patchnode@example.com, not an administrator.":
            "Users › Add User: nome completo PatchNode, e-mail es. patchnode@example.com, non amministratore.",
        "VPN connected? At home, is the iPhone on your Wi-Fi?":
            "VPN connessa? A casa, l’iPhone è sul tuo Wi-Fi?",
        "VPN off: turn it on, then pull to refresh.":
            "VPN spenta: accendila, poi trascina per aggiornare.",
        "VPN, HTTPS reverse proxy, split DNS, LAN-only access and IPS allow-list.":
            "VPN, reverse proxy HTTPS, split DNS, accesso solo dalla LAN e allow-list dell’IPS.",
        "View Only on Proxy Hosts is enough. PatchNode has no action on Nginx Proxy Manager.":
            "Basta View Only sui Proxy Hosts. PatchNode non ha azioni su Nginx Proxy Manager.",
        "With Scheme http, Proxmox answers 301 Moved Permanently and PatchNode can't read anything.":
            "Con Scheme http, Proxmox risponde 301 Moved Permanently e PatchNode non può leggere nulla.",
        "Without authentication, drop -u monitor.":
            "Senza autenticazione, togli -u monitor.",
        "You should get a token in return.":
            "Dovresti ricevere un token in risposta.",
        "You should see your datastores.":
            "Dovresti vedere i tuoi datastore.",
        "You should see your environments.":
            "Dovresti vedere i tuoi ambienti.",
        "You should see your nodes, VMs and storage. A list with only nodes and no CPU or memory means the token lacks rights.":
            "Dovresti vedere nodi, VM e storage. Un elenco con soli nodi e senza CPU né memoria significa che al token mancano diritti.",
        "Your LAN and VPN ranges allow-listed in your IPS (CrowdSec, fail2ban).":
            "Gli intervalli della tua LAN e VPN nella allow-list del tuo IPS (CrowdSec, fail2ban).",
        "api.tailscale.com unreachable":
            "api.tailscale.com irraggiungibile",
        "curl asks for the password, then prints the Docker version. Without the password you must get a 401.":
            "curl chiede la password, poi stampa la versione di Docker. Senza la password devi ricevere un 401.",
        "null means no active ban: that's a valid answer.":
            "null significa nessun ban attivo: è una risposta valida.",
        "“Actions disabled” (403 from the socket proxy)":
            "«Azioni disattivate» (403 dal socket proxy)",
        "“Enter the status page URL”":
            "«Inserisci l’URL della pagina di stato»",
        "Consoles: the Console button of a node, a container or a VM opens a terminal inside PatchNode (the node's shell, the container, or the VM's serial port), or the graphical console of a VM without a serial port. Face ID is asked every time. Consoles with an API token need Proxmox VE 9.1 or later.":
            "Console: il pulsante Console di un nodo, un container o una VM apre un terminale in PatchNode (la shell del nodo, il container o la porta seriale della VM), oppure la console grafica di una VM senza porta seriale. Face ID viene richiesto ogni volta. Le console con un token API richiedono Proxmox VE 9.1 o successivo.",
        "Consoles: a PatchNodeConsole role with VM.Console only, on the guest (/vms/101), and for a node's shell a PatchNodeNodeConsole role with Sys.Console only, on the node (/nodes/node-a) — never Sys.Console on a guest. On / (everything), the role alone is enough. A node's shell opened by another user than root@pam asks for a Linux login.":
            "Console: un ruolo PatchNodeConsole con il solo VM.Console, sul guest (/vms/101), e per la shell di un nodo un ruolo PatchNodeNodeConsole con il solo Sys.Console, sul nodo (/nodes/node-a) — mai Sys.Console su un guest. Su / (tutto), basta il ruolo da solo. La shell di un nodo aperta da un utente diverso da root@pam chiede un login Linux.",
        "A console gives a shell on the guest or the node: grant it only where you need it.":
            "Una console dà una shell sul guest o sul nodo: concedila solo dove ti serve.",
        "Consoles go through a websocket: in Nginx Proxy Manager, Websockets Support must be on for the Proxmox host.":
            "Le console passano da un websocket: in Nginx Proxy Manager, Websockets Support deve essere attivo per l’host Proxmox.",
        "Console: the token lacks the console privilege":
            "Console: al token manca il privilegio console",
        "Grant PatchNodeConsole on the guest (/vms/<id>) or PatchNodeNodeConsole on the node (/nodes/<node>), always with PVEAuditor, to the user and to the token (Minimum rights). PatchNode shows the exact commands to copy.":
            "Concedi PatchNodeConsole sul guest (/vms/<id>) o PatchNodeNodeConsole sul nodo (/nodes/<nodo>), sempre insieme a PVEAuditor, all’utente e al token (Permessi minimi). PatchNode mostra i comandi esatti da copiare.",
        "Console: Proxmox refused the token":
            "Console: Proxmox ha rifiutato il token",
        "Before Proxmox VE 9.1, consoles only accept a password session, not an API token. Update the nodes to 9.1 or later (apt full-upgrade).":
            "Prima di Proxmox VE 9.1, le console accettano solo una sessione con password, non un token API. Aggiorna i nodi a 9.1 o successivo (apt full-upgrade).",
        "Graphical console only: add a serial port":
            "Solo console grafica: aggiungere una porta seriale",
        "A VM gets a text terminal in PatchNode when it has a serial port. Add one, enable a login on it inside the VM, then restart the VM:":
            "Una VM ha un terminale testuale in PatchNode quando ha una porta seriale. Aggiungine una, attiva un login su di essa nella VM, poi riavvia la VM:",
        "Without a serial port, PatchNode opens the VM's graphical console.":
            "Senza porta seriale, PatchNode apre la console grafica della VM.",
        "SSH terminal":
            "Terminale SSH",
        "A dedicated user, this device's key, sudo or the docker group, risks and revocation.":
            "Un utente dedicato, la chiave di questo dispositivo, sudo o il gruppo docker, rischi e revoca.",
        "PatchNode opens SSH sessions to your own servers (Proxmox nodes, Docker hosts, containers, VMs) and, for a Docker host, runs docker compose in a project's folder. It connects only to the hosts you add, with a key generated on this device; nothing goes through a server of ours.":
            "PatchNode apre sessioni SSH verso i tuoi server (nodi Proxmox, host Docker, container, VM) e, per un host Docker, esegue docker compose nella cartella di un progetto. Si connette solo agli host che aggiungi, con una chiave creata su questo dispositivo; nulla passa da un nostro server.",
        "Every session asks for Face ID. The first connection to a host shows its fingerprint: compare it with the server's own before trusting it. PatchNode then refuses any other key for that host.":
            "Ogni sessione chiede Face ID. La prima connessione a un host mostra la sua impronta: confrontala con quella del server prima di fidarti. Poi PatchNode rifiuta qualsiasi altra chiave per quell’host.",
        "On the server, create a dedicated user, for example patchnode.":
            "Sul server, crea un utente dedicato, per esempio patchnode.",
        "In PatchNode, Settings › SSH: turn on the SSH terminal, open This device's public key and copy the authorized_keys line.":
            "In PatchNode, Impostazioni › SSH: attiva il terminale SSH, apri la chiave pubblica di questo dispositivo e copia la riga authorized_keys.",
        "On the server, add the line to ~/.ssh/authorized_keys of that user (folder 700, file 600).":
            "Sul server, aggiungi la riga al ~/.ssh/authorized_keys di quell’utente (cartella 700, file 600).",
        "Settings › SSH › Add a host: address, port, user. Link it to its Proxmox node or Docker host for the shortcuts.":
            "Impostazioni › SSH › Aggiungi un host: indirizzo, porta, utente. Collegalo al suo nodo Proxmox o host Docker per le scorciatoie.",
        "Docker: add the user to the docker group so docker compose runs without sudo. The docker group is equivalent to root on that host: keep the key's from= restriction.":
            "Docker: aggiungi l’utente al gruppo docker per eseguire docker compose senza sudo. Il gruppo docker equivale a root su quell’host: mantieni la restrizione from= della chiave.",
        "Proxmox: “Enter the container” runs pct enter, which needs root. Connect as root with the key only (PermitRootLogin prohibit-password), or allow just that command with sudo (edit with visudo):":
            "Proxmox: «Entra nel container» esegue pct enter, che richiede root. Connettiti come root solo con la chiave (PermitRootLogin prohibit-password), oppure consenti solo quel comando con sudo (modifica con visudo):",
        "Prefer the key to a password. A password is asked only when the server refuses the key, used for that connection, and never stored.":
            "Preferisci la chiave a una password. Una password viene chiesta solo se il server rifiuta la chiave, vale per quella connessione e non viene mai salvata.",
        "A session gives a full shell: whatever the user can do, PatchNode can do once unlocked.":
            "Una sessione dà una shell completa: tutto ciò che l’utente può fare, PatchNode può farlo una volta sbloccato.",
        "Keep SSH reachable only through your VPN, never exposed on the internet.":
            "Rendi SSH raggiungibile solo tramite la tua VPN, mai esposto su internet.",
        "from= limits where the key is accepted from; the no-…-forwarding options limit what it can do.":
            "from= limita da dove la chiave è accettata; le opzioni no-…-forwarding limitano ciò che può fare.",
        "Terminal content is never stored or logged; Diagnostics keep only the opening, closing, duration and error code.":
            "Il contenuto del terminale non viene mai salvato né registrato; la Diagnostica conserva solo apertura, chiusura, durata e codice di errore.",
        "Lost device, or a key you no longer trust: delete its line from authorized_keys on every server. The comment at the end of the line (patchnode-iPhone-…) tells which device it is.":
            "Dispositivo perso o chiave di cui non ti fidi più: elimina la sua riga da authorized_keys su ogni server. Il commento a fine riga (patchnode-iPhone-…) indica di quale dispositivo si tratta.",
        "Settings › SSH › Replace the key creates a new key and deletes the old one from this device.":
            "Impostazioni › SSH › Sostituisci la chiave crea una nuova chiave ed elimina la vecchia da questo dispositivo.",
        "Host key changed? If you reinstalled the server, check its new fingerprint, then Settings › SSH › the host › Forget the host key.":
            "Chiave dell’host cambiata? Se hai reinstallato il server, controlla la nuova impronta, poi Impostazioni › SSH › l’host › Dimentica la chiave dell’host.",
        "Connection refused or unreachable":
            "Connessione rifiutata o non raggiungibile",
        "Check the VPN, the address and the port (22 by default), and that the SSH server runs on the host.":
            "Controlla la VPN, l’indirizzo e la porta (22 per impostazione predefinita) e che il server SSH sia attivo sull’host.",
        "Key refused":
            "Chiave rifiutata",
        "The line is missing from that user's authorized_keys, or the file's permissions are too open (sshd then ignores it). The server's log says why:":
            "Manca la riga nell’authorized_keys di quell’utente, o i permessi del file sono troppo aperti (sshd allora lo ignora). Il log del server indica il motivo:",
        "This rule is root in every container of the node, and nearly root on the node itself for a privileged container: keep it for a dedicated user, with the key's from= restriction.":
            "Questa regola equivale a root in tutti i container del nodo, e quasi a root sul nodo stesso per un container privilegiato: riservala a un utente dedicato, con la restrizione from= della chiave.",
        "A role on a deeper path replaces, for the same user or token, the roles inherited from above: PatchNodeConsole alone on /vms/101 takes PVEAuditor away there, and the guest vanishes from PatchNode. On any path other than /, always grant PVEAuditor with the role, and PatchNodePower too if the guest keeps its actions ('PVEAuditor,PatchNodePower,PatchNodeConsole'), to the user and to the token. Use a user dedicated to PatchNode: on your own account, such an ACL would also replace your other roles on that path.":
            "Un ruolo su un percorso più preciso sostituisce, per lo stesso utente o token, i ruoli ereditati dall’alto: PatchNodeConsole da solo su /vms/101 vi toglie PVEAuditor, e il guest sparisce da PatchNode. Su qualsiasi percorso diverso da /, concedi sempre PVEAuditor insieme al ruolo, e anche PatchNodePower se il guest mantiene le sue azioni ('PVEAuditor,PatchNodePower,PatchNodeConsole'), all’utente e al token. Usa un utente dedicato a PatchNode: sul tuo account, un’ACL del genere sostituirebbe anche i tuoi altri ruoli su quel percorso.",
        "Check the token's effective rights on a path (user, token ID, path):":
            "Verifica i diritti effettivi del token su un percorso (utente, ID del token, percorso):",
        "A guest vanished after a role was granted on its path (/vms/<id>, /vms): that ACL replaced PVEAuditor inherited from /. Grant 'PVEAuditor,<role>' on that path instead, then check:":
            "Un guest è sparito dopo un ruolo concesso sul suo percorso (/vms/<id>, /vms): quell’ACL ha sostituito PVEAuditor ereditato da /. Concedi invece 'PVEAuditor,<ruolo>' su quel percorso, poi verifica:",
    ]
}
