#!/usr/bin/env bash
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export SANDBOX_HOMES="$TMP/homes"
export SANDBOX_CONFIG_LIB="$DIR/../image/sandbox-config.sh"

. "$DIR/../bin/lib.sh"
. "$SANDBOX_CONFIG_LIB"

pass=0 fail=0
ok()  { if eval "$1"; then echo "ok   $2"; pass=$((pass+1)); else echo "FAIL $2"; fail=$((fail+1)); fi; }
no()  { if eval "$1"; then echo "FAIL $2"; fail=$((fail+1)); else echo "ok   $2"; pass=$((pass+1)); fi; }

ok 'validate_name myproject'      'accepts myproject'
ok 'validate_name web-app_2'      'accepts web-app_2'
no 'validate_name ".hidden"'      'rejects leading dot'
no 'validate_name "a/b"'          'rejects slash'
no 'validate_name "has space"'    'rejects space'
no 'validate_name ""'             'rejects empty'

ok '[ "$(sandbox_home_path myproject)" = "$SANDBOX_HOMES/myproject" ]' 'home path'

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

K3S="$TMP/k3s.toml"
printf '[k3s]\ndisk = "8G"\nnode_ip = "10.99.0.1"\nenabled = true\n' > "$K3S"
ok '[ "$(sandbox_config "$K3S" k3s disk 4G)" = "8G" ]'             'config: reads disk'
ok '[ "$(sandbox_config "$K3S" k3s node_ip 1.2.3.4)" = "10.99.0.1" ]' 'config: reads node_ip'
ok '[ "$(sandbox_config "$K3S" k3s enabled false)" = "true" ]'      'config: booleans print lowercase'
printf '[k3s]\ndisk = "8G"\n' > "$K3S"
ok '[ "$(sandbox_config "$K3S" k3s node_ip 1.2.3.4)" = "1.2.3.4" ]' 'config: absent key -> default'
ok '[ "$(sandbox_config "$K3S" resources memory 1G)" = "1G" ]'     'config: absent section -> default'
ok '[ "$(sandbox_config "$TMP/nope.toml" k3s disk 8G)" = "8G" ]'   'config: missing file -> default'

mkdir -p "$SANDBOX_HOMES/alpha" "$SANDBOX_HOMES/beta"
ok '[ "$(list_sandboxes | tr "\n" " ")" = "alpha beta " ]' 'lists sorted dirs'
ok '[ -z "$(SANDBOX_HOMES=$TMP/none list_sandboxes)" ]' 'empty when dir absent'

echo 'cause: "Rosetta is not installed"' > "$TMP/rosetta.log"
echo 'error: no space left on device' > "$TMP/other.log"
ok 'rosetta_bootstrap_failure "$TMP/rosetta.log"' 'spots the Rosetta failure'
no 'rosetta_bootstrap_failure "$TMP/other.log"' 'ignores other failures'

GSTUB="$TMP/gumstub"

run_ensure_gum() {
    rm -rf "$GSTUB"
    mkdir -p "$GSTUB"
    [ "$1" = yes ] && { printf '#!/bin/sh\n' > "$GSTUB/gum"; chmod +x "$GSTUB/gum"; }
    if [ "$2" = yes ]; then
        {
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

LSTUB="$TMP/lstub"
mkdir -p "$LSTUB"
cat > "$LSTUB/container" <<'STUBEOF'
#!/usr/bin/env bash
[ "$1" = run ] && printf '%s\n' "$@" > "$LAUNCH_LOG"
exit 0
STUBEOF
chmod +x "$LSTUB/container"

run_launch() {
    rm -f "$TMP/launch.log"
    LAUNCH_LOG="$TMP/launch.log" SANDBOX_HOMES="$TMP/homes" SANDBOX_TUNNEL_WAIT=0 \
        PATH="$LSTUB:$PATH" bash "$REPOCOPY/bin/sandbox" "$@" >/dev/null 2>&1
}

run_launch testbox
ok '[ -s "$TMP/launch.log" ]'                       'launch: reaches container run'
ok 'grep -qx -- "--cap-add" "$TMP/launch.log"'      'launch: passes --cap-add'
ok 'grep -qx "ALL" "$TMP/launch.log"'               'launch: grants ALL'
ok 'grep -qx -- "--tty" "$TMP/launch.log"'          'launch: opens a TTY'
ok 'grep -qx -- "--init" "$TMP/launch.log"'         'launch: runs an init, so orphans get reaped'
no 'grep -qx -- "--detach" "$TMP/launch.log"'       'launch: stays in the foreground'

run_launch -d testbox
ok '[ -s "$TMP/launch.log" ]'                       'headless: reaches container run'
ok 'grep -qx -- "--detach" "$TMP/launch.log"'       'headless: detaches'
no 'grep -qx -- "--tty" "$TMP/launch.log"'          'headless: opens no TTY'
ok 'grep -qx "/usr/local/bin/sandbox-idle" "$TMP/launch.log"' 'headless: runs sandbox-idle'
ok 'grep -qx -- "--cap-add" "$TMP/launch.log"'      'headless: keeps --cap-add'
ok 'grep -qx -- "--init" "$TMP/launch.log"'         'headless: keeps --init'

run_launch --headless testbox
ok 'grep -qx -- "--detach" "$TMP/launch.log"'       'headless: --headless is the long form'

run_launch --nope; status=$?
ok '[ "$status" -eq 2 ]'                            'unknown option: exits 2'
no '[ -e "$TMP/launch.log" ]'                       'unknown option: launches nothing'

ASTUB="$TMP/astub"
mkdir -p "$ASTUB"
cat > "$ASTUB/container" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ATTACH_LOG"
if [ "$1" = ls ]; then
    echo 'ID  IMAGE  OS  ARCH  STATE  ADDR'
    [ -n "${RUNNING_IMAGE:-}" ] && echo "testbox  $RUNNING_IMAGE  linux  arm64  running  192.168.64.2"
fi
exit 0
STUBEOF
cat > "$ASTUB/gum" <<'STUBEOF'
#!/usr/bin/env bash
exit "$GUM_CONFIRM"
STUBEOF
chmod +x "$ASTUB/container" "$ASTUB/gum"

CURRENT="sandbox:$(bash "$REPOCOPY/bin/sandbox-src-hash")"

run_attach() {
    rm -f "$TMP/attach.log"
    ATTACH_LOG="$TMP/attach.log" RUNNING_IMAGE="$1" GUM_CONFIRM="${2:-1}" \
        SANDBOX_HOMES="$TMP/homes" SANDBOX_TUNNEL_WAIT=0 \
        PATH="$ASTUB:$PATH" bash "$REPOCOPY/bin/sandbox" "${3:-testbox}" >/dev/null 2>&1
}

run_attach "$CURRENT"
ok 'grep -q "sandbox-zellij$" "$TMP/attach.log"'    'running: attaches a shell'
no 'grep -q "^run " "$TMP/attach.log"'              'running: starts no second container'
no 'grep -q "^stop " "$TMP/attach.log"'             'running: stops nothing'
no 'grep -q "^delete " "$TMP/attach.log"'           'running: deletes nothing'
no 'grep -q "^build " "$TMP/attach.log"'            'running: builds no image'

run_attach sandbox:stale 1
ok 'grep -q "sandbox-zellij$" "$TMP/attach.log"'    'stale image, declined: attaches anyway'
no 'grep -q "^stop " "$TMP/attach.log"'             'stale image, declined: leaves it running'
no 'grep -q "^delete " "$TMP/attach.log"'           'stale image, declined: deletes nothing'

run_attach sandbox:stale 0
ok 'grep -q "^stop testbox$" "$TMP/attach.log"'         'stale image, confirmed: stops it'
ok 'grep -q "^delete --force testbox$" "$TMP/attach.log"' 'stale image, confirmed: deletes it'
ok 'grep -q "^run --rm" "$TMP/attach.log"'              'stale image, confirmed: starts it again'
no 'grep -q "sandbox-zellij$" "$TMP/attach.log"'        'stale image, confirmed: attaches to nothing'

run_attach "" 1 otherbox
ok 'grep -q "^run --rm" "$TMP/attach.log"'          'not running: starts it'
no 'grep -q "confirm" "$TMP/attach.log"'            'not running: asks nothing'

DSTUB="$TMP/dstub"
mkdir -p "$DSTUB"
cat > "$DSTUB/container" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DELETE_LOG"
exit 0
STUBEOF
cat > "$DSTUB/gum" <<'STUBEOF'
#!/usr/bin/env bash
case "$*" in
    *"Sandbox:"*)                  cat > /dev/null; echo "🗑 Delete container…" ;;
    *"which sandbox's container"*) cat > /dev/null; echo "$DELETE_NAME" ;;
    confirm*)                      exit "$GUM_CONFIRM" ;;
esac
STUBEOF
chmod +x "$DSTUB/container" "$DSTUB/gum"

DHOME="$SANDBOX_HOMES/deleteme"
mkdir -p "$DHOME"
echo 'work' > "$DHOME/keepme"

run_delete() {
    rm -f "$TMP/delete.log"
    DELETE_LOG="$TMP/delete.log" DELETE_NAME=deleteme GUM_CONFIRM="$1" \
        PATH="$DSTUB:$PATH" bash "$REPOCOPY/bin/sandbox" >/dev/null 2>&1
}

run_delete 0
ok 'grep -q "delete --force deleteme" "$TMP/delete.log"' 'delete: deletes the container'
ok '[ -f "$DHOME/keepme" ]'                              'delete: keeps what is in the home dir'
ok '[ -d "$DHOME" ]'                                     'delete: keeps the home dir'

run_delete 1
ok '[ ! -e "$TMP/delete.log" ]'                          'delete: declined -> touches nothing'

CODEH="$DIR/../image/sandbox-code"

run_code() {
    local cli="$TMP/code-stub"
    cat > "$cli" <<STUBEOF
#!/usr/bin/env bash
case "\$*" in
    "tunnel user show") [ "$2" = yes ] && echo 'account' || { echo 'not logged in'; exit 1; } ;;
    "tunnel status") echo '{"tunnel":null,"service_installed":false}' ;;
    *) echo "\$*" >> "$TMP/code-stub.log" ;;
esac
STUBEOF
    chmod +x "$cli"
    SANDBOX_VSCODE_CLI="$cli" HOME="$TMP" \
        bash "$CODEH" "$1" >"$TMP/vsc.out" 2>&1
}

rm -f "$TMP/code-stub.log"
no 'run_code up no'                                     'sandbox-code: up signed out -> fails'
ok 'grep -q "sandbox-code login" "$TMP/vsc.out"'        'sandbox-code: up signed out names the login command'
ok '[ ! -e "$TMP/code-stub.log" ]'                      'sandbox-code: up signed out starts no tunnel'

no 'run_code status yes'                                'sandbox-code: status with no tunnel -> fails'
ok 'grep -q "tunnel: not running" "$TMP/vsc.out"'       'sandbox-code: status says the tunnel is down'

rm -f "$TMP/code-stub.log"
run_code up yes
waited=0
while [ ! -s "$TMP/code-stub.log" ] && [ "$waited" -lt 20 ]; do sleep 0.1; waited=$((waited+1)); done
ok 'grep -q "^tunnel " "$TMP/code-stub.log"'            'sandbox-code: up signed in starts the tunnel'
ok 'grep -q -- "--accept-server-license-terms" "$TMP/code-stub.log"' \
                                                        'sandbox-code: up passes the license flag'
ok 'grep -q -- "--name" "$TMP/code-stub.log"'           'sandbox-code: up names the tunnel'

MANGEN="$DIR/../image/sandbox-manpage"
MCFG="$TMP/man.toml"
MOUT="$TMP/sandbox.7"
gen_man() { python3 "$MANGEN" "$MCFG" "${1:-}" > "$MOUT" 2>"$TMP/man.err"; }

cat > "$MCFG" <<'TOML'
[apt]
packages = ["podman", "ripgrep"]
[brew]
taps = ["hashicorp/tap"]
formulae = ["gh", "jq"]
casks = ["tflint"]
[post_install]
commands = ["gcloud components install gke-gcloud-auth-plugin --quiet"]
[k3s]
disk = "8G"
TOML
ok 'gen_man'                                            'sandbox-manpage: writes a page'
ok 'head -1 "$MOUT" | grep -q "^\.TH SANDBOX 7"'        'sandbox-manpage: starts with the man header'
ok 'grep -q "podman, ripgrep" "$MOUT"'                  'sandbox-manpage: lists the apt packages'
ok 'grep -q "hashicorp/tap" "$MOUT"'                    'sandbox-manpage: lists the brew taps'
ok 'grep -q "gh, jq" "$MOUT"'                           'sandbox-manpage: lists the formulae'
ok 'grep -q "tflint" "$MOUT"'                           'sandbox-manpage: lists the casks'
ok 'grep -qF "gke\\-gcloud\\-auth\\-plugin" "$MOUT"'    'sandbox-manpage: lists the post_install commands'
ok 'grep -qF "sandbox\\-k3s up" "$MOUT"'                'sandbox-manpage: documents sandbox-k3s'
ok 'grep -qF "sandbox\\-code login" "$MOUT"'            'sandbox-manpage: documents sandbox-code'

ok 'gen_man "curl man-db zsh"'                          'sandbox-manpage: accepts the base packages'
ok 'grep -qF "curl, man\\-db, zsh" "$MOUT"'             'sandbox-manpage: lists the base toolchain'

no 'grep -qF "man-db" "$MOUT"'                          'sandbox-manpage: escapes hyphens for troff'

printf '[apt]\npackages = []\n' > "$MCFG"
ok 'gen_man'                                            'sandbox-manpage: writes a page with nothing configured'
ok '[ "$(grep -c "None configured." "$MOUT")" -ge 4 ]'  'sandbox-manpage: says so where a list is empty'
ok 'grep -qF "sandbox\\-k3s up" "$MOUT"'                'sandbox-manpage: documents sandbox-k3s regardless of config'
ok 'grep -qF "sandbox\\-code login" "$MOUT"'            'sandbox-manpage: documents sandbox-code regardless of config'

ok 'grep -q "does not start at launch" "$MOUT"'         'sandbox-manpage: says k3s stays stopped by default'
printf '[k3s]\nautostart = true\n' > "$MCFG"
ok 'gen_man'                                            'sandbox-manpage: writes a page with k3s autostart on'
ok 'grep -q "starts at launch" "$MOUT"'                 'sandbox-manpage: says k3s starts at launch when autostart is on'
no 'grep -q "does not start at launch" "$MOUT"'         'sandbox-manpage: drops the stopped wording when autostart is on'

ENTRY="$DIR/../image/entrypoint.sh"
EBIN="$TMP/ebin"
ELOG="$TMP/entry.log"
ECFG="$TMP/entry.toml"
mkdir -p "$EBIN" "$TMP/ehome"
for helper in sandbox-kubeconfig sandbox-k3s sandbox-code sandbox-setup; do
    printf '#!/bin/sh\necho "%s $*" >> "$SANDBOX_TEST_LOG"\n' "$helper" > "$EBIN/$helper"
    chmod +x "$EBIN/$helper"
done
run_entrypoint() {
    : > "$ELOG"
    HOME="$TMP/ehome" SANDBOX_BIN="$EBIN" SANDBOX_CONFIG="$ECFG" \
        SANDBOX_TEST_LOG="$ELOG" bash "$ENTRY" true
}

printf '[k3s]\ndisk = "8G"\n' > "$ECFG"
ok 'run_entrypoint'                        'entrypoint: runs'
ok 'grep -q "sandbox-kubeconfig" "$ELOG"'  'entrypoint: builds the kubeconfig'
ok 'grep -q "sandbox-code up" "$ELOG"'     'entrypoint: starts the VS Code tunnel'
ok 'grep -q "sandbox-setup" "$ELOG"'       'entrypoint: runs the per-launch setup'
no 'grep -q "sandbox-k3s" "$ELOG"'         'entrypoint: no autostart key -> k3s stays stopped'

printf '[k3s]\nautostart = false\n' > "$ECFG"
ok 'run_entrypoint'                        'entrypoint: runs with autostart off'
no 'grep -q "sandbox-k3s" "$ELOG"'         'entrypoint: autostart false -> k3s stays stopped'

printf '[k3s]\nautostart = true\n' > "$ECFG"
ok 'run_entrypoint'                        'entrypoint: runs with autostart on'
ok 'grep -q "sandbox-k3s up" "$ELOG"'      'entrypoint: autostart true -> starts k3s'

NICE="$DIR/../image/sandbox-nice.sh"
if [ -e /proc/self/oom_score_adj ]; then
    ok 'CLAUDECODE=1 bash -c ". \"$NICE\"; [ \"\$(nice)\" = 10 ]"' \
                                                            'sandbox-nice: nices the shell'
    ok 'CLAUDECODE=1 bash -c ". \"$NICE\"; [ \"\$(cat /proc/self/oom_score_adj)\" = 1000 ]"' \
                                                            'sandbox-nice: volunteers for the OOM killer'
    ok 'CLAUDECODE=1 bash -c ". \"$NICE\"; nice" | grep -q 10' \
                                                            'sandbox-nice: a child inherits the nice value'

    unchanged() { env -u CLAUDECODE bash -c "before=\$($1); . \"$NICE\"; [ \"\$($1)\" = \"\$before\" ]"; }

    ok 'unchanged nice'                                     'sandbox-nice: leaves other shells alone'
    ok 'unchanged "cat /proc/self/oom_score_adj"'           'sandbox-nice: leaves their OOM score alone'

    ok 'CLAUDECODE=1 bash -uc ". \"$NICE\""'                'sandbox-nice: survives set -u'
    ok 'CLAUDECODE=1 PATH=/nonexistent /bin/bash -c ". \"$NICE\""' \
                                                            'sandbox-nice: survives a missing renice'

    BG="$DIR/../image/sandbox-background"
    run_bg() { env -u CLAUDECODE SANDBOX_NICE="$NICE" sh "$BG" "$@"; }

    ok '[ "$(run_bg nice)" = 10 ]'                          'sandbox-background: nices the command'
    ok '[ "$(run_bg cat /proc/self/oom_score_adj)" = 1000 ]' \
                                                            'sandbox-background: volunteers it for the OOM killer'
    ok '[ "$(run_bg sh -c "sh -c nice")" = 10 ]'            'sandbox-background: what it starts inherits'

    no 'run_bg sh -c "cat /proc/\$\$/cmdline" | grep -qa sandbox-background' \
                                                            'sandbox-background: execs, leaving argv alone'
    no 'run_bg > /dev/null 2>&1'                            'sandbox-background: no command -> fails'
    ok 'run_bg --help | grep -q "background work"'          'sandbox-background: --help explains it'
fi

WELCOME="$DIR/../image/sandbox-welcome"
WMARK="$TMP/welcomed"
run_welcome() { SANDBOX_WELCOME_MARKER="$WMARK" bash "$WELCOME" > "$TMP/welcome.out" 2>&1; }

ok 'run_welcome'                                        'sandbox-welcome: runs'
ok 'grep -q "man sandbox" "$TMP/welcome.out"'           'sandbox-welcome: names the man page'
ok '[ -e "$WMARK" ]'                                    'sandbox-welcome: records that it printed'
ok 'run_welcome'                                        'sandbox-welcome: runs again'
ok '[ ! -s "$TMP/welcome.out" ]'                        'sandbox-welcome: stays quiet the second time'

KUBE="$DIR/../image/sandbox-kubeconfig"
KHOME="$TMP/kubehome"
KSHIM="$TMP/kubeshim"
KSRC="$TMP/k3s-src.yaml"

filemode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null; }

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

printf 'apiVersion: v1\nkind: Config\n# sentinel\n' > "$KHOME/.kube/config"
ok 'run_kubeconfig'                                  'kubeconfig: re-runs against an existing kubeconfig'
ok 'grep -q "# sentinel" "$KHOME/.kube/config"'      'kubeconfig: never clobbers an existing kubeconfig'
ok '[ ! -L "$KHOME/.kube/config" ]'                  'kubeconfig: leaves the home kubeconfig a real file'

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

printf 'written through\n' > "$KSHIM/config"
ok 'grep -q "written through" "$KHOME/.kube/config"' 'kubeconfig: shim writes through to the home file'
ok '[ ! -L "$KHOME/.kube/config" ]'                  'kubeconfig: write-through keeps the home file real'

echo "----"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
