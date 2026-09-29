import AppKit
import Carbon.HIToolbox

/// 全局快捷键（Carbon RegisterEventHotKey，不需要额外权限）。唤起圆盘、剪贴板历史各占一个位置；
/// 给功能设置的快捷键从 100 开始编号。
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

    private static let pluginIDBase: UInt32 = 100
    private var pluginRegistrations: [UInt32: (pluginID: String, ref: EventHotKeyRef?)] = [:]
    private var registeredPluginHotKeys: [PluginHotKey] = []
    private var pluginHandler: ((String) -> Void)?
    /// 注册失败（多半是被其他 App 占用了）的功能
    private(set) var failedPluginIDs: Set<String> = []

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
        unregisterPluginHotKeys()
    }

    /// 注册功能的快捷键（和上次一样就不动）。按下时用功能的 ID 调用 handler。
    func registerPluginHotKeys(_ hotKeys: [PluginHotKey], handler: @escaping (String) -> Void) {
        pluginHandler = handler
        guard hotKeys != registeredPluginHotKeys else { return }
        unregisterPluginHotKeys()
        registeredPluginHotKeys = hotKeys
        guard !hotKeys.isEmpty else { return }
        installHandlerIfNeeded()
        for (index, hotKey) in hotKeys.enumerated() {
            let id = Self.pluginIDBase + UInt32(index)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(hotKey.key.keyCode, hotKey.key.modifiers,
                                             EventHotKeyID(signature: OSType(0x504F_5021), id: id),
                                             GetApplicationEventTarget(), 0, &ref)
            if status != noErr {
                NSLog("Pop: 注册快捷键 \(hotKey.key.display) 失败 (\(status))，可能已被其他 App 占用")
                failedPluginIDs.insert(hotKey.pluginID)
                ref = nil
            }
            pluginRegistrations[id] = (hotKey.pluginID, ref)
        }
    }

    private func unregisterPluginHotKeys() {
        for registration in pluginRegistrations.values {
            if let ref = registration.ref {
                UnregisterEventHotKey(ref)
            }
        }
        pluginRegistrations = [:]
        registeredPluginHotKeys = []
        failedPluginIDs = []
    }

    fileprivate func handlePress(id: UInt32) {
        if let slot = Slot(rawValue: id) {
            registrations[slot]?.handler()
        } else if let registration = pluginRegistrations[id] {
            pluginHandler?(registration.pluginID)
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }
}

extension HotKeyPreset {
    /// 和功能快捷键比较是否重复
    var keyCombo: KeyCombo? {
        carbonKey.map { KeyCombo(keyCode: $0.code, modifiers: $0.modifiers) }
    }

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
