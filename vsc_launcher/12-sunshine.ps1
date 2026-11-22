# 12-sunshine.ps1 - Sondage Sunshine (machines Linux) et icone Moonlight
# Fichier charge par vsc_launcher.ps1 (dot-source : meme portee script). Lignes d'origine 2086-2158.

# ---------- SUNSHINE (machines Linux) ----------
# Sunshine (serveur de streaming Linux, base d'Apollo) ouvre les memes ports que sur Windows :
#   47989 (HTTP, appairage + etat)  47984 (HTTPS)  47990 (interface web, TCP)  48010 (RTSP).
# Moonlight a besoin de 47989 ET 47984 ; 47990 / 48010 sont releves pour le diagnostic.
# Chaque carte Linux joignable est sondee toutes les 30 s (connexions TCP asynchrones, 4 ports a la fois).
# Resultat : l'icone Moonlight apparait sur la carte quand Sunshine repond (attenuee si l'hote n'est
# pas encore appaire dans Moonlight), avec le detail des ports en info-bulle et dans le journal.
$script:SunshinePorts = @(47989, 47984, 47990, 48010)
$script:NoRdp = @{}              # adresses sans repli RDP (machines Linux : pas de mstsc)
# Icone Moonlight + pastille d'etat, partagee par les cartes Windows (Apollo) et Linux (Sunshine).
# Pastille SANS vert/rouge (daltonisme) : session operationnelle = disque PLEIN bleu clair ;
# en connexion = anneau VIDE orange (la forme change, pas seulement la couleur).
$script:PaintMlIcon = {
  param($g, $s)
  $mlS = $script:MlState[$s.RdpIp]
  # SOMBRE tant qu'aucune session n'est active (Windows comme Linux) ; couleur = en connexion / operationnelle
  $active = [bool]($mlS -and ($mlS.State -eq 'live' -or $mlS.State -eq 'connecting'))
  $img = $(if ($active) { $script:MlIcon20 } elseif ($script:MlIcon20Dim) { $script:MlIcon20Dim } else { $script:MlIcon20 })
  if ($img) { $g.DrawImage($img, 0, 0, 20, 20) }
  # hote Sunshine detecte mais pas encore appaire dans Moonlight : "?" orange (forme, pas seulement couleur)
  if ($s.Unpaired) {
    $fq = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $bq = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(230, 159, 0))
    $g.DrawString("?", $fq, $bq, [single]11, [single]6); $fq.Dispose(); $bq.Dispose()
  }
  if ($mlS -and ($mlS.State -eq 'live' -or $mlS.State -eq 'connecting')) {
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    if ($mlS.State -eq 'live') {
      $bb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(86, 180, 233)); $bw = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 1.5)
      $g.FillEllipse($bb, 11, 11, 8, 8); $g.DrawEllipse($bw, 11, 11, 8, 8)
    } else {
      $bb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(20, 20, 20)); $bw = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(230, 159, 0), 2)
      $g.FillEllipse($bb, 11, 11, 8, 8); $g.DrawEllipse($bw, 11, 11, 8, 8)
    }
    $bb.Dispose(); $bw.Dispose()
  }
}
# Applique le resultat d'une sonde Sunshine a la carte Linux $c ($open : port -> ouvert ?, $ipSeen : IP reelle jointe)
$script:SunMemo = @{}            # dernier resultat de sonde par machine : survit a la reconstruction de l'affichage
$script:SunshineApply = {
  param($c, $open, $ipSeen, [bool]$quiet = $false)
  $script:SunMemo[[string]$c.PingHost] = @{ Open = $open; IpSeen = $ipSeen }
  $ready = [bool]($open[47989] -and $open[47984])
  $any = [bool]($open[47989] -or $open[47984] -or $open[47990] -or $open[48010])
  $state = $(if ($ready) { 'ready' } elseif ($any) { 'partial' } else { 'none' })
  $detail = (@($script:SunshinePorts | ForEach-Object { "" + $_ + $(if ($open[[int]$_]) { " ouvert" } else { " ferme" }) }) -join ', ')
  # adresse sous laquelle Moonlight connait (ou connaitra) l'hote : le nom du .ssh/config, sinon l'IP reellement jointe
  $addr = [string]$c.PingHost; $paired = $false
  if ($ready) {
    $mh = & $script:GetMoonlightHost $addr
    if ($mh.Paired) { $paired = $true }
    elseif ($ipSeen) { $mh2 = & $script:GetMoonlightHost $ipSeen; if ($mh2.Paired) { $paired = $true; $addr = [string]$ipSeen } }
  }
  if ($c.SunState -ne $state -and -not $quiet) {
    & $script:LogFn ("Sunshine: " + $c.Alias + " (" + $c.PingHost + $(if ($ipSeen -and $ipSeen -ne $c.PingHost) { " = " + $ipSeen }) + ") : " + $detail + " -> " + $(if ($ready) { "Sunshine DETECTE" } elseif ($any) { "ports Sunshine partiels (Moonlight a besoin de 47989 et 47984)" } else { "pas de Sunshine" }))
  }
  if ($ready -and $c.SunPaired -ne $paired -and $null -ne $c.SunPaired -and -not $quiet) {
    & $script:LogFn ("Sunshine: " + $c.Alias + " : " + $(if ($paired) { "hote APPAIRE dans Moonlight" } else { "hote NON appaire dans Moonlight (ajouter l'hote dans Moonlight puis saisir le PIN sur https://" + $c.PingHost + ":47990)" }))
  }
  $c.SunState = $state; $c.SunPaired = $paired; $c.SunAddr = $addr; $c.SunOpen = $open
  if ($ready) { $script:NoRdp[$addr] = $true; $script:NoRdp[[string]$c.PingHost] = $true }
  if ($c.Ml) {
    $show = [bool]($ready -and $script:MoonlightExe)
    $c.Ml.RdpIp = $addr
    $c.Ml.Unpaired = (-not $paired)
    $c.Ml.TipText = "Sunshine détecté sur " + $c.Alias + " : " + $detail + $(if ($paired) { "`nOuvrir Moonlight" } else { "`nHôte NON appairé dans Moonlight : ajoutez-le dans Moonlight, puis saisissez le PIN sur https://" + $c.PingHost + ":47990" })
    if ($c.SunShown -ne $show) {
      $c.Ml.Visible = $show; $c.SunShown = $show
      if (-not $quiet) { & $script:LogFn ("Sunshine: " + $c.Alias + " -> icone Moonlight " + $(if ($show) { "affichee" } else { "masquee" }) + $(if ($show -and -not $paired) { " (attenuee : non appaire)" })) }
    }
    try { $c.Ml.Invalidate() } catch { }
  }
}
