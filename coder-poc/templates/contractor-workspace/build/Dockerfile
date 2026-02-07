# Contractor Workspace Image
# Secure development environment with VS Code, common tools, and language runtimes

FROM ubuntu:22.04

LABEL maintainer="Platform Team"
LABEL description="Secure contractor development workspace"
LABEL version="1.0.0"

# Avoid interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Install base system packages
RUN apt-get update && apt-get install -y \
    # Core utilities
    curl \
    wget \
    git \
    vim \
    nano \
    sudo \
    htop \
    tree \
    unzip \
    zip \
    jq \
    # Networking tools
    openssh-client \
    ca-certificates \
    gnupg \
    dnsutils \
    iputils-ping \
    # Build essentials
    build-essential \
    pkg-config \
    # Locale support
    locales \
    && rm -rf /var/lib/apt/lists/* \
    && locale-gen en_US.UTF-8

# Install Node.js 20 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g npm@latest \
    && npm install -g yarn pnpm typescript ts-node

# Install Python 3.11
RUN apt-get update && apt-get install -y \
    python3.11 \
    python3.11-venv \
    python3-pip \
    && rm -rf /var/lib/apt/lists/* \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1

# Install Go 1.22
RUN curl -fsSL https://go.dev/dl/go1.22.0.linux-amd64.tar.gz | tar -C /usr/local -xzf - \
    && echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile.d/go.sh

# Install Docker CLI (for Docker-in-Docker scenarios if needed)
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu jammy stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# Install code-server (VS Code in browser)
# Release: https://github.com/coder/code-server/releases
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --version 4.108.2

# Install Coder CLI (optional - agent is injected at runtime)
RUN curl -fsSL https://coder.com/install.sh | sh || echo "Coder CLI install skipped"

# Install database tools
RUN apt-get update && apt-get install -y \
    postgresql-client \
    mysql-client \
    && rm -rf /var/lib/apt/lists/*

# Install .NET SDK 8.0 (for C# developers)
RUN wget https://dot.net/v1/dotnet-install.sh -O /tmp/dotnet-install.sh \
    && chmod +x /tmp/dotnet-install.sh \
    && /tmp/dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet \
    && ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet \
    && rm /tmp/dotnet-install.sh

# Install Java 21 (for Java/IntelliJ developers)
RUN apt-get update && apt-get install -y openjdk-21-jdk maven gradle \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user 'coder' with UID 1001 to avoid conflicts
# Handle case where user/UID might already exist
RUN if id -u 1001 >/dev/null 2>&1; then \
        existing_user=$(getent passwd 1001 | cut -d: -f1); \
        if [ "$existing_user" != "coder" ]; then \
            userdel -r "$existing_user" 2>/dev/null || true; \
            useradd -m -s /bin/bash -u 1001 coder; \
        fi; \
    elif id coder >/dev/null 2>&1; then \
        usermod -u 1001 coder; \
        groupmod -g 1001 coder 2>/dev/null || true; \
    else \
        useradd -m -s /bin/bash -u 1001 coder; \
    fi \
    && usermod -s /bin/bash coder

# SECURITY: Restricted sudo - only allow specific safe commands
# No general sudo access - contractors should not need root privileges
RUN echo "# Restricted sudo for coder user - security hardened" > /etc/sudoers.d/coder \
    && echo "coder ALL=(ALL) NOPASSWD: /usr/bin/apt-get update" >> /etc/sudoers.d/coder \
    && echo "coder ALL=(ALL) NOPASSWD: /usr/bin/apt-get install *" >> /etc/sudoers.d/coder \
    && echo "coder ALL=(ALL) NOPASSWD: /bin/systemctl status *" >> /etc/sudoers.d/coder \
    && echo "coder ALL=(ALL) NOPASSWD: /usr/sbin/update-ca-certificates" >> /etc/sudoers.d/coder \
    && echo "coder ALL=(ALL) NOPASSWD: /bin/cp * /usr/local/share/ca-certificates/*" >> /etc/sudoers.d/coder \
    && chmod 440 /etc/sudoers.d/coder

# Set up home directory
USER coder
WORKDIR /home/coder
ENV HOME=/home/coder
ENV PATH="${HOME}/.local/bin:/usr/local/go/bin:${PATH}"

# Create workspace directory
RUN mkdir -p /home/coder/workspace

# Configure git defaults
RUN git config --global init.defaultBranch main \
    && git config --global pull.rebase false \
    && git config --global core.editor vim

# Pre-create VS Code settings directory
RUN mkdir -p /home/coder/.local/share/code-server/User

# Copy VS Code settings
COPY --chown=coder:coder settings.json /home/coder/.local/share/code-server/User/settings.json

# Install common Python packages
RUN pip3 install --user --no-cache-dir \
    pytest \
    black \
    flake8 \
    mypy \
    requests \
    pyyaml

# Pre-install useful VS Code extensions
RUN code-server --install-extension ms-python.python \
    && code-server --install-extension dbaeumer.vscode-eslint \
    && code-server --install-extension esbenp.prettier-vscode \
    && code-server --install-extension eamodio.gitlens \
    && code-server --install-extension golang.go

# Database extensions (Toad SQL alternatives)
RUN code-server --install-extension mtxr.sqltools \
    && code-server --install-extension mtxr.sqltools-driver-pg \
    && code-server --install-extension mtxr.sqltools-driver-mysql \
    && code-server --install-extension cweijan.vscode-database-client2

# Java/IntelliJ alternatives
RUN code-server --install-extension redhat.java \
    && code-server --install-extension vscjava.vscode-java-debug \
    && code-server --install-extension vscjava.vscode-java-dependency \
    && code-server --install-extension vscjava.vscode-maven \
    && code-server --install-extension vmware.vscode-spring-boot

# .NET/C# alternatives (Open VSX compatible)
RUN code-server --install-extension muhammad-sammy.csharp || true

# AI coding agent - Roo Code (agentic AI assistant)
# Pre-installed so every developer has it ready without manual setup
RUN code-server --install-extension rooveterinaryinc.roo-cline

# OpenCode CLI - terminal-based AI coding agent
# Installed alongside Roo Code so developers can use either GUI or CLI
# The installer places the binary at ~/.opencode/bin/opencode (runs as coder user)
RUN curl -fsSL https://opencode.ai/install | bash
ENV PATH="/home/coder/.opencode/bin:${PATH}"

# Pre-install OpenAI-compatible provider SDK for OpenCode custom providers (LiteLLM)
# Without this, opencode can't load the "litellm" provider defined in opencode.json
RUN mkdir -p /home/coder/.config/opencode \
    && cd /home/coder/.config/opencode \
    && npm init -y \
    && npm install @ai-sdk/openai-compatible

# Explicitly remove Copilot/Cody if present from base image or sideload
RUN code-server --uninstall-extension github.copilot 2>/dev/null || true \
    && code-server --uninstall-extension github.copilot-chat 2>/dev/null || true \
    && code-server --uninstall-extension sourcegraph.cody-ai 2>/dev/null || true

# IntelliJ keymap for developers migrating from JetBrains
RUN code-server --install-extension k--kato.intellij-idea-keybindings

# Default command - will be overridden by Coder agent
CMD ["sleep", "infinity"]
