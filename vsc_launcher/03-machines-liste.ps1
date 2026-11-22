# 03-machines-liste.ps1 - Lecture de ~/.ssh/config, construction de $Machines, fusion du cache LAN (Windows/RDP)
# Fichier charge par vsc_launcher.ps1 (dot-source : meme portee script). Lignes d'origine 229-429.

# ---------- Lecture dynamique de ~/.ssh/config ----------
function Get-SshHosts([string]$path) {
  $list = @()
  if (-not (Test-Path $path)) { return $list }
  $current = $null
  foreach ($raw in (Get-Content $path)) {
    $t = $raw.Trim()
    if ($t.StartsWith('#')) { continue }
    if ($t -match '^(?i)Host\s+(\S.*)$') {
      $alias = ($Matches[1] -split '\s+')[0]
      if ($alias -match '[\*\?]') { $current = $null; continue }   # ignorer les patterns
      $current = [pscustomobject]@{ Alias = $alias; HostName = $alias; User = $null; Port = $null; IdentityFile = $null }
      $list += $current
    }
    elseif ($current -and $t -match '^(?i)HostName\s+(\S+)') {
      $current.HostName = $Matches[1]
    }
    elseif ($current -and $t -match '^(?i)User\s+(\S+)') {
      $current.User = $Matches[1]
    }
    elseif ($current -and $t -match '^(?i)Port\s+(\S+)') {
      $current.Port = $Matches[1]
    }
    elseif ($current -and $t -match '^(?i)IdentityFile\s+(\S+)') {
      $current.IdentityFile = $Matches[1]
    }
  }
  return $list
}

$sshConfig = Join-Path $env:USERPROFILE ".ssh\config"
$RemoteHosts = Get-SshHosts $sshConfig

# Liste finale : LOCAL d'abord, puis les hotes de la config (doublons .251/free fusionnes par alias different -> on garde les 2, ils partagent la couleur via le fichier Machine)
$Machines = @()
$script:BadAliases = @()   # alias contenant "@" -> incompatibles avec ssh-remote+
$Machines += [pscustomobject]@{ Host = ""; HostName = $null; Label = "LOCAL"; Role = "VS Code local (ce poste)"; Parent = $null; IconType = "pc"; Group = "LAN"; OsType = "windows" }   # LOCAL fusionne avec la colonne LAN (en tete)
$k = 0
foreach ($h in $RemoteHosts) {
  if ($KnownColors.ContainsKey($h.Alias)) {
    $pal = $KnownColors[$h.Alias]
  } else {
    $pal = $Palette[$k % $Palette.Count]
    $k++
  }
  # Convention "_" : "Vm-HomeAssistant_Router" = VM hebergeee sur l'hote "Router"
  # (le "@" est INTERDIT dans les alias : VS Code l'interprete comme user@host
  #  dans l'autority "ssh-remote+<alias>" -> echec de connexion)
  # L'alias est coupe au DERNIER underscore : tout le reste peut en contenir.
  $label = $h.Alias.ToUpper()
  $parent = $null
  if ($h.Alias -match '^(.+)_(.+)$') {
    $label  = $Matches[1].ToUpper()
    $parent = $Matches[2]
  }
  $role = if ($Notes.ContainsKey($h.Alias)) { $Notes[$h.Alias] }
          elseif ($parent) { "VM sur " + $parent }
          else { $h.HostName }
  # alerte explicite si un alias contient "@" (casse l'autority ssh-remote+ de VS Code)
  if ($h.Alias -match '@') {
    $script:BadAliases += $h.Alias
  }
  $Machines += [pscustomobject]@{
    Host     = $h.Alias
    HostName = $h.HostName          # cible du ping (l'alias ssh n'est pas resoluble par DNS)
    User     = $h.User              # utilisateur de connexion (affiche sur la carte, aligne droit)
    Port     = $h.Port              # port SSH non standard (deploy couleurs : ssh/scp -p)
    IdentityFile = $h.IdentityFile  # cle SSH declaree (deploy couleurs : ssh/scp -i)
    Label    = $label
    Parent   = $parent              # hote des VM si alias "vm_hote"
    Group    = $(if ($parent) { $parent } else { $h.Alias })   # colonne du launcher
    Role     = $role
    Color    = $pal.Color
    Dark     = $pal.Dark
    Fg       = $pal.Fg
    # filigrane de la carte : "pc" = ordinateur (VM ou LOCAL), "srv" = serveur physique
    IconType = $(if ($parent) { "pc" } else { "srv" })
    # OS suppose : la config .ssh/config ne contient que des machines SSH (Linux)
    OsType   = "linux"
  }
}

# ---------- Machines WINDOWS du LAN (issues du scan RDP mis en cache) ----------
# La config SSH ne liste que des machines Linux ; les postes Windows du LAN sont
# detectes par le scan du port RDP 3389 (tache de fond, cache JSON). Ici on
# fusionne le CACHE existant des le demarrage : les machines deja connues du
# scan precedent obtiennent leur carte immediatement.
$script:NetCachePath = Join-Path $env:LOCALAPPDATA "vsc-launcher\network-cache.json"
$script:StartupNotes = @()
# Fusion du cache LAN dans $Machines : scriptblock APPELABLE PLUSIEURS FOIS
# (demarrage + reconstruction d'affichage apres scan). Les IP deja connues sont
# sautees -> la liste LAN ne peut jamais "disparaitre" a une relecture.
$script:MergeLanCache = {
$script:StartupNotes = @()
if (Test-Path $script:NetCachePath) {
  try {
    $netCache = Get-Content $script:NetCachePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $knownIps = @($Machines | ForEach-Object { $_.HostName } | Where-Object { $_ })
    $added = 0
    foreach ($e in @($netCache.hosts)) {
      if (-not $e -or -not $e.rdp) { continue }
      if ($knownIps -contains $e.ip) { continue }
      # NOTE d'affichage VOLONTAIREMENT sobre : la MAC et le serveur parent ne
      # sont PAS ecrits sur la carte (ils sont deja visibles : la carte est dans
      # la colonne du serveur). Plus de mention "VM presumee" (non probant).
      $kindTxt = "poste du LAN"
      if ($e.vmname) { $kindTxt = "VM " + $e.vmname }
      # NOM du poste : celui stocke par le scan (reverse DNS) ; si le cache est
      # ancien (scan precedent sans ce champ), on retente la resolution ici.
      $nomHote = $e.name
      if (-not $nomHote) {
        # reverse DNS en ASYNCHRONE avec attente limitee : cet appel est fait sur
        # le FIL UI du launcher, un GetHostEntry synchrone qui pend gelerait toute
        # la fenetre (le DNS du LAN ne repond pas toujours).
        try {
          $arN = [System.Net.Dns]::BeginGetHostEntry($e.ip, $null, $null)
          if ($arN.AsyncWaitHandle.WaitOne(1200)) {
            $he = [System.Net.Dns]::EndGetHostEntry($arN)
            if ($he -and $he.HostName -and ($he.HostName -ne $e.ip)) { $nomHote = $he.HostName }
          }
        } catch { }
      }
      if ($nomHote) { $nomCourt = ($nomHote -split '\.')[0] } else { $nomCourt = ("PC-" + (($e.ip -split '\.')[-1])) }
      if ($nomCourt.Length -gt 14) { $nomCourt = $nomCourt.Substring(0, 14) }
      # LIEN avec un serveur de la config SSH : on ne rattache a la colonne d'un
      # hyperviseur que si le scan a CONFIRME le lien via libvirt (champ "via" =
      # ip ou mac : la VM est declaree dans virsh de l'hote).
      # Sans confirmation (MAC seulement, ou cache d'un ancien scan par table de
      # voisinage), la carte reste dans la colonne LAN grise : pas de faux rattachement.
      $grpLan = "LAN"; $colL = "#334155"; $dkL = "#263344"; $fgL = "#cbd5e1"
      $parentAlias = $null
      if ($e.parent -and $e.via) {
        $pm = @($Machines | Where-Object { $_.Host -eq $e.parent }) | Select-Object -First 1
        if ($pm) {
          $parentAlias = $e.parent
          $grpLan = $pm.Group
          $colL = $pm.Color; $dkL = $pm.Dark; $fgL = $pm.Fg
          # nom libvirt uniquement (WinServ2022, win11_q35-DevBis...) : le serveur
          # parent n'est pas repete, la carte est deja dans SA colonne
          if ($e.vmname) { $kindTxt = "VM " + $e.vmname } else { $kindTxt = "VM" }
        }
      }
      $Machines += [pscustomobject]@{
        Host = ""; HostName = $e.ip; User = $null; Port = $null; IdentityFile = $null
        Label = $nomCourt.ToUpper()
        Parent = $parentAlias; Group = $grpLan
        # L'IP est affichee sur la carte (label role) : c'est la cible du RDP.
        # "Windows" n'est pas repete : l'icone de la carte l'indique deja.
        Role = ($e.ip + " - RDP - " + $kindTxt)
        Color = $colL; Dark = $dkL; Fg = $fgL
        IconType = "pc"; OsType = "windows"; RdpIp = $e.ip
      }
      $added = $added + 1
    }
    $ageH = 0
    try { $ageH = [int]((Get-Date) - [datetime]::Parse($netCache.ts)).TotalHours } catch { }
    $script:StartupNotes += ("cache LAN (" + $script:NetCachePath + ", age " + $ageH + " h) : " + $added + " machine(s) Windows/RDP reprise(s)")
    # ATTRIBUTION des machines DEJA listees dans .ssh/config : le scan a resolu
    # leur hyperviseur libvirt -> leur carte est DEPLACEE dans la colonne de ce
    # serveur (et son role precisera de quelle VM il s'agit).
    $moved = 0
    foreach ($a in @($netCache.attrib)) {
      if (-not $a -or -not $a.parent -or -not $a.via) { continue }
      $mm2 = @($Machines | Where-Object { $_.HostName -eq $a.ip }) | Select-Object -First 1
      $pm2 = @($Machines | Where-Object { $_.Host -eq $a.parent }) | Select-Object -First 1
      if (-not $mm2 -or -not $pm2) { continue }
      # SECURITE : un hyperviseur ne doit jamais etre rattache a lui-meme (sa
      # propre IP est dans la liste a attribuer ; un lien MAC errone le
      # transformerait en VM de lui-meme).
      if ($mm2.Host -eq $a.parent) { continue }
      $mm2.Group = $pm2.Group
      $mm2.Parent = $a.parent
      # PAS de OsType ici : ces machines sont accessibles en SSH (elles sont
      # dans .ssh/config) -> Linux. libvirt ne dit RIEN de l'OS : la VM peut etre
      # Linux ou Windows. Forcer "windows" faisait passer des machines Linux pour
      # des Windows (regression constatee). Seules les cartes issues du SCAN RDP
      # (port 3389 ouvert) recoivent OsType = windows.
      $mm2.IconType = "pc"
      # note sobre : nom libvirt seulement (ni MAC, ni "hebergee par X" : la
      # carte est deja placee dans la colonne du serveur parent)
      $mm2.Role = $(if ($a.vmname) { "VM " + $a.vmname } else { "VM heberge" })
      $moved = $moved + 1
    }
    if ($moved -gt 0) { $script:StartupNotes += ("attribution libvirt : " + $moved + " machine(s) deplacee(s) dans la colonne de leur hyperviseur") }
    # rejoue le diagnostic du SCAN PRECEDENT (le job ne tourne qu'une fois par
    # processus : sans cela, un scan saute ne laisserait aucun indice)
    if ($netCache.diag) {
      foreach ($d in @($netCache.diag)) { $script:StartupNotes += ("cache scan: " + $d) }
    }
    if ($netCache.attrib) {
      foreach ($a in @($netCache.attrib)) {
        $script:StartupNotes += ("cache attrib: " + $a.ip + " -> " + $(if ($a.parent) { "VM '" + $a.vmname + "' sur " + $a.parent + " (" + $a.via + ")" } else { "non rattachee" }))
      }
    }
  } catch {
    $script:StartupNotes += ("cache LAN illisible : " + $_.Exception.Message)
  }
}
}
. $script:MergeLanCache

