# Security

This devcontainer is designed to run AI coding tools in an isolated environment, addressing security concerns around running these tools directly on corporate endpoints.

## Background

In February 2025, [LayerX Security Research](https://layerxsecurity.com/blog/claude-desktop-extensions-rce/) disclosed a critical zero-click remote code execution (RCE) vulnerability in Anthropic's Claude Desktop Extensions (DXT) framework. The vulnerability affects the Claude Desktop application and its extension ecosystem, where extensions run unsandboxed with full system privileges, acting as privileged execution bridges between the language model and the local operating system.

Many corporate security teams now require that AI coding tools be run only inside dedicated virtual machines, containers, or disposable environments — not directly on corporate endpoints.

**This devcontainer satisfies that requirement.**

## Isolation Model

```
┌────────────────────────────────────────────┐
│  Host Machine (corporate endpoint)         │
│                                            │
│  ● No AI tool binaries installed           │
│  ● No AI tool extensions or plugins        │
│  ● Only Docker is required                 │
│                                            │
│  ┌──────────────────────────────────────┐  │
│  │  Docker Container (isolated)         │  │
│  │                                      │  │
│  │  AI tools run here:                  │  │
│  │  - Claude Code CLI                   │  │
│  │  - OpenCode                          │  │
│  │  - Codex                             │  │
│  │                                      │  │
│  │  No access to:                       │  │
│  │  ✗ Host filesystem                   │  │
│  │  ✗ Host keychain / credential store  │  │
│  │  ✗ Host clipboard                    │  │
│  │  ✗ Host network interfaces           │  │
│  │  ✗ Other host applications           │  │
│  └──────────────────────────────────────┘  │
└────────────────────────────────────────────┘
```

## Security Controls

### No Host Volume Mounts

All data lives in Docker named volumes. No host directories are bind-mounted into the container. A compromise inside the container cannot access files on the host.

### No Shared Credential Stores

The container has no access to the host's keychain, credential manager, or browser profiles. SSH keys are injected at startup via a base64-encoded environment variable — they exist only inside the container's ephemeral filesystem.

### No Clipboard Sync

Docker containers do not share clipboard state with the host. Data cannot leak through copy/paste between the container and host.

### Network Isolation

The container communicates only with:
- The API proxy sidecar (internal Docker network)
- The configured API endpoint (outbound HTTPS)

It has no access to the host's VPN tunnels, corporate network interfaces, or other services running on the host.

### Ephemeral by Design

Running `docker compose down -v` destroys all container data, volumes, and state. The environment can be fully recreated from the configuration files. Treat the container as disposable.

### No Desktop Extensions

This environment runs AI tools as **command-line interfaces only** — not as desktop applications with extension frameworks. The DXT vulnerability (CVE-free as of disclosure, affects Claude Desktop Extensions) does not apply to CLI-only usage inside a container.

## Compliance Checklist

| Requirement | Status |
|---|---|
| AI tools not installed on host endpoint | ✅ Tools are inside the container only |
| Run in VM or isolated environment | ✅ Docker container provides isolation |
| No access to host file shares | ✅ No bind mounts — Docker volumes only |
| No clipboard sync | ✅ No shared clipboard |
| No shared credential stores | ✅ No keychain/credential manager access |
| No VPN split tunneling into prod networks | ✅ Container uses Docker network only |
| Environment is disposable | ✅ `docker compose down -v` destroys everything |
| No desktop extensions or plugins | ✅ CLI-only tools, no DXT framework |

## Recommendations

1. **Do not install AI coding tools on your host machine.** Use this container instead.
2. **Do not bind-mount host directories** into the container. The docker-compose.yml is configured to use named volumes only.
3. **Rotate SSH keys** used inside the container periodically.
4. **Review `.env` contents** before sharing — it may contain API keys and SSH private keys.
5. **Keep the container updated** — rebuild periodically to get security patches: `docker compose up -d --build`

## References

- [LayerX: Claude Desktop Extensions RCE Vulnerability](https://layerxsecurity.com/blog/claude-desktop-extensions-rce/)
- [Dev Containers Specification](https://containers.dev/)
- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
