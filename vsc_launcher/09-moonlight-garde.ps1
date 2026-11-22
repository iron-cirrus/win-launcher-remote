# 09-moonlight-garde.ps1 - Garde de taille des fenetres Moonlight, etat/lancement/arret des sessions
# Fichier charge par vsc_launcher.ps1 (dot-source : meme portee script). Lignes d'origine 1383-1554.

# ---------- GARDE DE LA TAILLE DES FENETRES MOONLIGHT (tache de fond, toutes les 5 s) ----------
# Un changement de configuration des ecrans locaux (ecran eteint/rallume, resolution, veille...)
# fait redimensionner/deplacer les fenetres par Windows : la fenetre du flux Moonlight ne couvre
# plus les ecrans choisis. Pour chaque session OPERATIONNELLE, la fenetre du flux est comparee a
# la place PREVUE a l'ouverture, recalculee sur la disposition ACTUELLE des ecrans :
#   - plusieurs ecrans : le rectangle englobant des ecrans de la session (calage exact) ;
#   - un seul ecran    : la position/taille relevee une fois le placement initial termine,
#                        exprimee par rapport a l'ecran (suit l'ecran s'il change de place).
# Ecart de plus de 6 px -> la fenetre est remise en place (et c'est ecrit dans le journal).
# Rien n'est fait si un ecran de la session a disparu, pendant le placement initial, ou si la
# fenetre est reduite.
$script:WinRef = @{}          # ip -> @{ Pid; Idxs; RelX; RelY; W; H } (session sur un seul ecran)
$script:WinGuardNote = @{}    # ip -> derniere raison d'abstention journalisee (evite la repetition)
$script:GuardWindows = {
  foreach ($ip in @($script:MlState.Keys)) {
    $mlS = $script:MlState[$ip]
    if (-not $mlS -or $mlS.State -ne 'live') { $script:WinRef.Remove($ip); continue }
    # processus Moonlight de la session : lance par le launcher, ou deja ouvert (adopte)
    $p = $null
    if ($script:RetryTimer -and $script:RetryTimer.Tag -and $script:RetryTimer.Tag.ContainsKey($ip)) { $p = $script:RetryTimer.Tag[$ip].Proc }
    if (-not $p -and $script:MlAdopted.ContainsKey($ip)) { $p = $script:MlAdopted[$ip] }
    if (-not $p) { continue }
    try { if ($p.HasExited) { continue } } catch { continue }
    # placement initial encore en cours pour ce processus : ne pas s'en meler
    if ($script:PlaceTimer -and $script:PlaceTimer.Enabled -and $script:PlaceTimer.Tag -and $script:PlaceTimer.Tag.Pid -eq $p.Id) { continue }
    $idxs = @($mlS.Idxs)
    if ($idxs.Count -eq 0) { continue }
    $missing = @($idxs | Where-Object { $i = $_; -not @($script:Screens | Where-Object { $_.Idx -eq $i }) })
    if ($missing.Count -gt 0) {
      $why = "ecran(s) " + ($missing -join '+') + " absent(s)"
      if ($script:WinGuardNote[$ip] -ne $why) { $script:WinGuardNote[$ip] = $why; & $script:LogFn ("Moonlight " + $ip + " : taille de fenetre non surveillee, " + $why + " (en attente de son retour)") }
      continue
    }
    $script:WinGuardNote.Remove($ip)
    $sel = & $script:ResolveSelection $ip $idxs
    if (-not $sel) { continue }
    $win = $null
    foreach ($w in [VscScrV3]::GetProcessWindows($p.Id)) { if ($w[5] -match $script:MoonlightStreamTitle) { $win = $w; break } }
    if (-not $win) { continue }          # fenetre du flux absente ou reduite
    $l = [int]$win[1]; $t = [int]$win[2]; $ww = [int]$win[3] - $l; $wh = [int]$win[4] - $t
    if ($sel.Multi) {
      $ex = $sel.X; $ey = $sel.Y; $ew = $sel.W; $eh = $sel.H
    } else {
      $ref = $script:WinRef[$ip]
      if (-not $ref -or $ref.Pid -ne $p.Id -or (($ref.Idxs -join '+') -ne ($idxs -join '+'))) {
        # premiere vue apres le placement : on retient la place ACTUELLE comme place prevue
        # (seulement si la fenetre est bien sur son ecran : centre dans l'ecran)
        $cx = $l + $ww / 2; $cy = $t + $wh / 2
        if ($cx -lt $sel.X -or $cx -ge ($sel.X + $sel.W) -or $cy -lt $sel.Y -or $cy -ge ($sel.Y + $sel.H)) { continue }
        $script:WinRef[$ip] = @{ Pid = $p.Id; Idxs = $idxs; RelX = $l - $sel.X; RelY = $t - $sel.Y; W = $ww; H = $wh }
        & $script:LogFn ("Moonlight " + $ip + " : place de la fenetre retenue (" + $ww + "x" + $wh + " sur l'ecran " + ($idxs -join '+') + ") -> surveillee")
        continue
      }
      $ew = [Math]::Min($ref.W, $sel.W); $eh = [Math]::Min($ref.H, $sel.H)
      $ex = $sel.X + [Math]::Max(0, [Math]::Min($ref.RelX, $sel.W - $ew)); $ey = $sel.Y + [Math]::Max(0, [Math]::Min($ref.RelY, $sel.H - $eh))
    }
    if ([Math]::Abs($l - $ex) -le 6 -and [Math]::Abs($t - $ey) -le 6 -and [Math]::Abs($ww - $ew) -le 6 -and [Math]::Abs($wh - $eh) -le 6) { continue }
    if ($sel.Multi) { [void][VscScrV3]::Fit([long]$win[0], $ex, $ey, $ew, $eh, [bool]$script:MultiScreenBorderless) }
    else { [void][VscScrV3]::Move([long]$win[0], $ex, $ey, $ew, $eh) }
    & $script:LogFn ("Moonlight " + $ip + " : fenetre deplacee/redimensionnee par Windows (" + $ww + "x" + $wh + " a " + $l + "," + $t + ") -> remise en place " + $ew + "x" + $eh + " a " + $ex + "," + $ey + " (ecrans " + ($idxs -join '+') + ")")
  }
}
# Session que Moonlight a ouverte sur la VM, d'apres l'historique de SES requetes (journaux
# Moonlight-*.log, les 80 plus recents, dans l'ordre) : Active = une session existe, AppId, Mode =
# mode ("LxHxFPS") du dernier /launch (un /resume ne le change pas). Renvoie $null si les journaux
# n'ont aucune requete vers cette machine.
$script:GetBelievedHostSession = {
  param([string]$ip)
  $state = $null
  try {
    $files = @(Get-ChildItem $script:MoonlightLogDir -Filter 'Moonlight-*.log' -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match '^Moonlight-(\d+)\.log$' } |
      Sort-Object { [long]([regex]::Match($_.Name, '\d+').Value) } | Select-Object -Last 80)
    $re = 'Executing request: "https://' + [regex]::Escape($ip) + ':\d+/(launch|resume|cancel)\?([^"]*)"'
    foreach ($f in $files) {
      $rows = $null; try { $rows = [System.IO.File]::ReadAllLines($f.FullName) } catch { continue }
      foreach ($ln in $rows) {
        $m = [regex]::Match($ln, $re)
        if (-not $m.Success) { continue }
        $kind = $m.Groups[1].Value; $q = $m.Groups[2].Value
        $am = [regex]::Match($q, 'appid=(\d+)'); $mm = [regex]::Match($q, 'mode=([0-9]+x[0-9]+x[0-9]+)')
        $aid = $(if ($am.Success) { [long]$am.Groups[1].Value } else { $null })
        if ($kind -eq 'cancel') { $state = [pscustomobject]@{ Active = $false; AppId = $null; Mode = $null; At = $f.LastWriteTime } }
        elseif ($kind -eq 'launch') { $state = [pscustomobject]@{ Active = $true; AppId = $aid; Mode = $(if ($mm.Success) { $mm.Groups[1].Value } else { $null }); At = $f.LastWriteTime } }
        elseif (-not $state -or -not $state.Active) { $state = [pscustomobject]@{ Active = $true; AppId = $aid; Mode = $null; At = $f.LastWriteTime } }   # /resume sans /launch connu : mode inconnu
      }
    }
  } catch { }
  return $state
}
# Application en cours sur la VM : identifiant lu dans la reponse "serverinfo" du serveur Apollo
# (requete HTTP en lecture seule, la meme que Moonlight envoie en permanence). 0 = rien en cours ;
# $null = serveur injoignable ou reponse illisible.
$script:GetHostRunningApp = {
  param([string]$ip)
  try {
    $rq = [System.Net.HttpWebRequest]::Create("http://" + $ip + ":47989/serverinfo?uniqueid=0123456789ABCDEF")
    $rq.Timeout = 2500
    $rs = $rq.GetResponse(); $sr = New-Object System.IO.StreamReader($rs.GetResponseStream())
    $txt = $sr.ReadToEnd(); $sr.Close(); $rs.Close()
    $cg = ([xml]$txt).root.currentgame
    if ($null -eq $cg -or "$cg" -eq '') { return $null }
    return [long]$cg
  } catch { return $null }
}
# Demarre Moonlight (stream) avec les arguments donnes, puis suivi de placement + surveillance.
# $applied : la resolution du profil a-t-elle pu etre appliquee sur la VM (voir SaveMoonlightProfile).
$script:LaunchMoonlightNow = {
  param([string]$ip, $mlArgs, $mlArgsBase, $sel, $prof, [bool]$applied = $true)
  try {
    if ($prof -and $sel) { & $script:SaveMoonlightProfile $ip $sel $prof $applied }
    $mp = Start-Process $script:MoonlightExe -ArgumentList $mlArgs -PassThru
    $null = $mp.Handle                               # garde le handle : permet de lire ExitCode ensuite
    if ($mp -and $sel) { & $script:PlaceOnScreen $mp.Id $sel }
    # la surveillance tourne toujours : elle alimente l'ETAT affiche sur la mini-carte ;
    # MoonlightRetryMax = 0 desactive seulement la reconnexion automatique
    if ($mp -and $sel) {
      & $script:SetMlState $ip 'connecting' $sel.Idxs
      & $script:WatchMoonlight $mp $ip $mlArgs $sel $mlArgsBase ([bool]$prof)
    }
  } catch {
    & $script:LogFn ("  ECHEC Moonlight: " + $_.Exception.Message)
    & $script:RdpFallback $ip "repli apres echec de Moonlight"
  }
}
# Ferme la session en cours sur la VM ("Moonlight quit <hote>"), attend que la VM soit libre
# (currentgame = 0, 8 s au plus) puis lance Moonlight. Asynchrone (minuteur) : l'interface ne
# gele pas. Etat porte par le minuteur (Tag).
$script:QuitThenLaunch = {
  param([string]$ip, $mlArgs, $mlArgsBase, $sel, $prof)
  $qp = $null
  try { $qp = Start-Process $script:MoonlightExe -ArgumentList @('quit', $ip) -PassThru; $null = $qp.Handle } catch {
    & $script:LogFn ("Moonlight: ECHEC de la commande 'quit' : " + $_.Exception.Message + " -> lancement sans fermer la session")
    & $script:LaunchMoonlightNow $ip $mlArgs $mlArgsBase $sel $prof $false
    return
  }
  & $script:SetMlState $ip 'connecting' $sel.Idxs $null "fermeture de la session precedente sur la VM"
  if (-not $script:PendingTimer) {
    $script:PendingTimer = New-Object System.Windows.Forms.Timer
    $script:PendingTimer.Interval = 300
    $script:PendingTimer.Add_Tick({
      $timer = $this
      $st = $timer.Tag
      if (-not $st -or -not $script:LogFn) { $timer.Stop(); $timer.Tag = $null; return }
      $now = Get-Date
      if (-not $st.QuitDone) {
        $ex = $true; try { $ex = $st.Quit.HasExited } catch { }
        if (-not $ex -and ($now - $st.T0).TotalSeconds -le 12) { return }
        $st.QuitDone = $true; $st.T1 = $now
        $qc = $null; try { $qc = $st.Quit.ExitCode } catch { }
        if (-not $ex) { try { $st.Quit.Kill() } catch { }; & $script:LogFn "Moonlight: la commande 'quit' ne se termine pas (12 s) -> abandon" }
        else { & $script:LogFn ("Moonlight: commande 'quit' terminee (code " + $(if ($null -eq $qc) { "inconnu" } else { $qc }) + ") -> attente de la liberation de la VM") }
      }
      if (($now - $st.LastProbe).TotalMilliseconds -lt 1000) { return }
      $st.LastProbe = $now
      $cur = & $script:GetHostRunningApp $st.Ip
      $waited = ($now - $st.T1).TotalSeconds
      # on attend la pause (MoonlightQuitSettleSec : suppression de l'ecran virtuel par la VM) ET que
      # le serveur ne signale plus d'application ; au plus 10 s
      $settled = ($waited -ge $script:MoonlightQuitSettleSec)
      if (($settled -and ($null -eq $cur -or $cur -eq 0)) -or $waited -gt 10) {
        $freed = ($null -eq $cur -or $cur -eq 0)       # injoignable/inconnu : on suppose libre
        $timer.Stop(); $timer.Tag = $null
        & $script:LogFn ("Moonlight: " + $(if ($freed) { "session fermee, VM liberee" } else { "la VM n'a pas libere la session apres 10 s (l'ancienne session sera reprise : resolution inchangee)" }) + " -> lancement")
        & $script:LaunchMoonlightNow $st.Ip $st.Args $st.Base $st.Sel $st.Prof $freed
      }
    })
  }
  $script:PendingTimer.Tag = @{ Ip = $ip; Args = $mlArgs; Base = $mlArgsBase; Sel = $sel; Prof = $prof; Quit = $qp; T0 = (Get-Date); QuitDone = $false; T1 = $null; LastProbe = [datetime]::MinValue }
  $script:PendingTimer.Start()
}

