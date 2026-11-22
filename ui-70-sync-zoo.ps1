# ui-70-sync-zoo.ps1 - BuildUI : synchronisation des conversations Zoo Code (tache de fond)
# Fichier charge par vsc_launcher.ps1 (dot-source : meme portee script). Lignes d'origine 4391-4641.

# ---------- Synchronisation des conversations Zoo Code (TACHE DE FOND) ----------
# Chaque machine distante heberge ses conversations Zoo Code (fork de Roo Code)
# dans ~/.vscode-server/data/User/globalStorage/zoocodeorganization.zoo-code/tasks
# -> UN dossier par tache (UUID) : history_item.json (index affiche dans
# l'historique) + api_conversation_history.json + ui_messages.json +
# task_metadata.json + checkpoints/. Verifie dans l'extension 3.96.0 : elle
# balaie ce dossier tasks/ au demarrage -> copier les dossiers manquants cote
# local (%APPDATA%\Code\User\globalStorage\... MEME nom de dossier) suffit a
# les faire apparaitre dans l'historique du Zoo Code local (recharger la fenetre).
# Les checkpoints (instantanes des fichiers de la MACHINE DISTANTE, inutiles et
# lourds ici) sont supprimes apres copie.
# EXECUTION EN Start-Job (comme le scan LAN) : le panneau reste TOTALEMENT
# reactif (watchdog, pings, clics) pendant les ssh/scp/tar. Chaque ligne ecrite
# par le job (Write-Output) est reversee EN DIRECT dans le log du launcher par
# le timer de suivi -> erreurs ssh/scp/tar visibles immediatement, stderr inclus.
$script:SyncJobBlock = {
  param([object[]]$machList, [string]$localTasks, [string]$wsRoot, [int]$maxMb, [string[]]$excludes)
  $ErrorActionPreference = "SilentlyContinue"
  # RunCmd : toute commande externe est TUEE au bout de N s ; stderr est joint a
  # la sortie avec [stderr].
  # IMPORTANT : Start-Process -PassThru, DANS UN Start-Job, ne fournit pas
  # toujours le ExitCode (objet Process sans acces -> null -> code force a -1).
  # Resultat : de fausses "ssh KO (exit -1)" sur des commandes REUSSIES (la liste
  # des UUID etait bien revenue) et donc 0 copie. On utilise desormais
  # System.Diagnostics.Process, dont ExitCode est fiable, avec lecture
  # ASYNCHRONE des flux (aucun blocage possible sur les pipes pleines).
  function RunProc {
    param([string]$exe, [string[]]$a, [int]$sec, [string]$outFile)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = (($a | ForEach-Object { if ($_) { ([string]$_) } else { '""' } } | ForEach-Object { if ($_ -match '\s') { ([string][char]34) + $_ + ([string][char]34) } else { $_ } }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = $null
    try { $p = [System.Diagnostics.Process]::Start($psi) }
    catch { return @{ Exit = -99; Output = ("lancement " + $exe + " impossible : " + $_.Exception.Message); Err = "" } }
    $fs = $null
    try {
      $tErr = $p.StandardError.ReadToEndAsync()
      $tOut = $null
      if ($outFile) {
        # flux binaire (tar) : stdout copie tel quel vers le fichier
        $fs = [System.IO.File]::Create($outFile)
        $tOut = $p.StandardOutput.BaseStream.CopyToAsync($fs)
      } else {
        $tOut = $p.StandardOutput.ReadToEndAsync()
      }
      try { $p.StandardInput.Close() } catch { }
      $fini = $true
      try { $fini = $p.WaitForExit($sec * 1000) } catch { }
      if (-not $fini) {
        try { $p.Kill() } catch { }
        try { $p.WaitForExit() } catch { }
        return @{ Exit = -98; Output = ("TIMEOUT : " + $exe + " tue apres " + $sec + " s"); Err = "" }
      }
      try { $p.WaitForExit() } catch { }
      try { $tOut.Wait($sec * 1000) | Out-Null } catch { }
      try { $tErr.Wait($sec * 1000) | Out-Null } catch { }
      $code = -1
      try { $code = [int]$p.ExitCode } catch { }
      $txt = ""; $errTxt = ""
      if (-not $outFile) { try { $txt = ($tOut.Result) + "" } catch { } }
      try { $errTxt = ($tErr.Result) + "" } catch { }
      return @{ Exit = $code; Output = $txt; Err = $errTxt }
    } finally {
      if ($fs) { try { $fs.Flush(); $fs.Dispose() } catch { } }
      try { $p.Dispose() } catch { }
    }
  }
  function RunCmd {
    param([string]$exe, [string[]]$a, [int]$sec)
    $r = RunProc $exe $a $sec $null
    $out = ((" " + $r.Output) -replace "`r?`n", " | ").Trim()
    $errTxt = (" " + $r.Err)
    if ($errTxt.Trim()) { $out += " [stderr] " + (($errTxt -replace "`r?`n", " | ").Trim()) }
    return @{ Exit = $r.Exit; Output = $out }
  }
  # variante binaire : stdout redirige tel quel vers un fichier (flux tar)
  function RunCmdBin {
    param([string]$exe, [string[]]$a, [int]$sec, [string]$outFile)
    $r = RunProc $exe $a $sec $outFile
    return @{ Exit = $r.Exit; Output = ((" " + $r.Err) -replace "`r?`n", " | ").Trim() }
  }
  function LocalManifest {
    param([string]$dir)
    if (-not (Test-Path $dir)) { return $null }
    $epoch = New-Object datetime(1970, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
    $items = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue)) {
      $rel = $f.FullName.Substring($dir.Length).TrimStart('\', '/').Replace('\', '/')
      $skip = $false
      foreach ($ex in $excludes) { if ($rel -like ($ex + "/*") -or $rel -like ("*/" + $ex + "/*")) { $skip = $true; break } }
      if ($skip) { continue }
      $mt = [int64](($f.LastWriteTimeUtc - $epoch).TotalSeconds)
      $items += ($rel + "|" + $f.Length + "|" + $mt)
    }
    return (@($items | Sort-Object) -join "`n")
  }
  # equivalent rsync d'UN workspace : manifeste compare puis tar par ssh (ou scp)
  function SyncWs {
    param($m, [string]$target, [string[]]$sshOpts, [string]$ws)
    $lbl = $(if ($m.Label) { $m.Label } else { $m.Host })
    $SQ = [string][char]39
    $BS = [string][char]92
    $q = $SQ + ($ws -replace $SQ, ($SQ + $BS + $SQ + $SQ + $SQ)) + $SQ
    $notP = ($excludes | ForEach-Object { "-not -path '*/" + $_ + "/*'" }) -join ' '
    $rD = RunCmd "ssh" ($sshOpts + @($target, "test -d " + $q + " && echo WS_OK || echo WS_ABSENT")) 12
    if ($rD.Output -notmatch 'WS_OK') {
      Write-Output ("  workspace " + $ws + " sur " + $lbl + " : ABSENT (ssh exit " + $rD.Exit + ", sortie=" + $rD.Output + ") -> ignore")
      return
    }
    $rS = RunCmd "ssh" ($sshOpts + @($target, "du -sk " + $q)) 15
    $sizeKb = 0
    if ($rS.Output -match '(\d+)') { $sizeKb = [int64]$Matches[1] }
    Write-Output ("  workspace " + $ws + " sur " + $lbl + " : existe, taille distante " + [math]::Round($sizeKb / 1024, 1) + " Mo")
    if ($sizeKb -gt ($maxMb * 1024)) {
      Write-Output ("  workspace " + $ws + " sur " + $lbl + " : " + [int]($sizeKb / 1024) + " Mo > plafond " + $maxMb + " Mo -> NON synchronise")
      return
    }
    $rM = RunCmd "ssh" ($sshOpts + @($target, ("find " + $q + " -type f " + $notP + " -printf '%P|%s|%T@\n'"))) 25
    if ($rM.Exit -ne 0) { Write-Output ("  workspace " + $ws + " : find distant KO (exit " + $rM.Exit + ") -> " + $rM.Output) }
    $remoteLines = @()
    foreach ($p in ($rM.Output -split ' \| ')) {
      $t = $p.Trim()
      if ($t -match '^[^|]+\|\d+\|\d+') { $remoteLines += ($t -replace '\.\d+$', '') }
    }
    $localMan = LocalManifest $((Join-Path (Join-Path $wsRoot $lbl) ((($ws -replace '^/+', '') -replace '/+', '\'))))
    Write-Output ("  workspace " + $ws + " (" + $lbl + ") : manifeste distant " + $remoteLines.Count + " fichier(s), local " + $(if ($localMan) { @(($localMan -split "`n") | Where-Object { $_ }).Count } else { "dossier absent" }) + " -> comparaison")
    if ($remoteLines.Count -eq 0) {
      Write-Output ("  workspace " + $ws + " : 0 fichier distant (ou find sans -printf) -> transfert complet sans comparaison")
    }
    $remoteMan = (@($remoteLines | Sort-Object) -join "`n")
    $relWs = ($ws -replace '^/+', '') -replace '/+', '\'
    $dest = Join-Path (Join-Path $wsRoot $lbl) $relWs
    if ($remoteLines.Count -gt 0 -and $localMan -eq $remoteMan) {
      Write-Output ("  workspace " + $ws + " (" + $lbl + ") : DEJA A JOUR (rien copie)")
      return
    }
    if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
    $tarExe = Get-Command tar.exe -ErrorAction SilentlyContinue
    $excl = ($excludes | ForEach-Object { "--exclude=" + $_ }) -join ' '
    $ok = $false
    if ($tarExe) {
      $tarF = Join-Path $env:TEMP ("sync-ws-" + [guid]::NewGuid().ToString("N") + ".tar")
      $rT = RunCmdBin "ssh" ($sshOpts + @($target, "tar " + $excl + " -C " + $q + " -cf - .")) 180 $tarF
      $tarLen = 0
      if (Test-Path $tarF) { $tarLen = (Get-Item $tarF).Length }
      Write-Output ("  workspace " + $ws + " (" + $lbl + ") : tar ssh exit=" + $rT.Exit + ", " + $tarLen + " octets" + $(if ($rT.Output) { ", stderr=" + $rT.Output } else { "" }))
      if ($rT.Exit -eq 0 -and $tarLen -gt 512) {
        $rX = RunCmd "tar" @("-xf", $tarF, "-C", $dest) 120
        if ($rX.Exit -eq 0) {
          $ok = $true
          Write-Output ("  workspace " + $ws + " (" + $lbl + ") : OK " + [math]::Round($tarLen / 1MB, 1) + " Mo debarque via tar -> " + $dest)
        } else {
          Write-Output ("  workspace " + $ws + " (" + $lbl + ") : ECHEC extraction tar (exit " + $rX.Exit + ") -> " + $rX.Output)
        }
      } else {
        Write-Output ("  workspace " + $ws + " (" + $lbl + ") : flux tar KO -> repli scp")
      }
      Remove-Item $tarF -Force -ErrorAction SilentlyContinue
    } else {
      Write-Output ("  workspace " + $ws + " (" + $lbl + ") : tar.exe absent -> repli scp direct")
    }
    if (-not $ok) {
      $scpOpts = @("-q", "-r", "-o", "ConnectTimeout=8", "-o", "BatchMode=yes", "-o", "NumberOfPasswordPrompts=0", "-o", "StrictHostKeyChecking=accept-new", "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=1")
      if ($m.Port) { $scpOpts += @("-P", $m.Port) }
      if ($m.IdentityFile) {
        $idFile = $m.IdentityFile -replace "^~", $env:USERPROFILE
        $scpOpts += @("-i", $idFile)
      }
      $rC = RunCmd "scp" ($scpOpts + @(($target + ":" + $ws), $dest)) 180
      if ($rC.Exit -eq 0) {
        Write-Output ("  workspace " + $ws + " (" + $lbl + ") : OK copie scp -r -> " + $dest)
      } else {
        Write-Output ("  workspace " + $ws + " (" + $lbl + ") : ECHEC scp (exit " + $rC.Exit + ") -> " + $rC.Output)
      }
    }
  }
  $remoteTasks = "~/.vscode-server/data/User/globalStorage/zoocodeorganization.zoo-code/tasks"
  if (-not (Test-Path $localTasks)) {
    New-Item -ItemType Directory -Path $localTasks -Force | Out-Null
    Write-Output ("dossier local cree : " + $localTasks)
  }
  foreach ($m in $machList) {
    $target = if ($m.User) { $m.User + "@" + $m.HostName } else { $m.HostName }
    $sshOpts = @("-n", "-o", "ConnectTimeout=8", "-o", "BatchMode=yes", "-o", "NumberOfPasswordPrompts=0", "-o", "StrictHostKeyChecking=accept-new", "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=1")
    # -r : la conversation est un DOSSIER (tout le contenu de tasks/<uuid>)
    $scpOpts = @("-q", "-r", "-o", "ConnectTimeout=8", "-o", "BatchMode=yes", "-o", "NumberOfPasswordPrompts=0", "-o", "StrictHostKeyChecking=accept-new", "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=1")
    if ($m.Port) { $sshOpts += @("-p", $m.Port); $scpOpts += @("-P", $m.Port) }
    if ($m.IdentityFile) {
      $idFile = $m.IdentityFile -replace "^~", $env:USERPROFILE
      $sshOpts += @("-i", $idFile); $scpOpts += @("-i", $idFile)
    }
    Write-Output ($m.Host + " (" + $target + ") : enumeration des conversations ...")
    $r = RunCmd "ssh" ($sshOpts + @($target, "ls -1 " + $remoteTasks)) 10
    if ($r.Exit -ne 0) {
      Write-Output ("  " + $m.Host + " : ssh KO (exit " + $r.Exit + ") -> " + $r.Output)
      continue
    }
    # RunCmd remplace les sauts de ligne par " | " -> ids = dossiers UUID
    $ids = @($r.Output -split " \| " | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^[0-9a-fA-F][0-9a-fA-F-]{20,40}$" })
    $copied = 0; $skipped = 0; $failed = 0
    foreach ($id in $ids) {
      $ld = Join-Path $localTasks $id
      if (Test-Path $ld) { $skipped = $skipped + 1; continue }
      $r2 = RunCmd "scp" ($scpOpts + @(($target + ":" + $remoteTasks + "/" + $id), $localTasks)) 20
      if ($r2.Exit -eq 0) {
        $copied = $copied + 1
        # checkpoints = copies des fichiers edites sur la MACHINE DISTANTE : sans
        # interet dans l'historique local (et volumineux) -> supprimes
        Remove-Item (Join-Path $ld "checkpoints") -Recurse -Force -ErrorAction SilentlyContinue
      } else {
        # 1er ECHEC de copie sur cette machine = machine instable/eteinte en cours
        # de route : on abandonne la machine (pas N timeouts inutiles) et on passe
        # a la machine suivante.
        $failed = $failed + 1
        Write-Output ("  " + $m.Host + " : ECHEC copie tache " + $id + " (exit " + $r2.Exit + ") -> " + $r2.Output + " -> abandon de la machine")
        # scp interrompu = dossier partiel : supprime pour que la tache soit
        # re-essayee proprement a la prochaine synch (sinon "deja la" l'occulterait)
        if (Test-Path $ld) { Remove-Item $ld -Recurse -Force -ErrorAction SilentlyContinue }
        break
      }
    }
    Write-Output ($m.Host + " : " + $ids.Count + " conversation(s) distante(s), " + $copied + " copiee(s), " + $skipped + " deja la, " + $failed + " echec(s)")

    # --- Miroir des dossiers de DEV rattaches aux conversations de CETTE machine.
    $rW = RunCmd "ssh" ($sshOpts + @($target, ("grep -ho workspace[^,]* " + $remoteTasks + "/*/history_item.json 2>/dev/null | sort -u"))) 20
    $wsList = @()
    foreach ($p in ($rW.Output -split ' \| ')) {
      $pc = ($p -replace '"', '').Trim()
      if ($pc -match '^workspace:(.+)$') {
        $wv = $Matches[1].Trim()
        # SEULE la racine "/" est ecartee (sync de tout le disque = non sens).
        # Les dossiers HORS home (/data, /srv, /opt, /var...) sont synchronises
        # sans restriction : la garde de taille WsMaxMb suffit.
        if ($wv -and $wv -ne "/" -and ($wsList -notcontains $wv)) { $wsList += $wv }
      }
    }
    if ($wsList.Count -eq 0) {
      Write-Output ("  " + $m.Host + " : aucun workspace de conversation identifie (grep ssh exit " + $rW.Exit + ")")
    } else {
      Write-Output ("  " + $m.Host + " : " + $wsList.Count + " workspace(s) de conversation : " + ($wsList -join ', '))
    }
    foreach ($wv in $wsList) { SyncWs $m $target $sshOpts $wv }
  }
  Write-Output "FIN"
}

