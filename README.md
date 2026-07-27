# apple-container-sandbox

Ad-hoc Linux sandboxes on [Apple Container](https://github.com/apple/container).
Each sandbox is a persistent home dir, container, and zellij session keyed by a
single `<name>`, all sharing one image built from `image/Dockerfile`.

## Install

```sh
git clone https://github.com/brhelwig/apple-container-sandbox.git ~/.sandbox
~/.sandbox/install.sh   # creates ~/Sandboxes, prints the PATH line to add
```

The menu needs `gum`; it offers to `brew install gum` the first time you open it
without one. `sandbox <name>` skips the menu and doesn't need `gum` at all.

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

## Packages

Edit `packages.toml` (apt / brew taps / formulae / casks / post_install). The
image rebuilds automatically when `packages.toml` or `image/` changes.

## Tests

```sh
bash test/run.sh
```
