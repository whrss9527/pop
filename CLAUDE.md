# 工作约定

## 改完怎么合并、怎么发版

- 在自己的分支上改，推上去开合并请求。合并进 main 之前 CI 要全部通过：两个版本的 Xcode 编译和单元测试，macOS 15、macOS 26 上的启动测试、一键更新的端到端测试、签名流程自测和浮窗截图。
- 用户能感觉到的改动先写入 CHANGELOG.md 顶部的 `## 未发布`，累积到准备发稳定版时才改成版本号和日期，比如 `## 0.69.0（2026-10-07）`。稳定版按上海时区每个工作日最多一个；当天已发布或逢周末时，工作日定时 CI 会重试。不要为每个小改动发布一个稳定版。
- main 每次合并且完整 CI 通过后自动发布 `MARKETING_VERSION-beta.<CI 运行序号>` 测试版。新安装默认只接收稳定版，已有通道选择保留。正式版和测试版都先上传全部附件再公开。
- 版本号：新功能升次版本号，只修问题升修订号。开始下一轮未发布改动时，把 `project.yml` 的 `MARKETING_VERSION` 设成下一个稳定版版本号；提升未发布章节时必须与它一致。只改单独发布的插件包走 Plugins 工作流，不提升 Pop 版本。
- 手动发布稳定版也遵守上述节奏，并要求顶部章节对应版本号；覆盖旧标签仅重建原版本。测试版可以手动使用 `make release VERSION=0.69.0-beta.1 BETA=1`。

## 插件包单独发布

- 插件包可以不跟着 Pop 发版：插件包文件夹里放 `plugin.json`（`id`、`version`，名字和介绍的 `zh-Hans`、`en`，`symbol`、`category`、`functions`，卸载时要删的 `defaultsKeys`、`keychainAccounts`、`dataFolders`），界面文字放在它自己的 `en.lproj/Localizable.strings` 里（代码里用 `bundle:` 查，跑 `scripts/check-localization.py --sync-zh-hans` 生成 `zh-Hans` 那份），功能 ID 用它自己的常量，不往 Pop 的 `BuiltinPluginID`、`PluginCatalog` 里加。
- 合并进 main 以后，Plugins 工作流（`scripts/publish-plugins.sh`）在最新正式版的标签上构建这些插件包，用发布出去的 Pop 装载检查，再传到那个版本的发布页、合进插件包列表；PR 里只检查不上传。改了已经发布的插件包，要把 `plugin.json` 的 `version` 往上加才会再发布。
- 单独发布的插件包只能用最新正式版里已经有的 Pop 代码；要改 Pop 本身的，先发 Pop 新版本。只改单独发布的插件包时不加 CHANGELOG.md 的版本（提升版本号才会发稳定版），改了什么写在 PR 里。

## 写法

- 代码注释、界面文字、README 和更新日志用中文；提交信息用英文，风格照 git log。
- 项目里不要写「类似某某」「相当于某某的……」这种拿别的产品作比较的话，直接说功能本身。
- shell 脚本里变量后面紧跟中文或全角符号时写成 `${VAR}`：macOS 自带的 bash 3.2 会把多字节字符的一部分当成变量名。

## 界面文字和翻译

- Pop 有中文和英文两套界面，默认跟着系统语言切换（系统语言两个都不是时用英文），也可以在「设置 → 通用」里选。界面文字用中文原文当 key：SwiftUI 的 `Text("中文")`、`Button("中文")` 这类直接写就行；其他地方显示给用户的文字（提示、错误、通知、卡片标题）写成 `String(localized: "中文")`。
- 每加一条界面文字，都要在 `Pop/Resources/en.lproj/Localizable.strings` 里加一行 `"中文原文" = "English";`（带变量时，字符串写 `%@`，整数写 `%lld`），然后跑 `scripts/check-localization.py --sync-zh-hans` 更新中文那份。CI 的 build-and-test 会检查每条中文都有英文，漏了会失败，日志里按 `.strings` 的格式列出缺的那几条。
- 发给 AI 的指令、演示模式的示例内容、用来识别中文的关键词表不翻译。
- 单元测试固定用中文界面跑（`project.yml` 里 scheme 的 test language），断言照旧写中文结果。

## 看浮窗的效果

- 浮窗的动画参数都在 `Pop/UI/Motion.swift`，玻璃效果在 `Pop/UI/Glass.swift`（macOS 26 上是 Liquid Glass，更早的系统用窗口后面的模糊）。
- CI 用演示模式（`POP_DEMO=1`，`POP_ANIMATION_SCALE` 把动画放慢）把圆盘、结果卡片、提示、列表、贴图走一遍，按时截图，再用深色外观（`POP_APPEARANCE=dark`）拍一组 `dark-` 开头的，推到 `ci-screenshots/macos-15` 和 `ci-screenshots/macos-26` 两个分支（每次覆盖）。改了浮窗之后 `git fetch origin ci-screenshots/macos-26` 就能看到动画的中间帧。
- GitHub 的 macOS runner 默认打开了「减弱动态效果」和「降低透明度」（玻璃会变成不透明、动画只剩淡入淡出），截图脚本会先把这两项关掉；runner 的桌面是纯黑的，所以截图里的玻璃看起来是灰色的，真机上会透出后面的内容。
- 本机也能跑：`scripts/overlay-screenshots.sh build/app/.../Pop.app 截图目录 6`。

## 待办

开发任务是本仓库标了 `agent` 的 issue。具体做法见 [whrss9527/plan 的 AGENTS.md](https://github.com/whrss9527/plan/blob/main/AGENTS.md) 中「用 issue 管任务的项目」一节：先按优先级、同优先级按编号认领，检查依赖和 `doing` / `blocked`，PR 写 `Closes #编号`。问题报告和功能请求使用仓库 issue 模板；标签定义从 plan 的统一模板同步。
