# setup_cypherium.ps1
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Write-Host "[0/10] setup environment..."

function Add-PathForCurrentSession {
    param([string]$PathToAdd)

    if ((Test-Path $PathToAdd) -and ($env:PATH -notlike "*$PathToAdd*")) {
        $env:PATH = "$PathToAdd;$env:PATH"
    }
}

function Add-UserPath {
    param([string]$PathToAdd)

    if (-not (Test-Path $PathToAdd)) {
        return
    }

    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($null -eq $UserPath) {
        $UserPath = ""
    }

    if ($UserPath -notlike "*$PathToAdd*") {
        [Environment]::SetEnvironmentVariable("Path", "$PathToAdd;$UserPath", "User")
    }

    Add-PathForCurrentSession $PathToAdd
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
        throw "winget is not available. Please install App Installer from Microsoft Store or install dependencies manually."
    }

    Write-Host "Installing $Id via winget..."

    winget install `
        --id $Id `
        -e `
        --source winget `
        --accept-package-agreements `
        --accept-source-agreements
}

function Find-GoBin {
    $Candidates = @(
        (Join-Path $HOME "go-sdk\go1.26.2\bin"),
        (Join-Path $HOME "go-sdk\go1.20.14\bin"),
        (Join-Path $HOME "go-sdk\go1.24.1\bin"),
        "C:\Program Files\Go\bin"
    )

    foreach ($Path in $Candidates) {
        if (Test-Path (Join-Path $Path "go.exe")) {
            return $Path
        }
    }

    return $null
}

function Clone-IfMissing {
    param(
        [string]$Path,
        [string]$Url
    )

    if (-not (Test-Path $Path)) {
        $Parent = Split-Path -Parent $Path
        New-Item -ItemType Directory -Force $Parent | Out-Null

        git clone $Url $Path

        if ($LASTEXITCODE -ne 0) {
            throw "git clone failed: $Url"
        }
    }
}

$env:GOPATH = Join-Path $HOME "go"
$env:GO111MODULE = "off"
$env:GOFLAGS = ""

[Environment]::SetEnvironmentVariable("GOPATH", $env:GOPATH, "User")
[Environment]::SetEnvironmentVariable("GO111MODULE", "off", "User")

New-Item -ItemType Directory -Force $env:GOPATH | Out-Null

Add-PathForCurrentSession "C:\Program Files\Git\cmd"
Add-PathForCurrentSession "C:\Program Files\Go\bin"
Add-PathForCurrentSession "$env:GOPATH\bin"
Add-PathForCurrentSession "C:\Python312"
Add-PathForCurrentSession "C:\Python312\Scripts"
Add-PathForCurrentSession "C:\Program Files\nodejs"
Add-PathForCurrentSession "$env:APPDATA\npm"
Add-PathForCurrentSession "C:\msys64\mingw64\bin"
Add-PathForCurrentSession "C:\msys64\usr\bin"

$GoBin = Find-GoBin
if ($null -ne $GoBin) {
    Add-PathForCurrentSession $GoBin
}

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
    Add-PathForCurrentSession "C:\Program Files\nodejs"
    Add-PathForCurrentSession "$env:APPDATA\npm"
}

if (-not (Test-Path "C:\msys64")) {
    Write-Host "MSYS2 is not installed. Installing MSYS2..."
    Winget-Install "MSYS2.MSYS2"
}

Add-PathForCurrentSession "C:\Program Files\Git\cmd"
Add-PathForCurrentSession "C:\Program Files\Go\bin"
Add-PathForCurrentSession "$env:GOPATH\bin"
Add-PathForCurrentSession "C:\Python312"
Add-PathForCurrentSession "C:\Python312\Scripts"
Add-PathForCurrentSession "C:\Program Files\nodejs"
Add-PathForCurrentSession "$env:APPDATA\npm"
Add-PathForCurrentSession "C:\msys64\mingw64\bin"
Add-PathForCurrentSession "C:\msys64\usr\bin"

Add-UserPath "C:\Program Files\Git\cmd"
Add-UserPath "C:\Program Files\Go\bin"
Add-UserPath "$env:GOPATH\bin"
Add-UserPath "C:\Python312"
Add-UserPath "C:\Python312\Scripts"
Add-UserPath "C:\Program Files\nodejs"
Add-UserPath "$env:APPDATA\npm"
Add-UserPath "C:\msys64\mingw64\bin"
Add-UserPath "C:\msys64\usr\bin"

if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
    throw "git.exe was not found in PATH."
}

if (-not (Get-Command go.exe -ErrorAction SilentlyContinue)) {
    throw "go.exe was not found in PATH."
}

if (-not (Get-Command python.exe -ErrorAction SilentlyContinue)) {
    throw "python.exe was not found in PATH."
}

if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) {
    throw "node.exe was not found in PATH."
}

if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
    throw "npm.cmd was not found in PATH."
}

Write-Host "Git:"
git --version

Write-Host "Go:"
go version

Write-Host "Python:"
python --version

Write-Host "Node.js:"
node -v

Write-Host "npm:"
npm -v

Write-Host "[2/10] install/check MSYS2 packages..."

$Bash = "C:\msys64\usr\bin\bash.exe"

if (-not (Test-Path $Bash)) {
    throw "MSYS2 bash was not found at $Bash."
}

& $Bash -lc "pacman -Sy --noconfirm make git mingw-w64-x86_64-gcc mingw-w64-x86_64-openssl mingw-w64-x86_64-gmp"

if ($LASTEXITCODE -ne 0) {
    throw "MSYS2 package install failed with exit code $LASTEXITCODE"
}

Write-Host "[3/10] install/check pm2..."

npm install -g pm2

Add-PathForCurrentSession "$env:APPDATA\npm"
Add-UserPath "$env:APPDATA\npm"

if (-not (Get-Command pm2.cmd -ErrorAction SilentlyContinue)) {
    throw "pm2.cmd was not found in PATH."
}

pm2 -v

Write-Host "[4/10] clone/update cypher repo..."

$CypheriumRoot = Join-Path $env:GOPATH "src\github.com\cypherium"
$CypherDir = Join-Path $CypheriumRoot "cypher"

New-Item -ItemType Directory -Force $CypheriumRoot | Out-Null
Set-Location $CypheriumRoot

if (-not (Test-Path $CypherDir)) {
    git clone https://github.com/CypherTroopers/cypher.git
}

Set-Location $CypherDir

git fetch --all
git checkout ecdsa_1.1_test_colossus-Xv2test
git pull --ff-only

Write-Host "[5/10] clone GOPATH dependencies..."

$GopathSrc = Join-Path $env:GOPATH "src"

Clone-IfMissing `
    -Path (Join-Path $GopathSrc "github.com\VictoriaMetrics\fastcache") `
    -Url "https://github.com/VictoriaMetrics/fastcache.git"

Clone-IfMissing `
    -Path (Join-Path $GopathSrc "github.com\shirou\gopsutil") `
    -Url "https://github.com/shirou/gopsutil.git"

Clone-IfMissing `
    -Path (Join-Path $GopathSrc "github.com\dlclark\regexp2") `
    -Url "https://github.com/dlclark/regexp2.git"

Clone-IfMissing `
    -Path (Join-Path $GopathSrc "github.com\go-sourcemap\sourcemap") `
    -Url "https://github.com/go-sourcemap/sourcemap.git"

Clone-IfMissing `
    -Path (Join-Path $GopathSrc "github.com\tklauser\go-sysconf") `
    -Url "https://github.com/tklauser/go-sysconf.git"

Clone-IfMissing `
    -Path (Join-Path $GopathSrc "github.com\tklauser\numcpus") `
    -Url "https://github.com/tklauser/numcpus.git"

Clone-IfMissing `
    -Path (Join-Path $GopathSrc "golang.org\x\sys") `
    -Url "https://github.com/golang/sys.git"

Clone-IfMissing `
    -Path (Join-Path $GopathSrc "github.com\naoina\toml") `
    -Url "https://github.com/naoina/toml.git"

Clone-IfMissing `
    -Path (Join-Path $GopathSrc "github.com\naoina\go-stringutil") `
    -Url "https://github.com/naoina/go-stringutil.git"

Clone-IfMissing `
    -Path (Join-Path $GopathSrc "gopkg.in\urfave\cli.v1") `
    -Url "https://gopkg.in/urfave/cli.v1"

Clone-IfMissing `
    -Path (Join-Path $GopathSrc "github.com\yusufpapurcu\wmi") `
    -Url "https://github.com/yusufpapurcu/wmi.git"

Clone-IfMissing `
    -Path (Join-Path $GopathSrc "github.com\go-ole\go-ole") `
    -Url "https://github.com/go-ole/go-ole.git"

$Regexp2Dir = Join-Path $GopathSrc "github.com\dlclark\regexp2"
Set-Location $Regexp2Dir
git fetch --tags
git checkout v1.1.8

Write-Host "[6/10] patch dependencies..."

Set-Location $CypherDir

$VendorRegexp2 = Join-Path $CypherDir "vendor\github.com\dlclark\regexp2"
$VendorDlclark = Join-Path $CypherDir "vendor\github.com\dlclark"

Remove-Item -Recurse -Force $VendorRegexp2 -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $VendorDlclark | Out-Null
Copy-Item -Path $Regexp2Dir -Destination $VendorDlclark -Recurse -Force

$DukLoggingPath = Join-Path $CypherDir "vendor\gopkg.in\olebedev\go-duktape.v3\duk_logging.c"

if (Test-Path $DukLoggingPath) {
    $Content = Get-Content -Raw $DukLoggingPath

    $Content = $Content.Replace('duk_uint8_t date_buf[32]', 'duk_uint8_t date_buf[64]')
    $Content = $Content.Replace('snprintf((char *) date_buf, sizeof(date_buf),, ', 'snprintf((char *) date_buf, sizeof(date_buf), ')
    $Content = $Content.Replace('sprintf((char *) date_buf, ', 'snprintf((char *) date_buf, sizeof(date_buf), ')

    Set-Content -Path $DukLoggingPath -Value $Content -NoNewline
}

Write-Host "[7/10] restore BLS/MCL libs and build cypher.exe..."

Set-Location $CypherDir

$BinDir = Join-Path $CypherDir "build\bin"
$MingwBin = "C:\msys64\mingw64\bin"

New-Item -ItemType Directory -Force $BinDir | Out-Null

if (-not (Test-Path ".\crypto\bls\lib\win")) {
    throw "crypto\bls\lib\win was not found."
}

git checkout -- .\crypto\bls\lib\win 2>$null

Remove-Item -Force ".\crypto\bls\lib\*.a" -ErrorAction SilentlyContinue
Copy-Item ".\crypto\bls\lib\win\*.a" ".\crypto\bls\lib\" -Force

Write-Host "Current BLS/MCL libs:"
Get-ChildItem ".\crypto\bls\lib\*.a" | Format-Table -AutoSize

$env:GOPATH = Join-Path $HOME "go"
$env:GO111MODULE = "off"
$env:GOFLAGS = ""
$env:CGO_ENABLED = "1"
$env:CC = Join-Path $MingwBin "gcc.exe"
$env:CXX = Join-Path $MingwBin "g++.exe"
$env:CGO_LDFLAGS_ALLOW = ".*"
$env:CGO_CFLAGS_ALLOW = ".*"
$env:CGO_CXXFLAGS_ALLOW = ".*"
$env:PATH = "$MingwBin;$env:PATH"

Remove-Item -Force ".\build\bin\cypher.exe" -ErrorAction SilentlyContinue

Write-Host "go env:"
go env GOPATH GO111MODULE GOFLAGS CGO_ENABLED CC CXX

Write-Host "Building cypher.exe..."

go build -o ".\build\bin\cypher.exe" ".\cmd\cypher"

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
    if (Test-Path $src) {
        Copy-Item $src $BinDir -Force
    } else {
        Write-Host "WARNING: DLL not found: $src"
    }
}

$CypherExe = Join-Path $CypherDir "build\bin\cypher.exe"

if (-not (Test-Path $CypherExe)) {
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

if (-not (Test-Path $CypherExe)) {
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

Write-Host ""
Write-Host "PM2 started cypher-node."
Write-Host "Check status with:"
Write-Host "  pm2 status"
Write-Host "  pm2 logs cypher-node"
Write-Host ""
Write-Host "Done."
