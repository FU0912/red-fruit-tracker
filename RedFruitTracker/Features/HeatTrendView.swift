import Foundation
import Charts
import SwiftUI

/// Uses only observed heat samples. A daily sample is not a full-day market feed.
struct OfficialTrendSection: View {
    let snapshots: [OfficialSnapshot]
    @State private var interval: TrendInterval = .day
    @State private var showsCandles = false
    @State private var selectedDate: Date?

    private var candles: [TrendCandle] {
        Array(TrendAggregation.candles(from: snapshots, interval: interval,
                                      value: { $0.officialHeatScore }).suffix(60))
    }

    private var selected: TrendCandle? {
        guard let selectedDate else { return candles.last }
        return candles.min { abs($0.bucket.timeIntervalSince(selectedDate)) < abs($1.bucket.timeIntervalSince(selectedDate)) }
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("官方热度").font(.headline)
                Spacer()
                Menu {
                    Button("走势线", systemImage: "chart.xyaxis.line") { showsCandles = false }
                    Button("蜡烛 K 线", systemImage: "chart.bar.xaxis") { showsCandles = true }
                } label: {
                    Label(showsCandles ? "K 线" : "走势", systemImage: "chevron.down")
                        .font(.subheadline)
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("heat-chart-style")
            }

            Picker("统计周期", selection: $interval) {
                Text("日").tag(TrendInterval.day)
                Text("周").tag(TrendInterval.week)
                Text("月").tag(TrendInterval.month)
                Text("季").tag(TrendInterval.quarter)
                Text("年").tag(TrendInterval.year)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("heat-chart-interval")

            if let selected {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.number(selected.close))
                        .font(.title2.weight(.semibold)).monospacedDigit()
                    Text(selected.bucket.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption).foregroundStyle(.secondary)
                    if showsCandles {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { sampleValues(selected) }
                            VStack(alignment: .leading, spacing: 4) { sampleValues(selected) }
                        }
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .accessibilityIdentifier("heat-chart-readout")

                plot
                Text(showsCandles
                     ? "开、高、低、收仅统计已采集数据；单次采样显示为横线，不补造波动。"
                     : "按住图表查看数值 · 每个周期显示最后一次采集的热度")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("暂未采集到官方热度", systemImage: "chart.xyaxis.line")
                    .font(.subheadline)
                Text("更新公开资料后逐步积累历史。页面未提供热度时保留空缺，不使用官方评分代替。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(Color(uiColor: .label))
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .onChange(of: interval) { _, _ in selectedDate = nil }
        .accessibilityIdentifier("official-trend-section")
    }

    @ViewBuilder private func sampleValues(_ candle: TrendCandle) -> some View {
        Text("开 \(Self.number(candle.open))")
        Text("高 \(Self.number(candle.high))")
        Text("低 \(Self.number(candle.low))")
        Text("收 \(Self.number(candle.close))")
    }

    private var plot: some View {
        Chart {
            ForEach(candles) { candle in
                if showsCandles {
                    RuleMark(x: .value("日期", candle.bucket),
                             yStart: .value("低", candle.low), yEnd: .value("高", candle.high))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(candleColor(candle))
                    if candle.open == candle.close {
                        // A real doji, not an invented high/low to make a thick bar.
                        PointMark(x: .value("日期", candle.bucket), y: .value("热度", candle.close))
                            .symbol { Rectangle().fill(candleColor(candle)).frame(width: 8, height: 2) }
                    } else {
                        BarMark(x: .value("日期", candle.bucket),
                                yStart: .value("开", min(candle.open, candle.close)),
                                yEnd: .value("收", max(candle.open, candle.close)),
                                width: .fixed(candles.count > 30 ? 3 : 7))
                            .foregroundStyle(candleColor(candle))
                    }
                } else {
                    AreaMark(x: .value("日期", candle.bucket),
                             yStart: .value("基线", yDomain.lowerBound), yEnd: .value("热度", candle.close))
                        .foregroundStyle(Color.accentColor.opacity(0.08))
                        .interpolationMethod(.linear)
                    LineMark(x: .value("日期", candle.bucket), y: .value("热度", candle.close))
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.linear)
                    if candles.count == 1 {
                        PointMark(x: .value("日期", candle.bucket), y: .value("热度", candle.close))
                            .foregroundStyle(Color.accentColor).symbolSize(28)
                    }
                }
            }
            if selectedDate != nil, let selected {
                RuleMark(x: .value("选中日期", selected.bucket))
                    .foregroundStyle(Color.secondary.opacity(0.6))
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
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Color(uiColor: .separator).opacity(0.5))
                AxisValueLabel {
                    if let number = value.as(Double.self) { Text(Self.number(number)) }
                }
            }
        }
        .frame(height: 200)
        .accessibilityIdentifier("official-heat-chart")
    }

    private func candleColor(_ candle: TrendCandle) -> Color {
        candle.close == candle.open ? .secondary : candle.close > candle.open ? .red : .green
    }

    private static func number(_ value: Double) -> String {
        if value >= 100_000_000 { return String(format: "%.1f亿", value / 100_000_000) }
        if value >= 10_000 { return String(format: "%.1f万", value / 10_000) }
        return value.formatted(.number.precision(.fractionLength(0)))
    }
}
