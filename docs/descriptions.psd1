# Descriptions complementaires des blocs qui n'ont pas de commentaire juste au-dessus dans le code.
# Cle = nom exact releve par generate-api-docs.ps1. Prioritaire sur le commentaire du code.
@{
  '$script:GetScreens'          = "Liste les ecrans de CE poste : Idx (numero Windows), X/Y/W/H dans le bureau virtuel, principal. Resultat trie par Idx."
  '$script:SetMlState'          = "Enregistre l'etat d'une session Moonlight pour une IP dans MlState (connecting / live / lost / ended)."
  '$script:GetMoonlightPrefs'   = "Lit les preferences de Moonlight dans le registre (HKCU) : resolution, fps, debit, deblocage des limites."
  '$script:SaveScreenChoice'    = "Ecrit le choix d'ecrans par machine (ScreenChoice) en JSON sur disque, pour le retrouver au prochain demarrage."
  '$script:MstscIdsFor'         = "Convertit une selection d'ecrans (sel) en identifiants de moniteurs mstsc (selectedmonitors)."
  '$script:ScanRemoteClients'   = "Detecte les clients Moonlight / mstsc DEJA ouverts (au demarrage puis toutes les 15 s) et les rattache a leur carte (adoption dans MlAdopted / RdpState)."
  '$script:GuardWindows'        = "Pour chaque session Moonlight operationnelle, compare la fenetre du flux a sa place prevue et la remet en place si l'ecart depasse 6 px."
  '$script:FindHomeScreen'      = "Trouve l'ecran d'accueil (adaptateur 'spacedesk' + moniteur 'Non-PnP') ou le launcher passe en plein ecran ; null s'il est absent."
  '$script:UpdateHome'          = "Recalcule l'ecran d'accueil ; si sa signature change, relance Relayout (parametre : relayout = true par defaut)."
  '$script:CardVisible'         = "Une carte doit-elle etre affichee ? (cartes injoignables masquees si HideInactiveCards, avec memoire AliveMemo du dernier etat connu)."
  '$script:Relayout'            = "Calcule et applique la disposition adaptative : colonnes par groupe, titres de colonne, taille de la fenetre, mode plein ecran sur l'ecran d'accueil."
  '$script:SunshineApply'       = "Applique le resultat de la sonde de ports Sunshine a la carte Linux : affiche/masque/attenue l'icone Moonlight et memorise dans SunMemo."
  '$script:RefreshTop'          = "Repeint la mini-carte des ecrans, la liste des sessions et met a jour les etiquettes de session des cartes."
  '$script:PaintTopMap'         = "Paint de la mini-carte globale des ecrans (panneau du haut) : cadres a l'echelle, numeros, selection, survol."
  '$script:PaintTopList'        = "Paint de la liste des sessions distantes (Moonlight / mstsc) avec etat et ecrans utilises."
  '$script:BuildTopPanel'       = "Construit le panneau du haut : mini-carte (selecteur global d'ecrans) + liste des sessions, et branche leurs evenements souris."
  '$script:LogFn'               = 'Journal : horodate le message, l''ajoute au tampon du processus (survit aux reconstructions) et a la zone de log. Appel : & $script:LogFn "texte".'
  '$script:LocalManifest'       = "Inventaire d'un dossier local (chemins + dates/tailles) pour le miroir de dossiers de dev ; null si absent."
  '$script:SyncWorkspace'       = "Miroir 'rsync' d'un dossier de dev local vers/depuis une machine distante via ssh/tar, en excluant WsExcludes et au-dela de WsMaxMb."
  '$script:DeployColors'        = "Genere et envoie (ssh/scp) a chaque hote le settings.json de VS Code Server avec la couleur de SA carte."
  '$script:PingCollect'         = "Collecte (toutes les 250 ms, sans reseau) les pings/TCP asynchrones lances par PingTick et met a jour pastille, ms et style de chaque carte."
  '$script:BuildUI'             = "Scriptblock REEXECUTABLE qui (re)construit toute l'interface en executant les fichiers ui-*.ps1 dans la portee script."
  '$script:RebuildUI'           = "Rechargement a chaud : arrete les timers, libere les controles, refusionne le cache LAN puis relance BuildUI. La fenetre reste en place."
}
