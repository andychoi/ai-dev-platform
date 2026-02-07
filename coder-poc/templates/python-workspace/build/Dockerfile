# Python Workspace Image
# Extends workspace-base with Python 3.11 and common packages

FROM workspace-base:latest

USER root

# Install Python 3.11 + build tools for native pip packages
RUN apt-get update && apt-get install -y \
    python3.11 \
    python3.11-venv \
    python3.11-dev \
    python3-pip \
    build-essential \
    && rm -rf /var/lib/apt/lists/* \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1

USER coder

# Common Python packages
RUN pip3 install --user --no-cache-dir \
    pytest \
    black \
    flake8 \
    mypy \
    requests \
    pyyaml

# VS Code extensions: Python
RUN code-server --install-extension ms-python.python

CMD ["sleep", "infinity"]
