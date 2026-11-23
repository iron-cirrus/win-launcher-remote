# 10-ouvrir-hote-windows.ps1 - OpenWindowsHost : Moonlight si possible, sinon RDP
# Fichier charge par vsc_launcher.ps1 (dot-source : meme portee script). Lignes d'origine 1555-1826.

# Ouvre une machine Windows : MOONLIGHT si (1) client installe ici, (2) ports Apollo
# ouverts sur la machine, (3) machine deja APPAIREE dans Moonlight ; sinon RDP (mstsc).
# Sonde des ports : connexions asynchrones, attente max 800 ms au total -> le clic
# ne gele jamais la fenetre plus de 0,8 s (refus immediat si le port est ferme).
# $screenIdx : numero(s) d'ecran(s) local(aux), contigus, ou ouvrir Moonlight (vide = dernier
# choix memorise, sinon ecran principal).
$script:OpenWindowsHost = {
  param([string]$ip, [int[]]$screenIdx = @())
  $viaRdp = {
    param($why)
    & $script:RdpFallback $ip $why
  }
  if (-not $script:MoonlightExe) { & $viaRdp "Moonlight non installe sur ce poste"; return }

  # 1) ports Apollo : tous demarres ensemble, puis collecte
  $socks = @()
  foreach ($port in $script:MoonlightPorts) {
    try {
      $t = New-Object System.Net.Sockets.TcpClient
      $socks += [pscustomobject]@{ Port = $port; Tcp = $t; Ar = $t.BeginConnect($ip, $port, $null, $null); Open = $false }
    } catch { }
  }
  $deadline = (Get-Date).AddMilliseconds(800)
  foreach ($s in $socks) {
    $left = [int][Math]::Max(0, ($deadline - (Get-Date)).TotalMilliseconds)
    try { if ($s.Ar.AsyncWaitHandle.WaitOne($left)) { $s.Tcp.EndConnect($s.Ar); $s.Open = $true } } catch { }
    try { $s.Tcp.Close() } catch { }
  }
  $closed = @($socks | Where-Object { -not $_.Open } | ForEach-Object { $_.Port })
  if ($socks.Count -eq 0 -or $closed.Count -gt 0) {
    & $viaRdp ("Moonlight installe mais ports Apollo fermes sur " + $ip + " : " + $(if ($closed.Count) { $closed -join ', ' } else { "sonde impossible" }))
    return
  }

  # 2) appairage : l'hote doit figurer dans le registre de Moonlight avec son
  # certificat (srvcert). On releve aussi sa liste d'applications.
  $mh = & $script:GetMoonlightHost $ip
  $paired = $mh.Paired; $apps = @($mh.Apps)
  if (-not $paired) {
    & $viaRdp ("ports Apollo ouverts sur " + $ip + " mais machine NON appairee dans Moonlight : ouvrir Moonlight une fois pour l'appairer")
    return
  }
  $app = $script:MoonlightApp
  # application absente de l'hote (ex. Sunshine Linux : pas de "Virtual Display") : "Desktop" si elle existe, sinon la 1re
  if ($apps.Count -gt 0 -and ($apps -notcontains $app)) { $app = $(if ($apps -contains 'Desktop') { 'Desktop' } else { $apps[0] }) }

  # 3) deja en cours ? (evite d'ouvrir une 2e session vers la meme machine)
  try {
    $run = @(Get-CimInstance Win32_Process -Filter "Name='Moonlight.exe'" -ErrorAction Stop |
      Where-Object { $_.CommandLine -like ("*stream*" + $ip + "*") })
    if ($run.Count -gt 0) {
      $hw = [IntPtr]::Zero
      foreach ($pr in $run) {
        $gp = Get-Process -Id $pr.ProcessId -ErrorAction SilentlyContinue
        if ($gp -and $gp.MainWindowHandle -ne [IntPtr]::Zero) { $hw = $gp.MainWindowHandle; break }
      }
      & $script:LogFn ("Moonlight: session DEJA ouverte vers " + $ip + $(if ($hw -ne [IntPtr]::Zero) { " -> fenetre ramenee au premier plan" } else { " (fenetre non identifiee)" }))
      if ($hw -ne [IntPtr]::Zero -and -not $script:WinHostDryRun) {
        [VscWinV4]::ShowWindow($hw, 9) | Out-Null
        [VscWinV4]::SetForegroundWindow($hw) | Out-Null
      }
      return
    }
  } catch { }

  # ecran cible (rescan : l'utilisateur a pu brancher/debrancher un ecran)
  $script:Screens = & $script:GetScreens
  # selection explicite (clic/glisser sur la mini-carte) : validee puis memorisee ;
  # une selection non contigue est refusee (le log dit pourquoi), rien n'est lance
  if ($screenIdx.Count -gt 0 -and -not (& $script:SetSelection $ip $screenIdx)) { return }
  $sel = & $script:ResolveSelection $ip @()
  $scrTxt = "ecran inconnu"
  if ($sel) {
    $scrTxt = $(if ($sel.Multi) { "ecrans " + ($sel.Idxs -join '+') + " (ensemble " + $sel.PW + "x" + $sel.PH + " physiques, place " + $sel.W + "x" + $sel.H + " a " + $sel.X + "," + $sel.Y + " ; ouverture sur l'ecran " + $sel.Anchor.Idx + ")" }
                else { "ecran " + $sel.Anchor.Idx + " (" + $sel.Anchor.PW + "x" + $sel.Anchor.PH + " physiques" + $(if ($sel.Anchor.PW -ne $sel.Anchor.W) { ", vu " + $sel.Anchor.W + "x" + $sel.Anchor.H + " avec la mise a l'echelle" }) + " a " + $sel.Anchor.X + "," + $sel.Anchor.Y + $(if ($sel.Anchor.Primary) { ", principal" }) + ")" })
    # le rectangle englobant couvre-t-il un ecran NON selectionne (selection en L) ?
    if ($sel.Multi) {
      $extra = @($script:Screens | Where-Object { $sel.Idxs -notcontains $_.Idx -and $_.X -lt ($sel.X + $sel.W) -and ($_.X + $_.W) -gt $sel.X -and $_.Y -lt ($sel.Y + $sel.H) -and ($_.Y + $_.H) -gt $sel.Y } | ForEach-Object { $_.Idx })
      if ($extra.Count -gt 0) { & $script:LogFn ("  note: le rectangle englobant couvre aussi l'ecran " + ($extra -join ', ') + " (non selectionne)") }
    }
  }
  # arguments : option d'affichage facultative pour le multi-ecrans (voir MultiScreenDisplayMode)
  $mlArgs = @("stream", $ip, ('"' + $app + '"'))
  if ($sel -and $sel.Multi -and $script:MultiScreenDisplayMode) { $mlArgs += @("--display-mode", [string]$script:MultiScreenDisplayMode) }
  # PROFIL genere depuis les ecrans choisis (resolution = rectangle englobant, fps, debit)
  $mlArgsBase = @($mlArgs)
  $prof = $null
  if ($sel -and $script:MoonlightAutoProfile) {
    $prof = & $script:BuildMoonlightProfile $sel $ip
    if ($prof) {
      $prof | Add-Member -NotePropertyName App -NotePropertyValue $app -Force   # application diffusee : memorisee avec le mode
      $mlArgs += $prof.Args
      & $script:LogFn ("Moonlight: profil genere pour les ecrans " + ($sel.Idxs -join '+') + " : " + $prof.Text + " (" + ($prof.Args -join ' ') + ")")
    }
  }
  & $script:LogFn ("Moonlight: ports " + ($script:MoonlightPorts -join '/') + " ouverts, machine appairee -> " + $script:MoonlightExe + " " + ($mlArgs -join ' ') + " sur " + $scrTxt)
  if ($script:WinHostDryRun) { & $script:LogFn "  [essai] Moonlight non lance"; return }
  # La VM applique la resolution demandee seulement a un VRAI lancement ("/launch") : si une session
  # est deja ouverte, Moonlight la REPREND ("/resume") et le bureau / l'ecran virtuel gardent l'ancienne
  # taille (voir MoonlightQuitToApplyProfile). La session en cours est deduite de l'historique des
  # requetes de Moonlight (fiable), completee par la reponse du serveur si elle annonce une application.
  $applied = $true; $needQuit = $false
  if ($prof -and $script:MoonlightQuitToApplyProfile) {
    $appId = $mh.AppIds[[string]$app]
    $newMode = "" + $prof.Width + "x" + $prof.Height + "x" + $prof.Fps
    $believed = & $script:GetBelievedHostSession $ip
    $cur = & $script:GetHostRunningApp $ip
    $curId = $(if ($cur) { [long]$cur } elseif ($believed -and $believed.Active -and $believed.AppId) { [long]$believed.AppId } else { [long]0 })
    if ($curId) {
      $hostMode = $(if ($believed -and $believed.Active) { $believed.Mode } else { $null })   # $null = mode inconnu
      $curName = ($mh.AppIds.GetEnumerator() | Where-Object { $_.Value -eq $curId } | Select-Object -First 1).Key
      $curTxt = $(if ($curName) { "'" + $curName + "'" } else { "id " + $curId })
      # applications de BUREAU fermables sans risque : par nom exact (MoonlightSafeQuitApps) ou par motif (MoonlightSafeQuitPatterns)
      $safeIds = @($mh.AppIds.GetEnumerator() | Where-Object {
        $an = [string]$_.Key; $ok = ($script:MoonlightSafeQuitApps -contains $an)
        if (-not $ok) { foreach ($pt in $script:MoonlightSafeQuitPatterns) { if ($an -like ("*" + $pt + "*")) { $ok = $true; break } } }
        $ok } | ForEach-Object { $_.Value })
      if ($safeIds -notcontains $curId) {
        # application "sensible" (jeu, Steam...) : pour lancer une AUTRE application, Moonlight envoie
        # lui-meme un /cancel qui fermerait celle-ci. On se reconnecte donc plutot a CETTE application
        # (reprise), sans profil : rien n'est ferme, la resolution de la VM reste celle de sa session.
        if ($curName) {
          & $script:LogFn ("Moonlight: l'application " + $curTxt + " tourne sur la VM : elle n'est PAS fermee ; connexion a cette application (reprise), resolution de la VM inchangee")
          $app = $curName
          $mlArgs = @("stream", $ip, ('"' + $app + '"')); $mlArgsBase = @($mlArgs); $prof = $null
        } else {
          & $script:LogFn ("Moonlight: une application inconnue (" + $curTxt + ") tourne sur la VM : lancement ANNULE pour ne pas la fermer (Moonlight la fermerait)")
          return
        }
      } elseif ($appId -and $curId -eq $appId -and $hostMode -and $hostMode -eq $newMode) {
        & $script:LogFn ("Moonlight: session " + $curTxt + " deja ouverte sur la VM avec ce mode (" + $newMode + ") -> reprise")
      } else {
        # session de bureau (Desktop / Virtual Display) a un autre mode ou une autre application :
        # fermeture sans risque (cela supprime aussi l'ecran virtuel), puis lancement neuf
        $needQuit = $true
        & $script:LogFn ("Moonlight: session " + $curTxt + " deja ouverte sur la VM (mode " + $(if ($hostMode) { $hostMode } else { "inconnu" }) + ", d'apres l'historique de Moonlight) -> fermeture puis relance de '" + $app + "' en " + $newMode)
      }
    }
  }
  if ($needQuit) { & $script:QuitThenLaunch $ip $mlArgs $mlArgsBase $sel $prof; return }
  & $script:LaunchMoonlightNow $ip $mlArgs $mlArgsBase $sel $prof $applied
}

# CLIENT VNC : recherche du viewer TurboVNC/RealVNC a l'installation du launcher.
# Le binaire peut s'appeler vncviewer.exe OU turbovnc-vncviewer.exe selon la
# version -> on balaye aussi le CONTENU du dossier d'installation.
$script:VncViewerExe = $null
$vncDirs = @(
  (Join-Path ${env:ProgramFiles} "TurboVNC"),
  (Join-Path ${env:ProgramFiles(x86)} "TurboVNC"),
  (Join-Path $env:LOCALAPPDATA "Programs\TurboVNC"),
  "C:\Program Files\TurboVNC",
  (Join-Path ${env:ProgramFiles} "RealVNC\VNC Viewer"),
  (Join-Path ${env:ProgramFiles} "RealVNC\Viewer")
)
foreach ($dir in $vncDirs) {
  if ($dir -and (Test-Path $dir)) {
    # d'abord le nom exact, puis n'importe quel *viewer*.exe du dossier
    $exact = Join-Path $dir "vncviewer.exe"
    if (Test-Path $exact) { $script:VncViewerExe = $exact; break }
    $any = Get-ChildItem -Path $dir -Filter "*viewer*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($any) { $script:VncViewerExe = $any.FullName; break }
    # TurboVNC recent livre un LAUNCHER .bat (vncviewer.bat) qui enveloppe le
    # vrai binaire (jar Java) : Start-Process sur le .bat transmet les arguments.
    $bat = Join-Path $dir "vncviewer.bat"
    if (Test-Path $bat) { $script:VncViewerExe = $bat; break }
  }
}
if (-not $script:VncViewerExe) {
  # dernier recours : PATH
  try { $cmd = Get-Command vncviewer -ErrorAction Stop; $script:VncViewerExe = $cmd.Source } catch { }
}
# VRAIE ICONE du client VNC : fichier .ico a cote du binaire en priorite
# (TurboVNC livre vncviewer.ico), sinon extraction depuis l'exe.
$script:VncIconBmp = $null
if ($script:VncViewerExe) {
  # .bat -> l'ico s'appelle vncviewer.ico a cote ; .exe -> extension identique
  $icoFile = $null
  if ($script:VncViewerExe -match '(?i)\.bat$') {
    $icoFile = Join-Path (Split-Path $script:VncViewerExe -Parent) "vncviewer.ico"
  } else {
    $icoFile = [System.IO.Path]::ChangeExtension($script:VncViewerExe, ".ico")
  }
  if (Test-Path $icoFile) {
    try {
      $ico = New-Object System.Drawing.Icon($icoFile)
      $script:VncIconBmp = $ico.ToBitmap()
    } catch { }
  }
  if (-not $script:VncIconBmp -and ($script:VncViewerExe -match '(?i)\.exe$')) {
    try {
      $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($script:VncViewerExe)
      if ($ico) { $script:VncIconBmp = $ico.ToBitmap() }
    } catch { $script:VncIconBmp = $null }
  }
}
# VRAI LOGO VS CODE : icone officielle extraite de Code.exe (ou app.exe).
# 'code' est souvent un shim .cmd dans bin\ -> on cherche le vrai exe.
$script:VscIconBmp = $null
try {
  $exeCandidates = @()
  if ($script:CodeExe) {
    $binDir = Split-Path $script:CodeExe -Parent
    $exeCandidates += (Join-Path (Split-Path $binDir -Parent) "Code.exe")
  }
  $exeCandidates += (Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code\Code.exe")
  $exeCandidates += (Join-Path $env:ProgramFiles "Microsoft VS Code\Code.exe")
  $exeCandidates += (Join-Path ${env:ProgramFiles(x86)} "Microsoft VS Code\Code.exe")
  foreach ($cand in $exeCandidates) {
    if ($cand -and (Test-Path $cand)) {
      $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($cand)
      if ($ico) {
        $script:VscIconBmp = $ico.ToBitmap()
        break
      }
    }
  }
} catch { $script:VscIconBmp = $null }
# Versions 20 px des logos VS Code et VNC : posees sur le PLAN DES ECRANS (panneau du
# haut) quand une remote app de cette machine y est reperee (fenetre ouverte).
$script:VscIcon20 = $null; $script:VncIcon20 = $null
try {
  if ($script:VscIconBmp) {
    $script:VscIcon20 = New-Object System.Drawing.Bitmap(20, 20, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gV = [System.Drawing.Graphics]::FromImage($script:VscIcon20)
    $gV.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $gV.DrawImage($script:VscIconBmp, 0, 0, 20, 20); $gV.Dispose()
  }
} catch { $script:VscIcon20 = $null }
try {
  if ($script:VncIconBmp) {
    $script:VncIcon20 = New-Object System.Drawing.Bitmap(20, 20, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gN = [System.Drawing.Graphics]::FromImage($script:VncIcon20)
    $gN.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $gN.DrawImage($script:VncIconBmp, 0, 0, 20, 20); $gN.Dispose()
  }
} catch { $script:VncIcon20 = $null }

# VRAIE ICONE SSH = celle du terminal que le clic SSH ouvre :
#   Windows Terminal (wt.exe) -> son logo officiel 16 px (PNG transparent du
#   paquet MSIX : wt.exe est un alias d'application, sans icone extractible) ;
#   sinon powershell.exe -> icone extraite de l'exe ; sinon dessin de repli.
# L'image est COPIEE en memoire (pas de verrou sur le fichier source).
$script:SshIconBmp = $null
try {
  if (Get-Command wt.exe -ErrorAction SilentlyContinue) {
    $wtPkg = Get-AppxPackage -Name Microsoft.WindowsTerminal -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($wtPkg) {
      # 32 px en priorite : l'icone est maintenant affichee en 20 px (reduction nette)
      foreach ($nm in @('Square44x44Logo.targetsize-32_altform-unplated.png', 'Square44x44Logo.targetsize-32.png', 'Square44x44Logo.targetsize-16_altform-unplated.png', 'Square44x44Logo.targetsize-16.png')) {
        $wtPng = Join-Path $wtPkg.InstallLocation ("Images\" + $nm)
        if (Test-Path $wtPng) {
          $ms = New-Object System.IO.MemoryStream(, [System.IO.File]::ReadAllBytes($wtPng))
          $tmpImg = [System.Drawing.Image]::FromStream($ms)
          $script:SshIconBmp = New-Object System.Drawing.Bitmap($tmpImg)
          $tmpImg.Dispose(); $ms.Dispose()
          break
        }
      }
    }
  }
  if (-not $script:SshIconBmp) {
    $psExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path $psExe) {
      $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($psExe)
      if ($ico) { $script:SshIconBmp = $ico.ToBitmap() }
    }
  }
} catch { $script:SshIconBmp = $null }

# Dossier remote a ouvrir par alias : le HOME de l'utilisateur de connexion
# (VS Code ne restaure PAS le dernier dossier avec un simple "--remote" :
#  il faut passer le chemin en argument). Calcule depuis le champ "User" de
# ~/.ssh/config : root -> /root, sinon -> /home/<user>.
$script:FolderMap = @{}
foreach ($h in $RemoteHosts) {
  if ($h.User) {
    if ($h.User -eq 'root') { $script:FolderMap[$h.Alias] = '/root' }
    else { $script:FolderMap[$h.Alias] = '/home/' + $h.User }
  }
}
$script:CardList = @()
# STATUT SANS ROUGE/VERT (daltonisme) : bleu clair = joignable, orange = injoignable, accompagnes d'un
# SYMBOLE (cercle plein / triangle / cercle vide), la couleur n'est plus le seul indice
$script:DotOk = [System.Drawing.Color]::FromArgb(86,180,233)    # bleu clair
$script:DotKo = [System.Drawing.Color]::FromArgb(230,159,0)     # orange
$script:SymOk = [string][char]0x25CF                             # ● joignable
$script:SymKo = [string][char]0x25B2                             # ▲ injoignable
$script:SymUnk = [string][char]0x25CB                            # ○ en attente
$script:DotUnk = [System.Drawing.Color]::FromArgb(120,120,120)  # gris (inconnu)

