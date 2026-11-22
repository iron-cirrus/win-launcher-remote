# ui-40-scan-lan.ps1 - BuildUI : scan du LAN en tache de fond (RDP 3389)
# Fichier charge par vsc_launcher.ps1 (dot-source : meme portee script). Lignes d'origine 2706-3100.

# ---------- Scan du LAN en tache de fond : postes WINDOWS (port RDP 3389) ----------
# TcpClient asynchrone : les 254 connexions du /24 sont demarrees d'un coup puis
# collectees -> scan complet en ~2 s. Pour chaque hote RDP ouvert :
#  - MAC via arp -> OUI : 52:54:00 (QEMU/KVM), 08:00:27 (VirtualBox),
#    00:0C:29 / 00:50:56 (VMware), 00:15:5D (Hyper-V) = VM hebergees,
#    sinon poste natif ;
#  - tracert (-h 4) : nb de sauts (1 = direct, >1 = derriere un hote = VM NAT).
# Le resultat est ecrit dans le cache JSON : les nouvelles cartes apparaissent
# au demarrage suivant du launcher (le scan n'est relance que si cache > 24 h).
$script:NetScanBlock = {
  param([string]$prefix, [string[]]$exclude, [string]$cachePath, [string[]]$hypList, [string[]]$attribList)
  $ErrorActionPreference = "SilentlyContinue"
  # ---------- GARDE-FOU ANTI-BLOCAGE ----------
  # Aucun appel systeme ne doit pouvoir pendre : chaque commande externe passe
  # par RunCmd, qui TUE le processus au bout de N secondes ; les resolutions DNS
  # se font en asynchrone avec attente limitee (GetHostEntry synchrone peut pendre
  # de longues secondes quand le DNS du LAN ne repond pas).
  # DEADLINE globale du scan : au-dela, on cesse tout appel ssh restant et on
  # ecrit le cache avec ce qui est deja connu.
  $scanStart = Get-Date
  $scanBudgetSec = 300
  function RunCmd {
    param([string]$exe, [string[]]$a, [int]$sec)
    $g = [guid]::NewGuid().ToString("N")
    $oF = Join-Path $env:TEMP ("job-out-" + $g + ".txt")
    # stderr dans un FICHIER SEPARRE :RedirectStandardOutput et
    # -RedirectStandardError vers le MEME fichier font parfois echouer
    # Start-Process (conflit d'acces Windows) -> sortie 0 caractere et
    # diagnostics vides (regression scan 2026-11-13).
    $eF = Join-Path $env:TEMP ("job-err-" + $g + ".txt")
    $iF = Join-Path $env:TEMP ("job-in-" + $g + ".txt")
    [System.IO.File]::WriteAllText($iF, "")
    $aStr = ($a | ForEach-Object { if ($_ -match '\s') { ([string][char]34) + $_ + ([string][char]34) } else { $_ } }) -join ' '
    try {
      $p = Start-Process -FilePath $exe -ArgumentList $aStr -NoNewWindow -PassThru -RedirectStandardOutput $oF -RedirectStandardError $eF -RedirectStandardInput $iF
    } catch { return "" }
    if (-not $p.WaitForExit($sec * 1000)) {
      try { $p.Kill() } catch { }
      try { $p.WaitForExit() } catch { }
      Remove-Item $oF, $eF, $iF -Force -ErrorAction SilentlyContinue
      return ("__TIMEOUT__ " + $exe + " tue apres " + $sec + " s")
    }
    try { $p.WaitForExit() } catch { }
    $txt = ""
    try { $txt = (Get-Content $oF -Raw -ErrorAction SilentlyContinue) + "" } catch { }
    try { $txt += (Get-Content $eF -Raw -ErrorAction SilentlyContinue) + "" } catch { }
    Remove-Item $oF, $eF, $iF -Force -ErrorAction SilentlyContinue
    return $txt
  }
  function Resolve-Name {
    param([string]$ipA, [int]$ms)
    try {
      $ar = [System.Net.Dns]::BeginGetHostEntry($ipA, $null, $null)
      if (-not $ar.AsyncWaitHandle.WaitOne($ms)) { return $null }
      $he = [System.Net.Dns]::EndGetHostEntry($ar)
      if ($he -and $he.HostName -and ($he.HostName -ne $ipA)) { return $he.HostName }
    } catch { }
    return $null
  }
  function ScanOver { return ((Get-Date) - $scanStart).TotalSeconds -gt $scanBudgetSec }
  $diag = @()
  $diag += ("scan : sous-reseau " + $prefix + ".1-254 | excludes " + (@($exclude).Count) + " | hotes a interroger " + (@($hypList).Count) + " (" + (($hypList | ForEach-Object { ($_ -split '\|')[0] }) -join ', ') + ") | a attribuer " + (@($attribList).Count))
  # MAC d'une IP du LAN : ligne exacte "<ip> <mac>" de la table ARP globale
  # (ARP Windows parfois vide pour une IP peu vue), puis 'arp -a <ip>'.
  # NOTE: la regex doit etre ANCREE PAR LIGNE (decoupage ligne a ligne) : une
  # regex '(?i)^...' appliquee a toute la chaine ne matche jamais, et le repli
  # ramasse la 1re MAC de la table = la PASSERELLE -> faux rattachements.
  $arpTableTxt = RunCmd "arp" @("-a") 10
  $arpLines = @($arpTableTxt -split "`r?`n")
  function Get-LanMac([string]$ipA) {
    $ipRe = [regex]::Escape($ipA)
    foreach ($ln in $arpLines) {
      $mm = [regex]::Match($ln, ('(?i)^\s*' + $ipRe + '\s+((?:[0-9a-fA-F]{2}[-:]){5}[0-9a-fA-F]{2})'))
      if ($mm.Success) { return ($mm.Groups[1].Value -replace '-', ':').ToUpper() }
    }
    $arpOne = RunCmd "arp" @("-a", $ipA) 8
    $mm2 = [regex]::Match($arpOne, ('(?im)^\s*' + $ipRe + '\s+((?:[0-9a-fA-F]{2}[-:]){5}[0-9a-fA-F]{2})'))
    if ($mm2.Success) { return ($mm2.Groups[1].Value -replace '-', ':').ToUpper() }
    return $null
  }
  $ips = @()
  for ($i = 1; $i -le 254; $i++) {
    $ip = $prefix + "." + $i
    if ($exclude -notcontains $ip) { $ips += $ip }
  }
  # 1) RDP 3389 : toutes les connexions demarrees en parallele, puis collecte
  $sock = @{}
  $pend = @()
  foreach ($ip in $ips) {
    $t = New-Object System.Net.Sockets.TcpClient
    $a = $t.BeginConnect($ip, 3389, $null, $null)
    if ($a) { $sock[$ip] = @{ Tcp = $t; Ar = $a }; $pend += $ip }
  }
  $rdpOpen = @()
  foreach ($ip in $pend) {
    $s = $sock[$ip]
    $ok = $false
    if ($s.Ar.AsyncWaitHandle.WaitOne(1500)) {
      try { $s.Tcp.EndConnect($s.Ar); $ok = $true } catch { }
    }
    try { $s.Tcp.Close() } catch { }
    if ($ok) { $rdpOpen += $ip }
  }
  $diag += ("sonde RDP 3389 : " + $pend.Count + " IP testees -> " + $rdpOpen.Count + " port(s) OUVERT(s)" + $(if ($rdpOpen.Count -gt 0) { " (" + ($rdpOpen -join ', ') + ")" } else { "  <-- AUCUN : pare-feu qui filtre 3389 ou sous-reseau incorrect" }))
  $diag += ("ARP local : " + (@($arpLines | Where-Object { $_ -match '([0-9a-fA-F]{2}[-:]){5}[0-9a-fA-F]{2}' }).Count) + " entree(s)")
  # 2) VM REELLEMENT DEFINIES chez chaque hyperviseur de .ssh/config.
  # PIPI GEOLE : ip neigh/arp du routeur (passerelle du LAN) contient la MAC de
  # TOUTES les machines du reseau -> rattachement abusif de postes natifs au
  # routeur. On interroge donc libvirt : les seules MAC/IP que l'hote DECLARE
  # comme ses propres VM (domiflist = MAC attribuee, domifaddr + baux DHCP = IP).
  $macToHyp = @{}
  $vmIpToHyp = @{}
  $hypIpToAlias = @{}
  # nom libvirt de la VM (domiflist/domifaddr/leases rattaches a la balise VM:)
  $macToVm = @{}
  $ipToVm = @{}
  foreach ($h in @($hypList)) {
    $parts = ($h -split '\|')
    $aliasH = $parts[0]
    if ($parts.Count -gt 1 -and $parts[1]) { $hypIpToAlias[$parts[1]] = $aliasH }
    $cmd = 'for d in $(virsh -c qemu:///system list --all --name 2>/dev/null || sudo -n virsh -c qemu:///system list --all --name 2>/dev/null); do echo "VM:$d"; virsh -c qemu:///system domiflist $d 2>/dev/null; virsh -c qemu:///system domifaddr $d 2>/dev/null; done; for n in $(virsh -c qemu:///system net-list --name 2>/dev/null || sudo -n virsh -c qemu:///system net-list --name 2>/dev/null); do virsh -c qemu:///system net-dhcp-leases $n 2>/dev/null; done'
    # BUDGET : si le scan a deja depasse son plafond, on ne relance plus de ssh
    if (((Get-Date) - $scanStart).TotalSeconds -gt $scanBudgetSec) {
      $diag += ("ssh " + $aliasH + " : BUDGET de scan (" + $scanBudgetSec + " s) depasse -> non interroge")
      continue
    }
    # ConnectTimeout ne couvre que l'etablissement de la connexion : une commande
    # distante qui pend (virsh sur un hyperviseur sature) bloquerait le job sans
    # fin -> RunCmd tue le ssh au bout de 30 s.
    $nbOut = RunCmd "ssh" @("-n", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-o", "NumberOfPasswordPrompts=0", "-o", "StrictHostKeyChecking=accept-new", $aliasH, $cmd) 30
    # DIAGNOSTIC : ce que l'hote a vraiment repondu (virsh absent ? droits ?)
    $nVm = ([regex]::Matches($nbOut, '(?m)^\s*VM:')).Count
    $errTxt = ""
    foreach ($pat in @('command not found', 'not found', 'permission denied', 'Failed to connect', 'could not resolve', 'timed out', 'Connection refused', 'Identity file')) {
      if ($nbOut -imatch $pat) { $errTxt += " [" + $pat + "]" }
    }
    $diag += ("ssh " + $aliasH + " : " + $nVm + " VM declaree(s), sortie " + $nbOut.Length + " caractere(s)" + $(if ($errTxt) { " ERREURS:" + $errTxt } else { "" }))
    if ($nVm -eq 0) {
      $premieres = (($nbOut -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 3) -join ' // ')
      $diag += ("  sortie brute " + $aliasH + " : " + $premieres)
    }
    # sortie = blocs "VM:<nom>" suivis des interfaces (MAC) et adresses (IP)
    $curVm = ""
    foreach ($line in ($nbOut -split "`r?`n")) {
      if ($line -match '^\s*VM:(.+)$') { $curVm = $Matches[1].Trim(); continue }
      if (-not $curVm) {
        # baux DHCP hors bloc VM : rattaches a l'hyperviseur quand meme
        foreach ($mi in [regex]::Matches($line, '([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}')) {
          $k = ($mi.Value -replace '-', ':').ToUpper()
          if (-not $macToHyp.ContainsKey($k)) { $macToHyp[$k] = $aliasH }
        }
        continue
      }
      foreach ($mi in [regex]::Matches($line, '([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}')) {
        $k = ($mi.Value -replace '-', ':').ToUpper()
        if (-not $macToHyp.ContainsKey($k)) { $macToHyp[$k] = $aliasH }
        if (-not $macToVm.ContainsKey($k)) { $macToVm[$k] = $curVm }
      }
      foreach ($ii in [regex]::Matches($line, '\b(\d{1,3}(?:\.\d{1,3}){3})\b')) {
        $ipK = $ii.Groups[1].Value
        if (-not $vmIpToHyp.ContainsKey($ipK)) { $vmIpToHyp[$ipK] = $aliasH }
        if (-not $ipToVm.ContainsKey($ipK)) { $ipToVm[$ipK] = $curVm }
      }
    }
  }
  # 3) pour chaque hote RDP : MAC/OUI (VM ou natif) + tracert (sauts) + nom + parent
  # Table ARP complete lue UNE fois : 'arp -a <ip>' rentre parfois bredouille
  # (cache Windows non peuple / resolution par nom) alors que la ligne existe
  # dans la table globale.
  $hosts = @()
  $diagMac = @()   # diagnostic : MAC resolvee localement pour chaque hote RDP
  foreach ($ip in $rdpOpen) {
    $mac = Get-LanMac $ip
    $diagMac += ($ip + " mac_local=" + $(if ($mac) { $mac } else { "AUCUNE (ARP vide)" }))
    $kind = "poste"
    if ($mac) {
      $oui = $mac.Substring(0, 8)
      if (@("52:54:00", "08:00:27", "00:0C:29", "00:50:56", "00:15:5D", "00:1C:42") -contains $oui) { $kind = "vm" }
    }
    $trOut = ""
    if (-not (((Get-Date) - $scanStart).TotalSeconds -gt $scanBudgetSec)) {
      $trOut = RunCmd "tracert" @("-d", "-h", "4", "-w", "800", $ip) 12
    }
    $hops = ([regex]::Matches($trOut, '(?m)^\s*\d+\s')).Count
    # reverse DNS : nom du poste, en ASYNCHRONE avec attente limitee (le DNS
    # synchrone peut pendre de longues secondes si le serveur du LAN ne repond pas)
    $name = Resolve-Name $ip 1200
    # PARENT (hyperviseur deja dans .ssh/config) : SEULEMENT si l'hote libvirt de
    # cet hyperviseur declare cette MAC ou cette IP comme une de SES VM.
    # (plus de table de voisinage : le routeur passerelle voit tout le LAN)
    $parent = $null
    $vmName = $null
    if ($vmIpToHyp.ContainsKey($ip)) { $parent = $vmIpToHyp[$ip]; $vmName = $ipToVm[$ip] }
    if (-not $parent -and $mac -and $macToHyp.ContainsKey($mac)) {
      $parent = $macToHyp[$mac]; $vmName = $macToVm[$mac]
    }
    # diagnostic : pourquoi le lien n'a PAS marche (MAC absente de la table
    # libvirt ? MAC inconnue ? OUI non virtuel ?)
    if (-not $parent) {
      $why = "mac=" + $(if ($mac) { $mac } else { "inconnue" })
      if ($mac -and -not $macToHyp.ContainsKey($mac)) { $why += " -> absente des domiflist de TOUS les hotes" }
      if ($mac) { $why += " | oui=" + $mac.Substring(0, [Math]::Min(8, $mac.Length)) }
      $why += " | vmDeclarees=" + $macToHyp.Count + " mac, " + $vmIpToHyp.Count + " ip"
      $diagMac += ($ip + " NON rattache : " + $why)
    }
    if (-not $parent -and $hops -ge 3) {
      # VM derriere un hote (NAT) : le tracert passe par l'hyperviseur lui-meme
      $hopIps = @([regex]::Matches($trOut, '\((\d{1,3}(?:\.\d{1,3}){3})\)') | ForEach-Object { $_.Groups[1].Value })
      foreach ($hi in $hopIps) {
        if ($hi -ne $ip -and $hypIpToAlias.ContainsKey($hi)) { $parent = $hypIpToAlias[$hi]; break }
      }
    }
    # kind : vm CONFIRMEE (parent libvirt) / vm PRESUMEE (MAC virtuelle sans
    # hyperviseur declarant) / poste natif
    if ($parent) { $kind = "vm" }
    $via = $null
    if ($parent) {
      if ($vmIpToHyp.ContainsKey($ip)) { $via = "ip" } else { $via = "mac" }
    }
    $hosts += [pscustomobject]@{ ip = $ip; mac = $mac; kind = $kind; hops = $hops; rdp = $true; name = $name; parent = $parent; via = $via; vmname = $vmName }
  }
  # 4) 2e PASSE pour les hotes NON rattaches : le lien par MAC a pu echouer car
  # le cache ARP de Windows etait vide (poste peu vu). On redemande la MAC de
  # l'IP PRECISE a chaque hyperviseur (ip neigh show <ip> : requete CIBLEE, pas la
  # table entiere -> pas du tout le probleme de la passerelle) puis on teste si
  # cette MAC appartient aux VM declarees de cet hote.
  for ($idx = 0; $idx -lt $hosts.Count; $idx++) {
    $hh = $hosts[$idx]
    if ($hh.parent) { continue }
    foreach ($h in @($hypList)) {
      $aliasH = ($h -split '\|')[0]
      if (((Get-Date) - $scanStart).TotalSeconds -gt $scanBudgetSec) { break }
      $nbOut = RunCmd "ssh" @("-n", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-o", "NumberOfPasswordPrompts=0", "-o", "StrictHostKeyChecking=accept-new", $aliasH, ("ip -4 neigh show " + $hh.ip + " 2>/dev/null; arp -n -i 0 " + $hh.ip + " 2>/dev/null")) 20
      $mm = [regex]::Match($nbOut, '([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}')
      if (-not $mm.Success) { continue }
      $mKey = ($mm.Value -replace '-', ':').ToUpper()
      if ($macToHyp.ContainsKey($mKey) -and ($macToHyp[$mKey] -eq $aliasH)) {
        $hh.mac = $mKey
        $hh.parent = $aliasH
        $hh.kind = "vm"
        $hh.via = "mac"
        $hh.vmname = $macToVm[$mKey]
        $hosts[$idx] = $hh
        break
      }
    }
  }
  # 5) ATTRIBUTION DES MACHINES DEJA DANS .ssh/config (alias = IP brute comme
  # 192.168.5.13) : elles sont EXCLUES du scan RDP (deja connues) donc ne
  # seraient JAMAIS rattachees a leur hyperviseur. On resout quand meme leur MAC
  # et on les rattache via libvirt -> le launcher deplace leur CARTE SSH dans la
  # colonne du serveur qui les heberge.
  $attrib = @()
  foreach ($ipA in @($attribList)) {
    if (-not $ipA) { continue }
    $mA = Get-LanMac $ipA
    $parA = $null; $vmA = $null; $viaA = $null
    if ($vmIpToHyp.ContainsKey($ipA)) { $parA = $vmIpToHyp[$ipA]; $vmA = $ipToVm[$ipA]; $viaA = "ip" }
    if (-not $parA -and $mA -and $macToHyp.ContainsKey($mA)) {
      $parA = $macToHyp[$mA]; $vmA = $macToVm[$mA]; $viaA = "mac"
    }
    if (-not $parA -and $mA) {
      # 2e passe ciblee sur l'hyperviseur (ip neigh show <ip>)
      foreach ($h in @($hypList)) {
        $aliasH = ($h -split '\|')[0]
        if (((Get-Date) - $scanStart).TotalSeconds -gt $scanBudgetSec) { break }
        $nbOut = RunCmd "ssh" @("-n", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-o", "NumberOfPasswordPrompts=0", "-o", "StrictHostKeyChecking=accept-new", $aliasH, ("ip -4 neigh show " + $ipA + " 2>/dev/null; arp -n -i 0 " + $ipA + " 2>/dev/null")) 20
        $mm = [regex]::Match($nbOut, '([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}')
        if (-not $mm.Success) { continue }
        $mKey = ($mm.Value -replace '-', ':').ToUpper()
        if ($macToHyp.ContainsKey($mKey) -and ($macToHyp[$mKey] -eq $aliasH)) {
          $mA = $mKey; $parA = $aliasH; $vmA = $macToVm[$mKey]; $viaA = "mac"; break
        }
      }
    }
    $attrib += [pscustomobject]@{ ip = $ipA; mac = $mA; parent = $parA; vmname = $vmA; via = $viaA }
    $diag += ("attrib " + $ipA + " : mac=" + $(if ($mA) { $mA } else { "?" }) +
      " -> " + $(if ($parA) { "VM '" + $vmA + "' sur " + $parA + " (preuve " + $viaA + ")" } else { "AUCUN hote libvirt ne la declare" }))
  }
  # DIAGNOSTIC : rend compte de ce que libvirt a bien voulu donner par hote
  # (remonte dans le log du launcher pour debugger les rattachements absents)
  foreach ($d2 in $diagMac) { $diag += $d2 }
  $diag += ("table libvirt : " + $macToHyp.Count + " MAC -> " + (($macToHyp.Keys | Select-Object -First 40 | ForEach-Object { $_ + "=" + $macToHyp[$_] + "/" + $macToVm[$_] }) -join ' ; '))
  foreach ($h in @($hypList)) {
    $aliasH = ($h -split '\|')[0]
    $nMac = 0; $nIp = 0
    foreach ($k in $macToHyp.Keys) { if ($macToHyp[$k] -eq $aliasH) { $nMac++ } }
    foreach ($k in $vmIpToHyp.Keys) { if ($vmIpToHyp[$k] -eq $aliasH) { $nIp++ } }
    $diag += ($aliasH + " : " + $nMac + " MAC / " + $nIp + " IP de VM declarees par libvirt")
  }
  $diag += ("hotes RDP : " + $hosts.Count + " | rattaches a un hote : " + (@($hosts | Where-Object { $_.parent }).Count))
  # CONSERVATION : un poste vu aux scans precedents mais absent du scan en cours
  # (PC endormi / hors reseau au moment du scan) est REPORTE dans le cache :
  # sinon sa carte disparaitrait alors qu'il existe reellement.
  # CONSERVATION DES ATTRIBUTIONS : un scan rate (ssh muet, ARP vide, budget
  # depasse) ne doit PAS effacer un rattachement libvirt DEJA prouve par un
  # scan precedent : sans cela, une VM deja rattachee a son hyperviseur
  # "retombait" dans la colonne LAN (regression win11_q35, 2026-11-13).
  $prev = @()
  if (Test-Path $cachePath) {
    try {
      $newIps = @($hosts | ForEach-Object { $_.ip })
      $pc = Get-Content $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json
      $prev = @($pc.hosts | Where-Object { $_ -and $_.rdp -and ($newIps -notcontains $_.ip) })
      $kept = 0
      foreach ($pa in @($pc.attrib)) {
        if (-not $pa -or -not $pa.parent -or -not $pa.via) { continue }
        for ($ai = 0; $ai -lt $attrib.Count; $ai++) {
          if ($attrib[$ai].ip -eq $pa.ip -and -not $attrib[$ai].parent) {
            $attrib[$ai].parent = $pa.parent
            $attrib[$ai].vmname = $pa.vmname
            if (-not $attrib[$ai].mac) { $attrib[$ai].mac = $pa.mac }
            $attrib[$ai].via = $pa.via + "+cache"
            $kept++
            break
          }
        }
      }
      if ($kept -gt 0) { $diag += ("conservation attrib : " + $kept + " rattachement(s) libvirt represse(s) par ce scan ont ete restaures depuis le cache") }
    } catch { }
  }
  $res = [pscustomobject]@{ ts = (Get-Date).ToString("o"); subnet = $prefix; hosts = @($hosts + $prev); attrib = @($attrib); diag = @($diag) }
  $dirCache = Split-Path $cachePath -Parent
  if (-not (Test-Path $dirCache)) { New-Item -ItemType Directory -Path $dirCache -Force | Out-Null }
  [System.IO.File]::WriteAllText($cachePath, ($res | ConvertTo-Json -Depth 4))
  return $res
}
$script:NetScanJob = $null
$netPrefix = $null
try {
  $lip = $null
  # PERF : Get-NetIPAddress (CIM) coutait ~1,4 s au demarrage ; l'API .NET
  # NetworkInterface donne la meme information en quelques millisecondes.
  try {
    foreach ($ni in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
      if ($ni.OperationalStatus -ne [System.Net.NetworkInformation.OperationalStatus]::Up) { continue }
      foreach ($ua in $ni.GetIPProperties().UnicastAddresses) {
        if ($ua.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
            $ua.Address.ToString() -like "192.168.*") { $lip = $ua.Address.ToString(); break }
      }
      if ($lip) { break }
    }
  } catch { }
  if (-not $lip) {
    $lip = ([System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
      Where-Object { $_.AddressFamily -eq 'InterNetwork' -and $_.IPAddressToString -like '192.168.*' } |
      Select-Object -First 1).IPAddressToString
  }
  if ($lip) { $netPrefix = (($lip -split '\.')[0..2] -join '.') }
} catch { }
# Regles de scan LAN :
#  - scan lance a CHAQUE demarrage, mais le cache n'est JAMAIS efface : il sert
#    de base (le job y reporte les postes non vus) et la fusion saute les IP deja
#    connues -> la liste LAN ne disparait jamais ;
#  - une seule serie de scan par processus : apres la reconstruction d'affichage,
#    $script:ScanLaunched empeche de relancer le job.
$script:NetNoScan = ($args -contains '-noscan')
# DIAGNOSTIC DE DECISION (le log montrait "scan LAN deja effectue" sans scan
# lance : il faut savoir pourquoi). IP locale + sous-reseau + etat du drapeau.
& $script:LogFn ("scan LAN : IP locale=" + $(if ($lip) { $lip } else { "NON TROUVEE (aucune 192.168.*)" }) +
  " sous-reseau=" + $(if ($netPrefix) { $netPrefix } else { "?" }) +
  " argument-noscan=" + $script:NetNoScan +
  " scan-deja-lance=" + $(if ($script:ScanLaunched) { "OUI" } else { "non" }) +
  " cache=" + $(if (Test-Path $script:NetCachePath) { "present" } else { "absent" }))
if ($netPrefix -and (-not $script:NetNoScan) -and (-not $script:ScanLaunched)) {
  $script:ScanLaunched = $true
  $netExcl = @(@($Machines | ForEach-Object { $_.HostName } | Where-Object { $_ }) + @($lip))
  # hyperviseurs a interroger (ssh <alias> "ip neigh") : les serveurs physiques
  # de la config, transmis sous forme "alias|ip" pour le repli par saut traceroute
  $netHyp = @($Machines | Where-Object { $_.Host -and $_.IconType -eq 'srv' } |
    ForEach-Object { $_.Host + "|" + $_.HostName })
  # machines DEJA connues dont l'HostName est une IP du sous-reseau scannage :
  # elles ne seront pas testees en RDP mais seront QUAND MEME rattachees a leur
  # hyperviseur libvirt (ex: alias "192.168.5.13" = VM Windows de Kvm-Gpu).
  $netAttrib = @($Machines | Where-Object { $_.HostName -and ($_.HostName -match ('^' + [regex]::Escape($netPrefix) + '\.')) } |
    ForEach-Object { $_.HostName } | Select-Object -Unique)
  & $script:LogFn ("scan LAN : attribution libvirt preparee pour " + $netAttrib.Count + " machine(s) deja connue(s) : " + ($netAttrib -join ', '))
  $script:NetScanJob = Start-Job -ScriptBlock $script:NetScanBlock -ArgumentList $netPrefix, $netExcl, $script:NetCachePath, $netHyp, $netAttrib
  & $script:LogFn ("scan LAN lance en tache de fond : " + $netPrefix + ".1-254, port RDP 3389 (cache : " + $script:NetCachePath + ")")
  & $script:LogFn "  -> l'affichage sera reconstruit automatiquement a la fin du scan"
} elseif ($netPrefix) {
  & $script:LogFn "scan LAN deja effectue dans ce processus : reconstruction sans rescanner"
} else {
  & $script:LogFn "scan LAN impossible : aucun sous-reseau 192.168.* detecte"
}

# deplacement en glissant le fond (attache UNE fois : la fenetre n'est pas recreee)
if (-not $script:Rebuild) {
  $form.Add_MouseDown({
    if ($script:UiFullscreen) { return }      # plein ecran sur l'ecran d'accueil : pas de deplacement
    [VscWinV4]::ReleaseCapture() | Out-Null
    [VscWinV4]::SendMessage($this.Handle, 0x0112, 0xF012, 0) | Out-Null   # WM_NCLBUTTONDOWN + HTCAPTION
  })
}

