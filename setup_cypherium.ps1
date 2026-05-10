#requires -RunAsAdministrator

# Run with Administrator PowerShell:
# powershell -ExecutionPolicy Bypass -File .\setup_cypherium.ps1

[CmdletBinding()]
param(
    [string]$RepoUrl = "https://github.com/CypherTroopers/cypher.git",
    [string]$RepoBranch = "ecdsa_1.1_test_colossus-Xv2test",
    [string]$GoVersion = "1.26.2",
    [string]$Gopath = (Join-Path $env:USERPROFILE "go"),
    [ValidateSet("mingw64", "ucrt64")]
    [string]$MsysFlavor = "mingw64",
    [string]$DataDir = "",
    [string]$GenesisFile = "",
    [Int64]$ExpectedChainId = 12367,
    [switch]$CleanData,
    [switch]$SkipInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message"
}

function Add-ProcessPath {
    param([string]$PathToAdd)
    if ((Test-Path -LiteralPath $PathToAdd) -and (($env:Path -split ';') -notcontains $PathToAdd)) {
        $env:Path = "$PathToAdd;$env:Path"
    }
}

function Invoke-NativeChecked {
    param(
        [scriptblock]$Command,
        [string]$ErrorMessage
    )
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$ErrorMessage ExitCode=$LASTEXITCODE"
    }
}

function Install-WingetPackage {
    param(
        [string[]]$Ids,
        [string]$Name,
        [string[]]$Commands = @(),
        [string[]]$Paths = @()
    )

    foreach ($command in $Commands) {
        if (Get-Command $command -ErrorAction SilentlyContinue) {
            Write-Host "$Name already installed. Found command: $command"
            return
        }
    }

    foreach ($path in $Paths) {
        if (Test-Path -LiteralPath $path) {
            Write-Host "$Name already installed. Found path: $path"
            return
        }
    }

    if ($SkipInstall) {
        throw "$Name was not found and -SkipInstall was specified."
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget was not found. Update App Installer from Microsoft Store or rerun with -SkipInstall after installing prerequisites manually."
    }

    foreach ($id in $Ids) {
        Write-Host "Installing $Name with winget package id: $id"
        & winget install --id $id -e --accept-source-agreements --accept-package-agreements

        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: winget returned $LASTEXITCODE for $id. Trying the next candidate if available."
            continue
        }

        foreach ($path in $Paths) {
            if (Test-Path -LiteralPath $path) { return }
        }

        foreach ($command in $Commands) {
            if (Get-Command $command -ErrorAction SilentlyContinue) { return }
        }

        return
    }

    throw "Failed to install or detect $Name."
}

function Get-GoBinPath {
    $preferred = "C:\Program Files\Go\bin\go.exe"

    if (Test-Path -LiteralPath $preferred) {
        return Split-Path -Parent $preferred
    }

    $cmd = Get-Command go.exe -ErrorAction Stop
    return Split-Path -Parent $cmd.Source
}

function Install-GoWindows {
    param([string]$Version)

    $preferred = "C:\Program Files\Go\bin\go.exe"

    if (Test-Path -LiteralPath $preferred) {
        $currentVersion = & $preferred version

        if ($currentVersion -match "go$([regex]::Escape($Version))") {
            Write-Host "Go $Version already installed."
            return
        }

        Write-Host "Go version differs. Found: $currentVersion. Expected: go$Version."
    }

    if ($SkipInstall) {
        throw "Go $Version was not found and -SkipInstall was specified."
    }

    $installer = Join-Path $env:TEMP "go$Version.windows-amd64.msi"
    $url = "https://go.dev/dl/go$Version.windows-amd64.msi"

    Write-Host "Downloading Go $Version from $url"
    Invoke-WebRequest -Uri $url -OutFile $installer
    Invoke-NativeChecked -Command { & msiexec.exe /i $installer /qn /norestart } -ErrorMessage "Go $Version installation failed."
}

function Assert-GoVersionSupported {
    param(
        [string]$GoExe,
        [string]$ExpectedVersion
    )

    $version = & $GoExe version
    Write-Host $version

    if ($version -notmatch "go$([regex]::Escape($ExpectedVersion))") {
        throw "Go $ExpectedVersion is required. Found: $version"
    }
}

function Copy-BLSWindowsLibraries {
    param([string]$CypherDir)

    $src = Join-Path $CypherDir "crypto\bls\lib\win"
    $dst = Join-Path $CypherDir "crypto\bls\lib"

    if (-not (Test-Path -LiteralPath $src)) {
        throw "Windows BLS static library directory not found: $src"
    }

    Copy-Item -LiteralPath (Join-Path $src "*") -Destination $dst -Recurse -Force
    Write-Host "Copied Windows BLS libraries from: $src"
}

function Patch-WindowsBLSCgoLDFLAGS {
    param([string]$CypherDir)

    $blsDir = Join-Path $CypherDir "crypto\bls"

    if (-not (Test-Path -LiteralPath $blsDir)) {
        throw "BLS source directory not found: $blsDir"
    }

    $files = Get-ChildItem -LiteralPath $blsDir -Filter "*.go" -Recurse
    $patched = 0

    foreach ($file in $files) {
        $content = Get-Content -LiteralPath $file.FullName -Raw
        $newContent = $content

        # Windows BLS archives reference __imp___gmpz_* symbols.
        # That means DLL import GMP is expected.
        # Do not force static GMP with -Wl,-Bstatic around -lgmpxx/-lgmp.
        $newContent = $newContent `
            -replace '\s+-Wl,-Bstatic\s+-lgmpxx\s+-lgmp\s+-lstdc\+\+\s+-Wl,-Bdynamic', ' -lgmpxx -lgmp -lstdc++' `
            -replace '\s+-Wl,-Bstatic\s+-lgmp\s+-lstdc\+\+\s+-Wl,-Bdynamic', ' -lgmp -lstdc++' `
            -replace '\s+-Wl,-Bstatic\s+-lgmpxx\s+-lgmp\s+-lstdc\+\+', ' -lgmpxx -lgmp -lstdc++' `
            -replace '\s+-Wl,-Bstatic\s+-lgmp\s+-lstdc\+\+', ' -lgmp -lstdc++'

        if ($newContent -ne $content) {
            Set-Content -LiteralPath $file.FullName -Value $newContent -NoNewline
            Write-Host "Patched Windows BLS cgo LDFLAGS: $($file.FullName)"
            $patched++
        }
    }

    if ($patched -eq 0) {
        Write-Host "WARNING: No Windows BLS cgo LDFLAGS were patched. Checking files manually may be required."
    }
}

function Get-ImportedDllNames {
    param(
        [string]$ObjdumpExe,
        [string]$BinaryPath
    )

    if (-not (Test-Path -LiteralPath $ObjdumpExe)) {
        return @()
    }

    $lines = & $ObjdumpExe -p $BinaryPath 2>$null | Select-String "DLL Name:"
    return @($lines | ForEach-Object { ($_.Line -replace '^\s*DLL Name:\s*', '').Trim() } | Where-Object { $_ })
}

function Copy-DependentDlls {
    param(
        [string]$BinaryPath,
        [string]$MsysBin,
        [string]$Destination
    )

    $objdump = Join-Path $MsysBin "objdump.exe"

    if (-not (Test-Path -LiteralPath $objdump)) {
        Write-Host "WARNING: objdump.exe was not found. Falling back to known MinGW runtime DLL names."

        $fallback = @(
            "libcrypto-3-x64.dll",
            "libgmp-10.dll",
            "libgmpxx-4.dll",
            "libstdc++-6.dll",
            "libgcc_s_seh-1.dll",
            "libwinpthread-1.dll"
        )

        foreach ($dll in $fallback) {
            $src = Join-Path $MsysBin $dll

            if (Test-Path -LiteralPath $src) {
                Copy-Item -LiteralPath $src -Destination (Join-Path $Destination $dll) -Force
                Write-Host "Copied DLL: $dll"
            }
        }

        return
    }

    $queue = New-Object System.Collections.Generic.Queue[string]
    $seen = @{}

    foreach ($dll in (Get-ImportedDllNames -ObjdumpExe $objdump -BinaryPath $BinaryPath)) {
        $queue.Enqueue($dll)
    }

    while ($queue.Count -gt 0) {
        $dll = $queue.Dequeue()

        if ($seen.ContainsKey($dll)) {
            continue
        }

        $seen[$dll] = $true
        $src = Join-Path $MsysBin $dll

        if (-not (Test-Path -LiteralPath $src)) {
            Write-Host "Skipping system or non-MSYS DLL: $dll"
            continue
        }

        $dst = Join-Path $Destination $dll
        Copy-Item -LiteralPath $src -Destination $dst -Force
        Write-Host "Copied DLL: $dll"

        foreach ($child in (Get-ImportedDllNames -ObjdumpExe $objdump -BinaryPath $src)) {
            if (-not $seen.ContainsKey($child)) {
                $queue.Enqueue($child)
            }
        }
    }
}

function Ensure-GitClone {
    param(
        [string]$Url,
        [string]$Directory
    )

    if (-not (Test-Path -LiteralPath (Join-Path $Directory ".git"))) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Directory) | Out-Null
        Invoke-NativeChecked -Command { & git clone $Url $Directory } -ErrorMessage "git clone failed: $Url"
    } else {
        Write-Host "Repository already exists: $Directory"
    }
}

function Install-GopathDependencies {
    $deps = @(
        @{ Url = "https://github.com/VictoriaMetrics/fastcache.git"; Directory = (Join-Path $Gopath "src\github.com\VictoriaMetrics\fastcache") },
        @{ Url = "https://github.com/shirou/gopsutil.git"; Directory = (Join-Path $Gopath "src\github.com\shirou\gopsutil") },
        @{ Url = "https://github.com/dlclark/regexp2.git"; Directory = (Join-Path $Gopath "src\github.com\dlclark\regexp2") },
        @{ Url = "https://github.com/go-sourcemap/sourcemap.git"; Directory = (Join-Path $Gopath "src\github.com\go-sourcemap\sourcemap") },
        @{ Url = "https://github.com/tklauser/go-sysconf.git"; Directory = (Join-Path $Gopath "src\github.com\tklauser\go-sysconf") },
        @{ Url = "https://github.com/tklauser/numcpus.git"; Directory = (Join-Path $Gopath "src\github.com\tklauser\numcpus") },
        @{ Url = "https://go.googlesource.com/sys"; Directory = (Join-Path $Gopath "src\golang.org\x\sys") }
    )

    foreach ($dep in $deps) {
        Ensure-GitClone -Url $dep.Url -Directory $dep.Directory
    }

    $regexp2Dir = Join-Path $Gopath "src\github.com\dlclark\regexp2"

    Push-Location $regexp2Dir
    try {
        Invoke-NativeChecked -Command { & git fetch --tags } -ErrorMessage "git fetch --tags failed for regexp2."
        Invoke-NativeChecked -Command { & git checkout v1.1.8 } -ErrorMessage "git checkout v1.1.8 failed for regexp2."
    } finally {
        Pop-Location
    }
}

function Patch-CypherDependencies {
    $regexp2Source = Join-Path $Gopath "src\github.com\dlclark\regexp2"
    $regexp2VendorParent = Join-Path $CypherDir "vendor\github.com\dlclark"
    $regexp2Vendor = Join-Path $regexp2VendorParent "regexp2"

    Remove-Item -LiteralPath $regexp2Vendor -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $regexp2VendorParent | Out-Null
    Copy-Item -LiteralPath $regexp2Source -Destination $regexp2VendorParent -Recurse -Force

    $dukLoggingPath = Join-Path $CypherDir "vendor\gopkg.in\olebedev\go-duktape.v3\duk_logging.c"

    if (Test-Path -LiteralPath $dukLoggingPath) {
        $content = Get-Content -LiteralPath $dukLoggingPath -Raw
        $content = $content -replace 'duk_uint8_t date_buf\[32\]', 'duk_uint8_t date_buf[64]'
        $content = $content -replace 'snprintf\(\(char \*\) date_buf, sizeof\(date_buf\),, ', 'snprintf((char *) date_buf, sizeof(date_buf), '
        $content = $content -replace 'sprintf\(\(char \*\) date_buf, "([^"]*)"', 'snprintf((char *) date_buf, sizeof(date_buf), "$1"'
        Set-Content -LiteralPath $dukLoggingPath -Value $content -NoNewline
    }
}

function Invoke-MsysPacmanChecked {
    param(
        [string]$Arguments,
        [string]$ErrorMessage
    )

    & $MsysBash -lc $Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "$ErrorMessage ExitCode=$LASTEXITCODE"
    }
}

function Update-Msys2Safely {
    Write-Host "Refreshing MSYS2 package database..."
    Invoke-MsysPacmanChecked -Arguments "pacman -Syy --noconfirm" -ErrorMessage "pacman database refresh failed."

    Write-Host "Updating MSYS2 core packages..."
    & $MsysBash -lc "pacman -Syu --noconfirm"

    if ($LASTEXITCODE -ne 0) {
        Write-Host "WARNING: pacman -Syu failed. Retrying once after forced database refresh..."
        Invoke-MsysPacmanChecked -Arguments "pacman -Syy --noconfirm" -ErrorMessage "pacman database refresh retry failed."
        Invoke-MsysPacmanChecked -Arguments "pacman -Syu --noconfirm" -ErrorMessage "pacman -Syu failed. Close all MSYS2 terminals and rerun this script."
    }

    Write-Host "Running second MSYS2 update pass..."
    & $MsysBash -lc "pacman -Su --noconfirm"

    if ($LASTEXITCODE -ne 0) {
        Write-Host "WARNING: pacman -Su failed. This can happen after MSYS2 core package updates."
        Write-Host "Close all MSYS2 terminals and rerun this script if the next package installation fails."
    }
}

Write-Step "0/10 Validate PowerShell and administrator context"

if (-not $PSVersionTable.PSVersion) {
    throw "This script must be run with PowerShell, not cmd.exe."
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Please run this script as Administrator PowerShell."
}

$MsysRoot = "C:\msys64"
$MsysBin = Join-Path $MsysRoot "$MsysFlavor\bin"
$MsysBash = Join-Path $MsysRoot "usr\bin\bash.exe"
$CypherRoot = Join-Path $Gopath "src\github.com\cypherium"
$CypherDir = Join-Path $CypherRoot "cypher"

Write-Step "1/10 Install or detect required Windows tools"

Install-WingetPackage -Ids @("Git.Git") -Name "Git" -Commands @("git.exe") -Paths @("C:\Program Files\Git\cmd\git.exe")
Install-GoWindows -Version $GoVersion
Install-WingetPackage -Ids @("MSYS2.MSYS2") -Name "MSYS2" -Paths @($MsysBash)
Install-WingetPackage -Ids @("OpenJS.NodeJS") -Name "Node.js" -Commands @("node.exe", "npm.cmd") -Paths @("C:\Program Files\nodejs\node.exe", "C:\Program Files\nodejs\npm.cmd")

Add-ProcessPath "C:\Program Files\Git\cmd"
Add-ProcessPath "C:\Program Files\Git\bin"
Add-ProcessPath "C:\Program Files\Go\bin"
Add-ProcessPath "C:\Program Files\nodejs"
Add-ProcessPath (Join-Path $env:APPDATA "npm")
Add-ProcessPath $MsysBin

$goBin = Get-GoBinPath
$goExe = Join-Path $goBin "go.exe"

Add-ProcessPath $goBin

Assert-GoVersionSupported -GoExe $goExe -ExpectedVersion $GoVersion
Invoke-NativeChecked -Command { & git --version } -ErrorMessage "git check failed."
Invoke-NativeChecked -Command { & npm --version } -ErrorMessage "npm check failed."
Invoke-NativeChecked -Command { & npm install -g pm2 } -ErrorMessage "pm2 install failed."

Add-ProcessPath (Join-Path $env:APPDATA "npm")

Invoke-NativeChecked -Command { & pm2 --version } -ErrorMessage "pm2 check failed."

Write-Step "2/10 Install MSYS2 CGO dependencies"

if (-not (Test-Path -LiteralPath $MsysBash)) {
    throw "MSYS2 bash not found: $MsysBash"
}

$mingwPrefix = if ($MsysFlavor -eq "ucrt64") { "mingw-w64-ucrt-x86_64" } else { "mingw-w64-x86_64" }

Update-Msys2Safely

Invoke-MsysPacmanChecked -Arguments "pacman -S --needed --noconfirm make cmake m4 texinfo ${mingwPrefix}-gcc ${mingwPrefix}-binutils ${mingwPrefix}-openssl ${mingwPrefix}-gmp" -ErrorMessage "MSYS2 dependency install failed."

$cc = Join-Path $MsysBin "gcc.exe"
$cxx = Join-Path $MsysBin "g++.exe"

if (-not (Test-Path -LiteralPath $cc)) {
    throw "gcc.exe not found: $cc"
}

if (-not (Test-Path -LiteralPath $cxx)) {
    throw "g++.exe not found: $cxx"
}

Invoke-NativeChecked -Command { & $cc --version } -ErrorMessage "gcc check failed."

Write-Step "3/10 Clone cypher under the GOPATH import path used by the codebase"

New-Item -ItemType Directory -Force -Path $CypherRoot | Out-Null

if (-not (Test-Path -LiteralPath (Join-Path $CypherDir ".git"))) {
    Invoke-NativeChecked -Command { & git clone $RepoUrl $CypherDir } -ErrorMessage "git clone failed."
} else {
    Write-Host "Repository already exists: $CypherDir"
}

Set-Location $CypherDir

Invoke-NativeChecked -Command { & git fetch --all } -ErrorMessage "git fetch failed."

if (-not [string]::IsNullOrWhiteSpace($RepoBranch)) {
    Invoke-NativeChecked -Command { & git checkout $RepoBranch } -ErrorMessage "git checkout failed for branch/ref: $RepoBranch"
}

Write-Host "Git branch:"
& git branch --show-current

Write-Host "Git commit:"
& git rev-parse HEAD

Write-Step "4/10 Configure GOPATH-mode Go and CGO for this process"

$env:GOROOT = Split-Path -Parent $goBin
$env:GOPATH = $Gopath
$env:GO111MODULE = "off"
$env:CGO_ENABLED = "1"
$env:CC = $cc
$env:CXX = $cxx
$env:CGO_CFLAGS_ALLOW = ".*"
$env:CGO_LDFLAGS_ALLOW = ".*"
$env:Path = "$goBin;$MsysBin;C:\Program Files\Git\cmd;C:\Program Files\Git\bin;C:\Program Files\nodejs;$(Join-Path $env:APPDATA 'npm');$env:Path"

Remove-Item Env:CGO_LDFLAGS -ErrorAction SilentlyContinue
Remove-Item Env:CGO_CFLAGS -ErrorAction SilentlyContinue

Write-Host "GOROOT=$env:GOROOT"
Write-Host "GOPATH=$env:GOPATH"
Write-Host "GO111MODULE=$(go env GO111MODULE)"
Write-Host "CGO_ENABLED=$(go env CGO_ENABLED)"
Write-Host "CC=$env:CC"

Write-Step "5/10 Copy Windows BLS static libraries into the cgo library directory"

Copy-BLSWindowsLibraries -CypherDir $CypherDir

Write-Step "6/10 Clone GOPATH dependencies"

Install-GopathDependencies

Write-Step "7/10 Patch dependencies"

Patch-CypherDependencies

Write-Step "7.5/10 Patch Windows BLS/GMP cgo LDFLAGS"

Patch-WindowsBLSCgoLDFLAGS -CypherDir $CypherDir

Write-Step "8/10 Build cypher.exe with direct external linker mode"

Remove-Item (Join-Path $CypherDir "build\bin") -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Join-Path $CypherDir "build\bin") | Out-Null

Invoke-NativeChecked `
    -Command {
        & $goExe clean -cache
    } `
    -ErrorMessage "go clean cache failed."

Invoke-NativeChecked `
    -Command {
        & $goExe build `
            -ldflags "-linkmode external -extldflags=-Wl,--disable-dynamicbase,--disable-high-entropy-va,--image-base,0x400000,-Bstatic,-lgmpxx,-lgmp,-lstdc++,-Bdynamic" `
            -o (Join-Path $CypherDir "build\bin\cypher.exe") `
            .\cmd\cypher
    } `
    -ErrorMessage "direct go build failed."

$CypherExe = Join-Path $CypherDir "build\bin\cypher.exe"

if (-not (Test-Path -LiteralPath $CypherExe)) {
    throw "cypher.exe was not created at expected path: $CypherExe"
}

Get-Item -LiteralPath $CypherExe

Write-Step "9/10 Copy MinGW runtime DLLs required by cypher.exe and verify binary"

Copy-DependentDlls -BinaryPath $CypherExe -MsysBin $MsysBin -Destination (Join-Path $CypherDir "build\bin")

$binPath = Join-Path $CypherDir "build\bin"
$env:Path = "$binPath;$MsysBin;$goBin;$env:Path"

Invoke-NativeChecked -Command { & $CypherExe version } -ErrorMessage "cypher.exe version check failed."
Invoke-NativeChecked -Command { & $CypherExe help } -ErrorMessage "cypher.exe help check failed."

Write-Step "10/10 Create data directory, initialize genesis, and register pm2"

if ([string]::IsNullOrWhiteSpace($DataDir)) {
    $DataDir = Join-Path $CypherDir "chaindbname"
}

New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

if ([string]::IsNullOrWhiteSpace($GenesisFile)) {
    $GenesisFile = Join-Path $CypherDir "genesistest.json"
}

if (-not (Test-Path -LiteralPath $GenesisFile)) {
    throw "Genesis file not found: $GenesisFile"
}

$genesisJson = Get-Content -LiteralPath $GenesisFile -Raw | ConvertFrom-Json
$chainId = $genesisJson.config.chainId

if ($null -eq $chainId) {
    throw "Genesis chainId was not found at config.chainId. GenesisFile=$GenesisFile"
}

if (($ExpectedChainId -ne 0) -and ([Int64]$chainId -ne $ExpectedChainId)) {
    throw "Unexpected genesis chainId. Expected $ExpectedChainId, actual $chainId. GenesisFile=$GenesisFile"
}

Write-Host "Cypher dir: $CypherDir"
Write-Host "Data dir: $DataDir"
Write-Host "Genesis file: $GenesisFile"
Write-Host "Genesis chainId: $chainId"

Get-FileHash -LiteralPath $GenesisFile -Algorithm SHA256 | Format-List

if ($CleanData) {
    Write-Host "CleanData was specified. Removing old chain database files but preserving keystore and node identity."

    $cleanTargets = @(
        (Join-Path $DataDir "chaindata"),
        (Join-Path $DataDir "transactions.rlp"),
        (Join-Path $DataDir "triecache"),
        (Join-Path $DataDir "cypher\chaindata"),
        (Join-Path $DataDir "cypher\transactions.rlp"),
        (Join-Path $DataDir "cypher\triecache"),
        (Join-Path $DataDir "cypher\colossusX"),
        (Join-Path $DataDir "history")
    )

    foreach ($target in $cleanTargets) {
        if (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Recurse -Force
            Write-Host "Removed: $target"
        }
    }
}

Invoke-NativeChecked -Command { & $CypherExe --datadir $DataDir init $GenesisFile } -ErrorMessage "cypher genesis init failed."

$StartScript = Join-Path $CypherDir "start-cypher.ps1"

$startScriptContent = @"
Set-StrictMode -Version Latest
`$ErrorActionPreference = "Stop"

Set-Location `$PSScriptRoot

`$ExternalIp = (Invoke-RestMethod -Uri "https://ipv4.icanhazip.com" -TimeoutSec 10).Trim()

& .\build\bin\cypher.exe ``
  --verbosity 4 ``
  --rnetport 7200 ``
  --syncmode full ``
  --nat "extip:`$ExternalIp" ``
  --ws ``
  --ws.addr 0.0.0.0 ``
  --ws.port 9251 ``
  --ws.origins "*" ``
  --metrics ``
  --http ``
  --http.addr 0.0.0.0 ``
  --http.port 8000 ``
  --http.api eth,web3,net,txpool ``
  --http.corsdomain "*" ``
  --port 6000 ``
  --datadir "$DataDir" ``
  --networkid $ExpectedChainId ``
  --gcmode archive ``
  --bootnodes enode://fe37c100a751e024f9bce73764b7360edf7690619e6e0bf2473f876834adf200feb68f17562a6eea77f263e947744978269db295c2ece9bfc24ad2be14eb69f1@161.97.184.220:6800
"@

Set-Content -LiteralPath $StartScript -Value $startScriptContent -Encoding UTF8

$PowerShellCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue

if (-not $PowerShellCommand) {
    $PowerShellCommand = Get-Command powershell.exe -ErrorAction Stop
}

$PowerShellExe = $PowerShellCommand.Source

try {
    & pm2 delete cypher-node 2>$null
} catch {
    Write-Host "cypher-node was not registered in PM2. Continuing..."
}
$global:LASTEXITCODE = 0
$Error.Clear()

Invoke-NativeChecked -Command { & pm2 start $PowerShellExe --name cypher-node -- -NoProfile -ExecutionPolicy Bypass -File $StartScript } -ErrorMessage "pm2 start failed."
Invoke-NativeChecked -Command { & pm2 save } -ErrorMessage "pm2 save failed."

Write-Host ""
Write-Host "PM2 started cypher-node."
Write-Host "Check status with:"
Write-Host "  pm2 status"
Write-Host "  pm2 logs cypher-node"
Write-Host ""
Write-Host "To enable auto-start after reboot, also run:"
Write-Host "  pm2 startup"
Write-Host ""
Write-Host "Done."
