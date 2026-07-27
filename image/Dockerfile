FROM debian:bookworm

ARG USERNAME=dev
ARG USER_UID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# 1. Base toolchain (python3 is needed to parse packages.toml).
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl file git git-lfs gnupg \
        locales procps python3 sudo unzip zsh \
    && git lfs install --system \
    && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && locale-gen \
    && rm -rf /var/lib/apt/lists/*

# 2. packages.toml -> apt packages (root).
COPY packages.toml /tmp/packages.toml
RUN pkgs="$(python3 -c 'import tomllib;print(" ".join(tomllib.load(open("/tmp/packages.toml","rb")).get("apt",{}).get("packages",[])))')" \
    && if [ -n "$pkgs" ]; then apt-get update \
       && apt-get install -y --no-install-recommends $pkgs \
       && rm -rf /var/lib/apt/lists/*; fi

# 3. podman: rootful shim + registry config (podman binary came from step 2).
RUN mkdir -p /etc/containers/registries.conf.d \
    && printf 'unqualified-search-registries = ["docker.io"]\n' \
        > /etc/containers/registries.conf.d/00-unqualified-docker.conf \
    && printf '#!/bin/sh\nexec sudo /usr/bin/podman "$@"\n' > /usr/local/bin/podman \
    && chmod +x /usr/local/bin/podman

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

# 6. packages.toml -> brew taps (declaring a tap trusts it, so its casks install).
RUN taps="$(python3 -c 'import tomllib;print(" ".join(tomllib.load(open("/tmp/packages.toml","rb")).get("brew",{}).get("taps",[])))')" \
    && for t in $taps; do brew tap "$t" && brew trust "$t"; done

# 7. packages.toml -> brew formulae.
RUN formulae="$(python3 -c 'import tomllib;print(" ".join(tomllib.load(open("/tmp/packages.toml","rb")).get("brew",{}).get("formulae",[])))')" \
    && if [ -n "$formulae" ]; then brew install $formulae; fi

# 8. packages.toml -> brew casks. Cask linking can emit a benign trailing
#    "Broken pipe" (non-zero exit) in a non-TTY build even though the cask
#    installed; tolerate that when the cask actually linked / is listed.
RUN casks="$(python3 -c 'import tomllib;print(" ".join(tomllib.load(open("/tmp/packages.toml","rb")).get("brew",{}).get("casks",[])))')" \
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

# 9. packages.toml -> post_install commands (fail the build on any error).
RUN python3 -c 'import tomllib;[print(c) for c in tomllib.load(open("/tmp/packages.toml","rb")).get("post_install",{}).get("commands",[])]' > /tmp/post_install.sh \
    && set -e && while IFS= read -r cmd; do [ -n "$cmd" ] && bash -lc "$cmd"; done < /tmp/post_install.sh

# 10. Shell seed into /etc/skel (root); entrypoint copies it into a fresh home.
USER root
RUN HOME=/etc/skel RUNZSH=no CHSH=no \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
    && printf 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"\n' | tee -a /etc/skel/.zshrc /etc/skel/.bashrc \
    && printf '\n[ -r /etc/sandbox-prompt.zsh ] && source /etc/sandbox-prompt.zsh\n' >> /etc/skel/.zshrc \
    && chown -R $USERNAME:$USERNAME /etc/skel

# 11. Entry points + sandbox helpers.
COPY image/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY image/setup.sh /usr/local/bin/sandbox-setup
COPY image/sandbox-zellij /usr/local/bin/sandbox-zellij
COPY image/sandbox-prompt.zsh /etc/sandbox-prompt.zsh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/sandbox-setup /usr/local/bin/sandbox-zellij

USER $USERNAME
WORKDIR $HOME
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
# Attach to (or create) a zellij session named after the sandbox.
CMD ["/usr/local/bin/sandbox-zellij"]
