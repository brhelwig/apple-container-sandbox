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
