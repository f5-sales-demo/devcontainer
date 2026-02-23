FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG USER_UID=1000
ARG USER_GID=1000
ARG USERNAME=vscode

ENV DEBIAN_FRONTEND=noninteractive

# ============================================================
# System packages
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
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
    dnsutils \
    net-tools \
    iputils-ping \
    traceroute \
    tcpdump \
    nmap \
    openssh-client \
    libssl-dev \
    libffi-dev \
    pkg-config \
    python3-pip \
    python3-venv \
    pipx \
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

# pre-commit
RUN pip install --break-system-packages pre-commit

# ============================================================
# User setup — rename vscode to match host username
# ============================================================
RUN if [ "$USERNAME" != "vscode" ]; then \
        usermod -l $USERNAME -d /home/$USERNAME -m vscode && \
        groupmod -n $USERNAME vscode && \
        sed -i "s/vscode/$USERNAME/g" /etc/sudoers.d/vscode 2>/dev/null || true && \
        mv /etc/sudoers.d/vscode /etc/sudoers.d/$USERNAME 2>/dev/null || true; \
    fi

# Adjust UID/GID to match host
RUN if [ "$USER_GID" != "1000" ]; then \
        groupmod --non-unique --gid $USER_GID $USERNAME 2>/dev/null || true; \
    fi && \
    if [ "$USER_UID" != "1000" ]; then \
        usermod --non-unique --uid $USER_UID --gid $USER_GID $USERNAME && \
        chown -R $USER_UID:$USER_GID /home/$USERNAME; \
    fi

# Entrypoint to fix volume permissions
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
