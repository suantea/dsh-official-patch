#!/bin/bash
# =============================================================================
# DSH Desktop（官方正式包）补丁脚本 —— 拖入非图片文件 → 文件名 chip + @路径 引用
#
# 原理：
#   1. preload 注入 dshDesktopFileBridge（webUtils 取真实路径）
#   2. intakeImages 分流：非图片写 window.dshDesktopPendingFilePaths[]
#   3. paste() 拦截器：检测 @路径 格式 → 替换成 U+FFFC → detectReference 管道自动渲染 chip
#   4. Je$2 命令：拖拽时提取路径写入 pending 数组
#
# 流程：备份 → 一次性注入三处补丁（幂等）→ ad-hoc 重签 → 清除隔离
# 官方更新后补丁会被覆盖，重跑本脚本即可。
#
# 用法：
#   ./install-patch.sh [应用路径]      # 默认 /Applications/DSH Desktop.app
# =============================================================================
set -euo pipefail

APP="${1:-/Applications/DSH Desktop.app}"
ROOT="$APP/Contents/Resources/app"
CONV="$ROOT/node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js"
PRELOAD="$ROOT/out/preload/index.cjs"
MARKER="dshDesktopFileBridge"

echo "==> DSH Desktop 拖放文件补丁安装脚本"
echo "==> 目标应用：$APP"

# ---------- 前置检查 ----------
if [ ! -f "$CONV" ]; then
  echo "错误：找不到 conversation 包文件：$CONV" >&2
  exit 1
fi
if [ ! -f "$PRELOAD" ]; then
  echo "错误：找不到 preload 产物：$PRELOAD" >&2
  exit 1
fi
if pgrep -f "DSH Desktop" > /dev/null 2>&1; then
  echo "警告：DSH Desktop 正在运行。请先退出应用再继续（运行中的进程可能回写文件）。"
  echo "（按 Ctrl-C 取消，或 5 秒后继续）"
  sleep 5
fi

# ---------- 幂等检查 ----------
if grep -q "$MARKER" "$CONV" && grep -q "$MARKER" "$PRELOAD"; then
  echo "==> 补丁均已应用，无需重复操作。"
  exit 0
fi

# ---------- 备份 ----------
backup() {
  local f="$1"
  if [ ! -f "$f.dshbak" ]; then
    cp -p "$f" "$f.dshbak"
    echo "==> 已备份：$(basename "$f") → $(basename "$f").dshbak"
  fi
}
backup "$CONV"
backup "$PRELOAD"

# ---------- 一次性注入三处补丁 ----------
python3 - "$CONV" "$PRELOAD" "$MARKER" <<'PY'
import sys

conv_path, preload_path, marker = sys.argv[1], sys.argv[2], sys.argv[3]

def fail(msg):
    print("错误：%s" % msg, file=sys.stderr)
    sys.exit(1)

def read(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()

def write(path, data):
    with open(path, "w", encoding="utf-8") as f:
        f.write(data)

# ── 锚点（三处） ──────────────────────────────────────────────────────────────
anchor_intake = (
    "\t\t\tconst intakeImages = (0, react.useCallback)((files) => {\n"
    "\t\t\t\tif (addImages === void 0 || files.length === 0) return;\n"
)
anchor_paste = (
    "\t\t\tpaste(text) {\n"
    "\t\t\t\tconst clean = text.replace(REFERENCE_PLACEHOLDER_RE, \"\");\n"
)
anchor_je2 = (
    "\t\t\t}, 4), editor.registerCommand(Je$2, (event) => {\n"
    "\t\t\t\tconst clipboardData = event.clipboardData ?? null;\n"
    "\t\t\t\tif (clipboardData === null) return false;\n"
    "\t\t\t\tconst files = Array.from(clipboardData.items).filter((item) => item.kind === \"file\").map((item) => item.getAsFile()).filter((file) => file !== null);\n"
    "\t\t\t\tif (files.length > 0) handlers.intakeFiles(files);\n"
)

# ── 插入块 ────────────────────────────────────────────────────────────────────
block_intake = (
    "\t\t\t\tconst bridge = typeof window !== \"undefined\" && window.dshDesktopFileBridge || null;\n"
    "\t\t\t\tif (bridge !== null && typeof bridge.getPathForFile === \"function\") {\n"
    "\t\t\t\t\tconst images = [], refs = [];\n"
    "\t\t\t\t\tfor (const file of files) {\n"
    "\t\t\t\t\t\tif (imageLimits !== void 0 && imageLimits.mediaTypes.includes(file.type)) { images.push(file); continue; }\n"
    "\t\t\t\t\t\tlet path = null;\n"
    "\t\t\t\t\t\ttry { path = bridge.getPathForFile(file); } catch (error) { path = null; }\n"
    "\t\t\t\t\t\tif (typeof path === \"string\" && path !== \"\") refs.push(path); else images.push(file);\n"
    "\t\t\t\t\t}\n"
    "\t\t\t\t\tif (refs.length > 0) window.dshDesktopPendingFilePaths = refs;\n"
    "\t\t\t\t\tif (images.length === 0) return;\n"
    "\t\t\t\t\tfiles = images;\n"
    "\t\t\t\t}\n"
)
block_paste = (
    "\t\t\t\t// DSH Desktop patch: @/path → U+FFFC so detectReference renders a chip\n"
    "\t\t\t\ttext = text.replace(/@(?:@|&quot;([^&]*?)&quot;|([^\\s]+))/gu, (_, q, plain) => {\n"
    "\t\t\t\t\tconst p = q !== undefined ? q : plain;\n"
    "\t\t\t\t\treturn window.dshDesktopPendingFilePaths && window.dshDesktopPendingFilePaths.includes(p) ? \"\\uFFFC\" : \"@\" + p;\n"
    "\t\t\t\t});\n"
)
block_je2 = (
    "\t\t\t\tif (files.length > 0) {\n"
    "\t\t\t\t\tconst bridge = typeof window !== \"undefined\" && window.dshDesktopFileBridge;\n"
    "\t\t\t\t\tif (bridge && typeof bridge.getPathForFile === \"function\") {\n"
    "\t\t\t\t\t\tconst refs = [];\n"
    "\t\t\t\t\t\tfor (const f of files) {\n"
    "\t\t\t\t\t\t\ttry { const p = bridge.getPathForFile(f); if (typeof p === \"string\" && p !== \"\") refs.push(p); } catch(e) {}\n"
    "\t\t\t\t\t\t}\n"
    "\t\t\t\t\t\tif (refs.length > 0) window.dshDesktopPendingFilePaths = refs;\n"
    "\t\t\t\t\t}\n"
    "\t\t\t\t\thandlers.intakeFiles(files);\n"
    "\t\t\t\t}\n"
)

# ── 注入 conversation ─────────────────────────────────────────────────────────
data = read(conv_path)
if marker in data:
    print("==> conversation：已打过补丁，跳过。")
else:
    for anchor, block, name in [
        (anchor_intake, block_intake, "intakeImages"),
        (anchor_paste, block_paste, "paste()"),
        (anchor_je2, block_je2, "Je$2"),
    ]:
        n = data.count(anchor)
        if n == 0:
            fail("%s：锚点未找到（%d 次），可能是版本不匹配。" % (name, n))
        if n > 1:
            fail("%s：锚点匹配 %d 次（应为 1），请勿手动改动后重试。" % (name, n))
        data = data.replace(anchor, anchor + block, 1)
        print("==> %s：补丁已应用。" % name)
    write(conv_path, data)

# ── 注入 preload ──────────────────────────────────────────────────────────────
preload_data = read(preload_path)
if marker in preload_data:
    print("==> preload：已打过补丁，跳过。")
else:
    anchors = [
        'electron.contextBridge.exposeInMainWorld("dshDesktopDirectoryPicker", {\n  pick: () => electron.ipcRenderer.invoke("directory-picker:open")\n});',
        "electron.contextBridge.exposeInMainWorld('dshDesktopDirectoryPicker', {\n  pick: () => electron.ipcRenderer.invoke('directory-picker:open')\n});",
        'electron.contextBridge.exposeInMainWorld("dshDesktopDirectoryPicker", {\n  pick: () => electron.ipcRenderer.invoke("directory-picker:open")\n})',
        "electron.contextBridge.exposeInMainWorld('dshDesktopDirectoryPicker', {\n  pick: () => electron.ipcRenderer.invoke('directory-picker:open')\n})",
    ]
    block_pre = (
        '\nelectron.contextBridge.exposeInMainWorld(\n'
        '  "dshDesktopFileBridge",\n'
        '  Object.freeze({\n'
        '    isDesktop: true,\n'
        '    getPathForFile: (file) => {\n'
        '      try {\n'
        '        return electron.webUtils.getPathForFile(file);\n'
        '      } catch {\n'
        '        return null;\n'
        '      }\n'
        '    }\n'
        '  })\n'
        ');'
    )
    applied = False
    for cand in anchors:
        if preload_data.count(cand) == 1:
            preload_data = preload_data.replace(cand, cand + block_pre, 1)
            applied = True
            break
    if not applied:
        idx = preload_data.find("dshDesktopDirectoryPicker")
        if idx >= 0:
            snippet = preload_data[max(0, idx-60): idx+160]
            fail("preload 锚点未精确匹配。现场片段：\n---\n%s\n---" % snippet)
        fail("preload 中找不到 dshDesktopDirectoryPicker，请反馈。")
    write(preload_path, preload_data)
    print("==> preload：dshDesktopFileBridge 已注入。")

PY

# ---------- 校验 ----------
grep -q "$MARKER" "$CONV" || { echo "错误：conversation 补丁校验失败" >&2; exit 1; }
grep -q "$MARKER" "$PRELOAD" || { echo "错误：preload 补丁校验失败" >&2; exit 1; }
echo "==> 三处补丁内容校验通过。"

# ---------- ad-hoc 重签 + 清隔离 ----------
echo "==> ad-hoc 重新签名..."
codesign --force --deep --sign - "$APP"
xattr -dr com.apple.quarantine "$APP" 2> /dev/null || true

if codesign --verify --deep --strict "$APP" 2> /tmp/dsh-codesign-verify.txt; then
  echo "==> 签名校验通过。"
else
  echo "警告：codesign 校验未通过："
  cat /tmp/dsh-codesign-verify.txt
fi

echo ""
echo "✅ 完成！启动 DSH Desktop，把 PDF/txt/md/docx 拖进对话测试。"
echo "   若 Gatekeeper 拦截：右键 DSH Desktop.app → 打开。"
echo "   官方应用日后自动更新后补丁会被覆盖，届时重跑本脚本即可。"
