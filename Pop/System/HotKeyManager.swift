import AppKit
import Carbon.HIToolbox

/// 全局快捷键（Carbon RegisterEventHotKey，不需要额外权限）。每个用途（唤起圆盘、剪贴板历史）占一个位置。
@MainActor
final class HotKeyManager {
    enum Slot: UInt32, CaseIterable {
        case ring = 1
        case clipboard = 2
    }

    private struct Registration {
        var preset: HotKeyPreset
        var ref: EventHotKeyRef?
        var handler: () -> Void
    }

    private var registrations: [Slot: Registration] = [:]
    private var handlerRef: EventHandlerRef?

    /// 注册（或更换）某个位置的快捷键；preset 为 .none 时取消。返回 false 表示被其他 App 占用了。
    @discardableResult
    func register(_ slot: Slot, preset: HotKeyPreset, handler: @escaping () -> Void) -> Bool {
        if var existing = registrations[slot], existing.preset == preset {
            existing.handler = handler
            registrations[slot] = existing
            return existing.ref != nil || preset == .none
        }
        unregister(slot)
        guard let key = preset.carbonKey else { return true }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x504F_5021), id: slot.rawValue)
        let status = RegisterEventHotKey(key.code, key.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            NSLog("Pop: 注册快捷键 \(preset.title) 失败 (\(status))，可能已被其他 App 占用")
            ref = nil
        }
        registrations[slot] = Registration(preset: preset, ref: ref, handler: handler)
        return ref != nil
    }

    func unregister(_ slot: Slot) {
        if let ref = registrations[slot]?.ref {
            UnregisterEventHotKey(ref)
        }
        registrations[slot] = nil
    }

    func unregisterAll() {
        for slot in Slot.allCases {
            unregister(slot)
        }
    }

    fileprivate func handlePress(id: UInt32) {
        guard let slot = Slot(rawValue: id) else { return }
        registrations[slot]?.handler()
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
        case .commandShiftV: return (UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey))
        case .commandOptionV: return (UInt32(kVK_ANSI_V), UInt32(cmdKey | optionKey))
        case .controlCommandV: return (UInt32(kVK_ANSI_V), UInt32(controlKey | cmdKey))
        case .optionV: return (UInt32(kVK_ANSI_V), UInt32(optionKey))
        }
    }
}

private func hotKeyEventHandler(_ nextHandler: EventHandlerCallRef?,
                                _ event: EventRef?,
                                _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData, let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    // Carbon 事件在主线程分发
    MainActor.assumeIsolated {
        manager.handlePress(id: hotKeyID.id)
    }
    return OSStatus(noErr)
}
