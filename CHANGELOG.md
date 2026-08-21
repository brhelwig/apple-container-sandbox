# Changelog

Calendar-versioned (`YY.MM.MICRO`), most recent first.

## Unreleased

### Added
- Every sandbox serves SSH. `openssh-server` joins the base toolchain, and
  `sandbox-ssh up|down|status` runs it; the launch starts it, next to the VS
  Code tunnel rather than in place of it, so both ways in work at once. The
  launcher publishes the sandbox's port 22 on a port of the Mac that belongs to
  that sandbox alone, handed out from `[ssh].port` upward and recorded in
  `~/Sandboxes/<name>/.sandbox-ssh-port`, so several sandboxes serve SSH at the
  same time and each keeps its port across launches. `sandbox --ssh-port <port>
  <name>` names the port instead.
- That port is open on every address of the Mac, so a tailnet or a LAN reaches
  a sandbox over SSH, not the Mac alone. `[ssh].address` narrows it to one
  address, and `[ssh].enabled = false` turns the server off everywhere.
- A public key is the only way into a sandbox over SSH: the account has no
  password, and the server refuses password logins and root logins. The launcher
  authorizes the Mac's own public keys the first time it creates a home, and
  never touches `~/.ssh/authorized_keys` again, so a key added by hand stays.
  `man sandbox` walks through authorizing a key and connecting.
- The SSH host key lives in `~/.sandbox-ssh`, in the sandbox home, so the
  fingerprint survives container recreation and image rebuilds. The image ships
  without a host key, so no two sandboxes share one.
- A session opened over SSH gets the same PATH as a shell in the sandbox, from
  `/etc/environment`, so `ssh <sandbox> kubectl get pods` finds the tools that
  Homebrew installed. `sftp` is served too, which is what `scp`, `rsync` and
  VS Code's Remote-SSH need.
- `sandbox -d <name>` launches a sandbox headless: the container runs detached
  with no zellij session, so the cluster and the VS Code tunnel keep running
  after the terminal closes. The launcher waits for the tunnel, prints where it
  stands, and returns. `sandbox <name>` attaches a shell to a headless sandbox
  at any time, and leaving that shell no longer stops it. In place of a zellij
  session the container runs `sandbox-idle`, which holds it open and exits on
  the stop signal so `container stop <name>` returns at once.
- `sandbox` rejects an unrecognized option instead of treating it as a sandbox
  name, so a mistyped flag no longer creates a sandbox called `--headles`.
- Every sandbox can run a single-node Kubernetes cluster. k3s is installed in
  every sandbox but stays stopped until you run `sandbox-k3s up`, which starts
  it in the background; `sandbox-k3s down|status` stop it and report on it. Set
  `[k3s].autostart = true` to start it at launch instead — it is `false` by
  default, so a sandbox you use for anything else pays neither the memory nor
  the startup cost. Cluster state persists across container recreation and image
  rebuilds on a sparse ext4 image in the sandbox home (`[k3s].disk`, default
  `8G`), loop-mounted at `/var/lib/rancher`. `man sandbox` reports which way the
  image was built.
- Starting the cluster publishes it to the sandbox kubeconfig automatically, as
  a `k3s` context. An existing kubeconfig is never modified — its own contexts,
  and any added later, are left alone.
- `KUBECONFIG` points at a shim directory on the container filesystem whose
  `config` entry symlinks back to `~/.kube/config`, so `kubectl config` and
  `gcloud container clusters get-credentials` can take the lock file the sandbox
  home refuses. Writes still land in the home and persist. Set up by
  `sandbox-kubeconfig`.

- Every sandbox carries the VS Code CLI and runs it as a Remote Tunnel, so a
  sandbox can be opened in VS Code Desktop or vscode.dev from anywhere. The
  tunnel dials out, so nothing listens in the sandbox and no port is published
  on the host. Manage it with `sandbox-code login|up|down|status`; after one
  sign-in the tunnel starts at launch, and the credentials persist in the
  sandbox home. See "Security scope" in the README for what a running tunnel
  exposes.

- `man sandbox` inside a sandbox describes the sandbox and lists the tools
  installed in it. The page is written during the build from the same
  `config.toml` that installs them, so it holds for the image it ships in.
  Every interactive shell of a fresh launch prints a line pointing at it, once.
  `man-db` joins the base toolchain, since `debian:bookworm` carries no `man`.

- Commands run by Claude Code are niced to 10, put in the idle I/O class, and
  made the first candidate for the OOM killer, so a build or test Claude starts
  cannot starve or kill the session. The shell Claude spawns each command in
  applies all three to itself and they are inherited; shells you type in,
  claude, and zellij are untouched. `sandbox-background <command>` does the
  same for anything else.
- The k3s cluster runs as background work too, so k3s and what it
  runs share the CPU and I/O standing. Its OOM score is set rather than
  inherited, since kubelet assigns its own; each pod container keeps the score
  kubelet computes from its quality of service class.

### Changed
- Deleting a sandbox from the menu removes the container only. The home dir and
  everything in it is kept, so the sandbox stays in the menu and relaunching
  recreates the container. It used to delete the home dir as well, which failed
  partway on files the container had written as root.
- Every sandbox runs with `--cap-add ALL`, because k3s requires
  `CAP_SYS_ADMIN` and `CAP_NET_ADMIN`, which the default capability set omits —
  see "Security scope" in the README.
- The node uses a fixed `node_ip` (default `10.99.0.1`) on a private bridge
  instead of the container's DHCP address, which changes on every recreation and
  would otherwise break the persisted cluster.
- One TOML reader serves the host CLI and both in-image helpers, so a setting is
  parsed the same way wherever it is read.
- Every sandbox installs the same base set of tools, whatever a given Mac's
  `config.toml` holds. The Debian packages and the Homebrew taps, formulae and
  casks that `config.toml.example` used to ship are now the `APT_PACKAGES`,
  `BREW_TAPS`, `BREW_FORMULAE` and `BREW_CASKS` build arguments in
  `image/Dockerfile`, and `cloudflared` is among them. `config.toml` still adds
  to each of those lists, and its `[post_install]` commands still run; what it
  can no longer do is leave a sandbox without the base set. An existing
  `config.toml` keeps working as it is — a package it names that is also in the
  base set installs once. `man sandbox` lists the two merged.

### Fixed
- `sandbox <name>` no longer destroys a running sandbox. It rebuilt the image
  first, then compared the result with the image the sandbox was started from.
  Any edit under `image/` or to `config.toml` since launch made the two differ,
  and it stopped and deleted the container without asking, which killed
  everything running inside a headless sandbox. It now looks for a running
  container before it builds anything, and attaches to one whatever image it
  started from. Where the image changed since, it says so and asks before it
  restarts the sandbox; decline and it attaches instead. Attaching no longer
  rebuilds the image either, because nothing is launched from it.
- A sandbox no longer fills up with zombie processes. Whatever the container
  ran held PID 1 — the zellij session, or `sandbox-idle` in a headless sandbox
  — and neither one waits on the processes the kernel reparents to it. Every
  background process that outlived its parent, such as the cluster, the VS Code
  tunnel and anything started with `sandbox-background`, left a dead entry
  behind on exit. Nothing cleared the entries, so a long-running sandbox
  consumed process slots until it was restarted. The launcher now passes
  `--init`, so the container runs an init that reaps them and forwards the stop
  signal. Relaunch a sandbox to pick this up.
- `sandbox-k3s --help` and `sandbox-background --help` printed their last
  sentence cut off mid-word. Both now hold their help text as text rather than
  as a range of comment lines.

### Removed
- `sandbox-kubeconfig` no longer replaces a `~/.kube/config` that symlinks to the
  cluster's own file. Only unreleased versions ever created that symlink.

## 26.7.0 — 2026-07-28

### Changed
- Renamed the config manifest from `packages.toml` to `config.toml`
  (`config.toml.example` is the tracked template). Migrate a local copy with
  `mv packages.toml config.toml`.

### Added
- `[resources]` section in `config.toml` sets each sandbox's `memory` and
  `cpus`, passed through to `container run`. The template ships `4G` / `4`;
  omit a value to fall back to Apple Container's default (~1 GiB memory).
