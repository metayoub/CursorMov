<p align="center">
  <img src="docs/images/icon.svg" width="112" alt="CursorMov icon">
</p>

<h1 align="center">CursorMov</h1>

<p align="center">
  <b>One click keeps your Mac awake, so your VPN and long-running jobs survive while you're away.</b>
</p>

<p align="center">
  <a href="https://your-username.github.io/cursormov/"><b>Website</b></a>
</p>

<p align="center">
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-000?logo=apple&logoColor=white">
  <img alt="Swift 6.2" src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white">
  <img alt="No dependencies" src="https://img.shields.io/badge/dependencies-none-2ea44f">
</p>

<p align="center">
  <img src="docs/images/menubar-off.svg" width="560" alt="Menu bar with CursorMov off: an empty coffee cup"><br>
  <sub>Off: an empty cup</sub><br><br>
  <img src="docs/images/menubar-on.svg" width="560" alt="Menu bar with CursorMov on: a full, steaming coffee cup"><br>
  <sub>On: a full, steaming cup</sub>
</p>

---

## Why

You start a build, a migration, or a big download, and go grab a coffee. Twenty
minutes later the Mac has locked itself, the VPN has dropped, and the job is gone.

CursorMov is a tiny menu bar app that stops that from happening. Click the cup,
walk away, and your session is still there when you get back.

## Features

- **One click on, one click off.** Left-click the cup in the menu bar.
- **Keeps the Mac awake.** No idle sleep, no screen dimming, no auto-lock while it's on.
- **Mouse nudge (on by default).** When you've been away for a minute, it moves the
  pointer one pixel and straight back. You'll never see it, but macOS and apps that
  watch for activity register you as present.
- **Never gets in your way.** The nudge only happens while you're idle, never while
  you're using the mouse or keyboard.
- **Quiet.** No Dock icon, no window, no notifications. Just a cup.
- **Safe defaults.** It always starts switched off, and quitting releases everything.

## Using it

| Action | What happens |
| --- | --- |
| **Left-click** the cup | Turns keep-awake on or off |
| **Right-click** the cup (or Control-click) | Opens the menu |

<p align="center">
  <img src="docs/images/menu.svg" width="320" alt="Right-click menu: status, Nudge mouse, Start when I log in, Quit">
</p>

- **Keeping Mac awake · 1h 12m** shows how long it's been on.
- **Nudge mouse** turns the mouse nudge on or off. Your choice is remembered.
- **Start when I log in** adds CursorMov to your login items.
- **Quit** (⌘Q) stops CursorMov and lets your Mac sleep normally again.

## Install

### Requirements

- macOS 26 or later
- Xcode 26 (or its command line tools with Swift 6.2)

### Build

```bash
git clone https://github.com/<your-username>/cursormov.git
cd cursormov
scripts/build-app.sh
```

This builds `build/CursorMov.app`. Move it to your Applications folder:

```bash
mv build/CursorMov.app /Applications/
open /Applications/CursorMov.app
```

The empty coffee cup appears in your menu bar.

> **First launch:** the app is signed locally (ad-hoc), not by a registered Apple developer.
> If macOS blocks it, open **System Settings → Privacy & Security** and click **Open Anyway**.

### Allow the mouse nudge

macOS only lets apps move the pointer if you allow it. The first time you turn
CursorMov on with **Nudge mouse** enabled, macOS asks for permission:

1. Click **Open System Settings** in the dialog.
2. In **Privacy & Security → Accessibility**, switch **CursorMov** on.

If you'd rather not grant it, that's fine. Keeping the Mac awake still works without
it, and only the nudge is skipped.

> If you rebuild the app, macOS may treat it as a new app. If the nudge stops working,
> remove CursorMov from the Accessibility list and add it again.

## How it works

- **Keep awake.** When on, CursorMov holds an IOKit power assertion
  (`PreventUserIdleDisplaySleep`). That stops the display and the system from idle
  sleeping, which also stops the idle screen lock. You can see it with
  `pmset -g assertions`.
- **Nudge.** Every 15 seconds it checks how long you've been idle. If it's been at least
  60 seconds, it posts a real mouse-moved event one pixel over and another one back.
  That resets macOS's idle timer just like a hand on the mouse would. If the pointer
  is parked in a screen corner, the nudge is skipped so it can't trigger a Hot Corner
  (such as Lock Screen); keep-awake still works there.

## Limitations

- **Keep the lid open.** macOS always sleeps a MacBook when the lid closes, and no
  regular app can prevent that.
- **VPN-side timeouts.** If your VPN server disconnects sessions with no traffic,
  keeping the Mac awake won't help with that.

## Development

```bash
swift test               # run the test suite
swift build              # debug build
scripts/build-app.sh     # build the .app bundle
```

The project is a Swift package:

```
Sources/CursorMovCore/   core logic (testable) and macOS system adapters
Sources/CursorMov/       the menu bar app (AppKit)
Tests/CursorMovCoreTests/
Resources/Info.plist     app bundle settings (no Dock icon)
scripts/build-app.sh     builds CursorMov.app
```

## License

To be decided.
