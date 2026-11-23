import Foundation

enum HeatTrendChartGeometry {
    static func plotRect(in size: CGSize) -> CGRect {
        CGRect(x: 36, y: 8, width: max(size.width - 108, 1), height: max(size.height - 38, 1))
    }

    static func xPosition(for date: Date, first: Date, last: Date, in rect: CGRect) -> CGFloat {
        guard last > first else { return rect.midX }
        let fraction = CGFloat(date.timeIntervalSince(first) / last.timeIntervalSince(first))
        return rect.minX + fraction * rect.width
    }
}
