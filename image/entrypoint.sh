#!/usr/bin/env bash
# Seed a fresh (bind-mounted, empty) $HOME from /etc/skel on first launch,
# run the per-sandbox setup hook, then exec the container command.
set -euo pipefail

if [ ! -e "$HOME/.sandbox-seeded" ]; then
    cp -a /etc/skel/. "$HOME/" 2>/dev/null || true
    touch "$HOME/.sandbox-seeded"
fi

/usr/local/bin/sandbox-setup || true

exec "$@"
