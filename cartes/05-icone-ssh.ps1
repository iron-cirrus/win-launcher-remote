# cartes\05-icone-ssh.ps1 - Icone SSH : dessin et clic (ouvre/ramene un terminal)
# Corps de la boucle 'foreach ($m in $MachinesOrd)' de ui-50-cartes.ps1 (dot-source par carte). Lignes d'origine du fichier ui-50 : 433-556.

  # ICONE SSH a gauche de l'icone VNC : ouvre un terminal SSH vers la machine
  # (meme principe que VNC : grise = machine joignable mais aucune session,
  # couleur = session ssh.exe active detectee par le watchdog).
  # Clic = signale la session existante, sinon ouvre powershell -NoExit ssh <alias>
  # (l'alias de ~/.ssh/config porte user/port/cle -> commande minimale).
  $icoSsh = New-Object System.Windows.Forms.Panel
  $icoSsh.Size = New-Object System.Drawing.Size(20, 20)
  $icoSsh.Location = New-Object System.Drawing.Point(($cardW - 80), ($cardH - 24))
  $icoSsh.BackColor = [System.Drawing.Color]::Transparent
  $icoSsh.Cursor = [System.Windows.Forms.Cursors]::Hand
  # pas d'icone SSH sur la carte LOCAL : uniquement les machines de .ssh/config
  $icoSsh.Visible = [bool]$m.Host
  $icoSsh | Add-Member -NotePropertyName SshAlias -NotePropertyValue $m.Host
  $icoSsh | Add-Member -NotePropertyName SshIp -NotePropertyValue $m.HostName
  $icoSsh | Add-Member -NotePropertyName SshConnected -NotePropertyValue $false
  if (-not $script:BmpSshOn) {
    $drawSsh = {
    param($g, $st, $s)
    # VRAIE icone du terminal (Windows Terminal / PowerShell) si disponible :
    # couleur = session ssh active ; grisee + attenuee sinon (comme l'icone VNC)
    if ($script:SshIconBmp) {
      if ($s.SshConnected) {
        $g.DrawImage($script:SshIconBmp, 0, 0, 16, 16)
      } else {
        $cm = New-Object System.Drawing.Imaging.ColorMatrix
        $cm.Matrix00 = 0.33; $cm.Matrix10 = 0.33; $cm.Matrix20 = 0.33
        $cm.Matrix01 = 0.33; $cm.Matrix11 = 0.33; $cm.Matrix21 = 0.33
        $cm.Matrix02 = 0.33; $cm.Matrix12 = 0.33; $cm.Matrix22 = 0.33
        $cm.Matrix33 = 0.45
        $ia = New-Object System.Drawing.Imaging.ImageAttributes
        $ia.SetColorMatrix($cm) | Out-Null
        $g.DrawImage($script:SshIconBmp, (New-Object System.Drawing.Rectangle(0, 0, 16, 16)), 0, 0,
          $script:SshIconBmp.Width, $script:SshIconBmp.Height, [System.Drawing.GraphicsUnit]::Pixel, $ia)
        $ia.Dispose()
      }
      return
    }
    # repli dessine (aucune icone de terminal trouvee)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    # terminal : cadre + prompt ">_" ; vert = session active, gris = aucune session
    $sc = if ($s.SshConnected) { [System.Drawing.Color]::FromArgb(235, 86, 180, 233) } else { [System.Drawing.Color]::FromArgb(120, 120, 120, 120) }
    $pen = New-Object System.Drawing.Pen($sc, 1.4)
    $g.DrawRectangle($pen, 1, 2, 13, 11)
    # ">"
    $g.DrawLines($pen, @([System.Drawing.Point]::new(3,5), [System.Drawing.Point]::new(6,7.5), [System.Drawing.Point]::new(3,10)))
    # "_"
    $g.DrawLine($pen, 8, 10, 12, 10)
    $pen.Dispose()
    }
    $script:BmpSshOn  = & $script:NewIconBmp 20 20 $drawSsh $null ([pscustomobject]@{ SshConnected = $true })  1.25
    $script:BmpSshOff = & $script:NewIconBmp 20 20 $drawSsh $null ([pscustomobject]@{ SshConnected = $false }) 1.25
  }
  $icoSsh.Add_Paint({
    param($s, $e)
    $e.Graphics.DrawImage($(if ($s.SshConnected) { $script:BmpSshOn } else { $script:BmpSshOff }), 0, 0, 20, 20)
  })
  $icoSsh.Add_Click({
    $aliasS = $this.SshAlias
    if (-not $aliasS) { return }
    $ipS = $this.SshIp
    # DEJA CONNECTE ? une session = processus ssh.exe dont la cmdline cite l'alias
    # ou l'IP. ssh.exe n'a PAS de fenetre : la console appartient a son ANCESTRE
    # (conhost / WindowsTerminal / powershell / cmd). On remonte donc la chaine
    # ParentProcessId jusqu'a trouver un ancetre dote d'une vraie fenetre.
    $sshProcs = @()
    try {
      $sshProcs = @(Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" |
        Where-Object { ($_.CommandLine -like ("*" + $aliasS + "*")) -or ($ipS -and $_.CommandLine -like ("*" + $ipS + "*")) })
    } catch { }
    if ($sshProcs.Count -gt 0) {
      $foundHwnd = [IntPtr]::Zero
      $foundTitle = ""
      foreach ($pr in $sshProcs) {
        $pidCourant = [int]$pr.ProcessId
        # 6 niveaux max : ssh <- powershell/cmd <- conhost <- WindowsTerminal ...
        for ($n = 0; $n -lt 6; $n++) {
          $gp = $null
          try { $gp = Get-Process -Id $pidCourant -ErrorAction Stop } catch { break }
          if ($gp -and $gp.MainWindowHandle -ne [IntPtr]::Zero) {
            $foundHwnd = $gp.MainWindowHandle; $foundTitle = $gp.MainWindowTitle; break
          }
          $pp = $null
          try { $pp = (Get-CimInstance Win32_Process -Filter ("ProcessId=" + $pidCourant) -ErrorAction Stop).ParentProcessId } catch { }
          if (-not $pp -or $pp -eq 0 -or [int]$pp -eq $pidCourant) { break }
          $pidCourant = [int]$pp
        }
        if ($foundHwnd -ne [IntPtr]::Zero) { break }
      }
      # Repli : fenetre dont le TITRE contient l'alias ou l'IP (Windows Terminal
      # affiche la commande en cours dans son onglet/titre)
      if ($foundHwnd -eq [IntPtr]::Zero) {
        try {
          foreach ($w in [VscWinV4]::GetAllWindows()) {
            if (($w[1] -like ("*" + $aliasS + "*")) -or ($ipS -and $w[1] -like ("*" + $ipS + "*"))) {
              $foundHwnd = [IntPtr][long]$w[0]; $foundTitle = $w[1]; break
            }
          }
        } catch { }
      }
      $this.SshConnected = $true; $this.Invalidate()
      if ($foundHwnd -ne [IntPtr]::Zero) {
        & $script:LogFn ("SSH: terminal DEJA OUVERT vers " + $aliasS + " (fenetre '" + $foundTitle + "') -> ramenee au premier plan")
        [VscWinV4]::ShowWindow($foundHwnd, 9) | Out-Null        # SW_RESTORE
        [VscWinV4]::SetForegroundWindow($foundHwnd) | Out-Null
      } else {
        & $script:LogFn ("SSH: session DEJA OUVERTE vers " + $aliasS + " (" + $sshProcs.Count + " processus ssh.exe) mais fenetre console non identifiee")
      }
      return
    }
    # Nouvelle session : Windows Terminal si disponible (nouvel onglet), sinon
    # powershell. -NoExit garde la fenetre ouverte apres la deconnexion.
    $wt = $null
    try { $wt = (Get-Command wt.exe -ErrorAction Stop).Source } catch { }
    try {
      if ($wt) {
        & $script:LogFn ("SSH: wt.exe new-tab powershell -NoExit ssh " + $aliasS)
        Start-Process $wt -ArgumentList ("new-tab powershell -NoExit ssh " + $aliasS)
      } else {
        & $script:LogFn ("SSH: powershell -NoExit ssh " + $aliasS)
        Start-Process powershell.exe -ArgumentList @("-NoExit", "ssh", $aliasS)
      }
    } catch { & $script:LogFn ("  ECHEC SSH: " + $_.Exception.Message) }
  })

