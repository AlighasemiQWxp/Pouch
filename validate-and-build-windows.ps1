$ErrorActionPreference = "Stop"
$RepositoryRoot = $PSScriptRoot
$FlutterDirectory = Join-Path $RepositoryRoot "flutter"

function Invoke-Check {
    param([string]$Executable, [string[]]$Arguments)
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Executable failed with exit code $LASTEXITCODE." }
}

Push-Location -LiteralPath $RepositoryRoot
try {
    Invoke-Check cargo @("fmt", "--manifest-path", "rust/Cargo.toml", "--", "--check")
    Invoke-Check cargo @("clippy", "--manifest-path", "rust/Cargo.toml", "--all-targets", "--locked", "--", "-D", "warnings")
    Invoke-Check cargo @("test", "--manifest-path", "rust/Cargo.toml", "--locked")
    Set-Location -LiteralPath $FlutterDirectory
    Invoke-Check flutter @("pub", "get", "--enforce-lockfile")
    Invoke-Check dart @("format", "--output=none", "--set-exit-if-changed", "lib", "test")
    Invoke-Check flutter @("analyze")
    Invoke-Check flutter @("test")
    Invoke-Check flutter @("build", "windows", "--release")
    $Bundle = Join-Path $FlutterDirectory "build/windows/x64/runner/Release"
    foreach ($Required in @("pouch.exe", "pouch_core.dll", "flutter_windows.dll", "data/flutter_assets")) {
        if (-not (Test-Path -LiteralPath (Join-Path $Bundle $Required))) {
            throw "The Windows bundle is missing $Required."
        }
    }
    Copy-Item -LiteralPath (Join-Path $RepositoryRoot "LICENSE") -Destination (Join-Path $Bundle "LICENSE")
    Copy-Item -LiteralPath (Join-Path $RepositoryRoot "THIRD_PARTY_NOTICES.md") -Destination $Bundle
    Copy-Item -LiteralPath (Join-Path $FlutterDirectory "assets/fonts/OFL.txt") -Destination (Join-Path $Bundle "Amiri-LICENSE.txt")
    $OutputDirectory = Join-Path $RepositoryRoot "dist"
    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    $VersionLine = Get-Content (Join-Path $FlutterDirectory "pubspec.yaml") | Where-Object { $_ -match '^version:' }
    $Version = ($VersionLine -replace '^version:\s*', '').Split('+')[0]
    $Archive = Join-Path $OutputDirectory "pouch-$Version-windows-x64.zip"
    Compress-Archive -Path (Join-Path $Bundle '*') -DestinationPath $Archive -Force
    Get-FileHash -LiteralPath $Archive -Algorithm SHA256
    Write-Host "Windows bundle prepared. Test the extracted archive before publishing: $Archive"
}
finally { Pop-Location }
