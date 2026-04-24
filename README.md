# cypher-deploy

## Setup

```bash
git clone https://github.com/CypherTroopers/cypher-deploy.git
cd cypher-deploy
 ```
linux
 ```
chmod +x setup_cypherium.sh
./setup_cypherium.sh
 ```
powershell
 ```
powershell -ExecutionPolicy Bypass -File .\setup_cypherium.ps1
 ```

## Check logs

```bash
pm2 logs
 ```
## start mining (console)
```bash
cd ~/go/src/github.com/cypherium/cypher
 ```
 ```
./build/bin/cypher attach ipc:./chaindbname/cypher.ipc
 ```
 ```
personal.newAccount("your password")
 ```
 ```
miner.start(1, "your address here", "your password")
 ```








