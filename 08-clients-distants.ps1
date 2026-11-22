# 08-clients-distants.ps1 - Detection des clients distants deja ouverts (Moonlight/mstsc)
# Fichier charge par vsc_launcher.ps1 (dot-source : meme portee script). Lignes d'origine 1242-1382.

# ---------- CLIENTS DISTANTS DEJA OUVERTS (scan au demarrage puis toutes les 15 s) ----------
# Ecrans reellement couverts par les fenetres d'un processus : un ecran compte s'il est couvert
# a 30 % au moins par une fenetre, ou s'il contient plus de la moitie de cette fenetre.
$script:ScreensOfPid = {
  param([int]$procId)
  $idxs = @()
  try {
    foreach ($w in [VscScrV3]::GetProcessWindows($procId)) {
      $l = [int]$w[1]; $t = [int]$w[2]; $r = [int]$w[3]; $b = [int]$w[4]
      $wa = [double](($r - $l) * ($b - $t)); if ($wa -le 0) { continue }
      foreach ($s in $script:Screens) {
        $ix = [Math]::Max(0, [Math]::Min($r, $s.X + $s.W) - [Math]::Max($l, $s.X))
        $iy = [Math]::Max(0, [Math]::Min($b, $s.Y + $s.H) - [Math]::Max($t, $s.Y))
        $ia = [double]($ix * $iy)
        if ($ia -le 0) { continue }
        if (($ia / ($s.W * $s.H)) -ge 0.3 -or ($ia / $wa) -gt 0.5) { if ($idxs -notcontains $s.Idx) { $idxs += $s.Idx } }
      }
    }
  } catch { }
  return ,@($idxs | Sort-Object)
}
# Carte correspondant a un nom d'hote ou une IP (ligne de commande Moonlight / mstsc)
$script:CardIpFor = {
  param([string]$hostTxt)
  if (-not $hostTxt) { return $null }
  foreach ($c in @($script:CardList)) {
    if (-not $c.Map -and -not $c.IsLinux) { continue }
    if ($c.PingHost -eq $hostTxt -or $c.Alias -eq $hostTxt -or $c.Label -eq $hostTxt -or ($c.SunAddr -and $c.SunAddr -eq $hostTxt)) {
      if ($c.IsLinux -and $c.SunAddr) { return $c.SunAddr }      # adresse sous laquelle Moonlight connait l'hote
      return $c.PingHost
    }
  }
  return $null
}
# Moonlight et mstsc deja lances (a la main, par une instance precedente du launcher...) :
# rattaches a leur machine et a leurs ecrans pour afficher les bons logos sur les mini-cartes.
#   Moonlight : machine = argument "stream <hote>" de la ligne de commande, sinon derniere requete
#               du journal Moonlight-<demarrage>.log du processus ; etat = OPERATIONNEL si la
#               fenetre du flux existe, sinon "en connexion". Sa fermeture -> ecrans grises.
#   mstsc     : machine = "/v:<ip>" ou fichier .rdp (le notre <ip>.rdp, ou "full address" lu dedans).
# Les ecrans sont ceux que couvre REELLEMENT la fenetre ; a defaut, la selection memorisee.
$script:MlAdopted = @{}
$script:ScanRemoteClients = {
  param([bool]$initial = $false)
  if (-not $script:CardList) { return }
  $found = 0
  # --- Moonlight
  try {
    $mlName = [IO.Path]::GetFileNameWithoutExtension([string]$script:MoonlightExe)
    if (-not $mlName) { $mlName = 'Moonlight' }
    $mps = @(Get-Process -Name $mlName -ErrorAction SilentlyContinue)
    if ($mps.Count -gt 0) {
      $cim = @(Get-CimInstance Win32_Process -Filter ("Name='" + $mlName + ".exe'") -ErrorAction SilentlyContinue)
      foreach ($p in $mps) {
        $cl = [string](@($cim | Where-Object { $_.ProcessId -eq $p.Id }) | Select-Object -First 1).CommandLine
        $hostTxt = $null
        $mm = [regex]::Match($cl, '\sstream\s+"?([^"\s]+)"?')
        if ($mm.Success) { $hostTxt = $mm.Groups[1].Value }
        $ip = & $script:CardIpFor $hostTxt
        if (-not $ip) {
          # lance depuis l'interface de Moonlight : journal de CE processus (nom = heure de demarrage)
          try {
            $ep = [long](($p.StartTime.ToUniversalTime() - [datetime]'1970-01-01').TotalSeconds)
            $lf = @(Get-ChildItem $script:MoonlightLogDir -Filter 'Moonlight-*.log' -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match '^Moonlight-(\d+)\.log$' -and [Math]::Abs([long]$Matches[1] - $ep) -le 5 }) | Select-Object -First 1
            if ($lf) {
              $hits = [regex]::Matches([System.IO.File]::ReadAllText($lf.FullName), 'Executing request: "https://([0-9\.]+):\d+/(launch|resume)')
              if ($hits.Count -gt 0) { $ip = & $script:CardIpFor $hits[$hits.Count - 1].Groups[1].Value }
            }
          } catch { }
        }
        if (-not $ip) { continue }
        $cur = $script:MlState[$ip]
        $tracked = ($script:RetryTimer -and $script:RetryTimer.Tag -and $script:RetryTimer.Tag.ContainsKey($ip))
        if ($tracked) { continue }                                  # lance par CE launcher : deja suivi
        $live = $false
        foreach ($ttl in [VscScrV3]::WindowTitles($p.Id)) { if ($ttl -match $script:MoonlightStreamTitle) { $live = $true; break } }
        # ecrans FIGES une fois la session connue : si Windows retrecit la fenetre (changement de
        # config des ecrans), la place prevue ne doit pas suivre (GuardWindows la remet en place)
        if ($cur -and @($cur.Idxs).Count -gt 0 -and ($cur.State -eq 'live' -or $cur.State -eq 'connecting')) { $idxs = @($cur.Idxs) }
        else { $idxs = & $script:ScreensOfPid $p.Id }
        if ($idxs.Count -eq 0 -and $cur) { $idxs = @($cur.Idxs) }
        if ($idxs.Count -eq 0) { $sx = & $script:ResolveSelection $ip @(); if ($sx) { $idxs = @($sx.Idxs) } }
        $state = $(if ($live) { 'live' } else { 'connecting' })
        $changed = (-not $cur) -or $cur.State -ne $state -or (($cur.Idxs -join '+') -ne ($idxs -join '+'))
        if (-not $script:MlAdopted.ContainsKey($ip)) {
          $script:MlAdopted[$ip] = $p
          & $script:LogFn ("Moonlight deja ouvert detecte : " + $ip + " (PID " + $p.Id + ", ecrans " + ($idxs -join '+') + ")")
        }
        if ($changed) { & $script:SetMlState $ip $state $idxs $null "processus deja ouvert" }
        $found++
      }
    }
    # Moonlight adopte qui s'est ferme : ecrans grises
    foreach ($k in @($script:MlAdopted.Keys)) {
      $ap = $script:MlAdopted[$k]; $gone = $true
      try { $gone = $ap.HasExited } catch { }
      if ($gone) {
        $script:MlAdopted.Remove($k)
        $cur = $script:MlState[$k]
        & $script:SetMlState $k 'none' $(if ($cur) { @($cur.Idxs) } else { @() }) $null "processus deja ouvert, ferme"
        & $script:LogFn ("Moonlight " + $k + " : session ouverte avant le launcher fermee -> retiree de l'affichage")
      }
    }
  } catch { }
  # --- mstsc
  try {
    $mp = @(Get-Process -Name mstsc -ErrorAction SilentlyContinue)
    if ($mp.Count -gt 0) {
      $cmds = @(Get-CimInstance Win32_Process -Filter "Name='mstsc.exe'" -ErrorAction SilentlyContinue)
      foreach ($cm in $cmds) {
        $cl = [string]$cm.CommandLine; if (-not $cl) { continue }
        $hostTxt = $null
        $mv = [regex]::Match($cl, '/v:\s*"?([^"\s:]+)')
        if ($mv.Success) { $hostTxt = $mv.Groups[1].Value }
        else {
          $mf = [regex]::Match($cl, '"([^"]+\.rdp)"|(\S+\.rdp)')
          if ($mf.Success) {
            $rf = $(if ($mf.Groups[1].Success) { $mf.Groups[1].Value } else { $mf.Groups[2].Value })
            try { $fa = [regex]::Match([System.IO.File]::ReadAllText($rf), 'full address:s:([^\r\n:]+)'); if ($fa.Success) { $hostTxt = $fa.Groups[1].Value.Trim() } } catch { }
            if (-not $hostTxt) { $hostTxt = [IO.Path]::GetFileNameWithoutExtension($rf) }
          }
        }
        $ip = & $script:CardIpFor $hostTxt
        if (-not $ip) { continue }
        $idxs = & $script:ScreensOfPid ([int]$cm.ProcessId)
        $cur = $script:RdpState[$ip]
        if ($idxs.Count -eq 0 -and $cur) { $idxs = @($cur.Idxs) }
        if ($idxs.Count -eq 0) { $sx = & $script:ResolveSelection $ip @(); if ($sx) { $idxs = @($sx.Idxs) } }
        if (-not $cur -or -not $cur.Proc -or $cur.Proc.Id -ne [int]$cm.ProcessId -or (($cur.Idxs -join '+') -ne ($idxs -join '+'))) {
          $pr = $null; try { $pr = Get-Process -Id $cm.ProcessId -ErrorAction Stop } catch { }
          $script:RdpState[$ip] = [pscustomobject]@{ Idxs = $idxs; Proc = $pr; Since = $(if ($cur) { $cur.Since } elseif ($pr) { $pr.StartTime } else { Get-Date }) }
          & $script:LogFn ("Etat mstsc " + $ip + " : session " + $(if ($cur) { "mise a jour" } else { "detectee" }) + " (PID " + $cm.ProcessId + ", ecrans " + ($idxs -join '+') + ")")
          if ($script:RefreshTop) { & $script:RefreshTop }
        }
        $found++
      }
    }
  } catch { }
  if ($initial) { & $script:LogFn ("demarrage : scan des clients distants -> " + $found + " session(s) Moonlight/mstsc deja ouverte(s)") }
}
