#!/usr/bin/env bash
# Bootstrap: make entry points executable, create the sandbox data dir, and
# print the PATH line to add. Safe to re-run.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

chmod +x "$REPO/bin/sandbox" "$REPO/bin/sandbox-build" "$REPO/bin/sandbox-src-hash" "$REPO/test/run.sh"
mkdir -p "${SANDBOX_HOMES:-$HOME/Sandboxes}"

# Seed the user's editable (gitignored) config from the tracked template.
# Kept separate so editing your config never conflicts with `git pull`.
if [ ! -f "$REPO/config.toml" ]; then
    cp "$REPO/config.toml.example" "$REPO/config.toml"
    echo "created config.toml from config.toml.example (edit it to add packages / set resources)"
fi

echo "Add this to your shell rc (e.g. ~/.zshrc):"
echo
echo "    export PATH=\"$REPO/bin:\$PATH\""
