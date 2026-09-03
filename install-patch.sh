#!/bin/bash
set -euo pipefail
APP="${1:-/Applications/DSH Desktop.app}"
CONV="$APP/Contents/Resources/app/node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js"
PRELOAD="$APP/Contents/Resources/app/out/preload/index.cjs"
MARKER="dshDesktopFileBridge"
echo "==> DSH Desktop 补丁安装脚本"
[ ! -f "$CONV" ] && echo "错误：找不到 $CONV" >&2 && exit 1
[ ! -f "$PRELOAD" ] && echo "错误：找不到 $PRELOAD" >&2 && exit 1
pgrep -f "DSH Desktop" >/dev/null 2>&1 && { echo "警告：应用正在运行，请先退出"; sleep 5; }
grep -q "$MARKER" "$CONV" && grep -q "$MARKER" "$PRELOAD" && { echo "已打补丁，跳过"; exit 0; }
[ ! -f "${CONV}.dshbak" ] && cp -p "$CONV" "${CONV}.dshbak" && echo "备份 client.js"
[ ! -f "${PRELOAD}.dshbak" ] && cp -p "$PRELOAD" "${PRELOAD}.dshbak" && echo "备份 index.cjs"
python3 "$(dirname "$0")/dsh-patch.py" "$CONV" "$PRELOAD" "$MARKER"
grep -q "$MARKER" "$CONV" || { echo "校验失败"; exit 1; }
codesign --force --deep --sign - "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
echo "✅ 完成！重启 DSH Desktop 测试。"
