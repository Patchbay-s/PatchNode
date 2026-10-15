import Foundation

extension GuideLibrary {
    private static let basicAuthProxy: [GuideBlock] = [
        .paragraph(t("Prometheus and Alertmanager have no token. Keep them on your LAN and VPN only; for a password, add an Access List with a user in Nginx Proxy Manager (Authorization tab, Satisfy All) and enter the same user and password in PatchNode. Without authentication, leave both fields empty.", "Prometheus et Alertmanager n’ont pas de jeton. Gardez-les sur votre LAN et votre VPN uniquement ; pour un mot de passe, ajoutez une Access List avec un utilisateur dans Nginx Proxy Manager (onglet Authorization, Satisfy All) et saisissez le même utilisateur et mot de passe dans PatchNode. Sans authentification, laissez les deux champs vides.")),
    ]

    static let prometheusGuide = Guide(
        topic: .service(.prometheus),
        title: t("Prometheus", "Prometheus"),
        summary: t("Targets down and your own PromQL charts.", "Cibles en panne et vos propres graphiques PromQL."),
        sections: [
            GuideSection(.purpose, [
                .paragraph(t("PatchNode lists the scrape targets with those down first, and draws the PromQL queries you save as charts (CPU, memory, disks…).", "PatchNode liste les cibles de collecte, celles en panne en tête, et trace sous forme de graphiques les requêtes PromQL que vous enregistrez (CPU, mémoire, disques…).")),
            ]),
            GuideSection(.setup, [
                .paragraph(t("Nothing to create in Prometheus: PatchNode only reads its HTTP API. Add a proxy host in front of it (below), then the URL in PatchNode.", "Rien à créer dans Prometheus : PatchNode lit seulement son API HTTP. Ajoutez un proxy host devant (ci-dessous), puis l’URL dans PatchNode.")),
            ]),
            GuideSection(.rights, [
                .paragraph(t("The HTTP API is read-only by default. Don't start Prometheus with --web.enable-admin-api or --web.enable-lifecycle behind this proxy host.", "L’API HTTP est en lecture seule par défaut. Ne lancez pas Prometheus avec --web.enable-admin-api ni --web.enable-lifecycle derrière ce proxy host.")),
            ]),
            GuideSection(.reverseProxy, basicAuthProxy + [
                .code("Domain Names:  prometheus.example.com\nScheme:        http\nForward Host:  192.0.2.30\nForward Port:  9090"),
            ]),
            GuideSection(.verify, [
                .code("curl -sS -u monitor https://prometheus.example.com/api/v1/status/buildinfo"),
                .paragraph(t("Without authentication, drop -u monitor.", "Sans authentification, retirez -u monitor.")),
            ]),
        ],
        troubleshooting: [
            GuideTroubleshooting(nil, t("A saved chart shows an error", "Un graphique enregistré affiche une erreur"), [
                .paragraph(t("PatchNode shows Prometheus's own message. Test the query in Prometheus's web interface (Graph) first, then paste it again.", "PatchNode affiche le message de Prometheus. Testez d’abord la requête dans l’interface web de Prometheus (Graph), puis recollez-la.")),
            ]),
        ]
    )

    static let alertmanagerGuide = Guide(
        topic: .service(.alertmanager),
        title: t("Alertmanager", "Alertmanager"),
        summary: t("Active alerts sorted by severity.", "Alertes en cours triées par gravité."),
        sections: [
            GuideSection(.purpose, [
                .paragraph(t("PatchNode shows active alerts sorted by severity (critical, warning, info) with a badge on the tab. Silenced and inhibited alerts are left out.", "PatchNode affiche les alertes en cours triées par gravité (critique, avertissement, info) avec un badge sur l’onglet. Les alertes silencieuses ou inhibées sont exclues.")),
            ]),
            GuideSection(.setup, [
                .paragraph(t("Nothing to create: PatchNode reads the v2 API. Set a severity label on your alert rules (critical, warning, info) to get them sorted.", "Rien à créer : PatchNode lit l’API v2. Mettez un label severity sur vos règles d’alerte (critical, warning, info) pour qu’elles soient triées.")),
                .code("labels:\n  severity: critical"),
            ]),
            GuideSection(.rights, [
                .paragraph(t("The API also allows creating silences: keep Alertmanager on your LAN and VPN only, behind authentication. PatchNode only reads.", "L’API permet aussi de créer des silences : gardez Alertmanager sur votre LAN et votre VPN uniquement, derrière une authentification. PatchNode ne fait que lire.")),
            ]),
            GuideSection(.reverseProxy, basicAuthProxy + [
                .code("Domain Names:  alertmanager.example.com\nScheme:        http\nForward Host:  192.0.2.30\nForward Port:  9093"),
            ]),
            GuideSection(.verify, [
                .code("curl -sS -u monitor https://alertmanager.example.com/api/v2/alerts"),
            ]),
        ],
        troubleshooting: [
            GuideTroubleshooting(nil, t("An alert is missing", "Une alerte manque"), [
                .paragraph(t("Silenced and inhibited alerts are not shown. Check Alertmanager's web interface (Silences).", "Les alertes silencieuses et inhibées ne sont pas affichées. Vérifiez l’interface web d’Alertmanager (Silences).")),
            ]),
        ]
    )

    static let grafanaGuide = Guide(
        topic: .service(.grafana),
        title: t("Grafana", "Grafana"),
        summary: t("Dashboards and Grafana alerts.", "Tableaux de bord et alertes Grafana."),
        sections: [
            GuideSection(.purpose, [
                .paragraph(t("PatchNode lists your dashboards (they open in an embedded browser where you sign in as usual) and shows Grafana's unified alerting alerts with the others.", "PatchNode liste vos tableaux de bord (ils s’ouvrent dans un navigateur intégré où vous vous connectez comme d’habitude) et affiche les alertes de l’alerting unifié de Grafana avec les autres.")),
            ]),
            GuideSection(.setup, [
                .steps([
                    t("Administration › Users and access › Service accounts › Add service account: name patchnode, role Viewer.", "Administration › Users and access › Service accounts › Add service account : nom patchnode, rôle Viewer."),
                    t("Add service account token, no expiry or a long one. Copy it (glsa_…).", "Add service account token, sans expiration ou longue. Copiez-le (glsa_…)."),
                    t("In PatchNode, paste the token.", "Dans PatchNode, collez le jeton."),
                ]),
            ]),
            GuideSection(.rights, [
                .paragraph(t("Role Viewer: it reads dashboards and alerts, and can't change anything. The token is never put in a dashboard URL.", "Rôle Viewer : il lit les tableaux de bord et les alertes, et ne peut rien modifier. Le jeton n’est jamais placé dans l’URL d’un tableau de bord.")),
            ]),
            GuideSection(.reverseProxy, [
                .code("Domain Names:  grafana.example.com\nScheme:        http\nForward Host:  192.0.2.31\nForward Port:  3000\nWebsockets:    on"),
                .paragraph(t("Set root_url in grafana.ini to your public name, so links and sign-in redirect correctly:", "Réglez root_url dans grafana.ini sur votre nom public, pour que les liens et la connexion redirigent correctement :")),
                .code("[server]\nroot_url = https://grafana.example.com/"),
            ]),
            GuideSection(.verify, [
                .code("read -rs GRAFANA_TOKEN\ncurl -sS -H \"Authorization: Bearer $GRAFANA_TOKEN\" \"https://grafana.example.com/api/search?limit=5\""),
            ]),
        ],
        troubleshooting: [
            GuideTroubleshooting(.tokenRejected, t("Token rejected (401)", "Jeton refusé (401)"), [
                .paragraph(t("Use a service account token (glsa_…), not an API key from an older Grafana nor your password.", "Utilisez un jeton de service account (glsa_…), pas une clé d’API d’un ancien Grafana ni votre mot de passe.")),
            ]),
            GuideTroubleshooting(nil, t("A dashboard asks to sign in", "Un tableau de bord demande de se connecter"), [
                .paragraph(t("That's expected: the embedded browser uses your own Grafana session, separate from the token. The session is cleared when PatchNode goes to the background.", "C’est normal : le navigateur intégré utilise votre propre session Grafana, distincte du jeton. La session est effacée quand PatchNode passe en arrière-plan.")),
            ]),
        ]
    )

    static let uptimeKumaGuide = Guide(
        topic: .service(.uptimeKuma),
        title: t("Uptime Kuma", "Uptime Kuma"),
        summary: t("Monitors of a status page, with uptime and latest heartbeats.", "Sondes d’une page de statut, avec disponibilité et derniers battements."),
        sections: [
            GuideSection(.purpose, [
                .paragraph(t("PatchNode reads a public status page of Uptime Kuma: each monitor's state, 24-hour uptime and latest heartbeats. A monitor down becomes an alert.", "PatchNode lit une page de statut publique d’Uptime Kuma : l’état de chaque sonde, sa disponibilité sur 24 heures et ses derniers battements. Une sonde en panne devient une alerte.")),
            ]),
            GuideSection(.setup, [
                .steps([
                    t("In Uptime Kuma, Status Pages › New Status Page: a name and a slug, e.g. homelab.", "Dans Uptime Kuma, Status Pages › New Status Page : un nom et un slug, ex. homelab."),
                    t("Add the monitors to show, then Save.", "Ajoutez les sondes à afficher, puis Save."),
                    t("In PatchNode, enter the status page's URL, ending with /status/<slug>. No token.", "Dans PatchNode, saisissez l’URL de la page de statut, terminée par /status/<slug>. Aucun jeton."),
                ]),
                .code("https://status.example.com/status/homelab"),
            ]),
            GuideSection(.rights, [
                .paragraph(t("Nothing to grant: only the monitors placed on this page are read. PatchNode has no action on Uptime Kuma.", "Rien à accorder : seules les sondes placées sur cette page sont lues. PatchNode n’a aucune action sur Uptime Kuma.")),
            ]),
            GuideSection(.reverseProxy, [
                .code("Domain Names:  status.example.com\nScheme:        http\nForward Host:  192.0.2.32\nForward Port:  3001\nWebsockets:    on"),
            ]),
            GuideSection(.verify, [
                .code("curl -sS https://status.example.com/api/status-page/homelab"),
            ]),
        ],
        troubleshooting: [
            GuideTroubleshooting(nil, t("“Enter the status page URL”", "« Saisissez l’URL de la page de statut »"), [
                .paragraph(t("The URL must end with /status/<slug> — the slug chosen when creating the status page, not the dashboard URL.", "L’URL doit se terminer par /status/<slug> — le slug choisi à la création de la page de statut, pas l’URL du tableau de bord.")),
            ]),
        ]
    )
}
