# CursorMov — menu bar keep-awake app

Date: 2026-10-15

## Intent and why

The user runs long jobs on their Mac and walks away. After a stretch of
inactivity the Mac locks itself, and when it does the VPN connection drops
and the session is lost. They want a tiny menu bar app that, while switched
on, keeps the session alive: the Mac must not sleep, dim, or lock, and the
VPN must stay connected.

**The main goal is keeping the session alive.** Everything else is secondary.

## What it is

A native macOS menu bar app (no Dock icon, no main window). It shows a
coffee cup icon next to the other menu bar icons (Wi‑Fi, battery, clock).

### Interaction

- **Left-click the cup** → toggles on/off. One click, nothing else.
- **Right-click the cup** → a small menu:
  - Status line, e.g. `Keeping Mac awake · 1h 12m` while on (time since it
    was switched on), or `Off` when off. Not clickable.
  - `Nudge mouse` — checkbox, **on by default**.
  - `Start when I log in` — checkbox, off by default.
  - `Quit`.

### Icon

- Off: an outlined empty coffee cup.
- On: a filled coffee cup with steam lines.
- Monochrome template image so it adapts to light/dark menu bars like the
  system icons do. The user picked the coffee cup from mockups (see
  `.superpowers/brainstorm/*/content/icon-and-menu.html`).

### While on

1. **Keep awake (primary mechanism).** Ask macOS not to idle-sleep the
   display or the system, which also prevents the idle screen lock. Release
   the request when switched off or on quit.
2. **Mouse nudge (backup, enabled by default, user can disable).** About
   once a minute, if the user has been idle, move the pointer by one pixel
   and straight back so it is imperceptible. The nudge must register with
   macOS as real user activity (i.e. reset the system idle timer), not just
   reposition the cursor silently — this is what covers a forced
   company screen-lock policy or apps that watch for user activity.
   Never nudge while the user is actively using the mouse/keyboard.

### State on launch

- App always launches in the **off** state; it never keeps the Mac awake
  unless the user asked in this run.
- `Nudge mouse` and `Start when I log in` preferences persist across
  launches.

## Goals

- One click to keep the session alive; one click to stop.
- Session survives hours of inactivity without locking, sleeping, or
  dropping the VPN.
- Invisible otherwise: no window, no Dock icon, no notifications.

## Final deliverable: README for GitHub

The user wants to publish the project on GitHub. Once the app works, write
a polished `README.md` that presents it: what it does and why, a picture of
the menu bar icon (off/on) and right-click menu, how to build/install it,
the Accessibility permission note, and the lid-open caveat. The project
folder should be a git repository so it can be pushed. Pushing to GitHub
itself is done only when the user says so.

Also a **GitHub Pages site**: a single landing page presenting the app
(same story and images as the README) with a clear "build it and start
using it" walkthrough. It's deployed by a GitHub Actions workflow once the
repo is pushed and Pages is enabled with source "GitHub Actions".

## Non-goals

- Schedules and "until a time of day" pickers. (Timed sessions and battery
  auto-off were added on 2026-10-15 at the user's request; see below.)
- Distribution (App Store, notarization). This is for the user's own Mac.
- Settings window.

## Anti-goals

- Moving the pointer while the user is working.
- Silently staying on after the user thinks it's off, or after quitting.
- Anything aimed at deceiving monitoring software beyond keeping the
  session alive.

## Constraints

- macOS 26 (user's Mac: macOS 26.5), Xcode 26.1, Swift 6.2.
- The Mac is a laptop (MacBook, `Mac16,1`). The user leaves the **lid
  open** when walking away, so closed-lid sleep is a non-goal: no admin
  rights, privileged helper, or `pmset disablesleep`.
- The Mac is **not** MDM-managed (`profiles status`: no DEP, no MDM), so
  there's no forced lock policy from IT and the user can grant
  Accessibility permission if the nudge needs it.
- VPN client is FortiClient (OpenVPN Connect is also installed). The user
  reports coming back to a **locked** Mac with the VPN dropped, so the
  design treats the lock/sleep as the cause. A VPN-side traffic idle
  timeout is out of scope unless keeping the Mac awake turns out not to be
  enough.
- Native Swift app. *(Claude's call — standard for menu bar apps; user
  didn't express a preference.)*

## Claude's calls (user didn't specify)

- Nudge interval ~60 s and "idle" threshold ~60 s.
- Launch-at-login off by default.
- Starts off on every launch.
- No Dock icon.
- Name: CursorMov (from the project folder).

## Left to the builder

- AppKit vs SwiftUI structure (note: left-click toggle + right-click menu
  is easiest with `NSStatusItem`).
- Exact APIs for power assertions, idle detection, synthetic mouse events,
  and login items.
- How to handle any macOS permission the nudge needs (e.g. Accessibility):
  ask once, clearly, and if it's denied the keep-awake part must still work.
- Icon drawing (SF Symbols or custom template images) matching the
  mockup's spirit.
- Project layout, build setup, tests.

## Additions (2026-10-15, user-approved)

- **Accessibility warning:** when the nudge is enabled but not trusted, the
  menu shows `⚠︎ Allow mouse nudge in Accessibility…`, opening that pane.
- **Timed sessions:** `Keep awake for` submenu with 15 min, 30 min, 1 h, 2 h,
  4 h. Left-click stays indefinite. Status reads
  `Keeping Mac awake · 25m left · until 15:30`; switches off at the end.
- **Battery safety:** `Turn off below battery` submenu: Never, 10%, 20%
  (default), 30%. Turns off when, on battery, the level drops to the
  threshold during a session (already-low at turn-on is respected). Status
  then reads `Off · battery below 20%`. No notification.
- Tooltip is a static `CursorMov — On/Off`; `Start when I log in` opens Login
  Items settings when macOS requires approval.

