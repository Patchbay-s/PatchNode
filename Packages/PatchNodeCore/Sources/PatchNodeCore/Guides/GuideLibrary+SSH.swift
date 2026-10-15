import Foundation

extension GuideLibrary {
    static let sshGuide = Guide(
        topic: .ssh,
        title: t("SSH terminal", "Terminal SSH"),
        summary: t("A dedicated user, this device's key, sudo or the docker group, risks and revocation.", "Utilisateur dédié, clé de l’appareil, sudo ou groupe docker, risques et révocation."),
        sections: [
            GuideSection(.purpose, [
                .paragraph(t("PatchNode opens SSH sessions to your own servers (Proxmox nodes, Docker hosts, containers, VMs) and, for a Docker host, runs docker compose in a project's folder. It connects only to the hosts you add, with a key generated on this device; nothing goes through a server of ours.", "PatchNode ouvre des sessions SSH vers vos propres serveurs (nœuds Proxmox, hôtes Docker, conteneurs, VM) et, pour un hôte Docker, lance docker compose dans le dossier d’un projet. Il ne se connecte qu’aux hôtes que vous ajoutez, avec une clé créée sur cet appareil ; rien ne passe par un serveur à nous.")),
                .paragraph(t("Every session asks for Face ID. The first connection to a host shows its fingerprint: compare it with the server's own before trusting it. PatchNode then refuses any other key for that host.", "Chaque session demande Face ID. La première connexion à un hôte affiche son empreinte : comparez-la avec celle du serveur avant de lui faire confiance. PatchNode refuse ensuite toute autre clé pour cet hôte.")),
            ]),
            GuideSection(.setup, [
                .steps([
                    t("On the server, create a dedicated user, for example patchnode.", "Sur le serveur, créez un utilisateur dédié, par exemple patchnode."),
                    t("In PatchNode, Settings › SSH: turn on the SSH terminal, open This device's public key and copy the authorized_keys line.", "Dans PatchNode, Réglages › SSH : activez le terminal SSH, ouvrez la clé publique de l’appareil et copiez la ligne authorized_keys."),
                    t("On the server, add the line to ~/.ssh/authorized_keys of that user (folder 700, file 600).", "Sur le serveur, ajoutez la ligne au ~/.ssh/authorized_keys de cet utilisateur (dossier 700, fichier 600)."),
                    t("Settings › SSH › Add a host: address, port, user. Link it to its Proxmox node or Docker host for the shortcuts.", "Réglages › SSH › Ajouter un hôte : adresse, port, utilisateur. Reliez-le à son nœud Proxmox ou à son hôte Docker pour les raccourcis."),
                ]),
                .code("sudo adduser --disabled-password patchnode\nsudo -u patchnode mkdir -p -m 700 /home/patchnode/.ssh\nsudo -u patchnode nano /home/patchnode/.ssh/authorized_keys   # paste the line\nsudo chmod 600 /home/patchnode/.ssh/authorized_keys"),
            ]),
            GuideSection(.rights, [
                .paragraph(t("Docker: add the user to the docker group so docker compose runs without sudo. The docker group is equivalent to root on that host: keep the key's from= restriction.", "Docker : ajoutez l’utilisateur au groupe docker pour lancer docker compose sans sudo. Le groupe docker équivaut à root sur cet hôte : gardez la restriction from= de la clé.")),
                .code("sudo usermod -aG docker patchnode"),
                .paragraph(t("Proxmox: “Enter the container” runs pct enter, which needs root. Connect as root with the key only (PermitRootLogin prohibit-password), or allow just that command with sudo (edit with visudo):", "Proxmox : « Entrer dans le conteneur » lance pct enter, qui demande root. Connectez-vous en root avec la clé seulement (PermitRootLogin prohibit-password), ou autorisez cette seule commande avec sudo (à modifier avec visudo) :")),
                .code("patchnode ALL=(root) NOPASSWD: /usr/sbin/pct enter *"),
                .warning(t("This rule is root in every container of the node, and nearly root on the node itself for a privileged container: keep it for a dedicated user, with the key's from= restriction.", "Cette règle équivaut à root dans tous les conteneurs du nœud, et presque à root sur le nœud lui-même pour un conteneur privilégié : réservez-la à un utilisateur dédié, avec la restriction from= de la clé.")),
                .warning(t("Prefer the key to a password. A password is asked only when the server refuses the key, used for that connection, and never stored.", "Préférez la clé à un mot de passe. Un mot de passe n’est demandé que si le serveur refuse la clé, sert à cette connexion et n’est jamais conservé.")),
            ]),
            GuideSection(.reverseProxy, [
                .bullets([
                    t("A session gives a full shell: whatever the user can do, PatchNode can do once unlocked.", "Une session donne un shell complet : tout ce que l’utilisateur peut faire, PatchNode le peut une fois déverrouillé."),
                    t("Keep SSH reachable only through your VPN, never exposed on the internet.", "Gardez SSH joignable uniquement par votre VPN, jamais exposé sur internet."),
                    t("from= limits where the key is accepted from; the no-…-forwarding options limit what it can do.", "from= limite d’où la clé est acceptée ; les options no-…-forwarding limitent ce qu’elle peut faire."),
                    t("Terminal content is never stored or logged; Diagnostics keep only the opening, closing, duration and error code.", "Le contenu du terminal n’est jamais conservé ni journalisé ; le Diagnostic ne garde que l’ouverture, la fermeture, la durée et le code d’erreur."),
                ]),
            ]),
            GuideSection(.verify, [
                .paragraph(t("Lost device, or a key you no longer trust: delete its line from authorized_keys on every server. The comment at the end of the line (patchnode-iPhone-…) tells which device it is.", "Appareil perdu, ou clé dont vous ne voulez plus : supprimez sa ligne d’authorized_keys sur chaque serveur. Le commentaire en fin de ligne (patchnode-iPhone-…) indique de quel appareil il s’agit.")),
                .code("sed -i '/patchnode-iPhone-20261011/d' ~/.ssh/authorized_keys"),
                .paragraph(t("Settings › SSH › Replace the key creates a new key and deletes the old one from this device.", "Réglages › SSH › Remplacer la clé crée une nouvelle clé et supprime l’ancienne de cet appareil.")),
                .paragraph(t("Host key changed? If you reinstalled the server, check its new fingerprint, then Settings › SSH › the host › Forget the host key.", "Clé d’hôte changée ? Si vous avez réinstallé le serveur, vérifiez sa nouvelle empreinte, puis Réglages › SSH › l’hôte › Oublier la clé d’hôte.")),
            ]),
        ],
        troubleshooting: [
            GuideTroubleshooting(nil, t("Connection refused or unreachable", "Connexion refusée ou injoignable"), [
                .paragraph(t("Check the VPN, the address and the port (22 by default), and that the SSH server runs on the host.", "Vérifiez le VPN, l’adresse et le port (22 par défaut), et que le serveur SSH tourne sur l’hôte.")),
                .code("systemctl status ssh"),
            ]),
            GuideTroubleshooting(nil, t("Key refused", "Clé refusée"), [
                .paragraph(t("The line is missing from that user's authorized_keys, or the file's permissions are too open (sshd then ignores it). The server's log says why:", "La ligne manque dans l’authorized_keys de cet utilisateur, ou les droits du fichier sont trop ouverts (sshd l’ignore alors). Le journal du serveur indique pourquoi :")),
                .code("journalctl -u ssh --since -10min"),
            ]),
        ]
    )
}
