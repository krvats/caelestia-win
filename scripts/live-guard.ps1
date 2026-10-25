# caelestia-win - animated wallpaper guard.
# Pauses the animated wallpaper while the PC runs on battery or while an app is fullscreen, and resumes it afterwards
# (the same rules caelestia-aw has). Started by "cw live set" and at login; ends by itself when no animated wallpaper
# is active. Both rules can be switched off in the settings window or with:  cw live rules battery|fullscreen on|off
$ErrorActionPreference = 'SilentlyContinue'

$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\CaelestiaWinLiveGuard', [ref]$created)
if (-not $created) { exit }   # one guard is enough

Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class CwFullscreen {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
    [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr m, ref MONITORINFO mi);
    public static bool IsFullscreen() {
        IntPtr h = GetForegroundWindow();
        if (h == IntPtr.Zero) return false;
        StringBuilder sb = new StringBuilder(256);
        GetClassName(h, sb, 256);
        string c = sb.ToString();
        if (c == "Progman" || c == "WorkerW" || c == "Shell_TrayWnd" || c == "Shell_SecondaryTrayWnd") return false;   // the desktop itself
        RECT r;
        if (!GetWindowRect(h, out r)) return false;
        IntPtr m = MonitorFromWindow(h, 2);
        MONITORINFO mi = new MONITORINFO();
        mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
        if (!GetMonitorInfo(m, ref mi)) return false;
        return r.Left <= mi.rcMonitor.Left && r.Top <= mi.rcMonitor.Top && r.Right >= mi.rcMonitor.Right && r.Bottom >= mi.rcMonitor.Bottom;
    }
}
'@

$CwHome    = Join-Path $HOME '.config\caelestia-win'
$StateFile = Join-Path $CwHome 'state.json'

function Find-Lively {
    $c = @((Join-Path $env:LOCALAPPDATA 'Programs\Lively Wallpaper\Lively.exe'), (Join-Path $env:ProgramFiles 'Lively Wallpaper\Lively.exe'))
    foreach ($p in $c) { if (Test-Path -LiteralPath $p) { return $p } }
    $cmd = Get-Command 'Lively.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$lively = Find-Lively
if (-not $lively) { exit }

$paused = $false
while ($true) {
    $st = $null
    try { $st = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json } catch { }
    if ($st) {
        if (-not $st.live) { break }   # an animated wallpaper is no longer active
        $want = $false
        if ($st.livePauseBattery -ne $false) {
            if ([System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus -eq 'Offline') { $want = $true }
        }
        if ($st.livePauseFullscreen -ne $false) {
            if ([CwFullscreen]::IsFullscreen()) { $want = $true }
        }
        if ($want -ne $paused) {
            $flag = 'true'
            if ($want) { $flag = 'false' }
            Start-Process -FilePath $lively -ArgumentList @('app', '--play', $flag) -WindowStyle Hidden | Out-Null
            $paused = $want
        }
    }
    Start-Sleep -Seconds 4
}
try { $mutex.ReleaseMutex() } catch { }
