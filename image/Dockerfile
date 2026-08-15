FROM debian:bookworm

ARG USERNAME=dev
ARG USER_UID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# 1. Base toolchain (python3 is needed to parse config.toml).
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl file git git-lfs gnupg \
        locales procps python3 sudo unzip zsh \
    && git lfs install --system \
    && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && locale-gen \
    && rm -rf /var/lib/apt/lists/*

# 2. config.toml -> apt packages (root).
COPY config.toml /tmp/config.toml
RUN pkgs="$(python3 -c 'import tomllib;print(" ".join(tomllib.load(open("/tmp/config.toml","rb")).get("apt",{}).get("packages",[])))')" \
    && if [ -n "$pkgs" ]; then apt-get update \
       && apt-get install -y --no-install-recommends $pkgs \
       && rm -rf /var/lib/apt/lists/*; fi

# 3. podman: rootful shim + registry config (podman binary came from step 2).
RUN mkdir -p /etc/containers/registries.conf.d \
    && printf 'unqualified-search-registries = ["docker.io"]\n' \
        > /etc/containers/registries.conf.d/00-unqualified-docker.conf \
    && printf '#!/bin/sh\nexec sudo /usr/bin/podman "$@"\n' > /usr/local/bin/podman \
    && chmod +x /usr/local/bin/podman

# 3b. config.toml -> k3s. Runtime deps plus the latest stable k3s binary, which
#     is deliberately unpinned to match how [brew] formulae track latest. The
#     kernel needs nothing: veth, bridge/br_netfilter, vxlan, netfilter/NAT and
#     overlayfs are all built in (CONFIG_MODULES=n, so k3s's modprobe warnings
#     at startup are expected and harmless).
RUN if python3 -c 'import tomllib,sys; sys.exit(0 if tomllib.load(open("/tmp/config.toml","rb")).get("k3s",{}).get("enabled") else 1)'; then \
        apt-get update \
        && apt-get install -y --no-install-recommends \
               conntrack ethtool iproute2 socat \
        && rm -rf /var/lib/apt/lists/* \
        && case "$(dpkg --print-architecture)" in \
             arm64) asset=k3s-arm64 ;; \
             amd64) asset=k3s ;; \
             *) echo "unsupported arch for k3s: $(dpkg --print-architecture)" >&2; exit 1 ;; \
           esac \
        && tag="$(curl -fsSL -o /dev/null -w '%{url_effective}' \
                  https://update.k3s.io/v1-release/channels/stable | sed 's|.*/||')" \
        && echo "installing k3s $tag ($asset)" \
        && curl -fsSL -o /usr/local/bin/k3s \
             "https://github.com/k3s-io/k3s/releases/download/$(printf '%s' "$tag" | sed 's/+/%2B/')/$asset" \
        && chmod +x /usr/local/bin/k3s \
        && /usr/local/bin/k3s --version; \
    fi

# 3c. config.toml -> the VS Code CLI, which `sandbox-code` runs as a tunnel. The
#     download is the alpine asset because there is no cli-linux-* build; it is
#     statically linked, so it runs on Debian. Unpinned, like the k3s binary.
#     The download endpoint answers with a 504 often enough to have failed a
#     build already, so the fetch retries rather than taking the first answer.
RUN if python3 -c 'import tomllib,sys; sys.exit(0 if tomllib.load(open("/tmp/config.toml","rb")).get("vscode",{}).get("enabled") else 1)'; then \
        case "$(dpkg --print-architecture)" in \
          arm64) asset=cli-alpine-arm64 ;; \
          amd64) asset=cli-alpine-x64 ;; \
          *) echo "unsupported arch for the VS Code CLI: $(dpkg --print-architecture)" >&2; exit 1 ;; \
        esac \
        && curl -fsSL --retry 5 --retry-delay 5 -o /tmp/vscode-cli.tar.gz \
             "https://code.visualstudio.com/sha/download?build=stable&os=$asset" \
        && tar -xzf /tmp/vscode-cli.tar.gz -C /usr/local/bin code \
        && rm -f /tmp/vscode-cli.tar.gz \
        && /usr/local/bin/code --version; \
    fi

# 4. Non-root user (Homebrew refuses root; UID matched for bind-mount ownership).
RUN useradd --uid $USER_UID --create-home --shell /usr/bin/zsh $USERNAME \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME \
    && chown -R $USERNAME:$USERNAME "/home/$USERNAME"

USER $USERNAME
ENV HOME=/home/$USERNAME SHELL=/usr/bin/zsh
WORKDIR $HOME

# 5. Homebrew under /home/linuxbrew (survives the runtime $HOME bind mount).
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"

# 6. config.toml -> brew taps. Trust each tap so its casks can install; trust
#    is a no-op/irrelevant for formula-only taps, so a failure there is ignored
#    (untrusted casks still fail at install time, so this doesn't weaken safety).
RUN taps="$(python3 -c 'import tomllib;print(" ".join(tomllib.load(open("/tmp/config.toml","rb")).get("brew",{}).get("taps",[])))')" \
    && for t in $taps; do brew tap "$t" && { brew trust "$t" || true; }; done

# 7. config.toml -> brew formulae.
RUN formulae="$(python3 -c 'import tomllib;print(" ".join(tomllib.load(open("/tmp/config.toml","rb")).get("brew",{}).get("formulae",[])))')" \
    && if [ -n "$formulae" ]; then brew install $formulae; fi

# 8. config.toml -> brew casks. Cask linking can emit a benign trailing
#    "Broken pipe" (non-zero exit) in a non-TTY build even though the cask
#    installed; tolerate that when the cask actually linked / is listed.
RUN casks="$(python3 -c 'import tomllib;print(" ".join(tomllib.load(open("/tmp/config.toml","rb")).get("brew",{}).get("casks",[])))')" \
    && for c in $casks; do \
         out="$(brew install --cask "$c" 2>&1)" && rc=0 || rc=$?; \
         printf '%s\n' "$out"; \
         [ "$rc" -eq 0 ] && continue; \
         if brew list --cask "$c" >/dev/null 2>&1 || printf '%s' "$out" | grep -q 'Linking Binary'; then \
           echo "note: cask $c installed (tolerating exit $rc)"; \
         else \
           echo "ERROR: cask $c failed to install" >&2; exit 1; \
         fi; \
       done

# 9. config.toml -> post_install commands (fail the build on any error).
RUN python3 -c 'import tomllib;[print(c) for c in tomllib.load(open("/tmp/config.toml","rb")).get("post_install",{}).get("commands",[])]' > /tmp/post_install.sh \
    && set -e && while IFS= read -r cmd; do [ -n "$cmd" ] && bash -lc "$cmd"; done < /tmp/post_install.sh

# 10. Shell seed into /etc/skel (root); entrypoint copies it into a fresh home.
USER root
RUN HOME=/etc/skel RUNZSH=no CHSH=no \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
    && printf 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"\n' | tee -a /etc/skel/.zshrc /etc/skel/.bashrc \
    && printf '\n[ -r /etc/sandbox-prompt.zsh ] && source /etc/sandbox-prompt.zsh\n' >> /etc/skel/.zshrc \
    && chown -R $USERNAME:$USERNAME /etc/skel

# 11. Entry points + sandbox helpers. config.toml lands at a stable path so
#     runtime helpers (sandbox-k3s, sandbox-code) can read their settings from it.
COPY image/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY image/setup.sh /usr/local/bin/sandbox-setup
COPY image/sandbox-zellij /usr/local/bin/sandbox-zellij
COPY image/sandbox-k3s /usr/local/bin/sandbox-k3s
COPY image/sandbox-code /usr/local/bin/sandbox-code
COPY image/sandbox-kubeconfig /usr/local/bin/sandbox-kubeconfig
COPY image/sandbox-prompt.zsh /etc/sandbox-prompt.zsh
COPY config.toml /etc/sandbox-config.toml
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/sandbox-setup \
        /usr/local/bin/sandbox-zellij /usr/local/bin/sandbox-k3s \
        /usr/local/bin/sandbox-code /usr/local/bin/sandbox-kubeconfig

# 11b. The kubeconfig shim dir. It has to sit on the container filesystem
#      rather than the bind-mounted home: kubectl locks a kubeconfig with a
#      mode-000 file alongside it, which virtiofs won't create. Its `config`
#      entry is a symlink, so the kubeconfig still lands in the home and
#      persists (see image/sandbox-kubeconfig).
RUN install -d -o $USERNAME -g $USERNAME /var/lib/sandbox /var/lib/sandbox/kube
ENV KUBECONFIG=/var/lib/sandbox/kube/config:/var/lib/sandbox/kube/k3s.yaml

USER $USERNAME
WORKDIR $HOME
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
# Attach to (or create) a zellij session named after the sandbox.
CMD ["/usr/local/bin/sandbox-zellij"]
