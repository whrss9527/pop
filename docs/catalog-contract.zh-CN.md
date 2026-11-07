# 插件目录观察契约

这是 #100 的第一项数据交付，不改变生产启动、注册、路由、下载索引或装载时机。快照不能直接当作已签名、可信的生产 catalog，也不等于按需装载已完成。

`PopCatalog` 是独立原生测试宿主，不编入 PluginBundles 源码。工作流先用原 Pop scheme 构建 App 和全部实际 bundle，再在两个新进程中按 zh-Hans/en 执行该测试。只查询自己的构建目录、核对包ID/版本/build，并调用 makePlugins 取得 info；不调用 didLoad、willUninstall 或功能执行入口。这样独立包也使用实际 bundle 的本地化资源，避免把原 PopTests 的重复类或缺失资源当成真实装载。

快照包含主程序与包的分别归属、展示顺序、名称/说明、分类/符号、清理偏好/钥匙串账号名/相对数据目录，以及功能 accepts、pattern、min/max、source、hidesOverlay、optionalContent 和 check。独立发布的 SleepTimer 保留自己的包版本与资源；不把它写成主程序内建功能。新增 PluginInfo 存储字段会让原生观察契约显式失败，不能悄悄漏掉。

`scripts/catalog-contract.py` 拒绝未知版本/字段、重复包/功能归属、空本地化、类型/长度/路径错误和未知check；两语言除名称/说明外的结构、构建与约束必须一致。正则由原生 NSRegularExpression 实际编译，Python 不用另一种方言近似。custom 仅记录12种现有ID，闭包不会序列化成JSON，也不声称匹配语义已经等价；那需要后续正反语料及受控执行验证。

工作流分别记录 macOS15/26 的 SHA、系统和 Xcode，所有构建和两语言测试都显式使用源码 SHA 作为 `POP_BUILD_ID`。正式导出必须读取 `metadata.json`，要求其中的源码和两语快照的 `buildID` 都与调用方传入的完整 SHA 一致；不能用两个相同的 `dev` 标识代替来源核验。保留构建/测试日志、原始 xcresult、附件及两语合并观察结果。跨系统差异需单独评估；当前观察快照不是跨系统兼容证明。

`evidence.json` 保存中文原始快照、英文原始快照、元数据和合并目录各自的相对路径、字节数及 SHA-256。路径必须留在清单所在目录内，包括符号链接解析后的路径；输出不能覆盖输入。导出后立即重新读取并核验全部文件，后续下载 artifact 也可以独立复核：

```sh
python3 scripts/catalog-contract.py export \
  --zh build/native-catalog/exports/zh-Hans --en build/native-catalog/exports/en \
  --metadata build/native-catalog/metadata.json --source "$GITHUB_SHA" \
  --output build/native-catalog/contract.json --manifest build/native-catalog/evidence.json
python3 scripts/catalog-contract.py verify \
  --manifest build/native-catalog/evidence.json --source "$GITHUB_SHA"
```

复核时的 SHA 应取自所审查的提交或运行记录，不从清单自行推定。文件摘要用于发现附件替换、损坏和混用，并将系统/Xcode元数据与同一观察结果关联；它不是数字签名，不能证明可编辑清单的真实性、执行环境可信或 custom 闭包语义等价。旧的 `buildID=dev` artifact 仍可通过库函数 `merge` 进行纯结构复核，不能追认成新的来源绑定验收通过。

后续才将验证的数据变为每包描述并建立实际 parity、统一生成 targets/TestCatalog/截图计划，最后按构建/信任与代际改按需解析。当前还不能删除生产目录或把未载入的检查默认当成 true。
