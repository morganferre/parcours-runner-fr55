# Parcours Runner – Forerunner 55

[English](README.md) · **Français**

Application Connect IQ pour la **Garmin Forerunner 55** : suivez un parcours GPX sur la montre,
avec les rues OpenStreetMap autour, et enregistrez une vraie activité **Course à pied** ou **Vélo**
(synchronisée avec Garmin Connect et Strava : GPS, distance, allure, FC, cadence, tours).

- carte du parcours avec rues, chemins et cours d'eau, déjà couru en couleur ;
- alerte (vibration + bip) quand on sort du parcours ;
- distance restante, anneau de progression ;
- 3 écrans de course (carte, données, tour), tour automatique ;
- tout fonctionne hors ligne pendant la course : parcours et rues sont rangés dans la montre ;
- montre en français ou en anglais, selon la langue réglée sur la montre ;
- plusieurs parcours dans la montre, **envoyés sans câble** depuis le téléphone.

**Site : [https://morganferre.github.io/parcours-runner-fr55/](https://morganferre.github.io/parcours-runner-fr55/)** : dessinez un parcours au doigt (il suit
les rues) ou importez un GPX, le site ajoute les rues autour et l'envoie à la montre.

## Démarrage rapide

Il faut un PC Windows (les scripts d'installation sont en PowerShell), une Forerunner 55 et un câble USB.

### 1. Installer les outils (une seule fois)

1. **Python 3** : <https://www.python.org/downloads/> (cochez « Add Python to PATH »).
   Aucune bibliothèque supplémentaire n'est nécessaire.
2. **SDK Connect IQ** : téléchargez le *SDK Manager* sur
   <https://developer.garmin.com/connect-iq/sdk/>, puis installez le dernier SDK
   et l'appareil **Forerunner 55** depuis le SDK Manager.
3. **VS Code** + l'extension **Monkey C** (de Garmin).
4. **Clé développeur** : dans VS Code, `Ctrl+Maj+P` › `Monkey C: Generate a Developer Key`.
   Elle sert à signer l'appli. Rangez-la **en dehors** du projet et ne la partagez jamais :
   les scripts la retrouvent tout seuls via les réglages de VS Code.

### 2. Récupérer le projet

```
git clone https://github.com/morganferre/parcours-runner-fr55.git
cd parcours-runner-fr55
```

(ou bouton **Code › Download ZIP** sur GitHub).

### 3. Préparer un parcours

**Pas encore de GPX ?** Créez-le, même depuis le téléphone, avec [gpx.studio](https://gpx.studio)
(gratuit, dans le navigateur) : touchez la carte pour poser les points, le tracé suit les rues
et les chemins (choisissez à pied ou à vélo), puis **Exporter** › GPX. Garmin Connect, Strava,
Komoot ou Visorando savent aussi exporter un parcours en GPX.

Copiez le GPX dans le dossier `tools\` du projet (les `tools\*.gpx` ne sont jamais publiés), puis
dans un terminal, depuis le dossier du projet :

```
python tools\prepare_route.py tools\mon_parcours.gpx
```

Le script télécharge les rues autour du parcours (OpenStreetMap, connexion Internet nécessaire),
les intègre à l'appli et compile `bin\ParcoursRunner.prg`.

Plusieurs parcours : donnez plusieurs GPX d'un coup. La montre affiche alors un menu **Parcours**
à l'ouverture (le nom vient du nom du fichier, `_` remplacés par des espaces) :

```
python tools\prepare_route.py tools\tour_du_lac.gpx tools\centre_ville.gpx tools\foret.gpx
```

Les rues de tous les parcours doivent tenir dans la montre (environ 110 Ko) : le script affiche
la place prise par chacun.

### Envoyer un parcours sans câble (via le téléphone)

**Le plus simple : le [site](https://morganferre.github.io/parcours-runner-fr55/)**, depuis le téléphone ou le PC.
1. Dessinez le parcours (touchez la carte, le tracé suit les rues, à pied ou à vélo) ou importez un GPX.
2. **Préparer les rues**, puis **Envoyer vers la montre**. La première fois, le site demande une
   clé GitHub limitée aux gists (un lien la crée en un clic) : elle reste dans votre navigateur.

Ou depuis le PC, avec le script :

```
python tools\prepare_route.py tools\mon_parcours.gpx --upload
```

Le parcours et ses rues partent dans un **gist GitHub secret** de votre compte (créé au premier
envoi, son adresse est gardée dans `tools\gist.txt`, non versionné). Le compte GitHub utilisé est
celui connecté à git sur le PC. Au premier envoi, l'appli est recompilée pour connaître ce gist :
installez-la une fois par câble.

Ensuite, sur la montre : **Parcours › Télécharger...** (téléphone à proximité avec Garmin Connect).
La montre reçoit environ 1 Ko/s : quelques secondes pour un petit parcours, environ 15 s pour 6 km
en ville. Un parcours renvoyé avec le même nom remplace l'ancien dans la liste en ligne (la liste
peut mettre quelques minutes à se rafraîchir).

**Parcours › Gérer...** affiche la place utilisée et permet de supprimer un parcours de la montre
(un parcours intégré à l'appli revient si vous réinstallez une nouvelle version de l'appli).

Options utiles :

| Option | Effet |
|---|---|
| `--width 400` | bande de rues plus large autour du parcours (défaut 300 m) |
| `--points 2000` | tracé plus précis (défaut : 60 points par km, jusqu'à 4 000) |
| `--reverse` | parcourir le GPX dans l'autre sens |
| `--flip-start` | aller-retour : partir de l'autre bout |
| `--name "Tour du lac"` | nom du parcours (avec un seul GPX) |
| `--key chemin\developer_key` | clé développeur, si elle n'est pas réglée dans VS Code |
| `--no-map` | revenir à la version sans parcours intégré |

### 4. Installer sur la montre

Branchez la montre en USB, puis :

```
powershell -ExecutionPolicy Bypass -File tools\install_watch.ps1
```

Ou copiez `bin\ParcoursRunner.prg` dans `GARMIN\APPS` avec l'Explorateur.
L'appli apparaît dans la liste des activités (bouton START depuis le cadran),
sous le nom **Parcours Runner**.

Au premier lancement d'un nouveau parcours, la montre range les rues dans son stockage
(quelques secondes, « Préparation rues... » en bas de la carte).

Pour changer les parcours de la montre : relancez l'étape 3 avec d'autres GPX, puis l'étape 4.

## Pendant la course

À l'ouverture de l'appli, choisissez le **parcours** (s'il y en a plusieurs), puis **Course à pied**
ou **Vélo** (START à chaque fois ; les derniers choix sont présélectionnés). Le GPS cherche pendant ce temps. En vélo, les allures sont remplacées par une
vitesse en km/h et le tour automatique est séparé (5 km par défaut).

| Bouton | Avant le départ | Pendant la course | En pause |
|---|---|---|---|
| **START** | démarrer | pause + menu | menu pause |
| **BACK** | retour au menu Parcours (ou quitter) | nouveau tour | menu pause |
| **UP / DOWN** | changer d'écran | changer d'écran | changer d'écran |
| **UP maintenu** | réglages | réglages | réglages |

Menu pause : **Reprendre**, **Enregistrer** (résumé puis sortie), **Supprimer** (avec confirmation).

Les écrans :
1. **Carte** : parcours, rues, distance restante en haut, allure et FC en bas.
2. **Données** : temps, distance, allure, FC.
3. **Tour** : temps et allure du tour en cours, distance du tour, allure moyenne.

Tour automatique tous les km (tous les 5 km en vélo, réglable) : vibration et fenêtre « TOUR 3 » avec l'allure du tour.

Réglages (UP maintenu) : zoom, orientation, rues oui/non, fond noir ou blanc, tour automatique.

## Bon à savoir

- La FR55 n'affiche que 8 couleurs. Sur fond noir : parcours **blanc**, déjà couru **magenta**
  (comme l'anneau de progression), rues **bleu** (grands axes en épais), chemins **vert**,
  cours d'eau et lacs **cyan**, vous en **jaune**, hors parcours en **rouge**.
- Les rues sont dessinées jusqu'au zoom 300 m. En ville très dense, les carrés les plus éloignés
  peuvent manquer : la montre limite le dessin pour ne jamais dépasser le temps autorisé.
  Si le script signale trop de rues, relancez avec `--width 200`.
- Si l'appli est fermée pendant une course (batterie vide...), la course est enregistrée automatiquement.
- Une appli copiée par USB ne peut pas être réglée depuis le téléphone : utilisez le menu UP maintenu.

## Tester dans le simulateur

1. Dans VS Code : `Ctrl+Maj+P` › `Monkey C: Run`, choisissez **Forerunner 55**.
2. **Simulation › Activity Data** : chargez le même GPX que le parcours préparé, puis **▶**.
3. Cliquez sur les boutons dessinés autour de la montre (START, BACK, UP, DOWN).

La langue se change dans le simulateur via **Settings › Language**.

`tools\simulator.ps1` automatise tout ça (compilation, lancement, clics, captures d'écran) :

```
powershell -File tools\simulator.ps1 -Build -Run -Keys "down,start" -Shot essai
```

## Langues

Les textes de la montre sont dans `resources/strings/strings.xml` (anglais, langue par défaut)
et `resources-fre/strings/strings.xml` (français). La montre choisit automatiquement selon sa langue.

Pour ajouter une langue : copiez `resources-fre` en `resources-<code>` (par exemple `resources-spa`
pour l'espagnol, `resources-deu` pour l'allemand), traduisez les textes, puis ajoutez
`<iq:language><code></iq:language>` dans `manifest.xml`.

## Organisation du code

```
source/ParcoursRunnerApp.mc        démarrage, GPS, cardio, minuterie
source/Util.mc                     réglages, textes traduits, mise en forme des temps et allures
source/RoutePack.mc                GÉNÉRÉ par tools/prepare_route.py (parcours et rues intégrés)
source/activity/RunSession.mc      enregistrement FIT (course ou vélo), pause, tours, allures
source/route/Route.mc              points du parcours (intégré ou collé depuis le téléphone)
source/route/RouteTracker.mc       position sur le parcours, progression, alerte hors parcours
source/route/RouteStore.mc         liste des parcours de la montre, parcours choisi
source/route/RouteInstaller.mc     copie des rues des parcours dans la montre (1er lancement)
source/route/RouteDownloader.mc    téléchargement d'un parcours depuis le gist secret
source/map/RouteMap.mc             écran carte : position, cap, animation, dessin
source/map/StreetTiles.mc          rues : installation dans la montre, carrés autour de la position
source/map/StreetLayer.mc          rues : dessin en arrière-plan dans deux images alternées
source/ui/MainView.mc              les 3 écrans (carte, données, tour)
source/ui/MainDelegate.mc          boutons
source/ui/RouteMenu.mc             menu Parcours (choix, Télécharger, Gérer / supprimer)
source/ui/DownloadView.mc          liste en ligne et téléchargement avec barre de progression
source/ui/SportMenu.mc             choix course à pied / vélo à l'ouverture
source/ui/PauseMenu.mc             menu pause (reprendre, enregistrer, supprimer)
source/ui/SettingsMenu.mc          menu réglages (UP maintenu)
source/ui/SummaryView.mc           résumé de fin
resources/route_pack/              GÉNÉRÉ par tools/prepare_route.py (non versionné)
resources*/strings/                textes de la montre, par langue
tools/                             préparation et envoi des parcours, installation, simulateur, polices
tools/debug/                       tests : fausse sortie au simulateur, téléchargement, site = script
docs/                              le site (GitHub Pages) : dessin, rues (prepare.js = prepare_route.py), envoi
```

`tools/generate_fonts.py` régénère les polices de chiffres (nécessite Pillow et la police
Bahnschrift de Windows) ; inutile sauf pour modifier leur dessin.

## Données cartographiques

Les rues proviennent d'[OpenStreetMap](https://www.openstreetmap.org/copyright)
© les contributeurs OpenStreetMap, sous licence ODbL, téléchargées via l'API Overpass.

## Licence

Code sous licence [MIT](LICENSE) : libre d'utilisation, de modification et de redistribution,
à condition de conserver la mention de copyright. Fourni sans garantie.
