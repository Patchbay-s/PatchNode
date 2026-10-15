#!/usr/bin/env python3
# Builds site/ (GitHub Pages, en/fr/es/de/it) from docs/appstore/privacy-policy.md and the
# texts below. Run after changing the privacy policy or support details.
import html, re, pathlib
repo = pathlib.Path(__file__).resolve().parent.parent
root = repo / 'site'
SUPPORT_URL = "https://github.com/Patchbay-s/PatchNode/issues"
# PatchNode is free software (GPL-3.0): every page links to its source code.
SOURCE_URL = "https://github.com/Patchbay-s/PatchNode"
SOURCE_BRANCH = "main"

LANGS = ['en', 'fr', 'es', 'de', 'it']
NAMES = {'en': 'English', 'fr': 'Français', 'es': 'Español', 'de': 'Deutsch', 'it': 'Italiano'}
L = {
 'en': dict(home='Home', privacy='Privacy', support='Support', policy='Privacy policy', updated='Last updated',
   source='Source code', license='License',
   footer='PatchNode is independent and not affiliated with Proxmox, Docker, Tailscale, Grafana or any supported product. No cookies or analytics on this site.'),
 'fr': dict(home='Accueil', privacy='Confidentialité', support='Assistance', policy='Politique de confidentialité', updated='Dernière mise à jour',
   source='Code source', license='Licence',
   footer='PatchNode est indépendant et n’est affilié ni à Proxmox, Docker, Tailscale, Grafana, ni aux produits pris en charge. Aucun cookie ni statistique d’usage sur ce site.'),
 'es': dict(home='Inicio', privacy='Privacidad', support='Soporte', policy='Política de privacidad', updated='Última actualización',
   source='Código fuente', license='Licencia',
   footer='PatchNode es una app independiente y no está afiliada a Proxmox, Docker, Tailscale, Grafana ni a ningún producto compatible. Sin cookies ni análisis de uso en este sitio.'),
 'de': dict(home='Start', privacy='Datenschutz', support='Support', policy='Datenschutzrichtlinie', updated='Zuletzt aktualisiert',
   source='Quellcode', license='Lizenz',
   footer='PatchNode ist unabhängig und nicht mit Proxmox, Docker, Tailscale, Grafana oder unterstützten Produkten verbunden. Keine Cookies und keine Nutzungsanalyse auf dieser Website.'),
 'it': dict(home='Home', privacy='Privacy', support='Assistenza', policy='Informativa sulla privacy', updated='Ultimo aggiornamento',
   source='Codice sorgente', license='Licenza',
   footer='PatchNode è indipendente e non è affiliata a Proxmox, Docker, Tailscale, Grafana né ai prodotti supportati. Nessun cookie né analisi d’uso su questo sito.'),
}

def href(from_lang, to_lang, name):
    up = '' if from_lang == 'en' else '../'
    return f'{up}{name}.html' if to_lang == 'en' else f'{up}{to_lang}/{name}.html'

def page(lang, name, title, body):
    l = L[lang]
    asset_prefix = '' if lang == 'en' else '../'
    current = ' aria-current="page"'
    nav = ''.join(f'<a href="{p}.html"{current if p==name else ""}>{l[k]}</a>' for p,k in [('index','home'),('privacy','privacy'),('support','support')])
    nav += ''.join(f'<a href="{href(lang, o, name)}" hreflang="{o}" lang="{o}">{NAMES[o]}</a>' for o in LANGS if o != lang)
    return f'''<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)} · PatchNode</title>
<meta name="description" content="PatchNode — HomeLab monitor for iPhone">
<link rel="icon" type="image/png" href="{asset_prefix}assets/favicon.png">
<link rel="stylesheet" href="{'' if lang=='en' else '../'}style.css">
</head>
<body>
<header><a class="brand" href="index.html"><img src="{asset_prefix}assets/patchnode-mark.png" alt="">PatchNode</a><nav>{nav}</nav></header>
<main>
{body}
</main>
<footer>{l['footer']}<br><a href="{SOURCE_URL}">{l['source']}</a> · <a href="{SOURCE_URL}/blob/{SOURCE_BRANCH}/LICENSE">{l['license']} GPL-3.0</a></footer>
</body>
</html>
'''

def md_to_html(md):
    out=[]; para=[]
    def flush():
        if para: out.append('<p>'+inline(' '.join(para))+'</p>'); para.clear()
    for line in md.splitlines():
        if not line.strip(): flush(); continue
        para.append(line.strip())
    flush()
    return '\n'.join(out)

def inline(t):
    t = html.escape(t, quote=False)
    t = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', t)
    t = re.sub(r'`(.+?)`', r'<code>\1</code>', t)
    return t

pp = open(repo / 'docs/appstore/privacy-policy.md').read()
policy = {}
for code, header in [('en', 'English'), ('fr', 'Français'), ('es', 'Español'), ('de', 'Deutsch'), ('it', 'Italiano')]:
    policy[code] = pp.split(f'\n## {header}\n', 1)[1].split('\n---', 1)[0].strip()
updated = re.search(r'Last updated / Dernière mise à jour : (\S+)', pp).group(1)

index = {
 'en': ('HomeLab monitor for iPhone', f'''<h1>Your HomeLab at a glance</h1>
<p class="lead">PatchNode keeps an eye on your self-hosted servers from your iPhone: Proxmox, Docker, alerts, backups, network, security and home automation. It talks directly to your servers, over your private network or VPN.</p>
<div class="card"><strong>Supported</strong>: Proxmox VE, Proxmox Backup Server, Docker (Portainer or a read-only socket proxy), Prometheus, Alertmanager, Grafana, Uptime Kuma, Tailscale, CrowdSec, Nginx Proxy Manager, AdGuard Home, Home Assistant, Glances.</div>
<h2>Consoles, SSH and Compose</h2>
<p>Open Proxmox consoles, an SSH terminal to your own servers (key created on the device, fingerprints pinned) and manage Docker Compose projects, on iPhone, iPad and Mac.</p>
<h2>Private by design</h2>
<ul><li>No account, no analytics, no advertising, no tracking.</li><li>Tokens stay in the iPhone's Keychain. Syncing your configuration, or your tokens through iCloud Keychain, is optional and off by default.</li><li>HTTPS only; actions always ask for confirmation and Face ID.</li></ul>
<h2>Try it without a server</h2>
<p>The built-in demo shows a complete sample HomeLab, generated on the device.</p>
<p><a href="support.html">Setup guides and support</a> · <a href="privacy.html">Privacy policy</a></p>'''),
 'fr': ('Supervisez votre HomeLab', f'''<h1>Votre HomeLab en un coup d’œil</h1>
<p class="lead">PatchNode surveille vos serveurs autohébergés depuis votre iPhone : Proxmox, Docker, alertes, sauvegardes, réseau, sécurité et domotique. L’app dialogue directement avec vos serveurs, via votre réseau privé ou votre VPN.</p>
<div class="card"><strong>Pris en charge</strong> : Proxmox VE, Proxmox Backup Server, Docker (Portainer ou socket proxy en lecture seule), Prometheus, Alertmanager, Grafana, Uptime Kuma, Tailscale, CrowdSec, Nginx Proxy Manager, AdGuard Home, Home Assistant, Glances.</div>
<h2>Consoles, SSH et Compose</h2>
<p>Ouvrez les consoles Proxmox, un terminal SSH vers vos propres serveurs (clé créée sur l’appareil, empreintes épinglées) et gérez vos projets Docker Compose, sur iPhone, iPad et Mac.</p>
<h2>Confidentiel par conception</h2>
<ul><li>Pas de compte, pas de statistiques d’usage, pas de publicité, pas de pistage.</li><li>Les jetons restent dans le trousseau de l’iPhone. La synchronisation de la configuration, ou des jetons via le trousseau iCloud, est facultative et désactivée par défaut.</li><li>HTTPS uniquement ; les actions demandent toujours une confirmation et Face ID.</li></ul>
<h2>Essayez sans serveur</h2>
<p>La démo intégrée montre un HomeLab fictif complet, généré sur l’appareil.</p>
<p><a href="support.html">Guides et assistance</a> · <a href="privacy.html">Politique de confidentialité</a></p>'''),
}

faq = {
 'en': [
  ("It works at home but not outside.", "PatchNode talks directly to your servers. Outside, your iPhone needs a VPN such as Tailscale or WireGuard, and your names must resolve through it (split DNS)."),
  ("Why is HTTPS required?", "Your tokens travel with every request. Put your services behind a reverse proxy with a valid certificate (for example Let's Encrypt with a DNS challenge)."),
  ("A service says “paused”.", "After a refused token or a reverse proxy block, PatchNode stops asking so it never gets your IP banned by CrowdSec or fail2ban. Allow-list your LAN and VPN in your IPS."),
  ("I lost my iPhone, or a token may have leaked.", "Revoke the tokens on each server, then create new ones. PatchNode is locked by Face ID or your passcode, but a revoked token is the only certain protection. Prefer read-only tokens."),
  ("Do you receive any data?", "No. There is no account, analytics, or server of ours. PatchNode connects only to the servers you configure. Nothing is shared with us unless you choose to share it."),
  ("Can I try without a server?", "Yes: Settings › Demo shows a complete sample HomeLab generated on the iPhone."),
 ],
 'fr': [
  ("Ça marche chez moi mais pas dehors.", "PatchNode dialogue directement avec vos serveurs. Dehors, votre iPhone a besoin d’un VPN comme Tailscale ou WireGuard, et vos noms doivent être résolus à travers lui (split DNS)."),
  ("Pourquoi HTTPS est-il obligatoire ?", "Vos jetons voyagent avec chaque requête. Placez vos services derrière un reverse proxy avec un certificat valide (par exemple Let’s Encrypt avec un challenge DNS)."),
  ("Un service est « en pause ».", "Après un jeton refusé ou un blocage du reverse proxy, PatchNode cesse d’interroger pour ne jamais faire bannir votre IP par CrowdSec ou fail2ban. Mettez votre LAN et votre VPN en liste blanche de votre IPS."),
  ("J’ai perdu mon iPhone, ou un jeton a pu fuiter.", "Révoquez les jetons sur chaque serveur, puis créez-en de nouveaux. PatchNode est verrouillé par Face ID ou votre code, mais seul un jeton révoqué protège à coup sûr. Préférez des jetons en lecture seule."),
  ("Recevez-vous des données ?", "Non. Pas de compte, pas de statistiques d’usage, pas de serveur à nous. Seul un e-mail au support que vous choisissez d’envoyer nous parvient."),
  ("Puis-je essayer sans serveur ?", "Oui : Réglages › Démo montre un HomeLab fictif complet généré sur l’iPhone."),
 ],
}
guides = {
 'en': [("Proxmox VE","User and API token, role PVEAuditor on / for the user and the token (Privilege Separation = intersection), PatchNodePower role (VM.PowerMgmt) for actions, always together with PVEAuditor on paths below / (a deeper ACL replaces the inherited roles, so guests would vanish), reverse proxy with the https scheme."),
        ("Proxmox Backup Server","Token user@realm!tokenid:secret (colon), role Audit on /."),
        ("Docker","Portainer access token, or tecnativa/docker-socket-proxy without a published port, on the reverse proxy's Docker network, POST=0, behind an Access List with a password (Satisfy All). Never expose docker.sock."),
        ("Prometheus, Alertmanager","No token: LAN/VPN only, optional Basic authentication through the reverse proxy."),
        ("Grafana","Service account with the Viewer role and a token."),
        ("Uptime Kuma","Create a status page and use its URL ending with /status/&lt;slug&gt;."),
        ("Tailscale","Settings › Trust credentials › OAuth client with Devices › Core › Read; not the API keys."),
        ("CrowdSec","cscli bouncers add patchnode; the Local API listens on 127.0.0.1 by default."),
        ("Nginx Proxy Manager","Dedicated user with View Only on Proxy Hosts."),
        ("AdGuard Home","Dedicated user in AdGuardHome.yaml (no read-only role: LAN/VPN only)."),
        ("Home Assistant, Glances","Long-lived token of a non-admin user; Glances in web server mode.")],
 'fr': [("Proxmox VE","Utilisateur et jeton API, rôle PVEAuditor sur / pour l’utilisateur et le jeton (Privilege Separation = intersection), rôle PatchNodePower (VM.PowerMgmt) pour les actions, toujours avec PVEAuditor sur les chemins sous / (une ACL plus précise remplace les rôles hérités, les invités disparaîtraient), reverse proxy avec le schéma https."),
        ("Proxmox Backup Server","Jeton utilisateur@realm!tokenid:secret (deux-points), rôle Audit sur /."),
        ("Docker","Jeton d’accès Portainer, ou tecnativa/docker-socket-proxy sans port publié, sur le réseau Docker du reverse proxy, POST=0, derrière une Access List avec mot de passe (Satisfy All). N’exposez jamais docker.sock."),
        ("Prometheus, Alertmanager","Pas de jeton : LAN/VPN uniquement, authentification Basic facultative via le reverse proxy."),
        ("Grafana","Service account avec le rôle Viewer et un jeton."),
        ("Uptime Kuma","Créez une page de statut et utilisez son URL terminée par /status/&lt;slug&gt;."),
        ("Tailscale","Settings › Trust credentials › client OAuth avec Devices › Core › Read ; pas les clés API."),
        ("CrowdSec","cscli bouncers add patchnode ; la Local API écoute sur 127.0.0.1 par défaut."),
        ("Nginx Proxy Manager","Utilisateur dédié avec View Only sur les Proxy Hosts."),
        ("AdGuard Home","Utilisateur dédié dans AdGuardHome.yaml (pas de rôle en lecture seule : LAN/VPN uniquement)."),
        ("Home Assistant, Glances","Jeton longue durée d’un utilisateur non administrateur ; Glances en mode serveur web.")],
}
support_text = {
 'en': ('Support', 'Setup guides and support', 'The full guides, with copyable commands and troubleshooting, are built into the app: Settings › Help and support › Guides.', 'In summary', 'Frequently asked questions', 'Contact',
        f'For support, read the in-app guides or open <a href="{SUPPORT_URL}">a GitHub issue</a>.'),
 'fr': ('Assistance', 'Guides et assistance', 'Les guides complets, avec commandes copiables et dépannage, sont intégrés à l’app : Réglages › Aide et support › Guides.', 'En résumé', 'Questions fréquentes', 'Contact',
        f'Pour obtenir de l’aide, consultez les guides de l’app ou ouvrez <a href="{SUPPORT_URL}">une issue GitHub</a>.'),
}

# Spanish, German and Italian (to be proofread by a native speaker).
index.update({
 'es': ('Monitor de HomeLab para iPhone', f'''<h1>Tu HomeLab de un vistazo</h1>
<p class="lead">PatchNode vigila tus servidores autoalojados desde tu iPhone: Proxmox, Docker, alertas, copias de seguridad, red, seguridad y domótica. Habla directamente con tus servidores, a través de tu red privada o tu VPN.</p>
<div class="card"><strong>Compatibles</strong>: Proxmox VE, Proxmox Backup Server, Docker (Portainer o un socket proxy de solo lectura), Prometheus, Alertmanager, Grafana, Uptime Kuma, Tailscale, CrowdSec, Nginx Proxy Manager, AdGuard Home, Home Assistant, Glances.</div>
<h2>Consolas, SSH y Compose</h2>
<p>Abre consolas de Proxmox, un terminal SSH hacia tus propios servidores (clave creada en el dispositivo, huellas fijadas) y gestiona proyectos Docker Compose, en iPhone, iPad y Mac.</p>
<h2>Privado por diseño</h2>
<ul><li>Sin cuenta, sin estadísticas de uso, sin publicidad, sin rastreo.</li><li>Los tokens se quedan en el llavero del iPhone. Sincronizar la configuración, o los tokens a través del Llavero de iCloud, es opcional y está desactivado por defecto.</li><li>Solo HTTPS; las acciones siempre piden confirmación y Face ID.</li></ul>
<h2>Pruébalo sin servidor</h2>
<p>La demo integrada muestra un HomeLab de ejemplo completo, generado en el dispositivo.</p>
<p><a href="support.html">Guías y soporte</a> · <a href="privacy.html">Política de privacidad</a></p>'''),
 'de': ('HomeLab-Monitor für das iPhone', f'''<h1>Dein HomeLab auf einen Blick</h1>
<p class="lead">PatchNode behält deine selbst gehosteten Server vom iPhone aus im Blick: Proxmox, Docker, Alarme, Backups, Netzwerk, Sicherheit und Hausautomation. Die App spricht direkt mit deinen Servern, über dein privates Netzwerk oder dein VPN.</p>
<div class="card"><strong>Unterstützt</strong>: Proxmox VE, Proxmox Backup Server, Docker (Portainer oder ein schreibgeschützter Socket-Proxy), Prometheus, Alertmanager, Grafana, Uptime Kuma, Tailscale, CrowdSec, Nginx Proxy Manager, AdGuard Home, Home Assistant, Glances.</div>
<h2>Konsolen, SSH und Compose</h2>
<p>Öffne Proxmox-Konsolen, ein SSH-Terminal zu deinen eigenen Servern (Schlüssel auf dem Gerät erzeugt, Fingerabdrücke festgelegt) und verwalte Docker-Compose-Projekte, auf iPhone, iPad und Mac.</p>
<h2>Privat von Grund auf</h2>
<ul><li>Kein Konto, keine Nutzungsstatistiken, keine Werbung, kein Tracking.</li><li>Tokens bleiben im Schlüsselbund des iPhone. Die Synchronisierung der Konfiguration oder der Tokens über den iCloud-Schlüsselbund ist optional und standardmäßig aus.</li><li>Nur HTTPS; Aktionen fragen immer nach Bestätigung und Face ID.</li></ul>
<h2>Ohne Server ausprobieren</h2>
<p>Die integrierte Demo zeigt ein vollständiges Beispiel-HomeLab, das auf dem Gerät erzeugt wird.</p>
<p><a href="support.html">Anleitungen und Support</a> · <a href="privacy.html">Datenschutzrichtlinie</a></p>'''),
 'it': ('Monitor per HomeLab su iPhone', f'''<h1>Il tuo HomeLab a colpo d’occhio</h1>
<p class="lead">PatchNode tiene d’occhio i tuoi server self-hosted dal tuo iPhone: Proxmox, Docker, avvisi, backup, rete, sicurezza e domotica. Comunica direttamente con i tuoi server, tramite la tua rete privata o la tua VPN.</p>
<div class="card"><strong>Supportati</strong>: Proxmox VE, Proxmox Backup Server, Docker (Portainer o un socket proxy in sola lettura), Prometheus, Alertmanager, Grafana, Uptime Kuma, Tailscale, CrowdSec, Nginx Proxy Manager, AdGuard Home, Home Assistant, Glances.</div>
<h2>Console, SSH e Compose</h2>
<p>Apri le console Proxmox, un terminale SSH verso i tuoi server (chiave creata sul dispositivo, impronte fissate) e gestisci i progetti Docker Compose, su iPhone, iPad e Mac.</p>
<h2>Privato per progettazione</h2>
<ul><li>Nessun account, nessuna statistica d’uso, nessuna pubblicità, nessun tracciamento.</li><li>I token restano nel portachiavi dell’iPhone. La sincronizzazione della configurazione, o dei token tramite il Portachiavi iCloud, è facoltativa e disattivata per impostazione predefinita.</li><li>Solo HTTPS; le azioni chiedono sempre conferma e Face ID.</li></ul>
<h2>Provalo senza server</h2>
<p>La demo integrata mostra un HomeLab di esempio completo, generato sul dispositivo.</p>
<p><a href="support.html">Guide e assistenza</a> · <a href="privacy.html">Informativa sulla privacy</a></p>'''),
})
faq.update({
 'es': [
  ("Funciona en casa pero no fuera.", "PatchNode habla directamente con tus servidores. Fuera de casa, tu iPhone necesita una VPN como Tailscale o WireGuard, y tus nombres deben resolverse a través de ella (DNS dividido)."),
  ("¿Por qué es obligatorio HTTPS?", "Tus tokens viajan con cada petición. Pon tus servicios detrás de un proxy inverso con un certificado válido (por ejemplo Let's Encrypt con un desafío DNS)."),
  ("Un servicio aparece «en pausa».", "Tras un token rechazado o un bloqueo del proxy inverso, PatchNode deja de consultar para que CrowdSec o fail2ban nunca bloqueen tu IP. Añade tu LAN y tu VPN a la lista de permitidos de tu IPS."),
  ("He perdido mi iPhone, o un token puede haberse filtrado.", "Revoca los tokens en cada servidor y crea otros nuevos. PatchNode está bloqueado con Face ID o tu código, pero solo un token revocado protege con certeza. Prefiere tokens de solo lectura."),
  ("¿Recibís algún dato?", "No. No hay cuenta, ni estadísticas de uso, ni servidor nuestro. Solo nos llega un correo al soporte que tú decidas enviar."),
  ("¿Puedo probarla sin servidor?", "Sí: Ajustes › Demo muestra un HomeLab de ejemplo completo generado en el iPhone."),
 ],
 'de': [
  ("Zu Hause klappt es, unterwegs nicht.", "PatchNode spricht direkt mit deinen Servern. Unterwegs braucht dein iPhone ein VPN wie Tailscale oder WireGuard, und deine Namen müssen darüber aufgelöst werden (Split DNS)."),
  ("Warum ist HTTPS Pflicht?", "Deine Tokens werden mit jeder Anfrage übertragen. Stelle deine Dienste hinter einen Reverse Proxy mit gültigem Zertifikat (zum Beispiel Let's Encrypt mit DNS-Challenge)."),
  ("Ein Dienst ist „pausiert“.", "Nach einem abgelehnten Token oder einer Sperre durch den Reverse Proxy hört PatchNode auf zu fragen, damit CrowdSec oder fail2ban deine IP nie sperren. Setze dein LAN und dein VPN auf die Allowlist deines IPS."),
  ("Ich habe mein iPhone verloren, oder ein Token könnte offengelegt sein.", "Widerrufe die Tokens auf jedem Server und erstelle neue. PatchNode ist mit Face ID oder deinem Code gesperrt, aber nur ein widerrufenes Token schützt sicher. Nutze bevorzugt schreibgeschützte Tokens."),
  ("Erhaltet ihr Daten?", "Nein. Es gibt kein Konto, keine Nutzungsstatistiken und keinen eigenen Server. Nur eine Support-E-Mail, die du selbst sendest, erreicht uns."),
  ("Kann ich es ohne Server ausprobieren?", "Ja: Einstellungen › Demo zeigt ein vollständiges Beispiel-HomeLab, das auf dem iPhone erzeugt wird."),
 ],
 'it': [
  ("Funziona a casa ma non fuori.", "PatchNode comunica direttamente con i tuoi server. Fuori casa, il tuo iPhone ha bisogno di una VPN come Tailscale o WireGuard, e i tuoi nomi devono essere risolti attraverso di essa (split DNS)."),
  ("Perché HTTPS è obbligatorio?", "I tuoi token viaggiano con ogni richiesta. Metti i tuoi servizi dietro un reverse proxy con un certificato valido (per esempio Let's Encrypt con una challenge DNS)."),
  ("Un servizio risulta «in pausa».", "Dopo un token rifiutato o un blocco del reverse proxy, PatchNode smette di interrogare per non far mai bannare il tuo IP da CrowdSec o fail2ban. Metti la tua LAN e la tua VPN nella lista consentita del tuo IPS."),
  ("Ho perso l’iPhone, o un token potrebbe essere trapelato.", "Revoca i token su ogni server, poi creane di nuovi. PatchNode è bloccato da Face ID o dal tuo codice, ma solo un token revocato protegge con certezza. Preferisci token in sola lettura."),
  ("Ricevete dei dati?", "No. Nessun account, nessuna statistica d’uso, nessun nostro server. Ci arriva solo un’e-mail al supporto che scegli tu di inviare."),
  ("Posso provarla senza server?", "Sì: Impostazioni › Demo mostra un HomeLab di esempio completo generato sull’iPhone."),
 ],
})
guides.update({
 'es': [("Proxmox VE","Usuario y token de API, rol PVEAuditor en / para el usuario y el token (Privilege Separation = intersección), rol PatchNodePower (VM.PowerMgmt) para las acciones, siempre con PVEAuditor en las rutas por debajo de / (una ACL más precisa sustituye los roles heredados y los invitados desaparecerían), proxy inverso con el esquema https."),
        ("Proxmox Backup Server","Token usuario@realm!tokenid:secreto (dos puntos), rol Audit en /."),
        ("Docker","Token de acceso de Portainer, o tecnativa/docker-socket-proxy sin puerto publicado, en la red Docker del proxy inverso, POST=0, detrás de una Access List con contraseña (Satisfy All). Nunca expongas docker.sock."),
        ("Prometheus, Alertmanager","Sin token: solo LAN/VPN, autenticación Basic opcional a través del proxy inverso."),
        ("Grafana","Service account con el rol Viewer y un token."),
        ("Uptime Kuma","Crea una página de estado y usa su URL terminada en /status/&lt;slug&gt;."),
        ("Tailscale","Settings › Trust credentials › cliente OAuth con Devices › Core › Read; no las claves de API."),
        ("CrowdSec","cscli bouncers add patchnode; la Local API escucha en 127.0.0.1 por defecto."),
        ("Nginx Proxy Manager","Usuario dedicado con View Only en Proxy Hosts."),
        ("AdGuard Home","Usuario dedicado en AdGuardHome.yaml (sin rol de solo lectura: solo LAN/VPN)."),
        ("Home Assistant, Glances","Token de larga duración de un usuario no administrador; Glances en modo servidor web.")],
 'de': [("Proxmox VE","Benutzer und API-Token, Rolle PVEAuditor auf / für Benutzer und Token (Privilege Separation = Schnittmenge), Rolle PatchNodePower (VM.PowerMgmt) für Aktionen, auf Pfaden unterhalb von / immer zusammen mit PVEAuditor (eine genauere ACL ersetzt die geerbten Rollen, die Gäste würden verschwinden), Reverse Proxy mit dem Schema https."),
        ("Proxmox Backup Server","Token benutzer@realm!tokenid:geheimnis (Doppelpunkt), Rolle Audit auf /."),
        ("Docker","Portainer-Zugriffstoken oder tecnativa/docker-socket-proxy ohne veröffentlichten Port, im Docker-Netzwerk des Reverse Proxy, POST=0, hinter einer Access List mit Passwort (Satisfy All). docker.sock nie freigeben."),
        ("Prometheus, Alertmanager","Kein Token: nur LAN/VPN, optional Basic-Authentifizierung über den Reverse Proxy."),
        ("Grafana","Service Account mit der Rolle Viewer und einem Token."),
        ("Uptime Kuma","Erstelle eine Statusseite und nutze ihre URL, die auf /status/&lt;slug&gt; endet."),
        ("Tailscale","Settings › Trust credentials › OAuth-Client mit Devices › Core › Read; nicht die API-Schlüssel."),
        ("CrowdSec","cscli bouncers add patchnode; die Local API lauscht standardmäßig auf 127.0.0.1."),
        ("Nginx Proxy Manager","Eigener Benutzer mit View Only auf Proxy Hosts."),
        ("AdGuard Home","Eigener Benutzer in AdGuardHome.yaml (keine schreibgeschützte Rolle: nur LAN/VPN)."),
        ("Home Assistant, Glances","Langlebiges Token eines Benutzers ohne Adminrechte; Glances im Webserver-Modus.")],
 'it': [("Proxmox VE","Utente e token API, ruolo PVEAuditor su / per l’utente e il token (Privilege Separation = intersezione), ruolo PatchNodePower (VM.PowerMgmt) per le azioni, sempre insieme a PVEAuditor sui percorsi sotto / (un’ACL più precisa sostituisce i ruoli ereditati, i guest sparirebbero), reverse proxy con lo schema https."),
        ("Proxmox Backup Server","Token utente@realm!tokenid:segreto (due punti), ruolo Audit su /."),
        ("Docker","Token di accesso Portainer, o tecnativa/docker-socket-proxy senza porta pubblicata, sulla rete Docker del reverse proxy, POST=0, dietro una Access List con password (Satisfy All). Non esporre mai docker.sock."),
        ("Prometheus, Alertmanager","Nessun token: solo LAN/VPN, autenticazione Basic facoltativa tramite il reverse proxy."),
        ("Grafana","Service account con il ruolo Viewer e un token."),
        ("Uptime Kuma","Crea una pagina di stato e usa il suo URL che termina con /status/&lt;slug&gt;."),
        ("Tailscale","Settings › Trust credentials › client OAuth con Devices › Core › Read; non le chiavi API."),
        ("CrowdSec","cscli bouncers add patchnode; la Local API ascolta su 127.0.0.1 per impostazione predefinita."),
        ("Nginx Proxy Manager","Utente dedicato con View Only su Proxy Hosts."),
        ("AdGuard Home","Utente dedicato in AdGuardHome.yaml (nessun ruolo in sola lettura: solo LAN/VPN)."),
        ("Home Assistant, Glances","Token di lunga durata di un utente non amministratore; Glances in modalità server web.")],
})
support_text.update({
 'es': ('Soporte', 'Guías y soporte', 'Las guías completas, con comandos copiables y solución de problemas, están integradas en la app: Ajustes › Ayuda y soporte › Guías.', 'En resumen', 'Preguntas frecuentes', 'Contacto',
        f'Para obtener ayuda, consulta las guías de la app o abre <a href="{SUPPORT_URL}">una incidencia en GitHub</a>.'),
 'de': ('Support', 'Anleitungen und Support', 'Die vollständigen Anleitungen mit kopierbaren Befehlen und Fehlerbehebung sind in die App integriert: Einstellungen › Hilfe und Support › Anleitungen.', 'Kurz gefasst', 'Häufige Fragen', 'Kontakt',
        f'Für Hilfe lies die Anleitungen in der App oder eröffne <a href="{SUPPORT_URL}">ein GitHub-Issue</a>.'),
 'it': ('Assistenza', 'Guide e assistenza', 'Le guide complete, con comandi copiabili e risoluzione dei problemi, sono integrate nell’app: Impostazioni › Aiuto e assistenza › Guide.', 'In sintesi', 'Domande frequenti', 'Contatto',
        f'Per assistenza, consulta le guide nell’app o apri <a href="{SUPPORT_URL}">una segnalazione GitHub</a>.'),
})

for lang in LANGS:
    d = root if lang=='en' else root/lang
    d.mkdir(exist_ok=True)
    t, b = index[lang]
    (d/'index.html').write_text(page(lang,'index',t,b))
    pt = L[lang]['policy']
    sep = ' :' if lang == 'fr' else ':'
    upd = f'<p class="lead">{L[lang]["updated"]}{sep} {updated}</p>'
    (d/'privacy.html').write_text(page(lang,'privacy',pt, f'<h1>{pt}</h1>\n{upd}\n'+md_to_html(policy[lang])))
    s = support_text[lang]
    body = f'<h1>{s[1]}</h1>\n<p class="lead">{s[2]}</p>\n<h2>{s[3]}</h2>\n' + ''.join(f'<div class="card"><strong>{g}</strong><br>{html.escape(x, quote=False).replace("&amp;lt;","&lt;").replace("&amp;gt;","&gt;")}</div>\n' for g,x in guides[lang])
    body += f'<h2>{s[4]}</h2>\n' + ''.join(f'<details><summary>{html.escape(q)}</summary><p>{html.escape(a)}</p></details>\n' for q,a in faq[lang])
    body += f'<h2>{s[5]}</h2>\n<p>{s[6]}</p>'
    (d/'support.html').write_text(page(lang,'support',s[0],body))
print("generated")
