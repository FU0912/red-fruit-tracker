import SwiftData
import SwiftUI

struct RootView: View {
    @Query(sort: \SeriesRecord.updatedAt, order: .reverse)
    private var series: [SeriesRecord]

    @State private var isShowingImportInfo = false

    var body: some View {
        NavigationStack {
            Group {
                if series.isEmpty {
                    ContentUnavailableView {
                        Label("还没有记录", systemImage: "books.vertical")
                    } description: {
                        Text("从红果漫剧分享一条链接开始")
                    }
                } else {
                    List(series) { item in
                        NavigationLink {
                            SeriesDetailView(series: item)
                        } label: {
                            SeriesRow(series: item)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("漫剧记录")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingImportInfo = true
                    } label: {
                        Label("导入", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .sheet(isPresented: $isShowingImportInfo) {
                ImportInfoView()
                    .presentationDetents([.medium])
            }
        }
    }
}

private struct SeriesRow: View {
    let series: SeriesRecord

    var body: some View {
        HStack(spacing: 12) {
            if let coverURL = series.coverURL, let url = URL(string: coverURL) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.15)
                }
                .frame(width: 56, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 56, height: 76)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(series.title)
                    .font(.headline)
                    .lineLimit(2)
                if !series.tagsText.isEmpty {
                    Text(series.tagsText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SeriesDetailView: View {
    let series: SeriesRecord

    var body: some View {
        List {
            Section("作品") {
                LabeledContent("标题", value: series.title)
                LabeledContent("来源 ID", value: series.sourceSeriesID)
                if let rating = series.officialRating {
                    LabeledContent("官方评分", value: String(format: "%.1f", rating))
                }
                if let heat = series.officialHeatText {
                    LabeledContent("官方热度", value: heat)
                }
            }

            Section("简介") {
                Text(series.intro.isEmpty ? "暂无简介" : series.intro)
                    .foregroundStyle(series.intro.isEmpty ? .secondary : .primary)
            }
        }
        .navigationTitle(series.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ImportInfoView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 42))
                    .foregroundStyle(.tint)
                Text("分享导入入口已准备")
                    .font(.headline)
                Text("下一步会把分享扩展收到的链接写入本地导入队列，再采集公开作品资料。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .navigationTitle("导入")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
