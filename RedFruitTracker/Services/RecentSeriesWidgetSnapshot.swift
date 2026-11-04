import Foundation
import SwiftData

enum RecentSeriesWidgetSnapshot {
    static func refresh(context: ModelContext) {
        var descriptor = FetchDescriptor<SeriesRecord>(
            sortBy: [
                SortDescriptor(\.createdAt, order: .reverse),
                SortDescriptor(\.sourceSeriesID)
            ]
        )
        descriptor.fetchLimit = 5
        guard let recentSeries = try? context.fetch(descriptor) else { return }
        refresh(series: recentSeries)
    }

    static func refresh(series: [SeriesRecord]) {
        let items = series
            .sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.sourceSeriesID < $1.sourceSeriesID
            }
            .prefix(5)
            .map {
                RecentSeriesWidgetItem(
                    id: $0.sourceSeriesID,
                    title: $0.title,
                    coverURL: $0.coverURL,
                    officialRating: $0.officialRating,
                    officialHeatText: $0.officialHeatText
                )
            }
        RecentSeriesWidgetStore.save(items)
    }
}
