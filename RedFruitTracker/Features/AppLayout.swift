import CoreGraphics
import SwiftUI

enum AppLayout {
    static let pageInset: CGFloat = 16
    static let sectionSpacing: CGFloat = 16
    static let minimumControlHeight: CGFloat = 44
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
            Text(metric.label)
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
