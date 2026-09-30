# Parcours Runner – Forerunner 55

[English](README.md) · **Français**

Application Connect IQ pour la **Garmin Forerunner 55** : suivez un parcours GPX sur la montre,
avec les rues OpenStreetMap autour, et enregistrez une vraie activité **Course à pied**
(synchronisée avec Garmin Connect et Strava : GPS, distance, allure, FC, cadence, tours).

- carte du parcours avec rues, chemins et cours d'eau, déjà couru en couleur ;
- alerte (vibration + bip) quand on sort du parcours ;
- distance restante, anneau de progression ;
- 3 écrans de course (carte, données, tour), tour automatique ;
- tout fonctionne hors ligne : le parcours et les rues sont intégrés à l'appli ;
- montre en français ou en anglais, selon la langue réglée sur la montre.

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

Exportez votre parcours en GPX (Garmin Connect, Strava, Komoot, Visorando…), puis dans un terminal,
depuis le dossier du projet :

```
python tools\prepare_route.py chemin\vers\mon_parcours.gpx
```

Le script télécharge les rues autour du parcours (OpenStreetMap, connexion Internet nécessaire),
les intègre à l'appli et compile `bin\ParcoursRunner.prg`.

Options utiles :

| Option | Effet |
|---|---|
| `--width 400` | bande de rues plus large autour du parcours (défaut 300 m) |
| `--points 2000` | tracé plus précis (défaut : 60 points par km, jusqu'à 4 000) |
| `--reverse` | parcourir le GPX dans l'autre sens |
| `--flip-start` | aller-retour : partir de l'autre bout |
| `--name "Tour du lac"` | nom du parcours |
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

Pour changer de parcours : relancez l'étape 3 avec un autre GPX, puis l'étape 4.

## Pendant la course

| Bouton | Avant le départ | Pendant la course | En pause |
|---|---|---|---|
| **START** | démarrer | pause + menu | menu pause |
| **BACK** | quitter l'appli | nouveau tour | menu pause |
| **UP / DOWN** | changer d'écran | changer d'écran | changer d'écran |
| **UP maintenu** | réglages | réglages | réglages |

Menu pause : **Reprendre**, **Enregistrer** (résumé puis sortie), **Supprimer** (avec confirmation).

Les écrans :
1. **Carte** : parcours, rues, distance restante en haut, allure et FC en bas.
2. **Données** : temps, distance, allure, FC.
3. **Tour** : temps et allure du tour en cours, distance du tour, allure moyenne.

Tour automatique tous les km (réglable) : vibration et fenêtre « TOUR 3 » avec l'allure du km.

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
source/ParcoursRunnerApp.mc   démarrage, GPS, cardio, minuterie
source/RunSession.mc          enregistrement FIT, pause, tours, allures
source/RouteMap.mc            parcours, rues, position, hors-parcours, dessin de la carte
source/Views.mc               les 3 écrans et le résumé de fin
source/Input.mc               boutons, menu pause, menu réglages
source/Util.mc                réglages, textes traduits, mise en forme des temps et allures
source/RoutePack.mc           GÉNÉRÉ par tools/prepare_route.py (parcours et rues intégrés)
resources/route_pack/         GÉNÉRÉ par tools/prepare_route.py (non versionné)
resources*/strings/           textes de la montre, par langue
tools/                        préparation des parcours, installation, simulateur, polices, convertisseur web
```

`tools/converter.html` (à ouvrir dans un navigateur) transforme un GPX en texte à coller dans les
réglages de l'appli depuis le téléphone : parcours seul, sans les rues, et seulement si l'appli
est installée depuis le Connect IQ Store.

`tools/generate_fonts.py` régénère les polices de chiffres (nécessite Pillow et la police
Bahnschrift de Windows) ; inutile sauf pour modifier leur dessin.

## Données cartographiques

Les rues proviennent d'[OpenStreetMap](https://www.openstreetmap.org/copyright)
© les contributeurs OpenStreetMap, sous licence ODbL, téléchargées via l'API Overpass.

## Licence

Code sous licence [MIT](LICENSE) : libre d'utilisation, de modification et de redistribution,
à condition de conserver la mention de copyright. Fourni sans garantie.
