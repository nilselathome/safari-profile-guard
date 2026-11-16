import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let enabledMenuItem = NSMenuItem(title: "Watching for Work windows", action: #selector(toggleEnabled), keyEquivalent: "")
    private let launchAtLoginMenuItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestAccessibilityPermissionIfNeeded()
        setUpStatusItem()
        SafariWatcher.shared.onWatchedWindowDetected = { [weak self] window, profile in
            self?.presentSwitchPrompt(window: window, detectedProfile: profile)
        }
        SafariWatcher.shared.start()
    }

    private func requestAccessibilityPermissionIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: "SafariProfileGuard")

        let menu = NSMenu()

        enabledMenuItem.target = self
        enabledMenuItem.state = Preferences.isEnabled ? .on : .off
        menu.addItem(enabledMenuItem)

        menu.addItem(.separator())

        let configureItem = NSMenuItem(title: "Configure Profiles…", action: #selector(configureProfiles), keyEquivalent: "")
        configureItem.target = self
        menu.addItem(configureItem)

        menu.addItem(.separator())

        launchAtLoginMenuItem.target = self
        launchAtLoginMenuItem.state = isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(launchAtLoginMenuItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit SafariProfileGuard", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleEnabled() {
        Preferences.isEnabled.toggle()
        enabledMenuItem.state = Preferences.isEnabled ? .on : .off
    }

    @objc private func configureProfiles() {
        let alert = NSAlert()
        alert.messageText = "Configure Profiles"
        alert.informativeText = "Which profile should trigger a warning, and which one should it offer to switch to?"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 56))

        let watchedLabel = NSTextField(labelWithString: "Watched profile:")
        watchedLabel.frame = NSRect(x: 0, y: 32, width: 110, height: 20)
        let watchedField = NSTextField(frame: NSRect(x: 115, y: 30, width: 145, height: 24))
        watchedField.stringValue = Preferences.watchedProfile

        let targetLabel = NSTextField(labelWithString: "Switch to:")
        targetLabel.frame = NSRect(x: 0, y: 2, width: 110, height: 20)
        let targetField = NSTextField(frame: NSRect(x: 115, y: 0, width: 145, height: 24))
        targetField.stringValue = Preferences.targetProfile

        container.addSubview(watchedLabel)
        container.addSubview(watchedField)
        container.addSubview(targetLabel)
        container.addSubview(targetField)
        alert.accessoryView = container

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let watched = watchedField.stringValue.trimmingCharacters(in: .whitespaces)
            let target = targetField.stringValue.trimmingCharacters(in: .whitespaces)
            if !watched.isEmpty { Preferences.watchedProfile = watched }
            if !target.isEmpty { Preferences.targetProfile = target }
        }
    }

    private var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if isLaunchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("SafariProfileGuard: failed to toggle launch-at-login: \(error)")
        }
        launchAtLoginMenuItem.state = isLaunchAtLoginEnabled ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func presentSwitchPrompt(window: AXUIElement, detectedProfile: String) {
        let target = Preferences.targetProfile
        NSApp.activate(ignoringOtherApps: true)
        OverlayManager.showBorder()

        let alert = NSAlert()
        alert.messageText = "New \(detectedProfile) Safari window"
        alert.informativeText = "This window opened on the \"\(detectedProfile)\" profile. Switch it to \"\(target)\"?"
        alert.addButton(withTitle: "Switch to \(target)")
        alert.addButton(withTitle: "Keep \(detectedProfile)")

        let response = alert.runModal()
        OverlayManager.hideBorder()

        if response == .alertFirstButtonReturn {
            SafariProfile.switchToProfile(target, for: window) { success in
                if !success {
                    NSLog("SafariProfileGuard: could not switch window to profile \(target)")
                }
            }
        }
    }
}
