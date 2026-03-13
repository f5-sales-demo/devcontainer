#!/bin/bash
input=$(cat)

CTX_USED=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
DIR=$(echo "$input" | jq -r '.workspace.current_dir // empty')
[ -z "$DIR" ] && DIR=$(pwd)

# Colors (matching p10k theme)
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[96m'
DIM='\033[2m'
RESET='\033[0m'

# Context usage color (green < 50%, yellow 50-79%, red 80%+)
CTX_INT=${CTX_USED%.*}
if [ "${CTX_INT:-0}" -ge 80 ]; then
  CTX_COLOR="${RED}"
elif [ "${CTX_INT:-0}" -ge 50 ]; then
  CTX_COLOR="${YELLOW}"
else
  CTX_COLOR="${GREEN}"
fi

# Check if we're in a git repo
if git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)
  [ -z "$BRANCH" ] && BRANCH=$(git -C "$DIR" rev-parse --short HEAD 2>/dev/null)

  STAGED=$(git -C "$DIR" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
  UNSTAGED=$(git -C "$DIR" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
  UNTRACKED=$(git -C "$DIR" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
  CONFLICTED=$(git -C "$DIR" diff --name-only --diff-filter=U 2>/dev/null | wc -l | tr -d ' ')

  if [ "$CONFLICTED" -gt 0 ]; then
    STATE="${RED}conflicted${RESET}"
    BRANCH_COLOR="${RED}"
  elif [ "$STAGED" -gt 0 ] || [ "$UNSTAGED" -gt 0 ]; then
    STATE="${YELLOW}dirty${RESET}"
    BRANCH_COLOR="${YELLOW}"
  elif [ "$UNTRACKED" -gt 0 ]; then
    STATE="${CYAN}untracked${RESET}"
    BRANCH_COLOR="${CYAN}"
  else
    STATE="${GREEN}clean${RESET}"
    BRANCH_COLOR="${GREEN}"
  fi

  DETAILS=""
  [ "$STAGED" -gt 0 ] && DETAILS="${DETAILS} ${GREEN}+${STAGED}${RESET}"
  [ "$UNSTAGED" -gt 0 ] && DETAILS="${DETAILS} ${YELLOW}~${UNSTAGED}${RESET}"
  [ "$UNTRACKED" -gt 0 ] && DETAILS="${DETAILS} ${CYAN}?${UNTRACKED}${RESET}"
  [ "$CONFLICTED" -gt 0 ] && DETAILS="${DETAILS} ${RED}!${CONFLICTED}${RESET}"

  echo -e "${CTX_COLOR}${CTX_USED}%${RESET} ${DIR} ${DIM}|${RESET} ${BRANCH_COLOR}${BRANCH}${RESET} ${STATE}${DETAILS}"
else
  echo -e "${CTX_COLOR}${CTX_USED}%${RESET} ${DIR}"
fi
