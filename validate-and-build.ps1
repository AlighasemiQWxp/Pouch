$ErrorActionPreference = "Stop"

$RepositoryRoot = $PSScriptRoot
$RustManifest = Join-Path $RepositoryRoot "rust\Cargo.toml"
$FlutterDirectory = Join-Path $RepositoryRoot "flutter"

function Invoke-Check {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Executable,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory
    )

    Write-Host "`n== $Name ==" -ForegroundColor Cyan
    Push-Location -LiteralPath $WorkingDirectory
    try {
        & $Executable @Arguments
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            throw "$Name failed with exit code $exitCode."
        }
    }
    finally {
        Pop-Location
    }
}

try {
    foreach ($toolName in @("cargo", "flutter")) {
        if (-not (Get-Command -Name $toolName -ErrorAction SilentlyContinue)) {
            throw "Required command '$toolName' was not found in PATH."
        }
    }

    if (-not (Test-Path -LiteralPath $RustManifest -PathType Leaf)) {
        throw "Rust manifest was not found: $RustManifest"
    }

    if (-not (Test-Path -LiteralPath (Join-Path $FlutterDirectory "pubspec.yaml") -PathType Leaf)) {
        throw "Flutter project was not found: $FlutterDirectory"
    }

    Invoke-Check -Name "Rust formatting" `
        -Executable "cargo" `
        -Arguments @("fmt", "--manifest-path", $RustManifest, "--", "--check") `
        -WorkingDirectory $RepositoryRoot

    Invoke-Check -Name "Rust Clippy" `
        -Executable "cargo" `
        -Arguments @("clippy", "--manifest-path", $RustManifest, "--all-targets", "--locked", "--", "-D", "warnings") `
        -WorkingDirectory $RepositoryRoot

    Invoke-Check -Name "Rust tests" `
        -Executable "cargo" `
        -Arguments @("test", "--manifest-path", $RustManifest, "--locked") `
        -WorkingDirectory $RepositoryRoot

    Invoke-Check -Name "Flutter dependency check" `
        -Executable "flutter" `
        -Arguments @("pub", "get", "--enforce-lockfile") `
        -WorkingDirectory $FlutterDirectory

    Invoke-Check -Name "Flutter analysis" `
        -Executable "flutter" `
        -Arguments @("analyze") `
        -WorkingDirectory $FlutterDirectory

    $FlutterTestDirectory = Join-Path $FlutterDirectory "test"
    $HasFlutterTests = $false
    if (Test-Path -LiteralPath $FlutterTestDirectory -PathType Container) {
        $HasFlutterTests = $null -ne (Get-ChildItem -LiteralPath $FlutterTestDirectory -Recurse -File -Filter "*_test.dart" -ErrorAction SilentlyContinue | Select-Object -First 1)
    }

    if ($HasFlutterTests) {
        Invoke-Check -Name "Flutter tests" `
            -Executable "flutter" `
            -Arguments @("test") `
            -WorkingDirectory $FlutterDirectory
    }
    else {
        Write-Host "`n== Flutter tests ==" -ForegroundColor Cyan
        Write-Host "Skipped because no Dart test files were found under flutter\test."
    }

    Invoke-Check -Name "Android release build" `
        -Executable "flutter" `
        -Arguments @("build", "apk", "--release") `
        -WorkingDirectory $FlutterDirectory

    Write-Host "`nAll checks passed. Android APK: flutter\build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Green
}
catch {
    Write-Host "Validation failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
