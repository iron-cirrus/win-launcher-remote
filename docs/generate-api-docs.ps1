# Regenere docs/api-index.json et docs/FUNCTIONS.md a partir du code (AST PowerShell).
# Lancer :  powershell -NoProfile -File .\docs\generate-api-docs.ps1
# A refaire apres toute modification (les numeros de ligne bougent). Les descriptions
# manuelles sont dans descriptions.psd1 ; sinon le commentaire juste au-dessus du bloc est utilise.
$ErrorActionPreference = 'Stop'
$docs = $PSScriptRoot
$dir  = Split-Path $docs -Parent
$root = Split-Path $dir -Parent
$desc = Import-PowerShellDataFile (Join-Path $docs 'descriptions.psd1')
$utf8 = New-Object System.Text.UTF8Encoding($true)

$main  = Get-Item (Join-Path $dir 'start.ps1')
$files = @($main) + @(Get-ChildItem $dir -Filter *.ps1 | Where-Object { $_.Name -ne 'start.ps1' } | Sort-Object Name) + @(Get-ChildItem (Join-Path $dir 'cartes') -Filter *.ps1 | Sort-Object Name)

$all = @()
foreach ($f in $files) {
  $t = $null; $e = $null
  $ast   = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$t, [ref]$e)
  $lines = [System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8)
  $rel   = if ($f.Name -eq 'start.ps1') { 'start.ps1' } else { $f.FullName.Substring($dir.Length + 1) -replace '\\','/' }
  $role  = ''
  foreach ($l in ($lines | Select-Object -First 3)) { if ($l -match '#\s*(?:cartes\\)?[\w\-\.]+\.ps1\s+-\s+(.*)$') { $role = $Matches[1]; break } }
  if (-not $role -and $f.Name -eq 'start.ps1') { $role = "Point d'entree : en-tete, relance en processus neuf, chargement des modules, BuildUI/RebuildUI, boucle ShowDialog, nettoyage." }
  $items = @()
  $nodes = $ast.FindAll({ param($x)
      ($x -is [System.Management.Automation.Language.FunctionDefinitionAst]) -or
      ($x -is [System.Management.Automation.Language.AssignmentStatementAst] -and
       $x.Left.Extent.Text -match '^\$script:' -and
       $x.Right -is [System.Management.Automation.Language.CommandExpressionAst] -and
       $x.Right.Expression -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) }, $false)
  foreach ($n in $nodes) {
    $depth = 0; $p = $n.Parent
    while ($p) { if ($p -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { $depth++ }; $p = $p.Parent }
    if ($depth -gt 0) { continue }
    $isFn = $n -is [System.Management.Automation.Language.FunctionDefinitionAst]
    $name = if ($isFn) { $n.Name } else { $n.Left.Extent.Text }
    $sb   = if ($isFn) { $n.Body } else { $n.Right.Expression.ScriptBlock }
    $par  = if ($sb.ParamBlock) { ($sb.ParamBlock.Parameters | ForEach-Object { $_.Extent.Text }) -join ', ' } else { '' }
    $c = @(); $i = $n.Extent.StartLineNumber - 2
    while ($i -ge 0 -and $lines[$i] -match '^\s*#') { $c = ,(($lines[$i] -replace '^\s*#\s*(-{3,}\s*)?','') -replace '\s*-{3,}\s*$','') + $c; $i-- }
    $d = ($c -join ' ').Trim()
    if ($desc.ContainsKey($name)) { $d = $desc[$name] }
    elseif ($d.Length -gt 320) { $d = $d.Substring(0, 317) + '...' }
    $items += [pscustomobject]@{ name = $name; kind = $(if ($isFn) { 'function' } else { 'scriptblock' }); params = $par; lineStart = $n.Extent.StartLineNumber; lineEnd = $n.Extent.EndLineNumber; description = $d }
  }
  $all += [pscustomobject]@{ file = $rel; role = $role; lines = $lines.Count; items = $items }
}

[System.IO.File]::WriteAllText((Join-Path $docs 'api-index.json'), ($all | ConvertTo-Json -Depth 5), $utf8)

$md = New-Object System.Collections.Generic.List[string]
$md.Add('# Reference des fonctions et scriptblocks')
$md.Add('')
$md.Add('> GENERE par `docs/generate-api-docs.ps1` le ' + (Get-Date -Format 'yyyy-MM-dd') + '. Ne pas editer a la main : modifier `descriptions.psd1` ou les commentaires du code, puis relancer le script.')
$md.Add('> Convention : un bloc `$script:Nom` s''appelle `& $script:Nom args` (ou `. $script:Nom` pour l''executer dans la portee courante). Voir [AI-CONTEXT.md](AI-CONTEXT.md).')
$md.Add('')
foreach ($f in $all) {
  $md.Add('## `' + $f.file + '` (' + $f.lines + ' lignes)')
  $md.Add('')
  if ($f.role) { $md.Add($f.role); $md.Add('') }
  if ($f.items.Count -gt 0) {
    $md.Add('| Nom | Parametres | Lignes | Role |'); $md.Add('|---|---|---|---|')
    foreach ($it in $f.items) {
      $pp = if ($it.params) { '`' + ($it.params -replace '\|','\|') + '`' } else { '' }
      $dd = ($it.description -replace '\|','\|')
      $md.Add('| `' + $it.name + '` | ' + $pp + ' | ' + $it.lineStart + '-' + $it.lineEnd + ' | ' + $dd + ' |')
    }
    $md.Add('')
  } else { $md.Add('_Pas de fonction ni de scriptblock nomme : code lineaire (declarations, construction de controles, handlers)._'); $md.Add('') }
}
[System.IO.File]::WriteAllLines((Join-Path $docs 'FUNCTIONS.md'), $md.ToArray(), $utf8)
Write-Host ('OK : ' + $all.Count + ' fichiers, ' + (($all | ForEach-Object { $_.items.Count } | Measure-Object -Sum).Sum) + ' blocs -> api-index.json, FUNCTIONS.md')
