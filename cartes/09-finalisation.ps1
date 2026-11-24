# cartes\09-finalisation.ps1 - Ajout des controles, z-order, info-bulles, enregistrement pour les watchdogs
# Corps de la boucle 'foreach ($m in $MachinesOrd)' de ui-50-cartes.ps1 (dot-source par carte). Lignes d'origine du fichier ui-50 : 956-1005.

  $card.Controls.AddRange(@($lblLabel, $lblUser, $icoUser, $lblRole, $dot, $lblSess, $logoVsc, $icoVnc, $icoSsh))
  if ($icoMap) { $card.Controls.AddRange(@($icoMap, $icoMl, $icoRdp)) }
  # Z-ORDER : l'icone DOIT etre AU-DESSUS du label user (le fond Transparent d'un
  # label ne laisse pas voir les freres derriere lui, seulement le fond parent)
  $icoUser.BringToFront()
  $form.Controls.Add($card)

  # info-bulles des icones (survol 0,4 s)
  $script:Tip.SetToolTip($logoVsc, $(if ($m.Host) { "VS Code (SSH) : ouvrir ou ramener la fenêtre" } else { "VS Code local : ouvrir ou ramener la fenêtre" }))
  $script:Tip.SetToolTip($icoVnc, "Bureau distant VNC")
  $script:Tip.SetToolTip($icoSsh, "Terminal SSH")

  # polices du titre : normale / barree (carte injoignable, voir PingCollect)
  $fontStrike = New-Object System.Drawing.Font($lblLabel.Font, ([System.Drawing.FontStyle]::Bold -bor [System.Drawing.FontStyle]::Strikeout))

  # enregistrer pour le watchdog (joignabilite) et le suivi "fenetre deja ouverte"
  if ($m.Host -or $m.RdpIp) {
    $entry = [pscustomobject]@{
      Card = $card; Dot = $dot; Logo = $logoVsc; Vnc = $icoVnc; Ssh = $icoSsh
      # style "injoignable" : labels a griser + polices/couleurs d'origine a restaurer
      Label = $m.Label; RdpOnly = [bool]($m.RdpIp -and -not $m.Host); MachIp = $m.HostName
      LblTitle = $lblLabel; LblUser = $lblUser; LblRole = $lblRole
      # mini-carte des ecrans + sonde asynchrone du port Apollo (OpenCheckTick)
      Map = $icoMap; Ml = $(if ($icoSun) { $icoSun } else { $icoMl }); RdpBtn = $icoRdp; ApAr = $null; ApTcp = $null; ApT0 = $null; ApOpen = $false
      # sonde SUNSHINE des machines Linux (ports 47989/47984/47990/48010, toutes les 30 s)
      Sess = $lblSess
      IsLinux = [bool]$icoSun; SunAr = $null; SunT0 = $null; SunLast = [datetime]::MinValue; SunOpen = @{}; SunState = ''; SunPaired = $null; SunAddr = $null; SunShown = $false
      FontNormal = $lblLabel.Font; FontStrike = $fontStrike; RoleFg = $fgColor
      # pas de suivi "fenetre VS Code" pour un poste RDP sans alias SSH
      NoVscWatch = ($m.RdpIp -and -not $m.Host)
      PingHost = $m.HostName; Alias = $(if ($m.Host) { $m.Host } else { $m.HostName }); LastOk = $null; LastOpen = $null
      # sonde VNC asynchrone : un port par tick du watchdog (5900 -> 5904)
      VncPort = 5900; VncAr = $null; VncTcp = $null; VncFound = $false; VncDone = $false; VncDoneAt = $null; VncLogged = $false
      # ping ASYNCHRONE : tache SendPingAsync en cours + objet Ping a liberer
      PingTask = $null; PingObj = $null; PingFail = $false
      # 2e chance si le ping echoue : connexion TCP au port du service (SSH : Port du .ssh/config,
      # poste RDP : 3389) ; echecs consecutifs (ping ET TCP) avant de declarer la carte hors ligne
      ProbePort = $(if ($m.RdpIp -and -not $m.Host) { 3389 } elseif ($m.Host -and $m.HostName) { $(if ($m.Port) { [int]$m.Port } else { 22 }) } else { 0 })
      TcpAr = $null; TcpCli = $null; TcpT0 = $null; FailStreak = 0
      # mini-carte : instant du dernier ping reussi (anti-clignotement, voir OpenCheckTick)
      MapOkAt = $null
    }
    $script:CardList += $entry
    $script:LayoutItems += [pscustomobject]@{ Card = $card; Group = $m.Group; Ping = $entry }
  } else {
    # LOCAL : toujours joignable, suivre seulement l'etat "ouvert"
    $script:LayoutItems += [pscustomobject]@{ Card = $card; Group = $m.Group; Ping = $null }
    $script:LogoLocal = $logoVsc
    $script:LastOpenLocal = $null
  }
