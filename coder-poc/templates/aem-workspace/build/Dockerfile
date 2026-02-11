# AEM 6.5 Workspace Image
# Extends workspace-base with Java 11 JDK, Maven 3.9.9, and AEM tooling
#
# IMPORTANT: AEM 6.5 requires Java 11 (NOT 21). This image is based on
# workspace-base directly, NOT java-workspace (which ships Java 21).

FROM workspace-base:latest

USER root

# Install Java 11 JDK + AEM build tooling
RUN apt-get update && apt-get install -y \
    openjdk-11-jdk \
    xmlstarlet \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Maven 3.9.9 from Apache archive (apt only has 3.6.x)
RUN curl -fsSL https://archive.apache.org/dist/maven/maven-3/3.9.9/binaries/apache-maven-3.9.9-bin.tar.gz \
    | tar -xz -C /opt \
    && ln -s /opt/apache-maven-3.9.9/bin/mvn /usr/local/bin/mvn

# Update PATH lockdown to include Java 11 + Maven
RUN sed -i 's|/home/coder/.opencode/bin"|/home/coder/.opencode/bin:/usr/lib/jvm/java-11-openjdk-amd64/bin:/opt/apache-maven-3.9.9/bin"|' /etc/profile.d/path-lockdown.sh

# Set JAVA_HOME for Maven and build tools
ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64

USER coder

# Pre-create AEM directories (persistent volume will overlay /home/coder,
# but these ensure correct ownership on first start)
RUN mkdir -p /home/coder/aem/author \
    && mkdir -p /home/coder/aem/publisher \
    && mkdir -p /home/coder/.m2

# Copy Maven settings with Adobe repo + AEM server credentials
# --chown required: COPY defaults to root:root regardless of USER directive
COPY --chown=coder:coder maven-settings.xml /home/coder/.m2/settings.xml

# Copy VS Code settings (Java 11 runtime, AEM file associations)
COPY --chown=coder:coder settings.json /home/coder/.local/share/code-server/User/settings.json

# Copy debug launch config (JPDA attach to AEM Author)
COPY --chown=coder:coder .vscode/launch.json /home/coder/.local/share/code-server/User/launch.json

# VS Code extensions: Java development
RUN code-server --install-extension redhat.java \
    && code-server --install-extension vscjava.vscode-java-debug \
    && code-server --install-extension vscjava.vscode-java-dependency \
    && code-server --install-extension vscjava.vscode-maven

# VS Code extensions: AEM/XML tooling
RUN code-server --install-extension dotjoshjohnson.xml

# IntelliJ keymap for developers migrating from JetBrains
RUN code-server --install-extension k--kato.intellij-idea-keybindings

CMD ["sleep", "infinity"]
