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
    @State private var notice: String?

    private var seasons: [SeasonRecord] {
        allSeasons
            .filter { $0.sourceSeriesID == series.sourceSeriesID }
            .sorted { $0.seasonNumber < $1.seasonNumber }
    }

    private var personalRecord: PersonalRecord? {
        personalRecords.first { $0.sourceSeriesID == series.sourceSeriesID }
    }

    private var watchedEpisodeCount: Int {
        allEpisodes.filter { $0.sourceSeriesID == series.sourceSeriesID && $0.isWatched }.count
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
                }

                Button(action: openSeries) {
                    Label("打开红果观看", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderedProminent)
                .disabled(series.sourceURL == nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var metadataSection: some View {
        if !series.intro.isEmpty || series.officialRating != nil || series.officialHeatText != nil {
            VStack(alignment: .leading, spacing: 12) {
                if series.officialRating != nil || series.officialHeatText != nil {
                    HStack(spacing: 22) {
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
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "观看进度", symbol: "bookmark.fill")

            if let personalRecord {
                if let firstSeason = seasons.first {
                    Picker(
                        "看到第几季",
                        selection: seasonBinding(for: personalRecord, defaultValue: firstSeason.seasonNumber)
                    ) {
                        ForEach(seasons, id: \.seasonNumber) { season in
                            Text("第\(season.seasonNumber)季").tag(season.seasonNumber)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    Text("先添加一个季，再记录观看进度。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Stepper(
                    "看到第 \(personalRecord.currentEpisodeNumber ?? 0) 集",
                    value: episodeBinding(for: personalRecord),
                    in: 0...999
                )

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
                Text("还没有季记录。可以先添加第 1 季，再逐集登记。")
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
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(season.title.isEmpty ? "第\(season.seasonNumber)季" : season.title)
                                        .font(.headline)
                                    Text(episodeSummary(for: season))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
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
            SectionTitle(title: "我的评分与点评", symbol: "star.bubble")

            if let personalRecord {
                RatingStars(rating: ratingBinding(for: personalRecord))

                ZStack(alignment: .topLeading) {
                    if personalRecord.review.isEmpty {
                        Text("写下这部漫剧的感受")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                    TextEditor(text: reviewBinding(for: personalRecord))
                        .frame(minHeight: 100)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                }

                Button("保存我的记录") {
                    personalRecord.updatedAt = .now
                    try? modelContext.save()
                    notice = "已保存。"
                }
                .buttonStyle(.bordered)
            }
        }
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
        let total = max(season.episodeCount, actual.count)
        return total == 0 ? "还没有集记录" : "\(watched)/\(total) 集已看"
    }

    private func seasonBinding(for personal: PersonalRecord, defaultValue: Int) -> Binding<Int> {
        Binding(
            get: { personal.currentSeasonNumber ?? defaultValue },
            set: { value in
                personal.currentSeasonNumber = value
                personal.currentEpisodeNumber = min(personal.currentEpisodeNumber ?? 0, 999)
                personal.localShelfState = "watching"
                personal.updatedAt = .now
                try? modelContext.save()
            }
        )
    }

    private func episodeBinding(for personal: PersonalRecord) -> Binding<Int> {
        Binding(
            get: { personal.currentEpisodeNumber ?? 0 },
            set: { value in
                personal.currentEpisodeNumber = value
                personal.localShelfState = value == 0 ? "unstarted" : "watching"
                personal.updatedAt = .now
                try? modelContext.save()
            }
        )
    }

    private func shelfStateBinding(for personal: PersonalRecord) -> Binding<String> {
        Binding(
            get: { personal.localShelfState },
            set: {
                personal.localShelfState = $0
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

    private func openSeries() {
        guard let sourceURL = series.sourceURL, let url = URL(string: sourceURL) else {
            notice = "这部作品还没有可跳转的红果链接。"
            return
        }
        openURL(url)
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
                    series.updatedAt = .now

                    let snapshot = OfficialSnapshot(sourceSeriesID: series.sourceSeriesID)
                    snapshot.officialRating = metadata.officialRating ?? series.officialRating
                    snapshot.officialHeatText = metadata.officialHeatText ?? series.officialHeatText
                    modelContext.insert(snapshot)
                    try? modelContext.save()
                    isRefreshing = false
                    notice = "公开资料已更新，并保存了一条数据快照。"
                }
            } catch {
                await MainActor.run {
                    isRefreshing = false
                    notice = "没有读取到可更新的公开资料，请检查链接或稍后重试。"
                }
            }
        }
    }
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
                TextField("作品名称", text: $title)
                TextField("红果链接", text: $sourceURL, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                TextField("封面图片链接", text: $coverURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                TextField("标签", text: $tagsText)
                TextField("简介", text: $intro, axis: .vertical)
                    .lineLimit(4...8)
            }
            .navigationTitle("编辑作品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        series.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        series.sourceURL = sourceURL.nilIfBlank
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
                TextField("季标题（可选）", text: $title)
                Stepper("预计 \(episodeCount) 集", value: $episodeCount, in: 0...999)
                TextField("本季观看链接（可选）", text: $sourceURL)
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
                sourceURL: sourceURL.nilIfBlank
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
    @State private var notice: String?

    private var episodes: [EpisodeRecord] {
        allEpisodes.filter {
            $0.sourceSeriesID == series.sourceSeriesID
                && $0.seasonNumber == season.seasonNumber
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(season.title.isEmpty ? "第\(season.seasonNumber)季" : season.title)
                        .font(.title2.weight(.bold))
                    Text("\(episodes.filter(\.isWatched).count)/\(max(season.episodeCount, episodes.count)) 集已看")
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
                .padding(.vertical, 8)
            }

            Section("剧集") {
                if episodes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("还没有逐集记录")
                            .foregroundStyle(.secondary)
                        Button {
                            isShowingAddEpisode = true
                        } label: {
                            Label("添加第一集", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(episodes, id: \.sourceVid) { episode in
                        EpisodeRow(
                            episode: episode,
                            onToggleWatched: { toggleWatched(episode) },
                            onOpen: { openEpisode(episode) },
                            canOpen: episode.webURL != nil || season.sourceURL != nil || series.sourceURL != nil
                        )
                    }
                    .onDelete(perform: deleteEpisodes)
                }
            }
        }
        .navigationTitle("第\(season.seasonNumber)季")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingAddEpisode = true
                } label: {
                    Label("添加剧集", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingAddEpisode) {
            AddEpisodeView(seriesID: series.sourceSeriesID, seasonNumber: season.seasonNumber)
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

    private func toggleWatched(_ episode: EpisodeRecord) {
        episode.isWatched.toggle()
        episode.watchedAt = episode.isWatched ? .now : nil
        if episode.isWatched {
            updateProgress(for: episode)
        }
        season.updatedAt = .now
        try? modelContext.save()
    }

    private func updateProgress(for episode: EpisodeRecord) {
        do {
            let records = try modelContext.fetch(FetchDescriptor<PersonalRecord>())
            let personal: PersonalRecord
            if let existing = records.first(where: { $0.sourceSeriesID == series.sourceSeriesID }) {
                personal = existing
            } else {
                personal = PersonalRecord(sourceSeriesID: series.sourceSeriesID)
                modelContext.insert(personal)
            }
            personal.currentSeasonNumber = season.seasonNumber
            personal.currentEpisodeNumber = episode.episodeNumber
            personal.localShelfState = "watching"
            personal.updatedAt = .now
        } catch {
            notice = "已更新剧集，但观看进度保存失败。"
        }
    }

    private func openEpisode(_ episode: EpisodeRecord) {
        guard let sourceURL = episode.webURL ?? season.sourceURL ?? series.sourceURL,
              let url = URL(string: sourceURL) else {
            notice = "这一集还没有可跳转的链接。"
            return
        }
        openURL(url)
    }

    private func deleteEpisodes(at offsets: IndexSet) {
        offsets.map { episodes[$0] }.forEach(modelContext.delete)
        try? modelContext.save()
    }
}

private struct EpisodeRow: View {
    let episode: EpisodeRecord
    let onToggleWatched: () -> Void
    let onOpen: () -> Void
    let canOpen: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleWatched) {
                Image(systemName: episode.isWatched ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(episode.isWatched ? .tint : .tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(episode.isWatched ? "标记为未看" : "标记为已看")

            VStack(alignment: .leading, spacing: 3) {
                Text("第\(episode.episodeNumber)集")
                    .font(.headline)
                if !episode.title.isEmpty {
                    Text(episode.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button(action: onOpen) {
                Image(systemName: "play.circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .disabled(!canOpen)
            .accessibilityLabel("打开这一集")
        }
        .padding(.vertical, 5)
    }
}

private struct AddEpisodeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let seriesID: String
    let seasonNumber: Int

    @State private var episodeNumber = 1
    @State private var title = ""
    @State private var webURL = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Stepper("第\(episodeNumber)集", value: $episodeNumber, in: 1...9999)
                TextField("集标题（可选）", text: $title)
                TextField("本集链接（可选）", text: $webURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }
            .navigationTitle("添加剧集")
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
            let duplicate = existing.contains {
                $0.sourceSeriesID == seriesID
                    && $0.seasonNumber == seasonNumber
                    && $0.episodeNumber == episodeNumber
            }
            guard !duplicate else {
                errorMessage = "这一集已经存在。"
                return
            }

            modelContext.insert(EpisodeRecord(
                sourceVid: UUID().uuidString,
                sourceSeriesID: seriesID,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                webURL: webURL.nilIfBlank
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
        }
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
