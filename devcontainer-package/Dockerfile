FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Pin code-server version for reproducibility and supply-chain safety.
# Check https://github.com/coder/code-server/releases for newer versions.
ARG CODE_SERVER_VERSION=4.115.0

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        git \
        jq \
        openssh-client \
        sudo \
        unzip \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install code-server from the versioned .deb package rather than the install.sh
# script, so the version is explicit and the download URL is auditable.
RUN ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server_${CODE_SERVER_VERSION}_${ARCH}.deb" \
        -o /tmp/code-server.deb \
    && dpkg -i /tmp/code-server.deb \
    && rm /tmp/code-server.deb

# Install the VS Code CLI for Remote Tunnels support.
# Maps dpkg architecture names to the VS Code CLI distribution names.
RUN ARCH="$(dpkg --print-architecture)" \
    && case "${ARCH}" in \
         amd64) VSCODE_ARCH="x64" ;; \
         arm64) VSCODE_ARCH="arm64" ;; \
         *) echo "Unsupported arch for VS Code CLI: ${ARCH}" && exit 1 ;; \
       esac \
    && curl -fsSL "https://update.code.visualstudio.com/latest/cli-linux-${VSCODE_ARCH}/stable" \
        -o /tmp/vscode-cli.tar.gz \
    && tar -xf /tmp/vscode-cli.tar.gz -C /usr/local/bin \
    && rm /tmp/vscode-cli.tar.gz \
    && chmod +x /usr/local/bin/code

RUN if ! id -u "$USERNAME" >/dev/null 2>&1; then \
      groupadd --gid "$USER_GID" "$USERNAME" \
      && useradd --uid "$USER_UID" --gid "$USER_GID" -m "$USERNAME"; \
    fi \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME" \
    && chmod 0440 "/etc/sudoers.d/$USERNAME"

COPY scripts/start-vscode-server.sh /usr/local/bin/start-vscode-server.sh
COPY scripts/healthcheck.sh /usr/local/bin/healthcheck.sh

RUN chmod +x /usr/local/bin/start-vscode-server.sh /usr/local/bin/healthcheck.sh

USER $USERNAME
WORKDIR /workspaces

EXPOSE 8443
HEALTHCHECK --interval=30s --timeout=5s --retries=5 CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/usr/local/bin/start-vscode-server.sh"]
