#!/bin/bash
input=$(cat)

CYAN='\033[96m'
GREEN='\033[32m'
YELLOW='\033[33m'
DIM='\033[2m'
RESET='\033[0m'

TASKS=$(echo "$input" | jq -r '.tasks // [] | length')
[ "$TASKS" -eq 0 ] && exit 0

RUNNING=$(echo "$input" | jq -r '[.tasks[] | select(.status == "running")] | length')
PENDING=$(echo "$input" | jq -r '[.tasks[] | select(.status == "pending")] | length')
DONE=$(echo "$input" | jq -r '[.tasks[] | select(.status == "completed" or .status == "done")] | length')

NAMES=$(echo "$input" | jq -r '[.tasks[] | select(.status == "running") | .name // .label // .description // "agent"] | join(", ")')

PARTS=""
[ "$RUNNING" -gt 0 ] && PARTS="${CYAN}${RUNNING} running${RESET}"
[ "$PENDING" -gt 0 ] && PARTS="${PARTS:+${PARTS} }${YELLOW}${PENDING} queued${RESET}"
[ "$DONE" -gt 0 ] && PARTS="${PARTS:+${PARTS} }${GREEN}${DONE} done${RESET}"

if [ -n "$NAMES" ] && [ "$NAMES" != "null" ]; then
  echo -e "${DIM}agents:${RESET} ${PARTS} ${DIM}[${NAMES}]${RESET}"
else
  echo -e "${DIM}agents:${RESET} ${PARTS}"
fi
