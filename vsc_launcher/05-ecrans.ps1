# 05-ecrans.ps1 - Ecrans locaux, etat des sessions Moonlight (MlState), bitmap grise
# Fichier charge par vsc_launcher.ps1 (dot-source : meme portee script). Lignes d'origine 485-675.

# ---------- ECRANS DE CE POSTE (disposition = topographie reelle) ----------
# Idx = numero Windows de l'ecran (\\.\DISPLAYn = numeros du bouton "Identifier" des
# parametres d'affichage) ; X/Y/W/H = rectangle dans le bureau virtuel (X, Y
# peuvent etre NEGATIFS : ecran a gauche / au-dessus de l'ecran principal).
# X/Y/W/H = taille VUE PAR CE PROCESSUS : Windows la REDUIT quand l'ecran est mis a l'echelle (un 4K a
# 125 % est annonce 3072x1728). Elle sert au PLACEMENT des fenetres (meme repere que SetWindowPos).
# PX/PY/PW/PH = resolution PHYSIQUE reelle (3840x2160), lue dans les parametres d'affichage : c'est elle
# qu'il faut demander a Moonlight / mstsc et afficher.
if (-not ('VscModeV1' -as [type])) {
  Add-Type @"
using System;
using System.Runtime.InteropServices;
public class VscModeV1 {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
    public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra; public int dmFields;
    public int dmPositionX, dmPositionY; public int dmDisplayOrientation, dmDisplayFixedOutput;
    public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName;
    public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
    public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight; }
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
  // [largeur, hauteur, x, y] PHYSIQUES du mode courant de l'ecran, ou null
  public static int[] Get(string dev) {
    var d = new DEVMODE(); d.dmSize = (short)Marshal.SizeOf(d);
    if (!EnumDisplaySettings(dev, -1, ref d)) return null;
    if (d.dmPelsWidth <= 0 || d.dmPelsHeight <= 0) return null;
    return new int[] { d.dmPelsWidth, d.dmPelsHeight, d.dmPositionX, d.dmPositionY };
  }
}
"@
}
$script:GetScreens = {
  $list = @()
  foreach ($s in [System.Windows.Forms.Screen]::AllScreens) {
    $n = 0; if ($s.DeviceName -match '(\d+)\s*$') { $n = [int]$Matches[1] }
    $ph = $null; try { $ph = [VscModeV1]::Get($s.DeviceName) } catch { }
    $pw = $(if ($ph) { $ph[0] } else { $s.Bounds.Width }); $phh = $(if ($ph) { $ph[1] } else { $s.Bounds.Height })
    $px = $(if ($ph) { $ph[2] } else { $s.Bounds.X }); $py = $(if ($ph) { $ph[3] } else { $s.Bounds.Y })
    $list += [pscustomobject]@{ Idx = $n; X = $s.Bounds.X; Y = $s.Bounds.Y; W = $s.Bounds.Width; H = $s.Bounds.Height; Primary = $s.Primary; PX = $px; PY = $py; PW = $pw; PH = $phh }
  }
  return ,@($list | Sort-Object Idx)
}
$script:Screens = & $script:GetScreens
$script:ScreensSig = (@($script:Screens | ForEach-Object { "" + $_.Idx + ":" + $_.X + "," + $_.Y + "," + $_.W + "x" + $_.H + "/" + $_.PW + "x" + $_.PH }) -join ';')

# Ecrans choisis par machine (IP -> LISTE de numeros d'ecran, 1 ou plusieurs contigus),
# conserves entre les lancements. Ancien format (un seul numero) lu tel quel.
$script:ScreenChoicePath = Join-Path $env:LOCALAPPDATA "vsc-launcher\screen-choice.json"
$script:ScreenChoice = @{}
try {
  if (Test-Path $script:ScreenChoicePath) {
    $scObj = Get-Content $script:ScreenChoicePath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($pp in $scObj.PSObject.Properties) { $script:ScreenChoice[$pp.Name] = @($pp.Value | ForEach-Object { [int]$_ }) }
  }
} catch { }
# Reglages du mode "plusieurs ecrans" :
#  - MultiScreenBorderless : retire barre de titre et bordures de la fenetre du flux pour
#    qu'elle occupe exactement le rectangle des ecrans choisis ;
#  - MultiScreenDisplayMode : si renseigne (ex. "windowed"), passe --display-mode a Moonlight
#    pour les selections multi-ecrans (a activer si le plein ecran de Moonlight refuse de
#    s'etendre sur plusieurs ecrans) ;
#  - MultiStreamTitle : motif du titre de la fenetre du FLUX (ex. "vm-win11-q35 - Moonlight"),
#    distincte de la petite fenetre de connexion.
$script:MultiScreenBorderless = $true
$script:MultiScreenDisplayMode = $null
$script:MultiStreamTitle = ' - Moonlight$'
# RECONNEXION AUTOMATIQUE : la connexion Moonlight peut tomber quand on s'identifie sur
# la session Windows (bascule du bureau de connexion vers celui de la session). Le
# launcher surveille alors le processus Moonlight qu'il a lance : s'il SE FERME de
# facon anormale apres avoir affiche le flux, il le relance (une seule fois) avec les
# memes ecrans. Reglages :
#  - MoonlightRetryMax : nombre de relances (0 = fonction desactivee) ;
#  - MoonlightRetryWithinSec : fenetre de surveillance apres le lancement (au-dela, la
#    session est consideree stable et la surveillance s'arrete) ;
#  - MoonlightRetryDelaySec : pause avant la relance ;
#  - MoonlightRetryOnAnyExit : $true = relancer meme si Moonlight se ferme avec le code 0
#    ("fermeture normale") ; par defaut seul un code d'erreur declenche la relance, pour
#    ne pas rouvrir une session que vous venez de fermer volontairement ;
#  - MoonlightStreamTitle : motif du titre de la fenetre du flux (preuve que la
#    connexion a abouti : sans flux affiche, pas de relance, la machine est injoignable).
$script:MoonlightRetryMax = 1
$script:MoonlightRetryWithinSec = 600
$script:MoonlightRetryDelaySec = 3
$script:MoonlightRetryOnAnyExit = $false
$script:MoonlightStreamTitle = ' - Moonlight$'

# ETAT MOONLIGHT PAR MACHINE (IP -> etat), affiche sur la mini-carte des ecrans :
#   connecting : Moonlight lance, flux pas encore affiche ;
#   live       : flux affiche et processus actif = OPERATIONNEL ;
#   lost       : la fenetre du flux a disparu alors que Moonlight tourne encore (ex. boite d'erreur) ;
#   ended      : Moonlight ferme (deconnexion) apres avoir affiche le flux.
# Les ecrans OCCUPES (connecting/live) portent l'icone Moonlight ; apres une deconnexion
# (ended/lost) ils sont GRISES jusqu'a la prochaine ouverture ou un nouveau choix d'ecrans.
$script:MlState = @{}
# sessions mstsc ouvertes par le launcher : ip -> { Idxs ; Proc ; Since } (retirees quand mstsc se ferme)
$script:RdpState = @{}
$script:MlStateLabels = @{ connecting = 'en connexion'; live = 'OPERATIONNEL'; lost = 'flux perdu'; ended = 'deconnecte' }
$script:SetMlState = {
  param([string]$ip, [string]$state, $idxs = @(), $code = $null, [string]$note = '')
  $ids = @($idxs | Where-Object { $null -ne $_ })
  $old = $script:MlState[$ip]
  if ($state -eq 'none') {
    $script:MlState.Remove($ip)
  } else {
    $script:MlState[$ip] = [pscustomobject]@{ State = $state; Idxs = $ids; Since = (Get-Date); Code = $code }
    # trace : chaque changement d'etat est ecrit dans le journal
    if ($script:LogFn -and (-not $old -or $old.State -ne $state)) {
      & $script:LogFn ("Etat Moonlight " + $ip + " : " + $script:MlStateLabels[$state] + " (ecrans " + ($ids -join '+') + ")" + $(if ($null -ne $code) { ", code de sortie " + $code }) + $(if ($note) { " - " + $note }))
    }
  }
  # redessine la mini-carte de la machine
  foreach ($c in @($script:CardList)) {
    if ($c.PingHost -eq $ip -or ($c.Ml -and $c.Ml.RdpIp -eq $ip)) {
      try { if ($c.Map) { $c.Map.Invalidate() }; if ($c.Ml) { $c.Ml.Invalidate() } } catch { }
    }
  }
  if ($script:RefreshTop) { & $script:RefreshTop }       # panneau du haut : icones des sessions + etiquettes des cartes
}
# Icone Moonlight (celle de Moonlight.exe : la roue a rayons) en 3 versions pre-rendues : couleur
# pour "operationnel", attenuee pour "en connexion". Repli dessine si l'exe est introuvable.
$script:MlIcon = $null; $script:MlIconDim = $null; $script:MlIcon20 = $null
try {
  $icoSrc = $(if ($script:MoonlightIconExe) { $script:MoonlightIconExe } else { $script:MoonlightExe })
  $bmpSrc = $null
  if ($icoSrc -and (Test-Path $icoSrc)) { $bmpSrc = ([System.Drawing.Icon]::ExtractAssociatedIcon($icoSrc)).ToBitmap() }
  if (-not $bmpSrc) {
    $bmpSrc = New-Object System.Drawing.Bitmap(32, 32, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gF = [System.Drawing.Graphics]::FromImage($bmpSrc); $gF.SmoothingMode = 'AntiAlias'
    $gF.FillEllipse([System.Drawing.Brushes]::White, 2, 2, 28, 28)
    $gF.FillEllipse((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(37, 99, 235))), 10, 0, 28, 28)
    $gF.Dispose()
  }
  $script:MlIcon = New-Object System.Drawing.Bitmap(16, 16, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $gI = [System.Drawing.Graphics]::FromImage($script:MlIcon)
  $gI.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $gI.DrawImage($bmpSrc, 0, 0, 16, 16); $gI.Dispose()
  # version 20 px : bouton "ouvrir Moonlight" en bas a droite des cartes Windows
  $script:MlIcon20 = New-Object System.Drawing.Bitmap(20, 20, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $gI20 = [System.Drawing.Graphics]::FromImage($script:MlIcon20)
  $gI20.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $gI20.DrawImage($bmpSrc, 0, 0, 20, 20); $gI20.Dispose()
  $cmDim = New-Object System.Drawing.Imaging.ColorMatrix
  $cmDim.Matrix00 = 0.33; $cmDim.Matrix10 = 0.33; $cmDim.Matrix20 = 0.33
  $cmDim.Matrix01 = 0.33; $cmDim.Matrix11 = 0.33; $cmDim.Matrix21 = 0.33
  $cmDim.Matrix02 = 0.33; $cmDim.Matrix12 = 0.33; $cmDim.Matrix22 = 0.33
  $cmDim.Matrix33 = 0.55
  $iaDim = New-Object System.Drawing.Imaging.ImageAttributes; $iaDim.SetColorMatrix($cmDim) | Out-Null
  $script:MlIconDim = New-Object System.Drawing.Bitmap(16, 16, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $gD = [System.Drawing.Graphics]::FromImage($script:MlIconDim)
  $gD.DrawImage($script:MlIcon, (New-Object System.Drawing.Rectangle(0, 0, 16, 16)), 0, 0, 16, 16, [System.Drawing.GraphicsUnit]::Pixel, $iaDim)
  $gD.Dispose(); $iaDim.Dispose()
} catch { $script:MlIcon = $null; $script:MlIconDim = $null; $script:MlIcon20 = $null }
# Icone de mstsc (bouton "ouvrir mstsc sur les ecrans selectionnes"), extraite de mstsc.exe en 20 px ;
# repli : petit ecran dessine.
$script:RdpIcon20 = $null
try {
  $mstscExe = Join-Path $env:SystemRoot "System32\mstsc.exe"
  $rdpSrc = $null
  if (Test-Path $mstscExe) { $rdpSrc = ([System.Drawing.Icon]::ExtractAssociatedIcon($mstscExe)).ToBitmap() }
  $script:RdpIcon20 = New-Object System.Drawing.Bitmap(20, 20, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $gR = [System.Drawing.Graphics]::FromImage($script:RdpIcon20)
  $gR.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  if ($rdpSrc) { $gR.DrawImage($rdpSrc, 0, 0, 20, 20) }
  else {
    $gR.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $gR.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 120, 212))), 1, 3, 18, 12)
    $gR.FillRectangle([System.Drawing.Brushes]::White, 3, 5, 14, 8)
    $gR.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 120, 212))), 7, 15, 6, 2)
  }
  $gR.Dispose()
} catch { $script:RdpIcon20 = $null }
# Versions SOMBRES (grisees + attenuees) des icones Moonlight et mstsc 20 px : affichees quand aucune
# session n'est ouverte, comme les icones VNC / SSH / VS Code des cartes (couleur = session active)
$script:MakeDimBmp = {
  param($src)
  $cm = New-Object System.Drawing.Imaging.ColorMatrix
  $cm.Matrix00 = 0.33; $cm.Matrix10 = 0.33; $cm.Matrix20 = 0.33
  $cm.Matrix01 = 0.33; $cm.Matrix11 = 0.33; $cm.Matrix21 = 0.33
  $cm.Matrix02 = 0.33; $cm.Matrix12 = 0.33; $cm.Matrix22 = 0.33
  $cm.Matrix33 = 0.42
  $ia = New-Object System.Drawing.Imaging.ImageAttributes; [void]$ia.SetColorMatrix($cm)
  $b = New-Object System.Drawing.Bitmap($src.Width, $src.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $gd = [System.Drawing.Graphics]::FromImage($b)
  $gd.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, $src.Width, $src.Height)), 0, 0, $src.Width, $src.Height, [System.Drawing.GraphicsUnit]::Pixel, $ia)
  $gd.Dispose(); $ia.Dispose()
  return $b
}
$script:MlIcon20Dim = $null; $script:RdpIcon20Dim = $null
try { if ($script:MlIcon20) { $script:MlIcon20Dim = & $script:MakeDimBmp $script:MlIcon20 } } catch { }
try { if ($script:RdpIcon20) { $script:RdpIcon20Dim = & $script:MakeDimBmp $script:RdpIcon20 } } catch { }
