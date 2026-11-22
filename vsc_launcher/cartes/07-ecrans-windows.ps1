# cartes\07-ecrans-windows.ps1 - Mini-carte des ecrans + boutons mstsc/Moonlight (machines Windows du LAN)
# Corps de la boucle 'foreach ($m in $MachinesOrd)' de ui-50-cartes.ps1 (dot-source par carte). Lignes d'origine du fichier ui-50 : 678-923.

  # MINI-CARTE DES ECRANS de ce poste (machines Windows) : chaque ecran est dessine a
  # l'echelle et a sa place reelle (gauche/droite/dessous...), avec son numero Windows.
  # Elle SERT A CHOISIR les ecrans (clic = un ecran, glisser = plusieurs ecrans contigus,
  # Ctrl+clic = ajouter/retirer) et ne lance RIEN : on ouvre ensuite avec les icones en bas a
  # droite de la carte (Moonlight, mstsc). Visible des que la machine repond au ping.
  $icoMap = $null; $icoMl = $null; $icoRdp = $null
  if ($m.RdpIp -and -not $m.Host) {
    $icoMap = New-Object System.Windows.Forms.Panel
    $icoMap.Size = New-Object System.Drawing.Size(($cardW - 62 - 58), 52)   # laisse la colonne d'icones a droite
    $icoMap.Location = New-Object System.Drawing.Point(62, 48)
    $icoMap.BackColor = [System.Drawing.Color]::Transparent
    $icoMap.Cursor = [System.Windows.Forms.Cursors]::Hand
    $icoMap.Visible = $false
    $icoMap | Add-Member -NotePropertyName RdpIp -NotePropertyValue $m.RdpIp
    $icoMap | Add-Member -NotePropertyName HoverIdx -NotePropertyValue 0
    # glisser pour selectionner : point de depart/courant, apercu de la selection, a-t-on bouge ?
    $icoMap | Add-Member -NotePropertyName Dragging -NotePropertyValue $false
    $icoMap | Add-Member -NotePropertyName DragMoved -NotePropertyValue $false
    $icoMap | Add-Member -NotePropertyName DragStart -NotePropertyValue $null
    $icoMap | Add-Member -NotePropertyName DragNow -NotePropertyValue $null
    $icoMap | Add-Member -NotePropertyName DragSet -NotePropertyValue @()
    try {
      [System.Windows.Forms.Control].GetProperty('DoubleBuffered',
        [System.Reflection.BindingFlags]'NonPublic,Instance').SetValue($icoMap, $true, $null)
    } catch { }
    $icoMap.Add_Paint({
      param($s, $e)
      $g = $e.Graphics
      # ecrans en bleu : l'APERCU pendant le glisser, sinon la selection memorisee (1 ou plusieurs)
      $selIdx = @()
      if ($s.Dragging) { $selIdx = @($s.DragSet) }
      else { $selObj = & $script:ResolveSelection $s.RdpIp @(); if ($selObj) { $selIdx = @($selObj.Idxs) } }
      # ETAT MOONLIGHT : ecrans OCCUPES (en connexion / operationnel) = bleu + icone Moonlight ;
      # ecrans de la derniere session DECONNECTEE (ferme / flux perdu) = gris
      $occIdx = @(); $grayIdx = @()
      $mlS = $script:MlState[$s.RdpIp]
      if ($mlS) { if ($mlS.State -eq 'live' -or $mlS.State -eq 'connecting') { $occIdx = @($mlS.Idxs) } else { $grayIdx = @($mlS.Idxs) } }
      $rdpS = $script:RdpState[$s.RdpIp]
      $rdpIdx = $(if ($rdpS) { @($rdpS.Idxs) } else { @() })
      $sessionActive = ($occIdx.Count -gt 0)
      $outlineIdx = $(if ($sessionActive) { $occIdx } else { $selIdx })
      $penBlue = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 96, 165, 250), 2)
      $grayTxtBr = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 200, 200, 200))
      $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $font = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
      $sf = New-Object System.Drawing.StringFormat
      $sf.Alignment = [System.Drawing.StringAlignment]::Center; $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
      $txtBr = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
      $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(150, 255, 255, 255), 1)
      $layout = & $script:MapLayout $s.Width $s.Height
      foreach ($r in $layout) {
        $isSel = $selIdx -contains $r.Idx; $isOcc = $occIdx -contains $r.Idx; $isGray = $grayIdx -contains $r.Idx
        # apercu du glisser = bleu clair ; occupe par Moonlight = bleu plein ; deconnecte = GRIS ;
        # choisi (sans session) = bleu plein ; survole = blanc translucide ; autre = sombre
        $isRdp = $rdpIdx -contains $r.Idx
        $fill = if ($s.Dragging -and $isSel) { [System.Drawing.Color]::FromArgb(210, 96, 165, 250) }
                elseif ($isRdp -and -not $isOcc) { [System.Drawing.Color]::FromArgb(235, 190, 85, 0) }     # orange fonce (mstsc), distinct du bleu (Moonlight / choix)
                elseif ($isOcc) { [System.Drawing.Color]::FromArgb(235, 37, 99, 235) }
                elseif ($isGray) { [System.Drawing.Color]::FromArgb(215, 112, 112, 112) }
                elseif ($isSel -and -not $sessionActive) { [System.Drawing.Color]::FromArgb(235, 37, 99, 235) }
                elseif ($r.Idx -eq $s.HoverIdx -and -not $s.Dragging) { [System.Drawing.Color]::FromArgb(110, 255, 255, 255) }
                else { [System.Drawing.Color]::FromArgb(110, 0, 0, 0) }
        $br = New-Object System.Drawing.SolidBrush($fill)
        $rc = New-Object System.Drawing.RectangleF($r.X, $r.Y, $r.Wd, $r.Ht)
        $g.FillRectangle($br, $rc)
        $g.DrawRectangle($pen, $rc.X, $rc.Y, $rc.Width, $rc.Height)
        # ecran choisi mais NON occupe (session active ailleurs) ou gris : cadre bleu = "cible du prochain lancement"
        if ($isSel -and -not $s.Dragging -and ($isGray -or ($sessionActive -and -not $isOcc))) {
          $g.DrawRectangle($penBlue, $rc.X + 1, $rc.Y + 1, $rc.Width - 2, $rc.Height - 2)
        }
        # (plus de numero d'ecran : le numero reste dans l'info-bulle au survol)
        # LOGOS des clients distants CENTRES dans l'ecran : Moonlight (attenue tant que le flux
        # n'est pas affiche) et/ou mstsc ; cote a cote si les deux occupent le meme ecran
        $logos = @()
        if ($isOcc -and $script:MlIcon) { $logos += $(if ($mlS.State -eq 'live') { $script:MlIcon } else { $script:MlIconDim }) }
        if ($isRdp -and $script:RdpIcon20) { $logos += $script:RdpIcon20 }
        if ($logos.Count -gt 0) {
          $isz = [single][Math]::Min(16, [Math]::Min([Math]::Floor($rc.Height * 0.7) + 2, $rc.Height - 2))
          $gap = [single]2
          $totW = $logos.Count * $isz + ($logos.Count - 1) * $gap
          $lx = [single]($rc.X + ($rc.Width - $totW) / 2); $ly = [single]($rc.Y + ($rc.Height - $isz) / 2)
          foreach ($lg in $logos) { $g.DrawImage($lg, $lx, $ly, $isz, $isz); $lx += $isz + $gap }
        }
        if ($r.Primary) {   # barre des taches : marque l'ecran principal
          $g.FillRectangle($txtBr, [single]($rc.X + $rc.Width * 0.3), [single]($rc.Bottom - 3), [single]($rc.Width * 0.4), [single]2)
        }
        $br.Dispose()
      }
      # plusieurs ecrans : contour de l'ENSEMBLE = zone que couvrira la fenetre de Moonlight
      $selRects = @($layout | Where-Object { $outlineIdx -contains $_.Idx })
      if ($selRects.Count -gt 1) {
        $ax = ($selRects | ForEach-Object { $_.X } | Measure-Object -Minimum).Minimum
        $ay = ($selRects | ForEach-Object { $_.Y } | Measure-Object -Minimum).Minimum
        $bx = ($selRects | ForEach-Object { $_.X + $_.Wd } | Measure-Object -Maximum).Maximum
        $by = ($selRects | ForEach-Object { $_.Y + $_.Ht } | Measure-Object -Maximum).Maximum
        $penSel = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 191, 219, 254), 2)
        $g.DrawRectangle($penSel, [single]($ax - 1), [single]($ay - 1), [single]($bx - $ax + 2), [single]($by - $ay + 2))
        $penSel.Dispose()
      }
      # rectangle de selection en pointilles pendant le glisser
      if ($s.Dragging -and $s.DragMoved -and $s.DragStart -and $s.DragNow) {
        $penBand = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 1)
        $penBand.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
        $bx1 = [Math]::Min($s.DragStart.X, $s.DragNow.X); $by1 = [Math]::Min($s.DragStart.Y, $s.DragNow.Y)
        $g.DrawRectangle($penBand, $bx1, $by1, [Math]::Abs($s.DragStart.X - $s.DragNow.X), [Math]::Abs($s.DragStart.Y - $s.DragNow.Y))
        $penBand.Dispose()
      }
      $font.Dispose(); $sf.Dispose(); $txtBr.Dispose(); $pen.Dispose(); $penBlue.Dispose(); $grayTxtBr.Dispose()
    })
    # GLISSER pour choisir plusieurs ecrans contigus : appui = point de depart, mouvement =
    # apercu des ecrans touches par le rectangle, relachement = ouverture de Moonlight sur
    # l'ensemble (fenetre calee sur tous les ecrans, voir PlaceOnScreen). Un simple clic
    # (moins de 4 px de deplacement) = un seul ecran. Ctrl+clic / Ctrl+glisser : ajoute ou
    # retire des ecrans a la selection memorisee SANS ouvrir (puis clic sur la carte).
    $icoMap.Add_MouseDown({
      param($s, $e)
      if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
      $s.Dragging = $true; $s.DragMoved = $false
      $s.DragStart = New-Object System.Drawing.Point($e.X, $e.Y); $s.DragNow = $s.DragStart
      $h0 = & $script:MapHit $s $e.X $e.Y
      $s.DragSet = $(if ($h0 -gt 0) { @($h0) } else { @() })
      $s.Invalidate()
    })
    $icoMap.Add_MouseMove({
      param($s, $e)
      if ($s.Dragging) {
        $s.DragNow = New-Object System.Drawing.Point($e.X, $e.Y)
        if ([Math]::Max([Math]::Abs($e.X - $s.DragStart.X), [Math]::Abs($e.Y - $s.DragStart.Y)) -ge 4) { $s.DragMoved = $true }
        if ($s.DragMoved) {
          # (pas de @(...) autour de l'appel : la fonction renvoie deja un tableau, @() l'imbriquerait)
          $inRect = & $script:MapScreensInRect $s $s.DragStart.X $s.DragStart.Y $e.X $e.Y
          $s.DragSet = $(if ($null -eq $inRect) { @() } else { @($inRect) })
        }
        $s.Invalidate()
        return
      }
      $h = & $script:MapHit $s $e.X $e.Y
      if ($h -ne $s.HoverIdx) {
        $s.HoverIdx = $h
        $s.Invalidate()
        $tipTxt = ""
        if ($h -gt 0) {
          $sc = @($script:Screens | Where-Object { $_.Idx -eq $h }) | Select-Object -First 1
          if ($sc) { $tipTxt = "Écran " + $sc.Idx + " : " + $sc.W + "x" + $sc.H + $(if ($sc.Primary) { " (principal)" }) + "`nClic : sélectionner cet écran`nGlisser : plusieurs écrans contigus`nCtrl+clic : ajouter/retirer`nPuis ouvrir avec l'icône Moonlight ou mstsc (en bas à droite)" }
        }
        # profil Moonlight correspondant a la selection courante (resolution / fps / debit)
        if ($h -gt 0 -and $script:MoonlightAutoProfile) {
          $selNow = & $script:ResolveSelection $s.RdpIp @()
          $pfl = $(if ($selNow) { & $script:BuildMoonlightProfile $selNow })
          if ($pfl) { $tipTxt += "`nProfil Moonlight (écrans " + ($selNow.Idxs -join '+') + ") : " + $pfl.Text }
        }
        # etat Moonlight de cet ecran (occupe ou derniere session), en tete de l'info-bulle
        $mls = $script:MlState[$s.RdpIp]
        if ($h -gt 0 -and $mls -and ($mls.Idxs -contains $h)) {
          $tipTxt = "Moonlight " + $script:MlStateLabels[$mls.State] + " depuis " + $mls.Since.ToString('HH:mm:ss') + $(if ($null -ne $mls.Code) { " (code " + $mls.Code + ")" }) + "`n" + $tipTxt
        }
        $rdpT = $script:RdpState[$s.RdpIp]
        if ($h -gt 0 -and $rdpT -and ($rdpT.Idxs -contains $h)) {
          $tipTxt = "mstsc (Bureau à distance) ouvert depuis " + $rdpT.Since.ToString('HH:mm:ss') + " sur les écrans " + ($rdpT.Idxs -join '+') + "`n" + $tipTxt
        }
        $script:Tip.SetToolTip($s, $tipTxt)
      }
    })
    $icoMap.Add_MouseUp({
      param($s, $e)
      if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left -or -not $s.Dragging) { return }
      $moved = $s.DragMoved
      $set = @($s.DragSet)
      $s.Dragging = $false; $s.DragMoved = $false; $s.DragStart = $null; $s.DragNow = $null; $s.DragSet = @()
      $s.Invalidate()
      if ($set.Count -eq 0) { return }
      if ($s.Parent.Disabled) { & $script:LogFn ("Carte " + $s.RdpIp + " inactive : machine injoignable (ping)"); return }
      if (([System.Windows.Forms.Control]::ModifierKeys -band [System.Windows.Forms.Keys]::Control) -ne 0) {
        # Ctrl : modifie la selection memorisee sans ouvrir (clic = bascule, glisser = ajoute)
        $cur = & $script:ResolveSelection $s.RdpIp @()
        $cmb = & $script:CtrlCombine $(if ($cur) { @($cur.Idxs) } else { @() }) $set $moved
        $new = $(if ($null -eq $cmb) { @() } else { @($cmb) })
        if ($new.Count -eq 0) { return }
        if (& $script:SetSelection $s.RdpIp $new) {
          & $script:LogFn ("ecrans selectionnes pour " + $s.RdpIp + " : " + ($new -join '+') + " (ouvrir avec l'icone Moonlight ou mstsc)")
        }
        $s.Invalidate()
        return
      }
      # sans Ctrl : le clic / le glisser REMPLACE la selection ; rien n'est lance
      if (& $script:SetSelection $s.RdpIp $set) {
        & $script:LogFn ("ecrans selectionnes pour " + $s.RdpIp + " : " + ($set -join '+') + " (ouvrir avec l'icone Moonlight ou mstsc)")
      }
      $s.Invalidate()
    })
    $icoMap.Add_MouseLeave({ param($s, $e) if (-not $s.Dragging -and $s.HoverIdx -ne 0) { $s.HoverIdx = 0; $s.Invalidate() } })

    # BOUTONS en bas a droite de la carte, en colonne : Moonlight au-dessus, mstsc en dessous.
    # Ils ouvrent la machine sur les ecrans SELECTIONNES dans la mini-carte (memorises par machine).
    # mstsc : toujours disponible (carte joignable). Moonlight : seulement si Apollo repond et que
    # la machine est appairee (voir OpenCheckTick). Un point colore sur l'icone Moonlight indique
    # une session : vert = operationnelle, orange = en connexion.
    $icoRdp = New-Object System.Windows.Forms.Panel
    $icoRdp.Size = New-Object System.Drawing.Size(20, 20)
    $icoRdp.Location = New-Object System.Drawing.Point(($cardW - 28), ($cardH - 24))
    $icoRdp.BackColor = [System.Drawing.Color]::Transparent
    $icoRdp.Cursor = [System.Windows.Forms.Cursors]::Hand
    $icoRdp.Visible = $false
    $icoRdp | Add-Member -NotePropertyName RdpIp -NotePropertyValue $m.RdpIp
    # SOMBRE tant qu'aucune session mstsc n'est ouverte vers cette machine
    $icoRdp.Add_Paint({
      param($s, $e)
      $on = $script:RdpState.ContainsKey([string]$s.RdpIp)
      $img = $(if ($on) { $script:RdpIcon20 } elseif ($script:RdpIcon20Dim) { $script:RdpIcon20Dim } else { $script:RdpIcon20 })
      if ($img) { $e.Graphics.DrawImage($img, 0, 0, 20, 20) }
    })
    $icoRdp.Add_MouseEnter({
      param($s, $e)
      $selObj = & $script:ResolveSelection $s.RdpIp @()
      $script:Tip.SetToolTip($s, "Ouvrir mstsc (Bureau à distance) sur " + $(if ($selObj) { "les écrans " + ($selObj.Idxs -join '+') + " (" + $selObj.PW + "x" + $selObj.PH + ")" } else { "l'écran principal" }))
    })
    $icoRdp.Add_MouseClick({
      param($s, $e)
      if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
      if ($s.Parent.Disabled) { & $script:LogFn ("Carte " + $s.RdpIp + " inactive : machine injoignable (ping)"); return }
      & $script:OpenMstsc $s.RdpIp $true
    })

    $icoMl = New-Object System.Windows.Forms.Panel
    $icoMl.Size = New-Object System.Drawing.Size(20, 20)
    $icoMl.Location = New-Object System.Drawing.Point(($cardW - 54), ($cardH - 24))    # meme rangee que les cartes Linux : mstsc (droite), Moonlight a sa gauche
    $icoMl.BackColor = [System.Drawing.Color]::Transparent
    $icoMl.Cursor = [System.Windows.Forms.Cursors]::Hand
    $icoMl.Visible = $false
    $icoMl | Add-Member -NotePropertyName RdpIp -NotePropertyValue $m.RdpIp
    $icoMl | Add-Member -NotePropertyName Unpaired -NotePropertyValue $false
    $icoMl.Add_Paint({ param($s, $e) & $script:PaintMlIcon $e.Graphics $s })
    $icoMl.Add_MouseEnter({
      param($s, $e)
      $selObj = & $script:ResolveSelection $s.RdpIp @()
      $mlS = $script:MlState[$s.RdpIp]
      $script:Tip.SetToolTip($s, "Ouvrir Moonlight sur " + $(if ($selObj) { "les écrans " + ($selObj.Idxs -join '+') + " (" + $selObj.PW + "x" + $selObj.PH + ")" } else { "l'écran principal" }) + $(if ($mlS) { "`nÉtat : " + $script:MlStateLabels[$mlS.State] }))
    })
    $icoMl.Add_MouseClick({
      param($s, $e)
      if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
      if ($s.Parent.Disabled) { & $script:LogFn ("Carte " + $s.RdpIp + " inactive : machine injoignable (ping)"); return }
      & $script:OpenWindowsHost $s.RdpIp
    })
  }

