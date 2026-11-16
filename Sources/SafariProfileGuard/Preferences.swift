import Foundation

enum Preferences {
    private static let defaults = UserDefaults.standard

    private static let watchedProfileKey = "watchedProfile"
    private static let targetProfileKey = "targetProfile"
    private static let enabledKey = "enabled"

    static var watchedProfile: String {
        get { defaults.string(forKey: watchedProfileKey) ?? "Work" }
        set { defaults.set(newValue, forKey: watchedProfileKey) }
    }

    static var targetProfile: String {
        get { defaults.string(forKey: targetProfileKey) ?? "Home" }
        set { defaults.set(newValue, forKey: targetProfileKey) }
    }

    static var isEnabled: Bool {
        get { defaults.object(forKey: enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: enabledKey) }
    }
}
