# 13-panneau-haut.ps1 - Panneau du haut : carte des ecrans + sessions distantes
# Fichier charge par vsc_launcher.ps1 (dot-source : meme portee script). Lignes d'origine 2159-2508.

# ---------- PANNEAU DU HAUT : DISPOSITION DES ECRANS + SESSIONS DISTANTES ----------
# La fenetre est coupee en deux : EN HAUT, la disposition des ecrans locaux (a l'echelle, positions
# relatives respectees) et la liste des sessions distantes ; EN BAS, les cartes des machines.
#  - La carte des ecrans est LE selecteur : clic = un ecran, glisser = plusieurs ecrans contigus,
#    Ctrl = ajouter / retirer. Ce choix est GLOBAL : les icones Moonlight et mstsc de TOUTES les
#    cartes ouvrent leur session sur les ecrans choisis.
#  - Les sessions distantes ouvertes (Moonlight, mstsc) y apparaissent : leur icone + le nom de la
#    machine sont poses sur les ecrans qu'elles occupent (bordure bleue = Moonlight, orange = mstsc ;
#    gris = session deconnectee). Cliquer une icone (ou une ligne de la liste) ramene la fenetre au
#    premier plan.
$script:ShowTopPanel = $true
$script:TopMap = $null; $script:TopList = $null
$script:TopPenBlue = [System.Drawing.Color]::FromArgb(86, 180, 233)
$script:TopPenOrange = [System.Drawing.Color]::FromArgb(230, 159, 0)
# nom affiche d'une machine d'apres son adresse (carte), sinon l'adresse
$script:CardNameFor = {
  param([string]$ip)
  foreach ($c in @($script:CardList)) {
    if ($c.PingHost -eq $ip -or ($c.Ml -and $c.Ml.RdpIp -eq $ip) -or ($c.SunAddr -and $c.SunAddr -eq $ip)) { return [string]$c.Label }
  }
  return $ip
}
# sessions distantes connues : Moonlight (MlState) + mstsc (RdpState)
$script:GetSessions = {
  $out = @()
  foreach ($ip in @($script:MlState.Keys)) {
    $m = $script:MlState[$ip]
    # session fermee ('ended') ou dont la fenetre a disparu ('lost') : plus affichee sur les ecrans
    if ($m.State -eq 'ended' -or $m.State -eq 'lost') { continue }
    $out += [pscustomobject]@{ Ip = [string]$ip; Name = (& $script:CardNameFor $ip); Kind = 'ml'; State = [string]$m.State; Idxs = @($m.Idxs); Since = $m.Since }
  }
  foreach ($ip in @($script:RdpState.Keys)) {
    $r = $script:RdpState[$ip]
    $out += [pscustomobject]@{ Ip = [string]$ip; Name = (& $script:CardNameFor $ip); Kind = 'rdp'; State = 'open'; Idxs = @($r.Idxs); Since = $r.Since }
  }
  return ,$out
}
# etiquette "ML 1+2" / "RDP 3" de chaque carte (sessions actives de la machine)
$script:RefreshSessionTags = {
  foreach ($c in @($script:CardList)) {
    if (-not $c.Sess) { continue }
    $keys = @([string]$c.PingHost)
    if ($c.Ml -and $c.Ml.RdpIp) { $keys += [string]$c.Ml.RdpIp }
    if ($c.SunAddr) { $keys += [string]$c.SunAddr }
    $lines = @()
    foreach ($k in ($keys | Select-Object -Unique)) {
      $m = $script:MlState[$k]
      if ($m -and $m.State -eq 'live') { $lines += ("ML " + (@($m.Idxs) -join '+')) }
      elseif ($m -and $m.State -eq 'connecting') { $lines += ("ML.. " + (@($m.Idxs) -join '+')) }
      $r = $script:RdpState[$k]
      if ($r) { $lines += ("RDP " + (@($r.Idxs) -join '+')) }
    }
    $t = ($lines -join "`n")
    if ($c.Sess.Text -ne $t) { $c.Sess.Text = $t }
    # icones Moonlight / mstsc : sombres sans session, en couleur avec session
    try { if ($c.Ml) { $c.Ml.Invalidate() }; if ($c.RdpBtn) { $c.RdpBtn.Invalidate() } } catch { }
  }
}
$script:RefreshTop = {
  try { if ($script:TopMap -and -not $script:TopMap.IsDisposed) { $script:TopMap.Invalidate() } } catch { }
  try { if ($script:TopList -and -not $script:TopList.IsDisposed) { $script:TopList.Invalidate() } } catch { }
  try { & $script:RefreshSessionTags } catch { }
}
# numero de l'ecran qui porte la fenetre du launcher
$script:LauncherScreenIdx = {
  try {
    $sc = [System.Windows.Forms.Screen]::FromControl($form)
    if ($sc.DeviceName -match '(\d+)\s*$') { return [int]$Matches[1] }
  } catch { }
  return 0
}
# ramene au premier plan la fenetre d'une session (Moonlight : fenetre du flux ; mstsc : sa fenetre)
$script:FocusSession = {
  param([string]$ip, [string]$kind)
  $p = $null
  if ($kind -eq 'ml') {
    if ($script:RetryTimer -and $script:RetryTimer.Tag -and $script:RetryTimer.Tag.ContainsKey($ip)) { $p = $script:RetryTimer.Tag[$ip].Proc }
    if (-not $p -and $script:MlAdopted.ContainsKey($ip)) { $p = $script:MlAdopted[$ip] }
  } else {
    $st = $script:RdpState[$ip]; if ($st) { $p = $st.Proc }
  }
  $alive = $false; try { if ($p -and -not $p.HasExited) { $alive = $true } } catch { }
  if (-not $alive) { & $script:LogFn ("session " + $kind + " " + $ip + " : plus de fenetre a ramener (session fermee)"); return }
  $hw = [IntPtr]::Zero
  foreach ($w in [VscScrV3]::GetProcessWindows($p.Id)) {
    $hw = [IntPtr][long]$w[0]
    if ($kind -ne 'ml' -or $w[5] -match $script:MoonlightStreamTitle) { break }
  }
  if ($hw -eq [IntPtr]::Zero) { try { $p.Refresh(); $hw = $p.MainWindowHandle } catch { } }
  if ($hw -eq [IntPtr]::Zero) { & $script:LogFn ("session " + $kind + " " + $ip + " : fenetre introuvable (reduite dans la barre des taches ?)"); return }
  & $script:LogFn ("session " + $kind + " " + $ip + " : fenetre ramenee au premier plan")
  if ($script:WinHostDryRun) { return }
  [void][VscWinV4]::ShowWindow($hw, 9)
  [void][VscWinV4]::SetForegroundWindow($hw)
}
$script:PaintTopMap = {
  param($s, $e)
  $g = $e.Graphics
  $g.Clear([System.Drawing.Color]::FromArgb(16, 16, 19))
  $penFrame = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(75, 75, 82), 1)
  $g.DrawRectangle($penFrame, 0, 0, ($s.Width - 1), ($s.Height - 1)); $penFrame.Dispose()
  $layout = & $script:MapLayout $s.Width $s.Height
  $selIdx = @()
  if ($s.Dragging) { $selIdx = @($s.DragSet) } else { $so = & $script:ResolveSelection $s.RdpIp @(); if ($so) { $selIdx = @($so.Idxs) } }
  $sessions = & $script:GetSessions          # (pas de @(...) autour : la fonction renvoie deja un tableau)
  $launcherIdx = & $script:LauncherScreenIdx
  $s.IconRects.Clear()
  $font = New-Object System.Drawing.Font("Segoe UI", 6.5, [System.Drawing.FontStyle]::Bold)
  $fontS = New-Object System.Drawing.Font("Segoe UI", 6)
  $sf = New-Object System.Drawing.StringFormat
  $sf.Alignment = [System.Drawing.StringAlignment]::Center; $sf.LineAlignment = [System.Drawing.StringAlignment]::Near
  $sf.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter; $sf.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap
  $txtBr = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
  $dimBr = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(150, 255, 255, 255))
  $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(150, 255, 255, 255), 1)
  $penBlue = New-Object System.Drawing.Pen($script:TopPenBlue, 3)
  $penOr = New-Object System.Drawing.Pen($script:TopPenOrange, 3)
  foreach ($r in $layout) {
    $rc = New-Object System.Drawing.RectangleF($r.X, $r.Y, $r.Wd, $r.Ht)
    $isSel = $selIdx -contains $r.Idx
    $mine = @($sessions | Where-Object { $_.Idxs -contains $r.Idx })
    $active = @($mine | Where-Object { $_.State -eq 'live' -or $_.State -eq 'connecting' -or $_.State -eq 'open' })
    $ghost = @($mine | Where-Object { $_.State -eq 'ended' -or $_.State -eq 'lost' })
    # fond : apercu du glisser / SELECTION (cible du prochain lancement) / deconnecte (gris) / survol / neutre
    $fill = if ($s.Dragging -and $isSel) { [System.Drawing.Color]::FromArgb(215, 96, 165, 250) }
            elseif ($isSel) { [System.Drawing.Color]::FromArgb(240, 37, 99, 235) }
            elseif ($ghost.Count -gt 0 -and $active.Count -eq 0) { [System.Drawing.Color]::FromArgb(230, 100, 100, 104) }
            elseif ($r.Idx -eq $s.HoverIdx -and -not $s.Dragging) { [System.Drawing.Color]::FromArgb(255, 72, 72, 82) }
            else { [System.Drawing.Color]::FromArgb(255, 38, 38, 45) }
    $br = New-Object System.Drawing.SolidBrush($fill)
    $g.FillRectangle($br, $rc); $br.Dispose()
    $g.DrawRectangle($pen, $rc.X, $rc.Y, $rc.Width, $rc.Height)
    # ecran OCCUPE : bordure bleue (Moonlight) et / ou orange (mstsc)
    if (@($active | Where-Object { $_.Kind -eq 'ml' }).Count -gt 0) { $g.DrawRectangle($penBlue, ($rc.X + 2), ($rc.Y + 2), ($rc.Width - 4), ($rc.Height - 4)) }
    if (@($active | Where-Object { $_.Kind -eq 'rdp' }).Count -gt 0) {
      $off = $(if (@($active | Where-Object { $_.Kind -eq 'ml' }).Count -gt 0) { 6 } else { 2 })
      $g.DrawRectangle($penOr, ($rc.X + $off), ($rc.Y + $off), ($rc.Width - 2 * $off), ($rc.Height - 2 * $off))
    }
    # LOGOS des clients distants poses sur l'ecran, avec le nom de la machine dessous
    $list = @($active + $ghost)
    if ($list.Count -gt 0) {
      $showNames = ($rc.Height -ge 46)
      $nameH = $(if ($showNames) { 11 } else { 0 })
      # une "case" par session (largeur egale) : l'icone est centree dans sa case, le nom en dessous
      $slotW = [single](($rc.Width - 8) / $list.Count)
      $isz = [single][Math]::Min(30, [Math]::Min([Math]::Floor(($rc.Height - 14 - $nameH) * 0.9), [Math]::Floor($slotW) - 6))
      if ($isz -ge 10) {
        $ly = [single]($rc.Y + ($rc.Height - $isz - $nameH) / 2)
        $si = 0
        foreach ($se in $list) {
          $slotX = [single]($rc.X + 4 + $si * $slotW); $si++
          $lx = [single]($slotX + ($slotW - $isz) / 2)
          $isGhost = ($se.State -eq 'ended' -or $se.State -eq 'lost')
          $img = $(if ($se.Kind -eq 'rdp') { $script:RdpIcon20 } elseif ($se.State -eq 'live') { $script:MlIcon } else { $script:MlIconDim })
          if ($img) { $g.DrawImage($img, $lx, $ly, $isz, $isz) }
          if ($se.State -eq 'connecting') { $po = New-Object System.Drawing.Pen($script:TopPenOrange, 2); $g.DrawRectangle($po, ($lx - 2), ($ly - 2), ($isz + 4), ($isz + 4)); $po.Dispose() }
          if ($showNames) {
            $nr = New-Object System.Drawing.RectangleF($slotX, ($ly + $isz + 1), $slotW, 11)
            $g.DrawString([string]$se.Name, $fontS, $(if ($isGhost) { $dimBr } else { $txtBr }), $nr, $sf)
          }
          [void]$s.IconRects.Add([pscustomobject]@{ X = $slotX; Y = $ly; W = $slotW; H = ($isz + $nameH); Ip = $se.Ip; Kind = $se.Kind; Name = $se.Name; State = $se.State; Since = $se.Since })
        }
      }
    }
    if ($r.Idx -eq $launcherIdx -and $rc.Height -ge 22) { $g.DrawString("LAUNCHER", $fontS, $dimBr, [single]($rc.X + 4), [single]($rc.Y + 3)) }
    if ($r.Primary) {   # barre des taches : marque l'ecran principal
      $g.FillRectangle($txtBr, [single]($rc.X + $rc.Width * 0.3), [single]($rc.Bottom - 5), [single]($rc.Width * 0.4), [single]2)
    }
  }
  # plusieurs ecrans choisis : contour de l'ENSEMBLE
  $selRects = @($layout | Where-Object { $selIdx -contains $_.Idx })
  if ($selRects.Count -gt 1) {
    $ax = ($selRects | ForEach-Object { $_.X } | Measure-Object -Minimum).Minimum
    $ay = ($selRects | ForEach-Object { $_.Y } | Measure-Object -Minimum).Minimum
    $bx = ($selRects | ForEach-Object { $_.X + $_.Wd } | Measure-Object -Maximum).Maximum
    $by = ($selRects | ForEach-Object { $_.Y + $_.Ht } | Measure-Object -Maximum).Maximum
    $penSel = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 191, 219, 254), 2)
    $g.DrawRectangle($penSel, [single]($ax - 1), [single]($ay - 1), [single]($bx - $ax + 2), [single]($by - $ay + 2)); $penSel.Dispose()
  }
  if ($s.Dragging -and $s.DragMoved -and $s.DragStart -and $s.DragNow) {
    $penBand = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 1); $penBand.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
    $g.DrawRectangle($penBand, [Math]::Min($s.DragStart.X, $s.DragNow.X), [Math]::Min($s.DragStart.Y, $s.DragNow.Y), [Math]::Abs($s.DragStart.X - $s.DragNow.X), [Math]::Abs($s.DragStart.Y - $s.DragNow.Y)); $penBand.Dispose()
  }
  $font.Dispose(); $fontS.Dispose(); $sf.Dispose(); $txtBr.Dispose(); $dimBr.Dispose(); $pen.Dispose(); $penBlue.Dispose(); $penOr.Dispose()
}
$script:PaintTopList = {
  param($s, $e)
  $g = $e.Graphics
  $g.Clear([System.Drawing.Color]::FromArgb(16, 16, 19))
  $penFrame = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(75, 75, 82), 1)
  $g.DrawRectangle($penFrame, 0, 0, ($s.Width - 1), ($s.Height - 1)); $penFrame.Dispose()
  $fB = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
  $f8 = New-Object System.Drawing.Font("Segoe UI", 8)
  $f8b = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
  $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
  $grey = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(150, 150, 158))
  $light = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(215, 215, 222))
  $x = 10; $y = 7
  $sel = & $script:ResolveSelection '__global' @()
  $selTxt = $(if ($sel) { "écran" + $(if ($sel.Idxs.Count -gt 1) { "s" }) + " " + ($sel.Idxs -join '+') + "  ·  " + $sel.PW + " x " + $sel.PH } else { "aucun écran" })
  $g.DrawString("CIBLE DES SESSIONS : " + $selTxt, $fB, $white, [single]$x, [single]$y)
  $y += 19
  $hint = "Clic ou glisser sur la carte des écrans pour choisir (Ctrl : ajouter / retirer), puis cliquer l'icône Moonlight ou mstsc d'une carte du bas : la session s'ouvre sur ces écrans."
  $hr = New-Object System.Drawing.RectangleF($x, $y, ($s.Width - 2 * $x), 34)
  $g.DrawString($hint, $f8, $grey, $hr)
  $y += 36
  $pl = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(60, 60, 66), 1)
  $g.DrawLine($pl, $x, $y, ($s.Width - $x), $y); $pl.Dispose()
  $y += 4
  $g.DrawString("SESSIONS DISTANTES", $f8b, $grey, [single]$x, [single]$y)
  $y += 16
  $s.RowRects.Clear()
  $sessAll = & $script:GetSessions
  $sessions = @($sessAll | Sort-Object { if ($_.State -eq 'ended' -or $_.State -eq 'lost') { 1 } else { 0 } }, Name, Kind)
  if ($sessions.Count -eq 0) {
    $g.DrawString("Aucune session distante ouverte", $f8, $grey, [single]$x, [single]$y)
  } else {
    $rowH = 20
    foreach ($se in $sessions) {
      if (($y + $rowH) -gt ($s.Height - 3)) { $g.DrawString("…", $f8b, $grey, [single]$x, [single]$y); break }
      $isGhost = ($se.State -eq 'ended' -or $se.State -eq 'lost')
      $img = $(if ($se.Kind -eq 'rdp') { $script:RdpIcon20 } elseif ($se.State -eq 'live') { $script:MlIcon } else { $script:MlIconDim })
      if ($img) { $g.DrawImage($img, [single]$x, [single]($y + 1), 16, 16) }
      $kindTxt = $(if ($se.Kind -eq 'rdp') { "mstsc" } else { "Moonlight" })
      $stTxt = $(if ($se.Kind -eq 'rdp') { "ouvert" } else { ([string]$script:MlStateLabels[$se.State]).ToLower() })
      $br = $(if ($isGhost) { $grey } else { $white })
      $g.DrawString([string]$se.Name, $f8b, $br, [single]($x + 22), [single]($y + 2))
      $nameW = $g.MeasureString([string]$se.Name, $f8b).Width
      $g.DrawString(($kindTxt + " · " + $stTxt + " · écran" + $(if ($se.Idxs.Count -gt 1) { "s" }) + " " + (@($se.Idxs) -join '+') + $(if ($se.Since) { " · " + $se.Since.ToString('HH:mm') })), $f8, $(if ($isGhost) { $grey } else { $light }), [single]($x + 22 + $nameW), [single]($y + 2))
      [void]$s.RowRects.Add([pscustomobject]@{ Y = $y; H = $rowH; Ip = $se.Ip; Kind = $se.Kind; State = $se.State })
      $y += $rowH
    }
  }
  $fB.Dispose(); $f8.Dispose(); $f8b.Dispose(); $white.Dispose(); $grey.Dispose(); $light.Dispose()
}
$script:BuildTopPanel = {
  # ----- carte des ecrans : selecteur global -----
  $m = New-Object System.Windows.Forms.Panel
  $m.BackColor = [System.Drawing.Color]::FromArgb(16, 16, 19)
  $m.Cursor = [System.Windows.Forms.Cursors]::Hand
  $m | Add-Member -NotePropertyName RdpIp -NotePropertyValue '__global'          # cle du choix GLOBAL (voir ResolveSelection)
  $m | Add-Member -NotePropertyName HoverIdx -NotePropertyValue 0
  $m | Add-Member -NotePropertyName HoverKey -NotePropertyValue ''
  $m | Add-Member -NotePropertyName Dragging -NotePropertyValue $false
  $m | Add-Member -NotePropertyName DragMoved -NotePropertyValue $false
  $m | Add-Member -NotePropertyName DragStart -NotePropertyValue $null
  $m | Add-Member -NotePropertyName DragNow -NotePropertyValue $null
  $m | Add-Member -NotePropertyName DragSet -NotePropertyValue @()
  $m | Add-Member -NotePropertyName PressIcon -NotePropertyValue $null
  $m | Add-Member -NotePropertyName IconRects -NotePropertyValue (New-Object System.Collections.ArrayList)
  try { [System.Windows.Forms.Control].GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'NonPublic,Instance').SetValue($m, $true, $null) } catch { }
  $m.Add_Paint({ param($s, $e) & $script:PaintTopMap $s $e })
  $m.Add_MouseDown({
    param($s, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $s.Dragging = $true; $s.DragMoved = $false; $s.PressIcon = $null
    $s.DragStart = New-Object System.Drawing.Point($e.X, $e.Y); $s.DragNow = $s.DragStart
    foreach ($ir in $s.IconRects) {
      if ($e.X -ge $ir.X -and $e.X -le ($ir.X + $ir.W) -and $e.Y -ge $ir.Y -and $e.Y -le ($ir.Y + $ir.H)) { $s.PressIcon = $ir; break }
    }
    $h0 = $(if ($s.PressIcon) { 0 } else { & $script:MapHit $s $e.X $e.Y })
    $s.DragSet = $(if ($h0 -gt 0) { @($h0) } else { @() })
    $s.Invalidate()
  })
  $m.Add_MouseMove({
    param($s, $e)
    if ($s.Dragging) {
      $s.DragNow = New-Object System.Drawing.Point($e.X, $e.Y)
      if ([Math]::Max([Math]::Abs($e.X - $s.DragStart.X), [Math]::Abs($e.Y - $s.DragStart.Y)) -ge 4) { $s.DragMoved = $true }
      if ($s.DragMoved) {
        $s.PressIcon = $null
        $inRect = & $script:MapScreensInRect $s $s.DragStart.X $s.DragStart.Y $e.X $e.Y
        $s.DragSet = $(if ($null -eq $inRect) { @() } else { @($inRect) })
      }
      $s.Invalidate()
      return
    }
    # survol : une icone de session (ramener la fenetre) ou un ecran (choisir)
    $hit = $null
    foreach ($ir in $s.IconRects) {
      if ($e.X -ge $ir.X -and $e.X -le ($ir.X + $ir.W) -and $e.Y -ge $ir.Y -and $e.Y -le ($ir.Y + $ir.H)) { $hit = $ir; break }
    }
    $h = $(if ($hit) { 0 } else { & $script:MapHit $s $e.X $e.Y })
    $key = $(if ($hit) { "i:" + $hit.Ip + $hit.Kind } else { "s:" + $h })
    if ($key -ne $s.HoverKey) {
      $s.HoverKey = $key
      if ($h -ne $s.HoverIdx) { $s.HoverIdx = $h; $s.Invalidate() }
      $tipTxt = ""
      if ($hit) {
        $tipTxt = $(if ($hit.Kind -eq 'rdp') { "mstsc (Bureau à distance)" } else { "Moonlight" }) + " · " + $hit.Name + "`n" + $(if ($hit.Kind -eq 'rdp') { "ouvert" } else { ([string]$script:MlStateLabels[$hit.State]).ToLower() }) + $(if ($hit.Since) { " depuis " + $hit.Since.ToString('HH:mm:ss') }) + "`nClic : ramener la fenêtre au premier plan"
      } elseif ($h -gt 0) {
        $sc = @($script:Screens | Where-Object { $_.Idx -eq $h }) | Select-Object -First 1
        if ($sc) { $tipTxt = "Écran " + $sc.Idx + " : " + $sc.PW + "x" + $sc.PH + $(if ($sc.PW -ne $sc.W) { " (vu " + $sc.W + "x" + $sc.H + " avec la mise à l'échelle)" }) + $(if ($sc.Primary) { " (principal)" }) + "`nClic : choisir cet écran`nGlisser : plusieurs écrans contigus`nCtrl+clic : ajouter / retirer" }
        if ($script:MoonlightAutoProfile) {
          $selNow = & $script:ResolveSelection $s.RdpIp @()
          $pfl = $(if ($selNow) { & $script:BuildMoonlightProfile $selNow })
          if ($pfl) { $tipTxt += "`nProfil Moonlight (écrans " + ($selNow.Idxs -join '+') + ") : " + $pfl.Text }
        }
      }
      $script:Tip.SetToolTip($s, $tipTxt)
      $s.Cursor = $(if ($hit) { [System.Windows.Forms.Cursors]::Hand } else { [System.Windows.Forms.Cursors]::Default })
    }
  })
  $m.Add_MouseUp({
    param($s, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left -or -not $s.Dragging) { return }
    $moved = $s.DragMoved; $set = @($s.DragSet); $press = $s.PressIcon
    $s.Dragging = $false; $s.DragMoved = $false; $s.DragStart = $null; $s.DragNow = $null; $s.DragSet = @(); $s.PressIcon = $null
    $s.Invalidate()
    # clic (sans glisser) sur une icone de session : la fenetre revient au premier plan
    if ($press -and -not $moved) { & $script:FocusSession $press.Ip $press.Kind; return }
    if ($set.Count -eq 0) { return }
    if (([System.Windows.Forms.Control]::ModifierKeys -band [System.Windows.Forms.Keys]::Control) -ne 0) {
      # Ctrl : clic = bascule d'un ecran, glisser = ajoute
      $cur = & $script:ResolveSelection '__global' @()
      $cmb = & $script:CtrlCombine $(if ($cur) { @($cur.Idxs) } else { @() }) $set $moved
      $new = $(if ($null -eq $cmb) { @() } else { @($cmb) })
      if ($new.Count -eq 0) { return }
      $set = $new
    }
    if (& $script:SetSelection '__global' $set) {
      & $script:LogFn ("ecrans cibles : " + ($set -join '+') + " (cliquer l'icone Moonlight ou mstsc d'une carte pour y ouvrir sa session)")
    }
    $s.Invalidate()
    if ($script:TopList) { $script:TopList.Invalidate() }
  })
  $m.Add_MouseLeave({ param($s, $e) if (-not $s.Dragging) { $s.HoverKey = ''; if ($s.HoverIdx -ne 0) { $s.HoverIdx = 0; $s.Invalidate() } } })
  # ----- liste de selection + sessions -----
  $l = New-Object System.Windows.Forms.Panel
  $l.BackColor = [System.Drawing.Color]::FromArgb(16, 16, 19)
  $l | Add-Member -NotePropertyName RowRects -NotePropertyValue (New-Object System.Collections.ArrayList)
  try { [System.Windows.Forms.Control].GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'NonPublic,Instance').SetValue($l, $true, $null) } catch { }
  $l.Add_Paint({ param($s, $e) & $script:PaintTopList $s $e })
  $l.Add_MouseMove({
    param($s, $e)
    $on = $false
    foreach ($rr in $s.RowRects) { if ($e.Y -ge $rr.Y -and $e.Y -le ($rr.Y + $rr.H)) { $on = $true; break } }
    $s.Cursor = $(if ($on) { [System.Windows.Forms.Cursors]::Hand } else { [System.Windows.Forms.Cursors]::Default })
  })
  $l.Add_MouseClick({
    param($s, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    foreach ($rr in $s.RowRects) {
      if ($e.Y -ge $rr.Y -and $e.Y -le ($rr.Y + $rr.H)) { & $script:FocusSession $rr.Ip $rr.Kind; break }
    }
  })
  $form.Controls.Add($m); $form.Controls.Add($l)
  $script:TopMap = $m; $script:TopList = $l
}
& $script:UpdateHome $false
