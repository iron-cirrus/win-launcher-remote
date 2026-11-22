# cartes\08-icone-sunshine.ps1 - Icone Moonlight des machines Linux (Sunshine)
# Corps de la boucle 'foreach ($m in $MachinesOrd)' de ui-50-cartes.ps1 (dot-source par carte). Lignes d'origine du fichier ui-50 : 924-955.

  # ---- machine LINUX : icone Moonlight si Sunshine est detecte (sonde des ports : OpenCheckTick) ----
  # Dans la rangee d'icones du bas, a gauche du terminal SSH. Masquee tant que Sunshine n'a pas repondu.
  $icoSun = $null
  if ($m.Host -and $m.OsType -eq 'linux' -and $m.HostName) {
    $icoSun = New-Object System.Windows.Forms.Panel
    $icoSun.Size = New-Object System.Drawing.Size(20, 20)
    $icoSun.Location = New-Object System.Drawing.Point(($cardW - 106), ($cardH - 24))
    $icoSun.BackColor = [System.Drawing.Color]::Transparent
    $icoSun.Cursor = [System.Windows.Forms.Cursors]::Hand
    $icoSun.Visible = $false
    $icoSun | Add-Member -NotePropertyName RdpIp -NotePropertyValue ([string]$m.HostName)    # adresse suivie par MlState (mise a jour par la sonde)
    $icoSun | Add-Member -NotePropertyName Unpaired -NotePropertyValue $false
    $icoSun | Add-Member -NotePropertyName TipText -NotePropertyValue ''
    $icoSun.Add_Paint({ param($s, $e) & $script:PaintMlIcon $e.Graphics $s })
    $icoSun.Add_MouseEnter({
      param($s, $e)
      $mlS = $script:MlState[$s.RdpIp]
      $script:Tip.SetToolTip($s, $s.TipText + $(if ($mlS) { "`nÉtat : " + $script:MlStateLabels[$mlS.State] }))
    })
    $icoSun.Add_MouseClick({
      param($s, $e)
      if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
      if ($s.Parent.Disabled) { & $script:LogFn ("Carte " + $s.RdpIp + " inactive : machine injoignable (ping)"); return }
      $mhS = & $script:GetMoonlightHost $s.RdpIp
      if (-not $mhS.Paired) {
        & $script:LogFn ("Sunshine: " + $s.RdpIp + " detecte mais NON appaire dans Moonlight : ajouter l'hote dans Moonlight puis saisir le PIN sur https://" + $s.RdpIp + ":47990")
        return
      }
      & $script:OpenWindowsHost $s.RdpIp
    })
    $card.Controls.Add($icoSun)
  }
