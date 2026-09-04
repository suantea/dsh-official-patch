#!/usr/bin/env swift
// dsh-ocr — 零依赖扫描 PDF/图片 OCR（macOS Vision framework）
//
// 用法:
//   swift dsh-ocr.swift <input.pdf|input.png|input.jpg> [--pdf] [--langs zh-Hans,en-US] [--out <base>]
//
//   <input>       扫描版 PDF 或图片（无文字层）
//   --pdf         除文本外，另输出带可搜索文字层的副本 <base>.ocr.pdf
//                 （每页叠加白色 FreeText annotation，视觉隐形、文本可搜索/复制）
//   --langs       识别语言，默认 zh-Hans,en-US
//   --out         输出基名（默认取输入文件名），生成 <base>.ocr.txt
//
// 依赖: 仅 macOS 系统框架（PDFKit / Vision / AppKit），无需第三方库。
// 退出码: 0=成功（可能零文本） 1=输入错误 2=OCR 失败

import Foundation
import PDFKit
import Vision
import AppKit

// ---------- 参数解析 ----------
let args = CommandLine.arguments
guard args.count >= 2 else {
    print("用法: swift dsh-ocr.swift <input.pdf|input.png|input.jpg> [--pdf] [--langs zh-Hans,en-US] [--out <base>]")
    exit(1)
}
let inputPath = args[1]
var wantPDF = false
var langs = ["zh-Hans", "en-US"]
var outBase: String? = nil

var i = 2
while i < args.count {
    switch args[i] {
    case "--pdf": wantPDF = true
    case "--langs":
        if i + 1 < args.count { langs = args[i + 1].split(separator: ",").map(String.init); i += 1 }
    case "--out":
        if i + 1 < args.count { outBase = args[i + 1]; i += 1 }
    default: break
    }
    i += 1
}

guard FileManager.default.fileExists(atPath: inputPath) else {
    print("错误: 输入文件不存在: \(inputPath)")
    exit(1)
}

// ---------- 输入解码: PDF → 页面图像; 图片 → 单页 ----------
func renderPages(from url: URL) -> (pages: [CGImage], labels: [String])? {
    if url.pathExtension.lowercased() == "pdf" {
        guard let doc = PDFDocument(url: url) else { return nil }
        var pages: [CGImage] = []
        var labels: [String] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0  // 2x 渲染保证 OCR 精度
            let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
            guard w > 0, h > 0 else { continue }
            let thumb = page.thumbnail(of: NSSize(width: w, height: h), for: .mediaBox)
            guard let cg = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            pages.append(cg)
            labels.append("Page \(i + 1)")
        }
        return (pages, labels)
    }
    // 图片输入
    guard let img = NSImage(contentsOf: url),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    return ([cg], ["Image"])
}

let url = URL(fileURLWithPath: inputPath)
guard let (pages, labels) = renderPages(from: url), !pages.isEmpty else {
    print("错误: 无法解析输入（不是合法 PDF/图片）")
    exit(1)
}

// ---------- Vision OCR ----------
func recognize(_ image: CGImage, languages: [String]) -> [VNRecognizedTextObservation] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = languages
    request.usesCPUOnly = false
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try? handler.perform([request])
    return request.results ?? []
}

// ---------- 输出 ----------
let fileBase = outBase ?? (inputPath as NSString).deletingPathExtension
let txtPath = fileBase + ".ocr.txt"
var txt = ""
var ocrDoc: PDFDocument? = nil
if wantPDF {
    ocrDoc = url.pathExtension.lowercased() == "pdf" ? PDFDocument(url: url) : PDFDocument()
}

var anyText = false
for (idx, pageCG) in pages.enumerated() {
    let results = recognize(pageCG, languages: langs)
    var pageText = ""
    for obs in results {
        if let top = obs.topCandidates(1).first {
            pageText += top.string + "\n"
        }
    }
    if !pageText.isEmpty { anyText = true }
    txt += "===== \(labels[idx]) =====\n\(pageText)\n"
    if let doc = ocrDoc, idx < doc.pageCount {
        // 叠加白色 FreeText 文字层（可搜索/复制，视觉隐形）
        let page = doc.page(at: idx)
        let pageBounds = page?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 612, height: 792)
        var y: CGFloat = pageBounds.height - 40
        for obs in results {
            guard let top = obs.topCandidates(1).first else { continue }
            let bounds = CGRect(x: 30, y: y - 18, width: pageBounds.width - 60, height: 20)
            let ann = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
            ann.contents = top.string
            ann.font = NSFont(name: "Helvetica", size: 12) ?? NSFont.systemFont(ofSize: 12)
            ann.fontColor = NSColor.white
            page?.addAnnotation(ann)
            y -= 18
        }
    }
}

do {
    try txt.write(toFile: txtPath, atomically: true, encoding: .utf8)
} catch {
    print("错误: 无法写文本输出 \(txtPath): \(error)")
    exit(2)
}
print("文本已输出: \(txtPath) (\(labels.count) 页, 识别文本: \(anyText ? "有" : "无"))")

if let doc = ocrDoc {
    let pdfPath = fileBase + ".ocr.pdf"
    if doc.write(toFile: pdfPath) {
        print("带文字层 PDF 已输出: \(pdfPath)")
    } else {
        print("警告: 写 PDF 输出失败: \(pdfPath)")
    }
}
exit(0)
