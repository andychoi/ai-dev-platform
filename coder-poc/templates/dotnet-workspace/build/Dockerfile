# .NET Workspace Image
# Extends workspace-base with .NET 8.0 SDK and C# extensions

FROM workspace-base:latest

USER root

# Install .NET SDK 8.0
RUN wget https://dot.net/v1/dotnet-install.sh -O /tmp/dotnet-install.sh \
    && chmod +x /tmp/dotnet-install.sh \
    && /tmp/dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet \
    && ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet \
    && rm /tmp/dotnet-install.sh

# Update PATH lockdown to include .NET
RUN sed -i 's|/home/coder/.opencode/bin"|/home/coder/.opencode/bin:/usr/share/dotnet"|' /etc/profile.d/path-lockdown.sh

USER coder

# C# VS Code extension (Open VSX compatible)
RUN code-server --install-extension muhammad-sammy.csharp || true

CMD ["sleep", "infinity"]
