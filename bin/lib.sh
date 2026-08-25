: "${SANDBOX_HOMES:=$HOME/Sandboxes}"

sandbox_config() {
    [ -r "$1" ] || { printf '%s\n' "$4"; return 0; }
    python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    val = tomllib.load(f).get(sys.argv[2], {}).get(sys.argv[3])
if isinstance(val, bool):
    val = "true" if val else "false"
print(sys.argv[4] if val in (None, "") else val)
PY
}

validate_name() {
    case "$1" in
        ""|.*|*/*|*[!a-zA-Z0-9_-]*) return 1 ;;
        *) return 0 ;;
    esac
}

sandbox_home_path() {
    printf '%s/%s\n' "$SANDBOX_HOMES" "$1"
}

: "${SANDBOX_DEFAULT_IMAGE:=ghcr.io/brhelwig/dev-container:latest-arm64}"

valid_image_ref() {
    case "${1:-}" in
        ""|*[!A-Za-z0-9._:/@-]*) return 1 ;;
        *) return 0 ;;
    esac
}

sandbox_image_path() {
    printf '%s/.sandbox-image\n' "$(sandbox_home_path "$1")"
}

sandbox_recorded_image() {
    head -n 1 "$(sandbox_image_path "$1")" 2>/dev/null || true
}

sandbox_set_image() {
    local path
    path="$(sandbox_image_path "$1")"
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$2" > "$path"
}

# The pin is written only by --image, so editing [image].ref still reaches
# every sandbox that never asked for one of its own.
sandbox_image_ref() {
    local config="$1" name="$2" ref
    ref="$(sandbox_recorded_image "$name")"
    if valid_image_ref "$ref"; then
        printf '%s\n' "$ref"
        return 0
    fi
    sandbox_config "$config" image ref "$SANDBOX_DEFAULT_IMAGE"
}

sandbox_home_path_path() {
    printf '%s/.sandbox-home\n' "$(sandbox_home_path "$1")"
}

sandbox_recorded_mount() {
    head -n 1 "$(sandbox_home_path_path "$1")" 2>/dev/null || true
}

sandbox_set_mount() {
    local path
    path="$(sandbox_home_path_path "$1")"
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$2" > "$path"
}

sandbox_host_arch() {
    case "$(uname -m)" in
        arm64|aarch64) printf 'arm64\n' ;;
        x86_64|amd64)  printf 'amd64\n' ;;
        *)             uname -m ;;
    esac
}

# A heredoc would take over the stdin these readers need for the piped JSON,
# so the script goes in as an argument instead.
SANDBOX_IMAGE_CONFIG_PY='
import json, sys

try:
    images = json.load(sys.stdin)
except ValueError:
    sys.exit(1)
if not images:
    sys.exit(1)

image = images[0]
variants = image.get("variants") or []
wanted = [
    v for v in variants
    if v.get("platform", {}).get("os") == "linux"
    and v.get("platform", {}).get("architecture") == sys.argv[1]
]
variant = (wanted or variants or [{}])[0]
config = (variant.get("config") or {}).get("config") or {}
env = dict(e.split("=", 1) for e in (config.get("Env") or []) if "=" in e)

workdir = config.get("WorkingDir") or ""
if not workdir.startswith("/") or workdir == "/":
    workdir = ""

description = image.get("configuration") or {}
print(env.get("HOME") or workdir)
print(config.get("User") or "")
print(env.get("SHELL") or "")
print(description.get("name") or "")
print((description.get("descriptor") or {}).get("digest") or "")
'

# Prints five lines from the image OCI config: home, user, shell, reference,
# digest. Empty lines where the image declares nothing.
sandbox_image_config() {
    container image inspect "$1" 2>/dev/null \
        | python3 -c "$SANDBOX_IMAGE_CONFIG_PY" "$(sandbox_host_arch)"
}

SANDBOX_RUNNING_IMAGE_PY='
import json, sys

try:
    containers = json.load(sys.stdin)
except ValueError:
    sys.exit(1)
for c in containers:
    if c.get("id") != sys.argv[1]:
        continue
    image = (c.get("configuration") or {}).get("image") or {}
    print(image.get("reference") or "")
    print((image.get("descriptor") or {}).get("digest") or "")
    print((c.get("status") or {}).get("state") or "")
    break
else:
    sys.exit(1)
'

# The running container reference, digest and state, one per line.
sandbox_running_image() {
    container ls --all --format json 2>/dev/null \
        | python3 -c "$SANDBOX_RUNNING_IMAGE_PY" "$1"
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

sandbox_image_env_args() {
    [ -r "$1" ] || return 0
    python3 - "$1" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    for entry in tomllib.load(f).get("image", {}).get("env", []):
        if entry:
            print("--env")
            print(entry)
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

sandbox_authorized_keys_path() {
    printf '%s/.ssh/authorized_keys\n' "$(sandbox_home_path "$1")"
}

# Blank lines and comments authorize nobody, so they don't count.
sandbox_authorized_key_count() {
    local count
    count="$(grep -cE '^[[:space:]]*[^#[:space:]]' \
        "$(sandbox_authorized_keys_path "$1")" 2>/dev/null || true)"
    printf '%s\n' "${count:-0}"
}

sandbox_seed_authorized_keys() {
    local name="$1" dir keys="" pub host_ssh_dir count
    dir="$(sandbox_home_path "$name")/.ssh"
    if [ -e "$dir/authorized_keys" ]; then return 0; fi
    host_ssh_dir="${SANDBOX_HOST_SSH_DIR:-$HOME/.ssh}"
    for pub in "$host_ssh_dir"/*.pub; do
        if [ -f "$pub" ]; then keys="$keys$(cat "$pub")"$'\n'; fi
    done
    if [ -f "$host_ssh_dir/authorized_keys" ]; then
        keys="$keys$(cat "$host_ssh_dir/authorized_keys")"$'\n'
    fi
    if [ -z "$keys" ]; then return 0; fi
    mkdir -p "$dir"
    chmod 700 "$dir"
    printf '%s' "$keys" > "$dir/authorized_keys"
    chmod 600 "$dir/authorized_keys"
    count="$(sandbox_authorized_key_count "$name")"
    echo "Authorized $count of your public keys for SSH into '$name'."
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

# The tunnel log is appended across launches, so only what the image wrote
# after this launch says anything about this launch.
sandbox_tunnel_url() {
    local log="$1" offset="${2:-0}"
    [ -s "$log" ] || return 1
    tail -c "+$((offset + 1))" "$log" 2>/dev/null \
        | grep -oE 'https://[^ ]*tunnel[^ ]*' \
        | tail -1 \
        | grep .
}

sandbox_file_size() {
    wc -c < "$1" 2>/dev/null | tr -d ' ' || true
}

list_sandboxes() {
    [ -d "$SANDBOX_HOMES" ] || return 0
    for entry in "$SANDBOX_HOMES"/*/; do
        [ -d "$entry" ] || continue
        basename "$entry"
    done | sort
}
