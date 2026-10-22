# 上架 Mac App Store

Pop 的 App Store 版和 GitHub 版用同一份代码，编译时带 `APP_STORE`（见 `Pop/App/Distribution.swift`），区别是：

- 开 App Sandbox，不带 iCloud 同步；
- 只能由 App Store 更新，没有一键更新、没有赞赏码；
- 插件包都打在 App 里（`Contents/PlugIns`），装上就是装载，不从网上下载；没有插件库，自己的插件不能用 Shell 脚本和快捷指令；
- 沙盒里跑不了的插件包不提供：压缩和解压、系统操作、加密打包、蓝牙设备、退出 App、卸载 App、新建文件、传到手机（`PluginCatalog.unavailableInAppStore`）；
- 沙盒里弹不出辅助功能的授权提示：「去授权」会打开系统设置并在访达里选中 Pop，请用户点「+」加进去；
- 在访达里选中的文件，要先在「设置 → 通用」里允许 Pop 访问所在的文件夹（security-scoped bookmark，见 `Pop/System/FolderAccess.swift`）；
- 不能注册只带 ⌥ 的全局快捷键（macOS 15 起沙盒里的 App 注册不了）。

在自己的 Mac 上试：`POP_SANDBOX=1 scripts/build-app.sh 99.0.0 build/sandbox` 构建 App Store 版的试用包 Pop2（名字和 Bundle ID 都和 Pop 分开），或者从 Sandbox check 工作流的产物 `Pop2` 下载。

## 只做一次的准备

证书和 App Store Connect API 密钥和 Stox 用的是同一套，只有 App ID 和描述文件是 Pop 自己的。

1. **App ID**：[开发者网站 → Identifiers](https://developer.apple.com/account/resources/identifiers/list) → +，App IDs → App，Bundle ID 选 Explicit，分别注册主程序 `io.github.whrss9527.pop` 和小组件 `io.github.whrss9527.pop.widgets`，能力都不用勾。
2. **描述文件**：[Profiles](https://developer.apple.com/account/resources/profiles/list) → +，Distribution 下面选 **Mac App Store Connect**，分别为上面两个 App ID 创建描述文件，证书选同一团队的 Apple Distribution，下载得到两份 `.provisionprofile`。不要使用开发描述文件或用主程序的描述文件代替小组件的。
3. **新建 App**：[App Store Connect](https://appstoreconnect.apple.com/apps) → + → 新建 App，平台 macOS，名称 `Pop – Right-Click Toolbox`（被占用的话换一个，同时改 `docs/app-store/listing/en-US/name.txt`），主要语言英语（美国），Bundle ID 选 `io.github.whrss9527.pop`，SKU 随便填（比如 pop）。
4. **App 隐私**：App Store Connect 里这个 App → App 隐私 → 「不收集数据」。隐私政策网址：英文 https://whrss.com/privacy/pop/ ，中文 https://whrss.com/zh/privacy/pop/ （`docs/app-store/listing/*/privacy_url.txt`，工作流会填进去）。
5. **Secrets**：在 pop 仓库的 Settings → Secrets and variables → Actions 里加上 `.github/workflows/app-store.yml` 开头列的那些。证书、密码和 API 密钥照抄 Stox 仓库里的；`APPSTORE_PROVISIONING_PROFILE` 是主程序描述文件的 base64，`APPSTORE_WIDGET_PROVISIONING_PROFILE` 是小组件描述文件的 base64（分别运行 `base64 -i 对应文件.provisionprofile | pbcopy`）。工作流解码后用 `APPSTORE_PROFILE` 和 `WIDGET_PROVISIONING_PROFILE` 传文件路径，并在结束时删除临时文件。

本机运行 `scripts/build-app-store.sh` 时，`APPSTORE_PROFILE` 和 `WIDGET_PROVISIONING_PROFILE` 都填本地 `.provisionprofile` 路径，不填 base64。正式打包会在构建前检查两份描述文件的团队、App ID 和发行类型；`ADHOC=1` 不需要描述文件，但不能代替正式签名验收。

## 上传、填资料、提交

在 Actions 页面手动运行 **app-store** 工作流：

- `build`：`upload` 构建、校验并上传；`validate` 只构建和校验（第一次先用它试）；`none` 不构建。
- `listing`：把 `docs/app-store/listing` 里的资料填进 App Store Connect，选上构建。
- `submit`：最后提交审核。

版本号默认取 `project.yml` 的 `MARKETING_VERSION`，构建号是提交数加运行次数，每次上传都会变大。

## 资料

`docs/app-store/listing`：`config.json`（类别、价格、销售范围、年龄分级），每种语言一个文件夹（名称、副标题、描述、关键词、推广文本、网址），`review_notes.txt`（给审核员的说明），`screenshots/en-US/`（截图，文件名决定顺序，多大都行：工作流用 `scripts/fit-screenshots.py` 做成 2880×1800，比例不是 16:10 的放在中间、四周用模糊的背景填满）。`python3 scripts/app-store-connect.py check` 检查字数和格式，`python3 -m unittest scripts/test_app_store_connect.py` 跑测试。
