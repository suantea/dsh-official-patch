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

if marker in read(conv_path):
    print("==> conversation: 已打过补丁，跳过")
else:
    data = read(conv_path)
    # 1. intakeImages
    a1 = "\t\t\tconst intakeImages = (0, react.useCallback)((files) => {\n\t\t\t\tif (addImages === void 0 || files.length === 0) return;\n"
    b1 = "\t\t\t\tconst bridge = typeof window !== \"undefined\" && window.dshDesktopFileBridge || null;\n\t\t\t\tif (bridge !== null && typeof bridge.getPathForFile === \"function\") {\n\t\t\t\t\tconst images = [], refs = [];\n\t\t\t\t\tfor (const file of files) {\n\t\t\t\t\t\tif (imageLimits !== void 0 && imageLimits.mediaTypes.includes(file.type)) { images.push(file); continue; }\n\t\t\t\t\t\tlet path = null;\n\t\t\t\t\t\ttry { path = bridge.getPathForFile(file); } catch (error) { path = null; }\n\t\t\t\t\t\tif (typeof path === \"string\" && path !== \"\") refs.push(path); else images.push(file);\n\t\t\t\t\t}\n\t\t\t\t\tif (refs.length > 0) window.dshDesktopPendingFilePaths = refs;\n\t\t\t\t\tif (images.length === 0) return;\n\t\t\t\t\tfiles = images;\n\t\t\t\t}\n"
    n = data.count(a1)
    if n != 1: fail("intakeImages 锚点匹配 %d 次" % n)
    data = data.replace(a1, a1 + b1, 1)
    print("==> intakeImages: 已注入")

    # 2. paste() U+FFFC
    a2 = "\t\t\tpaste(text) {\n\t\t\t\tconst clean = text.replace(REFERENCE_PLACEHOLDER_RE, \"\");\n"
    b2 = "\t\t\t\t// DSH Desktop patch: @/path → U+FFFC\n\t\t\t\ttext = text.replace(/@(?:@|&quot;([^&]*?)&quot;|([^\\s]+))/gu, (_, q, plain) => {\n\t\t\t\t\tconst p = q !== undefined ? q : plain;\n\t\t\t\t\treturn window.dshDesktopPendingFilePaths && window.dshDesktopPendingFilePaths.includes(p) ? \"\\uFFFC\" : \"@\" + p;\n\t\t\t\t});\n"
    n = data.count(a2)
    if n != 1: fail("paste 锚点匹配 %d 次" % n)
    data = data.replace(a2, a2 + b2, 1)
    print("==> paste(): 已注入")

    # 3. Je$2
    a3 = "\t\t\t}, 4), editor.registerCommand(Je$2, (event) => {\n\t\t\t\tconst clipboardData = event.clipboardData ?? null;\n\t\t\t\tif (clipboardData === null) return false;\n\t\t\t\tconst files = Array.from(clipboardData.items).filter((item) => item.kind === \"file\").map((item) => item.getAsFile()).filter((file) => file !== null);\n\t\t\t\tif (files.length > 0) handlers.intakeFiles(files);\n"
    b3 = "\t\t\t\tif (files.length > 0) {\n\t\t\t\t\tconst bridge = typeof window !== \"undefined\" && window.dshDesktopFileBridge;\n\t\t\t\t\tif (bridge && typeof bridge.getPathForFile === \"function\") {\n\t\t\t\t\t\tconst refs = [];\n\t\t\t\t\t\tfor (const f of files) {\n\t\t\t\t\t\t\ttry { const p = bridge.getPathForFile(f); if (typeof p === \"string\" && p !== \"\") refs.push(p); } catch(e) {}\n\t\t\t\t\t\t}\n\t\t\t\t\t\tif (refs.length > 0) window.dshDesktopPendingFilePaths = refs;\n\t\t\t\t\t}\n\t\t\t\t\thandlers.intakeFiles(files);\n\t\t\t\t}\n"
    n = data.count(a3)
    if n != 1: fail("Je$2 锚点匹配 %d 次" % n)
    data = data.replace(a3, a3 + b3, 1)
    print("==> Je$2: 已注入")

    # 4. document drop listener
    a4 = "\t\t\t}, [editor, keyboard]);\n\t\t\tconst keepFocus"
    b4 = "\t\t\t}, [editor, keyboard]);\n\t\t\t// DSH Desktop patch: intercept document drop\n\t\t\tif (typeof document !== \"undefined\") {\n\t\t\t\tdocument.addEventListener(\"drop\", (event) => {\n\t\t\t\t\tconst bridge = typeof window !== \"undefined\" && window.dshDesktopFileBridge;\n\t\t\t\t\tif (!bridge || typeof bridge.getPathForFile !== \"function\") return;\n\t\t\t\t\tconst dt = event.dataTransfer;\n\t\t\t\t\tif (!dt) return;\n\t\t\t\t\tconst items = Array.from(dt.items).filter((item) => item.kind === \"file\");\n\t\t\t\t\tif (items.length === 0) return;\n\t\t\t\t\tconst nonImage = items.map((item) => item.getAsFile()).filter((f) => f !== null).filter((f) => {\n\t\t\t\t\t\tconst t = f.type || \"\";\n\t\t\t\t\t\treturn !t.startsWith(\"image/\");\n\t\t\t\t\t});\n\t\t\t\t\tif (nonImage.length === 0) return;\n\t\t\t\t\tconst refs = [];\n\t\t\t\t\tfor (const f of nonImage) {\n\t\t\t\t\t\ttry { const p = bridge.getPathForFile(f); if (typeof p === \"string\" && p !== \"\") refs.push(p); } catch(e) {}\n\t\t\t\t\t}\n\t\t\t\t\tif (refs.length > 0 && typeof keyboard !== \"undefined\") {\n\t\t\t\t\t\tevent.preventDefault();\n\t\t\t\t\t\tevent.stopPropagation();\n\t\t\t\t\t\tconst text = refs.map((p) => /\\s/.test(p) ? `@\"${p}\"` : `@${p}`).join(\" \") + \" \";\n\t\t\t\t\t\twindow.dshDesktopPendingFilePaths = refs;\n\t\t\t\t\t\tkeyboard.paste(text);\n\t\t\t\t\t\treturn;\n\t\t\t\t\t}\n\t\t\t\t}, true);\n\t\t\t}\n\t\t\tconst keepFocus"
    n = data.count(a4)
    if n != 1: fail("document drop 锚点匹配 %d 次" % n)
    data = data.replace(a4, a4 + b4, 1)
    print("==> document drop listener: 已注入")

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

print("==> 全部完成")
