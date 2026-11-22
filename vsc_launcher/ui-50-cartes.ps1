# ui-50-cartes.ps1 - BuildUI : titres de colonne et cartes des machines
# Fichier charge par vsc_launcher.ps1 (dot-source : meme portee script). Lignes d'origine 3101-4104.

# ---------- Titres de colonne : crees par $script:Relayout (un par segment visible) ----------

# ---------- Cartes ----------
# Le corps de la boucle est decoupe en fichiers cartes\*.ps1. Chacun est lu et compile UNE FOIS
# (scriptblock) puis execute par dot-source a chaque carte : meme portee que l'ancien code monolithique,
# donc memes variables ($card, $lblLabel, $icoVnc...) partagees d'une etape a l'autre.
$script:CardParts = @(Get-ChildItem (Join-Path $script:LauncherDir 'cartes') -Filter '*.ps1' | Sort-Object Name |
  ForEach-Object { [scriptblock]::Create([System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)) })
foreach ($m in $MachinesOrd) {
  foreach ($cardPart in $script:CardParts) { . $cardPart }
}

