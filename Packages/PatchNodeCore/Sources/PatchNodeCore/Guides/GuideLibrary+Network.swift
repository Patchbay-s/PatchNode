import Foundation

extension GuideLibrary {
    static let networkGuide = Guide(
        topic: .networkPrerequisites,
        title: t("Network prerequisites", "Prérequis réseau"),
        summary: t(
            "VPN, HTTPS reverse proxy, split DNS, LAN-only access and IPS allow-list.",
            "VPN, reverse proxy HTTPS, split DNS, accès réservé au LAN et liste blanche de l’IPS."
        ),
        sections: [
            GuideSection(.purpose, [
                .paragraph(t(
                    "PatchNode talks directly from your iPhone to your servers. Nothing goes through a server of ours, so your iPhone must reach them: at home on Wi-Fi, and elsewhere through a VPN.",
                    "PatchNode dialogue directement de votre iPhone vers vos serveurs. Rien ne passe par un serveur à nous : votre iPhone doit donc pouvoir les joindre, chez vous en Wi-Fi et ailleurs via un VPN."
                )),
                .bullets([
                    t("A VPN such as Tailscale or WireGuard for access from outside.", "Un VPN comme Tailscale ou WireGuard pour l’accès depuis l’extérieur."),
                    t("An HTTPS reverse proxy with a valid certificate in front of every service (PatchNode refuses plain HTTP and invalid certificates).", "Un reverse proxy HTTPS avec un certificat valide devant chaque service (PatchNode refuse le HTTP simple et les certificats invalides)."),
                    t("Split DNS so the same names work at home and through the VPN.", "Un split DNS pour que les mêmes noms fonctionnent chez vous et via le VPN."),
                    t("Access restricted to your LAN and VPN.", "Un accès réservé à votre LAN et à votre VPN."),
                    t("Your LAN and VPN ranges allow-listed in your IPS (CrowdSec, fail2ban).", "Vos plages LAN et VPN en liste blanche de votre IPS (CrowdSec, fail2ban)."),
                ]),
            ]),
            GuideSection(.setup, [
                .paragraph(t("1. VPN. With Tailscale, install it on the server running the reverse proxy and on the iPhone, then advertise your LAN as a subnet route:", "1. VPN. Avec Tailscale, installez-le sur le serveur du reverse proxy et sur l’iPhone, puis annoncez votre LAN comme route de sous-réseau :")),
                .code("sudo tailscale up --advertise-routes=192.0.2.0/24"),
                .steps([
                    t("In the Tailscale admin console, Machines › the server › Edit route settings: approve the route.", "Dans la console d’administration Tailscale, Machines › le serveur › Edit route settings : approuvez la route."),
                    t("On the iPhone, open the Tailscale app and connect.", "Sur l’iPhone, ouvrez l’app Tailscale et connectez-vous."),
                ]),
                .paragraph(t("2. Split DNS. Give every service a name in your domain (proxmox.example.invalid…) that resolves to the reverse proxy's LAN address, for example with an AdGuard Home or Pi-hole rewrite:", "2. Split DNS. Donnez à chaque service un nom dans votre domaine (proxmox.example.invalid…) qui pointe vers l’adresse LAN du reverse proxy, par exemple avec une réécriture AdGuard Home ou Pi-hole :")),
                .code("*.example.com → 192.0.2.10"),
                .paragraph(t("Then, in the Tailscale admin console, DNS › Nameservers › Add nameserver › Custom: your DNS server, restricted to your domain (Split DNS).", "Puis, dans la console Tailscale, DNS › Nameservers › Add nameserver › Custom : votre serveur DNS, limité à votre domaine (Split DNS).")),
                .paragraph(t("3. Certificate. A wildcard certificate for *.example.com from Let's Encrypt with a DNS challenge works without opening any port to the internet.", "3. Certificat. Un certificat wildcard *.example.com de Let’s Encrypt avec un challenge DNS fonctionne sans ouvrir de port sur internet.")),
            ]),
            GuideSection(.rights, [
                .paragraph(t("Give PatchNode dedicated accounts and tokens, read-only first. Add the rights for actions (start, stop, restart) only once reading works, and only on what you want to control.", "Donnez à PatchNode des comptes et jetons dédiés, en lecture seule d’abord. N’ajoutez les droits d’action (démarrer, arrêter, redémarrer) qu’une fois la lecture fonctionnelle, et seulement sur ce que vous voulez piloter.")),
                .paragraph(t("Tokens stay in the iPhone's Keychain (this device only) and are sent only to the service they belong to.", "Les jetons restent dans le trousseau de l’iPhone (cet appareil uniquement) et ne sont envoyés qu’au service auquel ils appartiennent.")),
            ]),
            GuideSection(.reverseProxy, [
                .paragraph(t("Restrict every proxy host to your LAN and VPN. In Nginx Proxy Manager: Access Lists › Add Access List › Access tab:", "Réservez chaque proxy host à votre LAN et à votre VPN. Dans Nginx Proxy Manager : Access Lists › Add Access List › onglet Access :")),
                .code("allow 192.0.2.0/24\nallow 100.64.0.0/10\ndeny all"),
                .paragraph(t("100.64.0.0/10 is Tailscale's range. Select this Access List on each proxy host. Other proxies (Traefik, Caddy) have an equivalent IP allow-list.", "100.64.0.0/10 est la plage de Tailscale. Choisissez cette Access List sur chaque proxy host. Les autres proxys (Traefik, Caddy) ont une liste blanche d’IP équivalente.")),
                .paragraph(t("Allow-list the same ranges in your IPS, so a wrong token (repeated 401/403) never bans your own phone. With CrowdSec:", "Mettez les mêmes plages en liste blanche de votre IPS, pour qu’un mauvais jeton (401/403 répétés) ne bannisse jamais votre propre téléphone. Avec CrowdSec :")),
                .code("# /etc/crowdsec/parsers/s02-enrich/my-whitelist.yaml\nname: me/lan-whitelist\ndescription: \"LAN and VPN\"\nwhitelist:\n  reason: \"LAN and VPN\"\n  cidr:\n    - \"192.0.2.0/24\"\n    - \"100.64.0.0/10\""),
                .code("sudo systemctl reload crowdsec"),
                .warning(t("Never expose these services directly to the internet: PatchNode doesn't need it.", "N’exposez jamais ces services directement sur internet : PatchNode n’en a pas besoin.")),
            ]),
            GuideSection(.verify, [
                .paragraph(t("From a computer on the VPN, check that the name resolves to the proxy and that the certificate is valid:", "Depuis un ordinateur sur le VPN, vérifiez que le nom pointe vers le proxy et que le certificat est valide :")),
                .code("dig +short proxmox.example.invalid\ncurl -sSI https://proxmox.example.invalid"),
                .paragraph(t("The first command must print the proxy's LAN address; the second must answer without a certificate error.", "La première commande doit afficher l’adresse LAN du proxy ; la seconde doit répondre sans erreur de certificat.")),
            ]),
        ],
        troubleshooting: [
            GuideTroubleshooting(nil, t("It works at home but not outside", "Ça marche chez moi mais pas dehors"), [
                .bullets([
                    t("Is the VPN connected on the iPhone?", "Le VPN est-il connecté sur l’iPhone ?"),
                    t("Is the subnet route approved in the Tailscale admin console?", "La route de sous-réseau est-elle approuvée dans la console Tailscale ?"),
                    t("Does split DNS answer through the VPN? Otherwise the name resolves to nothing, or to a public address.", "Le split DNS répond-il via le VPN ? Sinon le nom ne résout rien, ou une adresse publique."),
                    t("Does the Access List allow 100.64.0.0/10?", "L’Access List autorise-t-elle 100.64.0.0/10 ?"),
                ]),
            ]),
        ]
    )

    /// Entries used by every guide that has no specific one for the problem.
    static func genericTroubleshooting(for problem: GuideProblem) -> GuideTroubleshooting {
        switch problem {
        case .proxyBlocked:
            GuideTroubleshooting(.proxyBlocked, t("Access blocked by the reverse proxy (403 page)", "Accès bloqué par le reverse proxy (page 403)"), [
                .paragraph(t("The answer is an HTML 403 page: the reverse proxy refused the request before it reached the service. Your token isn't the cause.", "La réponse est une page HTML 403 : le reverse proxy a refusé la requête avant qu’elle n’atteigne le service. Votre jeton n’est pas en cause.")),
                .bullets([
                    t("VPN off: turn it on, then pull to refresh.", "VPN coupé : activez-le, puis tirez pour rafraîchir."),
                    t("Access List: allow your LAN and VPN ranges (100.64.0.0/10 for Tailscale).", "Access List : autorisez vos plages LAN et VPN (100.64.0.0/10 pour Tailscale)."),
                    t("Banned by CrowdSec or fail2ban: list and remove the decision, then allow-list your ranges (see Network prerequisites).", "Banni par CrowdSec ou fail2ban : listez et supprimez la décision, puis mettez vos plages en liste blanche (voir Prérequis réseau)."),
                ]),
                .code("sudo cscli decisions list\nsudo cscli decisions delete --ip 192.0.2.50"),
                .paragraph(t("PatchNode pauses the service and tries again after 30 s, 60 s, then every 2 minutes, to avoid being banned.", "PatchNode met le service en pause et réessaie après 30 s, 60 s puis toutes les 2 minutes, pour éviter un bannissement.")),
            ])
        case .tokenRejected:
            GuideTroubleshooting(.tokenRejected, t("Token or password rejected (401)", "Jeton ou mot de passe refusé (401)"), [
                .bullets([
                    t("Copy the token again: a missing character, a space or a line break is enough to break it.", "Recopiez le jeton : un caractère manquant, une espace ou un retour à la ligne suffit à le casser."),
                    t("Check it hasn't expired or been revoked in the service.", "Vérifiez qu’il n’a pas expiré ni été révoqué dans le service."),
                    t("Check it with curl (Verify section of the service's guide).", "Vérifiez-le avec curl (section Vérification du guide du service)."),
                ]),
                .paragraph(t("Requests stay paused until you pull to refresh, so a wrong token isn't retried and can't get your IP banned. To change it: Settings › the service › enter the new token.", "Les requêtes restent en pause jusqu’au « tirer pour rafraîchir » : un mauvais jeton n’est pas renvoyé et ne peut pas faire bannir votre IP. Pour le changer : Réglages › le service › saisissez le nouveau jeton.")),
            ])
        case .insufficientRights:
            GuideTroubleshooting(.insufficientRights, t("Insufficient rights (403 from the service)", "Droits insuffisants (403 du service)"), [
                .paragraph(t("The token is valid but not allowed to read this information. Grant the read-only role described in the Minimum rights section of the service's guide.", "Le jeton est valide mais n’a pas le droit de lire ces informations. Accordez le rôle en lecture seule décrit dans la section Droits minimaux du guide du service.")),
            ])
        case .unreachable:
            GuideTroubleshooting(.unreachable, t("Service unreachable", "Service injoignable"), [
                .bullets([
                    t("VPN connected? At home, is the iPhone on your Wi-Fi?", "VPN connecté ? Chez vous, l’iPhone est-il sur votre Wi-Fi ?"),
                    t("Does the name resolve? A typo in the URL gives the same error.", "Le nom est-il résolu ? Une faute dans l’URL donne la même erreur."),
                    t("Is the certificate valid for this name? PatchNode refuses invalid and self-signed certificates.", "Le certificat est-il valide pour ce nom ? PatchNode refuse les certificats invalides et autosignés."),
                    t("Is the reverse proxy up, and the service behind it?", "Le reverse proxy est-il démarré, et le service derrière lui ?"),
                ]),
                .code("curl -sSI https://service.example.com"),
            ])
        case .misdirected:
            GuideTroubleshooting(.misdirected, t("421 Misdirected Request", "421 Misdirected Request"), [
                .paragraph(t("Several services share one reverse proxy and one wildcard certificate: iOS may reuse an HTTP/2 connection opened for another name, and the proxy answers 421. PatchNode retries once on a new connection automatically.", "Plusieurs services partagent un reverse proxy et un certificat wildcard : iOS peut réutiliser une connexion HTTP/2 ouverte pour un autre nom, et le proxy répond 421. PatchNode réessaie automatiquement une fois sur une nouvelle connexion.")),
                .paragraph(t("If it keeps happening, Settings › Diagnostics shows the requests (protocol, connection reused). That log contains your services' names and API paths: read it before sharing it with anyone.", "Si cela persiste, Réglages › Diagnostic montre les requêtes (protocole, connexion réutilisée). Ce journal contient les noms de vos services et les chemins d’API : relisez-le avant de le partager.")),
            ])
        case .timeout:
            GuideTroubleshooting(.timeout, t("The service answers too slowly (timeout)", "Le service répond trop lentement (délai dépassé)"), [
                .paragraph(t("PatchNode waits 10 seconds per request. A slow VPN route, an overloaded host or a heavy endpoint can exceed it.", "PatchNode attend 10 secondes par requête. Une route VPN lente, un hôte surchargé ou un endpoint lourd peuvent dépasser ce délai.")),
                .bullets([
                    t("Try again on Wi-Fi at home to rule out the VPN.", "Réessayez en Wi-Fi chez vous pour écarter le VPN."),
                    t("Toggle the VPN off and on: PatchNode then opens new connections.", "Coupez puis rallumez le VPN : PatchNode ouvre alors de nouvelles connexions."),
                    t("Check the host's load.", "Vérifiez la charge de l’hôte."),
                ]),
            ])
        }
    }
}
