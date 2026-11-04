import SwiftUI
import WidgetKit

private struct RecentSeriesEntry: TimelineEntry {
    let date: Date
    let items: [RecentSeriesWidgetItem]
}

private struct RecentSeriesProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentSeriesEntry {
        RecentSeriesEntry(date: .now, items: [
            RecentSeriesWidgetItem(id: "placeholder", title: "最近添加的漫剧", coverURL: nil, officialRating: nil, officialHeatText: nil)
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentSeriesEntry) -> Void) {
        completion(RecentSeriesEntry(date: .now, items: RecentSeriesWidgetStore.items()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentSeriesEntry>) -> Void) {
        let entry = RecentSeriesEntry(date: .now, items: RecentSeriesWidgetStore.items())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60 * 60))))
    }
}

@main
struct RecentSeriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecentSeriesWidget", provider: RecentSeriesProvider()) { entry in
            RecentSeriesWidgetView(entry: entry)
        }
        .configurationDisplayName("最近添加")
        .description("显示最近添加的漫剧记录。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct RecentSeriesWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: RecentSeriesEntry

    var body: some View {
        Group {
            if family == .systemSmall {
                smallWidget
            } else {
                mediumWidget
            }
        }
        .containerBackground(Color.secondary.opacity(0.08), for: .widget)
    }

    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("最近添加")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let item = entry.items.first {
                HStack(alignment: .center, spacing: 10) {
                    WidgetCover(url: item.coverURL)
                        .frame(width: 54, height: 76)
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("还没有记录", systemImage: "books.vertical")
                    .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var mediumWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近添加")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if entry.items.isEmpty {
                Text("添加作品后会显示在这里")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(entry.items.prefix(3)) { item in
                    HStack(spacing: 8) {
                        WidgetCover(url: item.coverURL)
                            .frame(width: 24, height: 32)
                        Text(item.title)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let rating = item.officialRating {
                            Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        if let heat = item.officialHeatText, !heat.isEmpty {
                            Label(heat.replacingOccurrences(of: "热度", with: ""), systemImage: "flame.fill")
                                .font(.caption2)
                                .foregroundStyle(.pink)
                        }
                    }
                    .frame(height: 34)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
    }
}

private struct WidgetCover: View {
    let url: String?

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.secondary.opacity(0.15))
                .overlay { Image(systemName: "film").foregroundStyle(.secondary) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
