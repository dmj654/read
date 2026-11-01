import SwiftUI
import UIKit

// MARK: - P3.5 大图分块视图（CATiledLayer）

/// P3.5 大图分块绘制视图：以 `CATiledLayer` 作图层，按需分块重绘，降低超大位图内存压力。
final class TiledImageView: UIView {
    var image: UIImage? {
        didSet { layer.setNeedsDisplay() }
    }
    var tileSize: CGFloat = 512

    override class var layerClass: AnyClass { CATiledLayer.self }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let tiled = layer as? CATiledLayer {
            tiled.tileSize = CGSize(width: tileSize, height: tileSize)
            tiled.levelsOfDetail = 4
            tiled.levelsOfDetailBias = 2
        }
    }

    override func draw(_ rect: CGRect) {
        guard let image, let cg = image.cgImage else { return }
        let bounds = self.bounds
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let drawW = image.size.width * scale
        let drawH = image.size.height * scale
        let origin = CGPoint(x: (bounds.width - drawW) / 2, y: (bounds.height - drawH) / 2)
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.draw(cg, in: CGRect(x: origin.x, y: origin.y, width: drawW, height: drawH))
    }
}

/// P3.5 SwiftUI 包装：超大图（任一维 > 3000pt）走分块渲染，否则普通 `Image`。
struct TiledImage: UIViewRepresentable {
    let image: UIImage
    let tileSize: CGFloat

    func makeUIView(context: Context) -> TiledImageView {
        let v = TiledImageView()
        v.image = image
        v.tileSize = tileSize
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: TiledImageView, context: Context) {
        uiView.image = image
        uiView.tileSize = tileSize
    }
}

// MARK: - P3.5 单页图片（本地数据 / 在线 URL，含缩放与增强）

private struct ComicPageImageView: View {
    let data: Data?
    let url: URL?
    let isLarge: Bool
    @Binding var scale: CGFloat

    var body: some View {
        Group {
            if let data, let ui = UIImage(data: data) {
                if isLarge {
                    TiledImage(image: ui, tileSize: 512)
                } else {
                    Image(uiImage: ui).resizable().scaledToFit()
                }
            } else if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFit()
                    case .failure: Color.red.opacity(0.15)
                    default: ProgressView()
                    }
                }
            } else {
                Color.gray.opacity(0.1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(scale)
        .gesture(
            MagnificationGesture().onChanged { scale = min(max($0, 1), 4) }
        )
    }
}

// MARK: - P3.5 漫画阅读器主视图

struct ComicReaderView: View {
    @State private var vm: ComicReaderViewModel
    var downloader: PageDownloading?

    @State private var scale: CGFloat = 1
    @State private var showSettings = false

    /// P5.2 减弱动态效果：开启后翻页改为无动画直接切换。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 双页模式下的"跨页"索引（每跨两页）。
    @State private var spreadIndex: Int = 0

    init(viewModel: ComicReaderViewModel, downloader: PageDownloading? = nil) {
        _vm = State(initialValue: viewModel)
        self.downloader = downloader
    }

    private var spreads: [[ComicImagePage]] {
        guard case .double = vm.mode else { return [] }
        var result: [[ComicImagePage]] = []
        var i = 0
        while i < vm.pages.count {
            let pair = Array(vm.pages[i..<min(i + 2, vm.pages.count)])
            result.append(pair)
            i += 2
        }
        return result
    }

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView("加载中…")
            } else if vm.pageCount == 0 {
                ContentUnavailableView("没有可显示的页面", systemImage: "photo")
            } else {
                readerContent
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { await vm.load() }
        .brightness(vm.brightness)
        .contrast(vm.enhanceOn ? 1.15 : 1)
        .sheet(isPresented: $showSettings) { settingsSheet }
        .onChange(of: vm.currentIndex) { _ in
            scale = 1
            vm.persistProgress()
        }
        .onChange(of: vm.mode) { _ in scale = 1; spreadIndex = vm.currentIndex / 2 }
    }

    private var title: String {
        switch vm.mode {
        case .single, .double: return "\(vm.currentIndex + 1) / \(vm.pageCount)"
        case .webtoon: return "\(vm.pageCount) 页"
        }
    }

    @ViewBuilder
    private var readerContent: some View {
        switch vm.mode {
        case .single:
            singlePager
        case .double:
            doublePager
        case .webtoon:
            webtoonScroller
        }
    }

    // MARK: 单页翻页（TabView 原生滑动）

    private var singlePager: some View {
        TabView(selection: $vm.currentIndex) {
            ForEach(vm.pages) { page in
                pageView(page).tag(page.index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .transaction { txn in
            if reduceMotion { txn.animation = nil }
        }
    }

    // MARK: 双页跨页

    private var doublePager: some View {
        TabView(selection: $spreadIndex) {
            ForEach(Array(spreads.enumerated()), id: \.offset) { idx, pair in
                HStack(spacing: 0) {
                    ForEach(pair) { page in
                        pageView(page)
                    }
                }
                .tag(idx)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .transaction { txn in
            if reduceMotion { txn.animation = nil }
        }
        .onChange(of: spreadIndex) { _ in vm.goTo(spreadIndex * 2) }
    }

    // MARK: 卷轴长图

    private var webtoonScroller: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(vm.pages) { page in
                    pageView(page)
                        .onAppear { vm.goTo(page.index) }
                }
            }
        }
    }

    // MARK: 通用单页渲染

    @ViewBuilder
    private func pageView(_ page: ComicImagePage) -> some View {
        GeometryReader { geo in
            ComicPageImageView(
                data: localDataIfLocal(page),
                url: remoteURLIfOnline(page),
                isLarge: isLarge(page),
                scale: $scale
            )
            .frame(width: geo.size.width, height: geo.size.height)
        }
        // P5.2 无障碍：图片页无文字可读，用位置与总数播报，避免 VoiceOver 读出空元素。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(page.index + 1) 页，共 \(vm.pageCount) 页")
        .accessibilityAddTraits(.isImage)
    }

    private func localDataIfLocal(_ page: ComicImagePage) -> Data? {
        // 本地容器按索引取位图；在线模式返回 nil（交由 AsyncImage）。
        vm.isLocal ? vm.localPageData(at: page.index) : nil
    }

    private func remoteURLIfOnline(_ page: ComicImagePage) -> URL? {
        vm.isOnline ? vm.resolvedURL(for: page, downloader: downloader) : nil
    }

    private func isLarge(_ page: ComicImagePage) -> Bool {
        guard let data = localDataIfLocal(page), let ui = UIImage(data: data) else { return false }
        return max(ui.size.width, ui.size.height) > 3000
    }

    // MARK: 工具栏

    private var toolbarContent: some ToolbarContent {
        Group {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("阅读模式", selection: $vm.mode) {
                        Text("单页").tag(ComicReaderMode.single)
                        Text("双页").tag(ComicReaderMode.double)
                        Text("卷轴").tag(ComicReaderMode.webtoon)
                    }
                    Button { showSettings = true } label: {
                        Label("画面设置", systemImage: "slider.horizontal.3")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("阅读选项")
                .accessibilityHint("切换单页、双页、卷轴模式，或打开画面设置")
            }
        }
    }

    // MARK: 设置面板（亮度 / 增强）

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("画面") {
                    VStack(alignment: .leading, spacing: Spacing.xs + 2) {
                        Text("亮度")
                        Slider(value: $vm.brightness, in: 0.2...1.5) {
                            Text("亮度")
                        } minimumValueLabel: {
                            Image(systemName: "sun.min")
                        } maximumValueLabel: {
                            Image(systemName: "sun.max")
                        }
                        .accessibilityLabel("画面亮度")
                        .accessibilityValue(A11yLabels.percent((vm.brightness - 0.2) / 1.3))
                    }
                    Toggle("图像增强", isOn: $vm.enhanceOn)
                        .accessibilityHint("提升对比度，适合灰底扫描件")
                }
            }
            .navigationTitle("阅读设置")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { showSettings = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
