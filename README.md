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
sandbox              # menu: launch a sandbox, or create/rename/delete
sandbox myproject    # launch "myproject" (offers to create it if new)
sandbox --help
```

Homes live at `~/Sandboxes/<name>` and are mounted as the container's entire
home, so auth, config, and shell history persist across image rebuilds and stay
separate between sandboxes. The container mounts **only** the home dir — drop
files into `~/Sandboxes/<name>` in Finder.

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
enabled = false                       # a single-node Kubernetes cluster, started on launch
disk    = "8G"                        # sparse ext4 image holding cluster state
node_ip = "10.99.0.1"                 # fixed node address; must not collide with your LAN

[vscode]
enabled = false                       # a VS Code Remote Tunnel, started on launch
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
- `[k3s]` runs a single-node Kubernetes cluster in every sandbox — see
  [Kubernetes](#kubernetes-k3s) below. Off by default.
- `[vscode]` lets you open a sandbox in VS Code — see
  [VS Code](#vs-code-remote-tunnels) below. Off by default.

## Kubernetes (k3s)

Set `enabled = true` under `[k3s]` and each sandbox gets its own single-node
cluster, started in the background as the sandbox launches. `kubectl`, `helm`,
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

`KUBECONFIG` points into `/var/lib/sandbox/kube`, not straight at `~/.kube`.
kubectl locks a kubeconfig by creating a mode-000 file next to it, and virtiofs —
the filesystem behind the bind-mounted sandbox home — refuses to create one, so
`kubectl config` and `gcloud container clusters get-credentials` fail against a
kubeconfig that lives only in the home. The lock is taken in that directory
instead, while its `config` entry symlinks to `~/.kube/config` so your kubeconfig
still lands in the home and survives the container. Run `sandbox-kubeconfig` to
rebuild it by hand.

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

- **The setting is global.** `config.toml` is shared, so enabling k3s applies to
  *every* sandbox — each with its own cluster, disk, and startup cost.
- **Needs `[resources].memory` of at least 4G.** Apple Container's ~1 GiB
  default is not enough for the control plane.
- **k3s is unpinned**, tracking the stable channel like `[brew]` formulae do, so
  two rebuilds can install different k3s versions.
- **The node IP is fixed** rather than the container's DHCP address, which
  changes on every recreation and would otherwise break the persisted cluster.
- `modprobe` warnings in the k3s log are expected — the kernel is monolithic and
  already has everything built in.

## VS Code (Remote Tunnels)

Set `enabled = true` under `[vscode]` and each sandbox gets the VS Code CLI plus
`sandbox-code`, which runs the sandbox as a
[Remote Tunnel](https://code.visualstudio.com/docs/remote/tunnels). The tunnel
dials out to the VS Code tunnel service, so nothing listens inside the sandbox
and no port is published on your Mac.

Sign in once per sandbox, then open it from VS Code Desktop (Remote Explorer,
with the Remote Tunnels extension) or from vscode.dev:

```sh
sandbox-code login     # GitHub or Microsoft account; asks which
sandbox-code up        # start the tunnel
sandbox-code status    # tunnel name and the link to open, or why it isn't up
sandbox-code down      # stop the tunnel (the sign-in is kept)
```

After the first sign-in there is nothing to repeat: launching the sandbox starts
the tunnel for you. The credentials and the server VS Code downloads live in
`~/.vscode`, which is the bind-mounted sandbox home, so both survive container
recreation and image rebuilds. A sandbox that has never been signed in prints
the `sandbox-code login` line at launch and carries on to a shell.

A few consequences worth knowing:

- **The setting is global**, like `[k3s]` — enabling it puts the CLI in every
  sandbox and starts a tunnel in each one you have signed in.
- **The tunnel is named after the sandbox**, lowercased, with anything outside
  letters, digits and hyphens replaced by a hyphen. Tunnel names belong to the
  account rather than the machine, so the same sandbox name in two places is a
  conflict. Whatever the tunnel service makes of a name lands in
  `~/.sandbox-code.log`, which `sandbox-code status` tails when the tunnel isn't
  up.
- **The CLI is unpinned**, tracking the stable channel like k3s and the `[brew]`
  formulae, so two rebuilds can install different versions.
- **A running tunnel is remote access to the sandbox** — see "Security scope"
  below.

## What's in the base image

Everything not in `config.toml` is structural, baked into `image/Dockerfile`:

- **Debian bookworm** (arm64) with a base toolchain: `build-essential`,
  `ca-certificates`, `curl`, `file`, `git`, `git-lfs`, `gnupg`, `locales`,
  `procps`, `python3` (parses `config.toml`), `sudo`, `unzip`, `zsh`.
- **Homebrew (linuxbrew)** under `/home/linuxbrew` (survives the runtime home
  mount).
- A **non-root user** (UID matched to your host for bind-mount ownership) with
  passwordless `sudo`, `zsh` + oh-my-zsh, and a `📦 <name>` prompt showing the
  sandbox name.
- **podman** wired for rootful use via a `sudo podman` shim (the `podman`
  package itself comes from `config.toml`).
- A launcher that drops you into a zellij session named after the sandbox.

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
- **`[k3s].enabled` drops the capability limits.** By default a sandbox gets
  Apple Container's standard capability set, which withholds `CAP_SYS_ADMIN` and
  `CAP_NET_ADMIN`. k3s needs both (mounts, cgroup delegation, iptables, network
  namespaces), so an enabled sandbox runs with `--cap-add ALL` and its startup
  remounts `/proc/sys` read-write and rewrites cgroup delegation. Since the
  setting is global, this applies to *every* sandbox. Code in a k3s sandbox is
  effectively root over that VM — still contained by the VM boundary, but with
  none of the in-guest restraint a default sandbox has.

- **`[vscode].enabled` adds a way in from outside the machine.** A running
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
