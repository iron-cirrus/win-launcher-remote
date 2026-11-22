# 11-icones-disposition.ps1 - Icones en cache (NewIconBmp) et disposition adaptative (Relayout)
# Fichier charge par vsc_launcher.ps1 (dot-source : meme portee script). Lignes d'origine 1827-2085.

# PERF : rendu d'une petite icone dans un bitmap transparent, UNE FOIS.
# Les icones des cartes (VS Code, VNC, SSH, user) ne sont plus redessinees par
# script a chaque repaint : le handler Paint se contente de poser le bitmap
# en cache correspondant a l'etat (ouvert/ferme, connecte/non).
# $draw recoit (Graphics, etat, objet porteur des proprietes lues par le dessin).
$script:NewIconBmp = {
  # $sc : facteur d'echelle. Les dessins sont ecrits pour une grille de 16 px ;
  # pour une icone de 20 px on passe 1.25 (dessin vectoriel net, pas d'agrandissement
  # d'une image 16 px deja rendue)
  param([int]$w, [int]$h, [scriptblock]$draw, $state, $s, [double]$sc = 1.0)
  $b = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $gI = [System.Drawing.Graphics]::FromImage($b)
  $gI.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $gI.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  if ($sc -ne 1.0) { $gI.ScaleTransform([float]$sc, [float]$sc) }
  try { [void](& $draw $gI $state $s) } finally { $gI.Dispose() }
  return ,$b
}
# info-bulles des icones de carte (un seul composant partage, cree une fois)
$script:Tip = New-Object System.Windows.Forms.ToolTip
$script:Tip.InitialDelay = 400
$script:BmpVscOn = $null; $script:BmpVscOff = $null
$script:BmpVncOn = $null; $script:BmpVncOff = $null
$script:BmpSshOn = $null; $script:BmpSshOff = $null
$script:BmpUser = $null

# ---------- Construction de l'IHM (scriptblock REEXECUTABLE) ----------
# La liste des machines peut changer (fin du scan LAN) : toute la fenetre est
# construite dans un scriptblock que le script relance dans le MEME processus
# (reconstruction Win32) au lieu de relancer powershell.
# ---------- DISPOSITION ADAPTATIVE ----------
# - Cartes INACTIVES (machine injoignable) : non affichees ; elles reapparaissent des que la machine
#   repond (la disposition se recalcule seule). Au demarrage, la memoire du dernier etat connu evite
#   que tout disparaisse puis reapparaisse a chaque reconstruction de l'affichage.
# - ECRAN D'ACCUEIL : si un ecran "Generic Non-PnP Monitor" branche sur l'adaptateur spacedesk est
#   present, le launcher s'ouvre en PLEIN ECRAN dessus ; s'il est absent, rien ne change (fenetre
#   normale, ajustee a son contenu). Branche/debranche en cours de route : suivi automatique.
# - COLONNES : une par groupe (LOCAL est fusionne dans LAN) ; elles sont centrees. Si la place manque
#   (largeur de l'ecran) les groupes les plus courts s'empilent sous les autres ; si une colonne est
#   trop haute elle se coupe en deux. Le journal (fleche) reduit la place des cartes au lieu
#   d'agrandir la fenetre quand elle est en plein ecran.
$script:HideInactiveCards = $true
$script:HomeScreenEnabled = $true
$script:HomeScreenAdapterRegex = 'spacedesk'          # nom de l'adaptateur graphique
$script:HomeScreenMonitorRegex = 'Non-?\s?PnP'        # nom du moniteur ("Generic Non-PnP Monitor")
$script:GroupTitles = @{ 'LAN' = 'LOCAL · LAN' }      # titre affiche d'une colonne (sinon : le nom du groupe)
$script:AliveMemo = @{}
# dernier etat connu (machine joignable ou non) conserve entre deux lancements : au demarrage la
# fenetre a tout de suite la bonne taille, sans attendre les premiers pings
$script:AliveMemoPath = Join-Path $env:LOCALAPPDATA "vsc-launcher\alive-memo.json"
try {
  if (Test-Path $script:AliveMemoPath) {
    $amObj = Get-Content $script:AliveMemoPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($pp in $amObj.PSObject.Properties) { $script:AliveMemo[$pp.Name] = [bool]$pp.Value }
  }
} catch { }
$script:HomeScreen = $null
$script:LayoutSig = ''
$script:LayoutMode = $null
$script:LayoutItems = @()
$script:UiTitlePool = @()
$script:UiFullscreen = $false
$script:UiTitleFont = $null
if (-not ('VscDispV1' -as [type])) {
  Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
public class VscDispV1 {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct DD { public int cb; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string DeviceName; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceString; public int StateFlags; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceID; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceKey; }
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool EnumDisplayDevices(string dev, uint i, ref DD d, uint f);
  // [nom du bureau (\\.\DISPLAYn), adaptateur graphique, moniteur] pour chaque ecran actif
  public static List<string[]> Monitors() {
    var r = new List<string[]>();
    for (uint i = 0; ; i++) {
      var a = new DD(); a.cb = Marshal.SizeOf(a);
      if (!EnumDisplayDevices(null, i, ref a, 0)) break;
      if ((a.StateFlags & 1) == 0) continue;
      for (uint j = 0; ; j++) {
        var m = new DD(); m.cb = Marshal.SizeOf(m);
        if (!EnumDisplayDevices(a.DeviceName, j, ref m, 0)) break;
        r.Add(new string[] { a.DeviceName, a.DeviceString, m.DeviceString });
      }
    }
    return r;
  }
}
"@
}
$script:FindHomeScreen = {
  if (-not $script:HomeScreenEnabled) { return $null }
  try {
    foreach ($r in [VscDispV1]::Monitors()) {
      if (($r[1] -match $script:HomeScreenAdapterRegex) -and ($r[2] -match $script:HomeScreenMonitorRegex)) {
        foreach ($s in [System.Windows.Forms.Screen]::AllScreens) {
          if ($s.DeviceName -eq $r[0]) { return [pscustomobject]@{ Name = $s.DeviceName; X = $s.Bounds.X; Y = $s.Bounds.Y; W = $s.Bounds.Width; H = $s.Bounds.Height } }
        }
      }
    }
  } catch { }
  return $null
}
$script:UpdateHome = {
  param([bool]$relayout = $true)
  $h = & $script:FindHomeScreen
  $sigN = $(if ($h) { "" + $h.Name + ":" + $h.X + "," + $h.Y + "," + $h.W + "x" + $h.H } else { '' })
  $o = $script:HomeScreen
  $sigO = $(if ($o) { "" + $o.Name + ":" + $o.X + "," + $o.Y + "," + $o.W + "x" + $o.H } else { '' })
  if ($sigN -eq $sigO) { return }
  $script:HomeScreen = $h
  if ($relayout -and $script:Relayout) { & $script:Relayout }
}
$script:CardVisible = {
  param($it)
  if (-not $script:HideInactiveCards -or -not $it.Ping) { return $true }
  $lo = $it.Ping.LastOk
  if ($lo -eq $true) { return $true }
  if ($null -eq $lo) { return [bool]$script:AliveMemo[[string]$it.Ping.PingHost] }
  return $false
}
$script:Relayout = {
  if (-not $form -or $form.IsDisposed -or -not $script:LayoutItems -or $script:LayoutItems.Count -eq 0) { return }
  $cardW = 240; $cardH = 105; $gap = 12; $x0 = 12; $y0 = 12; $titleH = 20
  $logH = [int]$script:UiLogH; if ($logH -le 0) { $logH = 96 }
  $hs = $script:HomeScreen
  $logOpen = ($script:LogBox -and -not $script:LogBox.IsDisposed -and $script:LogBox.Visible)
  $extraLog = $(if ($logOpen) { $logH + 8 } else { 0 })
  # --- place disponible : l'ecran d'accueil en entier, sinon la zone de travail de l'ecran de la fenetre
  $scr = $null
  if ($hs) { $availW = $hs.W; $availH = $hs.H }
  else {
    try { $scr = [System.Windows.Forms.Screen]::FromRectangle($form.Bounds) } catch { }
    if (-not $scr) { $scr = [System.Windows.Forms.Screen]::PrimaryScreen }
    $availW = $scr.WorkingArea.Width - 16; $availH = $scr.WorkingArea.Height - 16
  }
  # --- panneau du HAUT (carte des ecrans + sessions) : plein ecran = ~27 % de la hauteur, fenetre = 150 px
  $topH = 0
  if ($script:ShowTopPanel -and $script:TopMap -and -not $script:TopMap.IsDisposed) {
    $topH = $(if ($hs) { [int][Math]::Min(250, [Math]::Max(150, $availH * 0.27)) } else { 172 })
  }
  $yTop = $(if ($topH -gt 0) { $y0 + $topH + 10 } else { $y0 })    # debut de la zone des cartes (partie BASSE)
  $areaH = $availH - $yTop - 44 - $extraLog                       # hauteur utile pour titres + cartes
  $maxRows = [Math]::Max(1, [int][Math]::Floor(($areaH - $titleH + $gap) / ($cardH + $gap)))
  $maxCols = [Math]::Max(1, [int][Math]::Floor(($availW - 2 * $x0 + $gap) / ($cardW + $gap)))
  # --- segments : un groupe visible, coupe en tranches de $maxRows cartes
  $segs = @()
  foreach ($gname in @($script:UiGroupOrder)) {
    $items = @($script:LayoutItems | Where-Object { $_.Group -eq $gname -and (& $script:CardVisible $_) })
    if ($items.Count -eq 0) { continue }
    for ($i = 0; $i -lt $items.Count; $i += $maxRows) {
      $segs += [pscustomobject]@{ Group = $gname; Items = @($items[$i..([Math]::Min($i + $maxRows, $items.Count) - 1)]); Cont = ($i -gt 0) }
    }
  }
  if ($segs.Count -eq 0) { return }
  # --- repartition en colonnes : une par segment tant que la largeur le permet, sinon la plus courte
  $nCols = [Math]::Min($maxCols, $segs.Count)
  $colList = @()
  for ($c = 0; $c -lt $nCols; $c++) { $colList += [pscustomobject]@{ Segs = (New-Object System.Collections.ArrayList); H = 0 } }
  $si = 0
  foreach ($sg in $segs) {
    if ($segs.Count -le $maxCols) { $target = $colList[$si] }
    else {
      $target = $colList[0]
      foreach ($cl in $colList) { if ($cl.H -lt $target.H) { $target = $cl } }
    }
    [void]$target.Segs.Add($sg)
    $target.H += $titleH + $sg.Items.Count * ($cardH + $gap)
    $si++
  }
  $blockW = $nCols * $cardW + ($nCols - 1) * $gap
  if ($hs) { $W = $hs.W; $H = $hs.H } else { $W = [Math]::Max($blockW + 2 * $x0, 560) }
  $xOff = [int][Math]::Floor(($W - $blockW) / 2)
  if ($null -eq $script:UiTitleFont) { $script:UiTitleFont = New-Object System.Drawing.Font("Segoe UI", 9, ([System.Drawing.FontStyle]::Bold -bor [System.Drawing.FontStyle]::Italic)) }
  $form.SuspendLayout()
  # --- placement du panneau du haut : carte des ecrans (a gauche, proportionnelle) + liste (a droite)
  if ($script:TopMap -and -not $script:TopMap.IsDisposed) {
    if ($topH -gt 0) {
      $bandW = $W - 2 * $x0
      $scrs = @($script:Screens)
      $aspect = 2.4
      if ($scrs.Count -gt 0) {
        $mnX = ($scrs | ForEach-Object { $_.PX } | Measure-Object -Minimum).Minimum; $mxX = ($scrs | ForEach-Object { $_.PX + $_.PW } | Measure-Object -Maximum).Maximum
        $mnY = ($scrs | ForEach-Object { $_.PY } | Measure-Object -Minimum).Minimum; $mxY = ($scrs | ForEach-Object { $_.PY + $_.PH } | Measure-Object -Maximum).Maximum
        if (($mxY - $mnY) -gt 0) { $aspect = ($mxX - $mnX) / ($mxY - $mnY) }
      }
      $mapW = [int][Math]::Min($bandW * 0.62, [Math]::Max(240, ($topH - 8) * $aspect + 16))
      $script:TopMap.SetBounds($x0, $y0, $mapW, $topH)
      $script:TopList.SetBounds(($x0 + $mapW + $gap), $y0, ($bandW - $mapW - $gap), $topH)
      $script:TopMap.Visible = $true; $script:TopList.Visible = $true
    } else { $script:TopMap.Visible = $false; $script:TopList.Visible = $false }
  }
  $tp = 0; $maxY = $yTop
  for ($c = 0; $c -lt $nCols; $c++) {
    $x = [int]($xOff + $c * ($cardW + $gap)); $y = $yTop
    foreach ($sg in $colList[$c].Segs) {
      while ($script:UiTitlePool.Count -le $tp) {
        $lb = New-Object System.Windows.Forms.Label
        $lb.ForeColor = [System.Drawing.Color]::FromArgb(160, 160, 160); $lb.Font = $script:UiTitleFont
        $lb.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter; $lb.AutoSize = $false
        $lb.Size = New-Object System.Drawing.Size($cardW, ($titleH - 4)); $lb.BackColor = [System.Drawing.Color]::Transparent
        $form.Controls.Add($lb); $script:UiTitlePool += $lb
      }
      $lb = $script:UiTitlePool[$tp]; $tp++
      $gt = $script:GroupTitles[[string]$sg.Group]; if (-not $gt) { $gt = [string]$sg.Group }
      $lb.Text = $gt.ToUpper() + $(if ($sg.Cont) { " (suite)" } else { "" })
      $lb.Location = New-Object System.Drawing.Point($x, $y); $lb.Visible = $true
      $y += $titleH
      foreach ($it in $sg.Items) {
        $it.Card.Location = New-Object System.Drawing.Point($x, $y)
        $it.Card.Visible = $true      # (affectation systematique : avant l'affichage de la fenetre, le getter Visible renvoie toujours $false)
        $y += $cardH + $gap
      }
    }
    if ($y -gt $maxY) { $maxY = $y }
  }
  for ($k = $tp; $k -lt $script:UiTitlePool.Count; $k++) { $script:UiTitlePool[$k].Visible = $false }
  foreach ($it in $script:LayoutItems) { if (-not (& $script:CardVisible $it)) { $it.Card.Visible = $false } }
  if (-not $hs) { $H = ($maxY - $gap) + 44 + $extraLog }
  # --- pied de page (calcule sur la taille de la fenetre)
  $btnY = [int]($H - 36)
  $btnW = [int](($W - 24 - 110 - 30 - 12) / 2)
  if ($script:UiBtnDeploy) { $script:UiBtnDeploy.Location = New-Object System.Drawing.Point($x0, $btnY); $script:UiBtnDeploy.Size = New-Object System.Drawing.Size($btnW, 24) }
  if ($script:UiBtnSync) { $script:UiBtnSync.Location = New-Object System.Drawing.Point(($x0 + $btnW + 6), $btnY); $script:UiBtnSync.Size = New-Object System.Drawing.Size($btnW, 24) }
  if ($script:UiBtnLog) { $script:UiBtnLog.Location = New-Object System.Drawing.Point(($W - 12 - 110 - 24 - 6), $btnY) }
  if ($script:UiBtnQuit) { $script:UiBtnQuit.Location = New-Object System.Drawing.Point(($W - 12 - 110), $btnY) }
  if ($script:LogBox -and -not $script:LogBox.IsDisposed) {
    $script:LogBox.Location = New-Object System.Drawing.Point($x0, [int]($btnY - $logH - 8))
    $script:LogBox.Size = New-Object System.Drawing.Size(($W - 24), $logH)
  }
  # --- fenetre : plein ecran sur l'ecran d'accueil, sinon taille du contenu
  if ($hs) {
    $form.StartPosition = 'Manual'
    $form.Bounds = New-Object System.Drawing.Rectangle($hs.X, $hs.Y, $hs.W, $hs.H)
    $script:UiFullscreen = $true
  } else {
    $wasFull = $script:UiFullscreen; $script:UiFullscreen = $false
    $form.ClientSize = New-Object System.Drawing.Size($W, $H)
    if (-not $form.Visible) { $form.StartPosition = 'CenterScreen' }
    else {
      $wa = $scr.WorkingArea
      if ($wasFull) {
        $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $form.Location = New-Object System.Drawing.Point(([int]($wa.Left + ($wa.Width - $form.Width) / 2)), ([int]($wa.Top + ($wa.Height - $form.Height) / 2)))
      } else {
        $nx = $form.Left; $ny = $form.Top
        if ($form.Bottom -gt $wa.Bottom) { $ny = [Math]::Max($wa.Top, $wa.Bottom - $form.Height) }
        if ($form.Right -gt $wa.Right) { $nx = [Math]::Max($wa.Left, $wa.Right - $form.Width) }
        if ($nx -ne $form.Left -or $ny -ne $form.Top) { $form.Location = New-Object System.Drawing.Point($nx, $ny) }
      }
    }
  }
  $form.ResumeLayout()
  $form.Invalidate()
  $modeNow = $(if ($hs) { "plein ecran sur " + $hs.Name + " (" + $hs.W + "x" + $hs.H + ")" } else { "fenetre" })
  if ($script:LayoutMode -ne $modeNow -and $script:LogFn) {
    $script:LayoutMode = $modeNow
    & $script:LogFn ("disposition : " + $modeNow + $(if ($hs) { " [ecran non PnP spacedesk]" } else { " (ecran spacedesk non PnP absent)" }) + " ; " + $nCols + " colonne(s), " + $maxRows + " ligne(s) max")
  }
}
