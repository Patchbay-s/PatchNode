import Foundation

extension GuideLibrary {
    static let tailscaleGuide = Guide(
        topic: .service(.tailscale),
        title: t("Tailscale", "Tailscale"),
        summary: t("Devices of your tailnet: online, offline, keys about to expire.", "Appareils de votre tailnet : en ligne, hors ligne, clés bientôt expirées."),
        sections: [
            GuideSection(.purpose, [
                .paragraph(t("PatchNode lists your tailnet's devices: online or last seen, address, OS, and flags those offline for more than a day, keys expiring within 14 days and devices waiting for approval.", "PatchNode liste les appareils de votre tailnet : en ligne ou vu pour la dernière fois, adresse, OS, et signale ceux hors ligne depuis plus d’un jour, les clés qui expirent sous 14 jours et les appareils en attente d’approbation.")),
                .paragraph(t("It's the only service reached outside your private network: api.tailscale.com.", "C’est le seul service joint en dehors de votre réseau privé : api.tailscale.com.")),
            ]),
            GuideSection(.setup, [
                .steps([
                    t("In the Tailscale admin console: Settings › Trust credentials (formerly OAuth clients) › Generate OAuth client.", "Dans la console d’administration Tailscale : Settings › Trust credentials (anciennement OAuth clients) › Generate OAuth client."),
                    t("Scopes: Devices › Core, Read only. Nothing else.", "Scopes : Devices › Core, en lecture (Read). Rien d’autre."),
                    t("Copy the client ID and the client secret (tskey-client-…), shown once.", "Copiez le client ID et le client secret (tskey-client-…), affichés une fois."),
                    t("In PatchNode, enter client-id:client-secret. No URL to type.", "Dans PatchNode, saisissez client-id:client-secret. Aucune URL à saisir."),
                ]),
                .code("kAbCdEf1CNTRL:tskey-client-kAbCdEf1CNTRL-xxxxxxxx"),
                .warning(t("Don't use the API access keys of Settings › Keys: they expire within 90 days and carry all your rights. The OAuth client is limited to reading devices, and PatchNode exchanges it for a one-hour token kept in memory only.", "N’utilisez pas les clés d’accès API de Settings › Keys : elles expirent sous 90 jours et portent tous vos droits. Le client OAuth est limité à la lecture des appareils, et PatchNode l’échange contre un jeton d’une heure gardé uniquement en mémoire.")),
            ]),
            GuideSection(.rights, [
                .paragraph(t("Devices › Core › Read only. PatchNode has no action on Tailscale.", "Devices › Core › en lecture seule. PatchNode n’a aucune action sur Tailscale.")),
            ]),
            GuideSection(.reverseProxy, [
                .paragraph(t("None: PatchNode calls api.tailscale.com directly, over HTTPS.", "Aucun : PatchNode appelle directement api.tailscale.com, en HTTPS.")),
            ]),
            GuideSection(.verify, [
                .code("read -r TS_ID\nread -rs TS_SECRET\nTOKEN=$(printf 'client_id=%s&client_secret=%s' \"$TS_ID\" \"$TS_SECRET\" | curl -sS -d @- https://api.tailscale.com/api/v2/oauth/token | sed -E 's/.*\"access_token\":\"([^\"]+)\".*/\\1/')\ncurl -sS -H \"Authorization: Bearer $TOKEN\" https://api.tailscale.com/api/v2/tailnet/-/devices"),
            ]),
        ],
        troubleshooting: [
            GuideTroubleshooting(.tokenRejected, t("Client rejected (401)", "Client refusé (401)"), [
                .bullets([
                    t("Enter client-id:client-secret, separated by a colon.", "Saisissez client-id:client-secret, séparés par deux-points."),
                    t("The client may have been revoked in Settings › Trust credentials.", "Le client a pu être révoqué dans Settings › Trust credentials."),
                ]),
            ]),
            GuideTroubleshooting(.insufficientRights, t("403: scope missing", "403 : scope manquant"), [
                .paragraph(t("Generate a new client with Devices › Core › Read.", "Générez un nouveau client avec Devices › Core › Read.")),
            ]),
            GuideTroubleshooting(.unreachable, t("api.tailscale.com unreachable", "api.tailscale.com injoignable"), [
                .paragraph(t("This service goes through the internet, not your VPN: check the iPhone's internet access, or a DNS filter blocking tailscale.com.", "Ce service passe par internet, pas par votre VPN : vérifiez l’accès internet de l’iPhone, ou un filtre DNS qui bloquerait tailscale.com.")),
            ]),
        ]
    )

    static let crowdSecGuide = Guide(
        topic: .service(.crowdSec),
        title: t("CrowdSec", "CrowdSec"),
        summary: t("Active bans of your Local API.", "Bannissements en cours de votre Local API."),
        sections: [
            GuideSection(.purpose, [
                .paragraph(t("PatchNode lists active decisions (bans and captchas) from local detections and manual bans: IP or range, scenario, time left. Community blocklists aren't listed.", "PatchNode liste les décisions en cours (bannissements et captchas) issues des détections locales et des bans manuels : IP ou plage, scénario, temps restant. Les listes communautaires ne sont pas listées.")),
            ]),
            GuideSection(.setup, [
                .paragraph(t("On the CrowdSec host, create a bouncer key for PatchNode:", "Sur l’hôte CrowdSec, créez une clé de bouncer pour PatchNode :")),
                .code("sudo cscli bouncers add patchnode"),
                .paragraph(t("Copy the key (shown once) and paste it in PatchNode.", "Copiez la clé (affichée une fois) et collez-la dans PatchNode.")),
                .paragraph(t("The Local API listens on 127.0.0.1:8080 by default, and cscli and the local bouncers use that address. Simplest: a reverse proxy on the same host forwards to 127.0.0.1:8080. Otherwise listen on all addresses and let only the proxy through the firewall:", "La Local API écoute sur 127.0.0.1:8080 par défaut, et cscli et les bouncers locaux utilisent cette adresse. Le plus simple : un reverse proxy sur le même hôte transfère vers 127.0.0.1:8080. Sinon, écoutez sur toutes les adresses et ne laissez passer que le proxy dans le pare-feu :")),
                .code("# /etc/crowdsec/config.yaml\napi:\n  server:\n    listen_uri: 0.0.0.0:8080"),
                .code("sudo iptables -I INPUT -p tcp --dport 8080 ! -s 192.0.2.10 ! -i lo -j DROP\nsudo systemctl restart crowdsec\nsudo cscli lapi status"),
                .warning(t("Don't set listen_uri to the LAN address alone: cscli and the bouncers on 127.0.0.1 would lose the API and bans would stop being applied. cscli lapi status must still answer.", "Ne mettez pas listen_uri sur la seule adresse LAN : cscli et les bouncers sur 127.0.0.1 perdraient l’API et les bannissements ne seraient plus appliqués. cscli lapi status doit toujours répondre.")),
            ]),
            GuideSection(.rights, [
                .paragraph(t("A bouncer key only reads decisions: it can't add or remove any. PatchNode has no action on CrowdSec.", "Une clé de bouncer ne fait que lire les décisions : elle ne peut ni en ajouter ni en supprimer. PatchNode n’a aucune action sur CrowdSec.")),
            ]),
            GuideSection(.reverseProxy, [
                .code("Domain Names:  crowdsec.example.com\nScheme:        http\nForward Host:  127.0.0.1 (same host) or 192.0.2.17\nForward Port:  8080"),
                .warning(t("Allow-list your LAN and VPN in CrowdSec (see Network prerequisites), so a wrong key never bans your own phone.", "Mettez votre LAN et votre VPN en liste blanche de CrowdSec (voir Prérequis réseau), pour qu’une mauvaise clé ne bannisse jamais votre propre téléphone.")),
            ]),
            GuideSection(.verify, [
                .code("read -rs CS_KEY\ncurl -sS -H \"X-Api-Key: $CS_KEY\" https://crowdsec.example.com/v1/decisions"),
                .paragraph(t("null means no active ban: that's a valid answer.", "null signifie aucun bannissement en cours : c’est une réponse valide.")),
            ]),
        ],
        troubleshooting: [
            GuideTroubleshooting(.tokenRejected, t("Key rejected (403 from CrowdSec)", "Clé refusée (403 de CrowdSec)"), [
                .paragraph(t("CrowdSec answers 403 for an unknown key. Check it with cscli bouncers list, or create a new one.", "CrowdSec répond 403 pour une clé inconnue. Vérifiez-la avec cscli bouncers list, ou créez-en une nouvelle.")),
                .code("sudo cscli bouncers list"),
            ]),
            GuideTroubleshooting(nil, t("The list is empty", "La liste est vide")
                , [.paragraph(t("No active local ban: the API answers null. PatchNode shows “No active bans”.", "Aucun bannissement local en cours : l’API répond null. PatchNode affiche « Aucun bannissement actif »."))]),
        ]
    )

    static let nginxProxyManagerGuide = Guide(
        topic: .service(.nginxProxyManager),
        title: t("Nginx Proxy Manager", "Nginx Proxy Manager"),
        summary: t("Proxy hosts, certificates, and hosts refused by nginx.", "Proxy hosts, certificats, et hôtes refusés par nginx."),
        sections: [
            GuideSection(.purpose, [
                .paragraph(t("PatchNode lists your proxy hosts: enabled or not, destination, certificate, and in red those nginx refused (bad upstream, configuration error).", "PatchNode liste vos proxy hosts : activés ou non, destination, certificat, et en rouge ceux que nginx a refusés (upstream introuvable, erreur de configuration).")),
            ]),
            GuideSection(.setup, [
                .steps([
                    t("Users › Add User: full name PatchNode, e-mail e.g. patchnode@example.com, not an administrator.", "Users › Add User : nom PatchNode, e-mail ex. patchnode@example.com, pas administrateur."),
                    t("Permissions: Proxy Hosts › View Only, everything else Hidden.", "Permissions : Proxy Hosts › View Only, tout le reste Hidden."),
                    t("Set a password for this user.", "Définissez un mot de passe pour cet utilisateur."),
                    t("In PatchNode, enter the e-mail and the password. PatchNode gets a session token from them, kept in memory only.", "Dans PatchNode, saisissez l’e-mail et le mot de passe. PatchNode en tire un jeton de session gardé uniquement en mémoire."),
                ]),
            ]),
            GuideSection(.rights, [
                .paragraph(t("View Only on Proxy Hosts is enough. PatchNode has no action on Nginx Proxy Manager.", "View Only sur Proxy Hosts suffit. PatchNode n’a aucune action sur Nginx Proxy Manager.")),
            ]),
            GuideSection(.reverseProxy, [
                .paragraph(t("The admin interface (port 81) can be published by Nginx Proxy Manager itself, restricted to your LAN and VPN:", "L’interface d’administration (port 81) peut être publiée par Nginx Proxy Manager lui-même, réservée à votre LAN et votre VPN :")),
                .code("Domain Names:  npm.example.com\nScheme:        http\nForward Host:  192.0.2.10\nForward Port:  81"),
            ]),
            GuideSection(.verify, [
                .code("read -r NPM_USER\nread -rs NPM_PASS\nprintf '{\"identity\":\"%s\",\"secret\":\"%s\"}' \"$NPM_USER\" \"$NPM_PASS\" | curl -sS -H 'Content-Type: application/json' -d @- https://npm.example.com/api/tokens"),
                .paragraph(t("You should get a token in return.", "Vous devez recevoir un jeton en retour.")),
            ]),
        ],
        troubleshooting: [
            GuideTroubleshooting(.tokenRejected, t("E-mail or password rejected", "E-mail ou mot de passe refusé"), [
                .paragraph(t("Use the dedicated user's e-mail and password. Two-factor authentication isn't supported: use a user without it.", "Utilisez l’e-mail et le mot de passe de l’utilisateur dédié. L’authentification à deux facteurs n’est pas prise en charge : utilisez un utilisateur sans elle.")),
            ]),
            GuideTroubleshooting(.insufficientRights, t("No proxy host listed", "Aucun proxy host listé"), [
                .paragraph(t("Give the user View Only on Proxy Hosts (Users › the user › Permissions).", "Donnez à l’utilisateur View Only sur Proxy Hosts (Users › l’utilisateur › Permissions).")),
            ]),
        ]
    )

    static let adGuardHomeGuide = Guide(
        topic: .service(.adGuardHome),
        title: t("AdGuard Home", "AdGuard Home"),
        summary: t("Protection state and DNS statistics.", "État de la protection et statistiques DNS."),
        sections: [
            GuideSection(.purpose, [
                .paragraph(t("PatchNode shows whether protection is on, the number of queries and the share blocked, the average processing time, and the most queried and blocked domains.", "PatchNode indique si la protection est active, le nombre de requêtes et la part bloquée, le temps moyen de traitement, et les domaines les plus demandés et bloqués.")),
            ]),
            GuideSection(.setup, [
                .paragraph(t("Add a dedicated user to the users section of AdGuardHome.yaml, with a bcrypt password hash, then restart AdGuard Home:", "Ajoutez un utilisateur dédié dans la section users d’AdGuardHome.yaml, avec un hash bcrypt du mot de passe, puis redémarrez AdGuard Home :")),
                .code("htpasswd -B -n patchnode"),
                .code("users:\n  - name: patchnode\n    password: $2y$05$…"),
                .paragraph(t("In PatchNode, enter this user name and password.", "Dans PatchNode, saisissez cet utilisateur et ce mot de passe.")),
            ]),
            GuideSection(.rights, [
                .warning(t("AdGuard Home has no read-only role: this user can change the DNS settings. Keep AdGuard Home reachable only through your LAN and VPN. PatchNode only reads.", "AdGuard Home n’a pas de rôle en lecture seule : cet utilisateur peut modifier les réglages DNS. Gardez AdGuard Home joignable uniquement via votre LAN et votre VPN. PatchNode ne fait que lire.")),
            ]),
            GuideSection(.reverseProxy, [
                .code("Domain Names:  adguard.example.com\nScheme:        http\nForward Host:  192.0.2.19\nForward Port:  80"),
            ]),
            GuideSection(.verify, [
                .code("curl -sS -u patchnode https://adguard.example.com/control/status"),
            ]),
        ],
        troubleshooting: [
            GuideTroubleshooting(.tokenRejected, t("User or password rejected", "Utilisateur ou mot de passe refusé"), [
                .paragraph(t("AdGuard Home compares with the bcrypt hash of AdGuardHome.yaml: generate it again, then restart AdGuard Home.", "AdGuard Home compare avec le hash bcrypt d’AdGuardHome.yaml : régénérez-le, puis redémarrez AdGuard Home.")),
            ]),
        ]
    )
}
