param(
    [string]$Python,
    [string]$VenvPath
)

$ErrorActionPreference = "Stop"
trap {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Set-Location $PSScriptRoot
$bundleRoot = Split-Path -Parent $PSScriptRoot

$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot "RELEASE-MANIFEST.json") -Raw -Encoding UTF8 | ConvertFrom-Json

$localAppData = [Environment]::GetEnvironmentVariable("LOCALAPPDATA")
if ([string]::IsNullOrWhiteSpace($localAppData)) {
    $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
}
if ([string]::IsNullOrWhiteSpace($localAppData)) {
    throw "Cannot determine the current user's local application data directory."
}

if ([string]::IsNullOrWhiteSpace($VenvPath)) {
    $VenvPath = Join-Path $localAppData "PyMotion\LiteSDK\venv-cp312"
} elseif (-not [System.IO.Path]::IsPathRooted($VenvPath)) {
    $VenvPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $VenvPath))
}
$VenvPath = [System.IO.Path]::GetFullPath($VenvPath)

$venvPython = Join-Path $VenvPath "Scripts\python.exe"
if (Test-Path -LiteralPath $VenvPath -PathType Container) {
    if (-not (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
        $existing = Get-ChildItem -LiteralPath $VenvPath -Force | Select-Object -First 1
        if ($null -ne $existing) {
            throw "The selected installation directory already exists but is not a Python virtual environment: $VenvPath"
        }
    }
}
if (-not (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
    $runtimeSource = Join-Path $bundleRoot "runtime\python312"
    if ([string]::IsNullOrWhiteSpace($Python)) {
        if (-not (Test-Path -LiteralPath (Join-Path $runtimeSource "python.exe") -PathType Leaf)) {
            throw "Bundled Python runtime is missing."
        }
        $runtimeId = ([string]$manifest.sha256sums_sha256).Substring(0, 12)
        $runtimeDestination = Join-Path $localAppData "PyMotion\LiteSDK\runtime\python312-$runtimeId"
        if (-not (Test-Path -LiteralPath (Join-Path $runtimeDestination "python.exe") -PathType Leaf)) {
            $runtimeParent = Split-Path -Parent $runtimeDestination
            New-Item -ItemType Directory -Path $runtimeParent -Force | Out-Null
            Copy-Item -LiteralPath $runtimeSource -Destination $runtimeDestination -Recurse
        }
        $basePython = Join-Path $runtimeDestination "python.exe"
    } else {
        $basePython = [System.IO.Path]::GetFullPath($Python)
        if (-not (Test-Path -LiteralPath $basePython -PathType Leaf)) {
            throw "Selected Python executable is missing: $basePython"
        }
    }
    Write-Host "Creating isolated SDK environment: $VenvPath"
    & $basePython -m venv $VenvPath
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create the SDK virtual environment."
    }
}
$wheels = @(Get-ChildItem -LiteralPath (Join-Path $bundleRoot "wheels") -Filter *.whl -File)
if ($wheels.Count -lt 1) {
    throw "Expected at least one SDK wheel in the wheels directory."
}
foreach ($wheel in $wheels) {
    if ($wheel.Name -notlike "pymotion_lite-1.0.1-*-win_amd64.whl") {
        throw "Expected a Windows x64 pymotion-lite wheel, found $($wheel.Name)."
    }
    if ($wheel.Name -like "*-py3-none-any.whl") {
        throw "Refusing an unprotected pure-Python SDK wheel."
    }
}
# The historical distribution used a different package name while owning the
# same Python import path.  Remove it first so a later uninstall cannot delete
# files belonging to the canonical pymotion-lite distribution.
$legacyInstalled = & $venvPython -c "import importlib.metadata as m; print('yes' if any((d.metadata.get('Name') or '').lower().replace('_', '-') == 'pymotion-lite-sdk' for d in m.distributions()) else 'no')"
if ($LASTEXITCODE -ne 0) {
    throw "Failed to inspect installed Python distributions."
}
if ($legacyInstalled.Trim() -eq "yes") {
    & $venvPython -m pip uninstall --yes pymotion-lite-sdk
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to remove the legacy pymotion-lite-sdk distribution."
    }
}

$dependencyDirectory = Join-Path $bundleRoot "wheels\dependencies"
if (-not (Test-Path -LiteralPath $dependencyDirectory -PathType Container)) {
    throw "Offline dependency wheel directory is missing."
}
$requirementsLock = Join-Path $PSScriptRoot "requirements.lock"
if (-not (Test-Path -LiteralPath $requirementsLock -PathType Leaf)) {
    throw "Offline requirements file is missing."
}
& $venvPython -m pip install --no-index --only-binary=:all: --find-links (Join-Path $bundleRoot "wheels") --find-links $dependencyDirectory --no-cache-dir --force-reinstall -r $requirementsLock
if ($LASTEXITCODE -ne 0) {
    throw "Offline installation failed. Review the pip error above."
}

& $venvPython -c "import pymotion as pm; print(pm.lite.__version__)"
if ($LASTEXITCODE -ne 0) {
    throw "Installed SDK self-check failed."
}

$installationId = ([string]$manifest.sha256sums_sha256).Substring(0, 12)
$installationStateDirectory = Join-Path $localAppData "PyMotion\LiteSDK\installations"
New-Item -ItemType Directory -Path $installationStateDirectory -Force | Out-Null
$installationState = [ordered]@{
    schema = 1
    bundle_id = $installationId
    venv_path = $VenvPath
    python_tag = "cp312"
    installed_at_utc = (Get-Date).ToUniversalTime().ToString("o")
}
$installationStatePath = Join-Path $installationStateDirectory "$installationId.json"
$installationState | ConvertTo-Json | Set-Content -LiteralPath $installationStatePath -Encoding UTF8

Write-Host "PyMotion Lite SDK installed successfully in $VenvPath"
Write-Host "Activate it with: $VenvPath\Scripts\Activate.ps1"
Write-Host "Open the SDK workspace with: $(Join-Path (Split-Path -Parent $PSScriptRoot) 'open-sdk-vscode.bat')"
