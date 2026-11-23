# 01-win32-interop.ps1 - P/Invoke Win32 (EnumWindows, SetWindowPos...) : types C# versionnes
# Fichier charge par vsc_launcher.ps1 (dot-source : meme portee script). Lignes d'origine 26-180.

# P/Invoke : deplacement de la fenetre sans barre de titre + ShowWindow + EnumWindows.
# Le nom de type est VERSIONNE (VscWinV2, VscWinV4... a chaque changement du code C#) :
# un type Add-Type reste charge pour toute la session PowerShell ; sans nouveau nom,
# une ancienne definition (sans GetCodeWindows) resterait active -> MethodNotFound.
if (-not ('VscWinV4' -as [type])) {
  Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
public class VscWinV4 {
  [DllImport("user32.dll")] public static extern bool ReleaseCapture();
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, int wParam, int lParam);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  private static List<IntPtr> _wins;

  // Enumere TOUTES les fenetres visibles dont le titre contient "Visual Studio Code".
  // Indispensable : VS Code (Electron) met souvent plusieurs fenetres dans un seul
  // processus -> Get-Process.MainWindowHandle ne voit que la fenetre au premier plan.
  public static List<string[]> GetCodeWindows() {
    _wins = new List<IntPtr>();
    EnumWindows((h, l) => {
      if (IsWindowVisible(h)) _wins.Add(h);
      return true;
    }, IntPtr.Zero);
    var res = new List<string[]>();
    foreach (var h in _wins) {
      int len = GetWindowTextLength(h);
      if (len <= 0) continue;
      var sb = new System.Text.StringBuilder(len + 1);
      GetWindowText(h, sb, sb.Capacity);
      string t = sb.ToString();
      if (t.IndexOf("Visual Studio Code", StringComparison.OrdinalIgnoreCase) >= 0)
        res.Add(new string[] { ((long)h).ToString(), t });
    }
    return res;
  }

  // Enumere TOUTES les fenetres visibles (sans filtre sur le titre) -> [handle, titre].
  // Utilise pour detecter une fenetre VNC deja ouverte sur une IP donnee
  // (TurboVNC via vncviewer.bat = Java : Get-Process.MainWindowTitle ne le voit pas).
  public static List<string[]> GetAllWindows() {
    _wins = new List<IntPtr>();
    EnumWindows((h, l) => {
      if (IsWindowVisible(h)) _wins.Add(h);
      return true;
    }, IntPtr.Zero);
    var res = new List<string[]>();
    foreach (var h in _wins) {
      int len = GetWindowTextLength(h);
      if (len <= 0) continue;
      var sb = new System.Text.StringBuilder(len + 1);
      GetWindowText(h, sb, sb.Capacity);
      res.Add(new string[] { ((long)h).ToString(), sb.ToString() });
    }
    return res;
  }
}
"@
}

# P/Invoke 2 : fenetres d'UN processus + deplacement (placement de Moonlight sur
# l'ecran choisi). Type a part (et non ajoute a VscWinV4) : un type deja charge
# dans la session ne peut pas etre redefini.
if (-not ('VscScrV3' -as [type])) {
  Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
public class VscScrV3 {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, System.Text.StringBuilder sb, int n);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll", EntryPoint="GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr64(IntPtr h, int i);
  [DllImport("user32.dll", EntryPoint="SetWindowLongPtrW")] static extern IntPtr SetWindowLongPtr64(IntPtr h, int i, IntPtr v);
  [DllImport("user32.dll", EntryPoint="GetWindowLongW")] static extern int GetWindowLong32(IntPtr h, int i);
  [DllImport("user32.dll", EntryPoint="SetWindowLongW")] static extern int SetWindowLong32(IntPtr h, int i, int v);

  // Fenetres visibles de plus de 100 x 100 px appartenant au processus : [hwnd, gauche, haut, droite, bas, titre]
  public static List<string[]> GetProcessWindows(int pid) {
    var found = new List<IntPtr>();
    EnumWindows((h, l) => {
      uint p; GetWindowThreadProcessId(h, out p);
      if ((int)p == pid && IsWindowVisible(h)) found.Add(h);
      return true;
    }, IntPtr.Zero);
    var res = new List<string[]>();
    foreach (var h in found) {
      RECT r; if (!GetWindowRect(h, out r)) continue;
      if (r.Right - r.Left < 100 || r.Bottom - r.Top < 100) continue;
      int len = GetWindowTextLength(h);
      var sb = new System.Text.StringBuilder(len + 1);
      if (len > 0) GetWindowText(h, sb, sb.Capacity);
      res.Add(new string[] { ((long)h).ToString(), r.Left.ToString(), r.Top.ToString(), r.Right.ToString(), r.Bottom.ToString(), sb.ToString() });
    }
    return res;
  }
  // Titres de TOUTES les fenetres visibles du processus, de toute taille (une fenetre
  // reduite dans la barre des taches reste "visible" et garde son titre) : sert a savoir si
  // la fenetre du flux Moonlight existe encore, sans la confondre avec une fenetre reduite.
  public static List<string> WindowTitles(int pid) {
    var res = new List<string>();
    EnumWindows((h, l) => {
      uint p; GetWindowThreadProcessId(h, out p);
      if ((int)p == pid && IsWindowVisible(h)) {
        int len = GetWindowTextLength(h);
        if (len > 0) { var sb = new System.Text.StringBuilder(len + 1); GetWindowText(h, sb, sb.Capacity); res.Add(sb.ToString()); }
      }
      return true;
    }, IntPtr.Zero);
    return res;
  }
  // Deplace/redimensionne (SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW). Une fenetre
  // maximisee est d'abord restauree (sinon Windows la rattache a son ancien ecran).
  public static bool Move(long hwnd, int x, int y, int w, int h) {
    IntPtr p = new IntPtr(hwnd);
    if (IsZoomed(p)) ShowWindow(p, 9);
    return SetWindowPos(p, IntPtr.Zero, x, y, w, h, 0x0004 | 0x0010 | 0x0040);
  }
  // Cale la fenetre EXACTEMENT sur le rectangle (x, y, w, h), qui peut couvrir plusieurs
  // ecrans (coordonnees du bureau virtuel, X/Y negatifs possibles). Si borderless : retire
  // barre de titre, bordures et boutons agrandir/reduire -> la zone cliente occupe tout le
  // rectangle. Une fenetre deja sans bordure (plein ecran) n'est pas touchee.
  public static bool Fit(long hwnd, int x, int y, int w, int h, bool borderless) {
    IntPtr p = new IntPtr(hwnd);
    if (IsZoomed(p)) ShowWindow(p, 9);
    uint flags = 0x0004 | 0x0010 | 0x0040;                   // NOZORDER | NOACTIVATE | SHOWWINDOW
    if (borderless) {
      const int GWL_STYLE = -16;
      long st = (IntPtr.Size == 8) ? GetWindowLongPtr64(p, GWL_STYLE).ToInt64() : GetWindowLong32(p, GWL_STYLE);
      long ns = st & ~(0x00C00000L | 0x00040000L | 0x00020000L | 0x00010000L);   // CAPTION | THICKFRAME | MINIMIZEBOX | MAXIMIZEBOX
      if (ns != st) {
        if (IntPtr.Size == 8) SetWindowLongPtr64(p, GWL_STYLE, new IntPtr(ns)); else SetWindowLong32(p, GWL_STYLE, (int)ns);
        flags |= 0x0020;                                     // FRAMECHANGED : Windows recalcule le cadre
      }
    }
    return SetWindowPos(p, IntPtr.Zero, x, y, w, h, flags);
  }
}
"@
}

# P/Invoke 3 : fenetres "remote app" (VS Code Remote-SSH, clients VNC) avec le MONITEUR
# le plus proche. Indispensable au demarrage : une fenetre REDUITE dans la barre des taches
# renvoie un rectangle fantaisiste (ex. -1146,-1150 -> 310,-242) et GetProcessWindows
# (filtre >100x100 px) ne la voit pas du moins pas. MonitorFromWindow, lui, repond
# (MONITOR_DEFAULTTONEAREST) et designe l'ecran ou la fenetre reviendra.
# Type VERSIONNE (VscAppV2) : un Add-Type ne peut pas etre redefini dans la session.
if (-not ('VscAppV2' -as [type])) {
  Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
public class VscAppV2 {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct MONINFO { public int cb; public RECT rgnMonitor; public RECT rgnWork; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string name; public int flags; }
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, System.Text.StringBuilder sb, int n);
  [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool GetMonitorInfo(IntPtr h, ref MONINFO mi);
  const uint TONEAREST = 2;

  // Fenetres visibles dont le titre contient "SSH:" ou "VNC" : [hwnd, pid, titre, moniteur gauche/haut/droite/bas]
  public static List<string[]> RemoteAppWindows() {
    var found = new List<IntPtr>();
    EnumWindows((h, l) => { if (IsWindowVisible(h)) found.Add(h); return true; }, IntPtr.Zero);
    var res = new List<string[]>();
    foreach (var h in found) {
      int len = GetWindowTextLength(h);
      if (len <= 0) continue;
      var sb = new System.Text.StringBuilder(len + 1);
      GetWindowText(h, sb, sb.Capacity);
      string t = sb.ToString();
      if (t.IndexOf("SSH:", StringComparison.OrdinalIgnoreCase) < 0 && t.IndexOf("VNC", StringComparison.OrdinalIgnoreCase) < 0 && t.IndexOf("Visual Studio Code", StringComparison.OrdinalIgnoreCase) < 0) continue;
      uint pid; GetWindowThreadProcessId(h, out pid);
      int ml = 0, mt = 0, mr = 0, mb = 0;
      IntPtr mon = MonitorFromWindow(h, TONEAREST);
      if (mon != IntPtr.Zero) {
        var mi = new MONINFO(); mi.cb = Marshal.SizeOf(mi);
        if (GetMonitorInfo(mon, ref mi)) { ml = mi.rgnMonitor.Left; mt = mi.rgnMonitor.Top; mr = mi.rgnMonitor.Right; mb = mi.rgnMonitor.Bottom; }
      }
      res.Add(new string[] { ((long)h).ToString(), pid.ToString(), t, ml.ToString(), mt.ToString(), mr.ToString(), mb.ToString() });
    }
    return res;
  }
}
"@
}

