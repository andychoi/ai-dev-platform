# Docker-Enabled Workspace Image
# Extends python-workspace with Docker CLI and Docker Compose
# Used with a rootless DinD sidecar (see main.tf)

FROM python-workspace:latest

USER root

# Docker CLI and Docker Compose plugin
# NOTE: Only the CLI is installed — the Docker daemon runs in the DinD sidecar
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
       https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y docker-ce-cli docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

USER coder

# VS Code extension: Docker
RUN code-server --install-extension ms-azuretools.vscode-docker

CMD ["sleep", "infinity"]
