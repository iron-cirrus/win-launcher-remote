# cartes\03-logo-vscode.ps1 - Indicateur VS Code ouvert/ferme (bas droite)
# Corps de la boucle 'foreach ($m in $MachinesOrd)' de ui-50-cartes.ps1 (dot-source par carte). Lignes d'origine du fichier ui-50 : 257-321.

  # (l'ancienne icone OS separee a ete SUPPRIMEE : le logo systeme est
  #  desormais integre directement dans le filigrane ordinateur/serveur)

  # LOGO VS Code = INDICATEUR ouvert/ferme en bas a droite de la carte :
  #   OUVERT = logo colore BLEU (teinte via ColorMatrix) ; FERMEE = logo GRIS eteint.
  # VRAI logo extrait de Code.exe ($script:VscIconBmp) ; repli : ruban dessine.
  $logoVsc = New-Object System.Windows.Forms.Panel
  # ICONES 20 px (au lieu de 16), espacees de 6 px : plus faciles a viser.
  # Pas : VS Code a cardW-28, VNC a cardW-54, SSH a cardW-80 ; y = cardH-24
  # (la ligne de role, meme sur 2 lignes, se termine avant y=78)
  $logoVsc.Size = New-Object System.Drawing.Size(20, 20)
  $logoVsc.Location = New-Object System.Drawing.Point(($cardW - 28), ($cardH - 24))
  $logoVsc.BackColor = [System.Drawing.Color]::Transparent
  $logoVsc.Cursor = [System.Windows.Forms.Cursors]::Hand
  $logoVsc | Add-Member -NotePropertyName OpenState -NotePropertyValue $false
  $logoVsc | Add-Member -NotePropertyName VscBmp -NotePropertyValue $script:VscIconBmp
  # Le logo VS Code est un INDICATEUR de fenetre VS Code (remote) ouverte/fermee :
  # il n'a AUCUN sens sur un poste Windows detecte par le scan (pas d'alias SSH,
  # donc jamais de fenetre VS Code pour cette machine) -> masque. La carte LOCAL
  # le garde (elle ouvre bien un VS Code local).
  $logoVsc.Visible = -not ($m.RdpIp -and -not $m.Host)
  if (-not $script:BmpVscOn) {
    $drawVsc = {
    param($g, $open, $s)
    if ($s.VscBmp) {
      # teinte le logo officiel : bleu si fenetre ouverte, gris eteint sinon
      $cm = New-Object System.Drawing.Imaging.ColorMatrix
      if ($open) {
        # pousse le bleu, attenue rouge/vert -> rendu "actif bleu VS Code"
        $cm.Matrix00 = 0.30; $cm.Matrix11 = 0.60; $cm.Matrix22 = 1.35
        $cm.Matrix33 = 1.0
      } else {
        # niveaux de gris + opacite reduite -> logo "eteint"
        $cm.Matrix00 = 0.33; $cm.Matrix10 = 0.33; $cm.Matrix20 = 0.33
        $cm.Matrix01 = 0.33; $cm.Matrix11 = 0.33; $cm.Matrix21 = 0.33
        $cm.Matrix02 = 0.33; $cm.Matrix12 = 0.33; $cm.Matrix22 = 0.33
        $cm.Matrix33 = 0.65
      }
      $ia = New-Object System.Drawing.Imaging.ImageAttributes
      $ia.SetColorMatrix($cm) | Out-Null
      $rect = New-Object System.Drawing.Rectangle(0, 0, 16, 16)
      $g.DrawImage($s.VscBmp, $rect, 0, 0, $s.VscBmp.Width, $s.VscBmp.Height, `
        [System.Drawing.GraphicsUnit]::Pixel, $ia)
      $ia.Dispose()
    } else {
      # repli sans Code.exe : ruban style logo VS Code, bleu ou gris
      $col = if ($open) { [System.Drawing.Color]::FromArgb(230,0,120,212) } else { [System.Drawing.Color]::FromArgb(150,110,110,110) }
      $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
      $pen = New-Object System.Drawing.Pen($col, 2)
      $g.DrawLine($pen, 2, 2, 14, 8)
      $g.DrawLine($pen, 2, 14, 14, 8)
      $g.DrawLine($pen, 2, 2, 2, 14)
      $g.DrawLine($pen, 2, 2, 8, 16)
      $g.DrawLine($pen, 2, 14, 8, 0)
      $pen.Dispose()
    }
    }
    $script:BmpVscOn  = & $script:NewIconBmp 20 20 $drawVsc $true  $logoVsc 1.25
    $script:BmpVscOff = & $script:NewIconBmp 20 20 $drawVsc $false $logoVsc 1.25
  }
  $logoVsc.Add_Paint({
    param($s, $e)
    $e.Graphics.DrawImage($(if ($s.OpenState) { $script:BmpVscOn } else { $script:BmpVscOff }), 0, 0, 20, 20)
  })

