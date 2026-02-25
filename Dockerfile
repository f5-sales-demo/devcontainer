FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG USERNAME=vscode

# ============================================================
# Version pins
# ============================================================
ARG NODE_MAJOR=24
ARG PYTHON_VERSION=3.13
ARG GO_VERSION=1.24.1
ARG JAVA_VERSION=21
ARG MAVEN_VERSION=3.9.9
ARG GRADLE_VERSION=8.12.1
ARG TERRAFORM_DOCS_VERSION=0.19.0
ARG TFLINT_VERSION=0.55.1
ARG KUBECTL_VERSION=1.32.2
ARG HELM_VERSION=3.17.1
ARG ACT_VERSION=0.2.74
ARG UV_VERSION=0.6.2
ARG ACTIONLINT_VERSION=1.7.7
ARG PWSH_VERSION=7.5.4
ARG OC_VERSION=4.18.4
ARG YQ_VERSION=4.52.4
ARG TERRAGRUNT_VERSION=0.71.2
ARG IBMCLOUD_VERSION=2.31.0

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
    # Docker
    && install -m 0755 -d /etc/apt/keyrings \
    && curl ${CURL_RETRY} -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      > /etc/apt/sources.list.d/docker.list \
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
    dnsutils net-tools iputils-ping traceroute tcpdump nmap \
    # Shell tools
    bat fd-find ripgrep neovim htop tree fzf tmux file \
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
    # Docker CLI
    docker-ce-cli docker-buildx-plugin docker-compose-plugin \
    # Azure CLI
    azure-cli \
    # Locale
    locales \
    locales-all \
    # Additional tools
    dos2unix \
    eza \
    fontconfig \
    fonts-powerline \
    google-cloud-cli \
    graphviz \
    imagemagick \
    jq \
    lsd \
    mtr-tiny \
    shellcheck \
    unzip \
    yelp-tools \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen en_US.UTF-8 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create expected binary names for tools Ubuntu renames
RUN ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV TERM=xterm-256color

# PowerShell — Microsoft only publishes amd64 .deb packages;
# arm64 uses the official tar.gz from GitHub releases.
# hadolint ignore=DL3008,DL3059
RUN DPKG_ARCH=$(dpkg --print-architecture) \
    && if [ "$DPKG_ARCH" = "amd64" ]; then \
      apt-get update && apt-get install -y --no-install-recommends powershell \
      && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    else \
      mkdir -p /opt/microsoft/powershell/7 \
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
# 4. Go
# ============================================================
RUN ARCH=$(dpkg --print-architecture) \
    && curl ${CURL_RETRY} -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" | tar -xz -C /usr/local
ENV PATH="/usr/local/go/bin:${PATH}"

# ============================================================
# 5. Rust (system-wide)
# ============================================================
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH="/usr/local/cargo/bin:${PATH}"
RUN curl ${CURL_RETRY} --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --default-toolchain stable --no-modify-path \
    && chmod -R a+rX /usr/local/rustup /usr/local/cargo

# ============================================================
# 6. Maven + Gradle
# ============================================================
# hadolint ignore=DL3059
RUN curl ${CURL_RETRY} -fsSL "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
    | tar -xz -C /opt \
    && ln -s "/opt/apache-maven-${MAVEN_VERSION}/bin/mvn" /usr/local/bin/mvn

# hadolint ignore=DL3059
RUN curl ${CURL_RETRY} -fsSL "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" -o /tmp/gradle.zip \
    && unzip -q /tmp/gradle.zip -d /opt \
    && ln -s "/opt/gradle-${GRADLE_VERSION}/bin/gradle" /usr/local/bin/gradle \
    && rm /tmp/gradle.zip

# ============================================================
# 7. AWS CLI v2
# ============================================================
# hadolint ignore=DL3059
RUN ARCH=$(uname -m) \
    && curl ${CURL_RETRY} -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o /tmp/awscli.zip \
    && unzip -q /tmp/awscli.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscli.zip

# ============================================================
# 8. Binary tools (kubectl, helm, tflint, terraform-docs,
#    act, actionlint, yt-dlp, uv, opencode)
# ============================================================
# hadolint ignore=DL3059
RUN DPKG_ARCH=$(dpkg --print-architecture) && UNAME_ARCH=$(uname -m) \
    # kubectl
    && curl ${CURL_RETRY} -fsSLo /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${DPKG_ARCH}/kubectl" \
    && chmod +x /usr/local/bin/kubectl \
    # helm
    && curl ${CURL_RETRY} -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${DPKG_ARCH}.tar.gz" \
      | tar -xz --strip-components=1 -C /usr/local/bin "linux-${DPKG_ARCH}/helm" \
    # tflint
    && curl ${CURL_RETRY} -fsSL "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_${DPKG_ARCH}.zip" \
      -o /tmp/tflint.zip \
    && unzip -q /tmp/tflint.zip -d /usr/local/bin && rm /tmp/tflint.zip \
    # terraform-docs
    && curl ${CURL_RETRY} -fsSL "https://github.com/terraform-docs/terraform-docs/releases/download/v${TERRAFORM_DOCS_VERSION}/terraform-docs-v${TERRAFORM_DOCS_VERSION}-linux-${DPKG_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin terraform-docs \
    # act
    && if [ "$UNAME_ARCH" = "x86_64" ]; then ACT_ARCH="x86_64"; else ACT_ARCH="arm64"; fi \
    && curl ${CURL_RETRY} -fsSL "https://github.com/nektos/act/releases/download/v${ACT_VERSION}/act_Linux_${ACT_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin act \
    # actionlint
    && curl ${CURL_RETRY} -fsSL "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_${DPKG_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin actionlint \
    # yt-dlp
    && curl ${CURL_RETRY} -fsSLo /usr/local/bin/yt-dlp \
      "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" \
    && chmod +x /usr/local/bin/yt-dlp \
    # uv
    && curl ${CURL_RETRY} -fsSL "https://astral.sh/uv/${UV_VERSION}/install.sh" | sh \
    && mv "$HOME/.local/bin/uv" /usr/local/bin/uv \
    && mv "$HOME/.local/bin/uvx" /usr/local/bin/uvx 2>/dev/null || true \
    # opencode
    && if [ "$UNAME_ARCH" = "x86_64" ]; then OC_ARCH="x64"; else OC_ARCH="arm64"; fi \
    && curl ${CURL_RETRY} -fsSL "https://github.com/anomalyco/opencode/releases/latest/download/opencode-linux-${OC_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin opencode

# ============================================================
# 8b. Additional binary tools (code CLI, oc, yq, terragrunt, ibmcloud)
# ============================================================
# hadolint ignore=DL3059
RUN DPKG_ARCH=$(dpkg --print-architecture) \
    # VS Code CLI (code tunnel / code serve-web for remote dev connectivity)
    && if [ "$DPKG_ARCH" = "amd64" ]; then VSCODE_ARCH="x64"; else VSCODE_ARCH="arm64"; fi \
    && curl ${CURL_RETRY} -fsSL \
      "https://code.visualstudio.com/sha/download?build=stable&os=cli-linux-${VSCODE_ARCH}" \
      -o /tmp/vscode_cli.tar.gz \
    && tar -xzf /tmp/vscode_cli.tar.gz -C /usr/local/bin \
    && rm /tmp/vscode_cli.tar.gz \
    # oc (OpenShift CLI) — extract only oc binary
    && curl ${CURL_RETRY} -fsSL \
      "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OC_VERSION}/openshift-client-linux-${DPKG_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin oc \
    # yq v4 — installed as yq; yq4 is a symlink
    && curl ${CURL_RETRY} -fsSLo /usr/local/bin/yq \
      "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${DPKG_ARCH}" \
    && chmod +x /usr/local/bin/yq \
    && ln -sf /usr/local/bin/yq /usr/local/bin/yq4 \
    # yq v3 (EOL, last release 3.4.1) — installed as yq3
    && curl ${CURL_RETRY} -fsSLo /usr/local/bin/yq3 \
      "https://github.com/mikefarah/yq/releases/download/3.4.1/yq_linux_${DPKG_ARCH}" \
    && chmod +x /usr/local/bin/yq3 \
    # terragrunt
    && curl ${CURL_RETRY} -fsSLo /usr/local/bin/terragrunt \
      "https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/terragrunt_linux_${DPKG_ARCH}" \
    && chmod +x /usr/local/bin/terragrunt \
    # IBM Cloud CLI
    && if [ "$DPKG_ARCH" = "amd64" ]; then IBM_ARCH="amd64"; else IBM_ARCH="arm64"; fi \
    && curl ${CURL_RETRY} -fsSL \
      "https://github.com/IBM-Cloud/ibm-cloud-cli-release/releases/download/v${IBMCLOUD_VERSION}/IBM_Cloud_CLI_${IBMCLOUD_VERSION}_linux_${IBM_ARCH}.tar.gz" \
      -o /tmp/ibmcloud.tar.gz \
    && tar -xzf /tmp/ibmcloud.tar.gz -C /tmp \
    && install -m 755 /tmp/IBM_Cloud_CLI/ibmcloud /usr/local/bin/ibmcloud \
    && rm -rf /tmp/ibmcloud.tar.gz /tmp/IBM_Cloud_CLI

# ============================================================
# 9. npm global tools
# ============================================================
# hadolint ignore=DL3016,DL3059
RUN npm install -g \
    @anthropic-ai/claude-code \
    @openai/codex \
    prettier \
    markdownlint-cli2 \
    openclaw \
    @devcontainers/cli \
    playwright

# ============================================================
# 10. pip tools
# ============================================================
# hadolint ignore=DL3013,DL3059
RUN pip install --no-cache-dir --break-system-packages \
    pre-commit \
    ansible \
    black \
    pylint \
    yamllint \
    playwright \
    "markitdown[all]" \
    progressbar2 \
    checkov

# ============================================================
# 11. Playwright browsers (Chromium + system deps)
# ============================================================
# hadolint ignore=DL3059
RUN npx playwright install --with-deps chromium

# ============================================================
# User setup
# ============================================================
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Pre-create Homebrew prefix so the installer skips the sudo check
RUN mkdir -p /home/linuxbrew/.linuxbrew \
    && chown -R $USERNAME:$USERNAME /home/linuxbrew/.linuxbrew

USER $USERNAME
WORKDIR /home/$USERNAME

RUN mkdir -p ~/.cache ~/.local/bin ~/.claude \
    && echo '{"hasCompletedOnboarding": true}' > ~/.claude.json.default

# ============================================================
# 12. Homebrew (needed by openclaw configure)
# ============================================================
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl ${CURL_RETRY} -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

ENV HOMEBREW_NO_AUTO_UPDATE=1
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"

# ============================================================
# 13. VNC stack (Xvfb + x11vnc + noVNC + fluxbox)
# ============================================================
USER root
# hadolint ignore=DL3008,DL3059
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    x11vnc \
    novnc \
    fluxbox \
    x11-utils \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
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
    && git clone --depth=1 https://github.com/yuhonas/zsh-aliases-lsd.git \
      "${ZSH_CUSTOM}/plugins/zsh-aliases-lsd" \
    && sed -i 's/^plugins=(.*/plugins=(zsh-syntax-highlighting zsh-autosuggestions zsh-interactive-cd ubuntu jsontools gh common-aliases zsh-aliases-lsd zsh-tfenv conda-zsh-completion z pip terraform fluxcd azure git-auto-fetch helm istioctl iterm2 kube-ps1 kubectl sudo vscode aws fzf)/' \
      "$HOME/.zshrc"

ENV SHELL=/bin/zsh
WORKDIR /workspace

HEALTHCHECK NONE

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
