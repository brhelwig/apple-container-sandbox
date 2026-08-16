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
# Only the first match, which is [k3s]'s: [vscode] carries an `enabled` of its
# own, and flipping that one too would test something this case isn't about.
sed -i.bak '0,/^enabled = false$/s//enabled = true/' "$REPOCOPY/config.toml"
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

# image/sandbox-code config parsing. The launch hook gates the tunnel on
# `sandbox-code enabled`, and the Dockerfile gates the CLI download on the same
# setting, so a wrong answer here means either a tunnel with no CLI or a CLI
# nobody starts.
CODEH="$DIR/../image/sandbox-code"
VSC="$TMP/vscode.toml"
printf '[vscode]\nenabled = true\n' > "$VSC"
ok 'SANDBOX_VSCODE_CONFIG="$VSC" bash "$CODEH" enabled' 'sandbox-code: enabled = true -> 0'
printf '[vscode]\nenabled = false\n' > "$VSC"
no 'SANDBOX_VSCODE_CONFIG="$VSC" bash "$CODEH" enabled' 'sandbox-code: enabled = false -> 1'
printf '[apt]\npackages = []\n' > "$VSC"
no 'SANDBOX_VSCODE_CONFIG="$VSC" bash "$CODEH" enabled' 'sandbox-code: no section -> 1'
no 'SANDBOX_VSCODE_CONFIG="$TMP/nope.toml" bash "$CODEH" enabled' 'sandbox-code: missing file -> 1'

# Every other subcommand needs the CLI, which is only in the image when the
# setting was on at build time. Without it they must say so rather than fail
# obscurely, since the fix is a config edit and a relaunch.
printf '[vscode]\nenabled = true\n' > "$VSC"

# run_code <subcommand> <signed-in?>: run sandbox-code against a stubbed CLI,
# or against a path where no CLI exists when <signed-in?> is "nocli". Output
# lands in $TMP/vsc.out.
run_code() {
    local cli="$TMP/code-stub"
    if [ "$2" = nocli ]; then
        cli="$TMP/no-such-cli"
    else
        # `tunnel user show` exits non-zero when signed out; `tunnel status`
        # reports a null tunnel when none is running (both as the real CLI does).
        cat > "$cli" <<STUBEOF
#!/usr/bin/env bash
case "\$*" in
    "tunnel user show") [ "$2" = yes ] && echo 'account' || { echo 'not logged in'; exit 1; } ;;
    "tunnel status") echo '{"tunnel":null,"service_installed":false}' ;;
    *) echo "\$*" >> "$TMP/code-stub.log" ;;
esac
STUBEOF
        chmod +x "$cli"
    fi
    SANDBOX_VSCODE_CONFIG="$VSC" SANDBOX_VSCODE_CLI="$cli" HOME="$TMP" \
        bash "$CODEH" "$1" >"$TMP/vsc.out" 2>&1
}

no 'run_code up nocli'                                  'sandbox-code: up without the CLI -> fails'
ok 'grep -q "VS Code CLI isn.t in this image" "$TMP/vsc.out"' \
                                                        'sandbox-code: up without the CLI says why'

# The launch hook runs `up` on every launch of an enabled sandbox, including
# ones that were never signed in. It has to fail with the fix in hand.
rm -f "$TMP/code-stub.log"
no 'run_code up no'                                     'sandbox-code: up signed out -> fails'
ok 'grep -q "sandbox-code login" "$TMP/vsc.out"'        'sandbox-code: up signed out names the login command'
ok '[ ! -e "$TMP/code-stub.log" ]'                      'sandbox-code: up signed out starts no tunnel'

no 'run_code status yes'                                'sandbox-code: status with no tunnel -> fails'
ok 'grep -q "tunnel: not running" "$TMP/vsc.out"'       'sandbox-code: status says the tunnel is down'

# Signed in, `up` launches the tunnel in the background, so give the detached
# process a moment to record its arguments. Without
# --accept-server-license-terms the CLI waits for a prompt nobody can answer.
rm -f "$TMP/code-stub.log"
run_code up yes
waited=0
while [ ! -s "$TMP/code-stub.log" ] && [ "$waited" -lt 20 ]; do sleep 0.1; waited=$((waited+1)); done
ok 'grep -q "^tunnel " "$TMP/code-stub.log"'            'sandbox-code: up signed in starts the tunnel'
ok 'grep -q -- "--accept-server-license-terms" "$TMP/code-stub.log"' \
                                                        'sandbox-code: up passes the license flag'
ok 'grep -q -- "--name" "$TMP/code-stub.log"'           'sandbox-code: up names the tunnel'

# image/sandbox-manpage. The page is what a sandbox can say about itself from
# the inside, so its tool lists have to come from the config the image was
# built with — a page that lists something the build didn't install is worse
# than no page.
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
enabled = true
[vscode]
enabled = true
TOML
ok 'gen_man'                                            'sandbox-manpage: writes a page'
ok 'head -1 "$MOUT" | grep -q "^\.TH SANDBOX 7"'        'sandbox-manpage: starts with the man header'
ok 'grep -q "podman, ripgrep" "$MOUT"'                  'sandbox-manpage: lists the apt packages'
ok 'grep -q "hashicorp/tap" "$MOUT"'                    'sandbox-manpage: lists the brew taps'
ok 'grep -q "gh, jq" "$MOUT"'                           'sandbox-manpage: lists the formulae'
ok 'grep -q "tflint" "$MOUT"'                           'sandbox-manpage: lists the casks'
ok 'grep -qF "gke\\-gcloud\\-auth\\-plugin" "$MOUT"'    'sandbox-manpage: lists the post_install commands'
ok 'grep -qF "sandbox\\-k3s up" "$MOUT"'                'sandbox-manpage: documents sandbox-k3s when enabled'
ok 'grep -qF "sandbox\\-code login" "$MOUT"'            'sandbox-manpage: documents sandbox-code when enabled'

# The base toolchain comes from the same build argument that installs it, so
# the page and the image cannot disagree about it.
ok 'gen_man "curl man-db zsh"'                          'sandbox-manpage: accepts the base packages'
ok 'grep -qF "curl, man\\-db, zsh" "$MOUT"'             'sandbox-manpage: lists the base toolchain'

# A hyphen has to reach troff escaped, or the name renders as a dash and stops
# being the string you would type or search for.
no 'grep -qF "man-db" "$MOUT"'                          'sandbox-manpage: escapes hyphens for troff'

# A sandbox with nothing configured still gets a page, and it has to say the
# lists are empty rather than leaving a heading with nothing under it.
printf '[apt]\npackages = []\n' > "$MCFG"
ok 'gen_man'                                            'sandbox-manpage: writes a page with nothing configured'
ok '[ "$(grep -c "None configured." "$MOUT")" -ge 4 ]'  'sandbox-manpage: says so where a list is empty'
no 'grep -qF "sandbox\\-k3s up" "$MOUT"'                'sandbox-manpage: omits sandbox-k3s when disabled'
no 'grep -qF "sandbox\\-code login" "$MOUT"'            'sandbox-manpage: omits sandbox-code when disabled'
ok 'grep -qF "Set enabled under [k3s]" "$MOUT"'         'sandbox-manpage: says how to enable k3s'
ok 'grep -qF "Set enabled under [vscode]" "$MOUT"'      'sandbox-manpage: says how to enable the tunnel'

# image/sandbox-nice.sh. Sourced by every shell Claude spawns a command in, so
# what it does to that shell is what every command inherits. The assertions read
# the shell's own state after sourcing, since a setting that silently failed to
# apply looks exactly like one that was never asked for.
#
# Linux only: macOS has no /proc and no ionice, and this runs on the host as
# well as in CI.
NICE="$DIR/../image/sandbox-nice.sh"
if [ -e /proc/self/oom_score_adj ]; then
    # A subshell per case: nice and oom_score_adj are inherited, so applying
    # them to the test harness itself would leak into every later case.
    ok 'CLAUDECODE=1 bash -c ". \"$NICE\"; [ \"\$(nice)\" = 10 ]"' \
                                                            'sandbox-nice: nices the shell'
    ok 'CLAUDECODE=1 bash -c ". \"$NICE\"; [ \"\$(cat /proc/self/oom_score_adj)\" = 1000 ]"' \
                                                            'sandbox-nice: volunteers for the OOM killer'
    ok 'CLAUDECODE=1 bash -c ". \"$NICE\"; nice" | grep -q 10' \
                                                            'sandbox-nice: a child inherits the nice value'

    # Only Claude's shells. An interactive shell, zellij and claude itself have
    # to keep theirs, or the change protects nothing. CLAUDECODE has to be
    # unset rather than left out: these tests run under Claude often enough,
    # and there it is already in the environment.
    ok 'env -u CLAUDECODE bash -c ". \"$NICE\"; [ \"\$(nice)\" = 0 ]"' \
                                                            'sandbox-nice: leaves other shells alone'
    ok 'env -u CLAUDECODE bash -c ". \"$NICE\"; [ \"\$(cat /proc/self/oom_score_adj)\" = 0 ]"' \
                                                            'sandbox-nice: leaves their OOM score alone'

    # It runs in shells with -u set, and in ones where renice or ionice is
    # missing, so neither may fail the shell it was sourced into.
    ok 'CLAUDECODE=1 bash -uc ". \"$NICE\""'                'sandbox-nice: survives set -u'
    ok 'CLAUDECODE=1 PATH=/nonexistent /bin/bash -c ". \"$NICE\""' \
                                                            'sandbox-nice: survives a missing renice'

    # image/sandbox-background, which puts a command under the same settings on
    # purpose. sandbox-k3s starts the cluster through it, so the whole cluster
    # and its pods run as background work.
    BG="$DIR/../image/sandbox-background"
    run_bg() { env -u CLAUDECODE SANDBOX_NICE="$NICE" sh "$BG" "$@"; }

    ok '[ "$(run_bg nice)" = 10 ]'                          'sandbox-background: nices the command'
    ok '[ "$(run_bg cat /proc/self/oom_score_adj)" = 1000 ]' \
                                                            'sandbox-background: volunteers it for the OOM killer'
    ok '[ "$(run_bg sh -c "sh -c nice")" = 10 ]'            'sandbox-background: what it starts inherits'

    # It execs, so the command keeps its own argv — sandbox-k3s finds and stops
    # the server by matching that.
    no 'run_bg sh -c "cat /proc/\$\$/cmdline" | grep -qa sandbox-background' \
                                                            'sandbox-background: execs, leaving argv alone'
    no 'run_bg > /dev/null 2>&1'                            'sandbox-background: no command -> fails'
    ok 'run_bg --help | grep -q "background work"'          'sandbox-background: --help explains it'
fi

# image/sandbox-welcome. Every interactive zsh runs it, so it prints on the
# first one and stays quiet after: a pointer repeated in every zellij pane
# stops being a pointer and becomes noise.
WELCOME="$DIR/../image/sandbox-welcome"
WMARK="$TMP/welcomed"
run_welcome() { SANDBOX_WELCOME_MARKER="$WMARK" bash "$WELCOME" > "$TMP/welcome.out" 2>&1; }

ok 'run_welcome'                                        'sandbox-welcome: runs'
ok 'grep -q "man sandbox" "$TMP/welcome.out"'           'sandbox-welcome: names the man page'
ok '[ -e "$WMARK" ]'                                    'sandbox-welcome: records that it printed'
ok 'run_welcome'                                        'sandbox-welcome: runs again'
ok '[ ! -s "$TMP/welcome.out" ]'                        'sandbox-welcome: stays quiet the second time'

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

# GNU stat first: its -f is --file-system, which prints to stdout AND exits
# non-zero here, so trying the BSD form first would pollute the output on Linux.
filemode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null; }

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
