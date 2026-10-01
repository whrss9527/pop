import AppKit
import SwiftUI
@testable import Pop

/// 白噪音卡片：五种声音一排，点一下就放，再点一下暂停；下面是音量和定时停止。
/// 关掉卡片也接着放，菜单栏的耳机图标可以暂停、停止
struct FocusSoundsView: View {
    @ObservedObject var player: FocusSoundPlayer
    var onClose: () -> Void

    var body: some View {
        CardContainer(title: String(localized: "白噪音"), subtitle: subtitle, width: 400, onClose: onClose) {
            HStack(spacing: 6) {
                ForEach(FocusSound.allCases) { sound in
                    SoundTile(sound: sound, isSelected: sound == player.sound,
                              isPlaying: sound == player.sound && player.state == .playing) {
                        player.select(sound)
                    }
                }
            }
            Text(player.sound.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Slider(value: $player.volume, in: 0...1)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            }
            .help("音量")
            if let message = player.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("关掉卡片也接着放，菜单栏的耳机图标可以暂停、停止")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Picker("定时停止", selection: Binding(get: { player.timerMinutes }, set: { player.setTimer($0) })) {
                    ForEach(FocusSoundPlayer.timerChoices, id: \.self) { minutes in
                        Text(FocusSoundPlayer.timerTitle(minutes)).tag(minutes)
                    }
                }
                .fixedSize()
                if let remaining = player.remainingText {
                    Text(remaining)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                if player.state != .stopped {
                    Button("停止") { player.stop() }
                }
                Button(player.state == .playing ? String(localized: "暂停") : String(localized: "播放")) {
                    player.togglePlay()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.small)
    }

    private var subtitle: String? {
        switch player.state {
        case .playing:
            return String(localized: "播放中")
        case .paused:
            return String(localized: "已暂停")
        case .stopped:
            return nil
        }
    }
}

/// 一种声音：图标和名字。选中的带底色，正在放的图标一直在动
private struct SoundTile: View {
    let sound: FocusSound
    let isSelected: Bool
    let isPlaying: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: sound.symbol)
                    .font(.system(size: 18))
                    .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                    .frame(height: 22)
                Text(sound.title)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .padding(.vertical, 8)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(hovering ? 0.08 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(sound.detail)
    }
}
