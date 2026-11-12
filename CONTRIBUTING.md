# Contributing to WorkTimer

Thank you for considering a contribution to WorkTimer! Bug reports, ideas and pull requests are all welcome.

## Before you start

- For a bug, open an issue with the steps to reproduce it, what you expected, and your macOS and Xcode versions.
- For a new feature, open an issue first so we can agree on it before you spend time building it. WorkTimer stays deliberately small: local only, no accounts, no network, no third-party packages.

## How to contribute

1. **Fork and clone** the repository.
2. **Open the project:** `open WorkTimer.xcodeproj` (requires the Xcode version listed in the README and macOS 14 or later).
3. **Create a branch** for your change: `git checkout -b fix/short-description`.
4. **Make your changes.** Follow the folder layout described in the README (`App/`, `Timer/`, `Services/`, `Views/` and so on).
5. **Run the tests** and make sure they pass:
   ```sh
   xcodebuild test -scheme WorkTimer -destination 'platform=macOS'
   ```
   Add tests in `WorkTimerTests/` for new timer, persistence or history logic.
6. **Open a pull request** against `main`. Describe what changed and why, and add a screenshot for any visible UI change.

## Code style

- Follow the style of the surrounding code: 4-space indentation and Swift API Design Guidelines naming.
- Keep views small and put logic in models and services where it can be tested.
- Don't add third-party dependencies.
- Don't commit your signing team: leave `DEVELOPMENT_TEAM` unset in the project file.

## License

By contributing to WorkTimer, you agree that your contributions will be licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
