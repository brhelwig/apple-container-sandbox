#!/usr/bin/env bash
# Tests for bin/lib.sh and bin/sandbox-build. Uses an isolated SANDBOX_HOMES
# under a temp dir, and stubbed `container` / `sudo` / `gum` on PATH.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export SANDBOX_HOMES="$TMP/homes"

# shellcheck source=../bin/lib.sh
. "$DIR/../bin/lib.sh"

pass=0 fail=0
ok()  { if eval "$1"; then echo "ok   $2"; pass=$((pass+1)); else echo "FAIL $2"; fail=$((fail+1)); fi; }
no()  { if eval "$1"; then echo "FAIL $2"; fail=$((fail+1)); else echo "ok   $2"; pass=$((pass+1)); fi; }

# validate_name
ok 'validate_name myproject'      'accepts myproject'
ok 'validate_name web-app_2'      'accepts web-app_2'
no 'validate_name ".hidden"'      'rejects leading dot'
no 'validate_name "a/b"'          'rejects slash'
no 'validate_name "has space"'    'rejects space'
no 'validate_name ""'             'rejects empty'

# sandbox_home_path
ok '[ "$(sandbox_home_path myproject)" = "$SANDBOX_HOMES/myproject" ]' 'home path'

# list_sandboxes
mkdir -p "$SANDBOX_HOMES/alpha" "$SANDBOX_HOMES/beta"
ok '[ "$(list_sandboxes | tr "\n" " ")" = "alpha beta " ]' 'lists sorted dirs'
ok '[ -z "$(SANDBOX_HOMES=$TMP/none list_sandboxes)" ]' 'empty when dir absent'

# rosetta_bootstrap_failure
echo 'cause: "Rosetta is not installed"' > "$TMP/rosetta.log"
echo 'error: no space left on device' > "$TMP/other.log"
ok 'rosetta_bootstrap_failure "$TMP/rosetta.log"' 'spots the Rosetta failure'
no 'rosetta_bootstrap_failure "$TMP/other.log"' 'ignores other failures'

# bin/sandbox-build, driven against stubs. The repo is copied so the build sees
# a packages.toml (untracked in a real checkout).
REPOCOPY="$TMP/repo"
STUB="$TMP/stub"
mkdir -p "$REPOCOPY" "$STUB"
cp -R "$DIR/../bin" "$DIR/../image" "$REPOCOPY/"
cp "$DIR/../packages.toml.example" "$REPOCOPY/packages.toml"

cat > "$STUB/container" <<'STUBEOF'
#!/usr/bin/env bash
case "$1" in
    build)
        printf 'x' >> "$STUB/attempts"
        if [ "$(wc -c < "$STUB/attempts")" -le "$FAIL_BUILDS" ]; then
            echo "$BUILD_ERROR" >&2
            exit 1
        fi
        echo 'build ok' ;;
    *) exit 0 ;;
esac
STUBEOF
cat > "$STUB/sudo" <<'STUBEOF'
#!/usr/bin/env bash
echo "$@" >> "$STUB/sudo.log"
STUBEOF
cat > "$STUB/gum" <<'STUBEOF'
#!/usr/bin/env bash
echo "$@" >> "$STUB/gum.log"
exit "$GUM_CONFIRM"
STUBEOF
chmod +x "$STUB/container" "$STUB/sudo" "$STUB/gum"

ROSETTA_ERR='Error: internalError: "failed to bootstrap container buildkit (cause: "Rosetta is not installed"")"'

# run_build <builds-that-fail> <gum-confirm-exit> <build-error>: run
# bin/sandbox-build against the stubs; stdout in $out, stderr in $TMP/err.
run_build() {
    rm -f "$STUB/attempts" "$STUB/sudo.log" "$STUB/gum.log"
    out="$(STUB="$STUB" FAIL_BUILDS="$1" GUM_CONFIRM="$2" BUILD_ERROR="$3" \
        PATH="$STUB:$PATH" bash "$REPOCOPY/bin/sandbox-build" 2>"$TMP/err")"
}

run_build 1 0 "$ROSETTA_ERR"; status=$?
ok '[ "$status" -eq 0 ]'                        'consent: retried build succeeds'
ok 'grep -q -- "--install-rosetta" "$STUB/sudo.log"' 'consent: installs Rosetta'
ok '[ "${out#sandbox:}" != "$out" ]'            'consent: prints the image ref'

run_build 9 1 "$ROSETTA_ERR"; status=$?
ok '[ "$status" -ne 0 ]'                        'declined: fails'
ok '[ ! -e "$STUB/sudo.log" ]'                  'declined: installs nothing'
ok 'grep -q "rosetta = false" "$TMP/err"'       'declined: names the arm64-only opt-out'

run_build 9 0 'Error: no space left on device'; status=$?
ok '[ "$status" -ne 0 ]'                        'other failure: fails'
ok '[ ! -e "$STUB/gum.log" ]'                   'other failure: no prompt'

echo "----"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
