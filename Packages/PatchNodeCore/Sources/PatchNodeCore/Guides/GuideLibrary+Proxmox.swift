import Foundation

extension GuideLibrary {
    /// The troubleshooting entry a graphical console links to.
    public static let serialConsoleAnchor = "Graphical console only: add a serial port"

    static let proxmoxVEGuide = Guide(
        topic: .service(.proxmoxVE),
        title: t("Proxmox VE", "Proxmox VE"),
        summary: t("Nodes, VMs and containers, storage, tasks, power actions.", "Nœuds, VM et conteneurs, stockages, tâches, actions d’alimentation."),
        sections: [
            GuideSection(.purpose, [
                .paragraph(t(
                    "PatchNode shows your nodes (CPU, memory, disks, storage), every VM and container with charts per hour, day or week, and recent tasks with failures first. With the right role, it can start, shut down, stop or reboot a VM or container after a confirmation.",
                    "PatchNode affiche vos nœuds (CPU, mémoire, disques, stockages), chaque VM et conteneur avec des graphiques sur une heure, un jour ou une semaine, et les tâches récentes, échecs en tête. Avec le bon rôle, il peut démarrer, éteindre, arrêter ou redémarrer une VM ou un conteneur après confirmation."
                )),
                .paragraph(t(
                    "Proxmox › Backups (Proxmox VE) lists the backup jobs, the guests no job covers, the latest archive of every guest (from the storages holding backups, NFS and Proxmox Backup Server storages included) and the failed backup tasks. It needs no other right than PVEAuditor.",
                    "Proxmox › Sauvegardes (Proxmox VE) liste les tâches de sauvegarde, les VM et CT couverts par aucune tâche, la dernière archive de chacun (dans les stockages qui contiennent des sauvegardes, NFS et stockages Proxmox Backup Server compris) et les sauvegardes en échec. Aucun autre droit que PVEAuditor n’est nécessaire."
                )),
                .paragraph(t(
                    "Proxmox › Disk health shows, for each online node, the SMART status and remaining life of every disk (Disks in the node's menu) and the state and fill of every ZFS pool. It needs Sys.Audit, which PVEAuditor on / already gives. SMART data comes from smartmontools on the node; disks behind a USB bridge or a RAID controller often report none.",
                    "Proxmox › Santé des disques affiche, pour chaque nœud en ligne, l’état SMART et la durée de vie restante de chaque disque (menu Disques du nœud) ainsi que l’état et le remplissage de chaque pool ZFS. Il faut Sys.Audit, que PVEAuditor sur / donne déjà. Les données SMART viennent de smartmontools sur le nœud ; les disques derrière un adaptateur USB ou un contrôleur RAID n’en remontent souvent aucune."
                )),
                .paragraph(t(
                    "Disks in standby: reading SMART makes Proxmox run smartctl on every disk, which wakes up disks that went to sleep (spindown). PatchNode reads the disks only as you choose for each service in Disk health: Off (no request to the disks at all, no disk notification), On demand (the default: only with the button) or Automatic, once a day from a chosen time. A read covers the disk list with SMART and the ZFS pools; in between, the screen and the disk notifications use the last read, with its date. Pick a time when the disks already spin, for example during a scheduled backup.",
                    "Disques en veille : lire SMART fait lancer smartctl sur chaque disque par Proxmox, ce qui réveille les disques endormis (spindown). PatchNode ne lit les disques que comme vous le choisissez pour chaque service dans Santé des disques : Désactivé (aucune requête vers les disques, aucune notification de disque), À la demande (par défaut : seulement avec le bouton) ou Automatique, une fois par jour à partir d’une heure choisie. Une lecture comprend la liste des disques avec SMART et les pools ZFS ; entre deux lectures, l’écran et les notifications de disque utilisent la dernière lecture, avec sa date. Choisissez une heure où les disques tournent déjà, par exemple pendant une sauvegarde planifiée."
                )),
                .paragraph(t(
                    "Consoles: the Console button of a node, a container or a VM opens a terminal inside PatchNode (the node's shell, the container, or the VM's serial port), or the graphical console of a VM without a serial port. Face ID is asked every time. Consoles with an API token need Proxmox VE 9.1 or later.",
                    "Consoles : le bouton Console d’un nœud, d’un conteneur ou d’une VM ouvre un terminal dans PatchNode (shell du nœud, conteneur, ou port série de la VM), ou la console graphique d’une VM sans port série. Face ID est demandé à chaque fois. Les consoles avec un jeton API demandent Proxmox VE 9.1 ou plus récent."
                )),
                .paragraph(t(
                    "A cluster is one service: add any of its nodes. Nodes outside a cluster are separate services: add one service per node.",
                    "Un cluster = un service : ajoutez n’importe lequel de ses nœuds. Des nœuds hors cluster sont des services distincts : ajoutez un service par nœud."
                )),
            ]),
            GuideSection(.setup, [
                .steps([
                    t("Datacenter › Permissions › Users › Add: user monitor, realm Proxmox VE authentication server (monitor@pve). No password is needed for API use.", "Datacenter › Permissions › Users › Add : utilisateur monitor, realm Proxmox VE authentication server (monitor@pve). Aucun mot de passe n’est nécessaire pour l’API."),
                    t("Datacenter › Permissions › API Tokens › Add: user monitor@pve, Token ID patchnode. Keep Privilege Separation ticked (recommended).", "Datacenter › Permissions › API Tokens › Add : utilisateur monitor@pve, Token ID patchnode. Laissez Privilege Separation cochée (recommandé)."),
                    t("Copy the secret now: Proxmox shows it only once.", "Copiez le secret tout de suite : Proxmox ne l’affiche qu’une fois."),
                    t("In PatchNode, paste the full value: user@realm!tokenid=secret.", "Dans PatchNode, collez la valeur complète : utilisateur@realm!tokenid=secret."),
                ]),
                .code("monitor@pve!patchnode=00000000-0000-0000-0000-000000000000"),
                .paragraph(t("The same from the node's shell:", "La même chose depuis le shell du nœud :")),
                .code("pveum user add monitor@pve\npveum user token add monitor@pve patchnode --privsep 1"),
            ]),
            GuideSection(.rights, [
                .paragraph(t("Reading: role PVEAuditor on /. With Privilege Separation, a token only has the rights both it and its user have (the intersection): grant the role to both, or the lists stay empty.", "Lecture : rôle PVEAuditor sur /. Avec Privilege Separation, un jeton n’a que les droits communs à lui et à son utilisateur (l’intersection) : accordez le rôle aux deux, sinon les listes restent vides.")),
                .code("pveum acl modify / --roles PVEAuditor --users monitor@pve\npveum acl modify / --roles PVEAuditor --tokens 'monitor@pve!patchnode'"),
                .paragraph(t("Actions: rather than PVEVMUser (which also allows the console and more), create a role with the VM.PowerMgmt privilege only, on /vms, or /vms/100 for a single VM, with PVEAuditor next to it (see the warning below):", "Actions : plutôt que PVEVMUser (qui autorise aussi la console et plus), créez un rôle avec le seul privilège VM.PowerMgmt, sur /vms, ou /vms/100 pour une seule VM, avec PVEAuditor à côté (voir la mise en garde plus bas) :")),
                .code("pveum role add PatchNodePower --privs VM.PowerMgmt\npveum acl modify /vms --roles 'PVEAuditor,PatchNodePower' --users monitor@pve\npveum acl modify /vms --roles 'PVEAuditor,PatchNodePower' --tokens 'monitor@pve!patchnode'"),
                .paragraph(t("Consoles: a PatchNodeConsole role with VM.Console only, on the guest (/vms/101), and for a node's shell a PatchNodeNodeConsole role with Sys.Console only, on the node (/nodes/node-a) — never Sys.Console on a guest. On / (everything), the role alone is enough. A node's shell opened by another user than root@pam asks for a Linux login.", "Consoles : un rôle PatchNodeConsole avec le seul VM.Console, sur l’invité (/vms/101), et pour le shell d’un nœud un rôle PatchNodeNodeConsole avec le seul Sys.Console, sur le nœud (/nodes/node-a) — jamais Sys.Console sur un invité. Sur / (tout), le rôle seul suffit. Le shell d’un nœud ouvert par un autre utilisateur que root@pam demande un login Linux.")),
                .code("pveum role add PatchNodeConsole --privs VM.Console\npveum acl modify /vms/101 --roles 'PVEAuditor,PatchNodeConsole' --users monitor@pve\npveum acl modify /vms/101 --roles 'PVEAuditor,PatchNodeConsole' --tokens 'monitor@pve!patchnode'\npveum role add PatchNodeNodeConsole --privs Sys.Console\npveum acl modify /nodes/node-a --roles 'PVEAuditor,PatchNodeNodeConsole' --users monitor@pve\npveum acl modify /nodes/node-a --roles 'PVEAuditor,PatchNodeNodeConsole' --tokens 'monitor@pve!patchnode'"),
                .warning(t("A role on a deeper path replaces, for the same user or token, the roles inherited from above: PatchNodeConsole alone on /vms/101 takes PVEAuditor away there, and the guest vanishes from PatchNode. On any path other than /, always grant PVEAuditor with the role, and PatchNodePower too if the guest keeps its actions ('PVEAuditor,PatchNodePower,PatchNodeConsole'), to the user and to the token. Use a user dedicated to PatchNode: on your own account, such an ACL would also replace your other roles on that path.", "Un rôle sur un chemin plus précis remplace, pour le même utilisateur ou jeton, les rôles hérités du dessus : PatchNodeConsole seul sur /vms/101 y retire PVEAuditor, et l’invité disparaît de PatchNode. Sur tout chemin autre que /, accordez toujours PVEAuditor avec le rôle, et PatchNodePower aussi si l’invité garde ses actions ('PVEAuditor,PatchNodePower,PatchNodeConsole'), à l’utilisateur et au jeton. Utilisez un utilisateur dédié à PatchNode : sur votre propre compte, une telle ACL remplacerait aussi vos autres rôles sur ce chemin.")),
                .paragraph(t("Check the token's effective rights on a path (user, token ID, path):", "Vérifiez les droits effectifs du jeton sur un chemin (utilisateur, ID du jeton, chemin) :")),
                .code("pveum user token permissions monitor@pve patchnode --path /vms/101"),
                .warning(t("A console gives a shell on the guest or the node: grant it only where you need it.", "Une console donne un shell sur l’invité ou le nœud : ne l’accordez que là où vous en avez besoin.")),
                .warning(t("In zsh and bash, the ! of the token name must be inside single quotes ('monitor@pve!patchnode'), otherwise the shell tries to expand it.", "Dans zsh et bash, le « ! » du nom du jeton doit être entre guillemets simples ('monitor@pve!patchnode'), sinon le shell essaie de l’interpréter.")),
            ]),
            GuideSection(.reverseProxy, [
                .paragraph(t("Proxmox itself listens in HTTPS on port 8006. In Nginx Proxy Manager, the proxy host must forward with the https scheme:", "Proxmox écoute lui-même en HTTPS sur le port 8006. Dans Nginx Proxy Manager, le proxy host doit transférer avec le schéma https :")),
                .code("Domain Names:  proxmox.example.invalid\nScheme:        https\nForward Host:  192.0.2.11\nForward Port:  8006\nWebsockets:    on\nSSL:           your certificate, Force SSL on"),
                .warning(t("With Scheme http, Proxmox answers 301 Moved Permanently and PatchNode can't read anything.", "Avec le schéma http, Proxmox répond 301 Moved Permanently et PatchNode ne peut rien lire.")),
                .warning(t("Consoles go through a websocket: in Nginx Proxy Manager, Websockets Support must be on for the Proxmox host.", "Les consoles passent par un websocket : dans Nginx Proxy Manager, Websockets Support doit être activé pour l’hôte Proxmox.")),
            ]),
            GuideSection(.verify, [
                .paragraph(t("Type the token without it being displayed, then call the API:", "Saisissez le jeton sans qu’il s’affiche, puis appelez l’API :")),
                .code("read -rs PVE_TOKEN\ncurl -sS -H \"Authorization: PVEAPIToken=$PVE_TOKEN\" https://proxmox.example.invalid/api2/json/cluster/resources"),
                .paragraph(t("You should see your nodes, VMs and storage. A list with only nodes and no CPU or memory means the token lacks rights.", "Vous devez voir vos nœuds, VM et stockages. Une liste avec seulement des nœuds, sans CPU ni mémoire, signifie que le jeton manque de droits.")),
            ]),
        ],
        troubleshooting: [
            GuideTroubleshooting(.insufficientRights, t("Empty list, or “token without rights”", "Liste vide, ou « jeton sans droits »"), [
                .paragraph(t("Privilege Separation is ticked and the token has no permission of its own, or its user has none: the token's rights are the intersection of both. Grant PVEAuditor on / to the user and to the token.", "Privilege Separation est cochée et le jeton n’a pas de permission propre, ou son utilisateur n’en a pas : les droits du jeton sont l’intersection des deux. Accordez PVEAuditor sur / à l’utilisateur et au jeton.")),
                .code("pveum acl modify / --roles PVEAuditor --users monitor@pve\npveum acl modify / --roles PVEAuditor --tokens 'monitor@pve!patchnode'"),
                .paragraph(t("An action refused with “insufficient rights” needs VM.PowerMgmt (the PatchNodePower role in Minimum rights).", "Une action refusée pour « droits insuffisants » demande VM.PowerMgmt (le rôle PatchNodePower de Droits minimaux).")),
                .paragraph(t("A guest vanished after a role was granted on its path (/vms/<id>, /vms): that ACL replaced PVEAuditor inherited from /. Grant 'PVEAuditor,<role>' on that path instead, then check:", "Un invité a disparu après un rôle accordé sur son chemin (/vms/<id>, /vms) : cette ACL a remplacé PVEAuditor hérité de /. Accordez plutôt 'PVEAuditor,<rôle>' sur ce chemin, puis vérifiez :")),
                .code("pveum acl modify /vms/101 --roles 'PVEAuditor,PatchNodeConsole' --tokens 'monitor@pve!patchnode'\npveum user token permissions monitor@pve patchnode --path /vms/101"),
            ]),
            GuideTroubleshooting(.tokenRejected, t("Token rejected (401)", "Jeton refusé (401)"), [
                .bullets([
                    t("Paste the full value user@realm!tokenid=secret, with = before the secret.", "Collez la valeur complète utilisateur@realm!tokenid=secret, avec = avant le secret."),
                    t("The token may have expired (Expire field) or been deleted.", "Le jeton a pu expirer (champ Expire) ou être supprimé."),
                ]),
            ]),
            GuideTroubleshooting(nil, t("301 Moved Permanently", "301 Moved Permanently"), [
                .paragraph(t("The reverse proxy forwards in http to port 8006. Set Scheme to https on the proxy host.", "Le reverse proxy transfère en http vers le port 8006. Mettez le schéma https sur le proxy host.")),
            ]),
            GuideTroubleshooting(nil, t("Console: the token lacks the console privilege", "Console : le jeton n’a pas le droit console"), [
                .paragraph(t("Grant PatchNodeConsole on the guest (/vms/<id>) or PatchNodeNodeConsole on the node (/nodes/<node>), always with PVEAuditor, to the user and to the token (Minimum rights). PatchNode shows the exact commands to copy.", "Accordez PatchNodeConsole sur l’invité (/vms/<id>) ou PatchNodeNodeConsole sur le nœud (/nodes/<nœud>), toujours avec PVEAuditor, à l’utilisateur et au jeton (Droits minimaux). PatchNode affiche les commandes exactes à copier.")),
            ]),
            GuideTroubleshooting(nil, t("Console: Proxmox refused the token", "Console : Proxmox a refusé le jeton"), [
                .paragraph(t("Before Proxmox VE 9.1, consoles only accept a password session, not an API token. Update the nodes to 9.1 or later (apt full-upgrade).", "Avant Proxmox VE 9.1, les consoles n’acceptent qu’une session par mot de passe, pas un jeton API. Mettez les nœuds à jour en 9.1 ou plus récent (apt full-upgrade).")),
            ]),
            GuideTroubleshooting(nil, t(GuideLibrary.serialConsoleAnchor, "Console graphique seulement : ajouter un port série"), [
                .paragraph(t("A VM gets a text terminal in PatchNode when it has a serial port. Add one, enable a login on it inside the VM, then restart the VM:", "Une VM a un terminal texte dans PatchNode quand elle a un port série. Ajoutez-en un, activez une connexion dessus dans la VM, puis redémarrez la VM :")),
                .code("qm set 100 --serial0 socket\n# inside a Debian or Ubuntu VM:\nsystemctl enable --now serial-getty@ttyS0.service"),
                .paragraph(t("Without a serial port, PatchNode opens the VM's graphical console.", "Sans port série, PatchNode ouvre la console graphique de la VM.")),
            ]),
            GuideTroubleshooting(nil, t("Two nodes named the same (pve)", "Deux nœuds du même nom (pve)"), [
                .paragraph(t("Nodes outside a cluster are separate services: add each one as its own service. PatchNode shows the service name first so they stay distinct.", "Des nœuds hors cluster sont des services distincts : ajoutez-les chacun comme un service. PatchNode affiche le nom du service en premier pour les distinguer.")),
            ]),
        ]
    )

    static let proxmoxBackupServerGuide = Guide(
        topic: .service(.proxmoxBackupServer),
        title: t("Proxmox Backup Server", "Proxmox Backup Server"),
        summary: t("Datastores, latest backup of every guest, failed jobs.", "Datastores, dernière sauvegarde de chaque VM, tâches en échec."),
        sections: [
            GuideSection(.purpose, [
                .paragraph(t("PatchNode shows each datastore's space, the latest backup of every VM and container (in orange after two days) and recent backup, verify, prune and garbage collection tasks.", "PatchNode affiche l’espace de chaque datastore, la dernière sauvegarde de chaque VM et conteneur (en orange après deux jours) et les tâches récentes de sauvegarde, vérification, prune et garbage collection.")),
            ]),
            GuideSection(.setup, [
                .steps([
                    t("Configuration › Access Control › User Management › Add: user monitor, realm pbs (monitor@pbs).", "Configuration › Access Control › User Management › Add : utilisateur monitor, realm pbs (monitor@pbs)."),
                    t("API Token tab › Add: user monitor@pbs, Token Name patchnode. Copy the secret.", "Onglet API Token › Add : utilisateur monitor@pbs, Token Name patchnode. Copiez le secret."),
                    t("In PatchNode, paste user@realm!tokenid:secret — with a colon, unlike Proxmox VE.", "Dans PatchNode, collez utilisateur@realm!tokenid:secret — avec deux-points, contrairement à Proxmox VE."),
                ]),
                .code("monitor@pbs!patchnode:00000000-0000-0000-0000-000000000000"),
                .code("proxmox-backup-manager user create monitor@pbs\nproxmox-backup-manager user generate-token monitor@pbs patchnode"),
            ]),
            GuideSection(.rights, [
                .paragraph(t("Read-only: role Audit on /, for the user and the token (a token's rights are also limited by its user's). PatchNode has no action on PBS.", "Lecture seule : rôle Audit sur /, pour l’utilisateur et le jeton (les droits d’un jeton sont aussi limités par ceux de son utilisateur). PatchNode n’a aucune action sur PBS.")),
                .code("proxmox-backup-manager acl update / Audit --auth-id monitor@pbs\nproxmox-backup-manager acl update / Audit --auth-id 'monitor@pbs!patchnode'"),
            ]),
            GuideSection(.reverseProxy, [
                .paragraph(t("PBS listens in HTTPS on port 8007: forward with the https scheme.", "PBS écoute en HTTPS sur le port 8007 : transférez avec le schéma https.")),
                .code("Domain Names:  pbs.example.com\nScheme:        https\nForward Host:  192.0.2.12\nForward Port:  8007"),
            ]),
            GuideSection(.verify, [
                .code("read -rs PBS_TOKEN\ncurl -sS -H \"Authorization: PBSAPIToken=$PBS_TOKEN\" https://pbs.example.com/api2/json/admin/datastore"),
                .paragraph(t("You should see your datastores.", "Vous devez voir vos datastores.")),
            ]),
        ],
        troubleshooting: [
            GuideTroubleshooting(.insufficientRights, t("No datastore, or 403", "Aucun datastore, ou 403"), [
                .paragraph(t("Grant Audit on / to the user and the token. A datastore refused alone (per-datastore permissions) is shown without its details.", "Accordez Audit sur / à l’utilisateur et au jeton. Un datastore refusé seul (permissions par datastore) est affiché sans ses détails.")),
            ]),
            GuideTroubleshooting(.tokenRejected, t("Token rejected (401)", "Jeton refusé (401)"), [
                .paragraph(t("PBS uses a colon between the token ID and the secret: user@realm!tokenid:secret.", "PBS utilise deux-points entre l’ID du jeton et le secret : utilisateur@realm!tokenid:secret.")),
            ]),
        ]
    )
}
