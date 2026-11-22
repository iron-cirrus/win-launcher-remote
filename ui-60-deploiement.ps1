# ui-60-deploiement.ps1 - BuildUI : deploiement des couleurs, miroir rsync des dossiers de dev
# Fichier charge par vsc_launcher.ps1 (dot-source : meme portee script). Lignes d'origine 4105-4390.

# ---------- Deploiement des couleurs (integre au launcher) ----------
# Genere le ~/.vscode-server/data/Machine/settings.json de chaque hote avec la
# couleur de SA carte, et l'envoie par ssh/scp. Alimente par la liste dynamique
# de ~/.ssh/config (donc les nouveaux hotes
# heritent automatiquement d'une couleur de la palette).
# Execute ssh/scp avec un TIMEOUT DUR de 10 s : ConnectTimeout ne couvre que la
# connexion TCP (pas l'auth ni un process pendouillant apres le handshake).
# Au-dela de N secondes, le process est tue et le launcher reprend la main.
$script:RunTimeout = {
  param([string]$exe, [string[]]$argList, [int]$timeoutSec = 10)
  $guidN = [guid]::NewGuid().ToString("N")
  $outF = Join-Path $env:TEMP ("vsc-out-" + $guidN + ".txt")
  $errF = Join-Path $env:TEMP ("vsc-err-" + $guidN + ".txt")
  # FICHIER VIDE comme stdin (le peripherique NUL est refuse par Start-Process) :
  # sans console (launcher WinForms), ssh peut rester bloque a attendre une
  # saisie (passphrase/mot de passe) ; un stdin EOF immediat declenche l'echec.
  $inF = Join-Path $env:TEMP ("vsc-in-" + $guidN + ".txt")
  [System.IO.File]::WriteAllText($inF, "")
  # requote les arguments contenant des espaces (Start-Process ne le fait pas)
  $argStr = ($argList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
  $p = Start-Process -FilePath $exe -ArgumentList $argStr -NoNewWindow -PassThru `
        -RedirectStandardOutput $outF -RedirectStandardError $errF -RedirectStandardInput $inF
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  if (-not $p.WaitForExit($timeoutSec * 1000)) {
    $sw.Stop()
    & $script:LogFn ("  " + $exe + " toujours vivant apres " + [int]$sw.Elapsed.TotalSeconds + " s -> tue")
    try { $p.Kill() } catch {}
    try { $p.WaitForExit() } catch {}
    $res = [pscustomobject]@{ Exit = -1; Output = "TIMEOUT > " + $timeoutSec + " s (process " + $exe + " tue)" }
  } else {
    $sw.Stop()
    # PIEGE .NET : ExitCode n'est peuple qu'apres l'appel a WaitForExit() SANS
    # argument (le surcharge WaitForExit(ms) ne le garantit pas) -> sinon $null,
    # et $null -ne 0 = $true => faux ECHEC sur chaque hote.
    try { $p.WaitForExit() } catch {}
    $code = 0
    if ($null -ne $p.ExitCode) { $code = [int]$p.ExitCode }
    $txt = ""
    try {
      $txt = ((Get-Content $errF -Raw -ErrorAction SilentlyContinue) + " " + (Get-Content $outF -Raw -ErrorAction SilentlyContinue)).Trim()
    } catch {}
    $res = [pscustomobject]@{ Exit = $code; Output = ($txt -replace "`r?`n", " | ") }
  }
  Remove-Item $outF, $errF, $inF -ErrorAction SilentlyContinue
  return $res
}

# Variante de RunTimeout qui capture la SORTIE STANDARD EN OCTETS bruts dans un
# fichier (indispensable pour deballer un flux binaire type tar) : RunTimeout
# normal lit la sortie en texte et detruirait les octets.
$script:RunTimeoutBin = {
  param([string]$exe, [string[]]$argList, [int]$timeoutSec, [string]$outFile)
  $guidN = [guid]::NewGuid().ToString("N")
  $errF = Join-Path $env:TEMP ("vsc-err-" + $guidN + ".txt")
  $inF = Join-Path $env:TEMP ("vsc-in-" + $guidN + ".txt")
  [System.IO.File]::WriteAllText($inF, "")
  $argStr = ($argList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
  $p = Start-Process -FilePath $exe -ArgumentList $argStr -NoNewWindow -PassThru `
        -RedirectStandardOutput $outFile -RedirectStandardError $errF -RedirectStandardInput $inF
  $code = -1
  if (-not $p.WaitForExit($timeoutSec * 1000)) {
    try { $p.Kill() } catch { }
    try { $p.WaitForExit() } catch { }
    & $script:LogFn ("  " + $exe + " tue apres " + $timeoutSec + " s (flux binaire)")
  } else {
    try { $p.WaitForExit() } catch { }
    if ($null -ne $p.ExitCode) { $code = [int]$p.ExitCode }
  }
  $errTxt = ""
  try { $errTxt = ((Get-Content $errF -Raw -ErrorAction SilentlyContinue) + "").Trim() } catch { }
  Remove-Item $errF, $inF -ErrorAction SilentlyContinue
  return [pscustomobject]@{ Exit = $code; Output = ($errTxt -replace "`r?`n", " | ") }
}

# ---------- Miroir "rsync" des dossiers de DEV rattaches aux conversations ----------
# Chaque conversation Zoo Code enregistre le dossier de travail dans lequel elle a
# ete lancee : champ "workspace" de history_item.json (ex: /root/workplace).
# La synchro des conversations raporte donc ICI le CONTENU de ces dossiers, dans
# %LOCALAPPDATA%\vsc-launcher\workspaces\<hote>\<chemin distant sans /.
# Il n'y a pas de rsync sous Windows : l'equivalent est fait ainsi
#   1) MANIFESTE distant  : find -type f -printf '%P|%s|%T@' (nom|taille|mtime)
#   2) MANIFESTE local    : calcul equivalent en PowerShell
#   3) identiques -> rien a faire (= rsync "deja a jour")
#      differents -> tar -C <ws> -cf - . via ssh puis tar -xf (copie complete),
#      repli scp -r si tar.exe est absent.
# Exclusions et plafond de taille pour ne pas rapatrier 20 Go de dependances.
# Miroir des workspaces directement dans le HOME de la machine locale
# (C:\Users\<user>\workspaces\<LABEL>\<chemin distant sans slash initial>)
$script:WsRoot = Join-Path $env:USERPROFILE "workspaces"
$script:WsMaxMb = [int]400
$script:WsExcludes = @('node_modules', '.venv', 'venv', '__pycache__', '.cache', 'target', 'build', 'dist', '.terraform', 'vendor')
$script:LocalTasks = Join-Path $env:APPDATA "Code\User\globalStorage\zoocodeorganization.zoo-code\tasks"

$script:LocalManifest = {
  param([string]$dir)
  if (-not (Test-Path $dir)) { return $null }
  $epoch = New-Object datetime(1970, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
  $items = @()
  foreach ($f in @(Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue)) {
    $rel = $f.FullName.Substring($dir.Length).TrimStart('\', '/').Replace('\', '/')
    $skip = $false
    foreach ($ex in $script:WsExcludes) { if ($rel -like ($ex + "/*") -or $rel -like ("*/" + $ex + "/*")) { $skip = $true; break } }
    if ($skip) { continue }
    $mt = [int64](($f.LastWriteTimeUtc - $epoch).TotalSeconds)
    $items += ($rel + "|" + $f.Length + "|" + $mt)
  }
  return (@($items | Sort-Object) -join "`n")
}

$script:SyncWorkspace = {
  param($m, [string]$target, [string[]]$sshOpts, [string]$ws)
  $lbl = $(if ($m.Label) { $m.Label } else { $m.Host })
  # Chemin distant protege pour le shell distant. Ecrire une apostrophe echappee
  # en PowerShell est un piege : le backslash ne protege PAS la guillemet dans une
  # chaine double-quotee -> erreur de parsing. On construit donc apostrophe et
  # backslash a partir de leurs codes caractere, ce qui rend le texte lisible.
  $SQ = [string][char]39
  $BS = [string][char]92
  $q = $SQ + ($ws -replace $SQ, ($SQ + $BS + $SQ + $SQ + $SQ)) + $SQ
  # motifs PROTEGES par des GUILLEMETS SIMPLES cote shell distant (sans protection,
  # les * seraient developpes par le shell). PAS de guillemet DOUBLE : RunTimeout
  # encapsule toute la commande distante dans des guillemets doubles pour
  # Start-Process -> un guillemet double interne casserait le decoupage argv.
  $notP = ($script:WsExcludes | ForEach-Object { "-not -path '*/" + $_ + "/*'" }) -join ' '

  # 1) le dossier existe-t-il cote distant ?
  $rD = & $script:RunTimeout "ssh" ($sshOpts + @($target, "test -d " + $q + " && echo WS_OK || echo WS_ABSENT")) 12
  if ($rD.Output -notmatch 'WS_OK') {
    & $script:LogFn ("  workspace " + $ws + " sur " + $lbl + " : ABSENT (conversation d'une machine reformatree ?) -> ignore")
    return
  }
  # 2) taille distante (garde-fou)
  $rS = & $script:RunTimeout "ssh" ($sshOpts + @($target, "du -sk " + $q)) 15
  $sizeKb = 0
  if ($rS.Output -match '(\d+)') { $sizeKb = [int64]$Matches[1] }
  if ($sizeKb -gt ($script:WsMaxMb * 1024)) {
    & $script:LogFn ("  workspace " + $ws + " sur " + $lbl + " : " + [int]($sizeKb / 1024) + " Mo > plafond " + $script:WsMaxMb + " Mo -> NON synchronise (augmenter WsMaxMb)")
    return
  }
  # 3) manifeste distant (nom|taille|mtime, exclusions identiques au transfert)
  # -printf '%P|%s|%T@\n' en guillemets SIMPLES : les | ne sont pas des pipes
  $rM = & $script:RunTimeout "ssh" ($sshOpts + @($target, ("find " + $q + " -type f " + $notP + " -printf '%P|%s|%T@\n'"))) 25
  $remoteLines = @()
  foreach ($p in ($rM.Output -split ' \| ')) {
    $t = $p.Trim()
    if ($t -match '^[^|]+\|\d+\|\d+') { $remoteLines += ($t -replace '\.\d+$', '') }
  }
  if ($remoteLines.Count -eq 0) {
    & $script:LogFn ("  workspace " + $ws + " sur " + $lbl + " : 0 fichier (ou find sans -printf) -> transfert complet sans comparaison")
  }
  $remoteMan = (@($remoteLines | Sort-Object) -join "`n")

  # 4) destination locale + manifeste local
  $relWs = ($ws -replace '^/+', '') -replace '/+', '\'
  $dest = Join-Path (Join-Path $script:WsRoot $lbl) $relWs
  $localMan = & $script:LocalManifest $dest
  if ($remoteLines.Count -gt 0 -and $localMan -eq $remoteMan) {
    & $script:LogFn ("  workspace " + $ws + " (" + $lbl + ") -> " + $remoteLines.Count + " fichier(s) : DEJA A JOUR (rien copie)")
    return
  }
  if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }

  # 5) transfert : tar par ssh (conserve modes/mtimes, gere les exclusions)
  $tarExe = Get-Command tar.exe -ErrorAction SilentlyContinue
  $excl = ($script:WsExcludes | ForEach-Object { "--exclude=" + $_ }) -join ' '
  $ok = $false
  if ($tarExe) {
    $tarF = Join-Path $env:TEMP ("vsc-ws-" + [guid]::NewGuid().ToString("N") + ".tar")
    $rT = & $script:RunTimeoutBin "ssh" ($sshOpts + @($target, "tar " + $excl + " -C " + $q + " -cf - .")) 180 $tarF
    $tarLen = 0
    if (Test-Path $tarF) { $tarLen = (Get-Item $tarF).Length }
    if ($rT.Exit -eq 0 -and $tarLen -gt 512) {
      $rX = & $script:RunTimeout "tar" @("-xf", $tarF, "-C", $dest) 120
      if ($rX.Exit -eq 0) {
        $ok = $true
        & $script:LogFn ("  workspace " + $ws + " (" + $lbl + ") : " + [math]::Round($tarLen / 1MB, 1) + " Mo debarque via tar -> " + $dest)
      } else {
        & $script:LogFn ("  workspace " + $ws + " (" + $lbl + ") : ECHEC extraction tar (exit " + $rX.Exit + ") -> " + $rX.Output)
      }
    } else {
      & $script:LogFn ("  workspace " + $ws + " (" + $lbl + ") : flux tar KO (exit " + $rT.Exit + ", " + $tarLen + " octets) -> repli scp")
    }
    Remove-Item $tarF -Force -ErrorAction SilentlyContinue
  }
  # 6) repli sans tar : scp -r (plus lent, sans exclusions)
  if (-not $ok) {
    $scpOpts = @("-q", "-r", "-o", "ConnectTimeout=8", "-o", "BatchMode=yes", "-o", "NumberOfPasswordPrompts=0", "-o", "StrictHostKeyChecking=accept-new", "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=1")
    if ($m.Port) { $scpOpts += @("-P", $m.Port) }
    if ($m.IdentityFile) {
      $idFile = $m.IdentityFile -replace "^~", $env:USERPROFILE
      $scpOpts += @("-i", $idFile)
    }
    $rC = & $script:RunTimeout "scp" ($scpOpts + @(($target + ":" + $ws), $dest)) 180
    if ($rC.Exit -eq 0) {
      $ok = $true
      & $script:LogFn ("  workspace " + $ws + " (" + $lbl + ") : copie scp -r -> " + $dest)
    } else {
      & $script:LogFn ("  workspace " + $ws + " (" + $lbl + ") : ECHEC scp (exit " + $rC.Exit + ") -> " + $rC.Output)
    }
  }
}

$script:DeployColors = {
  # tracer QUEL ssh.exe est utilise (le launcher peut resoudre un autre binaire
  # que la console : Git-for-windows ssh vs OpenSSH Windows = comportements differents)
  $sshCmd = Get-Command ssh -ErrorAction SilentlyContinue
  if ($sshCmd) { & $script:LogFn ("  (ssh utilise : " + $sshCmd.Source + ")") }
  foreach ($m in $Machines) {
    if (-not $m.Host) { continue }
    $label = $m.Label
    $json = @"
{
  "workbench.colorCustomizations": {
    "titleBar.activeBackground": "$($m.Color)",
    "titleBar.activeForeground": "$($m.Fg)",
    "titleBar.inactiveBackground": "$($m.Dark)",
    "titleBar.inactiveForeground": "$($m.Fg)",
    "menubar.background": "$($m.Color)",
    "menubar.foreground": "$($m.Fg)",
    "menubar.selectionBackground": "$($m.Color)",
    "menubar.selectionForeground": "#ffffff",
    "activityBar.background": "$($m.Dark)",
    "activityBar.foreground": "#ffffff",
    "activityBar.inactiveForeground": "$($m.Fg)",
    "statusBar.background": "$($m.Color)",
    "statusBar.foreground": "#ffffff",
    "statusBar.noFolderBackground": "$($m.Color)",
    "statusBar.debuggingBackground": "#c2410c",
    "editorGroupHeader.tabsBackground": "$($m.Dark)"
  },
  "window.title": "`${rootName}`${separator}`${appName} [$label]"
}
"@
    $tmp = Join-Path $env:TEMP ("vsc-machine-" + $label + ".json")
    # UTF-8 SANS BOM : le BOM casse le parsing JSON cote remote
    [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))

    # CIBLE directe depuis la config : user@HostName avec -p/-P (et -i IdentityFile
    # si declare) : on ne depend PAS de la resolution de l'alias par OpenSSH.
    $target = if ($m.User) { $m.User + "@" + $m.HostName } else { $m.HostName }
    # -n : stdin pris sur NUL (le launcher n'a pas de console ; sinon ssh peut
    # pendre en attente d'une saisie invisible)
    $sshOpts = @("-n", "-o", "ConnectTimeout=8", "-o", "BatchMode=yes", "-o", "NumberOfPasswordPrompts=0", "-o", "StrictHostKeyChecking=accept-new", "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=1")
    $scpOpts = @("-q", "-o", "ConnectTimeout=8", "-o", "BatchMode=yes", "-o", "NumberOfPasswordPrompts=0", "-o", "StrictHostKeyChecking=accept-new", "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=1")
    $portTxt = ""
    if ($m.Port) {
      $sshOpts += @("-p", $m.Port)
      $scpOpts += @("-P", $m.Port)     # scp : -P majuscule pour le port
      $portTxt = " port " + $m.Port
    }
    if ($m.IdentityFile) {
      $idFile = $m.IdentityFile -replace '^~', $env:USERPROFILE
      $sshOpts += @("-i", $idFile)
      $scpOpts += @("-i", $idFile)
    }
    & $script:LogFn ("deploy couleurs " + $m.Host + " -> " + $target + " (" + $m.Color + $portTxt + ") ...")
    try {
      $sshArgs = $sshOpts + @($target, "mkdir -p ~/.vscode-server/data/Machine")
      & $script:LogFn ('  $ ssh ' + (($sshArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '))
      # TIMEOUT DUR 10 s : si ssh pend (auth, firewall qui droppe, handshake), le
      # process est tue et le launcher reprend la main immediatement.
      $r = & $script:RunTimeout "ssh" $sshArgs 10
      if ($r.Exit -ne 0) {
        if ($r.Output) { & $script:LogFn ("  ssh sortie : " + $r.Output) }
        throw "ssh mkdir exit " + $r.Exit
      }
      $scpArgs = $scpOpts + @($tmp, ($target + ":.vscode-server/data/Machine/settings.json"))
      & $script:LogFn ("  $ scp " + (($scpArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '))
      $r2 = & $script:RunTimeout "scp" $scpArgs 10
      if ($r2.Exit -ne 0) {
        if ($r2.Output) { & $script:LogFn ("  scp sortie : " + $r2.Output) }
        throw ("scp exit " + $r2.Exit)
      }
      & $script:LogFn ("  OK " + $m.Host)
    } catch {
      & $script:LogFn ("  ECHEC " + $m.Host + " : " + $_.Exception.Message)
      & $script:LogFn ("  => relancer a la main dans un terminal : ssh -v " + ($sshOpts -join ' ') + " " + $target + ' "hostname"')
    } finally {
      Remove-Item $tmp -ErrorAction SilentlyContinue
    }
    # l'IHM reste reactive entre chaque hote
    [System.Windows.Forms.Application]::DoEvents()
  }
  & $script:LogFn "deploiement termine - Reload Window dans chaque remote pour appliquer"
}

