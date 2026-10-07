#!/bin/sh
set -eu

: "${TS_STATE_DIR:=/data/tailscale}"
: "${SSH_AUTHORIZED_KEY:?Set SSH_AUTHORIZED_KEY to your SSH public key in Railway Variables}"
: "${SSH_PORT:=22}"
: "${TAILSCALE_SSH_PORT:=2222}"

mkdir -p /root/.ssh /run/sshd /data/ssh "$TS_STATE_DIR"
chmod 700 /root/.ssh /data/ssh "$TS_STATE_DIR"
printf '%s\n' "$SSH_AUTHORIZED_KEY" > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

if [ ! -s /data/ssh/ssh_host_ed25519_key ]; then
  ssh-keygen -q -t ed25519 -N '' -f /data/ssh/ssh_host_ed25519_key
fi
chmod 600 /data/ssh/ssh_host_ed25519_key
chmod 644 /data/ssh/ssh_host_ed25519_key.pub

/usr/sbin/sshd -t -f /etc/ssh/sshd_config
/usr/sbin/sshd -D -e -f /etc/ssh/sshd_config &
sshd_pid=$!
/usr/local/bin/containerboot &
tailscale_pid=$!

cleanup() {
  kill "$sshd_pid" "$tailscale_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Wait until containerboot has authenticated the node.
tailscale wait --timeout=120s

# Userspace networking has no tailscale0 interface. Tailscale Serve's raw TCP
# forwarder makes the loopback SSH daemon available privately to the tailnet.
tailscale serve --tcp="$TAILSCALE_SSH_PORT" "tcp://127.0.0.1:${SSH_PORT}" --bg

echo "Tailscale SSH bridge ready: ssh -p ${TAILSCALE_SSH_PORT} root@<tailscale-ip>"
tailscale status

tail -f /dev/null &
wait "$tailscale_pid"
