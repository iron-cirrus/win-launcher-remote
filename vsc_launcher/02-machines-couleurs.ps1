# 02-machines-couleurs.ps1 - Couleurs connues par alias, palette de secours, notes/roles
# Fichier charge par vsc_launcher.ps1 (dot-source : meme portee script). Lignes d'origine 181-228.

# ---------- Couleurs connues : CLES = ALIAS de ~/.ssh/config (sinon palette) ----------
# PALETTE ADAPTEE AU DALTONISME (protanopie, deuteranopie, tritanopie) : les couleurs ont ete CHOISIES par
# calcul parmi des fonds sombres (texte blanc lisible, contraste >= 5) en maximisant l'ecart de couleur
# (CIELAB) le plus faible entre deux cartes, mesure en vision normale ET avec les 3 simulations de
# daltonisme (Machado 2009). Ecart minimal entre deux cartes : 9,9 (l'ancienne palette : 1,3, brun et
# ambre quasi identiques). Les cartes different surtout par leur CLARTE et par l'axe bleu / orange,
# jamais par rouge contre vert. Le statut (en ligne, session, ecran occupe) ne repose plus sur la
# couleur seule : formes et symboles l'accompagnent.
# Meme jeu de couleurs que le deploiement sur les machines (couleur de la fenetre VS Code distante).
$KnownColors = @{
  "Kvm-Gpu"                          = @{ Color = "#9a4f0d"; Dark = "#7b3f0a"; Fg = "#ebdccf" }   # orange cuivre (clair)
  "Router-Aussudre"                  = @{ Color = "#5f4029"; Dark = "#4c3321"; Fg = "#dfd9d4" }   # brun sombre
  "free.iron-cirrus.net"             = @{ Color = "#5f4029"; Dark = "#4c3321"; Fg = "#dfd9d4" }   # meme machine que Router-Aussudre
  "192.168.5.251"                    = @{ Color = "#5f4029"; Dark = "#4c3321"; Fg = "#dfd9d4" }   # idem
  "Vm-Minecraft_Router"              = @{ Color = "#765692"; Dark = "#5e4575"; Fg = "#e4dde9" }   # violet clair
  "Vm-Minecraft_Router-Aussudre"     = @{ Color = "#765692"; Dark = "#5e4575"; Fg = "#e4dde9" }
  "Vm-HomeAssistant_Router"          = @{ Color = "#4c2378"; Dark = "#3d1c60"; Fg = "#dbd3e4" }   # violet profond
  "Vm-HomeAssistant_Router-Aussudre" = @{ Color = "#4c2378"; Dark = "#3d1c60"; Fg = "#dbd3e4" }
  "Vm-LiteLlm_Kvm-Gpu"               = @{ Color = "#436c54"; Dark = "#365643"; Fg = "#d9e2dd" }   # vert-gris
  "Vm-PyDev_Kvm-Gpu"                 = @{ Color = "#436c54"; Dark = "#365643"; Fg = "#d9e2dd" }   # idem (si alias pydev reapparait)
  "pythonDevLocal"                   = @{ Color = "#436c54"; Dark = "#365643"; Fg = "#d9e2dd" }   # idem (ancien alias)
  "VPS-Iskernel_Cloud"               = @{ Color = "#365fba"; Dark = "#2b4c95"; Fg = "#d7dff1" }   # bleu franc
  "VPS-Iskernel_OVH"                 = @{ Color = "#365fba"; Dark = "#2b4c95"; Fg = "#d7dff1" }
  "llmIskernel"                      = @{ Color = "#365fba"; Dark = "#2b4c95"; Fg = "#d7dff1" }   # (ancien alias)
  "Oneplus11-Internal_LAN"           = @{ Color = "#7c481f"; Dark = "#633a19"; Fg = "#e5dad2" }   # brun moyen
  "Oneplus11-External_Cloud"         = @{ Color = "#992368"; Dark = "#7a1c53"; Fg = "#ebd3e1" }   # magenta
}

# ---------- Palette de secours pour un hote inconnu (attribuee par ordre) ----------
$Palette = @(
  @{ Color = "#5c2c03"; Dark = "#4a2302"; Fg = "#ded5cd" }   # brun tres sombre
  @{ Color = "#256c78"; Dark = "#1e5660"; Fg = "#d3e2e4" }   # bleu-vert
  @{ Color = "#73613f"; Dark = "#5c4e32"; Fg = "#e3dfd9" }   # kaki
  @{ Color = "#0c4132"; Dark = "#0a3428"; Fg = "#ced9d6" }   # vert sapin
)

# Role lisible optionnel par alias (sinon "VM sur <parent>" ou HostName)
$Notes = @{
  "Router-Aussudre"       = "KVM hote principal (routeur LAN)"
  "free.iron-cirrus.net"  = "KVM hote principal (routeur LAN)"
  "192.168.5.251"         = "KVM hote principal (routeur LAN)"
  "Vm-Minecraft_Router"   = "VM Minecraft"
  "Vm-HomeAssistant_Router" = "VM Home Assistant"
  "Kvm-Gpu"               = "KVM hote GPU"
  "Vm-LiteLlm_Kvm-Gpu"    = "VM LiteLLM (sur Kvm-Gpu)"
  "VPS-Iskernel_OVH"      = "Serveur LLM distant (OVH)"
}

