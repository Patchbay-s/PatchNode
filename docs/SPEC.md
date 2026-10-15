# PatchNode — Spécification de l'app iOS

## 1. Objectif et principes

PatchNode est une app native iPhone et iPad (`TARGETED_DEVICE_FAMILY = 1,2`), aussi disponible sur les Mac Apple silicon en « Designed for iPad » (1.2) pour surveiller et piloter un HomeLab (Proxmox, Docker, Tailscale, Grafana, Prometheus et services annexes) depuis un seul tableau de bord. Elle est destinée à être publiée sur l'App Store : chaque utilisateur configure ses propres services. Les services sont prévus pour être joignables uniquement via un réseau privé (Tailscale ou autre VPN) : aucun service de monitoring n'a besoin d'être exposé sur internet.

Principes non négociables :

- **Réseau privé** : l'app appelle directement les URL saisies par l'utilisateur, en pratique joignables via son VPN. Seule exception prévue : l'API Tailscale (`api.tailscale.com`).
- **Pas de backend** : aucun serveur intermédiaire, aucune télémétrie, aucune collecte de données.
- **Moindre privilège** : un jeton dédié par service, en lecture seule par défaut. Les droits d'action sont ajoutés service par service.
- **Secrets dans le Keychain** : jamais dans les réglages, les logs ou le code. Verrouillage par Face ID.
- **HTTPS valide obligatoire** : pas de certificat auto-signé accepté par l'app, aucune exception ATS. L'utilisateur passe par un reverse proxy avec un certificat valide.
- **Actions confirmées** : toute action qui modifie un état demande une confirmation explicite avec le nom de la cible.
- **Architecture à fournisseurs** : chaque service est un module indépendant. Ajouter un service ne touche pas au reste.
- **Générique** : aucun domaine, IP ou nom d'hôte codé en dur. Les exemples de ce document (`homelab.example`, adresses de documentation `192.0.2.0/24`) ne servent que de placeholders.

## 2. Architecture technique

SwiftUI pur, organisé en packages Swift locaux pour que chaque fournisseur soit testable isolément. Aucune dépendance externe, sauf les exceptions de la 1.2 (CLAUDE.md) : SwiftTerm (terminal), SwiftNIO SSH d'Apple et ses dépendances Apple (SSH), noVNC embarqué (console graphique), versions figées.

| Choix | Détail |
| --- | --- |
| Langage | Swift 6.4, mode Swift 6, concurrence stricte (`async`/`await`, acteurs) |
| Interface | SwiftUI, `@Observable` (Observation) |
| Graphiques | Swift Charts |
| Configuration | SwiftData pour la liste des services (id, type, nom, URL), sans aucun secret. Schéma versionné (`VersionedSchema`) avec plan de migration. V2 (1.1) compatible CloudKit : aucun attribut unique, valeurs par défaut, entité `SyncedSetting` (onglets, ordre du tableau de bord). Synchronisation iCloud facultative (base privée de l'utilisateur, désactivée par défaut, appliquée au lancement suivant) ; doublons d'ID tolérés à l'affichage. Écran d'erreur si le store ne s'ouvre pas (jamais supprimé) |
| Secrets | Keychain, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, non synchronisé par défaut. Option explicite, désactivée par défaut : trousseau iCloud (`kSecAttrSynchronizable`, `WhenUnlocked`) |
| Réseau | `URLSession` avec un client HTTP commun |
| Extensions | WidgetKit (widgets), App Intents (raccourcis) |
| iOS minimum | iOS 27 |
| Localisation | String Catalog : anglais (développement), français, espagnol, allemand, italien. Guides : anglais et français côte à côte, espagnol/allemand/italien dans des tables indexées par le texte anglais (`GuideText+es/de/it.swift`, repli sur l’anglais) |

Structure du projet :

```text
PatchNode/
├── PatchNode/               # Cible iOS : écrans, navigation, Face ID
├── PatchNodeWidgets/        # Extension WidgetKit
└── Packages/
    ├── PatchNodeCore/       # Client HTTP, SecretStore/Keychain, modèles communs, erreurs
    ├── ProxmoxKit/         # Proxmox VE + PBS
    ├── DockerKit/          # Portainer + Docker Engine API
    ├── TailscaleKit/
    ├── ObservabilityKit/   # Grafana, Prometheus, Alertmanager, Uptime Kuma
    ├── SecurityKit/        # CrowdSec, NPM, AdGuard
    ├── HomeServicesKit/    # Home Assistant, Glances
    ├── RemoteAccessKit/    # 1.2 : client SSH, consoles Proxmox (termproxy, VNC), Docker Compose
    └── TerminalKit/        # 1.2 : terminal SwiftTerm partagé, shell de démo
```

Contrat commun à tous les fournisseurs :

```swift
protocol ServiceProvider: Sendable {
    var id: UUID { get }
    var kind: ServiceKind { get }
    var displayName: String { get }

    /// Vérifie la connexion et les droits du jeton.
    func healthCheck() async throws -> HealthStatus

    /// Résumé affiché sur le tableau de bord.
    func summary() async throws -> ServiceSummary
}

enum HealthStatus: Sendable {
    case ok
    case degraded(String)
    case unreachable(any Error & Sendable)   // ex. VPN coupé
    case unauthorized                        // jeton expiré ou révoqué
}
```

Règles de sécurité pour le code :

- Aucune exception ATS (`NSAllowsArbitraryLoads` interdit). URL saisies en HTTPS uniquement.
- Aucun secret dans les logs, y compris en debug. Masquer `Authorization`, `X-API-Key` et `X-Api-Key` dans tout affichage de requête.
- Face ID à l'ouverture et au retour au premier plan, contenu masqué dans le sélecteur d'apps.
- Délai 10 s, nouvelles tentatives espacées, jamais de retry sur 401/403 ni sur POST : une rafale de 401 peut déclencher un IPS type CrowdSec côté utilisateur.
- Détection du réseau privé : si aucun service ne répond, afficher un seul état « Réseau privé / VPN injoignable » plutôt qu'une erreur par service.
- Confirmation explicite, avec le nom de la cible, avant toute action qui modifie un état.
- Privacy Manifest (`PrivacyInfo.xcprivacy`) : aucune collecte, aucun tracking, Required Reason APIs déclarées.

### Migration SwiftData

Depuis la 1.0.1, le store est ouvert via `PatchNodeModelStore` avec un schéma versionné (`PatchNodeSchemaV1`, `VersionedSchema`) et `PatchNodeMigrationPlan` (`SchemaMigrationPlan`). V1 correspond exactement au store créé sans versionnement par la 1.0 : une mise à jour ne perd ni les services, ni les favoris PromQL, ni les épingles Home Assistant. Tout changement de modèle passe par un `PatchNodeSchemaV2` et une étape de migration (procédure en tête de `PatchNodeSchema.swift`) ; `SchemaMigrationTests` échoue sinon.

## 3. Jetons et droits par service

Un jeton dédié à l'app pour chaque service, jamais le compte admin. Ces informations alimentent l'aide intégrée de l'écran d'ajout de service.

| Service | Où le créer | Droits recommandés | En-tête HTTP |
| --- | --- | --- | --- |
| Proxmox VE | Datacenter > Permissions : utilisateur dédié (ex. `monitor@pve`), puis API Tokens | Rôle `PVEAuditor` sur `/` (utilisateur **et** jeton) ; pour les actions, un rôle dédié `PatchNodePower` avec le seul privilège `VM.PowerMgmt` sur `/vms` ou `/vms/<id>` (plutôt que `PVEVMUser`, trop large), toujours avec `PVEAuditor` sur ces chemins (`--roles 'PVEAuditor,PatchNodePower'`) : une ACL plus précise remplace les rôles hérités | `Authorization: PVEAPIToken=<user>@<realm>!<tokenid>=<secret>` |
| Proxmox Backup Server | Configuration > Access Control > API Token | Rôle `Audit` | `Authorization: PBSAPIToken=<user>@<realm>!<tokenid>:<secret>` |
| Portainer | My account > Access tokens | Utilisateur dédié (CE n'a pas de rôle lecture seule) | `X-API-Key: <jeton>` |
| Docker (socket proxy) | Variables de `tecnativa/docker-socket-proxy` | `CONTAINERS=1`, `INFO=1`, `POST=0` ; `POST=1` pour les actions | Basic via le reverse proxy |
| Tailscale | Admin console > Settings > Trust credentials (anciennement OAuth clients) | Scope `devices:core:read` | `Authorization: Bearer <jeton OAuth>` |
| Grafana | Administration > Service accounts | Rôle `Viewer` | `Authorization: Bearer <jeton>` |
| Prometheus, Alertmanager | Pas de jeton natif | Accès réseau privé, Basic en option | Aucun ou `Authorization: Basic` |
| Uptime Kuma | Page de statut publique | Lecture | Aucun |
| CrowdSec | `cscli bouncers add <nom>` | Lecture des décisions | `X-Api-Key: <clé bouncer>` |
| Home Assistant | Profil > Sécurité > Jetons longue durée | Utilisateur non admin | `Authorization: Bearer <jeton>` |
| AdGuard Home | Utilisateur de l'interface | Compte dédié | `Authorization: Basic` |
| Nginx Proxy Manager | Users > Add User, « View Only » | Lecture | `Authorization: Bearer <jeton via /api/tokens>` |
| Glances | Option `--password` | Lecture | `Authorization: Basic` |

Les noms exacts de menus et scopes peuvent varier selon les versions.

## 4. Référence API par service

Vérifier chaque endpoint dans la documentation de la version visée avant de coder.

### Proxmox VE

Base : `<URL>/api2/json`. Réponses enveloppées dans `{"data": ...}`. Plusieurs nœuds hors cluster = plusieurs services distincts.

| Méthode | Chemin | Usage |
| --- | --- | --- |
| GET | `/version` | Test de connexion (healthCheck) |
| GET | `/cluster/resources` | Nœuds, VM, LXC, stockages en un appel (`?type=vm`, `node`, `storage`) |
| GET | `/nodes/{node}/status` | CPU, RAM, uptime, version |
| GET | `/nodes/{node}/qemu/{vmid}/status/current` | État d'une VM (`lxc` pour un conteneur) |
| GET | `/nodes/{node}/qemu/{vmid}/rrddata?timeframe=hour` | Historique (`hour`, `day`, `week`…) |
| POST | `/nodes/{node}/qemu/{vmid}/status/{start,shutdown,stop,reboot}` | Actions (`VM.PowerMgmt`, rôle `PatchNodePower`) |
| GET | `/cluster/tasks` | Tâches récentes |
| GET | `/cluster/backup` | Tâches de sauvegarde vzdump planifiées (`Sys.Audit`) |
| GET | `/cluster/backup-info/not-backed-up` | VM et LXC couverts par aucune tâche active |
| GET | `/nodes/{node}/storage/{storage}/content?content=backup` | Archives de sauvegarde d'un stockage (`Datastore.Audit`) |
| GET | `/nodes/{node}/disks/list` | Disques physiques : santé SMART (`health`), durée de vie restante des SSD (`wearout`, 100 = neuf), usage (`Sys.Audit`, compris dans `PVEAuditor`). Sans `skipsmart=1`, Proxmox lance `smartctl -H -A` sur chaque disque (réveille les disques en veille) ; avec, seulement lsblk/udev (sysfs), `health` = UNKNOWN, `wearout` = N/A. PatchNode envoie toujours `skipsmart=1` sauf lecture SMART voulue |
| GET | `/nodes/{node}/disks/zfs` | Pools ZFS : état (`health`), taille, allocation, fragmentation (`Sys.Audit`). `zpool list` : état tenu par le noyau, pas d'accès disque, lu automatiquement |

Les actions renvoient un UPID à suivre via `/nodes/{node}/tasks/{upid}/status`.

Santé des disques (1.1) : écran Proxmox › Santé des disques, chargé à l'ouverture sans SMART. Réglage par service « Santé SMART des disques » (`SMARTSetting`) : Désactivé, À la demande (défaut, bouton « Lire l'état SMART » avec avertissement), Automatique une fois par jour à partir d'une heure choisie (défaut 18:00 ; à la première ouverture après l'heure, ou par la tâche d'arrière-plan `fr.antxis.apple.labwatch.smart` avec earliestBeginDate = heure choisie ; une lecture par jour local, à la demande comprise). Jamais de SMART au rafraîchissement, en arrière-plan ordinaire ni dans les widgets (`SMARTPolicy`, testé). La dernière lecture SMART (`SMARTReadingStore`, UserDefaults) complète les lectures sans SMART pour l'écran et les notifications de disque ; les pools sont relus au plus toutes les heures pendant le rafraîchissement. Disque SMART en échec ou pool ZFS FAULTED/UNAVAIL/SUSPENDED = rouge ; SSD à 10 % de vie restante ou moins, pool DEGRADED ou rempli à 80 % = orange (rouge à 90 %). Un refus (403) ne vide que la partie concernée ; 401, blocage du proxy ou service injoignable arrêtent le chargement.

Sauvegardes natives : l'app lit les sauvegardes directement dans Proxmox VE (tâches planifiées, invités non couverts, archives par stockage, échecs vzdump des dernières 24 h), sans exiger Proxmox Backup Server. PBS reste un service distinct pour ses datastores.

### Proxmox Backup Server

Base : `<URL>/api2/json`.

| Méthode | Chemin | Usage |
| --- | --- | --- |
| GET | `/admin/datastore` | Datastores |
| GET | `/admin/datastore/{store}/status` | Espace utilisé et disponible |
| GET | `/nodes/localhost/tasks` | Sauvegardes, vérifications, nettoyages |

### Docker via Portainer

Base : `<URL>/api`. L'API Docker Engine est relayée sous `/endpoints/{id}/docker/...`.

| Méthode | Chemin | Usage |
| --- | --- | --- |
| GET | `/endpoints` | Hôtes Docker |
| GET | `/endpoints/{id}/docker/containers/json?all=true` | Conteneurs |
| GET | `/endpoints/{id}/docker/containers/{cid}/stats?stream=false` | CPU et RAM |
| GET | `/endpoints/{id}/docker/containers/{cid}/logs?stdout=true&stderr=true&tail=200` | Logs |
| POST | `/endpoints/{id}/docker/containers/{cid}/{start,stop,restart}` | Actions |
| GET | `/stacks` | Stacks compose |

### Docker sans Portainer

Même API Docker Engine via un socket proxy derrière un reverse proxy HTTPS : `/containers/json?all=1`, `/containers/{id}/stats?stream=false`, `/containers/{id}/logs?...`, `/containers/{id}/{start,stop,restart}`.

Piège des logs : sans TTY, Docker multiplexe stdout et stderr avec un en-tête binaire de 8 octets par bloc (1 octet de flux, 3 octets nuls, 4 octets de taille big-endian). Il faut le décoder.

### Tailscale

Base : `https://api.tailscale.com/api/v2`.

| Méthode | Chemin | Usage |
| --- | --- | --- |
| POST | `/oauth/token` | Jeton d'accès depuis le client OAuth |
| GET | `/tailnet/-/devices` | Appareils, IP, dernière connexion, expiration de clé |

### Grafana, Prometheus, Alertmanager

| Service | Méthode | Chemin | Usage |
| --- | --- | --- | --- |
| Grafana | GET | `/api/health` | Santé |
| Grafana | GET | `/api/search?type=dash-db` | Dashboards (vue web intégrée) |
| Grafana | GET | `/api/alertmanager/grafana/api/v2/alerts` | Alertes actives |
| Prometheus | GET | `/api/v1/query?query=...` | Valeur instantanée |
| Prometheus | GET | `/api/v1/query_range?query=...&start=...&end=...&step=...` | Séries pour Swift Charts |
| Prometheus | GET | `/api/v1/targets` | Cibles UP / DOWN |
| Alertmanager | GET | `/api/v2/alerts` | Alertes en cours |

### Uptime Kuma

| Méthode | Chemin | Usage |
| --- | --- | --- |
| GET | `/api/status-page/{slug}` | Moniteurs de la page de statut |
| GET | `/api/status-page/heartbeat/{slug}` | Battements et disponibilité |

### CrowdSec

| Méthode | Chemin | Usage |
| --- | --- | --- |
| GET | `/v1/decisions` | Bans actifs (`null` s'il n'y en a aucun) |

### Home Assistant

| Méthode | Chemin | Usage |
| --- | --- | --- |
| GET | `/api/` | Test de connexion |
| GET | `/api/states` | États des entités |
| POST | `/api/services/{domain}/{service}` | Scène, script |

### AdGuard Home, NPM, Glances

| Service | Méthode | Chemin | Usage |
| --- | --- | --- | --- |
| AdGuard | GET | `/control/status` | Protection active |
| AdGuard | GET | `/control/stats` | Requêtes, blocages, top domaines |
| NPM | POST | `/api/tokens` | Obtenir un jeton |
| NPM | GET | `/api/nginx/proxy-hosts` | Hosts |
| Glances | GET | `/api/4/all` | Métriques (`/api/3/` pour Glances 3) |

## 5. Écrans et fonctionnalités

Onglets : Tableau de bord, Proxmox, Docker, Observabilité, Réglages. Les services non configurés disparaissent de l'interface.

| Écran | Contenu | Actions |
| --- | --- | --- |
| Tableau de bord | Une carte par service : état (vert, orange, rouge), chiffres clés, bandeau si le réseau privé est injoignable, bandeau si un certificat TLS expire dans moins de 14 jours (rouge sous 7 jours) | Tirer pour rafraîchir, toucher une carte pour le détail |
| Proxmox | Nœuds (CPU, RAM, stockage), VM et LXC filtrables, graphiques `rrddata`, tâches, sauvegardes natives Proxmox VE (et PBS si configuré) | Démarrer, arrêter, redémarrer avec confirmation |
| Docker | Hôtes, conteneurs par stack, état, CPU/RAM, logs avec recherche | Démarrer, arrêter, redémarrer |
| Observabilité | Alertes Grafana/Alertmanager, graphiques Prometheus favoris, Uptime Kuma, dashboards Grafana | Ajouter une requête PromQL favorite |
| Sécurité | Bans CrowdSec, hosts NPM, stats AdGuard | Lecture seule |
| Tailscale | Appareils, dernière connexion, expiration de clé | Lecture seule |
| Home Assistant | Entités choisies | Scènes et scripts sélectionnés |
| Réglages | Ajout et test des services, aide par type, Face ID, intervalle de rafraîchissement, notifications locales (1.1), export et import de la configuration (1.1) | Tester, supprimer (efface aussi le jeton), importer (fusion ou remplacement confirmé) |

Ajout d'un service : type, nom, URL (HTTPS obligatoire), jeton. L'app lance `healthCheck()` et n'enregistre le service que si le test réussit, avec un message clair sinon (injoignable, jeton refusé, droits insuffisants). Le jeton n'est jamais réaffiché ensuite.

Certificats TLS (1.1) : la date d'expiration du certificat de chaque service est lue pendant la poignée de main TLS que l'app fait de toute façon (délégué de session, aucune requête supplémentaire), seulement si l'évaluation du système accepte la chaîne ; la décision reste celle du système (`performDefaultHandling`). Conservée en mémoire, affichée dans le bandeau du tableau de bord et dans Diagnostic. Tailscale exclu (certificat de l'API Tailscale).

Export et import (1.1) : fichier JSON versionné `PatchNode-configuration` (version 1) sans aucun secret : services (ID, type, nom, URL), favoris PromQL, épingles Home Assistant, onglets, ordre du tableau de bord. Import validé (taille ≤ 1 Mo, format, version, URL HTTPS, type connu, doublons par ID ou par type et adresse, favoris et épingles rattachés à un service importé), aperçu, puis fusion ou remplacement (confirmation nommée, Face ID, jetons des services retirés supprimés). QR code si l'export fait au plus 2 300 octets ; import d'un QR depuis une photo, sans autorisation caméra.

Widgets : état global (petit), charge des nœuds Proxmox (moyen), conteneurs arrêtés ou en erreur (moyen). Heure de la dernière donnée affichée.

Raccourcis (App Intents) : « État du HomeLab », « Redémarrer la VM… », « Redémarrer le conteneur… », toujours avec confirmation.

### Consoles, SSH et Compose (1.2)

- **Consoles Proxmox** (PVE ≥ 9.1 pour un jeton API) : `POST …/termproxy` ou `…/vncproxy`, websocket `vncwebsocket` ouvert en natif avec `Authorization: PVEAPIToken=…`. Terminal pour un nœud (Sys.Console), un CT et une VM avec `serialN` (VM.Console) ; console graphique noVNC (embarquée, schéma local, CSP `connect-src 'none'`) pour une VM sans port série. Rôles `PatchNodeConsole` (VM.Console, sur `/vms/<id>`) et `PatchNodeNodeConsole` (Sys.Console, sur `/nodes/<nœud>` seulement), toujours accordés avec `PVEAuditor` (et `PatchNodePower` si le jeton l'a) sur un chemin sous `/` ; commandes `pveum` affichées si le droit manque, suivies de `pveum user token permissions`. Un guest qui disparaît alors que son nœud répond : ligne dans Diagnostic (droits ?), jamais présenté comme supprimé. Face ID à chaque ouverture.
- **SSH** (désactivé par défaut) : clé ed25519 de l'appareil (Keychain dédié, jamais synchronisée), empreinte d'hôte affichée au premier contact puis épinglée (entité SwiftData `SSHHost`, schéma V3), mot de passe saisi à la demande et jamais stocké, Face ID à chaque session. Raccourcis : SSH d'un nœud ou invité relié, « Entrer dans le conteneur » (`pct enter`).
- **Compose** : projets trouvés par les labels des conteneurs ; édition des fichiers `.yml/.yaml` du dossier et du `.env` (valeurs masquées), aperçu des différences, validation `docker compose config`, sauvegarde `.bak-<horodatage>` (5 gardées), vérification du chemin réel sur le serveur ; actions up/stop/restart/pull+up avec confirmation, Face ID, sortie en direct, jamais relancées. Stacks Portainer par l'API.
- Contenu des sessions et fichiers jamais journalisé ; le Diagnostic garde ouverture, fermeture, durée, code d'erreur.

## 6. Limites iOS

- `BGAppRefreshTask` s'exécute quand iOS le décide : suffisant pour les widgets, pas pour de l'alerte temps réel.
- Notifications immédiates impossibles sans serveur push (APNs) : hors périmètre, l'utilisateur garde ses alertes côté HomeLab. Depuis la 1.1, des **notifications locales** (désactivées par défaut, par type) sont publiées à la fin d'un rafraîchissement en arrière-plan, quand iOS en accorde un : nouveaux problèmes seulement, un nombre par type sans nom ni adresse, anti-répétition de 6 h, aucune si tous les services sont injoignables (VPN coupé). La logique de détection (`ConditionWatch`) est dans PatchNodeCore, testée sous Linux.
- Widgets limités par le budget de rafraîchissement iOS.
- L'app ne peut pas activer le VPN : elle détecte l'absence de connexion et invite à l'ouvrir.

## 7. Feuille de route

Chaque phase produit une app utilisable. On valide une phase avant d'ouvrir la suivante.

| Phase | Contenu | Critère de fin |
| --- | --- | --- |
| 1. Socle | `PatchNodeCore`, Réglages avec ajout et test d'un service, Face ID, détection réseau privé coupé, Privacy Manifest | Un service Proxmox s'ajoute, son jeton est dans le Keychain, `healthCheck()` répond |
| 2. Proxmox en lecture | Nœuds, VM, LXC, `rrddata`, tâches, carte tableau de bord | Toutes les VM et LXC s'affichent avec leur état |
| 3. Docker en lecture | Portainer et socket proxy, conteneurs par stack, logs décodés | Conteneurs affichés, logs lisibles |
| 4. Observabilité | Prometheus, alertes Grafana/Alertmanager, Uptime Kuma | Alertes en cours sur le tableau de bord |
| 5. Actions | Start/stop/reboot VM, LXC, conteneurs avec confirmation et suivi de tâche | Une action aboutit et son résultat s'affiche |
| 6. Services annexes | Tailscale, CrowdSec, NPM, AdGuard, Home Assistant, Glances, PBS | Chaque service a sa carte et son écran |
| 7. Intégration iOS | Widgets, App Intents, rafraîchissement en arrière-plan | Widgets avec l'état global |
| 8. Publication | Onboarding, textes App Store, politique de confidentialité, captures | Build accepté en TestFlight |

## Annexe — Installation de référence (exemple fictif)

Exemple d'installation type pour les tests sur appareil, à ne jamais coder en dur. Split DNS Tailscale vers AdGuard (`192.0.2.19`) restreint à `homelab.example`, hosts NPM en Access List « LAN Only » avec certificat wildcard `*.homelab.example`.

| Host | Destination |
| --- | --- |
| `node-a.homelab.example` | `https://192.0.2.11:8006` |
| `node-b.homelab.example` | `https://192.0.2.20:8006` |
| `portainer.homelab.example` | `https://192.0.2.23:9443` |
| `crowdsec-api.homelab.example` | `http://192.0.2.17:8080` |
| `adguard.homelab.example` | `http://192.0.2.19:80` |
| `npm.homelab.example` | `http://192.0.2.17:81` |
