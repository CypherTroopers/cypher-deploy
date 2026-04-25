[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

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
        throw "winget is not available. Install App Installer from Microsoft Store or install dependencies manually."
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

function Refresh-PathFromRegistry {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $combined = @($machine, $user, $env:Path) -join ";"
    $parts = $combined.Split(";") | Where-Object { $_ -and $_.Trim() -ne "" } | Select-Object -Unique
    $env:Path = ($parts -join ";")
}

function Resolve-NpmCommand {
    $cmd = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    $candidates = @(
        (Join-Path $env:ProgramFiles "nodejs\npm.cmd"),
        $(if ($programFilesX86) { Join-Path $programFilesX86 "nodejs\npm.cmd" }),
        (Join-Path $env:APPDATA "npm\npm.cmd")
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            Add-PathForCurrentSession (Split-Path -Parent $candidate)
            return $candidate
        }
    }

    return $null
}

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

Write-Host "[1/10] install/check Windows dependencies..."

if (-not (Ensure-Command git "Git is not installed. Installing Git...")) {
    Winget-Install "Git.Git"
    Add-PathForCurrentSession "C:\Program Files\Git\cmd"
}

if (-not (Ensure-Command go "Go is not installed. Installing Go...")) {
    Winget-Install "GoLang.Go"
    Add-PathForCurrentSession "C:\Program Files\Go\bin"
}

if (-not (Ensure-Command python "Python is not installed. Installing Python 3.12...")) {
    Winget-Install "Python.Python.3.12"
    Add-PathForCurrentSession "C:\Python312"
    Add-PathForCurrentSession "C:\Python312\Scripts"
}

if (-not (Ensure-Command node "Node.js is not installed. Installing Node.js...")) {
    Winget-Install "OpenJS.NodeJS.LTS"
    Refresh-PathFromRegistry
    Add-PathForCurrentSession "C:\Program Files\nodejs"
    Add-PathForCurrentSession "$env:APPDATA\npm"
}

if (-not (Test-Path -LiteralPath "C:\msys64")) {
    Write-Host "MSYS2 is not installed. Installing MSYS2..."
    Winget-Install "MSYS2.MSYS2"
}

Refresh-PathFromRegistry
Add-PathForCurrentSession "C:\Program Files\nodejs"
Add-PathForCurrentSession "$env:APPDATA\npm"

if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) { throw "git.exe was not found in PATH." }
if (-not (Get-Command go.exe -ErrorAction SilentlyContinue)) { throw "go.exe was not found in PATH." }
if (-not (Get-Command python.exe -ErrorAction SilentlyContinue)) { throw "python.exe was not found in PATH." }
if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) { throw "node.exe was not found in PATH." }

$NpmCmd = Resolve-NpmCommand
if (-not $NpmCmd) {
    throw "npm.cmd was not found. Reopen PowerShell once, or ensure Node.js was installed with npm."
}

Write-Host "[2/10] install/check MSYS2 packages..."

$bash = "C:\msys64\usr\bin\bash.exe"
if (-not (Test-Path -LiteralPath $bash)) {
    throw "MSYS2 bash was not found at $bash."
}

& $bash -lc "pacman -Sy --noconfirm --needed make git mingw-w64-x86_64-gcc mingw-w64-x86_64-openssl mingw-w64-x86_64-gmp"
if ($LASTEXITCODE -ne 0) {
    throw "MSYS2 package install failed with exit code $LASTEXITCODE"
}

Write-Host "[3/10] install/check pm2..."

& $NpmCmd install -g pm2
Refresh-PathFromRegistry
Add-PathForCurrentSession "$env:APPDATA\npm"

if (-not (Get-Command pm2.cmd -ErrorAction SilentlyContinue)) {
    throw "pm2.cmd was not found in PATH."
}

Write-Host "[4/10] clone/update cypher repo..."

$CypheriumRoot = Join-Path $env:GOPATH "src\github.com\cypherium"
$CypherDir = Join-Path $CypheriumRoot "cypher"
New-Item -ItemType Directory -Force -Path $CypheriumRoot | Out-Null
Set-Location $CypheriumRoot

if (-not (Test-Path -LiteralPath $CypherDir)) {
    git clone https://github.com/CypherTroopers/cypher.git
    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed: CypherTroopers/cypher"
    }
}

Set-Location $CypherDir

& git fetch --all
if ($LASTEXITCODE -ne 0) { throw "git fetch failed" }

& git checkout ecdsa_1.1_test_colossus-Xv2test
if ($LASTEXITCODE -ne 0) { throw "git checkout failed" }

& git pull --ff-only
if ($LASTEXITCODE -ne 0) { throw "git pull failed" }

Write-Host "[5/10] clone GOPATH dependencies..."

$GopathSrc = Join-Path $env:GOPATH "src"

Clone-IfMissing -Path (Join-Path $GopathSrc "github.com\VictoriaMetrics\fastcache") -Url "https://github.com/VictoriaMetrics/fastcache.git"
Clone-IfMissing -Path (Join-Path $GopathSrc "github.com\shirou\gopsutil") -Url "https://github.com/shirou/gopsutil.git"
Clone-IfMissing -Path (Join-Path $GopathSrc "github.com\dlclark\regexp2") -Url "https://github.com/dlclark/regexp2.git"
Clone-IfMissing -Path (Join-Path $GopathSrc "github.com\go-sourcemap\sourcemap") -Url "https://github.com/go-sourcemap/sourcemap.git"
Clone-IfMissing -Path (Join-Path $GopathSrc "github.com\tklauser\go-sysconf") -Url "https://github.com/tklauser/go-sysconf.git"
Clone-IfMissing -Path (Join-Path $GopathSrc "github.com\tklauser\numcpus") -Url "https://github.com/tklauser/numcpus.git"
Clone-IfMissing -Path (Join-Path $GopathSrc "golang.org\x\sys") -Url "https://github.com/golang/sys.git"
Clone-IfMissing -Path (Join-Path $GopathSrc "github.com\naoina\toml") -Url "https://github.com/naoina/toml.git"
Clone-IfMissing -Path (Join-Path $GopathSrc "github.com\naoina\go-stringutil") -Url "https://github.com/naoina/go-stringutil.git"
Clone-IfMissing -Path (Join-Path $GopathSrc "gopkg.in\urfave\cli.v1") -Url "https://github.com/urfave/cli.git"
Clone-IfMissing -Path (Join-Path $GopathSrc "github.com\yusufpapurcu\wmi") -Url "https://github.com/yusufpapurcu/wmi.git"
Clone-IfMissing -Path (Join-Path $GopathSrc "github.com\go-ole\go-ole") -Url "https://github.com/go-ole/go-ole.git"

$Regexp2Dir = Join-Path $GopathSrc "github.com\dlclark\regexp2"
Set-Location $Regexp2Dir

& git fetch --tags
if ($LASTEXITCODE -ne 0) { throw "regexp2 git fetch failed" }

& git checkout v1.1.8
if ($LASTEXITCODE -ne 0) { throw "regexp2 git checkout v1.1.8 failed" }

Write-Host "[6/10] patch dependencies..."

Set-Location $CypherDir

$VendorRegexp2 = Join-Path $CypherDir "vendor\github.com\dlclark\regexp2"
$VendorDlclark = Join-Path $CypherDir "vendor\github.com\dlclark"

Remove-Item -Recurse -Force $VendorRegexp2 -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $VendorDlclark | Out-Null
Copy-Item -Path $Regexp2Dir -Destination $VendorDlclark -Recurse -Force

$DukLoggingPath = Join-Path $CypherDir "vendor\gopkg.in\olebedev\go-duktape.v3\duk_logging.c"
if (Test-Path -LiteralPath $DukLoggingPath) {
    $content = Get-Content -Raw -LiteralPath $DukLoggingPath
    $content = $content.Replace('duk_uint8_t date_buf[32]', 'duk_uint8_t date_buf[64]')
    $content = $content.Replace('sprintf((char *) date_buf, ', 'snprintf((char *) date_buf, sizeof(date_buf), ')
    Set-Content -LiteralPath $DukLoggingPath -Value $content -NoNewline
}

Write-Host "[7/10] restore BLS/MCL libs and build cypher.exe..."

Set-Location $CypherDir

$BinDir = Join-Path $CypherDir "build\bin"
$MingwBin = "C:\msys64\mingw64\bin"
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

if (-not (Test-Path -LiteralPath ".\crypto\bls\lib\win")) {
    throw "crypto\bls\lib\win was not found."
}

& git checkout -- .\crypto\bls\lib\win 2>$null

Remove-Item -Force ".\crypto\bls\lib\*.a" -ErrorAction SilentlyContinue
Copy-Item ".\crypto\bls\lib\win\*.a" ".\crypto\bls\lib\" -Force

$env:CGO_ENABLED = "1"
$env:CC = Join-Path $MingwBin "gcc.exe"
$env:CXX = Join-Path $MingwBin "g++.exe"
$env:CGO_LDFLAGS_ALLOW = ".*"
$env:CGO_CFLAGS_ALLOW = ".*"
$env:CGO_CXXFLAGS_ALLOW = ".*"
$env:PATH = "$MingwBin;$env:PATH"

Remove-Item -Force ".\build\bin\cypher.exe" -ErrorAction SilentlyContinue

& go build -o ".\build\bin\cypher.exe" ".\cmd\cypher"
if ($LASTEXITCODE -ne 0) {
    throw "go build failed with exit code $LASTEXITCODE"
}

Write-Host "[8/10] copy runtime DLLs and verify cypher.exe..."

$dlls = @(
    "libcrypto-3-x64.dll",
    "libssl-3-x64.dll",
    "libgmp-10.dll",
    "libstdc++-6.dll",
    "libgcc_s_seh-1.dll",
    "libwinpthread-1.dll"
)

foreach ($dll in $dlls) {
    $src = Join-Path $MingwBin $dll
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination $BinDir -Force
    }
}

$CypherExe = Join-Path $CypherDir "build\bin\cypher.exe"
if (-not (Test-Path -LiteralPath $CypherExe)) {
    throw "cypher.exe was not found: $CypherExe"
}

& $CypherExe version
if ($LASTEXITCODE -ne 0) {
    throw "cypher.exe version failed with exit code $LASTEXITCODE"
}

Write-Host "[9/10] init chain data..."

Set-Location $CypherDir

& $CypherExe --datadir chaindbname init .\genesistest.json
if ($LASTEXITCODE -ne 0) {
    throw "cypher init failed with exit code $LASTEXITCODE"
}

Write-Host "[10/10] create start script and register pm2..."

$StartScript = Join-Path $CypherDir "start-cypher.ps1"
$StartScriptContent = @'
$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot

$CypherExe = Join-Path $PSScriptRoot "build\bin\cypher.exe"
if (-not (Test-Path -LiteralPath $CypherExe)) {
    throw "cypher.exe was not found: $CypherExe"
}

$ExtIp = ""
try {
    $ExtIp = (& curl.exe -4 -s ifconfig.io).Trim()
} catch {
    $ExtIp = ""
}

if (-not $ExtIp) {
    $ExtIp = (Invoke-RestMethod -Uri "https://ifconfig.io/ip").Trim()
}

if (-not $ExtIp) {
    throw "Failed to get external IPv4 address."
}

& $CypherExe `
  --verbosity 4 `
  --rnetport 7200 `
  --syncmode full `
  --nat "extip:$ExtIp" `
  --ws `
  --ws.addr "0.0.0.0" `
  --ws.port 9251 `
  --ws.origins "*" `
  --metrics `
  --http `
  --http.addr "0.0.0.0" `
  --http.port 8000 `
  --http.api "eth,web3,net,txpool" `
  --http.corsdomain "*" `
  --port 6000 `
  --datadir chaindbname `
  --networkid 12367 `
  --gcmode archive `
  --bootnodes "enode://1300eb515ce5ae1167f05cc2123c8ca7100cb86cfefc39d761e26ce19ba14535b233e9fc4c263444cc4c5934058eb9daa9cf7c4f9c40cbff19ee83055284c718@161.97.184.220:6000" `
  console
'@

Set-Content -Path $StartScript -Value $StartScriptContent -Encoding UTF8

cmd /c "pm2 delete cypher-node 2>nul"

pm2 start powershell.exe --name cypher-node -- -NoProfile -ExecutionPolicy Bypass -File "$StartScript"
if ($LASTEXITCODE -ne 0) {
    throw "pm2 start failed with exit code $LASTEXITCODE"
}

pm2 save

Write-Host "Done. Use: pm2 status / pm2 logs cypher-node"
