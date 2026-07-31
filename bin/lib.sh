# shellcheck shell=bash
# Shared helpers for the sandbox CLI. Sourced, not executed.

# Root dir holding one home dir per sandbox. Overridable for tests.
: "${SANDBOX_HOMES:=$HOME/Sandboxes}"

# validate_name <name>: 0 if <name> is a safe single path segment.
validate_name() {
    case "$1" in
        ""|.*|*/*|*[!a-zA-Z0-9_-]*) return 1 ;;
        *) return 0 ;;
    esac
}

# sandbox_home_path <name>: print the home dir path for <name>.
sandbox_home_path() {
    printf '%s/%s\n' "$SANDBOX_HOMES" "$1"
}

# sandbox_resource_args <config>: print the `container run` resource flags
# (--memory / --cpus) declared in [resources], one token per line. Silent if
# the file, the section, or a value is absent/empty.
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

# sandbox_k3s_value <config> <key> <default>: print the [k3s] setting <key>,
# falling back to <default> when the file, the section, or the key is
# absent/empty. Booleans print as lowercase true/false.
sandbox_k3s_value() {
    local out=""
    if [ -r "$1" ]; then
        out="$(python3 - "$1" "$2" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    val = tomllib.load(f).get("k3s", {}).get(sys.argv[2])
if isinstance(val, bool):
    val = "true" if val else "false"
print("" if val is None else val)
PY
)"
    fi
    if [ -n "$out" ]; then printf '%s\n' "$out"; else printf '%s\n' "$3"; fi
}

# sandbox_k3s_enabled <config>: 0 if [k3s].enabled is true.
sandbox_k3s_enabled() {
    [ "$(sandbox_k3s_value "$1" enabled false)" = "true" ]
}

# sandbox_cap_args <config>: print the `container run` capability flags, one
# token per line. k3s needs CAP_SYS_ADMIN (mount, cgroups) and CAP_NET_ADMIN
# (iptables, netns), neither of which is in the default set, so a k3s-enabled
# sandbox runs fully privileged. Silent when k3s is off.
sandbox_cap_args() {
    sandbox_k3s_enabled "$1" || return 0
    printf '%s\n' "--cap-add" "ALL"
}

# confirm <prompt>: ask for approval; 0 if approved. No terminal means no.
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

# ensure_gum: 0 if gum is usable, offering to install it first if it's missing.
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

# rosetta_bootstrap_failure <log>: 0 if <log> shows a build that failed because
# the builder VM wants Rosetta and it isn't installed.
rosetta_bootstrap_failure() {
    grep -q 'Rosetta is not installed' "$1"
}

# list_sandboxes: print non-hidden sandbox names, one per line, sorted.
list_sandboxes() {
    [ -d "$SANDBOX_HOMES" ] || return 0
    for entry in "$SANDBOX_HOMES"/*/; do
        [ -d "$entry" ] || continue
        basename "$entry"
    done | sort
}
