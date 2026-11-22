# ui-20-fenetre.ps1 - BuildUI : creation unique de la fenetre / liberation des controles
# Fichier charge par vsc_launcher.ps1 (dot-source : meme portee script). Lignes d'origine 2583-2612.

# ---------- Fenetre : creee UNE SEULE FOIS ----------
# La reconstruction apres scan ne detruit plus la fenetre : elle se reconsiderait
# ailleurs a l'ecran (StartPosition=CenterScreen) et clignotait. Seuls les
# controles (et leurs objets GDI+) sont liberes puis recres : la fenetre, sa
# position et sa taille restent identiques.
$script:Rebuild = ($null -ne $form)
if (-not $script:Rebuild) {
  $form = New-Object System.Windows.Forms.Form
  $form.Text = ""
  $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
  $form.BackColor = [System.Drawing.Color]::FromArgb(24,24,24)
  $form.StartPosition = "CenterScreen"
  $form.Topmost = $true
} else {
  # etat du log avant destruction, pour le retablir a l'identique apres rebuild
  $script:PrevLogVisible = $script:LogBox.Visible
  foreach ($oldCtl in @($form.Controls)) {
    [void]$form.Controls.Remove($oldCtl)
    # filigrane pre-rendu de la carte : Control.Dispose ne libere PAS le
    # BackgroundImage -> liberation explicite (les icones partagees en
    # $script:Ico* sont conservees, elles servent aux nouvelles cartes)
    try {
      if ($oldCtl.BackgroundImage) { $bi = $oldCtl.BackgroundImage; $oldCtl.BackgroundImage = $null; $bi.Dispose() }
    } catch { }
    try { $oldCtl.Dispose() } catch { }   # libere les objets GDI associes
  }
  $form.SuspendLayout()
}
$form.ClientSize = New-Object System.Drawing.Size($winW, $winHc)   # log FERMEE au depart

