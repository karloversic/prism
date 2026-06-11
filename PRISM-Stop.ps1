[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Admin self-elevation
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public class DpiHelper {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
$null = [DpiHelper]::SetProcessDPIAware()

[System.Windows.Forms.Application]::EnableVisualStyles()

# ── Color palette ──────────────────────────────────────────────────────────────
$BG_MAIN      = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
$BG_CARD      = [System.Drawing.ColorTranslator]::FromHtml("#161b22")
$BG_INPUT     = [System.Drawing.ColorTranslator]::FromHtml("#21262d")
$BORDER       = [System.Drawing.ColorTranslator]::FromHtml("#30363d")
$ACCENT       = [System.Drawing.ColorTranslator]::FromHtml("#2ea2cc")
$SUCCESS      = [System.Drawing.ColorTranslator]::FromHtml("#3fb950")
$WARNING      = [System.Drawing.ColorTranslator]::FromHtml("#d29922")
$DANGER       = [System.Drawing.ColorTranslator]::FromHtml("#f85149")
$TEXT_PRI     = [System.Drawing.ColorTranslator]::FromHtml("#e6edf3")
$TEXT_SEC     = [System.Drawing.ColorTranslator]::FromHtml("#8b949e")
$TEXT_DIM     = [System.Drawing.ColorTranslator]::FromHtml("#7d8590")

# ── Font scale ─────────────────────────────────────────────────────────────────
$FONT_TITLE   = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$FONT_HEADER  = New-Object System.Drawing.Font("Segoe UI", 11)
$FONT_BOLD    = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$FONT_NORMAL  = New-Object System.Drawing.Font("Segoe UI", 10)
$FONT_SMALL   = New-Object System.Drawing.Font("Segoe UI", 9)

# All layout coordinates are 96-DPI design units; the whole form is scaled once
# (see $form.Scale call before Application::Run) when the display DPI differs.
$_g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
$script:DPI_SCALE = $_g.DpiX / 96.0
$_g.Dispose()

# ── Layout constants ───────────────────────────────────────────────────────────
# Header h=60, three cards h=140 each, gaps=18, close button h=34, padding
# 60 + 18 + 140 + 18 + 140 + 18 + 140 + 18 + 34 + 16 = 602  → use 602
$CLIENT_W  = 480
$CLIENT_H  = 602
$HEADER_H  = 60
$CARD_X    = 12
$CARD_W    = $CLIENT_W - 24   # 456
$CARD_H    = 140
$GAP       = 18

# ── Main form ──────────────────────────────────────────────────────────────────
$form                 = New-Object System.Windows.Forms.Form
$form.Text            = "PRISM - Stop / Remove"
$form.ClientSize      = New-Object System.Drawing.Size($CLIENT_W, $CLIENT_H)
$form.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox     = $false
$form.MinimizeBox     = $true
$form.BackColor       = $BG_MAIN
$form.ForeColor       = $TEXT_PRI
$form.Font            = $FONT_NORMAL
$_icoPath = Join-Path (Split-Path -Parent $PSCommandPath) "prism-logo.ico"
if (-not (Test-Path $_icoPath)) { $_icoPath = "C:\PRISM\prism-logo.ico" }
if (Test-Path $_icoPath) { try { $form.Icon = New-Object System.Drawing.Icon($_icoPath) } catch {} }

# ── Header (h=60, matches PRISM-Setup design) ──────────────────────────────────
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

$lblSub           = New-Object System.Windows.Forms.Label
$lblSub.Text      = "Stop / Remove"
$lblSub.Font      = $FONT_HEADER
$lblSub.ForeColor = $TEXT_SEC
$lblSub.AutoSize  = $true
$lblSub.Location  = New-Object System.Drawing.Point(106, 0)

$header.Controls.AddRange(@($lblTitle, $lblSub))
$form.Controls.Add($header)

# ── Helper: build an action card ──────────────────────────────────────────────
# Returns a hashtable: @{ Button = <button>; StatusLabel = <label> }
function New-ActionCard {
    param(
        [int]                  $Y,
        [System.Drawing.Color] $AccentColor,
        [string]               $Title,
        [string]               $Description,
        [string]               $StatusText,
        [string]               $ButtonText,
        [System.Drawing.Color] $ButtonBg,
        [System.Drawing.Color] $ButtonFg,
        [bool]                 $ButtonBorder = $false
    )

    # Outer border panel (1px BORDER gives a subtle frame)
    $outer           = New-Object System.Windows.Forms.Panel
    $outer.Location  = New-Object System.Drawing.Point($CARD_X, $Y)
    $outer.Size      = New-Object System.Drawing.Size($CARD_W, $CARD_H)
    $outer.BackColor = $BORDER

    # Inner card
    $card           = New-Object System.Windows.Forms.Panel
    $card.Location  = New-Object System.Drawing.Point(1, 1)
    $card.Size      = New-Object System.Drawing.Size(($CARD_W - 2), ($CARD_H - 2))
    $card.BackColor = $BG_CARD

    # 4px left accent bar
    $accentBar           = New-Object System.Windows.Forms.Panel
    $accentBar.Location  = New-Object System.Drawing.Point(0, 0)
    $accentBar.Size      = New-Object System.Drawing.Size(4, ($CARD_H - 2))
    $accentBar.BackColor = $AccentColor
    $card.Controls.Add($accentBar)

    # Title (10pt bold, TEXT_PRI)
    $lblCardTitle           = New-Object System.Windows.Forms.Label
    $lblCardTitle.Text      = $Title
    $lblCardTitle.Font      = $FONT_BOLD
    $lblCardTitle.ForeColor = $TEXT_PRI
    $lblCardTitle.Location  = New-Object System.Drawing.Point(16, 11)
    $lblCardTitle.Size      = New-Object System.Drawing.Size(300, 20)
    $card.Controls.Add($lblCardTitle)

    # Status label (9pt, TEXT_SEC — e.g. "Monitoring: Active")
    $lblStatus           = New-Object System.Windows.Forms.Label
    $lblStatus.Text      = $StatusText
    $lblStatus.Font      = $FONT_SMALL
    $lblStatus.ForeColor = $TEXT_SEC
    $lblStatus.Location  = New-Object System.Drawing.Point(16, 33)
    $lblStatus.Size      = New-Object System.Drawing.Size(200, 18)
    $card.Controls.Add($lblStatus)

    # Description (9pt, TEXT_SEC, wraps — explicit Size, no AutoSize)
    $lblDesc           = New-Object System.Windows.Forms.Label
    $lblDesc.Text      = $Description
    $lblDesc.Font      = $FONT_SMALL
    $lblDesc.ForeColor = $TEXT_SEC
    $lblDesc.Location  = New-Object System.Drawing.Point(16, 52)
    $lblDesc.Size      = New-Object System.Drawing.Size(300, 74)
    $lblDesc.AutoSize  = $false
    $card.Controls.Add($lblDesc)

    # Action button (right-aligned, vertically centred)
    $btn                              = New-Object System.Windows.Forms.Button
    $btn.Text                         = $ButtonText
    $btn.Font                         = $FONT_SMALL
    $btn.Location                     = New-Object System.Drawing.Point(330, 34)
    $btn.Size                         = New-Object System.Drawing.Size(116, 46)
    $btn.FlatStyle                    = [System.Windows.Forms.FlatStyle]::Flat
    $btn.BackColor                    = $ButtonBg
    $btn.ForeColor                    = $ButtonFg
    $btn.Cursor                       = [System.Windows.Forms.Cursors]::Hand
    $btn.FlatAppearance.BorderSize    = 0
    if ($ButtonBorder) {
        $btn.FlatAppearance.BorderSize  = 1
        $btn.FlatAppearance.BorderColor = $BORDER
    }
    $card.Controls.Add($btn)

    $outer.Controls.Add($card)
    $form.Controls.Add($outer)

    return @{ Button = $btn; StatusLabel = $lblStatus }
}

# ── Card 1: Pause Monitoring (ACCENT accent bar, secondary button) ─────────────
$card1Y   = $HEADER_H + $GAP   # 78
$pause    = New-ActionCard `
    -Y           $card1Y `
    -AccentColor $ACCENT `
    -Title       "Pause Monitoring" `
    -Description "Temporarily disables the PRISM-Monitor scheduled task. S: drive and all files are preserved." `
    -StatusText  "Checking task status..." `
    -ButtonText  "Pause Monitoring" `
    -ButtonBg    $BG_CARD `
    -ButtonFg    ([System.Drawing.Color]::White) `
    -ButtonBorder $true

$btnPause      = $pause.Button
$lblPauseState = $pause.StatusLabel

# ── Card 2: Uninstall (WARNING accent bar, amber button) ──────────────────────
$card2Y     = $card1Y + $CARD_H + $GAP   # 236
$uninstall  = New-ActionCard `
    -Y           $card2Y `
    -AccentColor $WARNING `
    -Title       "Uninstall PRISM" `
    -Description "Removes tasks, registry, and tray icon. C:\PRISM folder and S: drive are kept intact." `
    -StatusText  "" `
    -ButtonText  "Uninstall PRISM" `
    -ButtonBg    $WARNING `
    -ButtonFg    ([System.Drawing.Color]::White) `
    -ButtonBorder $false

$btnUninstall = $uninstall.Button

# ── Card 3: Complete Removal (DANGER accent bar, red button) ──────────────────
$card3Y  = $card2Y + $CARD_H + $GAP   # 394
$removal = New-ActionCard `
    -Y           $card3Y `
    -AccentColor $DANGER `
    -Title       "Complete Removal" `
    -Description "Removes everything: tasks, registry, scripts, and the S: drive VHD. ALL DATA WILL BE LOST." `
    -StatusText  "" `
    -ButtonText  "Remove Everything" `
    -ButtonBg    $DANGER `
    -ButtonFg    ([System.Drawing.Color]::White) `
    -ButtonBorder $false

$btnRemove = $removal.Button

# ── Close button (secondary style, bottom-right) ──────────────────────────────
$btnCloseY = $card3Y + $CARD_H + $GAP   # 552
$btnClose                              = New-Object System.Windows.Forms.Button
$btnClose.Text                         = "Close"
$btnClose.Font                         = $FONT_NORMAL
$btnClose.Location                     = New-Object System.Drawing.Point(352, $btnCloseY)
$btnClose.Size                         = New-Object System.Drawing.Size(116, 34)
$btnClose.FlatStyle                    = [System.Windows.Forms.FlatStyle]::Flat
$btnClose.BackColor                    = $BG_CARD
$btnClose.ForeColor                    = $TEXT_SEC
$btnClose.Cursor                       = [System.Windows.Forms.Cursors]::Hand
$btnClose.FlatAppearance.BorderSize    = 1
$btnClose.FlatAppearance.BorderColor   = $BORDER
$form.Controls.Add($btnClose)

# ── Determine current task state on load ──────────────────────────────────────
$script:monitorEnabled = $true   # assume enabled; updated on Shown

function Refresh-PauseButton {
    # Get-ScheduledTask instead of parsing schtasks text output: the latter is
    # localized ("Status:" only exists on English Windows) and silently reported
    # every task as Active on non-English systems.
    $task = Get-ScheduledTask -TaskName "PRISM-Monitor" -ErrorAction SilentlyContinue
    if (-not $task) {
        $script:monitorEnabled = $false
        $lblPauseState.Text      = "Monitoring: Not installed"
        $lblPauseState.ForeColor = $TEXT_DIM
        $btnPause.Text           = "Pause Monitoring"
        $btnPause.Enabled        = $false
        $btnPause.BackColor      = $BG_CARD
        $btnPause.ForeColor      = $TEXT_DIM
        $btnPause.FlatAppearance.BorderSize  = 1
        $btnPause.FlatAppearance.BorderColor = $BORDER
    } elseif ($task.State -eq 'Disabled') {
        $script:monitorEnabled = $false
        $lblPauseState.Text      = "Monitoring: Disabled"
        $lblPauseState.ForeColor = $WARNING
        $btnPause.Text           = "Resume Monitoring"
        $btnPause.Enabled        = $true
        $btnPause.BackColor      = $ACCENT
        $btnPause.ForeColor      = [System.Drawing.Color]::White
        $btnPause.FlatAppearance.BorderSize = 0
    } else {
        $script:monitorEnabled = $true
        $lblPauseState.Text      = "Monitoring: Active"
        $lblPauseState.ForeColor = $SUCCESS
        $btnPause.Text           = "Pause Monitoring"
        $btnPause.Enabled        = $true
        $btnPause.BackColor      = $BG_CARD
        $btnPause.ForeColor      = [System.Drawing.Color]::White
        $btnPause.FlatAppearance.BorderSize  = 1
        $btnPause.FlatAppearance.BorderColor = $BORDER
    }
}

# ── Button handlers ────────────────────────────────────────────────────────────

$btnPause.Add_Click({
    try {
        if ($script:monitorEnabled) {
            Disable-ScheduledTask -TaskName "PRISM-Monitor" -ErrorAction Stop | Out-Null
            [System.Windows.Forms.MessageBox]::Show(
                "Monitoring paused.`nS: drive and all files are preserved.",
                "PRISM - Paused",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information)
        } else {
            Enable-ScheduledTask -TaskName "PRISM-Monitor" -ErrorAction Stop | Out-Null
            [System.Windows.Forms.MessageBox]::Show(
                "Monitoring resumed.",
                "PRISM - Resumed",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information)
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Could not change the PRISM-Monitor task: $_",
            "PRISM - Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
    }
    Refresh-PauseButton
})

$btnUninstall.Add_Click({
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Uninstall PRISM?`n`nS: drive and all data will be kept.",
        "Confirm Uninstall",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    schtasks /delete /tn "PRISM-Monitor" /f | Out-Null
    schtasks /delete /tn "PRISM-Config"  /f | Out-Null
    Remove-Item -Path "HKLM:\SOFTWARE\PRISM" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" `
        -Name "PRISM-Tray" -ErrorAction SilentlyContinue
    Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.CommandLine -like '*PRISM-Tray*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    [System.Windows.Forms.MessageBox]::Show(
        "PRISM uninstalled.`nS: drive preserved.",
        "PRISM - Uninstalled",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information)
    $form.Close()
})

$btnRemove.Add_Click({
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Remove EVERYTHING?`n`nThis will permanently delete:`n  - Scheduled tasks`n  - Registry entries`n  - C:\PRISM folder and all scripts`n  - The S: virtual drive and ALL its data`n`nThis cannot be undone.",
        "Confirm Complete Removal",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $removePath = "C:\PRISM\PRISM-Remove.ps1"
    if (-not (Test-Path $removePath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "PRISM-Remove.ps1 not found at C:\PRISM\",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }
    Start-Process powershell.exe `
        -ArgumentList "-NoProfile -ExecutionPolicy RemoteSigned -File `"$removePath`"" `
        -Verb RunAs
    $form.Close()
})

$btnClose.Add_Click({ $form.Close() })

$form.Add_Load({
    # Use live header height: after DPI auto-scaling it differs from $HEADER_H
    $lblTitle.Top = [int](($header.Height - $lblTitle.Height) / 2)
    $lblSub.Top   = [int](($header.Height - $lblSub.Height)   / 2)
})

# Populate pause state once the form is visible
$form.Add_Shown({ Refresh-PauseButton })

# Scale the finished layout once for the actual display DPI. The process is
# DPI-aware, so fonts already render larger at 125%/150% — without this the
# 96-DPI pixel layout clips them. Control.Scale resizes the whole tree.
if ($script:DPI_SCALE -gt 1.0) {
    $form.Scale((New-Object System.Drawing.SizeF($script:DPI_SCALE, $script:DPI_SCALE)))
}

[System.Windows.Forms.Application]::Run($form)
