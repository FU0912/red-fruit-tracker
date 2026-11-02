import Foundation
import ImageIO
import SwiftData
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab = 0
    @State private var isShowingAdd = false
    @State private var pendingShareURL: URL?
    @State private var presentedShareURL: URL?
    @State private var pendingShareRetryToken = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            LibraryView(
                pendingShareURL: pendingShareURL,
                onAdd: { isShowingAdd = true }
            )
            .tabItem {
                Label("书架", systemImage: "books.vertical.fill")
            }
            .tag(0)

            StatsView()
                .tabItem {
                    Label("统计", systemImage: "chart.xyaxis.line")
                }
                .tag(1)
        }
        .sheet(isPresented: $isShowingAdd, onDismiss: refreshPendingShare) {
            AddSeriesView(initialURL: pendingShareURL, autoSaveInitialURL: presentedShareURL != nil) {
                if let pendingShareURL {
                    ShareInbox.remove(pendingShareURL)
                }
                presentedShareURL = nil
            }
        }
        .task {
            refreshPendingShare()
            schedulePendingShareRetry()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshPendingShare()
                schedulePendingShareRetry()
            }
        }
        .onOpenURL { callbackURL in
            if let sharedURL = ShareRoute.sharedURL(from: callbackURL) {
                ShareInbox.enqueue(sharedURL)
            }
            refreshPendingShare()
            schedulePendingShareRetry()
        }
    }

    private func refreshPendingShare() {
        let nextURL = ShareInbox.firstURL()
        pendingShareURL = nextURL
        guard let nextURL,
              presentedShareURL != nextURL,
              !isShowingAdd else {
            if nextURL == nil {
                presentedShareURL = nil
            }
            return
        }

        selectedTab = 0
        presentedShareURL = nextURL
        // Let the scene finish foregrounding before presenting a sheet. This
        // avoids the share extension's handoff animation dismissing the sheet
        // in the same run loop as the URL callback.
        Task { @MainActor in
            await Task.yield()
            guard ShareInbox.firstURL() == nextURL,
                  presentedShareURL == nextURL,
                  !isShowingAdd else { return }
            isShowingAdd = true
        }

    }

    private func schedulePendingShareRetry() {
        pendingShareRetryToken &+= 1
        schedulePendingShareRetry(token: pendingShareRetryToken, attempt: 0)
    }

    private func schedulePendingShareRetry(token: Int, attempt: Int) {
        guard attempt < 5 else { return }

        // App Groups are eventually consistent across the extension and host
        // processes. A delayed read covers the handoff where iOS foregrounds
        // the app before the shared defaults store has refreshed.
        let delay = 0.25 * Double(attempt + 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard token == pendingShareRetryToken, !isShowingAdd else { return }
            refreshPendingShare()
            if !isShowingAdd {
                schedulePendingShareRetry(token: token, attempt: attempt + 1)
            }
        }
    }
}

private struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [
        SortDescriptor(\SeriesRecord.createdAt, order: .reverse),
        SortDescriptor(\SeriesRecord.sourceSeriesID)
    ])
    private var series: [SeriesRecord]

    @Query(sort: \SeasonRecord.seasonNumber)
    private var seasons: [SeasonRecord]

    @Query(sort: \PersonalRecord.updatedAt, order: .reverse)
    private var personalRecords: [PersonalRecord]

    let pendingShareURL: URL?
    let onAdd: () -> Void

    @AppStorage("redFruitTracker.officialRatingTrendCleaned") private var didClearLegacyRatingTrend = false
    @State private var searchText = ""
    @State private var isRefreshingAll = false
    @State private var refreshProgress = BatchRefreshProgress(total: 0)
    @State private var refreshTask: Task<Void, Never>?
    @State private var isStoppingRefresh = false
    @State private var refreshNotice: String?
    @State private var selectedSeries: SeriesRecord?
    @State private var seriesToDelete: SeriesRecord?
    @State private var deletionErrorMessage: String?

    private var visibleSeries: [SeriesRecord] {
        series.filter {
            LibrarySearch.matches(title: $0.title, tags: $0.tagsText, intro: $0.intro, query: searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleSeries.isEmpty {
                    VStack(spacing: 0) {
                        LibraryHeader(
                            searchText: $searchText,
                            isRefreshing: isRefreshingAll,
                            progress: refreshProgress,
                            isStopping: isStoppingRefresh,
                            onCancel: cancelRefresh,
                            onRefreshAll: refreshAllMetadata
                        )
                        LibraryEmptyState(isSearching: !searchText.isEmpty, onAdd: onAdd)
                    }
                } else {
                    List {
                        LibraryHeader(
                            searchText: $searchText,
                            isRefreshing: isRefreshingAll,
                            progress: refreshProgress,
                            isStopping: isStoppingRefresh,
                            onCancel: cancelRefresh,
                            onRefreshAll: refreshAllMetadata
                        )
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)

                        if let pendingShareURL {
                            ShareImportBanner(url: pendingShareURL, onTap: onAdd)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }

                        ForEach(visibleSeries) { item in
                            Button {
                                selectedSeries = item
                            } label: {
                                SeriesCard(
                                    series: item,
                                    seasons: seasons.filter { $0.sourceSeriesID == item.sourceSeriesID },
                                    personal: personalRecords.first { $0.sourceSeriesID == item.sourceSeriesID }
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("series-card-\(item.sourceSeriesID)")
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    seriesToDelete = item
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                .accessibilityIdentifier("delete-series-\(item.sourceSeriesID)")
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .padding(.top, 6)
                    .accessibilityIdentifier("library-list")
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottomTrailing) {
                if !visibleSeries.isEmpty {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .frame(width: 56, height: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                    .accessibilityIdentifier("add-series-button")
                    .accessibilityLabel("添加作品")
                    .padding(.trailing, 18)
                    .padding(.bottom, 16)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationDestination(item: $selectedSeries) { series in
                SeriesDetailView(series: series)
            }
            .alert("删除这部漫剧？", isPresented: Binding(
                get: { seriesToDelete != nil },
                set: { if !$0 { seriesToDelete = nil } }
            )) {
                Button("删除", role: .destructive) {
                    if let seriesToDelete {
                        delete(seriesToDelete)
                    }
                    seriesToDelete = nil
                }
                Button("取消", role: .cancel) {
                    seriesToDelete = nil
                }
            } message: {
                Text("会同时删除这部作品的季、集、评分和公开资料快照。")
            }
            .alert("删除失败", isPresented: Binding(
                get: { deletionErrorMessage != nil },
                set: { if !$0 { deletionErrorMessage = nil } }
            )) {
                Button("好", role: .cancel) {
                    deletionErrorMessage = nil
                }
            } message: {
                Text(deletionErrorMessage ?? "")
            }
            .alert("公开资料更新", isPresented: Binding(
                get: { refreshNotice != nil },
                set: { if !$0 { refreshNotice = nil } }
            )) {
                Button("好", role: .cancel) { refreshNotice = nil }
            } message: {
                Text(refreshNotice ?? "")
            }
            .task {
                clearLegacyRatingTrend()
            }
        }
    }

    private func delete(_ series: SeriesRecord) {
        do {
            let sourceID = series.sourceSeriesID
            let seasons = try modelContext.fetch(FetchDescriptor<SeasonRecord>())
            let episodes = try modelContext.fetch(FetchDescriptor<EpisodeRecord>())
            let personal = try modelContext.fetch(FetchDescriptor<PersonalRecord>())
            let snapshots = try modelContext.fetch(FetchDescriptor<OfficialSnapshot>())

            seasons.filter { $0.sourceSeriesID == sourceID }.forEach { modelContext.delete($0) }
            episodes.filter { $0.sourceSeriesID == sourceID }.forEach { modelContext.delete($0) }
            personal.filter { $0.sourceSeriesID == sourceID }.forEach { modelContext.delete($0) }
            snapshots.filter { $0.sourceSeriesID == sourceID }.forEach { modelContext.delete($0) }
            modelContext.delete(series)
            try modelContext.save()
        } catch {
            deletionErrorMessage = error.localizedDescription
        }
    }

    private func clearLegacyRatingTrend() {
        guard !didClearLegacyRatingTrend else { return }
        do {
            let snapshots = try modelContext.fetch(FetchDescriptor<OfficialSnapshot>())
            let legacySnapshots = snapshots.filter {
                $0.officialRating != nil || $0.officialRatingCount != nil
            }
            guard !legacySnapshots.isEmpty else {
                didClearLegacyRatingTrend = true
                return
            }
            legacySnapshots.forEach { $0.clearLegacyRatingTrend() }
            try modelContext.save()
            didClearLegacyRatingTrend = true
        } catch {
            return
        }
    }

    private func refreshAllMetadata() {
        startRefresh(showNotice: true)
    }

    private func startRefresh(showNotice: Bool) {
        guard !isRefreshingAll, refreshTask == nil else { return }
        refreshTask = Task { @MainActor in
            await refreshAllMetadata(showNotice: showNotice)
            refreshTask = nil
        }
    }

    private func cancelRefresh() {
        isStoppingRefresh = true
        refreshTask?.cancel()
    }

    @MainActor
    private func refreshAllMetadata(showNotice: Bool) async {
        guard !isRefreshingAll else { return }
        isRefreshingAll = true
        isStoppingRefresh = false
        defer { isRefreshingAll = false; isStoppingRefresh = false }

        let candidates = series.compactMap { item -> (SeriesRecord, URL)? in
            guard let sourceURL = item.sourceURL,
                  let url = URL(string: sourceURL),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            return (item, url)
        }
        refreshProgress = BatchRefreshProgress(total: candidates.count)
        let skipped = series.count - candidates.count

        for (item, url) in candidates {
            if Task.isCancelled { break }
            do {
                let metadata = try await PublicMetadataService.shared.fetch(from: url)
                try Task.checkCancellation()
                await applyPublicMetadata(metadata, to: item)
                try Task.checkCancellation()
                mergePublicSeasons(metadata.seasons, for: item)
                insertSnapshot(for: item, metadata: metadata)
                try modelContext.save()
                refreshProgress.record(success: true)
            } catch {
                if Task.isCancelled { break }
                refreshProgress.record(success: false)
            }
        }

        if showNotice {
            let status = Task.isCancelled ? "已停止更新" : "更新完成"
            refreshNotice = "\(status)：已处理 \(refreshProgress.completed)/\(refreshProgress.total) 部，成功 \(refreshProgress.succeeded) 部，失败 \(refreshProgress.failed) 部。"
                + (skipped > 0 ? "另有 \(skipped) 部没有网页链接，已跳过。" : "")
                + "个人评分、点评、观看状态和书架顺序均保留。"
        }
    }

    private func applyPublicMetadata(_ metadata: PublicSeriesMetadata, to item: SeriesRecord) async {
        if let coverURL = metadata.coverURL?.nilIfBlank,
           item.coverURL == nil || CoverURLSelector.shouldReplaceExisting(item.coverURL) {
            item.coverURL = coverURL
        } else if let existingCover = item.coverURL {
            // Only replace a legacy cover after a successful image probe. A
            // timeout or CDN failure must not erase a user-selected poster.
            if await CoverImageProbe.orientation(urlString: existingCover) == .landscape {
                if let coverURL = metadata.coverURL?.nilIfBlank {
                    item.coverURL = coverURL
                } else {
                    item.coverURL = nil
                }
            }
        }
        if item.intro.isEmpty, let intro = metadata.intro, !intro.isEmpty {
            item.intro = intro
        }
        if item.tagsText.isEmpty, let tagsText = metadata.tagsText, !tagsText.isEmpty {
            item.tagsText = tagsText
        }
        if let rating = metadata.officialRating { item.officialRating = rating }
        if let ratingCount = metadata.officialRatingCount { item.officialRatingCount = ratingCount }
        if let heatScore = metadata.officialHeatScore { item.officialHeatScore = heatScore }
        if let heat = metadata.officialHeatText, !heat.isEmpty { item.officialHeatText = heat }
        item.updatedAt = .now
    }

    private func mergePublicSeasons(_ metadataSeasons: [PublicSeasonMetadata], for item: SeriesRecord) {
        guard !metadataSeasons.isEmpty else { return }
        guard let existingSeasons = try? modelContext.fetch(FetchDescriptor<SeasonRecord>()),
              let existingEpisodes = try? modelContext.fetch(FetchDescriptor<EpisodeRecord>()) else {
            return
        }

        for metadataSeason in metadataSeasons {
            let existing = existingSeasons.first {
                $0.sourceSeriesID == item.sourceSeriesID && $0.seasonNumber == metadataSeason.seasonNumber
            }
            let season = existing ?? SeasonRecord(
                sourceSeriesID: item.sourceSeriesID,
                seasonNumber: metadataSeason.seasonNumber
            )
            if existing == nil { modelContext.insert(season) }
            if season.title.isEmpty { season.title = metadataSeason.title ?? "第\(metadataSeason.seasonNumber)季" }
            season.episodeCount = SeasonEpisodeCount.latest(
                existing: season.episodeCount,
                reported: metadataSeason.episodeCount,
                observed: metadataSeason.episodes.count
            )
            season.sourceURL = metadataSeason.sourceURL ?? season.sourceURL ?? item.sourceURL
            season.updatedAt = .now

            for metadataEpisode in metadataSeason.episodes {
                let existingEpisode = existingEpisodes.first {
                    $0.sourceSeriesID == item.sourceSeriesID
                        && $0.seasonNumber == metadataSeason.seasonNumber
                        && $0.episodeNumber == metadataEpisode.episodeNumber
                }
                let episode = existingEpisode ?? EpisodeRecord(
                    sourceVid: "\(item.sourceSeriesID)#s\(metadataSeason.seasonNumber)#e\(metadataEpisode.episodeNumber)",
                    sourceSeriesID: item.sourceSeriesID,
                    seasonNumber: metadataSeason.seasonNumber,
                    episodeNumber: metadataEpisode.episodeNumber
                )
                if existingEpisode == nil { modelContext.insert(episode) }
                if let title = metadataEpisode.title, !title.isEmpty { episode.title = title }
                if let webURL = metadataEpisode.webURL { episode.webURL = webURL }
            }
        }
    }

    private func insertSnapshot(for item: SeriesRecord, metadata: PublicSeriesMetadata) {
        guard metadata.officialHeatScore != nil
                || !(metadata.officialHeatText?.isEmpty ?? true)
                || !metadata.seasons.isEmpty else {
            return
        }
        let snapshot = OfficialSnapshot(sourceSeriesID: item.sourceSeriesID)
        snapshot.officialHeatScore = metadata.officialHeatScore
        snapshot.officialHeatText = metadata.officialHeatText
        if !metadata.seasons.isEmpty {
            snapshot.seasonCount = metadata.seasons.count
            snapshot.episodeCount = metadata.seasons.map(\.episodeCount).reduce(0, +)
        }
        modelContext.insert(snapshot)
    }
}

private struct LibraryHeader: View {
    @Binding var searchText: String
    let isRefreshing: Bool
    let progress: BatchRefreshProgress
    let isStopping: Bool
    let onCancel: () -> Void
    let onRefreshAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("漫剧记录")
                    .font(.system(size: 34, weight: .bold))
                    .accessibilityIdentifier("library-header-title")
                Spacer()
                Button(action: onRefreshAll) {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("更新全部公开资料")
                .disabled(isRefreshing)
            }

            if isRefreshing {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("已处理 \(progress.completed)/\(progress.total) 部")
                            .monospacedDigit()
                        Spacer()
                        Button(isStopping ? "正在停止…" : "停止", action: onCancel)
                            .disabled(isStopping)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
                        .accessibilityLabel("公开资料更新进度")
                    Text("成功 \(progress.succeeded) · 失败 \(progress.failed)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .accessibilityIdentifier("library-refresh-progress")
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)

                TextField("搜索作品名、简介或 #标签", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("library-search-field")

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(Capsule())
        }
        .padding(.horizontal, AppLayout.pageInset)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityIdentifier("library-header")
    }
}

private struct LibraryEmptyState: View {
    let isSearching: Bool
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: isSearching ? "magnifyingglass" : "books.vertical")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.secondary)

            Text(isSearching ? "没有匹配的作品" : "还没有记录")
                .font(.title3.weight(.semibold))

            Text(isSearching ? "换一个关键词试试" : "从红果漫剧分享一条链接，或手动添加作品")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !isSearching {
                Button(action: onAdd) {
                    Label("添加作品", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

private struct ShareImportBanner: View {
    let url: URL
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.on.square.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("有一条待处理的分享链接")
                        .font(.subheadline.weight(.semibold))
                    Text(url.host ?? url.absoluteString)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppLayout.pageInset)
            .padding(.vertical, 10)
            .background(.thinMaterial)
        }
        .buttonStyle(.plain)
    }
}

private struct SeriesCard: View {
    let series: SeriesRecord
    let seasons: [SeasonRecord]
    let personal: PersonalRecord?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverView(urlString: series.coverURL, title: series.title)
                .frame(width: 92, height: 128)
                .fixedSize()
                .accessibilityIdentifier("series-card-cover")
                .accessibilityLabel("\(series.title)封面")

            VStack(alignment: .leading, spacing: 8) {
                Text(series.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .accessibilityIdentifier("series-card-title")

                FixedWorkMetricGrid(metrics: [
                    WorkMetric(
                        id: "series-card-official-rating",
                        label: "官方",
                        value: series.officialRating.map { String(format: "%.1f", $0) } ?? "暂无评分",
                        tint: .orange,
                        symbol: "star.fill"
                    ),
                    WorkMetric(
                        id: "series-card-personal-rating",
                        label: "我的",
                        value: personal?.myRating.map { String(format: "%.1f", $0) } ?? "未评分",
                        tint: .blue,
                        symbol: "person.fill"
                    ),
                    WorkMetric(
                        id: "series-card-heat",
                        label: "热度",
                        value: compactHeatText,
                        tint: .pink,
                        symbol: "flame.fill"
                    ),
                    WorkMetric(
                        id: "series-card-season-count",
                        label: "季数",
                        value: seasons.isEmpty ? "待录入" : "\(seasons.count)季",
                        tint: .teal,
                        symbol: "square.stack.3d.up.fill"
                    )
                ])

                TagFlowLayout(horizontalSpacing: 4, verticalSpacing: 4) {
                    CompactInfoPill(
                        text: completionStatusText,
                        systemImage: completionStatusSymbol,
                        tint: completionStatusTint
                    )
                    .accessibilityIdentifier("series-card-completion-status")

                    CompactInfoPill(
                        text: shelfState.title,
                        systemImage: shelfState.systemImage,
                        tint: shelfStateTint
                    )
                    .accessibilityIdentifier("series-card-shelf-state")

                    if personal?.followsUpdates == true {
                        CompactInfoPill(
                            text: "追更",
                            systemImage: "bell.badge.fill",
                            tint: .indigo
                        )
                        .accessibilityIdentifier("series-card-follow-updates")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TagFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    if tags.isEmpty {
                        TagPill(text: "标签待读取")
                    } else {
                        ForEach(tags, id: \.self) { tag in
                            TagPill(text: tag)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 52, alignment: .topLeading)
                .clipped()

            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var tags: [String] {
        tagValues(series.tagsText)
    }

    private var compactHeatText: String {
        guard let heat = series.officialHeatText?.trimmingCharacters(in: .whitespacesAndNewlines), !heat.isEmpty else {
            return "待读取"
        }
        return heat.replacingOccurrences(of: "热度", with: "")
    }

    private var completionStatus: SeriesCompletionStatus {
        SeriesCompletionStatus(rawValue: series.completionStatus ?? "") ?? .unknown
    }

    private var completionStatusText: String {
        completionStatus.title
    }

    private var completionStatusSymbol: String {
        switch completionStatus {
        case .completed: return "checkmark.seal.fill"
        case .ongoing: return "clock"
        case .unknown: return "questionmark.circle"
        }
    }

    private var completionStatusTint: Color {
        switch completionStatus {
        case .completed: return .green
        case .ongoing: return .orange
        case .unknown: return .secondary
        }
    }

    private var shelfState: ShelfState {
        ShelfState.resolve(personal?.localShelfState)
    }

    private var shelfStateTint: Color {
        switch shelfState {
        case .unstarted: return .secondary
        case .watching: return .blue
        case .finished: return .green
        case .paused: return .orange
        case .dropped: return .red
        }
    }
}

private struct CompactInfoPill: View {
    let text: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            Text(text)
        }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(tint.opacity(0.1))
            .clipShape(Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(text)
    }
}

struct TagPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.65))
            .clipShape(Capsule())
    }
}

struct TagFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowCount = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextWidth = rowWidth == 0 ? size.width : rowWidth + horizontalSpacing + size.width
            if rowWidth > 0, nextWidth > maxWidth {
                totalHeight += rowHeight
                rowCount += 1
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth = nextWidth
                rowHeight = max(rowHeight, size.height)
            }
        }

        if rowWidth > 0 {
            totalHeight += rowHeight
            rowCount += 1
        }

        return CGSize(
            width: proposal.width ?? min(maxWidth, rowWidth),
            height: totalHeight + CGFloat(max(0, rowCount - 1)) * verticalSpacing
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

func tagValues(_ value: String) -> [String] {
    value
        .components(separatedBy: CharacterSet(charactersIn: ",，、|丨·/"))
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private final class CoverImageLoader: ObservableObject {
    private static let cache = NSCache<NSString, UIImage>()

    @Published private(set) var image: UIImage?
    @Published private(set) var isLoading = false
    @Published private(set) var hasFailed = false
    private var task: URLSessionDataTask?
    private var loadedURL: String?

    func load(urlString: String?, force: Bool = false) {
        guard let normalizedURLString = urlString?.nilIfBlank,
              let url = URL(string: normalizedURLString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            task?.cancel()
            task = nil
            loadedURL = nil
            image = nil
            isLoading = false
            hasFailed = false
            return
        }

        if !force, loadedURL == normalizedURLString, image != nil { return }
        loadedURL = normalizedURLString
        task?.cancel()
        hasFailed = false

        if let cached = Self.cache.object(forKey: normalizedURLString as NSString) {
            image = cached
            isLoading = false
            return
        }

        image = nil
        isLoading = true
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("image/jpeg,image/png,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("https://hongguoduanju.com/", forHTTPHeaderField: "Referer")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")

        task = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let data,
                  let httpResponse = response as? HTTPURLResponse,
                  200..<400 ~= httpResponse.statusCode,
                  let image = Self.decodeImage(data) else {
                DispatchQueue.main.async {
                    guard let self, self.loadedURL == normalizedURLString else { return }
                    self.image = nil
                    self.isLoading = false
                    self.hasFailed = true
                }
                return
            }

            Self.cache.setObject(image, forKey: normalizedURLString as NSString)
            DispatchQueue.main.async {
                guard let self, self.loadedURL == normalizedURLString else { return }
                self.image = image
                self.isLoading = false
            }
        }
        task?.resume()
    }

    func retry() {
        load(urlString: loadedURL, force: true)
    }

    private static func decodeImage(_ data: Data) -> UIImage? {
        if let image = UIImage(data: data) {
            return image
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    deinit {
        task?.cancel()
    }
}

struct CoverView: View {
    let urlString: String?
    let title: String?

    let width: CGFloat
    let height: CGFloat
    @StateObject private var loader: CoverImageLoader

    init(urlString: String?, title: String? = nil, width: CGFloat = 92, height: CGFloat = 128) {
        self.urlString = urlString
        self.title = title
        self.width = width
        self.height = height
        _loader = StateObject(wrappedValue: CoverImageLoader())
    }

    var body: some View {
        ZStack {
            fallback

            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
            } else if loader.isLoading {
                ProgressView()
                    .tint(.secondary)
            } else if loader.hasFailed {
                Button(action: loader.retry) {
                    Label("重试封面", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cover-load-retry")
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { loader.load(urlString: urlString) }
        .onChange(of: urlString) { _, newValue in loader.load(urlString: newValue) }
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: loader.hasFailed ? "photo.badge.exclamationmark" : "book.closed")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.secondary)
                    if let title = title?.nilIfBlank {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                            .padding(.horizontal, 8)
                    }
                    if urlString?.nilIfBlank == nil {
                        Text("暂无官方海报")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
    }
}

private struct StatsView: View {
    @Query(sort: [
        SortDescriptor(\SeriesRecord.createdAt, order: .reverse),
        SortDescriptor(\SeriesRecord.sourceSeriesID)
    ])
    private var series: [SeriesRecord]
    @Query private var personalRecords: [PersonalRecord]
    @Query(sort: \OfficialSnapshot.capturedAt, order: .reverse)
    private var snapshots: [OfficialSnapshot]

    private var completedCount: Int {
        series.filter { $0.completionStatus == SeriesCompletionStatus.completed.rawValue }.count
    }

    private var ongoingCount: Int {
        series.filter { $0.completionStatus == SeriesCompletionStatus.ongoing.rawValue }.count
    }

    private var unknownStatusCount: Int {
        series.filter { $0.completionStatus == nil || $0.completionStatus == SeriesCompletionStatus.unknown.rawValue }.count
    }

    private var lastUpdateText: String {
        guard let date = snapshots.map(\.capturedAt).max() else { return "暂无更新" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("总览")
                        .font(.title2.weight(.bold))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(LibraryFilter.allCases) { filter in
                            NavigationLink {
                                FilteredSeriesView(filter: filter)
                            } label: {
                                StatTile(
                                    title: filter.title,
                                    value: "\(count(for: filter))",
                                    symbol: filter.systemImage
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("stats-filter-\(filter.rawValue)")
                        }
                    }

                    NavigationLink {
                        SeasonChangeLogView(series: series, snapshots: snapshots)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("季集数变化记录")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("查看哪部作品发生变化、旧值、新值和时间")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text("\(SeasonChangeHistory.changes(from: snapshots).count)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(AppLayout.pageInset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("season-change-log-link")

                    VStack(alignment: .leading, spacing: 10) {
                        Label("公开资料更新", systemImage: "arrow.clockwise")
                            .font(.headline)
                        Text("最近一次公开资料更新：\(lastUpdateText)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppLayout.pageInset)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if unknownStatusCount > 0 {
                        Text("还有 \(unknownStatusCount) 部作品待手动选择完结状态。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(AppLayout.pageInset)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("统计")
        }
    }

    private func count(for filter: LibraryFilter) -> Int {
        switch filter {
        case .all:
            return series.count
        case .completed:
            return completedCount
        case .ongoing:
            return ongoingCount
        case .unknown:
            return unknownStatusCount
        case .followed:
            return series.filter { item in
                personalRecords.first(where: { $0.sourceSeriesID == item.sourceSeriesID })?.followsUpdates == true
            }.count
        case .unstarted, .watching, .finished, .paused, .dropped:
            return series.filter { item in
                ShelfState.resolve(
                    personalRecords.first(where: { $0.sourceSeriesID == item.sourceSeriesID })?.localShelfState
                ).rawValue == filter.rawValue
            }.count
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
            Text(value)
                .font(.title2.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct FilteredSeriesView: View {
    let filter: LibraryFilter

    @State private var selectedSeriesID: String?
    @State private var isShowingSeries = false

    @Query(sort: [
        SortDescriptor(\SeriesRecord.createdAt, order: .reverse),
        SortDescriptor(\SeriesRecord.sourceSeriesID)
    ])
    private var series: [SeriesRecord]
    @Query(sort: \SeasonRecord.seasonNumber)
    private var seasons: [SeasonRecord]
    @Query private var personalRecords: [PersonalRecord]

    private var filteredSeries: [SeriesRecord] {
        series.filter { item in
            switch filter {
            case .all:
                return true
            case .completed:
                return item.completionStatus == SeriesCompletionStatus.completed.rawValue
            case .ongoing:
                return item.completionStatus == SeriesCompletionStatus.ongoing.rawValue
            case .unknown:
                return item.completionStatus == nil
                    || item.completionStatus == SeriesCompletionStatus.unknown.rawValue
            case .followed:
                return personalRecords.first(where: { $0.sourceSeriesID == item.sourceSeriesID })?.followsUpdates == true
            case .unstarted, .watching, .finished, .paused, .dropped:
                return ShelfState.resolve(
                    personalRecords.first(where: { $0.sourceSeriesID == item.sourceSeriesID })?.localShelfState
                ).rawValue == filter.rawValue
            }
        }
    }

    var body: some View {
        Group {
            if filteredSeries.isEmpty {
                ContentUnavailableView(
                    filter.title,
                    systemImage: filter.systemImage,
                    description: Text("暂时没有符合条件的作品")
                )
            } else {
                List(filteredSeries) { item in
                    Button {
                        selectedSeriesID = item.sourceSeriesID
                        isShowingSeries = true
                    } label: {
                        SeriesCard(
                            series: item,
                            seasons: seasons.filter { $0.sourceSeriesID == item.sourceSeriesID },
                            personal: personalRecords.first { $0.sourceSeriesID == item.sourceSeriesID }
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("filtered-series-\(item.sourceSeriesID)")
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(filter.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $isShowingSeries) {
            if let selectedSeriesID,
               let selectedSeries = series.first(where: { $0.sourceSeriesID == selectedSeriesID }) {
                SeriesDetailView(series: selectedSeries)
            }
        }
    }
}

private struct SeasonChangeLogView: View {
    let series: [SeriesRecord]
    let snapshots: [OfficialSnapshot]

    private var changes: [SeasonCountChange] {
        SeasonChangeHistory.changes(from: snapshots)
    }

    private var titles: [String: String] {
        Dictionary(uniqueKeysWithValues: series.map { ($0.sourceSeriesID, $0.title) })
    }

    var body: some View {
        Group {
            if changes.isEmpty {
                ContentUnavailableView(
                    "暂无变化记录",
                    systemImage: "arrow.triangle.2.circlepath",
                    description: Text("公开资料更新后，季数或集数发生变化时会记录在这里")
                )
            } else {
                List(changes) { change in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(titles[change.sourceSeriesID] ?? "未命名作品")
                            .font(.headline)
                        Text("季数：\(countText(change.previousSeasonCount)) → \(countText(change.currentSeasonCount))")
                            .font(.subheadline)
                        Text("集数：\(countText(change.previousEpisodeCount)) → \(countText(change.currentEpisodeCount))")
                            .font(.subheadline)
                        Text(change.capturedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("季集数变化")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func countText(_ value: Int?) -> String {
        value.map(String.init) ?? "未记录"
    }
}

private struct AddSeriesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let initialURL: URL?
    let autoSaveInitialURL: Bool
    let onSaved: () -> Void

    @State private var sourceURLText: String
    @State private var detectedTitle: String
    @State private var coverURLText = ""
    @State private var tagsText = ""
    @State private var intro = ""
    @State private var officialRatingText = ""
    @State private var officialRatingCount: Int?
    @State private var officialHeatText = ""
    @State private var officialHeatScore: Double?
    @State private var completionStatus = SeriesCompletionStatus.unknown.rawValue
    @State private var shelfState = "unstarted"
    @State private var followsUpdates = false
    @State private var includeFirstSeason = false
    @State private var firstSeasonNumber = 1
    @State private var firstSeasonEpisodeCount = 0
    @State private var isFetching = false
    @State private var notice: String?
    @State private var errorMessage: String?
    @State private var detectedSeasons: [PublicSeasonMetadata] = []
    @State private var coverCandidates: [String] = []
    @State private var lastFetchedURL: String?
    @State private var hasAutoSavedInitialURL = false

    init(
        initialURL: URL?,
        autoSaveInitialURL: Bool = false,
        onSaved: @escaping () -> Void
    ) {
        self.initialURL = initialURL
        self.autoSaveInitialURL = autoSaveInitialURL
        self.onSaved = onSaved
        _sourceURLText = State(initialValue: initialURL?.absoluteString ?? "")
        _detectedTitle = State(initialValue: initialURL.flatMap { TitleNormalizer.fallback(from: $0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("红果分享链接", text: $sourceURLText, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)

                    Button(action: fetchMetadata) {
                        HStack {
                            Label("读取公开资料", systemImage: "arrow.down.circle")
                            Spacer()
                            if isFetching {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isFetching || sourceURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if !detectedTitle.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("自动识别的作品", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(detectedTitle)
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Label("粘贴链接后自动读取名称", systemImage: "sparkles")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if !detectedSeasons.isEmpty {
                        Label("已识别 \(detectedSeasons.count) 季公开资料", systemImage: "square.stack.3d.up.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let notice {
                        Text(notice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("作品")
                } footer: {
                    Text("可以直接粘贴带说明文字的分享内容，应用会自动提取其中的网页链接。")
                }

                if !coverCandidates.isEmpty {
                    Section("候选封面") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(coverCandidates, id: \.self) { candidate in
                                    Button {
                                        coverURLText = candidate
                                    } label: {
                                        CoverView(urlString: candidate, width: 72, height: 104)
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .stroke(
                                                        candidate == coverURLText ? Color.accentColor : .clear,
                                                        lineWidth: 3
                                                    )
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(candidate == coverURLText ? "当前封面" : "选择候选封面")
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        Text(coverURLText.isEmpty
                             ? "没有足够把握自动选封面，请点选人物海报或主角海报。"
                             : "已优先选择官方主图；如果不合适，可以点选其他候选图。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("展示信息") {
                    TextField("封面图片链接（可选）", text: $coverURLText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("标签，例如 修仙,爽剧", text: $tagsText)
                    TextField("简介", text: $intro, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("官方数据（可选）") {
                    TextField("官方评分", text: $officialRatingText)
                        .keyboardType(.decimalPad)
                    TextField("官方热度", text: $officialHeatText)
                }

                Section("我的记录") {
                    Picker("完结状态", selection: $completionStatus) {
                        ForEach(SeriesCompletionStatus.allCases) { status in
                            Text(status.title).tag(status.rawValue)
                        }
                    }

                    Picker("书架状态", selection: $shelfState) {
                        Text("未开始").tag("unstarted")
                        Text("观看中").tag("watching")
                        Text("已看完").tag("finished")
                        Text("暂时搁置").tag("paused")
                        Text("弃剧").tag("dropped")
                    }

                    Toggle("追更 / 预约", isOn: $followsUpdates)

                    Toggle("手动添加季", isOn: $includeFirstSeason)
                        .accessibilityIdentifier("manual-season-toggle")
                    if includeFirstSeason {
                        Stepper("第\(firstSeasonNumber)季", value: $firstSeasonNumber, in: 1...99)
                        Stepper("预计 \(firstSeasonEpisodeCount) 集", value: $firstSeasonEpisodeCount, in: 0...999)
                    }
                }
            }
            .navigationTitle("添加作品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .fontWeight(.semibold)
                }
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onChange(of: sourceURLText) { _, newValue in
                handlePastedText(newValue)
            }
            .task {
                guard let initialURL else { return }
                fetchMetadata(for: initialURL, force: true)
            }
        }
    }

    private func fetchMetadata() {
        guard let url = URLExtractor.firstURL(in: sourceURLText) else {
            errorMessage = "请输入以 http:// 或 https:// 开头的分享链接。"
            return
        }
        fetchMetadata(for: url, force: true)
    }

    private func handlePastedText(_ value: String) {
        guard let url = URLExtractor.firstURL(in: value) else { return }
        let normalizedURL = url.absoluteString
        if value != normalizedURL {
            sourceURLText = normalizedURL
        }
        guard lastFetchedURL != normalizedURL else { return }
        fetchMetadata(for: url)
    }

    private func fetchMetadata(for url: URL, force: Bool = false) {
        let normalizedURL = url.absoluteString
        guard force || lastFetchedURL != normalizedURL || detectedTitle.isEmpty else { return }

        isFetching = true
        notice = nil
        errorMessage = nil
        lastFetchedURL = normalizedURL

        Task {
            do {
                let metadata = try await PublicMetadataService.shared.fetch(from: url)
                await MainActor.run {
                    guard lastFetchedURL == normalizedURL else { return }
                    detectedTitle = metadata.title ?? TitleNormalizer.fallback(from: url) ?? ""
                    coverCandidates = metadata.coverCandidates
                    if coverURLText.isEmpty {
                        coverURLText = metadata.coverURL ?? ""
                    }
                    if intro.isEmpty { intro = metadata.intro ?? "" }
                    if tagsText.isEmpty { tagsText = metadata.tagsText ?? "" }
                    if officialRatingText.isEmpty, let rating = metadata.officialRating {
                        officialRatingText = String(format: "%.1f", rating)
                    }
                    officialRatingCount = metadata.officialRatingCount
                    if officialHeatText.isEmpty { officialHeatText = metadata.officialHeatText ?? "" }
                    officialHeatScore = metadata.officialHeatScore
                    detectedSeasons = metadata.seasons
                    includeFirstSeason = false
                    let coverNotice = metadata.coverURL == nil && !metadata.coverCandidates.isEmpty
                        ? "未自动采用不确定的图片，请在候选封面中选择人物海报。"
                        : nil
                    let metadataNotice = metadata.seasons.isEmpty
                        ? "已读取公开资料，请核对后保存。"
                        : "已读取公开资料和 \(metadata.seasons.count) 季分集信息，请核对后保存。"
                    notice = [metadataNotice, coverNotice]
                        .compactMap { $0 }
                        .joined(separator: " ")
                    isFetching = false
                    autoSaveIfNeeded()
                }
            } catch {
                await MainActor.run {
                    guard lastFetchedURL == normalizedURL else { return }
                    detectedTitle = TitleNormalizer.fallback(from: url) ?? ""
                    detectedSeasons = []
                    includeFirstSeason = false
                    notice = "没有读到完整公开资料，可以保存链接后再补充。"
                    isFetching = false
                    autoSaveIfNeeded()
                }
            }
        }
    }

    private func autoSaveIfNeeded() {
        guard autoSaveInitialURL, !hasAutoSavedInitialURL else { return }
        hasAutoSavedInitialURL = true
        Task { @MainActor in
            save()
        }
    }

    private func save() {
        guard let sourceURL = URLExtractor.firstURL(in: sourceURLText) else {
            errorMessage = "请先粘贴有效的红果分享链接。"
            return
        }

        let identity = SeriesImportIdentity(title: detectedTitle, fallbackURL: sourceURL)
        let cleanTitle = identity.baseTitle.isEmpty ? "待补充作品" : identity.baseTitle
        let cleanURL = sourceURL.absoluteString

        do {
            let existing = try modelContext.fetch(FetchDescriptor<SeriesRecord>())
            let record = existing.first { SeriesImportMatcher.matches($0, identity: identity) }
            let sourceID = record?.sourceSeriesID ?? identity.sourceID
            let target = record ?? SeriesRecord(
                sourceSeriesID: sourceID,
                title: cleanTitle,
                sourceURL: cleanURL.nilIfBlank
            )
            if record == nil {
                modelContext.insert(target)
            }

            target.sourceURL = SeriesLinkPolicy.primary(existing: target.sourceURL, incoming: cleanURL)
            target.title = cleanTitle
            if CoverURLSelector.shouldReplaceExisting(target.coverURL), let coverURL = coverURLText.nilIfBlank {
                target.coverURL = coverURL
            }
            if target.intro.isEmpty {
                target.intro = intro.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if target.tagsText.isEmpty {
                target.tagsText = tagsText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let rating = Double(officialRatingText) { target.officialRating = rating }
            if let officialRatingCount { target.officialRatingCount = officialRatingCount }
            if let officialHeatScore { target.officialHeatScore = officialHeatScore }
            if let heat = officialHeatText.nilIfBlank { target.officialHeatText = heat }
            if record == nil || completionStatus != SeriesCompletionStatus.unknown.rawValue {
                target.completionStatus = completionStatus
            }
            target.updatedAt = .now

            let personalRecords = try modelContext.fetch(FetchDescriptor<PersonalRecord>())
            if let personal = personalRecords.first(where: { $0.sourceSeriesID == sourceID }) {
                if record == nil {
                    personal.localShelfState = shelfState
                    personal.followsUpdates = followsUpdates
                    personal.followedAt = followsUpdates ? .now : nil
                }
                personal.updatedAt = .now
            } else {
                let personal = PersonalRecord(sourceSeriesID: sourceID)
                personal.localShelfState = shelfState
                personal.followsUpdates = followsUpdates
                personal.followedAt = followsUpdates ? .now : nil
                modelContext.insert(personal)
            }

            let existingSeasons = try modelContext.fetch(FetchDescriptor<SeasonRecord>())
            let existingEpisodes = try modelContext.fetch(FetchDescriptor<EpisodeRecord>())
            var importedSeasons = detectedSeasons

            if detectedSeasons.isEmpty, includeFirstSeason {
                let fallbackSeasonNumber = identity.inferredSeasonNumber ?? firstSeasonNumber
                importedSeasons = [PublicSeasonMetadata(
                    seasonNumber: fallbackSeasonNumber,
                    title: "第\(fallbackSeasonNumber)季",
                    episodeCount: firstSeasonEpisodeCount,
                    sourceURL: cleanURL.nilIfBlank,
                    episodes: []
                )]
            }

            for metadataSeason in importedSeasons {
                let season = existingSeasons.first {
                    $0.sourceSeriesID == sourceID
                        && $0.seasonNumber == metadataSeason.seasonNumber
                } ?? SeasonRecord(
                    sourceSeriesID: sourceID,
                    seasonNumber: metadataSeason.seasonNumber
                )
                if !existingSeasons.contains(where: { $0 === season }) {
                    modelContext.insert(season)
                }

                season.title = metadataSeason.title ?? "第\(metadataSeason.seasonNumber)季"
                season.episodeCount = SeasonEpisodeCount.latest(
                    existing: season.episodeCount,
                    reported: metadataSeason.episodeCount,
                    observed: metadataSeason.episodes.count
                )
                season.sourceURL = metadataSeason.sourceURL ?? cleanURL.nilIfBlank ?? season.sourceURL
                season.updatedAt = .now

                for metadataEpisode in metadataSeason.episodes {
                    let episode = existingEpisodes.first {
                        $0.sourceSeriesID == sourceID
                            && $0.seasonNumber == metadataSeason.seasonNumber
                            && $0.episodeNumber == metadataEpisode.episodeNumber
                    } ?? EpisodeRecord(
                        sourceVid: "\(sourceID)#s\(metadataSeason.seasonNumber)#e\(metadataEpisode.episodeNumber)",
                        sourceSeriesID: sourceID,
                        seasonNumber: metadataSeason.seasonNumber,
                        episodeNumber: metadataEpisode.episodeNumber
                    )
                    if !existingEpisodes.contains(where: { $0 === episode }) {
                        modelContext.insert(episode)
                    }
                    if let title = metadataEpisode.title, !title.isEmpty { episode.title = title }
                    if let webURL = metadataEpisode.webURL { episode.webURL = webURL }
                }

            }

            if officialHeatScore != nil || officialHeatText.nilIfBlank != nil || !importedSeasons.isEmpty {
                let snapshot = OfficialSnapshot(sourceSeriesID: sourceID)
                snapshot.officialHeatScore = officialHeatScore
                snapshot.officialHeatText = officialHeatText.nilIfBlank
                if !importedSeasons.isEmpty {
                    snapshot.seasonCount = importedSeasons.count
                    snapshot.episodeCount = importedSeasons.map(\.episodeCount).reduce(0, +)
                }
                modelContext.insert(snapshot)
            }

            try modelContext.save()
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
