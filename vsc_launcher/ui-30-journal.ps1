# ui-30-journal.ps1 - BuildUI : zone de log et bouton fleche
# Fichier charge par vsc_launcher.ps1 (dot-source : meme portee script). Lignes d'origine 2613-2705.

# ---------- Zone de log (actions executees + diagnostics) ----------
$btnY = [int]($winHc - 36)

# fleche d'ouverture/fermeture du log : dans la rangee de boutons, a gauche de "Fermer"
$btnLogToggle = New-Object System.Windows.Forms.Button
# police MARLETT (Windows) : "6" = fleche vers le BAS, "5" = fleche vers le HAUT
$btnLogToggle.Text = "5"                 # log ferme au depart -> fleche vers le haut
$btnLogToggle.Size = New-Object System.Drawing.Size(24, 24)
$btnLogToggle.Location = New-Object System.Drawing.Point(($winW - 12 - 110 - 24 - 6), $btnY)
$btnLogToggle.BackColor = [System.Drawing.Color]::FromArgb(38,38,38)
$btnLogToggle.ForeColor = [System.Drawing.Color]::White
$btnLogToggle.FlatStyle = "Flat"
$btnLogToggle.Font = New-Object System.Drawing.Font("Marlett", 9)
$form.Controls.Add($btnLogToggle)

$script:LogBox = New-Object System.Windows.Forms.TextBox
# Le LogBox est RECREA a chaque construction de l'IHM (rechargement apres scan) :
# sans tampon, tout le log precedent serait perdu. $script:LogBuffer conserve
# toutes les lignes du processus ; la nouvelle zone de log est repeuplee avec.
if (-not $script:LogBuffer) { $script:LogBuffer = New-Object System.Collections.ArrayList }
if ($script:LogBuffer.Count -gt 0) {
  $script:LogBox.Text = ($script:LogBuffer -join "`r`n")
  $script:LogBox.SelectionStart = $script:LogBox.TextLength
  $script:LogBox.ScrollToCaret()
}
# place du log quand il est OUVERT : a l'endroit exact ou etaient les boutons
# (winHc-36), les boutons etant decales de logH+8 vers le bas -> log entre les
# cartes (fin ~winHc-44) et les boutons ouverts (winHc+68).
$script:LogBox.Location = New-Object System.Drawing.Point($x0, [int]($winHc - 36))
$script:LogBox.Size = New-Object System.Drawing.Size(($winW - 24), $logH)
$script:LogBox.Multiline = $true
$script:LogBox.ReadOnly = $true
$script:LogBox.ScrollBars = "Vertical"
$script:LogBox.BackColor = [System.Drawing.Color]::FromArgb(12,12,12)
$script:LogBox.ForeColor = [System.Drawing.Color]::FromArgb(180,230,180)
$script:LogBox.Font = New-Object System.Drawing.Font("Consolas", 8)
# log ferme au 1er lancement ; lors d'une reconstruction, on conserve son etat
$script:LogBox.Visible = $(if ($script:Rebuild) { [bool]$script:PrevLogVisible } else { $false })
$form.Controls.Add($script:LogBox)

$script:UiBtnLog = $btnLogToggle
# panneau du HAUT : carte des ecrans (selecteur global) + sessions distantes (positionne par Relayout)
& $script:BuildTopPanel
$btnLogToggle.Add_Click({
  # ouvrir/fermer le log : $script:Relayout recalcule TOUT (fenetre ajustee ou, en plein ecran,
  # place reservee au journal en bas ; rangee de boutons repositionnee)
  if ($script:LogBox.Visible) {
    $script:LogBox.Visible = $false
    $this.Text = "5"                     # Marlett : fleche vers le HAUT = rouvrir
  } else {
    $script:LogBox.Visible = $true
    $this.Text = "6"                     # Marlett : fleche vers le BAS = fermer
  }
  & $script:Relayout
})

$script:LogFn = {
  param($msg)
  $stamp = (Get-Date).ToString("HH:mm:ss")
  $line = "[$stamp] $msg"
  # 1) tampon du processus (survit au rechargement de l'IHM)
  if (-not $script:LogBuffer) { $script:LogBuffer = New-Object System.Collections.ArrayList }
  [void]$script:LogBuffer.Add($line)
  if ($script:LogBuffer.Count -gt 400) { $script:LogBuffer.RemoveAt(0) }
  # 2) zone de log de la fenetre EN COURS (peut etre en train d'etre detruite
  # pendant un rechargement -> try/catch)
  try {
    if ($script:LogBox -and -not $script:LogBox.IsDisposed) {
      $script:LogBox.AppendText($line + "`r`n")
      $script:LogBox.SelectionStart = $script:LogBox.TextLength
      $script:LogBox.ScrollToCaret()
    }
  } catch { }
  # 3) journal sur disque : consultable meme apres fermeture du launcher
  try {
    $logFile = Join-Path $env:LOCALAPPDATA "vsc-launcher\launcher.log"
    $ld = Split-Path $logFile -Parent
    if (-not (Test-Path $ld)) { New-Item -ItemType Directory -Path $ld -Force | Out-Null }
    [System.IO.File]::AppendAllText($logFile, $line + "`r`n")
  } catch { }
}
& $script:LogFn ("Launcher demarre - " + $Machines.Count + " cartes, config SSH: " + $sshConfig)
if (-not $script:CodeExe) { & $script:LogFn "ERREUR: commande 'code' introuvable dans le PATH" }
if ($script:VncViewerExe) {
  & $script:LogFn ("client VNC trouve: " + $script:VncViewerExe + $(if ($script:VncIconBmp) { " (icone extraite)" }))
} else {
  & $script:LogFn "AVERTISSEMENT: aucun client VNC trouve (TurboVNC/RealVNC/vncviewer dans le PATH) -> repli protocole vnc://"
}
foreach ($ba in $script:BadAliases) {
  & $script:LogFn ("ATTENTION: alias '" + $ba + "' contient '@' -> VS Code l'interprete comme user@hote. Renommer dans .ssh/config (ex: '" + ($ba -replace '@', '_') + "')")
}
foreach ($n in $script:StartupNotes) { & $script:LogFn $n }

