# 插件目录观察契约

这是 #100 的第一项数据交付，不改变生产启动、注册、路由、下载索引或装载时机。快照不能直接当作已签名、可信的生产 catalog，也不等于按需装载已完成。

`PopCatalog` 是独立原生测试宿主，不编入 PluginBundles 源码。工作流先用原 Pop scheme 构建 App 和全部实际 bundle，再在两个新进程中按 zh-Hans/en 执行该测试。只查询自己的构建目录、核对包ID/版本/build，并调用 makePlugins 取得 info；不调用 didLoad、willUninstall 或功能执行入口。这样独立包也使用实际 bundle 的本地化资源，避免把原 PopTests 的重复类或缺失资源当成真实装载。

快照包含主程序与包的分别归属、展示顺序、名称/说明、分类/符号、清理偏好/钥匙串账号名/相对数据目录，以及功能 accepts、pattern、min/max、source、hidesOverlay、optionalContent 和 check。独立发布的 SleepTimer 保留自己的包版本与资源；不把它写成主程序内建功能。新增 PluginInfo 存储字段会让原生观察契约显式失败，不能悄悄漏掉。

`scripts/catalog-contract.py` 拒绝未知版本/字段、重复包/功能归属、空本地化、类型/长度/路径错误和未知check；两语言除名称/说明外的结构、构建与约束必须一致。正则由原生 NSRegularExpression 实际编译，Python 不用另一种方言近似。custom 仅记录12种现有ID，闭包不会序列化成JSON，也不声称匹配语义已经等价；那需要后续正反语料及受控执行验证。

工作流分别记录 macOS15/26 的 SHA、系统和 Xcode，保留构建/测试日志、原始 xcresult、附件及两语合并观察结果。跨系统差异需单独评估；当前观察快照不是跨系统兼容证明。

后续才将验证的数据变为每包描述并建立实际 parity、统一生成 targets/TestCatalog/截图计划，最后按构建/信任与代际改按需解析。当前还不能删除生产目录或把未载入的检查默认当成 true。
