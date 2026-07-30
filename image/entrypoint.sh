#!/usr/bin/env bash
# Seed a fresh (bind-mounted, empty) $HOME from /etc/skel on first launch, start
# the k3s cluster if one is configured, run the per-sandbox setup hook, then
# exec the container command.
set -euo pipefail

if [ ! -e "$HOME/.sandbox-seeded" ]; then
    cp -a /etc/skel/. "$HOME/" 2>/dev/null || true
    touch "$HOME/.sandbox-seeded"
fi

# Start the cluster when [k3s].enabled is set, ahead of the setup hook so
# project setup can rely on it. `up` returns as soon as the server is launched,
# so the shell isn't held up while the cluster converges, and a failure here
# must never keep you out of a shell.
if [ -x /usr/local/bin/sandbox-k3s ] && /usr/local/bin/sandbox-k3s enabled; then
    /usr/local/bin/sandbox-k3s up || echo "sandbox-k3s up failed; see /var/log/k3s.log" >&2
fi

/usr/local/bin/sandbox-setup || true

exec "$@"
