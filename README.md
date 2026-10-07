# Railway Tailscale container with OpenSSH

The container joins your Tailscale tailnet and runs OpenSSH locally. Because Railway normally does not provide `/dev/net/tun`, the image uses Tailscale userspace networking and `tailscale serve` to forward a private tailnet TCP port to the local SSH server. No Railway public domain or TCP Proxy is required.

## Railway configuration

Deploy this repository with **GitHub Repository**. Then:

1. Attach a persistent Volume at `/data`.
2. Add these Variables:

```text
TS_AUTHKEY=<fresh non-ephemeral Tailscale auth key>
TS_STATE_DIR=/data/tailscale
TS_AUTH_ONCE=true
TS_USERSPACE=true
TS_HOSTNAME=railway-tail-node
SSH_AUTHORIZED_KEY=<your SSH public key, one line>
```

Generate a key on Windows if needed:

```powershell
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\railway_tail"
Get-Content "$env:USERPROFILE\.ssh\railway_tail.pub"
```

Put only the `.pub` output into `SSH_AUTHORIZED_KEY`. Keep the private key on your computer. Revoke any auth key previously pasted into chat and create a replacement.

## Connect through Tailscale

After deployment, the service joins the tailnet and exposes the local SSH server privately on Tailscale TCP port `2222`:

```powershell
ssh -i "$env:USERPROFILE\.ssh\railway_tail" -p 2222 root@100.87.94.110
```

You can use the stable MagicDNS name instead of the IP if enabled:

```powershell
ssh -i "$env:USERPROFILE\.ssh\railway_tail" -p 2222 root@railway-tail-node
```

This is ordinary OpenSSH authenticated by your public key, but the connection stays inside the tailnet. Railway's public networking settings are not used. Tailscale's raw TCP Serve forwarder is specifically intended for protocols such as SSH and forwards the tailnet port to a local TCP service. ([Tailscale docs](https://tailscale.com/docs/reference/tailscale-cli/serve))

The `/data` volume preserves both the Tailscale node identity and the SSH host key, while a non-ephemeral auth key prevents each restart from creating a new node. The container does not provide a public SSH endpoint.
