# 隔离的本机 UI 验收入口

`scripts/build-ui-fixture.sh` 只构建 `build/ui-fixture/PopUIFixture.app`，不启动应用。默认构建并发为 2。手动验收时只打开这个包，不替换已安装的 Pop。

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

1. 圆盘：4/8/12 格、Long names、Loading、浅/深色，鼠标划过不可用动作，观察中心说明；点击和方向键/回车只更新选择提示，Reset 重置。
2. 全部功能：搜索中文、英文、拼音首字母，↑↓移动并滚动到选择，回车、⌘1–9验证选择提示，关闭回到圆盘。列表使用生产核心描述和插件包静态清单，不加载插件实现。
3. 插件库：5 seconds 模式中关闭、重开，核对日志是否取消旧请求；等待完成后搜索和安装。
4. 插件库：Fail once, then succeed 模式先看到失败，重试后关闭；重开后重新读取，不能遗留旧请求的错误。
5. 两种语言和浅/深色重复长名称、空搜索结果、已安装状态检查。

当前圆盘为普通中心圆盘，未覆盖真实屏幕边缘扇形、NSPanel 浮窗位置、右键按住拖动、权限或发行签名门禁。截图结论应明确属于此隔离入口。
