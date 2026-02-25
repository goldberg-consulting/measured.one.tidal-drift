# Contributing to TidalDrift

Thanks for your interest in contributing to TidalDrift. Here's how to get started.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/TidalDrift.git`
3. Make sure Xcode is selected: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
4. Build and run: `cd TidalDrift && ./build-app.sh`

## Development Workflow

- Create a feature branch from `main`: `git checkout -b feature/your-feature`
- Make your changes
- Run the in-app test suite: **Settings > Tests > Run All Tests**
- Verify the build completes: `cd TidalDrift && ./build-app.sh`
- Submit a pull request

## Code Style

- Follow existing Swift conventions in the codebase
- Use `Logger` (os.log) for structured logging, not `print` in production paths
- Avoid adding third-party dependencies -- TidalDrift is built entirely with Apple frameworks
- Keep views composable and small; extract reusable components

## Areas for Contribution

- **Linux/cross-platform support** for the networking layer
- **Improved codec support** (AV1, VP9)
- **Audio streaming** over LocalCast
- **Better error recovery** in the UDP transport layer
- **Accessibility** improvements
- **Localization** to other languages

## Reporting Issues

File issues on GitHub with:
- macOS version
- Steps to reproduce
- Relevant logs (from Console.app, filter by `com.tidaldrift`)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
