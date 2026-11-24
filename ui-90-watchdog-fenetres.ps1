# ui-90-watchdog-fenetres.ps1 - BuildUI : watchdog A, fenetres VS Code ouvertes (5 s)
# Fichier charge par vsc_launcher.ps1 (dot-source : meme portee script). Lignes d'origine 4760-5024.

# ---------- Watchdog A : fenetres VS Code ouvertes (5 s) ----------
# VS Code (Electron) heberge souvent PLUSIEURS fenetres dans UN SEUL processus :
# Get-Process.MainWindowHandle ne voit alors que la fenetre au premier plan.
# On enumere donc TOUTES les fenetres de haut niveau visibles via EnumWindows
# (VscWinV4::GetCodeWindows) et on rattache chaque titre a un remote :
#   - titre contenant "[SSH: <alias>]"  -> remote <alias> (egalite EXACTE)
#   - titre "Visual Studio Code" sans [SSH: ...] -> fenetre locale
$script:OpenCheckTick = {
  # --- ECRANS : si la disposition change (ecran branche/debranche/deplace), on rescanne
  # et on redessine les mini-cartes ---
  try {
    $scrNew = & $script:GetScreens
    $sigNew = (@($scrNew | ForEach-Object { "" + $_.Idx + ":" + $_.X + "," + $_.Y + "," + $_.W + "x" + $_.H + "/" + $_.PW + "x" + $_.PH }) -join ';')
    if ($sigNew -ne $script:ScreensSig) {
      $script:Screens = $scrNew; $script:ScreensSig = $sigNew
      & $script:LogFn ("ecrans: disposition modifiee -> " + $sigNew)
      foreach ($c in $script:CardList) { if ($c.Map) { $c.Map.Invalidate() } }
      & $script:UpdateHome                        # ecran spacedesk branche/debranche : plein ecran / fenetre
      & $script:Relayout                          # (la carte des ecrans du haut change de proportions)
      & $script:RefreshTop
    }
  } catch { }
  # --- GARDE : fenetres Moonlight remises a la place prevue (apres un changement d'ecrans) ---
  try { & $script:GuardWindows } catch { & $script:LogFn ("garde des fenetres : " + $_.Exception.Message) }
  if ($script:RefreshTop) { & $script:RefreshTop }                  # panneau du haut + etiquettes de session

  # --- MSTSC : detecte aussi les mstsc deja ouverts (lances a la main, ou par une ancienne
  # instance du launcher) : ligne de commande contenant l'IP ou son fichier .rdp. Tous les 3 ticks. ---
  $script:RdpScanN = 1 + [int]$script:RdpScanN
  if (($script:RdpScanN % 3) -eq 1) { & $script:ScanRemoteClients ($script:RdpScanN -eq 1) }
  # --- MSTSC : une session RDP lancee par le launcher est suivie jusqu'a la fermeture de son
  # processus mstsc ; les ecrans qu'elle occupe sont marques sur la mini-carte ---
  foreach ($k in @($script:RdpState.Keys)) {
    $st = $script:RdpState[$k]
    $gone = $false
    try { if ($st.Proc -and $st.Proc.HasExited) { $gone = $true } } catch { $gone = $true }
    if ($gone) {
      $script:RdpState.Remove($k)
      & $script:LogFn ("Etat mstsc " + $k + " : deconnecte (ecrans " + ($st.Idxs -join '+') + ")")
      if ($script:RefreshTop) { & $script:RefreshTop }
    }
  }

  # --- APOLLO : la mini-carte des ecrans n'apparait que sur une machine Windows
  # JOIGNABLE dont le port 47989 repond ET appairee dans Moonlight (client installe).
  # Sonde TCP asynchrone, une a la fois par carte, relancee a chaque tick (5 s). ---
  foreach ($c in $script:CardList) {
    if (-not $c.Map) { continue }
    if ($c.ApAr -ne $null) {
      if ($c.ApAr.IsCompleted) {
        $opened = $false
        try { $c.ApTcp.EndConnect($c.ApAr); $opened = $true } catch { }
        try { $c.ApTcp.Close() } catch { }
        $c.ApAr = $null; $c.ApTcp = $null; $c.ApOpen = $opened
      } elseif (((Get-Date) - $c.ApT0).TotalSeconds -gt 6) {
        try { $c.ApTcp.Close() } catch { }                    # port filtre : abandon apres 6 s
        $c.ApAr = $null; $c.ApTcp = $null; $c.ApOpen = $false
      }
    }
    # mini-carte des ecrans + bouton mstsc : des que la machine repond au ping ;
    # bouton Moonlight : seulement si Apollo repond ET que la machine est appairee
    # ANTI-CLIGNOTEMENT : un poste sans Apollo repond parfois mal au ping (ICMP filtre/perdu) ;
    # on ne masque la mini-carte (et donc l'etat des ecrans) qu'apres 30 s sans AUCUN ping reussi,
    # et jamais tant qu'un client distant (mstsc / Moonlight) est actif sur la machine.
    if ($c.LastOk -eq $true) { $c.MapOkAt = Get-Date }
    $inUse = ($script:RdpState.ContainsKey($c.PingHost)) -or ($script:MlState.ContainsKey($c.PingHost) -and ($script:MlState[$c.PingHost].State -eq 'live' -or $script:MlState[$c.PingHost].State -eq 'connecting'))
    # (la mini-carte par carte n'existe plus : le choix des ecrans se fait dans le panneau du HAUT ;
    #  ici seul le bouton mstsc suit la joignabilite)
    $reach = ($c.LastOk -eq $true) -or $inUse -or ($c.RdpBtn -and $c.RdpBtn.Visible -and $c.MapOkAt -and (((Get-Date) - $c.MapOkAt).TotalSeconds -lt 30))
    if ($c.RdpBtn -and $c.RdpBtn.Visible -ne $reach) {
      $c.RdpBtn.Visible = $reach
      & $script:LogFn ("ecrans: " + $c.PingHost + $(if ($reach) { " joignable -> bouton mstsc affiche" } else { " injoignable -> boutons masques" }))
    }
    $show = $false
    if ($reach -and $script:MoonlightExe -and $c.ApOpen) {
      $show = [bool](& $script:GetMoonlightHost $c.PingHost).Paired
    }
    if ($c.Ml -and $c.Ml.Visible -ne $show) {
      $c.Ml.Visible = $show
      & $script:LogFn ("Moonlight: " + $c.PingHost + $(if ($show) { " Apollo + appaire -> bouton Moonlight affiche" } else { " plus d'Apollo/appairage -> bouton Moonlight masque" }))
    }
    if ($c.ApAr -eq $null -and $c.LastOk -eq $true -and $script:MoonlightExe) {
      try {
        $c.ApTcp = New-Object System.Net.Sockets.TcpClient
        $c.ApT0 = Get-Date
        $c.ApAr = $c.ApTcp.BeginConnect($c.PingHost, 47989, $null, $null)
      } catch { $c.ApAr = $null; $c.ApTcp = $null }
    }
  }

  # --- SUNSHINE : sonde des ports des machines LINUX joignables (toutes les 30 s, asynchrone) ---
  foreach ($c in $script:CardList) {
    if (-not $c.IsLinux) { continue }
    if ($c.SunAr) {
      $allDone = $true
      foreach ($pr in $c.SunAr) { if (-not $pr.Ar.IsCompleted) { $allDone = $false } }
      if ($allDone -or (((Get-Date) - $c.SunT0).TotalSeconds -gt 6)) {
        $openS = @{}; $ipSeen = $null
        foreach ($pr in $c.SunAr) {
          $o = $false
          if ($pr.Ar.IsCompleted) {
            try {
              $pr.Tcp.EndConnect($pr.Ar); $o = $true
              if (-not $ipSeen) { $ipSeen = ([System.Net.IPEndPoint]$pr.Tcp.Client.RemoteEndPoint).Address.ToString() }
            } catch { }
          }
          try { $pr.Tcp.Close() } catch { }
          $openS[[int]$pr.Port] = $o
        }
        $c.SunAr = $null
        & $script:SunshineApply $c $openS $ipSeen
      }
    }
    if (-not $c.SunAr -and $c.LastOk -eq $true -and (((Get-Date) - $c.SunLast).TotalSeconds -ge 30)) {
      $c.SunLast = Get-Date; $c.SunT0 = Get-Date
      $arr = @()
      foreach ($port in $script:SunshinePorts) {
        try { $tS = New-Object System.Net.Sockets.TcpClient; $arr += [pscustomobject]@{ Port = $port; Tcp = $tS; Ar = $tS.BeginConnect($c.PingHost, $port, $null, $null) } } catch { }
      }
      $c.SunAr = $arr
    }
  }

  # --- SONDE VNC : un port par tick et par carte (5900 -> 5904), asynchrone ---
  foreach ($c in $script:CardList) {
    # sonde NEGATIVE rejouee toutes les 60 s (machine joignable) : un serveur VNC demarre apres le
    # launcher, ou une machine injoignable au demarrage, doit quand meme faire apparaitre l'icone
    if ($c.VncDone -and -not $c.VncFound -and $c.LastOk -eq $true -and $c.VncDoneAt -and (((Get-Date) - $c.VncDoneAt).TotalSeconds -ge 60)) {
      $c.VncDone = $false; $c.VncPort = 5900
    }
    if ($c.VncDone -or -not $c.PingHost) { continue }

    # 1) resultat de la sonde precedente ?
    if ($c.VncAr -ne $null) {
      $opened = $false
      try {
        if ($c.VncAr.AsyncWaitHandle.WaitOne(0)) {
          $c.VncTcp.EndConnect($c.VncAr)
          $opened = $true
        }
      } catch { $opened = $false }
      try { $c.VncTcp.Close() } catch {}
      $c.VncAr = $null; $c.VncTcp = $null
      if ($opened) {
        $c.VncFound = $true
        $c.VncDone = $true
        $c.Vnc.VncTarget = ($c.PingHost + ":" + $c.VncPort)
        $c.Vnc.Visible = $true
        & $script:LogFn ("VNC: port " + $c.VncPort + " OUVERT sur " + $c.PingHost + " -> icone VNC affichee")
        continue
      }
      $c.VncPort = $c.VncPort + 1
    }

    # 2) sinon, lance la sonde du port courant
    if ($c.VncPort -gt 5904) {
      $c.VncDone = $true
      $c.VncDoneAt = Get-Date
      if (-not $c.VncLogged) { $c.VncLogged = $true; & $script:LogFn ("VNC: aucun port 5900-5904 ouvert sur " + $c.PingHost + " (nouvel essai toutes les 60 s)") }
      continue
    }
    try {
      $c.VncTcp = New-Object System.Net.Sockets.TcpClient
      $c.VncAr = $c.VncTcp.BeginConnect($c.PingHost, $c.VncPort, $null, $null)
    } catch {
      $c.VncAr = $null; $c.VncTcp = $null
      $c.VncPort = $c.VncPort + 1
    }
  }

  # --- LIGNES DE COMMANDE ssh/java/vncviewer, avec CACHE ---
  # PERF : Get-CimInstance Win32_Process coute ~200-650 ms ; il etait appele
  # DEUX fois toutes les 5 s sur le fil de l'IHM. Desormais : Get-Process (~5 ms)
  # donne la liste des PID concernes ; la requete WMI (UNE seule, tous les noms)
  # n'est refaite que si cette liste a change depuis le tick precedent.
  $procSig = ""
  try {
    $procSig = (@(Get-Process -Name ssh, java, javaw, vncviewer -ErrorAction SilentlyContinue |
      ForEach-Object { $_.Id } | Sort-Object) -join ',')
  } catch { $procSig = "?" }
  if ($null -eq $script:ProcSig -or $procSig -ne $script:ProcSig) {
    $script:ProcSshCmds = @()
    $script:ProcVncCmds = @()
    if ($procSig) {
      try {
        foreach ($pr in @(Get-CimInstance Win32_Process -Filter "Name='ssh.exe' OR Name='java.exe' OR Name='javaw.exe' OR Name='vncviewer.exe'")) {
          if (-not $pr.CommandLine) { continue }
          if ($pr.Name -ieq 'ssh.exe') { $script:ProcSshCmds += $pr.CommandLine }
          else { $script:ProcVncCmds += $pr.CommandLine }
        }
      } catch { $procSig = $null }   # echec WMI : on retentera au prochain tick
    }
    $script:ProcSig = $procSig
  }

  # --- 3) etat "client VNC connecte" par carte : un processus java/vncviewer
  # dont la ligne de commande contient ip:port = session ouverte -> icone couleur,
  # sinon icone grisee (serveur joignable en VNC mais aucune session lancee). ---
  $cardsVnc = @($script:CardList | Where-Object { $_.VncFound })
  if ($cardsVnc.Count -gt 0) {
    $conns = @($script:ProcVncCmds)
    foreach ($c in $cardsVnc) {
      $ipC = $c.PingHost
      $on = $false
      foreach ($cl in $conns) {
        if ($cl -like ("*" + $ipC + ":*")) { $on = $true; break }
      }
      if ($c.Vnc.VncConnected -ne $on) {
        $c.Vnc.VncConnected = $on
        $c.Vnc.Invalidate()
        & $script:LogFn ("VNC: client " + $(if ($on) { "OUVERT" } else { "FERME" }) + " sur " + $ipC + " -> icone " + $(if ($on) { "couleur" } else { "grisee" }))
      }
    }
  }

  # --- 4) etat "session SSH active" par carte : un processus ssh.exe dont la
  # ligne de commande cite l'alias ou l'IP = terminal connecte -> icone verte. ---
  $sshCmds = @($script:ProcSshCmds)
  foreach ($c in $script:CardList) {
    if (-not $c.Ssh) { continue }
    $on = $false
    foreach ($cl in $sshCmds) {
      if (($cl -like ("*" + $c.Alias + "*")) -or ($c.PingHost -and $cl -like ("*" + $c.PingHost + "*"))) { $on = $true; break }
    }
    if ($c.Ssh.SshConnected -ne $on) {
      $c.Ssh.SshConnected = $on
      $c.Ssh.Invalidate()
      & $script:LogFn ("SSH: session " + $(if ($on) { "OUVERTE" } else { "FERMEE" }) + " vers " + $c.Alias + " -> icone " + $(if ($on) { "verte" } else { "grisee" }))
    }
  }

  # [handle, titre] pour chaque fenetre VS Code visible
  $wins = [VscWinV4]::GetCodeWindows()

  $winRemote = @{}
  foreach ($w in $wins) {
    $id = $null
    if ($w[1] -match '\[SSH:\s*([^\]]+)\]') { $id = $Matches[1].Trim() }
    $winRemote[$w[0]] = $id
  }

  # une fenetre n'appartient qu'A UNE carte : egalite exacte alias <-> identifiant
  foreach ($c in $script:CardList) {
    if ($c.NoVscWatch) { continue }   # poste RDP sans alias SSH : pas de VS Code
    $open = $false
    foreach ($k in $winRemote.Keys) {
      $id = $winRemote[$k]
      if ($id -and ($id -ieq $c.Alias)) { $open = $true; break }
    }
    if ($c.LastOpen -ne $open) {
      # bascule la teinte du logo VS Code : bleu (ouvert) / gris (ferme)
      $c.Logo.OpenState = $open
      $c.Logo.Invalidate()
      & $script:LogFn ("vscode: " + $c.Alias + " -> " + $(if ($open) { "fenetre OUVERTE" } else { "fenetre FERMEE" }))
      $c.LastOpen = $open
    }
  }

  # --- carte LOCAL : carre "ouvert" si une fenetre Code SANS remote existe ---
  $openLocal = $false
  foreach ($k in $winRemote.Keys) {
    if (-not $winRemote[$k]) { $openLocal = $true; break }
  }
  if ($script:LastOpenLocal -ne $openLocal) {
    $script:LogoLocal.OpenState = $openLocal
    $script:LogoLocal.Invalidate()
    & $script:LogFn ("vscode: LOCAL -> " + $(if ($openLocal) { "fenetre OUVERTE" } else { "fenetre FERMEE" }))
    $script:LastOpenLocal = $openLocal
  }
}

