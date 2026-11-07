# 隔离的本机 UI 验收入口

`scripts/build-ui-fixture.sh` 默认构建 `build/ui-fixture/PopUIFixture.app`，不启动应用。可传入独立输出目录，例如 `scripts/build-ui-fixture.sh build/edge-ui`；DerivedData、构建日志与 App 都留在该目录。默认构建并发为 2。手动验收时只打开这个包，不替换已安装的 Pop。

这个 target 直接编译并显示生产 `RingMenuView`、`PluginChooserView`、`PluginLibraryView`，不是单独仿制的页面。`POP_UI_FIXTURE` 只在该 target 中启用，生产 Pop 仍使用原来的入口；插件库视图新增可注入 model 的初始化器，默认行为不变。

## 隔离边界

- 独立 bundle ID `io.github.whrss9527.pop.ui-fixture`，独立 Info.plist，没有 `pop://` 注册和权限用途声明。
- 签名启用 App Sandbox，没有网络客户端、服务端或个人数据权限。URLSession 使用仅内存配置，所有请求由 URLProtocol 夹具截获；生产插件库的请求、取消、重试、解码与保存逻辑照常运行。
- 不构造生产 AppDelegate/AppController、ClipboardService、权限监视器、CloudSync、Updater、PluginManager；不装载插件包，不开启全局事件监视，不读取其他 App 选区。
- SettingsStore/PluginStore 使用 UUID suite 与临时目录；底部 Library 页显示目录，`requests.log` 记录 start/response/failure/cancel。没有替换或读取真实插件目录。验收后可删除该临时目录和 fixture 沙盒容器。
- 所有插件执行适配为底部选择提示；插件安装只写临时目录。外部链接通过 OpenURLAction 拦截。
- 窗口只分发自己的真实键盘事件；功能列表直接调用生产 `handleKey`。圆盘的键盘和点击分发是 fixture 适配器，复用生产选择/高亮模型，不能用它宣称实际右键手势、全局快捷键和 PopCoordinator 执行链路已经验收。

`POP_DEMO=1` 本身不满足上述隔离条件：生产控制器仍会先创建标准设置/剪贴板服务、启动插件管理、权限监视和云同步，之后才进入演示流程。不要用真实 App 加 POP_DEMO 代替此入口。

## 控件与场景

上方 Ring/Features/Library 切换场景。Dark 和 Reduce Motion 只作用于 fixture 中的视图，不改变系统设置。中文/English 按钮用 `-AppleLanguages` 新进程参数重开同一个 fixture，不写生产 App 或系统偏好；重开后场景回到默认圆盘。

1. 圆盘：Blue/White/Stripes 示例背景、1–12 格、Long names、Loading、浅/深色，鼠标划过不可用动作，观察中心说明；点击和方向键/回车只更新选择提示，Reset 重置。
2. 全部功能：搜索中文、英文、拼音首字母，↑↓移动并滚动到选择，回车、⌘1–9验证选择提示，关闭回到圆盘。列表使用生产核心描述和插件包静态清单，不加载插件实现。
3. 插件库：30 seconds 模式中关闭、重开，核对日志是否取消旧请求；等待完成后搜索和安装。
4. 插件库：Fail once, then succeed 模式先看到失败，重试后关闭；重开后重新读取，不能遗留旧请求的错误。
5. 两种语言和浅/深色重复长名称、空搜索结果、已安装状态检查。

## 连续屏幕边界预览

圆盘场景直接调用生产 `RingScreenBoundary`、`RingViewModel.freezePlacement` 和 `RingMenuView`。默认模拟屏幕为 1000×650 点；X/Y 滑杆没有位置预设或固定模式，也可在旁边数值框输入小数。展开 **Screen settings** 后，Width / Height 改变模拟物理屏幕，Menu bar 改变软件菜单栏条带，Dock 可选择无、底部、左侧或右侧的 56 点保留区；Notch 开关加入 160×32 点的合成物理遮挡。默认收起高级屏幕控件，为生产圆盘预览留出空间。所有这些控件都只作用于独立 fixture，不移动真实菜单栏或 Dock、不改变显示器设置。

- AppKit 坐标原点在模拟屏幕左下，Y 向上；Pixels/pt 为 1× 或 2×，决定生产求解器的显示像素精度。回显同时给出点与模拟像素，不把 Retina 的一个点称为一个物理像素。
- 预览只在最外层等比缩放以放入控件下方的独立区域；原屏幕固定尺寸、左上对齐，缩后占位也显式左上对齐，再在预览区域居中并裁切，避免 SwiftUI 缩放不改变布局尺寸而产生负偏移。输入、生产布局和诊断仍使用原始模拟屏幕坐标。鼠标先转换成相对原唤起点的偏移，不假设窗口中心等于唤起点。
- 绿色虚线是 Ring 可用区域，灰色顶部为软件菜单栏，黑色块是物理遮挡，橙色十字是原始唤起点；Bounds 显示每个入口的实际阴影包络，绿色表示完整容纳，红色表示越界或碰到物理遮挡。
- 诊断分开报告直接功能数和 More、半径、`targets contained`、hovered ID 与 invocation 序号；More 不计作直接功能。改变坐标、屏幕、格数或长名称会模拟新一次唤起，重新冻结生产 placement。Loading 只更新同一个模型的内容状态，invocation 序号和 placement 不应变化。
- `targets contained` 与绿色目标框只采用求解器相同的 `0.0000001` 点浮点容差；不会把一像素或一部分真实越界容许为通过。诊断另外输出目标距可用边缘的最小有符号 margin 和禁区相交深度，保留贴边浮点误差与真实裁切的区别。它只检查模拟屏幕内的生产目标包络，窗口里预览区域是否完整可见仍须截图验收。
- 连续 X/Y 调整复用与生产相同的单条内存缓存：配置、可用区、禁区和显示精度相同，且相邻唤起点相距不超过上次按钮最大边长时，将原切口作为几何求解偏好。每次更新参考锚点；距离过大或其他布局参数改变就重新决定方向，不持久化、不增加 UI 开关。切口不可继续容纳或回到正常圆盘时仍由生产求解器处理。
- 点击 More 或键盘选中后回车显示生产 `RingOverflowView`，点击、方向键/回车只进入假选择回显。返回圆盘复用原模型和冻结位置，Esc 关闭更多列表。
- 数值框编辑期间，窗口不把方向键/回车转发为菜单操作。编辑完成后点预览或用 Tab 离开字段，再验证圆盘键盘导航。

建议按连续坐标验收，而不是只拍少数预设点：

1. 保持 8 或 12 格，沿 X 从 0 滑到屏幕宽度、沿 Y 从 0 滑到屏幕高度，检查四边、四角与过渡位置；再对临界位置输入相差 `1 / Pixels per pt` 点的数值，观察相邻像素是否突然跳转方向或过早出现 More。
2. 四角附近同时调整 X/Y，穿过到两条边距离相同的位置；观察同一功能的方向、目标大小和顺序，避免整个菜单突然转向或被拉成巨大的扇形。
3. 把 Y 放在顶部菜单栏条带内；无 Notch 时顶部不应因为软件菜单栏而被整体禁用。有 Notch 时分别观察其左侧、正下方与右侧，所有实际按钮包络必须避开黑色禁区。
4. 开启左、右、底部 Dock，检查可用区域对应保留；切换 1×/2×、长名称、浅深色与背景，确认诊断和视觉一致。Loading 开关以及 More 返回不能改变同一次唤起的 placement。

这些场景覆盖注入屏幕几何下的生产 Ring 排列和局部指针/键盘选择，不覆盖实际 NSPanel 窗口层级、真实硬件刘海、右键按住拖动、全局快捷键、权限或发行签名门禁。截图结论应明确属于隔离预览；不能把模拟软件菜单栏称为已在真实菜单栏上验收。

生产屏幕快照只给 Ring 放开顶部软件菜单栏，卡片和提示仍使用原来的 `visibleFrame`。刘海禁区通过 `safeAreaInsets.top` 的顶部条带扣除 NSScreen 已报告为不受遮挡的全局坐标矩形；不猜测真实刘海宽度。Apple API 说明：[safeAreaInsets](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets)、[auxiliaryTopLeftArea](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea-uglc)、[auxiliaryTopRightArea](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytoprightarea-gr2n)。若有顶部遮挡但辅助区域元数据缺失，保守保留整个顶部遮挡条带。

## 翻译卡片取消

Translate 场景直接显示生产 TranslationCardView，AI/DeepL 使用只产出一次长文本、保持未完成的离线流，系统引擎始终不可用。模型在 Close 后故意仍被场景持有，活动流数和 requests.log 的 translation.start / translation.cancel 可核对视图消失是否真正取消工作；再次打开应有新请求。流不会完成，因此不会出现朗读、复制、贴图等完成后操作；设置、下载和其他外部动作均为空适配器。
