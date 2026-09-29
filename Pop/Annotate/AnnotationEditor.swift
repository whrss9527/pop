import AppKit
import SwiftUI

/// 截图标注窗口：上面是工具栏，下面是截图，在上面画箭头、方框、文字、马赛克……
/// 完成后复制、存到「下载」或者贴到屏幕上。
@MainActor
final class AnnotationWindowController: NSObject, NSWindowDelegate {
    private static var open: [AnnotationWindowController] = []

    private let window: NSWindow
    private let model: AnnotationModel

    /// 在屏幕中间打开一张截图（太大时缩小显示，合成时仍是原图大小）
    static func present(_ capture: ScreenCapture.Capture, near point: CGPoint) {
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        let scale = max(screen?.backingScaleFactor ?? 2, 1)
        let size = CGSize(width: CGFloat(capture.image.width) / scale, height: CGFloat(capture.image.height) / scale)
        let controller = AnnotationWindowController(model: AnnotationModel(image: capture.image, pointSize: size), screen: screen)
        open.append(controller)
        controller.show()
    }

    private init(model: AnnotationModel, screen: NSScreen?) {
        self.model = model
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let canvas = ScreenGeometry.fitted(model.size, within: CGSize(width: visible.width * 0.85, height: visible.height * 0.8 - 60))
        let contentSize = CGSize(width: max(canvas.width, 560), height: canvas.height + 52)
        window = NSWindow(contentRect: CGRect(origin: .zero, size: contentSize), styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "截图标注"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .floating
        window.contentView = NSHostingView(rootView: AnnotationEditorView(model: model, canvasSize: canvas,
                                                                          onFinish: { [weak self] action in self?.finish(action) }))
        window.setFrameOrigin(CGPoint(x: visible.midX - window.frame.width / 2, y: visible.midY - window.frame.height / 2))
    }

    private func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    enum Action {
        case copy
        case save
        case pin
        case cancel
    }

    private func finish(_ action: Action) {
        guard action != .cancel else {
            window.close()
            return
        }
        guard let png = model.renderPNG() else { return }
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        switch action {
        case .copy:
            PasteboardWriter.copy(png: png)
            PinBoard.shared.onToast?("已复制", center)
        case .save:
            let saved = (try? ImageFiles.saveToDownloads(png, name: ImageFiles.timestampedName("Pop 截图"))) != nil
            PinBoard.shared.onToast?(saved ? "已存到「下载」" : "存储失败", center)
        case .pin:
            if let image = NSImage(data: png) {
                image.size = model.size
                PinBoard.shared.pin(image: image, around: CGPoint(x: window.frame.midX, y: window.frame.midY))
            }
        case .cancel:
            break
        }
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        Self.open.removeAll { $0 === self }
    }
}

struct AnnotationEditorView: View {
    @ObservedObject var model: AnnotationModel
    /// 截图在窗口里显示的大小（点）
    let canvasSize: CGSize
    let onFinish: (AnnotationWindowController.Action) -> Void
    @FocusState private var textFocused: Bool
    /// 这一次拖动已经开始画了
    @State private var drawing = false

    private var scale: CGFloat { canvasSize.width / max(model.size.width, 1) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvas
                .frame(width: canvasSize.width, height: canvasSize.height)
                .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(keyboardShortcuts)
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("工具", selection: $model.tool) {
                ForEach(AnnotationTool.allCases) { tool in
                    Image(systemName: tool.symbol)
                        .help("\(tool.title)（\(String(tool.key).uppercased())）")
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            HStack(spacing: 4) {
                ForEach(AnnotationColor.allCases) { color in
                    Circle()
                        .fill(color.color)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(model.color == color ? 0.9 : 0.2),
                                                       lineWidth: model.color == color ? 2 : 1))
                        .frame(width: 16, height: 16)
                        .onTapGesture { model.color = color }
                }
            }
            Picker("粗细", selection: $model.lineWidth) {
                Text("细").tag(CGFloat(2))
                Text("中").tag(CGFloat(4))
                Text("粗").tag(CGFloat(8))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer(minLength: 4)
            Button {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .help("撤销（⌘Z）")
            .disabled(!model.canUndo && model.textAnchor == nil)
            Button("贴到屏幕") { onFinish(.pin) }
            Button("存储") { onFinish(.save) }
                .help("存到「下载」（⌘S）")
            Button("复制") { onFinish(.copy) }
                .buttonStyle(.borderedProminent)
                .help("复制标注后的图片（⌘C 或回车）")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - 画布

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: model.image, scale: 1)
                .resizable()
                .interpolation(.high)
            if let pixelated = model.pixelated {
                // 马赛克：只露出打码区域里的那部分
                Image(decorative: pixelated, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .mask(mosaicMask)
            }
            Canvas { context, _ in
                context.scaleBy(x: scale, y: scale)
                for annotation in model.annotations + (model.current.map { [$0] } ?? []) {
                    draw(annotation, in: &context)
                }
            }
            if let anchor = model.textAnchor {
                TextField("输入文字，回车完成", text: $model.textDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: AnnotationModel.fontSize(for: model.lineWidth) * scale, weight: .semibold))
                    .foregroundStyle(model.color.color)
                    .frame(width: max(canvasSize.width - anchor.x * scale - 8, 60), alignment: .leading)
                    .offset(x: anchor.x * scale, y: anchor.y * scale)
                    .focused($textFocused)
                    .onSubmit { model.commitText() }
                    .onAppear { textFocused = true }
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !drawing {
                    drawing = true
                    model.begin(at: CGPoint(x: value.startLocation.x / scale, y: value.startLocation.y / scale))
                }
                model.drag(to: CGPoint(x: value.location.x / scale, y: value.location.y / scale))
            }
            .onEnded { _ in
                drawing = false
                model.end()
            })
        .clipped()
    }

    private var mosaicMask: some View {
        Canvas { context, _ in
            context.scaleBy(x: scale, y: scale)
            for annotation in model.annotations + (model.current.map { [$0] } ?? []) where annotation.kind == .mosaic {
                context.fill(Path(annotation.bounds), with: .color(.black))
            }
        }
    }

    private func draw(_ annotation: Annotation, in context: inout GraphicsContext) {
        switch annotation.kind {
        case .mosaic:
            // 打码区域画一圈虚线，方便看出范围（合成时不画）
            context.stroke(Path(annotation.bounds), with: .color(.white.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 1 / scale, dash: [4 / scale]))
        case .text(let text):
            context.draw(Text(text)
                .font(.system(size: AnnotationModel.fontSize(for: annotation.lineWidth), weight: .semibold))
                .foregroundColor(annotation.color.color),
                         at: annotation.start, anchor: .topLeading)
        case .counter(let number):
            let radius = AnnotationModel.counterRadius(for: annotation.lineWidth)
            let circle = CGRect(x: annotation.start.x - radius, y: annotation.start.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: circle), with: .color(annotation.color.color))
            context.draw(Text("\(number)")
                .font(.system(size: radius * 1.1, weight: .bold))
                .foregroundColor(annotation.color.contrasting),
                         at: annotation.start, anchor: .center)
        case .arrow, .rectangle, .ellipse, .pen:
            if let path = annotation.strokePath {
                context.stroke(path, with: .color(annotation.color.color),
                               style: StrokeStyle(lineWidth: annotation.lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
    }

    // MARK: - 键盘

    /// 看不见的按钮，只为了接住快捷键
    private var keyboardShortcuts: some View {
        ZStack {
            Button("") { model.undo() }.keyboardShortcut("z", modifiers: .command)
            Button("") { onFinish(.copy) }.keyboardShortcut("c", modifiers: .command)
            Button("") { onFinish(.save) }.keyboardShortcut("s", modifiers: .command)
            Button("") { onFinish(.cancel) }.keyboardShortcut(.cancelAction)
            if model.textAnchor == nil {
                Button("") { onFinish(.copy) }.keyboardShortcut(.defaultAction)
                ForEach(AnnotationTool.allCases) { tool in
                    Button("") { model.tool = tool }.keyboardShortcut(KeyEquivalent(tool.key), modifiers: [])
                }
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
    }
}
