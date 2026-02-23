FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG USER_UID=1000
ARG USER_GID=1000
ARG USERNAME=vscode

ENV DEBIAN_FRONTEND=noninteractive

# ============================================================
# System packages
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core tools
    build-essential \
    curl \
    wget \
    git \
    vim \
    neovim \
    tmux \
    jq \
    yq \
    ripgrep \
    fd-find \
    fzf \
    bat \
    tree \
    htop \
    unzip \
    zip \
    less \
    file \
    gnupg2 \
    ca-certificates \
    apt-transport-https \
    software-properties-common \
    # Networking & debugging
    dnsutils \
    net-tools \
    iputils-ping \
    traceroute \
    tcpdump \
    nmap \
    openssh-client \
    # Development libraries
    libssl-dev \
    libffi-dev \
    pkg-config \
    # Python
    python3-pip \
    python3-venv \
    pipx \
    # Media & document tools
    ffmpeg \
    poppler-utils \
    qrencode \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Node.js 24.x
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Terraform
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list \
    && apt-get update && apt-get install -y terraform \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Python tools (pip)
RUN pip install --break-system-packages \
    pre-commit \
    ansible \
    black \
    pylint \
    yamllint

# npm global tools (as root)
RUN npm install -g \
    prettier \
    markdownlint-cli2 \
    @devcontainers/cli

# Standalone tools
RUN curl -sSfL https://raw.githubusercontent.com/nektos/act/master/install.sh | bash -s -- -b /usr/local/bin \
    && curl -sSfL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash | bash -s -- -b /usr/local/bin \
    && curl -sSfL https://terraform-docs.io/dl/latest/terraform-docs-linux-$(dpkg --print-architecture).tar.gz | tar -xz -C /usr/local/bin terraform-docs \
    && chmod +x /usr/local/bin/terraform-docs

# yt-dlp
RUN curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp \
    && chmod +x /usr/local/bin/yt-dlp

# VS Code CLI
RUN curl -sSfL "https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-$(dpkg --print-architecture | sed 's/amd64/x64/;s/arm64/arm64/')" -o /tmp/vscode-cli.tar.gz \
    && tar -xz -C /usr/local/bin -f /tmp/vscode-cli.tar.gz \
    && rm /tmp/vscode-cli.tar.gz

# ============================================================
# User setup
# ============================================================
RUN if [ "$USERNAME" != "vscode" ]; then \
        usermod -l $USERNAME -d /home/$USERNAME -m vscode && \
        groupmod -n $USERNAME vscode && \
        sed -i "s/vscode/$USERNAME/g" /etc/sudoers.d/vscode 2>/dev/null || true && \
        mv /etc/sudoers.d/vscode /etc/sudoers.d/$USERNAME 2>/dev/null || true; \
    fi

RUN if [ "$USER_GID" != "1000" ]; then \
        groupmod --non-unique --gid $USER_GID $USERNAME 2>/dev/null || true; \
    fi && \
    if [ "$USER_UID" != "1000" ]; then \
        usermod --non-unique --uid $USER_UID --gid $USER_GID $USERNAME && \
        chown -R $USER_UID:$USER_GID /home/$USERNAME; \
    fi

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER $USERNAME
WORKDIR /home/$USERNAME

# Install uv
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Pre-create directories for volumes
RUN mkdir -p ~/.cache/opencode ~/.cache/pre-commit ~/.local/bin ~/.claude

# Seed AI tool config
RUN echo '{"hasCompletedOnboarding": true}' > ~/.claude.json.default

ENV SHELL=/bin/zsh
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
