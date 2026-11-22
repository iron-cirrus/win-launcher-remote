# 07-mstsc.ps1 - mstsc (RDP) sur les ecrans selectionnes
# Fichier charge par vsc_launcher.ps1 (dot-source : meme portee script). Lignes d'origine 1174-1241.

# ---------- MSTSC SUR LES ECRANS SELECTIONNES ----------
# mstsc ne sait ouvrir une session que sur des ecrans CONTIGUS, designes dans un fichier .rdp
# ("use multimon:i:1" + "selectedmonitors:s:<ids>"). Le launcher genere ce fichier depuis la meme
# selection d'ecrans que Moonlight (mini-carte) : un fichier par machine dans le dossier ci-dessous.
# ATTENTION aux identifiants : ceux de mstsc (liste "mstsc /l") ne sont PAS les numeros Windows
# des ecrans. Par defaut le launcher suppose l'ordre des numeros Windows : le 1er ecran (n°
# Windows le plus petit) = id 0, le 2e = id 1, etc. ; MstscMonitorIdBase decale cette numerotation
# (1 si "mstsc /l" commence a 1). Si mstsc ouvre les mauvais ecrans, relever les ids avec
# "mstsc /l" et les saisir ici : $script:MstscMonitorIdMap = @{ 1 = 0; 2 = 1; 3 = 2; 4 = 3 }
# (numero Windows -> id mstsc).
$script:RdpDir = Join-Path $env:LOCALAPPDATA "vsc-launcher\rdp"
$script:MstscMonitorIdBase = 0
$script:MstscMonitorIdMap = @{}
$script:MstscIdsFor = {
  param($sel)
  $all = @($script:Screens | Sort-Object Idx)
  $ids = @()
  foreach ($i in @($sel.Idxs)) {
    if ($script:MstscMonitorIdMap.ContainsKey([int]$i)) { $ids += [int]$script:MstscMonitorIdMap[[int]$i]; continue }
    $pos = 0
    for ($k = 0; $k -lt $all.Count; $k++) { if ($all[$k].Idx -eq $i) { $pos = $k } }
    $ids += ($pos + [int]$script:MstscMonitorIdBase)
  }
  return ,@($ids | Sort-Object)
}
# Ouvre mstsc vers $ip. $useScreens : utiliser la selection d'ecrans (dernier choix memorise, sinon
# ecran principal) ; sinon mstsc simple (fenetre normale, comme avant).
$script:OpenMstsc = {
  param([string]$ip, [bool]$useScreens = $true)
  $script:Screens = & $script:GetScreens
  $sel = $(if ($useScreens) { & $script:ResolveSelection $ip @() } else { $null })
  if (-not $sel) {
    & $script:LogFn ("RDP: mstsc /v:" + $ip)
    if ($script:WinHostDryRun) { & $script:LogFn "  [essai] mstsc non lance"; return }
    try { Start-Process mstsc.exe -ArgumentList ("/v:" + $ip) } catch { & $script:LogFn ("  ECHEC RDP: " + $_.Exception.Message) }
    return
  }
  $ids = & $script:MstscIdsFor $sel
  $rdp = "screen mode id:i:2`r`nuse multimon:i:1`r`nselectedmonitors:s:" + ($ids -join ',') + "`r`n" +
    "desktopwidth:i:" + $sel.PW + "`r`ndesktopheight:i:" + $sel.PH + "`r`nsession bpp:i:32`r`n" +
    "full address:s:" + $ip + "`r`ndisplayconnectionbar:i:1`r`nredirectclipboard:i:1`r`n"
  $file = Join-Path $script:RdpDir (($ip -replace '[^0-9A-Za-z\.\-]', '_') + ".rdp")
  try {
    if (-not (Test-Path $script:RdpDir)) { New-Item -ItemType Directory -Path $script:RdpDir -Force | Out-Null }
    [System.IO.File]::WriteAllText($file, $rdp, [System.Text.Encoding]::ASCII)
  } catch {
    & $script:LogFn ("RDP: ecriture du fichier .rdp impossible (" + $_.Exception.Message + ") -> mstsc simple")
    if (-not $script:WinHostDryRun) { try { Start-Process mstsc.exe -ArgumentList ("/v:" + $ip) } catch { } }
    return
  }
  & $script:LogFn ("RDP: mstsc sur les ecrans " + ($sel.Idxs -join '+') + " (ensemble " + $sel.PW + "x" + $sel.PH + " ; ids mstsc " + ($ids -join ',') + ", a verifier avec 'mstsc /l') -> " + $file)
  if ($script:WinHostDryRun) { & $script:LogFn "  [essai] mstsc non lance"; return }
  try {
    $p = Start-Process mstsc.exe -ArgumentList ('"' + $file + '"') -PassThru
    $script:RdpState[$ip] = [pscustomobject]@{ Idxs = @($sel.Idxs); Proc = $p; Since = (Get-Date) }
    & $script:LogFn ("Etat mstsc " + $ip + " : ouvert (ecrans " + ($sel.Idxs -join '+') + ")")
    if ($script:RefreshTop) { & $script:RefreshTop }
  } catch { & $script:LogFn ("  ECHEC RDP: " + $_.Exception.Message) }
}
# Repli RDP (mstsc) : script-level car appele aussi apres un lancement differe. La selection
# d'ecrans n'est appliquee que si l'utilisateur en a memorise une pour cette machine.
$script:RdpFallback = {
  param([string]$ip, [string]$why)
  # machine Linux (Sunshine) : pas de Bureau a distance Windows -> on explique et on s'arrete
  if ($script:NoRdp -and $script:NoRdp.ContainsKey($ip)) { & $script:LogFn ("Moonlight/Sunshine " + $ip + " : " + $why + " (machine Linux : pas de repli mstsc)"); return }
  & $script:LogFn ("RDP: mstsc (" + $why + ")")
  & $script:OpenMstsc $ip ([bool]$script:ScreenChoice.ContainsKey($ip))
}
