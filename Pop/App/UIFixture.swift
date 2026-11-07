#if POP_UI_FIXTURE
import AppKit
import SwiftUI

/// 只由 PopUIFixture target 编译；不构造 AppDelegate/AppController，不启动任何系统服务。
@main
@MainActor
enum UIFixtureMain {
    private static var delegate: UIFixtureDelegate?
    static func main() {
        precondition(Bundle.main.bundleIdentifier == "io.github.whrss9527.pop.ui-fixture")
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let owner = UIFixtureDelegate()
        delegate = owner
        app.delegate = owner
        app.run()
    }
}

@MainActor
private final class UIFixtureDelegate: NSObject, NSApplicationDelegate {
    private var window: UIFixtureWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = UIFixtureState()
        let window = UIFixtureWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
                                     styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Pop UI Fixture — isolated / offline"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: UIFixtureView(state: state))
        window.onKey = { [weak state] in state?.handleKey($0) ?? false }
        self.window = window
        let menu = NSMenu()
        let item = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Pop UI Fixture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        menu.addItem(item)
        NSApp.mainMenu = menu
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// 仅处理本窗口送来的事件，不装本地/全局事件监听，也不合成系统输入。
private final class UIFixtureWindow: NSWindow {
    var onKey: ((NSEvent) -> Bool)?
    override func sendEvent(_ event: NSEvent) {
        // 坐标输入框编辑时，方向键和回车属于字段，不应触发菜单选择。
        if firstResponder is NSTextView {
            super.sendEvent(event)
            return
        }
        if event.type == .keyDown, onKey?(event) == true { return }
        super.sendEvent(event)
    }
}

private struct UIFixtureRingParameters: Equatable {
    let screen: CGRect
    let anchor: CGPoint
    let menuBarHeight: CGFloat
    let notch: Bool
    let displayScale: CGFloat
    let dock: Int
    let count: Int
    let longNames: Bool

    var boundary: RingScreenBoundary {
        let dockSize: CGFloat = 56
        let topInset: CGFloat = notch ? 32 : 0
        let top = max(menuBarHeight, topInset)
        let left: CGFloat = dock == 2 ? dockSize : 0
        let right: CGFloat = dock == 3 ? dockSize : 0
        let bottom: CGFloat = dock == 1 ? dockSize : 0
        let visible = CGRect(x: screen.minX + left, y: screen.minY + bottom,
                             width: screen.width - left - right, height: screen.height - top - bottom)
        let notchWidth: CGFloat = 160
        let leftArea = CGRect(x: screen.minX, y: screen.maxY - topInset,
                              width: (screen.width - notchWidth) / 2, height: topInset)
        let rightArea = CGRect(x: screen.midX + notchWidth / 2, y: screen.maxY - topInset,
                               width: (screen.width - notchWidth) / 2, height: topInset)
        return RingScreenBoundary(screenFrame: screen, visibleFrame: visible, topInset: topInset,
                                  auxiliaryTopLeft: leftArea, auxiliaryTopRight: rightArea,
                                  displayScale: displayScale)
    }
}

@MainActor
private final class UIFixtureState: ObservableObject {
    @Published var scene = 0
    @Published var dark = false
    @Published var reduceMotion = false
    @Published var count = 8
    @Published var loading = false
    @Published var backdrop = 0
    @Published var longNames = false
    @Published var screenWidth = 1000.0
    @Published var screenHeight = 650.0
    @Published var anchorX = 500.0
    @Published var anchorY = 325.0
    @Published var menuBarHeight = 28.0
    @Published var notch = false
    @Published var displayScale = 2.0
    @Published var dock = 0
    @Published var showBounds = true
    @Published var showScreenSettings = false
    @Published var showOverflow = false
    @Published private(set) var placementRevision = 0
    @Published var ring: RingViewModel
    @Published var chooser: PluginChooserModel
    @Published var notice = "Actions only update this message; no plug-in is executed."
    @Published var libraryOpen = false
    @Published var libraryMode = 0
    @Published var library: PluginLibraryModel?
    @Published var translationOpen = false
    @Published var translation: TranslationModel?
    let translationBackend = UIFixtureTranslationBackend()
    let presentation = OverlayPresentation(phase: .shown)
    let root: URL
    let defaults: UserDefaults
    let store: SettingsStore
    let pluginStore: PluginStore
    let catalog: [PluginInfo]
    private let session: URLSession
    private var activationCount = 0

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--fixture-root"), arguments.indices.contains(index + 1) {
            root = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        } else {
            root = FileManager.default.temporaryDirectory.appending(path: "PopUIFixture-\(UUID().uuidString)", directoryHint: .isDirectory)
        }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "io.github.whrss9527.pop.ui-fixture.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        store = SettingsStore(defaults: defaults)
        pluginStore = PluginStore(directory: root.appending(path: "Plugins", directoryHint: .isDirectory), defaults: defaults)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UIFixtureURLProtocol.self]
        session = URLSession(configuration: config)
        UIFixtureNetwork.shared.configure(root: root)
        // 只读取描述；不装载插件包、创建插件管理器或执行插件。
        let core = BuiltinPlugins.make().map(\.info)
        let existing = Set(core.map(\.id))
        catalog = core + PluginCatalog.all.compactMap { package in
            guard let id = package.functions.first, !existing.contains(id) else { return nil }
            return PluginInfo(id: id, name: package.name, symbol: package.symbol, summary: package.summary, accepts: [])
        }
        ring = Self.makeRing(Array(catalog.prefix(8)), loading: false)
        chooser = PluginChooserModel(plugins: catalog)
        chooser.onRun = { [weak self] info in self?.selected(info) }
        resetRing()
        print("POP_UI_FIXTURE_ROOT=\(root.path)")
    }

    var ringParameters: UIFixtureRingParameters {
        let width = min(max(screenWidth, 320), 1600)
        let height = min(max(screenHeight, 240), 1000)
        return UIFixtureRingParameters(screen: CGRect(x: 0, y: 0, width: width, height: height),
                                       anchor: CGPoint(x: min(max(anchorX, 0), width), y: min(max(anchorY, 0), height)),
                                       menuBarHeight: min(max(menuBarHeight, 0), 80), notch: notch,
                                       displayScale: displayScale, dock: dock,
                                       count: count, longNames: longNames)
    }

    private static func makeRing(_ entries: [PluginInfo], loading: Bool) -> RingViewModel {
        RingViewModel(layout: RingLayout(slots: entries.map { Optional($0.id) }), catalog: entries,
                      installed: Set(entries.map(\.id)), content: loading ? nil : ContentClassifier.classify(.text("Liquid glass")))
    }

    func resetRing() {
        let parameters = ringParameters
        anchorX = Double(parameters.anchor.x)
        anchorY = Double(parameters.anchor.y)
        screenWidth = Double(parameters.screen.width)
        screenHeight = Double(parameters.screen.height)
        menuBarHeight = Double(parameters.menuBarHeight)
        var entries = Array(catalog.prefix(parameters.count))
        if longNames {
            entries = entries.enumerated().map { index, info in
                PluginInfo(id: info.id, name: index % 2 == 0 ? "Translate selected text into another language" : "选中文字后转换为方便阅读的长名称示例",
                           symbol: info.symbol, summary: info.summary, accepts: info.accepts)
            }
        }
        ring = Self.makeRing(entries, loading: loading)
        let boundary = parameters.boundary
        ring.freezePlacement(anchor: parameters.anchor, safeFrame: boundary.availableFrame,
                             excludedFrames: boundary.excludedFrames, displayScale: boundary.displayScale)
        showOverflow = false
        placementRevision += 1
        notice = "New invocation #\(placementRevision) — production placement / RingMenuView"
    }

    func updateLoading() {
        ring.setLoadingForFixture(loading)
        notice = "Loading changed — same invocation #\(placementRevision), placement stays frozen"
    }

    func activate(_ index: Int) {
        NSApp.keyWindow?.makeFirstResponder(nil)
        if ring.isOverflow(index) {
            ring.overflowSelection = ring.slots.first(where: \.enabled)?.id ?? 0
            showOverflow = true
        } else if let info = ring.selectablePlugin(at: index) {
            ring.commit(index)
            showOverflow = false
            selected(info)
        }
    }

    func openLibrary() {
        let mode = ["slow", "retry", "ready"][libraryMode]
        let url = URL(string: "https://fixture.invalid/\(mode)/index.json")!
        library = PluginLibraryModel(sources: [url], session: session, defaults: defaults)
        libraryOpen = true
    }

    func selected(_ info: PluginInfo) {
        activationCount += 1
        notice = "Selected: \(info.name) [\(info.id)] — activation #\(activationCount)"
    }

    func openTranslation() {
        translation = TranslationModel(text: "Offline translation cancellation fixture", sourceLanguage: "en",
                                       targetLanguage: "zh-Hans", engine: .ai, services: translationBackend.services)
        translationOpen = true
    }

    /// 键盘分发是 fixture 适配器；列表直接复用生产 handleKey，圆盘复用生产选择/移动模型。
    func handleKey(_ event: NSEvent) -> Bool {
        guard !libraryOpen else { return false }
        if scene == 1 { return chooser.handleKey(event) }
        guard scene == 0 else { return false }
        if showOverflow {
            switch event.keyCode {
            case 123, 126:
                ring.overflowSelection = (ring.overflowSelection - 1 + ring.slots.count) % max(ring.slots.count, 1)
                return true
            case 124, 125:
                ring.overflowSelection = (ring.overflowSelection + 1) % max(ring.slots.count, 1)
                return true
            case 36, 76: activate(ring.overflowSelection); return true
            case 53: showOverflow = false; ring.resetSelection(); return true
            default: return false
            }
        }
        switch event.keyCode {
        case 123, 126: ring.setHovered(ring.nextVisibleSlot(by: -1)); return true
        case 124, 125: ring.setHovered(ring.nextVisibleSlot(by: 1)); return true
        case 36, 76:
            if let index = ring.hovered { activate(index) }
            return true
        case 53: ring.resetSelection(); return true
        default: return false
        }
    }

    /// 与生产语言设置一样重开后生效，但只用新进程参数，不写系统或生产 App 偏好。
    func language(_ identifier: String) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--fixture-root", root.path, "-AppleLanguages", "(\(identifier))"]
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if error == nil { NSApp.terminate(nil) }
            }
        }
    }
}

private struct UIFixtureView: View {
    @ObservedObject var state: UIFixtureState
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("Scene", selection: $state.scene) {
                    Text(verbatim: "Ring / 圆盘").tag(0)
                    Text(verbatim: "Features / 全部功能").tag(1)
                    Text(verbatim: "Library / 插件库").tag(2)
                    Text(verbatim: "Translate / 翻译").tag(3)
                }.pickerStyle(.segmented)
                Toggle("Dark", isOn: $state.dark).toggleStyle(.switch)
                Button("中文") { state.language("zh-Hans") }
                Button("English") { state.language("en") }
            }
            Text(verbatim: "Language buttons reopen this fixture. No AppController, clipboard, permissions, cloud, updater, or global event monitors.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            if state.scene == 0 {
                UIFixtureRingScene(state: state)
            } else if state.scene == 1 {
                PluginChooserView(model: state.chooser, onClose: { state.scene = 0 })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.scene == 2 {
                VStack(spacing: 20) {
                    Picker("Fake response", selection: $state.libraryMode) {
                        Text("30 seconds").tag(0)
                        Text("Fail once, then succeed").tag(1)
                        Text("Ready").tag(2)
                    }.frame(width: 360)
                    Button("Open production plugin library") { state.openLibrary() }
                    Text(verbatim: "Only URLProtocol fixtures. Installs write to a temporary plug-in directory; external links are blocked.")
                    Text(verbatim: state.root.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                UIFixtureTranslationScene(state: state, backend: state.translationBackend)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            Text(verbatim: state.notice).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(width: 900, height: 760)
        .preferredColorScheme(state.dark ? .dark : .light)
        .environment(\.openURL, OpenURLAction { _ in .discarded })
        .onChange(of: state.ringParameters) { _, _ in state.resetRing() }
        .onChange(of: state.loading) { _, _ in state.updateLoading() }
        .overlay {
            if state.showOverflow {
                // 仍在同一个隔离窗口内，让窗口自己的键盘适配器处理更多列表。
                ZStack {
                    Color.black.opacity(0.12).contentShape(Rectangle())
                        .onTapGesture { state.showOverflow = false; state.ring.resetSelection() }
                    RingOverflowView(model: state.ring, onSelect: { state.activate($0) },
                                     onBack: { state.showOverflow = false; state.ring.resetSelection() },
                                     onCancel: { state.showOverflow = false; state.ring.resetSelection() },
                                     maxHeight: 500)
                }
            }
        }
        .sheet(isPresented: $state.libraryOpen) {
            if let model = state.library {
                PluginLibraryView(store: state.store, pluginStore: state.pluginStore, model: model,
                                  onClose: { state.libraryOpen = false })
                    .environment(\.openURL, OpenURLAction { _ in .discarded })
            }
        }
    }
}

private struct UIFixtureRingScene: View {
    @ObservedObject var state: UIFixtureState

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Stepper("Slots: \(state.count)", value: $state.count, in: 1...12).frame(width: 130)
                Toggle("Long names", isOn: $state.longNames)
                Toggle("Loading", isOn: $state.loading)
                Toggle("Reduce Motion", isOn: $state.reduceMotion)
                Toggle("Bounds", isOn: $state.showBounds)
                Picker("Backdrop", selection: $state.backdrop) {
                    Text(verbatim: "Blue").tag(0)
                    Text(verbatim: "White").tag(1)
                    Text(verbatim: "Stripes").tag(2)
                }.labelsHidden().frame(width: 90)
                Button("Reset") { state.resetRing() }
            }
            HStack(spacing: 14) {
                scalar("X", value: $state.anchorX, range: 0...state.ringParameters.screen.width)
                scalar("Y", value: $state.anchorY, range: 0...state.ringParameters.screen.height)
            }
            DisclosureGroup(isExpanded: $state.showScreenSettings) {
                VStack(spacing: 6) {
                    HStack(spacing: 14) {
                        scalar("Width", value: $state.screenWidth, range: 320...1600)
                        scalar("Height", value: $state.screenHeight, range: 240...1000)
                    }
                    HStack {
                        scalar("Menu bar", value: $state.menuBarHeight, range: 0...80)
                        Toggle("Notch 160×32", isOn: $state.notch)
                        Picker("Dock", selection: $state.dock) {
                            Text(verbatim: "None").tag(0)
                            Text(verbatim: "Bottom").tag(1)
                            Text(verbatim: "Left").tag(2)
                            Text(verbatim: "Right").tag(3)
                        }.frame(width: 150)
                        Picker("Pixels/pt", selection: $state.displayScale) {
                            Text(verbatim: "1×").tag(1.0)
                            Text(verbatim: "2×").tag(2.0)
                        }.frame(width: 130)
                    }
                }.padding(.top, 4)
            } label: {
                Text(verbatim: "Screen settings · \(Int(state.ringParameters.screen.width))×\(Int(state.ringParameters.screen.height)) pt · \(Int(state.displayScale)) pixels/pt")
                    .font(.caption)
            }
            UIFixtureRingDiagnostics(state: state)
            GeometryReader { proxy in
                let screen = state.ringParameters.screen
                let fit = min(1, min(proxy.size.width / screen.width, proxy.size.height / screen.height))
                UIFixtureRingCanvas(state: state)
                    .frame(width: screen.width, height: screen.height)
                    .scaleEffect(fit, anchor: .topLeading)
                    .frame(width: screen.width * fit, height: screen.height * fit)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            Text(verbatim: "Simulated screen only. X/Y use AppKit points (Y up); Pixels/pt controls geometry precision. Preview is scaled to fit; the desktop, menu bar and Dock stay unchanged.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scalar(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: title).font(.caption).frame(minWidth: 16, alignment: .leading)
            Slider(value: value, in: range).accessibilityLabel(Text(verbatim: "Simulated \(title)"))
            TextField(title, value: value, format: .number.precision(.fractionLength(1)))
                .textFieldStyle(.roundedBorder).frame(width: 64)
                .accessibilityLabel(Text(verbatim: "Simulated \(title) value"))
        }
    }
}

private struct UIFixtureRingDiagnostics: View {
    @ObservedObject var state: UIFixtureState
    var body: some View {
        let parameters = state.ringParameters
        let boundary = parameters.boundary
        let placement = state.ring.placement
        let direct = state.ring.visibleSlots.filter { !$0.isOverflow }.count
        let fits = placement.map { placement in
            (0..<placement.visibleSlotCount).allSatisfy {
                let target = placement.labelFrame($0)
                return boundary.availableFrame.contains(target) && !boundary.excludedFrames.contains { $0.intersects(target) }
            }
        } ?? false
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: String(format: "Invocation #%d · anchor %.1f, %.1f pt / %.1f, %.1f px · direct %d/%d · More %@ · radius %.1f pt · targets contained %@",
                                  state.placementRevision, parameters.anchor.x, parameters.anchor.y,
                                  parameters.anchor.x * parameters.displayScale, parameters.anchor.y * parameters.displayScale,
                                  direct, state.ring.slots.count, placement?.hasOverflow == true ? "yes" : "no",
                                  state.ring.geometry.labelRadius, fits ? "true" : "false"))
            Text(verbatim: String(format: "Screen %.0f×%.0f pt · usable [%.0f, %.0f, %.0f, %.0f] · exclusions %d · hovered %@",
                                  parameters.screen.width, parameters.screen.height,
                                  boundary.availableFrame.minX, boundary.availableFrame.minY,
                                  boundary.availableFrame.width, boundary.availableFrame.height,
                                  boundary.excludedFrames.count, state.ring.hovered.map(String.init) ?? "none"))
        }
        .font(.system(size: 10, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct UIFixtureRingCanvas: View {
    @ObservedObject var state: UIFixtureState
    var body: some View {
        let parameters = state.ringParameters
        let boundary = parameters.boundary
        ZStack(alignment: .topLeading) {
            backdrop
            Color.gray.opacity(0.18)
                .frame(width: parameters.screen.width, height: max(parameters.menuBarHeight, parameters.notch ? 32 : 0))
            if let placement = state.ring.placement {
                RingMenuView(model: state.ring, presentation: state.presentation, reduceMotionOverride: state.reduceMotion)
                    .frame(width: placement.frame.width, height: placement.frame.height)
                    .position(x: placement.frame.midX, y: parameters.screen.maxY - placement.frame.midY)
            }
            Canvas { context, _ in
                func local(_ rect: CGRect) -> CGRect {
                    CGRect(x: rect.minX, y: parameters.screen.maxY - rect.maxY, width: rect.width, height: rect.height)
                }
                context.stroke(Path(parameters.screen), with: .color(.primary.opacity(0.7)), lineWidth: 1)
                context.stroke(Path(local(boundary.availableFrame)), with: .color(.green), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                for excluded in boundary.excludedFrames {
                    context.fill(Path(local(excluded)), with: .color(.black))
                }
                if state.showBounds, let placement = state.ring.placement {
                    for index in 0..<placement.visibleSlotCount {
                        let target = placement.labelFrame(index)
                        let fits = boundary.availableFrame.contains(target) && !boundary.excludedFrames.contains { $0.intersects(target) }
                        context.stroke(Path(local(target)), with: .color(fits ? .green : .red), lineWidth: 0.75)
                    }
                }
                let anchor = CGPoint(x: parameters.anchor.x, y: parameters.screen.maxY - parameters.anchor.y)
                var cross = Path()
                cross.move(to: CGPoint(x: anchor.x - 6, y: anchor.y))
                cross.addLine(to: CGPoint(x: anchor.x + 6, y: anchor.y))
                cross.move(to: CGPoint(x: anchor.x, y: anchor.y - 6))
                cross.addLine(to: CGPoint(x: anchor.x, y: anchor.y + 6))
                context.stroke(cross, with: .color(.orange), lineWidth: 1.5)
            }
            .allowsHitTesting(false)
        }
        .frame(width: parameters.screen.width, height: parameters.screen.height)
        .contentShape(Rectangle())
        .clipped()
        .environment(\.ringBackdropBlending, .withinWindow)
        .onContinuousHover { phase in
            guard !state.showOverflow else { return }
            if case .active(let point) = phase {
                state.ring.updateHover(offset: CGVector(dx: point.x - parameters.anchor.x,
                                                       dy: parameters.screen.maxY - point.y - parameters.anchor.y))
            } else { state.ring.setHovered(nil) }
        }
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
            if let index = state.ring.hovered { state.activate(index) }
        }
    }

    @ViewBuilder private var backdrop: some View {
        if state.backdrop == 1 {
            Color.white
        } else if state.backdrop == 2 {
            Canvas { context, size in
                for column in 0..<Int(ceil(size.width / 32)) {
                    let rect = CGRect(x: CGFloat(column) * 32, y: 0, width: 32, height: size.height)
                    context.fill(Path(rect), with: .color(column.isMultiple(of: 2) ? .black : .white))
                }
            }
        } else {
            LinearGradient(colors: [Color(red: 0.14, green: 0.43, blue: 0.65), Color(red: 0.34, green: 0.68, blue: 0.81)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

/// 保持译文流未完成，既能观察取消，也不会显示生产卡片的朗读/复制等完成后操作。
@MainActor
private final class UIFixtureTranslationBackend: ObservableObject {
    @Published private(set) var active = 0
    private var serial = 0
    private var streams: [Int: AsyncThrowingStream<String, Error>.Continuation] = [:]

    var services: TranslationServices {
        TranslationServices(
            unavailableReason: { engine in engine == .system ? "System translation is disabled in this fixture" : nil },
            translate: { [weak self] engine, _, target in
                guard let self else { throw CancellationError() }
                return await self.openStream(engine, target: target)
            },
            checkSystem: { _, _, _ in .unsupported }
        )
    }

    private func openStream(_ engine: TranslationEngine, target: String) -> AsyncThrowingStream<String, Error> {
        serial += 1
        let id = serial
        let path = "\(id)/\(engine.rawValue)/\(target)"
        UIFixtureNetwork.shared.record("translation.start", path: path)
        return AsyncThrowingStream { continuation in
            streams[id] = continuation
            active = streams.count
            continuation.onTermination = { [weak self] reason in
                let cancelled: Bool
                if case .cancelled = reason { cancelled = true } else { cancelled = false }
                Task { @MainActor [weak self] in
                    guard let self, self.streams.removeValue(forKey: id) != nil else { return }
                    self.active = self.streams.count
                    UIFixtureNetwork.shared.record(cancelled ? "translation.cancel" : "translation.finish", path: path)
                }
            }
            let text = (1...40).map { "Offline fragment \($0): this stream stays open until its consumer is cancelled." }.joined(separator: "\n")
            continuation.yield(text)
        }
    }
}

private struct UIFixtureTranslationScene: View {
    @ObservedObject var state: UIFixtureState
    @ObservedObject var backend: UIFixtureTranslationBackend

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button("Open offline translation") { state.openTranslation() }
                Text(verbatim: "Active fake streams: \(backend.active)")
            }
            Text(verbatim: "The model is retained after Close; view disappearance should still cancel its stream. System engine and all external actions are disabled.")
                .font(.caption).foregroundStyle(.secondary)
            if state.translationOpen, let model = state.translation {
                TranslationCardView(model: model, canReplace: false,
                                    onAction: { _ in state.notice = "Fixture action ignored" }, onDownload: {},
                                    onOpenSettings: { _ in state.notice = "Fixture settings action ignored" },
                                    onClose: { state.translationOpen = false })
            }
        }
    }
}

/// 请求日志只写本 fixture 临时目录；URLProtocol 中所有 URL 都被截获，没有真实传输。
private final class UIFixtureNetwork {
    static let shared = UIFixtureNetwork()
    private let lock = NSLock()
    private var url: URL?
    private var counts: [String: Int] = [:]
    func configure(root: URL) { url = root.appending(path: "requests.log") }
    @discardableResult func record(_ event: String, path: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        if event == "start" { counts[path, default: 0] += 1 }
        if let url {
            let data = Data("\(event) \(path)\n".utf8)
            if !FileManager.default.fileExists(atPath: url.path) { try? data.write(to: url) }
            else if let file = try? FileHandle(forWritingTo: url) {
                try? file.seekToEnd(); try? file.write(contentsOf: data); try? file.close()
            }
        }
        return counts[path, default: 0]
    }
}

private final class UIFixtureURLProtocol: URLProtocol {
    private var pending: DispatchWorkItem?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let count = UIFixtureNetwork.shared.record("start", path: url.path)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if url.path.contains("/retry/"), count == 1 {
                UIFixtureNetwork.shared.record("failure", path: url.path)
                self.client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
                return
            }
            // 用生产模型编码，避免手写字段偏离插件 schema；固定时间使索引和文件响应的校验值一致。
            let summary = "只保存到临时目录，不会执行"
            let englishSummary = "Saved only in the temporary directory; never executed"
            var fixture = PluginManifest(id: "fixture-search", name: "示例搜索", summary: summary,
                                         action: .init(type: .url, template: "https://fixture.invalid/search?q={text}"),
                                         output: .none, modifiedAt: Date(timeIntervalSince1970: 0))
            fixture.localized = ["en": .init(name: "Fixture Search", summary: englishSummary)]
            precondition(fixture.validationError() == nil)
            let manifest = try! PluginManifest.makeEncoder().encode(fixture)
            let index: [String: Any] = ["format": 1, "plugins": [["id": fixture.id, "name": fixture.name, "summary": summary, "author": "UI Fixture", "type": "url", "url": "plugin.json", "sha256": Digests.sha256(manifest), "localized": ["en": ["name": "Fixture Search", "summary": englishSummary]]]]]
            let data = url.lastPathComponent == "index.json" ? (try! JSONSerialization.data(withJSONObject: index)) : manifest
            UIFixtureNetwork.shared.record("response", path: url.path)
            self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        pending = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + (url.path.contains("/slow/") ? 30 : 0.25), execute: work)
    }
    override func stopLoading() {
        pending?.cancel()
        if let url = request.url { UIFixtureNetwork.shared.record("cancel", path: url.path) }
    }
}
#endif
