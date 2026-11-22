# AI-CONTEXT — lire AVANT de modifier le code

Projet : lanceur WinForms en **PowerShell 5.1** (Windows). Entree : `C:\app\vsc_launcher.ps1` ; modules : `C:\app\vsc_launcher\`.
Index machine : [api-index.json](api-index.json) (fichier → blocs → lignes → description). Reference lisible : [FUNCTIONS.md](FUNCTIONS.md). Etat : [STATE.md](STATE.md). Vue humaine : [README.md](README.md).
Langue des commentaires et du journal : **francais, sans accents dans le code** (ASCII dans les chaines de log, les accents sont tolerables mais les fichiers sont en UTF-8 **avec BOM** — a conserver, PS 5.1 en a besoin).

## Modele d'execution (a comprendre d'abord)

1. Tous les fichiers sont charges par **dot-source** (`. chemin`) → **meme portee script**. Aucun fichier n'est un module : pas de `Export-ModuleMember`, pas de `Import-Module`.
2. Ordre de chargement : `01..13` (fondations) puis `$script:BuildUI` = `ui-10 … ui-95`. `ui-50-cartes.ps1` compile `cartes\*.ps1` (tri alphabetique) en scriptblocks **une fois**, puis les execute par dot-source **a chaque carte** dans `foreach ($m in $MachinesOrd)`.
3. `BuildUI` est **rejouable** : `RebuildUI` l'execute a nouveau apres un scan LAN, dans la **meme fenetre** (`$form` non recree). Tout code de `ui-*`/`cartes\*` doit donc etre **idempotent** et liberer ce qu'il cree (GDI+, timers). `$script:Rebuild` vaut `$true` lors d'une reconstruction.
4. Les variables « locales » du code de `ui-*` et `cartes\*` ($m, $card, $form, $cardW, $winW, $btnY, $MachinesOrd…) vivent en **portee script** : elles sont partagees entre fichiers et lisibles par les handlers. Ne pas les renommer sans grep global.
5. Ajouter un fichier : `vsc_launcher\NN-nom.ps1` n'est PAS charge automatiquement → l'ajouter dans la liste de `vsc_launcher.ps1`. Un fichier dans `cartes\` est, lui, charge automatiquement. Un fichier `ui-*` doit etre ajoute dans le bloc `$script:BuildUI` de `vsc_launcher.ps1`.

## Invariants — NE PAS casser

- **Pas de `function` appelee depuis un handler d'evenement** (Add_Click, Add_Paint, Add_Tick…). Les handlers s'executent plus tard hors portee. Utiliser un scriptblock `$script:Nom = { param(...) ... }` et l'appeler `& $script:Nom arg1 arg2`. (Exceptions existantes : `Get-SshHosts`, `ConvertTo-DrawingColor`, appelees au chargement uniquement.)
- **Timers en portee `$script:`** (`$script:PlaceTimer`, `$script:SyncTimer`…) : un `Add_Tick` lit ses variables plus tard. Les timers du watchdog (`$openTimer`, `$pingTimer`, `$pingCollectTimer`, `$netTimer`) sont arretes et liberes par `RebuildUI` et a la fermeture.
- **Ne jamais bloquer le fil UI** : pas de `Ping.Send` synchrone, pas de `GetHostEntry` sans attente bornee, pas de `Start-Process -Wait` long. Reseau = asynchrone (`BeginConnect`, `SendPingAsync`) ou `Start-Job` (`NetScanBlock`, `SyncJobBlock`) ; sondes bornees (~800 ms).
- **Types `Add-Type` versionnes** : modifier le C# de `VscWinV4` / `VscScrV3` / `VscDispV1` impose de **changer le nom du type** (V5…) ET ses references.
- **Un alias `.ssh/config` ne contient jamais `@`**. Convention `Vm-Nom_Hote` : coupe au DERNIER `_` ; suffixe = hote parent.
- **Accessibilite** : etat jamais porte par la couleur seule (formes, symboles, texte). Palette `02-machines-couleurs.ps1` calculee pour le daltonisme.
- **GDI+** : tout `Bitmap/Pen/Brush/Font` cree dans une boucle de cartes est libere (`Dispose`) ou mis en cache en `$script:Bmp*`. `Control.Dispose` ne libere pas `BackgroundImage`.
- **Dessin pre-rendu** : filigrane et icones sont rendus UNE fois dans un bitmap (`NewIconBmp`), pas a chaque Paint.
- **Handlers `param($s, $e)`** : `$s` = expediteur ; les proprietes custom sont posees par `Add-Member` sur les controles (ex. `RdpIp`, `OpenState`, `Disabled`, `DarkColor`, `NormalColor`, `VscBmp`).
- Fin de script : `ShowDialog` est appele **une seule fois** ; apres lui, nettoyage des timers/jobs.

## Carte des responsabilites (qui appelle qui)

```
ShowDialog <- BuildUI
BuildUI:  ui-10 (tailles/colonnes) -> ui-20 (Form) -> ui-30 (LogFn) -> ui-40 (Start-Job NetScanBlock)
          -> ui-50 (cartes\01..09) -> ui-60 (DeployColors, SyncWorkspace) -> ui-70 (SyncJobBlock)
          -> ui-80 (boutons) -> ui-90 (OpenCheckTick) -> ui-95 (PingTick/PingCollect + Timers + suivi scan)
Clic carte Windows  -> OpenWindowsHost (10) -> LaunchMoonlightNow / QuitThenLaunch (09)
                                              -> PlaceOnScreen + WatchMoonlight (06) ; repli RdpFallback/OpenMstsc (07)
Selection d'ecrans   -> ResolveSelection / SetSelection (06) -> SaveScreenChoice -> BuildMoonlightProfile
Etat des sessions    -> SetMlState (05) -> MlState/RdpState -> RefreshTop/RefreshSessionTags (13)
Disposition          -> Relayout (11) lit LayoutItems, HomeScreen, UiWinW/Hc/H, LogBox
Fin de scan LAN      -> netTimer (ui-95) -> RebuildUI -> MergeLanCache (03) + BuildUI
Journal              -> & $script:LogFn "texte"   (disponible a partir de ui-30)
```

Attention : `LogFn` n'existe qu'apres `ui-30` ; les modules `01..13` testent `if ($script:LogFn)` avant de journaliser.

## Recettes

- **Trouver une fonction** : chercher le nom dans `docs\api-index.json` (champ `file`, `lineStart`), ou `Grep '\$script:Nom = \{'`.
- **Ajouter une etape de carte** : creer `cartes\NN-nom.ps1` ; elle voit `$m`, `$card`, `$cardW`, `$cardH`, `$lblLabel`… et doit ajouter ses controles a `$card.Controls` (avant `09-finalisation`, qui fait `AddRange` et le z-order).
- **Ajouter un reglage** : declarer `$script:Nom = valeur` dans le fichier `04-`/`06-` concerne, avec un commentaire expliquant l'unite.
- **Valider apres modification** : analyser chaque fichier avec `[System.Management.Automation.Language.Parser]::ParseFile` (0 erreur), puis lancer le script ~20 s et verifier l'absence d'erreur sur stderr (`Start-Process powershell -File ... -RedirectStandardError`). Un test fonctionnel reel (clic, Moonlight) exige l'utilisateur.
- **Regenerer la doc** : `powershell -NoProfile -File C:\app\vsc_launcher\docs\generate-api-docs.ps1` (met a jour `FUNCTIONS.md` et `api-index.json`). Ajouter une description manuelle dans `descriptions.psd1` pour un bloc sans commentaire.
- **Ne pas** deplacer un bloc `$script:X = {` apres le premier code qui l'appelle : l'ordre de definition compte (les blocs sont appeles a l'execution, mais `. $script:MergeLanCache` et `UpdateHome` s'executent des le chargement).

## Fichiers et dossiers ignorables

`C:\app\*.bak-*`, `C:\app\vsc_launcher.ps1.bak-*` : anciennes versions monolithiques (reference historique uniquement).
Autres scripts de `C:\app` (`openapp*.ps1`, `scan.ps1`, `guimap2.ps1`…) : hors perimetre du launcher.
