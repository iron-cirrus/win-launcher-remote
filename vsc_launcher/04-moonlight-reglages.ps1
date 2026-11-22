# 04-moonlight-reglages.ps1 - ConvertTo-DrawingColor, chemin de code.exe, constantes et reglages Moonlight
# Fichier charge par vsc_launcher.ps1 (dot-source : meme portee script). Lignes d'origine 430-484.

function ConvertTo-DrawingColor([string]$hex) {
  $h = $hex.TrimStart('#')
  [System.Drawing.Color]::FromArgb(
    [Convert]::ToInt32($h.Substring(0,2),16),
    [Convert]::ToInt32($h.Substring(2,2),16),
    [Convert]::ToInt32($h.Substring(4,2),16))
}

# Resolu UNE FOIS au niveau script (les handlers n'appellent aucune fonction)
$script:CodeExe = $null
try { $script:CodeExe = (Get-Command code -ErrorAction Stop).Source } catch { }

# ---------- Machines WINDOWS : Moonlight (Apollo/Sunshine) si possible, sinon RDP ----------
# Client Moonlight Qt de CE poste : emplacements d'installation usuels, puis PATH.
$script:MoonlightExe = $null
foreach ($cand in @(
    (Join-Path $env:ProgramFiles "Moonlight Game Streaming\Moonlight.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "Moonlight Game Streaming\Moonlight.exe"),
    (Join-Path $env:LOCALAPPDATA "Programs\Moonlight Game Streaming\Moonlight.exe"))) {
  if ($cand -and (Test-Path $cand)) { $script:MoonlightExe = $cand; break }
}
if (-not $script:MoonlightExe) {
  try { $script:MoonlightExe = (Get-Command Moonlight.exe -ErrorAction Stop).Source } catch { }
}
# Application a lancer sur l'hote. "Virtual Display" (Apollo) cree un ecran virtuel a la
# resolution demandee par le client : c'est la piste pour que le bureau suive les ecrans choisis,
# la VM ne changeant pas la resolution de son bureau avec "Desktop". Remettre "Desktop" pour
# retrouver le comportement precedent. Si l'hote appaire n'a pas cette application, la 1re de sa
# liste est utilisee.
$script:MoonlightApp = "Virtual Display"
# Applications dont une session ouverte peut etre FERMEE sans risque pour changer de mode ou
# d'application : de simples sessions de bureau. Toute autre application en cours sur la VM
# (Steam Big Picture, un jeu...) n'est jamais fermee par le launcher.
$script:MoonlightSafeQuitApps = @("Desktop", "Virtual Display")
# Une application dont le NOM contient l'un de ces motifs est une session de BUREAU : le launcher peut la
# fermer pour relancer a la bonne taille (Windows : "Desktop", "Virtual Display" ; Sunshine Linux :
# "Desktop", "Desktop 2K", "Desktop 1080p", "Low Res Desktop"...). Un jeu / Steam Big Picture n'en fait pas partie.
$script:MoonlightSafeQuitPatterns = @("Desktop", "Virtual Display")
# PLAFOND de resolution des machines LINUX (Sunshine) : la zone des ecrans choisis est reduite
# proportionnellement au-dela. L'encodeur maison du telephone (Qualcomm Venus, SoC Kalama / Snapdragon
# 8 Gen 2) n'annonce a Moonlight que du H.264 ; or le decodeur materiel du PC (Intel Iris Xe, D3D11VA)
# ne decode pas de H.264 au-dela de 4096 px (Moonlight le dit : "Streaming at resolutions above 4K using
# H.264 will likely fail"). MESURE dans les journaux de Moonlight : 3840x2160 a 60 i/s, 3840x720 et
# 3072x1728 = 0 erreur ; 5160x1440 et 7680x1440 = centaines d'erreurs "No valid decoder configuration" et
# ECRAN NOIR. D'ou 4096x2304 (limite H.264 niveau 5.2). Pour depasser (3 ecrans en 7680x1440), il faut
# que l'encodeur maison propose aussi du HEVC (le materiel le sait : jusqu'a 8192x8192). Reglage par adresse :
#   $script:MoonlightHostLimits['192.168.5.211'] = @{ MaxW = 4096; MaxH = 2304; MaxFps = 60 }
$script:LinuxProfileLimit = @{ MaxW = 4096; MaxH = 2304; MaxFps = 60 }
$script:MoonlightHostLimits = @{}
# Ports TCP que l'hote Apollo/Sunshine doit exposer : 47989 (HTTP, port de base) et
# 47984 (HTTPS). Les ports video/audio sont en UDP : non sondables sans client.
$script:MoonlightPorts = @(47989, 47984)
# Mode essai (tests) : journalise la commande au lieu de lancer mstsc/Moonlight.
$script:WinHostDryRun = $false

