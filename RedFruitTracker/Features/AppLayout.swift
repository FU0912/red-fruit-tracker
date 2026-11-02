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

struct FixedWorkMetricGrid: View {
    let metrics: [WorkMetric]
    var usesDarkAppearance = false

    private let columns = [GridItem(.flexible(minimum: 0), alignment: .leading),
                           GridItem(.flexible(minimum: 0), alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
            ForEach(metrics) { metric in
                HStack(spacing: 6) {
                    Image(systemName: metric.symbol)
                        .font(.caption.weight(.bold))
                    Text(metric.label)
                        .font(.caption.weight(.semibold))
                    Text(metric.value)
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .foregroundStyle(usesDarkAppearance ? Color.white.opacity(0.94) : Color.primary)
                .padding(.horizontal, 9)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .background(metric.tint.opacity(usesDarkAppearance ? 0.24 : 0.14), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(metric.tint.opacity(usesDarkAppearance ? 0.62 : 0.42), lineWidth: 0.8)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(metric.label) \(metric.value)")
                .accessibilityIdentifier(metric.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
