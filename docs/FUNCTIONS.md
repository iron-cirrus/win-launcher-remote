# Reference des fonctions et scriptblocks

> GENERE par `docs/generate-api-docs.ps1` le 2026-11-22. Ne pas editer a la main : modifier `descriptions.psd1` ou les commentaires du code, puis relancer le script.
> Convention : un bloc `$script:Nom` s'appelle `& $script:Nom args` (ou `. $script:Nom` pour l'executer dans la portee courante). Voir [AI-CONTEXT.md](AI-CONTEXT.md).

## `start.ps1` (116 lignes)

Point d'entree : en-tete, relance en processus neuf, chargement des modules, BuildUI/RebuildUI, boucle ShowDialog, nettoyage.

| Nom | Parametres | Lignes | Role |
|---|---|---|---|
| `$script:BuildUI` |  | 78-89 | Scriptblock REEXECUTABLE qui (re)construit toute l'interface en executant les fichiers ui-*.ps1 dans la portee script. |
| `$script:RebuildUI` |  | 95-103 | Rechargement a chaud : arrete les timers, libere les controles, refusionne le cache LAN puis relance BuildUI. La fenetre reste en place. |

## `01-win32-interop.ps1` (158 lignes)

P/Invoke Win32 (EnumWindows, SetWindowPos...) : types C# versionnes

_Pas de fonction ni de scriptblock nomme : code lineaire (declarations, construction de controles, handlers)._

## `02-machines-couleurs.ps1` (51 lignes)

Couleurs connues par alias, palette de secours, notes/roles

_Pas de fonction ni de scriptblock nomme : code lineaire (declarations, construction de controles, handlers)._

## `03-machines-liste.ps1` (204 lignes)

Lecture de ~/.ssh/config, construction de $Machines, fusion du cache LAN (Windows/RDP)

| Nom | Parametres | Lignes | Role |
|---|---|---|---|
| `Get-SshHosts` |  | 5-32 | Lecture dynamique de ~/.ssh/config |
| `$script:MergeLanCache` |  | 96-202 | Fusion du cache LAN dans $Machines : scriptblock APPELABLE PLUSIEURS FOIS (demarrage + reconstruction d'affichage apres scan). Les IP deja connues sont sautees -> la liste LAN ne peut jamais "disparaitre" a une relecture. |

## `04-moonlight-reglages.ps1` (58 lignes)

ConvertTo-DrawingColor, chemin de code.exe, constantes et reglages Moonlight

| Nom | Parametres | Lignes | Role |
|---|---|---|---|
| `ConvertTo-DrawingColor` |  | 4-10 |  |

## `05-ecrans.ps1` (194 lignes)

Ecrans locaux, etat des sessions Moonlight (MlState), bitmap grise

| Nom | Parametres | Lignes | Role |
|---|---|---|---|
| `$script:GetScreens` |  | 36-46 | Liste les ecrans de CE poste : Idx (numero Windows), X/Y/W/H dans le bureau virtuel, principal. Resultat trie par Idx. |
| `$script:SetMlState` | `[string]$ip, [string]$state, $idxs = @(), $code = $null, [string]$note = ''` | 102-122 | Enregistre l'etat d'une session Moonlight pour une IP dans MlState (connecting / live / lost / ended). |
| `$script:MakeDimBmp` | `$src` | 178-191 | Versions SOMBRES (grisees + attenuees) des icones Moonlight et mstsc 20 px : affichees quand aucune session n'est ouverte, comme les icones VNC / SSH / VS Code des cartes (couleur = session active) |

## `06-moonlight-profil.ps1` (501 lignes)

Profil Moonlight genere, selection d'ecrans, placement et surveillance de la fenetre

| Nom | Parametres | Lignes | Role |
|---|---|---|---|
| `$script:GetMoonlightPrefs` |  | 50-61 | Lit les preferences de Moonlight dans le registre (HKCU) : resolution, fps, debit, deblocage des limites. |
| `$script:BuildMoonlightProfile` | `$sel, [string]$ip = ''` | 64-100 | Profil pour une selection d'ecrans ($sel = sortie de ResolveSelection). Renvoie la resolution, le fps, le debit (Kbps), les arguments Moonlight et un texte lisible. |
| `$script:SaveMoonlightProfile` | `[string]$ip, $sel, $prof, [bool]$applied = $true` | 102-120 | Consigne le profil genere (machine, ecrans, rectangle, resolution, fps, debit, arguments). |
| `$script:SaveScreenChoice` |  | 121-127 | Ecrit le choix d'ecrans par machine (ScreenChoice) en JSON sur disque, pour le retrouver au prochain demarrage. |
| `$script:ScreensContiguous` | `$screens` | 131-149 | Des ecrans sont-ils CONTIGUS ? Deux ecrans sont voisins s'ils partagent un bord (meme partiel) ou se chevauchent ; l'ensemble est contigu si on peut aller de l'un a tous les autres de voisin en voisin (un simple contact par un coin ne compte pas). |
| `$script:ResolveSelection` | `[string]$ip, [int[]]$idxs = @()` | 156-188 | Selection d'ecrans a utiliser pour une machine : les numeros passes, sinon le dernier choix memorise, sinon l'ecran principal. Renvoie les ecrans retenus, leur RECTANGLE ENGLOBANT (X, Y, W, H : la zone que doit couvrir la fenetre), l'ecran d'OUVERTURE (Anchor : le principal s'il fait partie de la selection, sinon le... |
| `$script:SetSelection` | `[string]$ip, [int[]]$idxs` | 191-209 | Memorise une selection d'ecrans pour une machine. Refuse (et le dit dans le log) une selection vide, inconnue ou NON CONTIGUE. Renvoie $true si elle est acceptee. |
| `$script:MapLayout` | `[double]$w, [double]$h` | 212-234 | Mini-carte : rectangle (en px, dans un cadre w x h) de chaque ecran, a l'echelle et dans leurs positions relatives (ecrans a gauche/droite/dessous respectes). |
| `$script:MapHit` | `$panel, [int]$x, [int]$y` | 237-243 | Numero de l'ecran sous un point (x, y) de la mini-carte, 0 si aucun. |
| `$script:MapScreensInRect` | `$panel, [double]$x1, [double]$y1, [double]$x2, [double]$y2` | 247-255 | Numeros des ecrans touches par un rectangle tire a la souris sur la mini-carte (x1,y1)-(x2,y2) : tous les ecrans dont le dessin croise la zone ("glisser pour selectionner"). |
| `$script:CtrlCombine` | `$cur, $set, [bool]$moved` | 260-268 | Ctrl+clic / Ctrl+glisser : combine la selection memorisee ($cur) et les ecrans touches ($set). Un Ctrl+CLIC (moved faux) BASCULE l'ecran (le retire s'il y est, l'ajoute sinon) ; un Ctrl+GLISSER (moved vrai) AJOUTE tous les ecrans touches. |
| `$script:GetMoonlightHost` | `[string]$ip` | 272-294 | Appairage Moonlight d'une machine (registre de Moonlight) : l'hote doit avoir son certificat (srvcert) et l'IP parmi ses adresses. Renvoie aussi sa liste d'applications. |
| `$script:PlaceOnScreen` | `[int]$procId, $sel` | 310-378 | Placement de la fenetre de Moonlight sur l'ecran (ou les ecrans) choisi(s). Moonlight n'a AUCUNE option "ecran" : il ouvre le flux sur l'ecran ou se trouve sa propre fenetre. On surveille donc (200 ms, 25 s max) les fenetres du processus lance : - UN SEUL ecran : chaque fenetre, a son apparition, est ramenee sur cet... |
| `$script:WatchMoonlight` | `$proc, [string]$ip, $mlArgs, $sel, $mlArgsBase = $null, [bool]$profileUsed = $false` | 396-500 | Surveillance des processus Moonlight lances (voir RECONNEXION AUTOMATIQUE plus haut) : elle alimente a la fois la reconnexion automatique ET l'ETAT affiche sur la mini-carte ($script:SetMlState). Une entree par machine (IP), controlee une fois par seconde, jusqu'a la fermeture de Moonlight : - fenetre du flux ("... ... |

## `07-mstsc.ps1` (71 lignes)

mstsc (RDP) sur les ecrans selectionnes

| Nom | Parametres | Lignes | Role |
|---|---|---|---|
| `$script:MstscIdsFor` | `$sel` | 17-28 | Convertit une selection d'ecrans (sel) en identifiants de moniteurs mstsc (selectedmonitors). |
| `$script:OpenMstsc` | `[string]$ip, [bool]$useScreens = $true` | 31-62 | Ouvre mstsc vers $ip. $useScreens : utiliser la selection d'ecrans (dernier choix memorise, sinon ecran principal) ; sinon mstsc simple (fenetre normale, comme avant). |
| `$script:RdpFallback` | `[string]$ip, [string]$why` | 65-71 | Repli RDP (mstsc) : script-level car appele aussi apres un lancement differe. La selection d'ecrans n'est appliquee que si l'utilisateur en a memorise une pour cette machine. |

## `08-clients-distants.ps1` (144 lignes)

Detection des clients distants deja ouverts (Moonlight/mstsc)

| Nom | Parametres | Lignes | Role |
|---|---|---|---|
| `$script:ScreensOfPid` | `[int]$procId` | 7-24 | CLIENTS DISTANTS DEJA OUVERTS (scan au demarrage puis toutes les 15 s) Ecrans reellement couverts par les fenetres d'un processus : un ecran compte s'il est couvert a 30 % au moins par une fenetre, ou s'il contient plus de la moitie de cette fenetre. |
| `$script:CardIpFor` | `[string]$hostTxt` | 26-37 | Carte correspondant a un nom d'hote ou une IP (ligne de commande Moonlight / mstsc) |
| `$script:ScanRemoteClients` | `[bool]$initial = $false` | 46-144 | Detecte les clients Moonlight / mstsc DEJA ouverts (au demarrage puis toutes les 15 s) et les rattache a leur carte (adoption dans MlAdopted / RdpState). |

## `09-moonlight-garde.ps1` (175 lignes)

Garde de taille des fenetres Moonlight, etat/lancement/arret des sessions

| Nom | Parametres | Lignes | Role |
|---|---|---|---|
| `$script:GuardWindows` |  | 17-65 | Pour chaque session Moonlight operationnelle, compare la fenetre du flux a sa place prevue et la remet en place si l'ecart depasse 6 px. |
| `$script:GetBelievedHostSession` | `[string]$ip` | 70-93 | Session que Moonlight a ouverte sur la VM, d'apres l'historique de SES requetes (journaux Moonlight-*.log, les 80 plus recents, dans l'ordre) : Active = une session existe, AppId, Mode = mode ("LxHxFPS") du dernier /launch (un /resume ne le change pas). Renvoie $null si les journaux n'ont aucune requete vers cette m... |
| `$script:GetHostRunningApp` | `[string]$ip` | 97-108 | Application en cours sur la VM : identifiant lu dans la reponse "serverinfo" du serveur Apollo (requete HTTP en lecture seule, la meme que Moonlight envoie en permanence). 0 = rien en cours ; $null = serveur injoignable ou reponse illisible. |
| `$script:LaunchMoonlightNow` | `[string]$ip, $mlArgs, $mlArgsBase, $sel, $prof, [bool]$applied = $true` | 111-128 | Demarre Moonlight (stream) avec les arguments donnes, puis suivi de placement + surveillance. $applied : la resolution du profil a-t-elle pu etre appliquee sur la VM (voir SaveMoonlightProfile). |
| `$script:QuitThenLaunch` | `[string]$ip, $mlArgs, $mlArgsBase, $sel, $prof` | 132-174 | Ferme la session en cours sur la VM ("Moonlight quit <hote>"), attend que la VM soit libre (currentgame = 0, 8 s au plus) puis lance Moonlight. Asynchrone (minuteur) : l'interface ne gele pas. Etat porte par le minuteur (Tag). |

## `10-ouvrir-hote-windows.ps1` (275 lignes)

OpenWindowsHost : Moonlight si possible, sinon RDP

| Nom | Parametres | Lignes | Role |
|---|---|---|---|
| `$script:OpenWindowsHost` | `[string]$ip, [int[]]$screenIdx = @()` | 10-145 | Ouvre une machine Windows : MOONLIGHT si (1) client installe ici, (2) ports Apollo ouverts sur la machine, (3) machine deja APPAIREE dans Moonlight ; sinon RDP (mstsc). Sonde des ports : connexions asynchrones, attente max 800 ms au total -> le clic ne gele jamais la fenetre plus de 0,8 s (refus immediat si le port ... |

## `11-icones-disposition.ps1` (262 lignes)

Icones en cache (NewIconBmp) et disposition adaptative (Relayout)

| Nom | Parametres | Lignes | Role |
|---|---|---|---|
| `$script:NewIconBmp` | `[int]$w, [int]$h, [scriptblock]$draw, $state, $s, [double]$sc = 1.0` | 9-21 | PERF : rendu d'une petite icone dans un bitmap transparent, UNE FOIS. Les icones des cartes (VS Code, VNC, SSH, user) ne sont plus redessinees par script a chaque repaint : le handler Paint se contente de poser le bitmap en cache correspondant a l'etat (ouvert/ferme, connecte/non). $draw recoit (Graphics, etat, obje... |
| `$script:FindHomeScreen` |  | 93-105 | Trouve l'ecran d'accueil (adaptateur 'spacedesk' + moniteur 'Non-PnP') ou le launcher passe en plein ecran ; null s'il est absent. |
| `$script:UpdateHome` | `[bool]$relayout = $true` | 106-115 | Recalcule l'ecran d'accueil ; si sa signature change, relance Relayout (parametre : relayout = true par defaut). |
| `$script:CardVisible` | `$it` | 116-123 | Une carte doit-elle etre affichee ? (cartes injoignables masquees si HideInactiveCards, avec memoire AliveMemo du dernier etat connu). |
| `$script:Relayout` |  | 124-262 | Calcule et applique la disposition adaptative : colonnes par groupe, titres de colonne, taille de la fenetre, mode plein ecran sur l'ecran d'accueil. |

## `12-sunshine.ps1` (76 lignes)

Sondage Sunshine (machines Linux) et icone Moonlight

| Nom | Parametres | Lignes | Role |
|---|---|---|---|
| `$script:PaintMlIcon` | `$g, $s` | 16-40 | Icone Moonlight + pastille d'etat, partagee par les cartes Windows (Apollo) et Linux (Sunshine). Pastille SANS vert/rouge (daltonisme) : session operationnelle = disque PLEIN bleu clair ; en connexion = anneau VIDE orange (la forme change, pas seulement la couleur). |
| `$script:SunshineApply` | `$c, $open, $ipSeen, [bool]$quiet = $false` | 43-76 | Applique le resultat de la sonde de ports Sunshine a la carte Linux : affiche/masque/attenue l'icone Moonlight et memorise dans SunMemo. |

## `13-panneau-haut.ps1` (353 lignes)

Panneau du haut : carte des ecrans + sessions distantes

| Nom | Parametres | Lignes | Role |
|---|---|---|---|
| `$script:CardNameFor` | `[string]$ip` | 19-25 | nom affiche d'une machine d'apres son adresse (carte), sinon l'adresse |
| `$script:GetSessions` |  | 27-40 | sessions distantes connues : Moonlight (MlState) + mstsc (RdpState) |
| `$script:RefreshSessionTags` |  | 42-61 | etiquette "ML 1+2" / "RDP 3" de chaque carte (sessions actives de la machine) |
| `$script:RefreshTop` |  | 62-66 | Repeint la mini-carte des ecrans, la liste des sessions et met a jour les etiquettes de session des cartes. |
| `$script:LauncherScreenIdx` |  | 68-74 | numero de l'ecran qui porte la fenetre du launcher |
| `$script:FocusSession` | `[string]$ip, [string]$kind` | 76-98 | ramene au premier plan la fenetre d'une session (Moonlight : fenetre du flux ; mstsc : sa fenetre) |
| `$script:PaintTopMap` | `$s, $e` | 99-188 | Paint de la mini-carte globale des ecrans (panneau du haut) : cadres a l'echelle, numeros, selection, survol. |
| `$script:PaintTopList` | `$s, $e` | 189-238 | Paint de la liste des sessions distantes (Moonlight / mstsc) avec etat et ecrans utilises. |
| `$script:BuildTopPanel` |  | 239-352 | Construit le panneau du haut : mini-carte (selecteur global d'ecrans) + liste des sessions, et branche leurs evenements souris. |

## `ui-10-fenetre-colonnes.ps1` (76 lignes)

BuildUI : dimensions, regroupement par hote (colonnes)

_Pas de fonction ni de scriptblock nomme : code lineaire (declarations, construction de controles, handlers)._

## `ui-20-fenetre.ps1` (33 lignes)

BuildUI : creation unique de la fenetre / liberation des controles

_Pas de fonction ni de scriptblock nomme : code lineaire (declarations, construction de controles, handlers)._

## `ui-30-journal.ps1` (96 lignes)

BuildUI : zone de log et bouton fleche

| Nom | Parametres | Lignes | Role |
|---|---|---|---|
| `$script:LogFn` | `$msg` | 60-84 | Journal : horodate le message, l'ajoute au tampon du processus (survit aux reconstructions) et a la zone de log. Appel : & $script:LogFn "texte". |

## `ui-40-scan-lan.ps1` (398 lignes)

BuildUI : scan du LAN en tache de fond (RDP 3389)

| Nom | Parametres | Lignes | Role |
|---|---|---|---|
| `$script:NetScanBlock` | `[string]$prefix, [string[]]$exclude, [string]$cachePath, [string[]]$hypList, [string[]]$attribList` | 13-330 | Scan du LAN en tache de fond : postes WINDOWS (port RDP 3389) TcpClient asynchrone : les 254 connexions du /24 sont demarrees d'un coup puis collectees -> scan complet en ~2 s. Pour chaque hote RDP ouvert : - MAC via arp -> OUI : 52:54:00 (QEMU/KVM), 08:00:27 (VirtualBox), 00:0C:29 / 00:50:56 (VMware), 00:15:5D (Hyp... |

## `ui-50-cartes.ps1` (15 lignes)

BuildUI : titres de colonne et cartes des machines

_Pas de fonction ni de scriptblock nomme : code lineaire (declarations, construction de controles, handlers)._

## `ui-60-deploiement.ps1` (289 lignes)

BuildUI : deploiement des couleurs, miroir rsync des dossiers de dev

| Nom | Parametres | Lignes | Role |
|---|---|---|---|
| `$script:RunTimeout` | `[string]$exe, [string[]]$argList, [int]$timeoutSec = 10` | 12-49 | Deploiement des couleurs (integre au launcher) Genere le ~/.vscode-server/data/Machine/settings.json de chaque hote avec la couleur de SA carte, et l'envoie par ssh/scp. Alimente par la liste dynamique de ~/.ssh/config (donc les nouveaux hotes heritent automatiquement d'une couleur de la palette). Execute ssh/scp av... |
| `$script:RunTimeoutBin` | `[string]$exe, [string[]]$argList, [int]$timeoutSec, [string]$outFile` | 54-76 | Variante de RunTimeout qui capture la SORTIE STANDARD EN OCTETS bruts dans un fichier (indispensable pour deballer un flux binaire type tar) : RunTimeout normal lit la sortie en texte et detruirait les octets. |
| `$script:LocalManifest` | `[string]$dir` | 97-111 | Inventaire d'un dossier local (chemins + dates/tailles) pour le miroir de dossiers de dev ; null si absent. |
| `$script:SyncWorkspace` | `$m, [string]$target, [string[]]$sshOpts, [string]$ws` | 113-204 | Miroir 'rsync' d'un dossier de dev local vers/depuis une machine distante via ssh/tar, en excluant WsExcludes et au-dela de WsMaxMb. |
| `$script:DeployColors` |  | 206-288 | Genere et envoie (ssh/scp) a chaque hote le settings.json de VS Code Server avec la couleur de SA carte. |

## `ui-70-sync-zoo.ps1` (254 lignes)

BuildUI : synchronisation des conversations Zoo Code (tache de fond)

| Nom | Parametres | Lignes | Role |
|---|---|---|---|
| `$script:SyncJobBlock` | `[object[]]$machList, [string]$localTasks, [string]$wsRoot, [int]$maxMb, [string[]]$excludes` | 19-253 | Synchronisation des conversations Zoo Code (TACHE DE FOND) Chaque machine distante heberge ses conversations Zoo Code (fork de Roo Code) dans ~/.vscode-server/data/User/globalStorage/zoocodeorganization.zoo-code/tasks -> UN dossier par tache (UUID) : history_item.json (index affiche dans l'historique) + api_conversa... |

## `ui-80-pied-de-page.ps1` (121 lignes)

BuildUI : boutons du pied de page

_Pas de fonction ni de scriptblock nomme : code lineaire (declarations, construction de controles, handlers)._

## `ui-90-watchdog-fenetres.ps1` (268 lignes)

BuildUI : watchdog A, fenetres VS Code ouvertes (5 s)

| Nom | Parametres | Lignes | Role |
|---|---|---|---|
| `$script:OpenCheckTick` |  | 11-267 | Watchdog A : fenetres VS Code ouvertes (5 s) VS Code (Electron) heberge souvent PLUSIEURS fenetres dans UN SEUL processus : Get-Process.MainWindowHandle ne voit alors que la fenetre au premier plan. On enumere donc TOUTES les fenetres de haut niveau visibles via EnumWindows (VscWinV4::GetCodeWindows) et on rattache ... |

## `ui-95-watchdog-ping.ps1` (242 lignes)

BuildUI : watchdog B, ping des hotes (15 s), fin de construction

| Nom | Parametres | Lignes | Role |
|---|---|---|---|
| `$script:PingTick` |  | 10-22 | Watchdog B : ping periodique des hotes (15 s) PERF : l'ancien Ping.Send SYNCHRONE, hote par hote, sur le fil de l'IHM gelait la fenetre 1,2 s par machine eteinte (3 eteintes = 3,6 s toutes les 15 s). Desormais : PingTick DEMARRE tous les pings en parallele (SendPingAsync) et rend la main aussitot ; PingCollect (time... |
| `$script:SetCardStyle` | `$c, [bool]$dead` | 28-47 | Style d'une carte selon sa joignabilite. INJOIGNABLE : fond tres sombre (plus sombre que toutes les couleurs de carte, y compris le gris-bleu du LAN), texte attenue, nom BARRE -> une machine eteinte se voit au premier coup d'oeil (avant : gris 55,55,55 quasi identique aux cartes LAN, seul le "KO" differait). |
| `$script:PingCollect` |  | 49-156 | Collecte (toutes les 250 ms, sans reseau) les pings/TCP asynchrones lances par PingTick et met a jour pastille, ms et style de chaque carte. |

## `cartes/01-fond-filigrane.ps1` (139 lignes)

Panneau de la carte, couleurs, filigrane (ordinateur/serveur + logo OS), double tampon

_Pas de fonction ni de scriptblock nomme : code lineaire (declarations, construction de controles, handlers)._

## `cartes/02-textes.ps1` (116 lignes)

Titre, utilisateur, role/IP, temps de ping, etiquette de session

_Pas de fonction ni de scriptblock nomme : code lineaire (declarations, construction de controles, handlers)._

## `cartes/03-logo-vscode.ps1` (68 lignes)

Indicateur VS Code ouvert/ferme (bas droite)

_Pas de fonction ni de scriptblock nomme : code lineaire (declarations, construction de controles, handlers)._

## `cartes/04-icone-vnc.ps1` (114 lignes)

Icone VNC : dessin et clic (lance/ramene le client)

_Pas de fonction ni de scriptblock nomme : code lineaire (declarations, construction de controles, handlers)._

## `cartes/05-icone-ssh.ps1` (127 lignes)

Icone SSH : dessin et clic (ouvre/ramene un terminal)

_Pas de fonction ni de scriptblock nomme : code lineaire (declarations, construction de controles, handlers)._

## `cartes/06-clics-survol.ps1` (124 lignes)

Clic carte (ouvrir VS Code / Windows), clic droit (test SSH), survol

_Pas de fonction ni de scriptblock nomme : code lineaire (declarations, construction de controles, handlers)._

## `cartes/07-ecrans-windows.ps1` (249 lignes)

Mini-carte des ecrans + boutons mstsc/Moonlight (machines Windows du LAN)

_Pas de fonction ni de scriptblock nomme : code lineaire (declarations, construction de controles, handlers)._

## `cartes/08-icone-sunshine.ps1` (35 lignes)

Icone Moonlight des machines Linux (Sunshine)

_Pas de fonction ni de scriptblock nomme : code lineaire (declarations, construction de controles, handlers)._

## `cartes/09-finalisation.ps1` (53 lignes)

Ajout des controles, z-order, info-bulles, enregistrement pour les watchdogs

_Pas de fonction ni de scriptblock nomme : code lineaire (declarations, construction de controles, handlers)._

