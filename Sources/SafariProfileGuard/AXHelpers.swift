import ApplicationServices
import Foundation

enum AX {
    static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return result == .success ? value : nil
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    static func identifier(_ element: AXUIElement) -> String? {
        attribute(element, "AXIdentifier") as? String
    }

    static func title(_ element: AXUIElement) -> String? {
        attribute(element, kAXTitleAttribute) as? String
    }

    static func role(_ element: AXUIElement) -> String? {
        attribute(element, kAXRoleAttribute) as? String
    }

    /// Depth-first search for the first element matching `predicate`, never descending
    /// into AXWebArea (the page's own DOM accessibility tree, which can be huge).
    static func findFirst(in element: AXUIElement, maxDepth: Int, depth: Int = 0, predicate: (AXUIElement) -> Bool) -> AXUIElement? {
        if predicate(element) { return element }
        if role(element) == "AXWebArea" { return nil }
        if depth >= maxDepth { return nil }
        for child in children(element) {
            if let found = findFirst(in: child, maxDepth: maxDepth, depth: depth + 1, predicate: predicate) {
                return found
            }
        }
        return nil
    }

    @discardableResult
    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }
}

/// Everything specific to reading/driving Safari's per-window profile picker.
enum SafariProfile {
    /// Finds the toolbar button Safari uses to show/switch the window's profile,
    /// identified by its AXIdentifier, e.g. "TabGroupPickerButton?Profile=Work&Icon=hammer.fill".
    static func pickerButton(in window: AXUIElement) -> AXUIElement? {
        AX.findFirst(in: window, maxDepth: 6) { el in
            AX.identifier(el)?.hasPrefix("TabGroupPickerButton") ?? false
        }
    }

    /// Extracts the active profile name for a Safari window, e.g. "Work".
    /// Primary source is the picker button's identifier; falls back to parsing the
    /// window title's "<Profile> — <page title>" convention.
    static func currentProfile(for window: AXUIElement) -> String? {
        if let button = pickerButton(in: window),
           let id = AX.identifier(button),
           let profile = queryValue(in: id, key: "Profile") {
            return profile
        }
        if let title = AX.title(window), let range = title.range(of: " — ") {
            return String(title[title.startIndex..<range.lowerBound])
        }
        return nil
    }

    /// Opens the picker menu and presses the "Switch to <targetProfile> Window" item.
    /// Returns false if the button or menu item couldn't be found.
    static func switchToProfile(_ targetProfile: String, for window: AXUIElement, completion: @escaping (Bool) -> Void) {
        guard let button = pickerButton(in: window) else {
            completion(false)
            return
        }
        AX.press(button)
        let expectedTitle = "Switch to \(targetProfile) Window"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let menuItem = AX.findFirst(in: button, maxDepth: 3) { el in
                AX.role(el) == "AXMenuItem" && AX.title(el) == expectedTitle
            }
            if let menuItem {
                completion(AX.press(menuItem))
            } else {
                dismissOpenMenu()
                completion(false)
            }
        }
    }

    private static func dismissOpenMenu() {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
    }

    /// Parses "key=value" pairs out of an identifier like "Foo?Profile=Work&Icon=hammer.fill".
    private static func queryValue(in identifier: String, key: String) -> String? {
        guard let queryStart = identifier.firstIndex(of: "?") else { return nil }
        let query = identifier[identifier.index(after: queryStart)...]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0] == key {
                return String(parts[1])
            }
        }
        return nil
    }
}
