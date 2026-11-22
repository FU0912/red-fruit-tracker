import SwiftUI
import UIKit

struct LibraryTagSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var searchText: String
    let tags: [String]
    @Binding var selectedTags: Set<String>
    let matchingCount: Int

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 8)]
    private let tagColors: [Color] = [.blue, .teal, .orange, .pink, .purple, .indigo, .green]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                searchField

                HStack {
                    Text("标签")
                        .font(.headline)
                    Spacer()
                    Text("\(tags.count) 个")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if tags.isEmpty {
                    ContentUnavailableView(
                        "暂无标签",
                        systemImage: "tag",
                        description: Text("作品的公开标签读取后会显示在这里。")
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(tags, id: \.self) { tag in
                            tagButton(tag, color: tagColors[tags.firstIndex(of: tag).map { $0 % tagColors.count } ?? 0])
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("搜索作品")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") { dismiss() }
                    .fontWeight(.semibold)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Label("匹配 \(matchingCount) 部", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                Spacer(minLength: 8)
                if !selectedTags.isEmpty {
                    Text("已选 \(selectedTags.count) 个")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 54)
            .background(.regularMaterial)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索作品名、简介或 #标签", text: $searchText)
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("library-search-query")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    selectedTags.removeAll()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 32, height: 32)
                .accessibilityLabel("清除文字搜索")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func tagButton(_ tag: String, color: Color) -> some View {
        let isSelected = selectedTags.contains(tag)
        return Button {
            if isSelected {
                selectedTags.remove(tag)
            } else {
                selectedTags.insert(tag)
            }
            searchText = tags
                .filter { selectedTags.contains($0) }
                .map { "#\($0)" }
                .joined(separator: " ")
        } label: {
            ZStack(alignment: .trailing) {
                Text(tag)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)

            }
            .foregroundStyle(isSelected ? Color.white : color)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
                isSelected ? color : color.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(color.opacity(isSelected ? 0.65 : 0.28), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tag-filter-\(tag)")
        .accessibilityLabel(tag)
        .accessibilityValue(isSelected ? "已选择" : "未选择")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
