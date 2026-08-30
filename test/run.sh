#!/usr/bin/env bash
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export SANDBOX_HOMES="$TMP/homes"

. "$DIR/../bin/lib.sh"

pass=0 fail=0
ok()  { if eval "$1"; then echo "ok   $2"; pass=$((pass+1)); else echo "FAIL $2"; fail=$((fail+1)); fi; }
no()  { if eval "$1"; then echo "FAIL $2"; fail=$((fail+1)); else echo "ok   $2"; pass=$((pass+1)); fi; }

filemode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null; }

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
printf '[ssh]\nenabled = true\n' > "$RES"
ok '[ -z "$(sandbox_resource_args "$RES")" ]' 'resource args: no section -> none'
ok '[ -z "$(sandbox_resource_args "$TMP/nope.toml")" ]' 'resource args: missing file -> none'

ICFG="$TMP/image.toml"
printf '[image]\nref = "example/img:1"\nhome = "/home/dev"\npull = true\n' > "$ICFG"
ok '[ "$(sandbox_config "$ICFG" image ref other)" = "example/img:1" ]' 'config: reads ref'
ok '[ "$(sandbox_config "$ICFG" image home /home/x)" = "/home/dev" ]'  'config: reads home'
ok '[ "$(sandbox_config "$ICFG" image pull false)" = "true" ]'         'config: booleans print lowercase'
printf '[image]\nref = "example/img:1"\n' > "$ICFG"
ok '[ "$(sandbox_config "$ICFG" image home /home/x)" = "/home/x" ]'    'config: absent key -> default'
ok '[ "$(sandbox_config "$ICFG" resources memory 1G)" = "1G" ]'        'config: absent section -> default'
ok '[ "$(sandbox_config "$TMP/nope.toml" image ref d)" = "d" ]'        'config: missing file -> default'

ok 'valid_image_ref "ghcr.io/o/n:latest-arm64"'    'image ref: accepts a registry ref'
ok 'valid_image_ref "debian@sha256:abc123"'        'image ref: accepts a digest ref'
no 'valid_image_ref "bad ref"'                     'image ref: rejects a space'
no 'valid_image_ref "img; rm -rf /"'               'image ref: rejects a shell metacharacter'
no 'valid_image_ref ""'                            'image ref: rejects empty'

TLOG="$TMP/tunnel.log"
printf 'open https://old.example/tunnel/a\n' > "$TLOG"
OFFSET="$(sandbox_file_size "$TLOG")"
ok '[ "$(sandbox_tunnel_url "$TLOG" 0)" = "https://old.example/tunnel/a" ]' \
                                                   'tunnel: reads the link out of the log'
no 'sandbox_tunnel_url "$TLOG" "$OFFSET"'          'tunnel: a link written before this launch is not one'
printf 'open https://new.example/tunnel/b\n' >> "$TLOG"
ok '[ "$(sandbox_tunnel_url "$TLOG" "$OFFSET")" = "https://new.example/tunnel/b" ]' \
                                                   'tunnel: reads the link this launch wrote'
no 'sandbox_tunnel_url "$TMP/no-such.log" 0'       'tunnel: no log -> no link'

KHOMES="$TMP/keyhomes"
mkdir -p "$KHOMES/counted/.ssh"
printf '# a comment\n\n   \nssh-ed25519 AAAAone a\nssh-rsa AAAAtwo b\n' \
    > "$KHOMES/counted/.ssh/authorized_keys"
count_keys() { SANDBOX_HOMES="$KHOMES" sandbox_authorized_key_count "$1"; }
ok '[ "$(count_keys counted)" = 2 ]'               'keys: counts only lines that authorize somebody'
ok '[ "$(count_keys nosuch)" = 0 ]'                'keys: no file -> none'

mkdir -p "$SANDBOX_HOMES/alpha" "$SANDBOX_HOMES/beta"
ok '[ "$(list_sandboxes | tr "\n" " ")" = "alpha beta " ]' 'lists sorted dirs'
ok '[ -z "$(SANDBOX_HOMES=$TMP/none list_sandboxes)" ]' 'empty when dir absent'

ok 'valid_port 22'                    'port: accepts 22'
ok 'valid_port 65535'                 'port: accepts the highest port'
no 'valid_port 0'                     'port: rejects zero'
no 'valid_port 65536'                 'port: rejects one above the range'
no 'valid_port 22x'                   'port: rejects a non-number'
no 'valid_port ""'                    'port: rejects empty'
no 'valid_port 123456789012345678901' 'port: rejects a number too big to compare'

SCFG="$TMP/ssh.toml"
SAVED_HOMES="$SANDBOX_HOMES"
SANDBOX_HOMES="$TMP/sshhomes"

printf '[ssh]\nenabled = true\n' > "$SCFG"
ok 'sandbox_ssh_enabled "$SCFG"'                        'ssh: on when the config says so'
printf '[ssh]\nenabled = false\n' > "$SCFG"
no 'sandbox_ssh_enabled "$SCFG"'                        'ssh: off when the config says so'
printf '[image]\nref = "example/img:1"\n' > "$SCFG"
ok 'sandbox_ssh_enabled "$SCFG"'                        'ssh: on with no [ssh] section'
ok '[ "$(sandbox_ssh_address "$SCFG")" = "0.0.0.0" ]'   'ssh: every address by default'
printf '[ssh]\naddress = "127.0.0.1"\n' > "$SCFG"
ok '[ "$(sandbox_ssh_address "$SCFG")" = "127.0.0.1" ]' 'ssh: one address when set'

printf '[ssh]\nport = 2300\n' > "$SCFG"
mkdir -p "$SANDBOX_HOMES/one" "$SANDBOX_HOMES/two" "$SANDBOX_HOMES/three"
ok '[ "$(sandbox_ssh_port "$SCFG" one)" = 2300 ]'       'ssh port: allocates from the configured base'
ok '[ "$(cat "$SANDBOX_HOMES/one/.sandbox-ssh-port")" = 2300 ]' \
                                                        'ssh port: records it in the home'
ok '[ "$(sandbox_ssh_port "$SCFG" one)" = 2300 ]'       'ssh port: keeps it on the next launch'
ok '[ "$(sandbox_ssh_port "$SCFG" two)" = 2301 ]'       'ssh port: skips a port another sandbox holds'
printf '2400\n' > "$SANDBOX_HOMES/two/.sandbox-ssh-port"
ok '[ "$(sandbox_ssh_port "$SCFG" two)" = 2400 ]'       'ssh port: honours a port written by hand'
ok '[ "$(sandbox_ssh_port "$SCFG" three)" = 2301 ]'     'ssh port: reuses a port nobody holds now'
printf '[image]\nref = "example/img:1"\n' > "$SCFG"
mkdir -p "$SANDBOX_HOMES/four"
ok '[ "$(sandbox_ssh_port "$SCFG" four)" = 2222 ]'      'ssh port: falls back to 2222 with no base set'

HOSTKEYS="$TMP/hostssh"
mkdir -p "$HOSTKEYS" "$SANDBOX_HOMES/keyed" "$SANDBOX_HOMES/unkeyed"
printf 'ssh-ed25519 AAAAfirst mac\n' > "$HOSTKEYS/id_ed25519.pub"
printf 'ssh-rsa AAAAsecond mac\n' > "$HOSTKEYS/id_rsa.pub"
seed() { SANDBOX_HOST_SSH_DIR="$1" sandbox_seed_authorized_keys "$2" > "$TMP/seed.out"; }
AKEYS="$SANDBOX_HOMES/keyed/.ssh/authorized_keys"

ok 'seed "$HOSTKEYS" keyed'                             'seed: runs'
ok '[ "$(wc -l < "$AKEYS")" -eq 2 ]'                    'seed: copies every public key on the Mac'
ok 'grep -q AAAAfirst "$AKEYS"'                         'seed: copies the key itself'
ok 'grep -q "Authorized 2" "$TMP/seed.out"'             'seed: says what it authorized'
ok '[ "$(filemode "$AKEYS")" = 600 ]'                   'seed: the keys file is private'
ok '[ "$(filemode "$SANDBOX_HOMES/keyed/.ssh")" = 700 ]' 'seed: the .ssh dir is private'
printf 'ssh-ed25519 AAAAmine me\n' > "$AKEYS"
ok 'seed "$HOSTKEYS" keyed'                             'seed: runs against a sandbox that has keys'
ok '[ "$(wc -l < "$AKEYS")" -eq 1 ]'                    'seed: never overwrites keys already there'
ok '[ ! -s "$TMP/seed.out" ]'                           'seed: stays quiet when there is nothing to do'
ok 'seed "$TMP/no-keys-here" unkeyed'                   'seed: runs with no key on the Mac'
no '[ -e "$SANDBOX_HOMES/unkeyed/.ssh/authorized_keys" ]' \
                                                        'seed: no key on the Mac -> writes nothing'

AKONLY="$TMP/hostssh-akonly"
mkdir -p "$AKONLY" "$SANDBOX_HOMES/akonly"
printf 'ssh-ed25519 AAAAthird mac\n' > "$AKONLY/authorized_keys"
KEYS_AKONLY="$SANDBOX_HOMES/akonly/.ssh/authorized_keys"
ok 'seed "$AKONLY" akonly'                              'seed: runs with only a host authorized_keys'
ok 'grep -q AAAAthird "$KEYS_AKONLY"'                   'seed: falls back to the host authorized_keys'

mkdir -p "$SANDBOX_HOMES/both"
printf 'ssh-ed25519 AAAAfourth mac\n' > "$HOSTKEYS/authorized_keys"
KEYS_BOTH="$SANDBOX_HOMES/both/.ssh/authorized_keys"
ok 'seed "$HOSTKEYS" both'                              'seed: runs with both pub files and authorized_keys'
ok 'grep -q AAAAfirst "$KEYS_BOTH" && grep -q AAAAfourth "$KEYS_BOTH"' \
                                                        'seed: merges pub files with the host authorized_keys'

SANDBOX_HOMES="$SAVED_HOMES"

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
mkdir -p "$REPOCOPY"
cp -R "$DIR/../bin" "$REPOCOPY/"
cp "$DIR/../config.toml.example" "$REPOCOPY/config.toml"

# Answers `image inspect` and `ls` from fixtures, and logs every argv so the
# assertions can read back what the launcher asked for.
CSTUB="$TMP/cstub"
mkdir -p "$CSTUB"
cat > "$CSTUB/container" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CMD_LOG"
[ "$1 $2" = "run --detach" ] && printf '%s\n' "$@" > "$RUN_LOG"
[ -n "${IMG_ENV+set}" ] || IMG_ENV='"HOME=/home/dev","SHELL=/usr/bin/zsh"'
if [ "$1" = exec ]; then
    case " $* " in
        *" tic "*)
            cat > /dev/null
            exit "${TIC_STATUS:-0}"
            ;;
        *" infocmp "*)
            [ -n "${TERMINFO_MISSING:-}" ] && ! grep -q " tic " "$CMD_LOG" && exit 1
            exit 0
            ;;
    esac
fi
case "$1 $2" in
    "run --rm")
        printf '%s\n%s\n%s\n' "${PROBE_HOME-/home/probed}" \
            "${PROBE_USER-probeduser}" "${PROBE_SHELL-/bin/probesh}"
        ;;
    "image inspect")
        [ -n "${IMG_MISSING:-}" ] && exit 1
        cat <<JSON
[ { "id": "abc",
    "configuration": {
      "creationDate": "2026-01-01T00:00:00Z",
      "name": "$3",
      "descriptor": {"digest": "${IMG_DIGEST:-sha256:aaa}"} },
    "variants": [ ${IMG_VARIANTS:-}
      { "platform": {"os": "linux", "architecture": "arm64"},
        "digest": "sha256:v", "size": 1,
        "config": { "architecture": "arm64", "os": "linux",
          "config": { "User": "${IMG_USER-dev}",
                      "Env": [$IMG_ENV],
                      "WorkingDir": "${IMG_WORKDIR-/home/dev}" } } } ] } ]
JSON
        ;;
    "ls --all")
        # A launch that already happened leaves the container running, the
        # way a real one would.
        if [ -z "${RUNNING_STATE:-}" ] && [ -s "$RUN_LOG" ]; then
            RUNNING_STATE=running
            RUNNING_NAME="$(sed -n '/^--name$/{n;p;}' "$RUN_LOG")"
            RUNNING_REF="$(sed -n '/^sleep$/{x;p;q;};h' "$RUN_LOG")"
            RUNNING_DIGEST="${IMG_DIGEST:-sha256:aaa}"
        fi
        if [ -n "${RUNNING_STATE:-}" ]; then
            cat <<JSON
[ { "id": "${RUNNING_NAME:-testbox}",
    "configuration": {"image": {"reference": "${RUNNING_REF:-}",
                                "descriptor": {"digest": "${RUNNING_DIGEST:-}"}}},
    "status": {"state": "$RUNNING_STATE"} } ]
JSON
        else
            echo '[]'
        fi
        ;;
esac
exit 0
STUBEOF
cat > "$CSTUB/gum" <<'STUBEOF'
#!/usr/bin/env bash
exit "${GUM_CONFIRM:-1}"
STUBEOF
cat > "$CSTUB/infocmp" <<'STUBEOF'
#!/usr/bin/env bash
[ -n "${HOST_INFOCMP_FAILS:-}" ] && exit 1
echo "$*|"
STUBEOF
chmod +x "$CSTUB/container" "$CSTUB/gum" "$CSTUB/infocmp"

DEFAULT_IMAGE='ghcr.io/brhelwig/dev-container:latest-arm64'

run_launch() {
    rm -f "$TMP/run.log" "$TMP/cmd.log"
    env RUN_LOG="$TMP/run.log" CMD_LOG="$TMP/cmd.log" \
        SANDBOX_HOMES="$TMP/homes" SANDBOX_TUNNEL_WAIT=0 \
        SANDBOX_HOST_SSH_DIR="$HOSTKEYS" \
        PATH="$CSTUB:$PATH" bash "$REPOCOPY/bin/sandbox" "$@" > "$TMP/out.txt" 2>&1
}

run_launch testbox
ok '[ -s "$TMP/run.log" ]'                          'launch: reaches container run'
ok 'grep -qx -- "--cap-add" "$TMP/run.log"'         'launch: passes --cap-add'
ok 'grep -qx "ALL" "$TMP/run.log"'                  'launch: grants ALL'
ok 'grep -qx -- "--init" "$TMP/run.log"'            'launch: runs an init, so orphans get reaped'
ok 'grep -qx -- "--detach" "$TMP/run.log"'          'launch: detaches, so the sandbox outlives the shell'
no 'grep -qx -- "--tty" "$TMP/run.log"'             'launch: opens no TTY on run'
ok 'grep -qx "$DEFAULT_IMAGE" "$TMP/run.log"'       'launch: runs the default image'
ok 'grep -qx -- "--volume" "$TMP/run.log"'          'launch: mounts a volume'
ok 'grep -q ":/home/dev$" "$TMP/run.log"'           'launch: mounts at the home the image declares'
ok 'grep -qx "sleep" "$TMP/run.log"'                'launch: holds the container open'
ok 'grep -q "^exec --interactive --tty" "$TMP/cmd.log"' 'launch: attaches with exec'
ok 'grep -q "TERM=" "$TMP/cmd.log"'                 'launch: gives the attached shell a TERM'
ok 'grep -q "is still running" "$TMP/out.txt"'      'launch: says the sandbox outlived the shell'
ok 'grep -qx -- "--publish" "$TMP/run.log"'         'launch: publishes a port for SSH'
ok 'grep -qx "0.0.0.0:2222:22" "$TMP/run.log"'      'launch: every address, to port 22 in the sandbox'
ok '[ "$(cat "$TMP/homes/testbox/.sandbox-ssh-port")" = 2222 ]' \
                                                    'launch: records the SSH port in the home'
ok 'grep -q AAAAfirst "$TMP/homes/testbox/.ssh/authorized_keys"' \
                                                    'launch: authorizes your keys the first time'
no '[ -e "$TMP/homes/testbox/.sandbox-image" ]'     'launch: pins no image of its own'
ok '[ "$(sed -n 2p "$TMP/homes/testbox/.sandbox-image-facts")" = /home/dev ]' \
                                                    'launch: records where it mounted'

run_launch -d testbox
ok '[ -s "$TMP/run.log" ]'                          'headless: reaches container run'
ok 'grep -qx -- "--detach" "$TMP/run.log"'          'headless: detaches'
no 'grep -q "^exec " "$TMP/cmd.log"'                'headless: attaches nothing'
ok 'grep -q "Attach a shell" "$TMP/out.txt"'        'headless: says how to get a shell'
ok 'grep -q "^ssh: " "$TMP/out.txt"'                'headless: reports SSH without entering the sandbox'

run_launch --headless testbox
ok 'grep -qx -- "--detach" "$TMP/run.log"'          'headless: --headless is the long form'

run_launch --nope; status=$?
ok '[ "$status" -eq 2 ]'                            'unknown option: exits 2'
no '[ -e "$TMP/run.log" ]'                          'unknown option: launches nothing'

run_launch sshbox
ok 'grep -qx "0.0.0.0:2223:22" "$TMP/run.log"'      'ssh: the next sandbox gets the next port'
run_launch othersshbox
ok 'grep -qx "0.0.0.0:2224:22" "$TMP/run.log"'      'ssh: and the one after that, the next again'

run_launch --ssh-port 2345 sshbox
ok 'grep -qx "0.0.0.0:2345:22" "$TMP/run.log"'      'ssh-port: publishes the port you name'
run_launch sshbox
ok 'grep -qx "0.0.0.0:2345:22" "$TMP/run.log"'      'ssh-port: it sticks on the next launch'

run_launch -d --ssh-port 2346 headlessssh
ok 'grep -qx -- "--detach" "$TMP/run.log"'          'ssh-port: combines with headless'
ok 'grep -qx "0.0.0.0:2346:22" "$TMP/run.log"'      'ssh-port: publishes under headless too'

run_launch --ssh-port 99999 toobig; status=$?
ok '[ "$status" -eq 2 ]'                            'ssh-port: rejects a port out of range'
no '[ -e "$TMP/run.log" ]'                          'ssh-port: launches nothing'

printf '[ssh]\nenabled = false\n' > "$REPOCOPY/config.toml"
run_launch sshoff
ok '[ -s "$TMP/run.log" ]'                          'ssh off: still launches'
no 'grep -qx -- "--publish" "$TMP/run.log"'         'ssh off: publishes nothing'

printf '[ssh]\naddress = "127.0.0.1"\nport = 2500\n' > "$REPOCOPY/config.toml"
run_launch loopbackonly
ok 'grep -qx "127.0.0.1:2500:22" "$TMP/run.log"'    'ssh address: publishes on that address alone'

cp "$DIR/../config.toml.example" "$REPOCOPY/config.toml"

run_launch --image example.com/other:1 pinned
ok '[ "$(cat "$TMP/homes/pinned/.sandbox-image")" = example.com/other:1 ]' \
                                                    'image: --image pins the sandbox to that ref'
ok 'grep -qx "example.com/other:1" "$TMP/run.log"'  'image: --image runs that ref'
run_launch pinned
ok 'grep -qx "example.com/other:1" "$TMP/run.log"'  'image: the pin sticks with no flag'
rm -f "$TMP/homes/pinned/.sandbox-image"
run_launch pinned
ok 'grep -qx "$DEFAULT_IMAGE" "$TMP/run.log"'       'image: deleting the pin follows the config again'

printf '[image]\nref = "example.com/config:2"\n' > "$REPOCOPY/config.toml"
run_launch configured
ok 'grep -qx "example.com/config:2" "$TMP/run.log"' 'image: [image].ref is the default for every sandbox'
run_launch --image example.com/wins:3 configured
ok 'grep -qx "example.com/wins:3" "$TMP/run.log"'   'image: a pin beats [image].ref'
cp "$DIR/../config.toml.example" "$REPOCOPY/config.toml"

run_launch --image 'bad ref; rm -rf /' evil; status=$?
ok '[ "$status" -eq 2 ]'                            'image: rejects a ref that is not one'
no '[ -e "$TMP/run.log" ]'                          'image: launches nothing on a bad ref'

run_launch --pull pulled
ok 'grep -q "^image pull" "$TMP/cmd.log"'           'pull: --pull fetches the image again'
run_launch nopull
no 'grep -q "^image pull" "$TMP/cmd.log"'           'pull: an ordinary launch does not'

IMG_MISSING=1 run_launch notpulled
ok 'grep -q "^image pull" "$TMP/cmd.log"'           'image: fetches one that is not here yet'

IMG_WORKDIR=/home/wd IMG_ENV='"SHELL=/bin/sh"' run_launch workdirbox
ok 'grep -q ":/home/wd$" "$TMP/run.log"'            'home: falls back to WorkingDir with no HOME'

IMG_WORKDIR=/ IMG_ENV='' IMG_USER=1000 run_launch -d probedbox; status=$?
ok '[ "$status" -eq 0 ]'                            'probe: an image that says nothing still launches'
ok 'grep -q "^run --rm --entrypoint sh" "$TMP/cmd.log"' 'probe: asks the image instead of asking you'
ok 'grep -q ":/home/probed$" "$TMP/run.log"'        'probe: mounts where the image says its home is'
no 'grep -q "/home/$USER" "$TMP/run.log"'           'probe: never guesses your Mac username'
ok 'grep -q "probeduser@127.0.0.1" "$TMP/out.txt"'  'probe: names the account, not a uid'
ok '[ "$(sed -n 2p "$TMP/homes/probedbox/.sandbox-image-facts")" = /home/probed ]' \
                                                    'probe: remembers the answer'

IMG_WORKDIR=/ IMG_ENV='' IMG_USER=1000 run_launch -d probedbox
no 'grep -q "^run --rm --entrypoint sh" "$TMP/cmd.log"' 'probe: does not ask twice for the same image'

AMD64_VARIANT='{ "platform": {"os": "linux", "architecture": "amd64"},
  "digest": "sha256:x", "size": 1,
  "config": {"architecture": "amd64", "os": "linux",
             "config": {"User": "other", "Env": ["HOME=/home/wrongarch"],
                        "WorkingDir": "/home/wrongarch"}} },'
IMG_VARIANTS="$AMD64_VARIANT" run_launch multiarch
ok 'grep -q ":/home/dev$" "$TMP/run.log"'           'arch: picks the variant matching this Mac'
no 'grep -q "wrongarch" "$TMP/run.log"'             'arch: ignores the other architecture'

run_launch attachbox
ok 'grep -q "zellij attach --create attachbox" "$TMP/cmd.log"' \
                                                    'attach: joins a zellij session named after the sandbox'
ok 'grep -q "command -v zellij" "$TMP/cmd.log"'     'attach: only where the image has zellij'
ok 'grep -q "/usr/bin/zsh -l" "$TMP/cmd.log"'       'attach: otherwise the shell the image names'
IMG_ENV='"HOME=/home/dev"' PROBE_SHELL=/bin/sh run_launch noshell
ok 'grep -q "/bin/sh -l" "$TMP/cmd.log"'            'attach: asks the image when it names no shell'

export TERM=xterm-256color
run_launch knownterm
ok 'grep -q "TERM=xterm-256color" "$TMP/cmd.log"'   'terminal: attaches with the terminal you are using'
no 'grep -q " tic " "$TMP/cmd.log"'                 'terminal: imports nothing the sandbox already knows'

export TERM=xterm-ghostty TERMINFO_MISSING=1
run_launch importterm
ok 'grep -q "tic -x -o /home/dev/.terminfo" "$TMP/cmd.log"' \
                                                    'terminal: teaches the sandbox a terminal it does not know'
ok 'grep -q "TERM=xterm-ghostty" "$TMP/cmd.log"'    'terminal: then attaches with that terminal'

TIC_STATUS=1 run_launch fallbackterm
ok 'grep -q "TERM=xterm-256color" "$TMP/cmd.log"'   'terminal: falls back to one every image knows'
ok 'grep -q "does not know xterm-ghostty" "$TMP/out.txt"' \
                                                    'terminal: says so when it falls back'

HOST_INFOCMP_FAILS=1 run_launch nodescription
ok 'grep -q "TERM=xterm-256color" "$TMP/cmd.log"'   'terminal: falls back when this Mac cannot describe it either'
unset TERM TERMINFO_MISSING

mkdir -p "$TMP/homes/tunnelbox"
printf 'open https://old.tunnel.example/x\n' > "$TMP/homes/tunnelbox/.code-tunnel.log"
run_launch -d tunnelbox
no 'grep -q "old.tunnel.example" "$TMP/out.txt"'    'tunnel: a link from an earlier launch is not this one'

mkdir -p "$TMP/homes/movedbox"
printf 'sha256:aaa\n/home/old\ndev\n/bin/sh\n' > "$TMP/homes/movedbox/.sandbox-image-facts"
run_launch movedbox
ok 'grep -q "used to mount at /home/old" "$TMP/out.txt"' 'home: says so when the mount point moved'

RUNNING_STATE=running RUNNING_REF="$DEFAULT_IMAGE" RUNNING_DIGEST=sha256:aaa \
    run_launch testbox
ok 'grep -q "^exec --interactive --tty" "$TMP/cmd.log"' 'running: attaches to it'
no 'grep -q "^run " "$TMP/cmd.log"'                 'running: starts no second container'
no 'grep -q "^stop " "$TMP/cmd.log"'                'running: stops nothing'
no 'grep -q "^delete " "$TMP/cmd.log"'              'running: deletes nothing'

RUNNING_STATE=running RUNNING_REF="$DEFAULT_IMAGE" RUNNING_DIGEST=sha256:old \
    GUM_CONFIRM=1 run_launch testbox
ok 'grep -q "^exec --interactive --tty" "$TMP/cmd.log"' 'stale digest, declined: attaches anyway'
no 'grep -q "^stop " "$TMP/cmd.log"'                'stale digest, declined: leaves it running'
no 'grep -q "^delete " "$TMP/cmd.log"'              'stale digest, declined: deletes nothing'

RUNNING_STATE=running RUNNING_REF="$DEFAULT_IMAGE" RUNNING_DIGEST=sha256:old \
    GUM_CONFIRM=0 run_launch testbox
ok 'grep -qx "stop testbox" "$TMP/cmd.log"'         'stale digest, confirmed: stops it'
ok 'grep -qx "delete --force testbox" "$TMP/cmd.log"' 'stale digest, confirmed: deletes it'
ok 'grep -q "^run " "$TMP/cmd.log"'                 'stale digest, confirmed: starts it again'

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
    *"Sandbox:"*)            cat > /dev/null; echo "🗑 Delete…" ;;
    *"Delete which sandbox"*) cat > /dev/null; echo "$DELETE_NAME" ;;
    confirm*)                exit "$GUM_CONFIRM" ;;
esac
STUBEOF
cat > "$DSTUB/osascript" <<'STUBEOF'
#!/usr/bin/env bash
exit 1
STUBEOF
chmod +x "$DSTUB/container" "$DSTUB/gum" "$DSTUB/osascript"

DHOME="$SANDBOX_HOMES/deleteme"
mkdir -p "$DHOME"
echo 'work' > "$DHOME/keepme"

DTRASH="$TMP/deletetrash"

run_delete() {
    rm -f "$TMP/delete.log"
    DELETE_LOG="$TMP/delete.log" DELETE_NAME=deleteme GUM_CONFIRM="$1" \
        SANDBOX_TRASH="$DTRASH" \
        PATH="$DSTUB:$PATH" bash "$REPOCOPY/bin/sandbox" >/dev/null 2>&1
}

run_delete 1
ok '[ ! -e "$TMP/delete.log" ]'                          'delete: declined -> touches nothing'
ok '[ -f "$DHOME/keepme" ]'                              'delete: declined -> the home dir stays'

run_delete 0
ok 'grep -q "delete --force deleteme" "$TMP/delete.log"' 'delete: deletes the container'
ok '[ ! -e "$DHOME" ]'                                   'delete: the home dir leaves ~/Sandboxes'
no 'list_sandboxes | grep -qx deleteme'                  'delete: the sandbox leaves the menu'
ok '[ -f "$DTRASH/deleteme/keepme" ]'                    'delete: the files are in the Trash, not gone'

STOPSTUB="$TMP/stopstub"
mkdir -p "$STOPSTUB"
cp "$DSTUB/container" "$STOPSTUB/container"
cat > "$STOPSTUB/gum" <<'STUBEOF'
#!/usr/bin/env bash
case "$*" in
    *"Sandbox:"*)          cat > /dev/null; echo "⏹ Stop…" ;;
    *"Stop which sandbox"*) cat > /dev/null; echo "$STOP_NAME" ;;
esac
STUBEOF
chmod +x "$STOPSTUB/gum"

SHOME="$SANDBOX_HOMES/stopme"
mkdir -p "$SHOME"
echo 'work' > "$SHOME/keepme"

rm -f "$TMP/delete.log"
DELETE_LOG="$TMP/delete.log" STOP_NAME=stopme \
    PATH="$STOPSTUB:$PATH" bash "$REPOCOPY/bin/sandbox" >/dev/null 2>&1
ok 'grep -qx "stop stopme" "$TMP/delete.log"'            'stop: stops the container'
no 'grep -q "delete" "$TMP/delete.log"'                  'stop: deletes nothing'
ok '[ -f "$SHOME/keepme" ]'                              'stop: keeps what is in the home dir'

TRSTUB="$TMP/trstub"
mkdir -p "$TRSTUB"
cat > "$TRSTUB/osascript" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "${!#}" >> "$OSA_LOG"
exit "${OSA_EXIT:-0}"
STUBEOF
chmod +x "$TRSTUB/osascript"

TRASH="$TMP/trash"
trash_it() {
    rm -f "$TMP/osa.log"
    (
        export OSA_LOG="$TMP/osa.log" OSA_EXIT="$1"
        export SANDBOX_TRASH="$TRASH" PATH="$TRSTUB:$PATH"
        sandbox_trash "$2"
    )
}

TBOX="$TMP/trashme"
mkdir -p "$TBOX"; echo 'work' > "$TBOX/keepme"
ok 'trash_it 0 "$TBOX"'                        'trash: Finder takes it'
ok 'grep -qx "$TBOX" "$TMP/osa.log"'           'trash: hands Finder the path as an argument'
no '[ -e "$TRASH" ]'                           'trash: no move of its own once Finder has it'

ok 'trash_it 1 "$TBOX"'                        'trash: Finder refused -> moves it instead'
ok '[ -f "$TRASH/trashme/keepme" ]'            'trash: the files arrive intact'
no '[ -e "$TBOX" ]'                            'trash: and leave where they were'

mkdir -p "$TBOX"; echo 'second' > "$TBOX/keepme"
ok 'trash_it 1 "$TBOX"'                        'trash: a name already in the Trash is no error'
ok '[ "$(cat "$TRASH/trashme/keepme")" = work ]'   'trash: the one already there is untouched'
ok '[ "$(cat "$TRASH/trashme 2/keepme")" = second ]' 'trash: the second lands beside it'
no '[ -e "$TRASH/trashme/trashme" ]'           'trash: and is not buried inside the first'

ok 'trash_it 1 "$TMP/never-existed"'           'trash: nothing to trash is not a failure'

RSTUB="$TMP/rstub"
mkdir -p "$RSTUB"
cp "$CSTUB/container" "$RSTUB/container"
cat > "$RSTUB/gum" <<'STUBEOF'
#!/usr/bin/env bash
case "$*" in
    *"Sandbox:"*)           cat > /dev/null; echo "↺ Reset image…" ;;
    *"Reset which sandbox"*) cat > /dev/null; echo "$RESET_NAME" ;;
    confirm*)               exit "$GUM_CONFIRM" ;;
esac
STUBEOF
chmod +x "$RSTUB/container" "$RSTUB/gum"

RHOMES="$TMP/rhomes"
RHOME="$RHOMES/resetme"

run_reset() {
    rm -rf "$RHOMES"
    mkdir -p "$RHOME"
    echo 'work' > "$RHOME/keepme"
    printf 'pinned/img:1\n' > "$RHOME/.sandbox-image"
    printf 'sha256:stale\n/home/pinned\npinneduser\n/bin/pinnedsh\n' > "$RHOME/.sandbox-image-facts"
    rm -f "$TMP/run.log" "$TMP/cmd.log"
    env RUN_LOG="$TMP/run.log" CMD_LOG="$TMP/cmd.log" \
        SANDBOX_HOMES="$RHOMES" SANDBOX_TUNNEL_WAIT=0 \
        SANDBOX_HOST_SSH_DIR="$HOSTKEYS" RESET_NAME=resetme GUM_CONFIRM="$1" \
        PATH="$RSTUB:$PATH" bash "$REPOCOPY/bin/sandbox" -d >/dev/null 2>&1
}

run_reset 1
ok '[ "$(cat "$RHOME/.sandbox-image")" = "pinned/img:1" ]' 'reset: declined -> the pin stays'
no '[ -s "$TMP/run.log" ]'                          'reset: declined -> starts nothing'

run_reset 0
no '[ -e "$RHOME/.sandbox-image" ]'                 'reset: drops the pinned ref'
ok 'grep -q "^image pull" "$TMP/cmd.log"'           'reset: fetches the ref again'
ok 'grep -qx "delete --force resetme" "$TMP/cmd.log"' 'reset: removes the container'
ok 'grep -qx "$DEFAULT_IMAGE" "$TMP/run.log"'       'reset: starts it on the config ref'
no 'grep -qx "pinned/img:1" "$TMP/run.log"'         'reset: not on the ref it was pinned to'
ok '[ -f "$RHOME/keepme" ]'                         'reset: keeps what is in the home dir'
ok 'grep -q "^sha256:aaa$" "$RHOME/.sandbox-image-facts"' 'reset: the stale facts are replaced'

echo "----"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
