# launcher.ps1 — Lanceur VS Code Remote-SSH sous forme de cartes colorees
# - Liste des machines DYNAMIQUE, lue depuis ~/.ssh/config (C:\Users\invite\.ssh\config)
# - Carte = couleur workbench du remote ; clic = code --remote ssh-remote+<hote>
# - Avant d'ouvrir : verifie si une fenetre VS Code de ce remote est DEJA ouverte
#   (processus Code.exe avec ssh-remote+<hote> dans sa ligne de commande) -> la ramene au premier plan
# - Watchdog : ping periodique de chaque hote -> pastille verte (joignable) / rouge (eteinte)
# - Fenetre sans barre de titre, deplacable en glissant le fond ; fermeture par bouton "Fermer"
# Lancer :  powershell -ExecutionPolicy Bypass -File .\launcher.ps1

# PROCESSUS NEUF OBLIGATOIRE : relance dans une console deja utilisee (ex. ".\vsc_launcher.ps1"
# tape plusieurs fois dans la meme fenetre PowerShell), les minuteurs WinForms des executions
# PRECEDENTES (anciennes versions du code) restent vivants et se reveillent avec la nouvelle
# fenetre : ils agissaient sur les nouvelles cartes (mini-carte masquee/affichee toutes les 5 s).
# Si WinForms est deja charge dans ce processus, on relance le script dans un powershell neuf.
#
# CONSOLE INVISIBLE : par defaut, le launcher se relance dans un processus powershell CACHE (-Child)
# et la console d'origine rend la main aussitot -> aucune fenetre texte a fermer par erreur.
#   -Visible : garde la console visible, dans CE processus (debogage : on voit les erreurs).
#   -Child   : drapeau interne (processus deja relance en cache) ; ne pas l'utiliser a la main.
# Les erreurs de demarrage du processus cache sont ecrites dans %LOCALAPPDATA%\vsc-launcher\startup-error.log
param([switch]$Visible, [switch]$Child)

if ($PSCommandPath -and -not $Visible -and -not $Child) {
  $logDir = Join-Path $env:LOCALAPPDATA 'vsc-launcher'
  if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
  Start-Process powershell.exe -WindowStyle Hidden `
    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'), '-Child') `
    -RedirectStandardError (Join-Path $logDir 'startup-error.log') `
    -RedirectStandardOutput (Join-Path $logDir 'startup-output.log')
  return
}

# Secours : si la console du processus cache est quand meme visible (terminal par defaut de Windows 11),
# on la masque. Sans effet en mode -Visible.
if ($Child) {
  try {
    Add-Type -Namespace VscCon -Name V1 -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
'@
    $hCon = [VscCon.V1]::GetConsoleWindow()
    if ($hCon -ne [IntPtr]::Zero) { [void][VscCon.V1]::ShowWindow($hCon, 0) }
  } catch { }
}

if ($PSCommandPath -and @([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'System.Windows.Forms' }).Count -gt 0) {
  Write-Host "vsc_launcher : cette console a deja execute une fenetre WinForms -> relance dans un processus neuf"
  Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'), '-Visible')
  return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------- Modules (dot-sources : TOUT reste dans la portee script du launcher) ----------
# Dossier des modules : le dossier de ce fichier (start.ps1 vit DANS vsc_launcher).
$script:LauncherDir = $PSScriptRoot

# 1) Fondations : P/Invoke, couleurs, liste des machines, reglages, ecrans, Moonlight/RDP, disposition
. (Join-Path $script:LauncherDir '01-win32-interop.ps1')
. (Join-Path $script:LauncherDir '02-machines-couleurs.ps1')
. (Join-Path $script:LauncherDir '03-machines-liste.ps1')
. (Join-Path $script:LauncherDir '04-moonlight-reglages.ps1')
. (Join-Path $script:LauncherDir '05-ecrans.ps1')
. (Join-Path $script:LauncherDir '06-moonlight-profil.ps1')
. (Join-Path $script:LauncherDir '07-mstsc.ps1')
. (Join-Path $script:LauncherDir '08-clients-distants.ps1')
. (Join-Path $script:LauncherDir '09-moonlight-garde.ps1')
. (Join-Path $script:LauncherDir '10-ouvrir-hote-windows.ps1')
. (Join-Path $script:LauncherDir '11-icones-disposition.ps1')
. (Join-Path $script:LauncherDir '12-sunshine.ps1')
. (Join-Path $script:LauncherDir '13-panneau-haut.ps1')

# 2) Construction de l'IHM : scriptblock REEXECUTABLE (rechargement a chaud apres scan LAN).
#    Son contenu est decoupe en fichiers ui-*.ps1 executes dans l'ordre, dans la MEME portee.
$script:BuildUI = {
. (Join-Path $script:LauncherDir 'ui-10-fenetre-colonnes.ps1')
. (Join-Path $script:LauncherDir 'ui-20-fenetre.ps1')
. (Join-Path $script:LauncherDir 'ui-30-journal.ps1')
. (Join-Path $script:LauncherDir 'ui-40-scan-lan.ps1')
. (Join-Path $script:LauncherDir 'ui-50-cartes.ps1')
. (Join-Path $script:LauncherDir 'ui-60-deploiement.ps1')
. (Join-Path $script:LauncherDir 'ui-70-sync-zoo.ps1')
. (Join-Path $script:LauncherDir 'ui-80-pied-de-page.ps1')
. (Join-Path $script:LauncherDir 'ui-90-watchdog-fenetres.ps1')
. (Join-Path $script:LauncherDir 'ui-95-watchdog-ping.ps1')
}   # ---------- fin $script:BuildUI ----------

# RECHARGEMENT A CHAUD (appele par le timer de scan a la fin du scan LAN) :
# arrete les timers, LIBERE les controles et leurs objets GDI+, fusionne le cache
# fraichement ecrit, puis recree les cartes. La fenetre n'est NI fermee NI
# deplacee : elle garde sa position a l'ecran.
$script:RebuildUI = {
  & $script:LogFn "reconstruction de l'affichage dans la fenetre existante..."
  try { $openTimer.Stop(); $openTimer.Dispose() } catch { }
  try { $pingTimer.Stop(); $pingTimer.Dispose() } catch { }
  try { $pingCollectTimer.Stop(); $pingCollectTimer.Dispose() } catch { }
  try { $netTimer.Stop(); $netTimer.Dispose() } catch { }
  . $script:MergeLanCache
  . $script:BuildUI
}

# ShowDialog appele UNE SEULE FOIS : le rechargement ne recree plus la fenetre,
# seulement son contenu (les controles).
. $script:BuildUI
[void]$form.ShowDialog()
try { $openTimer.Stop(); $openTimer.Dispose() } catch { }
try { $pingTimer.Stop(); $pingTimer.Dispose() } catch { }
try { $pingCollectTimer.Stop(); $pingCollectTimer.Dispose() } catch { }
try { $netTimer.Stop(); $netTimer.Dispose() } catch { }
try { if ($script:PlaceTimer) { $script:PlaceTimer.Stop(); $script:PlaceTimer.Tag = $null; $script:PlaceTimer.Dispose() } } catch { }
try { if ($script:RetryTimer) { $script:RetryTimer.Stop(); $script:RetryTimer.Tag = $null; $script:RetryTimer.Dispose() } } catch { }
try { if ($script:PendingTimer) { $script:PendingTimer.Stop(); $script:PendingTimer.Tag = $null; $script:PendingTimer.Dispose() } } catch { }
try { if ($script:ZooSyncJob) { Stop-Job $script:ZooSyncJob -ErrorAction SilentlyContinue; Remove-Job $script:ZooSyncJob -Force -ErrorAction SilentlyContinue } } catch { }
