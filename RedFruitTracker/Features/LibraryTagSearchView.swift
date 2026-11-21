import SwiftUI
import UIKit

struct LibraryTagSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var searchText: String
    let tags: [String]
    @Binding var selectedTags: Set<String>
    let matchingCount: Int

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 10)]

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
                            tagButton(tag)
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
            ToolbarItem(placement: .topBarLeading) {
                Button("清除") {
                    searchText = ""
                    selectedTags.removeAll()
                }
                .disabled(searchText.isEmpty && selectedTags.isEmpty)
            }
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
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除文字搜索")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func tagButton(_ tag: String) -> some View {
        let isSelected = selectedTags.contains(tag)
        return Button {
            if isSelected {
                selectedTags.remove(tag)
            } else {
                selectedTags.insert(tag)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .frame(width: 12)
                    .opacity(isSelected ? 1 : 0)
                Text(tag)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                isSelected ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tag-filter-\(tag)")
        .accessibilityLabel(tag)
        .accessibilityValue(isSelected ? "已选择" : "未选择")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
