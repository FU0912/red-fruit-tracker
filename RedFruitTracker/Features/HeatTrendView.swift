import Foundation
import SwiftUI

/// Shows observed official-heat samples as OHLC candles without inventing intraday values.
struct OfficialTrendSection: View {
    let snapshots: [OfficialSnapshot]

    @State private var interval: TrendInterval = .day
    @State private var selectedDate: Date?

    private var candles: [TrendCandle] {
        Array(TrendAggregation.candles(
            from: snapshots,
            interval: interval,
            value: { $0.officialHeatScore }
        ).suffix(60))
    }

    private var selected: TrendCandle? {
        guard let selectedDate else { return candles.last }
        return candles.min {
            abs($0.bucket.timeIntervalSince(selectedDate))
                < abs($1.bucket.timeIntervalSince(selectedDate))
        }
    }

    private var yDomain: ClosedRange<Double> {
        let low = candles.map(\.low).min() ?? 0
        let high = candles.map(\.high).max() ?? 1
        let margin = max((high - low) * 0.15, max(high * 0.025, 1))
        return max(0, low - margin)...(high + margin)
    }

    private var xDomain: ClosedRange<Date> {
        guard let first = candles.first?.bucket, let last = candles.last?.bucket else {
            return Date.now.addingTimeInterval(-43_200)...Date.now.addingTimeInterval(43_200)
        }
        guard candles.count > 1 else {
            let halfStep = intervalDuration * 0.45
            return first.addingTimeInterval(-halfStep)...first.addingTimeInterval(halfStep)
        }

        let firstGap = candles[1].bucket.timeIntervalSince(first)
        let lastGap = last.timeIntervalSince(candles[candles.count - 2].bucket)
        return first.addingTimeInterval(-firstGap * 0.45)...last.addingTimeInterval(lastGap * 0.45)
    }

    private var intervalDuration: TimeInterval {
        switch interval {
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        case .quarter: return 91 * 86_400
        case .year: return 365 * 86_400
        }
    }

    private var xAxisCandles: [TrendCandle] {
        guard candles.count > 2 else { return candles }
        return [candles.first!, candles[candles.count / 2], candles.last!]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("官方热度")
                    .font(.headline)
                    .foregroundStyle(TrendPalette.primaryText)
                Spacer()
                Text("K 线")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TrendPalette.secondaryText)
            }

            intervalSelector

            if let selected {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Self.number(selected.close))
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(candleColor(selected))
                        Text(selected.bucket.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(TrendPalette.secondaryText)
                    }

                    HStack(spacing: 14) {
                        sampleValue("开", selected.open)
                        sampleValue("高", selected.high)
                        sampleValue("低", selected.low)
                        sampleValue("收", selected.close)
                    }
                    .font(.caption.monospacedDigit())

                    plot
                }
                .accessibilityIdentifier("heat-chart-readout")
            } else {
                ContentUnavailableView(
                    "暂无热度记录",
                    systemImage: "chart.xyaxis.line",
                    description: nil
                )
                .foregroundStyle(TrendPalette.primaryText)
                .frame(maxWidth: .infinity, minHeight: 190)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TrendPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onChange(of: interval) { _, _ in selectedDate = nil }
        .accessibilityIdentifier("official-trend-section")
    }

    private var intervalSelector: some View {
        HStack(spacing: 4) {
            ForEach(TrendInterval.allCases) { value in
                Button {
                    interval = value
                } label: {
                    Text(shortTitle(for: value))
                        .font(.subheadline.weight(interval == value ? .semibold : .regular))
                        .foregroundStyle(interval == value ? TrendPalette.primaryText : TrendPalette.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: AppLayout.minimumControlHeight)
                        .background {
                            if interval == value {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(TrendPalette.selection)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(interval == value ? .isSelected : [])
                .accessibilityIdentifier("heat-chart-interval-\(value.id)")
            }
        }
        .padding(4)
        .background(TrendPalette.controlSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("统计周期")
        .accessibilityIdentifier("heat-chart-interval")
    }

    private func shortTitle(for interval: TrendInterval) -> String {
        switch interval {
        case .day: return "日"
        case .week: return "周"
        case .month: return "月"
        case .quarter: return "季"
        case .year: return "年"
        }
    }

    private func sampleValue(_ label: String, _ value: Double) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(TrendPalette.secondaryText)
            Text(Self.number(value)).foregroundStyle(TrendPalette.primaryText)
        }
    }

    private var plot: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let plotRect = plotRect(in: size)
            let ticks = (0...4).map { index in
                yDomain.upperBound - (yDomain.upperBound - yDomain.lowerBound) * Double(index) / 4
            }

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for (index, value) in ticks.enumerated() {
                        let y = yPosition(for: value, in: plotRect)
                        var line = Path()
                        line.move(to: CGPoint(x: plotRect.minX, y: y))
                        line.addLine(to: CGPoint(x: plotRect.maxX, y: y))
                        context.stroke(
                            line,
                            with: .color(index == ticks.count - 1 ? TrendPalette.axis : TrendPalette.grid),
                            lineWidth: 0.7
                        )
                    }

                    for (index, candle) in candles.enumerated() {
                        let x = xPosition(for: candle.bucket, in: plotRect)
                        let highY = yPosition(for: candle.high, in: plotRect)
                        let lowY = yPosition(for: candle.low, in: plotRect)
                        let openY = yPosition(for: candle.open, in: plotRect)
                        let closeY = yPosition(for: candle.close, in: plotRect)
                        let color = candleColor(candle)

                        var wick = Path()
                        wick.move(to: CGPoint(x: x, y: highY))
                        wick.addLine(to: CGPoint(x: x, y: lowY))
                        context.stroke(wick, with: .color(color), lineWidth: 1.2)

                        let bodyHeight = max(abs(closeY - openY), 2)
                        let body = CGRect(
                            x: x - candleWidth(at: index, in: plotRect) / 2,
                            y: min(openY, closeY) - (closeY == openY ? 1 : 0),
                            width: candleWidth(at: index, in: plotRect),
                            height: bodyHeight
                        )
                        context.fill(
                            Path(roundedRect: body, cornerRadius: 1),
                            with: .color(color)
                        )
                    }

                    if let selectedDate, let selected {
                        let x = xPosition(for: selected.bucket, in: plotRect)
                        var guide = Path()
                        guide.move(to: CGPoint(x: x, y: plotRect.minY))
                        guide.addLine(to: CGPoint(x: x, y: plotRect.maxY))
                        context.stroke(
                            guide,
                            with: .color(TrendPalette.guide),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        )
                        let y = yPosition(for: selected.close, in: plotRect)
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)),
                            with: .color(candleColor(selected))
                        )
                    }
                }

                ForEach(Array(ticks.enumerated()), id: \.offset) { _, value in
                    Text(Self.axisNumber(value, step: (yDomain.upperBound - yDomain.lowerBound) / 4))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(TrendPalette.secondaryText)
                        .frame(width: 60, alignment: .leading)
                        .position(x: size.width - 30, y: yPosition(for: value, in: plotRect))
                }

                ForEach(Array(xAxisCandles.enumerated()), id: \.element.id) { index, candle in
                    Text(candle.bucket.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption2)
                        .foregroundStyle(TrendPalette.secondaryText)
                        .frame(width: 64, alignment: axisAlignment(at: index))
                        .position(x: axisLabelX(at: index, candle: candle, in: plotRect), y: size.height - 10)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        selectCandle(at: value.location.x, in: plotRect)
                    }
                    .onEnded { value in
                        if abs(value.translation.width) < 4 && abs(value.translation.height) < 4 {
                            selectCandle(at: value.location.x, in: plotRect)
                        }
                    }
            )
        }
        .frame(height: 210)
        .accessibilityIdentifier("official-heat-chart")
    }

    private func plotRect(in size: CGSize) -> CGRect {
        CGRect(x: 6, y: 10, width: max(size.width - 78, 1), height: max(size.height - 38, 1))
    }

    private func xPosition(for date: Date, in rect: CGRect) -> CGFloat {
        let range = xDomain.upperBound.timeIntervalSince(xDomain.lowerBound)
        guard range > 0 else { return rect.midX }
        let progress = date.timeIntervalSince(xDomain.lowerBound) / range
        return rect.minX + CGFloat(progress) * rect.width
    }

    private func yPosition(for value: Double, in rect: CGRect) -> CGFloat {
        let range = yDomain.upperBound - yDomain.lowerBound
        guard range > 0 else { return rect.midY }
        let progress = (value - yDomain.lowerBound) / range
        return rect.maxY - CGFloat(progress) * rect.height
    }

    private func candleWidth(at index: Int, in rect: CGRect) -> CGFloat {
        guard candles.count > 1 else { return 8 }
        let current = xPosition(for: candles[index].bucket, in: rect)
        let previousGap = index > 0
            ? current - xPosition(for: candles[index - 1].bucket, in: rect)
            : xPosition(for: candles[index + 1].bucket, in: rect) - current
        let nextGap = index < candles.count - 1
            ? xPosition(for: candles[index + 1].bucket, in: rect) - current
            : previousGap
        return max(2, min(14, min(previousGap, nextGap) * 0.58))
    }

    private func axisAlignment(at index: Int) -> Alignment {
        if index == 0 { return .leading }
        if index == xAxisCandles.count - 1 { return .trailing }
        return .center
    }

    private func axisLabelX(at index: Int, candle: TrendCandle, in rect: CGRect) -> CGFloat {
        if index == 0 { return rect.minX + 32 }
        if index == xAxisCandles.count - 1 { return rect.maxX - 32 }
        return xPosition(for: candle.bucket, in: rect)
    }

    private func selectCandle(at x: CGFloat, in rect: CGRect) {
        guard rect.contains(CGPoint(x: x, y: rect.midY)), !candles.isEmpty else { return }
        selectedDate = candles.min {
            abs(xPosition(for: $0.bucket, in: rect) - x)
                < abs(xPosition(for: $1.bucket, in: rect) - x)
        }?.bucket
    }

    private func candleColor(_ candle: TrendCandle) -> Color {
        if candle.close > candle.open { return TrendPalette.rising }
        if candle.close < candle.open { return TrendPalette.falling }
        return TrendPalette.neutral
    }

    private static func number(_ value: Double) -> String {
        if value >= 100_000_000 { return String(format: "%.1f亿", value / 100_000_000) }
        if value >= 10_000 { return String(format: "%.1f万", value / 10_000) }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    private static func axisNumber(_ value: Double, step: Double) -> String {
        let divisor: Double
        let suffix: String
        if abs(value) >= 100_000_000 {
            divisor = 100_000_000
            suffix = "亿"
        } else if abs(value) >= 10_000 {
            divisor = 10_000
            suffix = "万"
        } else {
            divisor = 1
            suffix = ""
        }

        let scaledStep = abs(step / divisor)
        let precision = scaledStep >= 10 ? 0 : scaledStep >= 1 ? 1 : scaledStep >= 0.1 ? 2 : 3
        return String(format: "%.*f", precision, value / divisor) + suffix
    }
}

private enum TrendPalette {
    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.66)
    static let grid = Color.white.opacity(0.15)
    static let axis = Color.white.opacity(0.28)
    static let guide = Color.white.opacity(0.48)
    static let surface = Color.white.opacity(0.075)
    static let controlSurface = Color.white.opacity(0.07)
    static let selection = Color.white.opacity(0.14)
    static let rising = Color(red: 0.42, green: 0.78, blue: 0.56)
    static let falling = Color(red: 0.94, green: 0.48, blue: 0.46)
    static let neutral = Color.white.opacity(0.78)
}
