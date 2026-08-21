#!/usr/bin/env bash
set -euo pipefail

BIN="${SANDBOX_BIN:-/usr/local/bin}"
CONFIG="${SANDBOX_CONFIG:-}"
if [ -z "$CONFIG" ]; then
    CONFIG="$HOME/.sandbox-config.toml"
    [ -r "$CONFIG" ] || CONFIG=/etc/sandbox-config.toml
fi

. "${SANDBOX_CONFIG_LIB:-/etc/sandbox-config.sh}"

if [ ! -e "$HOME/.sandbox-seeded" ]; then
    cp -a /etc/skel/. "$HOME/" 2>/dev/null || true
    touch "$HOME/.sandbox-seeded"
fi

"$BIN/sandbox-kubeconfig" || echo "sandbox-kubeconfig failed" >&2

if [ "$(sandbox_config "$CONFIG" k3s autostart false)" = "true" ]; then
    "$BIN/sandbox-k3s" up || echo "sandbox-k3s up failed; see /var/log/k3s.log" >&2
fi

"$BIN/sandbox-code" up || true

if [ "$(sandbox_config "$CONFIG" ssh enabled true)" = "true" ]; then
    "$BIN/sandbox-ssh" up || true
fi

"$BIN/sandbox-setup" || true

exec "$@"
