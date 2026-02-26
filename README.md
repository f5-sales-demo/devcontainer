# Dev Container

[![GitHub Pages Deploy](https://github.com/f5xc-salesdemos/devcontainer/actions/workflows/github-pages-deploy.yml/badge.svg)](https://github.com/f5xc-salesdemos/devcontainer/actions/workflows/github-pages-deploy.yml)
[![Repository Settings](https://github.com/f5xc-salesdemos/devcontainer/actions/workflows/enforce-repo-settings.yml/badge.svg)](https://github.com/f5xc-salesdemos/devcontainer/actions/workflows/enforce-repo-settings.yml)
[![License](https://img.shields.io/github/license/f5xc-salesdemos/devcontainer)](LICENSE)

Isolated development environment with AI coding tools

## Getting Started

```bash
mkdir devcontainer && cd devcontainer
curl -fsSLO https://raw.githubusercontent.com/f5xc-salesdemos/devcontainer/main/docker-compose.yml
docker compose up -d
docker compose exec dev zsh
```

See the [documentation](https://f5xc-salesdemos.github.io/devcontainer/) for configuration, local development, and Visual Studio Code setup.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for workflow rules,
branch naming, and CI requirements.

## License

See [LICENSE](LICENSE).
