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

# sandbox_resource_args
RES="$TMP/res.toml"
printf '[resources]\nmemory = "4G"\ncpus = 4\n' > "$RES"
ok '[ "$(sandbox_resource_args "$RES" | tr "\n" " ")" = "--memory 4G --cpus 4 " ]' 'resource args: memory and cpus'
printf '[resources]\nmemory = "2G"\n' > "$RES"
ok '[ "$(sandbox_resource_args "$RES" | tr "\n" " ")" = "--memory 2G " ]' 'resource args: memory only'
printf '[resources]\nmemory = ""\ncpus = ""\n' > "$RES"
ok '[ -z "$(sandbox_resource_args "$RES")" ]' 'resource args: empty values -> none'
printf '[apt]\npackages = []\n' > "$RES"
ok '[ -z "$(sandbox_resource_args "$RES")" ]' 'resource args: no section -> none'
ok '[ -z "$(sandbox_resource_args "$TMP/nope.toml")" ]' 'resource args: missing file -> none'

# list_sandboxes
mkdir -p "$SANDBOX_HOMES/alpha" "$SANDBOX_HOMES/beta"
ok '[ "$(list_sandboxes | tr "\n" " ")" = "alpha beta " ]' 'lists sorted dirs'
ok '[ -z "$(SANDBOX_HOMES=$TMP/none list_sandboxes)" ]' 'empty when dir absent'

# rosetta_bootstrap_failure
echo 'cause: "Rosetta is not installed"' > "$TMP/rosetta.log"
echo 'error: no space left on device' > "$TMP/other.log"
ok 'rosetta_bootstrap_failure "$TMP/rosetta.log"' 'spots the Rosetta failure'
no 'rosetta_bootstrap_failure "$TMP/other.log"' 'ignores other failures'

# ensure_gum, against a PATH holding only the stubs each case asks for.
GSTUB="$TMP/gumstub"

# run_ensure_gum <gum?> <brew?> <answer> <install-works?>: each argument yes/no.
# Stderr lands in $TMP/err.
run_ensure_gum() {
    rm -rf "$GSTUB"
    mkdir -p "$GSTUB"
    [ "$1" = yes ] && { printf '#!/bin/sh\n' > "$GSTUB/gum"; chmod +x "$GSTUB/gum"; }
    if [ "$2" = yes ]; then
        {
            # The stub runs under the test's stripped PATH, so it restores one.
            printf '#!/bin/sh\nPATH=/usr/bin:/bin\n'
            printf 'echo "$@" >> %s/brew.log\n' "$GSTUB"
            [ "$4" = yes ] && printf 'printf "#!/bin/sh\\n" > %s/gum && chmod +x %s/gum\n' "$GSTUB" "$GSTUB"
        } > "$GSTUB/brew"
        chmod +x "$GSTUB/brew"
    fi
    local answer="$3"
    (
        confirm() { [ "$answer" = yes ]; }
        PATH="$GSTUB" ensure_gum
    ) 2>"$TMP/err"
}

ok 'run_ensure_gum yes no no no'            'gum present: nothing to do'
ok '[ ! -e "$GSTUB/brew.log" ]'             'gum present: no install attempted'
no 'run_ensure_gum no no yes yes'           'no brew: fails'
ok 'grep -q brew.sh "$TMP/err"'             'no brew: points at Homebrew'
no 'run_ensure_gum no yes no yes'           'declined: fails'
ok '[ ! -e "$GSTUB/brew.log" ]'             'declined: installs nothing'
ok 'grep -q "brew install gum" "$TMP/err"'  'declined: names the install command'
ok 'run_ensure_gum no yes yes yes'          'consent: gum is usable afterwards'
ok 'grep -q "^install gum$" "$GSTUB/brew.log"' 'consent: runs brew install gum'
no 'run_ensure_gum no yes yes no'           'install without gum on PATH: fails'
ok 'grep -q "still isn.t on your PATH" "$TMP/err"' 'install without gum on PATH: says so'

# bin/sandbox-build, driven against stubs. The repo is copied so the build sees
# a config.toml (untracked in a real checkout).
REPOCOPY="$TMP/repo"
STUB="$TMP/stub"
mkdir -p "$REPOCOPY" "$STUB"
cp -R "$DIR/../bin" "$DIR/../image" "$REPOCOPY/"
cp "$DIR/../config.toml.example" "$REPOCOPY/config.toml"

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
