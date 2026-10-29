param(
    [string]$Notes = ""
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$pubspecPath = Join-Path $root "pubspec.yaml"
$source = Join-Path $root "build\app\outputs\flutter-apk\app-release.apk"

if (-not (Test-Path $source)) {
    throw "Release APK sa nenašiel: $source"
}

$pubspec = Get-Content $pubspecPath -Raw
$match = [regex]::Match(
    $pubspec,
    "(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)"
)
if (-not $match.Success) {
    throw "V pubspec.yaml sa nepodarilo nájsť verziu v tvare X.Y.Z+N."
}

$version = $match.Groups[1].Value
$build = [int]$match.Groups[2].Value
$releases = Join-Path $root "releases"
New-Item -ItemType Directory -Force -Path $releases | Out-Null

$fileName = "raritio-$version.apk"
$target = Join-Path $releases $fileName
Copy-Item -LiteralPath $source -Destination $target -Force

$item = Get-Item $target
$hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
$date = Get-Date -Format "yyyy-MM-dd HH:mm"
$row = "| $version | $date | $($item.Length) | ``$hash`` | $Notes |"

$versionsPath = Join-Path $releases "README.md"
if (-not (Test-Path $versionsPath)) {
    Set-Content -LiteralPath $versionsPath -Value "# Archív verzií Raritio`n`n| Verzia | Dátum | Veľkosť (B) | SHA256 | Poznámka |`n|---|---|---|---|---|" -Encoding utf8
}
$versions = Get-Content $versionsPath -Raw
$marker = "| $version |"
$pattern = "(?m)^" + [regex]::Escape($marker) + ".*$"
if ($versions -match $pattern) {
    $versions = [regex]::Replace($versions, $pattern, $row)
    Set-Content -LiteralPath $versionsPath -Value $versions -Encoding utf8
} else {
    Add-Content -LiteralPath $versionsPath -Value $row
}

Write-Output "Archived: $target"
Write-Output "SHA256: $hash"
