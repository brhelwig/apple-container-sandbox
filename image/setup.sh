#!/usr/bin/env bash
# Per-launch, per-sandbox setup. Re-runnable by hand as `sandbox-setup`.
# Add project-specific setup here.
set -euo pipefail

# Start the cluster when [k3s].enabled is set. `sandbox-k3s up` returns as soon
# as the server is launched, so the shell isn't held up while it converges.
# entrypoint.sh calls this hook as `sandbox-setup || true`, so a k3s failure can
# never keep you out of a shell.
if [ -x /usr/local/bin/sandbox-k3s ] && /usr/local/bin/sandbox-k3s enabled; then
    /usr/local/bin/sandbox-k3s up || echo "sandbox-k3s up failed; see /var/log/k3s.log" >&2
fi

exit 0
