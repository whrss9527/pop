import AppKit
import Carbon.HIToolbox

/// 全局快捷键（Carbon RegisterEventHotKey，不需要额外权限）。
@MainActor
final class HotKeyManager {
    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private(set) var current: HotKeyPreset = .none

    func register(_ preset: HotKeyPreset) {
        guard preset != current else { return }
        unregister()
        current = preset
        guard let key = preset.carbonKey else { return }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x504F_5021), id: 1)
        let status = RegisterEventHotKey(key.code, key.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            NSLog("Pop: 注册快捷键失败 (\(status))，可能已被其他 App 占用")
            hotKeyRef = nil
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        current = .none
    }

    fileprivate func handlePress() {
        onPress?()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }
}

extension HotKeyPreset {
    var carbonKey: (code: UInt32, modifiers: UInt32)? {
        switch self {
        case .none: return nil
        case .optionSpace: return (UInt32(kVK_Space), UInt32(optionKey))
        case .commandShiftSpace: return (UInt32(kVK_Space), UInt32(cmdKey | shiftKey))
        case .optionBacktick: return (UInt32(kVK_ANSI_Grave), UInt32(optionKey))
        }
    }
}

private func hotKeyEventHandler(_ nextHandler: EventHandlerCallRef?,
                                _ event: EventRef?,
                                _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    // Carbon 事件在主线程分发
    MainActor.assumeIsolated {
        manager.handlePress()
    }
    return OSStatus(noErr)
}
