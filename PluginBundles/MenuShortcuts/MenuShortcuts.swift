import AppKit
import ApplicationServices
@testable import Pop

/// 快捷键一览：用辅助功能读前台 App 菜单栏里的菜单项和快捷键，可以搜索，点一下就执行那个菜单项。
enum MenuShortcuts {
    /// 菜单栏里的一项：标题、快捷键、能不能用、子菜单
    struct Node: Equatable {
        var title: String
        var shortcut: String?
        var enabled: Bool
        var children: [Node] = []
    }

    /// 拍平以后列表里的一行
    struct Item: Equatable, Identifiable {
        /// 从顶层菜单到这一项的标题，比如 ["文件", "导出为", "PDF…"]
        var path: [String]
        var shortcut: String?
        var enabled: Bool

        var id: String { path.joined(separator: "\u{1F}") }
        var title: String { path.last ?? "" }
        /// 在哪个菜单里：「文件 › 导出为」
        var menu: String { path.dropLast().joined(separator: " › ") }
    }

    /// 读得太多太慢：最多这么多层子菜单、这么多项
    static let maxDepth = 3
    static let maxItems = 1500

    // MARK: - 快捷键怎么写

    /// 辅助功能给的特殊键图形（系统菜单用的编号）
    private static let glyphs: [Int: String] = [
        0x02: "⇥", 0x03: "⇤", 0x04: "⌤", 0x09: "␣", 0x0A: "⌦", 0x0B: "↩", 0x0D: "↩", 0x17: "⌫", 0x1B: "⎋", 0x1C: "⌧",
        0x62: "⇞", 0x63: "⇪", 0x64: "←", 0x65: "→", 0x66: "↖", 0x68: "↑", 0x69: "↘", 0x6A: "↓", 0x6B: "⇟",
        0x6F: "F1", 0x70: "F2", 0x71: "F3", 0x72: "F4", 0x73: "F5", 0x74: "F6", 0x75: "F7", 0x76: "F8", 0x77: "F9",
        0x78: "F10", 0x79: "F11", 0x7A: "F12", 0x87: "F13", 0x88: "F14", 0x89: "F15", 0x8C: "⏏",
    ]

    /// 方向键、功能键这些在菜单里是私用区的字符
    private static let functionKeys: [UInt32: String] = [
        0xF700: "↑", 0xF701: "↓", 0xF702: "←", 0xF703: "→",
        0xF704: "F1", 0xF705: "F2", 0xF706: "F3", 0xF707: "F4", 0xF708: "F5", 0xF709: "F6", 0xF70A: "F7", 0xF70B: "F8",
        0xF70C: "F9", 0xF70D: "F10", 0xF70E: "F11", 0xF70F: "F12", 0xF728: "⌦", 0xF729: "↖", 0xF72B: "↘", 0xF72C: "⇞", 0xF72D: "⇟",
    ]

    /// 拼出「⌃⌥⇧⌘K」这样的快捷键。modifiers 是辅助功能给的：第 0 位 ⇧、第 1 位 ⌥、第 2 位 ⌃、第 3 位表示没有 ⌘
    static func shortcut(character: String?, modifiers: Int, glyph: Int?) -> String? {
        let key: String
        if let glyph, let symbol = glyphs[glyph] {
            key = symbol
        } else if let character, let scalar = character.unicodeScalars.first {
            if let name = functionKeys[scalar.value] {
                key = name
            } else if character == " " {
                key = "␣"
            } else if character == "\t" {
                key = "⇥"
            } else if character == "\r" {
                key = "↩"
            } else if scalar.properties.isWhitespace || scalar.value < 0x20 || (0xF700...0xF8FF).contains(scalar.value) {
                return nil
            } else {
                key = character.uppercased()
            }
        } else {
            return nil
        }
        var text = ""
        if modifiers & 4 != 0 { text += "⌃" }
        if modifiers & 2 != 0 { text += "⌥" }
        if modifiers & 1 != 0 { text += "⇧" }
        if modifiers & 8 == 0 { text += "⌘" }
        return text + key
    }

    // MARK: - 拍平、筛选

    /// 拍平成列表，按菜单里的顺序；没有标题的（分隔线）不要，有子菜单的只列子菜单里的项。
    /// 同一个菜单里重名的只留第一个（执行时按标题找，也只能找到第一个）
    static func flatten(_ nodes: [Node]) -> [Item] {
        var items: [Item] = []
        var seen: Set<[String]> = []
        func add(_ nodes: [Node], path: [String]) {
            for node in nodes where !node.title.isEmpty {
                let current = path + [node.title]
                if !node.children.isEmpty {
                    add(node.children, path: current)
                } else if seen.insert(current).inserted {
                    items.append(Item(path: current, shortcut: node.shortcut, enabled: node.enabled))
                }
            }
        }
        add(nodes, path: [])
        return items
    }

    /// 搜索用的关键字：标题（拼音全拼、首字母也行）、所在的菜单、快捷键
    static func searchKeys(for item: Item) -> [String] {
        SearchText.keys(for: item.title) + SearchText.keys(for: item.menu) + (item.shortcut.map { [$0.lowercased()] } ?? [])
    }

    // MARK: - 读菜单栏

    /// 最多读这么久，大的 App 菜单很多、卡住的 App 回得很慢
    static let timeLimit: TimeInterval = 3

    /// 一个菜单项要读的属性，一次读完比一个个读快很多
    private static let itemAttributes = [kAXTitleAttribute, kAXChildrenAttribute, kAXEnabledAttribute,
                                         kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute, kAXMenuItemCmdGlyphAttribute]

    /// 读这个 App 的菜单栏（苹果菜单跳过）；没有辅助功能权限或者读不到时返回空
    static func read(pid: pid_t) -> [Node] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        guard let menuBar = axElement(app, kAXMenuBarAttribute) else { return [] }
        var budget = Budget(items: maxItems, deadline: Date().addingTimeInterval(timeLimit))
        var nodes: [Node] = []
        for top in axElements(menuBar, kAXChildrenAttribute).dropFirst() {
            guard !budget.isSpent else { break }
            guard let title = axString(top, kAXTitleAttribute), !title.isEmpty,
                  let menu = axElements(top, kAXChildrenAttribute).first else { continue }
            let children = menuItems(menu, depth: 1, budget: &budget)
            if !children.isEmpty {
                nodes.append(Node(title: title, shortcut: nil, enabled: true, children: children))
            }
        }
        return nodes
    }

    private struct Budget {
        var items: Int
        let deadline: Date

        var isSpent: Bool { items <= 0 || Date() > deadline }
    }

    private static func menuItems(_ menu: AXUIElement, depth: Int, budget: inout Budget) -> [Node] {
        var nodes: [Node] = []
        for item in axElements(menu, kAXChildrenAttribute) {
            guard !budget.isSpent else { break }
            let values = axValues(item, itemAttributes)
            guard let title = values[0] as? String, !title.isEmpty else { continue }
            budget.items -= 1
            var children: [Node] = []
            if let submenu = (values[1] as? [AXUIElement])?.first {
                // 子菜单太深的不列：只列出子菜单本身的话点了也没用
                guard depth < maxDepth else { continue }
                children = menuItems(submenu, depth: depth + 1, budget: &budget)
                guard !children.isEmpty else { continue }
            }
            let glyph = (values[5] as? NSNumber)?.intValue
            let text = shortcut(character: values[3] as? String, modifiers: (values[4] as? NSNumber)?.intValue ?? 0,
                                glyph: glyph == 0 ? nil : glyph)
            nodes.append(Node(title: title, shortcut: text, enabled: (values[2] as? NSNumber)?.boolValue ?? true, children: children))
        }
        return nodes
    }

    /// 按标题一层层找到这个菜单项，执行它。
    /// 打开对话框的菜单项要等对话框关掉才回话，超时（cannotComplete）也算已经执行了
    @discardableResult
    static func press(pid: pid_t, path: [String]) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        guard let menuBar = axElement(app, kAXMenuBarAttribute) else { return false }
        var container = menuBar
        for (index, title) in path.enumerated() {
            guard let item = axElements(container, kAXChildrenAttribute).first(where: { axString($0, kAXTitleAttribute) == title }) else {
                return false
            }
            if index == path.count - 1 {
                let result = AXUIElementPerformAction(item, kAXPressAction as CFString)
                return result == .success || result == .cannotComplete
            }
            guard let menu = axElements(item, kAXChildrenAttribute).first else { return false }
            container = menu
        }
        return false
    }

    // MARK: - 辅助功能

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    /// 一次读几个属性，按顺序给出；读不到的是 nil
    private static func axValues(_ element: AXUIElement, _ attributes: [String]) -> [CFTypeRef?] {
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, attributes as CFArray, [], &values) == .success,
              let array = values as? [AnyObject], array.count == attributes.count else {
            return attributes.map { axValue(element, $0) }
        }
        var result: [CFTypeRef?] = []
        for value in array {
            // 读不到的属性给的是一个包着错误的 AXValue
            if CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .axError {
                result.append(nil)
            } else {
                result.append(value)
            }
        }
        return result
    }

    private static func axElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = axValue(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func axElements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        (axValue(element, attribute) as? [AXUIElement]) ?? []
    }

    private static func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        axValue(element, attribute) as? String
    }
}
