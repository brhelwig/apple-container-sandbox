#!/usr/bin/env bash
# Tests for bin/lib.sh and bin/sandbox-build. Uses an isolated SANDBOX_HOMES
# under a temp dir, and stubbed `container` / `sudo` / `gum` on PATH.
#
# Assertions are eval'd strings, so the variables they read look unused here.
# shellcheck disable=SC2034
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

# sandbox_k3s_enabled
K3S="$TMP/k3s.toml"
printf '[k3s]\nenabled = true\n' > "$K3S"
ok 'sandbox_k3s_enabled "$K3S"'          'k3s enabled: true -> yes'
printf '[k3s]\nenabled = false\n' > "$K3S"
no 'sandbox_k3s_enabled "$K3S"'          'k3s enabled: false -> no'
printf '[apt]\npackages = []\n' > "$K3S"
no 'sandbox_k3s_enabled "$K3S"'          'k3s enabled: no section -> no'
no 'sandbox_k3s_enabled "$TMP/nope.toml"' 'k3s enabled: missing file -> no'

# sandbox_cap_args: k3s needs CAP_SYS_ADMIN/CAP_NET_ADMIN, absent from the default set.
printf '[k3s]\nenabled = true\n' > "$K3S"
ok '[ "$(sandbox_cap_args "$K3S" | tr "\n" " ")" = "--cap-add ALL " ]' 'cap args: enabled -> --cap-add ALL'
printf '[k3s]\nenabled = false\n' > "$K3S"
ok '[ -z "$(sandbox_cap_args "$K3S")" ]'  'cap args: disabled -> none'
ok '[ -z "$(sandbox_cap_args "$TMP/nope.toml")" ]' 'cap args: missing file -> none'

# sandbox_k3s_value <config> <key> <default>: settings the in-container helper reads.
printf '[k3s]\nenabled = true\ndisk = "8G"\nnode_ip = "10.99.0.1"\n' > "$K3S"
ok '[ "$(sandbox_k3s_value "$K3S" disk 4G)" = "8G" ]'             'k3s value: reads disk'
ok '[ "$(sandbox_k3s_value "$K3S" node_ip 1.2.3.4)" = "10.99.0.1" ]' 'k3s value: reads node_ip'
printf '[k3s]\nenabled = true\n' > "$K3S"
ok '[ "$(sandbox_k3s_value "$K3S" disk 8G)" = "8G" ]'             'k3s value: absent key -> default'
ok '[ "$(sandbox_k3s_value "$TMP/nope.toml" disk 8G)" = "8G" ]'   'k3s value: missing file -> default'

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
    out="$(env STUB="$STUB" FAIL_BUILDS="$1" GUM_CONFIRM="$2" BUILD_ERROR="$3" \
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

# bin/sandbox launch: the capability flags must actually reach `container run`,
# since a missing --cap-add leaves k3s to fail later and less obviously.
LSTUB="$TMP/lstub"
mkdir -p "$LSTUB"
cat > "$LSTUB/container" <<'STUBEOF'
#!/usr/bin/env bash
[ "$1" = run ] && printf '%s\n' "$@" > "$LAUNCH_LOG"
exit 0
STUBEOF
chmod +x "$LSTUB/container"

# run_launch: launch a sandbox against the stub; `container run` argv in $TMP/launch.log.
run_launch() {
    rm -f "$TMP/launch.log"
    LAUNCH_LOG="$TMP/launch.log" SANDBOX_HOMES="$TMP/homes" \
        PATH="$LSTUB:$PATH" bash "$REPOCOPY/bin/sandbox" testbox >/dev/null 2>&1
}

run_launch
ok '[ -s "$TMP/launch.log" ]'                       'launch: reaches container run'
no 'grep -qx -- "--cap-add" "$TMP/launch.log"'      'launch: k3s off -> no --cap-add'

# Flip the shipped `enabled = false` rather than appending a second [k3s]
# table, which would be a duplicate-table TOML error.
sed -i.bak 's/^enabled = false$/enabled = true/' "$REPOCOPY/config.toml"
ok 'sandbox_k3s_enabled "$REPOCOPY/config.toml"'    'launch fixture: k3s now enabled'
run_launch
ok 'grep -qx -- "--cap-add" "$TMP/launch.log"'      'launch: k3s on -> passes --cap-add'
ok 'grep -qx "ALL" "$TMP/launch.log"'               'launch: k3s on -> grants ALL'

# image/sandbox-k3s config parsing. The launch hook gates on `sandbox-k3s
# enabled`, so this has to agree with sandbox_k3s_enabled in lib.sh — tomllib
# yields a Python bool, which prints as "True" unless it's normalised.
K3SH="$DIR/../image/sandbox-k3s"
printf '[k3s]\nenabled = true\n' > "$K3S"
ok 'SANDBOX_K3S_CONFIG="$K3S" bash "$K3SH" enabled' 'sandbox-k3s: enabled = true -> 0'
printf '[k3s]\nenabled = false\n' > "$K3S"
no 'SANDBOX_K3S_CONFIG="$K3S" bash "$K3SH" enabled' 'sandbox-k3s: enabled = false -> 1'
printf '[apt]\npackages = []\n' > "$K3S"
no 'SANDBOX_K3S_CONFIG="$K3S" bash "$K3SH" enabled' 'sandbox-k3s: no section -> 1'
no 'SANDBOX_K3S_CONFIG="$TMP/nope.toml" bash "$K3SH" enabled' 'sandbox-k3s: missing file -> 1'

# lib.sh and sandbox-k3s must agree, since one gates the caps and the other the
# cluster startup; disagreement means a privileged sandbox with no cluster.
printf '[k3s]\nenabled = true\n' > "$K3S"
ok 'sandbox_k3s_enabled "$K3S" && SANDBOX_K3S_CONFIG="$K3S" bash "$K3SH" enabled' \
   'sandbox-k3s and lib.sh agree when enabled'

# image/sandbox-kubeconfig. kubectl locks a kubeconfig by creating "<file>.lock"
# with mode 000, and virtiofs — the filesystem behind the bind-mounted sandbox
# home — refuses to create such a file, so every `kubectl config` write against
# a file in $HOME fails. KUBECONFIG therefore points at a shim dir on the
# container filesystem, where the lock can be taken, whose entries write through
# to the real (persistent) kubeconfig in the home.
KUBE="$DIR/../image/sandbox-kubeconfig"
KHOME="$TMP/kubehome"
KSHIM="$TMP/kubeshim"
KSRC="$TMP/k3s-src.yaml"

filemode() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }

# run_kubeconfig: run the helper against the temp home, shim dir and cluster file.
run_kubeconfig() {
    HOME="$KHOME" SANDBOX_KUBE_DIR="$KSHIM" SANDBOX_K3S_KUBECONFIG="$KSRC" \
        bash "$KUBE" >"$TMP/kube.out" 2>&1
}

rm -rf "$KHOME" "$KSHIM"; rm -f "$KSRC"
ok 'run_kubeconfig'                                  'kubeconfig: runs with no home and no cluster'
ok '[ -L "$KSHIM/config" ]'                          'kubeconfig: shim entry is a symlink'
ok '[ "$(readlink "$KSHIM/config")" = "$KHOME/.kube/config" ]' \
                                                     'kubeconfig: shim entry targets the home kubeconfig'
ok '[ -f "$KHOME/.kube/config" ]'                    'kubeconfig: seeds a kubeconfig when absent'
ok 'grep -q "^kind: Config" "$KHOME/.kube/config"'   'kubeconfig: seeded file is a kubeconfig'
ok '[ "$(filemode "$KHOME/.kube/config")" = 600 ]'   'kubeconfig: seeded file is private'
ok '[ ! -e "$KSHIM/k3s.yaml" ]'                      'kubeconfig: no cluster -> no cluster entry'

# The regression this guards: sandbox-k3s used to `ln -sfn` the k3s kubeconfig
# over $HOME/.kube/config on every launch, destroying whatever was there.
printf 'apiVersion: v1\nkind: Config\n# sentinel\n' > "$KHOME/.kube/config"
ok 'run_kubeconfig'                                  'kubeconfig: re-runs against an existing kubeconfig'
ok 'grep -q "# sentinel" "$KHOME/.kube/config"'      'kubeconfig: never clobbers an existing kubeconfig'
ok '[ ! -L "$KHOME/.kube/config" ]'                  'kubeconfig: leaves the home kubeconfig a real file'

# A home left holding the old symlink has no data to lose, so it gets repaired.
ln -sfn "$KSRC" "$KHOME/.kube/config"
ok 'run_kubeconfig'                                  'kubeconfig: runs against the legacy symlink'
ok '[ ! -L "$KHOME/.kube/config" ]'                  'kubeconfig: repairs the legacy k3s symlink'
ok 'grep -q "^kind: Config" "$KHOME/.kube/config"'   'kubeconfig: reseeds after repairing the symlink'

# k3s names its context, cluster and user all "default", which collides with
# anything already called that in the user's own kubeconfig.
cat > "$KSRC" <<'EOF'
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: QQ==
    server: https://127.0.0.1:6443
  name: default
contexts:
- context:
    cluster: default
    user: default
  name: default
current-context: default
kind: Config
users:
- name: default
  user:
    client-certificate-data: QQ==
EOF
ok 'run_kubeconfig'                                  'kubeconfig: runs with a cluster present'
ok '[ -f "$KSHIM/k3s.yaml" ]'                        'kubeconfig: renders the cluster entry'
no 'grep -q ": default$" "$KSHIM/k3s.yaml"'          'kubeconfig: leaves no "default" name behind'
ok '[ "$(grep -c ": k3s$" "$KSHIM/k3s.yaml")" -eq 6 ]' \
                                                     'kubeconfig: renames cluster, user, context and current-context'
ok 'grep -q "server: https://127.0.0.1:6443" "$KSHIM/k3s.yaml"' \
                                                     'kubeconfig: keeps the cluster endpoint'
ok '[ "$(filemode "$KSHIM/k3s.yaml")" = 600 ]'       'kubeconfig: rendered cluster entry is private'

# The point of the shim: a write to the shim path lands in the persistent home
# file, while the lock kubectl takes alongside it stays on the container fs.
printf 'written through\n' > "$KSHIM/config"
ok 'grep -q "written through" "$KHOME/.kube/config"' 'kubeconfig: shim writes through to the home file'
ok '[ ! -L "$KHOME/.kube/config" ]'                  'kubeconfig: write-through keeps the home file real'

echo "----"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
