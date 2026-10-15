import Foundation

extension GuideLibrary {
    static let homeAssistantGuide = Guide(
        topic: .service(.homeAssistant),
        title: t("Home Assistant", "Home Assistant"),
        summary: t("The entities you choose, scenes and scripts.", "Les entités de votre choix, scènes et scripts."),
        sections: [
            GuideSection(.purpose, [
                .paragraph(t("PatchNode shows the sensors, lights and switches you pick, with their state, and can run the scenes and scripts you pick after a confirmation naming them.", "PatchNode affiche les capteurs, lumières et interrupteurs que vous choisissez, avec leur état, et peut lancer les scènes et scripts choisis après une confirmation qui les nomme.")),
            ]),
            GuideSection(.setup, [
                .steps([
                    t("Settings › People › Add person: a dedicated user patchnode, allowed to log in, not an administrator.", "Paramètres › Personnes › Ajouter une personne : un utilisateur dédié patchnode, autorisé à se connecter, non administrateur."),
                    t("Sign in as this user, then Profile › Security › Long-lived access tokens › Create token.", "Connectez-vous avec cet utilisateur, puis Profil › Sécurité › Jetons d’accès longue durée › Créer un jeton."),
                    t("Copy the token (shown once) and paste it in PatchNode.", "Copiez le jeton (affiché une fois) et collez-le dans PatchNode."),
                    t("In PatchNode, open Home Assistant › Choose entities.", "Dans PatchNode, ouvrez Home Assistant › Choisir les entités."),
                ]),
            ]),
            GuideSection(.rights, [
                .paragraph(t("A non-admin user can read states and call services, but not change the configuration. PatchNode only runs the scenes and scripts you pinned, after a confirmation.", "Un utilisateur non administrateur peut lire les états et appeler des services, mais pas modifier la configuration. PatchNode ne lance que les scènes et scripts épinglés, après confirmation.")),
            ]),
            GuideSection(.reverseProxy, [
                .code("Domain Names:  ha.example.com\nScheme:        http\nForward Host:  192.0.2.40\nForward Port:  8123\nWebsockets:    on"),
                .paragraph(t("Home Assistant must trust the proxy, in configuration.yaml:", "Home Assistant doit faire confiance au proxy, dans configuration.yaml :")),
                .code("http:\n  use_x_forwarded_for: true\n  trusted_proxies:\n    - 192.0.2.10"),
            ]),
            GuideSection(.verify, [
                .code("read -rs HA_TOKEN\ncurl -sS -H \"Authorization: Bearer $HA_TOKEN\" https://ha.example.com/api/"),
                .paragraph(t("The answer is {\"message\":\"API running.\"}.", "La réponse est {\"message\":\"API running.\"}.")),
            ]),
        ],
        troubleshooting: [
            GuideTroubleshooting(nil, t("400 Bad Request behind the proxy", "400 Bad Request derrière le proxy"), [
                .paragraph(t("Home Assistant refuses forwarded requests from an untrusted proxy: add use_x_forwarded_for and trusted_proxies (Reverse proxy section), then restart.", "Home Assistant refuse les requêtes transmises par un proxy non déclaré : ajoutez use_x_forwarded_for et trusted_proxies (section Reverse proxy), puis redémarrez.")),
            ]),
        ]
    )

    static let glancesGuide = Guide(
        topic: .service(.glances),
        title: t("Glances", "Glances"),
        summary: t("CPU, memory, load, disks and temperatures of a host.", "CPU, mémoire, charge, disques et températures d’un hôte."),
        sections: [
            GuideSection(.purpose, [
                .paragraph(t("PatchNode shows a host's CPU, memory and swap, load, file systems (orange above 85 %) and temperatures.", "PatchNode affiche le CPU, la mémoire et le swap, la charge, les systèmes de fichiers (orange au-delà de 85 %) et les températures d’un hôte.")),
            ]),
            GuideSection(.setup, [
                .paragraph(t("Run Glances in web server mode, for example with Docker. --disable-plugin processlist makes each refresh much lighter:", "Lancez Glances en mode serveur web, par exemple avec Docker. --disable-plugin processlist allège fortement chaque rafraîchissement :")),
                .code("docker run -d --name glances --restart unless-stopped --pid host \\\n  -p 192.0.2.50:61208:61208 \\\n  -e GLANCES_OPT=\"-w --disable-plugin processlist\" \\\n  nicolargo/glances:latest"),
            ]),
            GuideSection(.rights, [
                .paragraph(t("Glances only reads. With --password, it asks for a password (default user glances): enter the user and password in PatchNode; without it, leave both fields empty and rely on the Access List.", "Glances ne fait que lire. Avec --password, il demande un mot de passe (utilisateur par défaut glances) : saisissez l’utilisateur et le mot de passe dans PatchNode ; sans lui, laissez les deux champs vides et comptez sur l’Access List.")),
            ]),
            GuideSection(.reverseProxy, [
                .code("Domain Names:  glances.example.com\nScheme:        http\nForward Host:  192.0.2.50\nForward Port:  61208"),
            ]),
            GuideSection(.verify, [
                .code("curl -sS https://glances.example.com/api/4/cpu"),
                .paragraph(t("Glances 3 answers on /api/3/cpu; PatchNode tries both.", "Glances 3 répond sur /api/3/cpu ; PatchNode essaie les deux.")),
            ]),
        ],
        troubleshooting: [
            GuideTroubleshooting(.timeout, t("Slow refreshes or timeouts", "Rafraîchissements lents ou délais dépassés"), [
                .paragraph(t("The process list makes Glances's answer heavy. Start it with --disable-plugin processlist.", "La liste des processus alourdit la réponse de Glances. Lancez-le avec --disable-plugin processlist.")),
            ]),
        ]
    )
}
