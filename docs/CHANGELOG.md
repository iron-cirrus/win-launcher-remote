# CHANGELOG — historique des modifications

> Règle : **chaque** modification du code ajoute une entrée ici, en tête de fichier
> (date, fichiers touchés, quoi et pourquoi). Documenter les suppressions est aussi
> important que les ajouts : cela évite de réintroduire une approche abandonnée.

## 2026-11-24 — suppression du masquage des barres des tâches secondaires (module 14)

**Motif** : cela fonctionnait mal. Explorer recrée les fenêtres `Shell_SecondaryTrayWnd`
à chaque changement d'écrans ou redémarrage ; la course contre lui (cache toutes les 5 s
via le watchdog) était perdue et l'effet était irrégulier.

Fichiers touchés :

- **`14-barres-secondaires.ps1` — supprimé** (type C# `VscBarsV1` avec `HideSecondary()`,
  scriptblock `$script:HideSecondaryBars`).
- `start.ps1` : dot-source de `14-barres-secondaires.ps1` retiré — la liste des
  fondations s'arrête de nouveau à `13-panneau-haut.ps1`.
- `ui-90-watchdog-fenetres.ps1` : `OpenCheckTick` n'appelle plus
  `& $script:HideSecondaryBars` à chaque tick (5 s).
- `ui-95-watchdog-ping.ps1` : appel initial `& $script:HideSecondaryBars`
  (au démarrage, avant les timers) retiré.

**Conséquence** : les barres des tâches des écrans secondaires restent visibles, comme
sous Windows standard. La barre principale (`Shell_TrayWnd`) n'a jamais été touchée.

## 2026-11-23 — commit `90d2379` : sunshine limit + daemon barre secondaire

Ajout du module 14 (masquage des barres secondaires) — **annulé le 2026-11-24, voir
l'entrée ci-dessus**. L'historique de ce fichier commence à cette date ; les commits
antérieurs ne sont pas détaillés ici (voir `git log`).
