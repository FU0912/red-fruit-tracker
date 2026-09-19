import Foundation
import SwiftData
import SwiftUI

struct SeriesDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    let series: SeriesRecord

    @Query(sort: \SeasonRecord.seasonNumber)
    private var allSeasons: [SeasonRecord]

    @Query(sort: \EpisodeRecord.episodeNumber)
    private var allEpisodes: [EpisodeRecord]

    @Query
    private var personalRecords: [PersonalRecord]

    @State private var isShowingEdit = false
    @State private var isShowingAddSeason = false
    @State private var isRefreshing = false
    @State private var selectedSeasonNumber = 0
    @State private var notice: String?

    private var seasons: [SeasonRecord] {
        allSeasons
            .filter { $0.sourceSeriesID == series.sourceSeriesID }
            .sorted { $0.seasonNumber < $1.seasonNumber }
    }

    private var personalRecord: PersonalRecord? {
        personalRecords.first { $0.sourceSeriesID == series.sourceSeriesID }
    }

    private var selectedSeason: SeasonRecord? {
        if selectedSeasonNumber > 0,
           let selected = seasons.first(where: { $0.seasonNumber == selectedSeasonNumber }) {
            return selected
        }
        if let current = personalRecord?.currentSeasonNumber,
           let selected = seasons.first(where: { $0.seasonNumber == current }) {
            return selected
        }
        return seasons.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                metadataSection
                progressSection
                seasonsSection
                personalSection
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(series.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: refreshMetadata) {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Label("更新公开资料", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing || series.sourceURL == nil)

                Button {
                    isShowingEdit = true
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $isShowingEdit) {
            EditSeriesView(series: series)
        }
        .sheet(isPresented: $isShowingAddSeason) {
            AddSeasonView(
                seriesID: series.sourceSeriesID,
                suggestedNumber: (seasons.map(\.seasonNumber).max() ?? 0) + 1
            )
        }
        .alert("提示", isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )) {
            Button("好", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
        .task {
            ensurePersonalRecord()
            if selectedSeasonNumber == 0 {
                selectedSeasonNumber = personalRecord?.currentSeasonNumber ?? seasons.first?.seasonNumber ?? 0
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            CoverView(urlString: series.coverURL)
                .frame(width: 126, height: 176)

            VStack(alignment: .leading, spacing: 10) {
                Text(series.title)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)

                if !series.tagsText.isEmpty {
                    Text(series.tagsText.replacingOccurrences(of: ",", with: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: openCurrentPosition) {
                    Label(currentOpenTitle, systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderedProminent)
                .disabled(series.sourceURL == nil && selectedEpisode == nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var metadataSection: some View {
        if !series.intro.isEmpty || series.officialRating != nil || series.officialHeatText != nil {
            VStack(alignment: .leading, spacing: 14) {
                if series.officialRating != nil || series.officialHeatText != nil {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        if let rating = series.officialRating {
                            MetricLabel(title: "官方评分", value: String(format: "%.1f", rating), symbol: "star.fill")
                        }
                        if let heat = series.officialHeatText {
                            MetricLabel(title: "官方热度", value: heat, symbol: "flame.fill")
                        }
                    }
                }

                if !series.intro.isEmpty {
                    Text(series.intro)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "观看进度", symbol: "bookmark.fill")

            if let personalRecord {
                if let selectedSeason {
                    Picker(
                        "选择季",
                        selection: Binding(
                            get: { selectedSeasonNumber == 0 ? selectedSeason.seasonNumber : selectedSeasonNumber },
                            set: { value in
                                selectedSeasonNumber = value
                                personalRecord.currentSeasonNumber = value
                                personalRecord.currentEpisodeNumber = nil
                                personalRecord.localShelfState = "watching"
                                personalRecord.updatedAt = .now
                                try? modelContext.save()
                            }
                        )
                    ) {
                        ForEach(seasons, id: \.seasonNumber) { season in
                            Text("第\(season.seasonNumber)季").tag(season.seasonNumber)
                        }
                    }
                    .pickerStyle(.menu)

                    EpisodeProgressGrid(series: series, season: selectedSeason)
                } else {
                    Text("还没有季资料。请先更新公开资料，或手动添加一季。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Picker("状态", selection: shelfStateBinding(for: personalRecord)) {
                    Text("未开始").tag("unstarted")
                    Text("观看中").tag("watching")
                    Text("已看完").tag("finished")
                    Text("暂时搁置").tag("paused")
                }
                .pickerStyle(.menu)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var seasonsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(title: "分季", symbol: "square.stack.3d.up.fill")
                Spacer()
                Button {
                    isShowingAddSeason = true
                } label: {
                    Label("添加季", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
            }

            if seasons.isEmpty {
                Text("还没有季记录。可以先添加第 1 季，再补充集数。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(seasons, id: \.sourceSeasonKey) { season in
                        NavigationLink {
                            SeasonDetailView(series: series, season: season)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "book.closed")
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(season.title.isEmpty ? "第\(season.seasonNumber)季" : season.title)
                                        .font(.headline)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(episodeSummary(for: season))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let rating = season.myRating {
                                        Text("我的评分 \(String(format: "%.0f", rating))/5")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        if season.sourceSeasonKey != seasons.last?.sourceSeasonKey {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var personalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "整部作品的评分与点评", symbol: "star.bubble")

            if let personalRecord {
                RatingStars(rating: ratingBinding(for: personalRecord))
                ReviewEditor(text: reviewBinding(for: personalRecord), placeholder: "写下整部漫剧的感受")

                Button("保存总记录") {
                    personalRecord.updatedAt = .now
                    try? modelContext.save()
                    notice = "整部作品的评分和点评已保存。"
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var selectedEpisode: EpisodeRecord? {
        guard let personalRecord,
              let seasonNumber = personalRecord.currentSeasonNumber,
              let episodeNumber = personalRecord.currentEpisodeNumber else {
            return nil
        }
        return allEpisodes.first {
            $0.sourceSeriesID == series.sourceSeriesID
                && $0.seasonNumber == seasonNumber
                && $0.episodeNumber == episodeNumber
        }
    }

    private var currentOpenTitle: String {
        guard let personalRecord,
              let season = personalRecord.currentSeasonNumber,
              let episode = personalRecord.currentEpisodeNumber else {
            return "打开红果作品"
        }
        return "打开第\(season)季第\(episode)集"
    }

    private func ensurePersonalRecord() {
        guard personalRecord == nil else { return }
        let record = PersonalRecord(sourceSeriesID: series.sourceSeriesID)
        modelContext.insert(record)
        try? modelContext.save()
    }

    private func episodeSummary(for season: SeasonRecord) -> String {
        let actual = allEpisodes.filter {
            $0.sourceSeriesID == series.sourceSeriesID
                && $0.seasonNumber == season.seasonNumber
        }
        let watched = actual.filter(\.isWatched).count
        let total = max(season.episodeCount, actual.map(\.episodeNumber).max() ?? actual.count)
        return total == 0 ? "还没有集数资料" : "\(watched)/\(total) 集已看"
    }

    private func shelfStateBinding(for personal: PersonalRecord) -> Binding<String> {
        Binding(
            get: { personal.localShelfState },
            set: { value in
                personal.localShelfState = value
                personal.updatedAt = .now
                try? modelContext.save()
            }
        )
    }

    private func ratingBinding(for personal: PersonalRecord) -> Binding<Double?> {
        Binding(
            get: { personal.myRating },
            set: {
                personal.myRating = $0
                personal.updatedAt = .now
            }
        )
    }

    private func reviewBinding(for personal: PersonalRecord) -> Binding<String> {
        Binding(
            get: { personal.review },
            set: { personal.review = $0 }
        )
    }

    private func openCurrentPosition() {
        let sourceString: String?
        let isPrecise: Bool

        if let episode = selectedEpisode, let webURL = episode.webURL {
            sourceString = webURL
            isPrecise = true
        } else if let currentSeason = personalRecord?.currentSeasonNumber,
                  let season = seasons.first(where: { $0.seasonNumber == currentSeason }) {
            sourceString = season.sourceURL ?? series.sourceURL
            isPrecise = false
        } else {
            sourceString = series.sourceURL
            isPrecise = false
        }

        guard let sourceString, let url = URL(string: sourceString) else {
            notice = "这部作品还没有可跳转的红果链接。"
            return
        }
        openURL(url)
        if !isPrecise, personalRecord?.currentEpisodeNumber != nil {
            notice = "页面没有提供这一集的专属链接，已打开可用的本季或作品链接。"
        }
    }

    private func refreshMetadata() {
        guard let sourceURL = series.sourceURL,
              let url = URL(string: sourceURL) else {
            notice = "这部作品没有网页链接，无法更新公开资料。"
            return
        }

        isRefreshing = true
        Task {
            do {
                let metadata = try await PublicMetadataService.shared.fetch(from: url)
                await MainActor.run {
                    if let title = metadata.title, !title.isEmpty { series.title = title }
                    if let coverURL = metadata.coverURL { series.coverURL = coverURL }
                    if let intro = metadata.intro { series.intro = intro }
                    if let tagsText = metadata.tagsText { series.tagsText = tagsText }
                    if let rating = metadata.officialRating { series.officialRating = rating }
                    if let heat = metadata.officialHeatText { series.officialHeatText = heat }
                    mergePublicSeasons(metadata.seasons)
                    series.updatedAt = .now

                    let snapshot = OfficialSnapshot(sourceSeriesID: series.sourceSeriesID)
                    snapshot.officialRating = metadata.officialRating ?? series.officialRating
                    snapshot.officialHeatText = metadata.officialHeatText ?? series.officialHeatText
                    snapshot.episodeCount = metadata.seasons.map(\.episodeCount).reduce(0, +)
                    modelContext.insert(snapshot)
                    try? modelContext.save()
                    isRefreshing = false
                    notice = metadata.seasons.isEmpty
                        ? "公开资料已更新，并保存了一条数据快照。"
                        : "公开资料、季集信息已更新，并保存了一条数据快照。"
                }
            } catch {
                await MainActor.run {
                    isRefreshing = false
                    notice = "没有读取到可更新的公开资料，请检查链接或稍后重试。"
                }
            }
        }
    }

    private func mergePublicSeasons(_ metadataSeasons: [PublicSeasonMetadata]) {
        guard !metadataSeasons.isEmpty else { return }

        for metadataSeason in metadataSeasons {
            let existing = allSeasons.first {
                $0.sourceSeriesID == series.sourceSeriesID
                    && $0.seasonNumber == metadataSeason.seasonNumber
            }
            let season = existing ?? SeasonRecord(
                sourceSeriesID: series.sourceSeriesID,
                seasonNumber: metadataSeason.seasonNumber
            )
            if existing == nil { modelContext.insert(season) }
            season.title = metadataSeason.title ?? "第\(metadataSeason.seasonNumber)季"
            season.episodeCount = max(season.episodeCount, metadataSeason.episodeCount)
            season.sourceURL = metadataSeason.sourceURL ?? season.sourceURL ?? series.sourceURL
            season.updatedAt = .now

            for metadataEpisode in metadataSeason.episodes {
                let existingEpisode = allEpisodes.first {
                    $0.sourceSeriesID == series.sourceSeriesID
                        && $0.seasonNumber == metadataSeason.seasonNumber
                        && $0.episodeNumber == metadataEpisode.episodeNumber
                }
                let episode = existingEpisode ?? EpisodeRecord(
                    sourceVid: "\(series.sourceSeriesID)#s\(metadataSeason.seasonNumber)#e\(metadataEpisode.episodeNumber)",
                    sourceSeriesID: series.sourceSeriesID,
                    seasonNumber: metadataSeason.seasonNumber,
                    episodeNumber: metadataEpisode.episodeNumber
                )
                if existingEpisode == nil { modelContext.insert(episode) }
                if let title = metadataEpisode.title, !title.isEmpty { episode.title = title }
                if let webURL = metadataEpisode.webURL { episode.webURL = webURL }
            }
        }
    }
}

private struct EpisodeProgressGrid: View {
    @Environment(\.modelContext) private var modelContext

    let series: SeriesRecord
    let season: SeasonRecord

    @Query(sort: \EpisodeRecord.episodeNumber)
    private var allEpisodes: [EpisodeRecord]

    @Query
    private var personalRecords: [PersonalRecord]

    @State private var selectedRangeStart = 1

    private var episodes: [EpisodeRecord] {
        allEpisodes.filter {
            $0.sourceSeriesID == series.sourceSeriesID
                && $0.seasonNumber == season.seasonNumber
        }
    }

    private var totalEpisodeCount: Int {
        max(season.episodeCount, episodes.map(\.episodeNumber).max() ?? episodes.count)
    }

    private var ranges: [EpisodeRange] {
        guard totalEpisodeCount > 0 else { return [] }
        return stride(from: 1, through: totalEpisodeCount, by: 100).map { start in
            EpisodeRange(start: start, end: min(start + 99, totalEpisodeCount))
        }
    }

    private var selectedRange: EpisodeRange? {
        ranges.first(where: { $0.start == selectedRangeStart }) ?? ranges.first
    }

    private var visibleNumbers: [Int] {
        guard let selectedRange else { return [] }
        return Array(selectedRange.start...selectedRange.end)
    }

    private var watchedCount: Int {
        episodes.filter(\.isWatched).count
    }

    private var personalRecord: PersonalRecord? {
        personalRecords.first { $0.sourceSeriesID == series.sourceSeriesID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("第\(season.seasonNumber)季 · \(watchedCount)/\(totalEpisodeCount) 集已看")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let selectedRange {
                    Text("当前 \(selectedRange.start)-\(selectedRange.end)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if ranges.count > 1 {
                Picker("集数区间", selection: $selectedRangeStart) {
                    ForEach(ranges) { range in
                        Text("第\(range.start)-\(range.end)集").tag(range.start)
                    }
                }
                .pickerStyle(.menu)
            }

            if visibleNumbers.isEmpty {
                Text("还没有可展示的集数。请先更新公开资料，或手动填写本季集数。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5),
                    spacing: 8
                ) {
                    ForEach(visibleNumbers, id: \.self) { number in
                        let episode = episodes.first(where: { $0.episodeNumber == number })
                        let isCurrent = personalRecord?.currentSeasonNumber == season.seasonNumber
                            && personalRecord?.currentEpisodeNumber == number

                        Button {
                            toggleEpisode(number, existing: episode)
                        } label: {
                            VStack(spacing: 4) {
                                Text("\(number)")
                                    .font(.subheadline.weight(.semibold))
                                Image(systemName: episode?.isWatched == true ? "checkmark" : "circle")
                                    .font(.caption2.weight(.bold))
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(episode?.isWatched == true ? Color.white : Color.primary)
                            .background(episode?.isWatched == true ? Color.accentColor : Color(uiColor: .tertiarySystemGroupedBackground))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(isCurrent ? Color.accentColor : .clear, lineWidth: 2)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("第\(number)集\(episode?.isWatched == true ? "，已看" : "，未看")")
                    }
                }
            }

            Text("点击集数即可标记已看，并将它设为当前观看位置。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: season.seasonNumber) { _, _ in
            selectedRangeStart = 1
        }
        .task {
            if let currentEpisode = personalRecord?.currentEpisodeNumber {
                selectedRangeStart = ((currentEpisode - 1) / 100) * 100 + 1
            }
        }
    }

    private func toggleEpisode(_ number: Int, existing: EpisodeRecord?) {
        let episode: EpisodeRecord
        if let existing {
            episode = existing
        } else {
            episode = EpisodeRecord(
                sourceVid: "\(series.sourceSeriesID)#s\(season.seasonNumber)#e\(number)",
                sourceSeriesID: series.sourceSeriesID,
                seasonNumber: season.seasonNumber,
                episodeNumber: number
            )
            modelContext.insert(episode)
            season.episodeCount = max(season.episodeCount, number)
        }

        episode.isWatched.toggle()
        episode.watchedAt = episode.isWatched ? .now : nil
        if episode.isWatched {
            let personal = personalRecord ?? makePersonalRecord()
            personal.currentSeasonNumber = season.seasonNumber
            personal.currentEpisodeNumber = number
            personal.localShelfState = watchedCount + 1 >= totalEpisodeCount ? "finished" : "watching"
            personal.updatedAt = .now
        }
        season.updatedAt = .now
        try? modelContext.save()
    }

    private func makePersonalRecord() -> PersonalRecord {
        let record = PersonalRecord(sourceSeriesID: series.sourceSeriesID)
        modelContext.insert(record)
        return record
    }
}

private struct EpisodeRange: Identifiable, Hashable {
    let start: Int
    let end: Int

    var id: Int { start }
}

private struct EditSeriesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let series: SeriesRecord

    @State private var title: String
    @State private var sourceURL: String
    @State private var coverURL: String
    @State private var tagsText: String
    @State private var intro: String

    init(series: SeriesRecord) {
        self.series = series
        _title = State(initialValue: series.title)
        _sourceURL = State(initialValue: series.sourceURL ?? "")
        _coverURL = State(initialValue: series.coverURL ?? "")
        _tagsText = State(initialValue: series.tagsText)
        _intro = State(initialValue: series.intro)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("作品资料") {
                    TextField("作品名称", text: $title)
                    TextField("红果链接", text: $sourceURL, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("封面图片链接", text: $coverURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("标签", text: $tagsText, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("简介", text: $intro, axis: .vertical)
                        .lineLimit(4...10)
                }
            }
            .navigationTitle("编辑作品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        series.title = TitleNormalizer.normalize(title) ?? title.trimmingCharacters(in: .whitespacesAndNewlines)
                        series.sourceURL = URLExtractor.firstURL(in: sourceURL)?.absoluteString ?? sourceURL.nilIfBlank
                        series.coverURL = coverURL.nilIfBlank
                        series.tagsText = tagsText.trimmingCharacters(in: .whitespacesAndNewlines)
                        series.intro = intro.trimmingCharacters(in: .whitespacesAndNewlines)
                        series.updatedAt = .now
                        try? modelContext.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct AddSeasonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let seriesID: String
    let suggestedNumber: Int

    @State private var seasonNumber: Int
    @State private var title = ""
    @State private var episodeCount = 0
    @State private var sourceURL = ""
    @State private var errorMessage: String?

    init(seriesID: String, suggestedNumber: Int) {
        self.seriesID = seriesID
        self.suggestedNumber = suggestedNumber
        _seasonNumber = State(initialValue: suggestedNumber)
    }

    var body: some View {
        NavigationStack {
            Form {
                Stepper("第\(seasonNumber)季", value: $seasonNumber, in: 1...99)
                TextField("季标题（可选）", text: $title, axis: .vertical)
                    .lineLimit(1...3)
                Stepper("预计 \(episodeCount) 集", value: $episodeCount, in: 0...9999)
                TextField("本季观看链接（可选）", text: $sourceURL, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }
            .navigationTitle("添加一季")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
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

    private func save() {
        let key = "\(seriesID)#\(seasonNumber)"
        do {
            let existing = try modelContext.fetch(FetchDescriptor<SeasonRecord>())
            guard !existing.contains(where: { $0.sourceSeasonKey == key }) else {
                errorMessage = "这个季已经存在。"
                return
            }

            modelContext.insert(SeasonRecord(
                sourceSeriesID: seriesID,
                seasonNumber: seasonNumber,
                title: title.nilIfBlank ?? "第\(seasonNumber)季",
                episodeCount: episodeCount,
                sourceURL: URLExtractor.firstURL(in: sourceURL)?.absoluteString
            ))
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SeasonDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    let series: SeriesRecord
    let season: SeasonRecord

    @Query(sort: \EpisodeRecord.episodeNumber)
    private var allEpisodes: [EpisodeRecord]

    @State private var isShowingAddEpisode = false
    @State private var isShowingEdit = false
    @State private var notice: String?

    private var episodes: [EpisodeRecord] {
        allEpisodes.filter {
            $0.sourceSeriesID == series.sourceSeriesID
                && $0.seasonNumber == season.seasonNumber
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(season.title.isEmpty ? "第\(season.seasonNumber)季" : season.title)
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(episodes.filter(\.isWatched).count)/\(max(season.episodeCount, episodes.map(\.episodeNumber).max() ?? episodes.count)) 集已看")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let sourceURL = season.sourceURL ?? series.sourceURL,
                       let url = URL(string: sourceURL) {
                        Button {
                            openURL(url)
                        } label: {
                            Label("打开本季链接", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "逐集进度", symbol: "calendar")
                    EpisodeProgressGrid(series: series, season: season)
                    Button {
                        isShowingAddEpisode = true
                    } label: {
                        Label("补录一集链接", systemImage: "link.badge.plus")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                seasonRatingSection

                if !episodes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(title: "已录入的集资料", symbol: "list.number")
                        ForEach(episodes, id: \.sourceVid) { episode in
                            HStack(spacing: 12) {
                                Image(systemName: episode.isWatched ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(episode.isWatched ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("第\(episode.episodeNumber)集")
                                        .font(.subheadline.weight(.semibold))
                                    if !episode.title.isEmpty {
                                        Text(episode.title)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Spacer()
                                if let webURL = episode.webURL, let url = URL(string: webURL) {
                                    Button {
                                        openURL(url)
                                    } label: {
                                        Image(systemName: "play.circle")
                                            .font(.title3)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("打开第\(episode.episodeNumber)集")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("第\(season.seasonNumber)季")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingEdit = true
                } label: {
                    Label("编辑本季", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $isShowingEdit) {
            EditSeasonView(season: season)
        }
        .sheet(isPresented: $isShowingAddEpisode) {
            AddEpisodeView(
                seriesID: series.sourceSeriesID,
                seasonNumber: season.seasonNumber,
                suggestedNumber: (episodes.map(\.episodeNumber).max() ?? season.episodeCount) + 1
            )
        }
        .alert("提示", isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )) {
            Button("好", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    private var seasonRatingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "本季评分与点评", symbol: "star.bubble")
            RatingStars(rating: Binding(
                get: { season.myRating },
                set: {
                    season.myRating = $0
                    season.updatedAt = .now
                }
            ))
            ReviewEditor(
                text: Binding(
                    get: { season.review },
                    set: { season.review = $0 }
                ),
                placeholder: "写下这一季的感受"
            )
            Button("保存本季记录") {
                season.updatedAt = .now
                try? modelContext.save()
                notice = "本季评分和点评已保存。"
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct AddEpisodeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let seriesID: String
    let seasonNumber: Int
    let suggestedNumber: Int

    @State private var episodeNumber: Int
    @State private var title = ""
    @State private var webURL = ""
    @State private var errorMessage: String?

    init(seriesID: String, seasonNumber: Int, suggestedNumber: Int) {
        self.seriesID = seriesID
        self.seasonNumber = seasonNumber
        self.suggestedNumber = suggestedNumber
        _episodeNumber = State(initialValue: max(1, suggestedNumber))
    }

    var body: some View {
        NavigationStack {
            Form {
                Stepper("第\(episodeNumber)集", value: $episodeNumber, in: 1...99999)
                TextField("集标题（可选）", text: $title, axis: .vertical)
                    .lineLimit(1...3)
                TextField("本集链接（可选）", text: $webURL, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }
            .navigationTitle("补录一集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
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

    private func save() {
        do {
            let existing = try modelContext.fetch(FetchDescriptor<EpisodeRecord>())
            guard !existing.contains(where: {
                $0.sourceSeriesID == seriesID
                    && $0.seasonNumber == seasonNumber
                    && $0.episodeNumber == episodeNumber
            }) else {
                errorMessage = "这一集已经存在。"
                return
            }

            modelContext.insert(EpisodeRecord(
                sourceVid: UUID().uuidString,
                sourceSeriesID: seriesID,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                webURL: URLExtractor.firstURL(in: webURL)?.absoluteString
            ))
            if let season = try modelContext.fetch(FetchDescriptor<SeasonRecord>()).first(where: {
                $0.sourceSeriesID == seriesID && $0.seasonNumber == seasonNumber
            }) {
                season.episodeCount = max(season.episodeCount, episodeNumber)
                season.updatedAt = .now
            }
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct EditSeasonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let season: SeasonRecord

    @State private var title: String
    @State private var episodeCount: Int
    @State private var sourceURL: String

    init(season: SeasonRecord) {
        self.season = season
        _title = State(initialValue: season.title)
        _episodeCount = State(initialValue: season.episodeCount)
        _sourceURL = State(initialValue: season.sourceURL ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("季标题", text: $title, axis: .vertical)
                    .lineLimit(1...3)
                Stepper("预计 \(episodeCount) 集", value: $episodeCount, in: 0...9999)
                TextField("本季观看链接", text: $sourceURL, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }
            .navigationTitle("编辑第\(season.seasonNumber)季")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        season.title = title.nilIfBlank ?? "第\(season.seasonNumber)季"
                        season.episodeCount = episodeCount
                        season.sourceURL = URLExtractor.firstURL(in: sourceURL)?.absoluteString ?? sourceURL.nilIfBlank
                        season.updatedAt = .now
                        try? modelContext.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct MetricLabel: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SectionTitle: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.headline)
    }
}

private struct ReviewEditor: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
            }
            TextEditor(text: $text)
                .frame(minHeight: 100)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
    }
}

private struct RatingStars: View {
    @Binding var rating: Double?

    var body: some View {
        HStack(spacing: 12) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    rating = Double(value)
                } label: {
                    Image(systemName: (rating ?? 0) >= Double(value) ? "star.fill" : "star")
                        .font(.title2)
                        .foregroundStyle((rating ?? 0) >= Double(value) ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
            }
            if rating != nil {
                Button("清除") {
                    rating = nil
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
