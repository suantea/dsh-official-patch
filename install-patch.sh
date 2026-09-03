#!/bin/bash
set -euo pipefail

APP="${1:-/Applications/DSH Desktop.app}"
ROOT="$APP/Contents/Resources/app"
CONV="$ROOT/node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js"
PRELOAD="$ROOT/out/preload/index.cjs"
MARKER="dshDesktopFileBridge"

echo "==> DSH Desktop 拖放文件补丁安装脚本"
echo "==> 目标应用：$APP"

if [ ! -f "$CONV" ]; then
  echo "错误：找不到 conversation 包文件：$CONV" >&2
  exit 1
fi
if [ ! -f "$PRELOAD" ]; then
  echo "错误：找不到 preload 产物：$PRELOAD" >&2
  exit 1
fi
if pgrep -f "DSH Desktop" > /dev/null 2>&1; then
  echo "警告：DSH Desktop 正在运行。请先退出应用再继续。"
  sleep 5
fi

if grep -q "$MARKER" "$CONV" && grep -q "$MARKER" "$PRELOAD"; then
  echo "==> 补丁均已应用，无需重复操作。"
  exit 0
fi

backup() {
  local f="$1"
  if [ ! -f "$f.dshbak" ]; then
    cp -p "$f" "$f.dshbak"
    echo "==> 已备份：$(basename "$f") → $(basename "$f").dshbak"
  fi
}
backup "$CONV"
backup "$PRELOAD"

python3 /tmp/dsh-patch.py "$CONV" "$PRELOAD" "$MARKER"

grep -q "$MARKER" "$CONV" || { echo "错误：conversation 补丁校验失败" >&2; exit 1; }
grep -q "$MARKER" "$PRELOAD" || { echo "错误：preload 补丁校验失败" >&2; exit 1; }
echo "==> 补丁内容校验通过。"

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
