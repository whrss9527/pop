# 上架 Mac App Store

Pop 的 App Store 版和 GitHub 版用同一份代码，编译时带 `APP_STORE`（见 `Pop/App/Distribution.swift`），区别是：

- 开 App Sandbox，不带 iCloud 同步；
- 只能由 App Store 更新，没有一键更新、没有赞赏码；
- 插件包都打在 App 里（`Contents/PlugIns`），装上就是装载，不从网上下载；没有插件库，自己的插件不能用 Shell 脚本和快捷指令；
- 沙盒里跑不了的插件包不提供：压缩和解压、系统操作、加密打包、蓝牙设备（`PluginCatalog.unavailableInAppStore`）；
- 沙盒里弹不出辅助功能的授权提示：「去授权」会打开系统设置并在访达里选中 Pop，请用户点「+」加进去；
- 在访达里选中的文件，要先在「设置 → 通用」里允许 Pop 访问所在的文件夹（security-scoped bookmark，见 `Pop/System/FolderAccess.swift`）；
- 不能注册只带 ⌥ 的全局快捷键（macOS 15 起沙盒里的 App 注册不了）。

在自己的 Mac 上试：`POP_SANDBOX=1 scripts/build-app.sh 99.0.0 build/sandbox` 构建 App Store 版的试用包 Pop2（名字和 Bundle ID 都和 Pop 分开），或者从 Sandbox check 工作流的产物 `Pop2` 下载。

## 只做一次的准备

证书和 App Store Connect API 密钥和 Stox 用的是同一套，只有 App ID 和描述文件是 Pop 自己的。

1. **App ID**：[开发者网站 → Identifiers](https://developer.apple.com/account/resources/identifiers/list) → +，App IDs → App，Bundle ID 选 Explicit，填 `io.github.whrss9527.pop`，能力都不用勾。
2. **描述文件**：[Profiles](https://developer.apple.com/account/resources/profiles/list) → +，Distribution 下面选 **Mac App Store Connect**，App ID 选上面那个，证书选 Apple Distribution，下载得到 `.provisionprofile`。
3. **新建 App**：[App Store Connect](https://appstoreconnect.apple.com/apps) → + → 新建 App，平台 macOS，名称 `Pop – Right-Click Toolbox`（被占用的话换一个，同时改 `docs/app-store/listing/en-US/name.txt`），主要语言英语（美国），Bundle ID 选 `io.github.whrss9527.pop`，SKU 随便填（比如 pop）。
4. **App 隐私**：App Store Connect 里这个 App → App 隐私 → 「不收集数据」。隐私政策网址是 `docs/privacy.md` 在 GitHub 上的地址。
5. **Secrets**：在 pop 仓库的 Settings → Secrets and variables → Actions 里加上 `.github/workflows/app-store.yml` 开头列的那些。证书、密码和 API 密钥照抄 Stox 仓库里的，`APPSTORE_PROVISIONING_PROFILE` 是第 2 步的描述文件（`base64 -i Pop_Mac_App_Store.provisionprofile | pbcopy`）。

## 上传、填资料、提交

在 Actions 页面手动运行 **app-store** 工作流：

- `build`：`upload` 构建、校验并上传；`validate` 只构建和校验（第一次先用它试）；`none` 不构建。
- `listing`：把 `docs/app-store/listing` 里的资料填进 App Store Connect，选上构建。
- `submit`：最后提交审核。

版本号默认取 `project.yml` 的 `MARKETING_VERSION`，构建号是提交数加运行次数，每次上传都会变大。

## 资料

`docs/app-store/listing`：`config.json`（类别、价格、销售范围、年龄分级），每种语言一个文件夹（名称、副标题、描述、关键词、推广文本、网址），`review_notes.txt`（给审核员的说明），`screenshots/en-US/`（截图，文件名决定顺序，多大都行：工作流用 `scripts/fit-screenshots.py` 做成 2880×1800，比例不是 16:10 的放在中间、四周用模糊的背景填满）。`python3 scripts/app-store-connect.py check` 检查字数和格式，`python3 -m unittest scripts/test_app_store_connect.py` 跑测试。
