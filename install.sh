#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

chmod +x "$REPO/bin/sandbox" "$REPO/test/run.sh"
mkdir -p "${SANDBOX_HOMES:-$HOME/Sandboxes}"

if [ ! -f "$REPO/config.toml" ]; then
    cp "$REPO/config.toml.example" "$REPO/config.toml"
    echo "created config.toml from config.toml.example (edit it to choose an image / set resources)"
fi

echo "Add this to your shell rc (e.g. ~/.zshrc):"
echo
echo "    export PATH=\"$REPO/bin:\$PATH\""
