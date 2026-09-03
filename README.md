# dsh-official-patch

给 **DSH Desktop 官方正式包**（v0.7.x）就地打补丁的一键脚本：把对话输入框拖入/粘贴的**非图片文件**（PDF / Word / txt / md 等）转成本地 `@路径` 文件引用，agent 按路径直接读取。

> 背景：DSH 官方只允许拖图片（jpg/png/webp/gif）。根因是拖放接入了「图片附件通道」，Host 端 mediaTypes 写死为 4 种图片，且沙箱页面拿不到文件真实路径。本补丁走官方正式包 + 两处小改动，不动插件生态、可随时被官方更新覆盖后重跑。

## 原理（两处改动）

1. **preload 注入 `dshDesktopFileBridge`**
   在 `Resources/app/out/preload/index.cjs` 注入 `getPathForFile(file)`，用 Electron `webUtils` 把拖入的 File 解析成真实磁盘路径（web Harness 无此桥，自动回落原行为）。
2. **conversation 拖放分流**
   在 `dsh-client-ui-conversation` 的 `intakeImages` 收口处按类型分流：图片走原附件通道不变；非图片经桥取路径后，插入 `@/绝对路径`（含空格自动 `@"..."`）作为文件引用文本。

改完用 `codesign --force --deep --sign -` ad-hoc 重签，否则 macOS 拒绝启动修改过的签名包。

## 用法

```bash
# 默认目标 /Applications/DSH Desktop.app；装别处就传路径
./install-patch.sh
./install-patch.sh "/path/to/DSH Desktop.app"
```

脚本行为：

- **备份**：每个被改文件旁生成一份 `*.dshbak`（仅首次）；
- **幂等**：检测到两处补丁已应用则直接退出，可安全重复执行；
- **校验**：锚点匹配失败即中止并打印现场片段（版本漂移时据此适配）；
- **重签**：ad-hoc 深签 + 清除 quarantine 属性。

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
