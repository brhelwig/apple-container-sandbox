# Changelog

Calendar-versioned (`YY.MM.MICRO`), most recent first.

## Unreleased

### Added
- `[k3s]` section in `config.toml` runs a single-node Kubernetes cluster in each
  sandbox, started in the background at launch. Cluster state persists across
  container recreation and image rebuilds on a sparse ext4 image in the sandbox
  home (`disk`, default `8G`), loop-mounted at `/var/lib/rancher`. Manage it with
  `sandbox-k3s up|down|status`. Off by default.
- The cluster is published to the sandbox kubeconfig automatically, as a `k3s`
  context. An existing kubeconfig is never modified — its own contexts, and any
  added later, are left alone.
- `KUBECONFIG` points at a shim directory on the container filesystem whose
  `config` entry symlinks back to `~/.kube/config`. kubectl locks a kubeconfig
  by creating a mode-000 file next to it, which virtiofs — the filesystem behind
  the bind-mounted sandbox home — refuses to create, so a kubeconfig kept only in
  the home could never be written by `kubectl config` or by
  `gcloud container clusters get-credentials`. Writes still land in the home and
  persist. Set up by `sandbox-kubeconfig`, whether or not k3s is enabled.

- `[vscode]` section in `config.toml` puts the VS Code CLI in each sandbox and
  runs it as a Remote Tunnel, so a sandbox can be opened in VS Code Desktop or
  vscode.dev from anywhere. The tunnel dials out, so nothing listens in the
  sandbox and no port is published on the host. Manage it with
  `sandbox-code login|up|down|status`; after one sign-in the tunnel starts at
  launch, and the credentials persist in the sandbox home. Off by default — see
  "Security scope" in the README for what a running tunnel exposes.

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
- A configured k3s cluster starts as background work too, so k3s and what it
  runs share the CPU and I/O standing. OOM scores there are kubelet's, not
  inherited: it gives itself `-999`, which `sandbox-k3s` overrules with 1000
  once applied, while each container keeps the score kubelet computes from its
  quality of service class.

### Changed
- A sandbox with `[k3s].enabled` runs with `--cap-add ALL`, because k3s requires
  `CAP_SYS_ADMIN` and `CAP_NET_ADMIN`, which the default capability set omits.
  The setting is global, so this affects every sandbox — see "Security scope" in
  the README.
- The node uses a fixed `node_ip` (default `10.99.0.1`) on a private bridge
  instead of the container's DHCP address, which changes on every recreation and
  would otherwise break the persisted cluster.

## 26.7.0 — 2026-07-28

### Changed
- Renamed the config manifest from `packages.toml` to `config.toml`
  (`config.toml.example` is the tracked template). Migrate a local copy with
  `mv packages.toml config.toml`.

### Added
- `[resources]` section in `config.toml` sets each sandbox's `memory` and
  `cpus`, passed through to `container run`. The template ships `4G` / `4`;
  omit a value to fall back to Apple Container's default (~1 GiB memory).
