# PRISM Tray Icon - System Tray Integration
# Custom icon with professional appearance

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public class DpiHelper {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
$null = [DpiHelper]::SetProcessDPIAware()

# Resolve install path from registry; fall back to C:\PRISM
$script:prismPath = try {
    (Get-ItemProperty "HKLM:\SOFTWARE\PRISM" -Name "InstallPath" -ErrorAction Stop).InstallPath
} catch { "C:\PRISM" }

# Single-instance guard - exit silently if another PRISM tray process is running
$script:mutex = New-Object System.Threading.Mutex($false, "PRISM-Tray-Singleton")
$script:mutexAcquired = $false
try {
    $script:mutexAcquired = $script:mutex.WaitOne(0, $false)
} catch [System.Threading.AbandonedMutexException] {
    $script:mutexAcquired = $true   # previous process was killed; we now own it
}
if (-not $script:mutexAcquired) {
    $script:mutex.Dispose()
    exit 0
}

[System.Windows.Forms.Application]::EnableVisualStyles()

# Detect system dark mode
$script:isDark = $false
try {
    $script:isDark = (Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -ErrorAction Stop).AppsUseLightTheme -eq 0
} catch {}

# Win11-style renderer + DWM rounded corners - compiled lazily on first menu open
# so the tray icon appears immediately without waiting for C# compilation.
$script:typesCompiled = $false
$script:csharpCode = @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using System.Runtime.InteropServices;

public class Win11Renderer : ToolStripProfessionalRenderer {
    private readonly bool dark;

    private Color BG()     { return dark ? Color.FromArgb(40, 40, 40)   : Color.FromArgb(249, 249, 249); }
    private Color Hover()  { return dark ? Color.FromArgb(62, 62, 62)   : Color.FromArgb(230, 230, 230); }
    private Color FG()     { return dark ? Color.FromArgb(242, 242, 242) : Color.FromArgb(20, 20, 20); }
    private Color Dim()    { return dark ? Color.FromArgb(110, 110, 110) : Color.FromArgb(155, 155, 155); }
    private Color Sep()    { return dark ? Color.FromArgb(70, 70, 70)   : Color.FromArgb(210, 210, 210); }
    private Color Border() { return dark ? Color.FromArgb(70, 70, 70)   : Color.FromArgb(195, 195, 195); }

    public Win11Renderer(bool isDark) : base() { dark = isDark; }

    protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e) {
        using (SolidBrush b = new SolidBrush(BG()))
            e.Graphics.FillRectangle(b, e.AffectedBounds);
        Rectangle r = e.AffectedBounds;
        r.Width -= 1; r.Height -= 1;
        using (Pen p = new Pen(Border()))
            e.Graphics.DrawRectangle(p, r);
    }

    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e) {
        if (!e.Item.Selected || !e.Item.Enabled) return;
        Rectangle rect = new Rectangle(4, 2, e.Item.Width - 8, e.Item.Height - 4);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using (SolidBrush b = new SolidBrush(Hover()))
        using (GraphicsPath path = RoundRect(rect, 4))
            e.Graphics.FillPath(b, path);
    }

    protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e) {
        int y = e.Item.Height / 2;
        using (Pen p = new Pen(Sep()))
            e.Graphics.DrawLine(p, 8, y, e.Item.Width - 8, y);
    }

    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e) {
        string name = e.Item.Name ?? "";
        Color c = (name == "statusItem" || name == "timerItem")
                  ? e.Item.ForeColor
                  : (e.Item.Enabled ? FG() : Dim());
        TextFormatFlags flags = TextFormatFlags.VerticalCenter | TextFormatFlags.Left |
                                TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis |
                                TextFormatFlags.SingleLine;
        Rectangle r = new Rectangle(e.TextRectangle.X, 0, e.TextRectangle.Width, e.Item.Height);
        TextRenderer.DrawText(e.Graphics, e.Text, e.TextFont, r, c, flags);
    }

    protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e) {
        e.ArrowColor = e.Item.Enabled ? FG() : Dim();
        base.OnRenderArrow(e);
    }

    protected override void OnRenderImageMargin(ToolStripRenderEventArgs e) {
        using (SolidBrush b = new SolidBrush(BG()))
            e.Graphics.FillRectangle(b, e.AffectedBounds);
    }

    protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e) { }

    private static GraphicsPath RoundRect(Rectangle r, int rad) {
        int d = rad * 2;
        GraphicsPath gp = new GraphicsPath();
        gp.AddArc(r.X,         r.Y,          d, d, 180, 90);
        gp.AddArc(r.Right - d, r.Y,          d, d, 270, 90);
        gp.AddArc(r.Right - d, r.Bottom - d, d, d,   0, 90);
        gp.AddArc(r.X,         r.Bottom - d, d, d,  90, 90);
        gp.CloseFigure();
        return gp;
    }
}

public static class Dwm {
    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, uint attr, ref int val, int size);

    public static void RoundCorners(IntPtr hwnd) {
        int v = 3; // DWMWCP_ROUNDSMALL
        DwmSetWindowAttribute(hwnd, 33, ref v, 4);
    }
}

public class TaskbarCreatedMonitor : System.Windows.Forms.NativeWindow {
    private readonly System.Windows.Forms.NotifyIcon _icon;
    private static readonly uint _msg;

    [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Auto)]
    private static extern uint RegisterWindowMessage(string lpString);
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool ChangeWindowMessageFilterEx(IntPtr hWnd, uint msg, uint action, System.IntPtr change);

    static TaskbarCreatedMonitor() { _msg = RegisterWindowMessage("TaskbarCreated"); }

    public TaskbarCreatedMonitor(System.Windows.Forms.NotifyIcon icon) { _icon = icon; }

    public void AttachTo(System.Windows.Forms.Form form) {
        AssignHandle(form.Handle);
        if (_msg != 0) ChangeWindowMessageFilterEx(form.Handle, _msg, 1, System.IntPtr.Zero);
    }

    protected override void WndProc(ref System.Windows.Forms.Message m) {
        if (_msg != 0 && (uint)m.Msg == _msg) { _icon.Visible = false; _icon.Visible = true; }
        base.WndProc(ref m);
    }
}
"@

# Create a custom icon (teal/blue color - professional)
function Create-TealIcon {
    $bitmap   = New-Object System.Drawing.Bitmap(32, 32)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $teaBrush   = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(45, 166, 178))
    $whiteBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $darkBrush  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(25, 104, 115))
    $font       = New-Object System.Drawing.Font("Arial", 18, [System.Drawing.FontStyle]::Bold)
    $sf         = New-Object System.Drawing.StringFormat
    $sf.Alignment     = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center

    try {
        $graphics.FillEllipse($teaBrush, 1, 1, 30, 30)
        $graphics.FillEllipse($darkBrush, 4, 4, 24, 24)
        $graphics.DrawString("P", $font, $whiteBrush, [System.Drawing.RectangleF]::new(4, 4, 24, 24), $sf)
    } finally {
        $sf.Dispose(); $font.Dispose(); $graphics.Dispose()
        $teaBrush.Dispose(); $whiteBrush.Dispose(); $darkBrush.Dispose()
    }

    $icon = [System.Drawing.Icon]::FromHandle($bitmap.GetHicon())
    $bitmap.Dispose()
    return $icon
}

# Create main form (hidden)
$form = New-Object System.Windows.Forms.Form
$form.Text = "PRISM"
$form.Width = 1
$form.Height = 1
$form.StartPosition = "Manual"
$form.Location    = New-Object System.Drawing.Point(-32000, -32000)
$form.MinimumSize = New-Object System.Drawing.Size(1, 1)
$form.Opacity = 0
$form.ShowInTaskbar = $false
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.TopMost = $false

# Create notify icon (system tray)
$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$_icoPath = Join-Path $PSScriptRoot "prism-logo.ico"
if (Test-Path $_icoPath) {
    try {
        $notifyIcon.Icon = New-Object System.Drawing.Icon($_icoPath)
    } catch {
        $notifyIcon.Icon = Create-TealIcon
    }
} else {
    $notifyIcon.Icon = Create-TealIcon
}
$notifyIcon.Text = "PRISM - Running"

# Create context menu with Win11 styling
$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$contextMenu.ShowCheckMargin = $false
$contextMenu.Padding = New-Object System.Windows.Forms.Padding(0, 6, 0, 6)

try {
    $contextMenu.Font = New-Object System.Drawing.Font("Segoe UI Variable Text", 10)
} catch {
    $contextMenu.Font = New-Object System.Drawing.Font("Segoe UI", 10)
}

# Apply DWM rounded corners when menu opens (only after C# is compiled)
$contextMenu.Add_Opened({
    if ($script:typesCompiled) {
        try { [Dwm]::RoundCorners($contextMenu.Handle) } catch {}
    }
})

# Menu item 1: Status (dynamic, updated on open)
$statusItem = New-Object System.Windows.Forms.ToolStripMenuItem
$statusItem.Name    = "statusItem"
$statusItem.Enabled = $false
$contextMenu.Items.Add($statusItem) | Out-Null

$timerItem = New-Object System.Windows.Forms.ToolStripMenuItem
$timerItem.Name      = "timerItem"
$timerItem.Enabled   = $false
$timerItem.ForeColor = [System.Drawing.Color]::FromArgb(110, 110, 110)
$contextMenu.Items.Add($timerItem) | Out-Null

$script:lastTaskText  = "Status: Checking..."

function Set-StatusColor {
    if     ($script:lastTaskText -match 'Ready|Running') {
        $statusItem.ForeColor = [System.Drawing.Color]::FromArgb(63,  185, 80)   # green
    } elseif ($script:lastTaskText -match 'Recycled|Disabled') {
        $statusItem.ForeColor = [System.Drawing.Color]::FromArgb(210, 153, 34)   # amber
    } else {
        $statusItem.ForeColor = [System.Drawing.Color]::FromArgb(255, 107, 99)   # red
    }
}

function Get-PRISMRegProp {
    param([string]$Name)
    try { (Get-ItemProperty "HKLM:\SOFTWARE\PRISM" -Name $Name -ErrorAction Stop).$Name } catch { $null }
}

function Update-TimerText {
    try {
        $intervalMin = [int](Get-PRISMRegProp "MonitoringInterval")
        if (-not $intervalMin) { $intervalMin = 8 }

        $taskInfo = Get-ScheduledTaskInfo -TaskName "PRISM-Monitor" -ErrorAction SilentlyContinue
        $nextRun  = $null
        if ($taskInfo -and $taskInfo.NextRunTime) {
            $candidate = [datetime]$taskInfo.NextRunTime
            if ($candidate -gt [datetime]::Now) { $nextRun = $candidate }
        }

        # SYSTEM tasks aren't queryable from non-admin; estimate from LastRun registry value.
        # Advance by full cycles so we always resolve to the next future trigger.
        if (-not $nextRun) {
            $lastRunStr = Get-PRISMRegProp "LastRun"
            if ($lastRunStr) {
                $lastRun     = [datetime]$lastRunStr
                $intervalSec = $intervalMin * 60
                $elapsedSec  = ([datetime]::Now - $lastRun).TotalSeconds
                $cyclesDue   = [Math]::Floor($elapsedSec / $intervalSec)
                $nextRun     = $lastRun.AddSeconds(($cyclesDue + 1) * $intervalSec)
            }
        }

        if (-not $nextRun) {
            $timerItem.Text = "Next check: N/A"
            return
        }
        $left = $nextRun - [datetime]::Now
        if ($left.TotalSeconds -le 0) {
            $timerItem.Text = "Next check: now"
            return
        }
        $totalSecs = $intervalMin * 60
        $elapsed   = [Math]::Max(0.0, $totalSecs - $left.TotalSeconds)
        $progress  = [Math]::Min(1.0, $elapsed / $totalSecs)
        $barWidth  = 8
        $filled    = [int][Math]::Round($progress * $barWidth)
        $bar       = ([string]([char]0x2588) * $filled) + ([string]([char]0x2591) * ($barWidth - $filled))
        $mins      = [Math]::Floor($left.TotalMinutes)
        $secs      = $left.Seconds
        $timerItem.Text = "Next check: ${mins}m ${secs}s  $bar"
    } catch {
        $timerItem.Text = "Next check: Unknown"
    }
}

$contextMenu.Add_Opening({
    $statusItem.Text = $script:lastTaskText
    Set-StatusColor
    Update-TimerText
    if (([datetime]::Now - $script:lastTaskCheck).TotalSeconds -gt 60) {
        $script:refreshTimer.Start()
    }
})

$contextMenu.Items.Add("-") | Out-Null

# Menu item 2: Open S: Drive
$openItem = New-Object System.Windows.Forms.ToolStripMenuItem
$openItem.Text = "Open S: Drive"
$openItem.Add_Click({
    try {
        Start-Process "explorer.exe" -ArgumentList "S:\"
    } catch {
        [System.Windows.Forms.MessageBox]::Show("S: drive not accessible", "PRISM", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    }
})
$contextMenu.Items.Add($openItem) | Out-Null

# Menu item 3: View Logs
$logsItem = New-Object System.Windows.Forms.ToolStripMenuItem
$logsItem.Text = "View Logs"
$logsItem.Add_Click({
    $logsDir = Join-Path $script:prismPath "logs"
    if(Test-Path $logsDir) {
        Start-Process "explorer.exe" -ArgumentList $logsDir
    } else {
        [System.Windows.Forms.MessageBox]::Show("Logs folder not found", "PRISM", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
})
$contextMenu.Items.Add($logsItem) | Out-Null

# Menu item 4: S: Drive Info
$infoItem = New-Object System.Windows.Forms.ToolStripMenuItem
$infoItem.Text = "S: Drive Info"
$infoItem.Add_Click({
    $sDrive = Get-PSDrive -Name S -ErrorAction SilentlyContinue
    if($sDrive) {
        $usedGB = [Math]::Round($sDrive.Used / 1GB, 2)
        $freeGB = [Math]::Round($sDrive.Free / 1GB, 2)
        $totalGB = $usedGB + $freeGB
        $info = "S: Drive Status`n`n" + `
                "Total: $totalGB GB`n" + `
                "Used: $usedGB GB`n" + `
                "Free: $freeGB GB`n" + `
                "Status: Online"
        [System.Windows.Forms.MessageBox]::Show($info, "S: Drive Information", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } else {
        [System.Windows.Forms.MessageBox]::Show("S: drive not found or offline", "S: Drive Information", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    }
})
$contextMenu.Items.Add($infoItem) | Out-Null

$runNowItem = New-Object System.Windows.Forms.ToolStripMenuItem
$runNowItem.Text = "Run Monitor Now"
$runNowItem.Add_Click({
    try {
        Start-ScheduledTask -TaskName "PRISM-Monitor" -ErrorAction Stop
        [System.Windows.Forms.MessageBox]::Show("PRISM-Monitor triggered.", "PRISM", `
            [System.Windows.Forms.MessageBoxButtons]::OK, `
            [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        # Task missing or insufficient permissions - run PRISM.ps1 directly with elevation
        try {
            $prismScript = Join-Path $script:prismPath "PRISM.ps1"
            Start-Process powershell.exe -ArgumentList `
                "-NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File `"$prismScript`" -Action Monitor" `
                -Verb RunAs -ErrorAction Stop
            [System.Windows.Forms.MessageBox]::Show("Monitor triggered.", "PRISM", `
                [System.Windows.Forms.MessageBoxButtons]::OK, `
                [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Could not trigger monitor. Check Task Scheduler.", "PRISM", `
                [System.Windows.Forms.MessageBoxButtons]::OK, `
                [System.Windows.Forms.MessageBoxIcon]::Warning)
        }
    }
})
$contextMenu.Items.Add($runNowItem) | Out-Null

$forceRecycleItem = New-Object System.Windows.Forms.ToolStripMenuItem
$forceRecycleItem.Text = "Force Recycle Now"
$forceRecycleItem.Add_Click({
    $prismScript = Join-Path $script:prismPath "PRISM.ps1"
    if (-not (Test-Path $prismScript)) {
        [System.Windows.Forms.MessageBox]::Show(
            "PRISM is not fully installed.`nExpected: $prismScript",
            "PRISM - Not Installed",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }
    $result = [System.Windows.Forms.MessageBox]::Show(
        "Force partition recycle now?`n`nThis will delete the oldest folders on S: to free space.",
        "PRISM - Force Recycle",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        try {
            Start-Process powershell.exe -ArgumentList `
                "-NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File `"$prismScript`" -Action Format" `
                -Verb RunAs -ErrorAction Stop
            $notifyIcon.ShowBalloonTip(5000, "PRISM", "Force recycle started - check logs for results.", [System.Windows.Forms.ToolTipIcon]::Info)
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Could not start recycle. Try running as administrator.",
                "PRISM",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
})
$contextMenu.Items.Add($forceRecycleItem) | Out-Null

$configItem = New-Object System.Windows.Forms.ToolStripMenuItem
$configItem.Text = "Configure PRISM..."
$configItem.Add_Click({
    $configPath = Join-Path $script:prismPath "PRISM-Config.ps1"
    if (-not (Test-Path $configPath)) {
        [System.Windows.Forms.MessageBox]::Show("Configuration file not found at $script:prismPath", "PRISM", `
            [System.Windows.Forms.MessageBoxButtons]::OK, `
            [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }
    try {
        # Launch hidden (no OS-level SW_HIDE so UAC works); Config self-elevates via UAC
        Start-Process powershell.exe `
            -ArgumentList "-NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File `"$configPath`""
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Could not open configuration.", "PRISM", `
            [System.Windows.Forms.MessageBoxButtons]::OK, `
            [System.Windows.Forms.MessageBoxIcon]::Warning)
    }
})
$contextMenu.Items.Add($configItem) | Out-Null

$contextMenu.Items.Add("-") | Out-Null

# Menu item 5: Remove PRISM
$removeItem = New-Object System.Windows.Forms.ToolStripMenuItem
$removeItem.Text = "Remove PRISM..."
$removeItem.Add_Click({
    $stopScript = Join-Path $script:prismPath "PRISM-Stop.ps1"
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File `"$stopScript`"" -Verb RunAs
})
$contextMenu.Items.Add($removeItem) | Out-Null

$contextMenu.Items.Add("-") | Out-Null

# Menu item 6: About
$aboutItem = New-Object System.Windows.Forms.ToolStripMenuItem
$aboutItem.Text = "About PRISM"
$aboutItem.Add_Click({
    $t = Get-ScheduledTask -TaskName "PRISM-Monitor" -ErrorAction SilentlyContinue
    $taskState = if ($t) { $t.State } else { "Not Installed" }
    $sDriveAbout = Get-PSDrive -Name S -ErrorAction SilentlyContinue
    $driveSizeGB = if ($sDriveAbout) { [Math]::Round(($sDriveAbout.Used + $sDriveAbout.Free) / 1GB, 0) } else { "?" }
    $about = "PRISM`n`n" + `
             "Virtual Drive Management`n`n" + `
             "${driveSizeGB}GB S: Drive`n" + `
             "Installation: $script:prismPath`n" + `
             "Monitor Task: $taskState"
    [System.Windows.Forms.MessageBox]::Show($about, "About PRISM", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
})
$contextMenu.Items.Add($aboutItem) | Out-Null

$contextMenu.Items.Add("-") | Out-Null

$quitItem      = New-Object System.Windows.Forms.ToolStripMenuItem
$quitItem.Text = "Quit PRISM Tray"
$quitItem.Add_Click({
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    $form.Close()
})
$contextMenu.Items.Add($quitItem) | Out-Null

# Increase vertical padding on every menu item for more breathing room
foreach ($item in $contextMenu.Items) {
    if ($item -is [System.Windows.Forms.ToolStripMenuItem]) {
        $item.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)
    }
}

$notifyIcon.ContextMenuStrip = $contextMenu

# Double-click to open S: drive
$notifyIcon.Add_DoubleClick({
    try {
        Start-Process "explorer.exe" -ArgumentList "S:\"
    } catch {
        [System.Windows.Forms.MessageBox]::Show("S: drive not accessible", "PRISM", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    }
})

# Defer C# compilation into the message loop so Application::Run starts
# immediately and the menu is interactive from the first right-click.
# Compilation blocks the UI thread briefly but only after the pump is running,
# so early right-clicks are queued and processed rather than discarded.
$script:compileTimer = New-Object System.Windows.Forms.Timer
$script:compileTimer.Interval = 100
$script:compileTimer.Add_Tick({
    $script:compileTimer.Stop()
    $compiled = $false
    try {
        Add-Type -TypeDefinition $script:csharpCode -ReferencedAssemblies System.Windows.Forms,System.Drawing
        $contextMenu.Renderer = New-Object Win11Renderer($script:isDark)
        $script:taskbarMonitor = New-Object TaskbarCreatedMonitor($notifyIcon)
        $script:taskbarMonitor.AttachTo($form)
        $compiled = $true
    } catch {}
    $script:typesCompiled = $compiled
})
$script:compileTimer.Start()

$script:lastTaskCheck = [datetime]::MinValue

$script:refreshTimer = New-Object System.Windows.Forms.Timer
$script:refreshTimer.Interval = 50
$script:refreshTimer.Add_Tick({
    # First tick fires 50ms after startup so the icon appears instantly;
    # afterwards re-arm at 60s so the status/tooltip stay fresh.
    $script:refreshTimer.Stop()
    $script:refreshTimer.Interval = 60000
    $script:refreshTimer.Start()
    try {
        $t = Get-ScheduledTask -TaskName "PRISM-Monitor" -ErrorAction SilentlyContinue
        if ($t) {
            $script:lastTaskText = "Status: $($t.State)"
        } else {
            # SYSTEM-account tasks are invisible to non-admin Get-ScheduledTask.
            # Read the LastRun/LastResult values written by PRISM.ps1 each cycle.
            $lastRunStr = Get-PRISMRegProp "LastRun"
            $lastResult = Get-PRISMRegProp "LastResult"
            $intervalMin = [int](Get-PRISMRegProp "MonitoringInterval")
            if (-not $intervalMin) { $intervalMin = 8 }

            if ($lastRunStr) {
                $minutesAgo = ([datetime]::Now - [datetime]$lastRunStr).TotalMinutes
                if ($minutesAgo -le ($intervalMin * 2 + 5)) {
                    $script:lastTaskText = switch ($lastResult) {
                        "Recycled"   { "Status: Recycled" }
                        "DriveError" { "Status: Drive Error" }
                        default      { "Status: Ready" }
                    }
                } else {
                    $script:lastTaskText = "Status: Stale ($([int]$minutesAgo)m ago)"
                }
            } else {
                $script:lastTaskText = "Status: Not Installed"
            }
        }
    } catch {
        $script:lastTaskText = "Status: Unknown"
    }
    $script:lastTaskCheck = [datetime]::Now
    $statusItem.Text = $script:lastTaskText
    Set-StatusColor
    Update-TimerText

    # Mirror the status into the tray tooltip (NotifyIcon.Text caps at 63 chars)
    try {
        $tip = "PRISM - " + ($script:lastTaskText -replace '^Status:\s*', '')
        $sDriveTip = Get-PSDrive -Name S -ErrorAction SilentlyContinue
        if ($sDriveTip) {
            $pctTip = [Math]::Round($sDriveTip.Used * 100 / ($sDriveTip.Used + $sDriveTip.Free), 0)
            $tip += " | S: $pctTip% used"
        }
        if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 63) }
        $notifyIcon.Text = $tip
    } catch {}
})
$script:refreshTimer.Start()

# Form close handler - set icon invisible and release mutex here;
# dispose the NotifyIcon object only after Application::Run returns (see below).
$form.Add_FormClosing({
    $notifyIcon.Visible = $false
    try { $script:mutex.ReleaseMutex() } catch {}
    $script:mutex.Dispose()
})

# Hide the ghost form and show the startup balloon once the message loop is running.
# ShowBalloonTip requires an active message pump; calling it before Application::Run
# causes the balloon to be silently dropped on modern Windows.
$form.Add_Shown({
    $form.Hide()
    # Register the icon only after the message pump is running so the shell's
    # round-trip validation (NIN_SELECT bounce-back on Win11 22H2+) is answered.
    $notifyIcon.Visible = $true
    $notifyIcon.ShowBalloonTip(5000, "PRISM", "Running`nRight-click icon for menu", [System.Windows.Forms.ToolTipIcon]::Info)
})

[System.Windows.Forms.Application]::Run($form)

$notifyIcon.Dispose()
$form.Dispose()
