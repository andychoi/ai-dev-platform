# Workspace Base Image
# Core tools, code-server, AI agents, security hardening — NO language runtimes
# Production language templates (python, nodejs, java, dotnet) extend this image

FROM ubuntu:22.04

LABEL maintainer="Platform Team"
LABEL description="Base workspace image — core tools and AI agents"
LABEL version="2.0.0"

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
    # Networking tools (openssh-client intentionally excluded — scp/sftp are exfiltration vectors)
    ca-certificates \
    gnupg \
    dnsutils \
    iputils-ping \
    # Locale support
    locales \
    && rm -rf /var/lib/apt/lists/* \
    && locale-gen en_US.UTF-8

# Minimal Node.js (for AI agent tooling — OpenCode SDK needs npm)
# This is NOT the development Node.js — the nodejs-workspace adds full toolchain
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# SECURITY: Docker CLI intentionally NOT installed
# Container escape risk: if Docker socket is reachable, docker CLI allows full host access

# Install code-server (VS Code in browser)
# Release: https://github.com/coder/code-server/releases
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --version 4.108.2

# Claude Code CLI - terminal-based AI agent (Anthropic native)
# Installed as root so binary lands in /usr/bin/claude (system PATH)
RUN npm install -g @anthropic-ai/claude-code

# Ollama CLI — local model inference client (connects to host Mac's Ollama server)
# zstd required for Ollama's compressed archive extraction
RUN apt-get update && apt-get install -y zstd && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://ollama.com/install.sh | sh

# NOTE: Coder CLI intentionally NOT installed (484 MB) — agent is injected at runtime

# Install database tools
RUN apt-get update && apt-get install -y \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user 'coder' with UID 1001 to avoid conflicts
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
RUN echo "# Restricted sudo for coder user - security hardened" > /etc/sudoers.d/coder \
    && echo "coder ALL=(ALL) NOPASSWD: /usr/bin/apt-get update" >> /etc/sudoers.d/coder \
    && echo "coder ALL=(ALL) NOPASSWD: /bin/systemctl status *" >> /etc/sudoers.d/coder \
    && echo "coder ALL=(ALL) NOPASSWD: /usr/sbin/update-ca-certificates" >> /etc/sudoers.d/coder \
    && echo "coder ALL=(ALL) NOPASSWD: /bin/cp /certs/* /usr/local/share/ca-certificates/" >> /etc/sudoers.d/coder \
    && echo "coder ALL=(ALL) NOPASSWD: /usr/local/bin/setup-firewall.sh" >> /etc/sudoers.d/coder \
    && chmod 440 /etc/sudoers.d/coder

# SECURITY: Install iptables for network egress filtering
RUN apt-get update && apt-get install -y iptables \
    && rm -rf /var/lib/apt/lists/*

# SECURITY: Network egress firewall script
COPY --chmod=755 setup-firewall.sh /usr/local/bin/setup-firewall.sh

# SECURITY: Remove/restrict dangerous binaries that enable data exfiltration
RUN rm -f /usr/bin/ssh /usr/bin/scp /usr/bin/sftp /usr/bin/ssh-keygen /usr/bin/ssh-keyscan \
    && rm -f /usr/bin/nc /usr/bin/ncat /usr/bin/netcat \
    && rm -f /usr/bin/telnet /usr/bin/ftp \
    && rm -f /usr/bin/socat /usr/bin/nmap

# SECURITY: Shell audit logging
RUN echo '# Shell audit logging for security compliance' > /etc/profile.d/shell-audit.sh \
    && echo 'export PROMPT_COMMAND='\''RETRN_VAL=$?; if [ -f /usr/bin/logger ]; then /usr/bin/logger -p local6.debug -t bash "user=$(whoami) pwd=$(pwd) cmd=$(history 1 | sed "s/^[ ]*[0-9]\+[ ]*//" ) [rc=$RETRN_VAL]"; fi'\''' >> /etc/profile.d/shell-audit.sh \
    && echo 'export HISTTIMEFORMAT="%F %T "' >> /etc/profile.d/shell-audit.sh \
    && echo 'export HISTSIZE=10000' >> /etc/profile.d/shell-audit.sh \
    && echo 'export HISTFILESIZE=20000' >> /etc/profile.d/shell-audit.sh \
    && echo 'shopt -s histappend' >> /etc/profile.d/shell-audit.sh \
    && chmod 644 /etc/profile.d/shell-audit.sh

# SECURITY: Idle session timeout (30 minutes)
RUN echo 'export TMOUT=1800' > /etc/profile.d/idle-timeout.sh \
    && echo 'readonly TMOUT' >> /etc/profile.d/idle-timeout.sh \
    && chmod 644 /etc/profile.d/idle-timeout.sh

# SECURITY: PATH lockdown
RUN echo '# Locked-down PATH for contractor workspaces' > /etc/profile.d/path-lockdown.sh \
    && echo 'export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/bin:/home/coder/.local/bin:/home/coder/.opencode/bin"' >> /etc/profile.d/path-lockdown.sh \
    && echo 'readonly PATH' >> /etc/profile.d/path-lockdown.sh \
    && chmod 644 /etc/profile.d/path-lockdown.sh

# Set up home directory
USER coder
WORKDIR /home/coder
ENV HOME=/home/coder
ENV PATH="${HOME}/.local/bin:${PATH}"

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

# VS Code extensions: core
RUN code-server --install-extension eamodio.gitlens

# VS Code extensions: database tools
RUN code-server --install-extension mtxr.sqltools \
    && code-server --install-extension mtxr.sqltools-driver-pg

# AI coding agent - Roo Code
RUN code-server --install-extension rooveterinaryinc.roo-cline

# OpenCode CLI - terminal-based AI coding agent
RUN curl -fsSL https://opencode.ai/install | bash
ENV PATH="/home/coder/.opencode/bin:${PATH}"

# Pre-install OpenAI-compatible provider SDK for OpenCode (LiteLLM)
RUN mkdir -p /home/coder/.config/opencode \
    && cd /home/coder/.config/opencode \
    && npm init -y \
    && npm install @ai-sdk/openai-compatible

# Pre-create Claude Code CLI config directory
RUN mkdir -p /home/coder/.claude

# Explicitly remove Copilot/Cody if present
RUN code-server --uninstall-extension github.copilot 2>/dev/null || true \
    && code-server --uninstall-extension github.copilot-chat 2>/dev/null || true \
    && code-server --uninstall-extension sourcegraph.cody-ai 2>/dev/null || true

CMD ["sleep", "infinity"]
