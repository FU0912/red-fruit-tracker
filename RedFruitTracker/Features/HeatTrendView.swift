import Charts
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
        let margin = max((high - low) * 0.15, max(high * 0.02, 1))
        return max(0, low - margin)...(high + margin)
    }

    private var xDomain: ClosedRange<Date> {
        let first = candles.first?.bucket ?? .now
        let last = candles.last?.bucket ?? first
        let step: TimeInterval
        switch interval {
        case .day: step = 86_400
        case .week: step = 7 * 86_400
        case .month: step = 31 * 86_400
        case .quarter: step = 92 * 86_400
        case .year: step = 366 * 86_400
        }
        return first.addingTimeInterval(-step * 0.5)...last.addingTimeInterval(step * 0.5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("官方热度")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("K 线")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.58))
            }

            Picker("统计周期", selection: $interval) {
                Text("日").tag(TrendInterval.day)
                Text("周").tag(TrendInterval.week)
                Text("月").tag(TrendInterval.month)
                Text("季").tag(TrendInterval.quarter)
                Text("年").tag(TrendInterval.year)
            }
            .pickerStyle(.segmented)
            .environment(\.colorScheme, .dark)
            .accessibilityIdentifier("heat-chart-interval")

            if let selected {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Self.number(selected.close))
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(candleColor(selected))
                        Text(selected.bucket.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.62))
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
                .foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity, minHeight: 190)
            }
        }
        .padding(.vertical, AppLayout.sectionSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onChange(of: interval) { _, _ in selectedDate = nil }
        .accessibilityIdentifier("official-trend-section")
    }

    private func sampleValue(_ label: String, _ value: Double) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(.white.opacity(0.55))
            Text(Self.number(value)).foregroundStyle(.white.opacity(0.86))
        }
    }

    private var plot: some View {
        Chart {
            ForEach(candles) { candle in
                RuleMark(
                    x: .value("日期", candle.bucket),
                    yStart: .value("低", candle.low),
                    yEnd: .value("高", candle.high)
                )
                .lineStyle(StrokeStyle(lineWidth: 1.25))
                .foregroundStyle(candleColor(candle))

                if candle.open == candle.close {
                    PointMark(x: .value("日期", candle.bucket), y: .value("热度", candle.close))
                        .symbol {
                            Rectangle()
                                .fill(candleColor(candle))
                                .frame(width: 7, height: 2)
                        }
                } else {
                    BarMark(
                        x: .value("日期", candle.bucket),
                        yStart: .value("开", min(candle.open, candle.close)),
                        yEnd: .value("收", max(candle.open, candle.close)),
                        width: .fixed(candles.count > 30 ? 4 : 8)
                    )
                    .foregroundStyle(candleColor(candle))
                }
            }

            if let selectedDate, let selected {
                RuleMark(x: .value("选中日期", selected.bucket))
                    .foregroundStyle(.white.opacity(0.36))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXSelection(value: $selectedDate)
        .chartLegend(.hidden)
        .chartPlotStyle { $0.clipped() }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel().foregroundStyle(.white.opacity(0.62))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.white.opacity(0.14))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(Self.number(number)).foregroundStyle(.white.opacity(0.62))
                    }
                }
            }
        }
        .frame(height: 190)
        .accessibilityIdentifier("official-heat-chart")
    }

    private func candleColor(_ candle: TrendCandle) -> Color {
        candle.close == candle.open ? .white : candle.close > candle.open ? .green : .red
    }

    private static func number(_ value: Double) -> String {
        if value >= 100_000_000 { return String(format: "%.1f亿", value / 100_000_000) }
        if value >= 10_000 { return String(format: "%.1f万", value / 10_000) }
        return value.formatted(.number.precision(.fractionLength(0)))
    }
}
