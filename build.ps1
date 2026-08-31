<#
.SYNOPSIS
    Build the oob-usb-serial .deb package on Windows.

.DESCRIPTION
    A .deb can only be produced by Debian tooling, which does not run natively
    on Windows. This wrapper builds via one of two backends:

      1. WSL   - if a WSL distro is available, run ./build.sh inside it.
      2. Docker - otherwise, run the Debian-container build path.

    On Linux/macOS use ./build.sh directly instead.

.PARAMETER Version
    Optional package version (e.g. 1.2.0). If omitted, build.sh derives it from
    the nearest git tag or debian/changelog.

.PARAMETER Backend
    Force a backend: 'wsl' or 'docker'. Auto-detected if not specified.

.EXAMPLE
    .\build.ps1
    .\build.ps1 -Version 1.2.0
    .\build.ps1 -Backend docker
#>
[CmdletBinding()]
param(
    [string]$Version = "",
    [ValidateSet("auto", "wsl", "docker")]
    [string]$Backend = "auto",
    # WSL distro to build in. Defaults to the WSL default distro; set this if
    # your default distro lacks the Debian build tooling (dpkg-dev, debhelper).
    [string]$Distro = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Blue }
function Write-Err($msg)  { Write-Host "error: $msg" -ForegroundColor Red }

function Test-Wsl {
    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) { return $false }
    # At least one distro installed?
    $distros = (wsl -l -q) 2>$null
    return [bool]$distros
}

function Invoke-WslBuild {
    Write-Step "Building via WSL"
    # Translate the Windows repo path to a WSL /mnt path. Feed wslpath a
    # forward-slash path so backslashes are never lost in arg passing.
    $distroArgs = if ($Distro) { @("-d", $Distro) } else { @() }
    $fwd = $RepoRoot -replace '\\', '/'
    $wslPath = (wsl @distroArgs wslpath -a "$fwd").Trim()
    $verArg = if ($Version) { $Version } else { "" }
    # Install tooling if missing, then run build.sh.
    $script = @"
set -e
cd '$wslPath'
if ! command -v dpkg-buildpackage >/dev/null 2>&1; then
    echo '==> installing build tooling (sudo may prompt)'
    sudo apt-get update -qq
    sudo apt-get install -y -qq --no-install-recommends dpkg-dev debhelper fakeroot devscripts
fi
chmod +x build.sh
./build.sh '$verArg'
"@
    wsl @distroArgs -e bash -lc $script
    if ($LASTEXITCODE -ne 0) { throw "WSL build failed (exit $LASTEXITCODE)" }
}

function Invoke-DockerBuild {
    Write-Step "Building via Docker"
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker not found and no WSL distro available. Install Docker Desktop or a WSL distro."
    }
    $env:OOB_FORCE_DOCKER = "1"
    # build.sh handles the docker invocation itself; run it through bash if
    # available, otherwise invoke docker directly here.
    if (Get-Command bash -ErrorAction SilentlyContinue) {
        $verArg = if ($Version) { $Version } else { "" }
        bash -c "cd '$($RepoRoot -replace '\\','/')' && OOB_FORCE_DOCKER=1 ./build.sh $verArg"
    } else {
        $ver = if ($Version) { $Version } else { "0.0.0" }
        docker run --rm -v "${RepoRoot}:/src" -w /src debian:bookworm-slim bash -c @"
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends dpkg-dev debhelper fakeroot devscripts >/dev/null
chmod +x build.sh
./build.sh '$ver'
"@
    }
    if ($LASTEXITCODE -ne 0) { throw "Docker build failed (exit $LASTEXITCODE)" }
}

Write-Step "oob-usb-serial Windows build wrapper"

switch ($Backend) {
    "wsl"    { Invoke-WslBuild }
    "docker" { Invoke-DockerBuild }
    default  {
        if (Test-Wsl) { Invoke-WslBuild }
        else { Invoke-DockerBuild }
    }
}

Write-Step "Done. Artifact in dist\"
Get-ChildItem -Path (Join-Path $RepoRoot "dist") -Filter *.deb -ErrorAction SilentlyContinue |
    ForEach-Object { Write-Host "  $($_.Name)" }
