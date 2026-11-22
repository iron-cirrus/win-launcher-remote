# 06-moonlight-profil.ps1 - Profil Moonlight genere, selection d'ecrans, placement et surveillance de la fenetre
# Fichier charge par vsc_launcher.ps1 (dot-source : meme portee script). Lignes d'origine 676-1173.

# ---------- PROFIL MOONLIGHT GENERE DEPUIS LES ECRANS CHOISIS ----------
# Moonlight diffuse a la resolution de ses reglages (chez vous 7680x1440), quels que soient les
# ecrans choisis : sur un seul ecran 2560x1440 ou sur 4K, l'image est donc deformee ou entouree de
# bandes noires. Au lancement, le launcher genere un profil qui CORRESPOND aux ecrans choisis et le
# passe a Moonlight en ligne de commande (vos reglages Moonlight ne sont PAS modifies) :
#   --resolution LxH : taille en pixels du rectangle englobant des ecrans choisis ;
#   --fps            : celui de vos reglages Moonlight (ou MoonlightProfileFps) ;
#   --bitrate        : meme qualite PAR PIXEL que vos reglages (debit x pixels x fps), plafonne
#                      comme Moonlight (150 Mbit/s, 500 si "debloquer le debit" est active).
# Les profils generes sont consignes dans moonlight-profiles.json (a titre d'information) et
# l'info-bulle de la mini-carte affiche celui de la selection courante. Si une version de
# Moonlight refuse ces options (fermeture immediate sans flux), le launcher relance sans profil.
#  - MoonlightAutoProfile : $false = ne rien generer (Moonlight utilise ses reglages) ;
#  - MoonlightProfileMaxW/H : plafond de la resolution (reduite proportionnellement au-dela) ;
#  - MoonlightProfileFps / MoonlightProfileBitrateKbps : forcer une valeur ($null = automatique).
$script:MoonlightAutoProfile = $true
$script:MoonlightProfileMaxW = 8192
$script:MoonlightProfileMaxH = 4320
$script:MoonlightProfileFps = $null
$script:MoonlightProfileBitrateKbps = $null
$script:MoonlightProfilePath = Join-Path $env:LOCALAPPDATA "vsc-launcher\moonlight-profiles.json"
$script:MoonlightProfiles = @{}
# POURQUOI FERMER LA SESSION PRECEDENTE : la VM applique la resolution demandee seulement quand
# l'application est LANCEE ("/launch"). Si une session "Desktop" est deja ouverte, Moonlight la
# REPREND ("/resume") : le flux est bien encode a la nouvelle taille, mais le bureau de la VM
# garde l'ancienne resolution (ex. 7680x1440) et se retrouve ecrase dans le flux. Quand le profil
# change, le launcher ferme donc d'abord la session sur la VM (commande Moonlight "quit") puis
# relance. SECURITE : il ne ferme QUE l'application qu'il va diffuser (jamais un jeu ou une autre
# application en cours) et seulement si le mode a change depuis son dernier lancement.
# $false = ne jamais fermer de session (la resolution de la VM ne change alors qu'a la 1re ouverture).
$script:MoonlightQuitToApplyProfile = $true
# Etat de la session sur la VM : la reponse HTTP du serveur (non authentifiee) ne l'annonce pas de
# facon fiable (une session "Virtual Display" etait reprise alors que le serveur la disait absente).
# Le launcher s'appuie donc sur l'HISTORIQUE DES REQUETES DE MOONLIGHT (journaux Moonlight-*.log
# du dossier ci-dessous) : un "/launch" ouvre une session a SON mode, un "/resume" la reprend sans
# rien changer, un "/cancel" (commande quit) la ferme.
$script:MoonlightLogDir = $env:TEMP
# Pause apres la fermeture de la session avant de relancer : laisse la VM supprimer l'ecran
# virtuel precedent (secondes).
$script:MoonlightQuitSettleSec = 3
try {
  if (Test-Path $script:MoonlightProfilePath) {
    $prObj = Get-Content $script:MoonlightProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($pp in $prObj.PSObject.Properties) { $script:MoonlightProfiles[$pp.Name] = $pp.Value }
  }
} catch { }
$script:GetMoonlightPrefs = {
  $o = @{ Width = 1920; Height = 1080; Fps = 60; Bitrate = 0; Unlock = $false }
  try {
    $pk = Get-ItemProperty 'HKCU:\Software\Moonlight Game Streaming Project\Moonlight' -ErrorAction Stop
    if ($pk.width) { $o.Width = [int]$pk.width }
    if ($pk.height) { $o.Height = [int]$pk.height }
    if ($pk.fps) { $o.Fps = [int]$pk.fps }
    if ($pk.bitrate) { $o.Bitrate = [int]$pk.bitrate }
    $o.Unlock = ("" + $pk.unlockbitrate) -ieq 'true'
  } catch { }
  return $o
}
# Profil pour une selection d'ecrans ($sel = sortie de ResolveSelection). Renvoie la resolution, le
# fps, le debit (Kbps), les arguments Moonlight et un texte lisible.
$script:BuildMoonlightProfile = {
  param($sel, [string]$ip = '')
  if (-not $sel -or $sel.W -le 0 -or $sel.H -le 0) { return $null }
  $pf = & $script:GetMoonlightPrefs
  # RESOLUTION PHYSIQUE des ecrans (un 4K a 125 % de mise a l'echelle est vu 3072x1728 par le launcher)
  $w = $(if ($sel.PW) { [int]$sel.PW } else { [int]$sel.W }); $h = $(if ($sel.PH) { [int]$sel.PH } else { [int]$sel.H })
  $scaled = $false
  # plafonds : globaux, puis ceux de la machine (adresse) ou, pour une machine Linux (Sunshine), ceux de LinuxProfileLimit
  $maxW = [int]$script:MoonlightProfileMaxW; $maxH = [int]$script:MoonlightProfileMaxH; $maxFps = 0; $limTxt = ''
  $lim = $null
  if ($ip -and $script:MoonlightHostLimits.ContainsKey($ip)) { $lim = $script:MoonlightHostLimits[$ip] }
  elseif ($ip -and $script:NoRdp -and $script:NoRdp.ContainsKey($ip)) { $lim = $script:LinuxProfileLimit }
  if ($lim) {
    if ($lim.MaxW) { $maxW = [Math]::Min($maxW, [int]$lim.MaxW) }
    if ($lim.MaxH) { $maxH = [Math]::Min($maxH, [int]$lim.MaxH) }
    if ($lim.MaxFps) { $maxFps = [int]$lim.MaxFps }
    $limTxt = " (plafond de cette machine " + $maxW + "x" + $maxH + $(if ($maxFps) { " a " + $maxFps + " i/s" }) + ")"
  }
  if ($w -gt $maxW -or $h -gt $maxH) {
    $k = [Math]::Min($maxW / $w, $maxH / $h)
    $w = [int]([Math]::Floor($w * $k / 8) * 8); $h = [int]([Math]::Floor($h * $k / 8) * 8); $scaled = $true
  }
  $fps = $(if ($script:MoonlightProfileFps) { [int]$script:MoonlightProfileFps } else { [int]$pf.Fps })
  if ($maxFps -and $fps -gt $maxFps) { $fps = $maxFps }
  $refPx = [double]$pf.Width * [double]$pf.Height
  $perPx = $(if ($pf.Bitrate -gt 0 -and $refPx -gt 0) { $pf.Bitrate / $refPx } else { 0.0048 })   # 0,0048 ~ 10 Mbit/s en 1080p60
  $kbps = $perPx * $w * $h * ($fps / [double][Math]::Max(1, $pf.Fps))
  $cap = $(if ($pf.Unlock) { 500000 } else { 150000 })
  $kbps = [int][Math]::Min($cap, [Math]::Max(1000, [Math]::Round($kbps / 500) * 500))
  if ($script:MoonlightProfileBitrateKbps) { $kbps = [int]$script:MoonlightProfileBitrateKbps }
  $dim = "" + $w + "x" + $h
  return [pscustomobject]@{
    Width = $w; Height = $h; Fps = $fps; BitrateKbps = $kbps; Scaled = $scaled
    Args = @('--resolution', $dim, '--fps', ("" + $fps), '--bitrate', ("" + $kbps))
    Text = $dim + " a " + $fps + " images/s, " + [Math]::Round($kbps / 1000, 1) + " Mbit/s" + $(if ($scaled) { " (reduite : plafond " + $maxW + "x" + $maxH + ")" } elseif ($limTxt) { $limTxt })
  }
}
# Consigne le profil genere (machine, ecrans, rectangle, resolution, fps, debit, arguments).
$script:SaveMoonlightProfile = {
  param([string]$ip, $sel, $prof, [bool]$applied = $true)
  try {
    # "mode" = resolution reellement appliquee sur la VM par le dernier lancement ; s'il n'a pas pu
    # l'etre (autre application en cours, fermeture echouee) on garde l'ancienne valeur : le
    # prochain lancement reessaiera
    $prev = $script:MoonlightProfiles[$ip]
    $mode = $(if ($applied) { "" + $prof.Width + "x" + $prof.Height + "x" + $prof.Fps } elseif ($prev -and $prev.mode) { "" + $prev.mode } else { "" })
    $script:MoonlightProfiles[$ip] = [ordered]@{
      genere = (Get-Date).ToString('s'); mode = $mode; app = $(if ($applied -and $prof.App) { "" + $prof.App } elseif ($prev -and $prev.app) { "" + $prev.app } else { "" }); ecrans = @($sel.Idxs)
      rectangle = ("" + $(if ($sel.PW) { $sel.PW } else { $sel.W }) + "x" + $(if ($sel.PH) { $sel.PH } else { $sel.H }) + " a " + $sel.X + "," + $sel.Y)
      resolution = ("" + $prof.Width + "x" + $prof.Height); fps = $prof.Fps; debit_kbps = $prof.BitrateKbps
      arguments = ($prof.Args -join ' ')
    }
    $dPr = Split-Path $script:MoonlightProfilePath -Parent
    if (-not (Test-Path $dPr)) { New-Item -ItemType Directory -Path $dPr -Force | Out-Null }
    [System.IO.File]::WriteAllText($script:MoonlightProfilePath, ($script:MoonlightProfiles | ConvertTo-Json -Depth 4))
  } catch { }
}
$script:SaveScreenChoice = {
  try {
    $dSc = Split-Path $script:ScreenChoicePath -Parent
    if (-not (Test-Path $dSc)) { New-Item -ItemType Directory -Path $dSc -Force | Out-Null }
    [System.IO.File]::WriteAllText($script:ScreenChoicePath, ($script:ScreenChoice | ConvertTo-Json))
  } catch { }
}
# Des ecrans sont-ils CONTIGUS ? Deux ecrans sont voisins s'ils partagent un bord (meme
# partiel) ou se chevauchent ; l'ensemble est contigu si on peut aller de l'un a tous
# les autres de voisin en voisin (un simple contact par un coin ne compte pas).
$script:ScreensContiguous = {
  param($screens)
  $sc = @($screens)
  if ($sc.Count -le 1) { return $true }
  $seen = @{}
  $seen[$sc[0].Idx] = $true
  $queue = New-Object System.Collections.Queue
  $queue.Enqueue($sc[0])
  while ($queue.Count -gt 0) {
    $a = $queue.Dequeue()
    foreach ($b in $sc) {
      if ($seen.ContainsKey($b.Idx)) { continue }
      $ovX = [Math]::Min($a.X + $a.W, $b.X + $b.W) - [Math]::Max($a.X, $b.X)
      $ovY = [Math]::Min($a.Y + $a.H, $b.Y + $b.H) - [Math]::Max($a.Y, $b.Y)
      if (($ovX -gt 0 -and $ovY -ge 0) -or ($ovY -gt 0 -and $ovX -ge 0)) { $seen[$b.Idx] = $true; $queue.Enqueue($b) }
    }
  }
  return ($seen.Count -eq $sc.Count)
}
# Selection d'ecrans a utiliser pour une machine : les numeros passes, sinon le dernier
# choix memorise, sinon l'ecran principal. Renvoie les ecrans retenus, leur RECTANGLE
# ENGLOBANT (X, Y, W, H : la zone que doit couvrir la fenetre), l'ecran d'OUVERTURE
# (Anchor : le principal s'il fait partie de la selection, sinon le plus petit numero)
# et Multi. Un ecran debranche est ignore ; si le reste n'est plus contigu, on ne garde
# que le premier ecran.
$script:ResolveSelection = {
  param([string]$ip, [int[]]$idxs = @())
  $all = @($script:Screens)
  # SELECTION GLOBALE (carte des ecrans du panneau haut) : valable pour TOUTES les machines ; a defaut
  # (ancien fichier de choix) le dernier choix memorise pour cette machine, sinon l'ecran principal
  if ($idxs.Count -eq 0 -and $script:ScreenChoice.ContainsKey('__global')) { $idxs = @($script:ScreenChoice['__global']) }
  elseif ($idxs.Count -eq 0 -and $script:ScreenChoice.ContainsKey($ip)) { $idxs = @($script:ScreenChoice[$ip]) }
  $pick = @($all | Where-Object { $idxs -contains $_.Idx })
  if ($pick.Count -gt 1 -and -not (& $script:ScreensContiguous $pick)) { $pick = @($pick[0]) }
  if ($pick.Count -eq 0) {
    $prim = @($all | Where-Object { $_.Primary }) | Select-Object -First 1
    if (-not $prim -and $all.Count -gt 0) { $prim = $all[0] }
    if ($prim) { $pick = @($prim) }
  }
  if ($pick.Count -eq 0) { return $null }
  $x1 = ($pick | ForEach-Object { $_.X } | Measure-Object -Minimum).Minimum
  $y1 = ($pick | ForEach-Object { $_.Y } | Measure-Object -Minimum).Minimum
  $x2 = ($pick | ForEach-Object { $_.X + $_.W } | Measure-Object -Maximum).Maximum
  $y2 = ($pick | ForEach-Object { $_.Y + $_.H } | Measure-Object -Maximum).Maximum
  $anchor = @($pick | Where-Object { $_.Primary }) | Select-Object -First 1
  if (-not $anchor) { $anchor = $pick[0] }
  # rectangle englobant en pixels PHYSIQUES (resolution reelle a demander a Moonlight / mstsc)
  $px1 = ($pick | ForEach-Object { $_.PX } | Measure-Object -Minimum).Minimum
  $py1 = ($pick | ForEach-Object { $_.PY } | Measure-Object -Minimum).Minimum
  $px2 = ($pick | ForEach-Object { $_.PX + $_.PW } | Measure-Object -Maximum).Maximum
  $py2 = ($pick | ForEach-Object { $_.PY + $_.PH } | Measure-Object -Maximum).Maximum
  return [pscustomobject]@{
    Screens = $pick; Idxs = @($pick | ForEach-Object { $_.Idx })
    PW = [int]($px2 - $px1); PH = [int]($py2 - $py1)
    X = [int]$x1; Y = [int]$y1; W = [int]($x2 - $x1); H = [int]($y2 - $y1)
    Anchor = $anchor; Multi = ($pick.Count -gt 1)
  }
}
# Memorise une selection d'ecrans pour une machine. Refuse (et le dit dans le log) une
# selection vide, inconnue ou NON CONTIGUE. Renvoie $true si elle est acceptee.
$script:SetSelection = {
  param([string]$ip, [int[]]$idxs)
  $pick = @($script:Screens | Where-Object { $idxs -contains $_.Idx })
  if ($pick.Count -eq 0) { return $false }
  if (-not (& $script:ScreensContiguous $pick)) {
    & $script:LogFn ("ecrans " + (($pick | ForEach-Object { $_.Idx }) -join ', ') + " NON contigus -> selection ignoree (choisir des ecrans qui se touchent)")
    return $false
  }
  $script:ScreenChoice[$ip] = @($pick | ForEach-Object { $_.Idx })
  & $script:SaveScreenChoice
  # un NOUVEAU choix d'ecrans efface le gris de la derniere deconnexion (pas d'une session active) ;
  # choix GLOBAL : le gris de toutes les machines
  foreach ($gk in @($script:MlState.Keys)) {
    if ($ip -ne '__global' -and $gk -ne $ip) { continue }
    $mlS = $script:MlState[$gk]
    if ($mlS -and ($mlS.State -eq 'ended' -or $mlS.State -eq 'lost')) { & $script:SetMlState $gk 'none' }
  }
  return $true
}
# Mini-carte : rectangle (en px, dans un cadre w x h) de chaque ecran, a l'echelle
# et dans leurs positions relatives (ecrans a gauche/droite/dessous respectes).
$script:MapLayout = {
  param([double]$w, [double]$h)
  $all = @($script:Screens)
  $out = @()
  if ($all.Count -eq 0) { return ,$out }
  $minX = [double]::MaxValue; $minY = [double]::MaxValue; $maxX = [double]::MinValue; $maxY = [double]::MinValue
  # dessin a l'echelle de la disposition PHYSIQUE (un 4K a 125 % garde ses vraies proportions)
  foreach ($s in $all) {
    if ($s.PX -lt $minX) { $minX = $s.PX }; if ($s.PY -lt $minY) { $minY = $s.PY }
    if (($s.PX + $s.PW) -gt $maxX) { $maxX = $s.PX + $s.PW }; if (($s.PY + $s.PH) -gt $maxY) { $maxY = $s.PY + $s.PH }
  }
  $pad = 3.0
  $sc = [Math]::Min(($w - 2 * $pad) / ($maxX - $minX), ($h - 2 * $pad) / ($maxY - $minY))
  $ox = ($w - ($maxX - $minX) * $sc) / 2; $oy = ($h - ($maxY - $minY) * $sc) / 2
  foreach ($s in $all) {
    $out += [pscustomobject]@{
      Idx = $s.Idx; Primary = $s.Primary; W = $s.PW; H = $s.PH
      X = [single]($ox + ($s.PX - $minX) * $sc + 1); Y = [single]($oy + ($s.PY - $minY) * $sc + 1)
      Wd = [single]($s.PW * $sc - 2); Ht = [single]($s.PH * $sc - 2)
    }
  }
  return ,$out
}

# Numero de l'ecran sous un point (x, y) de la mini-carte, 0 si aucun.
$script:MapHit = {
  param($panel, [int]$x, [int]$y)
  foreach ($r in (& $script:MapLayout $panel.Width $panel.Height)) {
    if ($x -ge $r.X -and $x -le ($r.X + $r.Wd) -and $y -ge $r.Y -and $y -le ($r.Y + $r.Ht)) { return [int]$r.Idx }
  }
  return 0
}

# Numeros des ecrans touches par un rectangle tire a la souris sur la mini-carte
# (x1,y1)-(x2,y2) : tous les ecrans dont le dessin croise la zone ("glisser pour selectionner").
$script:MapScreensInRect = {
  param($panel, [double]$x1, [double]$y1, [double]$x2, [double]$y2)
  $lx = [Math]::Min($x1, $x2); $hx = [Math]::Max($x1, $x2); $ly = [Math]::Min($y1, $y2); $hy = [Math]::Max($y1, $y2)
  $out = @()
  foreach ($r in (& $script:MapLayout $panel.Width $panel.Height)) {
    if ($r.X -lt $hx -and ($r.X + $r.Wd) -gt $lx -and $r.Y -lt $hy -and ($r.Y + $r.Ht) -gt $ly) { $out += [int]$r.Idx }
  }
  return ,$out
}

# Ctrl+clic / Ctrl+glisser : combine la selection memorisee ($cur) et les ecrans touches
# ($set). Un Ctrl+CLIC (moved faux) BASCULE l'ecran (le retire s'il y est, l'ajoute sinon) ;
# un Ctrl+GLISSER (moved vrai) AJOUTE tous les ecrans touches.
$script:CtrlCombine = {
  param($cur, $set, [bool]$moved)
  $new = @($cur)
  foreach ($i in @($set)) {
    if (-not $moved -and ($new -contains $i)) { $new = @($new | Where-Object { $_ -ne $i }) }
    elseif ($new -notcontains $i) { $new += $i }
  }
  return ,$new
}

# Appairage Moonlight d'une machine (registre de Moonlight) : l'hote doit avoir son
# certificat (srvcert) et l'IP parmi ses adresses. Renvoie aussi sa liste d'applications.
$script:GetMoonlightHost = {
  param([string]$ip)
  $paired = $false; $apps = @(); $appIds = @{}
  try {
    $hk = 'HKCU:\Software\Moonlight Game Streaming Project\Moonlight\hosts'
    foreach ($hostKey in @(Get-ChildItem $hk -ErrorAction SilentlyContinue)) {
      $hp = Get-ItemProperty $hostKey.PSPath -ErrorAction SilentlyContinue
      if (-not $hp -or -not $hp.srvcert) { continue }
      if (@($hp.localaddress, $hp.manualaddress, $hp.remoteaddress, $hp.ipv6address) -contains $ip) {
        $paired = $true
        $apps = @(Get-ChildItem (Join-Path $hostKey.PSPath 'apps') -ErrorAction SilentlyContinue |
          ForEach-Object { (Get-ItemProperty $_.PSPath).name } | Where-Object { $_ })
        # identifiants des applications (nom -> id) : permettent de reconnaitre l'application en cours sur la VM
        foreach ($ak in @(Get-ChildItem (Join-Path $hostKey.PSPath 'apps') -ErrorAction SilentlyContinue)) {
          $ap = Get-ItemProperty $ak.PSPath -ErrorAction SilentlyContinue
          if ($ap -and $ap.name -and $ap.id) { $appIds[[string]$ap.name] = [long]$ap.id }
        }
        break
      }
    }
  } catch { }
  return [pscustomobject]@{ Paired = $paired; Apps = $apps; AppIds = $appIds }
}

# Placement de la fenetre de Moonlight sur l'ecran (ou les ecrans) choisi(s). Moonlight
# n'a AUCUNE option "ecran" : il ouvre le flux sur l'ecran ou se trouve sa propre fenetre.
# On surveille donc (200 ms, 25 s max) les fenetres du processus lance :
#  - UN SEUL ecran : chaque fenetre, a son apparition, est ramenee sur cet ecran (plein
#    ecran -> recadree sur l'ecran cible ; fenetre normale -> centree dessus, reduite
#    si plus grande) ;
#  - PLUSIEURS ecrans contigus : la petite fenetre de connexion est ramenee sur l'ecran
#    d'OUVERTURE (Anchor) pour que Moonlight y demarre ; puis la fenetre du FLUX (titre
#    "... - Moonlight") est redimensionnee et deplacee pour couvrir exactement le
#    rectangle englobant des ecrans choisis. Windows/SDL pouvant la remettre a sa taille
#    d'origine au demarrage du flux, le calage est verifie et reapplique (5 fois max)
#    jusqu'a ce qu'il tienne ~1,6 s.
# Hors calage multi-ecrans, chaque fenetre n'est deplacee QU'UNE FOIS (liberte ensuite).
# $sel : objet de $script:ResolveSelection (Screens, X/Y/W/H englobants, Anchor, Multi).
$script:PlaceOnScreen = {
  param([int]$procId, $sel)
  # L'etat du suivi est porte par le MINUTEUR lui-meme (propriete Tag) et non par une variable
  # de script : si la fenetre du launcher est fermee pendant un suivi, les variables du
  # script disparaissent mais le minuteur peut encore sonner une fois -> il doit pouvoir
  # s'arreter seul ($this) sans rien lire dans la portee du script.
  $state = @{ Pid = $procId; Sel = $sel; Fit = @{}; Done = (New-Object 'System.Collections.Generic.HashSet[string]'); T0 = (Get-Date) }
  if (-not $script:PlaceTimer) {
    $script:PlaceTimer = New-Object System.Windows.Forms.Timer
    $script:PlaceTimer.Interval = 200
    $script:PlaceTimer.Add_Tick({
      $timer = $this
      $st = $timer.Tag
      if (-not $st -or -not $script:LogFn) { $timer.Stop(); $timer.Tag = $null; return }
      $gone = $null -eq (Get-Process -Id $st.Pid -ErrorAction SilentlyContinue)
      if ($gone -or ((Get-Date) - $st.T0).TotalSeconds -gt 25) {
        $timer.Stop(); $timer.Tag = $null
        & $script:LogFn ("Moonlight: suivi de placement termine (" + $(if ($gone) { "processus ferme" } else { "25 s ecoulees" }) + ", " + $st.Done.Count + " fenetre(s) placee(s))")
        return
      }
      $sel = $st.Sel
      $t = $sel.Anchor            # ecran d'ouverture (= l'unique ecran quand Multi est faux)
      foreach ($w in [VscScrV3]::GetProcessWindows($st.Pid)) {
        if ($st.Done.Contains($w[0])) { continue }
        $l = [int]$w[1]; $tp = [int]$w[2]; $ww = [int]$w[3] - $l; $wh = [int]$w[4] - $tp
        $cx = $l + $ww / 2; $cy = $tp + $wh / 2
        # --- plusieurs ecrans : la fenetre du FLUX est calee sur le rectangle englobant
        if ($sel.Multi -and ($w[5] -match $script:MultiStreamTitle)) {
          $fs = $st.Fit[$w[0]]
          if (-not $fs) { $fs = @{ Applied = 0; Stable = 0 }; $st.Fit[$w[0]] = $fs }
          if (([Math]::Abs($l - $sel.X) -le 6) -and ([Math]::Abs($tp - $sel.Y) -le 6) -and ([Math]::Abs($ww - $sel.W) -le 6) -and ([Math]::Abs($wh - $sel.H) -le 6)) {
            $fs.Stable++
            if ($fs.Stable -ge 8) {
              [void]$st.Done.Add($w[0])
              & $script:LogFn ("Moonlight: fenetre '" + $w[5] + "' calee sur les ecrans " + ($sel.Idxs -join '+') + " (" + $sel.W + "x" + $sel.H + " a " + $sel.X + "," + $sel.Y + ")")
            }
            continue
          }
          $fs.Stable = 0
          if ($fs.Applied -ge 5) {
            [void]$st.Done.Add($w[0])
            & $script:LogFn ("Moonlight: fenetre '" + $w[5] + "' ne reste pas calee (" + $ww + "x" + $wh + " au lieu de " + $sel.W + "x" + $sel.H + ") -> abandon ; essayer MultiScreenDisplayMode = windowed")
            continue
          }
          [void][VscScrV3]::Fit([long]$w[0], $sel.X, $sel.Y, $sel.W, $sel.H, [bool]$script:MultiScreenBorderless)
          $fs.Applied++
          & $script:LogFn ("Moonlight: fenetre '" + $w[5] + "' (" + $ww + "x" + $wh + " a " + $l + "," + $tp + ") -> calage sur les ecrans " + ($sel.Idxs -join '+') + " : " + $sel.W + "x" + $sel.H + " a " + $sel.X + "," + $sel.Y + " (essai " + $fs.Applied + ")")
          continue
        }
        if ($cx -ge $t.X -and $cx -lt ($t.X + $t.W) -and $cy -ge $t.Y -and $cy -lt ($t.Y + $t.H)) {
          [void]$st.Done.Add($w[0]); continue          # deja sur le bon ecran
        }
        # ecran actuel de la fenetre (celui qui contient son centre)
        $src = @($script:Screens | Where-Object { $cx -ge $_.X -and $cx -lt ($_.X + $_.W) -and $cy -ge $_.Y -and $cy -lt ($_.Y + $_.H) }) | Select-Object -First 1
        if ($src -and $ww -ge ($src.W * 0.95) -and $wh -ge ($src.H * 0.95)) {
          $nx = $t.X; $ny = $t.Y; $nw = $t.W; $nh = $t.H                       # plein ecran -> plein ecran cible
        } else {
          $nw = [Math]::Min($ww, [int]($t.W * 0.9)); $nh = [Math]::Min($wh, [int]($t.H * 0.9))
          $nx = $t.X + [int](($t.W - $nw) / 2); $ny = $t.Y + [int](($t.H - $nh) / 2)
        }
        [void][VscScrV3]::Move([long]$w[0], $nx, $ny, $nw, $nh)
        [void]$st.Done.Add($w[0])
        & $script:LogFn ("Moonlight: fenetre '" + $w[5] + "' (" + $ww + "x" + $wh + ") deplacee sur l'ecran " + $t.Idx + " -> " + $nw + "x" + $nh + " a (" + $nx + "," + $ny + ")")
      }
    })
  }
  $script:PlaceTimer.Tag = $state
  $script:PlaceTimer.Start()
}

# Surveillance des processus Moonlight lances (voir RECONNEXION AUTOMATIQUE plus haut) : elle
# alimente a la fois la reconnexion automatique ET l'ETAT affiche sur la mini-carte
# ($script:SetMlState). Une entree par machine (IP), controlee une fois par seconde, jusqu'a
# la fermeture de Moonlight :
#   - fenetre du flux ("... - Moonlight") apparue  -> etat OPERATIONNEL (live) ;
#   - fenetre du flux disparue 4 s de suite alors que Moonlight tourne encore (ex. boite
#     d'erreur) -> etat "flux perdu" ; si elle revient -> de nouveau operationnel ;
#     (une fenetre reduite dans la barre des taches garde son titre : pas de fausse alerte) ;
#   - Moonlight ferme -> etat "deconnecte" (si le flux avait ete affiche), puis decision de
#     reconnexion :
#       oui  : fermeture avec un CODE D'ERREUR, flux deja affiche, dans la fenetre de
#              surveillance, et relances restantes ;
#       non  : code 0 (fermeture normale), flux jamais affiche, hors fenetre, ou plus de relance.
# Chaque decision est ecrite dans le journal (code de sortie, duree) pour pouvoir ajuster
# les reglages si Moonlight signale autrement la perte de connexion.
# Etat porte par le minuteur (Tag) : il peut s'arreter seul meme si le script est termine.
$script:WatchMoonlight = {
  param($proc, [string]$ip, $mlArgs, $sel, $mlArgsBase = $null, [bool]$profileUsed = $false)
  if (-not $script:RetryTimer) {
    $script:RetryTimer = New-Object System.Windows.Forms.Timer
    $script:RetryTimer.Interval = 1000
    $script:RetryTimer.Add_Tick({
      $timer = $this
      $tbl = $timer.Tag
      if (-not $tbl -or -not $script:LogFn) { $timer.Stop(); $timer.Tag = $null; return }
      $now = Get-Date
      foreach ($key in @($tbl.Keys)) {
        $st = $tbl[$key]
        # --- pause avant la relance, puis relance avec les memes arguments et les memes ecrans
        if ($st.RetryAt) {
          if ($now -lt $st.RetryAt) { continue }
          $st.RetryAt = $null
          try {
            $np = Start-Process $script:MoonlightExe -ArgumentList $st.Args -PassThru
            $null = $np.Handle                         # garde le handle : permet de lire ExitCode ensuite
            $st.Proc = $np; $st.T0 = Get-Date; $st.SawStream = $false; $st.Lost = $false; $st.Missing = 0; $st.Stable = $false
            # relance sans profil (options refusees) : ne compte pas comme une reconnexion automatique
            $note = $null
            if ($st.Fallback) { $st.Fallback = $false; $note = "relance sans les options du profil" }
            else { $st.Retries++; $note = "reconnexion automatique, tentative " + $st.Retries + "/" + $script:MoonlightRetryMax }
            & $script:SetMlState $st.Ip 'connecting' $st.Idxs $null $note
            if ($st.Sel) { & $script:PlaceOnScreen $np.Id $st.Sel }
          } catch {
            & $script:LogFn ("Moonlight: ECHEC de la reconnexion automatique : " + $_.Exception.Message)
            & $script:SetMlState $st.Ip 'none'
            $tbl.Remove($key)
          }
          continue
        }
        $p = $st.Proc
        $age = ($now - $st.T0).TotalSeconds
        if (-not $p.HasExited) {
          # la fenetre du flux existe-t-elle ? (toute taille : une fenetre reduite compte)
          $present = $false
          foreach ($ttl in [VscScrV3]::WindowTitles($p.Id)) { if ($ttl -match $script:MoonlightStreamTitle) { $present = $true; break } }
          if ($present) {
            $st.Missing = 0
            if (-not $st.SawStream) {
              $st.SawStream = $true
              & $script:SetMlState $st.Ip 'live' $st.Idxs $null ("flux affiche apres " + [int]$age + " s")
            } elseif ($st.Lost) {
              $st.Lost = $false
              & $script:SetMlState $st.Ip 'live' $st.Idxs $null "fenetre du flux de retour"
            }
          } elseif ($st.SawStream -and -not $st.Lost) {
            $st.Missing++
            if ($st.Missing -ge 4) {
              $st.Lost = $true
              & $script:SetMlState $st.Ip 'lost' $st.Idxs $null "la fenetre du flux a disparu alors que Moonlight tourne encore"
            }
          }
          if (-not $st.Stable -and $age -gt $script:MoonlightRetryWithinSec) {
            $st.Stable = $true
            & $script:LogFn ("Moonlight: session stable depuis " + [int]$age + " s -> plus de reconnexion automatique, l'etat reste suivi")
          }
          continue
        }
        # --- Moonlight s'est ferme
        $code = $null
        try { $code = $p.ExitCode } catch { }
        & $script:LogFn ("Moonlight: ferme (code de sortie " + $(if ($null -eq $code) { "inconnu" } else { $code }) + ") apres " + [int]$age + " s ; flux " + $(if ($st.SawStream) { "affiche" } else { "jamais affiche" }))
        # deconnexion : les ecrans occupes passent en gris (rien a griser si le flux n'a jamais ete affiche)
        # (l'affichage de la session est RETIRE des ecrans a la fermeture : plus de ghost gris ; une
        #  reconnexion automatique prevue le remet en "en connexion", voir plus bas)
        & $script:SetMlState $st.Ip 'none' $st.Idxs $code
        # profil refuse ? Moonlight s'est ferme aussitot avec une erreur sans jamais afficher de flux :
        # une option generee (--resolution / --fps / --bitrate) est peut-etre inconnue de cette
        # version -> relance UNE fois sans profil, et le profil automatique est desactive jusqu'a
        # la fermeture du launcher
        if ($st.ProfileUsed -and -not $st.FallbackDone -and -not $st.SawStream -and $age -lt 8 -and $null -ne $code -and $code -ne 0) {
          $st.FallbackDone = $true; $st.ProfileUsed = $false; $st.Fallback = $true
          $st.Args = $st.ArgsBase
          $script:MoonlightAutoProfile = $false
          $st.RetryAt = (Get-Date).AddSeconds(1)
          & $script:SetMlState $st.Ip 'connecting' $st.Idxs $null "relance sans profil"
          & $script:LogFn ("Moonlight: ferme aussitot (code " + $code + ") sans flux avec les options du profil -> relance SANS profil ; profil automatique desactive jusqu'a la fermeture du launcher")
          continue
        }
        $abnormal = ($null -ne $code -and $code -ne 0) -or $script:MoonlightRetryOnAnyExit
        $why = $null
        if ($st.Retries -ge $script:MoonlightRetryMax) { $why = "relances epuisees (" + $st.Retries + "/" + $script:MoonlightRetryMax + ")" }
        elseif ($age -gt $script:MoonlightRetryWithinSec) { $why = "hors de la fenetre de surveillance" }
        elseif (-not $st.SawStream) { $why = "le flux n'a jamais ete affiche (machine injoignable ou refus ?)" }
        elseif ($age -lt 3) { $why = "ferme trop vite" }
        elseif (-not $abnormal) { $why = "fermeture normale (code 0) : pas de reconnexion" }
        if ($why) {
          & $script:LogFn ("Moonlight: pas de reconnexion automatique : " + $why)
          $tbl.Remove($key)
        } else {
          $st.RetryAt = (Get-Date).AddSeconds($script:MoonlightRetryDelaySec)
          & $script:LogFn ("Moonlight: connexion perdue -> reconnexion automatique dans " + $script:MoonlightRetryDelaySec + " s")
          & $script:SetMlState $st.Ip 'connecting' $st.Idxs $null ("reconnexion automatique dans " + $script:MoonlightRetryDelaySec + " s")   # l'affichage reste (en connexion) pendant l'attente
        }
      }
      if ($tbl.Count -eq 0) { $timer.Stop(); $timer.Tag = $null }
    })
  }
  if (-not $script:RetryTimer.Tag) { $script:RetryTimer.Tag = @{} }
  $script:RetryTimer.Tag[$ip] = @{ Proc = $proc; Ip = $ip; Args = $mlArgs; Sel = $sel; Idxs = @($sel.Idxs); T0 = (Get-Date); SawStream = $false; Lost = $false; Missing = 0; Stable = $false; Retries = 0; RetryAt = $null; ArgsBase = $(if ($mlArgsBase) { $mlArgsBase } else { $mlArgs }); ProfileUsed = $profileUsed; FallbackDone = $false; Fallback = $false }
  $script:RetryTimer.Start()
}

