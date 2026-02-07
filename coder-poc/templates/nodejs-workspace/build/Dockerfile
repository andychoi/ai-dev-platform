# Node.js Workspace Image
# Extends workspace-base with full Node.js development toolchain

FROM workspace-base:latest

USER root

# Build tools for native npm packages (node-gyp) + dev toolchain
RUN apt-get update && apt-get install -y build-essential && rm -rf /var/lib/apt/lists/* \
    && npm install -g yarn pnpm typescript ts-node

USER coder

# VS Code extensions: JavaScript/TypeScript
RUN code-server --install-extension dbaeumer.vscode-eslint \
    && code-server --install-extension esbenp.prettier-vscode

CMD ["sleep", "infinity"]
