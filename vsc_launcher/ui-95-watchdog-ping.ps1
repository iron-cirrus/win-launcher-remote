# ui-95-watchdog-ping.ps1 - BuildUI : watchdog B, ping des hotes (15 s), fin de construction
# Fichier charge par vsc_launcher.ps1 (dot-source : meme portee script). Lignes d'origine 5025-5263.

# ---------- Watchdog B : ping periodique des hotes (15 s) ----------
# PERF : l'ancien Ping.Send SYNCHRONE, hote par hote, sur le fil de l'IHM gelait
# la fenetre 1,2 s par machine eteinte (3 eteintes = 3,6 s toutes les 15 s).
# Desormais : PingTick DEMARRE tous les pings en parallele (SendPingAsync) et
# rend la main aussitot ; PingCollect (timer 250 ms) applique les resultats
# des qu'ils arrivent. Aucun appel bloquant sur le fil de l'IHM.
$script:PingTick = {
  foreach ($c in $script:CardList) {
    if ($c.PingTask -or $c.PingFail -or $c.TcpAr -or -not $c.PingHost) { continue }   # verif precedente pas encore collectee
    try {
      $c.PingObj = New-Object System.Net.NetworkInformation.Ping
      $c.PingTask = $c.PingObj.SendPingAsync($c.PingHost, 1200)          # timeout 1,2 s / hote
    } catch {
      try { if ($c.PingObj) { $c.PingObj.Dispose() } } catch { }
      $c.PingObj = $null; $c.PingTask = $null
      $c.PingFail = $true                                                # ex: nom non resolu
    }
  }
}

# Style d'une carte selon sa joignabilite. INJOIGNABLE : fond tres sombre (plus
# sombre que toutes les couleurs de carte, y compris le gris-bleu du LAN),
# texte attenue, nom BARRE -> une machine eteinte se voit au premier coup d'oeil
# (avant : gris 55,55,55 quasi identique aux cartes LAN, seul le "KO" differait).
$script:SetCardStyle = {
  param($c, [bool]$dead)
  if ($dead) {
    $c.Card.Disabled = $true
    $c.Card.BackColor = $c.Card.DisabledColor
    $c.Card.Cursor = [System.Windows.Forms.Cursors]::No
    $c.LblTitle.ForeColor = [System.Drawing.Color]::FromArgb(125, 125, 125)
    $c.LblTitle.Font = $c.FontStrike
    $c.LblUser.ForeColor = [System.Drawing.Color]::FromArgb(95, 95, 95)
    $c.LblRole.ForeColor = [System.Drawing.Color]::FromArgb(95, 95, 95)
  } else {
    $c.Card.Disabled = $false
    $c.Card.BackColor = $c.Card.NormalColor
    $c.Card.Cursor = [System.Windows.Forms.Cursors]::Hand
    $c.LblTitle.ForeColor = [System.Drawing.Color]::White
    $c.LblTitle.Font = $c.FontNormal
    $c.LblUser.ForeColor = [System.Drawing.Color]::FromArgb(235, 235, 235)
    $c.LblRole.ForeColor = $c.RoleFg
  }
}

$script:PingCollect = {
  foreach ($c in $script:CardList) {
    $ok = $false
    $ms = -1
    $via = 'ping'
    if ($c.TcpAr) {
      # resultat de la 2e chance TCP (lancee apres un ping perdu), abandon apres 3 s
      $el = ((Get-Date) - $c.TcpT0).TotalMilliseconds
      if ($c.TcpAr.IsCompleted) {
        try { $c.TcpCli.EndConnect($c.TcpAr); $ok = $true; $ms = [int]$el } catch { }
      } elseif ($el -lt 3000) { continue }
      try { $c.TcpCli.Close() } catch { }
      $c.TcpAr = $null; $c.TcpCli = $null; $via = 'tcp'
    } elseif ($c.PingFail) {
      $c.PingFail = $false
    } elseif ($c.PingTask -and $c.PingTask.IsCompleted) {
      try {
        if ($c.PingTask.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
          $reply = $c.PingTask.Result
          $ok = ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success)
          if ($ok) { $ms = $reply.RoundtripTime }
        }
      } catch { $ok = $false }
      try { $c.PingObj.Dispose() } catch { }
      $c.PingTask = $null; $c.PingObj = $null
    } else {
      continue                                                           # pas de resultat pour cette carte
    }
    # PING PERDU : certains hotes (VPS chez un hebergeur, ICMP limite) perdent 10-15 % des pings
    # alors que SSH marche tres bien. Avant de conclure, 2e chance : connexion TCP au port du
    # service (resultat collecte aux passages suivants).
    if (-not $ok -and $via -eq 'ping' -and $c.ProbePort -gt 0) {
      try {
        $c.TcpCli = New-Object System.Net.Sockets.TcpClient
        $c.TcpT0 = Get-Date
        $c.TcpAr = $c.TcpCli.BeginConnect($c.PingHost, $c.ProbePort, $null, $null)
        continue
      } catch { try { $c.TcpCli.Close() } catch { }; $c.TcpAr = $null; $c.TcpCli = $null }
    }
    $prev = $c.LastOk
    if ($ok) { $c.FailStreak = 0 } else { $c.FailStreak = 1 + [int]$c.FailStreak }
    # HORS LIGNE seulement apres 2 verifications ratees D'AFFILEE (ping + TCP), soit ~30 s ;
    # au demarrage (etat inconnu) une seule suffit
    $alive = $ok -or (($prev -eq $true) -and $c.FailStreak -lt 2)
    # affichage : "12 ms" vert (ping, ou port TCP si le ping est perdu : voir l'info-bulle),
    # "..." gris (un echec isole, on attend la confirmation), "KO" rouge
    if ($ok) {
      $c.Dot.Text = ($script:SymOk + " " + $ms.ToString() + "ms")   # (pastille de 52 px : pas de place pour "tcp")
      $c.Dot.ForeColor = $script:DotOk
      if ($script:Tip) { $script:Tip.SetToolTip($c.Dot, $(if ($via -eq 'tcp') { "Ping perdu, mais le port " + $c.ProbePort + " répond (" + $ms + " ms)" } else { "Ping : " + $ms + " ms" })) }
    } elseif ($alive) {
      $c.Dot.Text = ($script:SymUnk + " ...")
      $c.Dot.ForeColor = [System.Drawing.Color]::Gray
    } else {
      $c.Dot.Text = ($script:SymKo + " KO")
      $c.Dot.ForeColor = $script:DotKo
    }

    if ($alive -and ($prev -eq $false)) {
      # machine revenue : reactive la carte (couleur normale)
      & $script:SetCardStyle $c $false
      & $script:LogFn ("watchdog: " + $c.PingHost + " joignable (" + $ms + " ms" + $(if ($via -eq 'tcp') { ", port " + $c.ProbePort }) + ") -> carte reactivee")
    } elseif (-not $alive -and ($prev -eq $true -or $prev -eq $null)) {
      # machine injoignable : carte assombrie, nom barre + clic bloque
      & $script:SetCardStyle $c $true
      & $script:LogFn ("watchdog: " + $c.PingHost + " INJOIGNABLE (" + $c.FailStreak + " verification(s) ratee(s), ping" + $(if ($c.ProbePort -gt 0) { " + port " + $c.ProbePort }) + ") -> carte desactivee")
    } elseif ($via -eq 'tcp' -and $ok -and $c.FailStreak -eq 0 -and -not $c.TcpNoted) {
      $c | Add-Member -NotePropertyName TcpNoted -NotePropertyValue $true -Force
      & $script:LogFn ("watchdog: " + $c.PingHost + " ping perdu mais port " + $c.ProbePort + " joignable (" + $ms + " ms) -> reste en ligne")
    }
    $c.LastOk = $alive
    $script:AliveMemo[[string]$c.PingHost] = [bool]$alive
  }
  # cartes INACTIVES masquees : la disposition est recalculee quand l'ensemble des cartes visibles change
  $sigV = (@($script:LayoutItems | ForEach-Object { if (& $script:CardVisible $_) { '1' } else { '0' } }) -join '')
  if ($sigV -ne $script:LayoutSig) {
    $script:LayoutSig = $sigV
    & $script:Relayout
    try {
      $amDir = Split-Path $script:AliveMemoPath -Parent
      if (-not (Test-Path $amDir)) { New-Item -ItemType Directory -Path $amDir -Force | Out-Null }
      [System.IO.File]::WriteAllText($script:AliveMemoPath, ($script:AliveMemo | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding $false))
    } catch { }
  }

  # DOUBLONS KO : un poste du scan RDP (sans alias SSH) injoignable, dont une AUTRE
  # carte de meme nom repond au ping, est un ancien enregistrement du cache (meme
  # PC revenu avec une autre IP : le scan reporte les postes absents).
  # -> on le retire de l'affichage et on reconstruit la grille (pas de trou).
  # NON destructif : le cache JSON n'est pas modifie ; si le PC "vivant" s'eteint,
  # l'ancienne carte reapparait au prochain lancement.
  $dups = @()
  foreach ($c in $script:CardList) {
    if (-not $c.RdpOnly -or $c.LastOk -ne $false) { continue }
    foreach ($o in $script:CardList) {
      if (-not [object]::ReferenceEquals($o, $c) -and $o.Label -eq $c.Label -and $o.LastOk -eq $true) {
        $dups += $c.MachIp; break
      }
    }
  }
  if ($dups.Count -gt 0) {
    if ($null -eq $script:HiddenIps) { $script:HiddenIps = @() }
    $script:HiddenIps = @($script:HiddenIps) + @($dups | Where-Object { $script:HiddenIps -notcontains $_ })
    & $script:LogFn ("doublon(s) KO masque(s) : " + ($dups -join ', ') + " (meme nom qu'une carte joignable) -> reconstruction")
    & $script:RebuildUI
    return
  }
}

$openTimer = New-Object System.Windows.Forms.Timer
$openTimer.Interval = 5000    # etat des fenetres VS Code : 5 s (reactif a la fermeture)
$openTimer.Add_Tick($script:OpenCheckTick)
$openTimer.Start()

$pingTimer = New-Object System.Windows.Forms.Timer
$pingTimer.Interval = 15000   # ping : 15 s
$pingTimer.Add_Tick($script:PingTick)
$pingTimer.Start()

# collecte des pings asynchrones : leger (aucun appel reseau), 250 ms
$pingCollectTimer = New-Object System.Windows.Forms.Timer
$pingCollectTimer.Interval = 250
$pingCollectTimer.Add_Tick($script:PingCollect)
$pingCollectTimer.Start()

# Suivi de la tache de fond de scan LAN : a sa fin, le cache JSON est a jour ->
# RECHARGE DYNAMIQUE DU LAUNCHER : on ferme la fenetre et le script se relance
# lui-meme avec -noscan (il chargera le cache fraichement ecrit sans rescanner).
if ($script:NetScanJob) {
  $netTimer = New-Object System.Windows.Forms.Timer
  $netTimer.Interval = 4000
  $netTimer.Add_Tick({
    $st = $script:NetScanJob.State
    if ($st -eq 'Running' -or $st -eq 'Queued' -or $st -eq 'Starting') { return }
    if ($st -eq 'Completed') {
      $res = Receive-Job $script:NetScanJob
      $n = 0
      if ($res -and $res.hosts) { $n = @($res.hosts).Count }
      & $script:LogFn ("scan LAN termine : " + $n + " poste(s) RDP trouve(s) -> rechargement automatique du launcher")
      if ($res -and $res.hosts) {
        foreach ($hh in @($res.hosts)) {
          if ($hh.parent) {
            & $script:LogFn ("  scan LAN: " + $hh.ip + " -> VM '" + $hh.vmname + "' sur " + $hh.parent + " (preuve " + $hh.via + ", mac " + $hh.mac + ")")
          } else {
            & $script:LogFn ("  scan LAN: " + $hh.ip + " -> " + $hh.kind + " (mac " + $hh.mac + ", " + $hh.hops + " saut(s)) : AUCUN hote libvirt ne la declare")
          }
        }
      }
      $script:NetRestart = $true
    } else {
      & $script:LogFn ("scan LAN en ECHEC (" + $st + ") - pas de rechargement")
      # detail de l'echec du job (le log du job est separe de celui du launcher)
      try {
        $cj = $script:NetScanJob.ChildJobs[0].JobStateInfo.Reason
        if ($cj) { & $script:LogFn ("  motif : " + $cj.Exception.Message) }
      } catch { }
    }
    # le diagnostic du scan est loggue MEME en cas d'echec (s'il a pu etre emis)
    if ($res -and $res.diag) {
      foreach ($d in @($res.diag)) { & $script:LogFn ("  scan LAN: " + $d) }
    }
    Remove-Job $script:NetScanJob -Force -ErrorAction SilentlyContinue
    $script:NetScanJob = $null
    $netTimer.Stop()
    # PAS de fermeture de fenetre : reconstruction des controles EN PLACE
    if ($script:NetRestart) { & $script:RebuildUI }
  })
  $netTimer.Start()
}

# premier controle immediat (des l'affichage)
& $script:OpenCheckTick
& $script:PingTick

# Sunshine : etat des machines Linux deja sondees, reapplique tout de suite apres une reconstruction
foreach ($c in $script:CardList) {
  if ($c.IsLinux -and $script:SunMemo.ContainsKey([string]$c.PingHost)) {
    $sm = $script:SunMemo[[string]$c.PingHost]
    & $script:SunshineApply $c $sm.Open $sm.IpSeen $true
    $c.SunLast = Get-Date          # pas de nouvelle sonde avant 30 s
  }
}
# disposition initiale (cartes visibles d'apres la memoire du dernier etat connu)
$script:LayoutSig = (@($script:LayoutItems | ForEach-Object { if (& $script:CardVisible $_) { '1' } else { '0' } }) -join '')
& $script:Relayout
& $script:RefreshTop

if ($script:Rebuild) {
  # le log etait OUVERT avant la reconstruction : la fleche et la place du journal sont retablies
  if ($script:PrevLogVisible) { $btnLogToggle.Text = "6" }
  $form.ResumeLayout()
  $form.Invalidate()
  & $script:LogFn "affichage reconstruit : fenetre laissee EN PLACE (pas de fermeture)"
}
