# Changelog

Calendar-versioned (`YY.MM.MICRO`), most recent first.

## Unreleased

### Added
- `[k3s]` section in `config.toml` runs a single-node Kubernetes cluster in each
  sandbox, started in the background at launch. Cluster state persists across
  container recreation and image rebuilds on a sparse ext4 image in the sandbox
  home (`disk`, default `8G`), loop-mounted at `/var/lib/rancher`. Manage it with
  `sandbox-k3s up|down|status`. Off by default.
- `~/.kube/config` is linked to the cluster's kubeconfig automatically.

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
