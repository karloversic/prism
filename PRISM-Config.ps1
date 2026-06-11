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

# Color palette
$BG_MAIN     = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
$BG_CARD     = [System.Drawing.ColorTranslator]::FromHtml("#161b22")
$BG_INPUT    = [System.Drawing.ColorTranslator]::FromHtml("#21262d")
$BORDER      = [System.Drawing.ColorTranslator]::FromHtml("#30363d")
$ACCENT      = [System.Drawing.ColorTranslator]::FromHtml("#2ea2cc")
$TEXT_PRI    = [System.Drawing.ColorTranslator]::FromHtml("#e6edf3")
$TEXT_SEC    = [System.Drawing.ColorTranslator]::FromHtml("#8b949e")
$TEXT_DIM    = [System.Drawing.ColorTranslator]::FromHtml("#484f58")
$SUCCESS     = [System.Drawing.ColorTranslator]::FromHtml("#3fb950")
$WARNING     = [System.Drawing.ColorTranslator]::FromHtml("#d29922")
$DANGER      = [System.Drawing.ColorTranslator]::FromHtml("#f85149")

# Shared fonts (matches installer style)
$FONT_TITLE  = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$FONT_HEADER = New-Object System.Drawing.Font("Segoe UI", 11)
$FONT_BOLD   = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$FONT_NORMAL = New-Object System.Drawing.Font("Segoe UI", 10)
$FONT_SMALL  = New-Object System.Drawing.Font("Segoe UI", 9)

# All layout coordinates are 96-DPI design units; the whole form is scaled once
# (see $form.Scale call before Application::Run) when the display DPI differs.
$script:HINT_H = [Math]::Ceiling($FONT_SMALL.GetHeight(96)) + 2

$_g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
$script:DPI_SCALE = $_g.DpiX / 96.0
$_g.Dispose()

# Registry load
$_regPath             = "HKLM:\SOFTWARE\PRISM"
$_regThreshold        = 95
$_regPreserve         = 5
$_regInterval         = 8
$script:_regDriveSize = 50
$script:_regMissing   = $false

if (Test-Path $_regPath) {
    $v = Get-ItemProperty -Path $_regPath -ErrorAction SilentlyContinue
    if ($null -ne $v.CapacityThreshold)  { $_regThreshold           = [int]$v.CapacityThreshold  }
    if ($null -ne $v.PreserveFolders)    { $_regPreserve            = [int]$v.PreserveFolders    }
    if ($null -ne $v.MonitoringInterval) { $_regInterval            = [int]$v.MonitoringInterval }
    if ($null -ne $v.DriveSize)          { $script:_regDriveSize    = [int]$v.DriveSize          }
} else {
    $script:_regMissing = $true
}

# Helper: get S: drive info
function Get-SDriveInfo {
    try {
        $d = Get-PSDrive -Name S -ErrorAction Stop
        $usedBytes  = $d.Used
        $freeBytes  = $d.Free
        $totalBytes = $usedBytes + $freeBytes
        if ($totalBytes -eq 0) { throw "zero total" }
        $usedGB  = [math]::Round($usedBytes  / 1GB, 1)
        $freeGB  = [math]::Round($freeBytes  / 1GB, 1)
        $pct     = [math]::Round($usedBytes * 100 / $totalBytes, 0)
        return [PSCustomObject]@{
            Online    = $true
            UsedGB    = $usedGB
            FreeGB    = $freeGB
            TotalGB   = [math]::Round($totalBytes / 1GB, 1)
            UsedBytes = $usedBytes
            Pct       = $pct
        }
    } catch {
        return [PSCustomObject]@{ Online = $false; UsedGB = 0; FreeGB = 0; TotalGB = 0; UsedBytes = 0; Pct = 0 }
    }
}

# Helper: get free space on C: in GB
function Get-CFreGB {
    try {
        $d = Get-PSDrive -Name C -ErrorAction Stop
        return [math]::Round($d.Free / 1GB, 1)
    } catch {
        return -1
    }
}

# Form — taller to accommodate hint rows under each setting
$form = New-Object System.Windows.Forms.Form
$form.Text            = "PRISM - Configuration"
$form.ClientSize      = New-Object System.Drawing.Size(540, 670)
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

# === 1. Header bar (h=60, matches PRISM-Setup design) ===
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Location  = New-Object System.Drawing.Point(0, 0)
$headerPanel.Size      = New-Object System.Drawing.Size(540, 60)
$headerPanel.BackColor = $BG_CARD
$form.Controls.Add($headerPanel)

$lblPrism = New-Object System.Windows.Forms.Label
$lblPrism.Text      = "PRISM"
$lblPrism.AutoSize  = $true
$lblPrism.ForeColor = $ACCENT
$lblPrism.Font      = $FONT_TITLE
$lblPrism.Location  = New-Object System.Drawing.Point(24, 0)
$headerPanel.Controls.Add($lblPrism)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text      = "Configuration"
$lblSub.AutoSize  = $true
$lblSub.ForeColor = $TEXT_SEC
$lblSub.Font      = $FONT_HEADER
$lblSub.Location  = New-Object System.Drawing.Point(106, 0)
$headerPanel.Controls.Add($lblSub)

# === 1b. Registry-missing warning banner (hidden by default) ===
$warnBanner = New-Object System.Windows.Forms.Panel
$warnBanner.Location  = New-Object System.Drawing.Point(12, 66)
$warnBanner.Size      = New-Object System.Drawing.Size(516, 42)
$warnBanner.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#3d2b00")
$warnBanner.Visible   = $false
$form.Controls.Add($warnBanner)

$lblWarnIcon = New-Object System.Windows.Forms.Label
$lblWarnIcon.Text      = "!"
$lblWarnIcon.Location  = New-Object System.Drawing.Point(12, 10)
$lblWarnIcon.Size      = New-Object System.Drawing.Size(16, 20)
$lblWarnIcon.ForeColor = $WARNING
$lblWarnIcon.Font      = $FONT_BOLD
$warnBanner.Controls.Add($lblWarnIcon)

$lblWarnText = New-Object System.Windows.Forms.Label
$lblWarnText.Text      = "PRISM registry not found - is PRISM installed? Settings cannot be saved."
$lblWarnText.Location  = New-Object System.Drawing.Point(32, 12)
$lblWarnText.Size      = New-Object System.Drawing.Size(478, $script:HINT_H)
$lblWarnText.ForeColor = $WARNING
$lblWarnText.Font      = $FONT_SMALL
$warnBanner.Controls.Add($lblWarnText)

# === 2. Drive Status card ===
# Y position shifts down 50 if banner is visible; we set it after banner decision
$statusY = 62   # default; bumped to 108 if banner shown

$statusOuter = New-Object System.Windows.Forms.Panel
$statusOuter.Location  = New-Object System.Drawing.Point(12, $statusY)
$statusOuter.Size      = New-Object System.Drawing.Size(516, 112)
$statusOuter.BackColor = $BORDER
$form.Controls.Add($statusOuter)

$statusCard = New-Object System.Windows.Forms.Panel
$statusCard.Location  = New-Object System.Drawing.Point(1, 1)
$statusCard.Size      = New-Object System.Drawing.Size(514, 110)
$statusCard.BackColor = $BG_CARD
$statusOuter.Controls.Add($statusCard)

$lblStatusTitle = New-Object System.Windows.Forms.Label
$lblStatusTitle.Text      = "DRIVE STATUS"
$lblStatusTitle.Location  = New-Object System.Drawing.Point(12, 10)
$lblStatusTitle.Size      = New-Object System.Drawing.Size(200, 20)
$lblStatusTitle.ForeColor = $TEXT_SEC
$lblStatusTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$statusCard.Controls.Add($lblStatusTitle)

$lblDriveLetter = New-Object System.Windows.Forms.Label
$lblDriveLetter.Text      = "S:"
$lblDriveLetter.Location  = New-Object System.Drawing.Point(12, 32)
$lblDriveLetter.Size      = New-Object System.Drawing.Size(36, 30)
$lblDriveLetter.ForeColor = $ACCENT
$lblDriveLetter.Font      = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$statusCard.Controls.Add($lblDriveLetter)

$lblDriveStatus = New-Object System.Windows.Forms.Label
$lblDriveStatus.Text      = "Checking..."
$lblDriveStatus.Location  = New-Object System.Drawing.Point(52, 40)
$lblDriveStatus.Size      = New-Object System.Drawing.Size(80, 18)
$lblDriveStatus.ForeColor = $TEXT_SEC
$lblDriveStatus.Font      = $FONT_SMALL
$statusCard.Controls.Add($lblDriveStatus)

$lblUsage = New-Object System.Windows.Forms.Label
$lblUsage.Text      = ""
$lblUsage.Location  = New-Object System.Drawing.Point(200, 34)
$lblUsage.Size      = New-Object System.Drawing.Size(300, 20)
$lblUsage.ForeColor = $TEXT_PRI
$lblUsage.Font      = $FONT_SMALL
$lblUsage.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$statusCard.Controls.Add($lblUsage)

$pbContainer = New-Object System.Windows.Forms.Panel
$pbContainer.Location  = New-Object System.Drawing.Point(12, 68)
$pbContainer.Size      = New-Object System.Drawing.Size(490, 10)
$pbContainer.BackColor = $BG_INPUT
$statusCard.Controls.Add($pbContainer)

$pbFill = New-Object System.Windows.Forms.Panel
$pbFill.Location  = New-Object System.Drawing.Point(0, 0)
$pbFill.Size      = New-Object System.Drawing.Size(0, 10)
$pbFill.BackColor = $SUCCESS
$pbContainer.Controls.Add($pbFill)

$lblDriveOfflineHint = New-Object System.Windows.Forms.Label
$lblDriveOfflineHint.Text      = "S: drive is not mounted. Resize and save operations are disabled."
$lblDriveOfflineHint.Location  = New-Object System.Drawing.Point(12, 84)
$lblDriveOfflineHint.Size      = New-Object System.Drawing.Size(490, 18)
$lblDriveOfflineHint.ForeColor = $DANGER
$lblDriveOfflineHint.Font      = $FONT_SMALL
$lblDriveOfflineHint.Visible   = $false
$statusCard.Controls.Add($lblDriveOfflineHint)

function Update-StatusCard {
    $info = Get-SDriveInfo
    if ($info.Online) {
        $lblDriveStatus.Text             = "Online"
        $lblDriveStatus.ForeColor        = $SUCCESS
        $lblUsage.Text                   = "$($info.UsedGB) GB used  /  $($info.FreeGB) GB free  ($($info.Pct)%)"
        $lblDriveOfflineHint.Visible     = $false
        # Use the live container width: after DPI auto-scaling it is not 490px
        $barW  = $pbContainer.ClientSize.Width
        $fillW = [int]([math]::Round($barW * $info.Pct / 100))
        if ($fillW -lt 0)     { $fillW = 0 }
        if ($fillW -gt $barW) { $fillW = $barW }
        $pbFill.Width = $fillW
        if ($info.Pct -ge 90) {
            $pbFill.BackColor = $DANGER
        } elseif ($info.Pct -ge 70) {
            $pbFill.BackColor = $WARNING
        } else {
            $pbFill.BackColor = $SUCCESS
        }
    } else {
        $lblDriveStatus.Text             = "Offline"
        $lblDriveStatus.ForeColor        = $DANGER
        $lblUsage.Text                   = ""
        $pbFill.Width                    = 0
        $lblDriveOfflineHint.Visible     = $true
    }
}

# === 3. Settings section ===
# Each row: label (22px) + hint (18px) + gap (16px) = 56px per row
# Top of section: 186 (or 186+50 if banner shown — adjusted at Shown time)
$settingsY = 186

$lblSettingsTitle = New-Object System.Windows.Forms.Label
$lblSettingsTitle.Text      = "SETTINGS"
$lblSettingsTitle.Location  = New-Object System.Drawing.Point(16, ($settingsY + 4))
$lblSettingsTitle.Size      = New-Object System.Drawing.Size(200, 20)
$lblSettingsTitle.ForeColor = $TEXT_SEC
$lblSettingsTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblSettingsTitle)

# New-SettingsRow: label + hint line + bordered spinner — mirrors installer's New-Row
function New-SettingsRow {
    param(
        [string]$LabelText,
        [string]$HintText,
        [int]   $Y,
        [int]   $Min,
        [int]   $Max,
        [int]   $DefaultVal
    )

    # Main label
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text      = $LabelText
    $lbl.Location  = New-Object System.Drawing.Point(28, $Y)
    $lbl.Size      = New-Object System.Drawing.Size(280, 22)
    $lbl.ForeColor = $TEXT_PRI
    $lbl.Font      = $FONT_NORMAL
    $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $form.Controls.Add($lbl)

    # Hint / description (dim, one line)
    $hint = New-Object System.Windows.Forms.Label
    $hint.Text      = $HintText
    $hint.Location  = New-Object System.Drawing.Point(28, ($Y + 22))
    $hint.Size      = New-Object System.Drawing.Size(280, $script:HINT_H)
    $hint.ForeColor = $TEXT_SEC
    $hint.Font      = $FONT_SMALL
    $form.Controls.Add($hint)

    # Bordered wrapper (matches installer style)
    $wrap = New-Object System.Windows.Forms.Panel
    $wrap.Location  = New-Object System.Drawing.Point(320, ($Y + 2))
    $wrap.Size      = New-Object System.Drawing.Size(140, 34)
    $wrap.BackColor = $BORDER
    $form.Controls.Add($wrap)

    $nud = New-Object System.Windows.Forms.NumericUpDown
    $nud.Location    = New-Object System.Drawing.Point(1, 1)
    $nud.Size        = New-Object System.Drawing.Size(138, 32)
    $nud.Minimum     = $Min
    $nud.Maximum     = $Max
    $nud.Value       = [math]::Max($Min, [math]::Min($Max, $DefaultVal))
    $nud.BackColor   = $BG_INPUT
    $nud.ForeColor   = $TEXT_PRI
    $nud.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $nud.Font        = New-Object System.Drawing.Font("Segoe UI", 11)
    $nud.TextAlign   = [System.Windows.Forms.HorizontalAlignment]::Center
    $wrap.Controls.Add($nud)

    return $nud
}

# Row Y positions: header at settingsY+4, first row at settingsY+26, 56px per row
$row1Y = $settingsY + 26
$capUpDown      = New-SettingsRow -LabelText "Capacity threshold (%)" -HintText "Delete oldest folders when S: exceeds this %" -Y $row1Y          -Min 80 -Max 99   -DefaultVal $_regThreshold
$preserveUpDown = New-SettingsRow -LabelText "Folders to preserve"    -HintText "Minimum folders kept during recycle pass"    -Y ($row1Y + 56)   -Min 1  -Max 20   -DefaultVal $_regPreserve
$intervalUpDown = New-SettingsRow -LabelText "Monitor interval (min)" -HintText "How often PRISM checks drive capacity"       -Y ($row1Y + 112)  -Min 1  -Max 60   -DefaultVal $_regInterval

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text      = "Changes apply on the next monitor cycle after saving."
$lblHint.Location  = New-Object System.Drawing.Point(28, ($row1Y + 168))
$lblHint.Size      = New-Object System.Drawing.Size(490, $script:HINT_H)
$lblHint.ForeColor = $TEXT_DIM
$lblHint.Font      = $FONT_SMALL
$form.Controls.Add($lblHint)

# === 4. Drive Resize section ===
# Sits below settings hint, separated by a line
# Settings block bottom: row1Y + 168 + 16 = row1Y + 184
# Separator at: row1Y + 192
$resizeSepY = $row1Y + 192

$sepLine = New-Object System.Windows.Forms.Panel
$sepLine.Location  = New-Object System.Drawing.Point(12, $resizeSepY)
$sepLine.Size      = New-Object System.Drawing.Size(516, 1)
$sepLine.BackColor = $BORDER
$form.Controls.Add($sepLine)

$lblResizeSectionTitle = New-Object System.Windows.Forms.Label
$lblResizeSectionTitle.Text      = "DRIVE RESIZE"
$lblResizeSectionTitle.Location  = New-Object System.Drawing.Point(16, ($resizeSepY + 8))
$lblResizeSectionTitle.Size      = New-Object System.Drawing.Size(300, 20)
$lblResizeSectionTitle.ForeColor = $TEXT_SEC
$lblResizeSectionTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblResizeSectionTitle)

# Drive size spinner lives in the resize section (not mixed in with monitor settings)
$driveSizeUpDown = New-SettingsRow -LabelText "Drive size (GB)" -HintText "Current VHD size - change then click Resize Drive" -Y ($resizeSepY + 28) -Min 5 -Max 2000 -DefaultVal $script:_regDriveSize

# Resize status description and button (revealed when size changes)
$lblResizeDesc = New-Object System.Windows.Forms.Label
$lblResizeDesc.Text      = ""
$lblResizeDesc.Location  = New-Object System.Drawing.Point(16, ($resizeSepY + 90))
$lblResizeDesc.Size      = New-Object System.Drawing.Size(380, 36)
$lblResizeDesc.ForeColor = $TEXT_SEC
$lblResizeDesc.Font      = $FONT_SMALL
$lblResizeDesc.Visible   = $false
$form.Controls.Add($lblResizeDesc)

$btnApplyResize = New-Object System.Windows.Forms.Button
$btnApplyResize.Text      = "Resize Drive"
$btnApplyResize.Location  = New-Object System.Drawing.Point(400, ($resizeSepY + 90))
$btnApplyResize.Size      = New-Object System.Drawing.Size(128, 36)
$btnApplyResize.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnApplyResize.BackColor = $TEXT_DIM
$btnApplyResize.ForeColor = $TEXT_PRI
$btnApplyResize.Enabled   = $false
$btnApplyResize.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnApplyResize.FlatAppearance.BorderSize = 0
$btnApplyResize.Visible   = $false
$form.Controls.Add($btnApplyResize)

function Update-ResizeSection {
    $newSize = [int]$driveSizeUpDown.Value
    $curSize = $script:_regDriveSize
    $info    = Get-SDriveInfo

    if ($newSize -eq $curSize) {
        $lblResizeDesc.Visible  = $false
        $btnApplyResize.Visible = $false
        return
    }

    $lblResizeDesc.Visible  = $true
    $btnApplyResize.Visible = $true

    if ($newSize -gt $curSize) {
        # Growing
        $needed    = $newSize - $curSize
        $cFreeGB   = Get-CFreGB
        $btnApplyResize.Text = "Expand Drive"

        if ($cFreeGB -ge 0 -and $cFreeGB -lt $needed) {
            # Not enough room on C:
            $lblResizeDesc.Text      = "Not enough space on C: - need $needed GB free, but only $cFreeGB GB available."
            $lblResizeDesc.ForeColor = $DANGER
            $btnApplyResize.BackColor = $TEXT_DIM
            $btnApplyResize.ForeColor = $TEXT_SEC
            $btnApplyResize.Enabled  = $false
        } else {
            $freeNote = if ($cFreeGB -ge 0) { " (C: has $cFreeGB GB free)" } else { "" }
            $lblResizeDesc.Text      = "S: will grow from $curSize GB to $newSize GB. No data will be lost.$freeNote"
            $lblResizeDesc.ForeColor = $TEXT_SEC
            $btnApplyResize.BackColor = $ACCENT
            $btnApplyResize.ForeColor = [System.Drawing.Color]::White
            $btnApplyResize.Enabled  = $true
        }

    } else {
        # Shrinking
        $btnApplyResize.Text = "Shrink Drive"
        $newSizeBytes = [long]$newSize * 1GB

        if ($info.Online -and $info.UsedBytes -gt $newSizeBytes) {
            $usedGB = [math]::Round($info.UsedBytes / 1GB, 2)
            $lblResizeDesc.Text       = "Cannot shrink: S: contains $usedGB GB of data (new size is $newSize GB). Free space on S: first."
            $lblResizeDesc.ForeColor  = $DANGER
            $btnApplyResize.BackColor = $TEXT_DIM
            $btnApplyResize.ForeColor = $TEXT_SEC
            $btnApplyResize.Enabled   = $false
        } else {
            $dataNote = if ($info.Online) { "$($info.UsedGB) GB of data will be" } else { "All data on S: will be" }
            $lblResizeDesc.Text       = "WARNING: $dataNote permanently deleted. S: is recreated at $newSize GB."
            $lblResizeDesc.ForeColor  = $WARNING
            $btnApplyResize.BackColor = $WARNING
            $btnApplyResize.ForeColor = [System.Drawing.Color]::Black
            $btnApplyResize.Enabled   = $true
        }
    }
}

$driveSizeUpDown.Add_ValueChanged({ Update-ResizeSection })

$btnApplyResize.Add_Click({
    $newSize = [int]$driveSizeUpDown.Value
    $curSize = $script:_regDriveSize
    $vhdPath = "C:\PRISM\PRISM.vhd"

    if ($newSize -gt $curSize) {
        # GROW — confirm with free-space context
        $needed  = $newSize - $curSize
        $cFreeGB = Get-CFreGB
        $spaceMsg = if ($cFreeGB -ge 0) { "`nC: drive has $cFreeGB GB free (need $needed GB)." } else { "" }

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Expand S: drive from $curSize GB to $newSize GB?$spaceMsg`n`nNo data on S: will be lost.",
            "Confirm Expand",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $btnApplyResize.Enabled = $false
        $btnApplyResize.Text    = "Expanding..."

        $newSizeMB  = $newSize * 1024
        $scriptPath = Join-Path $env:TEMP "prism_expand_$(Get-Random).txt"
        # expand vdisk requires the VHD to be detached first; re-attach and extend partition after
        $dpScript   = "select vdisk file=$vhdPath`r`ndetach vdisk noerr`r`nexpand vdisk maximum=$newSizeMB`r`nattach vdisk noerr`r`nselect partition 1`r`nassign letter=S noerr`r`nextend`r`nexit"
        $dpScript | Out-File -FilePath $scriptPath -Encoding ASCII -Force
        try {
            $dpOut = & diskpart /s $scriptPath 2>&1
            Start-Sleep -Seconds 5
            $failed = $dpOut | Where-Object { $_ -match "error" -and $_ -notmatch "noerr" }
            if ($failed) { throw ($failed -join "`n") }
            Set-ItemProperty -Path $_regPath -Name "DriveSize" -Value $newSize -Force -ErrorAction SilentlyContinue
            $script:_regDriveSize = $newSize
            Update-StatusCard
            Update-ResizeSection
            [System.Windows.Forms.MessageBox]::Show(
                "S: drive expanded to $newSize GB successfully.",
                "Expand Complete",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Expand failed: $_`n`nEnsure the VHD is at $vhdPath.",
                "Expand Failed",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error)
        } finally {
            if (Test-Path $scriptPath) { Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue }
            $btnApplyResize.Text    = "Expand Drive"
            $btnApplyResize.Enabled = $true
        }

    } else {
        # SHRINK — double-confirmation with data count
        $info         = Get-SDriveInfo
        $newSizeBytes = [long]$newSize * 1GB

        if ($info.Online -and $info.UsedBytes -gt $newSizeBytes) {
            $usedGB = [math]::Round($info.UsedBytes / 1GB, 2)
            [System.Windows.Forms.MessageBox]::Show(
                "Cannot shrink: S: contains $usedGB GB of data but the new size is only $newSize GB.`n`nDelete files from S: until usage is below $newSize GB, then try again.",
                "Cannot Shrink - Drive Not Empty",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        $dataLine = if ($info.Online) { "$($info.UsedGB) GB" } else { "all data" }
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "SHRINK S: from $curSize GB to $newSize GB.`n`nThis will permanently delete $dataLine on S: - the drive is recreated from scratch.`n`nThis cannot be undone. Continue?",
            "Confirm Shrink - Data Will Be Deleted",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        # Second confirmation for extra safety
        $confirm2 = [System.Windows.Forms.MessageBox]::Show(
            "Last chance: all data on S: will be permanently destroyed.`n`nAre you sure?",
            "Final Confirmation",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Stop)
        if ($confirm2 -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $btnApplyResize.Enabled = $false
        $btnApplyResize.Text    = "Shrinking..."

        $detachPath = Join-Path $env:TEMP "prism_detach_$(Get-Random).txt"
        $dpDetach   = "select vdisk file=$vhdPath`r`ndetach vdisk noerr`r`nexit"
        $dpDetach | Out-File -FilePath $detachPath -Encoding ASCII -Force
        try {
            & diskpart /s $detachPath 2>&1 | Out-Null
            Start-Sleep -Seconds 2

            if (Test-Path $vhdPath) {
                Remove-Item $vhdPath -Force -ErrorAction Stop
            }

            $createScript = "C:\PRISM\PRISM-CreateSDrive.ps1"
            if (-not (Test-Path $createScript)) { throw "PRISM-CreateSDrive.ps1 not found at C:\PRISM\" }
            $procCreate = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File `"$createScript`" -SizeGB $newSize" -Wait -PassThru -WindowStyle Hidden
            if ($procCreate.ExitCode -ne 0) { throw "Drive creation failed (exit $($procCreate.ExitCode))" }

            $markerScript = "C:\PRISM\PRISM.ps1"
            if (Test-Path $markerScript) {
                Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File `"$markerScript`" -Action CreateMarker" -Wait -WindowStyle Hidden
            }

            Set-ItemProperty -Path $_regPath -Name "DriveSize" -Value $newSize -Force -ErrorAction SilentlyContinue
            $script:_regDriveSize = $newSize
            Update-StatusCard
            Update-ResizeSection

            [System.Windows.Forms.MessageBox]::Show(
                "S: drive recreated at $newSize GB.`nThe drive is empty and ready to use.",
                "Shrink Complete",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Shrink failed: $_`n`nThe VHD may need to be recreated manually at C:\PRISM\PRISM.vhd.",
                "Shrink Failed",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error)
        } finally {
            if (Test-Path $detachPath) { Remove-Item $detachPath -Force -ErrorAction SilentlyContinue }
            $btnApplyResize.Text    = "Shrink Drive"
            $btnApplyResize.Enabled = $true
        }
    }
})

# === 5. Bottom button row ===
# Bottom of resize area: resizeSepY + 90 + 36 = resizeSepY + 126
# Button row: resizeSepY + 136
$btnRowY = $resizeSepY + 136

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text      = "Save Settings"
$btnSave.Location  = New-Object System.Drawing.Point(256, $btnRowY)
$btnSave.Size      = New-Object System.Drawing.Size(160, 36)
$btnSave.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSave.BackColor = $ACCENT
$btnSave.ForeColor = [System.Drawing.Color]::White
$btnSave.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnSave.FlatAppearance.BorderSize = 0
$form.Controls.Add($btnSave)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text      = "Close"
$btnClose.Location  = New-Object System.Drawing.Point(428, $btnRowY)
$btnClose.Size      = New-Object System.Drawing.Size(100, 36)
$btnClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClose.BackColor = $BG_INPUT
$btnClose.ForeColor = $TEXT_SEC
$btnClose.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnClose.FlatAppearance.BorderSize  = 1
$btnClose.FlatAppearance.BorderColor = $BORDER
$form.Controls.Add($btnClose)

# Adjust form height to snugly fit all content
$form.ClientSize = New-Object System.Drawing.Size(540, ($btnRowY + 56))

$btnSave.Add_Click({
    if (-not (Test-Path $_regPath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "PRISM registry key not found at HKLM:\SOFTWARE\PRISM.`n`nIs PRISM installed? Run PRISM-Setup.ps1 to install.",
            "Cannot Save - PRISM Not Installed",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }

    # Disable button while saving to prevent double-clicks
    $btnSave.Enabled = $false
    $btnSave.Text    = "Saving..."

    try {
        Set-ItemProperty -Path $_regPath -Name "CapacityThreshold"  -Value ([int]$capUpDown.Value)       -Force
        Set-ItemProperty -Path $_regPath -Name "PreserveFolders"    -Value ([int]$preserveUpDown.Value)  -Force
        Set-ItemProperty -Path $_regPath -Name "MonitoringInterval" -Value ([int]$intervalUpDown.Value)  -Force
        # Drive size registry value stays in sync (actual resize uses the Resize Drive button)
        Set-ItemProperty -Path $_regPath -Name "DriveSize"          -Value $script:_regDriveSize         -Force

        $newInterval    = [int]$intervalUpDown.Value
        $triggerStartup = New-ScheduledTaskTrigger -AtStartup
        $triggerRepeat  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
            -RepetitionInterval (New-TimeSpan -Minutes $newInterval) `
            -RepetitionDuration (New-TimeSpan -Days 9999)
        Set-ScheduledTask -TaskName "PRISM-Monitor" -Trigger @($triggerStartup, $triggerRepeat) -ErrorAction SilentlyContinue | Out-Null

        # Flash success state
        $btnSave.Text      = "Saved!"
        $btnSave.BackColor = $SUCCESS
        $form.Refresh()

        $script:_saveTimer = New-Object System.Windows.Forms.Timer
        $script:_saveTimer.Interval = 1500
        $script:_saveTimer.Add_Tick({
            $btnSave.Text      = "Save Settings"
            $btnSave.BackColor = $ACCENT
            $btnSave.Enabled   = $true
            $script:_saveTimer.Stop()
            $script:_saveTimer.Dispose()
            $script:_saveTimer = $null
        })
        $script:_saveTimer.Start()
    } catch {
        $btnSave.Text      = "Save Settings"
        $btnSave.BackColor = $ACCENT
        $btnSave.Enabled   = $true
        [System.Windows.Forms.MessageBox]::Show(
            "Save failed: $_",
            "Save Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$btnClose.Add_Click({ $form.Close() })

$form.Add_Load({
    # Use live header height: after DPI auto-scaling it differs from the 60px design value
    $lblPrism.Top = [int](($headerPanel.Height - $lblPrism.Height) / 2)
    $lblSub.Top   = [int](($headerPanel.Height - $lblSub.Height)   / 2)

    # NumericUpDown height is font-auto-sized and ignores Scale(); snap each
    # bordered wrapper panel to the real spinner height so no dead strip shows.
    foreach ($nud in @($capUpDown, $preserveUpDown, $intervalUpDown, $driveSizeUpDown)) {
        $wrap = $nud.Parent
        $cy   = $wrap.Top + [int]($wrap.Height / 2)
        $wrap.Height  = $nud.Height + 2
        $wrap.Top     = $cy - [int]($wrap.Height / 2)
        $nud.Location = New-Object System.Drawing.Point(1, 1)
        $nud.Width    = $wrap.Width - 2
    }

    if ($script:_regMissing) {
        $warnBanner.Visible = $true
        # Shift everything below the header down by the banner's live (scaled) footprint
        $shift = ($warnBanner.Bottom + 8) - $statusOuter.Top
        if ($shift -lt 0) { $shift = 0 }
        foreach ($ctrl in $form.Controls) {
            if ($ctrl -eq $headerPanel -or $ctrl -eq $warnBanner) { continue }
            $ctrl.Location = New-Object System.Drawing.Point($ctrl.Location.X, ($ctrl.Location.Y + $shift))
        }
        $form.ClientSize = New-Object System.Drawing.Size($form.ClientSize.Width, ($form.ClientSize.Height + $shift))
        $btnSave.Enabled = $false
    }

    Update-StatusCard
    Update-ResizeSection

    # Live refresh: keep the drive status card current while the window is open
    $script:statusTimer = New-Object System.Windows.Forms.Timer
    $script:statusTimer.Interval = 5000
    $script:statusTimer.Add_Tick({ Update-StatusCard })
    $script:statusTimer.Start()
})

$form.Add_FormClosing({
    if ($script:statusTimer) { $script:statusTimer.Stop(); $script:statusTimer.Dispose() }
})

# Scale the finished layout once for the actual display DPI. The process is
# DPI-aware, so fonts already render larger at 125%/150% — without this the
# 96-DPI pixel layout clips them. Control.Scale resizes the whole tree.
if ($script:DPI_SCALE -gt 1.0) {
    $form.Scale((New-Object System.Drawing.SizeF($script:DPI_SCALE, $script:DPI_SCALE)))
}

[System.Windows.Forms.Application]::Run($form)
