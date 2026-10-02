<#
Copies the signing secrets Sail Tactics needs from your ios-signing folder (the ones First Not Last
already uses) into this repo's GitHub Actions secrets, using the GitHub CLI you are logged in with.
Nothing is printed or stored anywhere else: each file is piped straight into `gh secret set`.

  .\godot\tools\ios\set_secrets.ps1
  (it asks for the Key ID and Issuer ID; or pass them: -KeyId ABC123DEF4 -IssuerId 12345678-aaaa-bbbb-cccc-1234567890ab)

KeyId    : the Key ID of the App Store Connect API key (the AuthKey_<KeyId>.p8 file in ios-signing).
           Use the same one as in First Not Last's ASC_KEY_ID secret.
IssuerId : the Issuer ID shown above the keys table at
           App Store Connect > Users and Access > Integrations > App Store Connect API.
#>
param(
    [string]$KeyId,
    [string]$IssuerId,
    [string]$Repo = "bolgerru/sail-tactics",
    [string]$Dir = (Join-Path $HOME "ios-signing")
)

$ErrorActionPreference = "Stop"

if (-not $KeyId) {
    Write-Host "API key files in ${Dir}:"
    Get-ChildItem $Dir -Filter "AuthKey_*.p8" | ForEach-Object { Write-Host ("  " + $_.Name + "   -> Key ID " + ($_.BaseName -replace "^AuthKey_", "")) }
    $KeyId = Read-Host "Key ID (the one that is active in App Store Connect > Integrations)"
}
if (-not $IssuerId) {
    $IssuerId = Read-Host "Issuer ID (the UUID above the keys table in App Store Connect > Integrations)"
}
# Keep only what can be in the IDs, so a stray "#", quote or space is harmless.
$KeyId = ($KeyId -replace "[^A-Za-z0-9]", "").ToUpper()
$IssuerId = ($IssuerId -replace "[^A-Fa-f0-9-]", "").ToLower()
if ($KeyId.Length -ne 10) { throw "Key ID should be 10 letters/digits, e.g. LA37C4G56W (got '$KeyId')." }
if ($IssuerId -notmatch "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$") {
    throw "Issuer ID should look like 12345678-abcd-1234-abcd-1234567890ab (got '$IssuerId')."
}

$p12 = Join-Path $Dir "github-secrets\IOS_DIST_CERT_P12_BASE64.txt"
$pw = Join-Path $Dir "github-secrets\IOS_DIST_CERT_P12_PASSWORD.txt"
$p8 = Join-Path $Dir ("AuthKey_{0}.p8" -f $KeyId)

foreach ($f in @($p12, $pw, $p8)) {
    if (-not (Test-Path $f)) {
        $keys = (Get-ChildItem $Dir -Filter "AuthKey_*.p8" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) -join ", "
        throw "Missing $f. API key files in ${Dir}: $keys"
    }
}
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "The GitHub CLI (gh) is not installed. Install it from https://cli.github.com, then run: gh auth login"
}
gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    throw "The GitHub CLI is not logged in. Run:  gh auth login   (choose GitHub.com, HTTPS, and log in with the browser), then run this script again."
}

function Set-Secret($Name, $Value) {
    $Value | gh secret set $Name --repo $Repo
    if ($LASTEXITCODE -ne 0) { throw "Setting $Name failed (see the message above)." }
}

Write-Host "Setting secrets on $Repo ..."
Set-Secret "IOS_DIST_CERT_P12_BASE64" (Get-Content -Raw $p12)
Set-Secret "IOS_DIST_CERT_P12_PASSWORD" (Get-Content -Raw $pw)
Set-Secret "ASC_API_KEY_P8" (Get-Content -Raw $p8)
Set-Secret "ASC_KEY_ID" $KeyId
Set-Secret "ASC_ISSUER_ID" $IssuerId

Write-Host ""
Write-Host "Done. Secrets now on ${Repo}:"
gh secret list --repo $Repo
