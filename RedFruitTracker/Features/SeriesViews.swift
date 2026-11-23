import Foundation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct SeriesDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    let series: SeriesRecord

    @Query(sort: \SeasonRecord.seasonNumber)
    private var allSeasons: [SeasonRecord]

    @Query
    private var personalRecords: [PersonalRecord]

    @Query(sort: \SeriesRecord.createdAt, order: .reverse)
    private var allSeries: [SeriesRecord]

    @State private var isIntroExpanded = false
    @State private var notice: String?
    @State private var personalSaveError: String?
    @State private var pendingBrowserFallbackURL: URL?
    @State private var reviewFocusGeneration = 0
    @State private var isShowingSeriesEdit = false
    @State private var isShowingRelatedSeriesAdd = false

    init(series: SeriesRecord) {
        self.series = series

        let sourceSeriesID = series.sourceSeriesID
        _allSeasons = Query(
            filter: #Predicate<SeasonRecord> { season in
                season.sourceSeriesID == sourceSeriesID
            },
            sort: \SeasonRecord.seasonNumber
        )
        _personalRecords = Query(
            filter: #Predicate<PersonalRecord> { personal in
                personal.sourceSeriesID == sourceSeriesID
            }
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
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppLayout.sectionSpacing) {
                    detailHeader
                    introSection
                    relatedWorksSection
                    relatedScreenshotSection
                    personalSection {
                        reviewFocusGeneration += 1
                    }
                }
                .padding(.horizontal, AppLayout.pageInset)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(DetailTheme.background.ignoresSafeArea())
        .onChange(of: reviewFocusGeneration) { _, _ in
            Task { @MainActor in
                await Task.yield()
                proxy.scrollTo("personal-review-input", anchor: .center)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(DetailTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingSeriesEdit = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("编辑作品")
                .accessibilityIdentifier("edit-series-button")
            }
        }
        .sheet(isPresented: $isShowingSeriesEdit) {
            EditSeriesView(series: series)
        }
        .alert("提示", isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )) {
            if let pendingBrowserFallbackURL {
                Button("用浏览器打开") {
                    openURL(pendingBrowserFallbackURL)
                    self.pendingBrowserFallbackURL = nil
                    notice = nil
                }
                Button("取消", role: .cancel) {
                    self.pendingBrowserFallbackURL = nil
                    notice = nil
                }
            } else {
                Button("好", role: .cancel) { notice = nil }
            }
        } message: {
            Text(notice ?? "")
        }
        .task {
            ensurePersonalRecord()
            if let personalRecord,
               personalRecord.nextSeasonDate != nil || personalRecord.nextSeasonDateUnknown {
                updateAppointmentNotification(for: personalRecord, date: personalRecord.nextSeasonDate)
            }
        }
        .onDisappear { flushPersonalChanges() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { flushPersonalChanges() }
        }
        }
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                    CoverView(urlString: series.coverURL, title: series.title, width: 132, height: 184)
                    .fixedSize()
                    .accessibilityIdentifier("series-detail-cover")

                VStack(alignment: .leading, spacing: 12) {
                    Button(action: copySeriesTitle) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(series.title)
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(4)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("series-detail-title")
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: AppLayout.minimumControlHeight, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("复制作品名称")
                    .accessibilityIdentifier("copy-series-title")

                    officialMetadataSection
                    originalWorkSection
                }
                .frame(maxWidth: .infinity, minHeight: 184, alignment: .topLeading)
                .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, minHeight: 184, alignment: .topLeading)

            if let url = redFruitURL {
                Button {
                    openRedFruitApp(url)
                } label: {
                    Label("打开红果漫剧", systemImage: "play.rectangle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(DetailTheme.accent)
                .accessibilityIdentifier("open-red-fruit-button")
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }

    private var relatedSeries: [SeriesRecord] {
        guard let key = series.relatedIPKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return []
        }
        let normalizedKey = key.lowercased()
        return allSeries.filter {
            $0.sourceSeriesID != series.sourceSeriesID
                && $0.relatedIPKey?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedKey
        }
    }

    private var relatedScreenshotSection: some View {
        RelatedScreenshotSection(series: series)
    }

    @ViewBuilder
    private var originalWorkSection: some View {
        if let title = series.originalTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("相关原著")
                    .font(.headline)
                    .foregroundStyle(.white)
                HStack(spacing: 12) {
                    CoverView(urlString: series.originalCoverURL, title: title, width: 58, height: 82)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        HStack(spacing: 5) {
                            Text("原著小说")
                            if let status = series.originalStatus, !status.isEmpty { Text("· \(status)") }
                            if let rating = series.originalRating { Text("· \(String(format: "%.1f", rating))分") }
                        }
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                    }
                    Spacer(minLength: 0)
                    if let originalURL = series.originalURL.flatMap(URL.init(string:)) {
                        Link("去阅读", destination: originalURL)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DetailTheme.accent)
                    }
                }
                .padding(12)
                .background(DetailTheme.cell, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var relatedWorksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("相关作品")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    isShowingRelatedSeriesAdd = true
                } label: {
                    Label("添加同 IP", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(DetailTheme.accent)
                .accessibilityIdentifier("add-related-series-button")
            }

            if relatedSeries.isEmpty {
                Text("粘贴红果分享内容，即可自动读取并关联作品")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DetailTheme.cell, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(relatedSeries) { related in
                            NavigationLink {
                                SeriesDetailView(series: related)
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    ZStack(alignment: .topTrailing) {
                                        CoverView(
                                            urlString: related.coverURL,
                                            title: related.title,
                                            width: 116,
                                            height: 164
                                        )
                                        Text("同 IP")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 5)
                                            .background(.black.opacity(0.62), in: Capsule())
                                            .padding(7)
                                    }
                                    Text(related.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)
                                        .frame(width: 116, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("同 IP：\(related.title)")
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("related-works-section")
        .sheet(isPresented: $isShowingRelatedSeriesAdd) {
            AddSeriesView(initialURL: nil, relatedToSeriesID: series.sourceSeriesID) {}
        }
    }

    private var officialMetadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FixedWorkMetricGrid(metrics: [
                WorkMetric(
                    id: "official-rating",
                    label: "官方",
                    value: series.officialRating.map { String(format: "%.1f", $0) } ?? "暂无评分",
                    tint: .orange,
                    symbol: "star.fill"
                ),
                WorkMetric(
                    id: "personal-rating",
                    label: "我的",
                    value: personalRecord?.myRating.map { String(format: "%.1f", $0) } ?? "未评分",
                    tint: .blue,
                    symbol: "person.fill"
                ),
                WorkMetric(
                    id: "official-heat",
                    label: "热度",
                    value: compactHeatText,
                    tint: .pink,
                    symbol: "flame.fill"
                ),
                WorkMetric(
                    id: "detail-season-count",
                    label: "季数",
                    value: "\(series.manualSeasonCount ?? seasons.count)季",
                    tint: .teal,
                    symbol: "square.stack.3d.up.fill"
                )
            ], usesDarkAppearance: true)

            TagFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                DetailPill(
                    text: completionStatusText,
                    systemImage: completionStatusSymbol,
                    tint: completionStatusTint
                )
                .accessibilityIdentifier("completion-status")

                DetailPill(
                    text: shelfState.title,
                    systemImage: shelfState.systemImage,
                    tint: shelfStateTint
                )
                .accessibilityIdentifier("detail-shelf-state")

                if personalRecord?.followsUpdates == true {
                    DetailPill(text: "追更", systemImage: "bell.badge.fill", tint: .indigo)
                        .accessibilityIdentifier("detail-follow-updates")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TagFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                if detailTags.isEmpty {
                    DetailTagPill(text: "暂无标签")
                } else {
                    ForEach(detailTags, id: \.self) { tag in
                        Button {
                            NotificationCenter.default.post(name: .searchLibraryTag, object: tag)
                        } label: {
                            DetailTagPill(text: tag)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("搜索标签：\(tag)")
                        .accessibilityIdentifier("detail-tag-\(tag)")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("official-tags")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactHeatText: String {
        guard let heat = series.officialHeatText?.trimmingCharacters(in: .whitespacesAndNewlines), !heat.isEmpty else {
            return "暂无"
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
        ShelfState.resolve(personalRecord?.localShelfState)
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

    private func personalSection(onReviewInteraction: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "我的评分与点评", symbol: "number.circle")
                .foregroundStyle(.white)

            if let personalRecord {
                VStack(spacing: 0) {
                    LabeledContent("完结状态") {
                        Picker("完结状态", selection: completionStatusBinding) {
                            ForEach(SeriesCompletionStatus.allCases) { status in
                                Text(status.title).tag(status.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("completion-status-picker")
                    }
                    .frame(minHeight: 48)
                    Divider().overlay(.white.opacity(0.12))
                    LabeledContent("观看状态") {
                        Picker("观看状态", selection: shelfStateBinding(for: personalRecord)) {
                            ForEach(ShelfState.allCases) { state in
                                Text(state.title).tag(state.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("shelf-state-picker")
                    }
                    .frame(minHeight: 48)
                    Divider().overlay(.white.opacity(0.12))
                    Toggle("追更", isOn: followUpdatesBinding(for: personalRecord))
                        .tint(DetailTheme.accent)
                        .frame(minHeight: 52)
                        .accessibilityIdentifier("follow-updates-toggle")
                    Divider().overlay(.white.opacity(0.12))
                    OptionalDatePickerRow(
                        date: nextSeasonDateBinding(for: personalRecord),
                        usesDarkAppearance: true,
                        nextSeasonNumber: (series.manualSeasonCount ?? (seasons.map(\.seasonNumber).max() ?? 0)) + 1
                    )
                    .accessibilityIdentifier("next-season-date-picker")
                    Toggle("即将上线", isOn: nextSeasonDateUnknownBinding(for: personalRecord))
                        .tint(DetailTheme.accent)
                        .frame(minHeight: 48)
                        .accessibilityIdentifier("next-season-date-unknown")
                    Divider().overlay(.white.opacity(0.12))
                    Stepper(value: manualSeasonCountBinding, in: 0...99) {
                        HStack {
                            Text("总季数")
                            Spacer(minLength: 8)
                            Text("\(manualSeasonCount)季")
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.84))
                        }
                    }
                    .frame(minHeight: 52)
                    .accessibilityIdentifier("manual-season-count-stepper")
                }
                .font(.body)
                .foregroundStyle(.white)
                .tint(.white)
                .padding(.horizontal, AppLayout.pageInset)
                .padding(.vertical, 4)
                .background(DetailTheme.cell, in: RoundedRectangle(cornerRadius: 12))

                RatingScorePicker(initialRating: personalRecord.myRating, usesDarkAppearance: true) { value in
                    commitPersonalRating(value, for: personalRecord)
                }
                ReviewEditor(
                    initialText: personalRecord.review,
                    placeholder: "写下整部漫剧的感受",
                    usesDarkAppearance: true,
                    accessibilityIdentifier: "personal-review-input",
                    onInteraction: onReviewInteraction,
                    onCommit: { value in
                        commitPersonalReview(value, for: personalRecord)
                    }
                )
                .id("personal-review-input")

                if let personalSaveError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(personalSaveError)
                        Button("重试保存") { flushPersonalChanges() }
                            .frame(minHeight: 44)
                    }
                    .font(.footnote)
                    .foregroundStyle(.white)
                }
            }
        }
    }

    private var detailTags: [String] {
        tagValues(series.tagsText)
    }

    private func copySeriesTitle() {
        UIPasteboard.general.string = series.title
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

    private func openRedFruitApp(_ url: URL) {
        UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { didOpenApp in
            guard !didOpenApp else { return }
            DispatchQueue.main.async {
                self.pendingBrowserFallbackURL = url
                self.notice = "红果尚未为这个链接提供应用内跳转，要在浏览器打开原始链接吗？"
            }
        }
    }

    private func ensurePersonalRecord() {
        guard personalRecord == nil else { return }
        let record = PersonalRecord(sourceSeriesID: series.sourceSeriesID)
        modelContext.insert(record)
        savePersonalChanges()
    }

    private func shelfStateBinding(for personal: PersonalRecord) -> Binding<String> {
        Binding(
            get: { personal.localShelfState },
            set: { value in
                personal.localShelfState = value
                personal.viewingStatusChangedAt = .now
                personal.updatedAt = .now
                savePersonalChanges()
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
                savePersonalChanges()
            }
        )
    }

    private var manualSeasonCount: Int {
        series.manualSeasonCount ?? seasons.count
    }

    private var manualSeasonCountBinding: Binding<Int> {
        Binding(
            get: { manualSeasonCount },
            set: { value in
                series.manualSeasonCount = value
                series.updatedAt = .now
                savePersonalChanges()
            }
        )
    }

    private func nextSeasonDateBinding(for personal: PersonalRecord) -> Binding<Date?> {
        Binding(
            get: { personal.nextSeasonDate },
            set: { value in
                personal.nextSeasonDate = value
                personal.nextSeasonDateUnknown = false
                personal.updatedAt = .now
                savePersonalChanges()
                updateAppointmentNotification(for: personal, date: value)
            }
        )
    }

    private func nextSeasonDateUnknownBinding(for personal: PersonalRecord) -> Binding<Bool> {
        Binding(
            get: { personal.nextSeasonDateUnknown },
            set: { value in
                personal.nextSeasonDateUnknown = value
                if value { personal.nextSeasonDate = nil }
                personal.updatedAt = .now
                savePersonalChanges()
                updateAppointmentNotification(for: personal, date: personal.nextSeasonDate)
            }
        )
    }

    private func updateAppointmentNotification(for personal: PersonalRecord, date: Date?) {
        let sourceID = personal.sourceSeriesID
        let descriptor = FetchDescriptor<UpdateNotificationRecord>(
            predicate: #Predicate<UpdateNotificationRecord> { record in
                record.sourceSeriesID == sourceID
            }
        )
        let existing = (try? modelContext.fetch(descriptor))?.first

        let isDateUnknown = personal.nextSeasonDateUnknown
        guard let date else {
            guard isDateUnknown else {
                if let existing { modelContext.delete(existing) }
                UpdateNotificationService.cancelAppointment(seriesID: sourceID)
                try? modelContext.saveAndNotifyCloudBackup()
                return
            }
            let notification = existing ?? UpdateNotificationRecord(
                sourceSeriesID: sourceID,
                title: series.title,
                scheduledAt: .distantFuture,
                isDateUnknown: true
            )
            if existing == nil { modelContext.insert(notification) }
            notification.title = series.title
            notification.scheduledAt = .distantFuture
            notification.isDateUnknown = true
            notification.isRead = false
            UpdateNotificationService.cancelAppointment(seriesID: sourceID)
            try? modelContext.saveAndNotifyCloudBackup()
            return
        }

        if let existing, Calendar.current.isDate(existing.scheduledAt, inSameDayAs: date) {
            return
        }

        let notification = existing ?? UpdateNotificationRecord(
            sourceSeriesID: personal.sourceSeriesID,
            title: series.title,
            scheduledAt: date
        )
        if existing == nil { modelContext.insert(notification) }
        notification.title = series.title
        notification.scheduledAt = date
        notification.isDateUnknown = false
        notification.isRead = false
        try? modelContext.saveAndNotifyCloudBackup()
        Task {
            await UpdateNotificationService.scheduleAppointment(
                seriesID: sourceID,
                title: series.title,
                date: date
            )
        }
    }

    private var completionStatusBinding: Binding<String> {
        Binding(
            get: { series.completionStatus ?? SeriesCompletionStatus.unknown.rawValue },
            set: { value in
                series.completionStatus = value
                series.updatedAt = .now
                savePersonalChanges()
            }
        )
    }

    private func commitPersonalRating(_ value: Double?, for personal: PersonalRecord) {
        personal.myRating = value
        personal.updatedAt = .now
        savePersonalChanges()
    }

    private func commitPersonalReview(_ value: String, for personal: PersonalRecord) {
        personal.review = value
        personal.updatedAt = .now
        savePersonalChanges()
    }

    private func flushPersonalChanges() {
        if modelContext.hasChanges { savePersonalChanges() }
    }

    private func savePersonalChanges() {
        do {
            try modelContext.saveAndNotifyCloudBackup()
            personalSaveError = nil
        } catch {
            personalSaveError = "自动保存未完成，内容仍保留在当前页面，请重试。"
        }
    }

}

private enum DetailTheme {
    static let background = Color(red: 0.16, green: 0.19, blue: 0.24)
    static let cell = Color.white.opacity(0.11)
    static let accent = Color(red: 0.30, green: 0.58, blue: 0.96)
}

private struct RelatedScreenshotSection: View {
    @Environment(\.modelContext) private var modelContext

    let series: SeriesRecord

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isShowingViewer = false
    @State private var viewerIndex = 0
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
        .accessibilityIdentifier("related-screenshot-section")
        .sheet(isPresented: $isShowingViewer) {
            let data = screenshotData
            let images = data.compactMap(RelatedScreenshotImage.image(from:))
            if !images.isEmpty {
                RelatedScreenshotViewer(
                    images: images,
                    data: data,
                    selectedIndex: $viewerIndex,
                    onSave: saveToPhotos,
                    onDelete: deleteScreenshot(at:)
                )
            }
        }
        .alert("相关截图", isPresented: noticeBinding) {
            Button("好", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
        .onChange(of: pickerItems) { _, _ in
            Task { await importScreenshot() }
        }
    }

    private var header: some View {
        HStack {
            Text("相关截图")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Spacer()
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: RelatedScreenshotImage.maximumCount,
                matching: .images,
                preferredItemEncoding: .automatic
            ) {
                Label("添加", systemImage: "photo.badge.plus")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(DetailTheme.accent)
            .accessibilityIdentifier("related-screenshot-picker")
        }
    }

    @ViewBuilder
    private var content: some View {
        if !screenshotData.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(screenshotData.enumerated()), id: \.offset) { index, data in
                        if let image = RelatedScreenshotImage.image(from: data) {
                            Button {
                                viewerIndex = index
                                isShowingViewer = true
                            } label: {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 132)
                                    .frame(maxHeight: 184)
                                    .background(DetailTheme.cell, in: RoundedRectangle(cornerRadius: 12))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.16)) }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { saveToPhotos(data) } label: {
                                    Label("保存到相册", systemImage: "square.and.arrow.down")
                                }
                                Button(role: .destructive) { deleteScreenshot(at: index) } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            .accessibilityLabel("展开相关截图 \(index + 1)")
                            .accessibilityIdentifier("related-screenshot-preview-\(index)")
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        } else {
            Label("尚未上传相关截图", systemImage: "photo")
                .foregroundStyle(.white.opacity(0.72))
                .frame(maxWidth: .infinity, minHeight: 84)
                .background(DetailTheme.cell, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var screenshotData: [Data] {
        RelatedScreenshotImage.images(from: series.relatedScreenshotData)
    }

    private var noticeBinding: Binding<Bool> {
        Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )
    }

    private func importScreenshot() async {
        guard !pickerItems.isEmpty else { return }
        do {
            var images = screenshotData
            for item in pickerItems.prefix(RelatedScreenshotImage.maximumCount) {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let normalizedData = await RelatedScreenshotImage.normalizedData(from: data) else {
                    continue
                }
                images.append(normalizedData)
                if images.count == RelatedScreenshotImage.maximumCount { break }
            }
            guard !images.isEmpty else { throw RelatedScreenshotImageError.invalidImage }
            series.relatedScreenshotData = RelatedScreenshotImage.archivedData(from: images)
            try modelContext.saveAndNotifyCloudBackup()
            self.pickerItems = []
        } catch {
            notice = error.localizedDescription
        }
    }

    private func deleteScreenshot(at index: Int) {
        var images = screenshotData
        guard images.indices.contains(index) else { return }
        images.remove(at: index)
        series.relatedScreenshotData = RelatedScreenshotImage.archivedData(from: images)
        viewerIndex = min(viewerIndex, max(images.count - 1, 0))
        try? modelContext.saveAndNotifyCloudBackup()
        if images.isEmpty { isShowingViewer = false }
    }

    private func saveToPhotos(_ data: Data) {
        Task {
            do {
                try await RelatedScreenshotImage.saveToPhotos(data: data)
                await MainActor.run { notice = "已保存到设备相册。" }
            } catch {
                await MainActor.run { notice = error.localizedDescription }
            }
        }
    }
}

private struct RelatedScreenshotViewer: View {
    @Environment(\.dismiss) private var dismiss

    let images: [UIImage]
    let data: [Data]
    @Binding var selectedIndex: Int
    let onSave: (Data) -> Void
    let onDelete: (Int) -> Void

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedIndex) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(16)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .background(DetailTheme.background)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if data.indices.contains(selectedIndex) {
                        Button { onSave(data[selectedIndex]) } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .accessibilityLabel("保存当前截图到相册")
                        Button(role: .destructive) {
                            onDelete(selectedIndex)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("删除当前截图")
                    }
                }
            }
        }
    }
}

private struct DetailPill: View {
    let text: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(text)
        }
            .accessibilityElement(children: .combine)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(tint.opacity(0.16))
            .clipShape(Capsule())
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
            try? modelContext.saveAndNotifyCloudBackup()
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
        try? modelContext.saveAndNotifyCloudBackup()
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
                        try? modelContext.saveAndNotifyCloudBackup()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

struct SeasonDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    let series: SeriesRecord
    let season: SeasonRecord

    @Query(sort: \EpisodeRecord.episodeNumber)
    private var allEpisodes: [EpisodeRecord]

    @State private var isShowingAddEpisode = false
    @State private var isShowingEdit = false
    @State private var notice: String?
    @State private var seasonSaveTask: Task<Void, Never>?
    @State private var seasonSaveError: String?

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
                .padding(AppLayout.pageInset)
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
            .padding(AppLayout.pageInset)
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
        .onDisappear { flushSeasonChanges() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { flushSeasonChanges() }
        }
    }

    private var seasonRatingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "本季评分与点评", symbol: "number.circle")
            RatingScorePicker(initialRating: season.myRating) { value in
                season.myRating = value
                season.updatedAt = .now
                scheduleSeasonSave()
            }
            ReviewEditor(
                initialText: season.review,
                placeholder: "写下这一季的感受",
                accessibilityIdentifier: "season-review-input",
                onCommit: { value in
                    season.review = value
                    season.updatedAt = .now
                    scheduleSeasonSave()
                }
            )

            if let seasonSaveError {
                VStack(alignment: .leading, spacing: 6) {
                    Text(seasonSaveError)
                    Button("重试保存") { flushSeasonChanges() }
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
    }

    private func scheduleSeasonSave() {
        seasonSaveTask?.cancel()
        seasonSaveTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            saveSeasonChanges()
        }
    }

    private func flushSeasonChanges() {
        seasonSaveTask?.cancel()
        seasonSaveTask = nil
        if modelContext.hasChanges { saveSeasonChanges() }
    }

    private func saveSeasonChanges() {
        seasonSaveTask?.cancel()
        seasonSaveTask = nil
        do {
            try modelContext.saveAndNotifyCloudBackup()
            seasonSaveError = nil
        } catch {
            seasonSaveError = "自动保存未完成，请重试。"
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
            try modelContext.saveAndNotifyCloudBackup()
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
                        try? modelContext.saveAndNotifyCloudBackup()
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
    let initialText: String
    let placeholder: String
    let accessibilityIdentifier: String
    var usesDarkAppearance = false
    var onInteraction: () -> Void = {}
    let onCommit: (String) -> Void

    @State private var draftBuffer: TextDraftBuffer
    @State private var commitTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    init(
        initialText: String,
        placeholder: String,
        usesDarkAppearance: Bool = false,
        accessibilityIdentifier: String = "review-input",
        onInteraction: @escaping () -> Void = {},
        onCommit: @escaping (String) -> Void
    ) {
        self.initialText = initialText
        self.placeholder = placeholder
        self.usesDarkAppearance = usesDarkAppearance
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onInteraction = onInteraction
        self.onCommit = onCommit
        _draftBuffer = State(initialValue: TextDraftBuffer(initialText))
    }

    var body: some View {
        TextField(
            "",
            text: $draftBuffer.draft,
            prompt: Text(placeholder).foregroundColor(usesDarkAppearance ? Color.white.opacity(0.92) : Color.secondary),
            axis: .vertical
        )
            .font(.system(.body, design: .rounded))
            .lineLimit(5...)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(usesDarkAppearance ? Color.white : Color.primary)
            .tint(usesDarkAppearance ? DetailTheme.accent : Color.accentColor)
            .focused($isFocused)
            .accessibilityIdentifier(accessibilityIdentifier)
            .background(usesDarkAppearance ? Color.white.opacity(0.12) : Color(uiColor: .tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(usesDarkAppearance ? Color.white.opacity(0.28) : Color(uiColor: .separator), lineWidth: 0.5)
            }
        .onChange(of: draftBuffer.draft) { _, _ in
            onInteraction()
            scheduleCommit()
        }
        .onChange(of: initialText) { _, value in
            guard value != draftBuffer.committed else { return }
            draftBuffer.reset(to: value)
        }
        .onChange(of: isFocused) { wasFocused, focused in
            if focused { onInteraction() }
            if wasFocused && !focused { commitDraft() }
        }
        .onDisappear { commitDraft() }
    }

    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 450_000_000) } catch { return }
            commitDraft()
        }
    }

    private func commitDraft() {
        commitTask?.cancel()
        commitTask = nil
        guard let value = draftBuffer.commit() else { return }
        onCommit(value)
    }
}

private struct RatingScorePicker: View {
    let initialRating: Double?
    let onCommit: (Double?) -> Void
    var usesDarkAppearance = false
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    init(
        initialRating: Double?,
        usesDarkAppearance: Bool = false,
        onCommit: @escaping (Double?) -> Void
    ) {
        self.initialRating = initialRating
        self.usesDarkAppearance = usesDarkAppearance
        self.onCommit = onCommit
        self._draft = State(initialValue: initialRating.map { String(format: "%.1f", $0) } ?? "")
    }

    var body: some View {
        HStack(spacing: 10) {
            Label("评分", systemImage: "number")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            TextField(
                "",
                text: $draft,
                prompt: Text("未评分").foregroundColor(usesDarkAppearance ? Color.white.opacity(0.92) : Color.secondary)
            )
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(usesDarkAppearance ? Color.white : Color.primary)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused($isFocused)
                .submitLabel(.done)
                .accessibilityIdentifier("personal-rating-input")
                .frame(minWidth: 56, minHeight: AppLayout.minimumControlHeight)
                .onSubmit(commitDraft)

            if !draft.isEmpty {
                Button {
                    draft = ""
                    onCommit(nil)
                    isFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(usesDarkAppearance ? Color.white.opacity(0.82) : Color.secondary)
                        .frame(width: AppLayout.minimumControlHeight, height: AppLayout.minimumControlHeight)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除评分")
            }
        }
        .frame(maxWidth: .infinity, minHeight: AppLayout.minimumControlHeight, alignment: .leading)
        .padding(.horizontal, 12)
        .background(usesDarkAppearance ? Color.white.opacity(0.08) : Color(uiColor: .tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .foregroundStyle(usesDarkAppearance ? Color.white : Color.primary)
        .tint(usesDarkAppearance ? DetailTheme.accent : Color.accentColor)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("personal-rating-score")
        .onChange(of: initialRating) { _, value in
            guard !isFocused else { return }
            draft = value.map { String(format: "%.1f", $0) } ?? ""
        }
        .onChange(of: isFocused) { wasFocused, focused in
            if wasFocused && !focused { commitDraft() }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    commitDraft()
                    isFocused = false
                }
            }
        }
    }

    private func commitDraft() {
        let valueText = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !valueText.isEmpty else {
            onCommit(nil)
            draft = ""
            return
        }
        guard let value = Double(valueText) else {
            draft = initialRating.map { String(format: "%.1f", $0) } ?? ""
            return
        }
        let normalized = RatingScale.normalized(value)
        onCommit(normalized)
        draft = String(format: "%.1f", normalized)
    }
}
