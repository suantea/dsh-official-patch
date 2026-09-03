#!/bin/bash
# =============================================================================
# DSH Desktop（官方正式包）补丁脚本 —— 拖入非图片文件 → 本地文件引用
#
# 作用：在官方 v0.7.x 安装包上就地应用两处小改动：
#   1. preload 注入 dshDesktopFileBridge（webUtils 取拖放文件真实路径）
#   2. dsh-client-ui-conversation 拖放分流：图片走原通道，非图片转 @路径 引用
# 流程：备份 → 打补丁（幂等，已打则跳过）→ ad-hoc 重签 → 清除隔离属性
#
# 注意：官方应用每次自动更新后补丁会被覆盖，重跑本脚本即可。
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
  echo "错误：找不到 conversation 包文件：$CONV"
  echo "请确认路径是官方 DSH Desktop 安装包（可在终端拖入 .app 获得路径）。" >&2
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
  echo "==> 两处补丁均已应用，无需重复操作。"
  exit 0
fi

# ---------- 备份（每个文件仅保留一份原始备份 .dshbak） ----------
backup() {
  local f="$1"
  if [ ! -f "$f.dshbak" ]; then
    cp -p "$f" "$f.dshbak"
    echo "==> 已备份：$(basename "$f") → $(basename "$f").dshbak"
  fi
}
backup "$CONV"
backup "$PRELOAD"

# ---------- 打补丁（字节级、带锚点校验，失败即中止） ----------
python3 - "$CONV" "$PRELOAD" "$MARKER" <<'PY'
import sys

conv_path, preload_path, marker = sys.argv[1], sys.argv[2], sys.argv[3]

def fail(msg):
    print("错误：%s" % msg, file=sys.stderr)
    sys.exit(1)

# ---- 1) conversation：intakeImages 拖放分流 ----
# 锚点：intakeImages 开头 + 守卫行（alpha.1/alpha.4 逐字一致，已实测）
anchor_conv = (
    "\t\t\tconst intakeImages = (0, react.useCallback)((files) => {\n"
    "\t\t\t\tif (addImages === void 0 || files.length === 0) return;\n"
)
# 插入块：非图片文件经桌面桥解析真实路径 → @路径 引用（显示文件名 chip）
block_conv = (
    "\t\t\t\tconst bridge = typeof window !== \"undefined\" && window.dshDesktopFileBridge || null;\n"
    "\t\t\t\tif (bridge !== null && typeof bridge.getPathForFile === \"function\") {\n"
    "\t\t\t\t\tconst images = [], refs = [];\n"
    "\t\t\t\t\tfor (const file of files) {\n"
    "\t\t\t\t\t\tif (imageLimits !== void 0 && imageLimits.mediaTypes.includes(file.type)) { images.push(file); continue; }\n"
    "\t\t\t\t\t\tlet path = null;\n"
    "\t\t\t\t\t\ttry { path = bridge.getPathForFile(file); } catch (error) { path = null; }\n"
    "\t\t\t\t\t\tif (typeof path === \"string\" && path !== \"\") refs.push(path); else images.push(file);\n"
    "\t\t\t\t\t}\n"
    "\t\t\t\t\tif (refs.length > 0 && editor !== null && !gate.current.locked && !gate.current.machineBusy) {\n"
    "\t\t\t\t\t\tconst refText = refs.map((p) => /\\s/.test(p) ? `@\"${p}\"` : `@${p}`).join(\" \") + \" \";\n"
    "\t\t\t\t\t\ttry {\n"
    "\t\t\t\t\t\t\teditor.update(() => {\n"
    "\t\t\t\t\t\t\t\tconst sel = Kr();\n"
    "\t\t\t\t\t\t\t\tif (!ur(sel)) return;\n"
    "\t\t\t\t\t\t\t\tfor (const raw of refText.split(\" \").filter(Boolean)) {\n"
    "\t\t\t\t\t\t\t\t\tlet p = raw, lbl = raw;\n"
    "\t\t\t\t\t\t\t\t\tconst qm = /^@\"(.*)\"$/.exec(raw);\n"
    "\t\t\t\t\t\t\t\t\tif (qm) { p = qm[1]; lbl = p.split(/[\\\\/]/).pop(); }\n"
    "\t\t\t\t\t\t\t\t\telse { lbl = p.split(/[\\\\/]/).pop(); }\n"
    "\t\t\t\t\t\t\t\t\tsel.insertNode($createReferenceChipNode({ source: \"dsh-file-reference\", ref: p, label: lbl, clipboardText: \"@\" + p }));\n"
    "\t\t\t\t\t\t\t\t\tsel.insertText(\" \");\n"
    "\t\t\t\t\t\t\t\t}\n"
    "\t\t\t\t\t\t\t});\n"
    "\t\t\t\t\t\t} catch (_) { keyboard.paste(refText); }\n"
    "\t\t\t\t\t}\n"
    "\t\t\t\t\tif (images.length === 0) return;\n"
    "\t\t\t\t\tfiles = images;\n"
    "\t\t\t\t}\n"
)

def apply_replace(path, old, new, what):
    with open(path, "r", encoding="utf-8") as fh:
        data = fh.read()
    if marker in data:
        print("==> %s：已打过补丁，跳过。" % what)
        return False
    n = data.count(old)
    if n != 1:
        fail("%s：锚点匹配 %d 次（应为 1），可能是版本不匹配。请勿手动改动后重试。" % (what, n))
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(data.replace(old, old + new))
    print("==> %s：补丁已应用。" % what)
    return True

# ---- 2) preload：注入 dshDesktopFileBridge ----
# 锚点：官方编译产物里的 directory-picker 暴露块（含引号/分号变体）
anchor_pre_candidates = [
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

def apply_preload(path):
    with open(path, "r", encoding="utf-8") as fh:
        data = fh.read()
    if marker in data:
        print("==> preload：已打过补丁，跳过。")
        return
    for cand in anchor_pre_candidates:
        if data.count(cand) == 1:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(data.replace(cand, cand + block_pre))
            print("==> preload：dshDesktopFileBridge 已注入。")
            return
    # 未匹配：打印现场帮助人工排查
    idx = data.find("dshDesktopDirectoryPicker")
    if idx >= 0:
        snippet = data[max(0, idx - 60): idx + 160]
        fail("preload 锚点未精确匹配。现场片段如下，请反馈以便适配：\n---\n%s\n---" % snippet)
    fail("preload 中找不到 dshDesktopDirectoryPicker，可能版本结构不同，请反馈。")

apply_replace(conv_path, anchor_conv, block_conv, "conversation")
apply_preload(preload_path)
PY

# ---------- 校验 ----------
grep -q "$MARKER" "$CONV" || { echo "错误：conversation 补丁校验失败" >&2; exit 1; }
grep -q "$MARKER" "$PRELOAD" || { echo "错误：preload 补丁校验失败" >&2; exit 1; }
echo "==> 两处补丁内容校验通过。"

# ---------- ad-hoc 重签 + 清隔离 ----------
echo "==> ad-hoc 重新签名（修改官方签名包后必需）..."
codesign --force --deep --sign - "$APP"
xattr -dr com.apple.quarantine "$APP" 2> /dev/null || true

if codesign --verify --deep --strict "$APP" 2> /tmp/dsh-codesign-verify.txt; then
  echo "==> 签名校验通过。"
else
  echo "警告：codesign 校验未通过（ad-hoc 签名在部分系统会提示，通常仍可运行）："
  cat /tmp/dsh-codesign-verify.txt
fi

echo ""
echo "✅ 完成！请启动 DSH Desktop，把 PDF/txt/md/docx 拖进对话测试。"
echo "   若 Gatekeeper 拦截：右键 DSH Desktop.app → 打开。"
echo "   官方应用日后自动更新后补丁会被覆盖，届时重跑本脚本即可。"
