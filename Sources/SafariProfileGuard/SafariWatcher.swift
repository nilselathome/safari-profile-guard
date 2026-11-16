import ApplicationServices
import Cocoa

/// Watches Safari for newly created windows and reports ones using the watched profile.
final class SafariWatcher {
    static let shared = SafariWatcher()

    var onWatchedWindowDetected: ((AXUIElement, String) -> Void)?

    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var handledWindowIDs = Set<String>()

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        if let safari = runningSafari() {
            attach(to: safari.processIdentifier)
        }
    }

    private func runningSafari() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.Safari" }
    }

    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.apple.Safari" else { return }
        // Safari's accessibility tree isn't populated the instant the process launches.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.attach(to: app.processIdentifier)
        }
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.apple.Safari" else { return }
        detach()
    }

    private func attach(to pid: pid_t) {
        if observedPID == pid { return }
        detach()

        var newObserver: AXObserver?
        let callback: AXObserverCallback = { _, element, notificationName, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<SafariWatcher>.fromOpaque(refcon).takeUnretainedValue()
            watcher.handleNotification(element: element, name: notificationName as String)
        }
        let createResult = AXObserverCreate(pid, callback, &newObserver)
        guard createResult == .success, let newObserver else {
            NSLog("SafariProfileGuard: failed to create AXObserver (result=\(createResult.rawValue))")
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(newObserver, appElement, kAXWindowCreatedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .defaultMode)

        observer = newObserver
        observedPID = pid
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedPID = nil
    }

    private func handleNotification(element: AXUIElement, name: String) {
        guard name == (kAXWindowCreatedNotification as String) else { return }
        // Give Safari a moment to populate the profile picker button on the new window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.inspect(window: element)
        }
    }

    private func inspect(window: AXUIElement) {
        guard Preferences.isEnabled else { return }
        guard let profile = SafariProfile.currentProfile(for: window) else { return }

        let windowID = AX.identifier(window) ?? String(describing: window)
        guard !handledWindowIDs.contains(windowID) else { return }
        guard profile.caseInsensitiveCompare(Preferences.watchedProfile) == .orderedSame else { return }

        handledWindowIDs.insert(windowID)
        onWatchedWindowDetected?(window, profile)
    }
}
