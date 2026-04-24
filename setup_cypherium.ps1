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

function Convert-ToMsysPath {
    param([string]$WinPath)

    $MsysPath = $WinPath -replace '\\', '/'
    $MsysPath = $MsysPath -replace '^C:', '/c'
    $MsysPath = $MsysPath -replace '^D:', '/d'
    $MsysPath = $MsysPath -replace '^E:', '/e'
    return $MsysPath
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
    param(
        [string]$Id
    )

    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw "winget is not available. Please install App Installer from Microsoft Store or install dependencies manually."
    }

    Write-Host "Installing $Id via winget source only..."

    winget install `
        --id $Id `
        -e `
        --source winget `
        --accept-package-agreements `
        --accept-source-agreements
}

function Invoke-MsysBashScript {
    param(
        [string]$Script,
        [string]$Name = "cypher-msys-script"
    )

    if (-not (Test-Path $Bash)) {
        throw "MSYS2 bash was not found at $Bash"
    }

    $TempScript = Join-Path $env:TEMP "$Name.sh"

    $Script = $Script -replace "`r`n", "`n"
    $Script = $Script -replace "`r", "`n"

    [System.IO.File]::WriteAllText(
        $TempScript,
        $Script,
        [System.Text.Encoding]::ASCII
    )

    & $Bash (Convert-ToMsysPath $TempScript)

    if ($LASTEXITCODE -ne 0) {
        throw "MSYS2 bash script failed: $Name, exit code $LASTEXITCODE"
    }
}

$env:GO111MODULE = "off"
[Environment]::SetEnvironmentVariable("GO111MODULE", "off", "User")

$env:GOPATH = Join-Path $HOME "go"
[Environment]::SetEnvironmentVariable("GOPATH", $env:GOPATH, "User")

$GoVersion = "1.26.2"
$GoInstallRoot = Join-Path $HOME "go-sdk"
$GoRoot = Join-Path $GoInstallRoot "go$GoVersion"
$GoBin = Join-Path $GoRoot "bin"

New-Item -ItemType Directory -Force $GoInstallRoot | Out-Null
New-Item -ItemType Directory -Force $env:GOPATH | Out-Null

Add-PathForCurrentSession $GoBin
Add-PathForCurrentSession "$env:GOPATH\bin"
Add-PathForCurrentSession "C:\Program Files\Git\cmd"
Add-PathForCurrentSession "C:\Program Files\nodejs"
Add-PathForCurrentSession "$env:APPDATA\npm"
Add-PathForCurrentSession "C:\msys64\mingw64\bin"
Add-PathForCurrentSession "C:\msys64\usr\bin"

Write-Host "[1/10] install/check Windows dependencies..."

if (-not (Ensure-Command git "Git is not installed. Installing Git...")) {
    Winget-Install "Git.Git"
    Add-PathForCurrentSession "C:\Program Files\Git\cmd"
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
Add-PathForCurrentSession "C:\Program Files\nodejs"
Add-PathForCurrentSession "$env:APPDATA\npm"
Add-PathForCurrentSession "C:\msys64\mingw64\bin"
Add-PathForCurrentSession "C:\msys64\usr\bin"

Add-UserPath "C:\Program Files\Git\cmd"
Add-UserPath "C:\Program Files\nodejs"
Add-UserPath "$env:APPDATA\npm"
Add-UserPath "C:\msys64\mingw64\bin"
Add-UserPath "C:\msys64\usr\bin"

if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
    throw "git was installed, but git.exe was not found in PATH. Please close PowerShell and open it again, then rerun this script."
}

if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) {
    throw "Node.js was installed, but node.exe was not found in PATH. Please close PowerShell and open it again, then rerun this script."
}

if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
    throw "npm was installed, but npm.cmd was not found in PATH. Please close PowerShell and open it again, then rerun this script."
}

Write-Host "Git:"
git --version

Write-Host "Node.js:"
node -v

Write-Host "npm:"
npm -v

Write-Host "[2/10] install Go $GoVersion..."

$GoZip = Join-Path $env:TEMP "go$GoVersion.windows-amd64.zip"
$GoUrl = "https://go.dev/dl/go$GoVersion.windows-amd64.zip"

if (-not (Test-Path $GoRoot)) {
    Write-Host "Downloading Go $GoVersion..."
    Invoke-WebRequest -Uri $GoUrl -OutFile $GoZip

    $ExtractDir = Join-Path $env:TEMP "go$GoVersion-extract"
    Remove-Item -Recurse -Force $ExtractDir -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force $ExtractDir | Out-Null

    Expand-Archive -Path $GoZip -DestinationPath $ExtractDir -Force

    Remove-Item -Recurse -Force $GoRoot -ErrorAction SilentlyContinue
    Move-Item -Path (Join-Path $ExtractDir "go") -Destination $GoRoot
}

$env:GOROOT = $GoRoot
[Environment]::SetEnvironmentVariable("GOROOT", $GoRoot, "User")

Add-PathForCurrentSession $GoBin
Add-PathForCurrentSession "$env:GOPATH\bin"
Add-UserPath $GoBin
Add-UserPath "$env:GOPATH\bin"

go version
go env -w GO111MODULE=off

Write-Host "[3/10] install/check MSYS2 packages..."

$Bash = "C:\msys64\usr\bin\bash.exe"

if (-not (Test-Path $Bash)) {
    throw "MSYS2 bash was not found at $Bash. Please close PowerShell and open it again, then rerun this script."
}

& $Bash -lc "pacman -Syu --noconfirm"
& $Bash -lc "pacman -S --needed --noconfirm base-devel git make autoconf automake libtool python mingw-w64-x86_64-python mingw-w64-x86_64-gcc mingw-w64-x86_64-cmake mingw-w64-x86_64-openssl mingw-w64-x86_64-gmp mingw-w64-x86_64-pkgconf"

Add-PathForCurrentSession "C:\msys64\mingw64\bin"
Add-PathForCurrentSession "C:\msys64\usr\bin"

Write-Host "[4/10] install pm2..."

npm install -g pm2

Add-PathForCurrentSession "$env:APPDATA\npm"

if (-not (Get-Command pm2.cmd -ErrorAction SilentlyContinue)) {
    throw "pm2 was installed, but pm2.cmd was not found in PATH. Please close PowerShell and open it again, then rerun this script."
}

pm2 -v

Write-Host "[5/10] clone cypher repo..."

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

$CypherDirMsys = Convert-ToMsysPath $CypherDir
$GoBinMsys = Convert-ToMsysPath $GoBin
$GoPathMsys = Convert-ToMsysPath $env:GOPATH

Write-Host "[5.1/10] restore repository Windows BLS/MCL libs..."

$RestoreBlsScript = @'
#!/usr/bin/env bash
set -euo pipefail

cd "__CYPHER_DIR_MSYS__"

if [ -d "crypto/bls/lib/win" ]; then
  echo "Restore crypto/bls/lib/win from repository..."
  git checkout -- crypto/bls/lib/win || true

  echo "Remove root BLS/MCL libs..."
  rm -f crypto/bls/lib/*.a

  echo "Copy repository win libs to crypto/bls/lib root..."
  cp -f crypto/bls/lib/win/*.a crypto/bls/lib/

  echo "Windows BLS/MCL libs:"
  ls -la crypto/bls/lib/win

  echo "Root BLS/MCL libs:"
  ls -la crypto/bls/lib/*.a
else
  echo "WARNING: crypto/bls/lib/win was not found. build_windows.ps1 may handle this."
fi
'@

$RestoreBlsScript = $RestoreBlsScript.Replace("__CYPHER_DIR_MSYS__", $CypherDirMsys)
Invoke-MsysBashScript -Script $RestoreBlsScript -Name "cypher-restore-bls"

Write-Host "[6/10] clone GOPATH dependencies..."

$FastcacheDir = Join-Path $env:GOPATH "src\github.com\VictoriaMetrics"
New-Item -ItemType Directory -Force $FastcacheDir | Out-Null
Set-Location $FastcacheDir
if (-not (Test-Path "fastcache")) {
    git clone https://github.com/VictoriaMetrics/fastcache.git
}

$GopsutilDir = Join-Path $env:GOPATH "src\github.com\shirou"
New-Item -ItemType Directory -Force $GopsutilDir | Out-Null
Set-Location $GopsutilDir
if (-not (Test-Path "gopsutil")) {
    git clone https://github.com/shirou/gopsutil.git
}

$Regexp2Root = Join-Path $env:GOPATH "src\github.com\dlclark"
$Regexp2Dir = Join-Path $Regexp2Root "regexp2"
New-Item -ItemType Directory -Force $Regexp2Root | Out-Null
Set-Location $Regexp2Root
if (-not (Test-Path $Regexp2Dir)) {
    git clone https://github.com/dlclark/regexp2.git
}
Set-Location $Regexp2Dir
git fetch --tags
git checkout v1.1.8

$SourcemapRoot = Join-Path $env:GOPATH "src\github.com\go-sourcemap"
New-Item -ItemType Directory -Force $SourcemapRoot | Out-Null
Set-Location $SourcemapRoot
if (-not (Test-Path "sourcemap")) {
    git clone https://github.com/go-sourcemap/sourcemap.git
}

$TkRoot = Join-Path $env:GOPATH "src\github.com\tklauser"
New-Item -ItemType Directory -Force $TkRoot | Out-Null
Set-Location $TkRoot
if (-not (Test-Path "go-sysconf")) {
    git clone https://github.com/tklauser/go-sysconf.git
}
if (-not (Test-Path "numcpus")) {
    git clone https://github.com/tklauser/numcpus.git
}

$XRoot = Join-Path $env:GOPATH "src\golang.org\x"
New-Item -ItemType Directory -Force $XRoot | Out-Null
Set-Location $XRoot
if (-not (Test-Path "sys")) {
    git clone https://go.googlesource.com/sys
}

Write-Host "[7/10] patch dependencies..."

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

Write-Host "[8/10] build cypher with build_windows.ps1..."

Set-Location $CypherDir

Write-Host "Current directory before Windows build:"
Get-Location

$BuildWindowsScript = Join-Path $CypherDir "build\build_windows.ps1"

if (-not (Test-Path $BuildWindowsScript)) {
    throw "build_windows.ps1 was not found: $BuildWindowsScript"
}

$env:GO111MODULE = "off"
$env:GOFLAGS = "-mod=mod"
$env:CGO_ENABLED = "1"
$env:CC = "gcc"
$env:CXX = "g++"
$env:CGO_LDFLAGS_ALLOW = ".*"
$env:CGO_CFLAGS_ALLOW = ".*"
$env:CGO_CXXFLAGS_ALLOW = ".*"

Add-PathForCurrentSession $GoBin
Add-PathForCurrentSession "$env:GOPATH\bin"
Add-PathForCurrentSession "C:\msys64\mingw64\bin"
Add-PathForCurrentSession "C:\msys64\usr\bin"

Write-Host "Go:"
go version

Write-Host "MSYS2 gcc:"
& $Bash -lc "export MSYSTEM=MINGW64; export PATH=/mingw64/bin:/usr/bin:$GoBinMsys:`$PATH; which gcc; gcc -dumpmachine"

Write-Host "Running:"
Write-Host ".\build\build_windows.ps1"

powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File $BuildWindowsScript

if ($LASTEXITCODE -ne 0) {
    throw "build_windows.ps1 failed with exit code $LASTEXITCODE"
}

Write-Host "[8.1/10] verify cypher.exe version..."

$CypherExe = Join-Path $CypherDir "build\bin\cypher.exe"

if (-not (Test-Path $CypherExe)) {
    throw "cypher.exe was not found after build_windows.ps1: $CypherExe"
}

& $CypherExe version

if ($LASTEXITCODE -ne 0) {
    throw "cypher.exe version failed with exit code $LASTEXITCODE"
}

Write-Host "[9/10] init chain data..."

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
  --bootnodes "enode://fe37c100a751e024f9bce73764b7360edf7690619e6e0bf2473f876834adf200feb68f17562a6eea77f263e947744978269db295c2ece9bfc24ad2be14eb69f1@161.97.184.220:6800" `
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
