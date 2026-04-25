# setup_cypherium.ps1
#requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Windows 判定（PowerShell 5.1対応）
if ($env:OS -ne "Windows_NT") {
    throw "This script must be run on Windows."
}

Write-Host "[0/10] setup environment..."

function Add-PathForCurrentSession {
    param([string]$PathToAdd)

    if ((Test-Path -LiteralPath $PathToAdd) -and ($env:PATH -notlike "*$PathToAdd*")) {
        $env:PATH = "$PathToAdd;$env:PATH"
    }
}

function Ensure-Command {
    param(
        [string]$Command,
        [string]$InstallMessage
    )

    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        Write-Host $InstallMessage
        return $false
    }

    return $true
}

function Winget-Install {
    param([string]$Id)

    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw "winget is not available."
    }

    Write-Host "Installing $Id via winget..."

    winget install `
        --id $Id `
        -e `
        --source winget `
        --accept-package-agreements `
        --accept-source-agreements
}

function Clone-IfMissing {
    param(
        [string]$Path,
        [string]$Url
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        $parent = Split-Path -Parent $Path
        New-Item -ItemType Directory -Force -Path $parent | Out-Null

        git clone $Url $Path
        if ($LASTEXITCODE -ne 0) {
            throw "git clone failed: $Url"
        }
    }
}

# Build env
$env:GOPATH = Join-Path $HOME "go"
$env:GO111MODULE = "off"
$env:GOFLAGS = ""
New-Item -ItemType Directory -Force -Path $env:GOPATH | Out-Null

Add-PathForCurrentSession "C:\Program Files\Git\cmd"
Add-PathForCurrentSession "C:\Program Files\Go\bin"
Add-PathForCurrentSession "$env:GOPATH\bin"
Add-PathForCurrentSession "C:\Python312"
Add-PathForCurrentSession "C:\Python312\Scripts"
Add-PathForCurrentSession "C:\Program Files\nodejs"
Add-PathForCurrentSession "$env:APPDATA\npm"
Add-PathForCurrentSession "C:\msys64\mingw64\bin"
Add-PathForCurrentSession "C:\msys64\usr\bin"

Write-Host "[1/10] install/check dependencies..."

if (-not (Ensure-Command git "Installing Git...")) {
    Winget-Install "Git.Git"
    Add-PathForCurrentSession "C:\Program Files\Git\cmd"
}

if (-not (Ensure-Command go "Installing Go...")) {
    Winget-Install "GoLang.Go"
    Add-PathForCurrentSession "C:\Program Files\Go\bin"
}

if (-not (Ensure-Command python "Installing Python...")) {
    Winget-Install "Python.Python.3.12"
}

if (-not (Ensure-Command node "Installing Node.js...")) {
    Winget-Install "OpenJS.NodeJS.LTS"
}

if (-not (Test-Path "C:\msys64")) {
    Winget-Install "MSYS2.MSYS2"
}

Write-Host "[2/10] install MSYS2 packages..."

$bash = "C:\msys64\usr\bin\bash.exe"
if (-not (Test-Path $bash)) {
    throw "MSYS2 bash not found"
}

& $bash -lc "pacman -Sy --noconfirm --needed make git mingw-w64-x86_64-gcc mingw-w64-x86_64-openssl mingw-w64-x86_64-gmp"
if ($LASTEXITCODE -ne 0) { throw "MSYS2 failed" }

Write-Host "[3/10] install pm2..."
npm install -g pm2

Write-Host "[4/10] clone cypher..."

$root = Join-Path $env:GOPATH "src\github.com\cypherium"
$repo = Join-Path $root "cypher"

New-Item -ItemType Directory -Force -Path $root | Out-Null
Set-Location $root

if (-not (Test-Path $repo)) {
    git clone https://github.com/CypherTroopers/cypher.git
}

Set-Location $repo
git fetch --all
git checkout ecdsa_1.1_test_colossus-Xv2test
git pull --ff-only

Write-Host "[5/10] fix regexp2..."

$src = Join-Path $env:GOPATH "src\github.com\dlclark\regexp2"
Clone-IfMissing $src "https://github.com/dlclark/regexp2.git"

Set-Location $src
git checkout v1.1.8

Set-Location $repo
Remove-Item -Recurse -Force ".\vendor\github.com\dlclark\regexp2" -ErrorAction SilentlyContinue
Copy-Item $src ".\vendor\github.com\dlclark\" -Recurse -Force

Write-Host "[6/10] build..."

$env:CGO_ENABLED = "1"
$env:CC = "C:\msys64\mingw64\bin\gcc.exe"
$env:CXX = "C:\msys64\mingw64\bin\g++.exe"

go build -o ".\build\bin\cypher.exe" ".\cmd\cypher"
if ($LASTEXITCODE -ne 0) { throw "build failed" }

Write-Host "[7/10] init..."

.\build\bin\cypher.exe --datadir chaindbname init .\genesistest.json

Write-Host "[8/10] create start script..."

$script = @'
$exe = ".\build\bin\cypher.exe"
$ip = (Invoke-RestMethod "https://ifconfig.io/ip").Trim()

& $exe `
--verbosity 4 `
--rnetport 7200 `
--nat "extip:$ip" `
--http --http.addr 0.0.0.0 --http.port 8000 --http.api "eth,web3,net,txpool" `
--port 6000 `
--datadir chaindbname `
--networkid 12367 `
console
'@

$script | Out-File ".\start.ps1" -Encoding utf8

Write-Host "[9/10] pm2 start..."
pm2 start powershell --name cypher -- -File .\start.ps1
pm2 save

Write-Host "[10/10] DONE"
