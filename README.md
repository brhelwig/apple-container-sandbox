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

**Bottom line: a sandbox is only as secure as the host it runs on.** Don't put
secrets in a sandbox you wouldn't put on the host, and don't run untrusted code
expecting containment.

## Tests

```sh
bash test/run.sh
```
