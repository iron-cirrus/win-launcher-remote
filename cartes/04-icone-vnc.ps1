# cartes\04-icone-vnc.ps1 - Icone VNC : dessin et clic (lance/ramene le client)
# Corps de la boucle 'foreach ($m in $MachinesOrd)' de ui-50-cartes.ps1 (dot-source par carte). Lignes d'origine du fichier ui-50 : 322-432.

  # ICONE VNC a gauche du logo VS Code : visible seulement si un port 5900..5904
  # est ouvert sur la machine (sonde TCP asynchrone du watchdog).
  # VRAI icone du client VNC (extraite de vncviewer.exe) si disponible, sinon dessin.
  # Teinte : COULEUR si un client VNC est OUVERT sur cette IP (process java/vncviewer
  # dont la cmdline contient ip:port), GRIS eteint sinon (serveur dispo, rien de connecte).
  # Clic = lance TurboVNC/RealVNC sur host:port (ou ramene la fenetre existante).
  $icoVnc = New-Object System.Windows.Forms.Panel
  $icoVnc.Size = New-Object System.Drawing.Size(20, 20)
  $icoVnc.Location = New-Object System.Drawing.Point(($cardW - 54), ($cardH - 24))
  # carte Windows : la place de VNC est apres mstsc (-28) et Moonlight (-54)
  if ($m.RdpIp -and -not $m.Host) { $icoVnc.Location = New-Object System.Drawing.Point(($cardW - 80), ($cardH - 24)) }
  $icoVnc.BackColor = [System.Drawing.Color]::Transparent
  $icoVnc.Cursor = [System.Windows.Forms.Cursors]::Hand
  $icoVnc.Visible = $false
  $icoVnc | Add-Member -NotePropertyName VncTarget -NotePropertyValue $null
  $icoVnc | Add-Member -NotePropertyName VncBmp -NotePropertyValue $script:VncIconBmp
  $icoVnc | Add-Member -NotePropertyName VncConnected -NotePropertyValue $false
  if (-not $script:BmpVncOn) {
    $drawVnc = {
    param($g, $conn, $s)
    if ($s.VncBmp) {
      if ($conn) {
        # client VNC ouvert -> icone en couleur
        $g.DrawImage($s.VncBmp, 0, 0, 16, 16)
      } else {
        # serveur dispo mais aucun client -> icone TRES grise eteinte (ColorMatrix
        # niveaux de gris + opacite forte reduite : bien plus discret que le logo ferme)
        $cm = New-Object System.Drawing.Imaging.ColorMatrix
        $cm.Matrix00 = 0.33; $cm.Matrix10 = 0.33; $cm.Matrix20 = 0.33
        $cm.Matrix01 = 0.33; $cm.Matrix11 = 0.33; $cm.Matrix21 = 0.33
        $cm.Matrix02 = 0.33; $cm.Matrix12 = 0.33; $cm.Matrix22 = 0.33
        $cm.Matrix33 = 0.40
        $ia = New-Object System.Drawing.Imaging.ImageAttributes
        $ia.SetColorMatrix($cm) | Out-Null
        $rect = New-Object System.Drawing.Rectangle(0, 0, 16, 16)
        $g.DrawImage($s.VncBmp, $rect, 0, 0, $s.VncBmp.Width, $s.VncBmp.Height, `
          [System.Drawing.GraphicsUnit]::Pixel, $ia)
        $ia.Dispose()
      }
      return
    }
    # repli dessine : petit ecran (bureau distant) + fleche "distance"
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    # vert = client connecte ; gris = serveur VNC dispo mais aucune session
    $vc = if ($conn) { [System.Drawing.Color]::FromArgb(230, 86, 180, 233) } else { [System.Drawing.Color]::FromArgb(110, 120, 120, 120) }
    $pen = New-Object System.Drawing.Pen($vc, 1)
    $g.DrawRectangle($pen, 1, 1, 13, 9)
    $g.DrawLine($pen, 8, 10, 8, 12)
    $g.DrawLine($pen, 5, 12, 11, 12)
    $g.DrawLine($pen, 4, 5, 11, 5)
    $g.DrawLines($pen, @([System.Drawing.Point]::new(9,3), [System.Drawing.Point]::new(11,5), [System.Drawing.Point]::new(9,7)))
    $pen.Dispose()
    }
    $script:BmpVncOn  = & $script:NewIconBmp 20 20 $drawVnc $true  $icoVnc 1.25
    $script:BmpVncOff = & $script:NewIconBmp 20 20 $drawVnc $false $icoVnc 1.25
  }
  $icoVnc.Add_Paint({
    param($s, $e)
    $e.Graphics.DrawImage($(if ($s.VncConnected) { $script:BmpVncOn } else { $script:BmpVncOff }), 0, 0, 20, 20)
  })
  $icoVnc.Add_Click({
    $t = $this.VncTarget
    if (-not $t) { return }
    $ipVnc = ($t -split ':')[0]
    # DEJA LANCE ? TurboVNC chez l'utilisateur = java.exe -jar VncViewer.jar <ip>:<port>.
    # Le TITRE de la fenetre ("TurboVNC: minecraftserver:2 (francois) [Tight...]")
    # ne contient PAS l'IP : l'IP n'est que dans la LIGNE DE COMMANDE du processus.
    # -> on cherche un processus java/vncviewer dont la cmdline contient ip:port,
    #    puis on ramene sa fenetre (MainWindowHandle fonctionne pour java.exe).
    $foundHwnd = [IntPtr]::Zero
    $foundTitle = ""
    try {
      $vncProcs = Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe' OR Name='vncviewer.exe'" |
        Where-Object { $_.CommandLine -like ("*" + $ipVnc + ":*") }
      foreach ($pr in $vncProcs) {
        $gp = Get-Process -Id $pr.ProcessId -ErrorAction SilentlyContinue
        if ($gp -and $gp.MainWindowHandle -ne 0) {
          $foundHwnd = $gp.MainWindowHandle; $foundTitle = $gp.MainWindowTitle; break
        }
      }
    } catch { }
    # Repli : une fenetre dont le TITRE contient l'IP (autres clients VNC)
    if ($foundHwnd -eq [IntPtr]::Zero) {
      try {
        $allWins = [VscWinV4]::GetAllWindows()
        foreach ($w in $allWins) {
          if ($w[1] -like ("*" + $ipVnc + "*")) {
            $foundHwnd = [IntPtr][long]$w[0]; $foundTitle = $w[1]; break
          }
        }
      } catch { }
    }
    if ($foundHwnd -ne [IntPtr]::Zero) {
      & $script:LogFn ("VNC: viewer DEJA lance sur " + $ipVnc + " (fenetre '" + $foundTitle + "') -> ramenee au premier plan")
      [VscWinV4]::ShowWindow($foundHwnd, 9) | Out-Null        # SW_RESTORE
      [VscWinV4]::SetForegroundWindow($foundHwnd) | Out-Null
      $this.VncConnected = $true; $this.Invalidate()
      return
    }
    # TurboVNC / RealVNC : "vncviewer.exe host:port" (ou -Host) ; sinon protocole vnc://
    # -WindowStyle Hidden : vncviewer.bat est un BATCH -> sans lui, une fenetre de
    # console cmd.exe "clignote" a l'ecran pendant le demarrage du viewer Java.
    if ($script:VncViewerExe) {
      & $script:LogFn ("VNC: " + $script:VncViewerExe + " " + $t)
      try { Start-Process $script:VncViewerExe -ArgumentList $t -WindowStyle Hidden } catch { & $script:LogFn ("  ECHEC VNC: " + $_.Exception.Message) }
    } else {
      & $script:LogFn ("VNC: ouverture de vnc://" + $t + " (vncviewer.exe introuvable, repli protocole)")
      try { Start-Process ("vnc://" + $t) } catch { & $script:LogFn ("  ECHEC VNC: " + $_.Exception.Message + " (aucun client VNC ?)") }
    }
  })

