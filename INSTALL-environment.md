# macOS User Environment Setup

> **Audience**: Plain-language instructions for OpenCode or a human operator.
> **Platform**: macOS on Apple Silicon (arm64). Homebrew is already installed.
> **Prerequisite**: None — this guide is fully standalone.
>
> **Execution**: Steps are sequential and idempotent. Each includes inline VERIFY comments.
> Steps marked **MANUAL STEP** require human interaction.

---

## Step 1 — Install Terminal Dependencies (Homebrew)

```bash
# Helper function: install a brew package with stale-Cellar recovery.
brew_install() {
  local pkg="$1"
  if brew install "$pkg" 2>&1; then
    return 0
  fi
  echo "  ⚠ brew install $pkg failed — checking for stale Cellar entry..."
  local cellar="/opt/homebrew/Cellar/$pkg"
  if [ -d "$cellar" ]; then
    echo "  Removing stale Cellar directory: $cellar"
    rm -rf "$cellar"
    if brew install "$pkg" 2>&1; then
      return 0
    fi
  fi
  if [ -d "$cellar" ]; then
    echo "  Attempting to link existing Cellar entry for $pkg..."
    brew link --overwrite "$pkg" 2>&1 || true
  fi
}

# Zsh plugins (checksummed, controlled install; symlinked into oh-my-zsh later)
brew_install zsh-autosuggestions
brew_install zsh-syntax-highlighting

# Powerlevel10k theme
brew install powerlevel10k

# Fonts — MesloLGS NF is Powerlevel10k's recommended font
brew install --cask font-meslo-for-powerlevel10k
brew install --cask font-meslo-lg-nerd-font

# Neovim (terminal editor with LSP support)
brew_install neovim
```

---

## Step 2 — Configure macOS System Defaults

All commands are idempotent — `defaults write` overwrites existing values.

### 2.1 — Power and Sleep

> **MANUAL STEP**: Open **System Settings** > **Battery** > **Options** and enable
> **"Prevent automatic sleeping on power adapter when the display is off"**.

### 2.2 — Dock

```bash
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0.25
defaults write com.apple.dock tilesize -int 45
defaults write com.apple.dock mineffect -string "scale"
defaults write com.apple.dock show-recents -bool false
killall Dock
```

### 2.3 — Finder

```bash
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
killall Finder
```

### 2.4 — Keyboard

```bash
defaults write -g KeyRepeat -int 1
defaults write -g InitialKeyRepeat -int 10
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
```

### 2.5 — Trackpad

```bash
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
defaults write NSGlobalDomain com.apple.trackpad.scaling -float 2.5
```

### 2.6 — Screenshots

```bash
mkdir -p ~/Screenshots
defaults write com.apple.screencapture location ~/Screenshots
defaults write com.apple.screencapture type -string "png"
```

### 2.7 — Miscellaneous

```bash
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true
```

### Verify macOS Defaults

```bash
defaults read com.apple.dock autohide                              # Expected: 1
defaults read com.apple.dock show-recents                          # Expected: 0
defaults read NSGlobalDomain AppleShowAllExtensions                # Expected: 1
defaults read com.apple.finder AppleShowAllFiles                   # Expected: 1
defaults read -g KeyRepeat                                         # Expected: 1
defaults read NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled   # Expected: 0
defaults read NSGlobalDomain ApplePressAndHoldEnabled              # Expected: 0
defaults read com.apple.screencapture location                     # Expected: ~/Screenshots
defaults read com.apple.desktopservices DSDontWriteNetworkStores   # Expected: 1
```

---

## Step 3 — Install iTerm2

```bash
[ -d "/Applications/iTerm.app" ] || brew install --cask iterm2
```

### 3.1 — Configure iTerm2 Font and Settings

```bash
PLIST="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
FONT="MesloLGS-NF-Regular 13"

if [ ! -d "/Applications/iTerm.app" ]; then
  echo "iTerm2 is not installed — skipping"
else
  if pgrep -xq iTerm2; then
    osascript -e 'tell application "iTerm2" to quit' 2>/dev/null
    for i in $(seq 1 20); do pgrep -xq iTerm2 || break; sleep 0.5; done
    if pgrep -xq iTerm2; then killall iTerm2 2>/dev/null; sleep 1; fi
  fi

  if [ ! -f "$PLIST" ]; then
    open -a iTerm2
    for i in $(seq 1 16); do [ -f "$PLIST" ] && break; sleep 0.5; done
    sleep 1
    osascript -e 'tell application "iTerm2" to quit' 2>/dev/null
    for i in $(seq 1 20); do pgrep -xq iTerm2 || break; sleep 0.5; done
  fi

  if [ -f "$PLIST" ]; then
    CURRENT="$(/usr/libexec/PlistBuddy -c 'Print :"New Bookmarks":0:"Normal Font"' "$PLIST" 2>/dev/null)"
    if [ "$CURRENT" != "$FONT" ]; then
      /usr/libexec/PlistBuddy -c "Set :\"New Bookmarks\":0:\"Normal Font\" \"$FONT\"" "$PLIST"
    fi
  fi
fi
```

### 3.2 — Configure iTerm2 Developer Settings

```bash
PLIST="$HOME/Library/Preferences/com.googlecode.iterm2.plist"

if [ -f "$PLIST" ]; then
  plist_profile_set() {
    local key="$1" type="$2" val="$3"
    /usr/libexec/PlistBuddy -c "Set :\"New Bookmarks\":0:\"$key\" $val" "$PLIST" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Add :\"New Bookmarks\":0:\"$key\" $type $val" "$PLIST"
  }

  plist_profile_set "Silence Bell" bool true
  plist_profile_set "Visual Bell" bool false
  plist_profile_set "Unlimited Scrollback" bool true
  plist_profile_set "Option Key Sends" integer 2
  plist_profile_set "Right Option Key Sends" integer 2
  plist_profile_set "BounceIconInDockEnabled" bool true

  # Shift+Enter → ESC[13;2u (CSI u) for Claude Code multi-line prompts
  SHIFT_ENTER_KEY="Keyboard Map:0xd-0x20000-0x24"
  if ! /usr/libexec/PlistBuddy -c "Print :'New Bookmarks':0:'$SHIFT_ENTER_KEY':Action" "$PLIST" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy \
      -c "Add :'New Bookmarks':0:'Keyboard Map':'0xd-0x20000-0x24' dict" \
      -c "Add :'New Bookmarks':0:'Keyboard Map':'0xd-0x20000-0x24':Version integer 2" \
      -c "Add :'New Bookmarks':0:'Keyboard Map':'0xd-0x20000-0x24':'Apply Mode' integer 0" \
      -c "Add :'New Bookmarks':0:'Keyboard Map':'0xd-0x20000-0x24':Action integer 10" \
      -c "Add :'New Bookmarks':0:'Keyboard Map':'0xd-0x20000-0x24':Text string [13;2u" \
      -c "Add :'New Bookmarks':0:'Keyboard Map':'0xd-0x20000-0x24':Escaping integer 2" \
      "$PLIST"
  fi

  defaults write com.googlecode.iterm2 TabStyleWithAutomaticOption -int 1
fi
```

> **MANUAL STEP — Notifications**: Open iTerm2 Settings → Profiles → Terminal,
> click "Filter Alerts" and check "Send escape sequence-generated alerts".

### 3.3 — Install it2 (iTerm2 Python CLI)

```bash
uv tool install it2
```

---

## Step 4 — Install Oh My Zsh

```bash
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh
  RUNZSH=no CHSH=no ~/.oh-my-zsh/tools/install.sh --unattended
fi
```

### 4.1 — Install Zsh Plugins

```bash
mkdir -p ~/.oh-my-zsh/custom/plugins
ln -sf "$(brew --prefix)/share/zsh-autosuggestions" \
  ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
ln -sf "$(brew --prefix)/share/zsh-syntax-highlighting" \
  ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
```

Clone community plugins (pinned to audited SHAs):

<!-- PINNED_DEPS_LAST_AUDITED: 2026-03-28 — next review: 2026-06-28 -->

```bash
pin_clone() {
  local url="$1" dest="$2" sha="$3"
  if [ -d "$dest" ]; then return; fi
  git clone --depth=50 "$url" "$dest"
  git -C "$dest" checkout "$sha"
}

pin_clone https://github.com/conda-incubator/conda-zsh-completion.git \
  ~/.oh-my-zsh/custom/plugins/conda-zsh-completion \
  632655aab6e147b90f75cf3d195ae2b48e7beec9

pin_clone https://github.com/z-shell/zsh-eza.git \
  ~/.oh-my-zsh/custom/plugins/zsh-eza \
  717b2312f7dab9809869f07d5fa905dad0a8f959

pin_clone https://github.com/cda0/zsh-tfenv.git \
  ~/.oh-my-zsh/custom/plugins/zsh-tfenv \
  f456a47c5e45f80913041eb7c4fa4159b46810db
```

Copy `gh-clone-complete` plugin from this repo:

```bash
mkdir -p ~/.oh-my-zsh/custom/plugins/gh-clone-complete
\cp -f configs/gh-clone-complete.plugin.zsh \
  ~/.oh-my-zsh/custom/plugins/gh-clone-complete/gh-clone-complete.plugin.zsh
```

Symlink Powerlevel10k theme:

```bash
ln -sf /opt/homebrew/share/powerlevel10k ~/.oh-my-zsh/custom/themes/powerlevel10k
```

### 4.2 — Configure `~/.zshrc`

```bash
sed -i '' 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' ~/.zshrc

# Full plugin list (common + macOS-only)
sed -i '' 's/^plugins=(.*/plugins=(zsh-syntax-highlighting zsh-autosuggestions zsh-interactive-cd jsontools gh gh-clone-complete common-aliases zsh-eza zsh-tfenv conda-zsh-completion z pip terraform fluxcd azure git-auto-fetch helm istioctl kube-ps1 kubectl sudo aws fzf docker history colored-man-pages command-not-found tmux dotenv emoji gcloud git pre-commit iterm2 macos podman)/' ~/.zshrc

grep -q 'ZSH_DOTENV_PROMPT' ~/.zshrc || \
  sed -i '' '/^source \$ZSH\/oh-my-zsh.sh/i\
export ZSH_DOTENV_PROMPT=false
' ~/.zshrc

sed -i '' 's/^# HYPHEN_INSENSITIVE=.*/HYPHEN_INSENSITIVE="true"/' ~/.zshrc
sed -i '' 's/^# COMPLETION_WAITING_DOTS=.*/COMPLETION_WAITING_DOTS="true"/' ~/.zshrc
sed -i '' 's/^# HIST_STAMPS=.*/HIST_STAMPS="yyyy-mm-dd"/' ~/.zshrc
```

### 4.3 — Powerlevel10k Instant Prompt

This block **must be the first thing** in `~/.zshrc`:

```bash
if ! grep -q 'p10k-instant-prompt' ~/.zshrc; then
  TMPFILE=$(mktemp)
  cat > "$TMPFILE" << 'INSTANT_PROMPT'
# Enable Powerlevel10k instant prompt.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

INSTANT_PROMPT
  cat ~/.zshrc >> "$TMPFILE"
  mv -f "$TMPFILE" ~/.zshrc
fi
```

### 4.4 — Homebrew PATH (before oh-my-zsh source)

```bash
if grep -q 'brew shellenv' ~/.zshrc; then
  sed -i '' '/brew shellenv/d' ~/.zshrc
fi
sed -i '' '/^source \$ZSH\/oh-my-zsh.sh/i\
eval $(/opt/homebrew/bin/brew shellenv)
' ~/.zshrc
```

### 4.5 — User Configuration (after oh-my-zsh source)

```bash
grep -q 'p10k.zsh' ~/.zshrc || \
  echo '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh' >> ~/.zshrc

grep -q 'HISTSIZE=50000' ~/.zshrc || echo 'export HISTSIZE=50000' >> ~/.zshrc
grep -q 'SAVEHIST=50000' ~/.zshrc || echo 'export SAVEHIST=50000' >> ~/.zshrc

grep -q 'alias vim=nvim' ~/.zshrc || echo 'alias vim=nvim' >> ~/.zshrc

grep -q 'export LESS=' ~/.zshrc || echo 'export LESS="-R -F -X -i -J --mouse"' >> ~/.zshrc
grep -q 'LESSHISTFILE' ~/.zshrc || echo 'export LESSHISTFILE="$HOME/.cache/lesshst"' >> ~/.zshrc
grep -q 'LESSOPEN' ~/.zshrc || echo 'export LESSOPEN="|~/.lessfilter %s"' >> ~/.zshrc

grep -q 'MANPAGER' ~/.zshrc || \
  echo 'export MANPAGER="sh -c '\''col -bx | bat -l man -p'\''"' >> ~/.zshrc
grep -q 'BAT_THEME' ~/.zshrc || echo 'export BAT_THEME="Coldark-Dark"' >> ~/.zshrc

grep -q '\.local/bin' ~/.zshrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
grep -q 'iTerm.app' ~/.zshrc || \
  echo 'export PATH="/Applications/iTerm.app/Contents/Resources/utilities:$PATH"' >> ~/.zshrc
```

---

## Step 5 — Install Dotfiles

```bash
\cp -f configs/.p10k.zsh ~/.p10k.zsh
\cp -f configs/.tmux.conf ~/.tmux.conf

[ -d ~/.tmux/plugins/tpm ] || \
  git clone --depth=1 https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

\cp -f configs/.digrc ~/.digrc
\cp -f configs/.inputrc ~/.inputrc
\cp -f configs/.nanorc ~/.nanorc
\cp -f configs/.lessfilter ~/.lessfilter
chmod +x ~/.lessfilter
touch ~/.hushlogin
```

---

## Verify the Complete Environment

```bash
ls "/Applications/iTerm.app"
which imgcat
ls ~/.oh-my-zsh/oh-my-zsh.sh
test -f ~/.oh-my-zsh/custom/themes/powerlevel10k/powerlevel10k.zsh-theme && echo "OK"
ls ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
ls ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
ls ~/.oh-my-zsh/custom/plugins/conda-zsh-completion
ls ~/.oh-my-zsh/custom/plugins/zsh-eza
ls ~/.oh-my-zsh/custom/plugins/zsh-tfenv
ls ~/.oh-my-zsh/custom/plugins/gh-clone-complete
test -f ~/.p10k.zsh && echo "OK: p10k config"
test -f ~/.tmux.conf && echo "OK: tmux config"
test -f ~/.digrc && echo "OK: digrc"
test -f ~/.inputrc && echo "OK: inputrc"
test -x ~/.lessfilter && echo "OK: lessfilter"
test -f ~/.nanorc && echo "OK: nanorc"
test -f ~/.hushlogin && echo "OK: hushlogin"
ls ~/Library/Fonts/MesloLGS\ NF\ Regular.ttf
grep '^ZSH_THEME="powerlevel10k' ~/.zshrc
grep '^plugins=(zsh-syntax-highlighting' ~/.zshrc
/usr/libexec/PlistBuddy -c 'Print :"New Bookmarks":0:"Silence Bell"' \
  ~/Library/Preferences/com.googlecode.iterm2.plist
defaults read com.googlecode.iterm2 TabStyleWithAutomaticOption
it2 --help
```

---

## Troubleshooting

### Reset Terminal Environment

```bash
rm -rf ~/.oh-my-zsh
rm -f ~/.p10k.zsh ~/.tmux.conf ~/.digrc ~/.inputrc ~/.nanorc ~/.lessfilter ~/.hushlogin
```

After cleanup, re-run this document from Step 4.
