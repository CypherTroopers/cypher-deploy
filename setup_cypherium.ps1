# setup_cypherium.ps1
$ErrorActionPreference = "Stop"

$GoVersion = "1.24.1"
$GoMsi = "go$GoVersion.windows-amd64.msi"
$GoUrl = "https://go.dev/dl/$GoMsi"

$env:GOPATH = "$env:USERPROFILE\go"
$env:GO111MODULE = "off"
$env:Path = "C:\Go\bin;C:\msys64\mingw64\bin;C:\msys64\usr\bin;$env:USERPROFILE\AppData\Roaming\npm;$env:Path"

[Environment]::SetEnvironmentVariable("GOPATH", $env:GOPATH, "User")
[Environment]::SetEnvironmentVariable("GO111MODULE", "off", "User")

Write-Host "[1/10] Install Git / Node.js / MSYS2 / Go..."

winget install --id Git.Git -e --accept-package-agreements --accept-source-agreements
winget install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements
winget install --id MSYS2.MSYS2 -e --accept-package-agreements --accept-source-agreements

cd $env:TEMP
Invoke-WebRequest -Uri $GoUrl -OutFile $GoMsi
Start-Process msiexec.exe -Wait -ArgumentList "/i `"$GoMsi`" /qn"

$env:Path = "C:\Go\bin;C:\msys64\mingw64\bin;C:\msys64\usr\bin;$env:USERPROFILE\AppData\Roaming\npm;$env:Path"

go version
go env -w GO111MODULE=off

Write-Host "[2/10] Install MSYS2 build tools..."

$bash = "C:\msys64\usr\bin\bash.exe"

& $bash -lc "pacman -Sy --noconfirm"
& $bash -lc "pacman -S --noconfirm mingw-w64-x86_64-gcc mingw-w64-x86_64-cmake mingw-w64-x86_64-openssl mingw-w64-x86_64-gmp make git curl wget mingw-w64-x86_64-pkg-config"

Write-Host "[3/10] Install pm2..."

npm install -g pm2

Write-Host "[4/10] Clone cypher repo..."

$CypheriumPath = "$env:GOPATH\src\github.com\cypherium"
New-Item -ItemType Directory -Force -Path $CypheriumPath | Out-Null
cd $CypheriumPath

if (!(Test-Path ".\cypher")) {
    git clone https://github.com/CypherTroopers/cypher.git
}

cd ".\cypher"
git fetch --all
git checkout ecdsa_1.1_test_colossus-Xv2test

if (Test-Path ".\crypto\bls\lib\windows") {
    Copy-Item ".\crypto\bls\lib\windows\*" ".\crypto\bls\lib\" -Force
} else {
    Write-Host "WARNING: .\crypto\bls\lib\windows not found. Linux BLS library cannot be used on native Windows."
}

Write-Host "[5/10] Clone GOPATH dependencies..."

New-Item -ItemType Directory -Force -Path "$env:GOPATH\src\github.com\VictoriaMetrics" | Out-Null
cd "$env:GOPATH\src\github.com\VictoriaMetrics"
if (!(Test-Path ".\fastcache")) {
    git clone https://github.com/VictoriaMetrics/fastcache.git
}

New-Item -ItemType Directory -Force -Path "$env:GOPATH\src\github.com\shirou" | Out-Null
cd "$env:GOPATH\src\github.com\shirou"
if (!(Test-Path ".\gopsutil")) {
    git clone https://github.com/shirou/gopsutil.git
}

New-Item -ItemType Directory -Force -Path "$env:GOPATH\src\github.com\dlclark" | Out-Null
cd "$env:GOPATH\src\github.com\dlclark"
if (!(Test-Path ".\regexp2")) {
    git clone https://github.com/dlclark/regexp2.git
}

cd ".\regexp2"
git fetch --tags
git checkout v1.1.8

New-Item -ItemType Directory -Force -Path "$env:GOPATH\src\github.com\go-sourcemap" | Out-Null
cd "$env:GOPATH\src\github.com\go-sourcemap"
if (!(Test-Path ".\sourcemap")) {
    git clone https://github.com/go-sourcemap/sourcemap.git
}

New-Item -ItemType Directory -Force -Path "$env:GOPATH\src\github.com\tklauser" | Out-Null
cd "$env:GOPATH\src\github.com\tklauser"
if (!(Test-Path ".\go-sysconf")) {
    git clone https://github.com/tklauser/go-sysconf.git
}
if (!(Test-Path ".\numcpus")) {
    git clone https://github.com/tklauser/numcpus.git
}

New-Item -ItemType Directory -Force -Path "$env:GOPATH\src\golang.org\x" | Out-Null
cd "$env:GOPATH\src\golang.org\x"
if (!(Test-Path ".\sys")) {
    git clone https://go.googlesource.com/sys
}

Write-Host "[6/10] Patch dependencies..."

cd "$env:GOPATH\src\github.com\cypherium\cypher"

Remove-Item -Recurse -Force ".\vendor\github.com\dlclark\regexp2" -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path ".\vendor\github.com\dlclark" | Out-Null
Copy-Item "$env:GOPATH\src\github.com\dlclark\regexp2" ".\vendor\github.com\dlclark\regexp2" -Recurse -Force

$DukLoggingPath = "$env:GOPATH\src\github.com\cypherium\cypher\vendor\gopkg.in\olebedev\go-duktape.v3\duk_logging.c"

if (Test-Path $DukLoggingPath) {
    $content = Get-Content $DukLoggingPath -Raw
    $content = $content -replace 'duk_uint8_t date_buf\[32\]', 'duk_uint8_t date_buf[64]'
    $content = $content -replace 'snprintf\(\(char \*\) date_buf, sizeof\(date_buf\),, ', 'snprintf((char *) date_buf, sizeof(date_buf), '
    Set-Content $DukLoggingPath $content
}

Write-Host "[7/10] Build cypher..."

cd "$env:GOPATH\src\github.com\cypherium\cypher"

go run build/ci.go install ./cmd/cypher

Write-Host "[8/10] Init chain data..."

.\build\bin\cypher.exe --datadir chaindbname init .\genesistest.json

Write-Host "[9/10] Create start script..."

$StartScript = @'
$ErrorActionPreference = "Stop"

cd "$PSScriptRoot"

$ExternalIp = Invoke-RestMethod -Uri "https://ifconfig.io"

.\build\bin\cypher.exe `
  --verbosity 4 `
  --rnetport 7200 `
  --syncmode full `
  --nat "extip:$ExternalIp" `
  --ws `
  --ws.addr 0.0.0.0 `
  --ws.port 9251 `
  --ws.origins "*" `
  --metrics `
  --http `
  --http.addr 0.0.0.0 `
  --http.port 8000 `
  --http.api eth,web3,net,txpool `
  --http.corsdomain "*" `
  --port 6000 `
  --datadir chaindbname `
  --networkid 12367 `
  --gcmode archive `
  --bootnodes enode://fe37c100a751e024f9bce73764b7360edf7690619e6e0bf2473f876834adf200feb68f17562a6eea77f263e947744978269db295c2ece9bfc24ad2be14eb69f1@161.97.184.220:6800 `
  console
'@

Set-Content -Path ".\start-cypher.ps1" -Value $StartScript

Write-Host "[10/10] Register pm2..."

pm2 delete cypher-node 2>$null
pm2 start powershell --name cypher-node -- -ExecutionPolicy Bypass -File "$env:GOPATH\src\github.com\cypherium\cypher\start-cypher.ps1"
pm2 save

Write-Host ""
Write-Host "PM2 started cypher-node."
Write-Host "Check status with:"
Write-Host "  pm2 status"
Write-Host "  pm2 logs cypher-node"
Write-Host ""
Write-Host "Done."
