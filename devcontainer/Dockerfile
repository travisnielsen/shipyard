FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID
ARG POWERSHELL_VERSION=7.5.2

# Pin code-server version for reproducibility and supply-chain safety.
# Check https://github.com/coder/code-server/releases for newer versions.
ARG CODE_SERVER_VERSION=4.115.0

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        apt-transport-https \
        build-essential \
        curl \
        gpg \
        git \
        jq \
        lsb-release \
        pipx \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
        openssh-client \
        software-properties-common \
        sudo \
        unzip \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js (current LTS) and enable modern JS package managers.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && corepack prepare pnpm@latest --activate \
    && corepack prepare yarn@stable --activate \
    && rm -rf /var/lib/apt/lists/*

# Install Azure CLI and GitHub CLI from official package feeds.
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg \
    && chmod go+r /etc/apt/keyrings/microsoft.gpg \
    && AZ_DISTRO="$(lsb_release -cs)" \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ ${AZ_DISTRO} main" > /etc/apt/sources.list.d/azure-cli.list \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends azure-cli gh \
    && rm -rf /var/lib/apt/lists/*

# Install PowerShell from official release tarballs for architecture portability.
RUN ARCH="$(dpkg --print-architecture)" \
    && case "${ARCH}" in \
         amd64) PS_ARCH="x64" ;; \
         arm64) PS_ARCH="arm64" ;; \
         *) echo "Unsupported architecture for PowerShell: ${ARCH}" && exit 1 ;; \
       esac \
    && curl -fsSL "https://github.com/PowerShell/PowerShell/releases/download/v${POWERSHELL_VERSION}/powershell-${POWERSHELL_VERSION}-linux-${PS_ARCH}.tar.gz" -o /tmp/powershell.tar.gz \
    && mkdir -p /opt/microsoft/powershell/7 \
    && tar -xzf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/7 \
    && chmod +x /opt/microsoft/powershell/7/pwsh \
    && ln -sf /opt/microsoft/powershell/7/pwsh /usr/local/bin/pwsh \
    && rm -f /tmp/powershell.tar.gz

# Install uv from Astral and expose binaries globally.
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && mv /root/.local/bin/uv /usr/local/bin/uv \
    && mv /root/.local/bin/uvx /usr/local/bin/uvx

# Install common Python quality tooling and React/TypeScript CLI tooling.
RUN PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install ruff \
    && PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install black \
    && PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install isort \
    && PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install mypy \
    && PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install pytest \
    && PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install pre-commit \
    && npm install -g typescript typescript-language-server eslint prettier create-vite

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
COPY scripts/tool-version-smoke-test.sh /usr/local/bin/tool-version-smoke-test.sh

RUN chmod +x /usr/local/bin/start-vscode-server.sh /usr/local/bin/healthcheck.sh /usr/local/bin/tool-version-smoke-test.sh

USER $USERNAME
WORKDIR /workspaces

EXPOSE 8443
HEALTHCHECK --interval=30s --timeout=5s --retries=5 CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/usr/local/bin/start-vscode-server.sh"]
