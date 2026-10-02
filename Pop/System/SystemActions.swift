import AppKit
import Carbon.HIToolbox
import CoreAudio

/// 系统操作：锁屏、熄屏、睡眠、屏幕保护程序、切换深色和浅色模式、静音、隐藏或显示桌面图标、显示隐藏文件、推出所有磁盘
enum SystemAction: String, CaseIterable, Equatable {
    case lockScreen
    case displaySleep
    case sleep
    case screenSaver
    case toggleDarkMode
    case toggleMute
    case toggleDesktopIcons
    case toggleHiddenFiles
    case ejectAll

    /// App Store 版开了沙盒：改不了访达和系统外观的设置，也让不了 Mac 睡眠、熄屏，这几样不提供
    var isAvailable: Bool {
        guard Distribution.isAppStore else { return true }
        switch self {
        case .displaySleep, .sleep, .toggleDarkMode, .toggleDesktopIcons, .toggleHiddenFiles:
            return false
        case .lockScreen, .screenSaver, .toggleMute, .ejectAll:
            return true
        }
    }
}

enum SystemActions {
    /// 一个挂载的磁盘（推出前判断用）
    struct Volume: Equatable {
        var url: URL
        var isInternal: Bool
        var isEjectable: Bool
        var isRemovable: Bool
        var isLocal: Bool
        var isRoot: Bool
    }

    static let finderDomain = "com.apple.finder"
    static let desktopIconsKey = "CreateDesktop"
    /// 访达里显示以点开头的隐藏文件（⇧⌘. 切换的也是它）
    static let hiddenFilesKey = "AppleShowAllFiles"
    /// 系统外观：深色模式时是 Dark，浅色模式时没有
    static let appearanceKey = "AppleInterfaceStyle"

    /// 系统现在是深色模式
    static func isDarkMode(style: String? = UserDefaults.standard.string(forKey: appearanceKey)) -> Bool {
        style?.lowercased() == "dark"
    }

    /// 桌面上现在显示图标（访达的 CreateDesktop 没设成否）
    static func desktopIconsVisible(in defaults: UserDefaults? = UserDefaults(suiteName: finderDomain)) -> Bool {
        guard let defaults, defaults.object(forKey: desktopIconsKey) != nil else { return true }
        return defaults.bool(forKey: desktopIconsKey)
    }

    /// 访达现在显示隐藏文件（没设置过是不显示）
    static func hiddenFilesShown(in defaults: UserDefaults? = UserDefaults(suiteName: finderDomain)) -> Bool {
        defaults?.bool(forKey: hiddenFilesKey) ?? false
    }

    /// 现在的声音输出静音了没有；输出设备不支持静音时是 nil
    static func isMuted() -> Bool? {
        guard let device = defaultOutputDevice() else { return nil }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = muteAddress
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr else { return nil }
        return muted != 0
    }

    /// 直接用 CoreAudio 设置声音输出静音，成功返回 true。App Store 版用它：沙盒里跑不了 osascript
    static func setMuted(_ muted: Bool) -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var address = muteAddress
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return false }
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// 现在的声音输出设备；没有时是 nil
    private static func defaultOutputDevice() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    /// 能推出的：外接的、可移除的、磁盘映像、网络上的；启动磁盘和内置的不算
    static func isEjectable(_ volume: Volume) -> Bool {
        guard !volume.isRoot else { return false }
        return volume.isEjectable || volume.isRemovable || !volume.isLocal || !volume.isInternal
    }

    /// 现在挂着的、能推出的磁盘
    static func ejectableVolumes() -> [URL] {
        let keys: [URLResourceKey] = [.volumeIsInternalKey, .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsLocalKey,
                                      .volumeIsRootFileSystemKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.filter { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return false }
            return isEjectable(Volume(url: url, isInternal: values.volumeIsInternal ?? true, isEjectable: values.volumeIsEjectable ?? false,
                                      isRemovable: values.volumeIsRemovable ?? false, isLocal: values.volumeIsLocal ?? true,
                                      isRoot: values.volumeIsRootFileSystem ?? false))
        }
    }

    static func title(_ action: SystemAction, desktopIconsVisible: Bool, darkMode: Bool, ejectable: Int,
                      muted: Bool = false, hiddenFilesShown: Bool = false) -> String {
        switch action {
        case .lockScreen: return String(localized: "锁屏")
        case .displaySleep: return String(localized: "熄屏")
        case .sleep: return String(localized: "睡眠")
        case .screenSaver: return String(localized: "屏幕保护程序")
        case .toggleDarkMode: return darkMode ? String(localized: "换成浅色模式") : String(localized: "换成深色模式")
        case .toggleMute: return muted ? String(localized: "取消静音") : String(localized: "静音")
        case .toggleDesktopIcons: return desktopIconsVisible ? String(localized: "隐藏桌面图标") : String(localized: "显示桌面图标")
        case .toggleHiddenFiles: return hiddenFilesShown ? String(localized: "不显示隐藏文件") : String(localized: "显示隐藏文件")
        case .ejectAll: return ejectable > 1 ? String(localized: "推出 \(ejectable) 个磁盘") : String(localized: "推出磁盘")
        }
    }

    /// 「系统操作」卡片：按钮的说法跟着现在的状态变；没有能推出的磁盘时不显示推出
    static func card(desktopIconsVisible: Bool, darkMode: Bool, ejectable: Int, muted: Bool = false, hiddenFilesShown: Bool = false) -> ResultCard {
        let actions = SystemAction.allCases.filter { $0.isAvailable && ($0 != .ejectAll || ejectable > 0) }
        return ResultCard(title: String(localized: "系统操作"), body: "",
                          detail: Distribution.isAppStore
                              ? String(localized: "推出前请先关掉磁盘上打开的文件")
                              : String(localized: "隐藏桌面图标、显示隐藏文件时会重新打开访达；推出前请先关掉磁盘上打开的文件"),
                          buttons: actions.map { action in
                              CardButton(title: title(action, desktopIconsVisible: desktopIconsVisible, darkMode: darkMode, ejectable: ejectable,
                                                      muted: muted, hiddenFilesShown: hiddenFilesShown),
                                         action: .system(action))
                          })
    }

    /// 执行操作，返回要提示的话（锁屏、睡眠这些不用提示）
    @MainActor
    static func run(_ action: SystemAction) async -> String? {
        switch action {
        case .lockScreen:
            // 系统锁屏的快捷键 ⌃⌘Q
            press(kVK_ANSI_Q, flags: [.maskCommand, .maskControl])
            return nil
        case .displaySleep:
            guard let reason = await command("/usr/bin/pmset", ["displaysleepnow"]) else { return nil }
            return reason.isEmpty ? String(localized: "熄屏失败") : String(localized: "熄屏失败：\(reason)")
        case .sleep:
            guard let reason = await command("/usr/bin/pmset", ["sleepnow"]) else { return nil }
            return reason.isEmpty ? String(localized: "睡眠失败") : String(localized: "睡眠失败：\(reason)")
        case .screenSaver:
            let engine = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
            do {
                _ = try await NSWorkspace.shared.openApplication(at: engine, configuration: NSWorkspace.OpenConfiguration())
                return nil
            } catch {
                return String(localized: "打不开屏幕保护程序：\(error.localizedDescription)")
            }
        case .toggleDarkMode:
            // 让 System Events 改系统外观；第一次会问能不能控制 System Events
            let dark = !isDarkMode()
            let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)"
            guard let reason = await command("/usr/bin/osascript", ["-e", script]) else { return nil }
            if reason.contains("-1743") {
                return String(localized: "要先在「系统设置 → 隐私与安全性 → 自动化」里允许 Pop 控制「System Events」")
            }
            return reason.isEmpty ? String(localized: "没能切换深浅色") : String(localized: "没能切换深浅色：\(reason)")
        case .toggleMute:
            // 「set volume」是 AppleScript 自带的命令，不用授权控制别的 App
            let mute = !(isMuted() ?? false)
            if Distribution.isAppStore {
                guard setMuted(mute) else { return String(localized: "没能切换静音") }
                return mute ? String(localized: "已静音") : String(localized: "已取消静音")
            }
            guard let reason = await command("/usr/bin/osascript", ["-e", "set volume output muted \(mute)"]) else {
                return mute ? String(localized: "已静音") : String(localized: "已取消静音")
            }
            return reason.isEmpty ? String(localized: "没能切换静音") : String(localized: "没能切换静音：\(reason)")
        case .toggleHiddenFiles:
            let show = !hiddenFilesShown()
            if let reason = await command("/usr/bin/defaults", ["write", finderDomain, hiddenFilesKey, "-bool", show ? "true" : "false"]) {
                return reason.isEmpty ? String(localized: "改不了访达的设置") : String(localized: "改不了访达的设置：\(reason)")
            }
            // 访达重新打开才会按新的设置显示
            _ = await command("/usr/bin/killall", ["Finder"])
            return show ? String(localized: "访达里显示隐藏文件了，再用一次就不显示") : String(localized: "访达里不再显示隐藏文件")
        case .toggleDesktopIcons:
            let show = !desktopIconsVisible()
            if let reason = await command("/usr/bin/defaults", ["write", finderDomain, desktopIconsKey, "-bool", show ? "true" : "false"]) {
                return reason.isEmpty ? String(localized: "改不了访达的设置") : String(localized: "改不了访达的设置：\(reason)")
            }
            // 访达重新打开才会按新的设置显示桌面
            _ = await command("/usr/bin/killall", ["Finder"])
            return show ? String(localized: "桌面图标又显示出来了") : String(localized: "桌面图标已隐藏，再用一次就显示出来")
        case .ejectAll:
            return await ejectAll()
        }
    }

    private static func ejectAll() async -> String {
        let volumes = ejectableVolumes()
        guard !volumes.isEmpty else { return String(localized: "没有能推出的磁盘") }
        var failures: [String] = []
        for volume in volumes {
            do {
                try await FileManager.default.unmountVolume(at: volume, options: [.allPartitionsAndEjectDisk, .withoutUI])
            } catch {
                failures.append(volume.lastPathComponent)
            }
        }
        if failures.isEmpty {
            let name = volumes[0].lastPathComponent
            return volumes.count == 1 ? String(localized: "已推出「\(name)」") : String(localized: "已推出 \(volumes.count) 个磁盘")
        }
        if failures.count == 1 {
            let name = failures[0]
            return String(localized: "「\(name)」正在使用，推不出来；先关掉上面打开的文件再试")
        }
        let names = failures.joinedAsList()
        return String(localized: "\(failures.count) 个磁盘正在使用，推不出来：\(names)")
    }

    /// 运行系统自带的命令：成功返回 nil，失败返回原因（没有原因时是空字符串）
    private static func command(_ path: String, _ arguments: [String]) async -> String? {
        let result = await ProcessRunner.run(URL(fileURLWithPath: path), arguments: arguments, stdin: nil, environment: [:], timeout: 15)
        switch result {
        case .success(let output) where output.status == 0:
            return nil
        case .success(let output):
            return output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        case .failure(let error):
            return error.message
        }
    }

    /// 按一下组合键
    private static func press(_ keyCode: Int, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let code = CGKeyCode(keyCode)
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
