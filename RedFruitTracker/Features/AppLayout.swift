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
}

struct FixedWorkMetricGrid: View {
    let metrics: [WorkMetric]
    var usesDarkAppearance = false

    private let columns = [GridItem(.flexible(minimum: 0), alignment: .leading),
                           GridItem(.flexible(minimum: 0), alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 1) {
                    Text(metric.label)
                        .font(.caption2)
                        .foregroundStyle(usesDarkAppearance ? Color.white.opacity(0.56) : Color.secondary)
                    Text(metric.value)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(metric.tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(metric.label) \(metric.value)")
                .accessibilityIdentifier(metric.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
