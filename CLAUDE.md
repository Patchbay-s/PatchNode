# PatchNode — règles du projet

Spécification complète : docs/SPEC.md. La lire avant toute nouvelle phase.

## Suivi
- docs/ROADMAP.md : état du projet, backlog, corrigé / validé (remplace BUGS.md, RECAP-MAC.md et PHASE1-8.md).
- docs/TESTS.md : checklist de tests sur iPhone (remplace TESTS-CE-SOIR.md).
- docs/AUDIT-v1.0.1.md : rapport d'audit complet.
- docs/RELEASE.md : checklist de publication d'une version (à dérouler à chaque release).
- Règle : chaque session met à jour docs/ROADMAP.md et docs/TESTS.md (cocher ce qui est fait ou validé, ajouter ce qui reste à faire ou à tester).

## Cible
- Aucune dépendance externe, sauf les exceptions validées par le mainteneur pour la 1.2 :
  SwiftTerm (terminal), SwiftNIO SSH d'Apple et ses dépendances Apple (swift-nio,
  swift-crypto, swift-atomics, swift-collections, swift-system, swift-asn1), noVNC
  (JavaScript embarqué dans le bundle, jamais chargé depuis internet). Citadel a été
  écarté (il dépend d'un fork tiers de swift-nio-ssh).
  - Versions figées : `exact:` dans les Package.swift pour les dépendances directes,
    `PatchNode.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
    versionné pour tout le graphe. Une version doit avoir au moins deux semaines.
  - Toute mise à jour : vérifier licence et dépendances transitives, mettre à jour
    la liste des licences (Réglages › À propos › Licences, `PatchNode/Licenses/`).
  - Aucune nouvelle dépendance sans accord explicite du mainteneur.
- App grand public (App Store) : aucun domaine, IP ou nom d'hôte propre à une installation dans le code.
- Interface localisée via String Catalog : anglais (langue de développement), français, espagnol, allemand et italien. Tout nouveau texte (app, widgets, guides, site, docs/appstore) dans les cinq langues ; es/de/it restent en « needs_review » tant qu’un natif ne les a pas relus.

## Règles non négociables
- Secrets uniquement dans le Keychain, jamais dans SwiftData/CloudKit, UserDefaults, logs ou code. Par défaut WhenUnlockedThisDeviceOnly, non synchronisable. Seule exception : l'option explicite « Synchroniser aussi les jetons avec le trousseau iCloud » (désactivée par défaut, confirmation + Face ID) qui écrit en kSecAttrSynchronizable + WhenUnlocked ; la désactiver ramène les jetons sur l'appareil et les retire du trousseau iCloud. Tout code Keychain passe par KeychainSecretStore. Chaque jeton est lié à son serveur (kSecAttrLabel = CredentialOrigin) : lire avec read(for:origin:), jamais envoyer un jeton à une autre origine.
- Clé privée SSH (ed25519, une par appareil, générée sur l'appareil) : Keychain uniquement, via `KeychainSecretStore` avec un service dédié et `synchronizes: { false }` — toujours WhenUnlockedThisDeviceOnly, jamais synchronisée (même avec l'option trousseau iCloud), jamais exportée, affichée ni journalisée ; seule la clé publique sort de l'app. Mot de passe SSH jamais stocké (saisi à la connexion). Empreinte d'hôte épinglée au premier contact validé ; connexion refusée si elle change.
- Contenu des sessions terminal (SSH, consoles Proxmox) et des fichiers compose/.env : jamais journalisé ni conservé ; le Diagnostic ne garde qu'ouverture, fermeture, erreur et durée. Tout chemin ou nom passé à un shell distant passe par `ShellQuoting` (tests d'injection).
- Synchronisation iCloud de la configuration (SwiftData + CloudKit, base privée de l'utilisateur) désactivée par défaut. Schéma compatible CloudKit : aucun attribut unique, valeur par défaut pour chaque attribut, uniquement des ajouts dans les versions suivantes ; les doublons d'ID sont tolérés à l'affichage (uniqued) et supprimés ensemble, jamais automatiquement.
- Aucune exception ATS. Aucun délégué qui accepte un certificat invalide. URL HTTPS obligatoires.
- Authorization / X-API-Key masqués dans tout log, même en DEBUG.
- Timeout 10 s, backoff espacé, jamais de retry sur 401/403 ni sur POST.
- Toute action modifiant un état = confirmation explicite avec le nom de la cible.
- Architecture à fournisseurs : un package par famille de services, conforme au protocole ServiceProvider.

## Validation
- Uniquement build + tests unitaires. Pas de simulateur visuel, pas de tests UI : le mainteneur vérifie sur l'appareil.
- Privilégier la vitesse d'itération.
- Environnement cloud sans Xcode : une phase n'est jamais considérée comme terminée sans un build xcodebuild réussi sur le Mac. Signaler clairement ce qui n'a pas été compilé.
- Objets d'environnement : `@Observable` + `@Environment(Type.self)` uniquement, fournis par `AppEnvironment` (`.appEnvironment(model)`) à la racine de chaque scène ; lancer scripts/check-environment.sh après tout ajout de store ou de scène.
- Après toute modification du projet Xcode ou ajout/suppression de fichiers dans PatchNode/ ou PatchNodeWidgets/ : lancer scripts/check-pbxproj.sh.
- Leçon du premier build sur appareil : le build generic sans signature ne suffit pas. Sur iPhone, Xcode a refusé un Info.plist d'extension copié en ressource (« Multiple commands produce ») et un plist d'extension sans CFBundleIdentifier.
- Toute nouvelle cible ou extension : GENERATE_INFOPLIST_FILE = YES, Info.plist exclu des ressources (membershipExceptions du dossier synchronisé), bundle ID préfixé par celui de l'app, MARKETING_VERSION et CURRENT_PROJECT_VERSION définis une seule fois au niveau du projet (jamais sur une cible), extension intégrée (Embed) et en dépendance de l'app. scripts/check-pbxproj.sh le vérifie.
- DEVELOPMENT_TEAM n'est jamais dans le projet : il vient de Config/Local.xcconfig (ignoré par git, modèle Config/Local.xcconfig.example), inclus par Config/Base.xcconfig. scripts/check-pbxproj.sh le vérifie.

## Sous-agents (.claude/agents/)
- test-engineer : après chaque provider, endpoint ou parseur.
- concurrency-reviewer : dès qu'il y a du code async/acteurs, ou des warnings de concurrence.
- security-auditor : après tout changement réseau/Keychain/auth/logs/plist, et obligatoirement en fin de phase.
- performance-reviewer : en fin de phase.
- En fin de phase : lancer concurrency-reviewer, security-auditor et performance-reviewer, corriger les points CRITIQUE/ÉLEVÉ, puis résumer.
