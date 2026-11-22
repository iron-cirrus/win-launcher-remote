# cartes\01-fond-filigrane.ps1 - Panneau de la carte, couleurs, filigrane (ordinateur/serveur + logo OS), double tampon
# Corps de la boucle 'foreach ($m in $MachinesOrd)' de ui-50-cartes.ps1 (dot-source par carte). Lignes d'origine du fichier ui-50 : 8-143.

  $g = $m.Group
  if (-not $grpRow.ContainsKey($g)) { $grpRow[$g] = 0 }
  $col = $colIdx[$g]
  $row = $grpRow[$g]
  $grpRow[$g] = $row + 1
  $cardX = [int]($x0 + $col * ($cardW + $gap))
  $cardY = [int]($y0 + $titleH + $row * ($cardH + $gap))

  # couleur locale grise, sinon couleur de la palette
  if ($m.Host -eq "") {
    $normalColor = ConvertTo-DrawingColor "#374151"
    $darkColor   = ConvertTo-DrawingColor "#27303c"
    $fgColor     = ConvertTo-DrawingColor "#d1d5db"
  } else {
    $normalColor = ConvertTo-DrawingColor $m.Color
    $darkColor   = ConvertTo-DrawingColor $m.Dark
    $fgColor     = ConvertTo-DrawingColor $m.Fg
  }

  $card = New-Object System.Windows.Forms.Panel
  $card.Location = New-Object System.Drawing.Point($cardX, $cardY)
  $card.Size = New-Object System.Drawing.Size($cardW, $cardH)
  $card.BackColor = $normalColor
  $card.Cursor = [System.Windows.Forms.Cursors]::Hand
  $card.Tag = $m.Host
  $card | Add-Member -NotePropertyName NormalColor -NotePropertyValue $normalColor
  $card | Add-Member -NotePropertyName DarkColor -NotePropertyValue $darkColor
  # carte inactive quand la machine est injoignable (grisee, clic bloquee)
  $card | Add-Member -NotePropertyName Disabled -NotePropertyValue $false
  $card | Add-Member -NotePropertyName DisabledColor -NotePropertyValue ([System.Drawing.Color]::FromArgb(34,34,37))
  $card | Add-Member -NotePropertyName IconType -NotePropertyValue $m.IconType
  # OS de la machine : sert a integrer le mini logo OS dans le filigrane
  $card | Add-Member -NotePropertyName OsType -NotePropertyValue $m.OsType
  # machine Windows du LAN (scan RDP) : le clic ouvre Moonlight (si Apollo) ou mstsc au lieu de VS Code
  $card | Add-Member -NotePropertyName RdpIp -NotePropertyValue $m.RdpIp

  # filigrane (watermark) en haut a gauche de la carte, derriere les labels :
  #   "pc"  = ordinateur simple (VM, et LOCAL) : ecran + pied
  #   "srv" = serveur physique : 3 badges empiles avec point d'etat
  # Le MINI LOGO OS (Windows 11 ou pingouin Tux) est integre DEDANS :
  #   "pc"  -> au centre de l'ecran ; "srv" -> en bas de la derniere tranche.
  # PERF : le filigrane est rendu UNE SEULE FOIS dans un bitmap transparent,
  # affiche ensuite en BackgroundImage (dessin NATIF WinForms). Avant, un script
  # PowerShell complet s'executait a chaque repaint -- et chaque label
  # transparent de la carte declenchait un repaint de la carte au survol.
  $wmBmp = & {
    param($s)
    $bmpW = New-Object System.Drawing.Bitmap(60, 50, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $wc  = [System.Drawing.Color]::FromArgb(60, 255, 255, 255)   # blanc translucide
    $pen = New-Object System.Drawing.Pen($wc, 2)
    $brs = New-Object System.Drawing.SolidBrush($wc)
    $g = [System.Drawing.Graphics]::FromImage($bmpW)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $ox = 8
    $oy = 8
    if ($s.IconType -eq "srv") {
      # serveur : 3 rectangles empiles + point d'etat a droite
      for ($i = 0; $i -lt 3; $i++) {
        $ry = $oy + ($i * 12)
        $g.DrawRectangle($pen, $ox, $ry, 42, 10)
        $g.FillEllipse($brs, ($ox + 33), ($ry + 3), 4, 4)
      }
      # mini logo OS selon l'OS :
      #   Windows -> logo (10,6 x 10,6 unites, echelle 2.2 : ~23 x 23 px)
      #   Linux   -> pingouin Tux (12 x 14 unites, echelle 2.0 : 24 x 28 px)
      #   tous deux CENTRES sur le chassis (centre x = ox+21 ; y = oy+17)
      if ($s.OsType -eq 'windows') {
        $k = 2.2
        $bx = $ox + 21 - (5.3 * $k); $by = $oy + 17 - (5.3 * $k)
      } else {
        $k = 2.0
        $bx = $ox + 21 - (6 * $k); $by = $oy + 17 - (7 * $k)
      }
    } else {
      # ordinateur : ecran (avec fine ligne "contenu"), pied et base
      $g.DrawRectangle($pen, $ox, $oy, 42, 26)
      $g.DrawLine($pen, ($ox + 5), ($oy + 19), ($ox + 37), ($oy + 19))
      $g.DrawLine($pen, ($ox + 21), ($oy + 26), ($ox + 21), ($oy + 33))
      $g.DrawLine($pen, ($ox + 11), ($oy + 33), ($ox + 31), ($oy + 33))
      # mini logo OS : affiche a l'interieur de l'ecran (42x26) ; Tux a
      # l'echelle 1.75 (~21 x 24,5 px : toute la hauteur de l'ecran) centre,
      # Windows a l'echelle 2.0 (~21 x 21 px, meme largeur que Tux) centre
      if ($s.OsType -eq 'windows') {
        $k = 2.0
        $bx = $ox + 21 - (5.3 * $k); $by = $oy + 13 - (5.3 * $k)
      } else {
        $k = 1.75
        $bx = $ox + 21 - (6 * $k); $by = $oy + 13 - (7 * $k)
      }
    }
    $pen.Dispose(); $brs.Dispose()

    # ----- MINI LOGO SYSTEME integre au filigrane (echelle $k) -----
    # $R : rectangle en unites LOCALES du logo -> pixels du bitmap
    $R = {
      param([double]$x, [double]$y, [double]$w, [double]$h)
      New-Object System.Drawing.RectangleF([float]($bx + $x * $k), [float]($by + $y * $k), [float]($w * $k), [float]($h * $k))
    }
    if ($s.OsType -eq 'windows') {
      # VRAI logo Windows 11 : 4 carres bleus PLATS (pas de perspective),
      # cote 5 unites, ecart 0,6 -> 10,6 x 10,6 unites
      $wb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235, 40, 170, 255))
      foreach ($p in @( @(0, 0), @(1, 0), @(0, 1), @(1, 1) )) {
        $g.FillRectangle($wb, (& $R ($p[0] * 5.6) ($p[1] * 5.6) 5 5))
      }
      $wb.Dispose()
    } else {
      # pingouin TUX (Linux) : 12 x 14 unites. Corps + tete + ailerons noirs
      # (liseres blancs translucides pour rester visible sur les cartes
      # sombres), ventre blanc, yeux, bec et pattes orange.
      $tBk = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(245, 22, 22, 22))
      $tWh = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(245, 248, 248, 248))
      $tOr = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(250, 250, 185, 30))
      $tOl = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(110, 255, 255, 255), [float]1)
      # corps, tete, aileron gauche, aileron droit
      $silh = @( @(1.2, 3.6, 9.6, 10.0), @(2.6, 0, 6.8, 7.0), @(0.2, 5.2, 2.8, 6.2), @(9.0, 5.2, 2.8, 6.2) )
      foreach ($e in $silh) { $g.DrawEllipse($tOl, (& $R $e[0] $e[1] $e[2] $e[3])) }
      foreach ($e in $silh) { $g.FillEllipse($tBk, (& $R $e[0] $e[1] $e[2] $e[3])) }
      $g.FillEllipse($tWh, (& $R 2.9 5.6 6.2 7.6))                                       # ventre
      $g.FillEllipse($tWh, (& $R 4.0 1.8 1.8 2.4)); $g.FillEllipse($tWh, (& $R 6.2 1.8 1.8 2.4))   # yeux
      $g.FillEllipse($tBk, (& $R 4.7 2.6 0.9 1.2)); $g.FillEllipse($tBk, (& $R 6.6 2.6 0.9 1.2))   # pupilles
      $g.FillEllipse($tOr, (& $R 4.3 3.9 3.4 1.7))                                       # bec
      $g.FillEllipse($tOr, (& $R 1.4 12.3 4.4 1.7)); $g.FillEllipse($tOr, (& $R 6.2 12.3 4.4 1.7)) # pattes
      $tBk.Dispose(); $tWh.Dispose(); $tOr.Dispose(); $tOl.Dispose()
    }
    $g.Dispose()
    $bmpW
  } $m | Where-Object { $_ -is [System.Drawing.Bitmap] } | Select-Object -Last 1
  $card.BackgroundImage = $wmBmp
  $card.BackgroundImageLayout = [System.Windows.Forms.ImageLayout]::None
  # double tampon (propriete protegee -> reflexion) : pas de scintillement au survol
  try {
    [System.Windows.Forms.Control].GetProperty('DoubleBuffered',
      [System.Reflection.BindingFlags]'NonPublic,Instance').SetValue($card, $true, $null)
  } catch { }

