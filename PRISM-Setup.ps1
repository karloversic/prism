if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File `"$PSCommandPath`"" -Verb RunAs
    exit
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DpiHelper {
    [DllImport("user32.dll")]   public static extern bool   SetProcessDPIAware();
    [DllImport("user32.dll")]   public static extern bool   ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
}
"@
$null = [DpiHelper]::SetProcessDPIAware()

# Enable visual styles so WinForms controls render with the OS theme
# (must be called before any controls are created / form is shown)
[System.Windows.Forms.Application]::EnableVisualStyles()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

# Color palette
$BG       = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
$BG_CARD  = [System.Drawing.ColorTranslator]::FromHtml("#161b22")
$BG_INPUT = [System.Drawing.ColorTranslator]::FromHtml("#21262d")
$BORDER   = [System.Drawing.ColorTranslator]::FromHtml("#30363d")
$TEXT_PRI = [System.Drawing.ColorTranslator]::FromHtml("#e6edf3")
$TEXT_SEC = [System.Drawing.ColorTranslator]::FromHtml("#8b949e")
$ACCENT   = [System.Drawing.ColorTranslator]::FromHtml("#2ea2cc")
$SUCCESS  = [System.Drawing.ColorTranslator]::FromHtml("#3fb950")
$DANGER   = [System.Drawing.ColorTranslator]::FromHtml("#f85149")

$FONT_BOLD   = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$FONT_NORMAL = New-Object System.Drawing.Font("Segoe UI", 10)
$FONT_SMALL  = New-Object System.Drawing.Font("Segoe UI", 9)
$FONT_MONO   = New-Object System.Drawing.Font("Consolas", 9)
$FONT_TITLE  = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$FONT_HEADER = New-Object System.Drawing.Font("Segoe UI", 11)

# All layout coordinates are 96-DPI design units; the whole form is scaled once
# (see $form.Scale call before Application::Run) when the display DPI differs.
$script:HINT_H = [Math]::Ceiling($FONT_SMALL.GetHeight(96)) + 2

$_g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
$script:DPI_SCALE = $_g.DpiX / 96.0
$_g.Dispose()

$script:USBPath = $PSScriptRoot

# Run a sub-script as a hidden separate process; returns exit code.
# -WindowStyle Hidden is passed both inside $psArgs (consumed by powershell.exe)
# and as a Start-Process parameter (OS-level process creation flag) — both are
# intentional: the former controls PowerShell's own window style setting, the
# latter suppresses the console window at the Win32 CreateProcess level.
function Run-Script {
    param([string]$Path, [string]$ExtraArgs = "")
    $psArgs = "-NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File `"$Path`""
    if ($ExtraArgs) { $psArgs += " $ExtraArgs" }
    $proc = Start-Process powershell.exe -ArgumentList $psArgs -Wait -PassThru -WindowStyle Hidden
    return $proc.ExitCode
}

# Checks
$alreadyInstalled = Test-Path "HKLM:\SOFTWARE\PRISM"
$requiredFiles    = @(
    "PRISM.ps1","PRISM-Deploy.ps1","PRISM-CreateSDrive.ps1","PRISM-Config.ps1",
    "PRISM-Stop.ps1","PRISM-Remove.ps1","PRISM-Remove.bat","PRISM-Tray.ps1","PRISM-Troubleshoot.bat",
    "PRISM-Launch.vbs"
)
$missingFiles = $requiredFiles | Where-Object { -not (Test-Path (Join-Path $script:USBPath $_)) }

# ── Layout constants (all in client-area coordinates) ─────────────────────────
# Client width 480 matches PRISM-Config and PRISM-Stop.
$CLIENT_W    = 480
$CLIENT_H    = 590
$HEADER_H    = 60
$PANEL_Y     = $HEADER_H
$PANEL_H     = $CLIENT_H - $HEADER_H   # 500
$CARD_X      = 20
$CARD_W      = $CLIENT_W - 40          # 540

# ── Main form ──────────────────────────────────────────────────────────────────
$form                 = New-Object System.Windows.Forms.Form
$form.Text            = "PRISM Setup"
$form.ClientSize      = New-Object System.Drawing.Size($CLIENT_W, $CLIENT_H)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox     = $false
$form.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor       = $BG
$form.ForeColor       = $TEXT_PRI
$form.Font            = $FONT_NORMAL
$_icoPath = Join-Path $script:USBPath "prism-logo.ico"
if (Test-Path $_icoPath) { try { $form.Icon = New-Object System.Drawing.Icon($_icoPath) } catch {} }

# ── Header ─────────────────────────────────────────────────────────────────────
$header           = New-Object System.Windows.Forms.Panel
$header.Location  = New-Object System.Drawing.Point(0, 0)
$header.Size      = New-Object System.Drawing.Size($CLIENT_W, $HEADER_H)
$header.BackColor = $BG_CARD

$lblTitle           = New-Object System.Windows.Forms.Label
$lblTitle.Text      = "PRISM"
$lblTitle.Font      = $FONT_TITLE
$lblTitle.ForeColor = $ACCENT
$lblTitle.AutoSize  = $true
$lblTitle.Location  = New-Object System.Drawing.Point(24, 0)

$script:lblH2           = New-Object System.Windows.Forms.Label
$script:lblH2.Text      = "Installation Setup"
$script:lblH2.Font      = $FONT_HEADER
$script:lblH2.ForeColor = $TEXT_SEC
$script:lblH2.AutoSize  = $true
$script:lblH2.Location  = New-Object System.Drawing.Point(106, 0)

$header.Controls.AddRange(@($lblTitle, $script:lblH2))

# ── Phase 1: Config panel ──────────────────────────────────────────────────────
$cfgPanel           = New-Object System.Windows.Forms.Panel
$cfgPanel.Location  = New-Object System.Drawing.Point(0, $PANEL_Y)
$cfgPanel.Size      = New-Object System.Drawing.Size($CLIENT_W, $PANEL_H)
$cfgPanel.BackColor = $BG

# Error card (shown when blocked)
$errCard           = New-Object System.Windows.Forms.Panel
$errCard.Location  = New-Object System.Drawing.Point($CARD_X, 20)
$errCard.Size      = New-Object System.Drawing.Size($CARD_W, 88)
$errCard.BackColor = $BG_CARD
$errCard.Visible   = $false

$lblErrTitle           = New-Object System.Windows.Forms.Label
$lblErrTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$lblErrTitle.ForeColor = $DANGER
$lblErrTitle.Location  = New-Object System.Drawing.Point(16, 12)
$lblErrTitle.Size      = New-Object System.Drawing.Size(408, 22)

$lblErrBody           = New-Object System.Windows.Forms.Label
$lblErrBody.Font      = $FONT_SMALL
$lblErrBody.ForeColor = $TEXT_SEC
$lblErrBody.Location  = New-Object System.Drawing.Point(16, 38)
$lblErrBody.Size      = New-Object System.Drawing.Size(408, 38)

$errCard.Controls.AddRange(@($lblErrTitle, $lblErrBody))

# Settings card — y=20, h=268
# Layout verification (all Y coords relative to settingsCard):
#   Title row:    y=14 (AutoSize label, ~20px tall) → bottom ≈ 34
#   Row 1 (Size):     y=48,  hint y=70 (bottom=88), NUD wrapper y=52 (bottom=86)
#   Row 2 (Thresh):   y=104, hint y=126 (bottom=144), NUD wrapper y=108 (bottom=142)
#   Row 3 (Preserve): y=160, hint y=182 (bottom=200), NUD wrapper y=164 (bottom=198)
#   Row 4 (Interval): y=216, hint y=238 (bottom=256), NUD wrapper y=220 (bottom=254)
#   Card height = 268 → bottom padding = 268-256 = 12 px ✓
$settingsCard           = New-Object System.Windows.Forms.Panel
$settingsCard.Location  = New-Object System.Drawing.Point($CARD_X, 20)
$settingsCard.Size      = New-Object System.Drawing.Size($CARD_W, 268)
$settingsCard.BackColor = $BG_CARD

$lblSettingsTitle           = New-Object System.Windows.Forms.Label
$lblSettingsTitle.Text      = "Configure your installation"
$lblSettingsTitle.Font      = $FONT_BOLD
$lblSettingsTitle.ForeColor = $TEXT_PRI
$lblSettingsTitle.Location  = New-Object System.Drawing.Point(16, 14)
$lblSettingsTitle.AutoSize  = $true

$settingsCard.Controls.Add($lblSettingsTitle)

# Helper: label + description + bordered NumericUpDown row
function New-Row {
    param(
        [System.Windows.Forms.Panel]$Parent,
        [int]$Y,
        [string]$LabelText,
        [string]$Desc,
        [int]$Min, [int]$Max, [int]$Default
    )
    # Main label
    $lbl           = New-Object System.Windows.Forms.Label
    $lbl.Text      = $LabelText
    $lbl.Font      = $FONT_NORMAL
    $lbl.ForeColor = $TEXT_PRI
    $lbl.Location  = New-Object System.Drawing.Point(16, $Y)
    $lbl.Size      = New-Object System.Drawing.Size(260, 22)
    $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    # Hint / description
    $hint           = New-Object System.Windows.Forms.Label
    $hint.Text      = $Desc
    $hint.Font      = $FONT_SMALL
    $hint.ForeColor = $TEXT_SEC
    $hint.Location  = New-Object System.Drawing.Point(16, ($Y + 22))
    $hint.Size      = New-Object System.Drawing.Size(260, $script:HINT_H)

    # Bordered wrapper; right edge at 424 (card-relative) leaves 16px padding
    $wrap           = New-Object System.Windows.Forms.Panel
    $wrap.Location  = New-Object System.Drawing.Point(284, ($Y + 4))
    $wrap.Size      = New-Object System.Drawing.Size(140, 34)
    $wrap.BackColor = $BORDER

    $nud              = New-Object System.Windows.Forms.NumericUpDown
    $nud.Location     = New-Object System.Drawing.Point(1, 1)
    $nud.Size         = New-Object System.Drawing.Size(138, 32)
    $nud.Minimum      = $Min
    $nud.Maximum      = $Max
    $nud.Value        = $Default
    $nud.BackColor    = $BG_INPUT
    $nud.ForeColor    = $TEXT_PRI
    $nud.BorderStyle  = [System.Windows.Forms.BorderStyle]::None
    $nud.Font         = New-Object System.Drawing.Font("Segoe UI", 11)
    $nud.TextAlign    = [System.Windows.Forms.HorizontalAlignment]::Center

    $wrap.Controls.Add($nud)
    $Parent.Controls.AddRange(@($lbl, $hint, $wrap))
    return $nud
}

# Rows: each row occupies 56px (22 label + 18 hint + 16 spacing between rows)
$script:nudSize     = New-Row -Parent $settingsCard -Y 48  -LabelText "Virtual drive size"      -Desc "Gigabytes (5 - 2000)"        -Min 5  -Max 2000 -Default 50
$script:nudSize.Add_ValueChanged({
    $needed = [int]$script:nudSize.Value + 5
    $lblNote.Text = "Requires $needed GB free on C:     Windows 8.1+     PowerShell 5.0+"
})
$script:nudThresh   = New-Row -Parent $settingsCard -Y 104 -LabelText "Capacity threshold"      -Desc "Delete oldest when over (%)"  -Min 80 -Max 99   -Default 95
$script:nudPreserve = New-Row -Parent $settingsCard -Y 160 -LabelText "Folders to preserve"     -Desc "Minimum kept during recycle"  -Min 1  -Max 20   -Default 5
$script:nudInterval = New-Row -Parent $settingsCard -Y 216 -LabelText "Monitor interval"        -Desc "Check frequency (minutes)"   -Min 1  -Max 60   -Default 8

# Info card — y = 20 + 268 + 12 = 300
$infoCard           = New-Object System.Windows.Forms.Panel
$infoCard.Location  = New-Object System.Drawing.Point($CARD_X, 300)
$infoCard.Size      = New-Object System.Drawing.Size($CARD_W, 104)
$infoCard.BackColor = $BG_CARD

$lblInfoTitle           = New-Object System.Windows.Forms.Label
$lblInfoTitle.Text      = "What will be installed"
$lblInfoTitle.Font      = $FONT_BOLD
$lblInfoTitle.ForeColor = $TEXT_PRI
$lblInfoTitle.Location  = New-Object System.Drawing.Point(16, 12)
$lblInfoTitle.AutoSize  = $true

$lblInfoBody           = New-Object System.Windows.Forms.Label
$lblInfoBody.Text      = "S: virtual drive (VHD)   C:\PRISM folder   PRISM-Monitor task   System tray icon"
$lblInfoBody.Font      = $FONT_SMALL
$lblInfoBody.ForeColor = $TEXT_SEC
$lblInfoBody.Location  = New-Object System.Drawing.Point(16, 44)
$lblInfoBody.Size      = New-Object System.Drawing.Size(408, 44)

$infoCard.Controls.AddRange(@($lblInfoTitle, $lblInfoBody))

# Requirements note — y = 300 + 116 + 10 = 426
$lblNote           = New-Object System.Windows.Forms.Label
$lblNote.Text      = "Requires 55 GB free on C:     Windows 8.1+     PowerShell 5.0+"
$lblNote.Font      = $FONT_SMALL
$lblNote.ForeColor = $TEXT_SEC
$lblNote.Location  = New-Object System.Drawing.Point($CARD_X, 426)
$lblNote.Size      = New-Object System.Drawing.Size($CARD_W, $script:HINT_H)
$lblNote.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

# Buttons — y = 426 + HINT_H + 20 ≈ 460  → bottom = 460+42 = 502 < 530 (PANEL_H) ✓
# Both buttons together span 130+12+170=312px; (480-312)/2=84 → centered
$btnBegin                              = New-Object System.Windows.Forms.Button
$btnBegin.Text                         = "Begin Installation"
$btnBegin.Font                         = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnBegin.ForeColor                    = $BG
$btnBegin.BackColor                    = $ACCENT
$btnBegin.FlatStyle                    = [System.Windows.Forms.FlatStyle]::Flat
$btnBegin.FlatAppearance.BorderSize    = 0
$btnBegin.Location                     = New-Object System.Drawing.Point(226, 460)
$btnBegin.Size                         = New-Object System.Drawing.Size(170, 42)
$btnBegin.Cursor                       = [System.Windows.Forms.Cursors]::Hand

$btnCancel                             = New-Object System.Windows.Forms.Button
$btnCancel.Text                        = "Cancel"
$btnCancel.Font                        = $FONT_NORMAL
$btnCancel.ForeColor                   = $TEXT_SEC
$btnCancel.BackColor                   = $BG_CARD
$btnCancel.FlatStyle                   = [System.Windows.Forms.FlatStyle]::Flat
$btnCancel.FlatAppearance.BorderColor  = $BORDER
$btnCancel.FlatAppearance.BorderSize   = 1
$btnCancel.Location                    = New-Object System.Drawing.Point(84, 460)
$btnCancel.Size                        = New-Object System.Drawing.Size(130, 42)
$btnCancel.Cursor                      = [System.Windows.Forms.Cursors]::Hand

$btnOpenRemove                             = New-Object System.Windows.Forms.Button
$btnOpenRemove.Text                        = "Open Remove Menu"
$btnOpenRemove.Font                        = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnOpenRemove.ForeColor                   = [System.Drawing.Color]::White
$btnOpenRemove.BackColor                   = $DANGER
$btnOpenRemove.FlatStyle                   = [System.Windows.Forms.FlatStyle]::Flat
$btnOpenRemove.FlatAppearance.BorderSize   = 0
$btnOpenRemove.Location                    = New-Object System.Drawing.Point(226, 460)
$btnOpenRemove.Size                        = New-Object System.Drawing.Size(170, 42)
$btnOpenRemove.Cursor                      = [System.Windows.Forms.Cursors]::Hand
$btnOpenRemove.Visible                     = $false

$cfgPanel.Controls.AddRange(@($errCard, $settingsCard, $infoCard, $lblNote, $btnBegin, $btnCancel, $btnOpenRemove))

# ── Phase 2: Deploy panel ──────────────────────────────────────────────────────
$depPanel           = New-Object System.Windows.Forms.Panel
$depPanel.Location  = New-Object System.Drawing.Point(0, $PANEL_Y)
$depPanel.Size      = New-Object System.Drawing.Size($CLIENT_W, $PANEL_H)
$depPanel.BackColor = $BG
$depPanel.Visible   = $false

# rtb: y=16, h=390 → bottom=406
$rtb              = New-Object System.Windows.Forms.RichTextBox
$rtb.Location     = New-Object System.Drawing.Point(20, 16)
$rtb.Size         = New-Object System.Drawing.Size(440, 390)
$rtb.BackColor    = $BG_CARD
$rtb.ForeColor    = $TEXT_PRI
$rtb.Font         = $FONT_MONO
$rtb.ReadOnly     = $true
$rtb.BorderStyle  = [System.Windows.Forms.BorderStyle]::None
$rtb.ScrollBars   = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical

# btnClose: y=428, h=42 → bottom=470 < 500 (PANEL_H) ✓
$btnClose                              = New-Object System.Windows.Forms.Button
$btnClose.Text                         = "Close"
$btnClose.Font                         = $FONT_NORMAL
$btnClose.ForeColor                    = $TEXT_SEC
$btnClose.BackColor                    = $BG_CARD
$btnClose.FlatStyle                    = [System.Windows.Forms.FlatStyle]::Flat
$btnClose.FlatAppearance.BorderColor   = $BORDER
$btnClose.FlatAppearance.BorderSize    = 1
$btnClose.Location                     = New-Object System.Drawing.Point(290, 428)
$btnClose.Size                         = New-Object System.Drawing.Size(170, 42)
$btnClose.Enabled                      = $false
$btnClose.Cursor                       = [System.Windows.Forms.Cursors]::Hand

$depPanel.Controls.AddRange(@($rtb, $btnClose))

# ── Assemble form ──────────────────────────────────────────────────────────────
$form.Controls.AddRange(@($header, $cfgPanel, $depPanel))

# ── Log helpers ────────────────────────────────────────────────────────────────
function Add-Log {
    param([string]$Text, [System.Drawing.Color]$Color = $TEXT_PRI)
    $rtb.SelectionStart  = $rtb.TextLength
    $rtb.SelectionLength = 0
    $rtb.SelectionColor  = $Color
    $rtb.AppendText($Text + "`n")
    $rtb.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Add-Step { param([string]$Text) Add-Log "  [ ] $Text ..." $TEXT_SEC }
function Add-OK   { param([string]$Text) Add-Log "  [$([char]0x2713)] $Text" $SUCCESS  }
function Add-Err  { param([string]$Text) Add-Log "  [!!] $Text"   $DANGER   }
function Add-Sep  { Add-Log ("  " + ("-" * 42)) $BORDER }

# ── Blocked-state setup ────────────────────────────────────────────────────────
if ($alreadyInstalled -or $missingFiles.Count -gt 0) {
    $settingsCard.Visible = $false
    $infoCard.Visible     = $false
    $lblNote.Visible      = $false
    $btnBegin.Visible     = $false
    $errCard.Visible      = $true

    if ($alreadyInstalled) {
        $lblErrTitle.Text = "PRISM is already installed on this system"
        $lblErrBody.Text  = "Use the Remove Menu to uninstall or manage your installation, then run this installer again."
        # Two-button layout matches normal Begin/Cancel positions
        $btnCancel.Text        = "Close"
        $btnOpenRemove.Visible = $true
    } else {
        $lblErrTitle.Text = "Missing required files"
        $lblErrBody.Text  = ($missingFiles -join ", ") + "`nAll PRISM files must be in the same folder as this installer."
        # Single centered Close button
        $btnCancel.Text     = "Close"
        $btnCancel.Location = New-Object System.Drawing.Point(175, 460)
    }
}

# ── Deployment ─────────────────────────────────────────────────────────────────
function Start-Deploy {
    $driveSize   = [int]$script:nudSize.Value
    $threshold   = [int]$script:nudThresh.Value
    $preserve    = [int]$script:nudPreserve.Value
    $interval    = [int]$script:nudInterval.Value
    $installPath = "C:\PRISM"
    $logsPath    = "C:\PRISM\logs"
    $usbPath     = $script:USBPath

    $cfgPanel.Visible  = $false
    $depPanel.Visible  = $true
    $script:lblH2.Text = "Installing..."

    Add-Log ""
    Add-Log "  PRISM  --  Partition Recycling and" $ACCENT
    Add-Log "             Intelligent Storage Management" $ACCENT
    Add-Log "  Drive: ${driveSize} GB   Threshold: ${threshold}%   Preserve: ${preserve}   Interval: ${interval} min" $TEXT_SEC
    Add-Sep
    Add-Log ""

    # Step 1: folders + files
    Add-Step "Creating installation folder and copying files"
    try {
        $null = New-Item -ItemType Directory -Path $installPath             -Force
        $null = New-Item -ItemType Directory -Path $logsPath                -Force
        $null = New-Item -ItemType Directory -Path "$logsPath\format-logs"  -Force
        $null = New-Item -ItemType Directory -Path "$installPath\backup"    -Force

        $filesToCopy = @(
            "PRISM.ps1","PRISM-Deploy.ps1","PRISM-Setup.ps1","PRISM-Stop.ps1",
            "PRISM-Remove.ps1","PRISM-Remove.bat","PRISM-Config.ps1","PRISM-Tray.ps1",
            "PRISM-CreateSDrive.ps1","PRISM-Troubleshoot.bat","PRISM-Launch.vbs",
            "prism-logo.ico","prism-logo.png"
        )
        foreach ($f in $filesToCopy) {
            $src = Join-Path $usbPath $f
            if (Test-Path $src) { Copy-Item $src $installPath -Force }
        }
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Add-OK "Files copied to $installPath"
    } catch {
        Add-Err "Folder setup failed: $_"
        Finish-Deploy $false
        return
    }

    # Step 2: create S: drive
    Add-Step "Creating virtual S: drive (${driveSize} GB)"
    $createScript = Join-Path $installPath "PRISM-CreateSDrive.ps1"
    $ec = Run-Script -Path $createScript -ExtraArgs "-SizeGB $driveSize"
    if ($ec -ne 0) {
        Add-Err "S: drive creation failed (exit $ec) -- free up space on C: and retry"
        Finish-Deploy $false
        return
    }
    Add-OK "S: drive created"

    # Step 3: create marker (non-fatal)
    # The marker is used by PRISM-Monitor to identify the managed folder but is
    # not strictly required for the drive or scheduler to function. A failure here
    # is logged and skipped so the rest of the installation can complete. The user
    # can recreate the marker later by running:  PRISM.ps1 -Action CreateMarker
    Add-Step "Creating target.marker on S:"
    $prismScript = Join-Path $installPath "PRISM.ps1"
    $ec = Run-Script -Path $prismScript -ExtraArgs "-Action CreateMarker"
    if ($ec -ne 0) {
        Add-Err "Marker creation failed (exit $ec) -- non-fatal, continuing"
    } else {
        Add-OK "target.marker created"
    }

    # Step 4: scheduler + registry
    Add-Step "Registering scheduled task and writing registry"
    $deployScript = Join-Path $installPath "PRISM-Deploy.ps1"
    $deployArgs   = "-InstallationPath `"$installPath`" -LogsPath `"$logsPath`" -DriveSize $driveSize -CapacityThreshold $threshold -PreserveFolders $preserve -MonitoringInterval $interval"
    $ec = Run-Script -Path $deployScript -ExtraArgs $deployArgs
    if ($ec -ne 0) {
        Add-Err "Scheduler/registry setup failed (exit $ec)"
        $errDetail = try { Get-Content "$logsPath\deploy-error.txt" -Raw -ErrorAction SilentlyContinue } catch { $null }
        if ($errDetail) { Add-Err $errDetail.Trim() }
        try { Remove-Item "$logsPath\deploy-error.txt" -Force -ErrorAction SilentlyContinue } catch {}
        Finish-Deploy $false
        return
    }
    Add-OK "PRISM-Monitor task registered"

    # Step 5: tray icon
    # HKCU:\...\Run always exists on Windows; -Force is present to handle any
    # edge case where the value doesn't yet exist under that key.
    Add-Step "Starting tray icon"
    $trayScript = Join-Path $installPath "PRISM-Tray.ps1"
    $runValue   = "powershell.exe -NonInteractive -NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File `"$trayScript`""
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "PRISM-Tray" -Value $runValue -Force

    # Launch the tray at Medium Integrity Level via CreateProcessWithTokenW.
    #
    # Shell.Application is in-process (InProcServer32) so any child it spawns
    # inherits this process's High IL token.  A NotifyIcon HWND at High IL cannot
    # receive the NIN_SELECT bounce-back Explorer sends on Win11 22H2+, so
    # Shell_NotifyIcon silently fails.
    #
    # Fix: open Explorer's process token (Medium IL), duplicate it as a primary
    # token, then CreateProcessWithTokenW to inherit Explorer's exact token.
    # This is reliable and needs no scheduler involvement.
    if (-not ([System.Management.Automation.PSTypeName]'PRISM_DeElevate').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Diagnostics;
public class PRISM_DeElevate {
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern IntPtr OpenProcess(uint a, bool b, int pid);
    [DllImport("advapi32.dll", SetLastError=true)]
    static extern bool OpenProcessToken(IntPtr h, uint a, out IntPtr t);
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    static extern bool DuplicateTokenEx(IntPtr t, uint a, IntPtr p, int il, int tt, out IntPtr nt);
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    static extern bool CreateProcessWithTokenW(IntPtr tok, int lf, string app, string cmd,
        uint cf, IntPtr env, string dir, ref SI si, out PI pi);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct SI {
        public int cb, _r0; public string lpReserved, lpDesktop, lpTitle;
        public uint dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public ushort wShowWindow, cbReserved2; public IntPtr lpReserved2, hIn, hOut, hErr;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct PI { public IntPtr hProcess, hThread; public uint dwPid, dwTid; }
    const uint PQLI=0x1000, TDUP=2, TASGN=1, TQRY=8, TALL=0xF01FF, CNW=0x08000000;
    public static int Launch(string cmd, string dir) {
        IntPtr hp=IntPtr.Zero, ht=IntPtr.Zero, hd=IntPtr.Zero;
        try {
            var p = Process.GetProcessesByName("explorer");
            if (p.Length == 0) return -1;
            hp = OpenProcess(PQLI, false, p[0].Id);
            if (hp == IntPtr.Zero) return Marshal.GetLastWin32Error();
            if (!OpenProcessToken(hp, TDUP|TASGN|TQRY, out ht)) return Marshal.GetLastWin32Error();
            if (!DuplicateTokenEx(ht, TALL, IntPtr.Zero, 2, 1, out hd)) return Marshal.GetLastWin32Error();
            var si = new SI { cb = System.Runtime.InteropServices.Marshal.SizeOf(typeof(SI)) };
            PI pi;
            if (!CreateProcessWithTokenW(hd, 0, null, cmd, CNW, IntPtr.Zero, dir, ref si, out pi))
                return Marshal.GetLastWin32Error();
            CloseHandle(pi.hProcess); CloseHandle(pi.hThread);
            return 0;
        } finally {
            if (hd != IntPtr.Zero) CloseHandle(hd);
            if (ht != IntPtr.Zero) CloseHandle(ht);
            if (hp != IntPtr.Zero) CloseHandle(hp);
        }
    }
}
"@
    }
    $trayCmd = "powershell.exe -NonInteractive -NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File `"$trayScript`""
    $launchResult = [PRISM_DeElevate]::Launch($trayCmd, $installPath)
    if ($launchResult -eq 0) {
        Add-OK "Tray icon launched and registered for auto-start"
    } else {
        Add-Err "Tray de-elevation failed (Win32 error $launchResult) — icon will appear after next login"
        Add-OK "Tray icon registered for auto-start on next login"
    }

    Add-Log ""
    Add-Sep
    Add-Log "  Installation complete!" $SUCCESS
    Add-Log ""
    Add-Log "  Look for the PRISM icon in your system tray." $TEXT_SEC
    Add-Log "  Right-click it to open the menu." $TEXT_SEC
    Add-Log ""

    Finish-Deploy $true
}

function Finish-Deploy {
    param([bool]$Success)
    if ($Success) {
        $script:lblH2.Text                  = "Installed Successfully"
        $btnClose.Text                      = "Done"
        $btnClose.BackColor                 = $ACCENT
        $btnClose.ForeColor                 = $BG
        $btnClose.FlatAppearance.BorderSize = 0
    } else {
        $script:lblH2.Text      = "Installation Failed"
        $script:lblH2.ForeColor = $DANGER
        $btnClose.Text          = "Close"
    }
    $btnClose.Enabled = $true
}

# ── Events ─────────────────────────────────────────────────────────────────────
$form.Add_Load({
    # Use live header height: after DPI auto-scaling it differs from $HEADER_H
    $lblTitle.Top     = [int](($header.Height - $lblTitle.Height)       / 2)
    $script:lblH2.Top = [int](($header.Height - $script:lblH2.Height)   / 2)

    # NumericUpDown height is font-auto-sized and ignores Scale(); snap each
    # bordered wrapper panel to the real spinner height so no dead strip shows.
    foreach ($nud in @($script:nudSize, $script:nudThresh, $script:nudPreserve, $script:nudInterval)) {
        $wrap = $nud.Parent
        $cy   = $wrap.Top + [int]($wrap.Height / 2)
        $wrap.Height  = $nud.Height + 2
        $wrap.Top     = $cy - [int]($wrap.Height / 2)
        $nud.Location = New-Object System.Drawing.Point(1, 1)
        $nud.Width    = $wrap.Width - 2
    }
})
$btnBegin.Add_Click({  Start-Deploy  })
$btnCancel.Add_Click({ $form.Close() })
$btnClose.Add_Click({  $form.Close() })
$btnOpenRemove.Add_Click({
    $stopScript = "C:\PRISM\PRISM-Stop.ps1"
    if (Test-Path $stopScript) {
        $launchVbs = "C:\PRISM\PRISM-Launch.vbs"
        if (Test-Path $launchVbs) {
            Start-Process wscript.exe -ArgumentList "`"$launchVbs`" runas `"$stopScript`""
        } else {
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File `"$stopScript`"" -Verb RunAs
        }
        $form.Close()
    } else {
        [System.Windows.Forms.MessageBox]::Show("PRISM-Stop.ps1 not found at C:\PRISM\", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

# Scale the finished layout once for the actual display DPI. The process is
# DPI-aware, so fonts already render larger at 125%/150% — without this the
# 96-DPI pixel layout clips them. Control.Scale resizes the whole tree.
if ($script:DPI_SCALE -gt 1.0) {
    $form.Scale((New-Object System.Drawing.SizeF($script:DPI_SCALE, $script:DPI_SCALE)))
}

$null = [DpiHelper]::ShowWindow([DpiHelper]::GetConsoleWindow(), 0)
[System.Windows.Forms.Application]::Run($form)
