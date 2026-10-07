FROM tailscale/tailscale:stable

RUN apk add --no-cache openssh

COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /usr/local/sbin/railway-entrypoint
RUN chmod 0755 /usr/local/sbin/railway-entrypoint

ENV TS_USERSPACE=true \
    TS_STATE_DIR=/data/tailscale \
    TS_AUTH_ONCE=true \
    TS_HOSTNAME=railway-tail-node \
    SSH_PORT=22 \
    TAILSCALE_SSH_PORT=2222

EXPOSE 22 2222
ENTRYPOINT ["/usr/local/sbin/railway-entrypoint"]
