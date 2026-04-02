# Contributing

Contributions are welcome! Here's how you can help:

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/your-username/claude-code-switch.git`
3. Create a branch: `git checkout -b feat/my-feature`
4. Make your changes
5. Test your changes: `./ccs help && ./ccs list`
6. Commit using [conventional commits](https://www.conventionalcommits.org/): `git commit -m "feat: add new provider"`
7. Push and open a Pull Request

## Commit Convention

This project uses [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` — new feature (minor version bump)
- `fix:` — bug fix (patch version bump)
- `docs:` — documentation changes
- `refactor:` — code refactoring
- `feat!:` — breaking change (major version bump)

## Guidelines

- Keep it POSIX sh compatible — no bash-isms (`[[ ]]`, arrays, `${var//pattern/replace}`)
- Zero external dependencies — only standard Unix tools
- Test on both macOS and Linux when possible
- Keep the script minimal — this tool is intentionally focused on provider switching only

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
