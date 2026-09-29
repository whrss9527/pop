# 工作约定

## 改完怎么合并、怎么发版

- 在自己的分支上改，推上去开合并请求。合并进 main 之前 CI 要全部通过：两个版本的 Xcode 编译和单元测试，macOS 15、macOS 26 上的启动测试、一键更新的端到端测试、签名流程自测和浮窗截图。
- 要发版本，就在 CHANGELOG.md 最上面加一节新版本，格式：`## 0.4.0（2026-09-29）`。推到 main、CI 通过后，CI 发现这个版本还没有标签，就自动打标签、打包并发布正式版，已安装的 Pop 会提示更新。用户能感觉到的改动都要写进去；只改 CI、文档或测试的可以不加，不加就只合并、不发版。
- 版本号：新功能升次版本号（0.3.1 升到 0.4.0），只修问题升修订号（0.4.0 升到 0.4.1）。先看 main 上最新的版本和标签，别和别的分支撞号；`project.yml` 里的 `MARKETING_VERSION` 跟着改。
- 想先给少数人试用：在 Actions 页面手动运行 Release 工作流，勾选「作为测试版」，或者 `make release VERSION=0.4.0 BETA=1`。

## 写法

- 代码注释、界面文字、README 和更新日志用中文；提交信息用英文，风格照 git log。
- 项目里不要写「类似某某」「相当于某某的……」这种拿别的产品作比较的话，直接说功能本身。
- shell 脚本里变量后面紧跟中文或全角符号时写成 `${VAR}`：macOS 自带的 bash 3.2 会把多字节字符的一部分当成变量名。

## 看浮窗的效果

- 浮窗的动画参数都在 `Pop/UI/Motion.swift`，玻璃效果在 `Pop/UI/Glass.swift`（macOS 26 上是 Liquid Glass，更早的系统用窗口后面的模糊）。
- CI 用演示模式（`POP_DEMO=1`，`POP_ANIMATION_SCALE` 把动画放慢）把圆盘、结果卡片、提示、列表走一遍，按时截图，推到 `ci-screenshots/macos-15` 和 `ci-screenshots/macos-26` 两个分支（每次覆盖）。改了浮窗之后 `git fetch origin ci-screenshots/macos-26` 就能看到动画的中间帧。
- 本机也能跑：`scripts/overlay-screenshots.sh build/app/.../Pop.app 截图目录 6`。
