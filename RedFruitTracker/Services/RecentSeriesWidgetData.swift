import Foundation
import WidgetKit

struct RecentSeriesWidgetItem: Codable, Identifiable {
    let id: String
    let title: String
    let coverURL: String?
    let officialRating: Double?
    let officialHeatText: String?
}

enum RecentSeriesWidgetStore {
    private static let suiteName = "group.com.f.redfruittracker"
    private static let key = "recentSeriesWidgetItems"

    static func items() -> [RecentSeriesWidgetItem] {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: key),
              let items = try? PropertyListDecoder().decode([RecentSeriesWidgetItem].self, from: data) else {
            return []
        }
        return items
    }

    static func save(_ items: [RecentSeriesWidgetItem]) {
        guard let data = try? PropertyListEncoder().encode(items) else { return }
        UserDefaults(suiteName: suiteName)?.set(data, forKey: key)
        WidgetCenter.shared.reloadTimelines(ofKind: "RecentSeriesWidget")
    }
}
