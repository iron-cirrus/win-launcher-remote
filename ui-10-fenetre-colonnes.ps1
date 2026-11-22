# ui-10-fenetre-colonnes.ps1 - BuildUI : dimensions, regroupement par hote (colonnes)
# Fichier charge par vsc_launcher.ps1 (dot-source : meme portee script). Lignes d'origine 2510-2582.

$script:CardList = @()
$script:LayoutItems = @()
$script:UiTitlePool = @()
$script:LayoutSig = ''
# cartes masquees (doublons KO, voir PingCollect) : retirees de la liste affichee
if (@($script:HiddenIps).Count -gt 0) {
  $Machines = @($Machines | Where-Object { -not ($_.RdpIp -and -not $_.Host -and ($script:HiddenIps -contains $_.RdpIp)) })
}
# ---------- Fenetre (aucune barre de titre) ----------
$cardW = [int]240
$cardH = [int]105         # 75 + 30 px : evite la troncature de la ligne "@hote"
$gap   = [int]12
$x0    = [int]12
$y0    = [int]12
$cols  = [int]3

# ---------- Groupement par hote : une COLONNE par groupe ----------
# Groupe = parent de l'alias ("Vm-X_Router" -> colonne "Router") ; un hote
# physique forme son propre groupe. LOCAL en tete de la 1re colonne.
# Rattachement des hotes physiques au groupe de leurs VM : l'alias du physique
# ("Router-Aussudre") doit rejoindre le groupe des VM qui le designent par leur
# suffixe parent ("..._Router") -> prefixe commun, comparaison insensible a la casse.
foreach ($m in $Machines) {
  if (-not $m.Parent -and $m.Host) {
    foreach ($p in ($Machines | Where-Object { $_.Parent } | ForEach-Object { $_.Parent } | Select-Object -Unique)) {
      if ($m.Host -like ($p + "*")) { $m.Group = $p; break }
    }
  }
}
# Cartes WINDOWS du LAN rattachees a un hyperviseur de la config (scan) : elles
# prennent le GROUPE DEFINITIF de ce parent (renomme juste au-dessus) -> la VM
# Windows apparait dans la colonne de son serveur, sous ses VM Linux.
foreach ($m in $Machines) {
  if ($m.RdpIp -and $m.Parent) {
    $pm = @($Machines | Where-Object { $_.Host -eq $m.Parent }) | Select-Object -First 1
    if ($pm) { $m.Group = $pm.Group }
  }
}
$grpOrder = @()
foreach ($m in $Machines) { if ($grpOrder -notcontains $m.Group) { $grpOrder += $m.Group } }
$grpCount = @{}
foreach ($m in $Machines) {
  if ($grpCount.ContainsKey($m.Group)) { $grpCount[$m.Group] += 1 } else { $grpCount[$m.Group] = 1 }
}
$script:UiGroupOrder = @($grpOrder)
$colIdx = @{}
for ($g = 0; $g -lt $grpOrder.Count; $g++) { $colIdx[$grpOrder[$g]] = $g }
$grpRow = @{}   # prochaine ligne libre dans chaque colonne
$titleH = [int]20         # hauteur de la rangee de TITRES de colonne

# ORE DANS CHAQUE COLONNE : la carte serveur physique (sans parent) en premier,
# puis les VM dans l'ordre de la config.
$MachinesOrd = @()
foreach ($gname in $grpOrder) {
  $members = @($Machines | Where-Object { $_.Group -eq $gname })
  $srv  = @($members | Where-Object { $_.IconType -eq 'srv' })
  $rest = @($members | Where-Object { $_.IconType -ne 'srv' })
  $MachinesOrd += ($srv + $rest)
}

$logH = [int]96           # zone de log (fermee a l'initialisation)
$cols = [int]$grpOrder.Count
$rows = 0
foreach ($g in $grpOrder) { if ($grpCount[$g] -gt $rows) { $rows = $grpCount[$g] } }
$winW = [int]($x0 * 2 + $cols * $cardW + ($cols - 1) * $gap)
$winHc = [int]($y0 * 2 + $titleH + $rows * ($cardH + $gap) - $gap + 8 + 24)   # hauteur SANS log
$winH = [int]($winHc + $logH + 8)                                   # hauteur AVEC log
# Memorises au niveau SCRIPT : le handler de la fleche du log s'execute bien plus
# tard et relisait $winHc/$winH dans la portee du 1er affichage. Apres une
# reconstruction (scan LAN, doublon KO masque) qui change le nombre de lignes,
# il utilisait l'ANCIENNE hauteur -> fenetre mal taillee, boutons sous le log.
$script:UiWinW = $winW; $script:UiWinHc = $winHc; $script:UiWinH = $winH; $script:UiLogH = $logH

