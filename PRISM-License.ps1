# PRISM - License Utilities
# Dot-sourced by PRISM.ps1 (monitor) and PRISM-Setup.ps1 (installer).
#
# Logic mirrors SETup/license_utils.ps1 and WKFusion/license_check.py:
#   RSA offline verify -> heartbeat on grace expiry -> activation on install.
#
# KEY DIFFERENCES from SETup:
#   - PRISM is machine-installed, so the licence binds to the SYSTEM DRIVE
#     volume serial number (like WKFusion), not a removable USB drive.
#   - The signed token is cached in HKLM:\SOFTWARE\PRISM\license so both the
#     elevated installer and the SYSTEM scheduled task can read/write it.
#   - The monitor runs headless: Update-PrismLicense never prompts or exits.
#     Interactive activation is a WinForms dialog (Show-PrismActivation).

# -- Constants -----------------------------------------------------------------
# Enforce TLS 1.2+ for all API calls (PS 5.1 may default to TLS 1.0 on older Win10)
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

$script:_PRISM_API_BASE = "https://script-masters-olive.vercel.app"
$script:_PRISM_PRODUCT  = "prism"
$script:_PRISM_LIC_REG  = "HKLM:\SOFTWARE\PRISM\license"

# RSA-2048 public key (.NET XML). Server signs with the paired private key.
# This public key can only verify - it cannot forge tokens.
# Same key pair as SETup/WKFusion. To regenerate: cd scriptmasters/web && npm run keygen
$script:_PRISM_RSA_XML = '<RSAKeyValue><Modulus>r9ZXehdt+ZFOFyXgfCb772GBjUIIU99shIPyvtcfTz9w7xe6/x9QQZRg3unbegMHuIHY9y1PzIL0VrbMumPL9nHzDFCq1f5OLYsGcyUkTCKwMHV/BpGT1uPc56T1535PzgpiOgmjJglIHXgnv7XOjQiQW/0epPH7cKSKqyp9c1ekdUQhVdyRN4wE2HA07PHTMWL8zMeLi5SAapRu/DmD+3QLraCvk7K3KQCEUl2icOazZdOAoBBVf1F2rnUTcDI30jyndouUWCZOpXs1Sq+ukaCKIHoGrWH59Lat3cflwbI/R2P8oqWI42wirJLIZyc0ANjVG3cAWIv27GvG9wMfGQ==</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>'

# -- RSA-SHA256 verification -----------------------------------------------------
function _PrismVerify-Signature {
    param(
        [Parameter(Mandatory)][string]$Payload,
        [Parameter(Mandatory)][string]$SigB64Url
    )
    try {
        $sig = $SigB64Url -replace '-', '+' -replace '_', '/'
        switch ($sig.Length % 4) { 2 { $sig += '==' } 3 { $sig += '=' } }
        $sigBytes     = [Convert]::FromBase64String($sig)
        if ($sigBytes.Length -eq 0) { return $false }
        $payloadBytes = [System.Text.Encoding]::UTF8.GetBytes($Payload)

        $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
        $rsa.FromXmlString($script:_PRISM_RSA_XML)
        $sha  = [System.Security.Cryptography.SHA256CryptoServiceProvider]::new()
        $hash = $sha.ComputeHash($payloadBytes)
        $oid  = [System.Security.Cryptography.CryptoConfig]::MapNameToOID('SHA256')
        return $rsa.VerifyHash($hash, $oid, $sigBytes)
    } catch {
        return $false
    }
}

# -- System drive VSN ------------------------------------------------------------
function Get-PrismDriveVsn {
    <#
    .SYNOPSIS
        Volume serial number of the system drive (the licence binding identity).
        Returns $null on failure.
    #>
    try {
        $qualifier = if ($env:SystemDrive) { $env:SystemDrive } else { "C:" }
        $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$qualifier'" -ErrorAction Stop
        $vsn  = $disk.VolumeSerialNumber
        if ([string]::IsNullOrWhiteSpace($vsn)) { return $null }
        return $vsn
    } catch { return $null }
}

# -- Registry token cache I/O -----------------------------------------------------
function Read-PrismLicenseCache {
    <#
    .SYNOPSIS
        Read and parse the cached signed token from the registry.
        Returns hashtable with fields: usb_vsn, plan, key_hash, last_verified,
        grace_expiry, signature, raw. Returns $null if missing or malformed.
    #>
    try {
        $reg = Get-ItemProperty -Path $script:_PRISM_LIC_REG -ErrorAction Stop
    } catch { return $null }
    $token = [string]$reg.signed_token
    if ([string]::IsNullOrWhiteSpace($token)) { return $null }
    $parts = $token.Trim() -split '\|'
    # The server emits exactly 6 fields; reject anything else so a stray '|'
    # cannot truncate the signature or smuggle extra data.
    if ($parts.Count -ne 6) { return $null }
    if ([string]::IsNullOrWhiteSpace($parts[0]) -or
        [string]::IsNullOrWhiteSpace($parts[2]) -or
        [string]::IsNullOrWhiteSpace($parts[5])) { return $null }
    return @{
        usb_vsn      = $parts[0].Trim()
        plan         = $parts[1].Trim().ToLower()
        key_hash     = $parts[2].Trim().ToLower()
        last_verified= $parts[3].Trim()
        grace_expiry = $parts[4].Trim()
        signature    = $parts[5].Trim()
        raw          = $token.Trim()
    }
}

function Write-PrismLicenseCache {
    <#
    .SYNOPSIS
        Persist the signed_token returned by the API to HKLM:\SOFTWARE\PRISM\license.
        Requires elevation (installer) or SYSTEM (monitor).
    #>
    param([Parameter(Mandatory)][string]$SignedToken)
    if (-not (Test-Path "HKLM:\SOFTWARE\PRISM")) {
        New-Item -Path "HKLM:\SOFTWARE" -Name "PRISM" -Force -ErrorAction Stop | Out-Null
    }
    if (-not (Test-Path $script:_PRISM_LIC_REG)) {
        New-Item -Path "HKLM:\SOFTWARE\PRISM" -Name "license" -Force -ErrorAction Stop | Out-Null
    }
    $parts = $SignedToken.Trim() -split '\|'
    Set-ItemProperty -Path $script:_PRISM_LIC_REG -Name "signed_token" -Value $SignedToken.Trim() -Force
    if ($parts.Count -eq 6) {
        # Convenience copies for diagnostics; signed_token stays authoritative.
        Set-ItemProperty -Path $script:_PRISM_LIC_REG -Name "usb_vsn"      -Value $parts[0] -Force
        Set-ItemProperty -Path $script:_PRISM_LIC_REG -Name "key_hash"     -Value $parts[2] -Force
        Set-ItemProperty -Path $script:_PRISM_LIC_REG -Name "grace_expiry" -Value $parts[4] -Force
    }
}

function Remove-PrismLicenseCache {
    try {
        if (Test-Path $script:_PRISM_LIC_REG) {
            Remove-Item -Path $script:_PRISM_LIC_REG -Recurse -Force -ErrorAction Stop
        }
    } catch { }
}

# -- Token validity ----------------------------------------------------------------
function _PrismToken-StillValid {
    param(
        [Parameter(Mandatory)][hashtable]$Token,
        [Parameter(Mandatory)][string]$CurrentVsn
    )
    if ($Token.usb_vsn -ne $CurrentVsn) { return $false }
    $payload = "$($Token.usb_vsn)|$($Token.plan)|$($Token.key_hash)|$($Token.last_verified)|$($Token.grace_expiry)"
    if (-not (_PrismVerify-Signature -Payload $payload -SigB64Url $Token.signature)) { return $false }
    try {
        $now = (Get-Date).ToUniversalTime()
        # Clock rollback detection: system time before last verification -> force online heartbeat
        $lastVerified = [datetime]::Parse($Token.last_verified, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
        if ($now -lt $lastVerified) { return $false }
        $expiry = [datetime]::Parse($Token.grace_expiry, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
        return ($now -lt $expiry)
    } catch { return $false }
}

# -- Generic API POST ---------------------------------------------------------------
function _PrismPost-Api {
    param(
        [Parameter(Mandatory)][string]$Endpoint,
        [Parameter(Mandatory)][hashtable]$Body
    )
    try {
        $json    = $Body | ConvertTo-Json -Compress
        $headers = @{ "Content-Type" = "application/json" }
        $resp    = Invoke-RestMethod -Uri "$($script:_PRISM_API_BASE)$Endpoint" `
                                     -Method POST -Body $json -Headers $headers `
                                     -TimeoutSec 15 -ErrorAction Stop
        return $resp
    } catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            try { $statusCode = [int]$_.Exception.Response.StatusCode } catch {}
        }
        # PS 5.1 often leaves ErrorDetails.Message empty on WebException; fall
        # back to reading the response stream so the API error code (REVOKED,
        # INVALID_KEY, ...) is not flattened into a bare HTTP status. Without
        # this, hard errors would be misclassified as transient network issues.
        $errCode = $null
        try {
            $errBody = $_.ErrorDetails.Message
            if ([string]::IsNullOrWhiteSpace($errBody) -and $_.Exception.Response) {
                $stream = $_.Exception.Response.GetResponseStream()
                if ($stream) {
                    $reader  = New-Object System.IO.StreamReader($stream)
                    $errBody = $reader.ReadToEnd()
                    $reader.Dispose()
                }
            }
            if (-not [string]::IsNullOrWhiteSpace($errBody)) {
                $errCode = (ConvertFrom-Json $errBody -ErrorAction Stop).error
            }
        } catch { $errCode = $null }
        $code = if ($errCode) { $errCode } elseif ($statusCode) { "HTTP_$statusCode" } else { "NETWORK_ERROR" }
        return [PSCustomObject]@{ _error = $code }
    }
}

# -- API wrappers --------------------------------------------------------------------
function Invoke-PrismActivate {
    param(
        [Parameter(Mandatory)][string]$LicenseKey,
        [Parameter(Mandatory)][string]$UsbVsn
    )
    return _PrismPost-Api -Endpoint "/api/activate" -Body @{
        license_key = $LicenseKey
        usb_vsn     = $UsbVsn
        product     = $script:_PRISM_PRODUCT
    }
}

function Invoke-PrismHeartbeat {
    param(
        [Parameter(Mandatory)][string]$KeyHash,
        [Parameter(Mandatory)][string]$UsbVsn
    )
    return _PrismPost-Api -Endpoint "/api/heartbeat" -Body @{
        key_hash = $KeyHash
        usb_vsn  = $UsbVsn
    }
}

# -- Error message map -----------------------------------------------------------------
$script:_PrismErrMsg = @{
    INVALID_KEY          = "License key not found."
    PRODUCT_MISMATCH     = "This key belongs to a different product."
    REVOKED              = "This license has been revoked."
    EXPIRED              = "This license has expired."
    RUNS_EXHAUSTED       = "All runs on this license have been used."
    ALREADY_BOUND        = "This key is already bound to a different computer."
    SEATS_EXHAUSTED      = "All PC seats on this license are in use. Contact sales to add seats."
    INVALID_REQUEST      = "Invalid key format. Expected: XXXX-XXXX-XXXX-XXXX"
    UNAUTHORIZED         = "License not recognized."
    SUBSCRIPTION_EXPIRED = "Subscription has expired."
    USB_MISMATCH         = "Hardware mismatch - this key is bound to a different computer."
    NETWORK_ERROR        = "Could not reach license server. Check your internet connection."
    SIGNING_ERROR        = "Server error while signing the license. Try again later."
}

$script:_PrismHardErrors = @(
    'REVOKED','SUBSCRIPTION_EXPIRED','RUNS_EXHAUSTED','UNAUTHORIZED','USB_MISMATCH'
)

# -- Silent offline-only check ------------------------------------------------------------
function Test-PrismLicenseSilent {
    <#
    .SYNOPSIS
        Validate using the locally cached token only.
        Returns @($valid, $message). Never prints, prompts, goes online, or exits.
    #>
    try {
        $vsn = Get-PrismDriveVsn
        if (-not $vsn) { return @($false, '') }
        $lic = Read-PrismLicenseCache
        if ($null -eq $lic) { return @($false, '') }
        if (_PrismToken-StillValid -Token $lic -CurrentVsn $vsn) {
            $expiry   = [datetime]::Parse($lic.grace_expiry, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
            $daysLeft = [int](($expiry - (Get-Date).ToUniversalTime()).TotalDays)
            return @($true, "License valid - ${daysLeft}d until next verification")
        }
        return @($false, '')
    } catch { return @($false, '') }
}

# -- Non-interactive validation gate ----------------------------------------------------------
function Update-PrismLicense {
    <#
    .SYNOPSIS
        Full non-interactive license validation: offline token check first, then
        an online heartbeat when the grace period has expired. Used by the
        headless monitor (SYSTEM scheduled task) and as the installer pre-check.
        Never prompts, never exits.
    .OUTPUTS
        Hashtable: @{ Valid = bool; Status = string; Message = string }
        Status values: Valid, Heartbeat, NotActivated, Offline, NoVsn,
        or a hard error code (REVOKED, SUBSCRIPTION_EXPIRED, ...).
    #>

    # >>> DEV-BYPASS (strip before shipping customer bundles)
    if ($env:PRISM_LOCAL_DEV -eq "1") {
        return @{ Valid = $true; Status = 'DevBypass'; Message = 'LOCAL DEV MODE - license check bypassed' }
    }
    # <<< DEV-BYPASS

    $vsn = Get-PrismDriveVsn
    if (-not $vsn) {
        return @{ Valid = $false; Status = 'NoVsn'; Message = 'Could not read the system drive serial number.' }
    }

    $lic = Read-PrismLicenseCache

    # -- 1. Offline check - valid cached token ----------------------------------
    if ($lic -and (_PrismToken-StillValid -Token $lic -CurrentVsn $vsn)) {
        $expiry   = [datetime]::Parse($lic.grace_expiry, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
        $daysLeft = [int](($expiry - (Get-Date).ToUniversalTime()).TotalDays)
        return @{ Valid = $true; Status = 'Valid'; Message = "License valid - ${daysLeft}d until next verification" }
    }

    # -- 2. Have key_hash + same machine -> heartbeat -----------------------------
    if ($lic -and $lic.key_hash -and $lic.usb_vsn -eq $vsn) {
        $resp = Invoke-PrismHeartbeat -KeyHash $lic.key_hash -UsbVsn $vsn

        if ($resp -and $resp.signed_token) {
            try { Write-PrismLicenseCache -SignedToken $resp.signed_token } catch { }
            $updated = Read-PrismLicenseCache
            if ($updated -and $updated.plan -eq 'runs') {
                $rem    = $resp.runs_remaining
                $suffix = if ($null -ne $rem) { "$rem run$(if ($rem -ne 1) {'s'}) remaining" } else { "run-limited" }
            } else {
                $expiry   = [datetime]::Parse($updated.grace_expiry, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
                $daysLeft = [int](($expiry - (Get-Date).ToUniversalTime()).TotalDays)
                $suffix   = "${daysLeft}d grace"
            }
            return @{ Valid = $true; Status = 'Heartbeat'; Message = "License verified online - $suffix" }
        }

        $err = if ($resp -and $resp._error) { [string]$resp._error } else { 'NETWORK_ERROR' }
        if ($script:_PrismHardErrors -contains $err) {
            $msg = $script:_PrismErrMsg[$err]
            if (-not $msg) { $msg = $err }
            return @{ Valid = $false; Status = $err; Message = $msg }
        }

        # Genuine network failure with an expired local token: fail closed.
        return @{ Valid = $false; Status = 'Offline'; Message = 'Cannot reach the license server and the local token has expired.' }
    }

    # -- 3. No valid activation -------------------------------------------------
    return @{ Valid = $false; Status = 'NotActivated'; Message = 'No license is activated on this computer.' }
}

# -- Interactive GUI activation -------------------------------------------------------------------
function Show-PrismActivation {
    <#
    .SYNOPSIS
        Modal WinForms dialog that activates a license key against the API and
        caches the signed token in the registry. Requires elevation.
        Returns $true on successful activation, $false on cancel/failure.
    .PARAMETER Owner
        Optional owner form so the dialog centers over the installer window.
        Deliberately untyped: this library is also dot-sourced by the headless
        monitor where System.Windows.Forms is not loaded, and an unresolvable
        parameter type constraint would break the function.
    #>
    param($Owner = $null)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $vsn = Get-PrismDriveVsn
    if (-not $vsn) {
        [System.Windows.Forms.MessageBox]::Show(
            "Could not read the system drive serial number. PRISM cannot be activated.",
            "PRISM - License", [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return $false
    }

    # Palette matches PRISM-Setup / PRISM-Config
    $BG       = [System.Drawing.ColorTranslator]::FromHtml("#0d1117")
    $BG_CARD  = [System.Drawing.ColorTranslator]::FromHtml("#161b22")
    $BG_INPUT = [System.Drawing.ColorTranslator]::FromHtml("#21262d")
    $BORDER   = [System.Drawing.ColorTranslator]::FromHtml("#30363d")
    $TEXT_PRI = [System.Drawing.ColorTranslator]::FromHtml("#e6edf3")
    $TEXT_SEC = [System.Drawing.ColorTranslator]::FromHtml("#8b949e")
    $ACCENT   = [System.Drawing.ColorTranslator]::FromHtml("#2ea2cc")
    $SUCCESS  = [System.Drawing.ColorTranslator]::FromHtml("#3fb950")
    $DANGER   = [System.Drawing.ColorTranslator]::FromHtml("#f85149")

    $dlg                 = New-Object System.Windows.Forms.Form
    $dlg.Text            = "PRISM - License Activation"
    $dlg.ClientSize      = New-Object System.Drawing.Size(420, 330)
    $dlg.BackColor       = $BG
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dlg.MaximizeBox     = $false
    $dlg.MinimizeBox     = $false
    $dlg.StartPosition   = if ($Owner) { [System.Windows.Forms.FormStartPosition]::CenterParent } else { [System.Windows.Forms.FormStartPosition]::CenterScreen }

    $header           = New-Object System.Windows.Forms.Panel
    $header.Location  = New-Object System.Drawing.Point(0, 0)
    $header.Size      = New-Object System.Drawing.Size(420, 52)
    $header.BackColor = $BG_CARD

    $lblTitle           = New-Object System.Windows.Forms.Label
    $lblTitle.Text      = "License Activation"
    $lblTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = $ACCENT
    $lblTitle.AutoSize  = $true
    $lblTitle.Location  = New-Object System.Drawing.Point(20, 13)
    $header.Controls.Add($lblTitle)

    $lblInfo           = New-Object System.Windows.Forms.Label
    $lblInfo.Text      = "Enter your license key to activate PRISM." + [Environment]::NewLine + "Purchase a key at scriptmasters.dev"
    $lblInfo.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
    $lblInfo.ForeColor = $TEXT_PRI
    $lblInfo.Location  = New-Object System.Drawing.Point(20, 68)
    $lblInfo.Size      = New-Object System.Drawing.Size(380, 42)

    $lblBind           = New-Object System.Windows.Forms.Label
    $lblBind.Text      = "IMPORTANT: this computer (system drive VSN $vsn) will claim one PC seat on the license. A license covers a fixed number of PCs - one seat per computer."
    $lblBind.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblBind.ForeColor = $TEXT_SEC
    $lblBind.Location  = New-Object System.Drawing.Point(20, 114)
    $lblBind.Size      = New-Object System.Drawing.Size(380, 48)

    $keyWrap           = New-Object System.Windows.Forms.Panel
    $keyWrap.Location  = New-Object System.Drawing.Point(20, 170)
    $keyWrap.Size      = New-Object System.Drawing.Size(380, 34)
    $keyWrap.BackColor = $BORDER

    $txtKey                  = New-Object System.Windows.Forms.TextBox
    $txtKey.Font             = New-Object System.Drawing.Font("Consolas", 13)
    $txtKey.BackColor        = $BG_INPUT
    $txtKey.ForeColor        = $TEXT_PRI
    $txtKey.BorderStyle      = [System.Windows.Forms.BorderStyle]::None
    $txtKey.CharacterCasing  = [System.Windows.Forms.CharacterCasing]::Upper
    $txtKey.MaxLength        = 19
    $txtKey.TextAlign        = [System.Windows.Forms.HorizontalAlignment]::Center
    $txtKey.Location         = New-Object System.Drawing.Point(1, 1)
    $txtKey.Size             = New-Object System.Drawing.Size(378, 32)
    $keyWrap.Controls.Add($txtKey)

    $lblStatus           = New-Object System.Windows.Forms.Label
    $lblStatus.Text      = "Format: XXXX-XXXX-XXXX-XXXX"
    $lblStatus.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblStatus.ForeColor = $TEXT_SEC
    $lblStatus.Location  = New-Object System.Drawing.Point(20, 212)
    $lblStatus.Size      = New-Object System.Drawing.Size(380, 38)

    $btnCancel                            = New-Object System.Windows.Forms.Button
    $btnCancel.Text                       = "Cancel"
    $btnCancel.Font                       = New-Object System.Drawing.Font("Segoe UI", 10)
    $btnCancel.ForeColor                  = $TEXT_SEC
    $btnCancel.BackColor                  = $BG_CARD
    $btnCancel.FlatStyle                  = [System.Windows.Forms.FlatStyle]::Flat
    $btnCancel.FlatAppearance.BorderColor = $BORDER
    $btnCancel.FlatAppearance.BorderSize  = 1
    $btnCancel.Location                   = New-Object System.Drawing.Point(20, 268)
    $btnCancel.Size                       = New-Object System.Drawing.Size(130, 42)
    $btnCancel.DialogResult               = [System.Windows.Forms.DialogResult]::Cancel

    $btnActivate                           = New-Object System.Windows.Forms.Button
    $btnActivate.Text                      = "Activate"
    $btnActivate.Font                      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnActivate.ForeColor                 = $BG
    $btnActivate.BackColor                 = $ACCENT
    $btnActivate.FlatStyle                 = [System.Windows.Forms.FlatStyle]::Flat
    $btnActivate.FlatAppearance.BorderSize = 0
    $btnActivate.Location                  = New-Object System.Drawing.Point(230, 268)
    $btnActivate.Size                      = New-Object System.Drawing.Size(170, 42)

    $dlg.Controls.AddRange(@($header, $lblInfo, $lblBind, $keyWrap, $lblStatus, $btnCancel, $btnActivate))
    $dlg.AcceptButton = $btnActivate
    $dlg.CancelButton = $btnCancel

    $btnActivate.Add_Click({
        $raw = $txtKey.Text.Trim().ToUpper()
        if (-not ($raw -match '^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$')) {
            $lblStatus.ForeColor = $DANGER
            $lblStatus.Text      = "Invalid format. Expected: XXXX-XXXX-XXXX-XXXX"
            return
        }

        $btnActivate.Enabled = $false
        $btnCancel.Enabled   = $false
        $lblStatus.ForeColor = $TEXT_SEC
        $lblStatus.Text      = "Activating..."
        $dlg.Refresh()

        $resp = Invoke-PrismActivate -LicenseKey $raw -UsbVsn $vsn

        if ($resp -and $resp.signed_token) {
            try {
                Write-PrismLicenseCache -SignedToken $resp.signed_token
            } catch {
                $lblStatus.ForeColor = $DANGER
                $lblStatus.Text      = "Could not save the license to the registry: $_"
                $btnActivate.Enabled = $true
                $btnCancel.Enabled   = $true
                return
            }
            $lblStatus.ForeColor = $SUCCESS
            $seatInfo = if ($resp.max_seats -and [int]$resp.max_seats -gt 1) { " (seat $($resp.seats_used) of $($resp.max_seats))" } else { "" }
            $lblStatus.Text      = "Activated! License bound to this computer$seatInfo."
            $dlg.DialogResult    = [System.Windows.Forms.DialogResult]::OK
            $dlg.Close()
            return
        }

        $err = if ($resp -and $resp._error) { [string]$resp._error } else { "UNKNOWN" }
        $msg = $script:_PrismErrMsg[$err]
        if (-not $msg) { $msg = "Error: $err" }
        $lblStatus.ForeColor = $DANGER
        $lblStatus.Text      = $msg
        $btnActivate.Enabled = $true
        $btnCancel.Enabled   = $true
    })

    # AutoScaleMode is a no-op for hand-built layouts: scale the finished tree
    # once for the actual display DPI before showing (same as the other GUIs).
    $g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    $dpiScale = $g.DpiX / 96.0
    $g.Dispose()
    if ($dpiScale -gt 1.0) {
        $dlg.Scale((New-Object System.Drawing.SizeF($dpiScale, $dpiScale)))
    }

    $result = if ($Owner) { $dlg.ShowDialog($Owner) } else { $dlg.ShowDialog() }
    $dlg.Dispose()
    return ($result -eq [System.Windows.Forms.DialogResult]::OK)
}
