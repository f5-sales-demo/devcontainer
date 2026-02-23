FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG USER_UID=1000
ARG USER_GID=1000
ARG USERNAME=vscode

ENV DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ============================================================
# System packages (only what devcontainer features don't cover)
# ============================================================
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    libssl-dev \
    libffi-dev \
    ffmpeg \
    poppler-utils \
    qrencode \
    dnsutils \
    net-tools \
    iputils-ping \
    traceroute \
    tcpdump \
    nmap \
    bat \
    fd-find \
    neovim \
    htop \
    tree \
    fzf \
    tmux \
    file \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# Standalone tools (no devcontainer features available)
# ============================================================
ARG ACTIONLINT_VERSION=1.7.7
RUN curl -sSfL "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_$(dpkg --print-architecture).tar.gz" \
    | tar -xz -C /usr/local/bin actionlint

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

RUN mkdir -p ~/.cache ~/.local/bin ~/.claude \
    && echo '{"hasCompletedOnboarding": true}' > ~/.claude.json.default

ENV SHELL=/bin/zsh
WORKDIR /workspace

HEALTHCHECK NONE

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
