# Alta Relay Releases

Pre-built binaries and deployment scripts for the Alta Relay system.

## Quick Install

### Server (Linux)

```bash
curl -sSL https://raw.githubusercontent.com/nmelo/alta-releases/main/deploy-server.sh | sudo bash
```

Options: `--port 5000` `--min-port 5010` `--max-port 5100` `--api-key KEY`

### Proxy (Raspberry Pi / Linux)

```bash
curl -sSL https://raw.githubusercontent.com/nmelo/alta-releases/main/deploy-proxy.sh | sudo bash -s -- \
  --server YOUR_SERVER:5000 \
  --session 12345678 \
  --drone 192.168.0.203
```

### Client (Windows)

Run PowerShell as Administrator:

```powershell
irm https://raw.githubusercontent.com/nmelo/alta-releases/main/deploy-client.ps1 | iex
# Then run:
Install-AltaClient -Server "YOUR_SERVER:5000" -Session "12345678"
```

## Manual Download

Download binaries from [Releases](https://github.com/nmelo/alta-releases/releases/latest):

| Binary | Platform | Purpose |
|--------|----------|---------|
| `alta-server-linux-amd64` | Linux x64 | Cloud relay server |
| `alta-proxy-linux-amd64` | Linux x64 | Field-side proxy |
| `alta-proxy-linux-arm` | Raspberry Pi | Field-side proxy |
| `alta-proxy-windows-amd64.exe` | Windows | Field-side proxy |
| `alta-client-windows-amd64.exe` | Windows | Operator-side client |

## Service Management

```bash
# Linux (server/proxy)
sudo systemctl status alta-relay    # or alta-proxy
sudo journalctl -u alta-relay -f    # View logs

# Windows (client)
nssm status alta-client
nssm restart alta-client
```

## Uninstall

```bash
# Server
curl -sSL https://raw.githubusercontent.com/nmelo/alta-releases/main/deploy-server.sh | sudo bash -s -- --uninstall

# Proxy
curl -sSL https://raw.githubusercontent.com/nmelo/alta-releases/main/deploy-proxy.sh | sudo bash -s -- --uninstall

# Client (Windows PowerShell as Admin)
nssm stop alta-client; nssm remove alta-client confirm; Remove-Item -Recurse C:\alta-relay
```
