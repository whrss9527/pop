import AppKit
import SwiftUI
@testable import Pop

/// 相似照片卡片：先在后台一张张读（显示进度），读完按「多像」分组；每组留最好的一张，其余勾上，点一下换。
@MainActor
final class SimilarPhotosModel: ObservableObject {
    nonisolated static let sensitivityKey = "pop.similarPhotos.sensitivity"

    enum Phase: Equatable {
        case scanning(done: Int, total: Int)
        case results
        case working
        case done(trashed: Int, freed: Int64, failed: Int)
    }

    let title: String
    @Published private(set) var phase: Phase
    @Published private(set) var photos: [PhotoSimilarity.Photo] = []
    @Published private(set) var groups: [PhotoSimilarity.Group] = []
    /// 要移到废纸篓的
    @Published var marked: Set<URL> = []
    @Published var sensitivity: PhotoSimilarity.Sensitivity {
        didSet {
            UserDefaults.standard.set(sensitivity.rawValue, forKey: Self.sensitivityKey)
            regroup()
        }
    }
    @Published private(set) var thumbnails: [URL: NSImage] = [:]
    /// 图片太多，只看了前面一部分
    @Published private(set) var truncated = false

    private let recycle: ([URL]) async -> [URL]

    init(title: String, photos: [PhotoSimilarity.Photo]? = nil, sensitivity: PhotoSimilarity.Sensitivity? = nil,
         recycle: @escaping ([URL]) async -> [URL]) {
        self.title = title
        self.recycle = recycle
        self.sensitivity = sensitivity ?? UserDefaults.standard.string(forKey: Self.sensitivityKey)
            .flatMap(PhotoSimilarity.Sensitivity.init(rawValue:)) ?? .normal
        phase = .scanning(done: 0, total: 0)
        if let photos {
            self.photos = photos
            phase = .results
            regroup()
        }
    }

    /// 找出图片，一张张读；每读一批更新一次进度
    func scan(_ roots: [URL]) {
        Task {
            let found = await runInBackground { PhotoSimilarity.imageFiles(in: roots) }
            truncated = found.truncated
            phase = .scanning(done: 0, total: found.urls.count)
            var loaded: [PhotoSimilarity.Photo] = []
            for start in stride(from: 0, to: found.urls.count, by: 24) {
                let batch = Array(found.urls[start..<min(start + 24, found.urls.count)])
                loaded += await runInBackground { batch.compactMap(PhotoSimilarity.load) }
                phase = .scanning(done: min(start + 24, found.urls.count), total: found.urls.count)
            }
            photos = loaded
            phase = .results
            regroup()
        }
    }

    private func regroup() {
        groups = PhotoSimilarity.groups(photos, sensitivity: sensitivity)
        // 每组留最好的一张
        marked = Set(groups.flatMap { $0.photos.dropFirst().map(\.url) })
        loadThumbnails()
    }

    private func loadThumbnails() {
        let missing = groups.flatMap { $0.photos.map(\.url) }.filter { thumbnails[$0] == nil }
        guard !missing.isEmpty else { return }
        Task {
            let images: [(URL, CGImage)] = await runInBackground {
                missing.compactMap { url in PhotoSimilarity.thumbnail(url).map { (url, $0) } }
            }
            for (url, image) in images {
                thumbnails[url] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            }
        }
    }

    /// 直接给缩略图（演示用的照片没有文件）
    func setThumbnails(_ images: [URL: CGImage]) {
        for (url, image) in images {
            thumbnails[url] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
    }

    func toggle(_ photo: PhotoSimilarity.Photo) {
        if marked.contains(photo.url) {
            marked.remove(photo.url)
        } else {
            marked.insert(photo.url)
        }
    }

    /// 勾上的一共多大
    var markedBytes: Int64 {
        photos.filter { marked.contains($0.url) }.reduce(0) { $0 + $1.bytes }
    }

    var summary: String {
        guard !groups.isEmpty else {
            return String(localized: "看了 \(photos.count) 张图片，没有找到相似的")
        }
        let count = groups.reduce(0) { $0 + $1.photos.count }
        let size = ByteCountFormatter.string(fromByteCount: markedBytes, countStyle: .file)
        return String(localized: "找到 \(groups.count) 组相似的照片，一共 \(count) 张；勾上的 \(marked.count) 张移到废纸篓能腾出 \(size)")
    }

    func trash() {
        guard phase == .results, !marked.isEmpty else { return }
        let chosen = photos.filter { marked.contains($0.url) }
        phase = .working
        Task {
            let trashed = Set(await recycle(chosen.map(\.url)).map { $0.standardizedFileURL.path(percentEncoded: false) })
            let moved = chosen.filter { trashed.contains($0.url.standardizedFileURL.path(percentEncoded: false)) }
            phase = .done(trashed: moved.count, freed: moved.reduce(0) { $0 + $1.bytes }, failed: chosen.count - moved.count)
        }
    }
}

struct SimilarPhotosView: View {
    @ObservedObject var model: SimilarPhotosModel
    var onReveal: (URL) -> Void
    var onOpenTrash: () -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "相似照片"), subtitle: model.title, width: 480, onClose: onClose) {
            switch model.phase {
            case .scanning(let done, let total):
                VStack(spacing: 8) {
                    ProgressView(value: Double(done), total: Double(max(total, 1)))
                    Text(total == 0 ? String(localized: "正在找图片…") : String(localized: "正在比较 \(done) / \(total) 张"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            case .results, .working:
                results
            case .done(let trashed, let freed, let failed):
                Text(String(localized: "移走了 \(trashed) 张，腾出 \(ByteCountFormatter.string(fromByteCount: freed, countStyle: .file))"))
                    .font(.callout)
                if failed > 0 {
                    Text(String(localized: "有 \(failed) 张没能移到废纸篓"))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button("打开废纸篓", action: onOpenTrash)
                    Button("完成", action: onClose)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var results: some View {
        Picker("多像", selection: $model.sensitivity) {
            ForEach(PhotoSimilarity.Sensitivity.allCases) { sensitivity in
                Text(sensitivity.title).tag(sensitivity)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .disabled(model.phase == .working)
        if !model.groups.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.groups) { group in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(group.photos) { photo in
                                    tile(photo, best: photo.url == group.photos.first?.url)
                                }
                            }
                            .padding(6)
                        }
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                    }
                }
            }
            .frame(height: min(CGFloat(model.groups.count) * 96, 300))
        }
        Text(model.summary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if model.truncated {
            Text(String(localized: "图片太多，只比较了前 \(PhotoSimilarity.limit) 张"))
                .font(.caption)
                .foregroundStyle(.orange)
        }
        HStack(spacing: 8) {
            Spacer()
            if model.phase == .working {
                ProgressView()
                    .controlSize(.small)
            }
            Button(String(localized: "移到废纸篓（\(model.marked.count) 张）")) { model.trash() }
                .disabled(model.marked.isEmpty || model.phase == .working)
        }
    }

    /// 悬停时的说明：文件名、尺寸、大小
    private func tip(_ photo: PhotoSimilarity.Photo) -> String {
        let size = ByteCountFormatter.string(fromByteCount: photo.bytes, countStyle: .file)
        return "\(photo.url.lastPathComponent)\n\(String(photo.width)) × \(String(photo.height)) · \(size)"
    }

    /// 一张：缩略图，勾上要移走的压暗、打个叉；最好的那张标「留着」。点一下换
    private func tile(_ photo: PhotoSimilarity.Photo, best: Bool) -> some View {
        let marked = model.marked.contains(photo.url)
        return Button {
            model.toggle(photo)
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = model.thumbnails[photo.url] {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.primary.opacity(0.08)
                    }
                }
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .opacity(marked ? 0.45 : 1)
                Image(nsImage: marked ? TileBadge.trash : TileBadge.kept)
                    .padding(3)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .bottomLeading) {
                if best && !marked {
                    Image(nsImage: TileBadge.best)
                        .padding(4)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .help(tip(photo))
        .contextMenu {
            Button("在访达中显示") { onReveal(photo.url) }
        }
        .accessibilityLabel(photo.url.lastPathComponent)
    }
}

/// 照片上的角标（打勾、移走、「留着」）先画成图片再放上去：macOS 26 的深色玻璃会把卡片里的形状和文字跟下面的内容叠在一起提亮，
/// 盖在浅色照片上时颜色淡得几乎看不见；画成图片就和照片一样照原样显示
@MainActor
private enum TileBadge {
    static let kept = render(Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 15))
        .foregroundStyle(.white, Color.green))
    static let trash = render(Image(systemName: "trash.circle.fill")
        .font(.system(size: 15))
        .foregroundStyle(.white, Color.red))
    static let best = render(Text("留着")
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Capsule().fill(Color.green)))

    private static func render(_ view: some View) -> NSImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.nsImage ?? NSImage()
    }
}
