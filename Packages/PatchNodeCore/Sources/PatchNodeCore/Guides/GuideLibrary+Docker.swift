import Foundation

extension GuideLibrary {
    static let dockerSocketProxyGuide = Guide(
        topic: .service(.dockerSocketProxy),
        title: t("Docker (socket proxy)", "Docker (socket proxy)"),
        summary: t("Containers of a Docker host through a read-only socket proxy.", "Conteneurs d’un hôte Docker via un socket proxy en lecture seule."),
        sections: [
            GuideSection(.purpose, [
                .paragraph(t("PatchNode lists the host's containers grouped by Compose project, with health, status, image, CPU and memory, logs, ports and volumes. With POST allowed, it can start, stop and restart a container.", "PatchNode liste les conteneurs de l’hôte groupés par projet Compose, avec santé, état, image, CPU et mémoire, journaux, ports et volumes. Si POST est autorisé, il peut démarrer, arrêter et redémarrer un conteneur.")),
                .warning(t("Never expose /var/run/docker.sock or the raw port 2375, even on your LAN: whoever reaches it is root on the host. Always go through a socket proxy and an authenticated reverse proxy.", "N’exposez jamais /var/run/docker.sock ni le port 2375 brut, même sur votre LAN : qui les atteint est root sur l’hôte. Passez toujours par un socket proxy et un reverse proxy authentifié.")),
            ]),
            GuideSection(.setup, [
                .paragraph(t("Run tecnativa/docker-socket-proxy without publishing any port, on a Docker network shared with the reverse proxy: only the proxy (and its authentication) can reach it.", "Lancez tecnativa/docker-socket-proxy sans publier de port, sur un réseau Docker partagé avec le reverse proxy : seul le proxy (et son authentification) peut l’atteindre.")),
                .code("docker network create proxy"),
                .code("services:\n  docker-socket-proxy:\n    image: tecnativa/docker-socket-proxy\n    restart: unless-stopped\n    environment:\n      CONTAINERS: 1\n      INFO: 1\n      POST: 0\n    volumes:\n      - /var/run/docker.sock:/var/run/docker.sock:ro\n    networks:\n      - proxy\nnetworks:\n  proxy:\n    external: true"),
                .paragraph(t("Attach Nginx Proxy Manager's container to the same proxy network. If the reverse proxy runs on another host, publish the port on the LAN address only (never 0.0.0.0) and let only the proxy's address through:", "Rattachez le conteneur de Nginx Proxy Manager au même réseau proxy. Si le reverse proxy tourne sur un autre hôte, publiez le port sur la seule adresse LAN (jamais 0.0.0.0) et ne laissez passer que l’adresse du proxy :")),
                .code("    ports:\n      - \"192.0.2.20:2375:2375\"\n\nsudo iptables -I DOCKER-USER -p tcp --dport 2375 ! -s 192.0.2.10 -j DROP"),
                .warning(t("CONTAINERS=1 also lets the reader see containers' environment variables, which often hold passwords. That's why the proxy must require authentication and stay on your LAN.", "CONTAINERS=1 permet aussi de lire les variables d’environnement des conteneurs, qui contiennent souvent des mots de passe. C’est pourquoi le proxy doit exiger une authentification et rester sur votre LAN.")),
            ]),
            GuideSection(.rights, [
                .bullets([
                    t("Reading: CONTAINERS=1, INFO=1, POST=0 (the default above).", "Lecture : CONTAINERS=1, INFO=1, POST=0 (la configuration ci-dessus)."),
                    t("Actions: POST=1, only while you need them. With POST=0, PatchNode shows “actions disabled”.", "Actions : POST=1, seulement le temps d’en avoir besoin. Avec POST=0, PatchNode affiche « actions désactivées »."),
                ]),
            ]),
            GuideSection(.reverseProxy, [
                .paragraph(t("In Nginx Proxy Manager, create an Access List with a user and password, and your LAN and VPN ranges:", "Dans Nginx Proxy Manager, créez une Access List avec un utilisateur et un mot de passe, et vos plages LAN et VPN :")),
                .steps([
                    t("Access Lists › Add Access List › Details: tick Satisfy All (both the password and the address are required).", "Access Lists › Add Access List › Details : cochez Satisfy All (le mot de passe et l’adresse sont tous deux exigés)."),
                    t("Authorization tab: add a user name and password.", "Onglet Authorization : ajoutez un utilisateur et un mot de passe."),
                    t("Access tab: allow 192.0.2.0/24 and 100.64.0.0/10, deny all.", "Onglet Access : autorisez 192.0.2.0/24 et 100.64.0.0/10, refusez le reste."),
                    t("Proxy host docker.example.com → http://docker-socket-proxy:2375 (same Docker network) with this Access List and your certificate.", "Proxy host docker.example.com → http://docker-socket-proxy:2375 (même réseau Docker) avec cette Access List et votre certificat."),
                    t("In PatchNode, enter the same user name and password in the two fields.", "Dans PatchNode, saisissez le même utilisateur et le même mot de passe dans les deux champs."),
                ]),
            ]),
            GuideSection(.verify, [
                .code("curl -sS -u monitor https://docker.example.com/version"),
                .paragraph(t("curl asks for the password, then prints the Docker version. Without the password you must get a 401.", "curl demande le mot de passe, puis affiche la version de Docker. Sans mot de passe, vous devez obtenir un 401.")),
            ]),
        ],
        troubleshooting: [
            GuideTroubleshooting(.tokenRejected, t("User or password rejected (401)", "Utilisateur ou mot de passe refusé (401)"), [
                .paragraph(t("Enter the user and password of the Access List's Authorization tab, not those of Nginx Proxy Manager's admin.", "Saisissez l’utilisateur et le mot de passe de l’onglet Authorization de l’Access List, pas ceux de l’administrateur de Nginx Proxy Manager.")),
            ]),
            GuideTroubleshooting(.insufficientRights, t("“Actions disabled” (403 from the socket proxy)", "« Actions désactivées » (403 du socket proxy)"), [
                .paragraph(t("The socket proxy refuses POST requests: set POST=1 and recreate the container, only while you need actions.", "Le socket proxy refuse les requêtes POST : mettez POST=1 et recréez le conteneur, seulement le temps d’avoir besoin des actions.")),
                .code("docker compose up -d docker-socket-proxy"),
            ]),
        ]
    )

    static let portainerGuide = Guide(
        topic: .service(.dockerPortainer),
        title: t("Portainer", "Portainer"),
        summary: t("Containers and stacks of every Docker environment managed by Portainer.", "Conteneurs et stacks de chaque environnement Docker géré par Portainer."),
        sections: [
            GuideSection(.purpose, [
                .paragraph(t("PatchNode lists every Docker environment of Portainer, their containers grouped by stack, with health, logs, CPU and memory, and can start, stop and restart a container.", "PatchNode liste chaque environnement Docker de Portainer et leurs conteneurs groupés par stack, avec santé, journaux, CPU et mémoire, et peut démarrer, arrêter et redémarrer un conteneur.")),
            ]),
            GuideSection(.setup, [
                .steps([
                    t("Administration › User-related › Users › Add user: a standard (non-admin) user, e.g. patchnode.", "Administration › User-related › Users › Add user : un utilisateur standard (non administrateur), ex. patchnode."),
                    t("Environments › your environment › Manage access: give this user access to the environments to monitor.", "Environments › votre environnement › Manage access : donnez à cet utilisateur l’accès aux environnements à surveiller."),
                    t("Sign in as this user, then My account › Access tokens › Add access token. Copy it (shown once).", "Connectez-vous avec cet utilisateur, puis My account › Access tokens › Add access token. Copiez-le (affiché une fois)."),
                    t("In PatchNode, use Portainer's own URL and paste the token.", "Dans PatchNode, utilisez l’URL de Portainer lui-même et collez le jeton."),
                ]),
            ]),
            GuideSection(.rights, [
                .paragraph(t("Business Edition: give the user the Read-only user role for reading only. Community Edition has no read-only role: a standard user can act on the containers of its environments.", "Business Edition : donnez à l’utilisateur le rôle Read-only user pour la lecture seule. La Community Edition n’a pas de rôle en lecture seule : un utilisateur standard peut agir sur les conteneurs de ses environnements.")),
            ]),
            GuideSection(.reverseProxy, [
                .code("Domain Names:  portainer.example.com\nScheme:        https\nForward Host:  192.0.2.23\nForward Port:  9443"),
                .paragraph(t("Port 9443 is Portainer's HTTPS port (scheme https); 9000 is plain HTTP (scheme http).", "Le port 9443 est le port HTTPS de Portainer (schéma https) ; 9000 est en HTTP simple (schéma http).")),
            ]),
            GuideSection(.verify, [
                .code("read -rs PORTAINER_TOKEN\ncurl -sS -H \"X-API-Key: $PORTAINER_TOKEN\" https://portainer.example.com/api/endpoints"),
                .paragraph(t("You should see your environments.", "Vous devez voir vos environnements.")),
            ]),
        ],
        troubleshooting: [
            GuideTroubleshooting(.tokenRejected, t("Access token rejected (401)", "Jeton d’accès refusé (401)"), [
                .paragraph(t("Create an access token (My account › Access tokens), not an Edge key or an API key of another tool.", "Créez un jeton d’accès (My account › Access tokens), pas une clé Edge ni une clé d’API d’un autre outil.")),
            ]),
            GuideTroubleshooting(nil, t("An environment shows as unreachable", "Un environnement apparaît injoignable")
                , [.paragraph(t("Portainer itself can't reach this environment (agent stopped, host off). Check it in Portainer's Environments page.", "Portainer lui-même n’atteint pas cet environnement (agent arrêté, hôte éteint). Vérifiez dans la page Environments de Portainer."))]),
        ]
    )
}
