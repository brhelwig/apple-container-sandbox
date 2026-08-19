# apple-container-sandbox

Ad-hoc Linux sandboxes on [Apple Container](https://github.com/apple/container).
Each sandbox is a persistent home dir, container, and zellij session keyed by a
single `<name>`, all sharing one image built from `image/Dockerfile`.

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
sandbox              # menu: launch a sandbox, or create/rename/delete a container
sandbox myproject    # launch "myproject" (offers to create it if new)
sandbox -d myproject # launch "myproject" headless — see below
sandbox --help
```

Deleting removes the container and nothing else. The home dir at
`~/Sandboxes/<name>` keeps every file in it, so the sandbox stays in the menu
and the next launch recreates the container. Delete a home dir yourself when you
want the files gone.

Homes live at `~/Sandboxes/<name>` and are mounted as the container's entire
home, so auth, config, and shell history persist across image rebuilds and stay
separate between sandboxes. The container mounts **only** the home dir — drop
files into `~/Sandboxes/<name>` in Finder.

## Headless

`sandbox -d <name>` launches a sandbox with no terminal attached. The container
runs detached, the cluster and the [VS Code tunnel](#vs-code-remote-tunnels)
start the way they always do, and the launcher waits for the tunnel, prints where
it stands, and returns your prompt. Close the terminal and open the sandbox from
VS Code.

```sh
sandbox -d myproject       # start it detached, then report the tunnel
sandbox myproject          # attach a shell whenever you want one
container stop myproject   # stop it
```

A headless launch differs from an ordinary one in two ways only:

- **No zellij session.** The container runs `sandbox-idle` in its place, which
  holds it open and exits on the stop signal. Attaching with `sandbox <name>`
  starts the zellij session then, and leaving that shell no longer stops the
  sandbox.
- **The tunnel is reported instead of a shell.** The launcher polls
  `sandbox-code status` inside the sandbox for up to 30 seconds and prints the
  result, so a sandbox that was never signed in says so rather than coming up
  silently with no way in. Set `SANDBOX_TUNNEL_WAIT` to change that budget.

Everything else is the same: same image, same home mount, same capabilities, and
the container is still removed when it stops.

## Finding your way around a sandbox

A sandbox can describe itself:

```sh
man sandbox
```

The page lists the tools installed in this sandbox, says where the home comes
from and what survives a rebuild, and covers the `sandbox-*` helpers. It is
written during the image build from the same `config.toml` that installs the
tools, so it describes the image it ships in rather than a list someone keeps
current by hand. Each freshly launched sandbox prints one line pointing at it.

## Claude in a sandbox

A command that Claude Code runs is niced to 10, put in the idle I/O class, and
made the first thing the kernel kills if the sandbox runs out of memory. So a
build or a test Claude starts loses the contest for CPU, disk and memory rather
than the session losing it — killing a command costs a command, killing claude
or zellij costs the session.

Claude spawns each command in its own shell, and that shell sets all three on
itself before the command starts. Every process under it inherits them. A shell
you type in keeps its own standing, and so do claude and zellij.

The OOM setting goes to the maximum rather than something milder because it
works from the command's side: each command volunteers itself, so nothing has to
raise claude's own standing. `ionice` has an effect only under an I/O scheduler
that implements priority, which is unverified for the Apple Container guest
kernel; the CPU and memory parts do not depend on it.

Run anything else the same way with `sandbox-background <command>`.

The k3s cluster starts through that wrapper, so k3s and what it runs
are niced and in the idle I/O class as well. Its OOM score is set rather than
inherited, because kubelet gives itself one — `deprioritize_server` in
`image/sandbox-k3s` covers the details. Each pod container keeps the score
kubelet computes from its quality of service class.

## Configuring the sandbox (`config.toml`)

Your config lives in `config.toml`, which is **gitignored** and seeded from the
tracked **`config.toml.example`**. Start from the template (this is exactly what
`install.sh` does on first run):

```sh
cp config.toml.example config.toml
```

Keeping it untracked means editing it never conflicts with `git pull`. Editing
`config.toml` (or anything in `image/`) changes the image's source hash, so the
next `sandbox <name>` rebuilds the image and recreates the sandbox on it.

```toml
[apt]
packages = ["podman", "ripgrep"]      # Debian packages (apt-native, arm64)

[brew]
taps     = ["hashicorp/tap"]          # taps are tapped AND trusted (so tap casks install)
formulae = ["gh", "node", "hashicorp/tap/terraform"]   # linuxbrew formulae
casks    = ["claude-code@latest"]     # Homebrew casks that ship a Linux build

[post_install]
commands = [                          # shell run at build time as the sandbox user (+ sudo)
  "gcloud components install gke-gcloud-auth-plugin --quiet",
]

[resources]
memory = "4G"                         # container memory (K/M/G/T/P); omit for the platform default
cpus   = 4                            # container CPU count; omit for the platform default

[k3s]
disk    = "8G"                        # sparse ext4 image holding cluster state
node_ip = "10.99.0.1"                 # fixed node address; must not collide with your LAN
```

- Prefer **apt** for stable, arch-native packages; **brew formulae** for current
  dev tooling; **casks** for prebuilt binaries (they must have a Linux build).
- A tap-provided formula/cask uses its fully-qualified name (e.g.
  `hashicorp/tap/terraform`) once its tap is listed in `taps`.
- `[post_install]` is for anything that isn't a package — component installs,
  downloading a binary or AppImage, etc. It runs after all installs and **fails
  the build** on error.
- `[resources]` sets each sandbox's memory and CPU (passed to `container run`).
  Omit a value to use Apple Container's default (~1 GiB memory). Changing these
  rebuilds the image on next launch, so the new limits take effect on a fresh
  container.
- `[k3s]` sizes and addresses the cluster every sandbox runs — see
  [Kubernetes](#kubernetes-k3s) below. Kubernetes and the VS Code CLI are always
  installed; there is nothing to turn on.

## Kubernetes (k3s)

Each sandbox gets its own single-node cluster, started in the background as the
sandbox launches. `kubectl`, `helm`,
`k9s` and friends come from `[brew].formulae`, and the cluster shows up in your
kubeconfig as a `k3s` context once it's ready.

```sh
sandbox-k3s status    # node + pod summary, or why it isn't up yet
sandbox-k3s down      # stop the cluster (state is kept)
sandbox-k3s up        # start it again
```

### Your kubeconfig

The cluster is added alongside whatever is already in `~/.kube/config`; nothing
there is modified, so remote clusters keep working next to the local one.

`KUBECONFIG` points into `/var/lib/sandbox/kube`, not straight at `~/.kube`,
because kubectl cannot take its lock file on the sandbox home — `image/sandbox-kubeconfig`
explains why. That directory's `config` entry symlinks to `~/.kube/config`, so
your kubeconfig still lands in the home and survives the container. Run
`sandbox-kubeconfig` to rebuild it by hand.

Bring-up takes roughly 30 s and ~800 MB of RAM. The launch hook doesn't wait for
it, so you get a shell immediately and the cluster converges behind you. If it
fails, you still get a shell — check `/var/log/k3s.log`.

**Cluster state persists.** It lives on a sparse ext4 image
(`~/Sandboxes/<name>/.sandbox-k3s.img`) that is loop-mounted inside the
container, so your workloads, cached images, and cluster objects survive
container recreation and image rebuilds. `disk` is a ceiling, not an
allocation — an `8G` image occupies ~1.5 GB of real disk with a cluster running.
The state can't live on the home dir directly because that's a virtiofs mount,
where `mknod` is denied and so overlayfs whiteouts are impossible.

To grow a disk later, stop the cluster and, in the sandbox,
`truncate -s <bigger> ~/.sandbox-k3s.img` then `resize2fs` it after remounting.
To start over, `sandbox-k3s down` and delete the image file.

A few consequences worth knowing:

- **Every sandbox runs one** — each with its own cluster, disk, and startup
  cost.
- **Needs `[resources].memory` of at least 4G.** Apple Container's ~1 GiB
  default is not enough for the control plane.
- **k3s is unpinned**, tracking the stable channel like `[brew]` formulae do, so
  two rebuilds can install different k3s versions.
- **The node IP is fixed** rather than the container's DHCP address, which
  changes on every recreation and would otherwise break the persisted cluster.
- `modprobe` warnings in the k3s log are expected — the kernel is monolithic and
  already has everything built in.

## VS Code (Remote Tunnels)

Each sandbox gets the VS Code CLI plus `sandbox-code`, which runs the sandbox as
a
[Remote Tunnel](https://code.visualstudio.com/docs/remote/tunnels). The tunnel
dials out to the VS Code tunnel service, so nothing listens inside the sandbox
and no port is published on your Mac.

Sign in once per sandbox, then open it from VS Code Desktop (Remote Explorer,
with the Remote Tunnels extension) or from vscode.dev:

```sh
sandbox-code login     # GitHub or Microsoft account; asks which
sandbox-code up        # start the tunnel
sandbox-code status    # tunnel name, its link once the log carries one, or why it isn't up
sandbox-code down      # stop the tunnel (the sign-in is kept)
```

After the first sign-in there is nothing to repeat: launching the sandbox starts
the tunnel for you. The credentials and the server VS Code downloads live in
`~/.vscode`, which is the bind-mounted sandbox home, so both survive container
recreation and image rebuilds. A sandbox that has never been signed in prints
the `sandbox-code login` line at launch and carries on to a shell.

To use the tunnel without keeping a terminal open, launch the sandbox
[headless](#headless).

A few consequences worth knowing:

- **The CLI is in every sandbox**, and a tunnel starts in each one you have
  signed in.
- **The tunnel is named after the sandbox**, lowercased, with anything outside
  letters, digits and hyphens replaced by a hyphen. Whatever the tunnel service
  makes of a name lands in `~/.sandbox-code.log`, which `sandbox-code status`
  tails when the tunnel isn't up.
- **An account holds ten tunnels.** Registering an eleventh deletes an unused
  one at random, and every sandbox you sign in registers one of the ten.
- **The CLI is unpinned**, tracking the stable channel like k3s and the `[brew]`
  formulae, so two rebuilds can install different versions.
- **A running tunnel is remote access to the sandbox** — see "Security scope"
  below.

## What's in the base image

Everything not in `config.toml` is structural, baked into `image/Dockerfile`:

- **Debian bookworm** (arm64) with a base toolchain: `build-essential`,
  `ca-certificates`, `curl`, `file`, `git`, `git-lfs`, `gnupg`, `locales`,
  `man-db` (reads `man sandbox`), `procps`, `python3` (parses `config.toml`),
  `sudo`, `unzip`, `zsh`.
- **Homebrew (linuxbrew)** under `/home/linuxbrew` (survives the runtime home
  mount).
- A **non-root user** (UID matched to your host for bind-mount ownership) with
  passwordless `sudo`, `zsh` + oh-my-zsh, and a `📦 <name>` prompt showing the
  sandbox name.
- **podman** wired for rootful use via a `sudo podman` shim (the `podman`
  package itself comes from `config.toml`).
- A launcher that drops you into a zellij session named after the sandbox.
- A `sandbox(7)` man page written from `config.toml` at build time, and a line
  at launch pointing at it.
- Commands run by Claude Code treated as background work — see
  [Claude in a sandbox](#claude-in-a-sandbox).

Your actual tools (`gh`, `node`, gcloud, terraform, …) come from `config.toml`,
not the base image.

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
  capability set withholds `CAP_SYS_ADMIN` and `CAP_NET_ADMIN`. k3s needs both
  (mounts, cgroup delegation, iptables, network namespaces), so every sandbox
  runs with `--cap-add ALL`, and its startup remounts `/proc/sys` read-write and
  rewrites cgroup delegation. Code in a sandbox is effectively root over that VM
  — still contained by the VM boundary, but with none of the in-guest restraint
  a capability-limited container has.

- **A tunnel is a way in from outside the machine.** A running
  tunnel means anyone signed in to that GitHub or Microsoft account can open the
  sandbox — its files and a terminal in it — from any machine, and the
  connection is relayed by a third-party service rather than staying on your
  network. The credentials that keep it running are plain files in the sandbox
  home. Stop it with `sandbox-code down`, and sign out with
  `code tunnel user logout`.

**Bottom line: a sandbox is only as secure as the host it runs on.** Don't put
secrets in a sandbox you wouldn't put on the host, and don't run untrusted code
expecting containment.

## Tests

```sh
bash test/run.sh
```

Every push also runs these on GitHub Actions, alongside ShellCheck, hadolint,
and a Docker build of `image/Dockerfile` against `config.toml.example` — the
build that catches a tap, formula, or cask breaking. Launching a real sandbox
isn't covered: Apple Container needs the Virtualization framework, which hosted
runners can't provide.
