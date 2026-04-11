# ╔════════════════════════════════════════════════════════════╗
# ║  Stage 1: deps  (stable foundations, ~4.5 GB)            ║
# ║  Rebuilds only on version ARG bumps or APT changes.      ║
# ╚════════════════════════════════════════════════════════════╝
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04 AS deps

ARG USERNAME=vscode

# ============================================================
# Version pins — deps stage (only tools without a "latest" API)
# ============================================================
ARG NODE_MAJOR=24
ARG PYTHON_VERSION=3.13
ARG JAVA_VERSION=25
ARG MAVEN_VERSION=3.9.14
ARG BROWSH_VERSION=1.8.2
ARG GHIDRA_VERSION=12.0.4
ARG GHIDRA_DATE=20260303

ENV DEBIAN_FRONTEND=noninteractive

# Retry flags for all curl downloads — handles transient network
# errors (connection timeouts, DNS failures) with exponential backoff.
# shellcheck disable=SC2140
ENV CURL_RETRY="--connect-timeout 30 --retry 3 --retry-connrefused --retry-delay 10"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ============================================================
# 1. APT repository setup
# ============================================================
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg software-properties-common apt-transport-https \
    # NodeSource
    && curl ${CURL_RETRY} -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
    # deadsnakes (Python)
    && add-apt-repository -y ppa:deadsnakes/ppa \
    # .NET backports (dotnet 9.0+ for Ubuntu 24.04)
    && add-apt-repository -y ppa:dotnet/backports \
    # HashiCorp
    && curl ${CURL_RETRY} -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
      > /etc/apt/sources.list.d/hashicorp.list \
    # GitHub CLI
    && curl ${CURL_RETRY} -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
    # Microsoft (Azure CLI + PowerShell)
    && curl ${CURL_RETRY} -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" \
      > /etc/apt/sources.list.d/azure-cli.list \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/ubuntu/24.04/prod $(lsb_release -cs) main" \
      > /etc/apt/sources.list.d/microsoft-prod.list \
    # Google Cloud CLI
    && curl ${CURL_RETRY} -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
      | gpg --dearmor -o /usr/share/keyrings/cloud-google-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/cloud-google-archive-keyring.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
      > /etc/apt/sources.list.d/google-cloud-sdk.list \
    # Dart SDK
    && curl ${CURL_RETRY} -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub \
      | gpg --dearmor -o /usr/share/keyrings/dart-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/dart-archive-keyring.gpg] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main" \
      > /etc/apt/sources.list.d/dart_stable.list \
    # Tailscale
    && curl ${CURL_RETRY} -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg \
      -o /usr/share/keyrings/tailscale-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu noble main" \
      > /etc/apt/sources.list.d/tailscale.list \
    # Mozilla (Firefox ESR — Browsh backend, amd64 + arm64)
    && ARCH="$(dpkg --print-architecture)" \
    && if [ "$ARCH" = "amd64" ] || [ "$ARCH" = "arm64" ]; then \
      curl ${CURL_RETRY} -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg \
        | gpg --dearmor -o /usr/share/keyrings/packages.mozilla.org.gpg \
      && echo "deb [signed-by=/usr/share/keyrings/packages.mozilla.org.gpg] https://packages.mozilla.org/apt mozilla main" \
        > /etc/apt/sources.list.d/mozilla.list \
      && printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' \
        > /etc/apt/preferences.d/mozilla; \
    fi \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ============================================================
# 2. APT package install
# ============================================================
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
    # System essentials
    build-essential pkg-config libssl-dev libffi-dev libcairo2-dev cmake lld \
    # Media / utilities
    ffmpeg poppler-utils qrencode \
    # Network tools
    dnsutils net-tools iputils-ping traceroute tcpdump nmap netcat-openbsd jnettop \
    # CLI browsers (xdg-open fallback for gh auth login)
    lynx w3m elinks links2 \
    # Tailscale VPN
    tailscale \
    # Firecrawl runtime dependencies
    redis-server \
    postgresql postgresql-client \
    rabbitmq-server \
    # Shell tools
    cron \
    bat bubblewrap fd-find ripgrep htop tree tmux file xxd \
    # Filesystem event watcher (plugin hook neutralization daemon)
    inotify-tools \
    # Node.js
    nodejs \
    # Python
    "python${PYTHON_VERSION}" "python${PYTHON_VERSION}-dev" "python${PYTHON_VERSION}-venv" \
    # Java
    "openjdk-${JAVA_VERSION}-jdk-headless" \
    # Terraform
    terraform \
    # GitHub CLI
    gh \
    # Azure CLI
    azure-cli \
    # Locale
    locales \
    locales-all \
    # Additional tools
    dos2unix \
    eza \
    fontconfig \
    fonts-noto-color-emoji \
    fonts-powerline \
    google-cloud-cli \
    graphviz \
    imagemagick \
    jq \
    mtr-tiny \
    shellcheck \
    unzip \
    xz-utils \
    yelp-tools \
    # Super-linter language runtimes
    clang-format \
    libxml2-utils \
    chktex \
    ruby-full \
    php-cli php-xml php-mbstring \
    libperl-critic-perl \
    lua5.4 liblua5.4-dev luarocks \
    r-base \
    dart \
    dotnet-sdk-9.0 \
    dotnet-runtime-8.0 \
    # C/C++ LSP server
    clangd \
    # D language compiler + package manager (for building dfmt)
    ldc \
    dub \
    # AI assistant tool dependencies
    libbrotli-dev \
    libc-ares-dev \
    libfmt-dev \
    liblz4-dev \
    libnghttp2-dev \
    libnghttp3-dev \
    libngtcp2-dev \
    libpcre2-dev \
    libreadline-dev \
    libsimdjson-dev \
    libsqlite3-dev \
    libuv1-dev \
    libevent-dev \
    libncurses-dev \
    libutf8proc-dev \
    libzstd-dev \
    # Super-linter build deps (for cpanm, luarocks C extensions)
    cpanminus \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen en_US.UTF-8 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Pre-seed wireshark debconf — allow non-root packet capture via dumpcap
# hadolint ignore=DL3059
RUN echo "wireshark-common wireshark-common/install-setuid boolean true" \
      | debconf-set-selections

# Pre-seed MS core fonts EULA — non-interactive acceptance
# hadolint ignore=DL3059
RUN echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" \
      | debconf-set-selections

# Install Microsoft core fonts (Arial, Times New Roman, Courier New, Verdana, etc.)
# hadolint ignore=DL3008,DL3059
RUN apt-get update && apt-get install -y --no-install-recommends \
    ttf-mscorefonts-installer \
    && fc-cache -fv \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ============================================================
# 2c. Firefox ESR + Browsh (amd64 + arm64)
# ============================================================
# hadolint ignore=DL3008,DL3059
RUN ARCH="$(dpkg --print-architecture)" \
    && if [ "$ARCH" = "amd64" ] || [ "$ARCH" = "arm64" ]; then \
      apt-get update \
      && apt-get install -y --no-install-recommends firefox-esr \
      && curl ${CURL_RETRY} -fsSL \
          "https://github.com/browsh-org/browsh/releases/download/v${BROWSH_VERSION}/browsh_${BROWSH_VERSION}_linux_${ARCH}.deb" \
          -o /tmp/browsh.deb \
      && dpkg -i /tmp/browsh.deb \
      && rm /tmp/browsh.deb \
      && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

# ============================================================
# 2b. Security & pentest APT packages
# ============================================================
# hadolint ignore=DL3008,DL3059
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Network analysis & diagnostics
    tshark \
    wireshark \
    iperf3 \
    masscan \
    socat \
    hping3 \
    iputils-arping \
    whois \
    netdiscover \
    ngrep \
    ethtool \
    # Web & service scanners
    nikto \
    sqlmap \
    dirb \
    whatweb \
    sslscan \
    # Password & authentication
    hydra \
    john \
    hashcat \
    medusa \
    ncrack \
    # Reverse engineering & forensics
    radare2 \
    gdb \
    gdb-multiarch \
    binwalk \
    strace \
    ltrace \
    foremost \
    libimage-exiftool-perl \
    # Runtime libraries (bettercap, scapy)
    libpcap-dev \
    libnetfilter-queue-dev \
    # Build deps for lxml (spiderfoot requirement)
    libxml2-dev \
    libxslt1-dev \
    # OSINT: media metadata & forensics
    exiv2 \
    mediainfo \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create expected binary names for tools Ubuntu renames
RUN ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV TERM=xterm-256color
ENV COLORTERM=truecolor

# PowerShell — Microsoft only publishes amd64 .deb packages;
# arm64 resolves latest version from GitHub and uses the tar.gz.
# hadolint ignore=DL3008,DL3059
RUN DPKG_ARCH=$(dpkg --print-architecture) \
    && if [ "$DPKG_ARCH" = "amd64" ]; then \
      apt-get update && apt-get install -y --no-install-recommends powershell \
      && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    else \
      PWSH_VERSION=$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/PowerShell/PowerShell/releases/latest" | sed 's|.*/||;s|^v||') \
      && mkdir -p /opt/microsoft/powershell/7 \
      && curl ${CURL_RETRY} -fsSL "https://github.com/PowerShell/PowerShell/releases/download/v${PWSH_VERSION}/powershell-${PWSH_VERSION}-linux-${DPKG_ARCH}.tar.gz" \
        | tar -xz -C /opt/microsoft/powershell/7 \
      && chmod 755 /opt/microsoft/powershell/7/pwsh \
      && ln -sf /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh \
      && ln -sf /usr/bin/pwsh /usr/bin/powershell; \
    fi

# ============================================================
# 3. Python bootstrap (symlinks + pip)
# ============================================================
RUN update-alternatives --install /usr/bin/python3 python3 "/usr/bin/python${PYTHON_VERSION}" 1 \
    && update-alternatives --install /usr/bin/python  python  "/usr/bin/python${PYTHON_VERSION}" 1 \
    && curl ${CURL_RETRY} -fsSL https://bootstrap.pypa.io/get-pip.py | "python${PYTHON_VERSION}"

# ============================================================
# 4. Go (latest stable — resolved at build time)
# ============================================================
RUN GO_VERSION=$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1 | sed 's/^go//') \
    && ARCH=$(dpkg --print-architecture) \
    && curl ${CURL_RETRY} -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" | tar -xz -C /usr/local
ENV PATH="/usr/local/go/bin:${PATH}"

# ============================================================
# 5. Rust (system-wide, stable + nightly — resolved by rustup)
# ============================================================
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH="/usr/local/cargo/bin:${PATH}"
RUN curl ${CURL_RETRY} --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --default-toolchain stable --no-modify-path \
    && rustup toolchain install nightly --profile minimal \
    && rustup component add clippy rustfmt rust-analyzer rust-src \
    && rustup component add --toolchain nightly clippy rustfmt rust-analyzer rust-src \
    && cargo install cargo-watch cargo-edit \
    && chown -R ${USERNAME}:${USERNAME} /usr/local/rustup /usr/local/cargo

# ============================================================
# 6. Maven + Gradle
# ============================================================
# hadolint ignore=DL3059
RUN curl ${CURL_RETRY} -fsSL "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
    | tar -xz -C /opt \
    && ln -s "/opt/apache-maven-${MAVEN_VERSION}/bin/mvn" /usr/local/bin/mvn

# hadolint ignore=DL3059
RUN GRADLE_VERSION=$(curl -fsSL https://services.gradle.org/versions/current | jq -r .version) \
    && curl ${CURL_RETRY} -fsSL "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" -o /tmp/gradle.zip \
    && unzip -q /tmp/gradle.zip -d /opt \
    && ln -s "/opt/gradle-${GRADLE_VERSION}/bin/gradle" /usr/local/bin/gradle \
    && rm /tmp/gradle.zip

# ============================================================
# 7. VNC stack (Xvfb + x11vnc + noVNC + fluxbox)
#    Moved to deps — stable APT packages, rarely changes.
# ============================================================
# hadolint ignore=DL3008,DL3059
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    x11vnc \
    novnc \
    fluxbox \
    x11-utils \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ============================================================
# 8. Nerd Fonts (JetBrainsMono, Hack, FiraCode)
#    Asset names are version-free — /releases/latest/download/ works directly.
# ============================================================
# hadolint ignore=DL3059
RUN mkdir -p /usr/local/share/fonts/nerd-fonts \
    && curl ${CURL_RETRY} -fsSL \
      "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz" \
      | tar -xJ -C /usr/local/share/fonts/nerd-fonts \
    && curl ${CURL_RETRY} -fsSL \
      "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.tar.xz" \
      | tar -xJ -C /usr/local/share/fonts/nerd-fonts \
    && curl ${CURL_RETRY} -fsSL \
      "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.tar.xz" \
      | tar -xJ -C /usr/local/share/fonts/nerd-fonts \
    && fc-cache -fv

# ============================================================
# 8b. Pre-warm Firefox profile for Browsh
#     First-run profile creation + extension install is slow
#     enough to cause "Waiting for Firefox to connect" hangs.
#     Running browsh once at build time caches everything.
# ============================================================
# hadolint ignore=DL3001,DL3059
RUN if command -v browsh >/dev/null 2>&1; then \
      Xvfb :99 -screen 0 1280x1024x24 -ac >/dev/null 2>&1 & \
      XVFB_PID=$! \
      && sleep 1 \
      && DISPLAY=:99 TERM=xterm browsh --startup-url https://example.com \
          --time-limit 15 >/dev/null 2>&1 || true \
      && kill $XVFB_PID 2>/dev/null || true; \
    fi


# ╔════════════════════════════════════════════════════════════╗
# ║  Stage 2: final  (volatile tools + user setup, ~1.5 GB)  ║
# ║  Changes to tools here don't rebuild the deps stage.      ║
# ╚════════════════════════════════════════════════════════════╝
FROM deps AS final

# SHELL doesn't cross FROM boundaries — redeclare for pipefail
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ARGs don't cross FROM boundaries — redeclare what final needs
ARG USERNAME=vscode
ARG IBMCLOUD_VERSION=2.41.1
ARG GHIDRA_VERSION=12.0.4
ARG GHIDRA_DATE=20260303
ARG BUILD_COMMIT=unknown
ARG BUILD_DATE=unknown
ARG ZIG_VERSION=0.15.2

# ============================================================
# 9. AWS CLI v2
# ============================================================
# hadolint ignore=DL3059
RUN ARCH=$(uname -m) \
    && curl ${CURL_RETRY} -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o /tmp/awscli.zip \
    && unzip -q /tmp/awscli.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscli.zip

# ============================================================
# 10. Binary tools (kubectl, helm, tflint, terraform-docs,
#     act, actionlint, yt-dlp, uv)
#     All resolve latest versions at build time.
# ============================================================
# hadolint ignore=DL3059
RUN ghlatest() { curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's|.*/||;s|^v||'; } \
    && DPKG_ARCH=$(dpkg --print-architecture) && UNAME_ARCH=$(uname -m) \
    # kubectl (latest stable)
    && KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt) \
    && curl ${CURL_RETRY} -fsSLo /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${DPKG_ARCH}/kubectl" \
    && chmod +x /usr/local/bin/kubectl \
    # helm (resolve version via GitHub redirect)
    && HELM_VERSION=$(ghlatest helm/helm) \
    && curl ${CURL_RETRY} -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${DPKG_ARCH}.tar.gz" \
      | tar -xz --strip-components=1 -C /usr/local/bin "linux-${DPKG_ARCH}/helm" \
    # tflint (latest — version-free asset name)
    && curl ${CURL_RETRY} -fsSL "https://github.com/terraform-linters/tflint/releases/latest/download/tflint_linux_${DPKG_ARCH}.zip" \
      -o /tmp/tflint.zip \
    && unzip -q /tmp/tflint.zip -d /usr/local/bin && rm /tmp/tflint.zip \
    # terraform-docs (resolve version — asset name contains version)
    && TERRAFORM_DOCS_VERSION=$(ghlatest terraform-docs/terraform-docs) \
    && curl ${CURL_RETRY} -fsSL "https://github.com/terraform-docs/terraform-docs/releases/latest/download/terraform-docs-v${TERRAFORM_DOCS_VERSION}-linux-${DPKG_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin terraform-docs \
    # act (latest — version-free asset name)
    && if [ "$UNAME_ARCH" = "x86_64" ]; then ACT_ARCH="x86_64"; else ACT_ARCH="arm64"; fi \
    && curl ${CURL_RETRY} -fsSL "https://github.com/nektos/act/releases/latest/download/act_Linux_${ACT_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin act \
    # actionlint (resolve version — asset name contains version)
    && ACTIONLINT_VERSION=$(ghlatest rhysd/actionlint) \
    && curl ${CURL_RETRY} -fsSL "https://github.com/rhysd/actionlint/releases/latest/download/actionlint_${ACTIONLINT_VERSION}_linux_${DPKG_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin actionlint \
    # yt-dlp (already latest)
    && curl ${CURL_RETRY} -fsSLo /usr/local/bin/yt-dlp \
      "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" \
    && chmod +x /usr/local/bin/yt-dlp \
    # uv (latest — omit version from installer URL)
    && curl ${CURL_RETRY} -fsSL "https://astral.sh/uv/install.sh" | sh \
    && mv "$HOME/.local/bin/uv" /usr/local/bin/uv \
    && mv "$HOME/.local/bin/uvx" /usr/local/bin/uvx 2>/dev/null || true \
    # neovim (latest — version-free asset name; map aarch64→arm64)
    && if [ "$UNAME_ARCH" = "aarch64" ]; then NVIM_ARCH="arm64"; else NVIM_ARCH="x86_64"; fi \
    && curl ${CURL_RETRY} -fsSL \
      "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${NVIM_ARCH}.tar.gz" \
      | tar -xz -C /opt \
    && ln -s "/opt/nvim-linux-${NVIM_ARCH}/bin/nvim" /usr/local/bin/nvim

# ============================================================
# 10b. Additional binary tools (code CLI, oc, yq, terragrunt,
#      ibmcloud, fzf, hadolint, codex)
#      All resolve latest versions at build time except IBM Cloud CLI.
# ============================================================
# hadolint ignore=DL3059
RUN ghlatest() { curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's|.*/||;s|^v||'; } \
    && DPKG_ARCH=$(dpkg --print-architecture) \
    # Visual Studio Code CLI (already latest)
    && if [ "$DPKG_ARCH" = "amd64" ]; then VSCODE_ARCH="x64"; else VSCODE_ARCH="arm64"; fi \
    && curl ${CURL_RETRY} -fsSL \
      "https://update.code.visualstudio.com/latest/cli-linux-${VSCODE_ARCH}/stable" \
      -o /tmp/vscode_cli.tar.gz \
    && tar -xzf /tmp/vscode_cli.tar.gz -C /usr/local/bin \
    && rm /tmp/vscode_cli.tar.gz \
    # oc (OpenShift CLI) — stable channel uses version-free filenames
    && if [ "$DPKG_ARCH" = "amd64" ]; then OC_ARCHIVE="openshift-client-linux.tar.gz"; else OC_ARCHIVE="openshift-client-linux-arm64.tar.gz"; fi \
    && curl ${CURL_RETRY} -fsSL \
      "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/${OC_ARCHIVE}" \
      | tar -xz -C /usr/local/bin oc \
    # yq v4 (latest — version-free asset name)
    && curl ${CURL_RETRY} -fsSLo /usr/local/bin/yq \
      "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${DPKG_ARCH}" \
    && chmod +x /usr/local/bin/yq \
    && ln -sf /usr/local/bin/yq /usr/local/bin/yq4 \
    # yq v3 (EOL, last release 3.4.1) — stays pinned
    && curl ${CURL_RETRY} -fsSLo /usr/local/bin/yq3 \
      "https://github.com/mikefarah/yq/releases/download/3.4.1/yq_linux_${DPKG_ARCH}" \
    && chmod +x /usr/local/bin/yq3 \
    # terragrunt (latest — version-free asset name)
    && curl ${CURL_RETRY} -fsSLo /usr/local/bin/terragrunt \
      "https://github.com/gruntwork-io/terragrunt/releases/latest/download/terragrunt_linux_${DPKG_ARCH}" \
    && chmod +x /usr/local/bin/terragrunt \
    # IBM Cloud CLI — stays pinned (no "latest" URL)
    && if [ "$DPKG_ARCH" = "amd64" ]; then IBM_ARCH="amd64"; else IBM_ARCH="arm64"; fi \
    && curl ${CURL_RETRY} -fsSL \
      "https://download.clis.cloud.ibm.com/ibm-cloud-cli/${IBMCLOUD_VERSION}/IBM_Cloud_CLI_${IBMCLOUD_VERSION}_${IBM_ARCH}.tar.gz" \
      -o /tmp/ibmcloud.tar.gz \
    && tar -xzf /tmp/ibmcloud.tar.gz -C /tmp \
    && install -m 755 /tmp/Bluemix_CLI/bin/ibmcloud /usr/local/bin/ibmcloud \
    && rm -rf /tmp/ibmcloud.tar.gz /tmp/Bluemix_CLI \
    # fzf (resolve version — asset name contains version)
    && FZF_VERSION=$(ghlatest junegunn/fzf) \
    && curl ${CURL_RETRY} -fsSL \
      "https://github.com/junegunn/fzf/releases/latest/download/fzf-${FZF_VERSION}-linux_${DPKG_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin fzf \
    # hadolint (latest — version-free asset name)
    && if [ "$DPKG_ARCH" = "amd64" ]; then HL_ARCH="x86_64"; else HL_ARCH="arm64"; fi \
    && curl ${CURL_RETRY} -fsSLo /usr/local/bin/hadolint \
      "https://github.com/hadolint/hadolint/releases/latest/download/hadolint-linux-${HL_ARCH}" \
    && chmod +x /usr/local/bin/hadolint \
    # codex (latest — version-free asset name, self-updates at runtime)
    && if [ "$DPKG_ARCH" = "amd64" ]; then CODEX_ARCH="x86_64"; else CODEX_ARCH="aarch64"; fi \
    && curl ${CURL_RETRY} -fsSL \
      "https://github.com/openai/codex/releases/latest/download/codex-${CODEX_ARCH}-unknown-linux-gnu.tar.gz" \
      | tar -xz -C /usr/local/bin \
    && mv /usr/local/bin/codex-${CODEX_ARCH}-unknown-linux-gnu /usr/local/bin/codex \
    && chmod +x /usr/local/bin/codex \
    && chown ${USERNAME}:${USERNAME} /usr/local/bin/codex \
    # gogcli (resolve version — asset name contains version)
    && GOGCLI_VERSION=$(ghlatest steipete/gogcli) \
    && curl ${CURL_RETRY} -fsSL "https://github.com/steipete/gogcli/releases/latest/download/gogcli_${GOGCLI_VERSION}_linux_${DPKG_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin gog

# ============================================================
# 10c. iTerm2 terminal image utilities
#      Standalone scripts — display images, transfer files,
#      and copy to clipboard via OSC 1337 escape sequences.
# ============================================================
# hadolint ignore=DL3059
RUN for util in imgcat imgls it2dl it2ul it2copy it2check; do \
      curl ${CURL_RETRY} -fsSL "https://iterm2.com/utilities/${util}" \
        -o "/usr/local/bin/${util}" \
      && chmod +x "/usr/local/bin/${util}"; \
    done

# ============================================================
# 10d. Super-linter binary tools (linters + formatters)
#      All resolve latest versions at build time.
# ============================================================
# hadolint ignore=DL3059
RUN ghlatest() { curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's|.*/||;s|^v||'; } \
    && DPKG_ARCH=$(dpkg --print-architecture) && UNAME_ARCH=$(uname -m) \
    # shfmt (version in asset name)
    && SHFMT_VERSION=$(ghlatest mvdan/sh) \
    && curl ${CURL_RETRY} -fsSLo /usr/local/bin/shfmt \
      "https://github.com/mvdan/sh/releases/latest/download/shfmt_v${SHFMT_VERSION}_linux_${DPKG_ARCH}" \
    && chmod +x /usr/local/bin/shfmt \
    # gitleaks (assets use x64/arm64, not amd64/arm64)
    && GITLEAKS_VERSION=$(ghlatest gitleaks/gitleaks) \
    && if [ "$DPKG_ARCH" = "amd64" ]; then GL_ARCH="x64"; else GL_ARCH="arm64"; fi \
    && curl ${CURL_RETRY} -fsSL "https://github.com/gitleaks/gitleaks/releases/latest/download/gitleaks_${GITLEAKS_VERSION}_linux_${GL_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin gitleaks \
    # editorconfig-checker (version-free asset; binary is bin/ec-linux-<arch>)
    && curl ${CURL_RETRY} -fsSL "https://github.com/editorconfig-checker/editorconfig-checker/releases/latest/download/ec-linux-${DPKG_ARCH}.tar.gz" \
      | tar -xz --strip-components=1 -C /usr/local/bin "bin/ec-linux-${DPKG_ARCH}" \
    && mv /usr/local/bin/ec-linux-${DPKG_ARCH} /usr/local/bin/editorconfig-checker \
    # clj-kondo
    && CLJ_KONDO_VERSION=$(ghlatest clj-kondo/clj-kondo) \
    && if [ "$DPKG_ARCH" = "amd64" ]; then CK_ARCH="amd64"; else CK_ARCH="aarch64"; fi \
    && curl ${CURL_RETRY} -fsSL "https://github.com/clj-kondo/clj-kondo/releases/latest/download/clj-kondo-${CLJ_KONDO_VERSION}-linux-${CK_ARCH}.zip" \
      -o /tmp/clj-kondo.zip \
    && unzip -q /tmp/clj-kondo.zip -d /usr/local/bin && rm /tmp/clj-kondo.zip \
    # dotenv-linter
    && if [ "$UNAME_ARCH" = "x86_64" ]; then DL_ARCH="x86_64"; else DL_ARCH="aarch64"; fi \
    && curl ${CURL_RETRY} -fsSL "https://github.com/dotenv-linter/dotenv-linter/releases/latest/download/dotenv-linter-linux-${DL_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin dotenv-linter \
    # gopls (Go LSP server)
    && GOBIN=/usr/local/bin go install golang.org/x/tools/gopls@v0.21.1 \
    # golangci-lint (install script auto-detects arch)
    && curl ${CURL_RETRY} -sSfL https://golangci-lint.run/install.sh | sh -s -- -b /usr/local/bin \
    # goreleaser
    && if [ "$UNAME_ARCH" = "x86_64" ]; then GR_ARCH="x86_64"; else GR_ARCH="arm64"; fi \
    && curl ${CURL_RETRY} -fsSL "https://github.com/goreleaser/goreleaser/releases/latest/download/goreleaser_Linux_${GR_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin goreleaser \
    # kubeconform (version-free asset)
    && curl ${CURL_RETRY} -fsSL "https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-${DPKG_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin kubeconform \
    # kustomize (install script handles special tag format)
    && curl ${CURL_RETRY} -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash \
    && mv kustomize /usr/local/bin/ \
    # protolint (version in asset name)
    && PROTOLINT_VERSION=$(ghlatest yoheimuta/protolint) \
    && curl ${CURL_RETRY} -fsSL "https://github.com/yoheimuta/protolint/releases/latest/download/protolint_${PROTOLINT_VERSION}_linux_${DPKG_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin protolint \
    # scalafmt (native binary — different asset names per arch)
    && if [ "$DPKG_ARCH" = "amd64" ]; then \
      curl ${CURL_RETRY} -fsSLo /usr/local/bin/scalafmt \
        "https://github.com/scalameta/scalafmt/releases/latest/download/scalafmt-linux-glibc"; \
    else \
      curl ${CURL_RETRY} -fsSL "https://github.com/scalameta/scalafmt/releases/latest/download/scalafmt-aarch64-pc-linux.zip" \
        -o /tmp/scalafmt.zip \
      && unzip -q /tmp/scalafmt.zip -d /usr/local/bin && rm /tmp/scalafmt.zip; \
    fi \
    && chmod +x /usr/local/bin/scalafmt \
    # ktlint (runnable JAR — arch-independent, needs Java)
    && curl ${CURL_RETRY} -fsSLo /usr/local/bin/ktlint \
      "https://github.com/pinterest/ktlint/releases/latest/download/ktlint" \
    && chmod +x /usr/local/bin/ktlint \
    # cljfmt (GraalVM native binary — Clojure formatter)
    && CLJFMT_VERSION=$(ghlatest weavejester/cljfmt) \
    && if [ "$DPKG_ARCH" = "amd64" ]; then CLJFMT_ARCH="amd64-static"; else CLJFMT_ARCH="aarch64"; fi \
    && curl ${CURL_RETRY} -fsSL "https://github.com/weavejester/cljfmt/releases/latest/download/cljfmt-${CLJFMT_VERSION}-linux-${CLJFMT_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin cljfmt \
    # gleam (static musl binary — Gleam formatter)
    && GLEAM_VERSION=$(ghlatest gleam-lang/gleam) \
    && curl ${CURL_RETRY} -fsSL "https://github.com/gleam-lang/gleam/releases/latest/download/gleam-v${GLEAM_VERSION}-${UNAME_ARCH}-unknown-linux-musl.tar.gz" \
      | tar -xz -C /usr/local/bin gleam

# ============================================================
# 10d. Java JAR tools (checkstyle, google-java-format)
#      Wrapper scripts in /usr/local/bin, JARs in /opt/
# ============================================================
# hadolint ignore=DL3059
RUN ghlatest() { curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's|.*/||;s|^v||'; } \
    # checkstyle (tag is "checkstyle-X.Y.Z" — strip the prefix)
    && CHECKSTYLE_VERSION=$(ghlatest checkstyle/checkstyle | sed 's/^checkstyle-//') \
    && curl ${CURL_RETRY} -fsSL \
      "https://github.com/checkstyle/checkstyle/releases/latest/download/checkstyle-${CHECKSTYLE_VERSION}-all.jar" \
      -o /opt/checkstyle.jar \
    && printf '#!/bin/sh\nexec java -jar /opt/checkstyle.jar "$@"\n' > /usr/local/bin/checkstyle \
    && chmod +x /usr/local/bin/checkstyle \
    # google-java-format
    && GJF_VERSION=$(ghlatest google/google-java-format) \
    && curl ${CURL_RETRY} -fsSL \
      "https://github.com/google/google-java-format/releases/latest/download/google-java-format-${GJF_VERSION}-all-deps.jar" \
      -o /opt/google-java-format.jar \
    && printf '#!/bin/sh\nexec java -jar /opt/google-java-format.jar "$@"\n' > /usr/local/bin/google-java-format \
    && chmod +x /usr/local/bin/google-java-format \
    # BFG Repo Cleaner (git history rewriting)
    && BFG_VERSION=$(ghlatest rtyley/bfg-repo-cleaner) \
    && curl ${CURL_RETRY} -fsSL \
      "https://repo1.maven.org/maven2/com/madgag/bfg/${BFG_VERSION}/bfg-${BFG_VERSION}.jar" \
      -o /opt/bfg.jar \
    && printf '#!/bin/sh\nexec java -jar /opt/bfg.jar "$@"\n' > /usr/local/bin/bfg \
    && chmod +x /usr/local/bin/bfg

# ============================================================
# 10e. PHP linters (PHAR downloads — requires php-cli from APT)
# ============================================================
# hadolint ignore=DL3059
RUN curl ${CURL_RETRY} -fsSLo /usr/local/bin/phpcs \
      "https://github.com/PHPCSStandards/PHP_CodeSniffer/releases/latest/download/phpcs.phar" \
    && chmod +x /usr/local/bin/phpcs \
    && curl ${CURL_RETRY} -fsSLo /usr/local/bin/phpstan \
      "https://github.com/phpstan/phpstan/releases/latest/download/phpstan.phar" \
    && chmod +x /usr/local/bin/phpstan \
    && curl ${CURL_RETRY} -fsSLo /usr/local/bin/psalm \
      "https://github.com/vimeo/psalm/releases/latest/download/psalm.phar" \
    && chmod +x /usr/local/bin/psalm \
    # pint (Laravel PHP formatter — PHAR download, NOT the Homebrew "pint")
    && curl ${CURL_RETRY} -fsSLo /usr/local/bin/pint \
      "https://github.com/laravel/pint/releases/latest/download/pint.phar" \
    && chmod +x /usr/local/bin/pint

# ============================================================
# 10f. PowerShell modules (PSScriptAnalyzer + arm-ttk)
# ============================================================
# hadolint ignore=DL3059
RUN pwsh -NoProfile -Command 'Set-PSRepository PSGallery -InstallationPolicy Trusted; Install-Module -Name PSScriptAnalyzer -Scope AllUsers -Force' \
    && git clone --depth=1 https://github.com/Azure/arm-ttk.git /usr/lib/microsoft/arm-ttk \
    && rm -rf /usr/lib/microsoft/arm-ttk/.git
ENV ARM_TTK_PSD1="/usr/lib/microsoft/arm-ttk/arm-ttk/arm-ttk.psd1"
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1

# ============================================================
# 10g. Security binary tools (pentest & recon)
#      All resolve latest versions at build time.
# ============================================================
# hadolint ignore=DL3003,DL3059
RUN ghlatest() { curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's|.*/||;s|^v||'; } \
    && DPKG_ARCH=$(dpkg --print-architecture) && UNAME_ARCH=$(uname -m) \
    # --- Recon: ProjectDiscovery suite ---
    && NUCLEI_VERSION=$(ghlatest projectdiscovery/nuclei) \
    && curl ${CURL_RETRY} -fsSL "https://github.com/projectdiscovery/nuclei/releases/download/v${NUCLEI_VERSION}/nuclei_${NUCLEI_VERSION}_linux_${DPKG_ARCH}.zip" \
      -o /tmp/nuclei.zip \
    && unzip -oq /tmp/nuclei.zip -d /usr/local/bin && rm /tmp/nuclei.zip \
    && SUBFINDER_VERSION=$(ghlatest projectdiscovery/subfinder) \
    && curl ${CURL_RETRY} -fsSL "https://github.com/projectdiscovery/subfinder/releases/download/v${SUBFINDER_VERSION}/subfinder_${SUBFINDER_VERSION}_linux_${DPKG_ARCH}.zip" \
      -o /tmp/subfinder.zip \
    && unzip -oq /tmp/subfinder.zip -d /usr/local/bin && rm /tmp/subfinder.zip \
    && HTTPX_VERSION=$(ghlatest projectdiscovery/httpx) \
    && curl ${CURL_RETRY} -fsSL "https://github.com/projectdiscovery/httpx/releases/download/v${HTTPX_VERSION}/httpx_${HTTPX_VERSION}_linux_${DPKG_ARCH}.zip" \
      -o /tmp/httpx.zip \
    && unzip -oq /tmp/httpx.zip -d /usr/local/bin && rm /tmp/httpx.zip \
    # --- Web fuzzing ---
    && FFUF_VERSION=$(ghlatest ffuf/ffuf) \
    && curl ${CURL_RETRY} -fsSL "https://github.com/ffuf/ffuf/releases/download/v${FFUF_VERSION}/ffuf_${FFUF_VERSION}_linux_${DPKG_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin ffuf \
    && if [ "$UNAME_ARCH" = "x86_64" ]; then GB_ARCH="x86_64"; else GB_ARCH="arm64"; fi \
    && curl ${CURL_RETRY} -fsSL "https://github.com/OJ/gobuster/releases/latest/download/gobuster_Linux_${GB_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin gobuster \
    && if [ "$DPKG_ARCH" = "amd64" ]; then \
      curl ${CURL_RETRY} -fsSL "https://github.com/epi052/feroxbuster/releases/latest/download/x86_64-linux-feroxbuster.tar.gz" \
        | tar -xz -C /usr/local/bin feroxbuster; \
    else \
      curl ${CURL_RETRY} -fsSL "https://github.com/epi052/feroxbuster/releases/latest/download/aarch64-linux-feroxbuster.zip" \
        -o /tmp/feroxbuster.zip \
      && unzip -oq /tmp/feroxbuster.zip -d /usr/local/bin && rm /tmp/feroxbuster.zip; \
    fi \
    && chmod +x /usr/local/bin/feroxbuster \
    # --- XSS scanner (binary is named dalfox-linux-ARCH inside archive) ---
    && curl ${CURL_RETRY} -fsSL "https://github.com/hahwul/dalfox/releases/latest/download/dalfox-linux-${DPKG_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin \
    && mv /usr/local/bin/dalfox-linux-${DPKG_ARCH} /usr/local/bin/dalfox \
    # --- Domain & URL enumeration (extract only the binary) ---
    && curl ${CURL_RETRY} -fsSL "https://github.com/owasp-amass/amass/releases/latest/download/amass_linux_${DPKG_ARCH}.tar.gz" \
      | tar -xz --strip-components=1 -C /usr/local/bin "amass_linux_${DPKG_ARCH}/amass" \
    && GAU_VERSION=$(ghlatest lc/gau) \
    && curl ${CURL_RETRY} -fsSL "https://github.com/lc/gau/releases/download/v${GAU_VERSION}/gau_${GAU_VERSION}_linux_${DPKG_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin gau \
    && if [ "$DPKG_ARCH" = "amd64" ]; then \
      WAYBACK_VERSION=$(ghlatest tomnomnom/waybackurls) \
      && curl ${CURL_RETRY} -fsSL "https://github.com/tomnomnom/waybackurls/releases/download/v${WAYBACK_VERSION}/waybackurls-linux-amd64-${WAYBACK_VERSION}.tgz" \
        | tar -xz -C /usr/local/bin waybackurls; \
    fi \
    # --- Supply chain & secret scanning ---
    && TRUFFLEHOG_VERSION=$(ghlatest trufflesecurity/trufflehog) \
    && curl ${CURL_RETRY} -fsSL "https://github.com/trufflesecurity/trufflehog/releases/download/v${TRUFFLEHOG_VERSION}/trufflehog_${TRUFFLEHOG_VERSION}_linux_${DPKG_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin trufflehog \
    && GRYPE_VERSION=$(ghlatest anchore/grype) \
    && curl ${CURL_RETRY} -fsSL "https://github.com/anchore/grype/releases/download/v${GRYPE_VERSION}/grype_${GRYPE_VERSION}_linux_${DPKG_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin grype \
    && SYFT_VERSION=$(ghlatest anchore/syft) \
    && curl ${CURL_RETRY} -fsSL "https://github.com/anchore/syft/releases/download/v${SYFT_VERSION}/syft_${SYFT_VERSION}_linux_${DPKG_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin syft \
    # --- Kubernetes security ---
    && KUBEBENCH_VERSION=$(ghlatest aquasecurity/kube-bench) \
    && curl ${CURL_RETRY} -fsSL "https://github.com/aquasecurity/kube-bench/releases/download/v${KUBEBENCH_VERSION}/kube-bench_${KUBEBENCH_VERSION}_linux_${DPKG_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin kube-bench \
    # --- Network attack (amd64 only) ---
    && if [ "$DPKG_ARCH" = "amd64" ]; then \
      curl ${CURL_RETRY} -fsSL "https://github.com/bettercap/bettercap/releases/latest/download/bettercap_linux_amd64.zip" \
        -o /tmp/bettercap.zip \
      && unzip -oq /tmp/bettercap.zip -d /usr/local/bin && rm /tmp/bettercap.zip \
      && chmod +x /usr/local/bin/bettercap; \
    fi \
    # --- OSINT: cloud & IP recon (go install) ---
    && GOBIN=/usr/local/bin go install github.com/jreisinger/checkip@v0.49.0 \
    && GOBIN=/usr/local/bin go install github.com/Macmod/goblob@v1.2.2 \
    && git clone --depth=1 --branch v2.0 https://github.com/redhuntlabs/bucketloot.git /tmp/bucketloot \
    && go build -C /tmp/bucketloot -o /usr/local/bin/bucketloot . && rm -rf /tmp/bucketloot \
    && rm -f /usr/local/bin/LICENSE* /usr/local/bin/README*

# ============================================================
# 10g-ii. Tirith — terminal security (homograph/injection guard)
# ============================================================
# hadolint ignore=DL3059
RUN DPKG_ARCH=$(dpkg --print-architecture) \
    && if [ "$DPKG_ARCH" = "amd64" ]; then TIRITH_ARCH="x86_64-unknown-linux-gnu"; \
      else TIRITH_ARCH="aarch64-unknown-linux-gnu"; fi \
    && curl ${CURL_RETRY} -fsSL "https://github.com/sheeki03/tirith/releases/latest/download/tirith-${TIRITH_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin tirith

# ============================================================
# 10h. OWASP ZAP (web app scanner — replaces Burp Suite)
#      Java app, arch-independent. Runs headless or via VNC.
# ============================================================
# hadolint ignore=DL3059
RUN ghlatest() { curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's|.*/||;s|^v||'; } \
    && ZAP_VERSION=$(ghlatest zaproxy/zaproxy) \
    && curl ${CURL_RETRY} -fsSL "https://github.com/zaproxy/zaproxy/releases/latest/download/ZAP_${ZAP_VERSION}_Linux.tar.gz" \
      | tar -xz -C /opt \
    && mv /opt/ZAP_${ZAP_VERSION} /opt/zaproxy \
    && printf '#!/bin/sh\nexec /opt/zaproxy/zap.sh "$@"\n' > /usr/local/bin/zap \
    && chmod +x /usr/local/bin/zap

# ============================================================
# 10i. Ghidra (reverse engineering framework — ~1.3 GB)
#      Java app, arch-independent. GUI via VNC or headless.
# ============================================================
# hadolint ignore=DL3059
RUN curl ${CURL_RETRY} -fsSL \
      "https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_${GHIDRA_VERSION}_build/ghidra_${GHIDRA_VERSION}_PUBLIC_${GHIDRA_DATE}.zip" \
      -o /tmp/ghidra.zip \
    && unzip -q /tmp/ghidra.zip -d /opt \
    && mv /opt/ghidra_* /opt/ghidra \
    && rm /tmp/ghidra.zip \
    && printf '#!/bin/sh\nexec /opt/ghidra/ghidraRun "$@"\n' > /usr/local/bin/ghidra \
    && chmod +x /usr/local/bin/ghidra

# ============================================================
# 10j. Metasploit Framework (amd64 only — ~1.2 GB)
#      ARM64 has known installer issues on Ubuntu 24.04.
# ============================================================
# hadolint ignore=DL3059
RUN if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
      curl ${CURL_RETRY} -fsSL https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb \
        > /tmp/msfinstall \
      && chmod +x /tmp/msfinstall \
      && /tmp/msfinstall \
      && rm /tmp/msfinstall; \
    fi

# ============================================================
# 10k. Language server binaries (LSP)
#      Pre-installed for faster editor startup. All resolve
#      latest versions at build time.
# ============================================================
# hadolint ignore=DL3059
RUN ghlatest() { curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's|.*/||;s|^v||'; } \
    && DPKG_ARCH=$(dpkg --print-architecture) && UNAME_ARCH=$(uname -m) \
    # marksman (Markdown/MDX LSP — self-contained binary, no runtime deps)
    && if [ "$DPKG_ARCH" = "amd64" ]; then MK_ARCH="x64"; else MK_ARCH="arm64"; fi \
    && curl ${CURL_RETRY} -fsSLo /usr/local/bin/marksman \
      "https://github.com/artempyanykh/marksman/releases/latest/download/marksman-linux-${MK_ARCH}" \
    && chmod +x /usr/local/bin/marksman \
    # terraform-ls (Terraform LSP — distributed via releases.hashicorp.com)
    && TFLS_VERSION=$(ghlatest hashicorp/terraform-ls) \
    && curl ${CURL_RETRY} -fsSL \
      "https://releases.hashicorp.com/terraform-ls/${TFLS_VERSION}/terraform-ls_${TFLS_VERSION}_linux_${DPKG_ARCH}.zip" \
      -o /tmp/terraform-ls.zip \
    && unzip -q /tmp/terraform-ls.zip -d /usr/local/bin && rm /tmp/terraform-ls.zip \
    # taplo (TOML LSP — gzip'd binary)
    && if [ "$UNAME_ARCH" = "x86_64" ]; then TAPLO_ARCH="x86_64"; else TAPLO_ARCH="aarch64"; fi \
    && curl ${CURL_RETRY} -fsSL \
      "https://github.com/tamasfe/taplo/releases/latest/download/taplo-linux-${TAPLO_ARCH}.gz" \
      | gzip -d > /usr/local/bin/taplo \
    && chmod +x /usr/local/bin/taplo \
    # jdtls (Eclipse JDT Language Server for Java — Python wrapper + plugin jars)
    && JDTLS_TARBALL=$(curl ${CURL_RETRY} -fsSL \
      "https://download.eclipse.org/jdtls/milestones/1.57.0/latest.txt") \
    && mkdir -p /opt/jdtls \
    && curl ${CURL_RETRY} -fsSL \
      "https://download.eclipse.org/jdtls/milestones/1.57.0/${JDTLS_TARBALL}" \
      | tar xzf - --no-same-owner -C /opt/jdtls \
    && chmod +x /opt/jdtls/bin/jdtls \
    && ln -s /opt/jdtls/bin/jdtls /usr/local/bin/jdtls

# ============================================================
# 10l-2. C# language server (csharp-ls via dotnet global tool)
# ============================================================
# hadolint ignore=DL3059
RUN dotnet tool install --global csharp-ls --version 0.16.0 \
    && ln -sf /home/vscode/.dotnet/tools/csharp-ls /usr/local/bin/csharp-ls

# ============================================================
# 10l. Zig cross-compilation toolchain (needed by napi-rs
#      for native addon builds in the Firecrawl section).
# ============================================================
# hadolint ignore=DL3059
RUN UNAME_ARCH=$(uname -m) \
    && curl ${CURL_RETRY} -fsSL \
      "https://ziglang.org/download/${ZIG_VERSION}/zig-${UNAME_ARCH}-linux-${ZIG_VERSION}.tar.xz" \
      | tar -xJ -C /opt \
    && ln -s "/opt/zig-${UNAME_ARCH}-linux-${ZIG_VERSION}/zig" /usr/local/bin/zig

# ============================================================
# 11. npm global tools
# ============================================================
# hadolint ignore=DL3016,DL3059
RUN npm install -g \
    pnpm \
    @anthropic-ai/claude-code \
    @mariozechner/pi-coding-agent \
    @oh-my-pi/pi-coding-agent \
    @f5xc-salesdemos/xcsh \
    prettier \
    markdownlint-cli2 \
    @devcontainers/cli \
    @googleworkspace/cli \
    html2canvas \
    @playwright/cli \
    playwright \
    grammy \
    @whiskeysockets/baileys \
    discord.js \
    pdfjs-dist \
    @napi-rs/canvas \
    matrix-js-sdk \
    puppeteer \
    puppeteer-extra \
    puppeteer-extra-plugin-stealth \
    eslint \
    @biomejs/biome \
    stylelint \
    htmlhint \
    "textlint@<15.5.3" \
    textlint-rule-terminology \
    jscpd \
    @coffeelint/cli \
    npm-groovy-lint \
    @stoplight/spectral-cli \
    gplint \
    @ibm/tekton-lint \
    asl-validator \
    renovate \
    markdownlint-cli \
    asciinema-player \
    yaml-language-server \
    bash-language-server \
    @mdx-js/language-server \
    typescript-language-server \
    typescript \
    @typescript/native-preview \
    pyright \
    vscode-langservers-extracted \
    intelephense \
    pptxgenjs \
    react-icons \
    react \
    react-dom \
    sharp \
    opencode-ai \
    opencode-claude-auth \
    js-deobfuscator

# Ensure Node.js can resolve globally-installed packages at the system prefix
# even after npm prefix is changed to $HOME/.npm-global later.
ENV NODE_PATH=/usr/lib/node_modules

# ============================================================
# 11a. Firecrawl — self-hosted web scraper (API on port 3002)
#      Requires Redis + PostgreSQL (started in entrypoint.sh).
# ============================================================
# hadolint ignore=DL3059
RUN git clone --depth=1 https://github.com/mendableai/firecrawl.git /opt/firecrawl

WORKDIR /opt/firecrawl/apps/api
# hadolint ignore=DL3059
RUN pnpm install --ignore-scripts

WORKDIR /opt/firecrawl/apps/api/node_modules/@mendable/firecrawl-rs
# hadolint ignore=DL3059
RUN npx napi build --platform --release

WORKDIR /opt/firecrawl/apps/api
# hadolint ignore=DL3059
RUN npx tsc

WORKDIR /opt/firecrawl/apps/playwright-service-ts
# hadolint ignore=DL3059
RUN pnpm install --ignore-scripts && npx tsc \
    && PLAYWRIGHT_BROWSERS_PATH=/home/vscode/.cache/ms-playwright npx playwright install chromium

# hadolint ignore=DL3059
RUN rm -rf /opt/firecrawl/.git

WORKDIR /

# Relax PostgreSQL auth for local socket connections (entrypoint manages lifecycle)
# hadolint ignore=DL3059
RUN PG_HBA=$(find /etc/postgresql -name pg_hba.conf -print -quit 2>/dev/null) \
    && if [ -n "$PG_HBA" ]; then \
        sed -i 's/peer/trust/g; s/scram-sha-256/trust/g' "$PG_HBA"; \
      fi

# ============================================================
# 12. pip tools
# ============================================================
# --ignore-installed: VNC deps (novnc, x11vnc) pull in Debian python3
# packages without pip RECORD files (typing_extensions, packaging, etc.).
# pip cannot upgrade these normally, so we skip the uninstall check.
# hadolint ignore=DL3013,DL3059
RUN pip install --no-cache-dir --break-system-packages --ignore-installed --root-user-action=ignore \
    "cryptography>=43,<47" \
    "pyopenssl>=24.3,<=25.3.0" \
    "packaging>=24,<26" \
    "boto3>=1.34" \
    tzdata \
    pre-commit \
    ansible \
    black \
    pylint \
    yamllint \
    playwright \
    playwright-stealth \
    undetected-chromedriver \
    nodriver \
    browserforge \
    "markitdown[all]" \
    python-pptx \
    progressbar2 \
    ansible-lint \
    cfn-lint \
    cpplint \
    flake8 \
    isort \
    mypy \
    pyink \
    ruff \
    snakefmt \
    snakemake \
    sqlfluff \
    codespell \
    git-filter-repo \
    zizmor \
    nbqa \
    mitreattack-python \
    # Recon (recon-ng, spiderfoot installed via git clone below)
    theHarvester \
    asciinema \
    aiohappyeyeballs \
    aiohttp \
    aiosignal \
    frozenlist \
    multidict \
    propcache \
    tabulate \
    yarl

# ============================================================
# 12a. OSINT Framework pip tools (osint-framework plugin)
#      Username, email, domain, cloud, threat-intel, mobile,
#      social, media, and forensic investigation tools.
# ============================================================
# hadolint ignore=DL3013,DL3059
RUN pip install --no-cache-dir --break-system-packages --ignore-installed --root-user-action=ignore \
    # Username & email recon
    sherlock-project \
    maigret \
    holehe \
    h8mail \
    sylva \
    # Domain & network recon
    dnsrecon \
    sublist3r \
    scanless \
    # Cloud security
    scoutsuite \
    c7n \
    roadrecon \
    # Threat intelligence
    iocextract \
    ioc_parser \
    pymisp \
    # Malware & file analysis
    oletools \
    pdfid \
    quicksand \
    # Mobile & app analysis
    apkleaks \
    frida-tools \
    # Social & messaging
    masto \
    wechatsogou \
    linelog2py \
    xeuledoc \
    # Media & archives
    waybackpack \
    dfir-unfurl \
    # Dark web
    torbot

# Security & pentest pip packages.
# Installed in isolated groups because mitmproxy, sslyze, impacket,
# and prowler pull conflicting cryptography/pyOpenSSL versions.
# A single pip install triggers massive resolver backtracking that
# downgrades zstandard (Python 3.13 cffi issue) or mitmproxy (ancient
# urwid with use_2to3).  Separate installs let each resolve cleanly.
# --ignore-installed: Debian system packages (blinker, etc.) lack
# pip RECORD files and block uninstall.
# hadolint ignore=DL3013,DL3059
RUN pip install --no-cache-dir --break-system-packages --ignore-installed --root-user-action=ignore \
    scapy impacket arjun hashid \
    && pip install --no-cache-dir --break-system-packages --ignore-installed --root-user-action=ignore \
    pwntools volatility3 "packaging>=24,<26"

# uv-isolated tools (notebooklm-mcp-cli, checkov, prowler, fierce)
# checkov requires Python <3.13 (FileType.JSON AttributeError on 3.13).
# prowler pins pydantic==1.x, boto3==1.26 — incompatible with global env.
# fierce pins dnspython==1.16.0 — incompatible with global dnspython 2.x.
# hadolint ignore=DL3059
RUN UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin \
    uv tool install notebooklm-mcp-cli \
    && UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin \
    uv tool install --python python3.12 checkov \
    && (UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin \
    uv tool install prowler 2>&1 | grep -v "missing.*RECORD") \
    && UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin \
    uv tool install fierce \
    && UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin \
    uv tool install mitmproxy \
    && UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin \
    uv tool install kube-hunter \
    && UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin \
    uv tool install sslyze

# signal-cli (Signal messenger CLI — Java application)
# hadolint ignore=DL3059
RUN SIGNAL_CLI_VERSION="0.14.1" \
    && curl -fsSL "https://github.com/AsamK/signal-cli/releases/download/v${SIGNAL_CLI_VERSION}/signal-cli-${SIGNAL_CLI_VERSION}.tar.gz" \
      -o /tmp/signal-cli.tar.gz \
    && tar xf /tmp/signal-cli.tar.gz -C /opt \
    && ln -sf "/opt/signal-cli-${SIGNAL_CLI_VERSION}/bin/signal-cli" /usr/local/bin/signal-cli \
    && rm /tmp/signal-cli.tar.gz

# ============================================================
# 12c. Ruby linters (rubocop + extensions)
# ============================================================
# hadolint ignore=DL3028,DL3059
RUN gem install --no-document \
    rubocop \
    rubocop-performance \
    rubocop-rails \
    rubocop-rake \
    rubocop-rspec \
    rubocop-minitest \
    htmlbeautifier \
    standardrb \
    origami \
    ruby-lsp

# ============================================================
# 12e. Perl linter modules (Perl::Critic extensions via cpanm)
#      Core Perl::Critic is from APT (libperl-critic-perl).
# ============================================================
# hadolint ignore=DL3059
RUN cpanm --notest \
    Perl::Critic::Bangs \
    Perl::Critic::Community \
    Perl::Critic::Lax \
    Perl::Critic::More \
    Perl::Critic::StricterSubs \
    Perl::Critic::Tics

# ============================================================
# 12f. Lua linter (luacheck via luarocks)
# ============================================================
# hadolint ignore=DL3059
RUN luarocks install luacheck

# ============================================================
# 12g. R linter (lintr)
# ============================================================
# hadolint ignore=DL3059
RUN Rscript -e 'install.packages(c("lintr", "purrr"), repos="https://cloud.r-project.org")'

# ============================================================
# 12h. Security Ruby gems (wpscan, evil-winrm)
# ============================================================
# hadolint ignore=DL3028,DL3059
RUN gem install --no-document \
    wpscan \
    evil-winrm

# ============================================================
# 12i. Git-cloned security tools (testssl.sh, exploitdb,
#      SecLists, docker-bench-security, recon-ng, spiderfoot)
# ============================================================
# hadolint ignore=DL3059
RUN git clone --depth=1 https://github.com/drwetter/testssl.sh.git /opt/testssl.sh \
    && ln -s /opt/testssl.sh/testssl.sh /usr/local/bin/testssl \
    && git clone --depth=1 https://gitlab.com/exploit-database/exploitdb.git /opt/exploitdb \
    && ln -s /opt/exploitdb/searchsploit /usr/local/bin/searchsploit \
    && git clone --depth=1 https://github.com/danielmiessler/SecLists.git /opt/seclists \
    && git clone --depth=1 https://github.com/docker/docker-bench-security.git /opt/docker-bench-security \
    && ln -s /opt/docker-bench-security/docker-bench-security.sh /usr/local/bin/docker-bench-security \
    # recon-ng and spiderfoot are not on PyPI — install from git
    && git clone --depth=1 https://github.com/lanmaster53/recon-ng.git /opt/recon-ng \
    && pip install --no-cache-dir --break-system-packages --root-user-action=ignore -r /opt/recon-ng/REQUIREMENTS \
    && ln -s /opt/recon-ng/recon-ng /usr/local/bin/recon-ng \
    && git clone --depth=1 https://github.com/smicallef/spiderfoot.git /opt/spiderfoot \
    # Spiderfoot pins lxml>=4.9.2,<5 but lxml 4.x Cython C code is
    # incompatible with Python 3.13 (removed _PyObject_NextNotImplemented,
    # changed _PyLong_AsByteArray).  Strip the <5 upper bound so pip uses
    # the already-installed lxml 6.x cp313 wheel.
    && sed -i 's/lxml>=4\.9\.2,<5/lxml>=4.9.2/' /opt/spiderfoot/requirements.txt \
    && pip install --no-cache-dir --break-system-packages --root-user-action=ignore -r /opt/spiderfoot/requirements.txt \
    && printf '#!/bin/sh\nexec python3 /opt/spiderfoot/sf.py "$@"\n' > /usr/local/bin/spiderfoot \
    && chmod +x /usr/local/bin/spiderfoot \
    && rm -rf /opt/testssl.sh/.git /opt/exploitdb/.git /opt/seclists/.git \
        /opt/docker-bench-security/.git /opt/recon-ng/.git /opt/spiderfoot/.git

# ============================================================
# 12j. ATT&CK Navigator (MITRE threat matrix visualization)
#      Angular app — built at image time, served as static files.
# ============================================================
# hadolint ignore=DL3059
RUN git clone --depth=1 https://github.com/mitre-attack/attack-navigator.git /tmp/attack-navigator

WORKDIR /tmp/attack-navigator/nav-app

# hadolint ignore=DL3059
RUN npm ci --ignore-scripts \
    && NODE_OPTIONS="--max-old-space-size=4096" npx ng build --configuration production 2>&1 | grep -v "chunkSizeWarningLimit" \
    && mkdir -p /opt/attack-navigator \
    && cp -r dist/browser/* /opt/attack-navigator/ \
    && rm -rf /tmp/attack-navigator \
    && printf '#!/bin/sh\necho "ATT&CK Navigator: http://localhost:${1:-4200}"\nexec npx serve /opt/attack-navigator -l ${1:-4200} -s\n' \
      > /usr/local/bin/attack-navigator \
    && chmod +x /usr/local/bin/attack-navigator

WORKDIR /

# ============================================================
# 12k. CALDERA (MITRE adversary emulation platform)
#      Installed in /opt/caldera with isolated Python 3.12 venv.
#      Runs on port 8888 (HTTP) / 8443 (HTTPS).
# ============================================================
# hadolint ignore=DL3059
RUN git clone --depth=1 --recurse-submodules --shallow-submodules \
      https://github.com/mitre/caldera.git /opt/caldera \
    && rm -rf /opt/caldera/.git /opt/caldera/plugins/*/.git

# hadolint ignore=DL3013,DL3059
RUN uv venv --python python3.12 /opt/caldera/.venv \
    && uv pip install --python /opt/caldera/.venv/bin/python \
      -r /opt/caldera/requirements.txt

# Build VueJS frontend (magma plugin) if present
# hadolint ignore=DL3059
RUN if [ -d /opt/caldera/plugins/magma ]; then \
      npm --prefix /opt/caldera/plugins/magma ci \
      && npm --prefix /opt/caldera/plugins/magma run build \
      && rm -rf /opt/caldera/plugins/magma/node_modules; \
    fi

# hadolint ignore=DL3059
RUN printf '#!/bin/sh\ncd /opt/caldera\nexec .venv/bin/python server.py --insecure "$@"\n' \
      > /usr/local/bin/caldera \
    && chmod +x /usr/local/bin/caldera

# ============================================================
# 12n. Hermes Agent (NousResearch — self-improving AI agent)
#      Installed in /opt/hermes-agent using system Python 3.x
#      (requires >=3.11; system Python 3.13 is compatible).
#      Reads OPENAI_BASE_URL + OPENAI_API_KEY from ~/.hermes/.env,
#      ANTHROPIC_TOKEN for Anthropic native auth.
#      Config baked to ~/.hermes/config.yaml (section 17).
# ============================================================
# hadolint ignore=DL3059
RUN git clone --depth=1 --recurse-submodules --shallow-submodules \
      https://github.com/NousResearch/hermes-agent.git /opt/hermes-agent \
    && rm -rf /opt/hermes-agent/.git \
    && (uv pip install --system --break-system-packages \
      -e "/opt/hermes-agent[all]" 2>&1 | grep -v "missing.*RECORD") \
    && npm --prefix /opt/hermes-agent install --ignore-scripts 2>/dev/null || true

# Pre-stage plugin install script and settings for section 12l
COPY claude-config/install-plugins.sh /opt/claude-config/install-plugins.sh
COPY claude-config/settings.json /opt/claude-config/settings.json
RUN chmod +x /opt/claude-config/install-plugins.sh

# ============================================================
# 12l. Claude Code plugins (pre-install from marketplaces)
#      Clones the official and f5xc-salesdemos marketplaces,
#      copies each enabled plugin into the cache, clones
#      superpowers separately, and generates
#      installed_plugins.json so Claude Code treats all
#      plugins as fully installed at first launch.
# ============================================================
# hadolint ignore=DL3059
RUN PLUGIN_BASE="/home/${USERNAME}/.claude/plugins" \
    && mkdir -p "${PLUGIN_BASE}/marketplaces" \
    && git clone --depth=1 --single-branch --branch main \
        https://github.com/anthropics/claude-plugins-official.git \
        "${PLUGIN_BASE}/marketplaces/claude-plugins-official" \
    && git clone --depth=1 --single-branch --branch main \
        https://github.com/f5xc-salesdemos/marketplace.git \
        "${PLUGIN_BASE}/marketplaces/f5xc-salesdemos-marketplace" \
    && git clone --depth=1 --single-branch --branch main \
        https://github.com/thedotmack/claude-mem.git \
        "${PLUGIN_BASE}/marketplaces/thedotmack" \
    && git clone --depth=1 --single-branch --branch main \
        https://github.com/f5xc-salesdemos/codex-plugin-cc.git \
        "${PLUGIN_BASE}/marketplaces/openai-codex" \
    && TS="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" \
    && printf '{"claude-plugins-official":{"source":{"source":"github","repo":"anthropics/claude-plugins-official"},"installLocation":"%s","lastUpdated":"%s","autoUpdate":true},"f5xc-salesdemos-marketplace":{"source":{"source":"github","repo":"f5xc-salesdemos/marketplace"},"installLocation":"%s","lastUpdated":"%s","autoUpdate":true},"thedotmack":{"source":{"source":"github","repo":"thedotmack/claude-mem"},"installLocation":"%s","lastUpdated":"%s","autoUpdate":false},"openai-codex":{"source":{"source":"github","repo":"f5xc-salesdemos/codex-plugin-cc"},"installLocation":"%s","lastUpdated":"%s","autoUpdate":false}}' \
        "${PLUGIN_BASE}/marketplaces/claude-plugins-official" "$TS" \
        "${PLUGIN_BASE}/marketplaces/f5xc-salesdemos-marketplace" "$TS" \
        "${PLUGIN_BASE}/marketplaces/thedotmack" "$TS" \
        "${PLUGIN_BASE}/marketplaces/openai-codex" "$TS" \
        > "${PLUGIN_BASE}/known_marketplaces.json" \
    && printf '{"fetchedAt":"%s","plugins":[]}' "$TS" \
        > "${PLUGIN_BASE}/blocklist.json" \
    && /opt/claude-config/install-plugins.sh \
        "${PLUGIN_BASE}" /opt/claude-config/settings.json \
    && chown -R ${USERNAME}:${USERNAME} "${PLUGIN_BASE}"

# claude-mem runtime dependencies (tree-sitter native parsers + worker)
# hadolint ignore=DL3016,DL3059
RUN CMEM_PKG=$(find /home/${USERNAME}/.claude/plugins/cache/thedotmack/claude-mem \
      -name "package.json" -not -path "*/node_modules/*" -maxdepth 3 -print -quit 2>/dev/null) \
    && if [ -n "$CMEM_PKG" ]; then \
        npm install --legacy-peer-deps --prefix "$(dirname "$CMEM_PKG")"; \
    fi

# 12m. Claude Code skills (git-cloned external skills)
# hadolint ignore=DL3059
RUN git clone --depth=1 --single-branch --branch main \
      https://github.com/zarazhangrui/frontend-slides.git \
      "/home/${USERNAME}/.claude/skills/frontend-slides" \
    && chown -R ${USERNAME}:${USERNAME} "/home/${USERNAME}/.claude"

# 12n. Share Claude Code skills with Codex via ~/.agents/skills symlink
# Codex discovers user skills from ~/.agents/skills/. A whole-directory symlink
# lets both agents share ~/.claude/skills/ as the single source of truth.
# hadolint ignore=DL3059
RUN mkdir -p "/home/${USERNAME}/.agents" \
    && ln -s "/home/${USERNAME}/.claude/skills" "/home/${USERNAME}/.agents/skills" \
    && chown -h ${USERNAME}:${USERNAME} "/home/${USERNAME}/.agents" "/home/${USERNAME}/.agents/skills"

# ============================================================
# 13. Playwright system dependencies (requires root for apt)
# ============================================================
# hadolint ignore=DL3059
RUN npx playwright install-deps

# Fix ownership of dirs created by root under /home/vscode (e.g. .cache from playwright)
# hadolint ignore=DL3059
RUN chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.cache

# ============================================================
# User setup
# ============================================================
USER $USERNAME
WORKDIR /home/$USERNAME

RUN mkdir -p ~/.cache ~/.local/bin ~/.claude ~/.claude/plans ~/.config/nvim \
    ~/.config/opencode \
    ~/.local/share/opencode \
    ~/.config/gogcli \
    ~/.config/gws \
    ~/.codex \
    ~/.pi/agent \
    ~/.omp/agent \
    ~/.xcsh/agent \
    ~/.xcsh/logs \
    ~/.hermes \
    ~/.hermes/cron \
    ~/.hermes/sessions \
    ~/.hermes/logs \
    ~/.hermes/memories \
    ~/.hermes/skills \
    ~/.hermes/hooks \
    ~/.hermes/image_cache \
    ~/.hermes/audio_cache \
    ~/.ssh

# Bun JavaScript runtime and package manager
# hadolint ignore=DL3059
RUN curl -fsSL https://bun.sh/install | bash
USER root
RUN ln -s /home/vscode/.bun/bin/bun /usr/local/bin/bun \
    && ln -s /home/vscode/.bun/bin/bunx /usr/local/bin/bunx
USER $USERNAME

# Install native Claude Code binary (replaces npm package)
# Retry up to 4 times with exponential back-off to handle transient
# CDN 429 rate-limit responses during parallel multi-arch builds.
# hadolint ignore=DL3059
RUN for attempt in 1 2 3 4; do \
      claude install --force && break; \
      echo "claude install attempt $attempt failed, retrying in $((attempt * 15))s..."; \
      sleep "$((attempt * 15))"; \
    done
USER root
RUN npm uninstall -g @anthropic-ai/claude-code
USER $USERNAME

# Playwright Chromium browser binary (runs as vscode — cache to ~/.cache/ms-playwright)
# hadolint ignore=DL3059
RUN (npx playwright install 2>&1 | grep -v "not in your PATH") \
    && playwright-cli install --skills || true
USER root
RUN CHROME_BIN="$(find /home/vscode/.cache/ms-playwright \
        -name chrome -path '*/chromium-*/chrome-linux*/chrome' -print -quit)" \
    && mkdir -p /opt/google/chrome \
    && ln -sf "$CHROME_BIN" /opt/google/chrome/chrome
USER $USERNAME

# Chrome DevTools MCP: pre-cache the package (runs as vscode so npm caches
# to ~/.npm/_npx; --headless is passed via .mcp.json args in each content repo)
# hadolint ignore=DL3059
RUN npm exec chrome-devtools-mcp@0.20.2 -- --version 2>/dev/null || true

# oh-my-opencode (OpenCode plugin system — "ultrawork" / "ulw" command)
# Build-time install uses npx oh-my-opencode for config scaffolding.
# hadolint ignore=DL3059
RUN npx -y oh-my-opencode install --no-tui \
    --claude=max20 --openai=no --gemini=no --copilot=no \
    && rm -f ~/.config/opencode/*.bak.*

# ============================================================
# 14. Language formatters (GitHub binaries + source build)
#     Replaces the previous Homebrew section. Each tool is
#     fetched from its authoritative GitHub release or built
#     from source. Arch-conditional logic handles the two
#     formatters (nixfmt, ormolu) that only publish x86_64
#     Linux binaries — arm64 falls back to Homebrew for those
#     two only.
# ============================================================
ENV FORCE_AUTOUPDATE_PLUGINS=true
ENV PATH="/home/vscode/.local/bin:${PATH}"

USER root
RUN mkdir -p /home/linuxbrew && chown ${USERNAME}:${USERNAME} /home/linuxbrew
USER $USERNAME

# hadolint ignore=DL3059
RUN DPKG_ARCH=$(dpkg --print-architecture) && UNAME_ARCH=$(uname -m) \
    && if [ "$UNAME_ARCH" = "x86_64" ]; then AIR_ARCH="x86_64"; else AIR_ARCH="aarch64"; fi \
    && curl ${CURL_RETRY} -fsSL \
      "https://github.com/posit-dev/air/releases/latest/download/air-${AIR_ARCH}-unknown-linux-gnu.tar.gz" \
      | tar -xz --strip-components=1 -C /tmp "air-${AIR_ARCH}-unknown-linux-gnu/air" \
    \
    && if [ "$UNAME_ARCH" = "x86_64" ]; then OXC_ARCH="x86_64"; else OXC_ARCH="aarch64"; fi \
    && curl ${CURL_RETRY} -fsSL \
      "https://github.com/oxc-project/oxc/releases/latest/download/oxfmt-${OXC_ARCH}-unknown-linux-gnu.tar.gz" \
      | tar -xz -C /tmp \
    \
    && dub fetch dfmt \
    && (dub build dfmt --compiler=ldc2 --build=release 2>&1 | grep -v "Warning Invalid source/import path") \
    && cp "$(find ~/.dub/packages -name dfmt -type f -perm /111 2>/dev/null | head -1)" /tmp/dfmt \
    \
    && if [ "$DPKG_ARCH" = "amd64" ]; then \
      curl ${CURL_RETRY} -fsSL \
        "https://github.com/NixOS/nixfmt/releases/latest/download/nixfmt" \
        -o /tmp/nixfmt \
      && curl ${CURL_RETRY} -fsSL \
        "https://github.com/tweag/ormolu/releases/latest/download/ormolu-x86_64-linux.zip" \
        -o /tmp/ormolu.zip \
      && unzip -qo /tmp/ormolu.zip ormolu -d /tmp \
      && rm /tmp/ormolu.zip; \
    else \
      mkdir -p /home/linuxbrew/.linuxbrew \
      && NONINTERACTIVE=1 /bin/bash -c "$(curl ${CURL_RETRY} -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" 2>&1 | grep -v "is not in your PATH" \
      && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" \
      && brew install nixfmt ormolu \
      && brew cleanup --prune=all -s \
      && cp /home/linuxbrew/.linuxbrew/bin/nixfmt /tmp/nixfmt \
      && cp /home/linuxbrew/.linuxbrew/bin/ormolu /tmp/ormolu; \
    fi

USER root
# hadolint ignore=DL3059
RUN install -m 755 /tmp/air /usr/local/bin/air \
    && UNAME_ARCH=$(uname -m) \
    && if [ "$UNAME_ARCH" = "x86_64" ]; then OXC_ARCH="x86_64"; else OXC_ARCH="aarch64"; fi \
    && install -m 755 "/tmp/oxfmt-${OXC_ARCH}-unknown-linux-gnu" /usr/local/bin/oxfmt \
    && install -m 755 /tmp/dfmt /usr/local/bin/dfmt \
    && install -m 755 /tmp/nixfmt /usr/local/bin/nixfmt \
    && install -m 755 /tmp/ormolu /usr/local/bin/ormolu \
    && rm -f /tmp/air "/tmp/oxfmt-*" /tmp/dfmt /tmp/nixfmt /tmp/ormolu
USER $USERNAME

# ============================================================
# 15. ZSH plugins (oh-my-zsh is pre-installed by devcontainers base)
# ============================================================
# hadolint ignore=DL3059
# checkov:skip=CKV2_DOCKER_1:sudo here is a zsh plugin name in a sed argument, not a system call
RUN ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}" \
    && git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git \
      "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" \
    && git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git \
      "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" \
    && git clone --depth=1 https://github.com/conda-incubator/conda-zsh-completion.git \
      "${ZSH_CUSTOM}/plugins/conda-zsh-completion" \
    && git clone --depth=1 https://github.com/z-shell/zsh-eza.git \
      "${ZSH_CUSTOM}/plugins/zsh-eza" \
    && git clone --depth=1 https://github.com/cda0/zsh-tfenv.git \
      "${ZSH_CUSTOM}/plugins/zsh-tfenv" \
    && mkdir -p "${ZSH_CUSTOM}/plugins/gh-clone-complete" \
    && git clone --depth=1 https://github.com/wbingli/zsh-claudecode-completion.git \
      "${ZSH_CUSTOM}/plugins/zsh-claudecode-completion" \
    && git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
      "${ZSH_CUSTOM}/themes/powerlevel10k" \
    && "${ZSH_CUSTOM}/themes/powerlevel10k/gitstatus/install" \
    && sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$HOME/.zshrc" \
    # Plugin list: common set + ubuntu (Linux-only). macOS INSTALL.md adds iterm2, macos, podman instead.
    && sed -i 's/^plugins=(.*/plugins=(zsh-syntax-highlighting zsh-autosuggestions zsh-interactive-cd jsontools gh gh-clone-complete common-aliases zsh-eza zsh-tfenv conda-zsh-completion z pip terraform fluxcd azure git-auto-fetch helm istioctl kube-ps1 kubectl sudo vscode aws fzf docker history colored-man-pages command-not-found tmux zsh-claudecode-completion dotenv emoji gcloud git pre-commit ubuntu)/' \
      "$HOME/.zshrc" \
    && sed -i 's/^# HYPHEN_INSENSITIVE=.*/HYPHEN_INSENSITIVE="true"/' "$HOME/.zshrc" \
    && sed -i 's/^# COMPLETION_WAITING_DOTS=.*/COMPLETION_WAITING_DOTS="true"/' "$HOME/.zshrc" \
    && sed -i 's/^# HIST_STAMPS=.*/HIST_STAMPS="yyyy-mm-dd"/' "$HOME/.zshrc" \
    && echo 'export HISTSIZE=50000' >> "$HOME/.zshrc" \
    && echo 'export SAVEHIST=50000' >> "$HOME/.zshrc" \
    && echo '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh' >> "$HOME/.zshrc" \
    && echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$HOME/.zshrc" \
    && echo 'alias vim=nvim' >> "$HOME/.zshrc" \
    && echo 'alias codex-exec="codex exec --skip-git-repo-check"' >> "$HOME/.zshrc" \
    && echo 'export LESS="-R -F -X -i -J --mouse"' >> "$HOME/.zshrc" \
    && echo 'export LESSHISTFILE="$HOME/.cache/lesshst"' >> "$HOME/.zshrc" \
    && echo 'export LESSOPEN="|~/.lessfilter %s"' >> "$HOME/.zshrc" \
    && echo 'export MANPAGER="sh -c '\''col -bx | bat -l man -p'\''"' >> "$HOME/.zshrc" \
    && echo 'export BAT_THEME="Coldark-Dark"' >> "$HOME/.zshrc" \
    && echo 'export BROWSER="browsh"' >> "$HOME/.zshrc" \
    && sed -i '/^source \$ZSH\/oh-my-zsh.sh/i export ZSH_DOTENV_PROMPT=false' "$HOME/.zshrc"

# ============================================================
# 16. User shell bootstrap (baked in — eliminates runtime setup)
# ============================================================
# hadolint ignore=DL3059
RUN mkdir -p "$HOME/.npm-global/lib/node_modules" "$HOME/.npm-global/bin" \
    && npm config set prefix "$HOME/.npm-global" \
    # Symlink system-installed typescript into user prefix so that
    # 'npx tsc' resolves the real compiler instead of the deprecated
    # 'tsc' npm stub package ("This is not the tsc command you are
    # looking for"). System packages live at /usr/lib/node_modules
    # but npx only checks the user prefix (~/.npm-global).
    && ln -sf /usr/lib/node_modules/typescript \
              "$HOME/.npm-global/lib/node_modules/typescript" \
    && ln -sf ../lib/node_modules/typescript/bin/tsc \
              "$HOME/.npm-global/bin/tsc" \
    && ln -sf ../lib/node_modules/typescript/bin/tsserver \
              "$HOME/.npm-global/bin/tsserver" \
    && git clone --depth=1 https://github.com/tfutils/tfenv.git "$HOME/.tfenv" \
    && "$HOME/.tfenv/bin/tfenv" install latest \
    && "$HOME/.tfenv/bin/tfenv" use latest \
    && git clone --depth=1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" \
    && zsh -c "autoload -U compinit && compinit" 2>/dev/null || true

# gogcli (gog) native zsh completions (generated from gog help-json schema)
COPY configs/_gog /usr/local/share/zsh/site-functions/_gog
COPY --chown=${USERNAME}:${USERNAME} configs/_gog /home/${USERNAME}/.oh-my-zsh/custom/completions/_gog

COPY --chown=${USERNAME}:${USERNAME} configs/.p10k.zsh /home/${USERNAME}/.p10k.zsh
COPY --chown=${USERNAME}:${USERNAME} \
    configs/gh-clone-complete.plugin.zsh \
    /home/${USERNAME}/.oh-my-zsh/custom/plugins/gh-clone-complete/gh-clone-complete.plugin.zsh
# Neovim plugins (lazy.nvim plugin manager + avante.nvim AI assistant)
COPY --chown=${USERNAME}:${USERNAME} configs/init.lua /home/${USERNAME}/.config/nvim/init.lua
COPY --chown=${USERNAME}:${USERNAME} configs/setup-nvim.sh /tmp/setup-nvim.sh
# hadolint ignore=DL3059
RUN bash /tmp/setup-nvim.sh && rm /tmp/setup-nvim.sh
COPY --chown=${USERNAME}:${USERNAME} configs/.hushlogin /home/${USERNAME}/.hushlogin
COPY --chown=${USERNAME}:${USERNAME} configs/.inputrc /home/${USERNAME}/.inputrc
COPY --chown=${USERNAME}:${USERNAME} configs/.tmux.conf /home/${USERNAME}/.tmux.conf
COPY --chown=${USERNAME}:${USERNAME} configs/.nanorc /home/${USERNAME}/.nanorc
COPY --chown=${USERNAME}:${USERNAME} configs/.lessfilter /home/${USERNAME}/.lessfilter
COPY --chown=${USERNAME}:${USERNAME} configs/.digrc /home/${USERNAME}/.digrc
COPY --chown=${USERNAME}:${USERNAME} configs/.aider.conf.yml /home/${USERNAME}/.aider.conf.yml
RUN chmod +x /home/${USERNAME}/.lessfilter

# ============================================================
# 17. All tool configuration — baked to final paths
#     COPY'd late so config changes rebuild only this thin
#     layer, not Playwright/Homebrew/ZSH (~1 GB).
# ============================================================
USER root

# --- System-wide scripts and managed policy ---
COPY claude-config/self-test.sh /opt/claude-config/self-test.sh
COPY claude-config/CLAUDE.md /etc/claude-code/CLAUDE.md

COPY claude-config/chrome-browser.sh /usr/local/lib/chrome-browser.sh
COPY claude-config/statusline.sh /opt/claude-config/statusline.sh
COPY claude-config/api-key-helper.sh /opt/claude-config/api-key-helper.sh
COPY claude-config/install-plugins.sh /opt/claude-config/install-plugins.sh
COPY claude-config/neutralize-hooks.sh /opt/claude-config/neutralize-hooks.sh
COPY .devcontainer/scripts/post-start.sh /opt/devcontainer/post-start.sh
COPY scripts/nightly-update.sh /opt/devcontainer/nightly-update.sh
RUN chmod +x /opt/claude-config/self-test.sh \
      /usr/local/lib/chrome-browser.sh \
      /opt/claude-config/statusline.sh /opt/claude-config/api-key-helper.sh \
      /opt/claude-config/install-plugins.sh \
      /opt/claude-config/neutralize-hooks.sh \
      /opt/devcontainer/post-start.sh \
      /opt/devcontainer/nightly-update.sh \
    && ln -s /opt/claude-config/self-test.sh /usr/local/bin/claude-self-test \
    && mkdir -p /etc/claude-code/.claude/rules \
    && echo "0 3 * * * /opt/devcontainer/nightly-update.sh" \
      | crontab -u ${USERNAME} -

# --- Claude Code: settings.json + claude.json → final $HOME paths ---
COPY --chown=${USERNAME}:${USERNAME} claude-config/settings.json /home/${USERNAME}/.claude/settings.json
COPY --chown=${USERNAME}:${USERNAME} claude-config/claude.json /home/${USERNAME}/.claude.json
COPY --chown=${USERNAME}:${USERNAME} claude-config/user-CLAUDE.md /home/${USERNAME}/.claude/CLAUDE.md



# --- Codex + Pi + Hermes: bake static defaults ---
COPY --chown=${USERNAME}:${USERNAME} codex-config/config.toml /home/${USERNAME}/.codex/config.toml
COPY --chown=${USERNAME}:${USERNAME} codex-config/sync-agents.sh /opt/codex-config/sync-agents.sh

# 17a. Sync Claude Code plugin agents → Codex .toml format
# Converts ~/.claude/plugins/cache/*/agents/*.md to ~/.codex/agents/*.toml
# so Codex can natively discover the same agents as Claude Code.
# hadolint ignore=DL3059
RUN chmod +x /opt/codex-config/sync-agents.sh \
    && /opt/codex-config/sync-agents.sh
COPY --chown=${USERNAME}:${USERNAME} pi-config/settings.json /home/${USERNAME}/.pi/agent/settings.json
COPY --chown=${USERNAME}:${USERNAME} omp-config/settings.json /home/${USERNAME}/.omp/agent/settings.json
COPY --chown=${USERNAME}:${USERNAME} omp-config/config.yml /home/${USERNAME}/.omp/agent/config.yml
COPY --chown=${USERNAME}:${USERNAME} xcsh-config/config.yml /home/${USERNAME}/.xcsh/agent/config.yml
COPY --chown=${USERNAME}:${USERNAME} opencode-config/opencode.json /home/${USERNAME}/.config/opencode/opencode.json
COPY --chown=${USERNAME}:${USERNAME} opencode-config/oh-my-openagent.json /home/${USERNAME}/.config/opencode/oh-my-openagent.json
COPY --chown=${USERNAME}:${USERNAME} opencode-config/opencode-permissions.json /home/${USERNAME}/.config/opencode/opencode-permissions.json
COPY --chown=${USERNAME}:${USERNAME} hermes-config/config.yaml /home/${USERNAME}/.hermes/config.yaml


# Map CLAUDE_CODE_OAUTH_TOKEN → ANTHROPIC_OAUTH_TOKEN for tools
# that read the Anthropic-native env var (e.g. Pi).
# hadolint ignore=SC2016
RUN printf '#!/bin/bash\nif [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] && [ -z "$ANTHROPIC_OAUTH_TOKEN" ]; then\n  export ANTHROPIC_OAUTH_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN"\nfi\n' \
      > /etc/profile.d/anthropic-oauth.sh \
    && chmod +x /etc/profile.d/anthropic-oauth.sh \
    && printf 'if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] && [ -z "$ANTHROPIC_OAUTH_TOKEN" ]; then\n  export ANTHROPIC_OAUTH_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN"\nfi\n' \
      >> /etc/zsh/zshenv

# ============================================================
# 18. Build fingerprint — bake commit SHA + date into the image
#     so Claude Code can identify its own version at runtime.
# ============================================================
RUN printf 'BUILD_COMMIT=%s\nBUILD_DATE=%s\nIMAGE=ghcr.io/f5xc-salesdemos/devcontainer\nREPO=https://github.com/f5xc-salesdemos/devcontainer\n' \
      "${BUILD_COMMIT}" "${BUILD_DATE}" > /etc/devcontainer-version

# ============================================================
# 19. Entrypoint (absolute last COPY — most volatile file)
# ============================================================
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# chmod the entrypoint and ensure the entire home directory (including hidden
# files/folders created by earlier root-owned stages such as .claude/, .config/,
# .codex/, .pi/, .omp/) is owned by the runtime user.
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}

USER $USERNAME
ENV SHELL=/bin/zsh
WORKDIR /workspace

HEALTHCHECK NONE

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
