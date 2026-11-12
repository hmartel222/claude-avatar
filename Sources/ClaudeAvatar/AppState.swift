import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI
import TapCore

final class TileWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that handles the first click even when the tile isn't the key window.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum RendererKind: String { case talkingHead, simli }

struct AvatarChoice: Identifiable, Hashable {
    let id: String      // URL path served by StaticServer, e.g. /avatars/mpfb.glb
    let title: String
}

/// Owns the capture engine, the local web server and the tile window.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    static let sizes: [(name: String, width: CGFloat)] = [("S", 240), ("M", 360), ("L", 540)]

    private let defaults = UserDefaults.standard

    @Published var isVisible = true
    @Published var faceHidden: Bool { didSet { defaults.set(faceHidden, forKey: "faceHidden"); applyPause() } }
    @Published var pinned: Bool { didSet { defaults.set(pinned, forKey: "pinned"); window?.level = pinned ? .floating : .normal } }
    /// Keep the tile hidden until Claude's audio starts, then hide it again after a quiet spell.
    @Published var autoShow: Bool {
        didSet { defaults.set(autoShow, forKey: "autoShow") }
    }
    /// Video-call look: living-room backdrop, Zoom-style lighting (both follow the time of day), backdrop blur.
    @Published var roomOn: Bool { didSet { defaults.set(roomOn, forKey: "roomOn"); pushStage() } }
    @Published var lightOn: Bool { didSet { defaults.set(lightOn, forKey: "lightOn"); pushStage() } }
    @Published var roomBlur: Double { didSet { defaults.set(roomBlur, forKey: "roomBlur"); pushStage() } }
    @Published var sensitivity: Double {
        didSet { defaults.set(sensitivity, forKey: "sensitivity"); model.eval("window.claudeAvatar?.setSensitivity(\(sensitivity))") }
    }
    @Published var avatarID: String {
        didSet { defaults.set(avatarID, forKey: "avatar"); if oldValue != avatarID { updatePageURL() } }
    }
    @Published var renderer: RendererKind {
        didSet {
            defaults.set(renderer.rawValue, forKey: "renderer")
            guard oldValue != renderer else { return }
            syncState = "idle"; rendererError = nil
            applySyncMode()
            updatePageURL()
        }
    }
    @Published var simliFaceID: String { didSet { defaults.set(simliFaceID, forKey: "simliFaceID") } }
    /// Manual nudge added to the measured latency (positive = hold the voice back longer).
    @Published var syncOffsetMs: Double { didSet { defaults.set(syncOffsetMs, forKey: "syncOffsetMs"); applyDelay() } }
    @Published private(set) var hasSimliKey = Keychain.has(SimliSession.account)
    @Published private(set) var syncState = "idle"
    @Published private(set) var measuredLatencyMs: Double?
    @Published private(set) var rendererError: String?
    /// Result of the last "Test connection" (key + face ID checked against Simli).
    @Published private(set) var keyStatus: String?
    @Published private(set) var keyStatusOK = false
    @Published private(set) var avatars: [AvatarChoice] = []
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var loginNote: String?
    @Published private(set) var sizeIndex: Int?

    let model = TileModel()
    // CLAUDE_AVATAR_PREFIX lets you point the tap at another app for testing.
    private let engine = TapEngine(prefix: ProcessInfo.processInfo.environment["CLAUDE_AVATAR_PREFIX"] ?? "com.anthropic.claudefordesktop")
    private var server: StaticServer?
    private var serverPort: UInt16?
    private var window: TileWindow?
    private var timer: Timer?
    private var restoreFrame: NSRect?
    private var hotKeyRef: EventHotKeyRef?
    private let loudLock = NSLock()
    private var lastLoud = Date.distantPast
    /// True while the tile is visible because auto-show opened it (only those get auto-hidden).
    private var autoShown = false
    /// Set when the user hides the tile mid-session; auto-show stays off until Claude goes quiet.
    private var suppressAuto = false
    private static let autoHideAfter: TimeInterval = 25

    private let userAvatarsDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Claude Avatar/avatars", isDirectory: true)
    }()

    private init() {
        let d = UserDefaults.standard
        faceHidden = d.bool(forKey: "faceHidden")
        autoShow = d.object(forKey: "autoShow") as? Bool ?? true
        roomOn = d.object(forKey: "roomOn") as? Bool ?? true
        lightOn = d.object(forKey: "lightOn") as? Bool ?? true
        roomBlur = d.object(forKey: "roomBlur") as? Double ?? 9
        pinned = d.object(forKey: "pinned") as? Bool ?? true
        let s = d.double(forKey: "sensitivity")
        sensitivity = s == 0 ? 1.0 : s
        avatarID = d.string(forKey: "avatar") ?? "/avatars/mpfb.glb"
        renderer = RendererKind(rawValue: d.string(forKey: "renderer") ?? "") ?? .talkingHead
        simliFaceID = d.string(forKey: "simliFaceID") ?? SimliSession.defaultFaceID
        syncOffsetMs = d.double(forKey: "syncOffsetMs")
    }

    // MARK: - renderer / sync mode

    var syncStatus: String {
        switch syncState {
        case "ready": return String(format: "Voice held back %.0f ms (measured %@ + nudge)", effectiveDelayMs, measuredLatencyMs.map { String(format: "%.0f ms", $0) } ?? "estimate")
        case "connecting": return "Connecting to Simli…"
        case "error": return "Simli unavailable – you hear Claude with no delay"
        default: return "Idle – Simli connects when Claude speaks"
        }
    }

    /// How long the voice is held back right now.
    var effectiveDelayMs: Double {
        guard renderer == .simli, syncState == "ready" else { return 0 }
        return max(0, (measuredLatencyMs ?? 350) + syncOffsetMs)
    }

    /// Sync mode (mute Claude's own output, play it back delayed) only makes sense with a video renderer
    /// that can actually connect. Without a key we leave Claude's audio alone.
    private func applySyncMode() {
        let on = renderer == .simli && hasSimliKey
        engine.detectInterrupts = on
        engine.muteOriginal = on
        applyDelay()
    }

    private func applyDelay() { engine.player.setDelay(ms: effectiveDelayMs) }

    func saveSimliKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if Keychain.set(trimmed, account: SimliSession.account) {
            hasSimliKey = true; rendererError = nil
            applySyncMode(); updatePageURL(force: true)
            testSimliConnection()
        } else { rendererError = "Couldn't save the key to the Keychain" }
    }

    /// Mints a session token with the saved key and face ID, so a bad key or face shows up now, not mid-conversation.
    func testSimliConnection() {
        keyStatus = "Checking with Simli…"; keyStatusOK = false
        let face = simliFaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            do {
                _ = try await SimliSession.fetchToken(faceID: face)
                keyStatus = "Key and face accepted ✓"; keyStatusOK = true
            } catch {
                keyStatus = error.localizedDescription; keyStatusOK = false
            }
        }
    }

    func removeSimliKey() {
        Keychain.delete(SimliSession.account)
        hasSimliKey = false; syncState = "idle"; keyStatus = nil
        applySyncMode(); updatePageURL(force: true)
    }

    private func handleSync(_ body: [String: Any]) {
        guard (body["renderer"] as? String) == renderer.rawValue.lowercased() || (body["renderer"] as? String) == "talkinghead" && renderer == .talkingHead else { return }
        syncState = body["state"] as? String ?? "idle"
        if let ms = body["latencyMs"] as? Double, renderer == .simli { measuredLatencyMs = ms }
        if syncState == "ready" || syncState == "error" { rendererError = syncState == "error" ? "Simli connection failed" : nil }
        applyDelay()
    }

    private func handleNeedToken() {
        let face = simliFaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            do {
                let token = try await SimliSession.fetchToken(faceID: face)
                _ = try? await model.webView?.callAsyncJavaScript("window.claudeAvatar.setSimliToken(token)",
                                                                  arguments: ["token": token], in: nil, contentWorld: .page)
            } catch {
                rendererError = error.localizedDescription
                _ = try? await model.webView?.callAsyncJavaScript("window.claudeAvatar.simliTokenError(message)",
                                                                  arguments: ["message": error.localizedDescription], in: nil, contentWorld: .page)
            }
        }
    }

    func launch() {
        // A second copy would fight the first over the WebSocket port.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != .current }) {
            NSApp.terminate(nil)
            return
        }
        try? FileManager.default.createDirectory(at: userAvatarsDir, withIntermediateDirectories: true)
        // First run: start at login so the tile can pop up on its own (toggle in the menu-bar panel).
        if !defaults.bool(forKey: "loginItemOffered") {
            defaults.set(true, forKey: "loginItemOffered")
            setLaunchAtLogin(true)
        }
        makeWindow()
        startEngine()
        startWebServer()
        registerHotKey()
        model.onPageLoaded = { [weak self] in self?.applyPageState() }
        model.onSync = { [weak self] body in MainActor.assumeIsolated { self?.handleSync(body) } }
        model.onNeedToken = { [weak self] in MainActor.assumeIsolated { self?.handleNeedToken() } }
        applySyncMode()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateSpeaking() }
        }
        // Sleep/wake can leave the tap dead: re-attach when the Mac wakes.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.engine.reattach() }
        }
    }

    // MARK: - window actions

    func toggleWindow() {
        guard let window else { return }
        if window.isVisible { window.orderOut(nil); suppressAuto = autoShow } else { window.orderFrontRegardless() }
        autoShown = false
        isVisible = window.isVisible
        applyPause()
    }

    private func setWindowVisible(_ show: Bool) {
        guard let window, window.isVisible != show else { return }
        if show { window.orderFrontRegardless() } else { window.orderOut(nil) }
        isVisible = show
        applyPause()
    }

    /// Resize to a preset, keeping the top-left corner fixed.
    func setSize(_ index: Int) {
        guard let window else { return }
        restoreFrame = nil
        let w = Self.sizes[index].width
        let old = window.frame
        let new = NSRect(x: old.minX, y: old.maxY - w * 3 / 4, width: w, height: w * 3 / 4)
        window.setFrame(new, display: true, animate: true)
    }

    /// Fill the screen's visible area at 4:3 (centered), or restore the previous size.
    func toggleMaximize() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        if let saved = restoreFrame {
            window.setFrame(saved, display: true, animate: true)
            restoreFrame = nil
            return
        }
        restoreFrame = window.frame
        let area = screen.visibleFrame
        let height = min(area.height, area.width * 3 / 4)
        let size = NSSize(width: height * 4 / 3, height: height)
        let origin = NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
        window.setFrame(NSRect(origin: origin, size: size), display: true, animate: true)
    }

    func openUserAvatarsFolder() { NSWorkspace.shared.open(userAvatarsDir) }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginNote = nil
        } catch {
            loginNote = "Couldn't change login item: \(error.localizedDescription)"
        }
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        if status == .requiresApproval { loginNote = "Approve Claude Avatar in System Settings → General → Login Items." }
    }

    func quit() {
        engine.stop()
        server?.stop()
        NSApp.terminate(nil)
    }

    // MARK: - setup

    private func makeWindow() {
        let w = TileWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 270),
                           styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = pinned ? .floating : .normal
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.contentAspectRatio = NSSize(width: 4, height: 3)
        w.contentMinSize = NSSize(width: 240, height: 180)

        let host = FirstMouseHostingView(rootView: TileView(model: model, app: self))
        host.sizingOptions = []
        w.contentView = host

        if !w.setFrameUsingName("ClaudeAvatarTile") { w.center() }
        w.setFrameAutosaveName("ClaudeAvatarTile")
        if !autoShow { w.orderFrontRegardless() }
        window = w
        isVisible = !autoShow

        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncSizeIndex() }
        }
        syncSizeIndex()
    }

    private func syncSizeIndex() {
        guard let width = window?.frame.width else { return }
        sizeIndex = Self.sizes.firstIndex { abs($0.width - width) < 2 }
    }

    private func startEngine() {
        engine.suppressSilence = true
        engine.onLog = { print("[tap] \($0)") }
        engine.onFatal = { [weak self] msg in
            DispatchQueue.main.async { self?.model.error = msg + "\nIs claude-tap already running?" }
        }
        engine.onFrame = { [weak self] peak, _ in
            guard let self, peak > 0.002 else { return }
            self.loudLock.lock(); self.lastLoud = Date(); self.loudLock.unlock()
        }
        engine.onChange = { [weak self] in
            guard let self else { return }
            self.model.claudeRunning = self.engine.claudeRunning
        }
        do { try engine.start() } catch { model.error = "Capture failed to start: \(error)" }
    }

    /// 400 ms silence timeout for the status dot (the page applies the same rule to the avatar).
    private func updateSpeaking() {
        loudLock.lock(); let last = lastLoud; loudLock.unlock()
        let speaking = Date().timeIntervalSince(last) < 0.4
        if speaking != model.speaking { model.speaking = speaking }
        guard autoShow else { autoShown = false; return }
        let quiet = Date().timeIntervalSince(last)
        if speaking, !suppressAuto, window?.isVisible == false {
            setWindowVisible(true); autoShown = true
        }
        if quiet > Self.autoHideAfter {
            suppressAuto = false
            if autoShown { setWindowVisible(false); autoShown = false }
        }
    }

    private func startWebServer() {
        guard let root = Self.webRoot() else {
            model.error = "web/ folder not found (expected in the app's Resources)"
            return
        }
        avatars = discoverAvatars(root: root)
        if !avatars.contains(where: { $0.id == avatarID }) { avatarID = avatars.first?.id ?? "/avatars/mpfb.glb" }
        let s = StaticServer(root: root, userAvatars: userAvatarsDir)
        server = s
        s.start { [weak self] port in
            guard let self else { return }
            if let port { self.serverPort = port; self.updatePageURL() }
            else { self.model.error = "Could not start the local web server" }
        }
    }

    private func discoverAvatars(root: URL) -> [AvatarChoice] {
        func glbs(in dir: URL) -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".glb") }.sorted()
        }
        let title: (String) -> String = { ($0 as NSString).deletingPathExtension.capitalized }
        return glbs(in: root.appendingPathComponent("avatars")).map { AvatarChoice(id: "/avatars/\($0)", title: title($0)) }
             + glbs(in: userAvatarsDir).map { AvatarChoice(id: "/user-avatars/\($0)", title: title($0) + " (custom)") }
    }

    private func updatePageURL(force: Bool = false) {
        guard let port = serverPort else { return }
        var c = URLComponents(string: "http://127.0.0.1:\(port)/")!
        c.queryItems = [URLQueryItem(name: "embedded", value: "1"),
                        URLQueryItem(name: "renderer", value: renderer == .simli ? "simli" : "talkinghead"),
                        URLQueryItem(name: "avatar", value: avatarID),
                        URLQueryItem(name: "sens", value: String(sensitivity)),
                        URLQueryItem(name: "room", value: roomOn ? "1" : "0"),
                        URLQueryItem(name: "light", value: lightOn ? "1" : "0"),
                        URLQueryItem(name: "blur", value: String(roomBlur))]
        // Test hook: CLAUDE_AVATAR_QUERY="idlefps=8&pr=0.75" appends tuning parameters.
        if let extra = ProcessInfo.processInfo.environment["CLAUDE_AVATAR_QUERY"] {
            c.percentEncodedQuery = (c.percentEncodedQuery ?? "") + "&" + extra
        }
        if force, renderer == .simli, model.pageURL == c.url { model.webView?.reload() } else { model.pageURL = c.url }
    }

    /// The page stops rendering while the tile is hidden or the face is off.
    private func applyPause() {
        model.eval("window.claudeAvatar?.setPaused(\(!isVisible || faceHidden))")
    }

    private func pushStage() {
        model.eval("window.claudeAvatar?.setStage({room: \(roomOn), light: \(lightOn), blur: \(roomBlur)})")
    }

    private func applyPageState() {
        pushStage()
        model.eval("window.claudeAvatar?.setSensitivity(\(sensitivity))")
        applyPause()
    }

    // MARK: - global hotkey ⌥⌘A (Carbon; needs no extra permission)

    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { AppState.shared.toggleWindow() } }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x434C_4156), id: 1)   // 'CLAV'
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_A), UInt32(optionKey | cmdKey), id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { print("hotkey registration failed: \(status)") }
    }

    /// Bundled copy first, then ./web or ../web for `swift run` during development.
    private static func webRoot() -> URL? {
        var candidates: [URL] = []
        if let env = ProcessInfo.processInfo.environment["CLAUDE_AVATAR_WEB"] { candidates.append(URL(fileURLWithPath: env)) }
        if let res = Bundle.main.resourceURL { candidates.append(res.appendingPathComponent("web")) }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidates += [cwd.appendingPathComponent("web"), cwd.deletingLastPathComponent().appendingPathComponent("web")]
        return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("index.html").path) }
    }
}
