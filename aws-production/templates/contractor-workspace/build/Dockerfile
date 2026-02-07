# Contractor Workspace Image (Production)
# Mirrors PoC image with production-hardened settings

FROM ubuntu:22.04

LABEL maintainer="Platform Team"
LABEL description="Secure contractor development workspace (production)"

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Install base system packages
RUN apt-get update && apt-get install -y \
    curl wget git vim nano sudo htop tree unzip zip jq \
    openssh-client ca-certificates gnupg dnsutils iputils-ping \
    build-essential pkg-config locales \
    && rm -rf /var/lib/apt/lists/* \
    && locale-gen en_US.UTF-8

# Install Node.js 20 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g npm@latest yarn pnpm typescript ts-node

# Install Python 3.11
RUN apt-get update && apt-get install -y \
    python3.11 python3.11-venv python3-pip \
    && rm -rf /var/lib/apt/lists/* \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1

# Install Go 1.22
RUN curl -fsSL https://go.dev/dl/go1.22.0.linux-amd64.tar.gz | tar -C /usr/local -xzf -

# Install code-server
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --version 4.108.2

# Install database tools
RUN apt-get update && apt-get install -y postgresql-client mysql-client \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -s /bin/bash -u 1000 coder \
    && echo "coder ALL=(ALL) NOPASSWD: /usr/bin/apt-get update, /usr/bin/apt-get install *, /usr/sbin/update-ca-certificates, /bin/cp * /usr/local/share/ca-certificates/*" > /etc/sudoers.d/coder \
    && chmod 440 /etc/sudoers.d/coder

USER coder
WORKDIR /home/coder
ENV HOME=/home/coder
ENV PATH="${HOME}/.local/bin:/usr/local/go/bin:${PATH}"

RUN mkdir -p /home/coder/workspace \
    && mkdir -p /home/coder/.local/share/code-server/User

# Git defaults
RUN git config --global init.defaultBranch main \
    && git config --global pull.rebase false

# VS Code extensions
RUN code-server --install-extension ms-python.python \
    && code-server --install-extension dbaeumer.vscode-eslint \
    && code-server --install-extension esbenp.prettier-vscode \
    && code-server --install-extension eamodio.gitlens \
    && code-server --install-extension golang.go

# AI coding agents
RUN code-server --install-extension rooveterinaryinc.roo-cline

# OpenCode CLI - terminal-based AI coding agent
# The installer places the binary at ~/.opencode/bin/opencode (runs as coder user)
RUN curl -fsSL https://opencode.ai/install | bash
ENV PATH="/home/coder/.opencode/bin:${PATH}"

# Pre-install OpenAI-compatible provider SDK for OpenCode custom providers (LiteLLM)
# Without this, opencode can't load the "litellm" provider defined in opencode.json
RUN cd /home/coder/.config/opencode && npm install @ai-sdk/openai-compatible

# Remove competing AI extensions
RUN code-server --uninstall-extension github.copilot 2>/dev/null || true \
    && code-server --uninstall-extension github.copilot-chat 2>/dev/null || true \
    && code-server --uninstall-extension sourcegraph.cody-ai 2>/dev/null || true

CMD ["sleep", "infinity"]
