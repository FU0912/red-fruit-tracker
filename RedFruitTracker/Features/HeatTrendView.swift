import Foundation
import SwiftUI

/// Official heat is a cumulative popularity signal. A period line chart and
/// range summary are more honest than inventing stock-style open/close values.
struct OfficialTrendSection: View {
    let snapshots: [OfficialSnapshot]

    @State private var period: HeatChartPeriod = .week
    @State private var selectedDate: Date?

    private var points: [HeatPoint] {
        let heatSnapshots = snapshots.filter { $0.officialHeatScore?.isFinite == true && $0.officialHeatScore! >= 0 }
        guard let latestDate = heatSnapshots.map(\.capturedAt).max() else { return [] }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -(period.windowDays - 1), to: latestDate) ?? latestDate
        let window = heatSnapshots.filter { $0.capturedAt >= start && $0.capturedAt <= latestDate }
        return HeatTrendAggregation.samples(
            from: window,
            granularity: period.granularity,
            value: { $0.officialHeatScore },
            calendar: calendar
        )
    }

    private var selected: HeatPoint? {
        guard let selectedDate else { return points.last }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    private var valueRange: ClosedRange<Double> {
        let low = points.map(\.lowestObserved).min()
        let high = points.map(\.highestObserved).max()
        guard let low, let high else { return 0...1 }
        let span = max(high - low, max(high * 0.08, 1))
        let margin = span * 0.16
        return max(0, low - margin)...(high + margin)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("官方热度")
                    .font(.headline)
                    .foregroundStyle(HeatTrendPalette.primaryText)
                Spacer()
                Text("趋势")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(HeatTrendPalette.secondaryText)
            }

            periodSelector

            if let selected {
                readout(selected)
                plot
            } else {
                ContentUnavailableView(
                    "暂无热度记录",
                    systemImage: "chart.xyaxis.line",
                    description: Text("刷新公开资料后会记录热度变化")
                )
                .foregroundStyle(HeatTrendPalette.primaryText)
                .frame(maxWidth: .infinity, minHeight: 190)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeatTrendPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onChange(of: period) { _, _ in selectedDate = nil }
        .accessibilityIdentifier("official-trend-section")
    }

    private var periodSelector: some View {
        HStack(spacing: 4) {
            ForEach(HeatChartPeriod.allCases) { value in
                Button {
                    period = value
                } label: {
                    Text(value.title)
                        .font(.subheadline.weight(period == value ? .semibold : .regular))
                        .foregroundStyle(period == value ? HeatTrendPalette.primaryText : HeatTrendPalette.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: AppLayout.minimumControlHeight)
                        .background {
                            if period == value { Capsule().fill(HeatTrendPalette.selection) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(period == value ? .isSelected : [])
                .accessibilityLabel("过去\(value.title)")
                .accessibilityIdentifier("heat-chart-interval-\(value.id)")
            }
        }
        .padding(4)
        .background(HeatTrendPalette.controlSurface, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("热度周期")
        .accessibilityIdentifier("heat-chart-interval")
    }

    private func readout(_ point: HeatPoint) -> some View {
        let delta = point.value - (points.first?.value ?? point.value)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.number(point.value))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(HeatTrendPalette.primaryText)
                Text(Self.change(delta))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(delta >= 0 ? HeatTrendPalette.rising : HeatTrendPalette.falling)
                Spacer(minLength: 0)
                Text(Self.dateLabel(point.date, period: period))
                    .font(.caption)
                    .foregroundStyle(HeatTrendPalette.secondaryText)
            }
            HStack(spacing: 16) {
                rangeValue("最高", points.map(\.highestObserved).max() ?? point.value)
                rangeValue("最低", points.map(\.lowestObserved).min() ?? point.value)
                Text("过去\(period.title)").foregroundStyle(HeatTrendPalette.secondaryText)
            }
            .font(.caption.monospacedDigit())
        }
        .accessibilityIdentifier("heat-chart-readout")
    }

    private func rangeValue(_ label: String, _ value: Double) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(HeatTrendPalette.secondaryText)
            Text(Self.number(value)).foregroundStyle(HeatTrendPalette.primaryText)
        }
    }

    private var plot: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let rect = plotRect(in: size)
            let ticks = [valueRange.upperBound, (valueRange.upperBound + valueRange.lowerBound) / 2, valueRange.lowerBound]
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for value in ticks {
                        var grid = Path()
                        let y = yPosition(for: value, in: rect)
                        grid.move(to: CGPoint(x: rect.minX, y: y))
                        grid.addLine(to: CGPoint(x: rect.maxX, y: y))
                        context.stroke(grid, with: .color(HeatTrendPalette.grid), lineWidth: 0.7)
                    }

                    if points.count == 1, let point = points.first {
                        let x = xPosition(for: point.date, in: rect)
                        let y = yPosition(for: point.value, in: rect)
                        context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: .color(HeatTrendPalette.rising))
                    } else if points.count > 1 {
                        var area = linePath(in: rect)
                        area.addLine(to: CGPoint(x: xPosition(for: points.last!.date, in: rect), y: rect.maxY))
                        area.addLine(to: CGPoint(x: xPosition(for: points.first!.date, in: rect), y: rect.maxY))
                        area.closeSubpath()
                        context.fill(area, with: .color(HeatTrendPalette.rising.opacity(0.13)))
                        context.stroke(linePath(in: rect), with: .color(HeatTrendPalette.rising), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        for point in points {
                            let x = xPosition(for: point.date, in: rect)
                            let y = yPosition(for: point.value, in: rect)
                            context.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)), with: .color(HeatTrendPalette.rising))
                        }
                    }

                    if selectedDate != nil, let selected {
                        let x = xPosition(for: selected.date, in: rect)
                        var guide = Path()
                        guide.move(to: CGPoint(x: x, y: rect.minY))
                        guide.addLine(to: CGPoint(x: x, y: rect.maxY))
                        context.stroke(guide, with: .color(HeatTrendPalette.guide), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }

                ForEach(Array(ticks.enumerated()), id: \.offset) { _, value in
                    Text(Self.axisNumber(value))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(HeatTrendPalette.secondaryText)
                        .frame(width: 52, alignment: .leading)
                        .position(x: size.width - 26, y: yPosition(for: value, in: rect))
                }
                ForEach(Array(axisPoints.enumerated()), id: \.element.id) { index, point in
                    Text(Self.dateLabel(point.date, period: period))
                        .font(.caption2)
                        .foregroundStyle(HeatTrendPalette.secondaryText)
                        .frame(width: 62, alignment: axisAlignment(at: index))
                        .position(x: axisLabelX(at: index, point: point, in: rect), y: size.height - 10)
                }
                if points.count == 1 {
                    Text("当前只有 1 次采样")
                        .font(.caption)
                        .foregroundStyle(HeatTrendPalette.secondaryText)
                        .position(x: rect.midX, y: rect.midY + 22)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in selectPoint(at: value.location.x, in: rect) })
        }
        .frame(height: 210)
        .accessibilityIdentifier("official-heat-chart")
    }

    private var axisPoints: [HeatPoint] {
        guard points.count > 2 else { return points }
        return [points.first!, points[points.count / 2], points.last!]
    }

    private func linePath(in rect: CGRect) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() {
            let location = CGPoint(x: xPosition(for: point.date, in: rect), y: yPosition(for: point.value, in: rect))
            if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
        }
        return path
    }

    private func plotRect(in size: CGSize) -> CGRect { CGRect(x: 6, y: 8, width: max(size.width - 64, 1), height: max(size.height - 38, 1)) }

    private func xPosition(for date: Date, in rect: CGRect) -> CGFloat {
        guard let first = points.first?.date, let last = points.last?.date, last > first else { return rect.midX }
        return rect.minX + CGFloat(date.timeIntervalSince(first) / last.timeIntervalSince(first)) * rect.width
    }

    private func yPosition(for value: Double, in rect: CGRect) -> CGFloat {
        let range = valueRange.upperBound - valueRange.lowerBound
        guard range > 0 else { return rect.midY }
        return rect.maxY - CGFloat((value - valueRange.lowerBound) / range) * rect.height
    }

    private func axisAlignment(at index: Int) -> Alignment {
        if axisPoints.count == 1 { return .center }
        if index == 0 { return .leading }
        if index == axisPoints.count - 1 { return .trailing }
        return .center
    }

    private func axisLabelX(at index: Int, point: HeatPoint, in rect: CGRect) -> CGFloat {
        if axisPoints.count == 1 { return xPosition(for: point.date, in: rect) }
        if index == 0 { return rect.minX + 30 }
        if index == axisPoints.count - 1 { return rect.maxX - 30 }
        return xPosition(for: point.date, in: rect)
    }

    private func selectPoint(at x: CGFloat, in rect: CGRect) {
        guard !points.isEmpty else { return }
        selectedDate = points.min { abs(xPosition(for: $0.date, in: rect) - x) < abs(xPosition(for: $1.date, in: rect) - x) }?.date
    }

    private static func number(_ value: Double) -> String {
        if value >= 100_000_000 { return String(format: "%.1f亿", value / 100_000_000) }
        if value >= 10_000 { return String(format: "%.1f万", value / 10_000) }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    private static func change(_ value: Double) -> String { (value >= 0 ? "+" : "") + number(value) }

    private static func axisNumber(_ value: Double) -> String {
        if value >= 100_000_000 { return String(format: "%.1f亿", value / 100_000_000) }
        if value >= 10_000 { return String(format: "%.1f万", value / 10_000) }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    private static func dateLabel(_ date: Date, period: HeatChartPeriod) -> String {
        switch period {
        case .year: return date.formatted(.dateTime.year().month(.abbreviated))
        case .week, .month, .quarter: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

private typealias HeatPoint = HeatTrendSample

private enum HeatChartPeriod: String, CaseIterable, Identifiable {
    case week, month, quarter, year

    var id: String { rawValue }
    var title: String {
        switch self {
        case .week: return "周"
        case .month: return "月"
        case .quarter: return "季"
        case .year: return "年"
        }
    }
    var windowDays: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .year: return 365
        }
    }
    var granularity: HeatTrendGranularity {
        switch self {
        case .week, .month: return .day
        case .quarter: return .week
        case .year: return .month
        }
    }
}

private enum HeatTrendPalette {
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.66)
    static let grid = Color.white.opacity(0.14)
    static let guide = Color.white.opacity(0.46)
    static let surface = Color.white.opacity(0.075)
    static let controlSurface = Color.white.opacity(0.07)
    static let selection = Color.white.opacity(0.16)
    static let rising = Color(uiColor: .systemGreen)
    static let falling = Color(uiColor: .systemRed)
}
