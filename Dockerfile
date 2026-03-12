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
ARG JAVA_VERSION=21
ARG MAVEN_VERSION=3.9.9
ARG BROWSH_VERSION=1.8.0

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
    # Mozilla (Firefox ESR — Browsh backend, amd64 only)
    && if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
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
    build-essential pkg-config libssl-dev libffi-dev \
    # Media / utilities
    ffmpeg poppler-utils qrencode \
    # Network tools
    dnsutils net-tools iputils-ping traceroute tcpdump nmap netcat-openbsd \
    # CLI browsers (xdg-open fallback for gh auth login)
    lynx w3m elinks links2 \
    # Tailscale VPN
    tailscale \
    # Shell tools
    bat fd-find ripgrep neovim htop tree tmux file \
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
    lsd \
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
    dotnet-sdk-8.0 \
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
# 2c. Firefox ESR + Browsh (amd64 only — Browsh has no arm64 build)
# ============================================================
# hadolint ignore=DL3008,DL3059
RUN if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
      apt-get update \
      && apt-get install -y --no-install-recommends firefox-esr \
      && curl ${CURL_RETRY} -fsSL \
          "https://github.com/browsh-org/browsh/releases/download/v${BROWSH_VERSION}/browsh_${BROWSH_VERSION}_linux_amd64.deb" \
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
# 5. Rust (system-wide, latest stable — resolved by rustup)
# ============================================================
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH="/usr/local/cargo/bin:${PATH}"
RUN curl ${CURL_RETRY} --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --default-toolchain stable --no-modify-path \
    && rustup component add clippy rustfmt \
    && chmod -R a+rX /usr/local/rustup /usr/local/cargo

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


# ╔════════════════════════════════════════════════════════════╗
# ║  Stage 2: final  (volatile tools + user setup, ~1.5 GB)  ║
# ║  Changes to tools here don't rebuild the deps stage.      ║
# ╚════════════════════════════════════════════════════════════╝
FROM deps AS final

# SHELL doesn't cross FROM boundaries — redeclare for pipefail
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ARGs don't cross FROM boundaries — redeclare what final needs
ARG USERNAME=vscode
ARG IBMCLOUD_VERSION=2.31.0

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
#     act, actionlint, yt-dlp, uv, opencode)
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
    # opencode (already latest)
    && if [ "$UNAME_ARCH" = "x86_64" ]; then OC_ARCH="x64"; else OC_ARCH="arm64"; fi \
    && curl ${CURL_RETRY} -fsSL "https://github.com/anomalyco/opencode/releases/latest/download/opencode-linux-${OC_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin opencode

# ============================================================
# 10b. Additional binary tools (code CLI, oc, yq, terragrunt,
#      ibmcloud, fzf, hadolint, codex)
#      All resolve latest versions at build time except IBM Cloud CLI.
# ============================================================
# hadolint ignore=DL3059
RUN ghlatest() { curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's|.*/||;s|^v||'; } \
    && DPKG_ARCH=$(dpkg --print-architecture) \
    # VS Code CLI (already latest)
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
    && chown ${USERNAME}:${USERNAME} /usr/local/bin/codex

# ============================================================
# 10c. Super-linter binary tools (linters + formatters)
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
    # trivy (install script auto-detects arch)
    && curl ${CURL_RETRY} -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin \
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
# hadolint ignore=DL3059
RUN ghlatest() { curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's|.*/||;s|^v||'; } \
    && DPKG_ARCH=$(dpkg --print-architecture) && UNAME_ARCH=$(uname -m) \
    # --- Recon: ProjectDiscovery suite ---
    && NUCLEI_VERSION=$(ghlatest projectdiscovery/nuclei) \
    && curl ${CURL_RETRY} -fsSL "https://github.com/projectdiscovery/nuclei/releases/latest/download/nuclei_${NUCLEI_VERSION}_linux_${DPKG_ARCH}.zip" \
      -o /tmp/nuclei.zip \
    && unzip -oq /tmp/nuclei.zip -d /usr/local/bin && rm /tmp/nuclei.zip \
    && SUBFINDER_VERSION=$(ghlatest projectdiscovery/subfinder) \
    && curl ${CURL_RETRY} -fsSL "https://github.com/projectdiscovery/subfinder/releases/latest/download/subfinder_${SUBFINDER_VERSION}_linux_${DPKG_ARCH}.zip" \
      -o /tmp/subfinder.zip \
    && unzip -oq /tmp/subfinder.zip -d /usr/local/bin && rm /tmp/subfinder.zip \
    && HTTPX_VERSION=$(ghlatest projectdiscovery/httpx) \
    && curl ${CURL_RETRY} -fsSL "https://github.com/projectdiscovery/httpx/releases/latest/download/httpx_${HTTPX_VERSION}_linux_${DPKG_ARCH}.zip" \
      -o /tmp/httpx.zip \
    && unzip -oq /tmp/httpx.zip -d /usr/local/bin && rm /tmp/httpx.zip \
    # --- Web fuzzing ---
    && FFUF_VERSION=$(ghlatest ffuf/ffuf) \
    && curl ${CURL_RETRY} -fsSL "https://github.com/ffuf/ffuf/releases/latest/download/ffuf_${FFUF_VERSION}_linux_${DPKG_ARCH}.tar.gz" \
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
    && curl ${CURL_RETRY} -fsSL "https://github.com/lc/gau/releases/latest/download/gau_${GAU_VERSION}_linux_${DPKG_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin gau \
    && if [ "$DPKG_ARCH" = "amd64" ]; then \
      WAYBACK_VERSION=$(ghlatest tomnomnom/waybackurls) \
      && curl ${CURL_RETRY} -fsSL "https://github.com/tomnomnom/waybackurls/releases/latest/download/waybackurls-linux-amd64-${WAYBACK_VERSION}.tgz" \
        | tar -xz -C /usr/local/bin waybackurls; \
    fi \
    # --- Supply chain & secret scanning ---
    && TRUFFLEHOG_VERSION=$(ghlatest trufflesecurity/trufflehog) \
    && curl ${CURL_RETRY} -fsSL "https://github.com/trufflesecurity/trufflehog/releases/latest/download/trufflehog_${TRUFFLEHOG_VERSION}_linux_${DPKG_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin trufflehog \
    && GRYPE_VERSION=$(ghlatest anchore/grype) \
    && curl ${CURL_RETRY} -fsSL "https://github.com/anchore/grype/releases/latest/download/grype_${GRYPE_VERSION}_linux_${DPKG_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin grype \
    && SYFT_VERSION=$(ghlatest anchore/syft) \
    && curl ${CURL_RETRY} -fsSL "https://github.com/anchore/syft/releases/latest/download/syft_${SYFT_VERSION}_linux_${DPKG_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin syft \
    # --- Kubernetes security ---
    && KUBEBENCH_VERSION=$(ghlatest aquasecurity/kube-bench) \
    && curl ${CURL_RETRY} -fsSL "https://github.com/aquasecurity/kube-bench/releases/latest/download/kube-bench_${KUBEBENCH_VERSION}_linux_${DPKG_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin kube-bench \
    # --- Network attack (amd64 only) ---
    && if [ "$DPKG_ARCH" = "amd64" ]; then \
      curl ${CURL_RETRY} -fsSL "https://github.com/bettercap/bettercap/releases/latest/download/bettercap_linux_amd64.zip" \
        -o /tmp/bettercap.zip \
      && unzip -oq /tmp/bettercap.zip -d /usr/local/bin && rm /tmp/bettercap.zip \
      && chmod +x /usr/local/bin/bettercap; \
    fi \
    && rm -f /usr/local/bin/LICENSE* /usr/local/bin/README*

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
RUN GHIDRA_ASSET=$(curl -fsSL "https://api.github.com/repos/NationalSecurityAgency/ghidra/releases/latest" \
      | jq -r '.assets[].name | select(endswith(".zip"))') \
    && curl ${CURL_RETRY} -fsSL \
      "https://github.com/NationalSecurityAgency/ghidra/releases/latest/download/${GHIDRA_ASSET}" \
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
# 11. npm global tools
# ============================================================
# hadolint ignore=DL3016,DL3059
RUN npm install -g \
    @anthropic-ai/claude-code \
    @mariozechner/pi-coding-agent \
    prettier \
    markdownlint-cli2 \
    openclaw \
    @devcontainers/cli \
    @googleworkspace/cli \
    html2canvas \
    playwright \
    eslint \
    @biomejs/biome \
    standard \
    ts-standard \
    stylelint \
    htmlhint \
    textlint \
    textlint-rule-terminology \
    jscpd \
    coffeelint \
    npm-groovy-lint \
    @stoplight/spectral-cli \
    gherkin-lint \
    tekton-lint \
    asl-validator \
    renovate \
    markdownlint-cli

# oh-my-opencode (OpenCode plugin system — "ultrawork" / "ulw" command)
# hadolint ignore=DL3059
RUN npx -y oh-my-opencode install --no-tui \
    --claude=max20 --openai=no --gemini=no --copilot=no

# ============================================================
# 12. pip tools
# ============================================================
# --ignore-installed: VNC deps (novnc, x11vnc) pull in Debian python3
# packages without pip RECORD files (typing_extensions, packaging, etc.).
# pip cannot upgrade these normally, so we skip the uninstall check.
# hadolint ignore=DL3013,DL3059
RUN pip install --no-cache-dir --break-system-packages --ignore-installed \
    pre-commit \
    ansible \
    black \
    pylint \
    yamllint \
    playwright \
    "markitdown[all]" \
    progressbar2 \
    checkov \
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
    fierce

# Security & pentest pip packages.
# Installed in isolated groups because mitmproxy, sslyze, impacket,
# and prowler pull conflicting cryptography/pyOpenSSL versions.
# A single pip install triggers massive resolver backtracking that
# downgrades zstandard (Python 3.13 cffi issue) or mitmproxy (ancient
# urwid with use_2to3).  Separate installs let each resolve cleanly.
# --ignore-installed: Debian system packages (blinker, etc.) lack
# pip RECORD files and block uninstall.
# hadolint ignore=DL3013,DL3059
RUN pip install --no-cache-dir --break-system-packages --ignore-installed \
    scapy impacket sslyze arjun hashid \
    && pip install --no-cache-dir --break-system-packages --ignore-installed \
    pwntools volatility3 \
    && pip install --no-cache-dir --break-system-packages --ignore-installed \
    mitmproxy \
    && pip install --no-cache-dir --break-system-packages --ignore-installed \
    prowler kube-hunter

# Aider AI chat — requires Python <3.13, so install isolated with uv + Python 3.12
# hadolint ignore=DL3059
RUN UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin \
    uv tool install --python python3.12 aider-chat@latest \
      --with aider-chat[browser] \
      --with aider-chat[help] \
      --with aider-chat[playwright]

# ============================================================
# 12b. Claude Code Proxy (Anthropic Messages API -> OpenAI)
# ============================================================
# Runs as a background process in entrypoint.sh when OPENAI_API_KEY is set.
# Build tools are needed for C extensions (httptools, uvloop) on Python 3.13.
# hadolint ignore=DL3008,DL3059
RUN git clone --depth=1 https://github.com/f5xc-salesdemos/claude-code-proxy.git /opt/claude-code-proxy

WORKDIR /opt/claude-code-proxy
# hadolint ignore=DL3008,DL3059
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
    && uv sync \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && chown -R $USERNAME:$USERNAME /opt/claude-code-proxy
# NOTE: build-essential is purged after Section 12i (git-cloned tools)
# because rubocop/prism (12d), wpscan (12h), and lxml/spiderfoot (12i)
# all require a C compiler.

# ============================================================
# 12c. SearXNG MCP server (web search for Claude Code)
# ============================================================
# stdio MCP server — Claude Code discovers this via settings.json,
# so it always appears in the tool schema regardless of provider type.
# hadolint ignore=DL3059
RUN git clone --depth=1 https://github.com/The-AI-Workshops/searxng-mcp-server.git /opt/searxng-mcp

WORKDIR /opt/searxng-mcp
RUN uv venv .venv \
    && uv pip install --python .venv/bin/python -r requirements.txt \
    && chown -R $USERNAME:$USERNAME /opt/searxng-mcp

# ============================================================
# 12d. Ruby linters (rubocop + extensions)
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
    standardrb

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
    && pip install --no-cache-dir --break-system-packages -r /opt/recon-ng/REQUIREMENTS \
    && ln -s /opt/recon-ng/recon-ng /usr/local/bin/recon-ng \
    && git clone --depth=1 https://github.com/smicallef/spiderfoot.git /opt/spiderfoot \
    # Spiderfoot pins lxml>=4.9.2,<5 but lxml 4.x Cython C code is
    # incompatible with Python 3.13 (removed _PyObject_NextNotImplemented,
    # changed _PyLong_AsByteArray).  Strip the <5 upper bound so pip uses
    # the already-installed lxml 6.x cp313 wheel.
    && sed -i 's/lxml>=4\.9\.2,<5/lxml>=4.9.2/' /opt/spiderfoot/requirements.txt \
    && pip install --no-cache-dir --break-system-packages -r /opt/spiderfoot/requirements.txt \
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
    && npx ng build --configuration production \
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

# Purge build-essential now that all C-extension installs are done.
# Kept through: Section 12b (claude-code-proxy), 12d (rubocop/prism),
# 12h (wpscan gem), 12i (recon-ng/spiderfoot pip deps), 12j (Navigator),
# and 12k (CALDERA).
# hadolint ignore=DL3059
RUN apt-get purge -y build-essential \
    && apt-get autoremove -y \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ============================================================
# 13. Playwright browsers (Chromium + system deps)
# ============================================================
# hadolint ignore=DL3059
RUN npx playwright install --with-deps chromium

# ============================================================
# User setup
# ============================================================
# Pre-create Homebrew prefix so the installer skips the sudo check
RUN mkdir -p /home/linuxbrew/.linuxbrew \
    && chown -R $USERNAME:$USERNAME /home/linuxbrew/.linuxbrew

USER $USERNAME
WORKDIR /home/$USERNAME

RUN mkdir -p ~/.cache ~/.local/bin ~/.claude ~/.config/nvim \
    && echo '{"hasCompletedOnboarding": true}' > ~/.claude.json.default

# Install native Claude Code binary (replaces npm package)
# hadolint ignore=DL3059
RUN claude install --force \
    && sudo npm uninstall -g @anthropic-ai/claude-code \
    && jq '. + {"hasCompletedOnboarding": true, "theme": "dark-daltonized"}' \
        ~/.claude.json > /tmp/claude.json && mv /tmp/claude.json ~/.claude.json

# ============================================================
# 14. Homebrew (needed by openclaw configure)
# ============================================================
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl ${CURL_RETRY} -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

ENV HOMEBREW_NO_AUTO_UPDATE=1
ENV PATH="/home/vscode/.local/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"

# AI assistant deps + formatters (no APT packages available)
# hadolint ignore=DL3059
RUN brew install ada-url hdrhistogram_c icu4c@78 llhttp uvwasi \
      air dfmt nixfmt ormolu oxfmt \
    && brew cleanup --prune=all -s

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
    && git clone --depth=1 https://github.com/yuhonas/zsh-aliases-lsd.git \
      "${ZSH_CUSTOM}/plugins/zsh-aliases-lsd" \
    && git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
      "${ZSH_CUSTOM}/themes/powerlevel10k" \
    && "${ZSH_CUSTOM}/themes/powerlevel10k/gitstatus/install" \
    && sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$HOME/.zshrc" \
    && sed -i 's/^plugins=(.*/plugins=(zsh-syntax-highlighting zsh-autosuggestions zsh-interactive-cd ubuntu jsontools gh common-aliases zsh-aliases-lsd zsh-tfenv conda-zsh-completion z pip terraform fluxcd azure git-auto-fetch helm istioctl iterm2 kube-ps1 kubectl sudo vscode aws fzf docker history colored-man-pages command-not-found)/' \
      "$HOME/.zshrc" \
    && sed -i 's/^# HYPHEN_INSENSITIVE=.*/HYPHEN_INSENSITIVE="true"/' "$HOME/.zshrc" \
    && sed -i 's/^# COMPLETION_WAITING_DOTS=.*/COMPLETION_WAITING_DOTS="true"/' "$HOME/.zshrc" \
    && sed -i 's/^# HIST_STAMPS=.*/HIST_STAMPS="yyyy-mm-dd"/' "$HOME/.zshrc" \
    && echo 'export HISTSIZE=50000' >> "$HOME/.zshrc" \
    && echo 'export SAVEHIST=50000' >> "$HOME/.zshrc" \
    && echo '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh' >> "$HOME/.zshrc" \
    && echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$HOME/.zshrc" \
    && echo 'alias vim=nvim' >> "$HOME/.zshrc" \
    && echo 'export LESS="-R -F -X -i -J --mouse"' >> "$HOME/.zshrc" \
    && echo 'export LESSHISTFILE="$HOME/.cache/lesshst"' >> "$HOME/.zshrc" \
    && echo 'export LESSOPEN="|~/.lessfilter %s"' >> "$HOME/.zshrc" \
    && echo 'export MANPAGER="sh -c '\''col -bx | bat -l man -p'\''"' >> "$HOME/.zshrc" \
    && echo 'export BAT_THEME="Coldark-Dark"' >> "$HOME/.zshrc" \
    && if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
      echo 'export BROWSER="browsh"' >> "$HOME/.zshrc"; \
    else \
      echo 'export BROWSER="lynx"' >> "$HOME/.zshrc"; \
    fi

# ============================================================
# 16. User shell bootstrap (baked in — eliminates runtime setup)
# ============================================================
# hadolint ignore=DL3059
RUN mkdir -p "$HOME/.npm-global" \
    && npm config set prefix "$HOME/.npm-global" \
    && git clone --depth=1 https://github.com/tfutils/tfenv.git "$HOME/.tfenv" \
    && "$HOME/.tfenv/bin/tfenv" install latest \
    && "$HOME/.tfenv/bin/tfenv" use latest \
    && zsh -c "autoload -U compinit && compinit" 2>/dev/null || true

COPY --chown=${USERNAME}:${USERNAME} configs/.p10k.zsh /home/${USERNAME}/.p10k.zsh
COPY --chown=${USERNAME}:${USERNAME} configs/init.vim /home/${USERNAME}/.config/nvim/init.vim
COPY --chown=${USERNAME}:${USERNAME} configs/.hushlogin /home/${USERNAME}/.hushlogin
COPY --chown=${USERNAME}:${USERNAME} configs/.inputrc /home/${USERNAME}/.inputrc
COPY --chown=${USERNAME}:${USERNAME} configs/.tmux.conf /home/${USERNAME}/.tmux.conf
COPY --chown=${USERNAME}:${USERNAME} configs/.nanorc /home/${USERNAME}/.nanorc
COPY --chown=${USERNAME}:${USERNAME} configs/.lessfilter /home/${USERNAME}/.lessfilter
RUN chmod +x /home/${USERNAME}/.lessfilter

# ============================================================
# 17. Claude Code configuration (self-test + managed policy)
#     COPY moved to end of file — config changes rebuild only
#     this thin layer, not Playwright/Homebrew/ZSH (~1 GB).
# ============================================================
# The Managed policy tier (/etc/claude-code/) is the highest priority in
# Claude Code's memory hierarchy and is always loaded, even when a project
# CLAUDE.md exists in the working directory. This prevents tool awareness
# from being deprioritized by large project-level instructions.
USER root
COPY claude-config/self-test.sh /opt/claude-config/self-test.sh
COPY claude-config/CLAUDE.md /etc/claude-code/CLAUDE.md
COPY claude-config/claude-proxy.sh /usr/local/lib/claude-proxy.sh
COPY opencode-config/opencode.json /opt/opencode-config/opencode.json
COPY opencode-config/opencode-anthropic.json /opt/opencode-config/opencode-anthropic.json
COPY codex-config/config.toml /opt/codex-config/config.toml
RUN chmod +x /opt/claude-config/self-test.sh /usr/local/lib/claude-proxy.sh \
    && ln -s /opt/claude-config/self-test.sh /usr/local/bin/claude-self-test \
    && mkdir -p /etc/claude-code/.claude/rules

# Shell hooks: source the proxy function in every interactive shell.
# If the user exports OPENAI_API_KEY after container start (or the
# entrypoint missed it), the next shell session starts the proxy
# automatically and sets ANTHROPIC_BASE_URL.
# - /etc/profile.d/ covers bash login shells
# - /etc/zsh/zshrc.d/ (sourced by oh-my-zsh base image) covers zsh
# hadolint ignore=SC1091
RUN printf '#!/bin/bash\n. /usr/local/lib/claude-proxy.sh\nstart_claude_proxy\n' \
      > /etc/profile.d/claude-proxy.sh \
    && chmod +x /etc/profile.d/claude-proxy.sh \
    && printf '. /usr/local/lib/claude-proxy.sh\nstart_claude_proxy\n' \
      >> /etc/zsh/zshenv

# Map CLAUDE_CODE_OAUTH_TOKEN → ANTHROPIC_OAUTH_TOKEN for tools
# that read the Anthropic-native env var (e.g. Pi).
# hadolint ignore=SC2016
RUN printf '#!/bin/bash\nif [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] && [ -z "$ANTHROPIC_OAUTH_TOKEN" ]; then\n  export ANTHROPIC_OAUTH_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN"\nfi\n' \
      > /etc/profile.d/anthropic-oauth.sh \
    && chmod +x /etc/profile.d/anthropic-oauth.sh \
    && printf 'if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] && [ -z "$ANTHROPIC_OAUTH_TOKEN" ]; then\n  export ANTHROPIC_OAUTH_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN"\nfi\n' \
      >> /etc/zsh/zshenv

# ============================================================
# 18. Entrypoint (absolute last COPY — most volatile file)
# ============================================================
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER $USERNAME
ENV SHELL=/bin/zsh
WORKDIR /workspace

HEALTHCHECK NONE

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
