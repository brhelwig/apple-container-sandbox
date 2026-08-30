# apple-container-sandbox

Ad-hoc Linux sandboxes on [Apple Container](https://github.com/apple/container).
Each sandbox is a persistent home dir and a container keyed by a single
`<name>`. It runs a published image — this repo builds nothing.

## Install

```sh
git clone https://github.com/brhelwig/apple-container-sandbox.git ~/.sandbox
~/.sandbox/install.sh
```

`install.sh` creates `~/Sandboxes`, seeds a `config.toml` from
`config.toml.example` (only if you don't have one yet), and prints the line to
add `~/.sandbox/bin` to your PATH. The menu needs `gum`; it offers to
`brew install gum` the first time you open it without one. `sandbox <name>`
skips the menu and doesn't need `gum` at all.

## Usage

```sh
sandbox              # menu: launch a sandbox, or stop/rename/reset/delete one
sandbox myproject    # launch "myproject" and attach a shell (creates it if new)
sandbox -d myproject # launch it without attaching anything
sandbox --image ghcr.io/you/img:tag myproject   # pin it to an image of its own
sandbox --pull myproject                        # fetch the image again first
sandbox --ssh-port 2250 myproject               # serve its SSH on this port
sandbox --help
```

**A sandbox keeps running when you leave its shell.** Launches are detached and
attaching is a separate step, so a build or an agent you start inside one
survives closing the terminal. Stop one from the menu or with
`container stop <name>`. That is the only thing that stops it.

Launching a sandbox that already runs attaches to it. Where the image it runs
has changed since it started, `sandbox` says so and asks before restarting it,
because a restart loses everything running inside. Decline, and it attaches to
what is already there.

Deleting removes the container and puts the home dir at `~/Sandboxes/<name>` in
the Trash, so the sandbox leaves the menu and its files are still there until you
empty the Trash. Stopping instead of deleting keeps both, and the next launch
picks up where you left off.

Resetting a sandbox drops the image ref pinned to it, fetches `[image].ref` from
the config, and recreates its container on that. The home dir is untouched, so
this changes what the sandbox runs on and keeps everything you put in it.

Homes live at `~/Sandboxes/<name>` and are mounted as the container's entire
home, so auth, config, and shell history persist across image changes and stay
separate between sandboxes. The container mounts **only** the home dir — drop
files into `~/Sandboxes/<name>` in Finder.

## Choosing an image

Every sandbox runs a published OCI image. By default that is
[`ghcr.io/brhelwig/dev-container`](https://github.com/brhelwig/dev-container),
which brings a Debian toolchain, Homebrew, zsh with oh-my-zsh, podman, k3s, the
VS Code CLI, and an entrypoint that starts sshd, a VS Code tunnel, tailscale, a
podman socket and a background zellij session.

Three ways to change it, most specific first:

```sh
sandbox --image ghcr.io/you/img:tag myproject   # this sandbox, from now on
```

The ref is recorded in `~/Sandboxes/myproject/.sandbox-image` and used on every
later launch. Pick `↺ Reset image…` from the menu to follow the config again.

```toml
[image]
ref = "ghcr.io/you/img:tag"      # every sandbox that has no pin of its own
```

With neither, sandboxes run `ghcr.io/brhelwig/dev-container:latest-arm64`.

**The launcher asks the image rather than asking you.** The home it mounts over,
the account SSH tells you to log in as, and the shell it attaches all come from
the image. It reads the image's OCI config first, and for an image that declares
none of that — a plain `debian:bookworm`, say — it starts the image once with its
entrypoint bypassed and asks. That takes about a second, and the answer is
remembered per sandbox, so it happens once per image.

```sh
sandbox --image debian:bookworm plain    # works with no configuration at all
```

**Moving tags drift.** `latest-arm64` is rebuilt weekly, and nothing notices
until something fetches it. `sandbox --pull <name>` fetches the ref again and
offers to restart the sandbox if what came down differs from what it is running.
The comparison is on the image digest, so a ref that resolves to the same image
under a different spelling doesn't cause a pointless restart.

## Headless

`sandbox -d <name>` launches a sandbox without attaching anything to it. The
launcher reports the ways in and returns your prompt.

```sh
sandbox -d myproject       # start it, then report the ways in
sandbox myproject          # attach a shell whenever you want one
container stop myproject   # stop it
```

It reports SSH from the Mac's side — the port it published and how many keys
would be accepted — so a sandbox with no authorized key says so rather than
coming up silently with no way in. If the image writes a VS Code tunnel log into
the home as `.code-tunnel.log`, the launcher watches it for up to 30 seconds and
prints the link. It only reads what this launch wrote, so a link from last week
is never reported as this one. Set `SANDBOX_TUNNEL_WAIT` to change that budget.

An ordinary launch differs only in attaching a shell afterwards.

## Configuring the sandbox (`config.toml`)

Your config lives in `config.toml`, which is **gitignored** and seeded from the
tracked **`config.toml.example`**. Start from the template (this is exactly what
`install.sh` does on first run):

```sh
cp config.toml.example config.toml
```

Keeping it untracked means editing it never conflicts with `git pull`.

```toml
[image]
ref = "ghcr.io/brhelwig/dev-container:latest-arm64"

[resources]
memory = "4G"                    # container memory (K/M/G/T/P); omit for the default
cpus   = 4                       # container CPU count; omit for the default

[ssh]
enabled = true                   # publish a port for every sandbox
port    = 2222                   # first port to hand out; each sandbox gets its own
address = "0.0.0.0"              # every address of the Mac; "127.0.0.1" for the Mac alone
```

- `[image].ref` picks what every sandbox runs — see
  [Choosing an image](#choosing-an-image). It is the only image setting, because
  everything else about an image comes from the image.
- `[resources]` sets each sandbox's memory and CPU (passed to `container run`).
  Omit a value to use Apple Container's default (~1 GiB memory).
- `[ssh]` decides whether every sandbox serves SSH, which port each one gets, and
  which address of the Mac that port is open on — see [SSH](#ssh).

## SSH

Every sandbox gets a port on the Mac and the launcher seeds its authorized keys.
Serving SSH on the inside is the image's job; `dev-container` starts sshd at
launch.

**A key is the only way in**, assuming the image's sshd is configured that way —
`dev-container`'s refuses passwords and root logins. The launcher copies every
`*.pub` in your Mac's `~/.ssh`, plus every key already in your Mac's own
`~/.ssh/authorized_keys`, into a sandbox the first time it creates the home, so
usually there is nothing to set up — this also covers hardware-backed keys
(security keys, agent-only keys) that never leave a `.pub` file lying around.
To authorize another key, append it to `~/Sandboxes/<name>/.ssh/authorized_keys`
— that file is the sandbox's `~/.ssh/authorized_keys`, so you can write it from
either side. If your Mac has no key yet, `ssh-keygen -t ed25519` makes one.

**One port per sandbox.** The launcher publishes the sandbox's SSH port on a port
of the Mac that belongs to that sandbox alone, so every sandbox can serve SSH at
the same time. Ports are handed out from `[ssh].port` upward, recorded in
`~/Sandboxes/<name>/.sandbox-ssh-port`, and kept for the life of the home. Name
one yourself with `sandbox --ssh-port <port> <name>`.

**Log in as the image's user, not yours.** `sandbox -d` prints the exact command;
for `dev-container` that is `ssh -p <port> dev@127.0.0.1`.

**It is reachable from other machines.** The port is open on every address the
Mac has, so a tailnet, the LAN, or anything else that reaches the Mac reaches the
sandbox at that port. Set `[ssh].address = "127.0.0.1"` to narrow it to the Mac
itself, or `[ssh].enabled = false` to turn it off. See
[Security scope](#security-scope).

**The host key survives the container** as long as the image keeps it in the
home. `dev-container` puts it in `~/.ssh-host-keys`, which is the bind-mounted
sandbox home, so recreating the container doesn't change the fingerprint and
`ssh` never warns that the host changed.

## VS Code (Remote Tunnels)

Running a tunnel is the image's job. `dev-container` ships the VS Code CLI and
starts a tunnel at launch once you have signed in, keeping the credentials and
the downloaded server under `~/.vscode` — the bind-mounted sandbox home — so one
sign-in survives container recreation. Sign in from inside the sandbox:

```sh
code tunnel user login
```

The launcher's part is only to report the link on a headless launch, which it
reads out of `.code-tunnel.log` in the sandbox home.

A running tunnel is a way into the sandbox from outside the machine — see
[Security scope](#security-scope).

## Security scope

This is a **convenience sandbox, not a security boundary.** Know what it does
and does not protect:

- **No network controls.** The container has unrestricted network access — it
  reaches the internet and your LAN like any host process. Nothing here
  firewalls, proxies, or limits egress.
- **Secrets are written to the filesystem in plaintext — not a keychain.** A
  sandbox's home is a bind mount at `~/Sandboxes/<name>` on your host. Anything
  written there (`gh`, `gcloud`, `aws` credentials, SSH keys, tokens, shell
  history) is stored as plain files on your host disk. Linux has no
  macOS-Keychain equivalent in play, so nothing lands in an OS secret store —
  at-rest protection is only whatever your host provides (disk encryption, file
  permissions, backups).
- **Isolation is VM/process-level only.** Each sandbox runs in its own Apple
  Container (a lightweight Linux VM), separating sandboxes from each other and
  from macOS — but a sandbox still runs your code with full network and your
  mounted home. It is not a jail for untrusted code.
- **Every sandbox runs without capability limits.** Apple Container's standard
  capability set withholds `CAP_SYS_ADMIN` and `CAP_NET_ADMIN`. Every sandbox
  runs with `--cap-add ALL` instead, so an image that wants to run nested
  containers or a Kubernetes cluster can. Code in a sandbox is effectively root
  over that VM — still contained by the VM boundary, but with none of the
  in-guest restraint a capability-limited container has.
- **You are running someone else's image.** Whatever the ref resolves to runs
  with those capabilities, your mounted home, and a published port. A moving tag
  means the code changes under you between launches. Pin a digest
  (`--image name@sha256:…`) where that matters.
- **A tunnel is a way in from outside the machine.** A running tunnel means
  anyone signed in to that GitHub or Microsoft account can open the sandbox — its
  files and a terminal in it — from any machine, and the connection is relayed by
  a third-party service rather than staying on your network. The credentials that
  keep it running are plain files in the sandbox home.
- **SSH is a way in from outside the machine too, and it is on by default.**
  Each sandbox's port is open on **every** address your Mac has, so anything that
  reaches the Mac — the LAN, a tailnet, the internet where the Mac is exposed to
  it — can try that port. What stands in the way is the key: a login needs a
  private key matching a line of `~/Sandboxes/<name>/.ssh/authorized_keys`. The
  launcher seeds that file with your Mac's own public keys, so whoever holds a key
  on your Mac can already get in. Whether passwords and root logins are refused
  is the image's sshd config, not this repo's — check the image you run. Narrow
  the port to the Mac with `[ssh].address = "127.0.0.1"`, or turn the server off
  with `[ssh].enabled = false`.

**Bottom line: a sandbox is only as secure as the host it runs on.** Don't put
secrets in a sandbox you wouldn't put on the host, and don't run untrusted code
expecting containment.

## Tests

```sh
bash test/run.sh
```

Every push also runs these on GitHub Actions alongside ShellCheck. Launching a
real sandbox isn't covered: Apple Container needs the Virtualization framework,
which hosted runners can't provide.
