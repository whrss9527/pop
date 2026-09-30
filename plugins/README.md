# 插件库

这个文件夹是 Pop 的插件库。Pop 在「设置 → 功能 → 插件库」里读取这里的 `index.json`，列出所有插件；点「安装」时下载对应的插件文件，核对 sha256 对得上才装进插件文件夹。

## 分享自己的插件

1. 在 Pop 里做好插件，在「我的插件」里点插件右边的「…」→「导出…」，得到一个 JSON 文件；文件名改成插件 ID（比如 `douban.json`），放进这个文件夹。插件 ID 只能用字母、数字、`.`、`-`、`_`，不能和已有的插件重复。
2. 算出文件的 sha256：

   ```sh
   shasum -a 256 plugins/douban.json
   ```

3. 在 `index.json` 的 `plugins` 里加一项，把上一步的结果填进 `sha256`：

   ```json
   {
     "id": "douban",
     "name": "豆瓣",
     "summary": "在豆瓣上搜书、电影和音乐",
     "author": "你的名字",
     "symbol": "film",
     "type": "url",
     "url": "douban.json",
     "sha256": "d47ea1ccf79da3279678aa85cd8791a1c89b6eb8ef2b89b568e5c5d6b793815d"
   }
   ```

4. 提交合并请求。单元测试会检查 `index.json` 和插件文件对得上：每一项都有文件、sha256 一致、名称和图标跟插件文件里的一样，文件夹里的插件也都列在索引里。改了插件文件要重新算 sha256；已经装过的用户会在插件库里看到「更新」。

## index.json 的字段

| 字段 | 说明 |
| --- | --- |
| `id` | 插件 ID，和插件文件里的 `id` 一样 |
| `name` / `summary` / `symbol` | 列表里显示的名称、说明和 [SF Symbol](https://developer.apple.com/sf-symbols/) 图标名，和插件文件里的一样 |
| `author` | 作者 |
| `type` | 插件的动作类型（`url`、`shell`、`javascript`、`shortcut`、`ai`），和插件文件里的 `action.type` 一样 |
| `url` | 插件文件的地址，写相对 `index.json` 的路径（比如 `douban.json`） |
| `sha256` | 插件文件的 SHA-256，小写十六进制 |

插件文件的格式见 [README 里的「自定义插件」](../README.md#自定义插件)。运行 Shell 脚本的插件，安装前 Pop 会先把脚本给用户看，同意了才装。
