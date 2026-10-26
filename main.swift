// 香菜番茄钟：悬浮在桌面上的工作计时小组件。
// 单击开始 / 停止，拖动挪位置，右键换形状（上传图片自动抠主体，或写一句话生成图标）。
import Cocoa
import SwiftUI
import Charts
import Vision
import CoreImage
import ImagePlayground
import UniformTypeIdentifiers

// MARK: - 数据

/// 一天按凌晨 5 点切换：直播到两三点也算前一天。
let cutoffHours = 5.0

func dayKey(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date.addingTimeInterval(-cutoffHours * 3600))
}

/// 把“工作日”日期串转回当天 0 点的 Date
func dayDate(_ key: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f.date(from: key) ?? Date()
}

func hm(_ ms: Double) -> String {
    let m = Int(max(0, ms) / 60000)
    return String(format: "%d:%02d", m / 60, m % 60)
}

func hms(_ ms: Double) -> String {
    let s = Int(max(0, ms) / 1000)
    return String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
}

struct Session: Codable { var s: Double; var e: Double }   // 毫秒时间戳

struct Store: Codable {
    var runningSince: Double?
    var days: [String: [Session]] = [:]
    var size: Double = 140
    var x: Double?
    var y: Double?
}

final class DataStore {
    static let shared = DataStore()
    let dir: URL
    var store = Store()

    var storeURL: URL { dir.appendingPathComponent("store.json") }
    var shapeURL: URL { dir.appendingPathComponent("shape.png") }
    var tokenURL: URL { dir.appendingPathComponent("modelscope-token.txt") }

    init() {
        dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("XiangcaiTimer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: storeURL),
           let s = try? JSONDecoder().decode(Store.self, from: data) {
            store = s
        }
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(store) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    var token: String? {
        get {
            let t = (try? String(contentsOf: tokenURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t?.isEmpty ?? true) ? nil : t
        }
        set {
            if let v = newValue, !v.isEmpty {
                try? v.write(to: tokenURL, atomically: true, encoding: .utf8)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
            } else {
                try? FileManager.default.removeItem(at: tokenURL)
            }
        }
    }

    var isRunning: Bool { store.runningSince != nil }

    func start() {
        guard store.runningSince == nil else { return }
        store.runningSince = Date().timeIntervalSince1970 * 1000
        save()
    }

    /// 返回这一段的时长（毫秒）
    @discardableResult
    func stop() -> Double {
        guard let s = store.runningSince else { return 0 }
        let e = Date().timeIntervalSince1970 * 1000
        let key = dayKey(Date(timeIntervalSince1970: s / 1000))
        store.days[key, default: []].append(Session(s: s, e: e))
        store.runningSince = nil
        save()
        return e - s
    }

    func ms(for key: String) -> Double {
        var t = (store.days[key] ?? []).reduce(0) { $0 + ($1.e - $1.s) }
        if let r = store.runningSince, dayKey(Date(timeIntervalSince1970: r / 1000)) == key {
            t += Date().timeIntervalSince1970 * 1000 - r
        }
        return t
    }

    var todayMs: Double { ms(for: dayKey(Date())) }

    var currentMs: Double {
        guard let r = store.runningSince else { return 0 }
        return Date().timeIntervalSince1970 * 1000 - r
    }
}

// MARK: - 激励的话

enum Cheer {
    static let start = [
        "开工！今天也是从第一个动作开始的。",
        "先做最难的那件，后面都是下坡路。",
        "老板们在等一条真正有用的内容。",
        "专注 25 分钟，比焦虑一下午有用。",
        "今天的每一条内容，都是线下课的一张门票。",
        "别等状态，开始了状态自己会来。",
        "一次只做一件事，做完再看手机。",
        "草根出身，靠的就是比别人多做一点。",
        "把今天最重要的一件事，先放进这一段。",
        "开始就赢了一半，剩下一半交给坚持。",
        "动起来，客户不会自己出现。",
        "你不是在打卡，是在搭自己的生意。",
        "这一段时间只属于手上这件事。",
        "写下第一句，后面就顺了。",
        "今天多走一步，月底多一个报名。",
    ]
    static let stop = [
        "收工这一段，辛苦了！",
        "又往前推了一步，喝口水歇一下。",
        "做完比做好更重要，你已经做完了。",
        "这段时间没白花，记账了。",
        "休息是为了下一段更专注。",
        "今天的你，比昨天多干了一点。",
        "小步快跑，积少成多。",
        "站起来走两步，眼睛看看远处。",
        "这一段的成果，记得发出去让人看见。",
        "停得下来，才开得起来。",
        "每一个小时，都在离目标更近。",
        "干得漂亮，给自己一点掌声。",
        "节奏比冲刺重要，慢慢来比较快。",
        "复盘一句：刚才最有用的是哪一件？",
        "收好这一段，下一段继续。",
    ]
}

// MARK: - 形状

enum ShapeError: LocalizedError {
    case unreadable, noSubject, needToken, generation(String)
    var errorDescription: String? {
        switch self {
        case .unreadable: return "这张图片打不开，换一张 JPG 或 PNG 试试。"
        case .noSubject: return "没在图片里找到明显的主体。换一张主体清楚、背景简单的图片试试。"
        case .needToken: return "生成图片需要先设置魔搭 ModelScope 的访问令牌。"
        case .generation(let m): return m
        }
    }
}

enum Shape {
    /// 默认形状：一颗番茄。
    static func tomato() -> NSImage {
        let size = NSSize(width: 400, height: 400)
        return NSImage(size: size, flipped: false) { _ in
            let body = NSBezierPath(ovalIn: NSRect(x: 30, y: 20, width: 340, height: 310))
            NSGradient(colors: [NSColor(red: 0.96, green: 0.36, blue: 0.29, alpha: 1),
                                NSColor(red: 0.80, green: 0.17, blue: 0.15, alpha: 1)])?
                .draw(in: body, relativeCenterPosition: NSPoint(x: -0.3, y: 0.35))
            NSColor(white: 1, alpha: 0.28).setFill()
            NSBezierPath(ovalIn: NSRect(x: 95, y: 230, width: 70, height: 38)).fill()
            let leaf = NSBezierPath()
            let c = NSPoint(x: 200, y: 318)
            for i in 0..<5 {
                let a = Double(i) / 5 * 2 * .pi + .pi / 2
                let tip = NSPoint(x: c.x + cos(a) * 78, y: c.y + sin(a) * 34)
                let l = NSPoint(x: c.x + cos(a - 0.45) * 30, y: c.y + sin(a - 0.45) * 16)
                let r = NSPoint(x: c.x + cos(a + 0.45) * 30, y: c.y + sin(a + 0.45) * 16)
                leaf.move(to: c)
                leaf.curve(to: tip, controlPoint1: l, controlPoint2: l)
                leaf.curve(to: c, controlPoint1: r, controlPoint2: r)
            }
            NSColor(red: 0.20, green: 0.55, blue: 0.27, alpha: 1).setFill()
            leaf.fill()
            let stem = NSBezierPath(roundedRect: NSRect(x: 192, y: 318, width: 16, height: 52), xRadius: 8, yRadius: 8)
            NSColor(red: 0.16, green: 0.45, blue: 0.22, alpha: 1).setFill()
            stem.fill()
            return true
        }
    }

    /// 用系统自带的“抠主体”能力（和照片 App 长按抠图同一套），返回透明背景的 PNG。
    /// keepWholeIfNone：找不到主体时直接用整张图（生成的图标用）。
    static func cutout(_ input: CIImage, keepWholeIfNone: Bool = false) throws -> Data {
        let handler = VNImageRequestHandler(ciImage: input)
        let request = VNGenerateForegroundInstanceMaskRequest()
        var out: CIImage
        do {
            try handler.perform([request])
            guard let obs = request.results?.first, !obs.allInstances.isEmpty else { throw ShapeError.noSubject }
            let buffer = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: true)
            out = CIImage(cvPixelBuffer: buffer)
        } catch {
            guard keepWholeIfNone else { throw error is ShapeError ? error : ShapeError.noSubject }
            out = input
        }
        let longest = max(out.extent.width, out.extent.height)
        if longest > 600 {
            let k = 600 / longest
            out = out.transformed(by: CGAffineTransform(scaleX: k, y: k))
        }
        out = out.transformed(by: CGAffineTransform(translationX: -out.extent.minX, y: -out.extent.minY))
        guard let cg = CIContext().createCGImage(out, from: out.extent) else { throw ShapeError.unreadable }
        guard let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw ShapeError.unreadable }
        return png
    }

    static func cutout(from url: URL) throws -> Data {
        guard let input = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { throw ShapeError.unreadable }
        return try cutout(input)
    }

    /// 一句话生成图标：先试 Mac 自带的 Image Playground，用不了再走魔搭 ModelScope。
    static func generate(_ sentence: String) async throws -> Data {
        if #available(macOS 15.4, *) {
            if let cg = try? await applePlayground(sentence) {
                return try cutout(CIImage(cgImage: cg), keepWholeIfNone: true)
            }
        }
        guard let token = DataStore.shared.token else { throw ShapeError.needToken }
        let data = try await modelScope(sentence, token: token)
        guard let ci = CIImage(data: data) else { throw ShapeError.unreadable }
        return try cutout(ci, keepWholeIfNone: true)
    }

    @available(macOS 15.4, *)
    @MainActor
    static func applePlayground(_ sentence: String) async throws -> CGImage {
        NSApp.activate(ignoringOtherApps: true)   // 系统要求生成时 App 在前台
        let creator = try await ImageCreator()
        let style = creator.availableStyles.contains(.animation) ? ImagePlaygroundStyle.animation : (creator.availableStyles.first ?? .animation)
        for try await img in creator.images(for: [.text(sentence)], style: style, limit: 1) {
            return img.cgImage
        }
        throw ShapeError.generation("Mac 自带的图片生成没有返回结果。")
    }

    static let msBase = "https://api-inference.modelscope.cn/v1"

    static func modelScope(_ sentence: String, token: String) async throws -> Data {
        let prompt = "\(sentence)。可爱的扁平贴纸风格图标，单个主体居中，轮廓清晰，纯白背景，不要文字"
        var req = URLRequest(url: URL(string: msBase + "/images/generations")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("true", forHTTPHeaderField: "X-ModelScope-Async-Mode")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["model": "Qwen/Qwen-Image", "prompt": prompt])
        req.timeoutInterval = 60
        let (d, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw ShapeError.generation("魔搭令牌不对或已失效，右键 → 设置生图令牌，重新粘贴一次。") }
        guard (200..<300).contains(code),
              let j = try JSONSerialization.jsonObject(with: d) as? [String: Any],
              let taskId = j["task_id"] as? String else {
            throw ShapeError.generation("魔搭没接受这次请求（\(code)）：\(String(data: d, encoding: .utf8)?.prefix(160) ?? "")")
        }
        for _ in 0..<40 {   // 最多等约 2 分钟
            try await Task.sleep(nanoseconds: 3_000_000_000)
            var poll = URLRequest(url: URL(string: msBase + "/tasks/\(taskId)")!)
            poll.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            poll.setValue("image_generation", forHTTPHeaderField: "X-ModelScope-Task-Type")
            let (pd, _) = try await URLSession.shared.data(for: poll)
            guard let pj = try JSONSerialization.jsonObject(with: pd) as? [String: Any] else { continue }
            let status = (pj["task_status"] as? String ?? "").uppercased()
            if status == "SUCCEED", let urls = pj["output_images"] as? [String], let first = urls.first, let u = URL(string: first) {
                return try await URLSession.shared.data(from: u).0
            }
            if status == "FAILED" { throw ShapeError.generation("魔搭生成失败了，换个说法再试一次。") }
        }
        throw ShapeError.generation("等了 2 分钟还没生成好，过一会儿再试。")
    }
}

// MARK: - 组件视图

final class WidgetView: NSView {
    var image: NSImage = Shape.tomato()
    var busyText: String?
    var onToggle: (() -> Void)?
    var onMenu: (() -> NSMenu)?
    var onMoved: (() -> Void)?

    private var downAt: NSPoint = .zero
    private var originAt: NSPoint = .zero
    private var dragged = false

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)

        let store = DataStore.shared
        let line1: String
        if let b = busyText { line1 = b }
        else if store.isRunning { line1 = "■ " + hms(store.currentMs) }
        else { line1 = "▶ 开始" }
        let line2 = "今天 " + hm(store.todayMs)

        let base = max(11, min(bounds.width, bounds.height) * 0.105)
        let a1: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: base, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let a2: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: max(9, base * 0.72), weight: .medium),
            .foregroundColor: NSColor(white: 1, alpha: 0.85),
        ]
        let s1 = NSAttributedString(string: line1, attributes: a1), s2 = NSAttributedString(string: line2, attributes: a2)
        let z1 = s1.size(), z2 = s2.size()
        let w = max(z1.width, z2.width) + base * 1.4
        let h = z1.height + z2.height + base * 0.45
        let pill = NSRect(x: (bounds.width - w) / 2, y: max(4, bounds.height * 0.05), width: w, height: h)
        let bg = store.isRunning ? NSColor(red: 0.13, green: 0.16, blue: 0.14, alpha: 0.9)
                                 : NSColor(red: 0.18, green: 0.49, blue: 0.29, alpha: 0.92)
        bg.setFill()
        NSBezierPath(roundedRect: pill, xRadius: min(h / 2, base * 0.9), yRadius: min(h / 2, base * 0.9)).fill()
        s1.draw(at: NSPoint(x: pill.midX - z1.width / 2, y: pill.maxY - base * 0.2 - z1.height))
        s2.draw(at: NSPoint(x: pill.midX - z2.width / 2, y: pill.minY + base * 0.22))
    }

    override func mouseDown(with event: NSEvent) {
        downAt = NSEvent.mouseLocation
        originAt = window?.frame.origin ?? .zero
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        let dx = p.x - downAt.x, dy = p.y - downAt.y
        if !dragged && hypot(dx, dy) < 3 { return }
        dragged = true
        window?.setFrameOrigin(NSPoint(x: originAt.x + dx, y: originAt.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        if dragged { onMoved?() } else if busyText == nil { onToggle?() }
    }

    override func menu(for event: NSEvent) -> NSMenu? { onMenu?() }
}

// MARK: - 激励气泡

final class Bubble {
    private var win: NSWindow?
    private var hideWork: DispatchWorkItem?

    func show(_ text: String, above anchor: NSWindow) {
        hideWork?.cancel()
        win?.orderOut(nil)
        let font = NSFont.systemFont(ofSize: 14, weight: .medium)
        let maxW: CGFloat = 260
        let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
        let r = str.boundingRect(with: NSSize(width: maxW, height: 400), options: [.usesLineFragmentOrigin])
        let size = NSSize(width: ceil(r.width) + 28, height: ceil(r.height) + 20)
        var origin = NSPoint(x: anchor.frame.midX - size.width / 2, y: anchor.frame.maxY + 8)
        if let vf = (anchor.screen ?? NSScreen.main)?.visibleFrame {
            if origin.y + size.height > vf.maxY { origin.y = anchor.frame.minY - size.height - 8 }
            origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - size.width - 8)
        }
        let w = NSWindow(contentRect: NSRect(origin: origin, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .floating
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let v = NSView(frame: NSRect(origin: .zero, size: size))
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(red: 0.13, green: 0.16, blue: 0.14, alpha: 0.94).cgColor
        v.layer?.cornerRadius = 12
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.textColor = .white
        label.frame = NSRect(x: 14, y: 10, width: size.width - 28, height: size.height - 20)
        v.addSubview(label)
        w.contentView = v
        w.alphaValue = 0
        w.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; w.animator().alphaValue = 1 }
        win = w
        let work = DispatchWorkItem { [weak self, weak w] in
            guard let w else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.4; w.animator().alphaValue = 0 }) {
                w.orderOut(nil)
                if self?.win === w { self?.win = nil }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }
}

// MARK: - 统计仪表盘

struct Bucket: Identifiable {
    let id: String
    let label: String
    let hours: Double
    let detail: String
}

struct StatsView: View {
    @State private var mode = 0          // 0 周 · 1 月 · 2 年
    @State private var offset = 0
    @State private var selected: String?
    @State private var tick = 0
    let refresh = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private let green = Color(red: 0.18, green: 0.49, blue: 0.29)
    private let data = DataStore.shared
    private let wd = ["日", "一", "二", "三", "四", "五", "六"]

    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.firstWeekday = 2; return c }
    private var today: Date { dayDate(dayKey(Date())) }

    private func key(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private var period: (title: String, buckets: [Bucket], workedDays: Int) {
        _ = tick
        switch mode {
        case 0:
            let mon = cal.date(byAdding: .day, value: -((cal.component(.weekday, from: today) + 5) % 7) + offset * 7, to: today)!
            var b: [Bucket] = [], worked = 0
            for i in 0..<7 {
                let d = cal.date(byAdding: .day, value: i, to: mon)!, k = key(d), ms = data.ms(for: k)
                if ms > 0 { worked += 1 }
                b.append(Bucket(id: k, label: "周" + wd[cal.component(.weekday, from: d) - 1], hours: ms / 36e5,
                                detail: "\(cal.component(.month, from: d))/\(cal.component(.day, from: d)) 周\(wd[cal.component(.weekday, from: d) - 1]) · \(hm(ms))"))
            }
            let end = cal.date(byAdding: .day, value: 6, to: mon)!
            let t = "\(cal.component(.month, from: mon))/\(cal.component(.day, from: mon)) – \(cal.component(.month, from: end))/\(cal.component(.day, from: end))" + (offset == 0 ? "（本周）" : "")
            return (t, b, worked)
        case 1:
            let first = cal.date(from: cal.dateComponents([.year, .month], from: cal.date(byAdding: .month, value: offset, to: today)!))!
            let n = cal.range(of: .day, in: .month, for: first)!.count
            var b: [Bucket] = [], worked = 0
            for i in 0..<n {
                let d = cal.date(byAdding: .day, value: i, to: first)!, k = key(d), ms = data.ms(for: k)
                if ms > 0 { worked += 1 }
                b.append(Bucket(id: k, label: "\(i + 1)", hours: ms / 36e5, detail: "\(cal.component(.month, from: d))/\(i + 1) · \(hm(ms))"))
            }
            return ("\(cal.component(.year, from: first)) 年 \(cal.component(.month, from: first)) 月" + (offset == 0 ? "（本月）" : ""), b, worked)
        default:
            let year = cal.component(.year, from: today) + offset
            var b: [Bucket] = [], worked = 0
            for m in 1...12 {
                let first = cal.date(from: DateComponents(year: year, month: m, day: 1))!
                let n = cal.range(of: .day, in: .month, for: first)!.count
                var ms = 0.0
                for i in 0..<n {
                    let v = data.ms(for: key(cal.date(byAdding: .day, value: i, to: first)!))
                    if v > 0 { worked += 1 }
                    ms += v
                }
                b.append(Bucket(id: "\(year)-\(m)", label: "\(m)月", hours: ms / 36e5, detail: "\(year) 年 \(m) 月 · \(hm(ms))"))
            }
            return ("\(year) 年" + (offset == 0 ? "（今年）" : ""), b, worked)
        }
    }

    var body: some View {
        let p = period
        let total = p.buckets.reduce(0) { $0 + $1.hours }
        let best = p.buckets.max { $0.hours < $1.hours }
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Picker("", selection: $mode) { Text("每周").tag(0); Text("每月").tag(1); Text("每年").tag(2) }
                    .pickerStyle(.segmented).frame(width: 220)
                    .onChange(of: mode) { _, _ in offset = 0; selected = nil }
                Spacer()
                Button { offset -= 1; selected = nil } label: { Image(systemName: "chevron.left") }
                Text(p.title).font(.headline).frame(minWidth: 170)
                Button { offset += 1; selected = nil } label: { Image(systemName: "chevron.right") }.disabled(offset >= 0)
            }
            HStack(spacing: 12) {
                tile("总工作时长", String(format: "%.1f", total), "小时")
                tile("日均", p.workedDays > 0 ? String(format: "%.1f", total / Double(p.workedDays)) : "0.0", "小时 · 按计时的 \(p.workedDays) 天")
                tile(mode == 2 ? "最忙的月" : "最忙的一天", (best?.hours ?? 0) > 0 ? best!.label : "—", (best?.hours ?? 0) > 0 ? String(format: "%.1f 小时", best!.hours) : "还没有记录")
            }
            Chart(p.buckets) { b in
                BarMark(x: .value("时间", b.label), y: .value("小时", b.hours), width: .ratio(0.62))
                    .foregroundStyle(selected == nil || selected == b.label ? green : green.opacity(0.35))
                    .cornerRadius(4)
            }
            .chartXSelection(value: $selected)
            .chartYAxis { AxisMarks(position: .leading) { v in AxisGridLine(); AxisValueLabel { if let h = v.as(Double.self) { Text(h == h.rounded() ? "\(Int(h))h" : String(format: "%.1fh", h)) } } } }
            .chartXAxis {
                AxisMarks { v in
                    AxisValueLabel {
                        if let s = v.as(String.self), mode != 1 || ["1", "5", "10", "15", "20", "25", "30"].contains(s) { Text(s) }
                    }
                }
            }
            .frame(height: 220)
            Text(selected.flatMap { s in p.buckets.first { $0.label == s }?.detail } ?? (total > 0 ? "鼠标移到柱子上看明细" : "这段时间还没有计时记录。单击桌面上的小组件开始计时。"))
                .font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
            HStack {
                Text("一天按凌晨 5 点切换。记录保存在本机。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("打开记录文件夹") { NSWorkspace.shared.open(data.dir) }
            }
        }
        .padding(20)
        .frame(minWidth: 600, minHeight: 470)
        .onReceive(refresh) { _ in tick += 1 }
        .onAppear { tick += 1 }
    }

    private func tile(_ title: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(green)
            Text(sub).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var window: NSWindow!
    var view: WidgetView!
    var statusItem: NSStatusItem!
    var statsWindow: NSWindow?
    var timer: Timer?
    let bubble = Bubble()
    let data = DataStore.shared

    func applicationDidFinishLaunching(_ note: Notification) {
        view = WidgetView()
        if let img = NSImage(contentsOf: data.shapeURL) { view.image = img }
        view.onToggle = { [weak self] in self?.toggle() }
        view.onMenu = { [weak self] in self?.buildMenu() ?? NSMenu() }
        view.onMoved = { [weak self] in self?.savePosition() }

        window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.contentView = view
        layout()
        window.orderFrontRegardless()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "香菜番茄钟")
        let m = NSMenu()
        m.delegate = self
        statusItem.menu = m

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.view.needsDisplay = true
            self.statusItem.button?.title = self.data.isRunning ? " " + hm(self.data.currentMs) : ""
        }
    }

    /// 按图片比例算窗口大小，最长边 = 设定的尺寸。
    func layout() {
        let side = data.store.size
        let s = view.image.size
        let k = side / max(s.width, s.height, 1)
        let size = NSSize(width: max(80, s.width * k), height: max(80, s.height * k))
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var origin = NSPoint(x: data.store.x ?? (screen.maxX - size.width - 40),
                             y: data.store.y ?? (screen.minY + 80))
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(NSRect(origin: origin, size: size)) }
        if !onScreen { origin = NSPoint(x: screen.maxX - size.width - 40, y: screen.minY + 80) }
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        view.needsDisplay = true
        window.invalidateShadow()
    }

    func savePosition() {
        data.store.x = window.frame.origin.x
        data.store.y = window.frame.origin.y
        data.save()
    }

    func toggle() {
        if data.isRunning {
            let ms = data.stop()
            bubble.show("这一段 \(hm(ms))，今天共 \(hm(data.todayMs))。\n" + Cheer.stop.randomElement()!, above: window)
        } else {
            data.start()
            bubble.show(Cheer.start.randomElement()!, above: window)
        }
        view.needsDisplay = true
    }

    // 状态栏菜单每次打开时重建，显示最新时长
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let fresh = buildMenu()
        for item in fresh.items {
            fresh.removeItem(item)
            menu.addItem(item)
        }
    }

    func item(_ title: String, _ action: Selector?, enabled: Bool = true) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = self
        it.isEnabled = enabled && action != nil
        return it
    }

    func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        m.addItem(item(data.isRunning ? "停止计时" : "开始计时", #selector(menuToggle)))
        m.addItem(item("今天已工作 \(hm(data.todayMs))", nil, enabled: false))
        m.addItem(item("工作统计（周 / 月 / 年）…", #selector(openStats)))
        m.addItem(.separator())
        m.addItem(item("换形状：写一句话生成…", #selector(promptShape)))
        m.addItem(item("换形状：上传图片…", #selector(pickShape)))
        m.addItem(item("恢复番茄形状", #selector(resetShape), enabled: FileManager.default.fileExists(atPath: data.shapeURL.path)))
        let sizeItem = NSMenuItem(title: "大小", action: nil, keyEquivalent: "")
        let sizes = NSMenu()
        for (name, v) in [("小", 100.0), ("中", 140.0), ("大", 200.0), ("特大", 280.0)] {
            let it = item(name, #selector(setSize(_:)))
            it.representedObject = v
            it.state = data.store.size == v ? .on : .off
            sizes.addItem(it)
        }
        sizeItem.submenu = sizes
        m.addItem(sizeItem)
        m.addItem(item("把小组件放回屏幕右下角", #selector(resetPosition)))
        m.addItem(.separator())
        m.addItem(item(data.token == nil ? "设置生图令牌（魔搭）…" : "更换生图令牌（魔搭）…", #selector(setToken)))
        m.addItem(item("打开计时记录文件夹", #selector(openFolder)))
        let quit = item("退出香菜番茄钟", #selector(quit))
        quit.keyEquivalent = "q"
        m.addItem(quit)
        return m
    }

    @objc func menuToggle() { toggle() }

    @objc func openStats() {
        if statsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 500),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "工作统计"
            w.contentViewController = NSHostingController(rootView: StatsView())
            w.isReleasedWhenClosed = false
            w.center()
            statsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        statsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func setSize(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? Double else { return }
        data.store.size = v
        data.save()
        layout()
    }

    @objc func resetPosition() {
        data.store.x = nil
        data.store.y = nil
        data.save()
        layout()
    }

    func applyShape(_ png: Data) {
        try? png.write(to: data.shapeURL, options: .atomic)
        if let img = NSImage(data: png) { view.image = img }
        layout()
    }

    func showError(_ title: String, _ err: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = err.localizedDescription
        if case ShapeError.needToken = err {
            alert.addButton(withTitle: "去设置令牌")
            alert.addButton(withTitle: "取消")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { setToken() }
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc func pickShape() {
        let panel = NSOpenPanel()
        panel.title = "选一张图片，自动抠出主体当小组件的形状"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        view.busyText = "抠图中…"
        view.needsDisplay = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Shape.cutout(from: url) }
            DispatchQueue.main.async {
                self.view.busyText = nil
                self.view.needsDisplay = true
                switch result {
                case .success(let png): self.applyShape(png)
                case .failure(let err): self.showError("没抠出来", err)
                }
            }
        }
    }

    @objc func promptShape() {
        let alert = NSAlert()
        alert.messageText = "写一句话，生成小组件图标"
        alert.informativeText = "比如：一只戴眼镜、举着奶茶的柴犬；一颗元气满满的番茄。生成后会自动抠出主体。"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "想要什么样的图标？"
        alert.accessoryView = field
        alert.addButton(withTitle: "生成")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        view.busyText = "生成中…"
        view.needsDisplay = true
        Task { @MainActor in
            do {
                let png = try await Shape.generate(text)
                self.view.busyText = nil
                self.applyShape(png)
            } catch {
                self.view.busyText = nil
                self.view.needsDisplay = true
                self.showError("没生成出来", error)
            }
        }
    }

    @objc func setToken() {
        let alert = NSAlert()
        alert.messageText = "设置魔搭 ModelScope 访问令牌"
        alert.informativeText = "用来“写一句话生成图标”。在 modelscope.cn 登录后，进入 个人中心 → 访问令牌，复制一个令牌粘贴到这里。令牌只保存在这台电脑上。留空并保存 = 删除令牌。"
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "ms-…"
        alert.accessoryView = field
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        data.token = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @objc func resetShape() {
        try? FileManager.default.removeItem(at: data.shapeURL)
        view.image = Shape.tomato()
        layout()
    }

    @objc func openFolder() { NSWorkspace.shared.open(data.dir) }

    @objc func quit() {
        // 退出时不停止计时：再次打开会接着算
        NSApp.terminate(nil)
    }
}

// MARK: - 启动

let args = CommandLine.arguments
// 命令行自检：XiangcaiTimer --cutout 输入图片 输出.png
if args.count == 4, args[1] == "--cutout" {
    do {
        try Shape.cutout(from: URL(fileURLWithPath: args[2])).write(to: URL(fileURLWithPath: args[3]))
        print("ok"); exit(0)
    } catch { print("失败：\(error.localizedDescription)"); exit(1) }
}
// 命令行自检：XiangcaiTimer --preview 形状图片或tomato 输出.png
if args.count == 4, args[1] == "--preview" {
    let v = WidgetView()
    if args[2] != "tomato", let img = NSImage(contentsOfFile: args[2]) { v.image = img }
    let s = v.image.size, k = 200 / max(s.width, s.height)
    v.frame = NSRect(x: 0, y: 0, width: s.width * k, height: s.height * k)
    let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
    v.cacheDisplay(in: v.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[3]))
    exit(0)
}

// 命令行自检：XiangcaiTimer --stats-preview 输出.png
if args.count == 3, args[1] == "--stats-preview" {
    MainActor.assumeIsolated {
        let r = ImageRenderer(content: StatsView().frame(width: 640, height: 500).background(Color.white))
        r.scale = 1
        if let cg = r.cgImage { try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[2])) }
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
