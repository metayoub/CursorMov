# CursorMov Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu bar app (coffee cup icon) that, while switched on, keeps the Mac from sleeping/locking and optionally nudges the mouse when the user is idle, so long jobs and the VPN session survive.

**Architecture:** Swift Package with two targets: `CursorMovCore` (pure, testable logic behind small protocols plus the macOS system adapters) and `CursorMov` (executable: AppKit `NSStatusItem` UI). A shell script assembles the release binary into `CursorMov.app` with `LSUIElement` so there's no Dock icon. The controller is driven by a 60 s timer and talks to the system only through injected protocols, so all behaviour is unit-tested with fakes.

**Tech Stack:** Swift 6.2, Swift Package Manager, Swift Testing (`import Testing`), AppKit, IOKit power assertions, CoreGraphics events, ServiceManagement (`SMAppService`). Xcode 26.1 toolchain, macOS 26.

**Spec:** `docs/superpowers/specs/2026-10-15-cursormov-design.md`

## Global Constraints

- Deployment target: macOS 26 (`platforms: [.macOS(.v26)]`); Swift tools 6.2.
- No third-party dependencies.
- App name / bundle: `CursorMov`, bundle id `com.cursormov.CursorMov`, `LSUIElement = true` (no Dock icon, no window).
- App always launches **off**. `Nudge mouse` defaults **on**; `Start when I log in` defaults **off**. Both persist.
- Status line copy, exactly: `Keeping Mac awake · <elapsed>` when on, `Off` when off. Menu items, exactly: `Nudge mouse`, `Start when I log in`, `Quit`.
- Icon: SF Symbol `cup.and.saucer` (off), `cup.and.heat.waves.fill` (on), as template images.
- Nudge interval 60 s; nudge only when user idle ≥ 60 s; move 1 px and straight back.
- Left-click toggles; right-click opens the menu.
- Releasing the keep-awake assertion on off and on quit is mandatory.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Never push to GitHub; the user does that.

## Review Focus

1. **Quit while on** → assertion released, Mac can sleep again. (Test in Task 2: `turnOff` releases; Task 5 wires `applicationWillTerminate` → `turnOff`; manual check via `pmset -g assertions`.)
2. **User actively working** → pointer is never moved. (Task 3: `tickDoesNotNudgeWhenUserRecentlyActive`.)
3. **Accessibility denied** → keep-awake still works, nudge is skipped silently, user is prompted at most once per run. (Task 3: `untrustedSkipsNudgeButStaysOn`, `promptsForAccessAtMostOnce`.)
4. **Double toggle / turnOff while off** → no leaked or double-released assertion. (Task 2: `turnOnTwiceAcquiresOnce`, `turnOffWhenOffDoesNothing`.)
5. **Nudge disabled mid-session** → next tick does not nudge; pointer always returns to its exact start point, including at a screen edge. (Task 3: `disablingNudgeStopsNudging`; Task 4: `nudgeReturnsPointerToStart` manual check at screen corner.)

---

### Task 1: Package scaffold, git, elapsed-time formatting

**Files:**
- Create: `Package.swift`, `.gitignore`, `Sources/CursorMovCore/ElapsedFormat.swift`, `Sources/CursorMov/main.swift` (placeholder `print("CursorMov")`), `Tests/CursorMovCoreTests/ElapsedFormatTests.swift`

**Interfaces:**
- Produces: `public func formatElapsed(_ seconds: TimeInterval) -> String`

- [ ] **Step 1: `git init`, add `.gitignore`** containing `.build/`, `build/`, `*.app`, `.superpowers/`, `.DS_Store`, `.swiftpm/`.

- [ ] **Step 2: Write `Package.swift`** — tools 6.2, platform `.macOS(.v26)`, library target `CursorMovCore`, executable target `CursorMov` depending on it, test target `CursorMovCoreTests`.

- [ ] **Step 3: Write the failing test**

```swift
import Testing
@testable import CursorMovCore

@Test func formatsElapsed() {
    #expect(formatElapsed(0) == "0m")
    #expect(formatElapsed(59) == "0m")
    #expect(formatElapsed(45 * 60) == "45m")
    #expect(formatElapsed(72 * 60) == "1h 12m")
    #expect(formatElapsed(3 * 3600) == "3h 0m")
    #expect(formatElapsed(-5) == "0m")
}
```

- [ ] **Step 4: Run** `swift test` — Expected: FAIL, `formatElapsed` not found.

- [ ] **Step 5: Implement `formatElapsed`** — floor to whole minutes, clamp negatives to 0; `"<m>m"` under an hour, else `"<h>h <m>m"`.

- [ ] **Step 6: Run** `swift test` — Expected: PASS. Also `swift build` succeeds.

- [ ] **Step 7: Commit** `chore: scaffold Swift package with elapsed-time formatting`

---

### Task 2: KeepAwakeController — on/off and status text

**Files:**
- Create: `Sources/CursorMovCore/Protocols.swift`, `Sources/CursorMovCore/KeepAwakeController.swift`, `Tests/CursorMovCoreTests/Fakes.swift`, `Tests/CursorMovCoreTests/KeepAwakeControllerTests.swift`

**Interfaces:**
- Consumes: `formatElapsed(_:)`
- Produces (all `public`):

```swift
public protocol KeepAwakeAssertion: AnyObject {
    /// Returns false if macOS refused the assertion.
    func acquire() -> Bool
    func release()
}
public protocol IdleTimeSource { func secondsSinceLastUserInput() -> TimeInterval }
public protocol MouseNudger { func nudge() }
public protocol AccessibilityAuthority {
    var isTrusted: Bool { get }
    func promptForAccess()
}
public protocol SettingsStore: AnyObject { var nudgeEnabled: Bool { get set } }

@MainActor public final class KeepAwakeController {
    public static let tickInterval: TimeInterval = 60
    public static let nudgeIdleThreshold: TimeInterval = 60
    public init(assertion: KeepAwakeAssertion, idle: IdleTimeSource, nudger: MouseNudger,
                accessibility: AccessibilityAuthority, settings: SettingsStore,
                now: @escaping () -> Date = Date.init)
    public private(set) var isOn: Bool          // false at init
    public private(set) var onSince: Date?
    public var onStateChange: ((Bool) -> Void)? // fired after isOn changes
    public var nudgeEnabled: Bool { get set }   // forwards to settings
    public func toggle()
    public func turnOn()
    public func turnOff()
    public func tick()                          // implemented in Task 3; empty here
    public func statusText() -> String
}
```

- [ ] **Step 1: Write fakes** in `Fakes.swift`: `FakeAssertion` (counts `acquireCount`/`releaseCount`, `acquireResult = true`), `FakeIdle` (settable `seconds`), `FakeNudger` (`nudgeCount`), `FakeAccessibility` (`isTrusted`, `promptCount`), `FakeSettings` (`nudgeEnabled = true`), and a mutable clock.

- [ ] **Step 2: Write the failing tests**

```swift
@MainActor @Test func startsOff()                 // isOn == false, onSince == nil, statusText() == "Off"
@MainActor @Test func toggleTurnsOnAndAcquires()  // isOn, acquireCount == 1, onSince == clock
@MainActor @Test func toggleTwiceReleases()       // !isOn, releaseCount == 1, onSince == nil
@MainActor @Test func turnOnTwiceAcquiresOnce()   // acquireCount == 1
@MainActor @Test func turnOffWhenOffDoesNothing() // releaseCount == 0
@MainActor @Test func failedAcquireStaysOff()     // acquireResult = false → isOn == false, onStateChange not fired
@MainActor @Test func statusTextShowsElapsed()    // on at T, clock T+72min → "Keeping Mac awake · 1h 12m"
@MainActor @Test func notifiesStateChanges()      // onStateChange receives [true, false] across two toggles
@MainActor @Test func nudgeEnabledForwardsToSettings() // set false → settings.nudgeEnabled == false
```

- [ ] **Step 3: Run** `swift test` — Expected: FAIL (types missing).

- [ ] **Step 4: Implement** protocols and controller per the interfaces above.

- [ ] **Step 5: Run** `swift test` — Expected: all PASS.

- [ ] **Step 6: Commit** `feat: keep-awake controller with on/off and status text`

---

### Task 3: Idle-aware mouse nudge in `tick()`

**Files:**
- Modify: `Sources/CursorMovCore/KeepAwakeController.swift`
- Test: `Tests/CursorMovCoreTests/NudgeTests.swift`

**Interfaces:**
- Consumes: Task 2 controller and fakes.
- Produces: `tick()` behaviour; `turnOn()` and `nudgeEnabled = true` may call `accessibility.promptForAccess()`.

Rules: `tick()` nudges iff `isOn && nudgeEnabled && accessibility.isTrusted && idle.secondsSinceLastUserInput() >= nudgeIdleThreshold`. When turning on (or enabling nudge while on) with nudge enabled and not trusted, call `promptForAccess()` — at most once per controller lifetime.

- [ ] **Step 1: Write the failing tests**

```swift
@MainActor @Test func tickNudgesWhenIdle()                     // on, trusted, idle 60 → nudgeCount == 1
@MainActor @Test func tickDoesNotNudgeWhenUserRecentlyActive() // idle 59 → 0
@MainActor @Test func tickDoesNothingWhenOff()                 // off, idle 600 → 0
@MainActor @Test func disablingNudgeStopsNudging()             // on, tick (1), nudgeEnabled = false, tick → still 1
@MainActor @Test func untrustedSkipsNudgeButStaysOn()          // isTrusted false, idle 600, tick → 0, isOn == true
@MainActor @Test func promptsForAccessAtMostOnce()             // untrusted: on, off, on, nudge false→true → promptCount == 1
@MainActor @Test func noPromptWhenNudgeDisabled()              // nudgeEnabled false, untrusted, turnOn → promptCount == 0
@MainActor @Test func noPromptWhenTrusted()                    // trusted, turnOn → promptCount == 0
```

- [ ] **Step 2: Run** `swift test` — Expected: new tests FAIL.

- [ ] **Step 3: Implement** the rules above.

- [ ] **Step 4: Run** `swift test` — Expected: all PASS.

- [ ] **Step 5: Commit** `feat: nudge mouse only when user is idle and nudge is enabled`

---

### Task 4: macOS system adapters

**Files:**
- Create: `Sources/CursorMovCore/System/PowerAssertion.swift`, `System/SystemIdleTime.swift`, `System/CGMouseNudger.swift`, `System/SystemAccessibility.swift`, `System/UserDefaultsSettings.swift`, `System/LoginItem.swift`
- Test: `Tests/CursorMovCoreTests/SystemAdapterTests.swift`

**Interfaces:**
- Consumes: protocols from Task 2.
- Produces:
  - `public final class PowerAssertion: KeepAwakeAssertion` — `IOPMAssertionCreateWithName` with `kIOPMAssertionTypePreventUserIdleDisplaySleep`, name `"CursorMov is keeping the Mac awake"`; `release()` is a no-op when nothing held; `deinit` releases.
  - `public struct SystemIdleTime: IdleTimeSource` — `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)`.
  - `public struct CGMouseNudger: MouseNudger` — read current location, post `.mouseMoved` CGEvent to `(x+1, y)` (use `x-1` if `x+1` is outside every display), then post `.mouseMoved` back to the original point.
  - `public struct SystemAccessibility: AccessibilityAuthority` — `AXIsProcessTrusted()`; prompt via `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt: true`.
  - `public final class UserDefaultsSettings: SettingsStore` — `init(defaults: UserDefaults = .standard)`, key `"nudgeEnabled"`, registered default `true`.
  - `public protocol LoginItemControlling { var isEnabled: Bool { get }; func setEnabled(_ enabled: Bool) throws }` and `public struct LoginItem: LoginItemControlling` over `SMAppService.mainApp` (`isEnabled` = `status == .enabled`). SMAppService is the source of truth; nothing stored in defaults.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func settingsDefaultNudgeOn()     // fresh UserDefaults(suiteName: UUID) → nudgeEnabled == true
@Test func settingsPersistNudge()       // set false, new UserDefaultsSettings on same suite → false
@Test func powerAssertionAppearsAndClears() {
    // acquire() == true; IOPMCopyAssertionsByProcess contains our name for getpid();
    // release(); our name no longer present; second release() does not crash
}
@Test func idleTimeIsNonNegative()      // SystemIdleTime().secondsSinceLastUserInput() >= 0
```

- [ ] **Step 2: Run** `swift test` — Expected: FAIL.

- [ ] **Step 3: Implement** the adapters.

- [ ] **Step 4: Run** `swift test` — Expected: all PASS.

- [ ] **Step 5: Commit** `feat: macOS adapters for power assertion, idle time, nudge, accessibility, settings, login item`

---

### Task 5: Menu bar app and `.app` bundle

**Files:**
- Create: `Sources/CursorMov/AppDelegate.swift`, `Sources/CursorMov/StatusItemController.swift`, `Resources/Info.plist`, `scripts/build-app.sh`
- Modify: `Sources/CursorMov/main.swift`

**Interfaces:**
- Consumes: `KeepAwakeController`, all Task 4 adapters, `LoginItemControlling`.
- Produces: `build/CursorMov.app` via `scripts/build-app.sh`.

- [ ] **Step 1: `main.swift`** — `NSApplication.shared`, `setActivationPolicy(.accessory)`, set `AppDelegate`, `run()`.

- [ ] **Step 2: `AppDelegate`** — builds the controller with real adapters; starts a `Timer` every `KeepAwakeController.tickInterval` calling `tick()`; owns `StatusItemController`; `applicationWillTerminate` calls `controller.turnOff()`.

- [ ] **Step 3: `StatusItemController`** — `NSStatusItem` with `button.sendAction(on: [.leftMouseUp, .rightMouseUp])`. Left-up → `controller.toggle()`. Right-up (or control-click) → build an `NSMenu` and pop it up via `statusItem.menu = menu; button.performClick(nil); statusItem.menu = nil`. Menu: disabled item with `controller.statusText()`, separator, `Nudge mouse` (checkmark = `controller.nudgeEnabled`), `Start when I log in` (checkmark = `loginItem.isEnabled`; on error show an `NSAlert` with the error text), separator, `Quit` (⌘Q, `NSApp.terminate`). Icon updates via `onStateChange`: `NSImage(systemSymbolName:accessibilityDescription:)` with `isTemplate = true`; tooltip mirrors status text.

- [ ] **Step 4: `Resources/Info.plist`** — `CFBundleIdentifier com.cursormov.CursorMov`, `CFBundleName CursorMov`, `CFBundleExecutable CursorMov`, `CFBundleShortVersionString 1.0.0`, `LSMinimumSystemVersion 26.0`, `LSUIElement true`.

- [ ] **Step 5: `scripts/build-app.sh`** — `swift build -c release`, create `build/CursorMov.app/Contents/{MacOS,Resources}`, copy binary and Info.plist, `codesign --force --sign - build/CursorMov.app`. Prints the app path. `set -euo pipefail`.

- [ ] **Step 6: Verify build** — Run `scripts/build-app.sh && open build/CursorMov.app`. Expected: empty cup in menu bar, no Dock icon.

- [ ] **Step 7: Verify behaviour manually** (report each result):
  - Left-click → steaming cup; `pmset -g assertions | grep CursorMov` shows `PreventUserIdleDisplaySleep`.
  - Right-click → menu shows `Keeping Mac awake · 0m`, `Nudge mouse` ✓, `Start when I log in`, `Quit`.
  - Left-click again → empty cup; `pmset` line gone.
  - Turn on, then Quit from menu → `pmset` line gone.
  - With Accessibility granted and nudge on, leave idle > 2 min → no lock; pointer position unchanged to the eye. Repeat with pointer parked in a screen corner.
  - `swift test` still PASS.

- [ ] **Step 8: Commit** `feat: menu bar app with coffee cup toggle and right-click menu`

---

### Task 6: GitHub README

**Files:**
- Create: `README.md`, `docs/images/menubar-off.svg`, `docs/images/menubar-on.svg`, `docs/images/menu.svg`

- [ ] **Step 1: Draw the images** — SVG recreations of the menu bar with the empty cup, with the steaming cup, and of the right-click menu (based on `.superpowers/brainstorm/*/content/icon-and-menu.html`, using the actual SF Symbol shapes' spirit). If a real screenshot of the running app can be captured (`screencapture -R`), prefer it as PNG.

- [ ] **Step 2: Write `README.md`** — sections: title + one-line pitch + images; Why (long jobs, VPN drops when the Mac locks); Features; Requirements (macOS 26, Xcode 26 / Swift 6.2); Build & install (`scripts/build-app.sh`, move to `/Applications`, first-launch Gatekeeper note for ad-hoc signed apps); Usage (left-click / right-click); Accessibility permission (why the nudge needs it, how to grant, note that rebuilding with ad-hoc signing may require re-granting); Limitations (lid must stay open; doesn't defeat VPN-side traffic timeouts); How it works (power assertion + idle-aware nudge); Development (`swift test`); License placeholder line to fill in once the user picks one.

- [ ] **Step 3: Verify** — every relative link/image path in README exists (`grep -o '](docs/[^)]*' README.md | cut -c3- | xargs ls`).

- [ ] **Step 4: Commit** `docs: add README for GitHub`

---

### Task 7: GitHub Pages site

**Files:**
- Create: `site/index.html`, `site/images/` (copies of `docs/images/*`), `.github/workflows/pages.yml`
- Modify: `README.md` (add "Website" link placeholder `https://<user>.github.io/<repo>/`)

**Interfaces:**
- Consumes: README content and images from Task 6.

- [ ] **Step 1: Write `site/index.html`** — one self-contained page (inline CSS, no JS frameworks, no external assets except optional Google Fonts), light/dark via `prefers-color-scheme`, readable at phone width. Sections: hero (coffee cup, name, one-line pitch, "Get started" anchor + GitHub link placeholder), the problem (Mac locks → VPN drops), how it works (keep-awake + idle-aware nudge), screenshots (`images/…`), **Get started** as numbered steps (requirements → `git clone` → `scripts/build-app.sh` → move to `/Applications` → first launch/Gatekeeper → grant Accessibility → left-click to start), using it (left/right click, menu items), limitations (lid open, VPN-side timeouts), footer.

- [ ] **Step 2: Write `.github/workflows/pages.yml`** — on push to `main` + `workflow_dispatch`; permissions `pages: write`, `id-token: write`, `contents: read`; `actions/configure-pages@v5`, `actions/upload-pages-artifact@v3` with `path: site`, `actions/deploy-pages@v4`.

- [ ] **Step 3: Verify** — `python3 -m http.server -d site 8765` and load `http://localhost:8765/`: all images load (no 404s in server log), the "Get started" anchor works; YAML parses (`ruby -ryaml -e 'YAML.load_file(".github/workflows/pages.yml")'`).

- [ ] **Step 4: Commit** `docs: add GitHub Pages site with build and usage guide`
