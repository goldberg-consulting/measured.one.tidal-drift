# Contributing to TidalDrift

Thank you for your interest in contributing to TidalDrift. This document covers the setup, workflow, and conventions for the project.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/TidalDrift.git`
3. Ensure Xcode is selected: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
4. Build and run: `cd TidalDrift && ./build-app.sh`

## Development Workflow

- Create a feature branch from `main`: `git checkout -b feature/your-feature`
- Make your changes
- Run local checks: `cd TidalDrift && swift build && swift test`
- Run the in-app test suite: **Settings > Tests > Run All Tests**
- Verify the build completes: `cd TidalDrift && ./build-app.sh`
- Submit a pull request targeting `main`

## CI and Release Notes

- CI runs `swiftlint`, `swift build`, `swift test`, and `xcodebuild` for the `TidalDrift` scheme with code signing disabled.
- Release notarization credentials are loaded from `TidalDrift/.env` and should never be committed.
- Apple Developer notarization credentials are only required for `./build-release.sh` without `--skip-notarize`.
- Build version metadata is sourced from `TidalDrift/version.env` (`APP_VERSION`, `BUILD_NUMBER`).
- `build-release.sh` does not copy artifacts to a network share unless you opt in with `COPY_TO_SHARE=1`.

## Code Style

- Follow existing Swift conventions in the codebase
- Use `Logger` (os.log) for structured logging; do not use `print` in production paths
- Avoid adding third-party dependencies. TidalDrift is built entirely with Apple frameworks.
- Keep views composable and small; extract reusable components

## Areas for Contribution

- **LocalCast app-window streaming**: the custom streaming pipeline is architecturally complete but not yet fully implemented. See [TidalDrift/LocalCast/README.md](TidalDrift/LocalCast/README.md) for the current state.
- **Linux/cross-platform support** for the networking layer
- **Improved codec support** (AV1, VP9)
- **Audio streaming** over LocalCast
- **Error recovery** in the UDP transport layer
- **Accessibility** improvements
- **Localization** to other languages

## Reporting Issues

File issues on GitHub with:
- macOS version
- Steps to reproduce
- Relevant logs (from Console.app, filter by `com.tidaldrift`)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
