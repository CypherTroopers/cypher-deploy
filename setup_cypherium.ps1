# setup_cypherium.ps1
$ErrorActionPreference = "Stop"

Write-Host "[0/10] setup environment..."

# ============================================================
# Basic environment
# ============================================================

$env:GO111MODULE = "off"
$env:GOPATH = "$env:USERPROFILE\go"

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

function Git-Clone-IfMissing {
    param(
        [string]$Dir,
        [string]$Repo
    )

    if (-not (Test-Path $Dir)) {
        git clone $Repo $Dir
    } else {
        Write-Host "Already exists: $Dir"
    }
}

function Convert-To-MsysPath {
    param([string]$WindowsPath)

    $full = (Resolve-Path $WindowsPath).Path
    $drive = $full.Substring(0, 1).ToLower()
    $rest = $full.Substring(2).Replace("\", "/")
    return "/$drive$rest"
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

    $goSdkPath = "$env:USERPROFILE\go-sdk\go1.24.1\bin\go.exe"

    if (Test-Path $goSdkPath) {
        return Split-Path $goSdkPath -Parent
    }

    $goCommand = Get-Command go.exe -ErrorAction Stop
    return Split-Path $goCommand.Source -Parent
}

function Get-GoRootFromGoBin {
    param([string]$GoBin)

    $goRoot = Split-Path $GoBin -Parent

    if (-not (Test-Path "$goRoot\src\runtime\runtime.go")) {
        throw "GOROOT is not valid: $goRoot"
    }

    return $goRoot
}

function Set-GoEnvironment {
    param(
        [string]$GoBin,
        [string]$GoRoot
    )

    if (-not (Test-Path "$GoBin\go.exe")) {
        throw "go.exe not found: $GoBin\go.exe"
    }

    if (-not (Test-Path "$GoRoot\src\runtime\runtime.go")) {
        throw "GOROOT does not exist or is incomplete: $GoRoot"
    }

    $env:GOROOT = $GoRoot
    $env:GOPATH = "$env:USERPROFILE\go"
    $env:GO111MODULE = "off"

    [Environment]::SetEnvironmentVariable("GOROOT", $GoRoot, "User")
    [Environment]::SetEnvironmentVariable("GOPATH", $env:GOPATH, "User")
    [Environment]::SetEnvironmentVariable("GO111MODULE", "off", "User")

    if ($env:Path -notlike "*$GoBin*") {
        $env:Path = "$GoBin;$env:Path"
    }

    Write-Host "Go environment:"
    Write-Host "  GOROOT=$env:GOROOT"
    Write-Host "  GOPATH=$env:GOPATH"
    Write-Host "  GO111MODULE=$env:GO111MODULE"

    & "$GoBin\go.exe" version
    & "$GoBin\go.exe" env GOROOT
}

function Write-Utf8NoBom {
    param(
        [string]$Path,
        [string]$Content
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Stop-ExistingCypherProcesses {
    param([string]$CypherExePath)

    $target = $CypherExePath.ToLower()

    $processes = Get-CimInstance Win32_Process |
        Where-Object {
            $_.Name -eq "cypher.exe" -and (
                ($_.ExecutablePath -and $_.ExecutablePath.ToLower() -eq $target) -or
                ($_.CommandLine -and $_.CommandLine.ToLower().Contains("cypher.exe"))
            )
        }

    foreach ($p in $processes) {
        Write-Host "Stopping existing cypher.exe process: PID=$($p.ProcessId)"
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Seconds 2
}

function Test-RequiredPortsFree {
    param([int[]]$Ports)

    $listeners = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalPort -in $Ports }

    if ($listeners) {
        Write-Host ""
        Write-Host "Required ports are already in use:"
        $listeners | Select-Object LocalAddress, LocalPort, OwningProcess | Format-Table

        foreach ($listener in $listeners) {
            $pid = $listener.OwningProcess
            $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $pid" -ErrorAction SilentlyContinue

            if ($proc) {
                Write-Host "PID $pid : $($proc.Name)"
                Write-Host "CommandLine: $($proc.CommandLine)"
                Write-Host ""
            }
        }

        throw "Port check failed. Stop the process using ports 6000 / 8000 / 9251, or change the ports."
    }

    Write-Host "Required ports are free: $($Ports -join ', ')"
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
# [1/10] Install Windows tools
# ============================================================

Write-Host "[1/10] install Windows tools..."

Install-WingetPackage `
    -Ids @("Git.Git") `
    -Name "Git" `
    -Commands @("git.exe") `
    -Paths @(
        "C:\Program Files\Git\cmd\git.exe",
        "C:\Program Files\Git\bin\git.exe"
    )

Install-WingetPackage `
    -Ids @("GoLang.Go.1.24", "GoLang.Go") `
    -Name "Go" `
    -Commands @("go.exe") `
    -Paths @(
        "C:\Program Files\Go\bin\go.exe",
        "$env:USERPROFILE\go-sdk\go1.24.1\bin\go.exe"
    )

Install-WingetPackage `
    -Ids @("OpenJS.NodeJS.LTS") `
    -Name "Node.js LTS" `
    -Commands @("npm.cmd") `
    -Paths @(
        "C:\Program Files\nodejs\node.exe",
        "C:\Program Files\nodejs\npm.cmd"
    )

Install-WingetPackage `
    -Ids @("Python.Python.3.12", "Python.Python.3") `
    -Name "Python" `
    -Commands @("python.exe", "py.exe") `
    -Paths @(
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
        "C:\Python312\python.exe"
    )

Install-WingetPackage `
    -Ids @("MSYS2.MSYS2") `
    -Name "MSYS2" `
    -Commands @() `
    -Paths @(
        "C:\msys64\usr\bin\bash.exe"
    )

Add-Path "C:\Program Files\Git\cmd"
Add-Path "C:\Program Files\Git\bin"
Add-Path "C:\Program Files\Go\bin"
Add-Path "$env:USERPROFILE\go-sdk\go1.24.1\bin"
Add-Path "C:\Program Files\nodejs"
Add-Path "$env:APPDATA\npm"
Add-Path "$env:LOCALAPPDATA\Programs\Python\Python312"
Add-Path "$env:LOCALAPPDATA\Programs\Python\Python312\Scripts"
Add-Path "C:\Python312"
Add-Path "C:\Python312\Scripts"
Add-Path "C:\msys64\mingw64\bin"
Add-Path "C:\msys64\usr\bin"

[Environment]::SetEnvironmentVariable("GOPATH", $env:GOPATH, "User")
[Environment]::SetEnvironmentVariable("GO111MODULE", "off", "User")

$env:Path = "C:\Program Files\Go\bin;$env:USERPROFILE\go-sdk\go1.24.1\bin;C:\msys64\mingw64\bin;C:\msys64\usr\bin;C:\Program Files\Git\cmd;C:\Program Files\Git\bin;C:\Program Files\nodejs;$env:APPDATA\npm;$env:Path"

Require-Command git
Require-Command go
Require-Command node
Require-Command npm

$goBinForEnv = Get-GoBinPath
$goRootForEnv = Get-GoRootFromGoBin -GoBin $goBinForEnv
Set-GoEnvironment -GoBin $goBinForEnv -GoRoot $goRootForEnv

Write-Host "Check Windows tools..."

where.exe go
go version
go env GOROOT
go env -w GO111MODULE=off
go env -w GOPATH="$env:GOPATH"

git --version
node --version
npm --version

if (Get-Command python -ErrorAction SilentlyContinue) {
    python --version
} elseif (Get-Command py -ErrorAction SilentlyContinue) {
    py -3 --version
} else {
    throw "Python command was not found after installation."
}

# ============================================================
# [2/10] Install MSYS2 build dependencies
# ============================================================

Write-Host "[2/10] install MSYS2 build dependencies..."

$bash = "C:\msys64\usr\bin\bash.exe"

if (-not (Test-Path $bash)) {
    throw "MSYS2 bash not found: $bash"
}

& $bash -lc "pacman -Syuu --noconfirm || true"
& $bash -lc "pacman -Suu --noconfirm || true"

& $bash -lc "pacman -S --needed --noconfirm base-devel git make cmake pkgconf m4 bzip2 texinfo patch unzip mingw-w64-x86_64-toolchain mingw-w64-x86_64-gcc mingw-w64-x86_64-cmake mingw-w64-x86_64-pkgconf mingw-w64-x86_64-openssl mingw-w64-x86_64-gmp mingw-w64-x86_64-python"

Write-Host "Check MSYS2 tools..."

& $bash -lc "make --version"
& $bash -lc "gcc --version"
& $bash -lc "g++ --version"
& $bash -lc "cmake --version"
& $bash -lc "pkg-config --version || pkgconf --version"
& $bash -lc "python --version"

# ============================================================
# [3/10] Install PM2
# ============================================================

Write-Host "[3/10] install pm2..."

npm install -g pm2

Add-Path "$env:APPDATA\npm"

if (-not (Get-Command pm2 -ErrorAction SilentlyContinue)) {
    if (Test-Path "$env:APPDATA\npm\pm2.cmd") {
        $env:Path = "$env:APPDATA\npm;$env:Path"
    } else {
        throw "pm2 command not found after npm install -g pm2."
    }
}

pm2 --version

# ============================================================
# [4/10] Clone cypher repo
# ============================================================

Write-Host "[4/10] clone cypher repo..."

$cypherRoot = "$env:GOPATH\src\github.com\cypherium"
$cypherDir  = "$cypherRoot\cypher"

New-Item -ItemType Directory -Force -Path $cypherRoot | Out-Null
Set-Location $cypherRoot

if (-not (Test-Path $cypherDir)) {
    git clone https://github.com/CypherTroopers/cypher.git
}

Set-Location $cypherDir

git fetch --all
git checkout ecdsa_1.1_test_colossus-Xv2test

# ============================================================
# [5/10] Copy Windows BLS libraries
# ============================================================

Write-Host "[5/10] copy Windows BLS libraries..."

Set-Location $cypherDir

if (Test-Path ".\crypto\bls\lib\win") {
    Copy-Item ".\crypto\bls\lib\win\*" ".\crypto\bls\lib\" -Force
} else {
    Write-Host "WARNING: .\crypto\bls\lib\win was not found."
}

# ============================================================
# [6/10] Clone GOPATH dependencies
# ============================================================

Write-Host "[6/10] clone GOPATH dependencies..."

New-Item -ItemType Directory -Force -Path "$env:GOPATH\src\github.com\VictoriaMetrics" | Out-Null
Git-Clone-IfMissing "$env:GOPATH\src\github.com\VictoriaMetrics\fastcache" "https://github.com/VictoriaMetrics/fastcache.git"

New-Item -ItemType Directory -Force -Path "$env:GOPATH\src\github.com\shirou" | Out-Null
Git-Clone-IfMissing "$env:GOPATH\src\github.com\shirou\gopsutil" "https://github.com/shirou/gopsutil.git"
Git-Clone-IfMissing "$env:GOPATH\src\github.com\shirou\w32" "https://github.com/shirou/w32.git"

New-Item -ItemType Directory -Force -Path "$env:GOPATH\src\github.com\dlclark" | Out-Null
Git-Clone-IfMissing "$env:GOPATH\src\github.com\dlclark\regexp2" "https://github.com/dlclark/regexp2.git"

Set-Location "$env:GOPATH\src\github.com\dlclark\regexp2"
git fetch --tags
git checkout v1.1.8

New-Item -ItemType Directory -Force -Path "$env:GOPATH\src\github.com\go-sourcemap" | Out-Null
Git-Clone-IfMissing "$env:GOPATH\src\github.com\go-sourcemap\sourcemap" "https://github.com/go-sourcemap/sourcemap.git"

New-Item -ItemType Directory -Force -Path "$env:GOPATH\src\github.com\tklauser" | Out-Null
Git-Clone-IfMissing "$env:GOPATH\src\github.com\tklauser\go-sysconf" "https://github.com/tklauser/go-sysconf.git"
Git-Clone-IfMissing "$env:GOPATH\src\github.com\tklauser\numcpus" "https://github.com/tklauser/numcpus.git"

New-Item -ItemType Directory -Force -Path "$env:GOPATH\src\golang.org\x" | Out-Null
Git-Clone-IfMissing "$env:GOPATH\src\golang.org\x\sys" "https://go.googlesource.com/sys"

New-Item -ItemType Directory -Force -Path "$env:GOPATH\src\github.com\naoina" | Out-Null
Git-Clone-IfMissing "$env:GOPATH\src\github.com\naoina\toml" "https://github.com/naoina/toml.git"
Git-Clone-IfMissing "$env:GOPATH\src\github.com\naoina\go-stringutil" "https://github.com/naoina/go-stringutil.git"

New-Item -ItemType Directory -Force -Path "$env:GOPATH\src\github.com\yusufpapurcu" | Out-Null
Git-Clone-IfMissing "$env:GOPATH\src\github.com\yusufpapurcu\wmi" "https://github.com/yusufpapurcu/wmi.git"

New-Item -ItemType Directory -Force -Path "$env:GOPATH\src\github.com\StackExchange" | Out-Null
Git-Clone-IfMissing "$env:GOPATH\src\github.com\StackExchange\wmi" "https://github.com/StackExchange/wmi.git"

New-Item -ItemType Directory -Force -Path "$env:GOPATH\src\github.com\go-ole" | Out-Null
Git-Clone-IfMissing "$env:GOPATH\src\github.com\go-ole\go-ole" "https://github.com/go-ole/go-ole.git"

New-Item -ItemType Directory -Force -Path "$env:GOPATH\src\github.com\cespare" | Out-Null
Git-Clone-IfMissing "$env:GOPATH\src\github.com\cespare\cp" "https://github.com/cespare/cp.git"

# ============================================================
# [7/10] Patch dependencies
# ============================================================

Write-Host "[7/10] patch dependencies..."

Set-Location $cypherDir

Write-Host "Patch regexp2 to v1.1.8 in vendor..."

Remove-Item ".\vendor\github.com\dlclark\regexp2" -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path ".\vendor\github.com\dlclark" | Out-Null
Copy-Item "$env:GOPATH\src\github.com\dlclark\regexp2" ".\vendor\github.com\dlclark\regexp2" -Recurse -Force

Write-Host "Patch go-duktape duk_logging.c..."

$dukLoggingPath = "$cypherDir\vendor\gopkg.in\olebedev\go-duktape.v3\duk_logging.c"

if (Test-Path $dukLoggingPath) {
    $text = Get-Content $dukLoggingPath -Raw

    $text = $text -replace 'duk_uint8_t date_buf\[32\]', 'duk_uint8_t date_buf[64]'
    $text = $text -replace 'snprintf\(\(char \*\) date_buf, sizeof\(date_buf\),, ', 'snprintf((char *) date_buf, sizeof(date_buf), '
    $text = $text -replace 'sprintf\(\(char \*\) date_buf,', 'snprintf((char *) date_buf, sizeof(date_buf),'

    Write-Utf8NoBom -Path $dukLoggingPath -Content $text
} else {
    Write-Host "WARNING: duk_logging.c not found: $dukLoggingPath"
}

# ============================================================
# [8/10] Build cypher
# ============================================================

Write-Host "[8/10] build cypher with direct go build..."

Set-Location $cypherDir

$env:CGO_ENABLED = "1"
$env:GO111MODULE = "off"
$env:GOPATH = "$env:USERPROFILE\go"

$env:CC = "C:\msys64\mingw64\bin\gcc.exe"
$env:CXX = "C:\msys64\mingw64\bin\g++.exe"

$env:CGO_CFLAGS_ALLOW = ".*"
$env:CGO_LDFLAGS_ALLOW = ".*"

$goBin = Get-GoBinPath
$goRoot = Get-GoRootFromGoBin -GoBin $goBin
Set-GoEnvironment -GoBin $goBin -GoRoot $goRoot

$goExe = Join-Path $goBin "go.exe"

if (-not (Test-Path $goExe)) {
    throw "go.exe not found: $goExe"
}

$env:Path = "$goBin;C:\msys64\mingw64\bin;C:\msys64\usr\bin;C:\Program Files\Git\cmd;C:\Program Files\Git\bin;C:\Program Files\nodejs;$env:APPDATA\npm;$env:Path"

$cypherMsysPath = Convert-To-MsysPath $cypherDir
$gopathMsysPath = Convert-To-MsysPath $env:GOPATH
$goBinMsysPath = Convert-To-MsysPath $goBin
$goRootMsysPath = Convert-To-MsysPath $goRoot

Write-Host "Go exe: $goExe"
Write-Host "Go bin: $goBin"
Write-Host "Go root: $goRoot"
Write-Host "Go bin msys path: $goBinMsysPath"
Write-Host "Go root msys path: $goRootMsysPath"
Write-Host "cypher path: $cypherDir"
Write-Host "cypher msys path: $cypherMsysPath"
Write-Host "GOPATH: $env:GOPATH"
Write-Host "GOPATH msys path: $gopathMsysPath"

$buildScript = @'
set -eo pipefail

cd '__CYPHER_MSYS_PATH__'

export PATH="__GO_BIN_MSYS_PATH__:/mingw64/bin:/usr/bin:$PATH"
export GOROOT='__GO_ROOT_MSYS_PATH__'
export GOPATH='__GOPATH_MSYS_PATH__'
export GO111MODULE=off
export CGO_ENABLED=1
export CC='/mingw64/bin/gcc.exe'
export CXX='/mingw64/bin/g++.exe'

echo "===== PATH ====="
echo "$PATH"

echo "===== go ====="
which go
go version
go env GOROOT
go env GOPATH
go env GO111MODULE

echo "===== gcc ====="
which gcc
gcc --version

echo "===== g++ ====="
which g++
g++ --version

echo "===== clean build/bin ====="
rm -rf build/bin
mkdir -p build/bin

echo "===== direct go build high image base ====="
go build \
  -buildmode=exe \
  -ldflags='-linkmode=external -extldflags "-Wl,--image-base,0x7ff900000000 -Wl,--disable-dynamicbase -Wl,--enable-auto-import -Wl,--enable-runtime-pseudo-reloc-v2"' \
  -o build/bin/cypher.exe \
  ./cmd/cypher 2>&1 | tee direct_go_build_highbase.log

echo "===== build/bin ====="
ls -la build/bin || true
'@

$buildScript = $buildScript.Replace("__CYPHER_MSYS_PATH__", $cypherMsysPath)
$buildScript = $buildScript.Replace("__GO_BIN_MSYS_PATH__", $goBinMsysPath)
$buildScript = $buildScript.Replace("__GO_ROOT_MSYS_PATH__", $goRootMsysPath)
$buildScript = $buildScript.Replace("__GOPATH_MSYS_PATH__", $gopathMsysPath)

$buildScriptPath = "$cypherDir\direct_go_build_highbase.sh"
Write-Utf8NoBom -Path $buildScriptPath -Content $buildScript

$buildScriptMsysPath = Convert-To-MsysPath $buildScriptPath

& $bash -lc "bash '$buildScriptMsysPath'"

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "===== direct go build log tail ====="
    Get-Content "$cypherDir\direct_go_build_highbase.log" -Tail 120 -ErrorAction SilentlyContinue
    throw "direct go build failed. Check: $cypherDir\direct_go_build_highbase.log"
}

$CypherExe = "$cypherDir\build\bin\cypher.exe"

if (-not (Test-Path $CypherExe)) {
    Write-Host ""
    Write-Host "===== build/bin ====="
    Get-ChildItem "$cypherDir\build\bin" -Force -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "===== direct go build log tail ====="
    Get-Content "$cypherDir\direct_go_build_highbase.log" -Tail 120 -ErrorAction SilentlyContinue

    throw "cypher.exe was not created."
}

Write-Host "cypher.exe created:"
Get-Item $CypherExe

# ============================================================
# [9/10] Copy runtime DLLs
# ============================================================

Write-Host "[9/10] copy runtime DLLs..."

Set-Location $cypherDir

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
    $src = "C:\msys64\mingw64\bin\$dll"

    if (Test-Path $src) {
        Copy-Item $src ".\build\bin\" -Force
        Write-Host "Copied: $dll"
    } else {
        Write-Host "WARNING: DLL not found: $dll"
    }
}

Write-Host "Check cypher.exe version..."

$env:Path = "$cypherDir\build\bin;C:\msys64\mingw64\bin;C:\msys64\usr\bin;$goBin;$env:Path"

if (Test-Path ".\build\bin\cypher.exe") {
    .\build\bin\cypher.exe version
} else {
    throw "cypher.exe was not created."
}

# ============================================================
# [10/10] Init chain data
# ============================================================

Write-Host "[10/10] init chain data..."

Set-Location $cypherDir

if (-not (Test-Path ".\genesistest.json")) {
    throw "genesistest.json not found: $cypherDir\genesistest.json"
}

.\build\bin\cypher.exe --datadir chaindbname init .\genesistest.json

# ============================================================
# Register PM2 with ecosystem.config.js
# ============================================================

Write-Host "Register pm2 with ecosystem.config.js..."

Set-Location $cypherDir

$cypherExePath = "$cypherDir\build\bin\cypher.exe"
$ecosystemPath = "$cypherDir\ecosystem.config.js"

if (-not (Test-Path $cypherExePath)) {
    throw "cypher.exe not found: $cypherExePath"
}

# Resolve node.exe directly. Do not rely on pm2.cmd finding "node".
$nodeExe = "C:\Program Files\nodejs\node.exe"

if (-not (Test-Path $nodeExe)) {
    $nodeFound = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($nodeFound) {
        $nodeExe = $nodeFound.Source
    } else {
        throw "node.exe not found. Node.js installation failed or PATH is broken."
    }
}

# Resolve PM2 JS directly. Do not use pm2.cmd.
$pm2Js = "$env:APPDATA\npm\node_modules\pm2\bin\pm2"

if (-not (Test-Path $pm2Js)) {
    npm install -g pm2

    if (-not (Test-Path $pm2Js)) {
        throw "PM2 JS entry was not found: $pm2Js"
    }
}

Write-Host "Node exe: $nodeExe"
Write-Host "PM2 JS: $pm2Js"

# IPv4 only. Do not use Invoke-RestMethod here because it may return IPv6.
$extIp = (curl.exe -4 -s ifconfig.io).Trim()

if ([string]::IsNullOrWhiteSpace($extIp)) {
    throw "Failed to get external IPv4."
}

if ($extIp -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
    throw "Failed to get IPv4 external IP. Got: $extIp"
}

Write-Host "External IPv4: $extIp"

Remove-Item "$cypherDir\start-cypher.cmd" -Force -ErrorAction SilentlyContinue
Remove-Item "$cypherDir\start-cypher.ps1" -Force -ErrorAction SilentlyContinue

# Stop old PM2 process if it exists.
& $nodeExe $pm2Js describe cypher-node *> $null

if ($LASTEXITCODE -eq 0) {
    Write-Host "Existing cypher-node found. Deleting..."
    & $nodeExe $pm2Js delete cypher-node
} else {
    Write-Host "cypher-node does not exist yet. Skip delete."
}

# Stop existing local cypher.exe if it was started manually.
Stop-ExistingCypherProcesses -CypherExePath $cypherExePath

# Check ports before PM2 starts.
Test-RequiredPortsFree -Ports @(6000, 8000, 9251)

$cypherDirJs = $cypherDir.Replace("\", "\\")
$cypherExePathJs = $cypherExePath.Replace("\", "\\")

$ecosystemScript = @"
module.exports = {
  apps: [
    {
      name: "cypher-node",
      cwd: "$cypherDirJs",
      script: "$cypherExePathJs",
      interpreter: "none",
      args: [
        "--verbosity", "4",
        "--rnetport", "7200",
        "--syncmode", "full",
        "--nat", "extip:$extIp",
        "--ws",
        "--ws.addr", "0.0.0.0",
        "--ws.port", "9251",
        "--ws.origins", "*",
        "--metrics",
        "--http",
        "--http.addr", "0.0.0.0",
        "--http.port", "8000",
        "--http.api", "eth,web3,net,txpool",
        "--http.corsdomain", "*",
        "--port", "6000",
        "--datadir", "C:\\Users\\sales\\go\\src\\github.com\\cypherium\\cypher\\chaindbname",
        "--networkid", "12367",
        "--gcmode", "archive",
        "--bootnodes", "enode://fe37c100a751e024f9bce73764b7360edf7690619e6e0bf2473f876834adf200feb68f17562a6eea77f263e947744978269db295c2ece9bfc24ad2be14eb69f1@161.97.184.220:6800"
      ],
      env: {
        PATH: "$cypherDirJs\\\\build\\\\bin;C:\\\\msys64\\\\mingw64\\\\bin;C:\\\\msys64\\\\usr\\\\bin;C:\\\\Program Files\\\\Go\\\\bin;C:\\\\Program Files\\\\nodejs;" + process.env.PATH
      },
      autorestart: true,
      max_restarts: 10,
      min_uptime: "10s"
    }
  ]
};
"@

Write-Utf8NoBom -Path $ecosystemPath -Content $ecosystemScript

if (-not (Test-Path $ecosystemPath)) {
    throw "ecosystem.config.js was not created: $ecosystemPath"
}

& $nodeExe $pm2Js flush

& $nodeExe $pm2Js start $ecosystemPath --only cypher-node

if ($LASTEXITCODE -ne 0) {
    throw "pm2 start cypher-node failed."
}

Start-Sleep -Seconds 5

& $nodeExe $pm2Js save

if ($LASTEXITCODE -ne 0) {
    throw "pm2 save failed."
}

& $nodeExe $pm2Js status

Write-Host ""
Write-Host "PM2 started cypher-node."
Write-Host ""
Write-Host "Check status with:"
Write-Host "  pm2 status"
Write-Host "  pm2 logs cypher-node"
Write-Host ""
Write-Host "Attach console with Windows IPC:"
Write-Host "  .\build\bin\cypher.exe attach ipc:\\.\pipe\cypher.ipc"
Write-Host ""
Write-Host "Build log:"
Write-Host "  $cypherDir\direct_go_build_highbase.log"
Write-Host ""
Write-Host "Done."
