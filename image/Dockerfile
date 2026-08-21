FROM debian:bookworm

ARG USERNAME=dev
ARG USER_UID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

ARG BASE_PACKAGES="build-essential ca-certificates curl file git git-lfs gnupg locales man-db openssh-server procps python3 sudo unzip zsh"
RUN apt-get update && apt-get install -y --no-install-recommends $BASE_PACKAGES \
    && git lfs install --system \
    && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && locale-gen \
    && rm -f /etc/ssh/ssh_host_* \
    && rm -rf /var/lib/apt/lists/*

ARG APT_PACKAGES="podman"
RUN apt-get update && apt-get install -y --no-install-recommends $APT_PACKAGES \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/containers/registries.conf.d \
    && printf 'unqualified-search-registries = ["docker.io"]\n' \
        > /etc/containers/registries.conf.d/00-unqualified-docker.conf \
    && printf '#!/bin/sh\nexec sudo /usr/bin/podman "$@"\n' > /usr/local/bin/podman \
    && chmod +x /usr/local/bin/podman

RUN apt-get update \
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
    && /usr/local/bin/k3s --version

RUN case "$(dpkg --print-architecture)" in \
      arm64) asset=cli-alpine-arm64 ;; \
      amd64) asset=cli-alpine-x64 ;; \
      *) echo "unsupported arch for the VS Code CLI: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac \
    && curl -fsSL --retry 5 --retry-delay 5 -o /tmp/vscode-cli.tar.gz \
         "https://code.visualstudio.com/sha/download?build=stable&os=$asset" \
    && tar -xzf /tmp/vscode-cli.tar.gz -C /usr/local/bin code \
    && rm -f /tmp/vscode-cli.tar.gz \
    && /usr/local/bin/code --version

RUN useradd --uid $USER_UID --create-home --shell /usr/bin/zsh $USERNAME \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME \
    && chown -R $USERNAME:$USERNAME "/home/$USERNAME"

USER $USERNAME
ENV HOME=/home/$USERNAME SHELL=/usr/bin/zsh
WORKDIR $HOME

RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"

ARG BREW_TAPS="terraform-linters/tap hashicorp/tap"
RUN for t in $BREW_TAPS; do brew tap "$t" && { brew trust "$t" || true; }; done

ARG BREW_FORMULAE="ansible awscli azure-cli cloudflare-wrangler cloudflared fzf gh go gum hadolint hashicorp/tap/terraform helm helmfile htop jq k9s kubectl kubectx kustomize lazygit lazysql mosh nano node pre-commit sops sqlite uv watch yq zellij zstd"
RUN brew install $BREW_FORMULAE

ARG BREW_CASKS="claude-code@latest gcloud-cli tflint"
RUN for c in $BREW_CASKS; do \
      out="$(brew install --cask "$c" 2>&1)" && rc=0 || rc=$?; \
      printf '%s\n' "$out"; \
      [ "$rc" -eq 0 ] && continue; \
      if brew list --cask "$c" >/dev/null 2>&1 || printf '%s' "$out" | grep -q 'Linking Binary'; then \
        echo "note: cask $c installed (tolerating exit $rc)"; \
      else \
        echo "ERROR: cask $c failed to install" >&2; exit 1; \
      fi; \
    done

USER root
RUN HOME=/etc/skel RUNZSH=no CHSH=no \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
    && printf 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"\n' | tee -a /etc/skel/.zshrc /etc/skel/.bashrc \
    && printf '\n[ -r /etc/sandbox-prompt.zsh ] && source /etc/sandbox-prompt.zsh\n' >> /etc/skel/.zshrc \
    && chown -R $USERNAME:$USERNAME /etc/skel

COPY config.toml /tmp/config.toml
RUN pkgs="$(python3 -c 'import tomllib;print(" ".join(tomllib.load(open("/tmp/config.toml","rb")).get("apt",{}).get("packages",[])))')" \
    && if [ -n "$pkgs" ]; then apt-get update \
       && apt-get install -y --no-install-recommends $pkgs \
       && rm -rf /var/lib/apt/lists/*; fi

USER $USERNAME
RUN taps="$(python3 -c 'import tomllib;print(" ".join(tomllib.load(open("/tmp/config.toml","rb")).get("brew",{}).get("taps",[])))')" \
    && for t in $taps; do brew tap "$t" && { brew trust "$t" || true; }; done

RUN formulae="$(python3 -c 'import tomllib;print(" ".join(tomllib.load(open("/tmp/config.toml","rb")).get("brew",{}).get("formulae",[])))')" \
    && if [ -n "$formulae" ]; then brew install $formulae; fi

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

RUN python3 -c 'import tomllib;[print(c) for c in tomllib.load(open("/tmp/config.toml","rb")).get("post_install",{}).get("commands",[])]' > /tmp/post_install.sh \
    && set -e && while IFS= read -r cmd; do [ -n "$cmd" ] && bash -lc "$cmd"; done < /tmp/post_install.sh

USER root
COPY image/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY image/setup.sh /usr/local/bin/sandbox-setup
COPY image/sandbox-zellij /usr/local/bin/sandbox-zellij
COPY image/sandbox-idle /usr/local/bin/sandbox-idle
COPY image/sandbox-k3s /usr/local/bin/sandbox-k3s
COPY image/sandbox-code /usr/local/bin/sandbox-code
COPY image/sandbox-ssh /usr/local/bin/sandbox-ssh
COPY image/sandbox-sshd.conf /etc/ssh/sandbox-sshd.conf
COPY image/sandbox-welcome /usr/local/bin/sandbox-welcome
COPY image/sandbox-background /usr/local/bin/sandbox-background
COPY image/sandbox-kubeconfig /usr/local/bin/sandbox-kubeconfig
COPY image/sandbox-prompt.zsh /etc/sandbox-prompt.zsh
COPY image/sandbox-nice.sh /etc/sandbox-nice.sh
COPY image/sandbox-config.sh /etc/sandbox-config.sh
COPY config.toml /etc/sandbox-config.toml
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/sandbox-setup \
        /usr/local/bin/sandbox-zellij /usr/local/bin/sandbox-idle \
        /usr/local/bin/sandbox-k3s /usr/local/bin/sandbox-code \
        /usr/local/bin/sandbox-welcome /usr/local/bin/sandbox-background \
        /usr/local/bin/sandbox-kubeconfig /usr/local/bin/sandbox-ssh

RUN printf 'PATH="%s"\n' "$PATH" > /etc/environment

COPY image/sandbox-manpage /tmp/sandbox-manpage
RUN install -d /usr/local/share/man/man7 \
    && python3 /tmp/sandbox-manpage /etc/sandbox-config.toml \
         "$BASE_PACKAGES" "$APT_PACKAGES" "$BREW_TAPS" "$BREW_FORMULAE" "$BREW_CASKS" \
         > /usr/local/share/man/man7/sandbox.7 \
    && rm -f /tmp/sandbox-manpage \
    && mandb -q \
    && man 7 sandbox > /dev/null \
    && printf '\n[ -x /usr/local/bin/sandbox-welcome ] && /usr/local/bin/sandbox-welcome\n' \
         >> /etc/zsh/zshrc

RUN printf '\n[ -r /etc/sandbox-nice.sh ] && . /etc/sandbox-nice.sh\n' >> /etc/zsh/zshenv

RUN install -d -o $USERNAME -g $USERNAME /var/lib/sandbox /var/lib/sandbox/kube
ENV KUBECONFIG=/var/lib/sandbox/kube/config:/var/lib/sandbox/kube/k3s.yaml

USER $USERNAME
WORKDIR $HOME
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/local/bin/sandbox-zellij"]
