# Java Workspace Image
# Extends workspace-base with Java 21 JDK and Maven

FROM workspace-base:latest

USER root

# Install Java 21 JDK + Maven
RUN apt-get update && apt-get install -y \
    openjdk-21-jdk \
    maven \
    && rm -rf /var/lib/apt/lists/*

# Update PATH lockdown to include Java
RUN sed -i 's|/home/coder/.opencode/bin"|/home/coder/.opencode/bin:/usr/lib/jvm/java-21-openjdk-amd64/bin"|' /etc/profile.d/path-lockdown.sh

USER coder

# VS Code extensions: Java
RUN code-server --install-extension redhat.java \
    && code-server --install-extension vscjava.vscode-java-debug \
    && code-server --install-extension vscjava.vscode-java-dependency \
    && code-server --install-extension vscjava.vscode-maven

# IntelliJ keymap for developers migrating from JetBrains
RUN code-server --install-extension k--kato.intellij-idea-keybindings

CMD ["sleep", "infinity"]
