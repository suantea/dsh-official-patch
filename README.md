# dsh-official-patch

给 **DSH Desktop 官方正式包**（v0.7.x）就地打补丁的一键脚本：把对话输入框拖入/粘贴的**非图片文件**（PDF / Word / txt / md 等）转成本地 `@路径` 文件引用，agent 按路径直接读取。

> 背景：DSH 官方只允许拖图片（jpg/png/webp/gif）。根因是拖放接入了「图片附件通道」，Host 端 mediaTypes 写死为 4 种图片，且沙箱页面拿不到文件真实路径。本补丁走官方正式包 + 两处小改动，不动插件生态、可随时被官方更新覆盖后重跑。

## 原理（两处改动）

1. **preload 注入 `dshDesktopFileBridge`**
   在 `Resources/app/out/preload/index.cjs` 注入 `getPathForFile(file)`，用 Electron `webUtils` 把拖入的 File 解析成真实磁盘路径（web Harness 无此桥，自动回落原行为）。
2. **conversation 拖放分流 + 文件名 chip**
   在 `dsh-client-ui-conversation` 的 `intakeImages` 收口处按类型分流：图片走原附件通道不变；非图片经桥取路径后，**直接注入官方 `ReferenceChipNode`（显示文件名 chip）**，发送时以 `@/绝对路径`（含空格自动 `@"..."`）作为文件引用序列化。若 chip 注入不可用（如焦点丢失），自动回退为插入纯文本 `@路径`。

附带改动：`paste()` 挂起路径转 U+FFFC 走官方 chip 渲染、粘贴文件事件取路径、11 处界面文案汉化（详见下方）。脚本对每个注入点支持**多版本锚点候选列表**（候选 1/2…），官方更新导致代码漂移时自动尝试下一组。

改完用 `codesign --force --deep --sign -` ad-hoc 重签，否则 macOS 拒绝启动修改过的签名包。

## 安装流程（首次）

```bash
# 1. 确认已装回官方正式版（不是 fork 版），默认装在 /Applications/DSH Desktop.app
ls "/Applications/DSH Desktop.app/Contents/Resources/app/node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js"

# 2. 跑一次脚本即可
~/dev/dsh-official-patch/install-patch.sh

# 3. 启动 DSH Desktop
open -a "DSH Desktop"
```

**测试**：把 PDF / Word / txt / md 拖进对话输入框，应看到**文件名 chip**（图标 + 文件名）被插入；图片仍走原附件通道不变。发出去让 agent 按 `@路径` 读取即可。

## 使用方式

补丁装好并启动 DSH Desktop 后，日常这样用：

1. **拖入文件**：从访达把 PDF / Word / txt / md 等直接拖进对话输入框，会插入一个**文件名 chip**（图标 + 文件名，如 `📄 产品需求文档.pdf`）；发送时序列化为 `@/绝对路径` 文件引用（路径含空格自动 `@"绝对路径"`）。
2. **发送即可读取**：直接按 Enter 发送，agent 会按 `@路径` 去本机读取文件内容——适合读长文档、代码、数据文件，不用把内容贴进对话。
3. **图片行为不变**：jpg / png / webp / gif 仍走原来的图片附件通道（缩略图预览），不受影响。
4. **手动输入同样有效**：想引用某文件时也可直接打字 `@/路径/文件名`（空格路径用 `@"/路径/文件名"`），效果与拖入一致。
5. **示例**：
   ```
   请总结一下这份文档的重点：@/Users/me/Downloads/产品需求文档.pdf
   ```

**注意事项**：
- agent 读取的是**本机绝对路径**，文件需停留在原位置；移动/删除文件或换机器后引用会失效。
- 扫描版 PDF（纯图片、无文字层）agent 读不到文字，需先经 OCR 转成带文字层的 PDF 再拖入。

## 扫描件 OCR（dsh-ocr）

扫描版 PDF（纯图片、无文字层）agent 读不到文字，用仓库里的零依赖 OCR 工具（macOS 自带 Vision framework，无需安装任何东西）先转出文字层：

```bash
# 基本用法：输出 <输入名>.ocr.txt（每页文本）
~/dev/dsh-official-patch/dsh-ocr ~/Downloads/扫描件.pdf

# 同时输出带可搜索文字层的 <输入名>.ocr.pdf（白色隐形 FreeText 文字层，可搜索/复制）
~/dev/dsh-official-patch/dsh-ocr ~/Downloads/扫描件.pdf --pdf

# 指定语言 / 输出基名
~/dev/dsh-official-patch/dsh-ocr 扫描件.pdf --langs zh-Hans,en-US --out /tmp/out
```

支持 PDF 与 png/jpg 图片输入；识别完成后把带文字层的 PDF（或 `--out` 指定基名）拖进 DSH 即可被 agent 读取。要求 macOS 12+（Vision 中文识别），Apple Silicon / Intel 均可。

## 故障排查

| 现象 | 原因 | 解法 |
|---|---|---|
| 脚本报「找不到 client.js」 | 路径不对，不是官方包 | 把 .app 拖到终端自动填路径：`./install-patch.sh "$(find ~/Applications -name "DSH Desktop.app")"` |
| 脚本报「锚点匹配失败」 | 官方版本不同、代码已漂移 | 保留错误打印的现场片段发给维护者适配 |
| 启动被 Gatekeeper 拦 | ad-hoc 签名 macOS 需手动放行 | 右键应用 → 打开（只需操作一次） |
| 启动后仍说两个插件加载失败 | 插件是针对早期 harness 装的，与补丁无关 | 在启动失败弹窗里「卸载这 2 个插件」即可继续 |
| 官方提示有新版本 | 应用内置更新源（`dshdesktop.com`）会覆盖补丁 | 同意更新后重跑一次脚本（几秒） |
| 脚本显示「均已应用，无需重复操作」 | 之前已打过补丁 | 正常跳过，不是坏现象 |

## 备份、还原与卸载

**自动备份**：脚本首次跑时，会把将被替换的原始文件原地保留一份 `.dshbak`（conversation 的 `client.js` 与 preload 的 `index.cjs`），幂等——同一文件不重复覆盖，已打过补丁时直接跳过。附带应用的 11 处界面文案汉化随 `dsh-patch.py` 一并写入，无需单独备份：官方更新会把整个 `Resources/app` 重置为官方原样，届时重跑脚本即可全部恢复。

**还原（手动恢复原版）**：

```bash
cd "/Applications/DSH Desktop.app/Contents/Resources/app"
mv node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js.dshbak \
   node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js
mv out/preload/index.cjs.dshbak out/preload/index.cjs
codesign --force --deep --sign - "/Applications/DSH Desktop.app"
```

> 文件被替换后需重新 ad-hoc 签名；若已随官方更新覆盖（原文件本来就是官方原样），直接重跑本脚本即可，无需手动还原。

**官方更新后**：更新会覆盖补丁与汉化，重跑一次脚本（几秒）即可全部恢复，`.dshbak` 备份也会随之重新生成。

**卸载**：按上面「还原」步骤恢复原文件后不再跑脚本即可；或直接重装官方包。

## 注意

- 官方应用**自动更新后补丁会被覆盖**，届时重跑一次脚本（几秒）。
- 首次启动若被 Gatekeeper 拦截：右键 → 打开。
- 只适配 **macOS arm64**（Apple Silicon）的官方正式包。

## 兼容性

| 官方版本 | 打包 harness | conversation 拖放代码 | 结论 |
|---|---|---|---|
| v0.7.1 / v0.7.2 | `0.1.2-alpha.1` | 与 alpha.4 的 `intakeImages` 区域**逐字一致** | 补丁直接复用 ✅ |

已在官方 v0.7.2 真包（GitHub release `dsh-desktop-mac-arm64.zip`）上自测：备份/注入/分流/幂等/重签全通过。
