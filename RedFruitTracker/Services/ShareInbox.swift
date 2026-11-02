import Foundation

enum ShareInbox {
    static let appGroupIdentifier = "group.com.f.redfruittracker"
    static let pendingURLsKey = "pendingShareURLs"

    static func pendingURLs() -> [URL] {
        pendingURLs(in: UserDefaults(suiteName: appGroupIdentifier))
    }

    static func pendingURLs(in defaults: UserDefaults?) -> [URL] {
        guard let defaults else { return [] }
        return (defaults.stringArray(forKey: pendingURLsKey) ?? [])
            .compactMap(URL.init(string:))
    }

    static func firstURL() -> URL? {
        pendingURLs().first
    }

    @discardableResult
    static func enqueue(_ url: URL) -> Bool {
        enqueue(url, in: UserDefaults(suiteName: appGroupIdentifier))
    }

    @discardableResult
    static func enqueue(_ url: URL, in defaults: UserDefaults?) -> Bool {
        guard let defaults else { return false }
        var values = defaults.stringArray(forKey: pendingURLsKey) ?? []
        let value = url.absoluteString
        if !values.contains(value) {
            values.append(value)
            defaults.set(values, forKey: pendingURLsKey)
            // The extension and the host app are separate processes; flush the
            // small queue through shared defaults before the extension exits.
            defaults.synchronize()
        }
        return true
    }

    static func remove(_ url: URL) {
        remove(url, in: UserDefaults(suiteName: appGroupIdentifier))
    }

    static func remove(_ url: URL, in defaults: UserDefaults?) {
        guard let defaults else { return }
        let value = url.absoluteString
        let remaining = (defaults.stringArray(forKey: pendingURLsKey) ?? [])
            .filter { $0 != value }
        defaults.set(remaining, forKey: pendingURLsKey)
        defaults.synchronize()
    }
}

enum ShareRoute {
    static let scheme = "redfruittracker"
    static let host = "share-import"

    static func callbackURL(for sharedURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: "url", value: sharedURL.absoluteString)]
        return components.url
    }

    static func sharedURL(from callbackURL: URL) -> URL? {
        guard callbackURL.scheme?.lowercased() == scheme,
              callbackURL.host?.lowercased() == host,
              let value = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "url" })?.value else {
            return nil
        }
        return URLExtractor.firstURL(in: value) ?? URL(string: value)
    }
}
