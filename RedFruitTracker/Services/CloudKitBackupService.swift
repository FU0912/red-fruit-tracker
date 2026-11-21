import CloudKit
import Combine
import CryptoKit
import Foundation
import SwiftData

extension Notification.Name {
    /// Posted after a successful local SwiftData save. The root view uses it
    /// to schedule a debounced cloud snapshot without coupling every editor
    /// to CloudKit.
    static let redFruitLibraryDidSave = Notification.Name("RedFruitTracker.libraryDidSave")
}

extension ModelContext {
    /// Persist locally first, then notify the cloud coordinator. Local data
    /// remains the source of truth when iCloud is unavailable.
    func saveAndNotifyCloudBackup() throws {
        try save()
        NotificationCenter.default.post(name: .redFruitLibraryDidSave, object: nil)
    }
}

struct SeriesBackupRecord: Codable, Equatable, Sendable {
    let sourceSeriesID: String
    let title: String
    let sourceURL: String?
    let coverURL: String?
    let intro: String
    let tagsText: String
    let officialRating: Double?
    let officialRatingCount: Int?
    let officialHeatScore: Double?
    let officialHeatText: String?
    let completionStatus: String?
    let manualSeasonCount: Int?
    let createdAt: Date
    let updatedAt: Date

    init(_ value: SeriesRecord) {
        sourceSeriesID = value.sourceSeriesID
        title = value.title
        sourceURL = value.sourceURL
        coverURL = value.coverURL
        intro = value.intro
        tagsText = value.tagsText
        officialRating = value.officialRating
        officialRatingCount = value.officialRatingCount
        officialHeatScore = value.officialHeatScore
        officialHeatText = value.officialHeatText
        completionStatus = value.completionStatus
        manualSeasonCount = value.manualSeasonCount
        createdAt = value.createdAt
        updatedAt = value.updatedAt
    }
}

struct SeasonBackupRecord: Codable, Equatable, Sendable {
    let sourceSeasonKey: String
    let sourceSeriesID: String
    let seasonNumber: Int
    let title: String
    let episodeCount: Int
    let sourceURL: String?
    let myRating: Double?
    let review: String
    let updatedAt: Date

    init(_ value: SeasonRecord) {
        sourceSeasonKey = value.sourceSeasonKey
        sourceSeriesID = value.sourceSeriesID
        seasonNumber = value.seasonNumber
        title = value.title
        episodeCount = value.episodeCount
        sourceURL = value.sourceURL
        myRating = value.myRating
        review = value.review
        updatedAt = value.updatedAt
    }
}

struct EpisodeBackupRecord: Codable, Equatable, Sendable {
    let sourceVid: String
    let sourceSeriesID: String
    let seasonNumber: Int
    let episodeNumber: Int
    let title: String
    let webURL: String?
    let isWatched: Bool
    let watchedAt: Date?

    init(_ value: EpisodeRecord) {
        sourceVid = value.sourceVid
        sourceSeriesID = value.sourceSeriesID
        seasonNumber = value.seasonNumber
        episodeNumber = value.episodeNumber
        title = value.title
        webURL = value.webURL
        isWatched = value.isWatched
        watchedAt = value.watchedAt
    }
}

struct PersonalBackupRecord: Codable, Equatable, Sendable {
    let sourceSeriesID: String
    let currentSeasonNumber: Int?
    let currentEpisodeNumber: Int?
    let myRating: Double?
    let review: String
    let localShelfState: String
    let followsUpdates: Bool
    let followedAt: Date?
    let viewingStatusChangedAt: Date?
    let nextSeasonDate: Date?
    let updatedAt: Date

    init(_ value: PersonalRecord) {
        sourceSeriesID = value.sourceSeriesID
        currentSeasonNumber = value.currentSeasonNumber
        currentEpisodeNumber = value.currentEpisodeNumber
        myRating = value.myRating
        review = value.review
        localShelfState = value.localShelfState
        followsUpdates = value.followsUpdates
        followedAt = value.followedAt
        viewingStatusChangedAt = value.viewingStatusChangedAt
        nextSeasonDate = value.nextSeasonDate
        updatedAt = value.updatedAt
    }
}

struct OfficialSnapshotBackupRecord: Codable, Equatable, Sendable {
    let sourceSeriesID: String
    let capturedAt: Date
    let officialRating: Double?
    let officialRatingCount: Int?
    let officialHeatScore: Double?
    let officialHeatText: String?
    let likeCount: Int?
    let favoriteCount: Int?
    let reviewCount: Int?
    let seasonCount: Int?
    let episodeCount: Int?

    init(_ value: OfficialSnapshot) {
        sourceSeriesID = value.sourceSeriesID
        capturedAt = value.capturedAt
        officialRating = value.officialRating
        officialRatingCount = value.officialRatingCount
        officialHeatScore = value.officialHeatScore
        officialHeatText = value.officialHeatText
        likeCount = value.likeCount
        favoriteCount = value.favoriteCount
        reviewCount = value.reviewCount
        seasonCount = value.seasonCount
        episodeCount = value.episodeCount
    }
}

struct ImportInboxBackupRecord: Codable, Equatable, Sendable {
    let originalURL: String
    let importedAt: Date
    let status: String
    let failureMessage: String?

    init(_ value: ImportInboxItem) {
        originalURL = value.originalURL
        importedAt = value.importedAt
        status = value.status
        failureMessage = value.failureMessage
    }
}

struct UpdateNotificationBackupRecord: Codable, Equatable, Sendable {
    let id: String
    let sourceSeriesID: String
    let title: String
    let scheduledAt: Date
    let isRead: Bool
    let createdAt: Date

    init(_ value: UpdateNotificationRecord) {
        id = value.id
        sourceSeriesID = value.sourceSeriesID
        title = value.title
        scheduledAt = value.scheduledAt
        isRead = value.isRead
        createdAt = value.createdAt
    }
}

enum LibraryBackupArchiveError: LocalizedError {
    case unsupportedSchemaVersion(Int)
    case databaseNotEmpty
    case duplicateRecords(String)
    case missingSeriesReference(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "此备份版本暂不支持（版本 \(version)）。"
        case .databaseNotEmpty:
            return "当前书架已有数据。为避免重复或覆盖，文件恢复只允许在空书架中进行。"
        case .duplicateRecords(let kind):
            return "备份中包含重复的\(kind)记录，未导入任何数据。"
        case .missingSeriesReference(let kind):
            return "备份中的\(kind)找不到对应作品，文件可能不完整。"
        }
    }
}

struct LibraryBackupArchive: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let exportedAt: Date
    let series: [SeriesBackupRecord]
    let seasons: [SeasonBackupRecord]
    let episodes: [EpisodeBackupRecord]
    let personalRecords: [PersonalBackupRecord]
    let officialSnapshots: [OfficialSnapshotBackupRecord]
    let importInboxItems: [ImportInboxBackupRecord]
    let updateNotifications: [UpdateNotificationBackupRecord]

    var recordCount: Int {
        series.count
            + seasons.count
            + episodes.count
            + personalRecords.count
            + officialSnapshots.count
            + importInboxItems.count
            + updateNotifications.count
    }

    init(
        schemaVersion: Int = LibraryBackupArchive.currentSchemaVersion,
        exportedAt: Date = .now,
        series: [SeriesBackupRecord],
        seasons: [SeasonBackupRecord],
        episodes: [EpisodeBackupRecord],
        personalRecords: [PersonalBackupRecord],
        officialSnapshots: [OfficialSnapshotBackupRecord],
        importInboxItems: [ImportInboxBackupRecord],
        updateNotifications: [UpdateNotificationBackupRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.series = series
        self.seasons = seasons
        self.episodes = episodes
        self.personalRecords = personalRecords
        self.officialSnapshots = officialSnapshots
        self.importInboxItems = importInboxItems
        self.updateNotifications = updateNotifications
    }

    @MainActor
    static func export(from context: ModelContext, exportedAt: Date = .now) throws -> Self {
        Self(
            exportedAt: exportedAt,
            series: try context.fetch(FetchDescriptor<SeriesRecord>())
                .sorted { $0.sourceSeriesID < $1.sourceSeriesID }
                .map(SeriesBackupRecord.init),
            seasons: try context.fetch(FetchDescriptor<SeasonRecord>())
                .sorted { $0.sourceSeasonKey < $1.sourceSeasonKey }
                .map(SeasonBackupRecord.init),
            episodes: try context.fetch(FetchDescriptor<EpisodeRecord>())
                .sorted { $0.sourceVid < $1.sourceVid }
                .map(EpisodeBackupRecord.init),
            personalRecords: try context.fetch(FetchDescriptor<PersonalRecord>())
                .sorted { $0.sourceSeriesID < $1.sourceSeriesID }
                .map(PersonalBackupRecord.init),
            officialSnapshots: try context.fetch(FetchDescriptor<OfficialSnapshot>())
                .sorted {
                    if $0.sourceSeriesID != $1.sourceSeriesID { return $0.sourceSeriesID < $1.sourceSeriesID }
                    return $0.capturedAt < $1.capturedAt
                }
                .map(OfficialSnapshotBackupRecord.init),
            importInboxItems: try context.fetch(FetchDescriptor<ImportInboxItem>())
                .sorted { $0.originalURL < $1.originalURL }
                .map(ImportInboxBackupRecord.init),
            updateNotifications: try context.fetch(FetchDescriptor<UpdateNotificationRecord>())
                .sorted { $0.id < $1.id }
                .map(UpdateNotificationBackupRecord.init)
        )
    }

    func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(Self.self, from: data)
        try archive.validate()
        return archive
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LibraryBackupArchiveError.unsupportedSchemaVersion(schemaVersion)
        }

        func requireUnique<Value: Hashable>(_ values: [Value], kind: String) throws {
            guard Set(values).count == values.count else {
                throw LibraryBackupArchiveError.duplicateRecords(kind)
            }
        }

        try requireUnique(series.map(\.sourceSeriesID), kind: "作品")
        try requireUnique(seasons.map(\.sourceSeasonKey), kind: "季")
        try requireUnique(episodes.map(\.sourceVid), kind: "集")
        try requireUnique(personalRecords.map(\.sourceSeriesID), kind: "个人记录")
        try requireUnique(importInboxItems.map(\.originalURL), kind: "导入队列")
        try requireUnique(updateNotifications.map(\.id), kind: "通知")

        let seriesIDs = Set(series.map(\.sourceSeriesID))
        guard seasons.allSatisfy({ seriesIDs.contains($0.sourceSeriesID) }),
              episodes.allSatisfy({ seriesIDs.contains($0.sourceSeriesID) }),
              personalRecords.allSatisfy({ seriesIDs.contains($0.sourceSeriesID) }),
              officialSnapshots.allSatisfy({ seriesIDs.contains($0.sourceSeriesID) }),
              updateNotifications.allSatisfy({ seriesIDs.contains($0.sourceSeriesID) }) else {
            throw LibraryBackupArchiveError.missingSeriesReference("季集或个人数据")
        }
    }

    @MainActor
    func restore(into context: ModelContext) throws {
        try validate()
        let hasExistingLibraryRecords = try context.fetchCount(FetchDescriptor<SeriesRecord>()) > 0
            || context.fetchCount(FetchDescriptor<SeasonRecord>()) > 0
            || context.fetchCount(FetchDescriptor<EpisodeRecord>()) > 0
            || context.fetchCount(FetchDescriptor<PersonalRecord>()) > 0
            || context.fetchCount(FetchDescriptor<OfficialSnapshot>()) > 0
        guard !hasExistingLibraryRecords else {
            throw LibraryBackupArchiveError.databaseNotEmpty
        }

        for value in series {
            context.insert(SeriesRecord(
                sourceSeriesID: value.sourceSeriesID,
                title: value.title,
                sourceURL: value.sourceURL,
                coverURL: value.coverURL,
                intro: value.intro,
                tagsText: value.tagsText,
                officialRating: value.officialRating,
                officialRatingCount: value.officialRatingCount,
                officialHeatScore: value.officialHeatScore,
                officialHeatText: value.officialHeatText,
                completionStatus: value.completionStatus,
                manualSeasonCount: value.manualSeasonCount,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        for value in seasons {
            let record = SeasonRecord(
                sourceSeriesID: value.sourceSeriesID,
                seasonNumber: value.seasonNumber,
                title: value.title,
                episodeCount: value.episodeCount,
                sourceURL: value.sourceURL,
                myRating: value.myRating,
                review: value.review
            )
            record.updatedAt = value.updatedAt
            context.insert(record)
        }
        for value in episodes {
            context.insert(EpisodeRecord(
                sourceVid: value.sourceVid,
                sourceSeriesID: value.sourceSeriesID,
                seasonNumber: value.seasonNumber,
                episodeNumber: value.episodeNumber,
                title: value.title,
                webURL: value.webURL,
                isWatched: value.isWatched,
                watchedAt: value.watchedAt
            ))
        }
        for value in personalRecords {
            let record = PersonalRecord(sourceSeriesID: value.sourceSeriesID)
            record.currentSeasonNumber = value.currentSeasonNumber
            record.currentEpisodeNumber = value.currentEpisodeNumber
            record.myRating = value.myRating
            record.review = value.review
            record.localShelfState = value.localShelfState
            record.followsUpdates = value.followsUpdates
            record.followedAt = value.followedAt
            record.viewingStatusChangedAt = value.viewingStatusChangedAt
            record.nextSeasonDate = value.nextSeasonDate
            record.updatedAt = value.updatedAt
            context.insert(record)
        }
        for value in officialSnapshots {
            let record = OfficialSnapshot(sourceSeriesID: value.sourceSeriesID, capturedAt: value.capturedAt)
            record.officialRating = value.officialRating
            record.officialRatingCount = value.officialRatingCount
            record.officialHeatScore = value.officialHeatScore
            record.officialHeatText = value.officialHeatText
            record.likeCount = value.likeCount
            record.favoriteCount = value.favoriteCount
            record.reviewCount = value.reviewCount
            record.seasonCount = value.seasonCount
            record.episodeCount = value.episodeCount
            context.insert(record)
        }
        let existingInboxURLs = Set(try context.fetch(FetchDescriptor<ImportInboxItem>()).map(\.originalURL))
        for value in importInboxItems where !existingInboxURLs.contains(value.originalURL) {
            let record = ImportInboxItem(originalURL: value.originalURL, status: value.status)
            record.importedAt = value.importedAt
            record.failureMessage = value.failureMessage
            context.insert(record)
        }
        let existingNotificationIDs = Set(try context.fetch(FetchDescriptor<UpdateNotificationRecord>()).map(\.id))
        for value in updateNotifications where !existingNotificationIDs.contains(value.id) {
            let record = UpdateNotificationRecord(
                sourceSeriesID: value.sourceSeriesID,
                title: value.title,
                scheduledAt: value.scheduledAt,
                isRead: value.isRead,
                createdAt: value.createdAt
            )
            record.id = value.id
            context.insert(record)
        }
    }
}

enum CloudBackupState: Equatable {
    case idle
    case syncing
    case synced(Date)
    case unavailable(String)
    case failed(String)

    var title: String {
        switch self {
        case .idle: return "未同步"
        case .syncing: return "同步中"
        case .synced: return "已同步"
        case .unavailable(let message): return message
        case .failed: return "同步失败"
        }
    }

    var systemImage: String {
        switch self {
        case .idle: return "icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .synced: return "checkmark.icloud"
        case .unavailable, .failed: return "exclamationmark.icloud"
        }
    }

    var feedbackMessage: String {
        switch self {
        case .idle:
            return "尚未完成 iCloud 备份。"
        case .syncing:
            return "正在同步到 iCloud。"
        case .synced(let date):
            return "备份完成，时间：\(date.formatted(date: .omitted, time: .shortened))。"
        case .unavailable(let message):
            return message
        case .failed(let message):
            return "云备份失败：\(message)"
        }
    }
}

enum CloudBackupRuntimePolicy {
    static let disabledMessage = "云备份未启用，本机记录正常保存。"
    static let missingEntitlementMessage = "当前安装签名没有 iCloud 容器权限；请使用已启用 CloudKit 的签名配置重新签名。记录仍保存在本机。"

    static var isCloudKitEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "RedFruitCloudKitEnabled") as? Bool == true
    }

    static func hasCloudKitEntitlements(containerIdentifier: String) -> Bool {
        guard let executableURL = Bundle.main.executableURL,
              let executable = try? Data(contentsOf: executableURL) else { return false }

        return MachOCloudKitEntitlementReader.contains(
            containerIdentifier: containerIdentifier,
            in: executable
        )
    }
}

private enum MachOCloudKitEntitlementReader {
    private enum ByteOrder {
        case little
        case big
    }

    private static let codeSignatureCommand: UInt32 = 0x1d
    private static let embeddedSignatureMagic: UInt32 = 0xfade0cc0
    private static let embeddedEntitlementsMagic: UInt32 = 0xfade7171
    private static let entitlementsSlot: UInt32 = 5

    static func contains(containerIdentifier: String, in executable: Data) -> Bool {
        for slice in slices(in: executable) {
            guard let signature = signatureData(in: slice) else { continue }
            if let entitlements = entitlements(in: signature) {
                let services = entitlements["com.apple.developer.icloud-services"] as? [String] ?? []
                let containers = entitlements["com.apple.developer.icloud-container-identifiers"] as? [String] ?? []
                return services.contains("CloudKit") && containers.contains(containerIdentifier)
            }

            // Some signers emit DER entitlements without the XML entitlement slot.
            let requiredValues = [
                "com.apple.developer.icloud-services",
                "CloudKit",
                "com.apple.developer.icloud-container-identifiers",
                containerIdentifier
            ]
            if requiredValues.allSatisfy({ signature.range(of: Data($0.utf8)) != nil }) {
                return true
            }
        }
        return false
    }

    private static func slices(in data: Data) -> [Data] {
        guard let magic = readUInt32(data, at: 0, order: .big) else { return [] }
        let fatOrder: ByteOrder
        let is64Bit: Bool
        switch magic {
        case 0xcafebabe:
            fatOrder = .big
            is64Bit = false
        case 0xbebafeca:
            fatOrder = .little
            is64Bit = false
        case 0xcafebabf:
            fatOrder = .big
            is64Bit = true
        case 0xbfbafeca:
            fatOrder = .little
            is64Bit = true
        default:
            return [data]
        }

        guard let count = readUInt32(data, at: 4, order: fatOrder), count <= 32 else { return [] }
        let entrySize = is64Bit ? 32 : 20
        return (0..<Int(count)).compactMap { index in
            let entry = 8 + index * entrySize
            let offset: UInt64?
            let size: UInt64?
            if is64Bit {
                offset = readUInt64(data, at: entry + 8, order: fatOrder)
                size = readUInt64(data, at: entry + 16, order: fatOrder)
            } else {
                offset = readUInt32(data, at: entry + 8, order: fatOrder).map(UInt64.init)
                size = readUInt32(data, at: entry + 12, order: fatOrder).map(UInt64.init)
            }
            guard let offset, let size,
                  offset <= UInt64(data.count),
                  size <= UInt64(data.count) - offset else { return nil }
            return data.subdata(in: Int(offset)..<Int(offset + size))
        }
    }

    private static func signatureData(in slice: Data) -> Data? {
        guard let magic = readUInt32(slice, at: 0, order: .big) else { return nil }
        let order: ByteOrder
        let headerSize: Int
        switch magic {
        case 0xfeedface:
            order = .big
            headerSize = 28
        case 0xcefaedfe:
            order = .little
            headerSize = 28
        case 0xfeedfacf:
            order = .big
            headerSize = 32
        case 0xcffaedfe:
            order = .little
            headerSize = 32
        default:
            return nil
        }

        guard let commandCount = readUInt32(slice, at: 16, order: order), commandCount <= 65535 else { return nil }
        var commandOffset = headerSize
        for _ in 0..<Int(commandCount) {
            guard let command = readUInt32(slice, at: commandOffset, order: order),
                  let commandSize = readUInt32(slice, at: commandOffset + 4, order: order),
                  commandSize >= 8,
                  commandOffset + Int(commandSize) <= slice.count else { return nil }

            if command == codeSignatureCommand, commandSize >= 16,
               let dataOffset = readUInt32(slice, at: commandOffset + 8, order: order),
               let dataSize = readUInt32(slice, at: commandOffset + 12, order: order),
               Int(dataOffset) <= slice.count,
               Int(dataSize) <= slice.count - Int(dataOffset) {
                return slice.subdata(in: Int(dataOffset)..<Int(dataOffset + dataSize))
            }
            commandOffset += Int(commandSize)
        }
        return nil
    }

    private static func entitlements(in signature: Data) -> [String: Any]? {
        guard readUInt32(signature, at: 0, order: .big) == embeddedSignatureMagic,
              let signatureLength = readUInt32(signature, at: 4, order: .big),
              let count = readUInt32(signature, at: 8, order: .big),
              count <= 128 else { return nil }

        for index in 0..<Int(count) {
            let entry = 12 + index * 8
            guard readUInt32(signature, at: entry, order: .big) == entitlementsSlot,
                  let blobOffset = readUInt32(signature, at: entry + 4, order: .big),
                  readUInt32(signature, at: Int(blobOffset), order: .big) == embeddedEntitlementsMagic,
                  let blobLength = readUInt32(signature, at: Int(blobOffset) + 4, order: .big),
                  blobLength >= 8,
                  blobOffset <= signatureLength,
                  blobLength <= signatureLength - blobOffset,
                  Int(blobOffset + blobLength) <= signature.count else { continue }

            let plistData = signature.subdata(in: Int(blobOffset + 8)..<Int(blobOffset + blobLength))
            if let plistObject = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil),
               let plist = plistObject as? [String: Any] {
                return plist
            }
        }
        return nil
    }

    private static func readUInt32(_ data: Data, at offset: Int, order: ByteOrder) -> UInt32? {
        guard offset >= 0, offset <= data.count - 4 else { return nil }
        let bytes = data[offset..<(offset + 4)]
        guard let first = bytes.first else { return nil }
        let values = Array(bytes)
        switch order {
        case .big:
            return UInt32(values[0]) << 24 | UInt32(values[1]) << 16 | UInt32(values[2]) << 8 | UInt32(values[3])
        case .little:
            return UInt32(values[3]) << 24 | UInt32(values[2]) << 16 | UInt32(values[1]) << 8 | UInt32(first)
        }
    }

    private static func readUInt64(_ data: Data, at offset: Int, order: ByteOrder) -> UInt64? {
        guard offset >= 0, offset <= data.count - 8 else { return nil }
        let values = Array(data[offset..<(offset + 8)])
        switch order {
        case .big:
            return values.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        case .little:
            return values.reversed().reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        }
    }
}

@MainActor
final class CloudKitBackupCoordinator: ObservableObject {
    nonisolated static let containerIdentifier = "iCloud.com.f.redfruittracker"
    private static let recordType = "LibraryBackup"
    private static let archiveField = "archive"
    private static let hashField = "archiveSHA256"
    private static let exportedAtField = "exportedAt"
    private static let schemaVersionField = "schemaVersion"
    private static let recordCountField = "recordCount"

    @Published private(set) var state: CloudBackupState = .idle

    private let injectedContainer: CKContainer?
    private let cloudKitEnabled: Bool
    private lazy var cloudContainer: CKContainer = {
        CKContainer(identifier: Self.containerIdentifier)
    }()
    private var debounceTask: Task<Void, Never>?
    private var isSyncing = false
    private var needsAnotherSync = false
    private var lastUploadedHash: String?

    init(container: CKContainer? = nil, cloudKitEnabled: Bool? = nil) {
        injectedContainer = container
        self.cloudKitEnabled = cloudKitEnabled ?? CloudBackupRuntimePolicy.isCloudKitEnabled
    }

    func start(context: ModelContext) async {
        guard prepareCloudKitIfEnabled() else { return }
        guard !isUITesting else { return }
        await synchronize(context: context, forceUpload: false)
    }

    /// A save is local and immediate. This queues a cloud snapshot after a
    /// short delay so multiple fields edited in one screen produce one upload.
    func scheduleAutomaticSync(context: ModelContext) {
        guard prepareCloudKitIfEnabled() else { return }
        guard !isUITesting else { return }
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(800))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            await self.synchronize(context: context, forceUpload: false)
        }
    }

    func manualSync(context: ModelContext) async {
        guard prepareCloudKitIfEnabled() else { return }
        await synchronize(context: context, forceUpload: true)
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }

    private func synchronize(context: ModelContext, forceUpload: Bool) async {
        guard prepareCloudKitIfEnabled() else { return }
        guard !isUITesting else { return }
        guard !isSyncing else {
            needsAnotherSync = true
            return
        }

        isSyncing = true
        needsAnotherSync = false
        state = .syncing
        defer {
            isSyncing = false
            if needsAnotherSync {
                scheduleAutomaticSync(context: context)
            }
        }

        do {
            let container = injectedContainer ?? cloudContainer
            let account = try await container.accountStatus()
            guard account == .available else {
                state = .unavailable(accountMessage(for: account))
                return
            }

            let archive = try LibraryBackupArchive.export(from: context)
            let database = container.privateCloudDatabase
            let remote = try await latestRemoteSnapshot(in: database)

            if archive.recordCount == 0, let remote,
               let restoredData = try await data(for: remote) {
                let restored = try LibraryBackupArchive.decode(restoredData)
                try restored.restore(into: context)
                try context.saveAndNotifyCloudBackup()
                state = .synced(.now)
                return
            }

            guard archive.recordCount > 0 else {
                state = .synced(.now)
                return
            }

            let data = try archive.encodedData()
            let hash = Self.sha256(data)

            let remoteHash = remote?.record[Self.hashField] as? String
            if !forceUpload, (hash == remoteHash || hash == lastUploadedHash) {
                state = .synced(archive.exportedAt)
                return
            }

            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("redfruit-library-\(UUID().uuidString).json")
            try data.write(to: temporaryURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }

            let record = CKRecord(recordType: Self.recordType)
            record[Self.archiveField] = CKAsset(fileURL: temporaryURL)
            record[Self.hashField] = hash as NSString
            record[Self.exportedAtField] = archive.exportedAt as NSDate
            record[Self.schemaVersionField] = archive.schemaVersion as NSNumber
            record[Self.recordCountField] = archive.recordCount as NSNumber
            _ = try await database.save(record)
            lastUploadedHash = hash
            state = .synced(archive.exportedAt)
        } catch {
            state = state(for: error)
        }
    }

    @discardableResult
    private func prepareCloudKitIfEnabled() -> Bool {
        guard cloudKitEnabled else {
            state = .unavailable(CloudBackupRuntimePolicy.disabledMessage)
            return false
        }
        guard injectedContainer != nil || CloudBackupRuntimePolicy.hasCloudKitEntitlements(
            containerIdentifier: Self.containerIdentifier
        ) else {
            state = .unavailable(CloudBackupRuntimePolicy.missingEntitlementMessage)
            return false
        }
        return true
    }

    private struct RemoteSnapshot {
        let record: CKRecord
    }

    private func latestRemoteSnapshot(in database: CKDatabase) async throws -> RemoteSnapshot? {
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: Self.exportedAtField, ascending: false)]
        let (results, _) = try await database.records(
            matching: query,
            inZoneWith: nil,
            desiredKeys: [Self.archiveField, Self.hashField, Self.exportedAtField],
            resultsLimit: 1
        )
        for (_, result) in results {
            if case .success(let record) = result { return RemoteSnapshot(record: record) }
        }
        return nil
    }

    private func data(for snapshot: RemoteSnapshot) async throws -> Data? {
        guard let asset = snapshot.record[Self.archiveField] as? CKAsset,
              let fileURL = asset.fileURL else { return nil }
        return try Data(contentsOf: fileURL)
    }

    private func accountMessage(for status: CKAccountStatus) -> String {
        switch status {
        case .noAccount: return "请登录 iCloud"
        case .restricted: return "iCloud 受限制"
        case .couldNotDetermine: return "iCloud 状态未知"
        case .available: return "iCloud 可用"
        case .temporarilyUnavailable: return "iCloud 暂不可用"
        @unknown default: return "iCloud 暂不可用"
        }
    }

    private func state(for error: Error) -> CloudBackupState {
        guard let cloudError = error as? CKError else {
            return .failed(error.localizedDescription)
        }
        switch cloudError.code {
        case .notAuthenticated:
            return .unavailable("请登录 iCloud")
        case .permissionFailure, .badContainer:
            return .unavailable("当前签名没有访问此 iCloud 容器的权限；请检查 Apple Developer 中的 CloudKit 容器和签名描述文件。记录仍保存在本机。")
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited,
             .zoneBusy, .operationCancelled:
            return .unavailable("网络暂不可用，数据已保存在本机")
        case .quotaExceeded:
            return .unavailable("iCloud 空间不足")
        default:
            return .failed(cloudError.localizedDescription)
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
