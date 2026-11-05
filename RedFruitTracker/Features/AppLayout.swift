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
        date.formatted(
            Date.FormatStyle()
                .locale(Locale(identifier: "zh_CN"))
                .month(.defaultDigits)
                .day(.defaultDigits)
        )
    }
}

struct OptionalDatePickerRow: View {
    @Binding private var date: Date?
    private let identifier: String
    private let usesDarkAppearance: Bool

    @State private var isShowingPicker = false
    @State private var draftDate = Date.now

    init(
        date: Binding<Date?>,
        identifier: String = "next-season-date-picker",
        usesDarkAppearance: Bool = false
    ) {
        _date = date
        self.identifier = identifier
        self.usesDarkAppearance = usesDarkAppearance
    }

    var body: some View {
        Button {
            draftDate = date ?? .now
            isShowingPicker = true
        } label: {
            HStack(spacing: 8) {
                Text("下一季预约日期")
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
        .sheet(isPresented: $isShowingPicker) {
            NavigationStack {
                DatePicker(
                    "预约日期",
                    selection: $draftDate,
                    in: Date.now...Date.distantFuture,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(.horizontal, 8)
                .navigationTitle("预约下一季")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { isShowingPicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            date = draftDate
                            isShowingPicker = false
                        }
                    }
                    if date != nil {
                        ToolbarItem(placement: .bottomBar) {
                            Button("清除日期", role: .destructive) {
                                date = nil
                                isShowingPicker = false
                            }
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var valueColor: Color {
        usesDarkAppearance ? Color.white.opacity(0.68) : Color.accentColor
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
