# Remove Non-OpenCode AI Tools from INSTALL.md Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove Google Antigravity, Visual Studio Code, Cursor, Zed, and Codex from INSTALL.md, leaving OpenCode as the sole AI assistant frontend.

**Architecture:** Nine discrete string-replacement edits to INSTALL.md executed bottom-up (highest line number first) so earlier edits don't shift line numbers for later ones. One GitHub issue and one PR wrap the change.

**Tech Stack:** Bash, gh CLI, Edit tool on INSTALL.md

---

## Task 1: Governance — GitHub Issue + Branch

- [ ] Create GitHub issue and capture issue number
- [ ] Checkout branch `fix/<N>-remove-non-opencode-ai-tools`

---

## Task 2: Edit 9 — Remove Step 16.5 (Visual Studio Code / Cursor / Zed verify)

**Files:** Modify `INSTALL.md` (~lines 2797–2807)

Remove the entire `### 16.5 — IDEs and Terminal` section.

---

## Task 3: Edit 8 — Remove `export VSCODE=cursor` block (Step 14.4)

**Files:** Modify `INSTALL.md` (~lines 2652–2655)

Remove the 3-line block setting `VSCODE=cursor` and its preceding comment.

---

## Task 4: Edit 7 — Remove `vscode` row from Oh My Zsh plugins table (Step 5.5)

**Files:** Modify `INSTALL.md` (~line 1022)

Remove the `| \`vscode\` | OMZ built-in | Visual Studio Code aliases |` table row.

---

## Task 5: Edit 6 — Remove `vscode` from Oh My Zsh plugins sed command (Step 5.5)

**Files:** Modify `INSTALL.md` (~line 974)

Remove `vscode` from the plugins=(...) substitution string.

---

## Task 6: Edit 5 — Remove Step 5.9 (Codex CLI)

**Files:** Modify `INSTALL.md` (~lines 1122–1147)

Remove the entire `### 5.9 — Install Codex CLI` section (~26 lines).

---

## Task 7: Edit 4 — Remove Step 4h (Zed)

**Files:** Modify `INSTALL.md` (~lines 461–475)

Remove the entire `## Step 4h — Install Zed` section.

---

## Task 8: Edit 3 — Remove Step 4f (Cursor)

**Files:** Modify `INSTALL.md` (~lines 445–459)

Remove the entire `## Step 4f — Install Cursor` section.

---

## Task 9: Edit 2 — Remove Step 4e (Visual Studio Code)

**Files:** Modify `INSTALL.md` (~lines 427–442)

Remove the entire `## Step 4e — Install Visual Studio Code` section.

---

## Task 10: Edit 1 — Remove Step 4c (Google Antigravity)

**Files:** Modify `INSTALL.md` (~lines 411–425)

Remove the entire `## Step 4c — Install Google Antigravity` section.

---

## Task 11: Edit 10 — Update preamble line count

**Files:** Modify `INSTALL.md` (line ~16)

Update `~1200 lines` → `~3200 lines`.

---

## Task 12: Verify

```bash
grep -n 'cursor\|codex\|antigravity\|agy\|zed\b\|vscode\|VSCODE\|VS Code\|Visual Studio\|Cursor\|Zed\b' INSTALL.md
```

Surviving matches must only be LSP binary names:
- `vscode-langservers-extracted` (npm package)
- `vscode-json/css/html-language-server` (LSP binary names in opencode.json)

---

## Task 13: Commit + PR

```bash
git add INSTALL.md
git commit -m "fix: remove non-OpenCode AI tools from INSTALL.md (#N)"
git push -u origin fix/<N>-remove-non-opencode-ai-tools
gh pr create --title "fix: remove non-OpenCode AI tools from INSTALL.md" --body "Closes #N"
gh pr merge --squash --delete-branch
```
