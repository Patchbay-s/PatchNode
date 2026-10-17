# PatchNode — Privacy Policy / Politique de confidentialité / Política de privacidad / Datenschutzrichtlinie / Informativa sulla privacy

Last updated / Dernière mise à jour : 2026-10-17

To publish at a public URL (App Store Connect › App Privacy › Privacy Policy URL)
and in the app's Settings › About once `AppLinks.privacyPolicy` is set. The same
text is readable offline in the app (Settings › About › Privacy policy).

---

## English

**PatchNode collects no data.** There is no account, no analytics, no advertising and
no tracking, and the developer receives nothing from the app.

**What stays on your iPhone.** The services you add (name, type, address) are stored
in the app's private storage, which is part of your iPhone's own backups (iCloud or
computer). Tokens and passwords are stored in the iOS Keychain, for this device only:
unless you turn on the token option below, they are never synced to iCloud and are not
restored to another device. Choices such as the refresh
interval, the tab bar, the dashboard order, the Home Assistant entities and the
PromQL charts you save are stored on the device (and in your iCloud if you turn on
iCloud sync, below).

**Network connections.** The app connects only to the servers you add, over HTTPS,
and to `api.tailscale.com` if you add a Tailscale service. It never contacts a server
of the developer. The demo mode generates its data on the device and contacts no
server.

**SSH and consoles (1.2).** If you turn on Settings › SSH (off by default) or open a
Proxmox console, the app connects directly to your own servers: over SSH to the hosts
you add, and to your Proxmox server's console through its API. Nothing goes through a
server of the developer. The SSH key is created on the device; its private part stays in
the device's Keychain, is never synced (even with the iCloud Keychain option) and never
leaves the device: only the public key is shown, for you to copy. An SSH password, if a
server asks for one, is used for that connection only and never stored. The hosts you
add (name, address, port, user, the fingerprint you accepted) are stored like your other
services, and in your iCloud if sync is on. What you type and see in a terminal or a
console, and the content of the compose and .env files you edit, is never stored, logged
or sent anywhere else: Diagnostics only keep when a session opened and closed, its
duration and an error code. The graphical console (noVNC) is built into the app and
never loaded from the internet.

**Widgets and Siri.** Widgets and Siri shortcuts read a summary kept on the device
(counts and names of nodes, VMs and containers), without any address or secret.

**Notifications.** If you turn them on (Settings › Notifications, off by default), the app
posts local notifications from the iPhone itself after a background refresh: no server
is involved and nothing leaves the device. They give a count only (for example “2
containers are unhealthy”), never a name or an address. What the app remembers to avoid
repeating them (anonymous identifiers of the problems already notified, and when)
stays on the device and in its backups, like your settings.

**Export.** Settings › Export and import creates a file or a QR code with your services'
names and addresses, PromQL charts (whose queries may name your hosts), Home Assistant
entities, tabs and dashboard order, **never a token or a password**. It goes only where
you send it; a screenshot of the QR code is kept in your Photos like any other.

**Diagnostics.** Settings › Diagnostics keeps the last 200 requests in memory: service
name, method, API path, status, timing, connection details, content type and server
software, without tokens,
bodies, host names or query values. It is lost when the app
quits, and shared only if you tap Share.

**iCloud sync (optional).** Off by default. If you turn on Settings › iCloud › Sync
configuration with iCloud, your services (names and addresses), PromQL charts, Home
Assistant entities, tabs and dashboard order are stored in your own iCloud account
(CloudKit private database) so your other devices can use them. Apple stores them under
its own privacy policy; the developer has no access to them. Tokens are not included.
A separate option, also off by default, stores tokens and passwords in iCloud Keychain,
end-to-end encrypted, on your devices signed in to the same Apple Account; turning it
off removes them from iCloud Keychain. With it on, deleting a service also removes its
token from iCloud Keychain, and deleting the app leaves the tokens there: turn the option
off first. Turning configuration sync off doesn't delete what is already in iCloud: delete
it with Settings › iCloud › Delete my iCloud data in the app (which also empties iCloud
Keychain of PatchNode's tokens if that option is on), or in iOS Settings › your name ›
iCloud › Manage Account Storage › PatchNode. A service deleted on another device has its
token removed from this one too.

**iOS reports.** iOS gives the app reports of its crashes, hangs and performance
(MetricKit). They are kept on the iPhone for 30 days (Settings › Diagnostics › iOS
reports) and never sent automatically. You can share one yourself, or, when you contact
support, attach a summary of the crashes (date, versions, exception type), off by default
and shown in full first, without any address, host name, service name, token or call
stack.

**Deleting your data.** Deleting a service removes its token from the Keychain, and,
with iCloud sync, the service from your other devices too.
Delete your services before deleting the app: iOS can keep Keychain items after an app
is removed.

**Support.** If you contact support from the app (Settings › Help and support ›
Contact support), your own Mail app opens with a prefilled message; nothing is sent
until you send it. The developer then receives your e-mail address, your message and,
only if you turned it on, a diagnostic report shown to you in full beforehand: app and
iOS versions, device model, language, the types of services configured, whether the
demo mode is on, and the kind and HTTP code of the latest errors per service type.
It never contains an address, host name, service name, token or content. Support
e-mails are used only to answer you and are deleted once the request is closed.

**Children.** The app is not directed at children and collects no data from anyone.

**Contact.** For any question about this policy: patchbay-s@proton.me, also reachable
from Settings › Help and support in the app.

---

## Français

**PatchNode ne collecte aucune donnée.** Pas de compte, pas de statistiques d'usage, pas
de publicité ni de pistage, et le développeur ne reçoit rien de l'app.

**Ce qui reste sur votre iPhone.** Les services que vous ajoutez (nom, type, adresse)
sont enregistrés dans le stockage privé de l'app, qui fait partie des sauvegardes de
votre iPhone (iCloud ou ordinateur). Les jetons et mots de passe sont enregistrés dans
le trousseau iOS, pour cet appareil uniquement : sauf si vous activez l'option des jetons
ci-dessous, ils ne sont jamais synchronisés avec
iCloud ni restaurés sur un autre appareil. Vos réglages (intervalle de rafraîchissement, barre
d'onglets, ordre du tableau de bord, entités Home Assistant, graphiques PromQL) restent
sur l'appareil (et dans votre iCloud si vous activez la synchronisation iCloud, ci-dessous).

**Connexions réseau.** L'app ne se connecte qu'aux serveurs que vous ajoutez, en HTTPS,
et à `api.tailscale.com` si vous ajoutez un service Tailscale. Elle ne contacte jamais
de serveur du développeur. Le mode démo génère ses données sur l'appareil et ne
contacte aucun serveur.

**SSH et consoles (1.2).** Si vous activez Réglages › SSH (désactivé par défaut) ou
ouvrez une console Proxmox, l'app se connecte directement à vos propres serveurs : en SSH
aux hôtes que vous ajoutez, et à la console de votre serveur Proxmox par son API. Rien ne
passe par un serveur du développeur. La clé SSH est créée sur l'appareil ; sa partie
privée reste dans le trousseau de l'appareil, n'est jamais synchronisée (même avec
l'option trousseau iCloud) et ne quitte jamais l'appareil : seule la clé publique est
affichée, pour que vous la copiiez. Un mot de passe SSH, si un serveur en demande un,
ne sert qu'à cette connexion et n'est jamais conservé. Les hôtes que vous ajoutez (nom,
adresse, port, utilisateur, empreinte acceptée) sont stockés comme vos autres services,
et dans votre iCloud si la synchronisation est activée. Ce que vous tapez et voyez dans
un terminal ou une console, et le contenu des fichiers compose et .env que vous modifiez,
n'est jamais conservé, journalisé ni envoyé ailleurs : le Diagnostic ne garde que
l'ouverture et la fermeture d'une session, sa durée et un code d'erreur. La console
graphique (noVNC) est intégrée à l'app et jamais chargée depuis internet.

**Widgets et Siri.** Les widgets et les raccourcis Siri lisent un résumé conservé sur
l'appareil (nombres, noms des nœuds, VM et conteneurs), sans aucune adresse ni secret.

**Notifications.** Si vous les activez (Réglages › Notifications, désactivées par défaut),
l'app publie des notifications locales depuis l'iPhone lui-même après un rafraîchissement
en arrière-plan : aucun serveur n'intervient et rien ne quitte l'appareil. Elles donnent
seulement un nombre (par exemple « 2 conteneurs sont en mauvaise santé »), jamais un nom
ni une adresse. Ce que l'app retient pour ne pas les répéter (des identifiants anonymes des
problèmes déjà notifiés, et quand) reste sur l'appareil et dans ses sauvegardes, comme
vos réglages.

**Export.** Réglages › Exporter et importer crée un fichier ou un QR code avec les noms et
adresses de vos services, les graphiques PromQL (dont les requêtes peuvent nommer vos
hôtes), les entités Home Assistant, les onglets et l'ordre du tableau de bord, **jamais
un jeton ni un mot de passe**. Il ne va que là où vous l'envoyez ; une capture du QR code
reste dans vos Photos comme toute autre.

**Diagnostic.** Réglages › Diagnostic garde en mémoire les 200 dernières requêtes : nom
du service, méthode, chemin d'API, statut, durée, détails de connexion, type de contenu
et logiciel serveur, sans
jeton, corps, nom d'hôte ni valeur de paramètre. Il disparaît à la
fermeture de l'app et n'est partagé que si vous touchez Partager.

**Synchronisation iCloud (facultative).** Désactivée par défaut. Si vous activez
Réglages › iCloud › Synchroniser la configuration avec iCloud, vos services (noms et
adresses), graphiques PromQL, entités Home Assistant, onglets et ordre du tableau de bord
sont enregistrés dans votre propre compte iCloud (base privée CloudKit) pour que vos autres
appareils puissent les utiliser. Apple les conserve selon sa propre politique de
confidentialité ; le développeur n'y a pas accès. Les jetons n'en font pas partie. Une
option distincte, elle aussi désactivée par défaut, enregistre les jetons et mots de passe
dans le trousseau iCloud, chiffrés de bout en bout, sur vos appareils connectés au même
compte Apple ; la désactiver les retire du trousseau iCloud. Quand elle est activée,
supprimer un service retire aussi son jeton du trousseau iCloud, et supprimer l'app y
laisse les jetons : désactivez d'abord l'option. Désactiver la synchronisation de la
configuration ne supprime pas ce qui est déjà dans iCloud : supprimez-le dans Réglages
iOS › votre nom › iCloud › Gérer le stockage du compte › PatchNode, ou avec Réglages ›
iCloud › Supprimer mes données iCloud dans l'app (qui vide aussi le trousseau iCloud des
jetons de PatchNode si cette option est activée). Un service supprimé sur un autre
appareil voit aussi son jeton retiré de celui-ci.

**Rapports iOS.** iOS fournit à l'app des rapports sur ses plantages, blocages et
performances (MetricKit). Ils restent sur l'iPhone 30 jours (Réglages › Diagnostic ›
Rapports iOS) et ne sont jamais envoyés automatiquement. Vous pouvez en partager un
vous-même ou, en contactant le support, joindre un résumé des plantages (date, versions,
type d'exception), désactivé par défaut et montré en entier avant, sans adresse, nom
d'hôte, nom de service, jeton ni pile d'appels.

**Supprimer vos données.** Supprimer un service retire son jeton du trousseau et, avec la
synchronisation iCloud, le service de vos autres appareils aussi.
Supprimez vos services avant de supprimer l'app : iOS peut conserver des éléments du
trousseau après la suppression d'une app.

**Support.** Si vous contactez le support depuis l'app (Réglages › Aide et support ›
Contacter le support), votre app Mail s'ouvre avec un message prérempli ; rien n'est
envoyé tant que vous ne l'envoyez pas. Le développeur reçoit alors votre adresse
e-mail, votre message et, seulement si vous l'avez activé, un rapport de diagnostic
qui vous est montré en entier avant : versions de l'app et d'iOS, modèle d'appareil,
langue, types de services configurés, mode démo activé ou non, et nature et code HTTP
des dernières erreurs par type de service. Il ne contient jamais d'adresse, de nom
d'hôte, de nom de service, de jeton ni de contenu. Les e-mails de support servent
uniquement à vous répondre et sont supprimés une fois la demande close.

**Enfants.** L'app ne s'adresse pas aux enfants et ne collecte de données auprès de
personne.

**Contact.** Pour toute question sur cette politique : patchbay-s@proton.me, aussi
accessible depuis Réglages › Aide et support dans l'app.

---

## Español

**PatchNode no recopila ningún dato.** No hay cuenta, ni estadísticas de uso, ni
publicidad, ni rastreo, y el desarrollador no recibe nada de la app.

**Lo que se queda en tu iPhone.** Los servicios que añades (nombre, tipo, dirección) se
guardan en el almacenamiento privado de la app, que forma parte de las copias de
seguridad de tu iPhone (iCloud u ordenador). Los tokens y contraseñas se guardan en el
llavero de iOS, solo para este dispositivo: salvo que actives la opción de los tokens
descrita más abajo, nunca se sincronizan con iCloud ni se
restauran en otro dispositivo. Tus ajustes (intervalo de actualización, barra de
pestañas, orden del panel, entidades de Home Assistant, gráficos PromQL guardados) se
quedan en el dispositivo (y en tu iCloud si activas la sincronización con iCloud, más abajo).

**Conexiones de red.** La app solo se conecta a los servidores que añades, por HTTPS, y
a `api.tailscale.com` si añades un servicio Tailscale. Nunca contacta con un servidor
del desarrollador. El modo demo genera sus datos en el dispositivo y no contacta con
ningún servidor.

**SSH y consolas (1.2).** Si activas Ajustes › SSH (desactivado por defecto) o abres
una consola de Proxmox, la app se conecta directamente a tus propios servidores: por SSH
a los hosts que añades, y a la consola de tu servidor Proxmox mediante su API. Nada pasa
por un servidor del desarrollador. La clave SSH se crea en el dispositivo; su parte
privada se queda en el llavero del dispositivo, nunca se sincroniza (ni siquiera con la
opción de llavero de iCloud) y nunca sale del dispositivo: solo se muestra la clave
pública, para que la copies. Una contraseña SSH, si un servidor la pide, solo se usa
para esa conexión y nunca se guarda. Los hosts que añades (nombre, dirección, puerto,
usuario, huella aceptada) se guardan como tus otros servicios, y en tu iCloud si la
sincronización está activada. Lo que escribes y ves en un terminal o una consola, y el
contenido de los archivos compose y .env que editas, nunca se guarda, registra ni envía
a ningún otro sitio: Diagnóstico solo guarda la apertura y el cierre de una sesión, su
duración y un código de error. La consola gráfica (noVNC) está integrada en la app y
nunca se carga desde internet.

**Widgets y Siri.** Los widgets y los atajos de Siri leen un resumen guardado en el
dispositivo (número y nombres de nodos, VM y contenedores), sin ninguna dirección ni
secreto.

**Notificaciones.** Si las activas (Ajustes › Notificaciones, desactivadas por defecto),
la app publica notificaciones locales desde el propio iPhone tras una actualización en
segundo plano: no interviene ningún servidor y nada sale del dispositivo. Solo indican
un número (por ejemplo «2 contenedores no están sanos»), nunca un nombre ni una
dirección. Lo que la app recuerda para no repetirlas (identificadores anónimos de los
problemas ya notificados, y cuándo) se queda en el dispositivo y en sus copias de
seguridad, como tus ajustes.

**Exportación.** Ajustes › Exportar e importar crea un archivo o un código QR con los
nombres y direcciones de tus servicios, los gráficos PromQL (cuyas consultas pueden
nombrar tus hosts), las entidades de Home Assistant, las pestañas y el orden del panel,
**nunca un token ni una contraseña**. Solo va adonde tú lo envíes; una captura del
código QR se guarda en tus Fotos como cualquier otra.

**Diagnóstico.** Ajustes › Diagnóstico guarda en memoria las últimas 200 peticiones:
nombre del servicio, método, ruta de la API, estado, duración, detalles de conexión,
tipo de contenido y software del servidor, sin tokens, cuerpos, nombres de host ni
valores de parámetros. Desaparece al cerrar la app y solo se comparte si tocas
Compartir.

**Sincronización con iCloud (opcional).** Desactivada por defecto. Si activas Ajustes ›
iCloud › Sincronizar la configuración con iCloud, tus servicios (nombres y direcciones),
gráficos PromQL, entidades de Home Assistant, pestañas y orden del panel se guardan en tu
propia cuenta de iCloud (base de datos privada de CloudKit) para que tus otros
dispositivos puedan usarlos. Apple los guarda según su propia política de privacidad; el
desarrollador no tiene acceso. Los tokens no se incluyen. Una opción aparte, también
desactivada por defecto, guarda los tokens y contraseñas en el Llavero de iCloud, con
cifrado de extremo a extremo, en tus dispositivos con la misma cuenta de Apple;
desactivarla los elimina del Llavero de iCloud. Con ella activada, eliminar un servicio
también borra su token del Llavero de iCloud, y eliminar la app deja allí los tokens:
desactiva antes la opción. Desactivar la sincronización de la configuración no borra lo
que ya está en iCloud: bórralo en Ajustes de iOS › tu nombre › iCloud › Gestionar el
almacenamiento de la cuenta › PatchNode, o con Ajustes › iCloud › Eliminar mis datos de
iCloud en la app (que también vacía el Llavero de iCloud de los tokens de PatchNode si
esa opción está activada). Un servicio eliminado en otro dispositivo también ve su token
eliminado de este.

**Informes de iOS.** iOS proporciona a la app informes de sus cierres inesperados,
bloqueos y rendimiento (MetricKit). Se guardan en el iPhone 30 días (Ajustes ›
Diagnóstico › Informes de iOS) y nunca se envían automáticamente. Puedes compartir uno tú
mismo o, al contactar con el soporte, adjuntar un resumen de los cierres (fecha,
versiones, tipo de excepción), desactivado por defecto y mostrado completo antes, sin
ninguna dirección, nombre de host, nombre de servicio, token ni pila de llamadas.

**Eliminar tus datos.** Eliminar un servicio borra su token del llavero y, con la
sincronización con iCloud, también el servicio de tus otros dispositivos. Elimina tus
servicios antes de eliminar la app: iOS puede conservar elementos del llavero después
de eliminar una app.

**Soporte.** Si contactas con el soporte desde la app (Ajustes › Ayuda y soporte ›
Contactar con soporte), se abre tu app Mail con un mensaje ya redactado; no se envía
nada hasta que tú lo envías. El desarrollador recibe entonces tu dirección de correo,
tu mensaje y, solo si lo activaste, un informe de diagnóstico que se te muestra completo
antes: versiones de la app y de iOS, modelo del dispositivo, idioma, tipos de servicios
configurados, si el modo demo está activado, y el tipo y el código HTTP de los últimos
errores por tipo de servicio. Nunca contiene una dirección, un nombre de host, un
nombre de servicio, un token ni contenido. Los correos de soporte solo se usan para
responderte y se eliminan una vez cerrada la solicitud.

**Menores.** La app no está dirigida a menores y no recopila datos de nadie.

**Contacto.** Para cualquier pregunta sobre esta política: patchbay-s@proton.me,
también accesible desde Ajustes › Ayuda y soporte en la app.

---

## Deutsch

**PatchNode erfasst keine Daten.** Es gibt kein Konto, keine Nutzungsstatistiken, keine
Werbung und kein Tracking, und der Entwickler erhält nichts von der App.

**Was auf deinem iPhone bleibt.** Die Dienste, die du hinzufügst (Name, Typ, Adresse),
werden im privaten Speicher der App abgelegt, der Teil der Backups deines iPhone ist
(iCloud oder Computer). Tokens und Passwörter werden im iOS-Schlüsselbund gespeichert,
nur für dieses Gerät: Sofern du die Token-Option unten nicht aktivierst, werden sie nie
mit iCloud synchronisiert und nicht auf einem
anderen Gerät wiederhergestellt. Deine Einstellungen (Aktualisierungsintervall,
Tableiste, Reihenfolge der Übersicht, Home-Assistant-Entitäten, gespeicherte
PromQL-Diagramme) bleiben auf dem Gerät (und in deiner iCloud, wenn du die
iCloud-Synchronisierung unten aktivierst).

**Netzwerkverbindungen.** Die App verbindet sich nur mit den Servern, die du hinzufügst,
über HTTPS, und mit `api.tailscale.com`, wenn du einen Tailscale-Dienst hinzufügst. Sie
kontaktiert nie einen Server des Entwicklers. Der Demomodus erzeugt seine Daten auf dem
Gerät und kontaktiert keinen Server.

**SSH und Konsolen (1.2).** Wenn du Einstellungen › SSH aktivierst (standardmäßig aus)
oder eine Proxmox-Konsole öffnest, verbindet sich die App direkt mit deinen eigenen
Servern: per SSH mit den Hosts, die du hinzufügst, und über die API mit der Konsole
deines Proxmox-Servers. Nichts läuft über einen Server des Entwicklers. Der SSH-Schlüssel
wird auf dem Gerät erzeugt; sein privater Teil bleibt im Schlüsselbund des Geräts, wird
nie synchronisiert (auch nicht mit der Option iCloud-Schlüsselbund) und verlässt das
Gerät nie: Nur der öffentliche Schlüssel wird angezeigt, damit du ihn kopieren kannst.
Ein SSH-Passwort, falls ein Server eines verlangt, gilt nur für diese Verbindung und wird
nie gespeichert. Die Hosts, die du hinzufügst (Name, Adresse, Port, Benutzer, akzeptierter
Fingerabdruck), werden wie deine anderen Dienste gespeichert, und in deiner iCloud, wenn
die Synchronisation aktiv ist. Was du in einem Terminal oder einer Konsole tippst und
siehst, und der Inhalt der bearbeiteten Compose- und .env-Dateien, wird nie gespeichert,
protokolliert oder anderswohin gesendet: Die Diagnose behält nur Öffnen und Schließen
einer Sitzung, ihre Dauer und einen Fehlercode. Die grafische Konsole (noVNC) ist in die
App eingebaut und wird nie aus dem Internet geladen.

**Widgets und Siri.** Widgets und Siri-Kurzbefehle lesen eine auf dem Gerät gespeicherte
Zusammenfassung (Anzahl und Namen von Nodes, VMs und Containern), ohne Adresse oder
Geheimnis.

**Mitteilungen.** Wenn du sie aktivierst (Einstellungen › Mitteilungen, standardmäßig
aus), sendet die App lokale Mitteilungen vom iPhone selbst nach einer Aktualisierung im
Hintergrund: Kein Server ist beteiligt, und nichts verlässt das Gerät. Sie nennen nur
eine Anzahl (zum Beispiel „2 Container sind nicht gesund“), nie einen Namen oder eine
Adresse. Was sich die App merkt, um sie nicht zu wiederholen (anonyme Kennungen der
bereits gemeldeten Probleme und wann), bleibt auf dem Gerät und in seinen Backups, wie
deine Einstellungen.

**Export.** Einstellungen › Exportieren und importieren erstellt eine Datei oder einen
QR-Code mit den Namen und Adressen deiner Dienste, den PromQL-Diagrammen (deren Abfragen
deine Hosts nennen können), den Home-Assistant-Entitäten, den Tabs und der Reihenfolge
der Übersicht, **nie ein Token oder ein Passwort**. Das Ergebnis gelangt nur dorthin, wohin du es
sendest; ein Bildschirmfoto des QR-Codes bleibt wie jedes andere in deinen Fotos.

**Diagnose.** Einstellungen › Diagnose behält die letzten 200 Anfragen im Arbeitsspeicher:
Name des Dienstes, Methode, API-Pfad, Status, Dauer, Verbindungsdetails, Inhaltstyp und
Serversoftware, ohne Tokens, Inhalte, Hostnamen oder Parameterwerte. Sie geht beim
Beenden der App verloren und wird nur geteilt, wenn du auf Teilen tippst.

**iCloud-Synchronisierung (optional).** Standardmäßig aus. Wenn du Einstellungen ›
iCloud › Konfiguration mit iCloud synchronisieren aktivierst, werden deine Dienste (Namen
und Adressen), PromQL-Diagramme, Home-Assistant-Entitäten, Tabs und die Reihenfolge der
Übersicht in deinem eigenen iCloud-Account gespeichert (private CloudKit-Datenbank),
damit deine anderen Geräte sie nutzen können. Apple speichert sie gemäß seiner eigenen
Datenschutzrichtlinie; der Entwickler hat keinen Zugriff darauf. Tokens sind nicht
enthalten. Eine separate Option, ebenfalls standardmäßig aus, speichert Tokens und
Passwörter im iCloud-Schlüsselbund, Ende-zu-Ende-verschlüsselt, auf deinen Geräten mit
demselben Apple Account; beim Ausschalten werden sie aus dem iCloud-Schlüsselbund entfernt.
Ist sie aktiv, entfernt das Löschen eines Dienstes auch sein Token aus dem
iCloud-Schlüsselbund, und das Löschen der App lässt die Tokens dort zurück: Schalte die
Option vorher aus. Das Ausschalten der Konfigurationssynchronisierung löscht nicht, was
bereits in iCloud liegt: Lösche es in den iOS-Einstellungen › dein Name › iCloud ›
Accountspeicher verwalten › PatchNode, oder in der App unter Einstellungen › iCloud ›
Meine iCloud-Daten löschen (das leert auch den iCloud-Schlüsselbund von den Tokens von
PatchNode, wenn diese Option aktiv ist). Wird ein Dienst auf einem anderen Gerät gelöscht,
wird sein Token auch von diesem entfernt.

**iOS-Berichte.** iOS stellt der App Berichte über ihre Abstürze, Hänger und Leistung
bereit (MetricKit). Sie bleiben 30 Tage auf dem iPhone (Einstellungen › Diagnose ›
iOS-Berichte) und werden nie automatisch gesendet. Du kannst einen selbst teilen oder,
wenn du den Support kontaktierst, eine Zusammenfassung der Abstürze anhängen (Datum,
Versionen, Ausnahmetyp), standardmäßig aus und vorher vollständig angezeigt, ohne
Adresse, Hostnamen, Dienstnamen, Token oder Aufrufstapel.

**Deine Daten löschen.** Wenn du einen Dienst löschst, wird sein Token aus dem
Schlüsselbund entfernt und, mit iCloud-Synchronisierung, der Dienst auch von deinen
anderen Geräten. Lösche deine Dienste, bevor du die App löschst: iOS kann
Schlüsselbundeinträge nach dem Entfernen einer App behalten.

**Support.** Wenn du den Support aus der App kontaktierst (Einstellungen › Hilfe und
Support › Support kontaktieren), öffnet sich deine Mail-App mit einer vorbereiteten
Nachricht; nichts wird gesendet, bevor du sie sendest. Der Entwickler erhält dann deine
E-Mail-Adresse, deine Nachricht und, nur wenn du ihn aktiviert hast, einen
Diagnosebericht, der dir vorher vollständig angezeigt wird: Versionen der App und von
iOS, Gerätemodell, Sprache, die eingerichteten Diensttypen, ob der Demomodus aktiv ist,
sowie Art und HTTP-Code der letzten Fehler je Diensttyp. Er enthält nie eine Adresse,
einen Hostnamen, einen Dienstnamen, ein Token oder Inhalte. Support-E-Mails dienen nur
dazu, dir zu antworten, und werden gelöscht, sobald die Anfrage abgeschlossen ist.

**Kinder.** Die App richtet sich nicht an Kinder und erfasst von niemandem Daten.

**Kontakt.** Für Fragen zu dieser Richtlinie: patchbay-s@proton.me, auch erreichbar
über Einstellungen › Hilfe und Support in der App.

---

## Italiano

**PatchNode non raccoglie alcun dato.** Nessun account, nessuna statistica d’uso, nessuna
pubblicità né tracciamento, e lo sviluppatore non riceve nulla dall’app.

**Cosa resta sul tuo iPhone.** I servizi che aggiungi (nome, tipo, indirizzo) sono
salvati nello spazio privato dell’app, che fa parte dei backup del tuo iPhone (iCloud o
computer). Token e password sono salvati nel portachiavi di iOS, solo per questo
dispositivo: a meno che tu non attivi l’opzione dei token descritta sotto, non vengono
mai sincronizzati con iCloud né ripristinati su un altro
dispositivo. Le tue impostazioni (intervallo di aggiornamento, barra delle schede,
ordine della dashboard, entità di Home Assistant, grafici PromQL salvati) restano sul
dispositivo (e nel tuo iCloud se attivi la sincronizzazione iCloud, più sotto).

**Connessioni di rete.** L’app si collega solo ai server che aggiungi, in HTTPS, e ad
`api.tailscale.com` se aggiungi un servizio Tailscale. Non contatta mai un server dello
sviluppatore. La modalità demo genera i suoi dati sul dispositivo e non contatta alcun
server.

**SSH e console (1.2).** Se attivi Impostazioni › SSH (disattivato per impostazione
predefinita) o apri una console Proxmox, l’app si connette direttamente ai tuoi server:
via SSH agli host che aggiungi, e alla console del tuo server Proxmox tramite la sua API.
Nulla passa da un server dello sviluppatore. La chiave SSH viene creata sul dispositivo;
la sua parte privata resta nel Portachiavi del dispositivo, non viene mai sincronizzata
(nemmeno con l’opzione Portachiavi iCloud) e non lascia mai il dispositivo: viene
mostrata solo la chiave pubblica, da copiare. Una password SSH, se un server la chiede,
vale solo per quella connessione e non viene mai salvata. Gli host che aggiungi (nome,
indirizzo, porta, utente, impronta accettata) vengono salvati come gli altri servizi, e
nel tuo iCloud se la sincronizzazione è attiva. Ciò che digiti e vedi in un terminale o
in una console, e il contenuto dei file compose e .env che modifichi, non viene mai
salvato, registrato né inviato altrove: la Diagnostica conserva solo apertura e chiusura
di una sessione, la sua durata e un codice di errore. La console grafica (noVNC) è
integrata nell’app e non viene mai caricata da internet.

**Widget e Siri.** I widget e le scorciatoie di Siri leggono un riepilogo conservato sul
dispositivo (numero e nomi di nodi, VM e container), senza alcun indirizzo né segreto.

**Notifiche.** Se le attivi (Impostazioni › Notifiche, disattivate per impostazione
predefinita), l’app pubblica notifiche locali dall’iPhone stesso dopo un aggiornamento
in background: nessun server è coinvolto e nulla lascia il dispositivo. Indicano solo
un numero (per esempio «2 container non sono integri»), mai un nome né un indirizzo.
Ciò che l’app ricorda per non ripeterle (identificatori anonimi dei problemi già
notificati, e quando) resta sul dispositivo e nei suoi backup, come le tue impostazioni.

**Esportazione.** Impostazioni › Esporta e importa crea un file o un codice QR con i nomi
e gli indirizzi dei tuoi servizi, i grafici PromQL (le cui query possono nominare i tuoi
host), le entità di Home Assistant, le schede e l’ordine della dashboard, **mai un token
né una password**. Va solo dove lo invii tu; uno screenshot del codice QR resta nelle
tue Foto come qualsiasi altro.

**Diagnostica.** Impostazioni › Diagnostica conserva in memoria le ultime 200 richieste:
nome del servizio, metodo, percorso dell’API, stato, durata, dettagli di connessione,
tipo di contenuto e software del server, senza token, corpi, nomi host né valori dei
parametri. Scompare alla chiusura dell’app ed è condivisa solo se tocchi Condividi.

**Sincronizzazione iCloud (facoltativa).** Disattivata per impostazione predefinita. Se
attivi Impostazioni › iCloud › Sincronizza la configurazione con iCloud, i tuoi servizi
(nomi e indirizzi), grafici PromQL, entità di Home Assistant, schede e ordine della
dashboard vengono salvati nel tuo account iCloud (database privato CloudKit) perché gli
altri tuoi dispositivi possano usarli. Apple li conserva secondo la propria informativa
sulla privacy; lo sviluppatore non vi ha accesso. I token non sono inclusi. Un’opzione
separata, anch’essa disattivata per impostazione predefinita, salva token e password nel
Portachiavi iCloud, con crittografia end-to-end, sui tuoi dispositivi collegati allo
stesso Account Apple; disattivarla li rimuove dal Portachiavi iCloud. Se è attiva,
eliminare un servizio rimuove anche il suo token dal Portachiavi iCloud, ed eliminare
l’app ve li lascia: disattiva prima l’opzione. Disattivare la sincronizzazione della
configurazione non elimina ciò che è già in iCloud: eliminalo in Impostazioni di iOS ›
il tuo nome › iCloud › Gestisci spazio dell’account › PatchNode, oppure con
Impostazioni › iCloud › Elimina i miei dati iCloud nell’app (che svuota anche il
Portachiavi iCloud dai token di PatchNode se quell’opzione è attiva). Un servizio
eliminato su un altro dispositivo vede il suo token rimosso anche da questo.

**Rapporti iOS.** iOS fornisce all’app rapporti su arresti anomali, blocchi e
prestazioni (MetricKit). Restano sull’iPhone per 30 giorni (Impostazioni › Diagnostica ›
Rapporti iOS) e non vengono mai inviati automaticamente. Puoi condividerne uno tu stesso
oppure, quando contatti l’assistenza, allegare un riepilogo degli arresti anomali (data,
versioni, tipo di eccezione), disattivato per impostazione predefinita e mostrato per
intero prima, senza indirizzi, nomi host, nomi di servizio, token né stack di chiamate.

**Eliminare i tuoi dati.** Eliminare un servizio rimuove il suo token dal portachiavi e,
con la sincronizzazione iCloud, anche il servizio dagli altri tuoi dispositivi.
Elimina i tuoi servizi prima di eliminare l’app: iOS può conservare elementi del
portachiavi dopo la rimozione di un’app.

**Supporto.** Se contatti il supporto dall’app (Impostazioni › Aiuto e assistenza ›
Contatta l’assistenza), si apre la tua app Mail con un messaggio precompilato; nulla
viene inviato finché non lo invii tu. Lo sviluppatore riceve allora il tuo indirizzo
e-mail, il tuo messaggio e, solo se l’hai attivato, un rapporto di diagnostica che ti
viene mostrato per intero prima: versioni dell’app e di iOS, modello del dispositivo,
lingua, tipi di servizi configurati, se la modalità demo è attiva, e tipo e codice HTTP
degli ultimi errori per tipo di servizio. Non contiene mai un indirizzo, un nome host,
un nome di servizio, un token né contenuti. Le e-mail di supporto servono solo a
risponderti e vengono eliminate una volta chiusa la richiesta.

**Minori.** L’app non è rivolta ai minori e non raccoglie dati da nessuno.

**Contatto.** Per qualsiasi domanda su questa politica: patchbay-s@proton.me,
raggiungibile anche da Impostazioni › Aiuto e assistenza nell’app.
