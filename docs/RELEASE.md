# Publier une version (checklist réutilisable)

À dérouler dans l'ordre pour chaque version (1.1, 1.2…). Cocher dans une copie de
la checklist (PR de release ou note), pas dans ce fichier.

## 1. Code et versions
- [ ] Toutes les PR de la version sont mergées dans `main` ; `git pull`.
- [ ] `MARKETING_VERSION` (ex. 1.1) et `CURRENT_PROJECT_VERSION` (build +1) changés
      **une seule fois, au niveau du projet** (jamais sur une cible) ;
      `scripts/check-pbxproj.sh` OK.
- [ ] `DEVELOPMENT_TEAM` inchangé.
- [ ] `swift test` dans chaque package (sur le Mac : tests SwiftData et Keychain
      compris).
- [ ] `xcodebuild … build` sans erreur ni avertissement ;
      `scripts/check-shipped-hosts.sh` et `scripts/check-environment.sh` OK.
- [ ] docs/TESTS.md : toutes les vérifications de la version faites sur l'iPhone
      (dont la mise à jour par-dessus la version publiée, sans la supprimer).
- [ ] String Catalogs : aucune chaîne manquante ; état des traductions es/de/it
      noté (relues ou « needs_review »).

- [ ] Dépendances (depuis la 1.2) : `Package.resolved` du projet versionné et
      inchangé sans raison ; toute version modifiée a au moins deux semaines,
      licence vérifiée, `LicensesView` et `PatchNode/Licenses/` à jour (CLAUDE.md).

## 2. iCloud (depuis la 1.1)
- [ ] CloudKit Console › conteneur `iCloud.fr.antxis.apple.labwatch` ›
      **Deploy Schema Changes** vers *Production* (sinon la synchro échoue chez
      les utilisateurs).
- [ ] Après une modification du schéma SwiftData : nouvelle version (V3…), seuls
      des ajouts, puis redéployer.

## 3. Archive
- [ ] Product › Archive (schéma Release, appareil générique).
- [ ] Vérifier l'archive :
      `codesign -d --entitlements - PatchNode.app` → `aps-environment` =
      `production`, conteneur iCloud correct, App Group présent ; l'extension
      widgets n'a pas d'entitlement iCloud.
- [ ] `PrivacyInfo.xcprivacy` présent dans l'app et l'extension.
- [ ] Distribute App › App Store Connect › Upload.

## 4. TestFlight
- [ ] Build traité, conformité de chiffrement. **1.2 : à revoir avant la soumission.**
      Jusqu'à la 1.1, seul HTTPS via les frameworks Apple (`ITSAppUsesNonExemptEncryption
      = NO`). La 1.2 ajoute SSH (algorithmes standard : ed25519, curve25519, AES-GCM,
      ChaCha20-Poly1305) implémenté par SwiftNIO SSH et Swift Crypto, hors frameworks du
      système. Répondre au questionnaire d'export d'App Store Connect (chiffrement
      standard, exemption grand public) et ajuster la clé en conséquence.
- [ ] Installation via TestFlight sur l'iPhone **par-dessus la version publiée** :
      services et jetons conservés, démo, une action, un widget.
- [ ] Si iCloud a changé : deux appareils sur le même compte, en production.

## 5. Fiche App Store (5 langues : en, fr, es, de, it)
- [ ] `docs/appstore/description.md` : sous-titre, mots-clés, texte
      promotionnel, description, **Nouveautés** de la version, collés dans
      chaque langue.
- [ ] Captures (`docs/appstore/screenshots.md`) si l'interface a changé.
- [ ] App Privacy (`docs/appstore/app-privacy.md`) : questionnaire relu,
      toujours « Data Not Collected ».
- [ ] URL de confidentialité et d'assistance valides.
- [ ] Notes pour la review (`docs/appstore/review-notes.md`) collées.

## 6. Site `patchnode-site`
- [ ] `python3 scripts/build-site.py` ; copier `site/` dans le dépôt public
      `Patchbay-s/PatchNode/site` ; vérifier les 5 langues et la date de la
      politique de confidentialité.

## 7. Soumission et publication
- [ ] Sélectionner le build, choisir **publication manuelle**.
- [ ] Soumettre ; répondre aux questions d'App Review depuis App Store Connect.
- [ ] Une fois acceptée : **Publier** manuellement au moment voulu.
- [ ] Tag git : `git tag -a v1.1 -m "PatchNode 1.1" <commit de l'archive>` puis
      `git push origin v1.1`.
- [ ] docs/ROADMAP.md : version marquée publiée, backlog reporté sur la suivante.
