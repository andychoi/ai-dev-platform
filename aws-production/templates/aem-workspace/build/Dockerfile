# AEM 6.5 Workspace Image (Production)
# Based on contractor-workspace pattern with Java 11, Maven 3.9.9, and AWS CLI v2
#
# IMPORTANT: AEM 6.5 requires Java 11 (NOT 21).
# AWS CLI v2 is included for S3-based JAR delivery (uses IAM task role, no keys).

FROM ubuntu:22.04

LABEL maintainer="Platform Team"
LABEL description="AEM 6.5 development workspace (production)"

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

# Install Java 11 JDK (AEM 6.5 requirement — NOT Java 21)
RUN apt-get update && apt-get install -y \
    openjdk-11-jdk \
    xmlstarlet \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64

# Install Maven 3.9.9 from Apache archive (apt only has 3.6.x)
RUN curl -fsSL https://archive.apache.org/dist/maven/maven-3/3.9.9/binaries/apache-maven-3.9.9-bin.tar.gz \
    | tar -xz -C /opt \
    && ln -s /opt/apache-maven-3.9.9/bin/mvn /usr/local/bin/mvn

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

# Install AWS CLI v2 (for S3-based JAR delivery via IAM task role)
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip

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
ENV PATH="${HOME}/.local/bin:/usr/lib/jvm/java-11-openjdk-amd64/bin:/opt/apache-maven-3.9.9/bin:${PATH}"

RUN mkdir -p /home/coder/workspace \
    && mkdir -p /home/coder/.local/share/code-server/User

# Pre-create AEM directories (EFS overlay on /home/coder creates these on first start)
RUN mkdir -p /home/coder/aem/author \
    && mkdir -p /home/coder/aem/publisher \
    && mkdir -p /home/coder/.m2

# Copy Maven settings with Adobe repo + AEM server credentials
COPY --chown=coder:coder maven-settings.xml /home/coder/.m2/settings.xml

# Copy VS Code settings (Java 11 runtime, AEM file associations)
COPY --chown=coder:coder settings.json /home/coder/.local/share/code-server/User/settings.json

# Copy debug launch config (JPDA attach to AEM Author)
COPY --chown=coder:coder .vscode/launch.json /home/coder/.local/share/code-server/User/launch.json

# Git defaults
RUN git config --global init.defaultBranch main \
    && git config --global pull.rebase false

# VS Code extensions: General development
RUN code-server --install-extension ms-python.python \
    && code-server --install-extension dbaeumer.vscode-eslint \
    && code-server --install-extension esbenp.prettier-vscode \
    && code-server --install-extension eamodio.gitlens

# VS Code extensions: Java development
RUN code-server --install-extension redhat.java \
    && code-server --install-extension vscjava.vscode-java-debug \
    && code-server --install-extension vscjava.vscode-java-dependency \
    && code-server --install-extension vscjava.vscode-maven

# VS Code extensions: AEM/XML tooling
RUN code-server --install-extension dotjoshjohnson.xml

# VS Code extensions: IntelliJ keymap for developers migrating from JetBrains
RUN code-server --install-extension k--kato.intellij-idea-keybindings

# AI coding agents
RUN code-server --install-extension rooveterinaryinc.roo-cline

# OpenCode CLI - terminal-based AI coding agent
RUN curl -fsSL https://opencode.ai/install | bash
ENV PATH="/home/coder/.opencode/bin:${PATH}"

# Pre-install OpenAI-compatible provider SDK for OpenCode custom providers (LiteLLM)
RUN cd /home/coder/.config/opencode && npm install @ai-sdk/openai-compatible

# Remove competing AI extensions
RUN code-server --uninstall-extension github.copilot 2>/dev/null || true \
    && code-server --uninstall-extension github.copilot-chat 2>/dev/null || true \
    && code-server --uninstall-extension sourcegraph.cody-ai 2>/dev/null || true

CMD ["sleep", "infinity"]
