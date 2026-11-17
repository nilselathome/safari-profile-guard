# SafariProfileGuard

A small macOS menu bar utility that watches for new Safari windows opened on
your "Work" profile and offers to switch them to "Home" — useful if Safari
tends to pick the wrong profile for new windows.

## Vibe coded
You should NOT install this on any computer that has sensitive data.
The code has not been properly reviewed by me, or anyone else (human).

USE AT OWN RISK.

When it detects a watched-profile window, it flashes a red border around
your screen(s) and shows a dialog: "Switch to Home?".

## How it works

Safari doesn't expose its per-window profile through any public API
(AppleScript, notifications, etc). This app reads it from Safari's
accessibility (AX) tree instead:

- It listens for `kAXWindowCreatedNotification` on Safari via an `AXObserver`.
- For each new window, it finds the toolbar's profile-picker button, whose
  `AXIdentifier` looks like `TabGroupPickerButton?Profile=Work&Icon=hammer.fill`,
  and reads the `Profile=` value out of it (falling back to parsing the
  window title's `"<Profile> — <page title>"` convention).
- To switch a window's profile, it presses that same button (which opens a
  menu) and presses the `"Switch to <Profile> Window"` menu item in it.

All of this requires Accessibility permission, which macOS will prompt for
on first launch (System Settings → Privacy & Security → Accessibility/Device
Control and Data Access, depending on macOS version).

Because this app is only ad-hoc signed (no Apple Developer ID), macOS ties
that Accessibility grant to the exact binary's signature rather than to the
app itself. Every rebuild produces a new signature, so after each build the
existing entry in that settings list silently becomes stale — it can still
show as enabled, but the app will fail to register for window notifications
(`AXObserverAddNotification` returns `kAXErrorAPIDisabled`). If watch mode
stops alerting after you rebuild, remove `SafariProfileGuard.app` from that
list (select it, click `−`) and relaunch it — it will re-prompt for
Accessibility access, and approving that fresh prompt fixes it.

## Building & running

### From Xcode

```bash
xcodegen generate   # regenerates SafariProfileGuard.xcodeproj from project.yml
open SafariProfileGuard.xcodeproj
```

Then build & run as usual (⌘R).

### Without Xcode

```bash
Scripts/build_and_install.sh
```

This builds a Release build and installs it to `/Applications/SafariProfileGuard.app`,
so it can be launched from Spotlight/Finder/Dock like a normal app. Run it
again any time after making changes.

## Using it

Click the shield icon in the menu bar:

- **Watching for Work windows** — toggle detection on/off.
- **Configure Profiles…** — change which profile triggers the warning, and
  which profile it offers to switch to (defaults: watch "Work", switch to
  "Home").
- **Launch at Login** — register/unregister as a login item.

## Requirements

- macOS 13+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) to regenerate the Xcode project after editing `project.yml`
