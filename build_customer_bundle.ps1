# PRISM - Customer Bundle Builder (owner tool, NOT shipped)
#
# Stages for_customers\PRISM as the distribution copy of this repo:
#   1. Copies every shipped file (scripts, batch wrappers, vbs shim, logos, docs)
#   2. Strips the DEV-BYPASS block (PRISM_LOCAL_DEV) from PRISM-License.ps1
#      so customers cannot skip the license check by setting an env var
#   3. Verifies no PRISM_LOCAL_DEV reference survives anywhere in the bundle
#   4. Zips the bundle to for_customers\PRISM.zip
#
# Unlike SETup, PRISM is NOT compiled to EXEs: the Task Scheduler job, the
# wscript launch shim and the installer all invoke the scripts by .ps1 path,
# so the bundle ships scripts. The bypass strip is the security-relevant step.
#
# Run:  powershell -NoProfile -ExecutionPolicy Bypass -File build_customer_bundle.ps1

$ErrorActionPreference = "Stop"

$repoRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$stageRoot = Join-Path $repoRoot "for_customers\PRISM"
$zipPath   = Join-Path $repoRoot "for_customers\PRISM.zip"

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host " PRISM" -ForegroundColor Cyan
Write-Host " Customer Bundle Builder" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# -- Stage layout ---------------------------------------------------------------
if (Test-Path $stageRoot) { Remove-Item $stageRoot -Recurse -Force }
if (Test-Path $zipPath)   { Remove-Item $zipPath -Force }
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stageRoot "docs") -Force | Out-Null

# Everything the installer requires/copies, plus wrappers and docs.
# Copy-Item preserves bytes, so files that need a UTF-8 BOM keep it.
$shipFiles = @(
    "PRISM.ps1", "PRISM-Deploy.ps1", "PRISM-Setup.ps1", "PRISM-Deploy.bat",
    "PRISM-CreateSDrive.ps1", "PRISM-Config.ps1", "PRISM-Stop.ps1",
    "PRISM-Remove.ps1", "PRISM-Remove.bat", "PRISM-Tray.ps1",
    "PRISM-Troubleshoot.bat", "PRISM-Launch.vbs",
    "prism-logo.ico", "prism-logo.png"
)
foreach ($f in $shipFiles) {
    $src = Join-Path $repoRoot $f
    if (-not (Test-Path $src)) { throw "Required file missing: $f" }
    Copy-Item $src $stageRoot -Force
    Write-Host "  [+] $f" -ForegroundColor DarkGray
}
foreach ($d in (Get-ChildItem (Join-Path $repoRoot "docs") -File -Filter *.md)) {
    Copy-Item $d.FullName (Join-Path $stageRoot "docs") -Force
    Write-Host "  [+] docs\$($d.Name)" -ForegroundColor DarkGray
}

# -- Strip DEV-BYPASS from the license library -----------------------------------
Write-Host ""
Write-Host "  Stripping DEV-BYPASS from PRISM-License.ps1..." -ForegroundColor Yellow
$licSrc   = Get-Content (Join-Path $repoRoot "PRISM-License.ps1") -Raw -Encoding UTF8
$stripped = [regex]::Replace($licSrc, '(?s)[ \t]*# >>> DEV-BYPASS.*?# <<< DEV-BYPASS\r?\n?', '')
if ($stripped -eq $licSrc) { throw "DEV-BYPASS markers not found in PRISM-License.ps1 - refusing to ship a bypassable build." }
if ($stripped -match 'PRISM_LOCAL_DEV') { throw "PRISM_LOCAL_DEV still present after strip - aborting." }

# Stripped source must still parse before it ships.
$errs = $null; $tokens = $null
[System.Management.Automation.Language.Parser]::ParseInput($stripped, [ref]$tokens, [ref]$errs) | Out-Null
if ($errs.Count -gt 0) { throw "Stripped PRISM-License.ps1 does not parse: $($errs[0].Message) (line $($errs[0].Extent.StartLineNumber))" }

[System.IO.File]::WriteAllText((Join-Path $stageRoot "PRISM-License.ps1"), $stripped, [System.Text.UTF8Encoding]::new($true))
Write-Host "  [OK] PRISM-License.ps1 staged without bypass" -ForegroundColor Green

# -- Safety check: no bypass reference anywhere in the bundle --------------------
$leaks = Get-ChildItem $stageRoot -Recurse -File |
    Where-Object { $_.Extension -in ".ps1", ".bat", ".vbs", ".md" } |
    Where-Object { (Get-Content $_.FullName -Raw) -match 'PRISM_LOCAL_DEV' }
if ($leaks) { throw "PRISM_LOCAL_DEV leaked into bundle: $($leaks.FullName -join ', ')" }
Write-Host "  [OK] no PRISM_LOCAL_DEV reference in the bundle" -ForegroundColor Green

# -- Zip --------------------------------------------------------------------------
Compress-Archive -Path $stageRoot -DestinationPath $zipPath -CompressionLevel Optimal
$zipMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)

Write-Host ""
Write-Host "================================" -ForegroundColor Green
Write-Host " Bundle complete!" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Green
Write-Host "  Folder : $stageRoot" -ForegroundColor Cyan
Write-Host "  Zip    : $zipPath ($zipMB MB)" -ForegroundColor Cyan
Write-Host "  Customer entry point: PRISM-Deploy.bat (asks for the license key during install)" -ForegroundColor Cyan
Write-Host ""
