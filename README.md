# Pop

类似 uTools「超级面板」的 macOS 菜单栏工具：在任意 App 里**长按鼠标右键**，Pop 读取你选中的内容：

- 选中的是外文：直接弹出翻译卡片（系统离线翻译，不联网、不收费）；
- 选中的是算式：直接算出结果；
- 其他情况（或者什么都没选中）：弹出**圆形功能菜单**，按住右键往某个方向一划、松开就执行那一格的功能。

装哪些功能、每个功能放在圆盘的哪一格、什么内容直接执行哪个功能，都可以在设置里调整。设置可以通过 **iCloud 同步**到你的其他 Mac，新版本可以在 App 里**一键更新**。

## 功能

| 模块 | 说明 |
| --- | --- |
| 唤起方式 | 长按右键（默认，短按仍是系统右键菜单）、修饰键 + 右键、鼠标中键、全局快捷键 |
| 读取选中内容 | 辅助功能接口 → 点 App 菜单里的「拷贝」→ 模拟 ⌘C，三层兜底；会备份并还原剪贴板，模拟按键时临时静音提示音 |
| 内容识别 | 中文 / 外文、链接、邮箱、JSON、算式、Unix 时间戳、文件、图片 |
| 圆盘菜单 | 4–12 格可选；按住划选、松开执行，或松开后点击；数字键 1–9/0 直选，方向键 + 回车，Esc 关闭；靠近屏幕边缘自动内移 |
| 内置功能 | 翻译、搜索、打开链接、计算、纯文本复制、JSON 格式化、时间戳转换、复制文件路径、在访达中显示、打开设置 |
| 直达规则 | 按内容类型决定跳过圆盘直接执行哪个功能（默认：外文 → 翻译，算式 → 计算） |
| iCloud 同步 | 圆盘布局、已安装的功能、直达规则、唤起方式、翻译设置；存在你自己的 iCloud 键值存储里 |
| 检查更新 | Sparkle 2，从 GitHub Releases 检查；EdDSA 签名校验；后台发现新版本时菜单栏图标变成下载箭头，不打断你 |

## 工作原理（关键点）

**长按右键怎么做到不影响正常右键？** macOS 的右键菜单在按下瞬间就会弹出，所以 Pop 用 `CGEventTap` 先把「右键按下」扣住并开始计时：

```
右键按下 → 扣住，开始计时（默认 250ms，可调）
 ├─ 计时内松开          → 按原顺序补发「按下 + 松开」→ 系统右键菜单照常弹出
 ├─ 按住拖动超过 6 像素 → 补发按下并放行拖动（游戏、3D 软件的右键拖拽不受影响）
 └─ 计时到              → 这次按压归 Pop：读取选中内容 → 翻译卡片或圆盘
```

补发的事件带有标记，回到拦截器时直接放行。因为按下事件没有交给目标 App，右键也不会改变 App 里的选区。

**浮窗为什么不抢焦点？** 圆盘和卡片是 `nonactivatingPanel`：原来的 App 一直在前台，选区不会丢，模拟的 ⌘C 也不会发到 Pop 自己身上。

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

> **一定要用固定的开发证书签名**（在 `Local.xcconfig` 里设置 `DEVELOPMENT_TEAM`）。用「本地签名（-）」的话，每次重新编译系统都会把 Pop 当成新 App，辅助功能授权会失效，需要在系统设置里删掉 Pop 再重新添加。

**没有付费开发者账号？** 在 `Config/Local.xcconfig` 里加上下面两行，关掉 iCloud 能力后也能正常开发（iCloud 同步会显示为不可用）：

```
POP_ENTITLEMENTS = Pop/Resources/Pop-NoCloud.entitlements
CODE_SIGN_IDENTITY = -
```

常用命令：

```bash
make build   # 编译
make test    # 跑单元测试（纯逻辑：内容识别、计算器、圆盘几何、设置编解码、同步冲突判断、插件）
make clean
```

每次推送代码，GitHub Actions 都会在 macOS 上生成工程、编译并运行测试（`.github/workflows/ci.yml`）。

## iCloud 同步

- 使用 iCloud 键值存储（`NSUbiquitousKeyValueStore`），Pop 没有服务器，数据存在用户自己的 iCloud 里；
- 需要付费开发者账号签名，`Config/Pop.xcconfig` 默认使用带 iCloud 能力的 `Pop/Resources/Pop.entitlements`；
- 多台 Mac 都改过时以最后一次修改为准；新装的 Mac 第一次同步会直接采用云端配置，不会用默认设置覆盖云端；
- iCloud 的存储标识由 Team ID + Bundle ID 组成，**正式发布后不要再改 Bundle ID**，否则老用户的同步数据会找不到。发布前在 `Config/Pop.xcconfig` 里把 `POP_BUNDLE_ID` 改成你自己的。

## 发布新版本（App 内一键更新）

更新流程：`scripts/release.sh` 打包 → Developer ID 签名 → Apple 公证 → 用 Sparkle 私钥签名并生成 `appcast.xml` → 上传到 GitHub Release。用户的 Pop 会定期读取 `https://github.com/whrss9527/pop/releases/latest/download/appcast.xml`，发现新版本后点「安装更新」即可完成下载、替换和重启。

### 一次性准备

1. **Developer ID 证书**：Xcode → Settings → Accounts → Manage Certificates → 添加「Developer ID Application」。
2. **公证凭据**（App 专用密码在 appleid.apple.com 生成）：

   ```bash
   xcrun notarytool store-credentials pop-notary --apple-id you@example.com --team-id ABCDE12345
   ```

3. **Sparkle 更新签名密钥**：

   ```bash
   make sparkle-tools          # 打印 Sparkle 工具所在目录
   <上面的目录>/generate_keys   # 私钥自动存进钥匙串，终端里会打印公钥
   ```

   把公钥填进 `Config/Pop.xcconfig` 的 `SPARKLE_PUBLIC_ED_KEY = ...` 并提交。私钥只存在你的钥匙串里，**不要提交、不要丢**（丢了之后已安装的旧版本将无法验证新版本）。可以用 `generate_keys -x 文件名` 导出备份。

4. **GitHub CLI**：`brew install gh && gh auth login`。

### 每次发布

```bash
scripts/release.sh 0.2.0     # 或 make release VERSION=0.2.0
```

版本号写在 `CFBundleShortVersionString`；`CFBundleVersion` 自动取 Git 提交数，保证单调递增（Sparkle 用它比较新旧）。没有配置公钥的开发构建不会启动更新器，「检查更新」会提示这是开发版本。

## 目录结构

```
Pop/
├── App/        启动入口、模块组装（AppController）、一次唤起的完整流程（PopCoordinator）
├── Core/       纯逻辑：设置模型与持久化、内容识别、计算器、圆盘/屏幕几何
├── Plugins/    插件协议、分发规则（Router）、内置功能
├── System/     事件拦截（MouseTrigger）、全局快捷键、读取选中内容、权限
├── UI/         浮动面板、圆盘、结果/翻译卡片、菜单栏图标
├── Settings/   设置窗口各页面（含拖拽式圆盘编辑器）
├── Sync/       iCloud 同步
├── Update/     Sparkle 自动更新
└── Resources/  Info.plist、entitlements
PopTests/       单元测试
Config/         xcconfig（签名、Bundle ID、Sparkle 公钥）
scripts/        发布脚本
```

## 扩展功能

新增一个功能只需要实现 `PopPlugin` 协议（`Pop/Plugins/Plugin.swift`），声明它能处理的内容类型，再加到 `BuiltinPlugins.make()` 里：

```swift
struct UppercasePlugin: PopPlugin {
    let info = PluginInfo(id: "uppercase", name: "转大写", symbol: "textformat.size.larger",
                          summary: "把选中的文字转成大写", accepts: [.text])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure("没有文字") }
        return .card(ResultCard(title: "转大写", body: text.uppercased(), copyText: text.uppercased()))
    }
}
```

之后计划支持的方向：脚本插件（manifest + Shell / AppleScript / JavaScript）、网页插件、截图 OCR、选中文字后自动弹出小工具条。

## 已知限制

- 需要辅助功能权限，并且因为 App Store 沙盒不允许使用辅助功能，只能通过官网 / GitHub 分发；
- 少数 App 既不支持辅助功能读取选区，菜单里也找不到「拷贝」，这时会模拟 ⌘C；非 QWERTY 键盘布局下模拟按键可能不准；
- 系统离线翻译的质量对长段落不如在线大模型，翻译引擎做成了可替换的，后续可以接入其他服务。
