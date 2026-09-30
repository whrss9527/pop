# Pop 开发指南

[← 回到 README](../README.zh-CN.md) · [English](guide.md)

## 开发

需要 macOS 15+、Xcode 16+（推荐 Xcode 26）。

```bash
brew install xcodegen
cp Config/Local.xcconfig.example Config/Local.xcconfig   # 填上你的 DEVELOPMENT_TEAM
make open                                                # 生成 Pop.xcodeproj 并用 Xcode 打开
```

在 Xcode 里运行后：

1. 按提示在「系统设置 → 隐私与安全性 → 辅助功能」里打开 Pop；
2. 在任意 App 里选中一段英文，长按右键，就会看到翻译卡片；
3. 第一次翻译某个语言组合时，按卡片上的提示到「设置 → 翻译」下载离线语言包。

> **一定要用固定的开发证书签名**（在 `Local.xcconfig` 里设置 `DEVELOPMENT_TEAM`）。用「本地签名（-）」的话，每次重新编译系统都会把 Pop 当成新 App，辅助功能授权会失效，需要在 Pop 的「设置 → 通用」里点「清除旧的授权记录」（或者在系统设置里删掉 Pop）再重新授权。

**没有付费开发者账号？** 在 `Config/Local.xcconfig` 里加上下面两行，关掉 iCloud 能力后也能正常开发（iCloud 同步会显示为不可用）：

```
POP_ENTITLEMENTS = Pop/Resources/Pop-NoCloud.entitlements
CODE_SIGN_IDENTITY = -
```

常用命令：

```bash
make build   # 编译
make test    # 跑单元测试（内容识别、各种转换、计算器、圆盘几何、设置编解码与迁移、同步冲突判断、插件与脚本运行、插件库、剪贴板数据库、更新检查）
make app     # 在本机构建 Release 版 Pop.app（通用版，本地签名），输出在 build/app
make clean
```

每次推送代码，GitHub Actions 都会在 macOS 上生成工程、编译并运行测试（`.github/workflows/ci.yml`），检查翻译，然后真正启动一次 Release 包，再用本地的假发布把一键更新完整走一遍（校验和不对要拒绝、换了签名证书要拒绝、正常版本要替换并重新启动；本地签名和证书签名各测一遍）。

### 界面语言

Pop 的开发语言是简体中文，界面文字直接用中文原文作 key；英文翻译在 `Pop/Resources/en.lproj/Localizable.strings`（授权提示在 `InfoPlist.strings`）。系统语言是英文时显示英文界面，是中文时显示中文。

- SwiftUI 的 `Text("中文")`、`Button("中文")` 这类会自动查翻译；其他写在代码里的界面文字用 `String(localized: "中文")`；
- 加了或者改了界面文字，在 `en.lproj/Localizable.strings` 里加一行 `"中文原文" = "English";`，再跑 `scripts/check-localization.py --sync-zh-hans` 更新 `zh-Hans` 那份；
- CI 编译时打开 `SWIFT_EMIT_LOC_STRINGS`，再用 `scripts/check-localization.py` 检查：两种语言的 key 和占位符一致，代码里用到的每一条中文都有英文翻译；缺的 key 会按 `.strings` 的格式列在日志里；
- 单元测试固定用中文界面跑（scheme 的测试语言是 `zh-Hans`）。

### iCloud 同步

- 使用 iCloud 键值存储（`NSUbiquitousKeyValueStore`），Pop 没有服务器，数据存在用户自己的 iCloud 里；
- 需要付费开发者账号签名，`Config/Pop.xcconfig` 默认使用带 iCloud 能力的 `Pop/Resources/Pop.entitlements`；
- 多台 Mac 都改过时以最后一次修改为准；新装的 Mac 第一次同步会直接采用云端配置，不会用默认设置覆盖云端；
- iCloud 的存储标识由 Team ID + Bundle ID 组成，**正式发布后不要再改 Bundle ID**，否则老用户的同步数据会找不到。发布前在 `Config/Pop.xcconfig` 里把 `POP_BUNDLE_ID` 改成你自己的。

### 目录结构

```
Pop/
├── App/        启动入口、模块组装（AppController）、一次唤起的完整流程（PopCoordinator）
├── Core/       纯逻辑：设置模型与持久化、内容识别、各种文字转换、计算器、圆盘/屏幕几何
├── Plugins/    插件协议、分发规则（Router）、内置功能、自定义插件（manifest、运行器、插件文件夹）、插件库
├── AI/         AI 接口（兼容 OpenAI Chat Completions，流式输出）、系统内置的模型、AI 卡片、钥匙串里的 API Key
├── Annotate/   截图标注：标注模型（箭头、方框、文字、马赛克、序号、背景）和标注窗口
├── Clipboard/  剪贴板历史：SQLite 存储、剪贴板监听、历史面板
├── System/     事件拦截（MouseTrigger）、全局快捷键、读取选中内容、粘贴回原 App、权限、通知、保持唤醒、倒计时
├── UI/         浮动面板、圆盘、结果/翻译卡片、「全部功能」列表、菜单栏图标、贴图、暂存架、屏幕标尺
├── Settings/   设置窗口各页面（含拖拽式圆盘编辑器、插件编辑器）
├── Sync/       iCloud 同步
├── Update/     检查更新（GitHub Releases）、下载校验、替换并重新启动
└── Resources/  Info.plist、entitlements、界面翻译（zh-Hans.lproj、en.lproj）
PopTests/       单元测试
plugins/        插件库：索引（index.json）和可以一键安装的插件
Config/         xcconfig（签名、Bundle ID）
scripts/        构建、签名、公证和测试脚本（发布流程和 CI 都用它们）
```

### 扩展功能

大多数需求用上面的[自定义插件](guide.zh-CN.md#自定义插件)就能满足，不用改代码。要做内置功能的话，实现 `PopPlugin` 协议（`Pop/Plugins/Plugin.swift`），声明它能处理的内容类型，在 `BuiltinPluginID` 里加一个 ID，再加到 `BuiltinPlugins.make()` 里（老用户升级后会自动装上新的内置功能）：

```swift
struct UppercasePlugin: PopPlugin {
    let info = PluginInfo(id: "uppercase", name: "转大写", symbol: "textformat.size.larger",
                          summary: "把选中的文字转成大写", accepts: [.text], pattern: "[a-z]")

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure("没有文字") }
        let upper = text.uppercased()
        return .card(ResultCard(title: "转大写", body: upper, copyText: upper, replaceText: upper))
    }
}
```

`PluginOutcome` 可以是结果卡片（`ResultCard` 支持多行结果、图片、颜色色块和自定义按钮）、交给翻译卡片、直接替换原文、轻提示，或者打开剪贴板历史、「全部功能」列表。

之后计划支持的方向：带界面的网页插件。

### 发布新版本

发版由 `CHANGELOG.md` 驱动，不用手动打标签：

1. 在 `CHANGELOG.md` 最上面加一节新版本，标题是版本号加日期，比如 `## 0.4.0（2026-09-29）`，内容会原样放进发布说明；
2. 改动推到 main（或者合并进 main）。CI 全部通过后，发现这个版本还没有 `v0.4.0` 标签，就自动构建通用版（Apple 芯片 / Intel）、启动测试、打包成 `Pop-<版本>.zip`、生成 `SHA256SUMS.txt`，打上标签并发布正式版。Release 先建成草稿，附件传完才公开；
3. 已经装着 Pop 的 Mac 下一次检查时就会收到这个版本，提示一键更新。

只改 CI、文档或测试、不想发版的话，就不要在 `CHANGELOG.md` 里加新版本。想先发个测试版给少数人试用，可以在 Actions 页面手动运行「Release」工作流并勾选「作为测试版」，或者在本机用 GitHub CLI（`brew install gh && gh auth login`）：

```bash
make release VERSION=0.4.0          # 手动发布正式版
make release VERSION=0.4.0 BETA=1   # 手动发布测试版（预发布）
```

- 版本号已经发布过时工作流会报错；手动运行时勾选 overwrite 可以用原标签的代码重新构建，替换附件并更新说明；
- `CFBundleShortVersionString` 取你填的版本号，`CFBundleVersion` 自动取 Git 提交数；
- 比较新旧时按数字逐段比较，同一个版本号带 `-beta.1` 之类后缀的比不带的旧。

### 签名与公证

发布流程默认用本地签名（ad-hoc），什么都不用配置。在仓库的 Settings → Secrets and variables → Actions 里加上证书后，之后发布的版本都会用证书签名：

| 签名方式 | 需要什么 | 一键更新后的辅助功能授权 | 第一次打开 |
| --- | --- | --- | --- |
| 本地签名（默认） | 什么都不用 | 每次更新都要重新授权 | 要先解除隔离 |
| 自签名证书 | 用 `make signing-certificate` 生成一张 | 保留 | 要先解除隔离 |
| Developer ID + 公证 | 付费开发者账号 | 保留 | 双击就能打开 |

**自签名证书**（免费）：

```bash
make signing-certificate    # 即 scripts/create-signing-certificate.sh，文件放在 ~/.pop-signing
```

按脚本最后打印的提示，把 `certificate.p12.base64` 的内容填进 Secret `MACOS_CERTIFICATE_P12`，把 `password.txt` 的内容填进 `MACOS_CERTIFICATE_PASSWORD`。**请备份这个文件夹**：用证书签名的 Pop 只接受同一张证书签名的更新，证书丢了只能换一张新的，已经安装的 Pop 就得手动下载一次新版本，并重新授权一次。

**Developer ID**：在「钥匙串访问」里把「Developer ID Application: …」证书连同私钥导出成 .p12，`base64 -i 证书.p12 | pbcopy` 后填进 `MACOS_CERTIFICATE_P12`，导出时设的密码填进 `MACOS_CERTIFICATE_PASSWORD`。再配上下面任意一组公证凭据，发布流程会自动提交苹果公证并钉上票据：

| Secrets | 说明 |
| --- | --- |
| `NOTARY_KEY_P8`、`NOTARY_KEY_ID`、`NOTARY_ISSUER_ID` | App Store Connect API 密钥：.p8 文件的内容（或者它的 base64）、密钥 ID、Issuer ID（个人密钥不填） |
| `NOTARY_APPLE_ID`、`NOTARY_PASSWORD`、`NOTARY_TEAM_ID` | Apple ID、App 专用密码（在 appleid.apple.com 生成）、Team ID |

从本地签名换成证书签名后，第一次更新仍然需要重新授权一次辅助功能，之后就不用了。
