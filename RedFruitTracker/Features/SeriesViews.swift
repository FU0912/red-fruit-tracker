import Foundation
import Charts
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

    @Query
    private var snapshots: [OfficialSnapshot]

    @State private var isShowingEdit = false
    @State private var isShowingAddSeason = false
    @State private var isRefreshing = false
    @State private var isIntroExpanded = false
    @State private var notice: String?

    init(series: SeriesRecord) {
        self.series = series

        let sourceSeriesID = series.sourceSeriesID
        _allSeasons = Query(
            filter: #Predicate<SeasonRecord> { season in
                season.sourceSeriesID == sourceSeriesID
            },
            sort: \SeasonRecord.seasonNumber
        )
        _allEpisodes = Query(
            filter: #Predicate<EpisodeRecord> { episode in
                episode.sourceSeriesID == sourceSeriesID
            },
            sort: \EpisodeRecord.episodeNumber
        )
        _personalRecords = Query(
            filter: #Predicate<PersonalRecord> { personal in
                personal.sourceSeriesID == sourceSeriesID
            }
        )
        _snapshots = Query(
            filter: #Predicate<OfficialSnapshot> { snapshot in
                snapshot.sourceSeriesID == sourceSeriesID
            },
            sort: \OfficialSnapshot.capturedAt
        )
    }

    private var seasons: [SeasonRecord] {
        allSeasons
            .sorted { $0.seasonNumber < $1.seasonNumber }
    }

    private var personalRecord: PersonalRecord? {
        personalRecords.first { $0.sourceSeriesID == series.sourceSeriesID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                detailHeader
                introSection
                OfficialTrendSection(snapshots: snapshots)
                personalSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .scrollIndicators(.hidden)
        .background(DetailTheme.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(DetailTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("更新公开资料", systemImage: "arrow.clockwise") {
                        refreshMetadata(showNotice: true)
                    }
                    .disabled(isRefreshing || redFruitURL == nil)
                    Button("编辑作品", systemImage: "pencil") {
                        isShowingEdit = true
                    }
                    Button("添加 / 查找其他季", systemImage: "plus") {
                        isShowingAddSeason = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("更多操作")
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
            if shouldAutoRefreshMetadata {
                refreshMetadata(showNotice: false)
            }
        }
    }

    private var shouldAutoRefreshMetadata: Bool {
        guard redFruitURL != nil,
              !ProcessInfo.processInfo.arguments.contains("--ui-testing"),
              MetadataRefreshSchedule.shouldRun() else {
            return false
        }
        return true
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                    CoverView(urlString: series.coverURL, title: series.title, width: 132, height: 184)
                    .fixedSize()
                    .accessibilityIdentifier("series-detail-cover")

                VStack(alignment: .leading, spacing: 12) {
                    Text(series.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("series-detail-title")

                    officialMetadataSection
                }
                .frame(maxWidth: .infinity, minHeight: 184, alignment: .topLeading)
                .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, minHeight: 184, alignment: .topLeading)

            if let url = redFruitURL {
                Button {
                    openURL(url)
                } label: {
                    Label("打开红果漫剧", systemImage: "play.rectangle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(DetailTheme.accent)
                .accessibilityIdentifier("open-red-fruit-button")
            }

            if isRefreshing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在后台更新公开资料")
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
                .accessibilityIdentifier("metadata-refreshing")
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }

    private var officialMetadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TagFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                DetailPill(
                    text: RatingPresentation.resolve(
                        officialRating: series.officialRating,
                        personalRating: personalRecord?.myRating
                    ).text,
                    systemImage: "number"
                )
                .accessibilityIdentifier("official-rating")

                DetailPill(
                    text: officialHeatText,
                    systemImage: "flame.fill"
                )
                .accessibilityIdentifier("official-heat")

                DetailPill(
                    text: completionStatusText,
                    systemImage: completionStatusSymbol
                )
                .accessibilityIdentifier("completion-status")

                DetailPill(
                    text: shelfState.title,
                    systemImage: shelfState.systemImage
                )
                .accessibilityIdentifier("detail-shelf-state")

                if personalRecord?.followsUpdates == true {
                    DetailPill(text: "追更 / 预约", systemImage: "bell.badge.fill")
                        .accessibilityIdentifier("detail-follow-updates")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TagFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                if detailTags.isEmpty {
                    DetailTagPill(text: "暂无标签")
                } else {
                    ForEach(detailTags, id: \.self) { tag in
                        DetailTagPill(text: tag)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("official-tags")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var officialHeatText: String {
        guard let heat = series.officialHeatText, !heat.isEmpty else {
            return "暂无热度"
        }
        return heat.hasSuffix("热度") ? heat : "\(heat)热度"
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

    private var shelfState: ShelfState {
        ShelfState.resolve(personalRecord?.localShelfState)
    }

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("基本信息")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                if !series.intro.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isIntroExpanded.toggle()
                        }
                    } label: {
                        Label(isIntroExpanded ? "收起" : "展开", systemImage: isIntroExpanded ? "chevron.up" : "chevron.down")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DetailTheme.accent)
                }
            }

            if series.intro.isEmpty {
                Text("暂无公开简介")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.58))
            } else {
                Text(series.intro)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(isIntroExpanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
                .overlay(.white.opacity(0.12))
        }
    }

    private var personalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "我的评分与点评", symbol: "number.circle")
                .foregroundStyle(.white)

            if let personalRecord {
                Picker("完结状态", selection: completionStatusBinding) {
                    ForEach(SeriesCompletionStatus.allCases) { status in
                        Text(status.title).tag(status.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)

                Picker("书架状态", selection: shelfStateBinding(for: personalRecord)) {
                    Text("未开始").tag("unstarted")
                    Text("观看中").tag("watching")
                    Text("已看完").tag("finished")
                    Text("暂时搁置").tag("paused")
                    Text("弃剧").tag("dropped")
                }
                .pickerStyle(.menu)
                .tint(.white)

                Toggle("追更 / 预约", isOn: followUpdatesBinding(for: personalRecord))
                    .tint(DetailTheme.accent)

                RatingScorePicker(rating: ratingBinding(for: personalRecord), usesDarkAppearance: true)
                ReviewEditor(
                    text: reviewBinding(for: personalRecord),
                    placeholder: "写下整部漫剧的感受",
                    usesDarkAppearance: true
                )

                Button("保存总记录") {
                    personalRecord.updatedAt = .now
                    try? modelContext.save()
                    notice = "整部作品的评分和点评已保存。"
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var detailTags: [String] {
        tagValues(series.tagsText)
    }

    private var redFruitURL: URL? {
        if let source = series.sourceURL, let url = URL(string: source) {
            return url
        }
        return seasons
            .compactMap(\.sourceURL)
            .compactMap(URL.init(string:))
            .first
    }

    private func ensurePersonalRecord() {
        guard personalRecord == nil else { return }
        let record = PersonalRecord(sourceSeriesID: series.sourceSeriesID)
        modelContext.insert(record)
        try? modelContext.save()
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

    private func followUpdatesBinding(for personal: PersonalRecord) -> Binding<Bool> {
        Binding(
            get: { personal.followsUpdates },
            set: { value in
                personal.followsUpdates = value
                personal.followedAt = value ? (personal.followedAt ?? .now) : nil
                personal.updatedAt = .now
                try? modelContext.save()
            }
        )
    }

    private var completionStatusBinding: Binding<String> {
        Binding(
            get: { series.completionStatus ?? SeriesCompletionStatus.unknown.rawValue },
            set: { value in
                series.completionStatus = value
                series.updatedAt = .now
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

    private func refreshMetadata(showNotice: Bool) {
        guard !isRefreshing else { return }
        guard let url = redFruitURL else {
            if showNotice {
                notice = "这部作品没有网页链接，无法更新公开资料。"
            }
            return
        }

        isRefreshing = true
        Task {
            do {
                let metadata = try await PublicMetadataService.shared.fetch(from: url)
                let existingCoverOrientation: CoverImageOrientation?
                if let existingCover = series.coverURL {
                    existingCoverOrientation = await CoverImageProbe.orientation(urlString: existingCover)
                } else {
                    existingCoverOrientation = nil
                }
                await MainActor.run {
                    if let title = metadata.title, !title.isEmpty {
                        if series.title.isEmpty {
                            series.title = TitleNormalizer.seriesTitle(title) ?? title
                        }
                    }
                    if let coverURL = metadata.coverURL?.nilIfBlank,
                       series.coverURL == nil || CoverURLSelector.shouldReplaceExisting(series.coverURL) {
                        series.coverURL = coverURL
                    } else if existingCoverOrientation == .landscape {
                        // A previous release could persist the share page's
                        // landscape video image. Replace or clear it only
                        // after a successful orientation probe.
                        series.coverURL = metadata.coverURL?.nilIfBlank
                    }
                    if series.intro.isEmpty, let intro = metadata.intro { series.intro = intro }
                    if series.tagsText.isEmpty, let tagsText = metadata.tagsText { series.tagsText = tagsText }
                    if let rating = metadata.officialRating { series.officialRating = rating }
                    if let ratingCount = metadata.officialRatingCount { series.officialRatingCount = ratingCount }
                    if let heatScore = metadata.officialHeatScore { series.officialHeatScore = heatScore }
                    if let heat = metadata.officialHeatText { series.officialHeatText = heat }
                    mergePublicSeasons(metadata.seasons)
                    series.updatedAt = .now

                    let snapshot = OfficialSnapshot(sourceSeriesID: series.sourceSeriesID)
                    snapshot.officialRating = metadata.officialRating ?? series.officialRating
                    snapshot.officialRatingCount = metadata.officialRatingCount ?? series.officialRatingCount
                    snapshot.officialHeatScore = metadata.officialHeatScore ?? series.officialHeatScore
                    snapshot.officialHeatText = metadata.officialHeatText ?? series.officialHeatText
                    if !metadata.seasons.isEmpty {
                        snapshot.seasonCount = metadata.seasons.count
                        snapshot.episodeCount = metadata.seasons.map(\.episodeCount).reduce(0, +)
                    }
                    modelContext.insert(snapshot)
                    try? modelContext.save()
                    MetadataRefreshSchedule.markRun()
                    isRefreshing = false
                    if showNotice {
                        notice = metadata.seasons.isEmpty
                            ? "公开资料已更新，并保存了一条数据快照。"
                            : "公开资料、季集信息已更新，并保存了一条数据快照。"
                    }
                }
            } catch {
                await MainActor.run {
                    isRefreshing = false
                    if showNotice {
                        notice = "没有读取到可更新的公开资料，请检查链接或稍后重试。"
                    }
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
                    $0.seasonNumber == metadataSeason.seasonNumber
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

private enum DetailTheme {
    static let background = Color(red: 0.28, green: 0.28, blue: 0.28)
    static let cell = Color.white.opacity(0.10)
    static let accent = Color(red: 0.30, green: 0.58, blue: 0.96)
    static let trendSurface = Color(uiColor: .systemBackground)
    static let trendPlot = Color(uiColor: .secondarySystemBackground)
}

private struct OfficialTrendSection: View {
    let snapshots: [OfficialSnapshot]
    @State private var interval: TrendInterval = .week

    private var heatCandles: [TrendCandle] {
        TrendAggregation.candles(
            from: snapshots,
            interval: interval,
            value: { $0.officialHeatScore }
        )
    }

    private var ratingCandles: [TrendCandle] {
        TrendAggregation.candles(
            from: snapshots,
            interval: interval,
            value: { $0.officialRating }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("官方数据趋势", systemImage: "chart.xyaxis.line")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color(uiColor: .label))
                Spacer()
                Picker("统计周期", selection: $interval) {
                    ForEach(TrendInterval.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.accentColor)
                .accessibilityLabel("官方趋势统计周期")
            }

            if heatCandles.isEmpty && ratingCandles.isEmpty {
                    Text("刷新公开资料后，这里会按日、周、月、季度或年度保存官方热度和评分变化。")
                        .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if !heatCandles.isEmpty {
                    OfficialCandleChart(title: "官方热度", candles: heatCandles, isRating: false)
                }
                if !ratingCandles.isEmpty {
                    OfficialCandleChart(title: "官方评分", candles: ratingCandles, isRating: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(DetailTheme.trendSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(uiColor: .separator), lineWidth: 0.5)
        }
        .accessibilityIdentifier("official-trend-section")
}
}

private struct OfficialCandleChart: View {
    let title: String
    let candles: [TrendCandle]
    let isRating: Bool

    private var yDomain: ClosedRange<Double> {
        if isRating {
            return 0...10
        }
        let low = candles.map(\.low).min() ?? 0
        let high = candles.map(\.high).max() ?? 1
        let minimumRange = max(high * 0.08, 1)
        let padding = max((high - low) * 0.14, minimumRange * 0.5)
        let upperBound = high + padding
        return max(0, low - padding)...max(upperBound, high + 0.01)
    }

    private var candleWidth: CGFloat {
        candles.count > 18 ? 7 : 12
    }

    private var minimumBodyHeight: Double {
        max((yDomain.upperBound - yDomain.lowerBound) * 0.012, isRating ? 0.08 : 0.5)
    }

    private func bodyLower(for candle: TrendCandle) -> Double {
        let lower = min(candle.open, candle.close)
        let upper = max(candle.open, candle.close)
        return max(yDomain.lowerBound, lower == upper ? lower - minimumBodyHeight / 2 : lower)
    }

    private func bodyUpper(for candle: TrendCandle) -> Double {
        let lower = min(candle.open, candle.close)
        let upper = max(candle.open, candle.close)
        return min(yDomain.upperBound, upper == lower ? upper + minimumBodyHeight / 2 : upper)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(uiColor: .label))

            Chart(candles) { candle in
                RuleMark(
                    x: .value("周期", candle.bucket),
                    yStart: .value("最低", candle.low),
                    yEnd: .value("最高", candle.high)
                )
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .lineStyle(StrokeStyle(lineWidth: 1.2))

                BarMark(
                    x: .value("周期", candle.bucket),
                    yStart: .value("开盘", bodyLower(for: candle)),
                    yEnd: .value("收盘", bodyUpper(for: candle)),
                    width: .fixed(candleWidth)
                )
                .foregroundStyle(candle.close >= candle.open ? Color.green : Color.red)
            }
            .chartPlotStyle { plot in
                plot
                    .background(DetailTheme.trendPlot)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .chartYScale(domain: yDomain)
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color(uiColor: .separator).opacity(0.7))
                    AxisTick().foregroundStyle(Color(uiColor: .secondaryLabel))
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color(uiColor: .separator).opacity(0.7))
                    AxisTick().foregroundStyle(Color(uiColor: .secondaryLabel))
                    AxisValueLabel()
                }
            }
            .frame(height: 180)
        }
    }
}

private struct DetailPill: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(text)
        }
            .accessibilityElement(children: .combine)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.86))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct DetailTagPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.80))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct EpisodeProgressControl: View {
    @Environment(\.modelContext) private var modelContext

    let series: SeriesRecord
    let season: SeasonRecord
    var usesDarkAppearance = false

    @Query
    private var allEpisodes: [EpisodeRecord]

    @Query
    private var personalRecords: [PersonalRecord]

    init(series: SeriesRecord, season: SeasonRecord, usesDarkAppearance: Bool = false) {
        self.series = series
        self.season = season
        self.usesDarkAppearance = usesDarkAppearance

        let sourceSeriesID = series.sourceSeriesID
        let seasonNumber = season.seasonNumber
        _allEpisodes = Query(
            filter: #Predicate<EpisodeRecord> { episode in
                episode.sourceSeriesID == sourceSeriesID
                    && episode.seasonNumber == seasonNumber
            },
            sort: \EpisodeRecord.episodeNumber
        )
        _personalRecords = Query(
            filter: #Predicate<PersonalRecord> { personal in
                personal.sourceSeriesID == sourceSeriesID
            }
        )
    }

    private var totalEpisodeCount: Int {
        max(season.episodeCount, allEpisodes.map(\.episodeNumber).max() ?? 0)
    }

    private var watchedCount: Int {
        allEpisodes.filter(\.isWatched).count
    }

    private var personalRecord: PersonalRecord? {
        personalRecords.first { $0.sourceSeriesID == series.sourceSeriesID }
    }

    private var currentEpisodeNumber: Int {
        guard personalRecord?.currentSeasonNumber == season.seasonNumber else { return 0 }
        return personalRecord?.currentEpisodeNumber ?? 0
    }

    private var currentEpisodeTextBinding: Binding<String> {
        Binding(
            get: { currentEpisodeNumber == 0 ? "" : String(currentEpisodeNumber) },
            set: { value in
                let digits = value.filter { $0.isASCII && $0.isNumber }
                guard !digits.isEmpty else {
                    setCurrentEpisode(0)
                    return
                }
                if let episode = Int(digits) {
                    setCurrentEpisode(episode)
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("第\(season.seasonNumber)季")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryText)
                Spacer()
                Text(EpisodeProgressSupport.summary(
                    watchedCount: watchedCount,
                    totalEpisodeCount: totalEpisodeCount
                ))
                .font(.subheadline)
                .foregroundStyle(secondaryText)
            }

            HStack(spacing: 8) {
                Text("当前看到")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(primaryText)

                TextField("未开始", text: currentEpisodeTextBinding)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryText)
                    .frame(width: 64, height: 40)
                    .background(usesDarkAppearance ? DetailTheme.cell : Color(uiColor: .tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityIdentifier("episode-progress-input")

                Text("/ \(totalEpisodeCount) 集")
                    .font(.subheadline)
                    .foregroundStyle(secondaryText)

                Spacer(minLength: 0)
            }
            .disabled(totalEpisodeCount == 0)
            .accessibilityLabel("当前观看进度")
            .accessibilityValue(currentEpisodeNumber == 0 ? "未开始" : "第\(currentEpisodeNumber)集")
        }
    }

    private var primaryText: Color {
        usesDarkAppearance ? .white : .primary
    }

    private var secondaryText: Color {
        usesDarkAppearance ? .white.opacity(0.62) : .secondary
    }

    private func setCurrentEpisode(_ value: Int) {
        guard let number = EpisodeProgressSupport.selectedEpisode(
            value,
            totalEpisodeCount: totalEpisodeCount
        ) else {
            if let personalRecord, personalRecord.currentSeasonNumber == season.seasonNumber {
                personalRecord.currentEpisodeNumber = nil
                if personalRecord.localShelfState != "dropped" {
                    personalRecord.localShelfState = watchedCount >= totalEpisodeCount && totalEpisodeCount > 0
                        ? "finished"
                        : watchedCount > 0 ? "watching" : "unstarted"
                }
                personalRecord.updatedAt = .now
            }
            try? modelContext.save()
            return
        }

        let episode = allEpisodes.first { $0.episodeNumber == number } ?? EpisodeRecord(
            sourceVid: "\(series.sourceSeriesID)#s\(season.seasonNumber)#e\(number)",
            sourceSeriesID: series.sourceSeriesID,
            seasonNumber: season.seasonNumber,
            episodeNumber: number
        )
        if !allEpisodes.contains(where: { $0.sourceVid == episode.sourceVid }) {
            modelContext.insert(episode)
        }
        let wasWatched = episode.isWatched
        episode.isWatched = true
        episode.watchedAt = episode.watchedAt ?? .now

        let personal = personalRecord ?? makePersonalRecord()
        personal.currentSeasonNumber = season.seasonNumber
        personal.currentEpisodeNumber = number
        let watchedAfter = watchedCount + (wasWatched ? 0 : 1)
        if personal.localShelfState != "dropped" {
            personal.localShelfState = watchedAfter >= totalEpisodeCount ? "finished" : "watching"
        }
        personal.updatedAt = .now
        season.updatedAt = .now
        try? modelContext.save()
    }

    private func makePersonalRecord() -> PersonalRecord {
        let record = PersonalRecord(sourceSeriesID: series.sourceSeriesID)
        modelContext.insert(record)
        return record
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
    @State private var completionStatus: String

    init(series: SeriesRecord) {
        self.series = series
        _title = State(initialValue: series.title)
        _sourceURL = State(initialValue: series.sourceURL ?? "")
        _coverURL = State(initialValue: series.coverURL ?? "")
        _tagsText = State(initialValue: series.tagsText)
        _intro = State(initialValue: series.intro)
        _completionStatus = State(initialValue: series.completionStatus ?? SeriesCompletionStatus.unknown.rawValue)
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

                    Picker("完结状态", selection: $completionStatus) {
                        ForEach(SeriesCompletionStatus.allCases) { status in
                            Text(status.title).tag(status.rawValue)
                        }
                    }
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
                        series.completionStatus = completionStatus
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
    @State private var detectedSeasons: [PublicSeasonMetadata] = []
    @State private var isFetching = false
    @State private var notice: String?
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

                Button {
                    fetchMetadata()
                } label: {
                    HStack {
                        Label("读取链接中的其他季", systemImage: "arrow.down.circle")
                        Spacer()
                        if isFetching { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(isFetching || URLExtractor.firstURL(in: sourceURL) == nil)

                if !detectedSeasons.isEmpty {
                    Text("已识别 \(detectedSeasons.count) 季，保存后会合并到当前作品。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("添加 / 查找其他季")
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
            .alert("操作提示", isPresented: Binding(
                get: { errorMessage != nil || notice != nil },
                set: { if !$0 { errorMessage = nil; notice = nil } }
            )) {
                Button("好", role: .cancel) { errorMessage = nil; notice = nil }
            } message: {
                Text(errorMessage ?? notice ?? "")
            }
        }
    }

    private func fetchMetadata() {
        guard let url = URLExtractor.firstURL(in: sourceURL) else { return }
        isFetching = true
        errorMessage = nil
        Task {
            do {
                let metadata = try await PublicMetadataService.shared.fetch(from: url)
                await MainActor.run {
                    detectedSeasons = metadata.seasons
                    if let first = metadata.seasons.first {
                        seasonNumber = first.seasonNumber
                        title = first.title ?? "第\(first.seasonNumber)季"
                        episodeCount = first.episodeCount
                    }
                    isFetching = false
                    if metadata.seasons.isEmpty {
                        notice = "链接中没有可识别的季资料，可以手动填写后保存。"
                    }
                }
            } catch {
                await MainActor.run {
                    isFetching = false
                    errorMessage = "没有读取到这条链接的公开季资料。"
                }
            }
        }
    }

    private func save() {
        do {
            let existingSeasons = try modelContext.fetch(FetchDescriptor<SeasonRecord>())
            let existingEpisodes = try modelContext.fetch(FetchDescriptor<EpisodeRecord>())
            let cleanURL = URLExtractor.firstURL(in: sourceURL)?.absoluteString
            let seasonsToSave = detectedSeasons.isEmpty
                ? [PublicSeasonMetadata(
                    seasonNumber: seasonNumber,
                    title: title.nilIfBlank,
                    episodeCount: episodeCount,
                    sourceURL: cleanURL,
                    episodes: []
                )]
                : detectedSeasons

            for metadataSeason in seasonsToSave {
                let season = existingSeasons.first {
                    $0.sourceSeriesID == seriesID && $0.seasonNumber == metadataSeason.seasonNumber
                } ?? SeasonRecord(sourceSeriesID: seriesID, seasonNumber: metadataSeason.seasonNumber)
                if !existingSeasons.contains(where: { $0 === season }) { modelContext.insert(season) }
                season.title = metadataSeason.seasonNumber == seasonNumber
                    ? (title.nilIfBlank ?? metadataSeason.title ?? "第\(metadataSeason.seasonNumber)季")
                    : (metadataSeason.title ?? "第\(metadataSeason.seasonNumber)季")
                season.episodeCount = max(season.episodeCount, metadataSeason.episodeCount)
                season.sourceURL = metadataSeason.sourceURL ?? cleanURL ?? season.sourceURL
                season.updatedAt = .now

                for metadataEpisode in metadataSeason.episodes {
                    let episode = existingEpisodes.first {
                        $0.sourceSeriesID == seriesID
                            && $0.seasonNumber == metadataSeason.seasonNumber
                            && $0.episodeNumber == metadataEpisode.episodeNumber
                    } ?? EpisodeRecord(
                        sourceVid: "\(seriesID)#s\(metadataSeason.seasonNumber)#e\(metadataEpisode.episodeNumber)",
                        sourceSeriesID: seriesID,
                        seasonNumber: metadataSeason.seasonNumber,
                        episodeNumber: metadataEpisode.episodeNumber
                    )
                    if !existingEpisodes.contains(where: { $0 === episode }) { modelContext.insert(episode) }
                    if let episodeTitle = metadataEpisode.title, !episodeTitle.isEmpty { episode.title = episodeTitle }
                    if let webURL = metadataEpisode.webURL { episode.webURL = webURL }
                }
            }
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

    init(series: SeriesRecord, season: SeasonRecord) {
        self.series = series
        self.season = season

        let sourceSeriesID = series.sourceSeriesID
        let seasonNumber = season.seasonNumber
        _allEpisodes = Query(
            filter: #Predicate<EpisodeRecord> { episode in
                episode.sourceSeriesID == sourceSeriesID
                    && episode.seasonNumber == seasonNumber
            },
            sort: \EpisodeRecord.episodeNumber
        )
    }

    private var episodes: [EpisodeRecord] {
        allEpisodes
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
                    SectionTitle(title: "观看进度", symbol: "bookmark")
                    EpisodeProgressControl(series: series, season: season)
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
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(title: "已录入集资料", symbol: "list.number")
                        Text("已录入 \(episodes.count) 集资料，页面不展开逐集列表。需要记录当前位置时，在上方输入当前集数即可。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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
            SectionTitle(title: "本季评分与点评", symbol: "number.circle")
            RatingScorePicker(rating: Binding(
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
    var usesDarkAppearance = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(usesDarkAppearance ? Color.white.opacity(0.42) : Color(uiColor: .secondaryLabel))
                    .padding(.top, 8)
                    .padding(.leading, 5)
            }
            TextEditor(text: $text)
                .frame(minHeight: 100)
                .scrollContentBackground(.hidden)
                .foregroundStyle(usesDarkAppearance ? Color.white : Color.primary)
        }
        .background(usesDarkAppearance ? Color.white.opacity(0.08) : Color(uiColor: .tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(usesDarkAppearance ? Color.white.opacity(0.14) : Color(uiColor: .separator), lineWidth: 0.5)
        }
    }
}

private struct RatingScorePicker: View {
    @Binding var rating: Double?
    var usesDarkAppearance = false

    var body: some View {
        Menu {
            Button("未评分") {
                rating = nil
            }

            ForEach(RatingScale.options, id: \.self) { value in
                Button {
                    rating = value
                } label: {
                    if rating == value {
                        Label(String(format: "%.1f 分", value), systemImage: "checkmark")
                    } else {
                        Text(String(format: "%.1f 分", value))
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Label("评分", systemImage: "number")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 12)
                Text(scoreText)
                    .font(.headline.monospacedDigit())
                    .accessibilityIdentifier("personal-rating-score")
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(usesDarkAppearance ? Color.white.opacity(0.66) : Color.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .background(usesDarkAppearance ? Color.white.opacity(0.08) : Color(uiColor: .tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .foregroundStyle(usesDarkAppearance ? Color.white : Color.primary)
        .tint(usesDarkAppearance ? DetailTheme.accent : Color.accentColor)
        .accessibilityLabel("评分")
        .accessibilityValue(scoreText)
    }

    private var scoreText: String {
        guard let rating else { return "未评分" }
        return String(format: "%.1f", rating)
    }

}
