# dsh-official-patch

给 **DSH Desktop 官方正式包**（v0.7.x）就地打补丁的一键脚本：把对话输入框拖入/粘贴的**非图片文件**（PDF / Word / txt / md 等）转成本地 `@路径` 文件引用，agent 按路径直接读取。

> 背景：DSH 官方只允许拖图片（jpg/png/webp/gif）。根因是拖放接入了「图片附件通道」，Host 端 mediaTypes 写死为 4 种图片，且沙箱页面拿不到文件真实路径。本补丁走官方正式包 + 两处小改动，不动插件生态、可随时被官方更新覆盖后重跑。

## 原理（两处改动）

1. **preload 注入 `dshDesktopFileBridge`**
   在 `Resources/app/out/preload/index.cjs` 注入 `getPathForFile(file)`，用 Electron `webUtils` 把拖入的 File 解析成真实磁盘路径（web Harness 无此桥，自动回落原行为）。
2. **conversation 拖放分流**
   在 `dsh-client-ui-conversation` 的 `intakeImages` 收口处按类型分流：图片走原附件通道不变；非图片经桥取路径后，插入 `@/绝对路径`（含空格自动 `@"..."`）作为文件引用文本。

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

**测试**：把 PDF / Word / txt / md 拖进对话输入框，应能看到 `@/绝对路径` 被插入；图片仍走原附件通道不变。发出去让 agent 读取即可。

## 故障排查

| 现象 | 原因 | 解法 |
|---|---|---|
| 脚本报「找不到 client.js」 | 路径不对，不是官方包 | 把 .app 拖到终端自动填路径：`./install-patch.sh "$(find ~/Applications -name "DSH Desktop.app")"` |
| 脚本报「锚点匹配失败」 | 官方版本不同、代码已漂移 | 保留错误打印的现场片段发给维护者适配 |
| 启动被 Gatekeeper 拦 | ad-hoc 签名 macOS 需手动放行 | 右键应用 → 打开（只需操作一次） |
| 启动后仍说两个插件加载失败 | 插件是针对早期 harness 装的，与补丁无关 | 在启动失败弹窗里「卸载这 2 个插件」即可继续 |
| 官方提示有新版本 | 应用内置更新源（`dshdesktop.com`）会覆盖补丁 | 同意更新后重跑一次脚本（几秒） |
| 脚本显示「均已应用，无需重复操作」 | 之前已打过补丁 | 正常跳过，不是坏现象 |

## 卸载补丁

```bash
cd "/Applications/DSH Desktop.app/Contents/Resources/app"
mv node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js.dshbak \
   node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js
mv out/preload/index.cjs.dshbak out/preload/index.cjs
```

或直接重装官方包。

## 恢复 / 卸载补丁

删掉被修改的两个文件，把对应 `.dshbak` 改回原名即可（或直接重装官方包）：

```bash
cd "/Applications/DSH Desktop.app/Contents/Resources/app"
mv node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js.dshbak \
   node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js
mv out/preload/index.cjs.dshbak out/preload/index.cjs
```

## 注意

- 官方应用**自动更新后补丁会被覆盖**，届时重跑一次脚本（几秒）。
- 首次启动若被 Gatekeeper 拦截：右键 → 打开。
- 只适配 **macOS arm64**（Apple Silicon）的官方正式包。

## 兼容性

| 官方版本 | 打包 harness | conversation 拖放代码 | 结论 |
|---|---|---|---|
| v0.7.1 / v0.7.2 | `0.1.2-alpha.1` | 与 alpha.4 的 `intakeImages` 区域**逐字一致** | 补丁直接复用 ✅ |

已在官方 v0.7.2 真包（GitHub release `dsh-desktop-mac-arm64.zip`）上自测：备份/注入/分流/幂等/重签全通过。
