import Foundation

enum MetadataRefreshSchedule {
    private static let lastRunKey = "redFruitTracker.metadataRefresh.lastRun"
    static let minimumInterval: TimeInterval = 24 * 60 * 60

    static func shouldRun(now: Date = .now) -> Bool {
        guard let timestamp = UserDefaults.standard.object(forKey: lastRunKey) as? Date else {
            return true
        }
        return now.timeIntervalSince(timestamp) >= minimumInterval
    }

    static func markRun(_ date: Date = .now) {
        UserDefaults.standard.set(date, forKey: lastRunKey)
    }

    static func lastRun() -> Date? {
        UserDefaults.standard.object(forKey: lastRunKey) as? Date
    }
}
