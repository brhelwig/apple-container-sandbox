#!/usr/bin/env bash
set -euo pipefail

if [ ! -e "$HOME/.sandbox-seeded" ]; then
    cp -a /etc/skel/. "$HOME/" 2>/dev/null || true
    touch "$HOME/.sandbox-seeded"
fi

# Not specific to k3s — it is also what lets `gcloud container clusters
# get-credentials` save a context. A failure here must never keep you out of a
# shell, and the same goes for the two below.
/usr/local/bin/sandbox-kubeconfig || echo "sandbox-kubeconfig failed" >&2

# Ahead of the setup hook so project setup can rely on the cluster. `up` returns
# as soon as the server is launched, so the shell isn't held up while the
# cluster converges.
/usr/local/bin/sandbox-k3s up || echo "sandbox-k3s up failed; see /var/log/k3s.log" >&2

# `up` refuses until the sandbox has been signed in once, and says which command
# does that.
/usr/local/bin/sandbox-code up || true

/usr/local/bin/sandbox-setup || true

exec "$@"
