# shellcheck shell=bash
# shellcheck disable=SC2148,SC2154,SC2155,SC2296
# gh-clone-complete.plugin.zsh
# GitHub repository tab completion for `git clone`
#
# Features:
# - Tab completion shows GitHub repos when typing `git clone <TAB>`
# - Caches repo lists for instant completion (10-minute TTL)
# - Transparent git wrapper expands `owner/repo` to full HTTPS URL
# - Gracefully degrades when gh is unavailable or unauthenticated
#
# Note: This file uses zsh-specific syntax (${(f)...}, $+commands, etc.)
# that shellcheck cannot parse. The SC2296 and SC2154 warnings are false
# positives for valid zsh code.

# Exit silently if gh CLI is not installed
(( $+commands[gh] )) || return 0

# ============================================================
# Configuration
# ============================================================
GH_CLONE_CACHE_DIR="${HOME}/.cache/gh-clone-complete"
GH_CLONE_CACHE_TTL=600  # 10 minutes in seconds

# ============================================================
# Cache Management
# ============================================================

# Create cache directory if needed
[[ -d "${GH_CLONE_CACHE_DIR}" ]] || mkdir -p "${GH_CLONE_CACHE_DIR}"

# Check if cache file is fresh (within TTL)
__gh_cache_is_fresh() {
  local file="$1"
  [[ -f "${file}" ]] || return 1
  local now=$(date +%s)
  local mtime=$(stat -c %Y "${file}" 2>/dev/null || stat -f %m "${file}" 2>/dev/null)
  (( now - mtime < GH_CLONE_CACHE_TTL ))
}

# Get list of owners (authenticated user + orgs)
__gh_get_owners() {
  local cache_file="${GH_CLONE_CACHE_DIR}/owners.list"

  if __gh_cache_is_fresh "${cache_file}"; then
    cat "${cache_file}"
    return 0
  fi

  # Fetch fresh list
  local owners=()
  local user
  user=$(gh api user --jq '.login' 2>/dev/null)
  [[ -n "${user}" ]] && owners+=("${user}")

  # Add organizations
  local orgs
  orgs=$(gh api user/orgs --jq '.[].login' 2>/dev/null)
  [[ -n "${orgs}" ]] && owners+=("${(@f)orgs}")

  if (( ${#owners[@]} > 0 )); then
    # Atomic write via temp file
    local tmp="${cache_file}.tmp.$$"
    printf '%s\n' "${owners[@]}" > "${tmp}"
    mv "${tmp}" "${cache_file}"
  fi

  printf '%s\n' "${owners[@]}"
}

# Get repositories for an owner
__gh_get_repos() {
  local owner="$1"
  local cache_file="${GH_CLONE_CACHE_DIR}/${owner}.repos"

  if __gh_cache_is_fresh "${cache_file}"; then
    cat "${cache_file}"
    return 0
  fi

  # Fetch fresh list (includes both owned and accessible repos)
  local repos
  repos=$(gh repo list "${owner}" --limit 1000 --json name --jq '.[].name' 2>/dev/null)

  if [[ -n "${repos}" ]]; then
    # Atomic write via temp file
    local tmp="${cache_file}.tmp.$$"
    printf '%s\n' "${repos}" > "${tmp}"
    mv "${tmp}" "${cache_file}"
  fi

  printf '%s\n' "${repos}"
}

# Background cache refresh (non-blocking)
# shellcheck disable=SC1009,SC1035,SC1072,SC1073
__gh_refresh_cache_background() {
  (
    # Check if gh is authenticated
    gh auth status &>/dev/null || return 0

    local owners
    owners=$(__gh_get_owners)
    [[ -z "${owners}" ]] && return 0

    # Refresh repo cache for each owner
    local owner
    for owner in ${(f)owners}; do
      __gh_get_repos "${owner}" >/dev/null
    done
  ) &
  disown
}

# Warm cache on shell startup (non-blocking)
__gh_refresh_cache_background

# ============================================================
# Git Wrapper Function
# ============================================================
# Expands owner/repo to full HTTPS URL for git clone
git() {
  if [[ "$1" == "clone" && -n "$2" && "$2" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$ ]]; then
    # Pattern matches owner/repo but not URLs, paths, or other git args
    command git clone "https://github.com/$2.git" "${@:3}"
  else
    command git "$@"
  fi
}

# ============================================================
# Completion Functions
# ============================================================

# GitHub repository completion source
__git_github_repositories() {
  local -a repos
  local owners owner repo_list

  owners=$(__gh_get_owners 2>/dev/null)
  [[ -z "${owners}" ]] && return 1

  for owner in ${(f)owners}; do
    repo_list=$(__gh_get_repos "${owner}" 2>/dev/null)
    [[ -z "${repo_list}" ]] && continue
    for repo in ${(f)repo_list}; do
      repos+=("${owner}/${repo}")
    done
  done

  _describe -t github-repositories 'GitHub repository' repos
}

# Override the default __git_any_repositories function
# This function is called by zsh's _git completion for `git clone`
# The original only provides local-repositories, remotes, and remote-repositories
# We add a fourth source: github-repositories
__git_any_repositories() {
  _alternative \
    'local-repositories::__git_local_repositories' \
    'remotes: :__git_remotes' \
    'remote-repositories::__git_remote_repositories' \
    'github-repositories::__git_github_repositories'
}
