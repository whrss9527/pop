import Foundation
@testable import Pop

/// 测试用的完整功能列表：Pop 自带的功能，加上插件包提供的功能（PluginBundles/ 下的代码也编进了单元测试）
enum TestCatalog {
    /// 编进测试的插件包的入口
    static let bundles: [PopPluginBundle.Type] = [
        ScreenPenEntry.self, CameraBubbleEntry.self, PointerHighlightEntry.self, TeleprompterEntry.self,
        KeyboardCleanerEntry.self, ScreenRulerEntry.self, LargeTypeEntry.self, SpellCheckEntry.self, CodeImageEntry.self,
        CronEntry.self, JSONTypesEntry.self, RegexTesterEntry.self, WatermarkEntry.self,
        PaletteEntry.self, TableOCREntry.self, NumberStatsEntry.self, ReminderEntry.self, CodeStatsEntry.self,
        FileCompareEntry.self, FolderToolsEntry.self, BatchRenameEntry.self, MenuShortcutsEntry.self, WindowLayoutEntry.self,
        SpeakEntry.self,
        TextImageEntry.self,
        WebCaptureEntry.self,
        ExtractInfoEntry.self,
        IDNumberEntry.self,
        LineToolsEntry.self,
        TextCleanupEntry.self,
        QuickNoteEntry.self,
        ChangeCaseEntry.self,
        EncodeDecodeEntry.self,
        YAMLJSONEntry.self,
        FormatXMLEntry.self,
        FormatSQLEntry.self,
        TableConvertEntry.self,
        MarkdownEntry.self,
        ToMarkdownEntry.self,
        MarkdownTOCEntry.self,
        DateSpanEntry.self,
        NumberConvertEntry.self,
        ContrastEntry.self,
        HashEntry.self,
        QRCodeEntry.self,
        Base64ImageEntry.self,
        RandomEntry.self,
        LinkInspectEntry.self,
        JWTEntry.self,
        CharInfoEntry.self,
        ScreenshotTranslateEntry.self,
        TextDiffEntry.self,
        ImageConvertEntry.self,
        StitchImagesEntry.self,
        IDPhotoEntry.self,
        CropImageEntry.self,
        RedactEntry.self,
        RemoveBackgroundEntry.self,
        ScanCodeEntry.self,
        ScreenRecordEntry.self,
        ScrollCaptureEntry.self,
        ShowKeystrokesEntry.self,
        FolderTreeEntry.self,
        ZipEntry.self,
        PDFEntry.self,
        VideoConvertEntry.self,
        TrimMediaEntry.self,
        TranscribeEntry.self,
        AirDropEntry.self,
        SendToPhoneEntry.self,
        OpenInTerminalEntry.self,
        KeepAwakeEntry.self,
        SystemActionsEntry.self,
        TimerEntry.self,
        SpotlightEntry.self,
        BeautifyEntry.self,
        ZoomEntry.self,
        CompareImagesEntry.self,
        SplitImageEntry.self,
        QuitAppsEntry.self,
        TidyFolderEntry.self,
        AppIconEntry.self,
        UninstallAppEntry.self,
        NewFileEntry.self,
        FileEncodingEntry.self,
        AppInfoEntry.self,
        MediaInfoEntry.self,
        SubtitlesEntry.self,
        FontPreviewEntry.self,
        EncryptFilesEntry.self,
        BatteryInfoEntry.self,
        VoiceRecorderEntry.self,
        SystemInfoEntry.self,
        SoundDevicesEntry.self,
        ResolutionEntry.self,
        DiskSpeedEntry.self,
        WorldTimeEntry.self,
        ChartEntry.self,
        SimilarPhotosEntry.self,
        FocusSoundsEntry.self,
        EmojiSymbolsEntry.self,
        BluetoothEntry.self,
        CalendarEntry.self,
        BreakReminderEntry.self,
        WindowPiPEntry.self,
        MouseWheelEntry.self,
        HoldToQuitEntry.self,
        SleepTimerEntry.self,
    ]

    /// 单独发布的插件包（不在 PluginCatalog 里，目录信息在它文件夹里的 plugin.json）：文件夹名 → 入口
    static let published: [String: PopPluginBundle.Type] = [
        "SleepTimer": SleepTimerEntry.self,
    ]

    /// 单独发布的插件包写在 PluginBundles/<文件夹>/plugin.json 里的目录信息（直接从源码里读）
    static func publishedMeta(_ folder: String) -> PluginPackageMeta? {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        guard let data = try? Data(contentsOf: root.appending(path: "PluginBundles/\(folder)/plugin.json")) else { return nil }
        return try? JSONDecoder().decode(PluginPackageMeta.self, from: data)
    }

    /// 单独发布的插件包自己带的英文翻译（PluginBundles/<文件夹>/en.lproj）
    static func publishedEnglishBundle(_ folder: String) -> Bundle? {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return Bundle(path: root.appending(path: "PluginBundles/\(folder)/en.lproj").path(percentEncoded: false))
    }

    /// 单独发布的插件包提供的功能
    static var publishedFunctionIDs: Set<String> {
        Set(published.values.flatMap { $0.makePlugins() }.map(\.info.id))
    }

    static func plugins() -> [any PopPlugin] {
        BuiltinPlugins.sorted(BuiltinPlugins.make() + bundles.flatMap { $0.makePlugins() })
    }

    static func infos() -> [PluginInfo] {
        plugins().map(\.info)
    }
}
