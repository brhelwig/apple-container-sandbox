#!/usr/bin/env bash
set -euo pipefail

if [ ! -e "$HOME/.sandbox-seeded" ]; then
    cp -a /etc/skel/. "$HOME/" 2>/dev/null || true
    touch "$HOME/.sandbox-seeded"
fi

# Not specific to k3s — it is also what lets `gcloud container clusters
# get-credentials` save a context — so it runs whether or not a cluster is
# configured. A failure here must never keep you out of a shell, and the same
# goes for the two below.
/usr/local/bin/sandbox-kubeconfig || echo "sandbox-kubeconfig failed" >&2

# Ahead of the setup hook so project setup can rely on the cluster. `up` returns
# as soon as the server is launched, so the shell isn't held up while the
# cluster converges.
if [ -x /usr/local/bin/sandbox-k3s ] && /usr/local/bin/sandbox-k3s enabled; then
    /usr/local/bin/sandbox-k3s up || echo "sandbox-k3s up failed; see /var/log/k3s.log" >&2
fi

# `up` refuses until the sandbox has been signed in once, and says which command
# does that.
if [ -x /usr/local/bin/sandbox-code ] && /usr/local/bin/sandbox-code enabled; then
    /usr/local/bin/sandbox-code up || true
fi

/usr/local/bin/sandbox-setup || true

exec "$@"
