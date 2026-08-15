#!/usr/bin/env bash
# Seed a fresh (bind-mounted, empty) $HOME from /etc/skel on first launch, put
# the kubeconfig together, start the k3s cluster and the VS Code tunnel if they
# are configured, run the per-sandbox setup hook, then exec the container
# command.
set -euo pipefail

if [ ! -e "$HOME/.sandbox-seeded" ]; then
    cp -a /etc/skel/. "$HOME/" 2>/dev/null || true
    touch "$HOME/.sandbox-seeded"
fi

# What KUBECONFIG points at, and the reason kubectl can write a kubeconfig at
# all in here (see the script). Not specific to k3s — it's also what lets
# `gcloud container clusters get-credentials` save a context — so it runs
# whether or not a cluster is configured, and never keeps you out of a shell.
/usr/local/bin/sandbox-kubeconfig || echo "sandbox-kubeconfig failed" >&2

# Start the cluster when [k3s].enabled is set, ahead of the setup hook so
# project setup can rely on it. `up` returns as soon as the server is launched,
# so the shell isn't held up while the cluster converges, and a failure here
# must never keep you out of a shell.
if [ -x /usr/local/bin/sandbox-k3s ] && /usr/local/bin/sandbox-k3s enabled; then
    /usr/local/bin/sandbox-k3s up || echo "sandbox-k3s up failed; see /var/log/k3s.log" >&2
fi

# Start the VS Code tunnel when [vscode].enabled is set. `up` refuses until the
# sandbox has been signed in once, and says which command does that, so a
# sandbox that has never been signed in just prints the instruction and carries
# on to a shell.
if [ -x /usr/local/bin/sandbox-code ] && /usr/local/bin/sandbox-code enabled; then
    /usr/local/bin/sandbox-code up || true
fi

/usr/local/bin/sandbox-setup || true

exec "$@"
