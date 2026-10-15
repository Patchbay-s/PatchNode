# PatchNode — App Store metadata

Name: **PatchNode**
Primary category: **Developer Tools** · Secondary: **Utilities**
Age rating: 4+ (no objectionable content, no web browsing other than the user's own Grafana).
Price: to decide. No in-app purchase, no subscription, no account.

Lengths checked: subtitle ≤ 30 characters, keywords ≤ 100 characters (commas, no spaces),
promotional text ≤ 170 characters, What's New ≤ 4000 characters.

Localizations: English (primary), French, Spanish, German, Italian. Add the three new
languages in App Store Connect › App Information and on the version page; the Spanish,
German and Italian texts are machine-quality drafts to have proofread by a native speaker.

---

## English (U.S.) — primary language

**Subtitle** (26): `HomeLab monitor for iPhone`

**Keywords** (94): `homelab,proxmox,docker,portainer,prometheus,grafana,tailscale,selfhosted,server,zfs,monitoring`

**Promotional text** (141):
Your whole HomeLab on one screen: Proxmox, Docker, alerts, backups, network and home automation. Private by design, straight to your servers.

**Description**:

PatchNode keeps an eye on your HomeLab from your iPhone. It talks directly to your own servers, over your private network or VPN, and shows what needs your attention first.

ONE DASHBOARD FOR EVERYTHING
• Proxmox VE: nodes, VMs and containers, storage, tasks, charts per hour, day or week, disk health (SMART, ZFS pools)
• TLS certificates: the expiry date of every service, with a warning 14 and 7 days before
• Proxmox Backup Server: datastores, latest backup of every guest, failed jobs
• Docker, through Portainer or a read-only socket proxy: containers by host and stack, health, logs, CPU and memory
• Prometheus, Alertmanager, Grafana and Uptime Kuma: active alerts, targets down, status pages, your own PromQL charts
• Tailscale: devices online, offline for days, keys about to expire
• CrowdSec, Nginx Proxy Manager and AdGuard Home: bans, proxy hosts, DNS statistics
• Home Assistant and Glances: the sensors you choose, scenes and scripts, host load and disks

ACT WITH CARE
Start, shut down or reboot a VM or a container, or run a Home Assistant scene. Every action names its target and asks for confirmation, with Face ID.

WIDGETS AND SIRI
Home Screen and Lock Screen widgets show the state of your HomeLab at a glance. Ask Siri for your HomeLab status.

NOTIFICATIONS, EXPORT AND ICLOUD
• Optional local notifications after a background refresh: service unreachable, failed backup, unhealthy container, new alert, certificate about to expire, disk problem. A count only on the Lock Screen.
• Export your configuration, without any token, as a file or a QR code, and import it on another iPhone.
• Optional iCloud sync of your configuration, in your own iCloud, off by default.

CONSOLES, SSH AND COMPOSE
• Proxmox consoles through the API: a terminal for nodes, containers and VMs with a serial port, the graphical console (noVNC, built in) for the others.
• SSH terminal to your own servers, with a key created on the device; the host's fingerprint is checked at the first connection, then pinned.
• Docker Compose: edit a project's files with a preview of the changes, validation and automatic backups; start, stop, restart or update it with live output; open a terminal in its folder.
• Tabs for several sessions on iPad and Mac, Face ID for every session.

PRIVATE BY DESIGN
• No account, no analytics, no advertising, no tracking. PatchNode collects no data.
• Tokens stay in this iPhone's Keychain. iCloud sync of your configuration, and of your tokens through iCloud Keychain, is optional and off by default.
• HTTPS only, no exception. Actions are never retried behind your back.
• The app only connects to the servers you add (and to api.tailscale.com if you add Tailscale).

TRY IT WITHOUT A SERVER
The built-in demo shows a complete sample HomeLab, generated on the device.

PatchNode works with your own self-hosted services; you need network access to them (for example through Tailscale or WireGuard). PatchNode is an independent app, not affiliated with or endorsed by Proxmox Server Solutions, Docker, Portainer, Grafana Labs, Tailscale, CrowdSec, Home Assistant or any other product it supports.

**What's New** (1.2):

PatchNode 1.2: iPad, Mac, consoles, SSH and Compose.

• iPad and Mac: PatchNode runs natively on iPad (sidebar, adaptive layouts, keyboard shortcuts) and on Apple silicon Macs, with a cleaner Dark Mode.
• Proxmox consoles: open the console of a node, a container or a VM from the app, as a terminal or the graphical console. Needs Proxmox VE 9.1 or later and the console privilege (PatchNode shows the commands to grant it).
• SSH terminal (off by default): connect to your own servers with a key created on the device. Fingerprints are checked and pinned; passwords are never stored.
• Docker Compose: edit compose and .env files with a preview of the changes, validation and automatic backups; start, stop, restart or update a project with live output; open a terminal in its folder. Portainer stacks through its API.
• Face ID for every session, nothing kept of what you type, and the demo to try everything without a server.

**What's New** (1.1, previous version) (1148):

PatchNode 1.1 is here.

• iCloud sync (optional, off by default): your services, PromQL charts, Home Assistant entities, tabs and dashboard order on all your devices, in your own iCloud. Tokens can follow through iCloud Keychain with a separate option.
• Export and import: your configuration as a file or a QR code, without any token, to set up another iPhone or keep a copy.
• Local notifications (optional): service unreachable, failed backup, unhealthy container, new alert, certificate about to expire, disk problem. Posted by the iPhone itself, with a count only on the Lock Screen. iOS decides when background refreshes run, so they can be late.
• TLS certificates: the expiry date of each service, read during the connection, with a warning 14 and 7 days before.
• Proxmox disk health: SMART status, SSD wear and ZFS pools of every node.
• New languages: Spanish, German and Italian.

Also in this version (from 1.0.1):
• Siri and Shortcuts actions are off by default; turn them on in Settings, with Face ID.
• Full-access Tailscale API keys are refused: use an OAuth client with read-only access.
• Better VoiceOver labels and plural forms.

---

## Français (France)

**Sous-titre** (24) : `Supervisez votre HomeLab`

**Mots-clés** (97) : `homelab,proxmox,docker,portainer,prometheus,grafana,tailscale,autohébergé,serveur,supervision,zfs`

**Texte promotionnel** (151) :
Tout votre HomeLab sur un écran : Proxmox, Docker, alertes, sauvegardes, réseau et domotique. Confidentiel par conception, en direct vers vos serveurs.

**Description** :

PatchNode surveille votre HomeLab depuis votre iPhone. L'app dialogue directement avec vos propres serveurs, via votre réseau privé ou votre VPN, et montre d'abord ce qui demande votre attention.

UN SEUL TABLEAU DE BORD
• Proxmox VE : nœuds, VM et conteneurs, stockages, tâches, graphiques sur une heure, un jour ou une semaine, santé des disques (SMART, pools ZFS)
• Certificats TLS : la date d'expiration de chaque service, avec une alerte 14 et 7 jours avant
• Proxmox Backup Server : datastores, dernière sauvegarde de chaque VM, tâches en échec
• Docker, via Portainer ou un socket proxy en lecture seule : conteneurs par hôte et par stack, santé, journaux, CPU et mémoire
• Prometheus, Alertmanager, Grafana et Uptime Kuma : alertes en cours, cibles en panne, pages de statut, vos graphiques PromQL
• Tailscale : appareils en ligne, hors ligne depuis des jours, clés bientôt expirées
• CrowdSec, Nginx Proxy Manager et AdGuard Home : bannissements, proxy hosts, statistiques DNS
• Home Assistant et Glances : les capteurs de votre choix, scènes et scripts, charge et disques des hôtes

AGIR AVEC PRUDENCE
Démarrez, éteignez ou redémarrez une VM ou un conteneur, lancez une scène Home Assistant. Chaque action nomme sa cible et demande une confirmation, avec Face ID.

WIDGETS ET SIRI
Les widgets de l'écran d'accueil et de l'écran verrouillé montrent l'état de votre HomeLab d'un coup d'œil. Demandez à Siri l'état de votre HomeLab.

NOTIFICATIONS, EXPORT ET ICLOUD
• Notifications locales facultatives après un rafraîchissement en arrière-plan : service injoignable, sauvegarde en échec, conteneur en mauvaise santé, nouvelle alerte, certificat bientôt expiré, problème de disque. Seulement un nombre sur l'écran verrouillé.
• Exportez votre configuration, sans aucun jeton, en fichier ou en QR code, et importez-la sur un autre iPhone.
• Synchronisation iCloud facultative de la configuration, dans votre propre iCloud, désactivée par défaut.

CONSOLES, SSH ET COMPOSE
• Consoles Proxmox par l’API : un terminal pour les nœuds, les conteneurs et les VM avec port série, la console graphique (noVNC, intégrée) pour les autres.
• Terminal SSH vers vos propres serveurs, avec une clé créée sur l’appareil ; l’empreinte de l’hôte est vérifiée à la première connexion, puis épinglée.
• Docker Compose : modifiez les fichiers d’un projet avec aperçu des différences, validation et sauvegardes automatiques ; démarrez, arrêtez, redémarrez ou mettez-le à jour avec la sortie en direct ; ouvrez un terminal dans son dossier.
• Onglets pour plusieurs sessions sur iPad et Mac, Face ID à chaque session.

CONFIDENTIEL PAR CONCEPTION
• Pas de compte, pas de statistiques d'usage, pas de publicité, pas de pistage. PatchNode ne collecte aucune donnée.
• Les jetons restent dans le trousseau de cet iPhone. La synchronisation iCloud de la configuration, et des jetons via le trousseau iCloud, est facultative et désactivée par défaut.
• HTTPS uniquement, sans exception. Les actions ne sont jamais renvoyées dans votre dos.
• L'app ne se connecte qu'aux serveurs que vous ajoutez (et à api.tailscale.com si vous ajoutez Tailscale).

ESSAYEZ SANS SERVEUR
La démo intégrée montre un HomeLab fictif complet, généré sur l'appareil.

PatchNode fonctionne avec vos propres services autohébergés ; vous devez pouvoir y accéder (par exemple via Tailscale ou WireGuard). PatchNode est une app indépendante, sans lien avec Proxmox Server Solutions, Docker, Portainer, Grafana Labs, Tailscale, CrowdSec, Home Assistant ni aucun autre produit pris en charge, et non approuvée par eux.

**Nouveautés** (1.2) :

PatchNode 1.2 : iPad, Mac, consoles, SSH et Compose.

• iPad et Mac : PatchNode fonctionne nativement sur iPad (barre latérale, mises en page adaptées, raccourcis clavier) et sur les Mac Apple silicon, avec un mode sombre plus soigné.
• Consoles Proxmox : ouvrez la console d’un nœud, d’un conteneur ou d’une VM depuis l’app, en terminal ou en console graphique. Demande Proxmox VE 9.1 ou plus récent et le droit console (PatchNode affiche les commandes pour l’accorder).
• Terminal SSH (désactivé par défaut) : connectez-vous à vos propres serveurs avec une clé créée sur l’appareil. Les empreintes sont vérifiées et épinglées ; les mots de passe ne sont jamais conservés.
• Docker Compose : modifiez les fichiers compose et .env avec aperçu des différences, validation et sauvegardes automatiques ; démarrez, arrêtez, redémarrez ou mettez à jour un projet avec la sortie en direct ; ouvrez un terminal dans son dossier. Stacks Portainer par son API.
• Face ID à chaque session, rien de conservé de ce que vous tapez, et la démo pour tout essayer sans serveur.

**Nouveautés** (1.1, previous version) (1366) :

PatchNode 1.1 est là.

• Synchronisation iCloud (facultative, désactivée par défaut) : vos services, graphiques PromQL, entités Home Assistant, onglets et ordre du tableau de bord sur tous vos appareils, dans votre propre iCloud. Les jetons peuvent suivre via le trousseau iCloud avec une option séparée.
• Export et import : votre configuration en fichier ou en QR code, sans aucun jeton, pour configurer un autre iPhone ou en garder une copie.
• Notifications locales (facultatives) : service injoignable, sauvegarde en échec, conteneur en mauvaise santé, nouvelle alerte, certificat bientôt expiré, problème de disque. Envoyées par l'iPhone lui-même, avec seulement un nombre sur l'écran verrouillé. iOS décide quand ont lieu les rafraîchissements en arrière-plan : elles peuvent arriver en retard.
• Certificats TLS : la date d'expiration de chaque service, lue pendant la connexion, avec une alerte 14 et 7 jours avant.
• Santé des disques Proxmox : état SMART, usure des SSD et pools ZFS de chaque nœud.
• Nouvelles langues : espagnol, allemand et italien.

Aussi dans cette version (issu de la 1.0.1) :
• Les actions Siri et Raccourcis sont désactivées par défaut ; activez-les dans Réglages, avec Face ID.
• Les clés API Tailscale à accès complet sont refusées : utilisez un client OAuth en lecture seule.
• Meilleurs libellés VoiceOver et accords au pluriel.

---

## Español (España) — to be proofread by a native speaker

**Subtítulo** (18): `Monitor de HomeLab`

**Palabras clave** (97): `homelab,proxmox,docker,portainer,prometheus,grafana,tailscale,autoalojado,servidor,monitorización`

**Texto promocional** (128):
Todo tu HomeLab en una pantalla: Proxmox, Docker, alertas, copias, red y domótica. Privado por diseño, directo a tus servidores.

**Descripción**:

PatchNode vigila tu HomeLab desde tu iPhone. Habla directamente con tus propios servidores, a través de tu red privada o tu VPN, y muestra primero lo que necesita tu atención.

UN SOLO PANEL PARA TODO
• Proxmox VE: nodos, VM y contenedores, almacenamiento, tareas, gráficos por hora, día o semana, salud de los discos (SMART, pools ZFS)
• Certificados TLS: la fecha de caducidad de cada servicio, con un aviso 14 y 7 días antes
• Proxmox Backup Server: datastores, última copia de cada invitado, tareas fallidas
• Docker, mediante Portainer o un socket proxy de solo lectura: contenedores por host y stack, salud, registros, CPU y memoria
• Prometheus, Alertmanager, Grafana y Uptime Kuma: alertas activas, objetivos caídos, páginas de estado, tus propios gráficos PromQL
• Tailscale: dispositivos en línea, desconectados desde hace días, claves a punto de caducar
• CrowdSec, Nginx Proxy Manager y AdGuard Home: bloqueos, proxy hosts, estadísticas DNS
• Home Assistant y Glances: los sensores que elijas, escenas y scripts, carga y discos de los hosts

ACTÚA CON CUIDADO
Inicia, apaga o reinicia una VM o un contenedor, o ejecuta una escena de Home Assistant. Cada acción nombra su objetivo y pide confirmación, con Face ID.

WIDGETS Y SIRI
Los widgets de la pantalla de inicio y de la pantalla bloqueada muestran el estado de tu HomeLab de un vistazo. Pregunta a Siri por el estado de tu HomeLab.

NOTIFICACIONES, EXPORTACIÓN E ICLOUD
• Notificaciones locales opcionales tras una actualización en segundo plano: servicio inaccesible, copia fallida, contenedor no sano, nueva alerta, certificado a punto de caducar, problema de disco. Solo un número en la pantalla bloqueada.
• Exporta tu configuración, sin ningún token, como archivo o código QR, e impórtala en otro iPhone.
• Sincronización opcional de la configuración con iCloud, en tu propio iCloud, desactivada por defecto.

CONSOLAS, SSH Y COMPOSE
• Consolas de Proxmox mediante la API: un terminal para nodos, contenedores y VM con puerto serie, y la consola gráfica (noVNC, integrada) para las demás.
• Terminal SSH hacia tus propios servidores, con una clave creada en el dispositivo; la huella del host se comprueba en la primera conexión y luego se fija.
• Docker Compose: edita los archivos de un proyecto con vista previa de los cambios, validación y copias de seguridad automáticas; inícialo, detenlo, reinícialo o actualízalo con la salida en directo; abre un terminal en su carpeta.
• Pestañas para varias sesiones en iPad y Mac, Face ID en cada sesión.

PRIVADO POR DISEÑO
• Sin cuenta, sin estadísticas de uso, sin publicidad, sin rastreo. PatchNode no recopila ningún dato.
• Los tokens se quedan en el llavero de este iPhone. La sincronización con iCloud de la configuración, y de los tokens a través del Llavero de iCloud, es opcional y está desactivada por defecto.
• Solo HTTPS, sin excepción. Las acciones nunca se repiten a tus espaldas.
• La app solo se conecta a los servidores que añades (y a api.tailscale.com si añades Tailscale).

PRUÉBALO SIN SERVIDOR
La demo integrada muestra un HomeLab de ejemplo completo, generado en el dispositivo.

PatchNode funciona con tus propios servicios autoalojados; necesitas acceso de red a ellos (por ejemplo mediante Tailscale o WireGuard). PatchNode es una app independiente, sin afiliación ni respaldo de Proxmox Server Solutions, Docker, Portainer, Grafana Labs, Tailscale, CrowdSec, Home Assistant ni ningún otro producto compatible.

**Novedades** (1.2):

PatchNode 1.2: iPad, Mac, consolas, SSH y Compose.

• iPad y Mac: PatchNode funciona de forma nativa en iPad (barra lateral, diseños adaptados, atajos de teclado) y en los Mac con Apple silicon, con un modo oscuro más cuidado.
• Consolas de Proxmox: abre la consola de un nodo, un contenedor o una VM desde la app, como terminal o consola gráfica. Requiere Proxmox VE 9.1 o posterior y el privilegio de consola (PatchNode muestra los comandos para concederlo).
• Terminal SSH (desactivado por defecto): conéctate a tus propios servidores con una clave creada en el dispositivo. Las huellas se comprueban y se fijan; las contraseñas nunca se guardan.
• Docker Compose: edita los archivos compose y .env con vista previa de los cambios, validación y copias de seguridad automáticas; inicia, detén, reinicia o actualiza un proyecto con la salida en directo; abre un terminal en su carpeta. Stacks de Portainer mediante su API.
• Face ID en cada sesión, nada guardado de lo que escribes, y la demostración para probarlo todo sin servidor.

**Novedades** (1.1, previous version) (1316):

Ya está aquí PatchNode 1.1.

• Sincronización con iCloud (opcional, desactivada por defecto): tus servicios, gráficos PromQL, entidades de Home Assistant, pestañas y orden del panel en todos tus dispositivos, en tu propio iCloud. Los tokens pueden seguirles a través del Llavero de iCloud con una opción aparte.
• Exportar e importar: tu configuración como archivo o código QR, sin ningún token, para configurar otro iPhone o guardar una copia.
• Notificaciones locales (opcionales): servicio inaccesible, copia fallida, contenedor no sano, nueva alerta, certificado a punto de caducar, problema de disco. Las envía el propio iPhone, con solo un número en la pantalla bloqueada. iOS decide cuándo se actualiza en segundo plano, así que pueden llegar con retraso.
• Certificados TLS: la fecha de caducidad de cada servicio, leída durante la conexión, con un aviso 14 y 7 días antes.
• Salud de los discos de Proxmox: estado SMART, desgaste de los SSD y pools ZFS de cada nodo.
• Nuevos idiomas: español, alemán e italiano.

También en esta versión (de la 1.0.1):
• Las acciones de Siri y Atajos están desactivadas por defecto; actívalas en Ajustes, con Face ID.
• Se rechazan las claves de API de Tailscale con acceso completo: usa un cliente OAuth de solo lectura.
• Mejores etiquetas de VoiceOver y formas de plural.

---

## Deutsch — to be proofread by a native speaker

**Untertitel** (27): `HomeLab-Monitor fürs iPhone`

**Schlüsselwörter** (95): `homelab,proxmox,docker,portainer,prometheus,grafana,tailscale,selfhosted,server,zfs,überwachung`

**Werbetext** (148):
Dein ganzes HomeLab auf einem Bildschirm: Proxmox, Docker, Alarme, Backups, Netzwerk und Smart Home. Privat von Grund auf, direkt zu deinen Servern.

**Beschreibung**:

PatchNode behält dein HomeLab vom iPhone aus im Blick. Die App spricht direkt mit deinen eigenen Servern, über dein privates Netzwerk oder dein VPN, und zeigt zuerst, was deine Aufmerksamkeit braucht.

EINE ÜBERSICHT FÜR ALLES
• Proxmox VE: Nodes, VMs und Container, Speicher, Aufgaben, Diagramme pro Stunde, Tag oder Woche, Festplattenzustand (SMART, ZFS-Pools)
• TLS-Zertifikate: das Ablaufdatum jedes Dienstes, mit einer Warnung 14 und 7 Tage vorher
• Proxmox Backup Server: Datastores, letztes Backup jedes Gasts, fehlgeschlagene Jobs
• Docker, über Portainer oder einen schreibgeschützten Socket-Proxy: Container nach Host und Stack, Zustand, Logs, CPU und Arbeitsspeicher
• Prometheus, Alertmanager, Grafana und Uptime Kuma: aktive Alarme, ausgefallene Targets, Statusseiten, deine eigenen PromQL-Diagramme
• Tailscale: Geräte online, seit Tagen offline, bald ablaufende Schlüssel
• CrowdSec, Nginx Proxy Manager und AdGuard Home: Sperren, Proxy Hosts, DNS-Statistiken
• Home Assistant und Glances: die Sensoren deiner Wahl, Szenen und Skripte, Last und Festplatten der Hosts

MIT BEDACHT HANDELN
Starte eine VM oder einen Container, fahre sie herunter oder starte sie neu, oder führe eine Home-Assistant-Szene aus. Jede Aktion nennt ihr Ziel und fragt nach Bestätigung, mit Face ID.

WIDGETS UND SIRI
Widgets auf dem Home- und dem Sperrbildschirm zeigen den Zustand deines HomeLab auf einen Blick. Frag Siri nach dem Status deines HomeLab.

MITTEILUNGEN, EXPORT UND ICLOUD
• Optionale lokale Mitteilungen nach einer Aktualisierung im Hintergrund: Dienst nicht erreichbar, Backup fehlgeschlagen, Container nicht gesund, neuer Alarm, Zertifikat läuft bald ab, Festplattenproblem. Auf dem Sperrbildschirm nur eine Anzahl.
• Exportiere deine Konfiguration ohne Tokens als Datei oder QR-Code und importiere sie auf einem anderen iPhone.
• Optionale iCloud-Synchronisierung der Konfiguration, in deiner eigenen iCloud, standardmäßig aus.

KONSOLEN, SSH UND COMPOSE
• Proxmox-Konsolen über die API: ein Terminal für Knoten, Container und VMs mit serieller Schnittstelle, die grafische Konsole (noVNC, eingebaut) für die übrigen.
• SSH-Terminal zu deinen eigenen Servern, mit einem auf dem Gerät erzeugten Schlüssel; der Fingerabdruck des Hosts wird bei der ersten Verbindung geprüft und dann festgelegt.
• Docker Compose: Bearbeite die Dateien eines Projekts mit Vorschau der Änderungen, Prüfung und automatischen Sicherungen; starte, stoppe, starte neu oder aktualisiere es mit Live-Ausgabe; öffne ein Terminal in seinem Ordner.
• Tabs für mehrere Sitzungen auf iPad und Mac, Face ID bei jeder Sitzung.

PRIVAT VON GRUND AUF
• Kein Konto, keine Nutzungsstatistiken, keine Werbung, kein Tracking. PatchNode erfasst keine Daten.
• Tokens bleiben im Schlüsselbund dieses iPhone. Die iCloud-Synchronisierung der Konfiguration und der Tokens über den iCloud-Schlüsselbund ist optional und standardmäßig aus.
• Nur HTTPS, ohne Ausnahme. Aktionen werden nie hinter deinem Rücken wiederholt.
• Die App verbindet sich nur mit den Servern, die du hinzufügst (und mit api.tailscale.com, wenn du Tailscale hinzufügst).

OHNE SERVER AUSPROBIEREN
Die integrierte Demo zeigt ein vollständiges Beispiel-HomeLab, das auf dem Gerät erzeugt wird.

PatchNode arbeitet mit deinen eigenen selbst gehosteten Diensten; du brauchst Netzwerkzugriff auf sie (zum Beispiel über Tailscale oder WireGuard). PatchNode ist eine unabhängige App, weder verbunden mit noch unterstützt von Proxmox Server Solutions, Docker, Portainer, Grafana Labs, Tailscale, CrowdSec, Home Assistant oder einem anderen unterstützten Produkt.

**Neuigkeiten** (1.2):

PatchNode 1.2: iPad, Mac, Konsolen, SSH und Compose.

• iPad und Mac: PatchNode läuft nativ auf dem iPad (Seitenleiste, angepasste Layouts, Tastaturkurzbefehle) und auf Macs mit Apple Silicon, mit einem sorgfältigeren Dunkelmodus.
• Proxmox-Konsolen: Öffne die Konsole eines Knotens, Containers oder einer VM in der App, als Terminal oder grafische Konsole. Erfordert Proxmox VE 9.1 oder neuer und das Konsolenrecht (PatchNode zeigt die Befehle, um es zu erteilen).
• SSH-Terminal (standardmäßig aus): Verbinde dich mit deinen eigenen Servern über einen auf dem Gerät erzeugten Schlüssel. Fingerabdrücke werden geprüft und festgelegt; Passwörter werden nie gespeichert.
• Docker Compose: Bearbeite Compose- und .env-Dateien mit Vorschau der Änderungen, Prüfung und automatischen Sicherungen; starte, stoppe, starte neu oder aktualisiere ein Projekt mit Live-Ausgabe; öffne ein Terminal in seinem Ordner. Portainer-Stacks über seine API.
• Face ID bei jeder Sitzung, nichts von dem, was du tippst, wird behalten, und die Demo, um alles ohne Server auszuprobieren.

**Neuigkeiten** (1.1, previous version) (1350):

PatchNode 1.1 ist da.

• iCloud-Synchronisierung (optional, standardmäßig aus): deine Dienste, PromQL-Diagramme, Home-Assistant-Entitäten, Tabs und die Reihenfolge der Übersicht auf all deinen Geräten, in deiner eigenen iCloud. Tokens können mit einer separaten Option über den iCloud-Schlüsselbund folgen.
• Export und Import: deine Konfiguration als Datei oder QR-Code, ohne Tokens, um ein anderes iPhone einzurichten oder eine Kopie zu behalten.
• Lokale Mitteilungen (optional): Dienst nicht erreichbar, Backup fehlgeschlagen, Container nicht gesund, neuer Alarm, Zertifikat läuft bald ab, Festplattenproblem. Vom iPhone selbst gesendet, auf dem Sperrbildschirm nur mit einer Anzahl. iOS entscheidet, wann Hintergrundaktualisierungen laufen, daher können sie verspätet kommen.
• TLS-Zertifikate: das Ablaufdatum jedes Dienstes, beim Verbindungsaufbau gelesen, mit einer Warnung 14 und 7 Tage vorher.
• Festplattenzustand in Proxmox: SMART-Status, SSD-Verschleiß und ZFS-Pools jedes Nodes.
• Neue Sprachen: Spanisch, Deutsch und Italienisch.

Außerdem in dieser Version (aus 1.0.1):
• Aktionen über Siri und Kurzbefehle sind standardmäßig aus; schalte sie in den Einstellungen mit Face ID ein.
• Tailscale-API-Schlüssel mit Vollzugriff werden abgelehnt: Nutze einen OAuth-Client mit Lesezugriff.
• Bessere VoiceOver-Beschriftungen und Pluralformen.

---

## Italiano — to be proofread by a native speaker

**Sottotitolo** (19): `Monitor per HomeLab`

**Parole chiave** (96): `homelab,proxmox,docker,portainer,prometheus,grafana,tailscale,selfhosted,server,zfs,monitoraggio`

**Testo promozionale** (139):
Tutto il tuo HomeLab in una schermata: Proxmox, Docker, avvisi, backup, rete e domotica. Privato per progettazione, diretto ai tuoi server.

**Descrizione**:

PatchNode tiene d’occhio il tuo HomeLab dal tuo iPhone. Comunica direttamente con i tuoi server, tramite la tua rete privata o la tua VPN, e mostra prima ciò che richiede la tua attenzione.

UNA SOLA DASHBOARD PER TUTTO
• Proxmox VE: nodi, VM e container, storage, attività, grafici per ora, giorno o settimana, stato dei dischi (SMART, pool ZFS)
• Certificati TLS: la data di scadenza di ogni servizio, con un avviso 14 e 7 giorni prima
• Proxmox Backup Server: datastore, ultimo backup di ogni guest, job non riusciti
• Docker, tramite Portainer o un socket proxy in sola lettura: container per host e stack, stato di salute, log, CPU e memoria
• Prometheus, Alertmanager, Grafana e Uptime Kuma: avvisi attivi, target non raggiungibili, pagine di stato, i tuoi grafici PromQL
• Tailscale: dispositivi online, offline da giorni, chiavi in scadenza
• CrowdSec, Nginx Proxy Manager e AdGuard Home: ban, proxy host, statistiche DNS
• Home Assistant e Glances: i sensori che scegli, scene e script, carico e dischi degli host

AGISCI CON PRUDENZA
Avvia, spegni o riavvia una VM o un container, oppure esegui una scena di Home Assistant. Ogni azione nomina il suo obiettivo e chiede conferma, con Face ID.

WIDGET E SIRI
I widget della schermata Home e della schermata di blocco mostrano lo stato del tuo HomeLab a colpo d’occhio. Chiedi a Siri lo stato del tuo HomeLab.

NOTIFICHE, ESPORTAZIONE E ICLOUD
• Notifiche locali facoltative dopo un aggiornamento in background: servizio non raggiungibile, backup non riuscito, container non integro, nuovo avviso, certificato in scadenza, problema di disco. Solo un numero nella schermata di blocco.
• Esporta la tua configurazione, senza alcun token, come file o codice QR, e importala su un altro iPhone.
• Sincronizzazione iCloud facoltativa della configurazione, nel tuo iCloud, disattivata per impostazione predefinita.

CONSOLE, SSH E COMPOSE
• Console Proxmox tramite l’API: un terminale per nodi, container e VM con porta seriale, la console grafica (noVNC, integrata) per le altre.
• Terminale SSH verso i tuoi server, con una chiave creata sul dispositivo; l’impronta dell’host viene verificata alla prima connessione, poi fissata.
• Docker Compose: modifica i file di un progetto con anteprima delle modifiche, validazione e backup automatici; avvialo, fermalo, riavvialo o aggiornalo con l’output in diretta; apri un terminale nella sua cartella.
• Schede per più sessioni su iPad e Mac, Face ID a ogni sessione.

PRIVATO PER PROGETTAZIONE
• Nessun account, nessuna statistica d’uso, nessuna pubblicità, nessun tracciamento. PatchNode non raccoglie alcun dato.
• I token restano nel portachiavi di questo iPhone. La sincronizzazione iCloud della configurazione, e dei token tramite il Portachiavi iCloud, è facoltativa e disattivata per impostazione predefinita.
• Solo HTTPS, senza eccezioni. Le azioni non vengono mai ripetute alle tue spalle.
• L’app si collega solo ai server che aggiungi (e ad api.tailscale.com se aggiungi Tailscale).

PROVALO SENZA SERVER
La demo integrata mostra un HomeLab di esempio completo, generato sul dispositivo.

PatchNode funziona con i tuoi servizi self-hosted; ti serve l’accesso di rete (per esempio tramite Tailscale o WireGuard). PatchNode è un’app indipendente, non affiliata né approvata da Proxmox Server Solutions, Docker, Portainer, Grafana Labs, Tailscale, CrowdSec, Home Assistant o qualsiasi altro prodotto supportato.

**Novità** (1.2):

PatchNode 1.2: iPad, Mac, console, SSH e Compose.

• iPad e Mac: PatchNode funziona in modo nativo su iPad (barra laterale, layout adattati, scorciatoie da tastiera) e sui Mac con Apple silicon, con una modalità scura più curata.
• Console Proxmox: apri la console di un nodo, di un container o di una VM dall’app, come terminale o console grafica. Richiede Proxmox VE 9.1 o successivo e il privilegio console (PatchNode mostra i comandi per concederlo).
• Terminale SSH (disattivato per impostazione predefinita): connettiti ai tuoi server con una chiave creata sul dispositivo. Le impronte vengono verificate e fissate; le password non vengono mai salvate.
• Docker Compose: modifica i file compose e .env con anteprima delle modifiche, validazione e backup automatici; avvia, ferma, riavvia o aggiorna un progetto con l’output in diretta; apri un terminale nella sua cartella. Stack Portainer tramite la sua API.
• Face ID a ogni sessione, nulla di ciò che digiti viene conservato, e la demo per provare tutto senza server.

**Novità** (1.1, previous version) (1352):

Ecco PatchNode 1.1.

• Sincronizzazione iCloud (facoltativa, disattivata per impostazione predefinita): servizi, grafici PromQL, entità di Home Assistant, schede e ordine della dashboard su tutti i tuoi dispositivi, nel tuo iCloud. I token possono seguirli tramite il Portachiavi iCloud con un’opzione separata.
• Esporta e importa: la tua configurazione come file o codice QR, senza alcun token, per configurare un altro iPhone o tenerne una copia.
• Notifiche locali (facoltative): servizio non raggiungibile, backup non riuscito, container non integro, nuovo avviso, certificato in scadenza, problema di disco. Inviate dall’iPhone stesso, con solo un numero nella schermata di blocco. iOS decide quando eseguire gli aggiornamenti in background, quindi possono arrivare in ritardo.
• Certificati TLS: la data di scadenza di ogni servizio, letta durante la connessione, con un avviso 14 e 7 giorni prima.
• Stato dei dischi Proxmox: stato SMART, usura degli SSD e pool ZFS di ogni nodo.
• Nuove lingue: spagnolo, tedesco e italiano.

Anche in questa versione (dalla 1.0.1):
• Le azioni di Siri e Comandi Rapidi sono disattivate per impostazione predefinita; attivale in Impostazioni, con Face ID.
• Le chiavi API di Tailscale con accesso completo vengono rifiutate: usa un client OAuth in sola lettura.
• Etichette VoiceOver e forme plurali migliorate.
