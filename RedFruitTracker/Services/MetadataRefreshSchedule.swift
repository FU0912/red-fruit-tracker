import Foundation

enum MetadataRefreshSchedule {
    private static let lastRunKey = "redFruitTracker.metadataRefresh.lastRun"
    static let minimumInterval: TimeInterval = 24 * 60 * 60

    static func shouldRun(now: Date = .now, defaults: UserDefaults = .standard) -> Bool {
        guard let timestamp = defaults.object(forKey: lastRunKey) as? Date else {
            return true
        }
        return now.timeIntervalSince(timestamp) >= minimumInterval
    }

    static func markAttempt(_ date: Date = .now, defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: lastRunKey)
    }
}
