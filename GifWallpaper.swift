// 움짤 배경화면 — 메뉴 막대에서 GIF/동영상을 골라 바탕화면에 재생합니다.
import AppKit
import AVFoundation
import ImageIO
import ServiceManagement

// MARK: - GIF 디코딩

struct GifFrames {
    let images: [CGImage]
    let keyTimes: [NSNumber]
    let duration: CFTimeInterval

    init?(url: URL) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(src)
        guard count > 0 else { return nil }

        var images: [CGImage] = []
        var delays: [Double] = []
        for i in 0..<count {
            guard let img = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            images.append(img)
            delays.append(GifFrames.delay(src, i))
        }
        guard !images.isEmpty else { return nil }

        let total = delays.reduce(0, +)
        var acc = 0.0
        var times: [NSNumber] = []
        for d in delays {
            times.append(NSNumber(value: acc / total))
            acc += d
        }
        self.images = images
        self.keyTimes = times
        self.duration = total
    }

    private static func delay(_ src: CGImageSource, _ i: Int) -> Double {
        let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
        let dict = (props?[kCGImagePropertyGIFDictionary] ?? props?[kCGImagePropertyPNGDictionary]
                    ?? props?[kCGImagePropertyWebPDictionary]) as? [CFString: Any]
        let keys: [CFString] = [kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime,
                                kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime,
                                kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime]
        for k in keys {
            if let v = dict?[k] as? Double, v > 0 { return v < 0.02 ? 0.1 : v }
        }
        return 0.1
    }
}

// MARK: - 바탕화면 창

final class WallpaperWindow: NSWindow {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        ignoresMouseEvents = true
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        setFrame(screen.frame, display: false)

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        contentView = view
    }

    func show(gif: GifFrames, fill: Bool) {
        clear()
        guard let root = contentView?.layer else { return }
        let layer = CALayer()
        layer.frame = root.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer.contentsGravity = fill ? .resizeAspectFill : .resizeAspect
        layer.masksToBounds = true
        layer.contents = gif.images.first

        if gif.images.count > 1 {
            let anim = CAKeyframeAnimation(keyPath: "contents")
            anim.values = gif.images
            anim.keyTimes = gif.keyTimes
            anim.calculationMode = .discrete
            anim.duration = gif.duration
            anim.repeatCount = .infinity
            anim.isRemovedOnCompletion = false
            layer.add(anim, forKey: "gif")
        }
        root.addSublayer(layer)
    }

    func show(video url: URL, fill: Bool) {
        clear()
        guard let root = contentView?.layer else { return }
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue

        let layer = AVPlayerLayer(player: queue)
        layer.frame = root.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        root.addSublayer(layer)
        queue.play()
    }

    func setPaused(_ paused: Bool) {
        guard let layer = contentView?.layer else { return }
        if let p = player {
            paused ? p.pause() : p.play()
            return
        }
        // CALayer 애니메이션 일시정지/재개
        if paused {
            let t = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0
            layer.timeOffset = t
        } else {
            let paused = layer.timeOffset
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - paused
        }
    }

    func clear() {
        player?.pause()
        looper = nil
        player = nil
        contentView?.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        contentView?.layer?.speed = 1
        contentView?.layer?.timeOffset = 0
        contentView?.layer?.beginTime = 0
    }
}

// MARK: - 앱

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let videoExts: Set<String> = ["mp4", "mov", "m4v"]
    private let defaults = UserDefaults.standard
    private var statusItem: NSStatusItem!
    private var windows: [WallpaperWindow] = []
    private var paused = false
    private var pauseItem: NSMenuItem!
    private var fillItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    private var currentURL: URL? {
        get { defaults.string(forKey: "path").map { URL(fileURLWithPath: $0) } }
        set { defaults.set(newValue?.path, forKey: "path") }
    }
    private var fill: Bool {
        get { defaults.object(forKey: "fill") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "fill") }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "photo.on.rectangle.angled",
                                           accessibilityDescription: "움짤 배경화면")
        buildMenu()

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(rebuild),
                       name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let wnc = NSWorkspace.shared.notificationCenter
        wnc.addObserver(self, selector: #selector(sleepPause),
                        name: NSWorkspace.screensDidSleepNotification, object: nil)
        wnc.addObserver(self, selector: #selector(wakeResume),
                        name: NSWorkspace.screensDidWakeNotification, object: nil)

        if currentURL.map({ FileManager.default.fileExists(atPath: $0.path) }) == true {
            rebuild()
        } else {
            chooseFile()
        }
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "움짤 선택…", action: #selector(chooseFile), keyEquivalent: "o")
        pauseItem = menu.addItem(withTitle: "일시정지", action: #selector(togglePause), keyEquivalent: "p")
        fillItem = menu.addItem(withTitle: "화면 꽉 채우기", action: #selector(toggleFill), keyEquivalent: "")
        fillItem.state = fill ? .on : .off
        menu.addItem(withTitle: "배경 끄기", action: #selector(turnOff), keyEquivalent: "")
        menu.addItem(.separator())
        loginItem = menu.addItem(withTitle: "로그인 시 자동 실행", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        statusItem.menu = menu
    }

    @objc private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "배경으로 쓸 움짤(GIF) 또는 동영상을 고르세요"
        panel.allowedContentTypes = [.gif, .png, .webP, .mpeg4Movie, .quickTimeMovie, .movie]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        currentURL = url
        paused = false
        rebuild()
    }

    @objc private func rebuild() {
        windows.forEach { $0.clear(); $0.orderOut(nil) }
        windows.removeAll()
        guard let url = currentURL else { return }

        let isVideo = videoExts.contains(url.pathExtension.lowercased())
        var gif: GifFrames?
        if !isVideo {
            gif = GifFrames(url: url)
            if gif == nil {
                alert("이 파일을 읽을 수 없어요:\n\(url.lastPathComponent)")
                return
            }
        }

        for screen in NSScreen.screens {
            let w = WallpaperWindow(screen: screen)
            if let gif { w.show(gif: gif, fill: fill) } else { w.show(video: url, fill: fill) }
            w.orderBack(nil)
            windows.append(w)
        }
        applyPause()
    }

    @objc private func togglePause() { paused.toggle(); applyPause() }

    private func applyPause() {
        windows.forEach { $0.setPaused(paused) }
        pauseItem.title = paused ? "재생" : "일시정지"
    }

    @objc private func sleepPause() { windows.forEach { $0.setPaused(true) } }
    @objc private func wakeResume() { if !paused { windows.forEach { $0.setPaused(false) } } }

    @objc private func toggleFill() {
        fill.toggle()
        fillItem.state = fill ? .on : .off
        rebuild()
    }

    @objc private func turnOff() {
        currentURL = nil
        rebuild()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert("로그인 항목 설정에 실패했어요. 앱을 '응용 프로그램' 폴더로 옮긴 뒤 다시 시도해 보세요.\n\(error.localizedDescription)")
        }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func alert(_ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "움짤 배경화면"
        a.informativeText = text
        a.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
