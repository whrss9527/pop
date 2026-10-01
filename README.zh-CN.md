<div align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Pop 图标">
  <h1>Pop</h1>
  <p><strong>长按右键，一划即达</strong></p>
  <p>住在 macOS 菜单栏里的右键工具箱。原生 Swift，玻璃质感，开源免费。</p>
  <p>
    <a href="https://github.com/whrss9527/pop/releases"><img alt="最新版本" src="https://img.shields.io/github/v/release/whrss9527/pop?include_prereleases&label=release&color=5B7BFF"></a>
    <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-111827?logo=apple&logoColor=white">
    <img alt="Liquid Glass" src="https://img.shields.io/badge/UI-Liquid%20Glass-7C6CFF">
    <a href="LICENSE"><img alt="GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-2563EB"></a>
  </p>
  <p><a href="README.md">English</a> · <b>简体中文</b></p>
  <p>
    <a href="https://github.com/whrss9527/pop/releases"><b>下载</b></a> ·
    <a href="CHANGELOG.md">更新日志</a> ·
    <a href="plugins/README.md">插件库</a>
  </p>
</div>

### **Pop** /pɒp/

听起来就像“泡泡”。

按住右键，一个泡泡从鼠标旁边冒出来；朝想去的方向一划，松手，泡泡“啵”地一下破掉，事情也就办完了。

英文里的 **pop**，既有“突然出现”的感觉，也有泡泡破掉时那声轻快的“啵”。**Pop** 想表达的，就是一种轻量、直接、用完即走的交互方式。

## 特性

- **长按右键就出来**：短按还是系统右键菜单，长按才是 Pop，游戏和 3D 软件的右键拖动也不受影响。
- **一划就办完**：圆盘上 80 多个功能随你摆，往那一格一划、松手就执行。
- **选中什么，就给什么**：外文直接翻译，算式直接出结果，单位、颜色直接换算，图片直接识字。
- **自己加功能**：网址、Shell、JavaScript、快捷指令都能写成插件，插件库里点一下就装。
- **顺手的小工具**：剪贴板历史、贴图、截图标注、屏幕取色和标尺，还有 AI 润色、总结、解释。
- **数据在你这儿**：Pop 没有服务器，剪贴板历史只存在本机，API Key 只放在钥匙串里。

## 安装

需要 macOS 15 或更新版本。

用 [Homebrew](https://brew.sh) 安装：

```sh
brew install --cask whrss9527/tap/pop
```

或者手动安装：

1. 在 [Releases](https://github.com/whrss9527/pop/releases) 下载最新的 `Pop-<版本>.zip`，解压后把 `Pop.app` 拖进「应用程序」。
2. 第一次打开时，按提示在「系统设置 → 隐私与安全性 → 辅助功能」里打开 Pop。
3. 以后有新版本，在 App 里点一下就更新好。

没经过苹果公证的包，第一次打开前先在终端运行 `xattr -dr com.apple.quarantine /Applications/Pop.app`。

## 上手

| 操作 | 效果 |
| --- | --- |
| 选中外文，长按右键 | 直接弹出翻译 |
| 选中算式、带单位的数值、颜色或图片，长按右键 | 直接算出结果、换算单位、转换颜色、识别文字 |
| 其他时候长按右键 | 弹出圆盘，往一格划过去、松手就执行 |
| 在圆心松开，或按 Esc | 关掉圆盘 |
| 数字键 1–9、0 | 直接选格 |
| 「设置 → 功能」 | 装哪些功能、放在哪一格，都由你定 |

## 文档

- [使用指南](docs/guide.zh-CN.md)：安装与更新、全部功能、自定义插件、链接与快捷指令、数据存在哪里、已知限制
- [开发指南](docs/development.zh-CN.md)：构建运行、目录结构、扩展功能、发布与签名
- [插件库](plugins/README.md)：分享你写的插件
- [更新日志](CHANGELOG.md)

## 支持

Pop 免费开源。觉得好用的话，点个 ⭐ Star 就是很大的鼓励；也可以微信扫一扫请我喝杯咖啡（App 里「设置 → 更新」也有这张码）。

<p align="center"><img src="Pop/Resources/donate-wechat.png" width="240" alt="微信赞赏码：请我喝杯咖啡"></p>

## 许可证

Copyright © 2026 whrss9527

Pop 是自由软件，以 [GNU 通用公共许可证第 3 版（GPL-3.0）](LICENSE) 发布：可以自由使用、研究、修改和分享；分发 Pop 或修改后的版本时，需要以同样的许可证提供源代码。

「Pop」这个名字和 Pop 的图标不在 GPL 授权范围内（GPL-3.0 第 7 条 e 项）。介绍 Pop、分享未经修改的副本时可以使用；分发修改后的版本时，请换用自己的名字和图标。

贡献需接受 [CONTRIBUTING.md](CONTRIBUTING.md) 里的贡献者协议。

---

<div align="center">
  <p><b>同样住在菜单栏里</b></p>
  <a href="https://github.com/whrss9527/meno"><img src="https://raw.githubusercontent.com/whrss9527/whrss9527/master/assets/cards/meno.svg" width="30%" alt="Meno：安静的菜单栏，由玻璃打造"></a>
  <a href="https://github.com/whrss9527/stox"><img src="https://raw.githubusercontent.com/whrss9527/whrss9527/master/assets/cards/stox.svg" width="30%" alt="Stox：一眼看盘，一键隐身"></a>
  <a href="https://github.com/whrss9527/proxi"><img src="https://raw.githubusercontent.com/whrss9527/whrss9527/master/assets/cards/proxi.svg" width="30%" alt="Proxi：一个开关，管好所有代理"></a>
</div>
