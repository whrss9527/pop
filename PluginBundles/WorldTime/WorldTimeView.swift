import AppKit
import SwiftUI
@testable import Pop

/// 「时区换算」卡片的状态：列出哪些城市、看的是哪个时刻、用滑块往前往后挪了多少
@MainActor
final class WorldTimeModel: ObservableObject {
    static let citiesKey = "pop.worldTime.cities"
    /// 滑块最多往前、往后挪一天，一格 15 分钟
    static let shiftLimit = 1440
    static let shiftStep = 15

    struct Row: Identifiable, Equatable {
        let id: String
        let city: WorldTime.City
        let isLocal: Bool
        /// 选中的文字里写的就是这个时区
        let isSource: Bool
        /// 在常用城市里（可以移除）；选中的时区不在常用城市里时临时多一行，可以加进去
        let isSaved: Bool
        /// 「21:00」
        let time: String
        /// 「10月2日周五」
        let date: String
        /// 比本地早一天是 -1，晚一天是 +1
        let dayOffset: Int
        /// 「UTC−7 · PDT」
        let detail: String
        /// 那里是一天里的第几分钟，画时间条用
        let minuteOfDay: Int
    }

    @Published private(set) var cityIDs: [String] {
        didSet {
            savedCities = cityIDs.compactMap(WorldTime.city(id:))
            defaults?.set(cityIDs, forKey: Self.citiesKey)
        }
    }
    @Published var shiftMinutes = 0
    @Published var search = ""
    @Published var isAdding = false
    /// 不挪的时候看的时刻：选中的时间，或者现在（开着时每 15 秒更新）
    @Published private(set) var base: Date

    let parsed: WorldTime.Parsed?
    /// 选中了文字，但是没认出里面的时间
    let unrecognized: Bool
    let local: TimeZone
    /// 选中的文字，显示在卡片上时截短
    let selectionText: String?
    /// 选中的文字里写了时区：代表那个时区的城市
    let sourceCity: WorldTime.City?
    let localCity: WorldTime.City
    private(set) var savedCities: [WorldTime.City]
    private let now: () -> Date
    private let defaults: UserDefaults?
    private let usesTimers: Bool
    private var timer: Timer?
    private var overlapCache: (key: String, value: DateInterval?)?

    /// cityIDs 不为 nil 时用这几个城市、不存设置（演示和测试用）
    init(text: String? = nil, now: @escaping () -> Date = Date.init, local: TimeZone = .current,
         defaults: UserDefaults? = .standard, cityIDs: [String]? = nil, usesTimers: Bool = true) {
        let current = now()
        let parsed = text.flatMap { WorldTime.parse($0, now: current, local: local) }
        self.parsed = parsed
        unrecognized = parsed == nil && !(text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.now = now
        self.local = local
        self.defaults = cityIDs == nil ? defaults : nil
        self.usesTimers = usesTimers
        let ids = cityIDs ?? (defaults?.stringArray(forKey: Self.citiesKey) ?? WorldTime.defaultCityIDs)
        self.cityIDs = ids
        savedCities = ids.compactMap(WorldTime.city(id:))
        base = parsed?.hasTime == true ? parsed?.date ?? current : Self.wholeMinute(current)
        sourceCity = parsed?.hasZone == true ? parsed.map { WorldTime.representative(for: $0.zone, at: $0.date) } : nil
        localCity = WorldTime.representative(for: local, at: current)
        selectionText = parsed == nil ? nil : text.map(Self.shorten)
    }

    /// 没认出选中的时间：看的是现在，跟着走
    var followsNow: Bool { parsed?.hasTime != true }

    var instant: Date {
        base.addingTimeInterval(TimeInterval(shiftMinutes * 60))
    }

    var rows: [Row] {
        let instant = self.instant
        let sourceZone = parsed?.hasZone == true ? parsed?.zone : nil
        var result: [Row] = []
        // 选中的时区不在常用城市里：临时放在最上面
        if let sourceCity, let sourceZone, !savedCities.contains(where: { $0.timeZone.identifier == sourceZone.identifier }) {
            result.append(row(sourceCity, id: "source", at: instant, isSource: true, isSaved: false))
        }
        // 本地的时区总是列出来
        if !savedCities.contains(where: { $0.timeZone.identifier == local.identifier }),
           !result.contains(where: { $0.city.timeZone.identifier == local.identifier }) {
            result.append(row(localCity, id: "local", at: instant, isSource: false, isSaved: false))
        }
        for city in savedCities {
            result.append(row(city, id: city.id, at: instant, isSource: city.timeZone.identifier == sourceZone?.identifier, isSaved: true))
        }
        return result
    }

    private func row(_ city: WorldTime.City, id: String, at instant: Date, isSource: Bool, isSaved: Bool) -> Row {
        let zone = city.timeZone
        var detail = WorldTime.offsetText(zone, at: instant)
        if city.id == "utc" {
            detail = String(localized: "协调世界时")
        } else if let abbreviation = WorldTime.abbreviation(zone, at: instant) {
            detail += " · " + abbreviation
        } else if zone.isDaylightSavingTime(for: instant) {
            detail += " · " + String(localized: "夏令时")
        }
        return Row(id: id, city: city, isLocal: zone.identifier == local.identifier, isSource: isSource, isSaved: isSaved,
                   time: WorldTime.timeText(instant, in: zone), date: WorldTime.dateText(instant, in: zone),
                   dayOffset: WorldTime.dayOffset(instant, in: zone, from: local), detail: detail,
                   minuteOfDay: WorldTime.minuteOfDay(instant, in: zone))
    }

    /// 卡片上第一行：「3pm PST」是洛杉矶 10月1日周四 15:00
    var headline: String? {
        guard let parsed, let selectionText else { return nil }
        let name = sourceCity?.name ?? localCity.name
        guard parsed.hasTime else {
            return String(localized: "「\(selectionText)」：\(name)现在的时间")
        }
        let date = WorldTime.dateText(parsed.date, in: parsed.zone)
        let time = WorldTime.timeText(parsed.date, in: parsed.zone)
        return String(localized: "「\(selectionText)」是\(name) \(date) \(time)")
    }

    var shiftText: String {
        guard shiftMinutes != 0 else { return String(localized: "拖动换个时间") }
        let sign = shiftMinutes > 0 ? "+" : "\u{2212}"
        let hours = abs(shiftMinutes) / 60
        let minutes = abs(shiftMinutes) % 60
        if hours == 0 {
            return sign + String(localized: "\(minutes) 分钟")
        }
        if minutes == 0 {
            return sign + String(localized: "\(hours) 小时")
        }
        return sign + String(localized: "\(hours) 小时 \(minutes) 分钟")
    }

    var resetTitle: String {
        followsNow ? String(localized: "回到现在") : String(localized: "回到选中的时间")
    }

    func setShift(_ minutes: Int) {
        let stepped = Int((Double(minutes) / Double(Self.shiftStep)).rounded()) * Self.shiftStep
        shiftMinutes = min(max(stepped, -Self.shiftLimit), Self.shiftLimit)
    }

    func reset() {
        shiftMinutes = 0
        if followsNow {
            base = Self.wholeMinute(now())
        }
    }

    // MARK: - 大家都在上班的时间

    /// 列出的几个地方（偏移不全一样时）在这一天（本地的那一天）都在 9:00–18:00 之间的第一段
    var overlap: DateInterval? {
        let zones = rows.map(\.city.timeZone)
        let instant = self.instant
        guard Set(zones.map { $0.secondsFromGMT(for: instant) }).count > 1 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = local
        let day = calendar.startOfDay(for: instant)
        let key = "\(day.timeIntervalSince1970)|" + zones.map(\.identifier).joined(separator: ",")
        if let overlapCache, overlapCache.key == key {
            return overlapCache.value
        }
        let value = WorldTime.commonWorkingHours(on: day, zones: zones)
        overlapCache = (key, value)
        return value
    }

    /// 有几个时区的话说一句什么时候大家都在上班；只有一个时区（或者偏移都一样）时为 nil
    var overlapText: String? {
        let zones = rows.map(\.city.timeZone)
        let instant = self.instant
        guard Set(zones.map { $0.secondsFromGMT(for: instant) }).count > 1 else { return nil }
        guard let overlap else {
            return String(localized: "这几个地方没有都在 9:00–18:00 之间的时间")
        }
        let start = WorldTime.timeText(overlap.start, in: local)
        let end = WorldTime.timeText(overlap.end, in: local)
        return String(localized: "大家都在上班（9:00–18:00）：本地 \(start)–\(end)")
    }

    /// 跳到大家都在上班的那一段的开头：正好落在整点、半点上，不按滑块的格子取整
    func jumpToOverlap() {
        guard let overlap else { return }
        let minutes = Int((overlap.start.timeIntervalSince(base) / 60).rounded())
        shiftMinutes = min(max(minutes, -Self.shiftLimit), Self.shiftLimit)
    }

    // MARK: - 城市

    var results: [WorldTime.City] {
        WorldTime.search(search, excluding: Set(cityIDs), limit: 6)
    }

    func add(_ city: WorldTime.City) {
        if !cityIDs.contains(city.id) {
            cityIDs.append(city.id)
        }
        search = ""
        isAdding = false
    }

    /// 回车：加第一个搜到的
    func addFirstResult() {
        if let city = results.first {
            add(city)
        }
    }

    func remove(_ id: String) {
        cityIDs.removeAll { $0 == id }
    }

    // MARK: - 复制

    /// 每行一个地方：「北京 10月2日周五 06:00（UTC+8）」
    var copyText: String {
        rows.map { row in
            String(localized: "\(row.city.name) \(row.date) \(row.time)（\(WorldTime.offsetText(row.city.timeZone, at: instant))）")
        }
        .joined(separator: "\n")
    }

    // MARK: - 跟着现在走

    func startTicking() {
        guard usesTimers, followsNow, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                // 挪过时间以后停在挪到的那一刻，不再跟着现在走
                guard let self, self.shiftMinutes == 0 else { return }
                self.base = Self.wholeMinute(self.now())
            }
        }
    }

    func stopTicking() {
        timer?.invalidate()
        timer = nil
    }

    /// 去掉秒：挪到的时刻都落在整分钟上
    static func wholeMinute(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
    }

    private static func shorten(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return line.count > 30 ? String(line.prefix(29)) + "…" : line
    }
}

struct WorldTimeView: View {
    @ObservedObject var model: WorldTimeModel
    var onCopy: () -> Void
    var onClose: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        CardContainer(title: String(localized: "时区换算"), width: 400, onClose: onClose) {
            if let headline = model.headline {
                Text(verbatim: headline)
                    .font(.callout)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.unrecognized {
                Text("没认出选中的文字里的时间，下面是各地现在的时间")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let hint = model.parsed?.hint {
                Label(hint, systemImage: "sun.max")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            rowList
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.2.circlepath")
                    .foregroundStyle(.secondary)
                Slider(value: Binding(get: { Double(model.shiftMinutes) }, set: { model.setShift(Int($0)) }),
                       in: Double(-WorldTimeModel.shiftLimit)...Double(WorldTimeModel.shiftLimit), step: Double(WorldTimeModel.shiftStep))
                    .help("往前、往后挪，看那时各地是几点（最多一天）")
                Text(verbatim: model.shiftText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(model.shiftMinutes == 0 ? .secondary : .primary)
                    .frame(width: 92, alignment: .trailing)
            }
            if let overlapText = model.overlapText {
                HStack(spacing: 6) {
                    Image(systemName: model.overlap == nil ? "moon.zzz" : "person.2")
                        .foregroundStyle(.secondary)
                    Text(verbatim: overlapText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if model.overlap != nil {
                        Button("看看那时", action: model.jumpToOverlap)
                    }
                }
            }
            if model.isAdding {
                searchSection
            }
            HStack(spacing: 8) {
                Button {
                    model.isAdding.toggle()
                } label: {
                    Label(model.isAdding ? String(localized: "收起") : String(localized: "添加城市"), systemImage: model.isAdding ? "chevron.up" : "plus")
                }
                if model.shiftMinutes != 0 {
                    Button(model.resetTitle, action: model.reset)
                }
                Spacer()
                Button("复制", action: onCopy)
            }
        }
        .controlSize(.small)
        .onAppear { model.startTicking() }
        .onDisappear { model.stopTicking() }
    }

    @ViewBuilder
    private var rowList: some View {
        let rows = model.rows
        let list = VStack(spacing: 2) {
            ForEach(rows) { row in
                ZoneRow(row: row, onRemove: removeAction(row), onAdd: addAction(row))
            }
        }
        if rows.count > 7 {
            ScrollView {
                list
            }
            .frame(height: ZoneRow.height * 7.5)
        } else {
            list
        }
    }

    /// 常用城市可以拿掉（至少留一个）
    private func removeAction(_ row: WorldTimeModel.Row) -> (() -> Void)? {
        guard row.isSaved, model.cityIDs.count > 1 else { return nil }
        let model = self.model
        return { model.remove(row.id) }
    }

    /// 临时多出来的一行（选中的时区、本地）可以加进常用城市
    private func addAction(_ row: WorldTimeModel.Row) -> (() -> Void)? {
        guard !row.isSaved else { return nil }
        let model = self.model
        return { model.add(row.city) }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("搜索城市、国家或时区：东京、dj、Tokyo、PST", text: $model.search)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit(model.addFirstResult)
                .onAppear { searchFocused = true }
            let results = model.results
            if results.isEmpty, !model.search.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("没有找到")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(results) { city in
                SearchResultRow(city: city, instant: model.instant) {
                    model.add(city)
                }
            }
        }
    }
}

/// 一个地方：名字和偏移、一天里的时间条、当地的时间和日期
private struct ZoneRow: View {
    static let height: CGFloat = 40

    let row: WorldTimeModel.Row
    var onRemove: (() -> Void)?
    var onAdd: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(verbatim: row.city.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    if let onAdd {
                        Button(action: onAdd) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .help("加到常用城市")
                    } else if hovering, let onRemove {
                        Button(action: onRemove) {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("从列表里拿掉")
                    }
                }
                // 「选中的」「本地」放在第二行：放在名字后面时，长一点的城市名（Los Angeles）会被截短
                HStack(spacing: 4) {
                    Text(verbatim: row.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if row.isSource {
                        tag(String(localized: "选中的"), color: .accentColor)
                    } else if row.isLocal {
                        tag(String(localized: "本地"), color: .secondary)
                    }
                }
            }
            .frame(width: 124, alignment: .leading)
            DayBar(minute: row.minuteOfDay)
            VStack(alignment: .trailing, spacing: 1) {
                Text(verbatim: row.time)
                    .font(.system(size: 17, weight: .medium))
                    .monospacedDigit()
                HStack(spacing: 3) {
                    if row.dayOffset != 0 {
                        Text(verbatim: row.dayOffset > 0 ? String(localized: "+\(row.dayOffset) 天") : String(localized: "\u{2212}\(-row.dayOffset) 天"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(row.dayOffset > 0 ? Color.orange : Color.blue)
                    }
                    Text(verbatim: row.date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 104, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: Self.height)
        .background(RoundedRectangle(cornerRadius: 8).fill(background))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(row.city.timeZone.localizedName(for: .generic, locale: Localization.locale) ?? row.city.timeZone.identifier)
        .contextMenu {
            if let onAdd {
                Button("加到常用城市", action: onAdd)
            }
            if let onRemove {
                Button("从列表里拿掉", action: onRemove)
            }
        }
    }

    private var background: Color {
        if row.isSource {
            return Color.accentColor.opacity(0.14)
        }
        return Color.primary.opacity(hovering ? 0.07 : 0.035)
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().strokeBorder(color.opacity(0.6), lineWidth: 0.8))
            .fixedSize()
    }
}

/// 一天 24 小时的条：夜里深、早晚浅、上班时间绿，竖线是那里现在（或者挪到的那一刻）几点
private struct DayBar: View {
    let minute: Int

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(Self.segments, id: \.start) { segment in
                        Rectangle()
                            .fill(Self.color(segment.part))
                            .frame(width: width * CGFloat(segment.end - segment.start) / 1440)
                    }
                }
                .frame(height: 8)
                .clipShape(Capsule())
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.primary)
                    .frame(width: 2.5, height: 16)
                    .offset(x: Self.markerOffset(width: width, minute: minute))
            }
            .frame(width: width, height: proxy.size.height)
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }

    /// 竖线的位置：按一天里的第几分钟，不出两头
    static func markerOffset(width: CGFloat, minute: Int) -> CGFloat {
        let position = width * CGFloat(minute) / 1440
        return min(max(position - 1.25, 0), width - 2.5)
    }

    private static let segments: [(start: Int, end: Int, part: WorldTime.DayPart)] = {
        var result: [(start: Int, end: Int, part: WorldTime.DayPart)] = []
        for minute in stride(from: 0, to: 1440, by: 60) {
            let part = WorldTime.DayPart.of(minute: minute)
            if let last = result.last, last.part == part {
                result[result.count - 1].end = minute + 60
            } else {
                result.append((minute, minute + 60, part))
            }
        }
        return result
    }()

    private static func color(_ part: WorldTime.DayPart) -> Color {
        switch part {
        case .night: return Color.indigo.opacity(0.32)
        case .edge: return Color.orange.opacity(0.32)
        case .work: return Color.green.opacity(0.55)
        }
    }
}

/// 搜到的城市：名字、偏移、那里现在几点，点一下加进列表
private struct SearchResultRow: View {
    let city: WorldTime.City
    let instant: Date
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(Color.accentColor)
                Text(verbatim: city.name)
                    .font(.callout)
                Text(verbatim: WorldTime.offsetText(city.timeZone, at: instant))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(verbatim: WorldTime.timeText(instant, in: city.timeZone))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
