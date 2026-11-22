# ui-80-pied-de-page.ps1 - BuildUI : boutons du pied de page
# Fichier charge par vsc_launcher.ps1 (dot-source : meme portee script). Lignes d'origine 4642-4759.

# ---------- Boutons pied de page ----------
# (positionnes pour la fenetre SANS log : le log est ferme a l'initialisation ;
#  le clic sur la fleche decale toute la rangee vers le bas)
$btnY = [int]($winHc - 36)

$btnDeploy = New-Object System.Windows.Forms.Button
$btnDeploy.Text = "Déployer les couleurs sur toutes les machines"
$btnDeploy.Location = New-Object System.Drawing.Point($x0, $btnY)
# LARGEURS EGALES : place disponible = fenetre - marges (24) - "Fermer" (110) - fleche log (30)
# - ecarts (6 entre les 2 boutons + 6 avant la fleche) ; chaque bouton prend la moitie
# (l'ancien bouton de synchro, fixe a 204 px, coupait son texte "...Zoo Co")
$btnW = [int](($winW - 24 - 110 - 30 - 12) / 2)
$btnDeploy.Size = New-Object System.Drawing.Size($btnW, 24)
$btnDeploy.BackColor = [System.Drawing.Color]::FromArgb(38,38,38)
$btnDeploy.ForeColor = [System.Drawing.Color]::White
$btnDeploy.FlatStyle = "Flat"
$btnDeploy.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$btnDeploy.Add_Click({
  # le deploiement bloque l'IHM quelques secondes par hote : on vide puis remplit le log
  & $script:LogFn "=== deploiement des couleurs (chaque hote peut prendre ~8 s si eteint) ==="
  [System.Windows.Forms.Application]::DoEvents()
  & $script:DeployColors
  [System.Windows.Forms.Application]::DoEvents()
})
$form.Controls.Add($btnDeploy)

$btnSync = New-Object System.Windows.Forms.Button
$btnSync.Text = "Synchroniser les conversations Zoo Code"
$btnSync.Location = New-Object System.Drawing.Point(($x0 + $btnW + 6), $btnY)
$btnSync.Size = New-Object System.Drawing.Size($btnW, 24)   # termine a 6 px de la fleche log
$btnSync.BackColor = [System.Drawing.Color]::FromArgb(20,60,60)
$btnSync.ForeColor = [System.Drawing.Color]::White
$btnSync.FlatStyle = "Flat"
$btnSync.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$script:ZooSyncJob = $null
$script:SyncTimer = $null
$btnSync.Add_Click({
  if ($script:ZooSyncJob) {
    $st0 = $script:ZooSyncJob.State
    if ($st0 -eq 'Running' -or $st0 -eq 'Queued' -or $st0 -eq 'Starting') {
      & $script:LogFn "sync zoo-code : DEJA EN COURS en tache de fond (le panneau reste utilisable)"
      return
    }
    # job termine mais pas encore nettoye : le nettoyage est fait ici au clic
    Remove-Job $script:ZooSyncJob -Force -ErrorAction SilentlyContinue
    $script:ZooSyncJob = $null
  }
  $syncMachs = @($Machines | Where-Object { $_.Host } | ForEach-Object {
    [pscustomobject]@{ Host = $_.Host; HostName = $_.HostName; User = $_.User; Port = $_.Port; IdentityFile = $_.IdentityFile; Label = $_.Label }
  })
  if ($syncMachs.Count -eq 0) { & $script:LogFn "sync zoo-code : aucune machine SSH -> rien a synchroniser"; return }
  & $script:LogFn ("=== synchronisation Zoo Code en TACHE DE FOND : " + $syncMachs.Count + " machine(s) - le panneau reste reactif, progression ci-dessous ===")
  $btnSync.Enabled = $false
  try {
    # PAS de (,...) devant $syncMachs : -ArgumentList preserve deja chaque
    # tableau comme argument unique (cf. scan LAN). La virgule aurait
    # double-emballé le tableau -> foreach sur UN seul element = le tableau
    # entier -> proprietes concatenees en tableau ("Bad port ' 22001 22 22'").
    $script:ZooSyncJob = Start-Job -ScriptBlock $script:SyncJobBlock -ArgumentList $syncMachs, $script:LocalTasks, $script:WsRoot, $script:WsMaxMb, $script:WsExcludes
  } catch {
    & $script:LogFn ("sync zoo-code : Start-Job IMPOSSIBLE -> " + $_.Exception.Message)
    $script:ZooSyncJob = $null
    try { $btnSync.Enabled = $true } catch { }
    return
  }
  if (-not $script:ZooSyncJob) {
    & $script:LogFn "sync zoo-code : Start-Job n'a rien retourne (service des jobs PowerShell desactive ?)"
    try { $btnSync.Enabled = $true } catch { }
    return
  }
  # TIMER EN PORTEE $script: : un handler Add_Tick s'execute PLUS TARD, quand la
  # portee locale du clic est morte -> $syncTimer local serait null au 1er tick
  # (erreur "InvokeMethodOnNull" constatee). En $script:, il survit au clic.
  $script:SyncTimer = New-Object System.Windows.Forms.Timer
  $script:SyncTimer.Interval = 1000
  $script:SyncTimer.Add_Tick({
    $job = $script:ZooSyncJob
    if (-not $job) {
      # job deja nettoye ailleurs : on coupe le timer sans erreur
      try { $script:SyncTimer.Stop(); $script:SyncTimer.Dispose() } catch { }
      try { $btnSync.Enabled = $true } catch { }
      return
    }
    # Receive-Job sur un job EN COURS rend ce qui a deja ete ecrit -> log en direct
    try { $lines = @(Receive-Job $job -ErrorAction SilentlyContinue) } catch { $lines = @() }
    foreach ($ln in $lines) { if ($null -ne $ln -and ("$ln").Trim()) { & $script:LogFn ("sync: " + $ln) } }
    $st = $job.State
    if ($st -eq 'Running' -or $st -eq 'Queued' -or $st -eq 'Starting') { return }
    if ($st -ne 'Completed') {
      & $script:LogFn ("sync zoo-code : job en ECHEC (" + $st + ")")
      try {
        $cj = $job.ChildJobs[0].JobStateInfo.Reason
        if ($cj) { & $script:LogFn ("  motif : " + $cj.Exception.Message) }
      } catch { }
    }
    & $script:LogFn ("sync zoo-code TERMINEE (statut " + $st + ") - Reload Window dans le VSC local pour voir l'historique ; dossiers de dev dans " + $script:WsRoot)
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    $script:ZooSyncJob = $null
    try { $script:SyncTimer.Stop(); $script:SyncTimer.Dispose() } catch { }
    $script:SyncTimer = $null
    try { $btnSync.Enabled = $true } catch { }
  })
  $script:SyncTimer.Start()
})
$form.Controls.Add($btnSync)

$btnQuit = New-Object System.Windows.Forms.Button
$btnQuit.Text = "Fermer"
$btnQuit.Location = New-Object System.Drawing.Point(($winW - 12 - 110), $btnY)
$btnQuit.Size = New-Object System.Drawing.Size(110, 24)
$btnQuit.BackColor = [System.Drawing.Color]::FromArgb(120,30,30)
$btnQuit.ForeColor = [System.Drawing.Color]::White
$btnQuit.FlatStyle = "Flat"
$btnQuit.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$btnQuit.Add_Click({ $this.Parent.Close() })
$form.Controls.Add($btnQuit)
$script:UiBtnDeploy = $btnDeploy; $script:UiBtnSync = $btnSync; $script:UiBtnQuit = $btnQuit

