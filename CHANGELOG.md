# Changelog

Calendar-versioned (`YY.MM.MICRO`), most recent first.

## Unreleased

### Added
- Every sandbox runs a single-node Kubernetes cluster, started in the background
  at launch. Cluster state persists across container recreation and image
  rebuilds on a sparse ext4 image in the sandbox home (`[k3s].disk`, default
  `8G`), loop-mounted at `/var/lib/rancher`. Manage it with
  `sandbox-k3s up|down|status`.
- The cluster is published to the sandbox kubeconfig automatically, as a `k3s`
  context. An existing kubeconfig is never modified — its own contexts, and any
  added later, are left alone.
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
- The k3s cluster starts as background work too, so k3s and what it
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

### Fixed
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
