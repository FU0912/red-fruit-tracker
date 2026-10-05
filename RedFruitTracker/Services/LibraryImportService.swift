import Foundation

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
