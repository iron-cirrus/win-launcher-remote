# cartes\02-textes.ps1 - Titre, utilisateur, role/IP, temps de ping, etiquette de session
# Corps de la boucle 'foreach ($m in $MachinesOrd)' de ui-50-cartes.ps1 (dot-source par carte). Lignes d'origine du fichier ui-50 : 144-256.

  $lblLabel = New-Object System.Windows.Forms.Label
  $lblLabel.Text = $m.Label
  $lblLabel.ForeColor = [System.Drawing.Color]::White
  $lblLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
  $lblLabel.AutoSize = $true
  # RESERVE a gauche : les labels démarrent a x=62 pour laisser la colonne
  # 8..58 au filigrane ordinateur/serveur (sinon le texte le recouvre)
  $lblLabel.Location = New-Object System.Drawing.Point(62, 4)
  $lblLabel.BackColor = [System.Drawing.Color]::Transparent
  $lblLabel.Cursor = [System.Windows.Forms.Cursors]::Hand

  # (le "@HOTE" n'est plus affiche : la colonne du launcher porte deja le groupe)
  # utilisateur de connexion : ligne juste SOUS LE TITRE, alignee a gauche
  # (icone "user" a x=62, nom a x=80). Avant : aligne a droite, il flottait
  # seul au milieu de la carte, loin du nom de la machine.
  $lblUser = New-Object System.Windows.Forms.Label
  if ($m.User) { $lblUser.Text = $m.User } else { $lblUser.Text = "" }
  $lblUser.ForeColor = [System.Drawing.Color]::FromArgb(235, 235, 235)
  $lblUser.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
  $lblUser.TextAlign = [System.Drawing.ContentAlignment]::TopLeft
  $lblUser.AutoSize = $false
  $lblUser.Size = New-Object System.Drawing.Size(($cardW - 80 - 10), 18)
  $lblUser.Location = New-Object System.Drawing.Point(80, 27)
  $lblUser.BackColor = [System.Drawing.Color]::Transparent
  $lblUser.Cursor = [System.Windows.Forms.Cursors]::Hand

  # petite icone "user" (tete + epaules) a gauche du nom de connexion
  $icoUser = New-Object System.Windows.Forms.Panel
  $icoUser.Size = New-Object System.Drawing.Size(14, 16)
  $icoUser.Location = New-Object System.Drawing.Point(62, 28)
  $icoUser.BackColor = [System.Drawing.Color]::Transparent
  $icoUser.Cursor = [System.Windows.Forms.Cursors]::Hand
  $icoUser.Visible = [bool]$m.User
  if (-not $script:BmpUser) {
    $drawUser = {
    param($g, $st, $s)
    $uc = [System.Drawing.Color]::FromArgb(180, 255, 255, 255)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $br = New-Object System.Drawing.SolidBrush($uc)
    $g.FillEllipse($br, 4, 1, 6, 6)                    # tete
    $g.FillPie($br, 1, 8, 12, 12, 180, 180)            # epaules (demi-disque)
    $br.Dispose()
    }
    $script:BmpUser = & $script:NewIconBmp 14 16 $drawUser $null $null
  }
  $icoUser.Add_Paint({ param($s, $e) $e.Graphics.DrawImage($script:BmpUser, 0, 0, 14, 16) })
  # sans utilisateur (LOCAL, postes RDP) : la ligne utilisateur VIDE est masquee. Un label
  # "transparent" repeint le fond de la carte : pose sur la note (role), il en cachait tout
  # sauf les premiers caracteres ("192").
  $lblUser.Visible = [bool]$m.User

  $lblRole = New-Object System.Windows.Forms.Label
  # l'IP COMPLETE doit toujours figurer sur une carte LAN (les VM rattachees a un hyperviseur
  # n'avaient plus que "VM <nom>") : on la place en tete du role si elle n'y est pas deja
  $ipShown = $(if ($m.RdpIp) { [string]$m.RdpIp } elseif ($m.HostName -match '^\d{1,3}(\.\d{1,3}){3}$') { [string]$m.HostName } else { '' })
  $lblRole.Text = $(if ($ipShown -and ([string]$m.Role).IndexOf($ipShown) -lt 0) { $ipShown + " - " + $m.Role } else { $m.Role })
  $lblRole.ForeColor = $fgColor
  $lblRole.Font = New-Object System.Drawing.Font("Segoe UI", 7.5)
  $lblRole.MaximumSize = New-Object System.Drawing.Size(($cardW - 72), 0)
  $lblRole.AutoSize = $true
  # sous la ligne utilisateur ; sans utilisateur (LOCAL, postes RDP) on remonte
  # le role pour ne pas laisser de trou sous le titre
  $lblRole.Location = New-Object System.Drawing.Point(62, $(if ($m.User) { 50 } else { 32 }))
  # poste Windows du LAN : la mini-carte des ecrans commence a y=48 -> note sur UNE ligne
  # pour ne pas empieter dessus. PAS de hauteur fixe + AutoEllipsis : selon la police / la mise a
  # l'echelle, une ligne ne tenait pas dans la hauteur et Windows ne montrait que "1...".
  # Taille naturelle sur une seule ligne (pas de retour) : l'IP, en tete, est toujours entiere ;
  # seule la fin peut etre rognee par le bord de la carte (texte complet en info-bulle).
  if ($m.RdpIp -and -not $m.Host) {
    $lblRole.AutoEllipsis = $false
    $lblRole.MaximumSize = New-Object System.Drawing.Size(0, 0)
    $lblRole.AutoSize = $true
    if ($script:Tip) { $script:Tip.SetToolTip($lblRole, $lblRole.Text) }
    # DISPOSITION IDENTIQUE A CELLE DES CARTES LINUX : titre / ligne "utilisateur" (ici la nature de
    # la machine : "poste du LAN", "VM ...") / ligne IP en dessous (y=50) / rangee d'icones en bas
    $kindTxt2 = ([string]$m.Role) -replace '^\s*[\d\.]+\s*-\s*', '' -replace '^RDP\s*-\s*', ''
    $lblUser.Text = $kindTxt2
    $lblUser.Location = New-Object System.Drawing.Point(62, 27)
    $lblUser.Size = New-Object System.Drawing.Size(($cardW - 72), 18)
    $lblUser.Visible = $true
    $lblRole.Text = ([string]$m.RdpIp) + " - RDP"
    $lblRole.Top = 50
  }
  $lblRole.BackColor = [System.Drawing.Color]::Transparent
  $lblRole.Cursor = [System.Windows.Forms.Cursors]::Hand

  # (la ligne "ssh <alias>" n'est plus affichee dans la carte : trop d'infos ;
  #  l'alias reste visible dans le log au clic / clic droit diagnostic)
  # temps de ping (watchdog) JUSTE SOUS le filigrane ordinateur/serveur :
  # "12 ms" vert / "KO" rouge / "..." gris
  $dot = New-Object System.Windows.Forms.Label
  $dot.AutoSize = $false
  $dot.Size = New-Object System.Drawing.Size(52, 14)
  $dot.Location = New-Object System.Drawing.Point(8, 50)
  $dot.TextAlign = [System.Drawing.ContentAlignment]::TopLeft
  $dot.Font = New-Object System.Drawing.Font("Consolas", 7.5, [System.Drawing.FontStyle]::Bold)
  $dot.BackColor = [System.Drawing.Color]::Transparent
  if ($m.Host -eq "") { $dot.Text = ($script:SymOk + " local"); $dot.ForeColor = $script:DotOk }
  else { $dot.Text = ($script:SymUnk + " ..."); $dot.ForeColor = $script:DotUnk }
  $dot.Cursor = [System.Windows.Forms.Cursors]::Hand

  # ETIQUETTE DE SESSION (sous le temps de ping) : "ML 1+2" = Moonlight sur les ecrans 1 et 2,
  # "RDP 3" = mstsc sur l'ecran 3 (texte : ne repose pas sur la couleur). Alimentee par RefreshSessionTags.
  $lblSess = New-Object System.Windows.Forms.Label
  $lblSess.AutoSize = $false
  $lblSess.Size = New-Object System.Drawing.Size(56, 26)
  $lblSess.Location = New-Object System.Drawing.Point(8, 64)
  $lblSess.TextAlign = [System.Drawing.ContentAlignment]::TopLeft
  $lblSess.Font = New-Object System.Drawing.Font("Consolas", 7, [System.Drawing.FontStyle]::Bold)
  $lblSess.ForeColor = [System.Drawing.Color]::FromArgb(235, 235, 235)
  $lblSess.BackColor = [System.Drawing.Color]::Transparent
  $lblSess.Text = ''

