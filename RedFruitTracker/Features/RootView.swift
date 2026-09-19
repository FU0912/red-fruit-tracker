import Foundation
import Charts
import SwiftData
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab = 0
    @State private var isShowingAdd = false
    @State private var pendingShareURL: URL?

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
        .sheet(isPresented: $isShowingAdd) {
            AddSeriesView(initialURL: pendingShareURL) {
                if let pendingShareURL {
                    ShareInbox.remove(pendingShareURL)
                }
                refreshPendingShare()
            }
        }
        .task {
            refreshPendingShare()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshPendingShare()
            }
        }
    }

    private func refreshPendingShare() {
        pendingShareURL = ShareInbox.firstURL()
    }
}

private struct LibraryView: View {
    @Query(sort: \SeriesRecord.updatedAt, order: .reverse)
    private var series: [SeriesRecord]

    @Query(sort: \PersonalRecord.updatedAt, order: .reverse)
    private var personalRecords: [PersonalRecord]

    let pendingShareURL: URL?
    let onAdd: () -> Void

    @State private var searchText = ""

    private var visibleSeries: [SeriesRecord] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return series }

        return series.filter { item in
            item.title.localizedCaseInsensitiveContains(keyword)
                || item.tagsText.localizedCaseInsensitiveContains(keyword)
                || item.intro.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleSeries.isEmpty {
                    LibraryEmptyState(isSearching: !searchText.isEmpty, onAdd: onAdd)
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 148), spacing: 16)],
                            spacing: 20
                        ) {
                            ForEach(visibleSeries) { item in
                                NavigationLink {
                                    SeriesDetailView(series: item)
                                } label: {
                                    SeriesCard(
                                        series: item,
                                        personal: personalRecords.first { $0.sourceSeriesID == item.sourceSeriesID }
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                    }
                    .background(Color(uiColor: .systemGroupedBackground))
                }
            }
            .navigationTitle("漫剧记录")
            .searchable(text: $searchText, prompt: "搜索作品、标签或简介")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onAdd) {
                        Label("添加作品", systemImage: "plus")
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let pendingShareURL {
                    ShareImportBanner(url: pendingShareURL, onTap: onAdd)
                }
            }
        }
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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.thinMaterial)
        }
        .buttonStyle(.plain)
    }
}

private struct SeriesCard: View {
    let series: SeriesRecord
    let personal: PersonalRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverView(urlString: series.coverURL)
                .aspectRatio(0.72, contentMode: .fit)

            Text(series.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 5) {
                Image(systemName: "bookmark")
                Text(progressText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressText: String {
        guard let personal,
              let season = personal.currentSeasonNumber,
              let episode = personal.currentEpisodeNumber else {
            return "未开始"
        }
        return "看到第\(season)季 · 第\(episode)集"
    }
}

struct CoverView: View {
    let urlString: String?

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        fallback
                    case .empty:
                        ZStack {
                            fallback
                            ProgressView()
                        }
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay {
                Image(systemName: "book.closed")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
    }
}

private struct StatsView: View {
    @Query private var series: [SeriesRecord]
    @Query private var personalRecords: [PersonalRecord]
    @Query private var seasons: [SeasonRecord]
    @Query private var episodes: [EpisodeRecord]
    @Query private var snapshots: [OfficialSnapshot]

    private var watchedEpisodes: Int {
        episodes.filter(\.isWatched).count
    }

    private var ratedRecords: [PersonalRecord] {
        personalRecords.filter { $0.myRating != nil }
    }

    private var averageRating: Double? {
        guard !ratedRecords.isEmpty else { return nil }
        return ratedRecords.compactMap(\.myRating).reduce(0, +) / Double(ratedRecords.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("总览")
                        .font(.title2.weight(.bold))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatTile(title: "作品", value: "\(series.count)", symbol: "books.vertical")
                        StatTile(title: "季", value: "\(seasons.count)", symbol: "square.stack.3d.up")
                        StatTile(title: "已看集数", value: "\(watchedEpisodes)", symbol: "checkmark.circle")
                        StatTile(title: "我的平均分", value: averageRating.map { String(format: "%.1f", $0) } ?? "—", symbol: "star")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("数据快照", systemImage: "chart.xyaxis.line")
                            .font(.headline)
                        Text("已保存 \(snapshots.count) 条官方数据快照。后续刷新后可在这里形成热度、评分和观看数据趋势图。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if !snapshots.isEmpty {
                        SnapshotTrendChart(snapshots: snapshots)
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("统计")
        }
    }
}

private struct SnapshotTrendChart: View {
    let snapshots: [OfficialSnapshot]

    private var ratingPoints: [(date: Date, value: Double)] {
        snapshots.compactMap { snapshot in
            guard let value = snapshot.officialRating else { return nil }
            return (snapshot.capturedAt, value)
        }
        .sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("官方评分趋势", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)

            if ratingPoints.count >= 2 {
                Chart {
                    ForEach(Array(ratingPoints.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("时间", point.date),
                            y: .value("评分", point.value)
                        )
                        .foregroundStyle(.tint)
                        PointMark(
                            x: .value("时间", point.date),
                            y: .value("评分", point.value)
                        )
                        .foregroundStyle(.tint)
                    }
                }
                .chartYScale(domain: 0...10)
                .chartYAxis {
                    AxisMarks(values: [0, 2, 4, 6, 8, 10])
                }
                .frame(height: 190)
            } else {
                Text("至少刷新或录入两次官方评分后显示趋势。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

private struct AddSeriesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let initialURL: URL?
    let onSaved: () -> Void

    @State private var title: String
    @State private var sourceURLText: String
    @State private var coverURLText = ""
    @State private var tagsText = ""
    @State private var intro = ""
    @State private var officialRatingText = ""
    @State private var officialHeatText = ""
    @State private var shelfState = "unstarted"
    @State private var includeFirstSeason = true
    @State private var firstSeasonNumber = 1
    @State private var firstSeasonEpisodeCount = 0
    @State private var isFetching = false
    @State private var notice: String?
    @State private var errorMessage: String?

    init(initialURL: URL?, onSaved: @escaping () -> Void) {
        self.initialURL = initialURL
        self.onSaved = onSaved
        _title = State(initialValue: "")
        _sourceURLText = State(initialValue: initialURL?.absoluteString ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("作品名称", text: $title)
                        .textInputAutocapitalization(.never)
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

                    if let notice {
                        Text(notice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("作品")
                } footer: {
                    Text("分享链接能公开读取到什么，就填入什么；读取失败时仍可手动保存。")
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
                    Picker("书架状态", selection: $shelfState) {
                        Text("未开始").tag("unstarted")
                        Text("观看中").tag("watching")
                        Text("已看完").tag("finished")
                        Text("暂时搁置").tag("paused")
                    }

                    Toggle("先建立一个季", isOn: $includeFirstSeason)
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
        }
    }

    private func fetchMetadata() {
        guard let url = URL(string: sourceURLText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            errorMessage = "请输入以 http:// 或 https:// 开头的分享链接。"
            return
        }

        isFetching = true
        notice = nil

        Task {
            do {
                let metadata = try await PublicMetadataService.shared.fetch(from: url)
                await MainActor.run {
                    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        title = metadata.title ?? ""
                    }
                    if coverURLText.isEmpty { coverURLText = metadata.coverURL ?? "" }
                    if intro.isEmpty { intro = metadata.intro ?? "" }
                    if tagsText.isEmpty { tagsText = metadata.tagsText ?? "" }
                    if officialRatingText.isEmpty, let rating = metadata.officialRating {
                        officialRatingText = String(format: "%.1f", rating)
                    }
                    if officialHeatText.isEmpty { officialHeatText = metadata.officialHeatText ?? "" }
                    notice = "已读取公开资料，请核对后保存。"
                    isFetching = false
                }
            } catch {
                await MainActor.run {
                    notice = "没有读到完整公开资料，可以继续手动填写。"
                    isFetching = false
                }
            }
        }
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            errorMessage = "作品名称不能为空。"
            return
        }

        let cleanURL = sourceURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceID = cleanURL.isEmpty ? "local-\(UUID().uuidString)" : cleanURL

        do {
            let existing = try modelContext.fetch(FetchDescriptor<SeriesRecord>())
            guard !existing.contains(where: { $0.sourceSeriesID == sourceID }) else {
                errorMessage = "这个链接已经在书架里了。"
                return
            }

            let record = SeriesRecord(
                sourceSeriesID: sourceID,
                title: cleanTitle,
                sourceURL: cleanURL.nilIfBlank,
                coverURL: coverURLText.nilIfBlank,
                intro: intro.trimmingCharacters(in: .whitespacesAndNewlines),
                tagsText: tagsText.trimmingCharacters(in: .whitespacesAndNewlines),
                officialRating: Double(officialRatingText),
                officialHeatText: officialHeatText.nilIfBlank
            )
            modelContext.insert(record)

            let personal = PersonalRecord(sourceSeriesID: sourceID)
            personal.localShelfState = shelfState
            modelContext.insert(personal)

            if includeFirstSeason {
                modelContext.insert(SeasonRecord(
                    sourceSeriesID: sourceID,
                    seasonNumber: firstSeasonNumber,
                    title: "第\(firstSeasonNumber)季",
                    episodeCount: firstSeasonEpisodeCount,
                    sourceURL: cleanURL.nilIfBlank
                ))
            }

            if Double(officialRatingText) != nil || officialHeatText.nilIfBlank != nil {
                let snapshot = OfficialSnapshot(sourceSeriesID: sourceID)
                snapshot.officialRating = Double(officialRatingText)
                snapshot.officialHeatText = officialHeatText.nilIfBlank
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
