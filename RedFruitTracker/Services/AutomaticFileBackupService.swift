import BackgroundTasks
import Foundation
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum AutomaticFileBackupService {
    static let taskIdentifier = "com.f.redfruittracker.automatic-file-backup"
    static let statusKey = "redFruitTracker.automaticFileBackupStatus"
    private static let bookmarkKey = "redFruitTracker.automaticFileBackupFolderBookmark"
    private static let lastBackupDayKey = "redFruitTracker.automaticFileBackupLastDay"

    static func register(container: ModelContainer) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            run(processingTask, container: container)
        }
        scheduleNextRun()
    }

    static func scheduleNextRun(now: Date = .now, calendar: Calendar = .autoupdatingCurrent) {
        let startOfToday = calendar.startOfDay(for: now)
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            ?? now.addingTimeInterval(24 * 60 * 60)
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = nextMidnight
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func setFolder(_ folderURL: URL, context: ModelContext) throws {
        let didAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { folderURL.stopAccessingSecurityScopedResource() }
        }

        let values = try folderURL.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw CocoaError(.fileReadUnsupportedScheme) }
        let bookmark = try folderURL.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: lastBackupDayKey)
        try writeBackup(to: folderURL, context: context)
        scheduleNextRun()
    }

    @MainActor
    static func runIfDue(context: ModelContext, now: Date = .now, calendar: Calendar = .autoupdatingCurrent) {
        guard UserDefaults.standard.string(forKey: lastBackupDayKey) != dayKey(for: now, calendar: calendar),
              let folderURL = resolvedFolderURL() else { return }
        do {
            try writeBackup(to: folderURL, context: context, now: now, calendar: calendar)
        } catch {
            UserDefaults.standard.set("自动备份失败：\(error.localizedDescription)", forKey: statusKey)
        }
    }

    private static func run(_ task: BGTask, container: ModelContainer) {
        scheduleNextRun()
        let operation = Task { @MainActor in
            runIfDue(context: container.mainContext)
            let succeeded = UserDefaults.standard.string(forKey: lastBackupDayKey) == dayKey(for: .now, calendar: .autoupdatingCurrent)
            task.setTaskCompleted(success: succeeded)
        }
        task.expirationHandler = { operation.cancel() }
    }

    @MainActor
    private static func writeBackup(
        to folderURL: URL,
        context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws {
        let didAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { folderURL.stopAccessingSecurityScopedResource() }
        }

        let archive = try LibraryBackupArchive.export(from: context, exportedAt: now)
        let data = try archive.encodedData()
        let destination = folderURL.appendingPathComponent("漫剧记录自动备份_\(timestamp(now, calendar: calendar)).json")
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: destination, options: [], error: &coordinationError) { url in
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }

        UserDefaults.standard.set(dayKey(for: now, calendar: calendar), forKey: lastBackupDayKey)
        UserDefaults.standard.set("上次自动备份 \(timestamp(now, calendar: calendar))", forKey: statusKey)
    }

    private static func resolvedFolderURL() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let folderURL = try? URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            UserDefaults.standard.set("自动备份目录授权已失效，请重新选择 iCloud Drive 文件夹", forKey: statusKey)
            return nil
        }
        if isStale, let renewedBookmark = try? folderURL.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(renewedBookmark, forKey: bookmarkKey)
        }
        return folderURL
    }

    private static func timestamp(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy.MM.dd__HH.mm"
        return formatter.string(from: date)
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct BackupFolderPicker: UIViewControllerRepresentable {
    let onResult: (Result<URL, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onResult: onResult)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onResult: (Result<URL, Error>) -> Void

        init(onResult: @escaping (Result<URL, Error>) -> Void) {
            self.onResult = onResult
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onResult(.failure(CocoaError(.fileNoSuchFile)))
                return
            }
            onResult(.success(url))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onResult(.failure(CocoaError(.userCancelled)))
        }
    }
}
