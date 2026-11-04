import Foundation
import SwiftData

struct SeriesImportIdentity: Equatable {
    let baseTitle: String
    let key: String
    let sourceID: String
    let inferredSeasonNumber: Int?

    init(title: String?, fallbackURL: URL) {
        let normalizedTitle = TitleNormalizer.normalize(title)
            ?? TitleNormalizer.fallback(from: fallbackURL)
            ?? fallbackURL.absoluteString
        let baseTitle = TitleNormalizer.seriesTitle(normalizedTitle) ?? normalizedTitle
        let key = TitleNormalizer.seriesKey(baseTitle) ?? fallbackURL.absoluteString

        self.baseTitle = baseTitle
        self.key = key
        self.sourceID = "redfruit-title:\(key)"
        self.inferredSeasonNumber = TitleNormalizer.seasonNumber(normalizedTitle)
    }
}

enum SeriesImportMatcher {
    static func matches(_ record: SeriesRecord, identity: SeriesImportIdentity) -> Bool {
        if record.sourceSeriesID == identity.sourceID {
            return true
        }

        return TitleNormalizer.seriesKey(record.title) == identity.key
    }
}

enum SeriesRecordLookup {
    static func existing(
        matching identity: SeriesImportIdentity,
        in context: ModelContext
    ) throws -> SeriesRecord? {
        let sourceID = identity.sourceID
        var idDescriptor = FetchDescriptor<SeriesRecord>(
            predicate: #Predicate<SeriesRecord> { $0.sourceSeriesID == sourceID }
        )
        idDescriptor.fetchLimit = 1
        if let record = try context.fetch(idDescriptor).first {
            return record
        }

        let title = identity.baseTitle
        let titleDescriptor = FetchDescriptor<SeriesRecord>(
            predicate: #Predicate<SeriesRecord> { $0.title == title }
        )
        return try context.fetch(titleDescriptor).first {
            SeriesImportMatcher.matches($0, identity: identity)
        }
    }
}
