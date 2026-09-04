import sys, os
conv_path, preload_path, marker = sys.argv[1], sys.argv[2], sys.argv[3]

def fail(msg):
    print("错误：%s" % msg, file=sys.stderr)
    sys.exit(1)

def read(p):
    with open(p, 'r', encoding='utf-8') as f:
        return f.read()

def write(p, d):
    with open(p, 'w', encoding='utf-8') as f:
        f.write(d)

def inject_once(data, candidates, name):
    """candidates: [(anchor, block), ...] 按序取第一个恰好匹配 1 次的锚点注入。"""
    for idx, (anchor, block) in enumerate(candidates, 1):
        n = data.count(anchor)
        if n == 1:
            data = data.replace(anchor, anchor + block, 1)
            print("==> %s: 已注入（候选 %d/%d）" % (name, idx, len(candidates)))
            return data
    detail = "，".join("候选%d=%d次" % (i + 1, data.count(a)) for i, (a, _b) in enumerate(candidates))
    fail("%s：所有锚点候选均未匹配（%s），官方版本可能已漂移" % (name, detail))

if marker in read(conv_path):
    print("==> conversation: 已打过补丁，跳过")
else:
    data = read(conv_path)

    # ---- 1. intakeImages：非图片文件拖入 → 文件名 chip（回退纯文本 @路径） ----
    chip_block = (
        "\t\t\t\tconst bridge = typeof window !== \"undefined\" && window.dshDesktopFileBridge || null;\n"
        "\t\t\t\tif (bridge !== null && typeof bridge.getPathForFile === \"function\") {\n"
        "\t\t\t\t\tconst images = [], refs = [];\n"
        "\t\t\t\t\tfor (const file of files) {\n"
        "\t\t\t\t\t\tif (imageLimits !== void 0 && imageLimits.mediaTypes.includes(file.type)) { images.push(file); continue; }\n"
        "\t\t\t\t\t\tlet path = null;\n"
        "\t\t\t\t\t\ttry { path = bridge.getPathForFile(file); } catch (error) { path = null; }\n"
        "\t\t\t\t\t\tif (typeof path === \"string\" && path !== \"\") refs.push(path); else images.push(file);\n"
        "\t\t\t\t\t}\n"
        "\t\t\t\t\tif (refs.length > 0) {\n"
        "\t\t\t\t\t\twindow.dshDesktopPendingFilePaths = refs;\n"
        "\t\t\t\t\t\tconst ed = (typeof keyboard !== \"undefined\" && keyboard !== null) ? (keyboard.editor ?? null) : null;\n"
        "\t\t\t\t\t\tlet chipInserted = false;\n"
        "\t\t\t\t\t\tif (ed !== null && typeof $createReferenceChipNode === \"function\") {\n"
        "\t\t\t\t\t\t\ttry {\n"
        "\t\t\t\t\t\t\t\ted.update(() => {\n"
        "\t\t\t\t\t\t\t\t\tconst sel = Kr();\n"
        "\t\t\t\t\t\t\t\t\tif (ur(sel)) {\n"
        "\t\t\t\t\t\t\t\t\t\tconst nodes = [];\n"
        "\t\t\t\t\t\t\t\t\t\tfor (const p of refs) {\n"
        "\t\t\t\t\t\t\t\t\t\t\tnodes.push($createReferenceChipNode({\n"
        "\t\t\t\t\t\t\t\t\t\t\t\tsource: \"dsh-file-reference\",\n"
        "\t\t\t\t\t\t\t\t\t\t\t\tref: p,\n"
        "\t\t\t\t\t\t\t\t\t\t\t\tlabel: String(p).split(\"/\").pop(),\n"
        "\t\t\t\t\t\t\t\t\t\t\t\tclipboardText: \"@\" + p\n"
        "\t\t\t\t\t\t\t\t\t\t\t}));\n"
        "\t\t\t\t\t\t\t\t\t\t}\n"
        "\t\t\t\t\t\t\t\t\t\tnodes.push(Go(\" \"));\n"
        "\t\t\t\t\t\t\t\t\t\tsel.insertNodes(nodes);\n"
        "\t\t\t\t\t\t\t\t\t\tchipInserted = true;\n"
        "\t\t\t\t\t\t\t\t\t}\n"
        "\t\t\t\t\t\t\t\t});\n"
        "\t\t\t\t\t\t\t} catch (error) { chipInserted = false; }\n"
        "\t\t\t\t\t\t}\n"
        "\t\t\t\t\t\tif (!chipInserted) {\n"
        "\t\t\t\t\t\t\tconst refText = refs.map((p) => /\\s/.test(p) ? `@\"${p}\"` : `@${p}`).join(\" \") + \" \";\n"
        "\t\t\t\t\t\t\tif (typeof keyboard !== \"undefined\") keyboard.paste(refText);\n"
        "\t\t\t\t\t\t}\n"
        "\t\t\t\t\t\tif (images.length > 0) addImages(images);\n"
        "\t\t\t\t\t\treturn;\n"
        "\t\t\t\t\t}\n"
        "\t\t\t\t\tif (images.length === 0) return;\n"
        "\t\t\t\t\tfiles = images;\n"
        "\t\t\t\t}\n"
    )
    c1_anchor = "\t\t\tconst intakeImages = (0, react.useCallback)((files) => {\n\t\t\t\tif (addImages === void 0 || files.length === 0) return;\n"
    c2_anchor = "\t\t\tconst intakeImages = (0, react.useCallback)((files) => {\n"
    c2_block = "\t\t\t\tif (addImages === void 0 || files.length === 0) return;\n" + chip_block
    data = inject_once(data, [(c1_anchor, chip_block), (c2_anchor, c2_block)], "intakeImages")

    # ---- 2. Je$2（粘贴事件）：文件 → 取路径进 pending，仍走官方 intakeFiles ----
    # 核心块只补路径提取；完整锚点（a3_full）已含原版 intakeFiles 调用行，
    # 宽松锚点（a3_loose）则在 b3_loose 里补上调用行 —— 避免重复调用。
    b3_core = (
        "\t\t\t\tif (files.length > 0) {\n"
        "\t\t\t\t\tconst bridge = typeof window !== \"undefined\" && window.dshDesktopFileBridge;\n"
        "\t\t\t\t\tif (bridge && typeof bridge.getPathForFile === \"function\") {\n"
        "\t\t\t\t\t\tconst refs = [];\n"
        "\t\t\t\t\t\tfor (const f of files) {\n"
        "\t\t\t\t\t\t\ttry { const p = bridge.getPathForFile(f); if (typeof p === \"string\" && p !== \"\") refs.push(p); } catch(e) {}\n"
        "\t\t\t\t\t\t}\n"
        "\t\t\t\t\t\tif (refs.length > 0) window.dshDesktopPendingFilePaths = refs;\n"
        "\t\t\t\t\t}\n"
        "\t\t\t\t}\n"
    )
    a3_full = "\t\t\t}, 4), editor.registerCommand(Je$2, (event) => {\n\t\t\t\tconst clipboardData = event.clipboardData ?? null;\n\t\t\t\tif (clipboardData === null) return false;\n\t\t\t\tconst files = Array.from(clipboardData.items).filter((item) => item.kind === \"file\").map((item) => item.getAsFile()).filter((file) => file !== null);\n\t\t\t\tif (files.length > 0) handlers.intakeFiles(files);\n"
    a3_loose = "\t\t\t}, 4), editor.registerCommand(Je$2, (event) => {\n"
    b3_loose = (
        "\t\t\t\tconst clipboardData = event.clipboardData ?? null;\n"
        "\t\t\t\tif (clipboardData === null) return false;\n"
        "\t\t\t\tconst files = Array.from(clipboardData.items).filter((item) => item.kind === \"file\").map((item) => item.getAsFile()).filter((file) => file !== null);\n"
        "\t\t\t\tif (files.length > 0) handlers.intakeFiles(files);\n"
    ) + b3_core
    data = inject_once(data, [(a3_full, b3_core), (a3_loose, b3_loose)], "Je$2")

    write(conv_path, data)

# Preload
pdata = read(preload_path)
if marker not in pdata:
    a5 = 'electron.contextBridge.exposeInMainWorld("dshDesktopDirectoryPicker", {\n  pick: () => electron.ipcRenderer.invoke("directory-picker:open")\n});'
    b5 = '\nelectron.contextBridge.exposeInMainWorld(\n  "dshDesktopFileBridge",\n  Object.freeze({\n    isDesktop: true,\n    getPathForFile: (file) => {\n      try {\n        return electron.webUtils.getPathForFile(file);\n      } catch {\n        return null;\n      }\n    }\n  })\n);'
    if pdata.count(a5) == 1:
        pdata = pdata.replace(a5, a5 + b5, 1)
        write(preload_path, pdata)
        print("==> preload: dshDesktopFileBridge 已注入")
    else:
        fail("preload 锚点未匹配")
else:
    print("==> preload: 已打过补丁，跳过")

# ============ 5. 界面文案汉化（zh 段内替换，11 处） ============
# 每个包 zh 字典里值仍为英文的键 → 中文。技术词/单位不翻。
import re as _re, os as _os
ZH_FIXES = {
    "dsh-client-ui-chat": {
        '"settings.transcript.normal": "Normal",': '"settings.transcript.normal": "标准",',
        '"settings.transcript.compact": "Compact",': '"settings.transcript.compact": "紧凑",',
    },
    "dsh-client-ui-cordis": {
        '"panel.trigger": "Cordis Plugin",': '"panel.trigger": "Cordis 插件",',
        '"panel.runningCount": "{count} running",': '"panel.runningCount": "{count} 个运行中",',
        '"body.hostCode": "Host",': '"body.hostCode": "宿主",',
        '"body.clientCode": "Client",': '"body.clientCode": "客户端",',
    },
    "dsh-client-ui-model-selection": {
        '"effort.providerDefault": "Default",': '"effort.providerDefault": "默认",',
    },
    "dsh-client-ui-plan": {
        '"chip.label": "Plan",': '"chip.label": "计划",',
    },
    "dsh-client-ui-skill": {
        '"row.title": "Skill",': '"row.title": "技能",',
    },
    "dsh-client-ui-trajectory": {
        '"tab.schema": "Schema",': '"tab.schema": "架构",',
    },
}
# conversation 的汉化在 conv_path 自身
ZH_FIXES["dsh-client-ui-conversation"] = {
    '"access.fullLabel": "Full access",': '"access.fullLabel": "完全访问",',
}
_app_root = _os.path.dirname(_os.path.dirname(_os.path.dirname(_os.path.dirname(_os.path.dirname(conv_path)))))
for _pkg, _repl in ZH_FIXES.items():
    _p = _os.path.join(_app_root, "node_modules", "@deepseek-ai", _pkg, "lib", "client.js")
    if not _os.path.exists(_p):
        print("==> 汉化 %s: 文件不存在，跳过" % _pkg)
        continue
    _d = read(_p)
    _zs = _d.find("\t\tconst zh = {")
    _es = _d.find("\t\tconst en = {")
    if _zs < 0 or _es < 0 or _es < _zs:
        print("==> 汉化 %s: 找不到 zh/en 边界，跳过" % _pkg)
        continue
    _zone = _d[_zs:_es]
    _done = 0
    for _old, _new in _repl.items():
        if _new in _zone:
            _done += 1  # 已汉化
        elif _old in _zone:
            _zone = _zone.replace(_old, _new, 1)
            _done += 1
    if _done:
        write(_p, _d[:_zs] + _zone + _d[_es:])
        print("==> 汉化 %s: %d 条已应用" % (_pkg, _done))

print("==> 全部完成")
