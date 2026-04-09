FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

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

# Install code-server for remote editor hosting.
RUN curl -fsSL https://code-server.dev/install.sh | sh

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
