import CloudKit
import Combine
import CryptoKit
import Foundation
import Security
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
        return try decoder.decode(Self.self, from: data)
    }

    @MainActor
    func restore(into context: ModelContext) {
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
        for value in importInboxItems {
            let record = ImportInboxItem(originalURL: value.originalURL, status: value.status)
            record.importedAt = value.importedAt
            record.failureMessage = value.failureMessage
            context.insert(record)
        }
        for value in updateNotifications {
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
        guard let task = SecTaskCreateFromSelf(nil),
              let services = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.icloud-services" as CFString,
                nil
              ) as? [String],
              let containers = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.icloud-container-identifiers" as CFString,
                nil
              ) as? [String] else {
            return false
        }

        return services.contains("CloudKit") && containers.contains(containerIdentifier)
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
                restored.restore(into: context)
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
