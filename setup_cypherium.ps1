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

function Convert-ToMsysPath {
    param([string]$WinPath)

    $Full = [System.IO.Path]::GetFullPath($WinPath)

    if ($Full -match '^([A-Za-z]):\\(.*)$') {
        $Drive = $matches[1].ToLowerInvariant()
        $Tail = $matches[2] -replace '\\', '/'
        return "/$Drive/$Tail"
    }

    throw "Cannot convert path to MSYS path: $WinPath"
}

$env:GOPATH = Join-Path $HOME "go"
$env:GO111MODULE = "off"

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

$Regexp2Dir = Join-Path $GopathSrc "github.com\dlclark\regexp2"
Set-Location $Regexp2Dir
git fetch --tags
git checkout v1.1.8

Write-Host "[6/10] patch dependencies and create Windows build script..."

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

$BuildWindowsScript = Join-Path $CypherDir "build\build_windows.ps1"
New-Item -ItemType Directory -Force (Join-Path $CypherDir "build") | Out-Null

@'
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$bashExe = "C:\msys64\usr\bin\bash.exe"
$mingwBin = "C:\msys64\mingw64\bin"
$binDir = Join-Path $repoRoot "build\bin"
$herumiRoot = Join-Path $repoRoot "build\herumi-bls"

function Convert-ToMsysPath {
    param([string]$WinPath)

    $Full = [System.IO.Path]::GetFullPath($WinPath)

    if ($Full -match '^([A-Za-z]):\\(.*)$') {
        $Drive = $matches[1].ToLowerInvariant()
        $Tail = $matches[2] -replace '\\', '/'
        return "/$Drive/$Tail"
    }

    throw "Cannot convert path: $WinPath"
}

function Invoke-BashChecked {
    param([string]$Script)

    & $bashExe -lc $Script

    if ($LASTEXITCODE -ne 0) {
        throw "bash command failed with exit code $LASTEXITCODE"
    }
}

New-Item -ItemType Directory -Force $binDir | Out-Null

if (-not (Test-Path "$herumiRoot\.git")) {
    git clone --recursive https://github.com/herumi/bls.git $herumiRoot

    if ($LASTEXITCODE -ne 0) {
        throw "git clone herumi/bls failed"
    }
}

$herumiMsys = Convert-ToMsysPath $herumiRoot

Write-Host "==> build mcl"

$mclBuild = @'
export MSYSTEM=MINGW64
export PATH=/mingw64/bin:/usr/bin:$PATH
cd __HERUMI_MSYS__/mcl
make clean || true
make -j4 OS=mingw64 lib/libmcl.a MCL_FP_BIT=256 MCL_FR_BIT=256
'@

$mclBuild = $mclBuild.Replace("__HERUMI_MSYS__", $herumiMsys)
Invoke-BashChecked $mclBuild

Write-Host "==> build bls"

$blsBuild = @'
export MSYSTEM=MINGW64
export PATH=/mingw64/bin:/usr/bin:$PATH
cd __HERUMI_MSYS__
make -j4 MCL_FP_BIT=256 MCL_FR_BIT=256 lib/libbls256.a
'@

$blsBuild = $blsBuild.Replace("__HERUMI_MSYS__", $herumiMsys)
Invoke-BashChecked $blsBuild

Write-Host "==> copy BLS/MCL libs"

Copy-Item "$herumiRoot\lib\libbls256.a" "$repoRoot\crypto\bls\lib\win\" -Force
Copy-Item "$herumiRoot\mcl\lib\libmcl.a" "$repoRoot\crypto\bls\lib\win\" -Force
Copy-Item "$repoRoot\crypto\bls\lib\win\*.a" "$repoRoot\crypto\bls\lib\" -Force

Write-Host "==> build cypher.exe"

$env:GOPATH = "C:\Users\Administrator\go"
$env:GO111MODULE = "off"
$env:CGO_ENABLED = "1"
$env:CC = "$mingwBin\gcc.exe"
$env:CXX = "$mingwBin\g++.exe"
$env:CGO_LDFLAGS_ALLOW = ".*"
$env:CGO_CFLAGS_ALLOW = ".*"
$env:CGO_CXXFLAGS_ALLOW = ".*"
$env:PATH = "$mingwBin;$env:PATH"

Set-Location $repoRoot

Remove-Item -Force ".\build\bin\cypher.exe" -ErrorAction SilentlyContinue

go build -o ".\build\bin\cypher.exe" ".\cmd\cypher"

if ($LASTEXITCODE -ne 0) {
    throw "go build failed with exit code $LASTEXITCODE"
}

Write-Host "==> copy runtime DLLs"

$dlls = @(
    "libcrypto-3-x64.dll",
    "libssl-3-x64.dll",
    "libgmp-10.dll",
    "libstdc++-6.dll",
    "libgcc_s_seh-1.dll",
    "libwinpthread-1.dll"
)

foreach ($dll in $dlls) {
    Copy-Item "$mingwBin\$dll" "$binDir\" -Force -ErrorAction SilentlyContinue
}

Write-Host "==> verify"

$CypherExe = Join-Path $repoRoot "build\bin\cypher.exe"

if (-not (Test-Path $CypherExe)) {
    throw "cypher.exe was not created: $CypherExe"
}

& $CypherExe version

if ($LASTEXITCODE -ne 0) {
    throw "cypher.exe version failed with exit code $LASTEXITCODE"
}
'@ | Set-Content -Encoding UTF8 $BuildWindowsScript

Write-Host "[7/10] build cypher with build_windows.ps1..."

Set-Location $CypherDir

powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File ".\build\build_windows.ps1"

if ($LASTEXITCODE -ne 0) {
    throw "build_windows.ps1 failed with exit code $LASTEXITCODE"
}

Write-Host "[8/10] verify cypher.exe version..."

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

@'
$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot

$CypherExe = Join-Path $PSScriptRoot "build\bin\cypher.exe"

if (-not (Test-Path $CypherExe)) {
    throw "cypher.exe was not found: $CypherExe"
}

$ExtIp = (& curl.exe -4 -s ifconfig.io).Trim()

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
'@ | Set-Content -Encoding UTF8 $StartScript

cmd /c "pm2 delete cypher-node 2>nul"
pm2 start powershell.exe --name cypher-node -- -NoProfile -ExecutionPolicy Bypass -File "$StartScript"
pm2 save

Write-Host ""
Write-Host "PM2 started cypher-node."
Write-Host "Check status with:"
Write-Host "  pm2 status"
Write-Host "  pm2 logs cypher-node"
Write-Host ""
Write-Host "Done."
