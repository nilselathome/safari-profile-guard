import ApplicationServices
import Cocoa

/// Watches Safari for newly created windows and reports ones using the watched profile.
final class SafariWatcher {
    static let shared = SafariWatcher()

    var onWatchedWindowDetected: ((AXUIElement, String) -> Void)?

    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var handledWindowIDs = Set<CGWindowID>()

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

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .defaultMode)
        observer = newObserver
        observedPID = pid

        registerForWindowCreation(pid: pid, observer: newObserver, attempt: 0)
    }

    /// Right after Safari (re)launches, AXObserverAddNotification can keep failing for a
    /// while — either transiently (kAXErrorCannotComplete, before Safari's AX server is
    /// ready) or because Accessibility permission isn't granted yet (kAXErrorAPIDisabled,
    /// while the user is still looking at the system prompt). Retry until it succeeds,
    /// giving the permission case much more time since it's waiting on the user, then
    /// catch up on whatever windows already exist — Safari usually restores them before
    /// we're done registering, and kAXWindowCreatedNotification never fires for those.
    private func registerForWindowCreation(pid: pid_t, observer: AXObserver, attempt: Int) {
        guard observedPID == pid else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let result = AXObserverAddNotification(observer, appElement, kAXWindowCreatedNotification as CFString, refcon)

        guard result == .success else {
            let isWaitingOnPermission = result == .apiDisabled
            let maxAttempts = isWaitingOnPermission ? 150 : 10
            let interval = isWaitingOnPermission ? 2.0 : 0.5

            guard attempt < maxAttempts else {
                NSLog("SafariProfileGuard: failed to register for window-created notifications (result=\(result.rawValue))")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
                self?.registerForWindowCreation(pid: pid, observer: observer, attempt: attempt + 1)
            }
            return
        }

        for window in AX.windows(appElement) {
            inspect(window: window)
        }
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedPID = nil
        // Window IDs belonged to the Safari process that just went away.
        handledWindowIDs.removeAll()
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
        guard profile.caseInsensitiveCompare(Preferences.watchedProfile) == .orderedSame else { return }

        // Tie the decision (switch or keep) to this specific window: if we can
        // identify it reliably, never ask about it twice.
        if let windowID = AX.windowID(window) {
            guard !handledWindowIDs.contains(windowID) else { return }
            handledWindowIDs.insert(windowID)
        }
        onWatchedWindowDetected?(window, profile)
    }
}
