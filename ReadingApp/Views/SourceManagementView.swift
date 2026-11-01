import SwiftUI
import SwiftData

/// P1.1/P1.9 书源管理页：列表、启停开关、删除、粘贴 JSON 导入。
/// P5.2 无障碍：开关补齐可朗读标签（名称 + 类型 + 启用态），导入按钮与文本域提供明确提示。
struct SourceManagementView: View {
    @State private var repository: SourceRepository
    @State private var sources: [SourceRule] = []
    @State private var showingImport = false
    @State private var importText = ""

    init(repository: SourceRepository) { _repository = State(initialValue: repository) }

    var body: some View {
        NavigationStack {
            List {
                if sources.isEmpty {
                    ContentUnavailableView("还没有书源", systemImage: "server.rack",
                                           description: Text("点右上角按钮粘贴 Legado 书源 JSON 导入"))
                }
                ForEach(sources) { source in
                    HStack(spacing: Spacing.s) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.name)
                                .lineLimit(2)
                            Text(source.type == .novel ? "小说" : "漫画")
                                .font(.caption)
                                .foregroundStyle(Palette.secondaryText)
                        }
                        Spacer(minLength: Spacing.s)
                        Toggle("启用", isOn: binding(for: source))
                            .labelsHidden()
                            .accessibilityLabel("\(source.name)，\(source.type == .novel ? "小说" : "漫画")书源")
                            .accessibilityHint(source.enabled ? "当前已启用，双击停用" : "当前已停用，双击启用")
                    }
                    .accessibilityElement(children: .contain)
                }
                .onDelete { indices in
                    for i in indices { try? repository.delete(sources[i]) }
                    refresh()
                }
            }
            .navigationTitle("书源")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingImport = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("导入书源")
                    .accessibilityHint("粘贴 Legado 书源 JSON 后导入")
                }
            }
            .task { refresh() }
            .sheet(isPresented: $showingImport) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("粘贴 Legado 书源 JSON 后导入：")
                            .font(.caption)
                        TextEditor(text: $importText)
                            .border(Palette.secondaryText)
                            .padding(.horizontal, Spacing.xs)
                            .accessibilityLabel("书源 JSON 内容")
                        Button("导入") {
                            if let data = importText.data(using: .utf8) {
                                try? repository.importSource(json: data)
                                importText = ""
                                showingImport = false
                                refresh()
                            }
                        }
                        .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityHint("解析并保存以上 JSON，内容为空时不可用")
                    }
                    .padding()
                    .navigationTitle("导入书源")
                }
            }
        }
    }

    private func refresh() { sources = (try? repository.allSources()) ?? [] }

    private func binding(for source: SourceRule) -> Binding<Bool> {
        Binding(get: { source.enabled }, set: { newValue in
            try? repository.toggle(source, enabled: newValue)
            refresh()
        })
    }
}
