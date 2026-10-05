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

    static func enqueue(_ url: URL) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }

        var values = defaults.stringArray(forKey: pendingURLsKey) ?? []
        let value = url.absoluteString
        if !values.contains(value) {
            values.append(value)
            defaults.set(values, forKey: pendingURLsKey)
        }
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
