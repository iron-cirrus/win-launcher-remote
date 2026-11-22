# VSC Launcher — documentation (humains)

Lanceur de machines sous forme de **cartes colorees** (WinForms / PowerShell 5.1).
Un clic sur une carte ouvre la machine : VS Code Remote-SSH (Linux), Moonlight ou RDP (Windows), VNC, terminal SSH.

> Documents voisins : [FUNCTIONS.md](FUNCTIONS.md) (reference de chaque fonction, generee) ·
> [STATE.md](STATE.md) (variables d'etat, timers, fichiers ecrits) · [AI-CONTEXT.md](AI-CONTEXT.md) (regles pour une IA) ·
> [api-index.json](api-index.json) (index lisible par machine).

## Lancer

```powershell
powershell -ExecutionPolicy Bypass -File C:\app\win-launcher-remote\start.ps1
```

`start.ps1` est a la RACINE du depot `win-launcher-remote` (ancien `C:\app\vsc_launcher.ps1`, puis `vsc_launcher\start.ps1`) et charge ses modules depuis son propre dossier. Le script se relance seul dans un processus neuf
si la console a deja affiche une fenetre WinForms (sinon d'anciens minuteurs survivent et agissent sur les nouvelles cartes).

## Ce que fait l'application

- **Liste des machines dynamique** : lue dans `~\.ssh\config` (alias `Vm-Nom_Hote` = VM hebergee sur `Hote` ; un `@` dans un alias est interdit).
- **Machines Windows du LAN** : trouvees par un scan du port RDP 3389 (tache de fond), mises en cache dans `%LOCALAPPDATA%\vsc-launcher\network-cache.json`.
- **Une colonne par hote**, la carte du serveur en tete puis ses VM. Les cartes injoignables sont masquees/grisees.
- **Pastille de ping** (watchdog 15 s) : « 12 ms » / « KO » — le statut n'est jamais porte par la couleur seule (palette adaptee au daltonisme).
- **Detection des fenetres deja ouvertes** (watchdog 5 s) : un clic ramene la fenetre VS Code existante au lieu d'en ouvrir une autre.
- **Windows** : mini-carte des ecrans du poste (clic / glisser / Ctrl) pour choisir sur quels ecrans ouvrir Moonlight (profil de resolution genere, fenetre calee, reconnexion automatique) ou mstsc.
- **Linux** : icone Moonlight si Sunshine repond ; icones VNC et SSH selon les ports/sessions detectes.
- **Outils** : deploiement des couleurs sur les hotes, miroir de dossiers de dev, synchronisation des conversations Zoo Code, journal.

## Architecture en un coup d'oeil

```
win-launcher-remote\   (racine du depot git)
   ├─ start.ps1            point d'entree (85 lignes)
   ├─ 01..13-*.ps1         FONDATIONS : P/Invoke, couleurs, machines, ecrans, Moonlight/RDP, disposition, panneau haut
   ├─ ui-10..ui-95-*.ps1   CONTENU de $script:BuildUI (construction de la fenetre, rejouable)
   │   └─ ui-50-cartes.ps1 boucle « une carte par machine » → cartes\01..09-*.ps1
   ├─ cartes\              les 9 etapes de construction d'UNE carte
   └─ docs\                cette documentation + generateur
```

Tout est charge par **dot-source** : tous les fichiers partagent **la meme portee script**. Decouper le code en fichiers n'a rien change au comportement.

### Ordre d'execution

1. `start.ps1` : garde « processus neuf », puis dot-source de `01` a `13`.
2. Definition de `$script:BuildUI` (qui dot-source `ui-10` a `ui-95`) et de `$script:RebuildUI`.
3. `. $script:BuildUI` puis `$form.ShowDialog()` — appele **une seule fois**.
4. A la fin du scan LAN, `RebuildUI` reconstruit les cartes **dans la fenetre existante** (la fenetre ne bouge pas).
5. Apres la fermeture : arret des timers et des jobs.

## Les fichiers

### Fondations (`01..13` a la racine)

| Fichier | Contenu |
|---|---|
| `01-win32-interop` | Types C# `VscWinV4` / `VscScrV3` : enumeration/deplacement de fenetres (noms versionnes, voir pieges). |
| `02-machines-couleurs` | Couleur de carte par alias (`$KnownColors`), palette de secours, roles lisibles (`$Notes`). |
| `03-machines-liste` | `Get-SshHosts`, construction de `$Machines`, fusion du cache LAN (`MergeLanCache`). |
| `04-moonlight-reglages` | `ConvertTo-DrawingColor`, `code.exe`, chemin Moonlight, application (« Virtual Display »), plafonds de resolution Linux. |
| `05-ecrans` | Ecrans locaux (`GetScreens`), etats de session (`MlState`, `RdpState`), icones attenuees. |
| `06-moonlight-profil` | Profil Moonlight genere depuis les ecrans, validation de contiguite, mini-carte (`MapLayout`…), `PlaceOnScreen`, `WatchMoonlight` (reconnexion). |
| `07-mstsc` | Ouverture RDP sur les ecrans choisis, repli RDP. |
| `08-clients-distants` | Scan des clients Moonlight/mstsc deja ouverts. |
| `09-moonlight-garde` | Garde de taille des fenetres, session/app courante de l'hote, lancement, « quitter puis relancer ». |
| `10-ouvrir-hote-windows` | `OpenWindowsHost` (Moonlight sinon RDP) + recherche des icones VNC/VS Code/SSH. |
| `11-icones-disposition` | Icones pre-rendues (`NewIconBmp`), ecran d'accueil, `Relayout` (disposition adaptative). |
| `12-sunshine` | Sonde Sunshine (ports 47989/47984/47990/48010), icone Moonlight des cartes. |
| `13-panneau-haut` | Mini-carte globale des ecrans + liste des sessions distantes. |

### Construction de l'interface (`ui-*` a la racine)

| Fichier | Contenu |
|---|---|
| `ui-10-fenetre-colonnes` | Dimensions, regroupement par hote, ordre des colonnes. |
| `ui-20-fenetre` | Creation unique de la fenetre ; a la reconstruction, liberation des anciens controles. |
| `ui-30-journal` | Zone de log, fleche d'ouverture, `LogFn`. |
| `ui-40-scan-lan` | Scan du LAN (job de fond `NetScanBlock`). |
| `ui-50-cartes` | Boucle sur les machines → `cartes\*`. |
| `ui-60-deploiement` | `RunTimeout`, deploiement des couleurs, miroir de dossiers de dev. |
| `ui-70-sync-zoo` | Job de fond de synchronisation des conversations Zoo Code. |
| `ui-80-pied-de-page` | Boutons du bas (deployer, synchroniser, fermer). |
| `ui-90-watchdog-fenetres` | `OpenCheckTick` (5 s) : fenetres VS Code, VNC, SSH, Sunshine, sessions. |
| `ui-95-watchdog-ping` | `PingTick` (15 s), `PingCollect` (250 ms), style des cartes, timers, suivi du scan LAN. |

### Etapes d'une carte (`cartes\`)

`01-fond-filigrane` → `02-textes` → `03-logo-vscode` → `04-icone-vnc` → `05-icone-ssh` → `06-clics-survol` → `07-ecrans-windows` → `08-icone-sunshine` → `09-finalisation`.
L'ordre est l'ordre alphabetique des noms ; un nouveau fichier ajoute dans ce dossier est execute automatiquement.

## Ou modifier quoi

| Je veux… | Fichier |
|---|---|
| changer la couleur / le role d'une machine | `02-machines-couleurs.ps1` |
| changer l'application Moonlight, les plafonds de resolution | `04-moonlight-reglages.ps1` |
| changer la taille/disposition des cartes | `ui-10-fenetre-colonnes.ps1` (constantes) et `11` (`Relayout`) |
| ajouter une icone sur les cartes | nouveau fichier dans `cartes\` + `NewIconBmp` (`11`) |
| changer les intervalles de ping / watchdog | `ui-95-watchdog-ping.ps1` (`Interval`) |
| changer ce que fait un clic sur une carte | `cartes\06-clics-survol.ps1` (Linux/local), `10-ouvrir-hote-windows.ps1` (Windows) |
| exclure des dossiers du miroir de dev | `ui-60-deploiement.ps1` (`$script:WsExcludes`) |

## Fichiers ecrits sur le poste

Tout dans `%LOCALAPPDATA%\vsc-launcher\` : `network-cache.json`, `screen-choice.json`, `moonlight-profiles.json`, `alive-memo.json`, `launcher.log`, `rdp\`. Voir [STATE.md](STATE.md).

## Pieges connus

- **Handlers = pas de `function`** : un handler d'evenement WinForms s'execute plus tard, hors de la portee du script. On utilise donc des scriptblocks `$script:Nom` appeles par `& $script:Nom`.
- **Types C# versionnes** (`VscWinV4`…) : un `Add-Type` reste charge pour toute la session ; changer le C# impose de changer le nom du type.
- **`@` interdit dans un alias SSH** : VS Code l'interprete comme `user@host`.
- **Le thread UI ne doit jamais bloquer** : pings, scans, sondes de ports sont asynchrones ; les taches longues sont des `Start-Job`.
- **Palette daltonisme** : ne pas remplacer symboles/formes par de la couleur seule.
- **Numeros de ligne** de `FUNCTIONS.md` : perimes apres une edition ; relancer `docs\generate-api-docs.ps1`.

## Sauvegardes

`vsc_launcher.ps1.bak-avant-*` (restes dans `C:\app`, hors depot) sont les versions monolithiques d'avant decoupage ; `ui-50-cartes.ps1.bak-avant-decoupage` aussi. Ils ne sont plus utilises.
