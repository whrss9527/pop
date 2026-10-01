import AppKit
import SwiftUI
@testable import Pop

/// 媒体信息卡片：文件名和概况（格式、时长、大小、码率），下面按视频、音频、字幕、拍摄信息一组组列出来；
/// 带着拍摄地点时标成橙色，可以去掉位置另存一份。
@MainActor
final class MediaInfoModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case saving
        case saved(URL)
        case failed(String)
    }

    struct Row: Equatable {
        let label: String
        let value: String
        var warning = false
    }

    struct Section: Equatable {
        let title: String
        let rows: [Row]
    }

    let report: MediaInspector.Report
    @Published private(set) var phase: Phase = .idle
    private let strip: (URL) async throws -> URL

    init(report: MediaInspector.Report, strip: @escaping (URL) async throws -> URL = MediaInspector.exportWithoutLocation) {
        self.report = report
        self.strip = strip
    }

    var isAudioOnly: Bool {
        report.video.isEmpty
    }

    /// 「QuickTime · 1:23 · 412 MB · 39.5 Mbps」
    var headline: String {
        var parts = [report.container]
        if report.duration > 0 {
            parts.append(MediaInspector.duration(report.duration))
        }
        parts.append(ByteCountFormatter.string(fromByteCount: report.bytes, countStyle: .file))
        if report.overallBitRate > 0 {
            parts.append(MediaInspector.bitRate(report.overallBitRate))
        }
        return parts.joined(separator: " · ")
    }

    var sections: [Section] {
        var sections: [Section] = []
        for (index, track) in report.video.enumerated() {
            var rows = [Row(label: String(localized: "编码格式"), value: track.codec)]
            var size = "\(String(track.width)) × \(String(track.height))"
            if let name = MediaInspector.resolutionName(width: track.width, height: track.height) {
                size += " · " + name
            }
            rows.append(Row(label: String(localized: "画面"), value: size))
            if track.frameRate > 0 {
                rows.append(Row(label: String(localized: "帧率"), value: String(localized: "\(MediaInspector.frameRate(track.frameRate)) 帧/秒")))
            }
            if track.bitRate > 0 {
                rows.append(Row(label: String(localized: "码率"), value: MediaInspector.bitRate(track.bitRate)))
            }
            rows.append(Row(label: String(localized: "动态范围"), value: track.hdr ?? "SDR"))
            let color = [track.colorPrimaries, track.bitDepth.map { String(localized: "\(String($0)) 位") }].compactMap { $0 }
            if !color.isEmpty {
                rows.append(Row(label: String(localized: "色彩"), value: color.joined(separator: " · ")))
            }
            let title = report.video.count > 1 ? String(localized: "视频 \(String(index + 1))") : String(localized: "视频")
            sections.append(Section(title: title, rows: rows))
        }
        for (index, track) in report.audio.enumerated() {
            var rows = [Row(label: String(localized: "编码格式"), value: track.codec)]
            rows.append(Row(label: String(localized: "声道"),
                            value: MediaInspector.channels(track.channels) + " · " + MediaInspector.sampleRate(track.sampleRate)))
            if track.bitRate > 0 {
                rows.append(Row(label: String(localized: "码率"), value: MediaInspector.bitRate(track.bitRate)))
            }
            if let language = track.language {
                rows.append(Row(label: String(localized: "语言"), value: language))
            }
            let title = report.audio.count > 1 ? String(localized: "音频 \(String(index + 1))") : String(localized: "音频")
            sections.append(Section(title: title, rows: rows))
        }
        if !report.subtitles.isEmpty {
            sections.append(Section(title: String(localized: "字幕"),
                                    rows: [Row(label: String(localized: "语言"), value: report.subtitles.joinedAsList())]))
        }
        var details: [Row] = []
        func add(_ label: String, _ value: String?, warning: Bool = false) {
            if let value { details.append(Row(label: label, value: value, warning: warning)) }
        }
        add(String(localized: "标题"), report.title)
        add(String(localized: "艺人"), report.artist)
        add(String(localized: "专辑"), report.album)
        add(String(localized: "设备"), report.device)
        add(String(localized: "软件"), report.software)
        add(isAudioOnly ? String(localized: "创建时间") : String(localized: "拍摄时间"), report.created.map(Self.format))
        add(String(localized: "拍摄地点"), report.location.map(Self.coordinates), warning: true)
        if !details.isEmpty {
            sections.append(Section(title: String(localized: "信息"), rows: details))
        }
        return sections
    }

    /// 复制用的文字：一组一行
    var text: String {
        var lines = [report.url.lastPathComponent, headline]
        for section in sections {
            lines.append("\(section.title)：" + section.rows.map { "\($0.label) \($0.value)" }.joined(separator: " · "))
        }
        return lines.joined(separator: "\n")
    }

    /// 「31.2304, 121.4737」
    static func coordinates(_ location: MediaInspector.Location) -> String {
        String(format: "%.4f, %.4f", location.latitude, location.longitude)
    }

    static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    /// 在地图里看拍摄地点
    var mapURL: URL? {
        guard let location = report.location else { return nil }
        return URL(string: "https://maps.apple.com/?ll=\(location.latitude),\(location.longitude)&q=\(location.latitude),\(location.longitude)")
    }

    /// 去掉位置另存一份
    func removeLocation() {
        guard phase != .saving else { return }
        phase = .saving
        let url = report.url
        Task {
            do {
                phase = .saved(try await strip(url))
            } catch let failure as MediaInspector.Failure {
                phase = .failed(failure.message)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}

struct MediaInfoView: View {
    @ObservedObject var model: MediaInfoModel
    var artwork: NSImage?
    var onReveal: (URL) -> Void
    var onCopy: () -> Void
    var onOpenMap: (URL) -> Void
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "媒体信息"), subtitle: model.report.url.lastPathComponent, width: 440, onClose: onClose) {
            HStack(spacing: 10) {
                Group {
                    if let artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: model.isAudioOnly ? "music.note" : "film")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.primary.opacity(0.06))
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.report.url.lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(model.headline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(model.sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
                                ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                                    GridRow {
                                        Text(row.label)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 56, alignment: .trailing)
                                        Text(row.value)
                                            .font(.callout)
                                            .foregroundStyle(row.warning ? Color.orange : Color.primary)
                                            .monospacedDigit()
                                            .fixedSize(horizontal: false, vertical: true)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: listHeight)
            if model.report.location != nil {
                locationNote
            }
            HStack(spacing: 8) {
                Spacer()
                Button("在访达中显示") { onReveal(model.report.url) }
                Button("复制信息", action: onCopy)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.small)
    }

    /// 列表的高度：按组数和行数估，最高 380，再多就滚动
    private var listHeight: CGFloat {
        let sections = model.sections
        let rows = sections.reduce(0) { $0 + $1.rows.count }
        return min(CGFloat(sections.count) * 21 + CGFloat(rows) * 21 + CGFloat(max(sections.count - 1, 0)) * 10, 380)
    }

    /// 带着拍摄地点：说明一下，可以在地图里看，或者去掉位置另存一份
    @ViewBuilder
    private var locationNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch model.phase {
            case .idle, .saving:
                Text("这个文件里记着拍摄地点，发给别人前可以去掉")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .saved(let url):
                Text(String(localized: "已另存为「\(url.lastPathComponent)」，画面和声音没有重新编码"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack(spacing: 8) {
                if let map = model.mapURL {
                    Button("在地图中查看") { onOpenMap(map) }
                }
                if case .saved(let url) = model.phase {
                    Button("显示另存的文件") { onReveal(url) }
                } else {
                    Button("去掉位置另存一份") { model.removeLocation() }
                        .disabled(model.phase == .saving)
                    if model.phase == .saving {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
    }
}
