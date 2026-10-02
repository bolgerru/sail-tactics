<#
Copies the signing secrets Sail Tactics needs from your ios-signing folder (the ones First Not Last
already uses) into this repo's GitHub Actions secrets, using the GitHub CLI you are logged in with.
Nothing is printed or stored anywhere else: each file is piped straight into `gh secret set`.

  .\godot\tools\ios\set_secrets.ps1 -KeyId <App Store Connect Key ID> -IssuerId <Issuer ID>

KeyId    : the Key ID of the App Store Connect API key (the AuthKey_<KeyId>.p8 file in ios-signing).
           Use the same one as in First Not Last's ASC_KEY_ID secret.
IssuerId : the Issuer ID shown above the keys table at
           App Store Connect > Users and Access > Integrations > App Store Connect API.
#>
param(
    [Parameter(Mandatory = $true)][string]$KeyId,
    [Parameter(Mandatory = $true)][string]$IssuerId,
    [string]$Repo = "bolgerru/sail-tactics",
    [string]$Dir = (Join-Path $HOME "ios-signing")
)

$ErrorActionPreference = "Stop"
$KeyId = $KeyId.Trim()
$IssuerId = $IssuerId.Trim()

$p12 = Join-Path $Dir "github-secrets\IOS_DIST_CERT_P12_BASE64.txt"
$pw = Join-Path $Dir "github-secrets\IOS_DIST_CERT_P12_PASSWORD.txt"
$p8 = Join-Path $Dir ("AuthKey_{0}.p8" -f $KeyId)

foreach ($f in @($p12, $pw, $p8)) {
    if (-not (Test-Path $f)) {
        $keys = (Get-ChildItem $Dir -Filter "AuthKey_*.p8" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) -join ", "
        throw "Missing $f. API key files in ${Dir}: $keys"
    }
}
gh auth status | Out-Null

Write-Host "Setting secrets on $Repo ..."
Get-Content -Raw $p12 | gh secret set IOS_DIST_CERT_P12_BASE64 --repo $Repo
Get-Content -Raw $pw | gh secret set IOS_DIST_CERT_P12_PASSWORD --repo $Repo
Get-Content -Raw $p8 | gh secret set ASC_API_KEY_P8 --repo $Repo
$KeyId | gh secret set ASC_KEY_ID --repo $Repo
$IssuerId | gh secret set ASC_ISSUER_ID --repo $Repo

Write-Host ""
Write-Host "Done. Secrets now on ${Repo}:"
gh secret list --repo $Repo
