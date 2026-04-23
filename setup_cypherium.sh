#!/usr/bin/env bash
set -euo pipefail

export PATH=/usr/local/go/bin:/usr/local/bin:$PATH
export GOPATH="$HOME/go"
export GO111MODULE=off

echo "[1/10] apt update/upgrade..."
sudo apt update
sudo apt upgrade -y
sudo apt full-upgrade -y
sudo apt autoremove -y
sudo apt autoclean -y

echo "[2/10] install Go 1.24.1..."
cd /tmp
wget -4 -O go1.24.1.linux-amd64.tar.gz https://go.dev/dl/go1.24.1.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.24.1.linux-amd64.tar.gz

go version || true
go env -w GO111MODULE=off

grep -qxF 'export PATH=/usr/local/go/bin:/usr/local/bin:$PATH' ~/.bashrc || echo 'export PATH=/usr/local/go/bin:/usr/local/bin:$PATH' >> ~/.bashrc
grep -qxF 'export GOPATH=$HOME/go' ~/.bashrc || echo 'export GOPATH=$HOME/go' >> ~/.bashrc
grep -qxF 'export GO111MODULE=off' ~/.bashrc || echo 'export GO111MODULE=off' >> ~/.bashrc

echo "[3/10] install build dependencies..."
sudo apt-get update
sudo apt-get install -y \
  gcc cmake libssl-dev openssl libgmp-dev \
  bzip2 m4 build-essential git curl libc-dev \
  wget texinfo nodejs npm pcscd

echo "[4/10] install latest node via n and pm2..."
sudo npm install -g n
sudo n stable
sudo apt purge -y nodejs npm
sudo apt autoremove -y

export PATH=/usr/local/bin:$PATH
hash -r

sudo /usr/local/bin/npm install -g pm2

echo "[5/10] clone cypher repo..."
mkdir -p "$GOPATH/src/github.com/cypherium"
cd "$GOPATH/src/github.com/cypherium"

if [ ! -d cypher ]; then
  git clone https://github.com/CypherTroopers/cypher.git
fi

cd cypher
git fetch --all
git checkout ecdsa_1.1_test_colossus-Xv2test
cp -f ./crypto/bls/lib/linux/* ./crypto/bls/lib/

echo "[6/10] clone GOPATH dependencies..."
mkdir -p "$GOPATH/src/github.com/VictoriaMetrics"
cd "$GOPATH/src/github.com/VictoriaMetrics"
[ -d fastcache ] || git clone https://github.com/VictoriaMetrics/fastcache.git

mkdir -p "$GOPATH/src/github.com/shirou"
cd "$GOPATH/src/github.com/shirou"
[ -d gopsutil ] || git clone https://github.com/shirou/gopsutil.git

mkdir -p "$GOPATH/src/github.com/dlclark"
cd "$GOPATH/src/github.com/dlclark"
if [ ! -d regexp2 ]; then
  git clone https://github.com/dlclark/regexp2.git
fi
cd regexp2
git fetch --tags
git checkout v1.1.8

mkdir -p "$GOPATH/src/github.com/go-sourcemap"
cd "$GOPATH/src/github.com/go-sourcemap"
[ -d sourcemap ] || git clone https://github.com/go-sourcemap/sourcemap.git

mkdir -p "$GOPATH/src/github.com/tklauser"
cd "$GOPATH/src/github.com/tklauser"
[ -d go-sysconf ] || git clone https://github.com/tklauser/go-sysconf.git
[ -d numcpus ] || git clone https://github.com/tklauser/numcpus.git

mkdir -p "$GOPATH/src/golang.org/x"
cd "$GOPATH/src/golang.org/x"
[ -d sys ] || git clone https://go.googlesource.com/sys

echo "[7/10] patch dependencies..."

cd "$GOPATH/src/github.com/cypherium/cypher"

# Pin regexp2 into vendor directory
rm -rf vendor/github.com/dlclark/regexp2
mkdir -p vendor/github.com/dlclark
cp -a "$GOPATH/src/github.com/dlclark/regexp2" vendor/github.com/dlclark/

# Safely patch duk_logging.c
DUK_LOGGING_PATH="$GOPATH/src/github.com/cypherium/cypher/vendor/gopkg.in/olebedev/go-duktape.v3/duk_logging.c"

if [ -f "$DUK_LOGGING_PATH" ]; then
  sed -i 's/duk_uint8_t date_buf\[32\]/duk_uint8_t date_buf[64]/' "$DUK_LOGGING_PATH"
  sed -i 's/snprintf((char \*) date_buf, sizeof(date_buf),, /snprintf((char *) date_buf, sizeof(date_buf), /g' "$DUK_LOGGING_PATH"
  sed -i 's/sprintf((char \*) date_buf, "\(.*\)"/snprintf((char *) date_buf, sizeof(date_buf), "\1"/' "$DUK_LOGGING_PATH" || true
fi

echo "[8/10] build cypher..."
cd "$GOPATH/src/github.com/cypherium/cypher"
make clean
make cypher

echo "[9/10] init chain data..."
./build/bin/cypher --datadir chaindbname init ./genesistest.json

echo "[10/10] create start script and register pm2..."
cat <<'EOS' > start-cypher.sh
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

./build/bin/cypher \
  --verbosity 4 \
  --rnetport 7200 \
  --syncmode full \
  --nat extip:$(curl -4 -s ifconfig.io) \
  --ws \
  --ws.addr 0.0.0.0 \
  --ws.port 9251 \
  --ws.origins "*" \
  --metrics \
  --http \
  --http.addr 0.0.0.0 \
  --http.port 8000 \
  --http.api eth,web3,net,txpool \
  --http.corsdomain "*" \
  --port 6000 \
  --datadir chaindbname \
  --networkid 12367 \
  --gcmode archive \
  --bootnodes enode://fe37c100a751e024f9bce73764b7360edf7690619e6e0bf2473f876834adf200feb68f17562a6eea77f263e947744978269db295c2ece9bfc24ad2be14eb69f1@161.97.184.220:6800 \
  console
EOS

chmod +x start-cypher.sh

/usr/local/bin/pm2 delete cypher-node >/dev/null 2>&1 || true
/usr/local/bin/pm2 start ./start-cypher.sh --name cypher-node
/usr/local/bin/pm2 save

echo
echo "Done."
echo "Next commands:"
echo "  source ~/.bashrc"
echo "  /usr/local/bin/pm2 logs cypher-node"
echo "  /usr/local/bin/pm2 status"
EOF

chmod +x setup_cypherium.sh
./setup_cypherium.sh
