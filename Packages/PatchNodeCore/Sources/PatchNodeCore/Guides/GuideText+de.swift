// German translations of the built-in guides, keyed by the English text.
// Generated from the translation tables; to be proofread by a native speaker.
// A missing entry falls back to English (GuideLibraryTests checks there is none).

extension GuideText {
    static let de: [String: String] = [
        "Disks in standby: reading SMART makes Proxmox run smartctl on every disk, which wakes up disks that went to sleep (spindown). PatchNode reads the disks only as you choose for each service in Disk health: Off (no request to the disks at all, no disk notification), On demand (the default: only with the button) or Automatic, once a day from a chosen time. A read covers the disk list with SMART and the ZFS pools; in between, the screen and the disk notifications use the last read, with its date. Pick a time when the disks already spin, for example during a scheduled backup.":
            "Festplatten im Ruhezustand: Das Lesen von SMART lässt Proxmox smartctl auf jeder Festplatte ausführen, was schlafende Festplatten aufweckt (Spindown). PatchNode liest die Festplatten nur so, wie du es für jeden Dienst unter Festplattenzustand wählst: Aus (keine Anfrage an die Festplatten, keine Festplattenmitteilung), Auf Anfrage (Standard: nur über die Schaltfläche) oder Automatisch, einmal täglich ab einer gewählten Uhrzeit. Eine Abfrage umfasst die Festplattenliste mit SMART und die ZFS-Pools; dazwischen nutzen der Bildschirm und die Festplattenmitteilungen die letzte Abfrage mit ihrem Datum. Wähle eine Uhrzeit, zu der die Festplatten ohnehin laufen, zum Beispiel während eines geplanten Backups.",
        "1. VPN. With Tailscale, install it on the server running the reverse proxy and on the iPhone, then advertise your LAN as a subnet route:":
            "1. VPN. Installiere Tailscale auf dem Server mit dem Reverse Proxy und auf dem iPhone und gib dann dein LAN als Subnetzroute frei:",
        "100.64.0.0/10 is Tailscale's range. Select this Access List on each proxy host. Other proxies (Traefik, Caddy) have an equivalent IP allow-list.":
            "100.64.0.0/10 ist der Bereich von Tailscale. Wähle diese Access List bei jedem Proxy-Host. Andere Proxys (Traefik, Caddy) haben eine gleichwertige IP-Freigabeliste.",
        "2. Split DNS. Give every service a name in your domain (proxmox.example.invalid…) that resolves to the reverse proxy's LAN address, for example with an AdGuard Home or Pi-hole rewrite:":
            "2. Split DNS. Gib jedem Dienst einen Namen in deiner Domain (proxmox.example.invalid…), der auf die LAN-Adresse des Reverse Proxys auflöst, zum Beispiel mit einem Rewrite in AdGuard Home oder Pi-hole:",
        "3. Certificate. A wildcard certificate for *.example.com from Let's Encrypt with a DNS challenge works without opening any port to the internet.":
            "3. Zertifikat. Ein Wildcard-Zertifikat für *.example.com von Let’s Encrypt mit DNS-Challenge funktioniert, ohne einen Port ins Internet zu öffnen.",
        "301 Moved Permanently":
            "301 Moved Permanently",
        "400 Bad Request behind the proxy":
            "400 Bad Request hinter dem Proxy",
        "403: scope missing":
            "403: Scope fehlt",
        "421 Misdirected Request":
            "421 Misdirected Request",
        "A VPN such as Tailscale or WireGuard for access from outside.":
            "Ein VPN wie Tailscale oder WireGuard für den Zugriff von unterwegs.",
        "A bouncer key only reads decisions: it can't add or remove any. PatchNode has no action on CrowdSec.":
            "Ein Bouncer-Schlüssel liest nur Entscheidungen: Er kann keine hinzufügen oder entfernen. PatchNode hat keine Aktion für CrowdSec.",
        "A cluster is one service: add any of its nodes. Nodes outside a cluster are separate services: add one service per node.":
            "Ein Cluster ist ein Dienst: Füge einen beliebigen seiner Knoten hinzu. Knoten außerhalb eines Clusters sind getrennte Dienste: Füge einen Dienst pro Knoten hinzu.",
        "A dashboard asks to sign in":
            "Ein Dashboard verlangt eine Anmeldung",
        "A non-admin user can read states and call services, but not change the configuration. PatchNode only runs the scenes and scripts you pinned, after a confirmation.":
            "Ein Benutzer ohne Adminrechte kann Zustände lesen und Dienste aufrufen, aber nicht die Konfiguration ändern. PatchNode führt nur die angehefteten Szenen und Skripte aus, nach einer Bestätigung.",
        "A saved chart shows an error":
            "Ein gespeichertes Diagramm zeigt einen Fehler",
        "API Token tab › Add: user monitor@pbs, Token Name patchnode. Copy the secret.":
            "Tab API Token › Add: Benutzer monitor@pbs, Token Name patchnode. Kopiere das Geheimnis.",
        "Access List: allow your LAN and VPN ranges (100.64.0.0/10 for Tailscale).":
            "Access List: Erlaube die Bereiche deines LANs und VPNs (100.64.0.0/10 für Tailscale).",
        "Access Lists › Add Access List › Details: tick Satisfy All (both the password and the address are required).":
            "Access Lists › Add Access List › Details: Satisfy All ankreuzen (Passwort und Adresse sind beide nötig).",
        "Access blocked by the reverse proxy (403 page)":
            "Zugriff vom Reverse Proxy blockiert (403-Seite)",
        "Access restricted to your LAN and VPN.":
            "Zugriff auf dein LAN und VPN beschränkt.",
        "Access tab: allow 192.0.2.0/24 and 100.64.0.0/10, deny all.":
            "Tab Access: 192.0.2.0/24 und 100.64.0.0/10 erlauben, alles andere verweigern.",
        "Access token rejected (401)":
            "Zugriffstoken abgelehnt (401)",
        "Actions: POST=1, only while you need them. With POST=0, PatchNode shows “actions disabled”.":
            "Aktionen: POST=1, nur solange du sie brauchst. Mit POST=0 zeigt PatchNode „Aktionen deaktiviert“.",
        "Actions: rather than PVEVMUser (which also allows the console and more), create a role with the VM.PowerMgmt privilege only, on /vms, or /vms/100 for a single VM, with PVEAuditor next to it (see the warning below):":
            "Aktionen: Statt PVEVMUser (das auch die Konsole und mehr erlaubt) eine Rolle nur mit dem Privileg VM.PowerMgmt anlegen, auf /vms oder /vms/100 für eine einzelne VM, zusammen mit PVEAuditor (siehe Warnung unten):",
        "Active alerts sorted by severity.":
            "Aktive Alarme nach Schweregrad sortiert.",
        "Active bans of your Local API.":
            "Aktive Sperren deiner Local API.",
        "AdGuard Home":
            "AdGuard Home",
        "AdGuard Home compares with the bcrypt hash of AdGuardHome.yaml: generate it again, then restart AdGuard Home.":
            "AdGuard Home vergleicht mit dem bcrypt-Hash in AdGuardHome.yaml: Erzeuge ihn neu und starte AdGuard Home neu.",
        "AdGuard Home has no read-only role: this user can change the DNS settings. Keep AdGuard Home reachable only through your LAN and VPN. PatchNode only reads.":
            "AdGuard Home hat keine Nur-Lese-Rolle: Dieser Benutzer kann die DNS-Einstellungen ändern. Halte AdGuard Home nur über dein LAN und VPN erreichbar. PatchNode liest nur.",
        "Add a dedicated user to the users section of AdGuardHome.yaml, with a bcrypt password hash, then restart AdGuard Home:":
            "Füge in AdGuardHome.yaml im Abschnitt users einen eigenen Benutzer mit bcrypt-Passworthash hinzu und starte AdGuard Home neu:",
        "Add service account token, no expiry or a long one. Copy it (glsa_…).":
            "Add service account token, ohne Ablauf oder mit langem Ablauf. Kopiere es (glsa_…).",
        "Add the monitors to show, then Save.":
            "Füge die anzuzeigenden Monitore hinzu, dann Save.",
        "Administration › User-related › Users › Add user: a standard (non-admin) user, e.g. patchnode.":
            "Administration › User-related › Users › Add user: ein Standardbenutzer (kein Admin), z. B. patchnode.",
        "Administration › Users and access › Service accounts › Add service account: name patchnode, role Viewer.":
            "Administration › Users and access › Service accounts › Add service account: Name patchnode, Rolle Viewer.",
        "Alertmanager":
            "Alertmanager",
        "Allow-list the same ranges in your IPS, so a wrong token (repeated 401/403) never bans your own phone. With CrowdSec:":
            "Setze dieselben Bereiche in deinem IPS auf die Freigabeliste, damit ein falsches Token (wiederholte 401/403) nie dein eigenes Telefon sperrt. Mit CrowdSec:",
        "Allow-list your LAN and VPN in CrowdSec (see Network prerequisites), so a wrong key never bans your own phone.":
            "Setze dein LAN und VPN in CrowdSec auf die Freigabeliste (siehe Netzwerkvoraussetzungen), damit ein falscher Schlüssel nie dein eigenes Telefon sperrt.",
        "An HTTPS reverse proxy with a valid certificate in front of every service (PatchNode refuses plain HTTP and invalid certificates).":
            "Ein HTTPS-Reverse-Proxy mit gültigem Zertifikat vor jedem Dienst (PatchNode lehnt unverschlüsseltes HTTP und ungültige Zertifikate ab).",
        "An action refused with “insufficient rights” needs VM.PowerMgmt (the PatchNodePower role in Minimum rights).":
            "Eine mit „unzureichende Rechte“ abgelehnte Aktion braucht VM.PowerMgmt (die Rolle PatchNodePower unter Mindestrechte).",
        "An alert is missing":
            "Ein Alarm fehlt",
        "An environment shows as unreachable":
            "Eine Umgebung wird als nicht erreichbar angezeigt",
        "Attach Nginx Proxy Manager's container to the same proxy network. If the reverse proxy runs on another host, publish the port on the LAN address only (never 0.0.0.0) and let only the proxy's address through:":
            "Hänge den Container von Nginx Proxy Manager an dasselbe Proxy-Netzwerk. Läuft der Reverse Proxy auf einem anderen Host, veröffentliche den Port nur auf der LAN-Adresse (nie 0.0.0.0) und lass nur die Adresse des Proxys durch:",
        "Authorization tab: add a user name and password.":
            "Tab Authorization: Benutzername und Passwort hinzufügen.",
        "Banned by CrowdSec or fail2ban: list and remove the decision, then allow-list your ranges (see Network prerequisites).":
            "Von CrowdSec oder fail2ban gesperrt: Entscheidung auflisten und entfernen, dann deine Bereiche freigeben (siehe Netzwerkvoraussetzungen).",
        "Business Edition: give the user the Read-only user role for reading only. Community Edition has no read-only role: a standard user can act on the containers of its environments.":
            "Business Edition: Gib dem Benutzer die Rolle Read-only user, um nur zu lesen. Die Community Edition hat keine Nur-Lese-Rolle: Ein Standardbenutzer kann die Container seiner Umgebungen steuern.",
        "CONTAINERS=1 also lets the reader see containers' environment variables, which often hold passwords. That's why the proxy must require authentication and stay on your LAN.":
            "CONTAINERS=1 zeigt auch die Umgebungsvariablen der Container, die oft Passwörter enthalten. Deshalb muss der Proxy eine Authentifizierung verlangen und in deinem LAN bleiben.",
        "CPU, memory, load, disks and temperatures of a host.":
            "CPU, Speicher, Last, Festplatten und Temperaturen eines Hosts.",
        "Check it hasn't expired or been revoked in the service.":
            "Prüfe, dass es im Dienst nicht abgelaufen oder widerrufen ist.",
        "Check it with curl (Verify section of the service's guide).":
            "Prüfe es mit curl (Abschnitt Prüfen in der Anleitung des Dienstes).",
        "Check the host's load.":
            "Prüfe die Last des Hosts.",
        "Client rejected (401)":
            "Client abgelehnt (401)",
        "Configuration › Access Control › User Management › Add: user monitor, realm pbs (monitor@pbs).":
            "Configuration › Access Control › User Management › Add: Benutzer monitor, Realm pbs (monitor@pbs).",
        "Containers and stacks of every Docker environment managed by Portainer.":
            "Container und Stacks aller von Portainer verwalteten Docker-Umgebungen.",
        "Containers of a Docker host through a read-only socket proxy.":
            "Container eines Docker-Hosts über einen schreibgeschützten Socket-Proxy.",
        "Copy the client ID and the client secret (tskey-client-…), shown once.":
            "Kopiere Client-ID und Client-Secret (tskey-client-…), die nur einmal angezeigt werden.",
        "Copy the key (shown once) and paste it in PatchNode.":
            "Kopiere den Schlüssel (nur einmal angezeigt) und füge ihn in PatchNode ein.",
        "Copy the secret now: Proxmox shows it only once.":
            "Kopiere das Geheimnis jetzt: Proxmox zeigt es nur einmal.",
        "Copy the token (shown once) and paste it in PatchNode.":
            "Kopiere das Token (nur einmal angezeigt) und füge es in PatchNode ein.",
        "Copy the token again: a missing character, a space or a line break is enough to break it.":
            "Kopiere das Token erneut: Ein fehlendes Zeichen, ein Leerzeichen oder ein Zeilenumbruch reicht, um es unbrauchbar zu machen.",
        "Create an access token (My account › Access tokens), not an Edge key or an API key of another tool.":
            "Erstelle ein Zugriffstoken (My account › Access tokens), keinen Edge-Schlüssel und keinen API-Schlüssel eines anderen Tools.",
        "CrowdSec":
            "CrowdSec",
        "CrowdSec answers 403 for an unknown key. Check it with cscli bouncers list, or create a new one.":
            "CrowdSec antwortet bei einem unbekannten Schlüssel mit 403. Prüfe ihn mit cscli bouncers list oder erstelle einen neuen.",
        "Dashboards and Grafana alerts.":
            "Dashboards und Grafana-Alarme.",
        "Datacenter › Permissions › API Tokens › Add: user monitor@pve, Token ID patchnode. Keep Privilege Separation ticked (recommended).":
            "Datacenter › Permissions › API Tokens › Add: Benutzer monitor@pve, Token ID patchnode. Privilege Separation angekreuzt lassen (empfohlen).",
        "Datacenter › Permissions › Users › Add: user monitor, realm Proxmox VE authentication server (monitor@pve). No password is needed for API use.":
            "Datacenter › Permissions › Users › Add: Benutzer monitor, Realm Proxmox VE authentication server (monitor@pve). Für die API-Nutzung ist kein Passwort nötig.",
        "Datastores, latest backup of every guest, failed jobs.":
            "Datastores, letzte Sicherung jedes Gasts, fehlgeschlagene Jobs.",
        "Devices of your tailnet: online, offline, keys about to expire.":
            "Geräte deines Tailnets: online, offline, bald ablaufende Schlüssel.",
        "Devices › Core › Read only. PatchNode has no action on Tailscale.":
            "Devices › Core › nur Read. PatchNode hat keine Aktion für Tailscale.",
        "Docker (socket proxy)":
            "Docker (Socket-Proxy)",
        "Does split DNS answer through the VPN? Otherwise the name resolves to nothing, or to a public address.":
            "Antwortet das Split DNS über das VPN? Sonst löst der Name zu nichts oder zu einer öffentlichen Adresse auf.",
        "Does the Access List allow 100.64.0.0/10?":
            "Erlaubt die Access List 100.64.0.0/10?",
        "Does the name resolve? A typo in the URL gives the same error.":
            "Wird der Name aufgelöst? Ein Tippfehler in der URL ergibt denselben Fehler.",
        "Don't set listen_uri to the LAN address alone: cscli and the bouncers on 127.0.0.1 would lose the API and bans would stop being applied. cscli lapi status must still answer.":
            "Setze listen_uri nicht nur auf die LAN-Adresse: cscli und die Bouncer auf 127.0.0.1 verlören die API, und Sperren würden nicht mehr angewendet. cscli lapi status muss weiter antworten.",
        "Don't use the API access keys of Settings › Keys: they expire within 90 days and carry all your rights. The OAuth client is limited to reading devices, and PatchNode exchanges it for a one-hour token kept in memory only.":
            "Verwende nicht die API-Schlüssel unter Settings › Keys: Sie laufen innerhalb von 90 Tagen ab und haben alle deine Rechte. Der OAuth-Client darf nur Geräte lesen, und PatchNode tauscht ihn gegen ein 1-Stunden-Token, das nur im Speicher bleibt.",
        "E-mail or password rejected":
            "E-Mail oder Passwort abgelehnt",
        "Empty list, or “token without rights”":
            "Leere Liste oder „Token ohne Rechte“",
        "Enter client-id:client-secret, separated by a colon.":
            "Gib client-id:client-secret ein, durch einen Doppelpunkt getrennt.",
        "Enter the user and password of the Access List's Authorization tab, not those of Nginx Proxy Manager's admin.":
            "Gib Benutzer und Passwort aus dem Tab Authorization der Access List ein, nicht die des Admins von Nginx Proxy Manager.",
        "Environments › your environment › Manage access: give this user access to the environments to monitor.":
            "Environments › deine Umgebung › Manage access: Gib diesem Benutzer Zugriff auf die zu überwachenden Umgebungen.",
        "From a computer on the VPN, check that the name resolves to the proxy and that the certificate is valid:":
            "Prüfe von einem Rechner im VPN, dass der Name auf den Proxy auflöst und das Zertifikat gültig ist:",
        "Generate a new client with Devices › Core › Read.":
            "Erzeuge einen neuen Client mit Devices › Core › Read.",
        "Give PatchNode dedicated accounts and tokens, read-only first. Add the rights for actions (start, stop, restart) only once reading works, and only on what you want to control.":
            "Gib PatchNode eigene Konten und Tokens, zunächst nur lesend. Füge die Rechte für Aktionen (starten, stoppen, neu starten) erst hinzu, wenn das Lesen funktioniert, und nur für das, was du steuern willst.",
        "Give the user View Only on Proxy Hosts (Users › the user › Permissions).":
            "Gib dem Benutzer View Only für Proxy Hosts (Users › der Benutzer › Permissions).",
        "Glances":
            "Glances",
        "Glances 3 answers on /api/3/cpu; PatchNode tries both.":
            "Glances 3 antwortet unter /api/3/cpu; PatchNode versucht beide.",
        "Glances only reads. With --password, it asks for a password (default user glances): enter the user and password in PatchNode; without it, leave both fields empty and rely on the Access List.":
            "Glances liest nur. Mit --password verlangt es ein Passwort (Standardbenutzer glances): Gib Benutzer und Passwort in PatchNode ein; ohne lass beide Felder leer und verlass dich auf die Access List.",
        "Grafana":
            "Grafana",
        "Grant Audit on / to the user and the token. A datastore refused alone (per-datastore permissions) is shown without its details.":
            "Vergib Audit auf / an Benutzer und Token. Ein einzeln abgelehnter Datastore (Rechte pro Datastore) wird ohne Details angezeigt.",
        "Home Assistant":
            "Home Assistant",
        "Home Assistant must trust the proxy, in configuration.yaml:":
            "Home Assistant muss dem Proxy vertrauen, in configuration.yaml:",
        "Home Assistant refuses forwarded requests from an untrusted proxy: add use_x_forwarded_for and trusted_proxies (Reverse proxy section), then restart.":
            "Home Assistant lehnt weitergeleitete Anfragen eines nicht vertrauenswürdigen Proxys ab: Füge use_x_forwarded_for und trusted_proxies hinzu (Abschnitt Reverse Proxy), dann neu starten.",
        "If it keeps happening, Settings › Diagnostics shows the requests (protocol, connection reused). That log contains your services' names and API paths: read it before sharing it with anyone.":
            "Passiert es weiterhin, zeigt Einstellungen › Diagnose die Anfragen (Protokoll, wiederverwendete Verbindung). Dieses Protokoll enthält die Namen deiner Dienste und API-Pfade: Lies es, bevor du es teilst.",
        "In PatchNode, enter client-id:client-secret. No URL to type.":
            "Gib in PatchNode client-id:client-secret ein. Keine URL nötig.",
        "In PatchNode, enter the e-mail and the password. PatchNode gets a session token from them, kept in memory only.":
            "Gib in PatchNode E-Mail und Passwort ein. PatchNode erhält daraus ein Sitzungstoken, das nur im Speicher bleibt.",
        "In PatchNode, enter the same user name and password in the two fields.":
            "Gib in PatchNode denselben Benutzernamen und dasselbe Passwort in die beiden Felder ein.",
        "In PatchNode, enter the status page's URL, ending with /status/<slug>. No token.":
            "Gib in PatchNode die URL der Statusseite ein, endend auf /status/<slug>. Kein Token.",
        "In PatchNode, enter this user name and password.":
            "Gib in PatchNode diesen Benutzernamen und dieses Passwort ein.",
        "In PatchNode, open Home Assistant › Choose entities.":
            "Öffne in PatchNode Home Assistant › Entitäten wählen.",
        "In PatchNode, paste the full value: user@realm!tokenid=secret.":
            "Füge in PatchNode den vollständigen Wert ein: user@realm!tokenid=secret.",
        "In PatchNode, paste the token.":
            "Füge in PatchNode das Token ein.",
        "In PatchNode, paste user@realm!tokenid:secret — with a colon, unlike Proxmox VE.":
            "Füge in PatchNode user@realm!tokenid:secret ein, mit Doppelpunkt, anders als bei Proxmox VE.",
        "In PatchNode, use Portainer's own URL and paste the token.":
            "Verwende in PatchNode die URL von Portainer selbst und füge das Token ein.",
        "In Nginx Proxy Manager, create an Access List with a user and password, and your LAN and VPN ranges:":
            "Erstelle in Nginx Proxy Manager eine Access List mit Benutzer und Passwort sowie den Bereichen deines LANs und VPNs:",
        "In Uptime Kuma, Status Pages › New Status Page: a name and a slug, e.g. homelab.":
            "In Uptime Kuma unter Status Pages › New Status Page: ein Name und ein Slug, z. B. homelab.",
        "In the Tailscale admin console, Machines › the server › Edit route settings: approve the route.":
            "In der Tailscale-Adminkonsole unter Machines › der Server › Edit route settings: Route freigeben.",
        "In the Tailscale admin console: Settings › Trust credentials (formerly OAuth clients) › Generate OAuth client.":
            "In der Tailscale-Adminkonsole: Settings › Trust credentials (früher OAuth clients) › Generate OAuth client.",
        "In zsh and bash, the ! of the token name must be inside single quotes ('monitor@pve!patchnode'), otherwise the shell tries to expand it.":
            "In zsh und bash muss das ! im Tokennamen in einfachen Anführungszeichen stehen ('monitor@pve!patchnode'), sonst versucht die Shell, es zu expandieren.",
        "Insufficient rights (403 from the service)":
            "Unzureichende Rechte (403 vom Dienst)",
        "Is the VPN connected on the iPhone?":
            "Ist das VPN auf dem iPhone verbunden?",
        "Is the certificate valid for this name? PatchNode refuses invalid and self-signed certificates.":
            "Ist das Zertifikat für diesen Namen gültig? PatchNode lehnt ungültige und selbst signierte Zertifikate ab.",
        "Is the reverse proxy up, and the service behind it?":
            "Laufen der Reverse Proxy und der Dienst dahinter?",
        "Is the subnet route approved in the Tailscale admin console?":
            "Ist die Subnetzroute in der Tailscale-Adminkonsole freigegeben?",
        "It works at home but not outside":
            "Es funktioniert zu Hause, aber nicht unterwegs",
        "It's the only service reached outside your private network: api.tailscale.com.":
            "Es ist der einzige Dienst außerhalb deines privaten Netzwerks: api.tailscale.com.",
        "Key rejected (403 from CrowdSec)":
            "Schlüssel abgelehnt (403 von CrowdSec)",
        "PatchNode lists active decisions (bans and captchas) from local detections and manual bans: IP or range, scenario, time left. Community blocklists aren't listed.":
            "PatchNode zeigt die aktiven Entscheidungen (Sperren und Captchas) aus lokalen Erkennungen und manuellen Sperren: IP oder Bereich, Szenario, Restzeit. Community-Blocklisten werden nicht aufgeführt.",
        "PatchNode lists every Docker environment of Portainer, their containers grouped by stack, with health, logs, CPU and memory, and can start, stop and restart a container.":
            "PatchNode zeigt jede Docker-Umgebung von Portainer und ihre Container nach Stack gruppiert, mit Zustand, Logs, CPU und Speicher, und kann einen Container starten, stoppen und neu starten.",
        "PatchNode lists the host's containers grouped by Compose project, with health, status, image, CPU and memory, logs, ports and volumes. With POST allowed, it can start, stop and restart a container.":
            "PatchNode zeigt die Container des Hosts nach Compose-Projekt gruppiert, mit Zustand, Status, Image, CPU und Speicher, Logs, Ports und Volumes. Mit erlaubtem POST kann es einen Container starten, stoppen und neu starten.",
        "PatchNode lists the scrape targets with those down first, and draws the PromQL queries you save as charts (CPU, memory, disks…).":
            "PatchNode zeigt die Scrape-Ziele, ausgefallene zuerst, und zeichnet deine gespeicherten PromQL-Abfragen als Diagramme (CPU, Speicher, Festplatten…).",
        "PatchNode lists your dashboards (they open in an embedded browser where you sign in as usual) and shows Grafana's unified alerting alerts with the others.":
            "PatchNode zeigt deine Dashboards (sie öffnen sich in einem eingebetteten Browser, in dem du dich wie gewohnt anmeldest) und die Alarme aus Grafanas Unified Alerting zusammen mit den anderen.",
        "PatchNode lists your proxy hosts: enabled or not, destination, certificate, and in red those nginx refused (bad upstream, configuration error).":
            "PatchNode zeigt deine Proxy-Hosts: aktiviert oder nicht, Ziel, Zertifikat, und in Rot die von nginx abgelehnten (falscher Upstream, Konfigurationsfehler).",
        "PatchNode lists your tailnet's devices: online or last seen, address, OS, and flags those offline for more than a day, keys expiring within 14 days and devices waiting for approval.":
            "PatchNode zeigt die Geräte deines Tailnets: online oder zuletzt gesehen, Adresse, Betriebssystem, und markiert Geräte, die seit über einem Tag offline sind, Schlüssel, die in 14 Tagen ablaufen, und Geräte, die auf Freigabe warten.",
        "PatchNode pauses the service and tries again after 30 s, 60 s, then every 2 minutes, to avoid being banned.":
            "PatchNode pausiert den Dienst und versucht es nach 30 s, 60 s und dann alle 2 Minuten erneut, um nicht gesperrt zu werden.",
        "PatchNode reads a public status page of Uptime Kuma: each monitor's state, 24-hour uptime and latest heartbeats. A monitor down becomes an alert.":
            "PatchNode liest eine öffentliche Statusseite von Uptime Kuma: Zustand jedes Monitors, Verfügbarkeit über 24 Stunden und letzte Heartbeats. Ein ausgefallener Monitor wird zum Alarm.",
        "PatchNode shows Prometheus's own message. Test the query in Prometheus's web interface (Graph) first, then paste it again.":
            "PatchNode zeigt die Meldung von Prometheus selbst. Teste die Abfrage zuerst in der Weboberfläche von Prometheus (Graph) und füge sie dann erneut ein.",
        "PatchNode shows a host's CPU, memory and swap, load, file systems (orange above 85 %) and temperatures.":
            "PatchNode zeigt CPU, Speicher und Swap, Last, Dateisysteme (orange über 85 %) und Temperaturen eines Hosts.",
        "PatchNode shows active alerts sorted by severity (critical, warning, info) with a badge on the tab. Silenced and inhibited alerts are left out.":
            "PatchNode zeigt aktive Alarme nach Schweregrad sortiert (critical, warning, info) mit einem Badge auf dem Tab. Stummgeschaltete und unterdrückte Alarme werden ausgelassen.",
        "PatchNode shows each datastore's space, the latest backup of every VM and container (in orange after two days) and recent backup, verify, prune and garbage collection tasks.":
            "PatchNode zeigt den Platz jedes Datastores, die letzte Sicherung jeder VM und jedes Containers (orange nach zwei Tagen) und aktuelle Backup-, Verify-, Prune- und Garbage-Collection-Aufgaben.",
        "PatchNode shows the sensors, lights and switches you pick, with their state, and can run the scenes and scripts you pick after a confirmation naming them.":
            "PatchNode zeigt die gewählten Sensoren, Lichter und Schalter mit ihrem Zustand und kann die gewählten Szenen und Skripte nach einer Bestätigung mit ihrem Namen ausführen.",
        "PatchNode shows whether protection is on, the number of queries and the share blocked, the average processing time, and the most queried and blocked domains.":
            "PatchNode zeigt, ob der Schutz an ist, die Zahl der Anfragen und den blockierten Anteil, die durchschnittliche Bearbeitungszeit und die am häufigsten abgefragten und blockierten Domains.",
        "PatchNode shows your nodes (CPU, memory, disks, storage), every VM and container with charts per hour, day or week, and recent tasks with failures first. With the right role, it can start, shut down, stop or reboot a VM or container after a confirmation.":
            "PatchNode zeigt deine Knoten (CPU, Speicher, Festplatten, Storage), jede VM und jeden Container mit Diagrammen pro Stunde, Tag oder Woche und die letzten Aufgaben, Fehler zuerst. Mit der passenden Rolle kann es eine VM oder einen Container nach einer Bestätigung starten, herunterfahren, stoppen oder neu starten.",
        "PatchNode talks directly from your iPhone to your servers. Nothing goes through a server of ours, so your iPhone must reach them: at home on Wi-Fi, and elsewhere through a VPN.":
            "PatchNode spricht direkt von deinem iPhone mit deinen Servern. Nichts läuft über einen Server von uns, also muss dein iPhone sie erreichen: zu Hause per WLAN, unterwegs über ein VPN.",
        "PatchNode waits 10 seconds per request. A slow VPN route, an overloaded host or a heavy endpoint can exceed it.":
            "PatchNode wartet 10 Sekunden pro Anfrage. Eine langsame VPN-Route, ein überlasteter Host oder ein aufwendiger Endpunkt kann das überschreiten.",
        "Monitors of a status page, with uptime and latest heartbeats.":
            "Monitore einer Statusseite, mit Verfügbarkeit und letzten Heartbeats.",
        "Network prerequisites":
            "Netzwerkvoraussetzungen",
        "Never expose /var/run/docker.sock or the raw port 2375, even on your LAN: whoever reaches it is root on the host. Always go through a socket proxy and an authenticated reverse proxy.":
            "Gib niemals /var/run/docker.sock oder den rohen Port 2375 frei, auch nicht im LAN: Wer ihn erreicht, ist root auf dem Host. Geh immer über einen Socket-Proxy und einen authentifizierten Reverse Proxy.",
        "Never expose these services directly to the internet: PatchNode doesn't need it.":
            "Gib diese Dienste niemals direkt ins Internet frei: PatchNode braucht das nicht.",
        "Nginx Proxy Manager":
            "Nginx Proxy Manager",
        "No active local ban: the API answers null. PatchNode shows “No active bans”.":
            "Keine aktive lokale Sperre: Die API antwortet null. PatchNode zeigt „Keine aktiven Sperren“.",
        "No datastore, or 403":
            "Kein Datastore oder 403",
        "No proxy host listed":
            "Kein Proxy-Host aufgeführt",
        "Nodes outside a cluster are separate services: add each one as its own service. PatchNode shows the service name first so they stay distinct.":
            "Knoten außerhalb eines Clusters sind getrennte Dienste: Füge jeden als eigenen Dienst hinzu. PatchNode zeigt den Dienstnamen zuerst, damit sie unterscheidbar bleiben.",
        "Nodes, VMs and containers, storage, tasks, power actions.":
            "Knoten, VMs und Container, Storage, Aufgaben, Ein-/Aus-Aktionen.",
        "None: PatchNode calls api.tailscale.com directly, over HTTPS.":
            "Keiner: PatchNode ruft api.tailscale.com direkt über HTTPS auf.",
        "Nothing to create in Prometheus: PatchNode only reads its HTTP API. Add a proxy host in front of it (below), then the URL in PatchNode.":
            "In Prometheus ist nichts anzulegen: PatchNode liest nur seine HTTP-API. Setze einen Proxy-Host davor (unten), dann die URL in PatchNode.",
        "Nothing to create: PatchNode reads the v2 API. Set a severity label on your alert rules (critical, warning, info) to get them sorted.":
            "Nichts anzulegen: PatchNode liest die v2-API. Setze ein Label severity in deinen Alarmregeln (critical, warning, info), damit sie sortiert werden.",
        "Nothing to grant: only the monitors placed on this page are read. PatchNode has no action on Uptime Kuma.":
            "Nichts freizugeben: Nur die Monitore auf dieser Seite werden gelesen. PatchNode hat keine Aktion für Uptime Kuma.",
        "On the CrowdSec host, create a bouncer key for PatchNode:":
            "Erstelle auf dem CrowdSec-Host einen Bouncer-Schlüssel für PatchNode:",
        "On the iPhone, open the Tailscale app and connect.":
            "Öffne auf dem iPhone die Tailscale-App und verbinde dich.",
        "PBS listens in HTTPS on port 8007: forward with the https scheme.":
            "PBS lauscht per HTTPS auf Port 8007: mit dem Schema https weiterleiten.",
        "PBS uses a colon between the token ID and the secret: user@realm!tokenid:secret.":
            "PBS verwendet einen Doppelpunkt zwischen Token-ID und Geheimnis: user@realm!tokenid:secret.",
        "Paste the full value user@realm!tokenid=secret, with = before the secret.":
            "Füge den vollständigen Wert user@realm!tokenid=secret ein, mit = vor dem Geheimnis.",
        "Permissions: Proxy Hosts › View Only, everything else Hidden.":
            "Permissions: Proxy Hosts › View Only, alles andere Hidden.",
        "Port 9443 is Portainer's HTTPS port (scheme https); 9000 is plain HTTP (scheme http).":
            "Port 9443 ist der HTTPS-Port von Portainer (Schema https); 9000 ist unverschlüsseltes HTTP (Schema http).",
        "Portainer":
            "Portainer",
        "Portainer itself can't reach this environment (agent stopped, host off). Check it in Portainer's Environments page.":
            "Portainer selbst erreicht diese Umgebung nicht (Agent gestoppt, Host aus). Prüfe es auf der Seite Environments in Portainer.",
        "Privilege Separation is ticked and the token has no permission of its own, or its user has none: the token's rights are the intersection of both. Grant PVEAuditor on / to the user and to the token.":
            "Privilege Separation ist angekreuzt und das Token hat keine eigene Berechtigung, oder sein Benutzer hat keine: Die Rechte des Tokens sind die Schnittmenge beider. Vergib PVEAuditor auf / an Benutzer und Token.",
        "Prometheus":
            "Prometheus",
        "Prometheus and Alertmanager have no token. Keep them on your LAN and VPN only; for a password, add an Access List with a user in Nginx Proxy Manager (Authorization tab, Satisfy All) and enter the same user and password in PatchNode. Without authentication, leave both fields empty.":
            "Prometheus und Alertmanager haben kein Token. Halte sie nur im LAN und VPN; für ein Passwort füge in Nginx Proxy Manager eine Access List mit Benutzer hinzu (Tab Authorization, Satisfy All) und gib denselben Benutzer und dasselbe Passwort in PatchNode ein. Ohne Authentifizierung lass beide Felder leer.",
        "Protection state and DNS statistics.":
            "Schutzstatus und DNS-Statistik.",
        "Proxmox Backup Server":
            "Proxmox Backup Server",
        "Proxmox VE":
            "Proxmox VE",
        "Proxmox itself listens in HTTPS on port 8006. In Nginx Proxy Manager, the proxy host must forward with the https scheme:":
            "Proxmox selbst lauscht per HTTPS auf Port 8006. In Nginx Proxy Manager muss der Proxy-Host mit dem Schema https weiterleiten:",
        "Proxmox › Backups (Proxmox VE) lists the backup jobs, the guests no job covers, the latest archive of every guest (from the storages holding backups, NFS and Proxmox Backup Server storages included) and the failed backup tasks. It needs no other right than PVEAuditor.":
            "Proxmox › Sicherungen (Proxmox VE) zeigt die Sicherungsjobs, die von keinem Job abgedeckten Gäste, das letzte Archiv jedes Gasts (aus den Speichern mit Sicherungen, NFS und Proxmox Backup Server eingeschlossen) und fehlgeschlagene Sicherungen. Mehr als PVEAuditor ist nicht nötig.",
        "Proxmox › Disk health shows, for each online node, the SMART status and remaining life of every disk (Disks in the node's menu) and the state and fill of every ZFS pool. It needs Sys.Audit, which PVEAuditor on / already gives. SMART data comes from smartmontools on the node; disks behind a USB bridge or a RAID controller often report none.":
            "Proxmox › Festplattenzustand zeigt für jeden Online-Knoten den SMART-Status und die Restlebensdauer jeder Festplatte (Disks im Knotenmenü) sowie Zustand und Füllstand jedes ZFS-Pools. Es braucht Sys.Audit, das PVEAuditor auf / bereits gibt. SMART-Daten kommen von smartmontools auf dem Knoten; Festplatten hinter einem USB-Adapter oder RAID-Controller liefern oft keine.",
        "Proxy host docker.example.com → http://docker-socket-proxy:2375 (same Docker network) with this Access List and your certificate.":
            "Proxy-Host docker.example.com → http://docker-socket-proxy:2375 (gleiches Docker-Netzwerk) mit dieser Access List und deinem Zertifikat.",
        "Proxy hosts, certificates, and hosts refused by nginx.":
            "Proxy-Hosts, Zertifikate und von nginx abgelehnte Hosts.",
        "Read-only: role Audit on /, for the user and the token (a token's rights are also limited by its user's). PatchNode has no action on PBS.":
            "Nur lesen: Rolle Audit auf /, für Benutzer und Token (die Rechte eines Tokens sind auch durch die seines Benutzers begrenzt). PatchNode hat keine Aktion für PBS.",
        "Reading: CONTAINERS=1, INFO=1, POST=0 (the default above).":
            "Lesen: CONTAINERS=1, INFO=1, POST=0 (die Vorgabe oben).",
        "Reading: role PVEAuditor on /. With Privilege Separation, a token only has the rights both it and its user have (the intersection): grant the role to both, or the lists stay empty.":
            "Lesen: Rolle PVEAuditor auf /. Mit Privilege Separation hat ein Token nur die Rechte, die es und sein Benutzer gemeinsam haben (die Schnittmenge): Vergib die Rolle beiden, sonst bleiben die Listen leer.",
        "Requests stay paused until you pull to refresh, so a wrong token isn't retried and can't get your IP banned. To change it: Settings › the service › enter the new token.":
            "Anfragen bleiben pausiert, bis du zum Aktualisieren ziehst, damit ein falsches Token nicht erneut versucht wird und deine IP nicht sperren lassen kann. Zum Ändern: Einstellungen › der Dienst › neues Token eingeben.",
        "Restrict every proxy host to your LAN and VPN. In Nginx Proxy Manager: Access Lists › Add Access List › Access tab:":
            "Beschränke jeden Proxy-Host auf dein LAN und VPN. In Nginx Proxy Manager: Access Lists › Add Access List › Tab Access:",
        "Role Viewer: it reads dashboards and alerts, and can't change anything. The token is never put in a dashboard URL.":
            "Rolle Viewer: Sie liest Dashboards und Alarme und kann nichts ändern. Das Token steht nie in der URL eines Dashboards.",
        "Run Glances in web server mode, for example with Docker. --disable-plugin processlist makes each refresh much lighter:":
            "Starte Glances im Webserver-Modus, zum Beispiel mit Docker. --disable-plugin processlist macht jede Aktualisierung viel leichter:",
        "Run tecnativa/docker-socket-proxy without publishing any port, on a Docker network shared with the reverse proxy: only the proxy (and its authentication) can reach it.":
            "Starte tecnativa/docker-socket-proxy ohne veröffentlichten Port in einem mit dem Reverse Proxy geteilten Docker-Netzwerk: Nur der Proxy (und seine Authentifizierung) erreicht ihn.",
        "Scopes: Devices › Core, Read only. Nothing else.":
            "Scopes: Devices › Core, nur Read. Sonst nichts.",
        "Service unreachable":
            "Dienst nicht erreichbar",
        "Set a password for this user.":
            "Lege ein Passwort für diesen Benutzer fest.",
        "Set root_url in grafana.ini to your public name, so links and sign-in redirect correctly:":
            "Setze root_url in grafana.ini auf deinen öffentlichen Namen, damit Links und Anmeldung richtig weiterleiten:",
        "Settings › People › Add person: a dedicated user patchnode, allowed to log in, not an administrator.":
            "Settings › People › Add person: ein eigener Benutzer patchnode, darf sich anmelden, kein Administrator.",
        "Several services share one reverse proxy and one wildcard certificate: iOS may reuse an HTTP/2 connection opened for another name, and the proxy answers 421. PatchNode retries once on a new connection automatically.":
            "Mehrere Dienste teilen sich einen Reverse Proxy und ein Wildcard-Zertifikat: iOS kann eine für einen anderen Namen geöffnete HTTP/2-Verbindung wiederverwenden, und der Proxy antwortet 421. PatchNode versucht es automatisch einmal mit einer neuen Verbindung.",
        "Sign in as this user, then My account › Access tokens › Add access token. Copy it (shown once).":
            "Melde dich als dieser Benutzer an, dann My account › Access tokens › Add access token. Kopiere es (nur einmal angezeigt).",
        "Sign in as this user, then Profile › Security › Long-lived access tokens › Create token.":
            "Melde dich als dieser Benutzer an, dann Profil › Sicherheit › Langlebige Zugriffstoken › Token erstellen.",
        "Silenced and inhibited alerts are not shown. Check Alertmanager's web interface (Silences).":
            "Stummgeschaltete und unterdrückte Alarme werden nicht angezeigt. Prüfe die Weboberfläche von Alertmanager (Silences).",
        "Slow refreshes or timeouts":
            "Langsame Aktualisierungen oder Zeitüberschreitungen",
        "Split DNS so the same names work at home and through the VPN.":
            "Split DNS, damit dieselben Namen zu Hause und über das VPN funktionieren.",
        "Tailscale":
            "Tailscale",
        "Targets down and your own PromQL charts.":
            "Ausgefallene Ziele und deine eigenen PromQL-Diagramme.",
        "That's expected: the embedded browser uses your own Grafana session, separate from the token. The session is cleared when PatchNode goes to the background.":
            "Das ist normal: Der eingebettete Browser verwendet deine eigene Grafana-Sitzung, getrennt vom Token. Die Sitzung wird gelöscht, wenn PatchNode in den Hintergrund geht.",
        "The API also allows creating silences: keep Alertmanager on your LAN and VPN only, behind authentication. PatchNode only reads.":
            "Die API erlaubt auch das Anlegen von Silences: Halte Alertmanager nur im LAN und VPN, hinter einer Authentifizierung. PatchNode liest nur.",
        "The HTTP API is read-only by default. Don't start Prometheus with --web.enable-admin-api or --web.enable-lifecycle behind this proxy host.":
            "Die HTTP-API ist standardmäßig nur lesend. Starte Prometheus hinter diesem Proxy-Host nicht mit --web.enable-admin-api oder --web.enable-lifecycle.",
        "The Local API listens on 127.0.0.1:8080 by default, and cscli and the local bouncers use that address. Simplest: a reverse proxy on the same host forwards to 127.0.0.1:8080. Otherwise listen on all addresses and let only the proxy through the firewall:":
            "Die Local API lauscht standardmäßig auf 127.0.0.1:8080, und cscli sowie die lokalen Bouncer nutzen diese Adresse. Am einfachsten: Ein Reverse Proxy auf demselben Host leitet an 127.0.0.1:8080 weiter. Sonst auf allen Adressen lauschen und nur den Proxy durch die Firewall lassen:",
        "The URL must end with /status/<slug> — the slug chosen when creating the status page, not the dashboard URL.":
            "Die URL muss auf /status/<slug> enden: der beim Anlegen der Statusseite gewählte Slug, nicht die URL des Dashboards.",
        "The admin interface (port 81) can be published by Nginx Proxy Manager itself, restricted to your LAN and VPN:":
            "Die Admin-Oberfläche (Port 81) kann Nginx Proxy Manager selbst veröffentlichen, beschränkt auf dein LAN und VPN:",
        "The answer is an HTML 403 page: the reverse proxy refused the request before it reached the service. Your token isn't the cause.":
            "Die Antwort ist eine HTML-403-Seite: Der Reverse Proxy hat die Anfrage abgelehnt, bevor sie den Dienst erreichte. Dein Token ist nicht die Ursache.",
        "The answer is {\"message\":\"API running.\"}.":
            "Die Antwort lautet {\"message\":\"API running.\"}.",
        "The client may have been revoked in Settings › Trust credentials.":
            "Der Client wurde womöglich unter Settings › Trust credentials widerrufen.",
        "The entities you choose, scenes and scripts.":
            "Die gewählten Entitäten, Szenen und Skripte.",
        "The first command must print the proxy's LAN address; the second must answer without a certificate error.":
            "Der erste Befehl muss die LAN-Adresse des Proxys ausgeben; der zweite muss ohne Zertifikatsfehler antworten.",
        "The list is empty":
            "Die Liste ist leer",
        "The process list makes Glances's answer heavy. Start it with --disable-plugin processlist.":
            "Die Prozessliste macht die Antwort von Glances schwer. Starte es mit --disable-plugin processlist.",
        "The reverse proxy forwards in http to port 8006. Set Scheme to https on the proxy host.":
            "Der Reverse Proxy leitet per http an Port 8006 weiter. Setze Scheme beim Proxy-Host auf https.",
        "The same from the node's shell:":
            "Dasselbe in der Shell des Knotens:",
        "The service answers too slowly (timeout)":
            "Der Dienst antwortet zu langsam (Zeitüberschreitung)",
        "The socket proxy refuses POST requests: set POST=1 and recreate the container, only while you need actions.":
            "Der Socket-Proxy lehnt POST-Anfragen ab: Setze POST=1 und erstelle den Container neu, nur solange du Aktionen brauchst.",
        "The token is valid but not allowed to read this information. Grant the read-only role described in the Minimum rights section of the service's guide.":
            "Das Token ist gültig, darf diese Information aber nicht lesen. Vergib die Nur-Lese-Rolle aus dem Abschnitt Mindestrechte der Anleitung des Dienstes.",
        "The token may have expired (Expire field) or been deleted.":
            "Das Token ist womöglich abgelaufen (Feld Expire) oder gelöscht.",
        "Then, in the Tailscale admin console, DNS › Nameservers › Add nameserver › Custom: your DNS server, restricted to your domain (Split DNS).":
            "Dann in der Tailscale-Adminkonsole DNS › Nameservers › Add nameserver › Custom: dein DNS-Server, auf deine Domain beschränkt (Split DNS).",
        "This service goes through the internet, not your VPN: check the iPhone's internet access, or a DNS filter blocking tailscale.com.":
            "Dieser Dienst läuft über das Internet, nicht über dein VPN: Prüfe den Internetzugang des iPhones oder einen DNS-Filter, der tailscale.com blockiert.",
        "Toggle the VPN off and on: PatchNode then opens new connections.":
            "Schalte das VPN aus und wieder ein: PatchNode öffnet dann neue Verbindungen.",
        "Token or password rejected (401)":
            "Token oder Passwort abgelehnt (401)",
        "Token rejected (401)":
            "Token abgelehnt (401)",
        "Tokens stay in the iPhone's Keychain (this device only) and are sent only to the service they belong to.":
            "Tokens bleiben im Schlüsselbund des iPhones (nur dieses Gerät) und werden nur an ihren Dienst gesendet.",
        "Try again on Wi-Fi at home to rule out the VPN.":
            "Versuche es zu Hause im WLAN erneut, um das VPN auszuschließen.",
        "Two nodes named the same (pve)":
            "Zwei gleichnamige Knoten (pve)",
        "Type the token without it being displayed, then call the API:":
            "Gib das Token ein, ohne dass es angezeigt wird, dann rufe die API auf:",
        "Uptime Kuma":
            "Uptime Kuma",
        "Use a service account token (glsa_…), not an API key from an older Grafana nor your password.":
            "Verwende ein Dienstkonto-Token (glsa_…), keinen API-Schlüssel eines älteren Grafana und nicht dein Passwort.",
        "Use the dedicated user's e-mail and password. Two-factor authentication isn't supported: use a user without it.":
            "Verwende E-Mail und Passwort des eigenen Benutzers. Zwei-Faktor-Authentifizierung wird nicht unterstützt: Nutze einen Benutzer ohne.",
        "User or password rejected":
            "Benutzer oder Passwort abgelehnt",
        "User or password rejected (401)":
            "Benutzer oder Passwort abgelehnt (401)",
        "Users › Add User: full name PatchNode, e-mail e.g. patchnode@example.com, not an administrator.":
            "Users › Add User: vollständiger Name PatchNode, E-Mail z. B. patchnode@example.com, kein Administrator.",
        "VPN connected? At home, is the iPhone on your Wi-Fi?":
            "VPN verbunden? Ist das iPhone zu Hause in deinem WLAN?",
        "VPN off: turn it on, then pull to refresh.":
            "VPN aus: Schalte es ein, dann zieh zum Aktualisieren.",
        "VPN, HTTPS reverse proxy, split DNS, LAN-only access and IPS allow-list.":
            "VPN, HTTPS-Reverse-Proxy, Split DNS, Zugriff nur aus dem LAN und IPS-Freigabeliste.",
        "View Only on Proxy Hosts is enough. PatchNode has no action on Nginx Proxy Manager.":
            "View Only für Proxy Hosts genügt. PatchNode hat keine Aktion für Nginx Proxy Manager.",
        "With Scheme http, Proxmox answers 301 Moved Permanently and PatchNode can't read anything.":
            "Mit Scheme http antwortet Proxmox mit 301 Moved Permanently, und PatchNode kann nichts lesen.",
        "Without authentication, drop -u monitor.":
            "Ohne Authentifizierung lass -u monitor weg.",
        "You should get a token in return.":
            "Du solltest ein Token zurückbekommen.",
        "You should see your datastores.":
            "Du solltest deine Datastores sehen.",
        "You should see your environments.":
            "Du solltest deine Umgebungen sehen.",
        "You should see your nodes, VMs and storage. A list with only nodes and no CPU or memory means the token lacks rights.":
            "Du solltest deine Knoten, VMs und Storage sehen. Eine Liste nur mit Knoten ohne CPU oder Speicher bedeutet, dass dem Token Rechte fehlen.",
        "Your LAN and VPN ranges allow-listed in your IPS (CrowdSec, fail2ban).":
            "Die Bereiche deines LANs und VPNs auf der Freigabeliste deines IPS (CrowdSec, fail2ban).",
        "api.tailscale.com unreachable":
            "api.tailscale.com nicht erreichbar",
        "curl asks for the password, then prints the Docker version. Without the password you must get a 401.":
            "curl fragt nach dem Passwort und gibt dann die Docker-Version aus. Ohne Passwort musst du ein 401 erhalten.",
        "null means no active ban: that's a valid answer.":
            "null bedeutet keine aktive Sperre: Das ist eine gültige Antwort.",
        "“Actions disabled” (403 from the socket proxy)":
            "„Aktionen deaktiviert“ (403 vom Socket-Proxy)",
        "“Enter the status page URL”":
            "„Gib die URL der Statusseite ein“",
        "Consoles: the Console button of a node, a container or a VM opens a terminal inside PatchNode (the node's shell, the container, or the VM's serial port), or the graphical console of a VM without a serial port. Face ID is asked every time. Consoles with an API token need Proxmox VE 9.1 or later.":
            "Konsolen: Die Schaltfläche Konsole eines Knotens, Containers oder einer VM öffnet ein Terminal in PatchNode (Shell des Knotens, Container oder serielle Schnittstelle der VM) oder die grafische Konsole einer VM ohne serielle Schnittstelle. Face ID wird jedes Mal abgefragt. Konsolen mit einem API-Token erfordern Proxmox VE 9.1 oder neuer.",
        "Consoles: a PatchNodeConsole role with VM.Console only, on the guest (/vms/101), and for a node's shell a PatchNodeNodeConsole role with Sys.Console only, on the node (/nodes/node-a) — never Sys.Console on a guest. On / (everything), the role alone is enough. A node's shell opened by another user than root@pam asks for a Linux login.":
            "Konsolen: eine Rolle PatchNodeConsole nur mit VM.Console, auf dem Gast (/vms/101), und für die Shell eines Knotens eine Rolle PatchNodeNodeConsole nur mit Sys.Console, auf dem Knoten (/nodes/node-a) – nie Sys.Console auf einem Gast. Auf / (alles) genügt die Rolle allein. Die Shell eines Knotens, die ein anderer Benutzer als root@pam öffnet, verlangt eine Linux-Anmeldung.",
        "A console gives a shell on the guest or the node: grant it only where you need it.":
            "Eine Konsole gibt eine Shell auf dem Gast oder Knoten: Erteile sie nur dort, wo du sie brauchst.",
        "Consoles go through a websocket: in Nginx Proxy Manager, Websockets Support must be on for the Proxmox host.":
            "Konsolen laufen über einen Websocket: In Nginx Proxy Manager muss Websockets Support für den Proxmox-Host aktiviert sein.",
        "Console: the token lacks the console privilege":
            "Konsole: Dem Token fehlt das Konsolenrecht",
        "Grant PatchNodeConsole on the guest (/vms/<id>) or PatchNodeNodeConsole on the node (/nodes/<node>), always with PVEAuditor, to the user and to the token (Minimum rights). PatchNode shows the exact commands to copy.":
            "Erteile PatchNodeConsole auf dem Gast (/vms/<id>) oder PatchNodeNodeConsole auf dem Knoten (/nodes/<knoten>), immer zusammen mit PVEAuditor, dem Benutzer und dem Token (Minimale Rechte). PatchNode zeigt die genauen Befehle zum Kopieren.",
        "Console: Proxmox refused the token":
            "Konsole: Proxmox hat das Token abgelehnt",
        "Before Proxmox VE 9.1, consoles only accept a password session, not an API token. Update the nodes to 9.1 or later (apt full-upgrade).":
            "Vor Proxmox VE 9.1 akzeptieren Konsolen nur eine Sitzung mit Passwort, kein API-Token. Aktualisiere die Knoten auf 9.1 oder neuer (apt full-upgrade).",
        "Graphical console only: add a serial port":
            "Nur grafische Konsole: eine serielle Schnittstelle hinzufügen",
        "A VM gets a text terminal in PatchNode when it has a serial port. Add one, enable a login on it inside the VM, then restart the VM:":
            "Eine VM erhält in PatchNode ein Textterminal, wenn sie eine serielle Schnittstelle hat. Füge eine hinzu, aktiviere darauf in der VM eine Anmeldung und starte die VM neu:",
        "Without a serial port, PatchNode opens the VM's graphical console.":
            "Ohne serielle Schnittstelle öffnet PatchNode die grafische Konsole der VM.",
        "SSH terminal":
            "SSH-Terminal",
        "A dedicated user, this device's key, sudo or the docker group, risks and revocation.":
            "Ein eigener Benutzer, der Schlüssel dieses Geräts, sudo oder die Gruppe docker, Risiken und Widerruf.",
        "PatchNode opens SSH sessions to your own servers (Proxmox nodes, Docker hosts, containers, VMs) and, for a Docker host, runs docker compose in a project's folder. It connects only to the hosts you add, with a key generated on this device; nothing goes through a server of ours.":
            "PatchNode öffnet SSH-Sitzungen zu deinen eigenen Servern (Proxmox-Knoten, Docker-Hosts, Container, VMs) und führt für einen Docker-Host docker compose im Ordner eines Projekts aus. Es verbindet sich nur mit den Hosts, die du hinzufügst, mit einem auf diesem Gerät erzeugten Schlüssel; nichts läuft über einen Server von uns.",
        "Every session asks for Face ID. The first connection to a host shows its fingerprint: compare it with the server's own before trusting it. PatchNode then refuses any other key for that host.":
            "Jede Sitzung verlangt Face ID. Die erste Verbindung zu einem Host zeigt seinen Fingerabdruck: Vergleiche ihn mit dem des Servers, bevor du ihm vertraust. Danach lehnt PatchNode jeden anderen Schlüssel für diesen Host ab.",
        "On the server, create a dedicated user, for example patchnode.":
            "Lege auf dem Server einen eigenen Benutzer an, zum Beispiel patchnode.",
        "In PatchNode, Settings › SSH: turn on the SSH terminal, open This device's public key and copy the authorized_keys line.":
            "In PatchNode unter Einstellungen › SSH: Aktiviere das SSH-Terminal, öffne den öffentlichen Schlüssel dieses Geräts und kopiere die authorized_keys-Zeile.",
        "On the server, add the line to ~/.ssh/authorized_keys of that user (folder 700, file 600).":
            "Füge die Zeile auf dem Server in ~/.ssh/authorized_keys dieses Benutzers ein (Ordner 700, Datei 600).",
        "Settings › SSH › Add a host: address, port, user. Link it to its Proxmox node or Docker host for the shortcuts.":
            "Einstellungen › SSH › Host hinzufügen: Adresse, Port, Benutzer. Verknüpfe ihn mit seinem Proxmox-Knoten oder Docker-Host für die Kurzbefehle.",
        "Docker: add the user to the docker group so docker compose runs without sudo. The docker group is equivalent to root on that host: keep the key's from= restriction.":
            "Docker: Füge den Benutzer der Gruppe docker hinzu, damit docker compose ohne sudo läuft. Die Gruppe docker entspricht root auf diesem Host: Behalte die from=-Einschränkung des Schlüssels.",
        "Proxmox: “Enter the container” runs pct enter, which needs root. Connect as root with the key only (PermitRootLogin prohibit-password), or allow just that command with sudo (edit with visudo):":
            "Proxmox: „Container betreten“ führt pct enter aus, das root benötigt. Verbinde dich als root nur mit dem Schlüssel (PermitRootLogin prohibit-password) oder erlaube nur diesen Befehl mit sudo (mit visudo bearbeiten):",
        "Prefer the key to a password. A password is asked only when the server refuses the key, used for that connection, and never stored.":
            "Bevorzuge den Schlüssel gegenüber einem Passwort. Ein Passwort wird nur abgefragt, wenn der Server den Schlüssel ablehnt, gilt nur für diese Verbindung und wird nie gespeichert.",
        "A session gives a full shell: whatever the user can do, PatchNode can do once unlocked.":
            "Eine Sitzung gibt eine vollständige Shell: Alles, was der Benutzer darf, kann PatchNode, sobald es entsperrt ist.",
        "Keep SSH reachable only through your VPN, never exposed on the internet.":
            "Halte SSH nur über dein VPN erreichbar, nie offen im Internet.",
        "from= limits where the key is accepted from; the no-…-forwarding options limit what it can do.":
            "from= begrenzt, woher der Schlüssel akzeptiert wird; die Optionen no-…-forwarding begrenzen, was er darf.",
        "Terminal content is never stored or logged; Diagnostics keep only the opening, closing, duration and error code.":
            "Der Inhalt des Terminals wird nie gespeichert oder protokolliert; die Diagnose behält nur Öffnen, Schließen, Dauer und Fehlercode.",
        "Lost device, or a key you no longer trust: delete its line from authorized_keys on every server. The comment at the end of the line (patchnode-iPhone-…) tells which device it is.":
            "Gerät verloren oder Schlüssel nicht mehr vertrauenswürdig: Lösche seine Zeile aus authorized_keys auf jedem Server. Der Kommentar am Zeilenende (patchnode-iPhone-…) zeigt, welches Gerät es ist.",
        "Settings › SSH › Replace the key creates a new key and deletes the old one from this device.":
            "Einstellungen › SSH › Schlüssel ersetzen erzeugt einen neuen Schlüssel und löscht den alten von diesem Gerät.",
        "Host key changed? If you reinstalled the server, check its new fingerprint, then Settings › SSH › the host › Forget the host key.":
            "Host-Schlüssel geändert? Wenn du den Server neu installiert hast, prüfe seinen neuen Fingerabdruck und dann Einstellungen › SSH › der Host › Host-Schlüssel vergessen.",
        "Connection refused or unreachable":
            "Verbindung abgelehnt oder nicht erreichbar",
        "Check the VPN, the address and the port (22 by default), and that the SSH server runs on the host.":
            "Prüfe das VPN, die Adresse und den Port (standardmäßig 22) und ob der SSH-Server auf dem Host läuft.",
        "Key refused":
            "Schlüssel abgelehnt",
        "The line is missing from that user's authorized_keys, or the file's permissions are too open (sshd then ignores it). The server's log says why:":
            "Die Zeile fehlt in authorized_keys dieses Benutzers, oder die Dateirechte sind zu offen (sshd ignoriert sie dann). Das Protokoll des Servers sagt warum:",
        "This rule is root in every container of the node, and nearly root on the node itself for a privileged container: keep it for a dedicated user, with the key's from= restriction.":
            "Diese Regel entspricht root in jedem Container des Knotens und für einen privilegierten Container fast root auf dem Knoten selbst: Nutze sie nur für einen eigenen Benutzer, mit der from=-Einschränkung des Schlüssels.",
        "A role on a deeper path replaces, for the same user or token, the roles inherited from above: PatchNodeConsole alone on /vms/101 takes PVEAuditor away there, and the guest vanishes from PatchNode. On any path other than /, always grant PVEAuditor with the role, and PatchNodePower too if the guest keeps its actions ('PVEAuditor,PatchNodePower,PatchNodeConsole'), to the user and to the token. Use a user dedicated to PatchNode: on your own account, such an ACL would also replace your other roles on that path.":
            "Eine Rolle auf einem genaueren Pfad ersetzt für denselben Benutzer oder dasselbe Token die von oben geerbten Rollen: PatchNodeConsole allein auf /vms/101 nimmt dort PVEAuditor weg, und der Gast verschwindet aus PatchNode. Auf jedem Pfad außer / immer PVEAuditor zusammen mit der Rolle vergeben, und auch PatchNodePower, wenn der Gast seine Aktionen behalten soll ('PVEAuditor,PatchNodePower,PatchNodeConsole'), dem Benutzer und dem Token. Verwende einen eigenen Benutzer für PatchNode: Bei deinem eigenen Konto würde eine solche ACL auch deine anderen Rollen auf diesem Pfad ersetzen.",
        "Check the token's effective rights on a path (user, token ID, path):":
            "Die tatsächlichen Rechte des Tokens auf einem Pfad prüfen (Benutzer, Token-ID, Pfad):",
        "A guest vanished after a role was granted on its path (/vms/<id>, /vms): that ACL replaced PVEAuditor inherited from /. Grant 'PVEAuditor,<role>' on that path instead, then check:":
            "Ein Gast ist verschwunden, nachdem eine Rolle auf seinem Pfad vergeben wurde (/vms/<id>, /vms): Diese ACL hat das von / geerbte PVEAuditor ersetzt. Vergib dort stattdessen 'PVEAuditor,<rolle>' und prüfe dann:",
    ]
}
