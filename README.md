# WorkTimer

[![CI](https://github.com/leandreAlly/worktimer/actions/workflows/ci.yml/badge.svg)](https://github.com/leandreAlly/worktimer/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)

A minimalist focus timer for macOS. Commit to a task for a set time, watch
it count down on split-flap digits, then review how it went. Everything
stays on this Mac: no account, no sync, no network.

Built with Swift, SwiftUI, SwiftData, Swift Charts and UserNotifications.
No third-party packages. Requires macOS 14 Sonoma or later.

## Build and install

You need Xcode 27 or later installed in `/Applications` (the project file uses the Xcode 27 format).

```sh
git clone https://github.com/leandreAlly/worktimer.git
cd worktimer
```

### From Xcode

1. Open `WorkTimer.xcodeproj`.
2. Choose **Product › Scheme › Edit Scheme… › Run › Build Configuration ›
   Release**.
3. **Product › Build** (⌘B).
4. Xcode doesn't put the app in the project folder. It builds into its own
   DerivedData folder:
   `~/Library/Developer/Xcode/DerivedData/WorkTimer-<random>/Build/Products/Release/WorkTimer.app`.
   To get there, use **Product › Show Build Folder in Finder**, which opens the
   `Build` folder, then open **Products › Release**.
5. Quit any running WorkTimer, then drag `WorkTimer.app` into `/Applications`.
6. Set the Build Configuration back to **Debug** for everyday development.

### From Terminal

```sh
# Build a Release copy into build/Release
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme WorkTimer -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/Release build

# Quit any running copy, then install it
osascript -e 'tell application id "ally.WorkTimer" to quit'
ditto build/Release/Build/Products/Release/WorkTimer.app /Applications/WorkTimer.app
open /Applications/WorkTimer.app
```

`DEVELOPER_DIR` is only needed when `xcode-select -p` points at the Command
Line Tools instead of Xcode. `ditto` copies the app bundle with its code
signature intact.

The app is signed "to run locally", which is all a Mac needs to run an app
you built yourself. To give it to someone else you would sign it with a
Developer ID and notarize it.

### Run the tests

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -scheme WorkTimer -destination 'platform=macOS'
```

## Notifications

WorkTimer posts a notification when time is up or a break ends, even if the
app is closed by then.

1. The first time you start a timed session, macOS asks whether WorkTimer may
   send notifications. Click **Allow**.
2. If you missed it, or clicked **Don't Allow**: open **System Settings ›
   Notifications › WorkTimer** and turn on **Allow notifications**. Choose
   **Banners** or **Alerts**, and keep **Play sound for notifications** on to
   hear the bell when WorkTimer is in the background.
   WorkTimer's Settings shows **Open System Settings** under "Notify when time is
   up" when macOS has notifications turned off for it.
3. Notifications are time sensitive, so they get through a Focus mode. To
   stop that, turn off **Time Sensitive Notifications** for WorkTimer in the
   same place.

To turn notifications off inside WorkTimer instead, use **Settings › Sound &
notifications › Notify when time is up**. The bell still plays when the
timer finishes while WorkTimer is open.

## Using it

| Key | Does |
|---|---|
| ⌘↵ | Commit on Ready, finish & log while working, open or confirm Review |
| Space | Commit, then pause / resume |
| 1 2 3 · 4 · C | Presets (editable in Settings) · no limit · custom minutes |
| Hold R | Discard a paused session (one second) |
| D · M · L | Review: done · need more time · continue later |
| ⌘\ | Full window → compact → mini → full |
| ⌃⌘F | Presentation mode (Esc leaves) |
| ⌘Y | History |
| ⇧⌘E | Export history as CSV (in History) |
| ⌘, | Settings |
| ⌃⌥Space | Show or hide WorkTimer from any app |

The menu bar shows the time left while a session runs; click it for quick
controls.

## Where data lives

The app is sandboxed, so everything is inside its container:

- History: `~/Library/Containers/ally.WorkTimer/Data/Library/Application Support/default.store`
  (SwiftData).
- The session in progress and settings:
  `~/Library/Containers/ally.WorkTimer/Data/Library/Preferences/ally.WorkTimer.plist`.

**History › Export CSV…** writes every session to a file you choose. To start
over, quit WorkTimer and delete `~/Library/Containers/ally.WorkTimer`.

## Project layout

```
WorkTimer/
  App/        App entry, shared models, keyboard, window modes, menu bar clock
  Timer/      The timer engine and its state, time source and dependencies
  Models/     SwiftData model (WorkSession)
  Services/   Persistence, notifications and chime, history maths, CSV, hot key
  Design/     Palette, typography, split-flap clock, buttons
  Views/      Screens: Ready, Focus, Review, compact, menu bar, history,
              presentation, settings
  Resources/  Bundled fonts (SIL OFL, licences included) and the bell
WorkTimerTests/  Engine, persistence, interaction, history and settings tests
```

Debug builds accept `-WTPreviewState <focusing|openended|long|paused|almostup|break|review|ready>`
and `-WTPreviewMode <compact|mini|menu|history|settings|presentation>` to open
straight into a sample state with an in-memory database, for design checks.
Release builds don't include this code.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening an issue or pull request.

## License

WorkTimer is released under the [MIT License](LICENSE). The bundled Inter Tight and JetBrains Mono fonts are under the SIL Open Font License; their licences are in `WorkTimer/Resources/Fonts/`.
