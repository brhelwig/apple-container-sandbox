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
