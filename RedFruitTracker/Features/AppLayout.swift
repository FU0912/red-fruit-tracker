import CoreGraphics
import Foundation
import SwiftUI

enum AppLayout {
    static let pageInset: CGFloat = 16
    static let sectionSpacing: CGFloat = 16
    static let minimumControlHeight: CGFloat = 44
}

enum AppDateText {
    static func monthDay(_ date: Date) -> String {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(month)月\(day)日"
    }
}

struct OptionalDatePickerRow: View {
    @Binding private var date: Date?
    private let identifier: String
    private let usesDarkAppearance: Bool
    private let nextSeasonNumber: Int?

    @State private var isShowingPicker = false

    init(
        date: Binding<Date?>,
        identifier: String = "next-season-date-picker",
        usesDarkAppearance: Bool = false,
        nextSeasonNumber: Int? = nil
    ) {
        _date = date
        self.identifier = identifier
        self.usesDarkAppearance = usesDarkAppearance
        self.nextSeasonNumber = nextSeasonNumber
    }

    var body: some View {
        Button {
            isShowingPicker = true
        } label: {
            HStack(spacing: 8) {
                Text(nextSeasonNumber.map { "第\($0)季待上线" } ?? "下一季预约日期")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 8)
                Text(date.map(AppDateText.monthDay) ?? "选择日期")
                    .foregroundStyle(valueColor)
                Image(systemName: "calendar")
                    .foregroundStyle(valueColor)
            }
            .frame(minHeight: AppLayout.minimumControlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(usesDarkAppearance ? Color.white : Color.primary)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(date.map(AppDateText.monthDay) ?? "未选择")
        .fullScreenCover(isPresented: $isShowingPicker) {
            ZStack {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .onTapGesture { isShowingPicker = false }

                AppointmentCalendarSheet(date: $date, usesDarkAppearance: usesDarkAppearance)
                    .frame(maxWidth: 360, maxHeight: 500)
                    .background(usesDarkAppearance ? Color(uiColor: .secondarySystemBackground) : Color(uiColor: .systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.24), radius: 24, y: 10)
                    .padding(20)
            }
            .presentationBackground(.clear)
        }
    }

    private var valueColor: Color {
        usesDarkAppearance ? Color.white.opacity(0.92) : Color.accentColor
    }
}

private struct AppointmentCalendarSheet: View {
    private static let accent = Color(red: 0.30, green: 0.58, blue: 0.96)

    @Binding var date: Date?
    let usesDarkAppearance: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date
    @State private var displayedMonth: Date

    init(date: Binding<Date?>, usesDarkAppearance: Bool) {
        _date = date
        self.usesDarkAppearance = usesDarkAppearance
        let initialDate = date.wrappedValue ?? .now
        _selectedDate = State(initialValue: initialDate)
        _displayedMonth = State(initialValue: Calendar.current.startOfMonth(for: initialDate))
    }

    private var calendar: Calendar { .autoupdatingCurrent }
    private var monthStart: Date { calendar.startOfMonth(for: displayedMonth) }
    private var monthDayCount: Int { calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30 }
    private var leadingCellCount: Int {
        (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
    }
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let splitIndex = (calendar.firstWeekday - 1) % symbols.count
        return Array(symbols[splitIndex...]) + Array(symbols[..<splitIndex])
    }
    private var monthTitle: String {
        monthStart.formatted(
            Date.FormatStyle()
                .locale(Locale(identifier: "zh_CN"))
                .year()
                .month(.wide)
        )
    }
    private var canShowPreviousMonth: Bool {
        monthStart > calendar.startOfMonth(for: .now)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                HStack {
                    Button {
                        changeMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 44, height: 44)
                    }
                    .disabled(!canShowPreviousMonth)
                    .accessibilityLabel("上个月")
                    .accessibilityIdentifier("appointment-previous-month")

                    Spacer()
                    Text(monthTitle)
                        .font(.headline)
                        .monospacedDigit()
                        .accessibilityIdentifier("appointment-calendar-month")
                    Spacer()

                    Button {
                        changeMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("下个月")
                    .accessibilityIdentifier("appointment-next-month")
                }
                .buttonStyle(.plain)
                .tint(usesDarkAppearance ? Self.accent : Color.accentColor)

                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(weekdaySymbols.indices, id: \.self) { index in
                        Text(weekdaySymbols[index])
                            .font(.caption.weight(.medium))
                            .foregroundStyle(usesDarkAppearance ? Color.white.opacity(0.68) : Color.secondary)
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .accessibilityHidden(true)
                    }

                    ForEach(0..<42, id: \.self) { index in
                        if let dayDate = dateForCell(index) {
                            dayButton(dayDate)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .accessibilityIdentifier("appointment-calendar-days")

                Text("已选择  \(AppDateText.monthDay(selectedDate))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(usesDarkAppearance ? Color.white.opacity(0.92) : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("appointment-selected-date")

            }
            .padding(.horizontal, AppLayout.pageInset)
            .padding(.top, 12)
            .navigationTitle("预约下一季")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定", action: commitSelection)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("appointment-confirm")
                }
                if date != nil {
                    ToolbarItem(placement: .bottomBar) {
                        Button("清除日期", role: .destructive) {
                            date = nil
                            dismiss()
                        }
                    }
                }
            }
            .tint(usesDarkAppearance ? Self.accent : Color.accentColor)
            .preferredColorScheme(usesDarkAppearance ? .dark : nil)
        }
    }

    @ViewBuilder
    private func dayButton(_ dayDate: Date) -> some View {
        let components = calendar.dateComponents([.year, .month, .day], from: dayDate)
        let identifier = String(
            format: "appointment-day-%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        let isSelected = calendar.isDate(selectedDate, inSameDayAs: dayDate)
        let isAvailable = calendar.startOfDay(for: dayDate) >= calendar.startOfDay(for: .now)

        Button {
            selectedDate = calendar.startOfDay(for: dayDate)
        } label: {
            Text("\(components.day ?? 0)")
                .font(.body.weight(isSelected ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(dayTextColor(isSelected: isSelected, isAvailable: isAvailable))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    if isSelected {
                        Circle().fill(usesDarkAppearance ? Self.accent : Color.accentColor)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .accessibilityLabel("\(components.year ?? 0)年\(components.month ?? 0)月\(components.day ?? 0)日")
        .accessibilityValue(isSelected ? "已选" : "未选")
        .accessibilityIdentifier(identifier)
    }

    private func commitSelection() {
        date = calendar.startOfDay(for: selectedDate)
        dismiss()
    }

    private func dayTextColor(isSelected: Bool, isAvailable: Bool) -> Color {
        if isSelected { return .white }
        if !isAvailable { return usesDarkAppearance ? Color.white.opacity(0.28) : Color.secondary.opacity(0.45) }
        return usesDarkAppearance ? .white : .primary
    }

    private func dateForCell(_ index: Int) -> Date? {
        let day = index - leadingCellCount + 1
        guard (1...monthDayCount).contains(day) else { return nil }
        return calendar.date(byAdding: .day, value: day - 1, to: monthStart)
    }

    private func changeMonth(by offset: Int) {
        guard let nextMonth = calendar.date(byAdding: .month, value: offset, to: monthStart) else { return }
        displayedMonth = nextMonth
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        dateInterval(of: .month, for: date)?.start ?? startOfDay(for: date)
    }
}

struct WorkMetric: Identifiable {
    let id: String
    let label: String
    let value: String
    let tint: Color
    let symbol: String
}

struct TextDraftBuffer: Equatable {
    var draft: String
    private(set) var committed: String

    init(_ text: String) {
        draft = text
        committed = text
    }

    mutating func update(_ text: String) {
        draft = text
    }

    mutating func reset(to text: String) {
        draft = text
        committed = text
    }

    mutating func commit() -> String? {
        guard draft != committed else { return nil }
        committed = draft
        return committed
    }
}

struct FixedWorkMetricGrid: View {
    let metrics: [WorkMetric]
    var usesDarkAppearance = false

    var body: some View {
        TagFlowLayout(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(metrics) { metric in
                WorkMetricPill(metric: metric, usesDarkAppearance: usesDarkAppearance)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkMetricPill: View {
    let metric: WorkMetric
    let usesDarkAppearance: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: metric.symbol)
            Text(metric.value)
                .monospacedDigit()
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(usesDarkAppearance ? metric.tint : metric.tint)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(metric.tint.opacity(usesDarkAppearance ? 0.16 : 0.10))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.label) \(metric.value)")
        .accessibilityIdentifier(metric.id)
    }
}
