: "${SANDBOX_HOMES:=$HOME/Sandboxes}"

SANDBOX_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "${SANDBOX_CONFIG_LIB:-$SANDBOX_LIB_DIR/../image/sandbox-config.sh}"

validate_name() {
    case "$1" in
        ""|.*|*/*|*[!a-zA-Z0-9_-]*) return 1 ;;
        *) return 0 ;;
    esac
}

sandbox_home_path() {
    printf '%s/%s\n' "$SANDBOX_HOMES" "$1"
}

sandbox_image_ref() {
    printf '%s\n' "${IMAGE:-ghcr.io/brhelwig/apple-container-sandbox:latest}"
}

sandbox_image_digest() {
    container image inspect "$1" 2>/dev/null | python3 -c '
import json, sys

def find(node):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "digest" and isinstance(value, str) and value.startswith("sha256:"):
                return value
            found = find(value)
            if found:
                return found
    elif isinstance(node, list):
        for value in node:
            found = find(value)
            if found:
                return found
    return None

try:
    data = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
digest = find(data)
if digest:
    print(digest)
' 2>/dev/null || true
}

sandbox_resource_args() {
    [ -r "$1" ] || return 0
    python3 - "$1" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    res = tomllib.load(f).get("resources", {})
for flag, key in (("--memory", "memory"), ("--cpus", "cpus")):
    val = res.get(key)
    if val not in (None, ""):
        print(flag)
        print(val)
PY
}

valid_port() {
    case "${1:-}" in
        ""|*[!0-9]*) return 1 ;;
    esac
    [ "${#1}" -le 5 ] || return 1
    [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

sandbox_ssh_enabled() {
    [ "$(sandbox_config "$1" ssh enabled true)" = "true" ]
}

sandbox_ssh_address() {
    sandbox_config "$1" ssh address 0.0.0.0
}

sandbox_ssh_port_path() {
    printf '%s/.sandbox-ssh-port\n' "$(sandbox_home_path "$1")"
}

sandbox_recorded_ssh_port() {
    cat "$(sandbox_ssh_port_path "$1")" 2>/dev/null || true
}

sandbox_set_ssh_port() {
    local path
    path="$(sandbox_ssh_port_path "$1")"
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$2" > "$path"
}

sandbox_ssh_ports_taken() {
    local skip="$1" name port
    while IFS= read -r name; do
        [ "$name" != "$skip" ] || continue
        port="$(sandbox_recorded_ssh_port "$name")"
        if valid_port "$port"; then printf '%s\n' "$port"; fi
    done < <(list_sandboxes)
}

sandbox_ssh_port() {
    local config="$1" name="$2" port base taken
    port="$(sandbox_recorded_ssh_port "$name")"
    if valid_port "$port"; then
        printf '%s\n' "$port"
        return 0
    fi
    base="$(sandbox_config "$config" ssh port 2222)"
    valid_port "$base" || base=2222
    taken=" $(sandbox_ssh_ports_taken "$name" | tr '\n' ' ')"
    port="$base"
    while [ "$port" -le 65535 ]; do
        case "$taken" in
            *" $port "*) port=$((port + 1)) ;;
            *) break ;;
        esac
    done
    if [ "$port" -gt 65535 ]; then
        echo "No SSH port is free at or above $base." >&2
        return 1
    fi
    sandbox_set_ssh_port "$name" "$port"
    printf '%s\n' "$port"
}

sandbox_seed_authorized_keys() {
    local name="$1" dir keys="" pub count
    dir="$(sandbox_home_path "$name")/.ssh"
    if [ -e "$dir/authorized_keys" ]; then return 0; fi
    for pub in "${SANDBOX_HOST_SSH_DIR:-$HOME/.ssh}"/*.pub; do
        if [ -f "$pub" ]; then keys="$keys$(cat "$pub")"$'\n'; fi
    done
    if [ -z "$keys" ]; then return 0; fi
    mkdir -p "$dir"
    chmod 700 "$dir"
    printf '%s' "$keys" > "$dir/authorized_keys"
    chmod 600 "$dir/authorized_keys"
    count="$(printf '%s' "$keys" | grep -c . || true)"
    echo "Authorized ${count:-0} of your public keys for SSH into '$name'."
}

confirm() {
    if command -v gum >/dev/null 2>&1; then
        gum confirm "$1"
        return
    fi
    [ -r /dev/tty ] || return 1
    local reply
    printf '%s [y/N] ' "$1" >&2
    read -r reply < /dev/tty || return 1
    case "$reply" in
        y|Y|yes|Yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

ensure_gum() {
    command -v gum >/dev/null 2>&1 && return 0

    echo "The menu needs gum, and it isn't installed." >&2
    if ! command -v brew >/dev/null 2>&1; then
        echo "Install Homebrew (https://brew.sh), then: brew install gum" >&2
    elif confirm 'Install gum now? (runs: brew install gum)'; then
        brew install gum >&2 && command -v gum >/dev/null 2>&1 && return 0
        echo "gum still isn't on your PATH." >&2
    else
        echo "Not installed. Install it later with: brew install gum" >&2
    fi
    echo "Or skip the menu and name the sandbox: sandbox <name>" >&2
    return 1
}

list_sandboxes() {
    [ -d "$SANDBOX_HOMES" ] || return 0
    for entry in "$SANDBOX_HOMES"/*/; do
        [ -d "$entry" ] || continue
        basename "$entry"
    done | sort
}
