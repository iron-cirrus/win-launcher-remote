# cartes\06-clics-survol.ps1 - Clic carte (ouvrir VS Code / Windows), clic droit (test SSH), survol
# Corps de la boucle 'foreach ($m in $MachinesOrd)' de ui-50-cartes.ps1 (dot-source par carte). Lignes d'origine du fichier ui-50 : 557-677.

  # clic : fenetre DEJA ouverte -> la ramener au premier plan ; sinon lancer code.
  # Fiabilite : on liste tous les Code.exe avec une fenetre visible (MainWindowHandle != 0).
  #   - remote : le process fenetre porte "ssh-remote+<alias>" (ou "ssh-remote%2B") dans sa cmdline ;
  #     a defaut on accepte n'importe quelle fenetre Code si aucune ne matche l'alias.
  #   - local  : n'importe quelle fenetre Code dont la cmdline NE contient PAS "--remote".
  # (logique INLINE : les handlers ne peuvent pas appeler de fonction du script)
  $card.Add_Click({
    if ($this.Disabled) {
      & $script:LogFn ("Carte " + $this.Tag + " inactive : machine injoignable (ping)")
      return
    }
    # machine Windows du LAN (scan RDP) : Moonlight si Apollo dispo, sinon RDP
    if ($this.RdpIp) {
      & $script:OpenWindowsHost $this.RdpIp
      return
    }
    if (-not $script:CodeExe) {
      & $script:LogFn "ERREUR: commande 'code' introuvable dans le PATH"
      return
    }
    $alias = $this.Tag
    if ($alias) { & $script:LogFn ("Clic carte " + $alias + " -> recherche d'une fenetre VS Code deja ouverte...") }
    else { & $script:LogFn "Clic carte LOCAL" }
    # Enumere TOUTES les fenetres VS Code (Electron = 1 process, N fenetres)
    # et rattache chaque titre au remote exact "[SSH: <alias>]".
    $wins = [VscWinV4]::GetCodeWindows()
    $foundHwnd = [IntPtr]::Zero
    foreach ($w in $wins) {
      $id = $null
      if ($w[1] -match '\[SSH:\s*([^\]]+)\]') { $id = $Matches[1].Trim() }
      if ($alias) {
        if ($id -and ($id -ieq $alias)) { $foundHwnd = [IntPtr][long]$w[0]; break }
      } else {
        if (-not $id) { $foundHwnd = [IntPtr][long]$w[0]; break }   # LOCAL : sans remote
      }
    }
    if ($foundHwnd -ne [IntPtr]::Zero) {
      & $script:LogFn ("Fenetre deja ouverte (hwnd " + $foundHwnd + ") -> ramenee au premier plan")
      [VscWinV4]::ShowWindow($foundHwnd, 9) | Out-Null        # SW_RESTORE
      [VscWinV4]::SetForegroundWindow($foundHwnd) | Out-Null
    } elseif ($alias) {
      $args2 = @("--remote", ("ssh-remote+" + $alias))
      if ($script:FolderMap.ContainsKey($alias)) { $args2 += $script:FolderMap[$alias] }
      & $script:LogFn ("Aucune fenetre -> " + $script:CodeExe + " " + ($args2 -join ' '))
      Start-Process $script:CodeExe -ArgumentList $args2
    } else {
      & $script:LogFn ("Aucune fenetre locale -> " + $script:CodeExe)
      Start-Process $script:CodeExe
    }
  })

  # clic DROIT sur la carte = test SSH en log (diagnostic "acces a la machine echoue")
  $card.Add_MouseClick({
    param($s, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Right) { return }
    $alias = $s.Tag
    if (-not $alias) { & $script:LogFn "Test SSH non applicable pour LOCAL"; return }
    & $script:LogFn ("Test SSH: ssh -o ConnectTimeout=6 -o BatchMode=yes " + $alias + " hostname")
    try {
      # RunTimeout (et non & ssh) : un ssh qui pend bloquerait l'IHM sans fin
      $rt = & $script:RunTimeout "ssh" @("-o", "ConnectTimeout=6", "-o", "BatchMode=yes", "-o", "NumberOfPasswordPrompts=0", "-o", "StrictHostKeyChecking=accept-new", $alias, "hostname") 12
      if ($rt.Exit -eq 0) { & $script:LogFn ("  OK (exit 0) -> " + $rt.Output) }
      else { & $script:LogFn ("  ECHEC (exit " + $rt.Exit + ") -> " + $rt.Output) }
    } catch {
      & $script:LogFn ("  EXCEPTION: " + $_.Exception.Message)
    }
  })

  foreach ($lbl in @($lblLabel, $lblUser, $icoUser, $lblRole, $dot, $logoVsc)) {
    $lbl.Add_Click({
      if ($this.Parent.Disabled) {
        & $script:LogFn ("Carte " + $this.Parent.Tag + " inactive : machine injoignable (ping)")
        return
      }
      if ($this.Parent.RdpIp) {
        & $script:OpenWindowsHost $this.Parent.RdpIp
        return
      }
      if (-not $script:CodeExe) {
        & $script:LogFn "ERREUR: commande 'code' introuvable dans le PATH"
        return
      }
      $alias = $this.Parent.Tag
      if ($alias) { & $script:LogFn ("Clic carte " + $alias + " -> recherche d'une fenetre VS Code deja ouverte...") }
      else { & $script:LogFn "Clic carte LOCAL" }
      # Enumere TOUTES les fenetres VS Code (cf. handler de la carte)
      $wins = [VscWinV4]::GetCodeWindows()
      $foundHwnd = [IntPtr]::Zero
      foreach ($w in $wins) {
        $id = $null
        if ($w[1] -match '\[SSH:\s*([^\]]+)\]') { $id = $Matches[1].Trim() }
        if ($alias) {
          if ($id -and ($id -ieq $alias)) { $foundHwnd = [IntPtr][long]$w[0]; break }
        } else {
          if (-not $id) { $foundHwnd = [IntPtr][long]$w[0]; break }
        }
      }
      if ($foundHwnd -ne [IntPtr]::Zero) {
        & $script:LogFn ("Fenetre deja ouverte (hwnd " + $foundHwnd + ") -> ramenee au premier plan")
        [VscWinV4]::ShowWindow($foundHwnd, 9) | Out-Null        # SW_RESTORE
        [VscWinV4]::SetForegroundWindow($foundHwnd) | Out-Null
      } elseif ($alias) {
        $args2 = @("--remote", ("ssh-remote+" + $alias))
        if ($script:FolderMap.ContainsKey($alias)) { $args2 += $script:FolderMap[$alias] }
        & $script:LogFn ("Aucune fenetre -> " + $script:CodeExe + " " + ($args2 -join ' '))
        Start-Process $script:CodeExe -ArgumentList $args2
      } else {
        & $script:LogFn ("Aucune fenetre locale -> " + $script:CodeExe)
        Start-Process $script:CodeExe
      }
    })
  }

  # survol : teinte foncee (sauf carte inactive)
  $card.Add_MouseEnter({ if (-not $this.Disabled) { $this.BackColor = $this.DarkColor } })
  $card.Add_MouseLeave({ if (-not $this.Disabled) { $this.BackColor = $this.NormalColor } })
  foreach ($lbl in @($lblLabel, $lblUser, $icoUser, $lblRole, $dot, $logoVsc, $icoVnc)) {
    $lbl.Add_MouseEnter({ if (-not $this.Parent.Disabled) { $this.Parent.BackColor = $this.Parent.DarkColor } })
    $lbl.Add_MouseLeave({ if (-not $this.Parent.Disabled) { $this.Parent.BackColor = $this.Parent.NormalColor } })
  }

