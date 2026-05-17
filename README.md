# cypher-deploy

## Setup Linux/Windows

```bash
git clone https://github.com/CypherTroopers/cypher-deploy.git
cd cypher-deploy
 ```
linux
 ```
chmod +x setup_cypherium2.sh
./setup_cypherium2.sh
 ```
Windows
 ```
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" /v DisabledComponents /t REG_DWORD /d 32 /f
```
```
Restart-Computer
```
```
foreach ($p in 6000,7200,8000,9251) {
  New-NetFirewallRule -DisplayName "Cypher TCP $p" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $p
  New-NetFirewallRule -DisplayName "Cypher UDP $p" -Direction Inbound -Action Allow -Protocol UDP -LocalPort $p
}
```
```
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
./setup_cypherium2.ps1
```
## Check logs

```bash
pm2 logs
 ```
```bash
Ctrl+C
 ```
## start mining (console)Linux/Windows
```bash
cd ~/go/src/github.com/cypherium/cypher
 ```
Linux
 ```
./build/bin/cypher attach ipc:./chaindbname/cypher.ipc
 ```
Windows
```
.\build\bin\cypher.exe attach ipc:\\.\pipe\cypher.ipc
```
console command Linux/Windows
 ```
personal.newAccount("your password")
 ```
 ```
miner.start(1, "your address here", "your password")
 ```








