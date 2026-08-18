#!/usr/bin/env bash
set -euo pipefail

if [ ! -e "$HOME/.sandbox-seeded" ]; then
    cp -a /etc/skel/. "$HOME/" 2>/dev/null || true
    touch "$HOME/.sandbox-seeded"
fi

/usr/local/bin/sandbox-kubeconfig || echo "sandbox-kubeconfig failed" >&2

/usr/local/bin/sandbox-k3s up || echo "sandbox-k3s up failed; see /var/log/k3s.log" >&2

/usr/local/bin/sandbox-code up || true

/usr/local/bin/sandbox-setup || true

exec "$@"
