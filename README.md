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
PowerShell
 ```
Set-ExecutionPolicy Bypass -Scope Process -Force
.\setup_cypherium.ps1
 ```

## Check logs

```bash
pm2 logs
 ```
```bash
Ctrl+C
 ```
## start mining (console)
```bash
cd ~/go/src/github.com/cypherium/cypher
 ```
Linux
 ```
./build/bin/cypher attach ipc:./chaindbname/cypher.ipc
 ```
PowerShell
```
.\build\bin\cypher.exe attach ipc:\\.\pipe\cypher.ipc
```
console command
 ```
personal.newAccount("your password")
 ```
 ```
miner.start(1, "your address here", "your password")
 ```








