# setup_cypherium.ps1
# Run with Administrator PowerShell:
# powershell -ExecutionPolicy Bypass -File .\setup_cypherium.ps1

#requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$RepoUrl = "https://github.com/CypherTroopers/cypher.git",
    [string]$RepoBranch = "ecdsa_1.1_test_colossus-Xv2test",
    [string]$Gopath = "$env:USERPROFILE\go",
    [ValidateSet("mingw64", "ucrt64")]
    [string]$MsysFlavor = "mingw64",
    [string]$DataDir = "",
    [string]$GenesisFile = ""
)

$ErrorActionPreference = "Stop"

Write-Host "[0/8] setup environment..."

# ============================================================
# PowerShell safety check
# ============================================================

if (-not $PSVersionTable.PSVersion) {
    throw "This script must be run with PowerShell, not cmd.exe."
}

# ============================================================
# Paths and basic environment
# ============================================================

$env:GOPATH = $Gopath
$env:GO111MODULE = "off"
$env:CGO_ENABLED = "1"

$CypherRoot = Join-Path $env:GOPATH "src\github.com\cypherium"
$CypherDir = Join-Path $CypherRoot "cypher"
$MsysRoot = "C:\msys64"
$MsysBin = Join-Path $MsysRoot "$MsysFlavor\bin"
$MsysBash = Join-Path $MsysRoot "usr\bin\bash.exe"

if ([string]::IsNullOrWhiteSpace($DataDir)) {
    $DataDir = Join-Path $CypherDir "chaindata"
}

function Add-Path {
    param([string]$PathToAdd)

    if (Test-Path $PathToAdd) {
        if ($env:Path -notlike "*$PathToAdd*") {
            $env:Path = "$PathToAdd;$env:Path"
        }

        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ([string]::IsNullOrWhiteSpace($userPath)) {
            $userPath = ""
        }

        if ($userPath -notlike "*$PathToAdd*") {
            if ([string]::IsNullOrWhiteSpace($userPath)) {
                [Environment]::SetEnvironmentVariable("Path", $PathToAdd, "User")
            } else {
                [Environment]::SetEnvironmentVariable("Path", "$PathToAdd;$userPath", "User")
            }
        }
    }
}

function Install-WingetPackage {
    param(
        [string[]]$Ids,
        [string]$Name,
        [string[]]$Commands = @(),
        [string[]]$Paths = @()
    )

    foreach ($Command in $Commands) {
        if (Get-Command $Command -ErrorAction SilentlyContinue) {
            Write-Host "$Name already installed. Found command: $Command"
            return
        }
    }

    foreach ($Path in $Paths) {
        if (Test-Path $Path) {
            Write-Host "$Name already installed. Found path: $Path"
            return
        }
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget was not found. Please update App Installer from Microsoft Store."
    }

    foreach ($Id in $Ids) {
        Write-Host "Installing $Name using winget id: $Id"
        winget install --id $Id -e --accept-source-agreements --accept-package-agreements

        foreach ($Command in $Commands) {
            if (Get-Command $Command -ErrorAction SilentlyContinue) {
                Write-Host "$Name installed successfully. Found command: $Command"
                return
            }
        }

        foreach ($Path in $Paths) {
            if (Test-Path $Path) {
                Write-Host "$Name installed successfully. Found path: $Path"
                return
            }
        }

        if ($LASTEXITCODE -eq 0) {
            Write-Host "$Name installed or already exists."
            return
        }

        Write-Host "WARNING: winget returned exit code $LASTEXITCODE for $Id. Trying next candidate if available..."
    }

    throw "Failed to install or detect $Name."
}

function Require-Command {
    param([string]$Command)

    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Command"
    }
}

function Get-GoBinPath {
    $preferredGo = "C:\Program Files\Go\bin\go.exe"

    if (Test-Path $preferredGo) {
        return Split-Path $preferredGo -Parent
    }

    $goCommand = Get-Command go.exe -ErrorAction Stop
    return Split-Path $goCommand.Source -Parent
}

function Assert-GoVersionSupported {
    param([string]$GoExe)

    $goVersion = & $GoExe version
    Write-Host $goVersion

    if ($goVersion -notmatch 'go(\d+)\.(\d+)') {
        throw "Could not parse Go version: $goVersion"
    }

    $major = [int]$Matches[1]
    $minor = [int]$Matches[2]

    if (($major -lt 1) -or (($major -eq 1) -and ($minor -lt 13))) {
        throw "Go 1.13 or newer is required. Found: $goVersion"
    }
}

function Set-GoEnvironment {
    param([string]$GoBin)

    if (-not (Test-Path "$GoBin\go.exe")) {
        throw "go.exe not found: $GoBin\go.exe"
    }

    $goRoot = Split-Path $GoBin -Parent
    if (-not (Test-Path "$goRoot\src\runtime\runtime.go")) {
        throw "GOROOT is not valid: $goRoot"
    }

    $env:GOROOT = $goRoot
    $env:GOPATH = $Gopath
    $env:GO111MODULE = "off"
    $env:CGO_ENABLED = "1"

    [Environment]::SetEnvironmentVariable("GOROOT", $env:GOROOT, "User")
    [Environment]::SetEnvironmentVariable("GOPATH", $env:GOPATH, "User")
    [Environment]::SetEnvironmentVariable("GO111MODULE", "off", "User")
    [Environment]::SetEnvironmentVariable("CGO_ENABLED", "1", "User")

    Add-Path $GoBin

    Write-Host "Go environment:"
    Write-Host "  GOROOT=$env:GOROOT"
    Write-Host "  GOPATH=$env:GOPATH"
    Write-Host "  GO111MODULE=$env:GO111MODULE"
    Write-Host "  CGO_ENABLED=$env:CGO_ENABLED"
}

function Invoke-CheckedNativeCommand {
    param(
        [scriptblock]$Command,
        [string]$ErrorMessage
    )

    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw $ErrorMessage
    }
}

# ============================================================
# Admin check
# ============================================================

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    throw "Please run this script as Administrator PowerShell."
}

# ============================================================
# [1/8] Install required Windows tools
# ============================================================

Write-Host "[1/8] install required Windows tools..."

Install-WingetPackage `
    -Ids @("Git.Git") `
    -Name "Git" `
    -Commands @("git.exe") `
    -Paths @("C:\Program Files\Git\cmd\git.exe", "C:\Program Files\Git\bin\git.exe")

Install-WingetPackage `
    -Ids @("GoLang.Go") `
    -Name "Go" `
    -Commands @("go.exe") `
    -Paths @("C:\Program Files\Go\bin\go.exe")

Install-WingetPackage `
    -Ids @("MSYS2.MSYS2") `
    -Name "MSYS2" `
    -Commands @() `
    -Paths @("C:\msys64\usr\bin\bash.exe")

Add-Path "C:\Program Files\Git\cmd"
Add-Path "C:\Program Files\Git\bin"
Add-Path "C:\Program Files\Go\bin"
Add-Path $MsysBin
Add-Path "C:\msys64\usr\bin"

$env:Path = "C:\Program Files\Go\bin;$MsysBin;C:\msys64\usr\bin;C:\Program Files\Git\cmd;C:\Program Files\Git\bin;$env:Path"

Require-Command git
Require-Command go

$goBin = Get-GoBinPath
Set-GoEnvironment -GoBin $goBin
$goExe = Join-Path $goBin "go.exe"
Assert-GoVersionSupported -GoExe $goExe

git --version

# ============================================================
# [2/8] Install MSYS2 CGO dependencies
# ============================================================

Write-Host "[2/8] install MSYS2 CGO dependencies..."

if (-not (Test-Path $MsysBash)) {
    throw "MSYS2 bash not found: $MsysBash"
}

$mingwPrefix = if ($MsysFlavor -eq "ucrt64") { "mingw-w64-ucrt-x86_64" } else { "mingw-w64-x86_64" }

& $MsysBash -lc "pacman -Syuu --noconfirm || true"
& $MsysBash -lc "pacman -Suu --noconfirm || true"
& $MsysBash -lc "pacman -S --needed --noconfirm base-devel git make pkgconf ${mingwPrefix}-gcc ${mingwPrefix}-openssl ${mingwPrefix}-gmp"

if (-not (Test-Path (Join-Path $MsysBin "gcc.exe"))) {
    throw "gcc.exe not found in MSYS2 $MsysFlavor bin: $MsysBin"
}

$env:CC = Join-Path $MsysBin "gcc.exe"
$env:CXX = Join-Path $MsysBin "g++.exe"

& $env:CC --version

# ============================================================
# [3/8] Clone cypher under GOPATH import path
# ============================================================

Write-Host "[3/8] clone cypher under GOPATH import path..."

New-Item -ItemType Directory -Force -Path $CypherRoot | Out-Null

if (-not (Test-Path $CypherDir)) {
    git clone $RepoUrl $CypherDir
} else {
    Write-Host "Already exists: $CypherDir"
}

Set-Location $CypherDir

git fetch --all --tags

if (-not [string]::IsNullOrWhiteSpace($RepoBranch)) {
    git checkout $RepoBranch
}

Write-Host "Repository:"
Write-Host "  $CypherDir"
Write-Host "Git branch:"
git branch --show-current
Write-Host "Git commit:"
git rev-parse HEAD

# ============================================================
# [4/8] Disable Go modules and enable CGO
# ============================================================

Write-Host "[4/8] configure Go GOPATH mode..."

go env -w GO111MODULE=off
go env -w CGO_ENABLED=1
go env -w GOPATH="$env:GOPATH"

$env:GO111MODULE = "off"
$env:CGO_ENABLED = "1"
$env:GOPATH = $Gopath

Write-Host "GO111MODULE=$(go env GO111MODULE)"
Write-Host "CGO_ENABLED=$(go env CGO_ENABLED)"
Write-Host "GOPATH=$(go env GOPATH)"

# ============================================================
# [5/8] Copy Windows BLS libraries
# ============================================================

Write-Host "[5/8] copy Windows BLS libraries..."

Set-Location $CypherDir

if (Test-Path ".\crypto\bls\lib\win") {
    Copy-Item ".\crypto\bls\lib\win\*.a" ".\crypto\bls\lib\" -Force
    Write-Host "Copied Windows BLS .a files into .\crypto\bls\lib"
} else {
    Write-Host "WARNING: .\crypto\bls\lib\win was not found. Continuing because .\crypto\bls\lib may already contain the required libraries."
}

# ============================================================
# [6/8] Build cypher via build/ci.go install
# ============================================================

Write-Host "[6/8] build cypher with go run .\build\ci.go install .\cmd\cypher..."

Set-Location $CypherDir

$env:Path = "$goBin;$MsysBin;C:\msys64\usr\bin;C:\Program Files\Git\cmd;C:\Program Files\Git\bin;$env:Path"
$env:CC = Join-Path $MsysBin "gcc.exe"
$env:CXX = Join-Path $MsysBin "g++.exe"
$env:CGO_CFLAGS_ALLOW = ".*"
$env:CGO_LDFLAGS_ALLOW = ".*"

Remove-Item ".\build\bin" -Recurse -Force -ErrorAction SilentlyContinue

Invoke-CheckedNativeCommand `
    -Command { & $goExe run .\build\ci.go install .\cmd\cypher } `
    -ErrorMessage "cypher build failed. The command was: go run .\build\ci.go install .\cmd\cypher"

$CypherExe = Join-Path $CypherDir "build\bin\cypher.exe"

if (-not (Test-Path $CypherExe)) {
    throw "cypher.exe was not created at expected build script output path: $CypherExe"
}

Write-Host "cypher.exe created:"
Get-Item $CypherExe

# ============================================================
# [7/8] Copy MSYS2 runtime DLLs and verify binary
# ============================================================

Write-Host "[7/8] copy runtime DLLs and verify cypher.exe..."

$dlls = @(
    "libcrypto-3-x64.dll",
    "libssl-3-x64.dll",
    "libgmp-10.dll",
    "libstdc++-6.dll",
    "libgcc_s_seh-1.dll",
    "libwinpthread-1.dll",
    "libzstd.dll",
    "zlib1.dll"
)

foreach ($dll in $dlls) {
    $src = Join-Path $MsysBin $dll

    if (Test-Path $src) {
        Copy-Item $src ".\build\bin\" -Force
        Write-Host "Copied: $dll"
    } else {
        Write-Host "WARNING: DLL not found in $MsysBin: $dll"
    }
}

$env:Path = "$CypherDir\build\bin;$MsysBin;C:\msys64\usr\bin;$goBin;$env:Path"

& $CypherExe version
& $CypherExe help

# ============================================================
# [8/8] Create data directory and initialize genesis
# ============================================================

Write-Host "[8/8] create data directory and initialize genesis..."

Set-Location $CypherDir
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

if ([string]::IsNullOrWhiteSpace($GenesisFile)) {
    if (Test-Path ".\genesis.json") {
        $GenesisFile = Join-Path $CypherDir "genesis.json"
    } elseif (Test-Path ".\genesistest.json") {
        $GenesisFile = Join-Path $CypherDir "genesistest.json"
    } else {
        throw "No genesis file was found. Pass -GenesisFile explicitly."
    }
}

if (-not (Test-Path $GenesisFile)) {
    throw "Genesis file not found: $GenesisFile"
}

Write-Host "Cypher dir:"
Write-Host "  $CypherDir"
Write-Host "Data dir:"
Write-Host "  $DataDir"
Write-Host "Genesis file:"
Write-Host "  $GenesisFile"
Write-Host "Genesis SHA256:"
Get-FileHash $GenesisFile -Algorithm SHA256 | Format-List

Invoke-CheckedNativeCommand `
    -Command { & $CypherExe --datadir $DataDir init $GenesisFile } `
    -ErrorMessage "cypher genesis init failed."

Write-Host ""
Write-Host "Done. Built binary:"
Write-Host "  $CypherExe"
Write-Host "Data directory:"
Write-Host "  $DataDir"
Write-Host ""
Write-Host "Example local start command:"
Write-Host "  .\build\bin\cypher.exe --datadir `"$DataDir`" --syncmode full --gcmode archive --http --http.addr 127.0.0.1 --ws --ws.addr 127.0.0.1 console"
