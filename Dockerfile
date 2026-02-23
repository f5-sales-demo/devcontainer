FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG USER_UID=1000
ARG USER_GID=1000
ARG USERNAME=vscode

ENV DEBIAN_FRONTEND=noninteractive

# ============================================================
# System packages (only what devcontainer features don't cover)
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build essentials
    build-essential \
    pkg-config \
    libssl-dev \
    libffi-dev \
    # Media & document tools
    ffmpeg \
    poppler-utils \
    qrencode \
    # Networking & debugging
    dnsutils \
    net-tools \
    iputils-ping \
    traceroute \
    tcpdump \
    nmap \
    # Utilities not in base image
    bat \
    fd-find \
    neovim \
    htop \
    tree \
    file \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# Python tools (no devcontainer features available for these)
# ============================================================
RUN pip install --break-system-packages \
    pre-commit \
    ansible \
    black \
    pylint \
    yamllint

# ============================================================
# npm tools (no devcontainer features available for these)
# ============================================================
RUN npm install -g \
    markdownlint-cli2

# ============================================================
# Standalone tools (no devcontainer features available)
# ============================================================

# actionlint
RUN curl -sSfL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash | bash -s -- -b /usr/local/bin

# yt-dlp
RUN curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp \
    && chmod +x /usr/local/bin/yt-dlp

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

# Pre-create directories for volumes
RUN mkdir -p ~/.cache ~/.local/bin ~/.claude

# Seed AI tool config
RUN echo '{"hasCompletedOnboarding": true}' > ~/.claude.json.default

ENV SHELL=/bin/zsh
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
