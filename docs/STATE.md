# Etat, timers, taches de fond, fichiers

Toutes les variables ci-dessous sont en portee `$script:` (partagee par tous les fichiers). Detail des fonctions : [FUNCTIONS.md](FUNCTIONS.md).

## Donnees de reference (construites au chargement)

| Variable | Definie dans | Contenu |
|---|---|---|
| `$Machines` | `03`, completee par `MergeLanCache` | Liste des cartes : Host (alias), HostName, User, Port, IdentityFile, Label, Parent, Group, Role, Color/Dark/Fg, IconType (`pc`/`srv`), OsType, RdpIp (machines LAN Windows). |
| `$KnownColors`, `$Palette`, `$Notes` | `02` | Couleur par alias ; palette de secours ; role lisible. |
| `$script:BadAliases`, `StartupNotes` | `03` | Alias invalides (`@`) ; notes ecrites au journal au demarrage. |
| `$script:Screens`, `ScreensSig` | `05`, rafraichi par `OpenCheckTick` | Ecrans locaux (Idx, X, Y, W, H). |
| `$script:CodeExe`, `MoonlightExe`, `VncViewerExe` | `04`, `10` | Executables detectes. |
| `$script:VncIconBmp`, `VscIconBmp`, `SshIconBmp`, `Bmp*`, `MlIcon*`, `RdpIcon20*` | `05`, `10`, `11` | Icones en cache (liberees seulement a la fermeture). |

## Etat dynamique

| Variable | Cle → valeur |
|---|---|
| `MlState` | IP → `@{State = connecting/live/lost/ended; Idxs; …}` (sessions Moonlight) |
| `RdpState` | IP → `@{Idxs; Proc; Since}` (session mstsc) |
| `MlAdopted` | sessions Moonlight deja ouvertes, reprises par `ScanRemoteClients` |
| `ScreenChoice` | IP (ou `__global`) → numeros d'ecrans choisis (persiste) |
| `MoonlightProfiles` | IP → dernier profil genere (persiste) |
| `WinRef`, `WinGuardNote` | reference de position / derniere abstention de `GuardWindows` |
| `CardList` | cartes construites (suivi ping/ouvert/sessions) — vide puis rempli a chaque `BuildUI` |
| `LayoutItems`, `LayoutSig`, `LayoutMode`, `UiTitlePool`, `UiGroupOrder` | disposition adaptative (`Relayout`) |
| `AliveMemo`, `SunMemo`, `HiddenIps` | dernier etat connu (cartes injoignables, sonde Sunshine, doublons masques) |
| `UiWinW / UiWinHc / UiWinH / UiLogH` | tailles de fenetre memorisees pour les handlers tardifs |
| `LogBuffer`, `LogBox` | journal du processus ; zone de log (recree a chaque BuildUI) |
| `NetScanJob`, `ZooSyncJob` | jobs de fond en cours |

## Timers

| Timer | Intervalle | Action | Defini dans |
|---|---|---|---|
| `$openTimer` | 5 s | `OpenCheckTick` : fenetres VS Code, VNC, SSH, ports Sunshine, sessions, ecrans | `ui-95` |
| `$pingTimer` | 15 s | `PingTick` : lance les pings asynchrones | `ui-95` |
| `$pingCollectTimer` | 250 ms | `PingCollect` : recolte, met a jour les cartes | `ui-95` |
| `$netTimer` | 4 s | surveille `NetScanJob`, puis `RebuildUI` | `ui-95` |
| `$script:SyncTimer` | 1 s | suit `ZooSyncJob` | `ui-80` |
| `$script:PlaceTimer`, `RetryTimer`, `PendingTimer` | ponctuels | placement de la fenetre Moonlight, reconnexion, attente de libération de la VM | `06`, `09` |

`OpenCheckTick` appelle `GuardWindows` a chaque tick (5 s) et `ScanRemoteClients` un tick sur trois (15 s).

## Taches de fond (`Start-Job`)

- `NetScanBlock` (`ui-40`) : scan /24 du port RDP 3389, resolution des VM via libvirt, ecrit `network-cache.json`.
- `SyncJobBlock` (`ui-70`) : synchronisation des conversations Zoo Code des machines distantes.

## Fichiers ecrits (`%LOCALAPPDATA%\vsc-launcher\`)

| Fichier | Ecrit par | Role |
|---|---|---|
| `network-cache.json` | `NetScanBlock` | machines Windows/RDP du LAN, rattachements aux hyperviseurs |
| `screen-choice.json` | `SaveScreenChoice` | ecrans choisis par machine |
| `moonlight-profiles.json` | `SaveMoonlightProfile` | profils de resolution generes |
| `alive-memo.json` | `PingCollect` (lu au chargement par `11`) | derniere joignabilite connue (affichage rapide au demarrage) |
| `launcher.log` | `LogFn` | journal |
| `rdp\` | `OpenMstsc` | fichiers .rdp generes |

Autres emplacements : miroir de dev `%USERPROFILE%\workspaces` (`WsRoot`, max 400 Mo), conversations Zoo Code locales `%APPDATA%\Code\User\globalStorage\zoocodeorganization.zoo-code\tasks`, config SSH `%USERPROFILE%\.ssh\config`, registre Moonlight `HKCU:\Software\Moonlight Game Streaming Project\Moonlight`.

## Ports

Moonlight/Apollo : TCP 47989 (HTTP) et 47984 (HTTPS). Sunshine (Linux) : 47989, 47984, 47990 (web), 48010 (RTSP). VNC : 5900–5904. RDP : 3389. Les ports video/audio sont en UDP (non sondables).
