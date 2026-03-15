# Chrome Headless + DevTools MCP in the Dev Container

This guide documents the exact changes required to make the
[Chrome DevTools MCP server](https://github.com/anthropics/chrome-devtools-mcp)
work inside the headless ARM64 dev container.

## Problem Statement

The dev container runs on ARM64 (Apple Silicon) with Ubuntu 24.04
and has no physical display. The Chrome DevTools MCP server is
launched by the Claude Code proxy as:

```
npm exec chrome-devtools-mcp@latest
```

The proxy does **not** pass any CLI flags — `--headless` is never
included. Without intervention, Puppeteer tries to launch Chrome
in headful mode and fails:

```
Missing X server to start the headful browser. Either set headless
to true or use xvfb-run to run your Puppeteer script.
```

There is no configuration-based way to pass `--headless` to the
proxy-launched MCP server. The proxy uses its own registered MCP
instance (from the marketplace plugin system) and ignores any
`mcpServers` entries in `~/.claude/settings.json`.

Two changes are required:

1. A **Chrome symlink** so Puppeteer can find the browser
2. A **headless injection patch** in the MCP entry point

## Prerequisite: Playwright Chromium

The Dockerfile already installs Playwright's bundled Chromium at
line 1017:

```dockerfile
RUN npx playwright install --with-deps chromium
```

This installs a working ARM64 Chromium binary at:

```
/home/vscode/.cache/ms-playwright/chromium-1208/chrome-linux/chrome
```

> **Why Playwright's Chromium?** Google Chrome has no ARM64 `.deb`
> package. Ubuntu 24.04's `chromium-browser` apt package redirects
> to snap, which does not work inside containers. Playwright's
> bundled Chromium is the only reliable option for ARM64 containers.

## Change 1: Chrome Symlink

Puppeteer looks for Chrome at the "stable" channel path
`/opt/google/chrome/chrome`. Without a binary at this path, the
MCP server fails with:

```
Could not find Google Chrome executable for channel 'stable' at:
 - /opt/google/chrome/chrome.
```

Create a symlink to bridge Puppeteer's lookup to the Playwright
binary:

```bash
mkdir -p /opt/google/chrome
ln -sf /home/vscode/.cache/ms-playwright/chromium-1208/chrome-linux/chrome \
       /opt/google/chrome/chrome
```

**Verify:**

```bash
/opt/google/chrome/chrome --version
# Expected: Chromium 145.0.7632.0
```

## Change 2: Headless Injection Patch

The MCP server is launched by the proxy without `--headless`.
Since there is no way to configure the proxy to pass this flag,
the server's entry point must be patched to auto-inject it before
argument parsing runs.

### Target file

```
node_modules/chrome-devtools-mcp/build/src/bin/chrome-devtools-mcp-main.js
```

When installed via `npm exec`, the full path is:

```
/home/vscode/.npm/_npx/<hash>/node_modules/chrome-devtools-mcp/build/src/bin/chrome-devtools-mcp-main.js
```

### What to patch

Insert 3 lines **before** the `parseArguments()` call. The
`parseArguments` function reads `process.argv`, so the flag must
be pushed before it runs.

**Before (original):**

```javascript
import { cliOptions, parseArguments } from './chrome-devtools-mcp-cli-options.js';
export const args = parseArguments(VERSION);
```

**After (patched):**

```javascript
import { cliOptions, parseArguments } from './chrome-devtools-mcp-cli-options.js';
// Auto-inject headless mode for container environments without a display server
if (!process.argv.includes('--headless')) {
    process.argv.push('--headless');
}
export const args = parseArguments(VERSION);
```

The guard (`if (!process.argv.includes('--headless'))`) is
idempotent — if `--headless` is already present, nothing happens.

### Why the patch is necessary

The Claude Code proxy launches the MCP server through its own
plugin system, not through the `mcpServers` config in
`~/.claude/settings.json`. The process tree confirms this:

```
npm exec chrome-devtools-mcp@latest
  └─ sh -c "chrome-devtools-mcp"
      └─ node .../node_modules/.bin/chrome-devtools-mcp
```

The node process receives **no** CLI flags:

```bash
cat /proc/<PID>/cmdline | tr '\0' ' '
# node /home/vscode/.npm/_npx/.../node_modules/.bin/chrome-devtools-mcp
```

Approaches that were tried and **did not work**:

- Adding `mcpServers` config with `--headless` in args — the
  proxy ignores this and launches its own instance
- Using `/mcp` to reconnect — reconnects to the same process
  without new flags
- Setting environment variables — no env var controls headless
  mode in the MCP server

## Where to Apply These Changes

Both changes should be applied in the **Dockerfile** or
**entrypoint.sh**, after Playwright Chromium is installed and
after the first `npm exec chrome-devtools-mcp@latest` populates
the npx cache.

### Option A: Dockerfile (build-time)

Add after the Playwright install block (line 1017):

```dockerfile
# Bridge Puppeteer's Chrome lookup to Playwright's Chromium
RUN mkdir -p /opt/google/chrome \
    && ln -sf /home/vscode/.cache/ms-playwright/chromium-1208/chrome-linux/chrome \
              /opt/google/chrome/chrome

# Pre-cache chrome-devtools-mcp and patch for headless mode
RUN npm exec chrome-devtools-mcp@latest -- --version 2>/dev/null || true \
    && MCP_MAIN=$(find /home/vscode/.npm/_npx -name 'chrome-devtools-mcp-main.js' \
                  -path '*/bin/*' 2>/dev/null | head -1) \
    && if [ -n "$MCP_MAIN" ]; then \
         sed -i '/^export const args = parseArguments(VERSION);/i \
// Auto-inject headless mode for container environments without a display server\
\nif (!process.argv.includes('\''--headless'\'')) {\n    process.argv.push('\''--headless'\'');\n}' \
           "$MCP_MAIN"; \
       fi
```

### Option B: entrypoint.sh (runtime)

Add a function that patches the file on first launch:

```bash
patch_chrome_devtools_mcp() {
    local mcp_main
    mcp_main=$(find /home/vscode/.npm/_npx -name 'chrome-devtools-mcp-main.js' \
               -path '*/bin/*' 2>/dev/null | head -1)
    if [ -n "$mcp_main" ] && ! grep -q 'Auto-inject headless' "$mcp_main"; then
        sed -i '/^export const args = parseArguments(VERSION);/i \
// Auto-inject headless mode for container environments without a display server\
\nif (!process.argv.includes('\''--headless'\'')) {\n    process.argv.push('\''--headless'\'');\n}' \
          "$mcp_main"
    fi
}
```

> **Note:** The entrypoint approach handles MCP server updates
> (when `npm exec` fetches a newer version, the patch needs to
> be reapplied).

## Verification

After applying both changes, verify the full stack works:

### 1. Chrome binary responds

```bash
/opt/google/chrome/chrome --headless --no-sandbox --disable-gpu \
    --dump-dom about:blank
# Expected: <html><head></head><body></body></html>
```

### 2. Symlink points to the right binary

```bash
ls -la /opt/google/chrome/chrome
# Expected: symlink -> /home/vscode/.cache/ms-playwright/chromium-1208/chrome-linux/chrome
```

### 3. Patch is in place

```bash
grep -A3 'Auto-inject headless' \
    "$(find /home/vscode/.npm/_npx -name 'chrome-devtools-mcp-main.js' \
       -path '*/bin/*' 2>/dev/null | head -1)"
# Expected:
# // Auto-inject headless mode for container environments without a display server
# if (!process.argv.includes('--headless')) {
#     process.argv.push('--headless');
# }
```

### 4. MCP tools work in Claude Code

After reconnecting with `/mcp`, test navigation and screenshots:

- `navigate_page` to `https://example.com` — should succeed
- `take_screenshot` — should produce a valid PNG
- `take_snapshot` — should return an accessibility tree

### 5. Chrome process runs headless

```bash
ps aux | grep chrome | grep headless
# Expected: process args include --headless=new
```

## Reference: Full File (Patched)

The complete `chrome-devtools-mcp-main.js` after patching:

```javascript
/**
 * @license
 * Copyright 2025 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */
import '../polyfill.js';
import process from 'node:process';
import { createMcpServer, logDisclaimers } from '../index.js';
import { logger, saveLogsToFile } from '../logger.js';
import { computeFlagUsage } from '../telemetry/flagUtils.js';
import { StdioServerTransport } from '../third_party/index.js';
import { VERSION } from '../version.js';
import { cliOptions, parseArguments } from './chrome-devtools-mcp-cli-options.js';
// Auto-inject headless mode for container environments without a display server
if (!process.argv.includes('--headless')) {
    process.argv.push('--headless');
}
export const args = parseArguments(VERSION);
const logFile = args.logFile ? saveLogsToFile(args.logFile) : undefined;
if (process.env['CI'] ||
    process.env['CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS']) {
    console.error(
        "turning off usage statistics. process.env['CI'] || " +
        "process.env['CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS'] is set."
    );
    args.usageStatistics = false;
}
if (process.env['CHROME_DEVTOOLS_MCP_CRASH_ON_UNCAUGHT'] !== 'true') {
    process.on('unhandledRejection', (reason, promise) => {
        logger('Unhandled promise rejection', promise, reason);
    });
}
logger(`Starting Chrome DevTools MCP Server v${VERSION}`);
const { server, clearcutLogger } = await createMcpServer(args, {
    logFile,
});
const transport = new StdioServerTransport();
await server.connect(transport);
logger('Chrome DevTools MCP Server connected');
logDisclaimers(args);
void clearcutLogger?.logDailyActiveIfNeeded();
void clearcutLogger?.logServerStart(computeFlagUsage(args, cliOptions));
```
