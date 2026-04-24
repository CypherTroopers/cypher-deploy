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
        "C:\Program Files\Go\bin",
        (Join-Path $HOME "go-sdk\go1.26.2\bin"),
        (Join-Path $HOME "go-sdk\go1.20.14\bin"),
        (Join-Path $HOME "go-sdk\go1.24.1\bin")
    )

    foreach ($Path in $Candidates) {
        if (Test-Path (Join-Path $Path "go.exe")) {
            return $Path
        }
    }

    return $null
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

$GoBin = Find-GoBin
if ($null -ne $GoBin) {
    Add-PathForCurrentSession $GoBin
}

if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
    throw "git.exe was not found in PATH. Please close PowerShell and open it again, then rerun this script."
}

if (-not (Get-Command go.exe -ErrorAction SilentlyContinue)) {
    throw "go.exe was not found in PATH. Please close PowerShell and open it again, then rerun this script."
}

if (-not (Get-Command python.exe -ErrorAction SilentlyContinue)) {
    throw "python.exe was not found in PATH. Please close PowerShell and open it again, then rerun this script."
}

if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) {
    throw "node.exe was not found in PATH. Please close PowerShell and open it again, then rerun this script."
}

if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
    throw "npm.cmd was not found in PATH. Please close PowerShell and open it again, then rerun this script."
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
    throw "MSYS2 bash was not found at $Bash. Please close PowerShell and open it again, then rerun this script."
}

& $Bash -lc "pacman -Sy --noconfirm make mingw-w64-x86_64-gcc mingw-w64-x86_64-openssl mingw-w64-x86_64-gmp"

if ($LASTEXITCODE -ne 0) {
    throw "MSYS2 package install failed with exit code $LASTEXITCODE"
}

Write-Host "[3/10] install/check pm2..."

npm install -g pm2

Add-PathForCurrentSession "$env:APPDATA\npm"
Add-UserPath "$env:APPDATA\npm"

if (-not (Get-Command pm2.cmd -ErrorAction SilentlyContinue)) {
    throw "pm2.cmd was not found in PATH. Please close PowerShell and open it again, then rerun this script."
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

Write-Host "[5/10] confirm Windows build files..."

$BuildWindowsScript = Join-Path $CypherDir "build\build_windows.ps1"
$WindowsBuildMd = Join-Path $CypherDir "WINDOWS_BUILD.md"

if (-not (Test-Path $BuildWindowsScript)) {
    Write-Host "build_windows.ps1 was not found in current branch."
    Write-Host "Searching file..."
    Get-ChildItem -Path $CypherDir -Recurse -Filter "build_windows.ps1" -ErrorAction SilentlyContinue | Select-Object FullName

    throw @"
build_windows.ps1 was not found.

According to WINDOWS_BUILD.md, this repo should include:
  build\build_windows.ps1

You are probably on an old checkout or the branch does not contain the Windows build script.
Please commit/push build\build_windows.ps1 to this branch, or switch to the branch that contains it.
"@
}

if (Test-Path $WindowsBuildMd) {
    Write-Host "WINDOWS_BUILD.md found:"
    Write-Host $WindowsBuildMd
} else {
    Write-Host "WARNING: WINDOWS_BUILD.md was not found, but continuing because build_windows.ps1 exists."
}

Write-Host "[6/10] patch dependency if needed..."

$DukLoggingPath = Join-Path $CypherDir "vendor\gopkg.in\olebedev\go-duktape.v3\duk_logging.c"

if (Test-Path $DukLoggingPath) {
    $Content = Get-Content -Raw $DukLoggingPath

    $Content = $Content.Replace('duk_uint8_t date_buf[32]', 'duk_uint8_t date_buf[64]')
    $Content = $Content.Replace('snprintf((char *) date_buf, sizeof(date_buf),, ', 'snprintf((char *) date_buf, sizeof(date_buf), ')
    $Content = $Content.Replace('sprintf((char *) date_buf, ', 'snprintf((char *) date_buf, sizeof(date_buf), ')

    Set-Content -Path $DukLoggingPath -Value $Content -NoNewline
}

Write-Host "[7/10] build cypher with build_windows.ps1..."

Set-Location $CypherDir

$env:GO111MODULE = "off"
$env:CGO_ENABLED = "1"
$env:CGO_LDFLAGS_ALLOW = ".*"
$env:CGO_CFLAGS_ALLOW = ".*"
$env:CGO_CXXFLAGS_ALLOW = ".*"

Add-PathForCurrentSession "C:\msys64\mingw64\bin"
Add-PathForCurrentSession "C:\msys64\usr\bin"

Write-Host "Current directory:"
Get-Location

Write-Host "Running:"
Write-Host "powershell -ExecutionPolicy Bypass -File .\build\build_windows.ps1"

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
