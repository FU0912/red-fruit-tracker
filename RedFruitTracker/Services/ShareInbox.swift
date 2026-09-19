import Foundation

enum ShareInbox {
    static let appGroupIdentifier = "group.com.f.redfruittracker"
    static let pendingURLsKey = "pendingShareURLs"

    static func pendingURLs() -> [URL] {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return []
        }

        return (defaults.stringArray(forKey: pendingURLsKey) ?? [])
            .compactMap(URL.init(string:))
    }

    static func firstURL() -> URL? {
        pendingURLs().first
    }

    static func remove(_ url: URL) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }

        let value = url.absoluteString
        let remaining = (defaults.stringArray(forKey: pendingURLsKey) ?? [])
            .filter { $0 != value }
        defaults.set(remaining, forKey: pendingURLsKey)
    }
}
